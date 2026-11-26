# -*- coding: utf-8 -*-
"""R90 文档增量更新：README 徽章/摘要、CHANGELOG、VERSION、ROADMAP、EVOLOG。全部追加或定点替换，不整篇重写。"""
import json, os, glob, re, io

ROOT = r'C:\Library'
TOTAL = 1882
JSONL = 1921
VER = 'v2.82.0'
TODAY = '2026-11-25'
TODAY_N = 118   # 今日累计 78 + 本轮 40

# ---------- 磁盘实测行数 ----------
lines = 0
for p in glob.glob(os.path.join(ROOT, 'DL_*', '*.st')):
    with open(p, encoding='utf-8', errors='ignore') as f:
        lines += sum(1 for _ in f)

# ---------- README ----------
rp = os.path.join(ROOT, 'README.md')
txt = open(rp, encoding='utf-8').read()
txt = txt.replace('Total%20Components-1842%20%2F%2010%2C000', 'Total%20Components-1882%20%2F%2010%2C000')
txt = txt.replace('SFT%20Corpus-1881%20records', 'SFT%20Corpus-1921%20records')
txt = re.sub(r'\*\*Total Components: [\d,]+ / 10,000 \([\d.]+%\)\*\*', '**Total Components: 1,882 / 10,000 (18.82%)**', txt)
txt = txt.replace('**Version: v2.81.0**', '**Version: v2.82.0**')
txt = txt.replace('**SFT 语料: 1881 条**', '**SFT 语料: 1921 条**')
txt = re.sub(r'\*\*全库约 [\d,]+ 行（磁盘 \.st 实测口径）\*\*', '**全库约 %s 行（磁盘 .st 实测口径）**' % format(lines, ','), txt)

summary = (
 "> **R90（2026-11-25 第 3 轮 · 冲刺）**：**40 件入册（复杂 4 + 简单 36，4 族×10 件模板派生）**——"
 "RO/NF 膜法水处理族 10（回收率/膜通量/渗透压/净驱动压/浓差极化/LSI 结垢指数/浓水目标/段间压降/产水品质监视 + RoMembraneFlushSeq C4）·"
 "压缩空气系统能效族 10（比功率/FAD/压力露点/泄漏率/储罐容积/管路压降/喷嘴耗气/加卸载回差/干燥机再生损耗 + AirCompressorMasterSeq C4）·"
 "锂电极片涂布辊压族 10（湿膜厚度/面密度/辊压间隙/线载荷/孔隙率/压实比/烘箱热量/溶剂衡算/分区张力 + CoaterGapTrimSeq C4）·"
 "浮法玻璃锡槽退火族 10（锡槽温度插值/带宽/厚度/退火温降率/残余应力/保护气配比/锡渣速率/切裁优化/退火窑升温序 + FloatBathTopRollSeq C5）；"
 "总库 1,842→**1,882**，v2.82.0，SFT **1921**。**L2 闸：40/40 PASS = 100%，零 FAIL 零 EXEMPT（连续第 13 轮）**，串行 jobs=1，单件均 0.37 s，负向对照 8/8 全命中；"
 "**跨文件 ENUM 冲突检查：新增 6 个 ENUM 与存量 1,842 件零重名**（R87 起常驻维度）。"
 "审校全量 40 件：BLOCK 3（主控复核 3/3 成立、误判率 0%，全部已修并返修复裁）/ MAJOR 1 / MINOR 8，拒收 0，三道去重判重 0；"
 "修复件 0（非当日首轮，配额归零）。开源队列 232→**234 行**，本轮四族（RO 膜法/纸机流送/浮法玻璃/锂电涂布）ST 开源实测命中见 HARVEST_R90。\n"
 "> **R90 关键教训**：「先把量夹到工艺量程再判是否超量程」会使判据恒真（Lehr 退火速率件），"
 "**判据必须用未夹的原始值**；R19「只置 xValid 不闸断实值通路」本轮 3 件同型复发（CoaterGapTrim / AirCompMaster / RoFlush 类），"
 "已升级为出口层强制闸断规则。\n"
)
anchor = '> **R89（2026-11-25 第 2 轮 · 冲刺）**'
assert anchor in txt
txt = txt.replace(anchor, summary + anchor, 1)
open(rp, 'w', encoding='utf-8').write(txt)

# ---------- CHANGELOG ----------
cp = os.path.join(ROOT, 'CHANGELOG.md')
ct = open(cp, encoding='utf-8').read()
entry = """## [v2.82.0] — 2026-11-25 · R90 冲刺轮（当日第 3 轮）

### Added
- **40 个组件入库**（复杂 4 + 简单 36），总库 1,842 → **1,882**；SFT 语料 1,881 → **1,921**。
- RO/NF 膜法水处理族 10：`FC_DL_RoRecoveryCalc` / `RoFluxCalc` / `RoOsmoticPressureCalc` / `RoNetDrivingPressureCalc` / `RoConcentrationPolarizationCalc` / `RoScaleSaturationIndexCalc` / `RoBrineFlowTargetCalc` / `RoStagePressureDropCalc` / `FB_DL_RoPermeateQualityWatch` / `FB_DL_RoMembraneFlushSeq`（C4）
- 压缩空气系统能效族 10：`FC_DL_AirCompSpecificPowerCalc` / `AirCompFreeAirDeliveryCalc` / `AirDewPointCalc` / `AirLeakRateCalc` / `AirReceiverSizingCalc` / `AirPipePressureDropCalc` / `AirNozzleConsumptionCalc` / `AirCompLoadUnloadHystCalc` / `AirDryerPurgeLossCalc` / `FB_DL_AirCompressorMasterSeq`（C4）
- 锂电极片涂布辊压族 10：`FC_DL_CoaterWetThicknessCalc` / `CoaterArealLoadingCalc` / `CalenderGapCalc` / `CalenderLineLoadCalc` / `ElectrodePorosityCalc` / `ElectrodeCompactionRatioCalc` / `CoaterDryZoneHeatCalc` / `CoaterSolventBalanceCalc` / `CoaterTensionZoneCalc` / `FB_DL_CoaterGapTrimSeq`（C4）
- 浮法玻璃锡槽退火族 10：`FC_DL_FloatBathTempProfileCalc` / `GlassRibbonWidthCalc` / `GlassThicknessCalc` / `LehrAnnealingScheduleCalc` / `GlassResidualStressCalc` / `TinBathAtmosphereCalc` / `FloatBathDrossCalc` / `GlassCutOptimizeCalc` / `FB_DL_LehrZoneTempSeq` / `FB_DL_FloatBathTopRollSeq`（C5）

### Fixed
- `FC_DL_LehrAnnealingScheduleCalc`：速率出口改为宽钳（真实值），超速判据改用未夹的 `_fRateRaw` —— 原「先夹到 ±15 再判 ≤15」使上限判据恒真，超速降温被误判为「在退火曲线内」（安全侧）。
- `FB_DL_CoaterGapTrimSeq`：非激活相指令跟随实测改为止仅在测量有效时执行，测量 NaN 时保持上拍指令，堵住 NaN 直达间隙指令出口。
- `FB_DL_AirCompressorMasterSeq`：`fLoadBar`/`fUnloadBar` 出口改三分支，组态非法时闸断为字面量 0.0，不再外泄 NaN 至压力开关组态。

### Changed
- 新增红线候选：**判据与出口必须同源于原始值**——任何「先饱和钳制再判是否超限」的写法一律视为缺陷（R90 Lehr 事故）。
- 出口层强制闸断：凡 `VAR_OUTPUT` 含 REAL 且主体存在 `_b…Ok/_b…Bad` 有效性标志的 FB，REAL 出口必须在同一分支有字面量赋值或 `LIMIT` 包裹（R19 扩面）。

"""
ct = ct.replace('## [v2.81.0]', entry + '## [v2.81.0]', 1)
open(cp, 'w', encoding='utf-8').write(ct)

# ---------- VERSION（仅 DL_Process 本轮触及） ----------
vp = os.path.join(ROOT, 'DL_Process', 'VERSION')
with open(vp, 'a', encoding='utf-8') as f:
    f.write('\nv2.82.0  %s  R90：+40 件（复杂 4 + 简单 36），DL_Process 471→511 件\n' % TODAY)

# ---------- ROADMAP ----------
mp = os.path.join(ROOT, 'ROADMAP.md')
mt = open(mp, encoding='utf-8').read()
block = """
## R90（2026-11-25 第 3 轮 · 冲刺）小结

- 入库 40 件（复杂 4 + 简单 36），总库 1,842 → **1,882**（18.82%），v2.82.0，SFT **1,921**。
- 新增域：RO/NF 膜法水处理、压缩空气系统能效、锂电极片涂布辊压、浮法玻璃锡槽退火。四族词根全库饱和度实测均为 0，属真空域。
- 质量：L2 闸席原生裁决 **40/40 PASS，零 FAIL 零 EXEMPT（连续第 13 轮）**，串行 jobs=1，单件均 0.37 s，负向对照 8/8 命中；跨文件 ENUM 检查新增 6 个枚举零重名。
- 审校全量 40 件：BLOCK 3 / MAJOR 1 / MINOR 8，主控复核 3/3 成立、误判 0%，全部已修；拒收 0；三道去重判重 0（道 2 命中 28 全为 `REAL×n` 已知假阳性）。
- 修复件 0（非当日首轮，配额归零）。

### R91 待办（P0）

1. **R19 扩面专项**：全库 471 件 DL_Process 扫「REAL 出口只置 xValid 未闸断实值通路」，改 `dl_gate.py` 加锚点（本轮 3 件同型，已达 ≥3 阈值）
2. 判据同源专项：全库扫「先 LIMIT 夹到工艺量程再判是否超量程」的恒真判据
3. 旧账 11 处跨文件 ENUM 冲突清账（批量改名 + 全量 L2 回归）
4. 40 件 + R89 39 件 API 推送，并改 `workflow_dispatch` 触发 CI（Git Data API 更新 ref 不产生 push 事件）
5. 队列补仓至 ≥240（当前 234）
6. `FN_FC 双出口` 口径确认：部分 FC 使用 `VAR_OUTPUT + : BOOL` 返回码双出口，需确认是否全部平台兼容
7. 看板同步（当日末轮）
8. R21 三件 `fCycleS` 由调用方注入的周期合理性钳位（MAJOR 挂账）
"""
mt = mt.rstrip() + '\n' + block
open(mp, 'w', encoding='utf-8').write(mt)

# ---------- AGENT_EVOLUTION_LOG ----------
ep = os.path.join(ROOT, 'AGENT_EVOLUTION_LOG.md')
evo = """
## R90（2026-11-25 第 3 轮 · 冲刺轮）

- 墙钟 ≈ 52′；四点检查点：规划 T+3′、40 件全落盘 T+22′、闸裁 T+33′、入库 T+39′。
- 五席召唤：主控原生 ／ 开源供料 `daoli-oss-hunter` 原名回退 ／ 编码 `plc-programming-expert` 原名回退 ／ 闸 `daoli-compile-verifier` 原名回退 ×2（返修复裁）／ 审校 `daoli-qa-dedup` 原名回退。团队包连续第 8 轮未生效（`dlf-*` 报 not available），需重启 WorkBuddy。零 general-purpose 兜底（第 67 轮）。
- 子代理 5 次（满预算）。第 5 席用于返修复裁，第 3 件修复由主控直改并披露。
- 新增规则 20 条（五席），游标 → R704。
- 本体教训：R19「只置有效性位不闸断实值通路」在本轮 3 件复发，说明该缺陷形态不是个案而是模板级惯性 → 已提「出口层强制闸断」机检锚点，进入 R91 P0。
- 另一教训：`LIMIT` 既是饱和器也是判据污染源，凡「夹紧后判超限」必恒真。
"""
open(ep, 'a', encoding='utf-8').write(evo)

print('docs ok  lines=%s  total=%d jsonl=%d' % (format(lines, ','), TOTAL, JSONL))
