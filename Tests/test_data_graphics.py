"""Exercise Data and Graphics menu forms through the actual engine bridge."""
import json
from test_menu import Session, columns, ROOT
s=Session();results=[]
cases={
 'FillSeries':{'rows':5,'startval':1,'formula':'X+1','title':'Sequence'},
 'SearchAndReplace':{'search-type':'text','search-rule':'equal','search-expression':'old','action':'replace-value','replace-expression':'new','data':columns(['old','older','keep'])},
 'SearchAndReplaceAdvanced':{'search-type':'text','search-rule':'equal','search-expression':'old','action':'replace-value','replace-expression':'new','data':columns(['old','older','keep'])},
 'ClearMissing':{'data':columns([1,'*',3,4]),'missing-text':''},
 'TextCode':{'data':columns(['red','blue','red','green'])},
 'Dates':{'data':columns(['2026-01-02','2026-01-11']),'indate':'2026-01-01','interval':'d'},
 'GroupCategorise':{'data':columns([1,2,3,4,5,6])},
 'GroupExtract':{'data':columns([1,2,3,4,5,6]),'identifiers':columns([1,1,1,2,2,2]),'Extract matching rows':{'expression':'X1=2'}},
 'TransformLog':{'data':columns([-1,0,1,2,3,4]),'c':2},
 'TransformLog10':{'data':columns([1,10,100,1000])},
 'TransformLogit':{'data':columns([.1,.2,.4,.6,.8,.9])},
 'TransformProbit':{'data':columns([.1,.2,.4,.6,.8,.9])},
 'TransformAngular':{'data':columns([.1,.2,.4,.6,.8,.9])},
 'TransformCumulate':{'data':columns([1,2,3,4])},
 'TransformECDF':{'data':columns([3,1,4,2])},
 'TransformZSD':{'data':columns([1,2,3,4])},
 'LadderPowers':{'data':columns([1,2,3,4])},
 'ApplyFunction':{'data':columns([1,2,3,4]),'expression':'X*2','new_column_name':'Doubled'},
 'PairDifferences':{'y':columns([5,8,11]),'x':columns([1,2,3])},
 'PairMeans':{'y':columns([5,8,11,1,2,3])},
 'PairSlopes':{'y':columns([3,6,8,11,13]),'x':columns([1,2,3,4,5])},
 'Normal':{'data':columns([3,1,4,2,5])},
 'Standardize':{'data':columns([3,1,4,2,5])},
 'Rank':{'data':columns([3,1,4,2,5])},
 'UnivariateSummaryToWorksheetOnly':{'data':columns([1,2,3,4,5,6,7,8])},
 'ConvertUnits':{'data':columns([0,100]),'conversion':'(X*1.8)+32|Degrees (F)'},
 'ConvertUnitsScreen':{'data':columns([0,100]),'conversion':'(X*1.8)+32|Degrees (F)'},
 'SortInPlace':{'data':columns([3,1,4,2],[30,10,40,20])},
 'Sort':{'data':columns([3,1,4,2])},
 'ToggleFilters':{'data':columns([3,1,4,2],[30,10,40,20]),'Filter worksheet rows':{'column':1,'match':'1'}},
 'Rotate':{'data':columns([1,2,3],[4,5,6])},
 'Combine':{'data':columns([1,2,3],[4,5,6])},
 'GroupSplit':{'gids':columns(['A','A','B','B']),'data':columns([1,2,3,4])},
 'DummyVariables':{'data':columns(['A','B','A','C','B','C'])},
 'Tabulate':{'rows':columns(['A','A','B','B']),'columns':columns(['X','Y','X','Y'])},
 'Detabulate':{'data':columns([1,2],[3,4])},
 'ExpandFrequencies':{'categories':columns(['A','B']),'counts':columns([2,3])},
 'ContractFrequencies':{'categories':columns(['A','B','A','B','B'])},
 'BarPlot':{'values':columns([3,5,2]),'labels':columns(['A','B','C'])},
 'BarPlotFrequency':{'rawValues':columns(['A','B','A','C','B'])},
 'BoxWhiskerPlot':{'data':columns([1,2,3,4,7],[2,3,5,7,8])},
 'BoxWhiskerPlotText':{'data':columns([1,2,3,4,7],[2,3,5,7,8])},
 'ControlPlot':{'Y':columns([10,11,9,12,11,10]),'X':columns([1,2,3,4,5,6])},
 'ErrorPlot':{'group-count':1,'ydatNew':columns([2,4,3]),'xdatNew':columns([1,2,3]),'ydatuNew':columns([3,5,4]),'ydatlNew':columns([1,3,2])},
 'CochranePlot':{'odds':columns([.8,1.2,1.1]),'lci':columns([.5,.9,.8]),'uci':columns([1.2,1.5,1.4]),'gn':columns([100,120,150]),'pg':columns([0,0,0]),'title':columns(['A','B','C'])},
 'HistogramPlot':{'data':columns([1,2,2,3,4,5,6,7,8,9,10])},
 'HistogramPlotText':{'data':columns([1,2,2,3,4,5,6,7,8,9,10])},
 'LadderPlot':{'data':columns([1,2,3,4],[2,4,4,6])},
 'LinePlot':{'n':1,'Ynew':columns([2,4,3,5]),'Xnew':columns([1,2,3,4])},
 'NormalPlot':{'X':columns([1,2,3,4,5,6,7,8,10])},
 'PyramidPlot':{'male':columns([10,20,15]),'female':columns([12,22,17]),'labels':columns(['Young','Middle','Older'])},
 'ROCPlot':{'series-count':1,'P1':columns([2,4,6,8,10]),'A1':columns([1,2,3,5,7])},
 'ScatterPlot':{'n':1,'Ynew':columns([2,4,3,5]),'Xnew':columns([1,2,3,4])},
 'ScatterPlotText':{'Y':columns([2,4,3,5]),'X':columns([1,2,3,4])},
 'SpreadPlot':{'data':columns([1,2,3,5,6],[2,3,4,6,8])},
 'SurvivalPlot':{'group-count':1,'xdatNew':columns([1,2,3,4]),'cdatNew':columns([0,0,0,0]),'ydatNew':columns([.9,.8,.7,.6]),'ydatlNew':columns([.8,.7,.6,.5]),'ydatuNew':columns([1,.9,.8,.7])},
 'GraphicsOptions':{},
}
catalog=json.loads((ROOT/'Content/analysis-menu.json').read_text())
for op in catalog['operations']:
 if op.startswith('Rnd'):cases[op]={'cols':2,'rows':6,'seed':31415,'df':5,'dfn':5,'dfd':8,'a':2,'b':3,'p':.4,'xm':2,'sd':1,'n':5,'nn':5,'l':0,'s':1,'mu':0,'sigma':1}
for name,answers in cases.items():
 try:
  result=s.run(name,answers)
  assert 'Error rendering' not in result['html'] and 'Chart not drawn' not in result['html'],result['html'][:1000]
  assert result['html'] or result['frames'] or name=='GraphicsOptions'
  if name in ['BarPlot','ScatterPlot','HistogramPlot','BoxWhiskerPlot','NormalPlot','LinePlot']:assert '<svg' in result['html']
  expected={'FillSeries':['1','2','3','4','5'],'Dates':['1','10'],'TextCode':['1','2','1','3'],'GroupCategorise':['1','1','1','2','2','2'],'GroupExtract':['4','5','6'],'ConvertUnits':['32','212'],'ConvertUnitsScreen':['32','212'],'SortInPlace':['1','2','3','4'],'ToggleFilters':['1'],'SearchAndReplace':['new','older','keep'],'SearchAndReplaceAdvanced':['new','older','keep']}
  if name in expected:
   actual=[c['text'] for c in result['frames'][0]['cells'] if c['col']==0 and c['row']>0]
   assert actual==expected[name],(name,actual,expected[name])
  results.append({'operation':name,'result':'pass','frames':result['frames']});print('PASS',name,flush=True)
 except Exception as e:
  results.append({'operation':name,'error':str(e)});print('FAIL',name,str(e)[:700],flush=True)
s.finish()
(ROOT/'FullEngine/publish/data-graphics-test-results.json').write_text(json.dumps(results,indent=2)+'\n')
assert all('error' not in r for r in results)
