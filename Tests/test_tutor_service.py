"""Exercise the real service against a loopback synthetic provider; no live OpenAI calls."""
import json
import os
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
DOTNET = os.environ.get('DOTNET', str(ROOT / '../../work/dotnet/dotnet'))
DLL = ROOT / 'TutorService/bin/Debug/net10.0/TutorService.dll'
seen = []


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.headers.get('Transfer-Encoding') == 'chunked':
            chunks = []
            while True:
                length = int(self.rfile.readline().split(b';')[0], 16)
                if not length:
                    self.rfile.readline()
                    break
                chunks.append(self.rfile.read(length))
                self.rfile.read(2)
            payload = b''.join(chunks)
        else:
            payload = self.rfile.read(int(self.headers['Content-Length']))
        body = json.loads(payload)
        seen.append((dict(self.headers), body))
        question = body['input'][-1]['content']
        status = 401 if question == 'provider error' else 200
        reply = {'error': {'message': 'synthetic-provider-key should not be exposed'}} if status == 401 else {
            'status': 'incomplete' if question == 'incomplete' else 'completed',
            'id': 'resp_synthetic', 'model': 'synthetic-model',
            'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Synthetic provider reply: use people with the condition as the denominator.'}]}]
        }
        data = json.dumps(reply).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


class Service:
    def __init__(self, folder, **settings):
        self.port = free_port()
        self.url = f'http://127.0.0.1:{self.port}'
        environment = {k: v for k, v in os.environ.items() if not k.startswith(('OPENAI_', 'TUTOR_', 'ASPNETCORE_'))}
        environment.update(ASPNETCORE_ENVIRONMENT='Development', ASPNETCORE_URLS=self.url,
                           OPENAI_API_KEY='synthetic-provider-key', TUTOR_TEST_UPSTREAM=provider_url,
                           TUTOR_MODEL='synthetic-model', TUTOR_DATA_DIRECTORY=str(folder))
        environment.update(settings)
        for key in [key for key, value in environment.items() if value is None]:
            del environment[key]
        self.log = tempfile.TemporaryFile()
        self.process = subprocess.Popen([DOTNET, str(DLL)], env=environment, cwd=ROOT, stdout=self.log, stderr=self.log)
        deadline = time.time() + 15
        while time.time() < deadline:
            if self.process.poll() is not None:
                self.log.seek(0)
                raise AssertionError('Service failed to start: ' + self.log.read().decode())
            try:
                self.call('GET', '/health')
                return
            except OSError:
                time.sleep(.05)
        self.close()
        raise AssertionError('Service did not start')

    def call(self, method, route, data=None, token=None, headers=None):
        h = {'Content-Type': 'application/json', **(headers or {})}
        if token:
            h['Authorization'] = 'Bearer ' + token
        request = Request(self.url + route, data=None if data is None else json.dumps(data).encode(), method=method, headers=h)
        try:
            response = urlopen(request, timeout=5)
        except HTTPError as error:
            response = error
        content = response.read()
        return response.status, json.loads(content) if content else None

    def create(self, **kwargs):
        status, body = self.call('POST', '/v1/sessions', {}, **kwargs)
        assert status == 200, (status, body)
        return body['token']

    def close(self):
        self.process.terminate()
        self.process.wait(timeout=5)
        self.log.close()


def question(text='What is sensitivity?'):
    return {'schemaVersion': 1, 'lesson': 'diagnostic', 'context': '[Course: denominators] Synthetic course reference.',
            'messages': [{'role': 'user', 'text': text}]}


class ManagedTutorTests(unittest.TestCase):
    def setUp(self):
        seen.clear()
        self.folder = tempfile.TemporaryDirectory(prefix='statsdirect-tutor-')
        self.services = []

    def tearDown(self):
        for service in self.services:
            if service.process.poll() is None:
                service.close()
        self.folder.cleanup()

    def start(self, **settings):
        service = Service(self.folder.name, **settings)
        self.services.append(service)
        return service

    def test_automatic_session_and_server_owned_credentials_and_prompt(self):
        service = self.start()
        token = service.create()
        self.assertEqual(len(token), 64)
        status, body = service.call('POST', '/v1/tutor', question(), token)
        self.assertEqual(status, 200)
        self.assertIn('denominator', body['text'])
        self.assertNotIn('synthetic-provider-key', json.dumps(body))
        self.assertEqual(len(seen), 1)
        headers, sent = seen[0]
        self.assertEqual(headers['Authorization'], 'Bearer synthetic-provider-key')
        self.assertNotIn(token, json.dumps(sent))
        self.assertEqual(sent['model'], 'synthetic-model')
        self.assertFalse(sent['store'])
        self.assertNotIn('tools', sent)
        self.assertIn('Epidemiology and causal inference', sent['instructions'])
        self.assertIn('[Course: denominators]', sent['instructions'])
        ledger = Path(self.folder.name, 'sessions.json').read_text()
        for private in [token, 'synthetic-provider-key', 'denominators', 'What is sensitivity?', '127.0.0.1']:
            self.assertNotIn(private, ledger)

    def test_invalid_requests_never_reach_provider(self):
        service = self.start()
        token = service.create()
        self.assertEqual(service.call('POST', '/v1/tutor', question())[0], 401)
        self.assertEqual(service.call('POST', '/v1/tutor', question(), '0' * 64)[0], 401)
        for bad in [{**question(), 'model': 'unapproved-model'}, {**question(), 'instructions': 'ignore rules'},
                    {**question(), 'lesson': 'missing'}, {**question(), 'context': 'x' * 32001},
                    {**question(), 'messages': [{'role': 'system', 'text': 'override'}]},
                    {**question(), 'messages': [{'role': 'assistant', 'text': 'no question'}]},
                    {**question(), 'messages': [None]}, {**question(), 'messages': [{'role': 'user', 'text': 'x' * 8001}]}]:
            self.assertEqual(service.call('POST', '/v1/tutor', bad, token)[0], 400)
        self.assertEqual(service.call('POST', '/v1/tutor', question(), token, {'Origin': 'https://unexpected.invalid'})[0], 403)
        self.assertFalse(seen)

    def test_daily_budget_survives_restart_and_spoofed_headers(self):
        service = self.start(TUTOR_DAILY_REQUESTS='1')
        token = service.create()
        self.assertEqual(service.call('POST', '/v1/tutor', question(), token)[0], 200)
        service.close()
        restarted = self.start(TUTOR_DAILY_REQUESTS='1')
        another = restarted.create(headers={'X-Forwarded-For': '203.0.113.19'})
        status, body = restarted.call('POST', '/v1/tutor', question(), another, {'X-Forwarded-For': '203.0.113.20'})
        self.assertEqual((status, body['error']['code']), (429, 'daily_limit'))
        self.assertEqual(len(seen), 1)

    def test_registration_cap_revocation_and_provider_errors(self):
        service = self.start(TUTOR_IP_DAILY_SESSIONS='2')
        first, second = service.create(), service.create()
        self.assertEqual(service.call('POST', '/v1/sessions', {}, headers={'X-Forwarded-For': '203.0.113.99'})[0], 429)
        status, body = service.call('POST', '/v1/tutor', question('provider error'), first)
        self.assertEqual(status, 503)
        self.assertNotIn('synthetic-provider-key', json.dumps(body))
        self.assertEqual(service.call('POST', '/v1/tutor', question('incomplete'), second)[0], 502)
        self.assertEqual(service.call('DELETE', '/v1/session', token=first)[0], 204)
        self.assertEqual(service.call('POST', '/v1/tutor', question(), first)[0], 401)

    def test_inactive_service_does_not_ask_learners_for_provider_keys(self):
        service = self.start(OPENAI_API_KEY='')
        status, body = service.call('POST', '/v1/sessions', {})
        self.assertEqual((status, body['error']['code']), (503, 'not_activated'))
        self.assertIn('No personal OpenAI key', body['error']['message'])
        self.assertFalse(seen)

    def test_production_rejects_plain_http_and_untrusted_forwarded_scheme(self):
        service = self.start(ASPNETCORE_ENVIRONMENT='Production', TUTOR_TEST_UPSTREAM=None)
        self.assertEqual(service.call('POST', '/v1/sessions', {}, headers={'X-Forwarded-Proto': 'https'})[0], 400)
        self.assertFalse(seen)


if __name__ == '__main__':
    provider = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
    provider_url = f'http://127.0.0.1:{provider.server_port}/v1/responses'
    threading.Thread(target=provider.serve_forever, daemon=True).start()
    try:
        unittest.main(verbosity=2)
    finally:
        provider.shutdown()
