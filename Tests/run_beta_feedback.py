"""Native macOS integration checks. Add --live to test the signed-in ChatGPT account with bundled example data."""
from pathlib import Path
import argparse,subprocess,plistlib,uuid
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app',type=Path,default=root/'StatsDirect Viewer.app',help='Use resources and engine from this app, including an extracted release ZIP')
parser.add_argument('--live',action='store_true')
parser.add_argument('--stay-open',action='store_true')
parser.add_argument('--groups-only',action='store_true',help='Run only the native group-selection checks')
args=parser.parse_args()
source_app=args.app.resolve()
assert (source_app/'Contents/MacOS/StatsDirectViewer').is_file(), source_app
out=root/'.build/feedback-native';out.mkdir(exist_ok=True)
subprocess.run([str(root/'Grid/node_modules/esbuild/bin/esbuild'),'Tests/feedback-renderer.mjs','--bundle','--format=iife','--outfile=.build/feedback-renderer.js'],cwd=root,check=True)
(out/'Viewer.swift').write_text((root/'Sources/main.swift').read_text().split('MainActor.assumeIsolated {')[0])
helpers=[]
for name in ['learning-workspace','provider-learning','report-export','group-identifier']:
 p=out/(name+'.swift');p.write_text((root/('Tests/'+name+'-driver.swift')).read_text().replace('@main struct','struct'));helpers.append(str(p))
app=out/'StatsDirect Feedback Check.app';(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
info=plistlib.loads((root/'Info.plist').read_bytes());info['CFBundleIdentifier']='com.statsdirect.feedback.'+uuid.uuid4().hex;info['CFBundleExecutable']='FeedbackCheck';(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
for f in ['Resources','Frameworks']:
 p=app/'Contents'/f
 if p.is_symlink():p.unlink()
 p.symlink_to((source_app/'Contents'/f).resolve())
cmd=['swiftc','-parse-as-library','-target','arm64-apple-macosx14.0','-module-cache-path',str(root/'.build/swift-cache')]+[str(x) for x in (root/'Sources').glob('*.swift') if x.name!='main.swift']+[str(out/'Viewer.swift'),str(root/'Tests/beta-feedback-driver.swift')]+helpers+['-o',str(app/'Contents/MacOS/FeedbackCheck'),'-framework','Cocoa','-framework','WebKit','-framework','PDFKit','-framework','Security']
subprocess.run(cmd,cwd=root,check=True)
print('Testing app resources and engine:',source_app,flush=True)
subprocess.run([str(app/'Contents/MacOS/FeedbackCheck'),str(root/'.build/beta-feedback-exports')]+(['--live'] if args.live else [])+(['--groups-only'] if args.groups_only else [])+(['--stay-open'] if args.stay_open else []),cwd=root,check=True)
