"""The Distributions calculator on the Mac, as the Windows ctlPDF: the probabilities of a value, and (the value box left empty, one
probability box filled) the value of a probability. R is the arbiter for every figure it has a function for; the record of each run
carries the boxes under the Windows names (value, df, df2, lower, upper, two_sided, asked), as RunRecord writes them."""
from r_runtime import rscript as find_rscript
from test_menu import Session, ROOT
import json, math, subprocess, sys

R=find_rscript()
def r(expression):
    out=subprocess.check_output([R,'--vanilla','-e','cat(sprintf("%.15g", '+expression+'))'],text=True,stderr=subprocess.DEVNULL)
    return float(out.strip().splitlines()[-1])
def near(got,expected,rel=1e-9,abs_tol=1e-12):
    assert math.isclose(got,expected,rel_tol=rel,abs_tol=abs_tol),(got,expected)
session=Session()
def run(name,boxes):
    """Run Distribution<name> answering its one form; return the completed snapshot and the record's parameters."""
    s=session.run('Distribution'+name,{form_title(name):boxes})
    record=json.loads(s['record']) if isinstance(s.get('record'),str) else None
    assert record and record['operation']=='Distribution'+name and record['version']==1,(name,s.get('record'))
    return s,record['parameters']
titles={'Normal':'Z','T':'T','F':'F','ChiSquare':'ChiSq','Q':'Q','Binomial':'Binomial','Poisson':'Poisson','NonCentralT':'NonCentralT'}
def form_title(name):return titles[name]+' distribution'
failures=[]
def case(label,check):
    try:check();print('PASS',label,flush=True)
    except Exception as error:failures.append((label,str(error)));print('FAIL',label,str(error)[:800],flush=True)

# The probabilities of a value: every box the distribution shows, against R, and the record's names.
def calculate_z():
    _,p=run('Normal',{'x':1.96})
    assert p['asked']=='calculate' and set(p)=={'value','lower','upper','two_sided','asked'},p
    near(p['value'],1.96);near(p['lower'],r('pnorm(1.96)'),1e-12);near(p['upper'],r('pnorm(1.96,lower.tail=FALSE)'),1e-12);near(p['two_sided'],r('2*pnorm(1.96,lower.tail=FALSE)'),1e-12)
case('normal: value gives both tails and the two-sided P, recorded as the Windows boxes',calculate_z)
def calculate_t():
    _,p=run('T',{'x':2,'df':10})
    assert p['asked']=='calculate' and p['df']==10,p
    near(p['upper'],r('pt(2,10,lower.tail=FALSE)'),1e-12);near(p['lower'],r('pt(2,10)'),1e-12);near(p['two_sided'],r('2*pt(2,10,lower.tail=FALSE)'),1e-12)
case('t: value gives both tails and the two-sided P',calculate_t)
def calculate_others():
    _,p=run('ChiSquare',{'x':7.81,'df':3});assert set(p)=={'value','df','upper','asked'},p;near(p['upper'],r('pchisq(7.81,3,lower.tail=FALSE)'),1e-12)
    _,p=run('F',{'x':3.58,'df':6,'df2':8});assert set(p)=={'value','df','df2','upper','asked'},p;near(p['upper'],r('pf(3.58,6,8,lower.tail=FALSE)'),1e-12)
    _,p=run('Q',{'x':3.8,'df':36,'df2':4});assert set(p)=={'value','df','df2','lower','upper','asked'},p;near(p['lower'],r('ptukey(3.8,4,36)'),1e-7)
    _,p=run('Binomial',{'x':0.3,'df':20,'df2':5});assert p['asked']=='calculate' and set(p)=={'value','df','df2','lower','upper','two_sided','asked'},p
    near(p['lower'],r('dbinom(5,20,0.3)'),1e-12);near(p['upper'],r('pbinom(4,20,0.3,lower.tail=FALSE)'),1e-12);near(p['two_sided'],r('pbinom(5,20,0.3)'),1e-12)
    _,p=run('Poisson',{'df':2,'df2':3});assert set(p)=={'df','df2','lower','upper','two_sided','asked'} and 'value' not in p,p
    near(p['lower'],r('dpois(2,3)'),1e-12);near(p['upper'],r('ppois(1,3,lower.tail=FALSE)'),1e-12);near(p['two_sided'],r('ppois(2,3)'),1e-12)
    _,p=run('NonCentralT',{'x':2,'df':10,'df2':1});assert set(p)=={'value','df','df2','lower','upper','asked'},p;near(p['upper'],r('pt(2,10,ncp=1,lower.tail=FALSE)'),1e-9)
case('chi-square, F, studentized range, binomial, Poisson and non-central t: the boxes each distribution shows, against R',calculate_others)

# The value of a probability: the Windows calculator's Invert, through the value box left empty.
def invert_cases():
    _,p=run('Normal',{'x':None,'upper':0.025});assert p['asked']=='invert-upper',p;near(p['value'],r('qnorm(0.975)'),1e-12);near(p['lower'],0.975,1e-12);near(p['two_sided'],0.05,1e-12)
    _,p=run('Normal',{'x':'','lower':0.975});assert p['asked']=='invert-lower',p;near(p['value'],r('qnorm(0.975)'),1e-12)
    _,p=run('Normal',{'x':None,'two_sided':0.05});assert p['asked']=='invert-two-sided',p;near(p['value'],r('qnorm(0.975)'),1e-12);near(p['upper'],0.025,1e-12)
    _,p=run('T',{'x':None,'df':10,'upper':0.025});assert p['asked']=='invert-upper',p;near(p['value'],r('qt(0.975,10)'),1e-10)
    _,p=run('T',{'x':None,'df':10,'lower':0.975});assert p['asked']=='invert-lower',p;near(p['value'],r('qt(0.975,10)'),1e-10)
    _,p=run('T',{'x':None,'df':10,'two_sided':0.05});assert p['asked']=='invert-two-sided',p;near(p['value'],r('qt(0.975,10)'),1e-10)
    _,p=run('ChiSquare',{'x':None,'df':3,'upper':0.01});assert p['asked']=='invert-upper',p;near(p['value'],r('qchisq(0.99,3)'),1e-9)
    _,p=run('F',{'x':None,'df':6,'df2':8,'upper':0.05});assert p['asked']=='invert-upper',p;near(p['value'],r('qf(0.95,6,8)'),1e-8)
    _,p=run('Q',{'x':None,'df':36,'df2':4,'upper':0.05});assert p['asked']=='invert-upper',p;near(p['value'],r('qtukey(0.95,4,36)'),1e-5)
    _,p=run('NonCentralT',{'x':None,'df':10,'df2':1,'upper':0.1});assert p['asked']=='invert-upper',p;near(p['value'],r('qt(0.9,10,ncp=1)'),1e-6)
    _,p=run('Poisson',{'df':14,'df2':None,'upper':0.025});assert p['asked']=='invert-upper' and 'value' not in p,p
    near(r('ppois(13,%r,lower.tail=FALSE)'%p['df2']),0.025,1e-6);near(p['upper'],0.025,1e-9)
    _,p=run('Poisson',{'df':14,'df2':None,'two_sided':0.025});assert p['asked']=='invert-two-sided',p;near(r('ppois(14,%r)'%p['df2']),0.025,1e-6)
case('invert: the eleven cases of the Windows checks give R\'s quantiles, with the other boxes and "asked" recorded',invert_cases)
def refusals():
    try:session.run('DistributionT',{'T distribution':{'x':None,'df':10}});raise AssertionError('an empty form was accepted')
    except AssertionError as e:
        if 'validation' not in str(e):raise
    try:session.run('DistributionT',{'T distribution':{'x':None,'df':10,'lower':0.9,'upper':0.1}});raise AssertionError('two boxes were accepted')
    except AssertionError as e:
        if 'validation' not in str(e):raise
    try:session.run('DistributionBinomial',{'Binomial distribution':{'x':None,'df':20,'df2':5}});raise AssertionError('a binomial inverse was accepted')
    except AssertionError as e:
        if 'validation' not in str(e):raise
case('refusals: no box, two boxes, and the binomial (no inverse) are asked again',refusals)
session.finish()
if failures:
    for label,error in failures:print('FAIL',label,error[:300])
    sys.exit(1)
print('PASS: the Distributions calculator calculates and inverts as the Windows ctlPDF, records its boxes under the Windows names, and agrees with R')
