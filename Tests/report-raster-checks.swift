import Cocoa
import WebKit

extension ReportExportTests {
    // Only diagnostic probes: they never rescue the original failed PNG assertion.
    // The explicit flag exercises the probes on a healthy host before relying on CI logs.
    @MainActor static func rasterDiagnostics(_ report: Document, markup: String) async {
        let window=report.web.window
        print("Raster host: frame=\(report.web.frame) hidden=\(report.web.isHiddenOrHasHiddenAncestor) windowVisible=\(window?.isVisible ?? false) miniaturized=\(window?.isMiniaturized ?? false) key=\(window?.isKeyWindow ?? false) occlusion=\(window?.occlusionState.rawValue ?? 0)")
        for (command,arguments) in [("/usr/bin/vm_stat",[String]()),("/bin/ps",["-axo","pid,ppid,rss,comm"])] {
            let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:command);process.arguments=arguments
            process.standardOutput=pipe;process.standardError=pipe
            do {
                try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
                let lines=String(decoding:data,as:UTF8.self).split(separator:"\n")
                print(lines.filter{command.hasSuffix("vm_stat") || $0.contains("WebKit") || $0.contains("StatsDirect") || $0.contains("FeedbackCheck")}.joined(separator:"\n"))
            } catch {print("Raster process diagnostic:",error.localizedDescription)}
        }
        do {
            let result:Any=try await withCheckedThrowingContinuation { continuation in
                report.web.callAsyncJavaScript(#"""
                const wait=promise=>{let timer;return Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('probe timed out')),3000);})]).finally(()=>clearTimeout(timer));};
                const pixels=canvas=>{
                  const p=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
                  let ink=0,opaque=0;for(let i=0;i<p.length;i+=4){if(p[i+3])opaque++;if(p[i+3]&&Math.min(p[i],p[i+1],p[i+2])<242)ink++;}
                  const center=(40*canvas.width+100)*4;
                  return {ink,opaque,first:[...p.slice(0,4)],center:[...p.slice(center,center+4)]};
                };
                const simple='<svg xmlns="http://www.w3.org/2000/svg" width="100" height="40"><rect width="100" height="40" fill="#237040"/></svg>';
                const uri=svg=>'data:image/svg+xml;charset=utf-8,'+encodeURIComponent(svg);
                const png='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGO4I2LzHwAFKAIsEAh12wAAAABJRU5ErkJggg==';
                const blob=URL.createObjectURL(new Blob([markup],{type:'image/svg+xml'})),samples=[];
                try {
                  const plain=document.createElement('canvas');plain.width=200;plain.height=80;
                  const context=plain.getContext('2d');context.fillStyle='#dc143c';context.fillRect(0,0,200,80);
                  samples.push({name:'fillRect',...pixels(plain)});
                  for(const [name,src,attached] of [['png',png,false],['simple-svg',uri(simple),false],['svg-data',uri(markup),false],['svg-blob',blob,false],['svg-attached',uri(markup),true]]){
                    for(const frequent of [false,true]){
                      const image=new Image(),sample={name,frequent,attached};
                      try {
                        image.src=src;await wait(image.decode());
                        if(attached){image.style.cssText='position:fixed;left:0;top:0;width:100px;height:40px;opacity:0.01;pointer-events:none';document.body.append(image);image.getBoundingClientRect();await wait(new Promise(requestAnimationFrame));}
                        const canvas=document.createElement('canvas');canvas.width=200;canvas.height=80;
                        const ctx=canvas.getContext('2d',{willReadFrequently:frequent});ctx.fillStyle='white';ctx.fillRect(0,0,200,80);ctx.drawImage(image,0,0,200,80);
                        Object.assign(sample,{complete:image.complete,width:image.naturalWidth,height:image.naturalHeight,...pixels(canvas)});
                      } catch(error){sample.error=String(error);}
                      finally {image.remove();}
                      samples.push(sample);
                    }
                  }
                } finally {URL.revokeObjectURL(blob);}
                return {userAgent:navigator.userAgent,visibility:document.visibilityState,focus:document.hasFocus(),devicePixelRatio,viewport:[innerWidth,innerHeight],samples};
                """#,arguments:["markup":markup],in:nil,in:.page) { continuation.resume(with:$0) }
            }
            let data=try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
            print("Raster probes:",String(decoding:data,as:UTF8.self));fflush(stdout)
            if CommandLine.arguments.contains("--raster-diagnostics") {
                let samples=(result as? [String:Any])?["samples"] as? [[String:Any]] ?? []
                precondition(samples.count==11 && samples.allSatisfy{($0["ink"] as? Int ?? 0)>50},"Healthy-host raster diagnostic probes failed")
            }
        } catch {
            print("Raster probes failed:",error.localizedDescription);fflush(stdout)
            if CommandLine.arguments.contains("--raster-diagnostics") {precondition(false,"Raster diagnostics must execute in their explicit self-check")}
        }
    }
}
