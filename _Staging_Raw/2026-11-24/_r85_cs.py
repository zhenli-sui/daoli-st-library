# -*- coding: utf-8 -*-
"""R85 定向 code search：五族垂直工艺 + 4 复杂件（语法 token 法，R83/R84 经验）"""
import json, sys, time, urllib.request, urllib.parse, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Accept": "application/vnd.github.text-match+json",
      "Authorization": "Bearer " + TK}

Q = [
 ('A', '"FUNCTION_BLOCK" quench'),
 ('A', '"FUNCTION_BLOCK" carburizing'),
 ('A', '"FUNCTION_BLOCK" austenitizing'),
 ('B', '"FUNCTION_BLOCK" anodizing'),
 ('B', '"FUNCTION_BLOCK" extrusion press'),
 ('B', '"FUNCTION_BLOCK" billet'),
 ('C', '"FUNCTION_BLOCK" die casting'),
 ('C', '"FUNCTION_BLOCK" diecast'),
 ('C', '"FUNCTION_BLOCK" shot velocity'),
 ('D', '"FUNCTION_BLOCK" sintering'),
 ('D', '"FUNCTION_BLOCK" powder metallurgy'),
 ('D', '"FUNCTION_BLOCK" dew point furnace'),
 ('E', '"FUNCTION_BLOCK" brewhouse'),
 ('E', '"FUNCTION_BLOCK" mash tun'),
 ('E', '"FUNCTION_BLOCK" crystallizer'),
 ('E', '"FUNCTION_BLOCK" sugar boiling'),
 ('X', '"FUNCTION_BLOCK" case depth'),
 ('X', '"FUNCTION_BLOCK" supersaturation'),
]

out = []
for fam, q in Q:
    url = "https://api.github.com/search/code?q=%s&per_page=20" % urllib.parse.quote(q)
    rec = {'fam': fam, 'q': q, 'hits': [], 'total': 0, 'err': None}
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40)
        d = json.loads(r.read().decode('utf-8'))
        rec['total'] = d.get('total_count', 0)
        for it in d.get('items', [])[:20]:
            rec['hits'].append({'repo': it['repository']['full_name'],
                                'path': it['path'],
                                'url': it['html_url']})
    except Exception as e:
        rec['err'] = '%s %s' % (type(e).__name__, str(e)[:160])
    out.append(rec)
    print('[%s] %-42s total=%-4s items=%-3s %s' % (fam, q, rec['total'], len(rec['hits']), rec['err'] or ''))
    time.sleep(6.5)
json.dump(out, open(r'C:\Library\_Staging_Raw\2026-11-24\_r85_cs.json', 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print('DONE')
