from pathlib import Path
import shutil,re,html,sys
base=Path(__file__).resolve().parent
if len(sys.argv) != 2: raise SystemExit('Usage: python3 import_help.py /path/to/statisticalhelp')
repository=Path(sys.argv[1]).resolve()
content=base/'Content'; content.mkdir(exist_ok=True)
src=repository/'Docs'
if not (src/'basic_descriptive_statistics/univariate_summary.htm').is_file(): raise SystemExit('Expected generated help in repository/Docs')
if (content/'Help').exists(): shutil.rmtree(content/'Help')
shutil.copytree(src, content/'Help', ignore=shutil.ignore_patterns('*.log.zip'))
shutil.copy(repository/'LICENSE',base/'STATISTICALHELP-LICENSE.txt')
source=(src/'basic_descriptive_statistics/univariate_summary.htm').read_text()
start=source.index('<table',source.index('Results from StatsDirect'))
end=source.index('</table>',start)+len('</table>')
table=source[start:end]
css='''body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#203040;background:#fff;margin:0;padding:40px 56px;line-height:1.55;max-width:960px}h1{font-size:30px;letter-spacing:-.6px;margin:12px 0}h2{font-size:20px;margin-top:32px}a{color:#08675f}p{max-width:760px}.eyebrow{font-size:12px;font-weight:650;letter-spacing:1.5px;color:#08675f;text-transform:uppercase}.note{border-left:3px solid #3c9186;padding:12px 18px;background:#eef6f4;font-size:14px}table{border-collapse:collapse;width:100%;font-size:14px;font-variant-numeric:tabular-nums}td,th{padding:8px 14px;border-bottom:1px solid #e1e7e9;text-align:left}tr:first-child{font-weight:600;background:#edf3f5}td:last-child{text-align:right}svg{max-width:100%;height:auto}.ci{color:blue}.grandtotal,.model{color:#000080}.pval{color:#008000}.score{color:#008080}.subtotal{color:#800000}.warn{color:red}@media print{body{padding:0;max-width:none}tr,svg{break-inside:avoid}a{color:inherit}}'''
(content/'viewer.css').write_text(css)
(content/'report.html').write_text('''<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Michelson · Univariate summary</title><link rel="stylesheet" href="viewer.css"></head><body><div class="eyebrow">StatsDirect / Report viewer prototype</div><h1>Univariate summary</h1><p>Michelson · Speed of light measurements</p><p class="note">Saved example, not a live calculation. The results table below is copied unchanged from the StatsDirect help example. This prototype tests report display; the calculation engine is not connected.</p><p><a id="help-link" href="Help/basic_descriptive_statistics/univariate_summary.htm">Read the original method and worked example →</a></p><h2>Descriptive statistics</h2>'''+table+'''<h2>SVG rendering check</h2><p>Illustration of the documented mean and its 95% confidence limits; this graphic is a viewer fixture, not engine-generated output.</p><svg xmlns="http://www.w3.org/2000/svg" width="800" height="150" viewBox="0 0 800 150" role="img" aria-label="Mean 299.8524, lower confidence limit 299.836722593166, upper confidence limit 299.868077406834"><rect width="800" height="150" rx="10" fill="#f3f7f8"/><path d="M110 64H690M110 48V80M690 48V80" stroke="#27786f" stroke-width="3"/><circle cx="400" cy="64" r="7" fill="#164f49"/><g font-family="Arial" font-size="14" fill="#203040" text-anchor="middle"><text x="110" y="112">299.836722593166</text><text x="400" y="35">Mean 299.8524</text><text x="690" y="112">299.868077406834</text></g></svg></body></html>''')
items=[]
for file in sorted(src.rglob('*.htm')):
    if len(file.relative_to(src).parts)!=2 or file.relative_to(src).parts[0] in ['Skins','Data']: continue
    text=file.read_text(errors='replace')
    match=re.search(r'<title>(.*?)</title>',text,re.S|re.I)
    title=html.unescape(re.sub('<[^>]+>','',match[1])).strip() if match else file.stem.replace('_',' ')
    relative=file.relative_to(src)
    items.append((relative.parts[0].replace('_',' ').title(),title,relative.as_posix()))
body=''; group=None
for category,title,path in items:
    if category!=group:
        if group: body+='</ul></section>'
        body+=f'<section><h2>{html.escape(category)}</h2><ul>'; group=category
    body+=f'<li><a href="Help/{html.escape(path)}">{html.escape(title)}</a></li>'
body+='</ul></section>'
(content/'help-index.html').write_text('''<!doctype html><html lang="en"><head><meta charset="utf-8"><title>StatsDirect help library</title><link rel="stylesheet" href="viewer.css"><style>input{font:inherit;width:90%;padding:12px;border:1px solid #bac8cf;border-radius:8px}li{margin:6px 0}ul{list-style:none;padding:0}</style></head><body><div class="eyebrow">StatsDirect / Help</div><h1>Help library</h1><p>Original StatsDirect help pages, available offline. Filter by topic title or category.</p><input aria-label="Filter help topics" placeholder="Find a topic…" type="search" oninput="filterTopics(this.value)">'''+body+'''<script>function filterTopics(value){const q=value.toLowerCase();document.querySelectorAll('section').forEach(s=>{const category=s.querySelector('h2').textContent.toLowerCase();s.querySelectorAll('li').forEach(li=>li.hidden=!(category+' '+li.textContent.toLowerCase()).includes(q));s.hidden=![...s.querySelectorAll('li')].some(li=>!li.hidden)})}</script></body></html>''')
print(f'Copied original help collection; indexed {len(items)} topics; extracted original results table.')
