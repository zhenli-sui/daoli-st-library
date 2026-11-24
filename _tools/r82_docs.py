# -*- coding: utf-8 -*-
"""R82 文档增量：README 徽章 / CHANGELOG / VERSION / ROADMAP / EVOLOG / DAILY_RETRO / BATTLE_REPORT
用法: python r82_docs.py <facts.json>
facts.json 需含: total, jsonl, today, complex, simple, repairs, gate_pass, gate_fail,
                gate_exempt, gate_total, first_pass, ci, queue_total, queue_green,
                queue_yellow, queue_red, traceless, by_cat, new_names, rejected, minors
全部为「已事实核对」的数字，脚本不做推断。
"""
import io, json, os, sys, datetime

LIB = r'C:\Library'
STG = os.path.join(LIB, '_Staging_Raw', '2026-11-24')
R = 'R82'
VER = '2.74.0'
NOW = '2026-11-24T12:02:00+08:00'

f = json.load(io.open(sys.argv[1], encoding='utf-8'))
T = f['total']; J = f['jsonl']; TODAY = f['today']
CX = f['complex']; SM = f['simple']; RP = f['repairs']
GP = f['gate_pass']; GF = f['gate_fail']; GE = f['gate_exempt']; GT = f['gate_total']
FP = f.get('first_pass', GP)
CI = f['ci']
QT = f['queue_total']; QG = f['queue_green']; QY = f['queue_yellow']; QR = f['queue_red']
TRC = f['traceless']
REJ = f.get('rejected', 0)
MINORS = f.get('minors', 0)
BYCAT = f['by_cat']
rate = 100.0 * GP / GT if GT else 0.0
today_rate = 100.0 * TODAY / 300.0

log = []


def note(s):
    log.append(s)
    print(s)


# ---------- 1. README 徽章 + 摘要行 ----------
p = os.path.join(LIB, 'README.md')
s = io.open(p, encoding='utf-8').read()
o = s
import re
s = re.sub(r'(Total%20Components-)([\d,]+)(-)', lambda m: m.group(1) + format(T, ',') + m.group(3), s, count=1)
s = re.sub(r'(Total Components:\s*)([\d,]+)(\s*/\s*10,000)', lambda m: m.group(1) + format(T, ',') + m.group(3), s)
s = re.sub(r'(SFT%20Samples-)([\d,]+)(-)', lambda m: m.group(1) + format(J, ',') + m.group(3), s, count=1)
s = re.sub(r'(Version-)(v?[\d.]+)(-)', lambda m: m.group(1) + 'v' + VER + m.group(3), s, count=1)
if s != o:
    io.open(p, 'w', encoding='utf-8').write(s)
    note('README 徽章更新 → %d / %d / v%s' % (T, J, VER))

# ---------- 2. CHANGELOG 追加 ----------
cl = os.path.join(LIB, 'CHANGELOG.md')
names = f.get('new_names', [])
block = ['\n## v%s — 2026-11-24（R82 构建轮 · 冲刺模式）\n' % VER,
         '\n### Added — %d 件（复杂 %d / 简单 %d）\n' % (CX + SM, CX, SM),
         '分类分布：' + ' / '.join('%s %d' % (k.replace('DL_', ''), v) for k, v in BYCAT.items()) + '\n',
         '\n五族简单件（同族连号族模板派生）：\n',
         '- 族 A 混凝絮凝沉淀 8 件：加药反算 / 稀释比 / 沉降速度 / 泥位 / 表面负荷 / SVI / 浊度微调 / 斜板面积\n',
         '- 族 B 污泥脱水 7 件：螺旋压榨 / 含固率 / 聚合物 / 离心液 / 滤液回流 / 物料平衡 / 带压负荷\n',
         '- 族 C 湿式洗涤与催化 7 件：液气比 / HTU / 药剂耗 / 催化衰减 / 文丘里压降 / 除雾流速 / 排放折算\n',
         '- 族 D 设备点检维护 7 件：RUL / 轴承热漂 / 换油 / MTBF / 订货点 / PM 日期 / 润滑间隔\n',
         '- 族 E 厌氧沼气 7 件：产气率 / 甲烷比 / OLR / VFA碱度 / 气柜 / 停留时间 / 火炬\n',
         '- 复杂件 4 件：混凝加药闭环 / 螺旋压榨脱水序列 / 洗涤塔药剂投加闭环 / 厌氧消化负荷控制\n',
         '\n### Changed\n',
         '- `dl_gate.py` 新增 4 条静态锚点：`R509_FOR_DOWNTO`（库级共性编译缺陷，实测 7 件在库件命中）/ '
         '`R525_UNIT_LABEL_INVERTED`（换算常量名实相反）/ `R526_CONST_ZERO_REF`（声明常量零引用）/ '
         '`R527_TON_CROSS_PHASE`（TON 的 IN 跨相 OR 实为累计看门狗）\n',
         '- 重建 `_dedup_fingerprints.json`：84 条（覆盖 5.6%%）→ **%d 条（覆盖 100%%）**，'
         '三道去重之「签名指纹道」恢复可用（sig 60 组 / api 46 组 / 词根倒排 642 词）\n' % T,
         '- 全局规则编号游标校正：游标文件停在 R504 已过期（实测最大 R529），按 R483 重建 → R530 起分配\n',
         '\n### Fixed\n',
         '- 本轮修复件 0（非当日首轮，铁律一配额归零）；存量 7 件 `FOR..DOWNTO` 编译阻断件本轮只做机检锚点落地，'
         '定点修复顺延次日首轮\n',
         '\n### Rejected / Known Issues\n',
         '- 本轮拒收 %d 件（详见 BATTLE_REPORT_R82 §4）\n' % REJ,
         '- 已知挂账：R80 遗留 5 件逻辑 MAJOR（量纲/分母/物性表/差压因子/复位判据）连续第 3 轮未修，'
         '受「修复只在当日首轮」铁律约束，待次日首轮清\n',
         '- `FOR..DOWNTO` 在库仍存 7 件（Device 2 / MathData 3 / Motion 1 / Process 1），L2 必 FAIL，挂次日首轮\n',
         '\n---\n']
io.open(cl, 'a', encoding='utf-8').write(''.join(block))
note('CHANGELOG v%s 追加' % VER)

# ---------- 3. VERSION 文件（仅本轮触及子库） ----------
for sub in ('DL_Process', 'DL_Device'):
    vp = os.path.join(LIB, sub, 'VERSION')
    if os.path.exists(vp):
        io.open(vp, 'a', encoding='utf-8').write('%s\n' % VER)
        note('VERSION 追加 %s → %s' % (sub, VER))

# ---------- 4. ROADMAP 小结 + 下轮待办 ----------
rm = os.path.join(LIB, 'ROADMAP.md')
blk = ['\n## R82 构建轮小结（2026-11-24 上午轮 · 冲刺模式）\n\n',
       '> **R82 小结**：**%d 件入册**（复杂 %d + 简单 %d，5 族模板派生），总库 →**%d**（%.2f%%），v%s，SFT →**%d**。'
       '**L2 闸：终裁 %d/%d PASS = %.1f%%**（首裁 %.1f%%），拒收 %d 件。修复件 %d（非当日首轮，配额归零）。'
       '开源队列 %d 条（绿 %d / 黄 %d / 红 %d），溯源 %d/%d。今日 **%d/300（%.1f%%）**。\n'
       % (CX + SM, CX, SM, T, 100.0 * T / 10000.0, VER, J, GP, GT, rate, 100.0 * FP / GT if GT else 0,
          REJ, RP, QT, QG, QY, QR, TRC, CX + SM, TODAY, today_rate),
       '> **R83 待办（P0）**：① **7 件 `FOR..DOWNTO` 定点修复**（`FB_DL_UltrasonicWeldCtrl` / `FB_DL_VisionLightBank` / '
       '`FC_DL_DwordToHexString` / `FC_DL_LrealToFixedField` / `FC_DL_PolyEvalHorner` / `FB_DL_MarkPositionLatch` / '
       '`FB_DL_RotaryIndexerCycleSeq`）——次日首轮占 4 件配额，余 3 件分两轮；② R80 遗留 5 件逻辑 MAJOR 仍未清（第 3 轮挂账），'
       '建议增设「安全侧缺陷不受修复配额限制」例外条款；③ `FC_DL_LaneDiverterAngleCalc` 的 `DL_RAD_TO_DEG := 0.0174533` '
       '名实相反常量修正（全库仅此 1 件，机检已能自动定位）；④ 队列深度 %d < 200，需补仓或正式改口径；'
       '⑤ 值守三项（GITHUB_TOKEN 真检索 / GATE MAJOR 人核 / L3 向量门）第 14 轮顺延。\n' % QT]
io.open(rm, 'a', encoding='utf-8').write(''.join(blk))
note('ROADMAP R82 小结 + R83 待办追加')

# ---------- 5. AGENT_EVOLUTION_LOG 追加 ----------
ev = os.path.join(LIB, 'AGENT_EVOLUTION_LOG.md')
eb = ['\n## R82（2026-11-24 上午轮 · 冲刺模式）\n\n',
      '- **库级共性编译缺陷确认**：`FOR..DOWNTO` 在库命中 7 件（非 R81 估的 3 件），RuSTy 1.0.8 报 E007。'
      '该批件均在 R70 前入库、从未真编译过 → 已落 `dl_gate.py` 锚点 `R509_FOR_DOWNTO`（BLOCK 级），'
      '机检自动拦截，不需人工记忆。\n',
      '- **换算常量名实相反全库普查**：仅 1 件（`FC_DL_LaneDiverterAngleCalc`），已落锚点 `R525_UNIT_LABEL_INVERTED`。\n',
      '- **指纹库重建**：84 条 → %d 条（100%% 覆盖），道 2 从「降级不可用」恢复为「可用」；'
      'sig 指纹组 60 / api 指纹组 46 / 词根倒排 642。\n' % T,
      '- **规则号游标治理事故（第 2 次）**：游标文件停在 R504，实测最大已 R529；本轮规格书内部又用 R525~R528 作临时标签，'
      '与 R81-B 已占号冲突。处置：游标重建为 R530 起，规格书标签重映射，并确立「开轮第一步核对各账本实测最大值，'
      '不信游标文件」为强制步骤。\n',
      '- **席位名回退首次触发**：`dlf-*` 五席名全部即时失败（团队包 enabled 但当前会话未加载代理定义），'
      '按预案回退原名 `daoli-oss-hunter` / `plc-programming-expert` / `daoli-compile-verifier` / `daoli-qa-dedup`，'
      '零兜底 general-purpose。结论：团队包需重启 WorkBuddy 才生效。\n',
      '\n---\n']
io.open(ev, 'a', encoding='utf-8').write(''.join(eb))
note('AGENT_EVOLUTION_LOG R82 追加')

print('\n=== 文档增量完成 ===')
