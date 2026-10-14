"""Independent BIFF8 reader verifies legacy export; boundary errors preserve destination."""
import json,subprocess,tempfile,sys
from pathlib import Path
import xlrd
root=Path(__file__).resolve().parents[1]
p=subprocess.Popen([sys.argv[1] if len(sys.argv)>1 else str(root/'.build/workbook-driver'),str(root/'FullEngine/publish/StatsDirectEngine.dylib')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
def req(**v):
 p.stdin.write(json.dumps(v)+'\n');p.stdin.flush();return json.loads(p.stdout.readline())
try:
 with tempfile.TemporaryDirectory() as tmp:
  f=Path(tmp)/'data.xls'
  cells=[dict(col=0,row=0,text='0012',kind='text'),dict(col=1,row=0,text='1.5',kind='number'),dict(col=2,row=0,text='=1+1',kind='text'),dict(col=3,row=0,text='true',kind='boolean'),dict(col=4,row=0,text='2026-10-14',kind='datetime'),dict(col=255,row=65535,text='edge',kind='text')]
  r=req(action='exportXls',path=str(f),sheets=[dict(name='Data',cells=cells),dict(name='Other',cells=[])]);assert r.get('ok'),r
  b=xlrd.open_workbook(f);sh=b.sheet_by_index(0);assert b.sheet_names()==['Data','Other'];assert sh.cell_value(0,0)=='0012';assert sh.cell_value(0,1)==1.5;assert sh.cell_type(0,1)==xlrd.XL_CELL_NUMBER;assert sh.cell_value(0,2)=='=1+1';assert sh.cell_type(0,2)==xlrd.XL_CELL_TEXT;assert sh.cell_type(0,3)==xlrd.XL_CELL_BOOLEAN;assert sh.cell_type(0,4)==xlrd.XL_CELL_DATE;assert sh.cell_value(65535,255)=='edge'
  previous=f.read_bytes()
  for cell in [dict(col=256,row=0,text='overflow',kind='text'),dict(col=0,row=65536,text='overflow',kind='text'),dict(col=0,row=0,text='x'*32768,kind='text')]:
   r=req(action='exportXls',path=str(f),sheets=[dict(name='Data',cells=[cell])]);assert r.get('error'),r;assert f.read_bytes()==previous
  print('PASS: independent XLS values/types/dates, literal formulas, multiple sheets, exact BIFF8 limits and atomic failure')
finally:p.terminate();p.wait()
