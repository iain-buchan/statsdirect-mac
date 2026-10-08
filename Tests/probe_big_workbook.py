"""Times the streaming Excel paths on a workbook of Excel's full height (1,048,576 rows x 4).

Usage: python3 Tests/probe_big_workbook.py <repo root> <node> [workbook-driver]
The driver defaults to .build/workbook-driver (built from Tests/bridge-driver.cpp's workbook
variant). The probe workbook is written with openpyxl on first use.
"""
import json, subprocess, sys, time, re, zipfile, os, random
from pathlib import Path
ROOT = Path(sys.argv[1]); node = sys.argv[2]; driver = Path(sys.argv[3]) if len(sys.argv) > 3 else ROOT/'.build/workbook-driver'
big = ROOT/'.build/big.xlsx'
if not big.exists():
    import openpyxl
    book = openpyxl.Workbook(write_only=True); sheet = book.create_sheet('Big'); rnd = random.Random(1)
    sheet.append(['x', 'y', 'group', 'w'])
    for r in range(1048575): sheet.append([r, rnd.gauss(0, 1), r % 7, round(rnd.random() * 1000, 3)])
    book.save(big)
proc = subprocess.Popen([str(driver), str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def request(**payload):
    t = time.time(); proc.stdin.write(json.dumps(payload) + '\n'); proc.stdin.flush(); r = json.loads(proc.stdout.readline()); return r, time.time() - t
def rss():
    return int(subprocess.check_output(['ps', '-o', 'rss=', '-p', str(proc.pid)]).strip()) // 1024
snap = ROOT/'.build/snap-probe'; snap.mkdir(exist_ok=True)
opened, dt = request(action='open', path=str(ROOT/'.build/big.xlsx'), snapshot=str(snap))
print(f'open big.xlsx (snapshot): {dt:.2f}s, cells {opened["cellCount"]:,}, rss {rss()} MB, snapshot {Path(opened["sheets"][0]["snapshot"]).stat().st_size/1e6:.1f} MB')
# (a) new workbook holding every cell of the big sheet, written by the streaming writer
new_file = ROOT/'.build/big-new.xlsx'
saved, dt = request(action='save', path=str(new_file), snapshot=opened['sheets'][0]['snapshot'])
print(f'save 4,194,304 cells as a new workbook: {dt:.2f}s, ok={saved.get("ok")}, {new_file.stat().st_size/1e6:.1f} MB, rss {rss()} MB')
reopened, dt = request(action='open', path=str(new_file), snapshot=str(snap))
print(f'reopen new workbook: {dt:.2f}s, cells {reopened["cellCount"]:,}, rows {reopened["sheets"][0]["rows"]:,}')
with zipfile.ZipFile(new_file) as z:
    xml = z.read('xl/worksheets/sheet1.xml')
    print('  cells in XML:', len(re.findall(rb'<c ', xml)), ' first row:', xml[xml.find(b'<row '):xml.find(b'<row ')+160])
    print('  last row tail:', xml[-200:])
# (b) one-cell edit of the opened big workbook: streams the worksheet part
edits = ROOT/'.build/big-edit.sdcol'
subprocess.check_call([node, str(ROOT/'.build/edit-one.mjs'), str(edits)])
patched = ROOT/'.build/big-patched.xlsx'
saved, dt = request(action='save', id=opened['id'], path=str(patched), snapshot=str(edits))
print(f'streaming patch of big.xlsx (2 cells): {dt:.2f}s, {saved}, {patched.stat().st_size/1e6:.1f} MB, rss {rss()} MB')
with zipfile.ZipFile(patched) as z:
    xml = z.read('xl/worksheets/sheet1.xml')
    i = xml.find(b'r="B1048576"'); print('  edited cell:', xml[i-5:i+60])
    i = xml.find(b'r="B8"'); print('  edited text cell:', xml[i-5:i+80])
    print('  cells in XML:', len(re.findall(rb'<c ', xml)))
check, dt = request(action='open', path=str(patched), snapshot=str(snap))
print(f'reopen patched: {dt:.2f}s, cells {check["cellCount"]:,}')
print(request(action='close', id=opened['id'])[0], request(action='close', id=reopened['id'])[0], request(action='close', id=check['id'])[0])
proc.stdin.close(); proc.wait()
for f in snap.iterdir(): f.unlink()
