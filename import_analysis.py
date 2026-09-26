"""Import the Windows Data, Analysis and Graphics trees and resolve offline help."""
from pathlib import Path
import xml.etree.ElementTree as ET, json, re, shutil, hashlib, sys
base=Path(__file__).resolve().parent
source=Path(sys.argv[1]); help_source=Path(sys.argv[2]); menu=source/'StatsDirectUI/Assets/menu.xml'
ns={'m':'http://www.statsdirect.com/schemas/Menu.xsd','s':'http://www.statsdirect.com/schemas/Operation.xsd'}
aliases={e.get('Name'):e.get('Link').replace('/Content/','Help/').replace('\\','/') for e in ET.parse(help_source/'Project/Advanced/STATSDIRECT.flali').getroot()}
ids={int(n):aliases[name] for name,n in re.findall(r'#define\s+(\w+)\s+(\d+)',(help_source/'Project/Advanced/SD3ContextID.h').read_text(encoding='utf-8-sig')) if name in aliases}
ops={}
def convert(node):
    label=node.get('label','').replace('&',''); result={'label':label}
    if label == '-': return {'separator':True}
    if op:=node.get('operation'):
        root=ET.parse(base/'FullEngine/Upstream/StatsDirectUI/Assets/Operations'/f'{op}.xml').getroot()
        help=root.find('s:help',ns); path=ids.get(int(help.get('chm-id','0')),'') if help is not None else ''
        if path and not (base/'Content'/path).is_file():path=''
        title=root.findtext('s:friendly-name',default=op,namespaces=ns)
        ops[op]={'id':op,'title':title,'help':path,'instant':any(x.text==op for x in root.findall('s:suggested-operations/s:suggested-operation',ns))}
        result['operation']=op
    children=node.find('m:sub-items',ns)
    if children is not None:result['children']=[convert(x) for x in children]
    return result
menus=[convert(x) for x in ET.parse(menu).findall('m:sub-items/m:menu-item',ns)]
result={'menu':next(x for x in menus if x['label']=='Analysis'),'menus':menus,'operations':ops,'sourceSHA256':hashlib.sha256(menu.read_bytes()).hexdigest()}
for op in ('LOESS','MethodComparisonRegression'):
    ops[op]['unavailable']='This R-based method is not enabled in the Mac prototype yet. Method help and R → New R Session are available.'
(base/'Content/analysis-menu.json').write_text(json.dumps(result,indent=2)+'\n')
shutil.copy2(menu,base/'Content/windows-menu.xml')
print(len(ops),'menu operations;',sum(bool(x['help']) for x in ops.values()),'offline help links')
