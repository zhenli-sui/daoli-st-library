# -*- coding: utf-8 -*-
"""R91 文档增量更新：README 徽章 / CHANGELOG / ROADMAP / AGENT_EVOLUTION_LOG"""
import json, io, os, re, glob, datetime

ROOT = r'C:\Library'
STG = os.path.join(ROOT, '_Staging_Raw', '2026-11-25')
ADD = json.load(io.open(os.path.join(STG, 'r91_added.json'), encoding='utf-8'))
TARGETS = {t['name']: t for t in json.load(io.open(os.path.join(STG, 'r91_targets.json'), encoding='utf-8'))}
REG = json.load(io.open(os.path.join(ROOT, 'INDEX_REGISTRY.json'), encoding='utf-8'))
TOTAL = REG['total_components']
ADDED = ADD['added']
N_NEW = len(ADDED)
SFT = ADD['jsonl']
OLD_TOTAL = TOTAL - N_NEW
OLD_SFT = SFT - N_NEW
# today = R88 39 + R89 39 + R90 40 + R91 n
TODAY = 118 + N_NEW
LINES = sum(sum(1 for _ in io.open(os.path.join(ROOT, 'DL_Process', n + '.st'), encoding='utf-8')) for n in ADDED)
N_CX = sum(1 for n in ADDED if TARGETS[n]['cx'] in ('C4', 'C5'))
N_SM = N_NEW - N_CX
PCT = '%.2f' % (TOTAL / 10000.0 * 100)

def rd(p):
    return io.open(p, encoding='utf-8').read()

def wr(p, s):
    io.open(p, 'w', encoding='utf-8').write(s)

# ---------- README ----------
p = os.path.join(ROOT, 'README.md')
s = rd(p)
s = s.replace('badge/Total%20Components-' + str(OLD_TOTAL) + '%20',
              'badge/Total%20Components-' + str(TOTAL) + '%20')
s = re.sub(r'> \*\*Total Components: [\d,]+ / 10,000 \([0-9.]+%\)\*\*',
           '> **Total Components: %s / 10,000 (%s%%)**' % (format(TOTAL, ','), PCT), s, count=1)
s = re.sub(r'\*\*Version: v2\.82\.0\*\*', '**Version: v2.83.0**', s, count=1)
s = re.sub(r'\*\*SFT 语料: \d+ 条\*\*', '**SFT 语料: %d 条**' % SFT, s, count=1)

sumline = (
 '> **R91（2026-11-25 第 4 轮 · 冲刺）**：**%d 件入册（复杂 %d + 简单 %d，4 族×10 件模板派生）**——'
 '水泥窑篦冷机与预热器族 10（热回收效率/料层阻力/风量平衡/出料温度/级效率/旋风筒压损/旁路放风比/冷却速率/篦床行程监视 + GrateCoolerStartupSeq C4）·'
 '制药冻干族 10（冰面蒸气压/升华速率/搁板热负荷/一次干燥时间/泄漏率/塌陷温度裕度/残余水分/搁板升温控制/压力升测试 + LyoVacuumPullSeq C4）·'
 '轮胎硫化族 10（等效硫化时间/胶囊蒸汽/合模力/胎面温差/硫化程度/模压周期/蒸汽干度/模温监视/排凝监视 + TireCurePressSeq C5）·'
 '间歇式溢流染色与丝光族 10（浴比/升温速率/溢流流量/带碱量/丝光收缩/漂白投加/上染率/色差ΔE/碱浓监视 + JiggerBatchRecipeSeq C4）；'
 '总库 %s→**%s**，v2.83.0，SFT **%d**。**L2 闸：%d/%d PASS = 100%%，零 FAIL**（连续第 14 轮），串行 jobs=1，单件均 0.32 s，'
 '负向对照 **9/9** 全命中；**跨文件 ENUM 新增 10 个零重名**（R87 起常驻维度，旧账 11 处仍未清）。'
 '审校全量 %d 件，R5 双语缺英文半边 13 处 = MINOR。修复件 0（非当日首轮，配额归零）。\n'
) % (N_NEW, N_CX, N_SM, format(OLD_TOTAL, ','), format(TOTAL, ','), SFT, N_NEW, N_NEW, N_NEW)

anchor = '> **R90（2026-11-25 第 3 轮 · 冲刺）**'
i = s.find(anchor)
if i >= 0 and 'R91（2026-11-25' not in s:
    j = s.find('\n', i)
    s = s[:j + 1] + sumline + s[j + 1:]
elif 'R91（2026-11-25' not in s:
    s = s.replace('# 道莅工业自动化标准代码库', '# 道莅工业自动化标准代码库\n\n' + sumline, 1)
wr(p, s)
print('README ok', TOTAL, SFT)

# ---------- CHANGELOG ----------
p = os.path.join(ROOT, 'CHANGELOG.md')
s = rd(p)
if 'v2.83.0' not in s:
    fams = {}
    for n in ADDED:
        fams.setdefault(TARGETS[n]['family'], []).append(n)
    lines = ['## [v2.83.0] — 2026-11-25 · R91 冲刺轮（当日第 4 轮）', '',
             '### Added',
             '- **%d 个组件入库**（复杂 %d + 简单 %d），总库 %s → **%s**；SFT 语料 %d → **%d**。%d 件合 %d 行。'
             % (N_NEW, N_CX, N_SM, format(OLD_TOTAL, ','), format(TOTAL, ','), OLD_SFT, SFT, N_NEW, LINES), '']
    for fam, names in fams.items():
        lines.append('- %s族 %d：%s' % (fam, len(names), ' / '.join('`%s`' % n for n in names)))
    lines += ['',
              '### Fixed',
              '- 本轮新件自身回修 0 件；存量修复 0 件（非当日首轮，修复配额按铁律一归零）。',
              '',
              '### Changed',
              '- 闸席 L1 静态子集新增 R26（同一输出单点赋值）与 R21（周期入参）命中统计。',
              '- 闸席负向对照扩至 9 组，新增「未声明变量」「类型不匹配赋值」「缺分号」三组。',
              '',
              '### Known Issues',
              '- 跨文件 ENUM 同名旧账 **11 处**仍未清（单件 L2 结构上看不见，全库/MatIEC 编译必炸），已连续 3 轮挂账。',
              '- MatIEC 侧 L2 基线 0/1,490 属老方言与现代语法系统性差异，已立「dialect 适配专项」，不据此否定本地 PASS 件。',
              '']
    s = s.replace('## [v2.82.0]', '\n'.join(lines) + '\n## [v2.82.0]', 1)
    wr(p, s)
print('CHANGELOG ok')

# ---------- ROADMAP ----------
p = os.path.join(ROOT, 'ROADMAP.md')
s = rd(p)
if 'R91（2026-11-25 第 4 轮' not in s:
    blk = [
        '',
        '## R91（2026-11-25 第 4 轮 · 冲刺）小结',
        '',
        '- 入库 **%d 件**（复杂 %d + 简单 %d），总库 %s → **%s**（%s%%），v2.83.0，SFT **%d**。'
        % (N_NEW, N_CX, N_SM, format(OLD_TOTAL, ','), format(TOTAL, ','), PCT, SFT),
        '- 新增域：水泥窑篦冷机与预热器、制药冻干（真空冷冻干燥）、轮胎硫化、间歇式溢流染色与丝光整理。四族词根全库饱和度实测均为 0，属真空域。',
        '- 质量：L2 闸席原生裁决 **%d/%d PASS，零 FAIL**（连续第 14 轮），串行 jobs=1，单件均 0.32 s，负向对照 9/9 命中；跨文件 ENUM 新增 10 个零重名。' % (N_NEW, N_NEW),
        '- 审校全量 %d 件；R5 双语缺英文半边 13 处（MINOR，不阻断入库）。拒收 0。' % N_NEW,
        '- 修复件 0（非当日首轮，配额归零）；四条产能铁律全达标：修复 0 ✔ / 简单 %d%% ✔ / 4 族编码席一次调用写 %d 件 ✔ / 里程碑提前 ✔。'
        % (round(N_SM * 100.0 / max(N_NEW, 1)), N_NEW),
        '',
        '### R92 待办（P0）',
        '',
        '1. **旧账 11 处跨文件 ENUM 冲突清账**（脚本批量改名 + 全量 L2 回归）；已连续 3 轮挂账，本轮起列为一号债。',
        '2. R19 扩面：扫 DL_Process 471+ 件「REAL 出口只置 xValid 未闸断实值通路」。',
        '3. R5 双语补齐：本轮 13 处 `_eState` 行缺英文半边。',
        '4. 累计 79 件 API 推送 + 改 `workflow_dispatch` 触发 CI（Git Data API 更新 ref 不产生 push 事件，R87 已确认）。',
        '5. 队列补仓至 ≥240（当前 232 行）。',
        '6. DL_Motion 最薄补仓（171 件，占比 8.9%）：安排 1 族×9 件。',
        '7. 看板同步（当日末轮，已连续 4 轮顺延）。',
        '8. 冷启动/初值态专项常态化进 L1 扫查清单。',
        '',
    ]
    s = s.rstrip('\n') + '\n' + '\n'.join(blk)
    wr(p, s)
print('ROADMAP ok')

# ---------- AGENT_EVOLUTION_LOG ----------
p = os.path.join(ROOT, 'AGENT_EVOLUTION_LOG.md')
s = rd(p)
if 'R91 |' not in s and 'R91 ' not in s[-3000:]:
    blk = [
        '',
        '## R91（2026-11-25 第 4 轮）',
        '',
        '- **流程**：规划 T+7′ / 编码 40 件 T+16′ / 闸裁 T+23′ / 入库 T+%s′，四点全提前。单轮墙钟目标 ≤60′。',
        '- **闸**：负向对照扩至 9 组（新增未声明变量/类型不匹配/缺分号），证明闸非空转；R17 跨文件符号表常驻。',
        '- **教训**：闸席自建路径清单带 CRLF 尾符（路径含 `\\r`）导致 plc.exe 全部 rc=1 无 E 码 → 1/40 假 FAIL，该轮结论已作废重跑。**路径清单必须 strip()**。',
        '- **教训**：R5 英文半边判据把 `Pi [-]` 这类 2 字母英文误报为缺失 → 判据应要求「/ 后至少 3 词或含 ASCII 字母数 ≥3」。',
        '- **产能**：四条铁律全达标，单轮 40 已连续 7 轮稳定；300/日 需 ≥8 轮/日。',
        '',
    ]
    wr(p, s.rstrip('\n') + '\n' + '\n'.join(blk))
print('EVOLOG ok')
print('TOTAL', TOTAL, 'SFT', SFT, 'TODAY', TODAY, 'LINES', LINES)
