"""R84 文档增量：README 徽章 / CHANGELOG / ROADMAP / EVOLOG / VERSION。全部追加式，不整篇重写。"""
import json, os, re, datetime

LIB = r'C:\Library'
STAGE = os.path.join(LIB, '_Staging_Raw', '2026-11-24')
co = json.load(open(os.path.join(STAGE, '_r84_closeout.json'), encoding='utf-8'))
st = json.load(open(os.path.join(STAGE, '_r84_stats.json'), encoding='utf-8'))
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
reg = json.load(open(REG, encoding='utf-8'))
TOTAL = co['registry']
DAY = st['today_total']
VER = co['version']

# 1) README 徽章
rp = os.path.join(LIB, 'README.md')
t = open(rp, encoding='utf-8').read()
orig = t
t = re.sub(r'Total%20Components-\d+', 'Total%20Components-' + str(TOTAL), t)
t = re.sub(r'Total Components: [\d,]+', 'Total Components: %s' % format(TOTAL, ','), t)
if 'SFT' in t:
    t = re.sub(r'SFT-%d+' % co['jsonl'], 'SFT-%d' % co['jsonl'], t)
    t = re.sub(r'SFT [\d,]+', 'SFT %s' % format(co['jsonl'], ','), t)
t = re.sub(r'v2\.\d+\.\d+', VER, t)
open(rp, 'w', encoding='utf-8').write(t)
print('README badge:', 'changed' if t != orig else 'no-change', '| total', TOTAL, '| sft', co['jsonl'])

# 2) CHANGELOG 追加
cp = os.path.join(LIB, 'CHANGELOG.md')
entry = """
## %s — 2026-11-24（第 84 轮 · 冲刺模式 · 五族垂直）

### Added（%d 件入册：复杂 %d / 简单 %d）
- **汽车零部件机加工族（DL_Device 8）**：%s
- **制药固体制剂族（DL_Process 8）**：%s
- **化工间歇反应釜族（DL_Process 7）**：%s
- **水泥窑炉煅烧族（DL_Device 7）**：%s
- **造纸纸浆族（DL_Process 7）**：%s
- **复杂件（C4~C5）4**：%s

### Changed
- `INDEX_REGISTRY.json` 总量 → **%s**（v%s）；`total_components` 字段修正（R82~R83 遗留 1,570 陈旧值）。
- SFT 语料 → **%s** 条（+%d）。

### Fixed
- 修复件 **0**（非当日首轮，修复配额归零，铁律一）。

### Rejected
%s
""" % (VER, co['registered'], st['complex_n'], st['simple_n'],
       '、'.join(st['fam']['A']), '、'.join(st['fam']['B']), '、'.join(st['fam']['C']),
       '、'.join(st['fam']['D']), '、'.join(st['fam']['E']), '、'.join(st['fam']['X']),
       format(TOTAL, ','), VER[1:], format(co['jsonl'], ','), co['registered'] - st['complex_n'] - st['simple_n'] + st['simple_n'] - (co['registered'] - st['complex_n']),
       st['rejected_md'])
open(cp, 'a', encoding='utf-8').write(entry)
print('CHANGELOG appended')

# 3) ROADMAP 追加
rop = os.path.join(LIB, 'ROADMAP.md')
seg = """
## R84 构建轮小结（2026-11-24 傍晚轮 · 冲刺模式 · 五个新垂直族）

> **R84 小结**：**%d 件入册**（复杂 %d / 简单 %d），总库 %s→**%s**（%.1f%%），%s，SFT %s→**%s**。五族垂直：汽车零部件机加工 8 / 制药固体制剂 8 / 化工间歇反应釜 7 / 水泥窑炉煅烧 7 / 造纸纸浆 7 + 复杂 4（刀具磨损刀补闭环、放热失控五级联锁、压片片重自动控制、流浆箱喷射比闭环）。**L2 闸席原生裁决：%d PASS / %d FAIL / %d EXEMPT，通过率 %.1f%%**。审校：%d PASS / %d 存疑 / %d 拒收。修复件 0（非当日首轮，配额归零）。今日 **%d/300（%.1f%%）**。墙钟 %s′。
> **R85 待办（P0）**：%s

""" % (co['registered'], st['complex_n'], st['simple_n'], format(st['prev_total'], ','), format(TOTAL, ','),
       TOTAL / 100.0, VER, format(st['prev_jsonl'], ','), format(co['jsonl'], ','),
       st['pass'], st['fail'], st['exempt'], st['pass_rate'],
       st['qa_pass'], st['qa_doubt'], st['qa_reject'],
       DAY, DAY / 3.0, st['wall_min'], st['next_p0'])
open(rop, 'a', encoding='utf-8').write(seg)
print('ROADMAP appended')

# 4) EVOLOG 追加
ep = os.path.join(LIB, 'AGENT_EVOLUTION_LOG.md')
evo = """
## R84（2026-11-24 傍晚）— 五席进化 %d 条，游标 R%d → R%d

| 席位 | 新增规则 | 要点 |
|---|---|---|
| DIRECTOR | %d | %s |
| PLC_EXPERT | %d | %s |
| OSS_HUNTER | %d | %s |
| COMPILE_VERIFIER | %d | %s |
| QA_DEDUP | %d | %s |

**本轮结构性问题**：%s

""" % (st['evo_n'], st['evo_from'] - 1, st['evo_to'],
       st['evo']['dir_n'], st['evo']['dir'], st['evo']['plc_n'], st['evo']['plc'],
       st['evo']['oss_n'], st['evo']['oss'], st['evo']['cv_n'], st['evo']['cv'],
       st['evo']['qa_n'], st['evo']['qa'], st['evo']['issue'])
open(ep, 'a', encoding='utf-8').write(evo)
print('EVOLOG appended')

# 5) VERSION 文件
for sub in ('DL_Device', 'DL_Process'):
    vp = os.path.join(LIB, sub, 'VERSION')
    if os.path.exists(vp):
        old = open(vp, encoding='utf-8').read().strip().splitlines()
        new = old + ['%s  2026-11-24  R84  %s  %d 件' % (VER, sub, reg['counts'].get(sub, 0))]
        open(vp, 'w', encoding='utf-8').write('\n'.join(new) + '\n')
        print('VERSION', sub, '->', VER, reg['counts'].get(sub))
    else:
        open(vp, 'w', encoding='utf-8').write('%s  2026-11-24  R84  %d 件\n' % (VER, reg['counts'].get(sub, 0)))
        print('VERSION', sub, 'created')
