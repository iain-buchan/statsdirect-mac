"""Real native file IO -> actual grid model -> native save -> base-R/CSV reader."""
import csv,io,json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
driver=Path(sys.argv[1]).resolve();node=Path(sys.argv[2]).resolve()
r='/Library/Frameworks/R.framework/Resources/bin/Rscript';script=ROOT/'Content/R/data-files.R'
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
row.names(patients)<-c("p1","p2","p3")
observations<-matrix(1:6,3,2,dimnames=list(c("a","b","c"),c("before","after")))
ignored<-function()1
empty<-data.frame(x=integer(),y=character())
all_missing<-data.frame(x=c(NA_real_,NA_real_),s=c("",NA_character_))
save(patients,observations,empty,all_missing,ignored,file="source.RData")
saveRDS(patients,"source.rds")
''')
 run(r,'--vanilla',fixture,d)
 run(driver,'read-r',d/'source.RData',script,d/'book.json')
 book=json.loads((d/'book.json').read_text());assert len(book['sheets'])==4 and len(book['warnings'])==1
 for mode,target in [('r','copy'),('r-edit','edited')]:
  run(node,ROOT/'Tests/data-file-model.mjs',mode,d/'book.json',d/'tables.json')
  run(driver,'write-r',d/'tables.json',d/(target+'.RData'),'rdata',script)
 run(driver,'read-r',d/'source.rds',script,d/'single.json')
 run(node,ROOT/'Tests/data-file-model.mjs','r',d/'single.json',d/'one.json')
 run(driver,'write-r',d/'one.json',d/'copy.rds','rds',script)
 verify=d/'verify.R';verify.write_text('''
a<-commandArgs(TRUE);setwd(a[1]);original<-new.env();load("source.RData",original)
copy<-new.env();load("copy.RData",copy)
stopifnot(identical(original$patients,copy$patients),identical(original$observations,copy$observations))
stopifnot(identical(readRDS("source.rds"),readRDS("copy.rds")),identical(original$empty,copy$empty),identical(original$all_missing,copy$all_missing))
edited<-new.env();load("edited.RData",edited)
stopifnot(edited$patients$age[1]==22L,as.character(edited$patients$group[1])=="new group",is.ordered(edited$patients$group),identical(levels(edited$patients$group),c("control","treated","unused","new group")))
stopifnot(identical(edited$patients$time,original$patients$time),identical(edited$patients$missing_text,original$patients$missing_text))
''');run(r,'--vanilla',verify,d)
 print('PASS: RData and RDS round trips preserve base-R table/matrix types, factors, logicals, dates, timestamps, row names, NA, NaN and Inf')
 print('PASS: grid edits update an integer column and ordered factor without altering untouched values')
 before=(d/'copy.RData').read_bytes()
 run(node,ROOT/'Tests/data-file-model.mjs','r-invalid',d/'book.json',d/'bad.json')
 assert run(driver,'write-r',d/'bad.json',d/'copy.RData','rdata',script,ok=False).returncode!=0
 assert (d/'copy.RData').read_bytes()==before
 (d/'bad.rds').write_text('corrupt input')
 assert run(driver,'read-r',d/'bad.rds',script,d/'bad-read.json',ok=False).returncode!=0
 print('PASS: invalid R column edits leave an existing destination unchanged; corrupt input fails explicitly')
