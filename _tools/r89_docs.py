import re, os, datetime
L = r'C:\Library'
def patch(p, old, new, count=1):
    s = open(p, encoding='utf-8').read()
    assert old in s, p + ' :: ' + old[:60]
    s = s.replace(old, new, count)
    open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------- README ----------
p = os.path.join(L, 'README.md')
patch(p, 'Total%20Components-1803%20%2F%2010%2C000-blue', 'Total%20Components-1842%20%2F%2010%2C000-blue')
patch(p, 'SFT%20Corpus-1842%20records-informational', 'SFT%20Corpus-1881%20records-informational')
patch(p, '> **Total Components: 1,803 / 10,000 (18.03%)** ｜ **Phase 2: 常态节奏 10~20 件/轮（R60 起按 R249/R193/R362 动态下调）** ｜ **Version: v2.80.0** ｜ **SFT 语料: 1842 条**',
      '> **Total Components: 1,842 / 10,000 (18.42%)** ｜ **Phase 2: 常态节奏 10~20 件/轮（R60 起按 R249/R193/R362 动态下调）** ｜ **Version: v2.81.0** ｜ **SFT 语料: 1881 条**')
patch(p, '> **R88（2026-11-25 凌晨轮 · 冲刺）**',
      '> **R89（2026-11-25 第 2 轮 · 冲刺）**：**39 件入册（复杂 4 + 简单 35，5 族模板派生）**——矿山破碎筛分族 9（破碎产能/筛分效率/浓密沉降面积/排矿口调整序/筛板磨损/球磨功率/絮凝投加/底流浓度/润滑联锁序）·板带剪切卷取族 9（张力设定/分条刀隙/钢卷小车定位/锥度张力/带长累计/刀隙调整序/卷重估算/开卷胀缩/板凸度）·锻造加热退火族 9（坯料加热时间/退火保温/分区升温序/锻造载荷/冷却速率/截面均匀性/模具润滑序/淬火延迟/炉门联锁序）·涂装喷涂族 8（漆膜厚度/喷枪流量/排风风门序/涂料消耗/固化曲线/静电电压/换色序/过滤棉寿命/机器人轨迹序）+ 复杂 4（RotaryKnifeCutSyncCtrl C5·ElectronicLineShaftSeq C4·CamSlavePhaseOffsetSeq C4·SCurveTimeOptCalc C3）；总库 1,803→**1,842**，v2.81.0，SFT **1881**。**L2 闸：40/40 PASS = 100%，零 EXEMPT（连续第 12 轮）**；**跨文件符号表首投入即抓 1 处新 ENUM 冲突**（已改名复裁 PASS，旧账 11 处仍在）；审校全量 40 件：BLOCK 6（主控复核 6/6 成立、误判 0%，全部已修）/ MAJOR 6 / MINOR 19，拒收 1（CoilTaperTensionSeq ↔ WinderTensionTaperCtrl 判重）；修复件 0（非当日首轮）。\n> **R88（2026-11-25 凌晨轮 · 冲刺）**')

# ---------- CHANGELOG ----------
p = os.path.join(L, 'CHANGELOG.md')
s = open(p, encoding='utf-8').read()
anchor = '## [v2.80.0] — 2026-11-25 · R88 冲刺轮（当日首轮）'
entry = """## [v2.81.0] — 2026-11-25 · R89 冲刺轮（当日第 2 轮）

### Added
- **39 个组件入库**（复杂 4 + 简单 35），总库 1,803 → **1,842**。
- 矿山破碎筛分族 9：`FC_DL_CrusherThroughputCalc` / `ScreenEfficiencyCalc` / `ThickenerSettlingAreaCalc` / `BallMillPowerDrawCalc` / `UnderflowDensityCalc` / `FB_DL_CrusherGapAdjustSeq` / `ScreenPanelWearMonitor` / `ThickenerFlocDoseCtrl` / `CrusherLubeInterlockSeq`
- 板带剪切卷取族 9：`FC_DL_StripTensionRefCalc` / `SlitterKnifeClearanceCalc` / `StripLengthAccumCalc` / `CoilWeightEstCalc` / `StripCrownCalc` / `FB_DL_CoilCarIndexSeq` / `ShearBladeGapSeq` / `UncoilerMandrelSeq`
- 锻造加热退火族 9：`FC_DL_ForgeBilletHeatTimeCalc` / `AnnealSoakTimeCalc` / `ForgeLoadTonCalc` / `BilletTempUniformCalc` / `QuenchDelayCalc` / `FB_DL_FurnaceZoneHeatSeq` / `AnnealCoolRateCtrl` / `ForgeDieLubeSeq` / `FurnaceDoorInterlockSeq`
- 涂装喷涂族 8：`FC_DL_PaintFilmThicknessCalc` / `SprayFlowRateCalc` / `PaintConsumptionCalc` / `ElectrostaticVoltageCalc` / `BoothFilterLifeCalc` / `FB_DL_BoothExhaustDamperSeq` / `OvenCureProfileSeq` / `ColorChangeSeq` / `PaintRobotPathSeq`
- 复杂 4：`FB_DL_RotaryKnifeCutSyncCtrl`(C5) / `ElectronicLineShaftSeq`(C4) / `CamSlavePhaseOffsetSeq`(C4) / `FC_DL_SCurveTimeOptCalc`(C3)

### Fixed
- `FC_DL_ScreenEfficiencyCalc`：筛分效率式分母 `(1−O)(F+U−1)` 系统性放大 η 并饱和至 100% → 改标准二产品式 `E = U(F−O)/(F(U−O))`。
- `FB_DL_BoothExhaustDamperSeq`：斜坡步长未做非有限闸，NaN 直穿风门输出 → 加归零闸。
- `FB_DL_PaintRobotPathSeq`：补偿量无出口闸 → 出口加非有限/越界归零闸。
- `FB_DL_ElectronicLineShaftSeq`：故障锁存期仍跟随主轴、主轴转速 NaN 直穿 → 加锁存互锁 + `_bMasterOk` 单点有效性位。
- `FB_DL_CamSlavePhaseOffsetSeq`：`fOffsetActDeg` NaN 播种后永久冻结 → 播种与出口各加 ±360° 非有限闸。

### Changed
- `FB_DL_BoothExhaustDamperSeq` 枚举 `E_DL_BdsPhase` → `E_DL_BedsPhase`（与存量 `FB_DL_BatchDoseSeq` 同名异义冲突）。

### Removed
- `FB_DL_CoilTaperTensionSeq` 拒收（与在册 `FB_DL_WinderTensionTaperCtrl` 功能完全重合），移入 `_quarantine/R89/`。

"""
s = s.replace(anchor, entry + anchor, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------- ROADMAP ----------
p = os.path.join(L, 'ROADMAP.md')
s = open(p, encoding='utf-8').read()
s += """
## R89（2026-11-25 第 2 轮 · 冲刺）小结

- 入库 39 件（复杂 4 + 简单 35），总库 1,803 → **1,842**（18.42%），v2.81.0。
- 新增域：矿山破碎筛分、板带剪切分卷、锻造加热退火、涂装喷涂线（前两族在 ST 开源生态实测真件极少且均无证）。
- 质量：L2 40/40 PASS 零 EXEMPT（连续第 12 轮）；**跨文件符号表首投入即抓 1 处新 ENUM 冲突**（单件编译不可见）；审校全量 40 件报 6 BLOCK，主控复核 6/6 成立并全修，误判率 0%。
- 拒收 1（`FB_DL_CoilTaperTensionSeq` ↔ 在册 `FB_DL_WinderTensionTaperCtrl`）。
- ★ 方法论纠正：`extension:` 与 OR 组合会静默吞结果返 0，前 7 轮「垂直工艺族开源真空」结论须逐词重测复核。

### R90 待办（P0）

1. 跨文件符号表并入常驻 L1（`_r89_symtab.py` 的 TYPE 抽取逻辑）
2. 旧账 11 处跨文件 ENUM 冲突清账（批量改名 + 全量 L2 回归）
3. 非有限闸扩面：全库扫「REAL 输出只写 xValid 未闸实值通路」
4. 四族检索式逐词重测，复核 7 轮「垂直族真空」结论
5. 队列补仓 ≥240（228 临界 200 红警）
6. 39 件 API 推送 + 改 `workflow_dispatch` 触发 CI
7. 看板同步（当日末轮）
"""
open(p, 'w', encoding='utf-8', newline='').write(s)
print('README/CHANGELOG/ROADMAP ok')
