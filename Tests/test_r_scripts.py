"""Run generated R scripts from actual completed engine sessions (no mock input history)."""
from pathlib import Path
import json, subprocess, sys, tempfile
from test_menu import Session, columns, ROOT

R=Path('/Library/Frameworks/R.framework/Resources/bin/Rscript')
GEN=Path(sys.argv[2]).resolve()
session=Session()
cases={
 'TPaired':{'data':columns([312,242,340,388,296,254,391,402,290],[300,201,232,312,220,256,328,330,231]),'doAgreement':True},
 'TSingle':{'data':columns([1,2,3,4,5,7]),'population-mean':3},
 'TUnpaired':{'data':columns([1,2,3,5,6],[4,5,6,7,9])},
 'TSingleSummary':{'nx':10,'mu':12,'sd1':3,'mu0':10},
 'TUnpairedSummary':{'nx1':10,'um1':12,'sd1':3,'nx2':12,'um2':9,'sd2':4},
 'ExactSign':{'n':20,'r':15},
 'PropSingle':{'n':100,'r':20,'qpi':.2},
 'ExactFisher':{'scrap':columns([1,11],[9,3])},
 'ExactFisherX':{'scrap':columns([1,11],[9,3])},
 'ExactORCML':{'scrap':columns([1,11],[9,3])},
 'Chi2by2':{'scrap':columns([20,10],[10,20]),'doFisher':True},
 'ExactMcNamar':{'scrap':columns([20,10],[5,20])},
 'ExactMcNamarChi':{'scrap':columns([20,10],[5,20])},
 'ExactChiRbyC':{'data':columns([10,12,8],[9,11,15]),'doExact':True},
 'ExactFisherRbyC':{'data':columns([10,12,8],[9,11,15]),'doExact':True},
 'RatePoissonCI':{'revents':12,'tar':1000},
 'UnivariateSummary':{'data':columns([1,2,3,4,5,6,7,8,9,10])},
 'UnivariateSummaryToWorksheetOnly':{'data':columns([1,2,3,4,5,6,7,8,9,10])},
 'QuickSummary':{'data':columns([1,2,3,4,5])},
 'Normality':{'data':columns([1,2,2,3,4,5,6,7,8,10])},
 'MannWhitney':{'data':columns([1,2,3,4,5],[4,6,7,8,9])},
 'Wilcoxon':{'data':columns([2,3,5,7,9],[1,1,4,5,6])},
 'Spearman':{'data':columns([1,2,3,4,5],[3,1,4,5,7])},
 'Kendall':{'data':columns([1,2,3,4,5],[3,1,4,5,7])},
 'Smirnov':{'data':columns([1,2,3,4,5],[4,6,7,8,9])},
 'Kruskal':{'data':columns([1,2,3,4],[3,5,6,8],[7,8,9,11])},
 'OneWay':{'data':columns([1,2,3,4],[3,5,6,8],[7,8,9,11])},
 'SimpleLinearRegression':{'y':columns([3,4,5,7,9,11]),'x':columns([1,2,3,4,5,6])},
 'VarianceRatio':{'data':columns([1,2,3,4,5],[2,3,4,6,9])},
}
for name in ['Normal','T','F','ChiSquare','Q','Binomial','Poisson','NonCentralT']:cases['Distribution'+name]={}
# Compare the generated R analysis with outputs from the original engine.
assertions={
 'TPaired':'stopifnot(abs(result$p.value-original_results$tail_2)<1e-10, abs(result$estimate-original_results$mean)<1e-10, file.exists("agreement.pdf"))',
 'TSingleSummary':'stopifnot(abs(result$statistic-original_results$t)<1e-10, abs(result$p.value-original_results$p_2)<1e-10, abs(result$conf.int[1]-original_results$from)<1e-10)',
 'ExactFisher':'stopifnot(abs(exact_result$p.value-original_results$p_2)<1e-10)',
 'Spearman':'stopifnot(abs(result$estimate-original_results$rho)<1e-10)',
 'OneWay':'stopifnot(abs(result[[1]][1,"F value"]-original_results$f)<1e-10, abs(result[[1]][1,"Pr(>F)"]-original_results$p)<1e-10)',
 'SimpleLinearRegression':'stopifnot(abs(coef(model)[2]-original_results$slope)<1e-10)',
}
def generate_run(folder,name,output,check=''):
 snapshot=folder/(name+'.json');script=folder/(name+'.R')
 snapshot.write_text(json.dumps({'operation':name,'output':output,'title':'Verification: '+name}))
 result=subprocess.check_output([str(GEN),str(snapshot),str(ROOT/'Content'),str(script)],text=True).strip()
 with script.open('a') as f:f.write('\n'+check+'\n')
 run=subprocess.run([str(R),'--vanilla',str(script)],cwd=folder,text=True,capture_output=True,timeout=60)
 assert run.returncode==0,(name,run.stdout[-2000:],run.stderr[-2000:])
 return result,script.read_text()
failures=[]
try:
 with tempfile.TemporaryDirectory(prefix='statsdirect-r-scripts-') as directory:
  folder=Path(directory)
  for name,answers in cases.items():
   try:
    output=session.run(name,answers)
    assert all('name' in h and 'kind' in h for h in output['history'])
    assert generate_run(folder,name,output,assertions.get(name,''))[0]=='recipe'
    if name=='TPaired':
     assert any(h['name']=='gamma' and h['kind']=='confidence' and h['value']==95 for h in output['history'])
    print('PASS',name,flush=True)
   except Exception as error:failures.append((name,str(error)));print('FAIL',name,str(error)[:2500],flush=True)
  # Matched missing values must keep pair alignment; custom confidence must survive export.
  preferences={'use-default-ci':True,'default-ci':'90','selectGroupsByIdentifier':False,'decp':'6','pdecp':'4','use-scientific-notation-for-small-p-values':False}
  output=session.run('TPaired',{'data':columns([10,'*',20,30],[8,9,17,25]),'doAgreement':True},preferences=preferences)
  generate_run(folder,'TPaired',output,'stopifnot(nrow(data)==3, confidence==0.9, abs(result$p.value-original_results$tail_2)<1e-10)')
  print('PASS paired missing values and 90% confidence',flush=True)
  # The selected block is the only data passed to R, despite a taller worksheet.
  selected=columns([10,'',20,30],[8,9,17,'']);selected.update(preserveRows=True,source='Worksheet rows 5–8',range={'firstRow':5,'lastRow':8,'columns':[1,2]})
  output=session.run('TPaired',{'data':selected})
  _,script=generate_run(folder,'TPaired',output,'stopifnot(identical(unname(lengths(data_frames$data)), c(4L,4L)), is.na(data_frames$data[[1]][2]), is.na(data_frames$data[[2]][4]), nrow(data)==2, abs(result$p.value-original_results$tail_2)<1e-10, input_history[[1]]$value$range$firstRow==5, input_history[[1]]$value$data_frame=="data", is.null(input_history[[1]]$value$columns))')
  print('PASS exact selected block, aligned missing cells and non-duplicated R history',flush=True)
  # Single-column differences use one-sample t, without generating a bogus second series.
  output=session.run('TPaired',{'data':columns([2,3,5,4,8])})
  generate_run(folder,'TPaired',output,'stopifnot(ncol(data)==1, abs(result$p.value-original_results$tail_2)<1e-10)')
  print('PASS single-column paired differences',flush=True)
  # Unknown methods produce an explicitly labelled starter and preserve hostile-looking text literally.
  payload='quote " \\ Unicode café\n);system("touch INJECTION_EXECUTED");#'
  output={'history':[{'name':'text','kind':'text','title':'Input','value':payload},{'name':'data','kind':'grid','mode':'Text','value':columns([payload,'0012',''])}]}
  kind,script=generate_run(folder,'UnmappedMethod',output,'stopifnot(identical(parameters$text,data_frames$data[[1]][1]), data_frames$data[[1]][2]=="0012", !file.exists("INJECTION_EXECUTED"))')
  assert kind=='starter' and 'not yet available' in script
  print('PASS unsupported method is honest and quoted input cannot execute code',flush=True)
  # Column names may legitimately be blank or repeated.
  frame=columns([2,4,7],[1,2,3]);frame['columns'][0]['title']='';frame['columns'][1]['title']=''
  output=session.run('TPaired',{'data':frame})
  generate_run(folder,'TPaired',output,'stopifnot(identical(names(data_frames$data), c("", "")))')
  print('PASS empty and repeated column labels',flush=True)
  # Generated output tables are available for deeper analysis even without a method recipe.
  output=session.run('FillSeries',{'rows':5,'startval':10,'formula':'X+2','title':'Generated values'})
  kind,_=generate_run(folder,'FillSeries',output,'stopifnot(identical(result_tables[[1]][[1]],c(10,12,14,16,18)))')
  assert kind=='starter'
  print('PASS result tables survive the R handoff',flush=True)
  # The dedicated R×C screen has a separate snapshot shape.
  output={'input':{'counts':[[10,9],[12,11],[8,15]],'rowLabels':['a','b','c'],'columnLabels':['x','y'],'doExact':True,'doMonteCarlo':True,'iterations':500,'seed':12345,'cco':.9},'values':{}}
  generate_run(folder,'ExactChiRbyCScreen',output,'stopifnot(identical(dim(counts),c(3L,2L)),confidence==.9,is.finite(simulation$p.value))')
  print('PASS dedicated contingency snapshot, Fisher and Monte Carlo',flush=True)
finally:session.finish()
if failures:raise AssertionError(failures)
print('PASS all generated scripts and engine comparisons')
