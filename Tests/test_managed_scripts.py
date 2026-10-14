"""Execute both Windows scripting languages against the real Mac host."""
import uuid
from test_menu import Session
s=Session()
def run(language,script,answer=None):
 id=str(uuid.uuid4());r=s.request(action='start',id=id,operation='UserScript',language=language,script=script)
 assert not r.get('error'),r
 r=s.wait(id)
 if answer is not None:
  assert r['state']=='input' and r['prompt']['kind']=='boolean',r
  s.request(action='answer',id=id,token=r['token'],value=answer);r=s.wait(id)
 s.close(id);return r
try:
 for language,code in [('CSharp','Console.WriteLine(Math.Sqrt(81));'),('VB','Console.WriteLine(Math.Sqrt(81))')]:
  r=run(language,code);assert r['state']=='complete' and r['console'].strip()=='9',r
 r=run('CSharp','bool cancelled; var yes = host.GetBoolean("Proceed?", "Check", true, out cancelled); Console.WriteLine(yes); host.Warning("Script report", "Host");',True)
 assert r['state']=='complete' and r['console'].strip()=='True' and 'Script report' in r['html'],r
 for language in ['VB','CSharp']:
  r=run(language,'not valid code !');assert r['state']=='failed' and r.get('error'),r
 r=run('CSharp','Console.WriteLine("before"); throw new Exception("user failure");')
 assert r['state']=='failed' and r['console'].strip()=='before',r
 # Console routing and locks are restored after a failing script.
 r=run('VB','Console.WriteLine(6 * 7)');assert r['state']=='complete' and r['console'].strip()=='42',r
 id=str(uuid.uuid4());s.request(action='start',id=id,operation='UserScript',script='bool c; host.GetBoolean("Cancel?", "Check", true, out c);',language='CSharp')
 r=s.wait(id);assert r['state']=='input',r
 s.request(action='cancel',id=id);r=s.wait(id);assert r['state']=='cancelled',r;s.close(id)
 ids=[str(uuid.uuid4()),str(uuid.uuid4())]
 for i,id in enumerate(ids):
  s.request(action='start',id=id,operation='UserScript',language='CSharp',script=f'Console.WriteLine("start{i}"); bool c; host.GetBoolean("Wait", "Check", true, out c); Console.WriteLine("end{i}");')
 states=[s.wait(id) for id in ids]
 for i,id in enumerate(ids):
  assert states[i]['state']=='input',states[i]
  s.request(action='answer',id=id,token=states[i]['token'],value=True);r=s.wait(id)
  assert r['console'].splitlines()==[f'start{i}',f'end{i}'],r;s.close(id)
 print('PASS: C#/VB compilation, numeric execution, native host input/report, compile/runtime failures, console restoration and cancellation')
finally:s.finish()
