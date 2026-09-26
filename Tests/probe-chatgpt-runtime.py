#!/usr/bin/env python3
"""Contract probe against the pinned real runtime; signed out, no model call possible."""
import json, os, pathlib, selectors, subprocess, sys, tempfile
runtime, resources = map(lambda p: pathlib.Path(p).resolve(), sys.argv[1:])
with tempfile.TemporaryDirectory(prefix='statsdirect-protocol-') as temporary:
    root = pathlib.Path(temporary); workspace = root/'Workspace'; workspace.mkdir()
    (root/'config.toml').write_bytes((resources/'config.toml').read_bytes())
    env = {k:v for k,v in os.environ.items() if k in ['HOME','USER','LOGNAME','TMPDIR','LANG']}
    env.update(CODEX_HOME=str(root), PATH='/usr/bin:/bin:/usr/sbin:/sbin',RUST_LOG='off')
    process = subprocess.Popen([str(runtime),'--strict-config'],cwd=workspace,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
    def write(message): process.stdin.write(json.dumps(message)+'\n'); process.stdin.flush()
    def call(i, method, params):
        write({'id':i,'method':method,'params':params})
        while True:
            line = process.stdout.readline()
            assert line, 'Runtime exited'
            item = json.loads(line)
            if item.get('id') == i:
                assert 'error' not in item, item.get('error')
                return item['result']
    try:
        call(1,'initialize',{'clientInfo':{'name':'statsdirect_contract_test','version':'0.3.4'},'capabilities':{'experimentalApi':True}})
        write({'method':'initialized'})
        assert call(2,'account/read',{'refreshToken':False})['account'] is None
        thread = call(3,'thread/start',{'cwd':str(workspace),'approvalPolicy':'never','sandbox':'read-only','ephemeral':True,'environments':[],'baseInstructions':'You are a biostatistics tutor. Only use the supplied StatsDirect tools.', 'dynamicTools':[{'type':'function','name':'statsdirect_workspace','description':'Read open StatsDirect document metadata','inputSchema':{'type':'object','properties':{},'required':[],'additionalProperties':False}}]})
        assert thread['instructionSources'] == [], thread['instructionSources']
        assert thread['sandbox']['type'] == 'readOnly'
        # Validation and context creation are local. With no account this cannot contact a model.
        turn = call(4,'turn/start',{'threadId':thread['thread']['id'],'environments':[],'sandboxPolicy':{'type':'readOnly','networkAccess':False},'input':[{'type':'text','text':'Protocol validation only.'}]})
        assert turn['turn']['id']
        call(5,'turn/interrupt',{'threadId':thread['thread']['id'],'turnId':turn['turn']['id']})
        call(6,'thread/unsubscribe',{'threadId':thread['thread']['id']})
        print('Pinned runtime: initialization, signed-out account, no-environment thread with a controlled dynamic tool, turn schema, interrupt and unsubscribe passed')
    finally:
        process.stdin.close(); process.terminate(); process.wait(timeout=5)
