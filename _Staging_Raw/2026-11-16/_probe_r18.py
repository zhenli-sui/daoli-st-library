import json, re

d = json.load(open('INDEX_REGISTRY.json', encoding='utf-8'))
comps = sorted(d['components'], key=lambda c: c.get('registered_at', ''))
for c in comps[-22:]:
    p = c['file_path'].replace(chr(92), '/')
    try:
        t = open(p, encoding='utf-8', errors='ignore').read()
    except Exception:
        print(c['name'], 'MISSING', p)
        continue
    codes = sorted(set(re.findall(r'16#0001_([0-9A-Fa-f]{4})', t)))
    print(c['registered_at'][:16], c['name'], c['category'], c['type'], codes)
