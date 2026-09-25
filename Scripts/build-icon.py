#!/usr/bin/env python3
"""Package the original Windows icon as a macOS ICNS (no redesign)."""
import pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
work = pathlib.Path(sys.argv[1] if len(sys.argv)>1 else root/'.build')/'StatsDirect.iconset'
work.mkdir(parents=True, exist_ok=True)
source = root/'Content/Brand/statsdirect.png'
for size in (16,32,128,256,512):
    for scale in (1,2):
        name=f'icon_{size}x{size}'+('@2x' if scale==2 else '')+'.png'
        subprocess.run(['sips','-z',str(size*scale),str(size*scale),str(source),'--out',str(work/name)],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['iconutil','-c','icns',str(work),'-o',str(work.parent/'StatsDirect.icns')],check=True)
