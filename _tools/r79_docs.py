# -*- coding: utf-8 -*-
"""R79 文档增量：README / CHANGELOG / 6xVERSION / ROADMAP / EVOLOG（数据取自 registry + _r79_facts.json）"""
import os, re, json

R = r'C:\Library'
STAGE = os.path.join(R, '_Staging_Raw', '2026-11-24')
d = json.load(open(os.path.join(R, 'INDEX_REGISTRY.json'), encoding='utf-8'))
F = json.load(open(os.path.join(STAGE, '_r79_facts.json'), encoding='utf-8'))
TOT = d['total_components']
CNT = d['counts']
VER = 'v2.71.0'
PCT = TOT / 10000 * 100
SFT = sum(1 for ln in open(os.path.join(R, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl'), encoding='utf-8') if ln.strip())

# ---- README ----
p = os.path.join(R, 'README.md')
s = open(p, encoding='utf-8').read()
s = re.sub(r'Total%20Components-\d+%20%2F%2010%2C000-blue', 'Total%%20Components-%d%%20%%2F%%2010%%2C000-blue' % TOT, s, count=1)
s = re.sub(r'(> \*\*Total Components: )[\d,]+( / 10,000 \()[\d.]+(%\)\*\*)',
           lambda m: m.group(1) + format(TOT, ',') + m.group(2) + '%.2f' % PCT + m.group(3), s, count=1)
s = re.sub(r'\| \*\*Version: v[\d.]+', '| **Version: ' + VER, s, count=1)
s = re.sub(r'\| \*\*SFT 语料: \d+ 条', '| **SFT 语料: %d 条' % SFT, s, count=1)
if 'v2.71.0（R79' not in s:
    line = ('\n> **v2.71.0（R79 · 2026-11-24）**：%d 件入册（复杂 %d / 简单 %d，5 族模板派生）｜总库 **%s/10,000（%.2f%%）**｜'
            'SFT 语料 **%d** 条｜**L2 闸 %s**｜审校拒收 %d｜开源队列 %d 条 溯源 %s｜产能冲刺模式（复杂件上限 4）。\n'
            % (F['added'], F['complex'], F['simple'], format(TOT, ','), PCT, SFT,
               F['gate_line'], F['rejected'], F['queue'], F['trace']))
    idx = s.find('---', s.find('Total Components'))
    s = (s[:idx] + line + '\n' + s[idx:]) if idx > 0 else (s + line)
open(p, 'w', encoding='utf-8').write(s)
print('README ok', TOT, SFT)

# ---- CHANGELOG ----
p = os.path.join(R, 'CHANGELOG.md')
s = open(p, encoding='utf-8').read()
if '## v2.71.0' not in s:
    block = open(os.path.join(STAGE, '_r79_changelog.md'), encoding='utf-8').read()
    i = s.find('## v2.70.0')
    s = (s[:i] + block + '\n\n' + s[i:]) if i > 0 else (s + '\n\n' + block)
    open(p, 'w', encoding='utf-8').write(s)
print('CHANGELOG ok')

# ---- VERSION.md ----
for cat, desc in F['touch'].items():
    p = os.path.join(R, cat, 'VERSION.md')
    s = open(p, encoding='utf-8').read()
    if 'R79' in s:
        continue
    s = s.rstrip() + ('\n\n## R79 · %s · 2026-11-24\n- 新增 %s，本库累计 **%d** 件。\n'
                      '- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。\n'
                      % (VER, desc, CNT[cat]))
    open(p, 'w', encoding='utf-8').write(s)
print('VERSION ok')

# ---- ROADMAP ----
p = os.path.join(R, 'ROADMAP.md')
s = open(p, encoding='utf-8').read()
if 'R79 构建轮小结' not in s:
    s = s.rstrip() + '\n\n' + open(os.path.join(STAGE, '_r79_roadmap.md'), encoding='utf-8').read()
    open(p, 'w', encoding='utf-8').write(s)
print('ROADMAP ok')

# ---- EVOLOG ----
p = os.path.join(R, 'AGENT_EVOLUTION_LOG.md')
s = open(p, encoding='utf-8').read()
if 'R79 构建轮' not in s:
    s = s.rstrip() + '\n\n' + open(os.path.join(STAGE, '_r79_evolog.md'), encoding='utf-8').read()
    open(p, 'w', encoding='utf-8').write(s)
print('EVOLOG ok  TOT=%d SFT=%d' % (TOT, SFT))
