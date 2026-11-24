import io, os, re, datetime

R = 'R75'
TS = '2026-11-23'
TOTAL = 1288
SFT = 1327
VER = 'v2.67.0'

# ---------- README ----------
p = r'C:\Library\README.md'
s = open(p, encoding='utf-8').read()
s = s.replace('Total%20Components-1252%20%2F%2010%2C000', 'Total%20Components-1288%20%2F%2010%2C000')
s = s.replace('SFT%20Corpus-1291%20records', 'SFT%20Corpus-1327%20records')
s = s.replace('**Total Components: 1252 / 10,000 (12.52%)**', '**Total Components: 1288 / 10,000 (12.88%)**')
s = s.replace('**Version: v2.66.0**', '**Version: v2.67.0**')
s = s.replace('**SFT 语料: 1291 条**', '**SFT 语料: 1327 条**')

r75 = ('> **R75（2026-11-23）**：**39 件交付（36 新件 + 3 点修）+ 2 件接口适配**——复杂件 13（Device：BurnerFlameGuard·VfdStateWordMatch·VfdCtrlWordBuild·IoLinkPortDiag'
       '｜Process：InjectionMoldClampSeq·PaintBoothAirBalance·WaterChlorineDoseTrim·CentrifugeSpinSeq'
       '｜Motion：DeltaRobotIk｜MathData：WeirFlowCalc·AkimaInterp1D｜Base：ManualOverride｜Algo：PeltierTempCtrl）'
       '+ 简单件 23（MathData 8：CabsComplexCalc·Exp10Calc·SpeedUnitConvert·FirstOrderImpResp·QuartileCalc·PowerFactorCalc·DitherSignalGen·MoistureContentCalc'
       '｜Base 7：ControlModeSel·DwRealReinterp·DualWindowBandCmp·ParamSnapshotRestore·SignalCrossbar8·WorkdayCalendarCalc·SmokeDetZoneMon'
       '｜Motion 3：GearRatioCalc·CrankKinFwd·BeltLengthCalc｜Device 2：EtSlaveDiagBase·EtSyncUnitDiagBase｜Algo 2：OvershootPctCalc·SettleTimeCalc｜Process 1：VocVentTrim）'
       '；点修 3（DryerExhaustHumidityCtl / WeightClassifySort / ChamberPurgeDry 多出参零回执补齐）+ CamTableInterp VLA 修复（v1.0.2，增 uPointCnt 显式点数）'
       '；总库 1,252→**1,288**，SFT **1,327**；**L2 闸 40/40 PASS = 100%**（首次零失败轮）；审校去重见 QA_REVIEW_R75；开源队列 **50 条（绿区 49 / 黄区 1）**，溯源占比 25/39 = 64.1%。\n\n')
anchor = '> **R73（2026-11-23）**'
assert anchor in s
s = s.replace(anchor, r75 + anchor, 1)
open(p, 'w', encoding='utf-8').write(s)
print('README ok')

# ---------- CHANGELOG ----------
p = r'C:\Library\CHANGELOG.md'
s = open(p, encoding='utf-8').read()
new = '''## v2.67.0 — 2026-11-23（R75 三十六件入册 + 三件零回执点修 + CamTable VLA 解耦 ｜ 首次 L2 零失败轮）

### Added（36 件：DL_MathData 10 / DL_Base 8 / DL_Device 6 / DL_Process 5 / DL_Motion 4 / DL_Algo 3）
- **复杂件 13**：`FB_DL_BurnerFlameGuard`（C5 燃烧器火焰安全监督，吹扫许可/点火/火焰建立/运行监视/锁存五相，火焰丢失即时关阀与锁存判定双路径分离）｜`FB_DL_InjectionMoldClampSeq`（C5 注塑五段顺控，段出口=到位+段超时双条件，模保最高优先中断）
  ｜`FB_DL_DeltaRobotIk`（C5 三角洲并联机器人闭式逆解，域检查前置统一置无效，归一化奇异判据）｜`FB_DL_VfdStateWordMatch`（C3 状态字→离散状态号，期望集单向包含匹配，失配锁存状态号）
  ｜`FB_DL_PaintBoothAirBalance`（C4 喷漆房压差环 + 送排比双环，持续越限才降级）｜`FC_DL_WeirFlowCalc`（C3 薄壁/宽顶堰流量，淹没度判别后换修正系数）
  ｜`FB_DL_WaterChlorineDoseTrim`（C4 流量浊度前馈 + 余氯死区反馈微调，上限硬钳位后冻结积分）｜`FB_DL_CentrifugeSpinSeq`（C4 三段升速，临界带内最大加速度快穿，振动超限独立中断路径）
  ｜`FC_DL_AkimaInterp1D`（C4 Akima 一维插值，斜率差权重，点数显式入参钳位防 VLA）｜`FB_DL_VfdCtrlWordBuild`（C3 状态意图→控制字位序，每位显式赋值不依赖残留）
  ｜`FB_DL_ManualOverride`（C3 请求态/生效态分离 + 强制超时回落 + 曾强制标志）｜`FB_DL_IoLinkPortDiag`（C3 物理/通信/设备三层诊断聚合）
  ｜`FB_DL_PeltierTempCtrl`（C4 TEC 双向温控，带符号单 PID + 条件积分抗饱和 + 极性翻转清零积分）
- **简单件 23**：MathData 8（`FC_DL_CabsComplexCalc` 防溢出模长 / `FC_DL_Exp10Calc` / `FC_DL_SpeedUnitConvert` / `FB_DL_FirstOrderImpResp` / `FC_DL_QuartileCalc` / `FC_DL_PowerFactorCalc` / `FB_DL_DitherSignalGen`/ `FC_DL_MoistureContentCalc`）
  ｜Base 7（`E_DL_ControlModeSel` 模式枚举 / `FC_DL_DwRealReinterp` IEEE754 手拆位置解释 / `FB_DL_DualWindowBandCmp` 双窗三态 / `FB_DL_ParamSnapshotRestore` 双缓冲快照 / `FB_DL_SignalCrossbar8` 8×8 路由 / `FC_DL_WorkdayCalendarCalc` 儒略日工作日 / `FB_DL_SmokeDetZoneMon` 烟感分区三态）
  ｜Motion 3（`FC_DL_GearRatioCalc` / `FB_DL_CrankKinFwd` 曲柄滑块正解 / `FC_DL_BeltLengthCalc`）｜Device 2（`ST_DL_EtSlaveDiagBase` / `ST_DL_EtSyncUnitDiagBase` EtherCAT 诊断基结构，clean-room 去厂商哈希后缀）
  ｜Algo 2（`FC_DL_OvershootPctCalc` / `FC_DL_SettleTimeCalc` 回路 KPI 族）｜Process 1（`FB_DL_VocVentTrim` VOC 需求通风，与 RoomCo2DemandVent 同构异介质）

### Fixed（4 件）
- `FC_DL_CamTableInterp` **v1.0.2**：`aCam : ARRAY[*]` → `ARRAY[1..200] OF ST_DL_CamPoint`，新增 `uPointCnt : UINT` 入参并在函数首部钳位 [2,200]，下标体系 0 基改 1 基；解 `FB_DL_CamOverrideTrim` E037 VLA 透传（该件同步 v1.0.1，全库无其他调用点）
- `FB_DL_DryerExhaustHumidityCtl` **v1.0.1**：两处 `FC_DL_HumidAirEnthalpy` 调用补 `uErrorId =>` 回执 + 声明 2 个 UDINT 接收变量
- `FB_DL_WeightClassifySort` **v1.0.1**：`FC_DL_LimitClassify` 调用补 `uErrorId => uBandErr`，回执非零时 `bBandInv := TRUE` 走 NG 安全侧分流
- `FB_DL_ChamberPurgeDry` **v1.0.1**：`FC_DL_DewPointCalc` 调用补全部 3 出参回执，`bDewInRange` 并入有效判据（域内回执失败则露点不锁存）

### Changed
- registry **1,252 → 1,288**（v2.66.0 → v2.67.0），counts **167 / 314 / 142 / 234 / 133 / 298**（sum 断言过）
- SFT 语料 **1,291 → 1,327** 条（+36 全量语料，含 output 完整源码）
- 开源候选队列 **29 → 50 条**（R75 猎人净增 21 条，绿区 49 / 黄区 1 / 红区 0）；本轮新增 3 个绿区仓：OpenPLC / PLCFiddle / libmodbus-adjacent 语义层
- **首次 L2 零失败轮**：40 检 40 PASS，零豁免、零拒收、零返修轮次

'''
s = s.replace('## v2.65.0 — 2026-11-23', new + '## v2.65.0 — 2026-11-23', 1)
open(p, 'w', encoding='utf-8').write(s)
print('CHANGELOG ok')

# ---------- VERSION ----------
for cat in ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']:
    p = os.path.join(r'C:\Library', cat, 'VERSION')
    if os.path.exists(p):
        open(p, 'w', encoding='utf-8').write('2.67.0\n')

# ---------- ROADMAP ----------
p = r'C:\Library\ROADMAP.md'
s = open(p, encoding='utf-8').read()
s = s.rstrip() + '''

## R75 构建轮小结（2026-11-23）

> **R75 小结**：**39 件交付（36 新件 + 3 点修）+ 2 件接口适配**——复杂 13 新（C5×3 / C4×5 / C3×5）+ 简单 23 新，点修 DryerExhaustHumidityCtl / WeightClassifySort / ChamberPurgeDry（多出参零回执补齐），另 `FC_DL_CamTableInterp` v1.0.2 解 VLA 透传（E037 清零）。总库 1,252→**1,288**，v2.67.0，SFT 1,291→**1,327**。**L2 闸 40/40 PASS = 100%**（历史首次零失败零豁免轮）。开源队列 29→**50 条**（绿区 49），溯源 25/39 = 64.1%。零检索轮（WebSearch 0/3，连续第 12 轮）。
> **R76 待办（P0）**：① **闸侧关键字撞名静态检查**——本轮 `FC_DL_AkimaInterp1D` 因局部数组 `aT` 撞 IEC `AT` 关键字报 E007，建议 `l2_check.py` 预筛加「标识符与 IEC 关键字不区分大小写撞名」告警（R415）；② **闸侧 FB-PROPERTY 剥离预处理器**（R74 挂账未清，SingleAxis/BatchDosingControl 仍豁免，若 R76 未上线则新件直接禁用 PROPERTY 写法而非豁免）；③ 开源队列已耗至绿区 49，R76 需恢复 1 次真检索补仓（`oss_harvest --exclude` 参数先落地）；④ 码位子带扩容口径终审（Akima 启用 0005_05xx 扩展子带首槽）；⑤ 值守三项第 7 轮顺延（MatIEC-CI 待配 remote / oss_harvest token / GATE MAJOR 人核）。
'''
open(p, 'w', encoding='utf-8').write(s)
print('ROADMAP ok')

# ---------- AGENT_EVOLUTION_LOG ----------
p = r'C:\Library\AGENT_EVOLUTION_LOG.md'
s = open(p, encoding='utf-8').read()
s = s.rstrip() + '''

## R75 轮（2026-11-23）
- **组织**：猎人∥编码（B1 并行净省约 6′）+ 复杂 14 件一次派发 → 简单 26 件一次派发（B2 批内一次性派发）+ L2 严格串行 jobs=1（A2）。五角色原生召唤 **5/5**（总监 / 猎人 / PLC 编码×2 调用 / 审校去重；编译闸主控直跑直读），零兜底，WebSearch 0/3（连续第 12 零检索轮）。
- **L2**：**40 检 40 PASS = 100%**，零豁免、零拒收、零返修轮次——历史首次。唯一过程失败为 `FC_DL_AkimaInterp1D` 首轮 E007（局部数组 `aT` 撞 IEC 保留字 `AT`，RuSTy 关键字不区分大小写），编码专家自检出后改名 `aTang` 一次通过。
- **新增红线 R15**：标识符禁止与 IEC 61131-3 保留字大小写不敏感同名（`AT`/`AD`/`END`/`VAR`/`CASE`/`FUN`/`TIME` 等），最短前缀+完整语义词 ≥3 字符。立规依据：本轮 aT→E007 单例，但属系统性雷（`aT`/`At`/`at` 全部中招）。
- **审校**：12 项定向扫查 + 三道去重，结果见 `_Staging_Raw/2026-11-23/QA_REVIEW_R75.md`。
- **收口**：registry 1,252→**1,288**（v2.67.0，counts 167/314/142/234/133/298，sum 断言过）；JSONL 1,291→**1,327**（+36 全量语料，instruction 真实工况 + architecture_thought 架构/状态机/防错/解耦 CoT）；6 库 VERSION 齐升 2.67.0；README 徽章 + R75 摘要行；CHANGELOG v2.67.0；ROADMAP R75 小结 + R76 待办 5 项。
'''
open(p, 'w', encoding='utf-8').write(s)
print('EVOLOG ok')
