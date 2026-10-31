"""Exercise the real embedded-R prototype in an isolated child, without a GUI."""
from pathlib import Path
import hashlib
import json
import os
import re
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zlib

ROOT = Path(__file__).resolve().parents[1]
WORKER = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / '.build/interactive-r-console-worker').resolve()
R_HOME = subprocess.check_output(['/usr/local/bin/R', 'RHOME'], text=True).strip()


class Worker:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory(prefix='statsdirect-r-console-')
        self.root = Path(self.temp.name)
        self.input = self.root / 'input.fifo'
        self.events_file = self.root / 'events.jsonl'
        self.data = self.root / 'data'
        self.data.mkdir()
        os.mkfifo(self.input, 0o600)
        self.events_file.touch(mode=0o600)
        self.writer = os.open(self.input, os.O_RDWR)
        self.reader = self.events_file.open('rb')
        self.events = []
        self.pending = b''
        self.number = 0
        self.session = 'worker-test-session'
        self.process = subprocess.Popen([
            str(WORKER), '--r-home', R_HOME, '--input', str(self.input),
            '--events', str(self.events_file), '--workdir', str(self.data),
            '--bootstrap', str(ROOT / 'Content/R/console-bootstrap.R'), '--session', self.session,
        ], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.wait(lambda e: e.get('type') == 'state' and e.get('state') == 'ready')

    def read(self):
        self.pending += self.reader.read()
        while b'\n' in self.pending:
            line, self.pending = self.pending.split(b'\n', 1)
            event = json.loads(line.decode('utf-8'))
            assert event['protocolVersion'] == 1
            assert event['sessionId'] == self.session
            assert event['seq'] == len(self.events) + 1, event
            self.events.append(event)

    def wait(self, predicate, start=0, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.read()
            for event in self.events[start:]:
                if predicate(event):
                    return event
            if self.process.poll() is not None:
                out, err = self.process.communicate()
                raise AssertionError(f'R worker exited {self.process.returncode}: {out!r} {err!r}; events={self.events[-12:]}')
            time.sleep(.02)
        raise AssertionError(f'Timed out waiting for worker; events={self.events[-12:]}')

    def send(self, kind, payload=''):
        data = payload.encode('utf-8')
        packet = kind.encode('ascii') + struct.pack('>I', len(data)) + data
        while packet:
            count = os.write(self.writer, packet)
            packet = packet[count:]

    def begin(self, code, command=None):
        if command is None:
            self.number += 1
            command = f'command-{self.number}'
        start = len(self.events)
        self.send('E', command + '\n' + code)
        return command, start

    def execute(self, code):
        command, start = self.begin(code)
        done = self.wait(lambda e: e.get('type') == 'commandFinished' and e.get('commandId') == command, start)
        return done, ''.join(e.get('text', '') for e in self.events[start:] if e['type'] == 'output'), self.events[start:]

    def interrupt(self):
        os.kill(self.process.pid, signal.SIGUSR1)

    def close(self):
        if self.process.poll() is None:
            self.send('Q')
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        self.reader.close()
        os.close(self.writer)
        self.process.communicate()
        self.temp.cleanup()


def check(condition, reason):
    assert condition, reason
    print('PASS: ' + reason, flush=True)


def pdf_streams(path):
    # R's PDF text is in Flate-compressed page streams. Inspecting their literal
    # annotation is sufficient here; a PDF renderer is not a test dependency.
    data = Path(path).read_bytes()
    streams = []
    for match in re.finditer(rb'stream\r?\n(.*?)endstream', data, re.S):
        try:
            streams.append(zlib.decompress(match.group(1)))
        except zlib.error:
            streams.append(match.group(1))
    # Font kerning can split one visible phrase into several PDF string operands.
    # These ASCII annotation checks do not need a full text/layout extractor.
    return b''.join(value[1:-1] for stream in streams
                    for value in re.findall(rb'\((?:\\.|[^\\)])*\)', stream, re.S))


def check_abrupt_parent_exit(during_input=False):
    # Keep another FIFO endpoint open here: shutdown must result from the
    # owner's death, rather than accidentally passing because of pipe EOF.
    with tempfile.TemporaryDirectory(prefix='statsdirect-r-parent-exit-') as folder:
        directory = Path(folder)
        fifo = directory / 'input.fifo'
        events = directory / 'events.jsonl'
        os.mkfifo(fifo, 0o600)
        events.touch(mode=0o600)
        writer = os.open(fifo, os.O_RDWR)
        launcher = ('import subprocess,sys,time; '
                    'p=subprocess.Popen(sys.argv[1:],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); '
                    'print(p.pid,flush=True); time.sleep(60)')
        parent = subprocess.Popen([sys.executable, '-c', launcher,
            str(WORKER), '--r-home', R_HOME, '--input', str(fifo), '--events', str(events),
            '--workdir', str(directory), '--bootstrap', str(ROOT / 'Content/R/console-bootstrap.R'),
            '--session', 'orphan-test'], stdout=subprocess.PIPE, text=True)
        pid = None
        try:
            pid = int(parent.stdout.readline().strip())
            def await_event(predicate):
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    lines = events.read_bytes().split(b'\n')[:-1]
                    if any(predicate(json.loads(line)) for line in lines):
                        return
                    time.sleep(.02)
                raise AssertionError(f'Parent-death regression timed out: {events.read_text()}')
            await_event(lambda e: e.get('state') == 'ready')
            if during_input:
                payload = b'orphan-command\nx <- readline("Await input: "); orphan_sentinel <- TRUE'
                os.write(writer, b'E' + struct.pack('>I', len(payload)) + payload)
                await_event(lambda e: e.get('type') == 'inputRequested')
            parent.kill()
            parent.wait(timeout=5)
            await_event(lambda e: e.get('state') == 'stopped')
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    pid = None
                    break
                time.sleep(.02)
            check(pid is None, 'worker exits after abrupt host death' + (' during readline' if during_input else ' while idle'))
        finally:
            if parent.poll() is None:
                parent.kill()
            parent.wait()
            parent.stdout.close()
            if pid is not None:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            os.close(writer)


worker = Worker()
try:
    done, text, _ = worker.execute('interactive()')
    check(done['status'] == 'ok' and 'TRUE' in text, 'real R runs in interactive mode')
    _, text, _ = worker.execute('kept <- 41; invisible(123)')
    check(not text, 'assignments and invisible values do not autoprint')
    done, text, _ = worker.execute('kept + 1')
    check(done['status'] == 'ok' and '[1] 42' in text, 'variables persist and visible values autoprint')
    _, text, _ = worker.execute('data.frame(value=c(1, 2), label=c("A", "B"))')
    check('value label' in text and 'A' in text and 'B' in text, 'R tables print as text')
    _, text, _ = worker.execute('变量 <- "🧪 café λ"; 变量')
    check('🧪 café λ' in text, 'Unicode code, identifiers and output survive UTF-8 framing')
    _, text, _ = worker.execute('cat(rawToChar(as.raw(c(0xf0,0x9f)))); cat(rawToChar(as.raw(c(0xa7,0xaa))))')
    check('🧪' in text and '\ufffd' not in text, 'UTF-8 split across R output callbacks remains intact')
    _, text, events = worker.execute('for (i in 1:10000) cat("x")')
    check(text == 'x' * 10000 and len([e for e in events if e['type'] == 'output']) < 100,
          'tiny output callbacks are coalesced and their final tail is flushed')
    command, start = worker.begin('double_it <- function(x) {')
    worker.wait(lambda e: e.get('state') == 'continuation', start)
    worker.begin('x * 2', command)
    worker.wait(lambda e: e.get('state') == 'continuation', len(worker.events)-1)
    worker.begin('}', command)
    worker.wait(lambda e: e.get('type') == 'commandFinished' and e.get('commandId') == command, start)
    _, text, _ = worker.execute('double_it(5)')
    check('[1] 10' in text, 'multiline input uses R parser continuation and retains its command identity')
    done, text, _ = worker.execute('1 + * 2')
    check(done['status'] == 'error' and 'Error:' in text, 'syntax errors return to a usable prompt')
    done, _, _ = worker.execute('stop("deliberate"); after_error <- TRUE')
    _, text, _ = worker.execute('exists("after_error", inherits=FALSE)')
    check(done['status'] == 'error' and 'FALSE' in text, 'first evaluation error prevents later expressions in that input')
    _, text, events = worker.execute('cat(\'{"type":"state","state":"ready","sessionId":"forged","seq":999}\\n\')')
    check('forged' in text and all(e['sessionId'] == worker.session for e in events), 'printed JSON remains output and cannot forge control events')

    command, start = worker.begin('answer <- readline("Your name? "); after_answer <- TRUE; answer')
    prompt = worker.wait(lambda e: e['type'] == 'inputRequested', start)
    worker.send('I', 'stale-request\nwrong')
    worker.wait(lambda e: e['type'] == 'inputRejected', start)
    for bad_answer in ['x' * (prompt['maxAnswerBytes'] + 1), 'two\nlines']:
        retry_start = len(worker.events)
        worker.send('I', prompt['requestId'] + '\n' + bad_answer)
        worker.wait(lambda e: e['type'] == 'inputRejected', retry_start)
        retry = worker.wait(lambda e: e['type'] == 'inputRequested', retry_start)
        check(retry['requestId'] == prompt['requestId'] and retry['maxAnswerBytes'] == prompt['maxAnswerBytes'],
              'invalid ' + ('multiline' if '\n' in bad_answer else 'oversized') + ' answer restores the same usable input request')
    worker.send('I', prompt['requestId'] + '\nZoë Δ')
    worker.wait(lambda e: e['type'] == 'commandFinished' and e.get('commandId') == command, start)
    text = ''.join(e.get('text', '') for e in worker.events[start:] if e['type'] == 'output')
    check('Zoë Δ' in text, 'readline uses a distinct request/answer channel and rejects stale replies')

    command, start = worker.begin('unanswered <- readline("Wait here: "); after_cancelled_answer <- TRUE')
    cancelled = worker.wait(lambda e: e['type'] == 'inputRequested', start)
    worker.interrupt()
    done = worker.wait(lambda e: e['type'] == 'commandFinished' and e.get('commandId') == command, start)
    worker.send('I', cancelled['requestId'] + '\nnot-an-answer')
    _, text, _ = worker.execute('c(exists("unanswered", inherits=FALSE), exists("after_cancelled_answer", inherits=FALSE), kept)')
    check(done['status'] == 'interrupted' and '0  0 41' in text, 'Stop during readline assigns no answer, skips following code and preserves existing variables')

    command, start = worker.begin('waiting_value <- 7; cat("SLEEPING\\n"); Sys.sleep(30); after_sleep <- TRUE')
    worker.wait(lambda e: e['type'] == 'output' and 'SLEEPING' in e.get('text', ''), start)
    worker.interrupt()
    done = worker.wait(lambda e: e['type'] == 'commandFinished' and e.get('commandId') == command, start)
    _, text, _ = worker.execute('c(waiting_value, kept, exists("after_sleep", inherits=FALSE))')
    check(done['status'] == 'interrupted' and '7 41  0' in text, 'Stop interrupts Sys.sleep without resetting the R workspace')
    command, start = worker.begin('repeat {}')
    worker.wait(lambda e: e.get('state') == 'busy', start)
    time.sleep(.1); worker.interrupt()
    done = worker.wait(lambda e: e['type'] == 'commandFinished' and e.get('commandId') == command, start)
    check(done['status'] == 'interrupted', 'Stop interrupts a running R loop')
    command, start = worker.begin('second_unanswered <- readline("Wait again: "); second_sentinel <- TRUE')
    second_prompt = worker.wait(lambda e: e['type'] == 'inputRequested', start)
    worker.send('I', cancelled['requestId'] + '\nstale earlier answer')
    worker.wait(lambda e: e['type'] == 'inputRejected', start)
    worker.interrupt()
    done = worker.wait(lambda e: e['type'] == 'commandFinished' and e.get('commandId') == command, start)
    _, text, _ = worker.execute('c(exists("second_unanswered", inherits=FALSE), exists("second_sentinel", inherits=FALSE), kept)')
    check(second_prompt['requestId'] != cancelled['requestId'] and done['status'] == 'interrupted' and '0  0 41' in text,
          'readline still interrupts after loop and sleep interrupts, and rejects a previous request ID')
    command, start = worker.begin('if (TRUE) {')
    worker.wait(lambda e: e.get('state') == 'continuation', start)
    worker.interrupt()
    done = worker.wait(lambda e: e['type'] == 'commandFinished' and e.get('commandId') == command, start)
    _, text, _ = worker.execute('kept + 1')
    check(done['status'] == 'interrupted' and '[1] 42' in text, 'Stop clears incomplete input while retaining earlier variables')

    done, text, events = worker.execute('plot(1:3, 1:3)')
    plots = [e for e in events if e['type'] == 'plot']
    check(done['status'] == 'ok' and len(plots) == 1, 'ordinary R plot produces a closed PDF snapshot')
    first = Path(plots[0]['path']); first_hash = hashlib.sha256(first.read_bytes()).hexdigest()
    check(first.read_bytes().startswith(b'%PDF-'), 'plot attachment is a real PDF')
    _, _, events = worker.execute('cat("unchanged plot\\n"); mean(1:4)')
    check(not [e for e in events if e['type'] == 'plot'], 'nonplot expressions do not duplicate the previous chart snapshot')
    _, _, events = worker.execute('abline(a=0, b=1, col="red")')
    next_plots = [e for e in events if e['type'] == 'plot']
    check(len(next_plots) == 1 and next_plots[0]['path'] != str(first) and hashlib.sha256(first.read_bytes()).hexdigest() == first_hash,
          'later drawing retains the original device and creates a new immutable snapshot')
    _, _, events = worker.execute('for (i in 1:3) plot(1:3, (1:3)*i)')
    paths = [Path(e['path']) for e in events if e['type'] == 'plot']
    check(len(paths) == 3 and len(set(paths)) == 3 and all(p.read_bytes().startswith(b'%PDF-') for p in paths),
          'multiple plots within one expression retain separate PDF snapshots')

    done, _, events = worker.execute('plot(1:5); abline(h=3); abline(h=c(1,5), col="red"); mtext("Finished annotations", side=3)')
    plots = [e for e in events if e['type'] == 'plot']
    check(done['status'] == 'ok' and len(plots) == 1 and b'Finished annotations' in pdf_streams(plots[0]['path']),
          'one submitted chart with lines and text emits only its completed annotated page')
    done, _, events = worker.execute('plot(1:3, main="First page"); abline(h=2); plot(3:1, main="Second page"); mtext("Second finished", side=3)')
    plots = [e for e in events if e['type'] == 'plot']
    check(done['status'] == 'ok' and len(plots) == 2
          and b'First page' in pdf_streams(plots[0]['path']) and b'Second finished' in pdf_streams(plots[1]['path']),
          'two distinct plot pages in one submission remain separate complete chart snapshots')

    paired_source = (ROOT / 'FullEngine/Upstream/tests/RScript/examples/TPaired.R').read_text()
    done, text, events = worker.execute(paired_source)
    plots = [e for e in events if e['type'] == 'plot']
    check(done['status'] == 'ok' and 'Paired t-test' in text and len(plots) == 1
          and b'Mean difference and 95% limits of agreement' in pdf_streams(plots[0]['path']),
          'actual paired t agreement script emits one final chart including its last annotation')

    done, text, events = worker.execute('plot(1:3, main="Before error"); abline(h=2); stop("EXPECTED_PLOT_ERROR"); after_plot_error <- TRUE')
    plots = [e for e in events if e['type'] == 'plot']
    _, sentinel_text, _ = worker.execute('exists("after_plot_error", inherits=FALSE)')
    check(done['status'] == 'error' and 'EXPECTED_PLOT_ERROR' in text and len(plots) == 1
          and b'Before error' in pdf_streams(plots[0]['path']) and '[1] FALSE' in sentinel_text,
          'error flushes existing drawing once without running remaining source')

    command, start = worker.begin('plot(1:3, main="Before Stop"); abline(h=2); cat("PLOT_WAITING\\n"); Sys.sleep(30); after_plot_stop <- TRUE')
    worker.wait(lambda e: e['type'] == 'output' and 'PLOT_WAITING' in e.get('text', ''), start)
    worker.interrupt()
    done = worker.wait(lambda e: e['type'] == 'commandFinished' and e.get('commandId') == command, start)
    plots = [e for e in worker.events[start:] if e['type'] == 'plot']
    _, sentinel_text, _ = worker.execute('exists("after_plot_stop", inherits=FALSE)')
    check(done['status'] == 'interrupted' and len(plots) == 1
          and b'Before Stop' in pdf_streams(plots[0]['path']) and '[1] FALSE' in sentinel_text,
          'Stop flushes existing drawing once, retains interruption status and skips remaining source')
    _, text, _ = worker.execute('length(dev.list())')
    check('[1] 1' in text, 'snapshotting never closes the learner graphics device')
    print('PASS: interactive R worker integration completed', flush=True)
finally:
    worker.close()

check_abrupt_parent_exit()
check_abrupt_parent_exit(during_input=True)
