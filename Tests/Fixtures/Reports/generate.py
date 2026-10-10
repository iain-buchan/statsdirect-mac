"""Small original RTF/metafile fixtures; no third-party report data.
WMF and EMF records follow Microsoft's MS-WMF/MS-EMF file layouts.
Regenerate with python3 Tests/Fixtures/Reports/generate.py.
"""
import struct
import zlib
from pathlib import Path
root=Path(__file__).parent
pack=struct.pack

def wrec(function,payload=b''):
    payload+=b'\0'*(len(payload)%2)
    return pack('<IH',3+len(payload)//2,function)+payload
label=b'WMF chart'
wr=[wrec(0x020b,pack('<hh',0,0)),wrec(0x020c,pack('<hh',240,400)),wrec(0x02fa,pack('<HhhI',0,2,0,0x00804020)),wrec(0x012d,pack('<H',0)),wrec(0x0214,pack('<hh',20,40)),wrec(0x0213,pack('<hh',180,40)),wrec(0x0213,pack('<hh',180,350)),wrec(0x0418,pack('<hhhh',110,210,100,200)),wrec(0x0521,pack('<H',len(label))+label+b'\0'*(len(label)%2)+pack('<hh',200,60)),wrec(0)]
# Correct canonical placeable layout.
place=pack('<IHhhhhHI',0x9ac6cdd7,0,0,0,400,240,96,0)
checksum=0
for value in struct.unpack('<10H',place):checksum^=value
wmf=place+pack('<H',checksum)+pack('<HHHIHIH',1,9,0x300,(18+sum(map(len,wr)))//2,1,max(map(len,wr))//2,0)+b''.join(wr)
(root/'chart.wmf').write_bytes(wmf)
(root/'standard-wmf.rtf').write_text('{\\rtf1\\ansi Standard WMF chart. {\\pict\\wmetafile8\\picwgoal6000\\pichgoal3600 '+wmf[22:].hex()+'}}')

def erec(kind,payload=b''):
    payload+=b'\0'*((-len(payload))%4)
    return pack('<II',kind,len(payload)+8)+payload
label='EMF chart'.encode('utf-16le')
# Explicit fields: bounds, graphics mode/scales, reference, length/offset/options, clip rect, dx offset.
text=pack('<4iIff2i3I4iI',0,0,400,240,1,1.0,1.0,60,200,len(label)//2,76,0,0,0,0,0,0)+label
logfont=pack('<5i8B',-20,0,0,0,400,0,0,0,1,0,0,0,0x22)+'Calibri'.encode('utf-16le').ljust(64,b'\0')
er=[erec(18,pack('<I',1)),erec(37,pack('<I',0x80000007)),erec(27,pack('<ii',40,20)),erec(54,pack('<ii',40,180)),erec(54,pack('<ii',350,180)),erec(42,pack('<4i',200,100,210,110)),erec(82,pack('<I',1)+logfont+b'\0'*228),erec(37,pack('<I',1)),erec(84,text),erec(14,pack('<III',0,0,20))]
header=pack('<II4i4iIIIIHHIII4i',1,88,0,0,400,240,0,0,10583,6350,0x464d4520,0x10000,88+sum(map(len,er)),len(er)+1,2,0,0,0,0,400,240,106,64)
emf=header+b''.join(er)
(root/'chart.emf').write_bytes(emf)
base=r'''{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0 Arial;}}\f0\fs24
\b Legacy statistical report\b0\par
\i Paired measurements\i0  \ul Reviewed\ul0\par
Greek: \u945? = 0.05; \u967?\super 2\nosupersub ; 95% confidence interval.\par
\trowd\trgaph108\cellx2500\cellx5000\intbl Measurement\cell Value\cell\row
\trowd\cellx2500\cellx5000\intbl Mean difference\cell 12.5\cell\row\pard\par
{\v !!help!-> 123 <-!help!! }Visible after hidden metadata.\par
\v Hidden inline text\v0 Visible again.\par
{\field{\*\fldinst INCLUDEPICTURE "https://example.invalid/do-not-fetch.png"}{\fldrslt External field text only.}}\par
'''
pict=lambda fmt,data:'{\\pict\\'+fmt+'\\picwgoal6000\\pichgoal3600 '+data.hex()+'}'
rtf=base+'{\\*\\shppict'+pict('emfblip',emf)+'}{\\nonshppict'+pict('wmetafile8',wmf)+'}\\par\n'+pict('wmetafile8',wmf)+'\\par\nEnd of legacy report.}'
(root/'legacy-charts.rtf').write_text(rtf)
(root/'binary-picture.rtf').write_bytes(b'{\\rtf1\\ansi Before '+b'{\\pict\\emfblip\\bin'+str(len(emf)).encode()+b' '+emf+b'} After}')
(root/'damaged-picture.rtf').write_text(r'{\rtf1\ansi Keep this text. {\pict\emfblip 00010203} Still readable.}')

def chunk(kind,data):
    return pack('>I',len(data))+kind+data+pack('>I',zlib.crc32(kind+data))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',pack('>IIBBBBB',2,2,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\0\xff\0\0\0\xff\0\0\0\0\xff\xff\xff\xff'))+chunk(b'IEND',b'')
(root/'raster-picture.rtf').write_text('{\\rtf1\\ansi Raster picture. '+pict('pngblip',png)+'}')

# A short header row spanning the physical grid used by subsequent data rows.
# Word often repeats a row definition immediately before its terminating row.
layout=r'{\rtf1\ansi\deff0{\fonttbl{\f0 Calibri;}}\f0\fs20\b Layout checks\b0\par Body at the ordinary report size.\par\par '
def row(edges,values):
    definition=r'\trowd\trgaph108'+''.join(r'\cellx'+str(x) for x in edges)
    return definition+r'\intbl '+r'\cell '.join(values)+r'\cell '+definition+r'\row '
layout+=row([1200,6000],[r'\ul Study\ul0',r'\ul Estimate and confidence limits\ul0'])
layout+=row([1200,2400,4200,6000],['Trial A','12.5','10.25','14.75'])
layout+=row([1200,2400,4200,6000],['Trial B','-2.5','-3.25','-1.75'])
layout+=r'\pard\par \i Interpretation stays italic.\i0\par}'
(root/'layout.rtf').write_text(layout)
