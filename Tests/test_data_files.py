from r_runtime import rscript as find_rscript
"""Real native file IO -> actual grid model -> native save -> base-R/CSV reader."""
import csv,io,json,os,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
driver=Path(sys.argv[1]).resolve();node=Path(sys.argv[2]).resolve()
r=find_rscript();script=ROOT/'Content/R/data-files.R'
def run(*args,ok=True):
 p=subprocess.run([str(a) for a in args],capture_output=True,text=True)
 if ok: assert p.returncode==0,p.stderr
 return p
with tempfile.TemporaryDirectory(prefix='statsdirect-data-tests-') as folder:
 d=Path(folder);source='id,note,value\r\n0012,"café, ""quoted""",0\r\n0045,"two\nlines",-0.125\r\n,,\r\n'
 for name,data in [('utf8',source.encode()),('bom',b'\xef\xbb\xbf'+source.encode()),('utf16le',b'\xff\xfe'+source.encode('utf-16-le')),('utf16be',b'\xfe\xff'+source.encode('utf-16-be')),('windows',source.encode('cp1252'))]:
  (d/'in.csv').write_bytes(data)
  run(driver,'read-csv',d/'in.csv',d/'decoded.txt')
  run(node,ROOT/'Tests/data-file-model.mjs','csv',d/'decoded.txt',d/'grid.csv')
  run(driver,'write-csv',d/'grid.csv',d/'saved.csv')
  with (d/'saved.csv').open(encoding='utf-8-sig',newline='') as f:actual=list(csv.reader(f))
  assert actual==list(csv.reader(io.StringIO(source,newline=''))),(name,actual)
 print('PASS: CSV native read/grid/write for UTF-8, BOM, both UTF-16 byte orders and Windows-1252')
 fixture=d/'fixture.R'
 fixture.write_text('''
args <- commandArgs(TRUE);setwd(args[1])
patients <- data.frame(id=c("0012","0045","0078"), age=c(21L,NA_integer_,45L), score=c(1.2345678901234567,NaN,Inf), note=c("comma, quote \\\" and café", "two\\nlines", ""), group=ordered(c("control","treated",NA),levels=c("control","treated","unused")), flag=c(TRUE,FALSE,NA), date=as.Date(c("2026-09-01",NA,"2026-09-03")), time=as.POSIXct(c("2026-09-01 12:30:00.123456",NA,"2026-09-03 13:00:00"),tz="Europe/London"), missing_text=c("",NA,"NA"), stringsAsFactors=FALSE)
patients$open_end <- as.Date(c(1, Inf, -Inf), origin="1970-01-01"); patients$stamp_end <- as.POSIXct(c(0, Inf, 86400.5), origin="1970-01-01", tz="UTC")
patients$combo <- c("\\n\u0301x", "%\u0301", "\u0600%25"); patients$bom <- c("\ufefffirst", "x", "\ufeffz")
patients$naf <- addNA(factor(c("a", NA, "b"))); names(patients)[names(patients) == "note"] <- "no\rte"
sub_frame <- data.frame(x=1:4)[c(4,2),,drop=FALSE]; char_rows <- data.frame(x=1:2); row.names(char_rows) <- c("1","2")
matcol <- data.frame(a=1:3); matcol$m <- matrix(1:6, 3, 2)
row.names(patients)<-c("p1","p2","p3")
observations<-matrix(1:6,3,2,dimnames=list(c("a","b","c"),c("before","after")))
ignored<-function()1
empty<-data.frame(x=integer(),y=character())
all_missing<-data.frame(x=c(NA_real_,NA_real_),s=c("",NA_character_))
save(patients,observations,empty,all_missing,ignored,sub_frame,char_rows,matcol,file="source.RData")
saveRDS(patients,"source.rds")
''')
 run(r,'--vanilla',fixture,d)
 snapshots=d/'snapshots'
 run(driver,'read-r',d/'source.RData',script,d/'book.json',snapshots)
 book=json.loads((d/'book.json').read_text());assert len(book['sheets'])==6 and len(book['warnings'])==2 and any('matcol' in w for w in book['warnings']),book['warnings']
 assert all(s['cells']==[] and Path(s['snapshot']).is_file() for s in book['sheets']) and book['sheets'][0]['rRowNames']==['p1','p2','p3'] and book['sheets'][0]['rColumns'][4]['levels']==['control','treated','unused']
 for mode,target in [('r','copy'),('r-edit','edited')]:
  run(node,ROOT/'Tests/data-file-model.mjs',mode,d/'book.json',d/'tables.sdcol',d/'tables.json')
  run(driver,'write-r',d/'tables.sdcol',d/'tables.json',d/(target+'.RData'),'rdata',script)
 run(driver,'read-r',d/'source.rds',script,d/'single.json',snapshots)
 run(node,ROOT/'Tests/data-file-model.mjs','r',d/'single.json',d/'one.sdcol',d/'one.json')
 run(driver,'write-r',d/'one.sdcol',d/'one.json',d/'copy.rds','rds',script)
 verify=d/'verify.R';verify.write_text('''
a<-commandArgs(TRUE);setwd(a[1]);original<-new.env();load("source.RData",original)
copy<-new.env();load("copy.RData",copy)
stopifnot(identical(original$patients,copy$patients),identical(original$observations,copy$observations))
stopifnot(identical(readRDS("source.rds"),readRDS("copy.rds")),identical(original$empty,copy$empty),identical(original$all_missing,copy$all_missing))
stopifnot(identical(original$sub_frame,copy$sub_frame),identical(original$char_rows,copy$char_rows),is.integer(attr(copy$sub_frame,"row.names")))
edited<-new.env();load("edited.RData",edited)
stopifnot(edited$patients$age[1]==22L,as.character(edited$patients$group[1])=="new group",is.ordered(edited$patients$group),identical(levels(edited$patients$group),c("control","treated","unused","new group")))
stopifnot(identical(edited$patients$time,original$patients$time),identical(edited$patients$missing_text,original$patients$missing_text))
''');run(r,'--vanilla',verify,d)
 print('PASS: RData and RDS round trips preserve base-R table/matrix types, factors (including an NA level), logicals, dates and timestamps (including open-ended Inf), integer and character row names, NA, NaN, Inf, byte-order marks, combining marks beside escapes and a carriage return in a column name')
 print('PASS: grid edits update an integer column and ordered factor without altering untouched values')
 before=(d/'copy.RData').read_bytes()
 run(node,ROOT/'Tests/data-file-model.mjs','r-invalid',d/'book.json',d/'bad.sdcol',d/'bad.json')
 bad=run(driver,'write-r',d/'bad.sdcol',d/'bad.json',d/'copy.RData','rdata',script,ok=False);assert bad.returncode!=0 and 'Invalid integer value in patients / age, row 1' in bad.stderr,bad.stderr
 assert (d/'copy.RData').read_bytes()==before
 run(node,ROOT/'Tests/data-file-model.mjs','r-nul',d/'book.json',d/'nul.sdcol',d/'nul.json')
 nul=run(driver,'write-r',d/'nul.sdcol',d/'nul.json',d/'copy.RData','rdata',script,ok=False);assert nul.returncode!=0 and 'NUL' in nul.stderr,nul.stderr
 assert (d/'copy.RData').read_bytes()==before
 (d/'bad.rds').write_text('corrupt input')
 assert run(driver,'read-r',d/'bad.rds',script,d/'bad-read.json',snapshots,ok=False).returncode!=0
 assert not [f for f in snapshots.iterdir() if 'bad' in f.name]
 print('PASS: invalid R column edits leave an existing destination unchanged; corrupt input fails explicitly')
 # Numbers formatted natively for R match what the grid shows (JavaScript's String(number)).
 samples=['0','1','-1','100','0.1','0.5','1.5','123456.5','1e21','1e+21','1e-7','1e-6','0.000001','123456789012345680000','1234567890123456789012','5e-324','1.7976931348623157e308','-0.0','2.5e-5','1e16','12345678.9','0.30000000000000004','-1.25e-8','1e100','1.0000000000000002']
 (d/'numbers.txt').write_text('\n'.join(samples))
 run(driver,'format-numbers',d/'numbers.txt',d/'formatted.txt')
 expected=subprocess.check_output([str(node),'-e',"process.stdout.write(require('fs').readFileSync(process.argv[1],'utf8').split('\\n').map(Number).map(String).join('\\n'))",str(d/'numbers.txt')],text=True)
 assert (d/'formatted.txt').read_text()==expected,((d/'formatted.txt').read_text(),expected)
 print('PASS: native number formatting matches JavaScript for integers, fractions, exponents, extremes and negative zero')
 if os.environ.get('STATSDIRECT_SCALE')=='1':
  big=d/'big.R';big.write_text('''
args <- commandArgs(TRUE);setwd(args[1]);set.seed(1);n <- 1048575L
frame <- data.frame(id=seq_len(n), value=rnorm(n), group=factor(sample(c("a","b","c"), n, TRUE)), when=as.Date("2020-01-01")+seq_len(n) %% 3000, stringsAsFactors=FALSE)
frame$value[c(10L, 20L)] <- NA; frame$label <- ifelse(seq_len(n) %% 1000L == 0L, NA_character_, paste0("row ", seq_len(n)))
saveRDS(frame, "big.rds")
''');run(r,'--vanilla',big,d)
  t=time.time();run(driver,'read-r',d/'big.rds',script,d/'big.json',snapshots);read_time=time.time()-t
  bigbook=json.loads((d/'big.json').read_text());assert bigbook['sheets'][0]['rows']==1048576 and bigbook['sheets'][0]['columns']==5
  t=time.time();run(node,ROOT/'Tests/data-file-model.mjs','r',d/'big.json',d/'big.sdcol',d/'big-tables.json');model_time=time.time()-t
  t=time.time();run(driver,'write-r',d/'big.sdcol',d/'big-tables.json',d/'big-copy.rds','rds',script);write_time=time.time()-t
  check=d/'check.R';check.write_text('a<-commandArgs(TRUE);setwd(a[1]);stopifnot(identical(readRDS("big.rds"),readRDS("big-copy.rds")))');run(r,'--vanilla',check,d)
  print(f'PASS: a 1,048,575-row x 5-column data frame round-trips identically through R, the grid model and R (read {read_time:.1f}s, model {model_time:.1f}s, write {write_time:.1f}s)')
