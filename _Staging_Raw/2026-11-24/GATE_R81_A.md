# GATE R81-A 逐件裁决表（36 件简单件）

- 裁决人：编译闸席 dlf-compile-verifier（一票否决权）
- 时间：2026-11-24
- 批次：R81 批 A（DL_Process 23 + DL_Device 7 + DL_Motion 6）
- 工具链：RuSTy `plc.exe --check`（L2 真编译），**串行 jobs=1**
- 命令（可复现）：
  ```
  python C:\Library\_tools\l2_check.py --out _Staging_Raw\2026-11-24\_l2_r81a.json $(cat _Staging_Raw\2026-11-24\_files_r81a.txt)
  ```
- L2 原始结果：`_l2_r81a.json`（36 行，每行 rc=0 / pass=true）；`PASS=36 FAIL=0 TOTAL=36`
- 名称校正：清单中 `FC_DL_SlipRatioCalc` 磁盘实为 `FC_DL_RollerSlipRatioCalc.st`；`FC_DL_SuctionCupCount` 实为 `FC_DL_SuctionCupCountCalc.st`。均按磁盘实名裁决，件数不变（36）。

## 一、汇总裁决

| 项 | 数 |
|---|---|
| 总件数 | 36 |
| PASS | 35 |
| FAIL | 1（FAIL(LOGIC)，L2 编译通过但算错） |
| EXEMPT | 0 |
| 通过率 | 35/36 = 97.2% |

**批量结论：BLOCK（放行 35 件，扣留 1 件）** —— 扣留件 `FC_DL_BeamToppleRiskChk`，其余 35 件可入注册流程。

## 二、逐件裁决

| # | 文件 | L2 | 裁决 | 逻辑复核 |
|---|---|---|---|---|
| 1 | DL_Process/FC_DL_ShuttleStrokeTimeEst.st | rc=0 | PASS | 梯形/三角判据 Vmax²/Acc 正确；t= d/V+V/Acc、2√(d/Acc) 均正确；除法前有 Acc/Vmax 正闸 |
| 2 | DL_Process/FC_DL_ShuttleAisleLockChk.st | rc=0 | PASS | 冲突计数与 deny 码同源，无对立表述；bGrant 仅 deny=0 |
| 3 | DL_Process/FC_DL_LifterCycleTimeEst.st | rc=0 | PASS | 单程=层高×(层数-1)/速度 正确；rCap 隐含「1 件/循环」口径（MINOR） |
| 4 | DL_Process/FC_DL_StocktakeVarianceCalc.st | rc=0 | PASS | DINT 中间量+双侧饱和正确；账面负时差异率为负（MINOR） |
| 5 | **DL_Process/FC_DL_BeamToppleRiskChk.st** | rc=0 | **FAIL(LOGIC)** | **L70 偏心系数用带符号偏移，负偏移使利用率被低估 → 漏报倾覆风险（MAJOR/BLOCK）** |
| 6 | DL_Process/FC_DL_CellOccupyRateCalc.st | rc=0 | PASS | 可用=总-封存，除前有非正闸；占用率未截断可 >100%（MINOR）；DL_R_MAX 死常量 |
| 7 | DL_Process/FC_DL_ForkExtendSafeChk.st | rc=0 | PASS | 余量与判据同源（fork ≤ clear-margin 且对齐合格）；DL_EPS 死常量 |
| 8 | DL_Process/FC_DL_BinLabelCheckSum.st | rc=0 | PASS | 校验和上限 32+12+28=72，INT 无溢出；WHILE 有看门狗 EXIT |
| 9 | DL_Process/FC_DL_FoamSuppressDutyCalc.st | rc=0 | PASS | 单向单调、限幅正确；量纲不闭环（MINOR），DL_DUTY_LO 被当液位下界复用（名实不符） |
| 10 | DL_Process/FC_DL_RinseWaterVolumeCalc.st | rc=0 | PASS | 单位链 mm→m（/2000）→m²×m×1000→L 逐级正确 |
| 11 | DL_Process/FC_DL_SanitizeHoldTimeCalc.st | rc=0 | PASS | 浓度比方向正确；温度系数限幅 0.5~2.0 后取倒数，顺序合规 |
| 12 | DL_Process/FC_DL_ConductivityDilutionCalc.st | rc=0 | PASS | R=(Cf-Cw)/(Ct-Cw) 与配水比 (1-1/R) 推导正确；分母非正前置 |
| 13 | DL_Process/FC_DL_NozzleClogIndexCalc.st | rc=0 | PASS | 超流截断为 0，报警门限用限幅后值且方向一致 |
| 14 | DL_Process/FC_DL_SipResidueVolumeEst.st | rc=0 | PASS | 面积/容积单位链正确；坡度项 sin(θ)×0.5×全管容 在 90° 时物理失真（MINOR） |
| 15 | DL_Process/FC_DL_FillValveSealWearEst.st | rc=0 | PASS | 仅超温部分计入加速；额定为零前置闸 |
| 16 | DL_Process/FC_DL_BottleNeckLevelMargin.st | rc=0 | PASS | 余量式与文档一致，负余量必报风险；DL_EPS 死常量 |
| 17 | DL_Process/FC_DL_ReceiverPressureDropCalc.st | rc=0 | PASS | 压降/时长折算正确；Nm³/min 未除 P_atm≈1.013（MINOR，系统偏差 ~1.3%） |
| 18 | DL_Process/FC_DL_AirQualityClassifyCalc.st | rc=0 | PASS | ISO 8573-1 露点/含油分级边界与 ELSIF 链一致；出口预置 4 级（最不利） |
| 19 | DL_Process/FC_DL_DesiccantLifeEstimate.st | rc=0 | PASS | 有效容量=容量×降额，乘积正闸后再作分母 |
| 20 | DL_Process/FC_DL_MotorLoadFactorCalc.st | rc=0 | PASS | 过载位用限幅前 raw 判定，信息未被限幅吃掉 |
| 21 | DL_Process/FC_DL_CompressorDutyCycleCalc.st | rc=0 | PASS | 加载+卸载>窗口 判无效；能耗分母零前置闸 |
| 22 | DL_Process/FC_DL_DrainIntervalCalc.st | rc=0 | PASS | 间隔=积水量/析水率×60；间隔内积水量回代自洽 |
| 23 | DL_Process/FC_DL_IdleRunRatioCalc.st | rc=0 | PASS | 加载时间越界判无效；空转时间负值截断 |
| 24 | DL_Device/FC_DL_VacuumPadForceCalc.st | rc=0 | PASS | F=(π/4)d²Δp，mm→m 与 kPa→Pa 双向换算正确，量级校验 50mm/60kPa→118N ✓ |
| 25 | DL_Device/FC_DL_SuctionFlowEst.st | rc=0 | PASS | Q=Cd·A·√(2Δp/ρ) 正确，m³/s×60000→L/min 正确；Nm³/h 实为实际态 m³/h（MINOR） |
| 26 | DL_Device/FC_DL_SheetPeelForceCalc.st | rc=0 | PASS | mm²×1e-6、kPa×1000 得 N；角度系数 0°→1 / 90°→0.5 / 180°→0 ✓；DL_EPS 死常量 |
| 27 | DL_Device/FC_DL_VacHoldDecayChk.st | rc=0 | PASS | 真空回升走 bSuspect 路径并双清零，不误报泄漏 |
| 28 | DL_Device/FC_DL_PadWearIndexCalc.st | rc=0 | PASS | 负增长截断、到期用限幅前 raw；0.7×% + 0.3×mm×10 量纲不齐（MINOR，口径已声明） |
| 29 | DL_Device/FC_DL_VacuumGenDutyCalc.st | rc=0 | PASS | 通电>周期 判无效；占空比限幅后再算耗气 |
| 30 | DL_Device/FC_DL_SuctionCupCountCalc.st | rc=0 | PASS | 截断+余量进位等价 CEIL，REAL_TO_INT 前有 32000 兜底，无回绕 |
| 31 | DL_Motion/FC_DL_LineSpeedMatchRatio.st | rc=0 | PASS | 速比=从/主，偏差分母设定速比前置正闸（设定值过小时偏差放大，MINOR） |
| 32 | DL_Motion/FC_DL_ChainWearElongation.st | rc=0 | PASS | 伸长率方向正确，仅正伸长触发送换 |
| 33 | DL_Motion/FC_DL_RollerSlipRatioCalc.st | rc=0 | PASS | 打滑率=(辊-带)/辊，负向被拖动可表达；报警用限幅后绝对值不产生漏报 |
| 34 | DL_Motion/FC_DL_SkateWheelLoadCalc.st | rc=0 | PASS | 前轴占比 0.5+e/base 限幅 0.1~0.9；奇数轮前轴多 1 个，(n+1)/2 整型除法正确 |
| 35 | DL_Motion/FC_DL_LaneDiverterAngleCalc.st | rc=0 | PASS | ATAN 弧度→度（/0.0174533）正确；通过时间 mm→m、m/min→m/s 正确 |
| 36 | DL_Motion/FC_DL_TrackingOffsetChk.st | rc=0 | PASS | 脉冲/每米脉冲→m，偏移与容差同量纲；每米脉冲零前置闸 |

## 三、FAIL 件最小修法

### FC_DL_BeamToppleRiskChk（DL_Process）— FAIL(LOGIC) / BLOCK
- 症状：L70 `rEccFactor := 1.0 + rCgOffset_mm / rBeamDepth_mm;`
  偏移为负（载荷重心偏向另一侧）时系数 <1，甚至可为负：
  例 `rCgOffset_mm = -200, rBeamDepth_mm = 100` → 系数 = -1 → 有效载荷为负 → 利用率负 → `bRisk=FALSE`，同时 `rEffLoadKg` 输出负质量。
  而 L66 域闸只拦 `rBeamCapKg/rLoadKg/rBeamDepth_mm`，**未拦 `rCgOffset_mm` 的符号**，负值可全量通过。
- 影响：倾覆风险漏报（安全侧失效），非显示瑕疵。
- 最小修法（行为单向收紧，一行）：
  ```iec
  // L70 现： rEccFactor := 1.0 + rCgOffset_mm / rBeamDepth_mm;
  rEccFactor := 1.0 + ABS(rCgOffset_mm) / rBeamDepth_mm; // 偏心放大量按偏移绝对值计 / use the absolute offset
  ```
  并在 L66 域闸补一条等价可选校验（二者取一即可，推荐上面的 ABS 写法）：
  ```iec
  IF (rBeamCapKg < 0.0) OR (rLoadKg < 0.0) OR (rBeamDepth_mm < 0.0) OR (ABS(rCgOffset_mm) > rBeamDepth_mm) THEN
      RETURN; // 偏心超过截面深度在工程上不可信 / offset beyond the section depth is not credible
  END_IF;
  ```
- 回归要求：修完必须补 2 条向量 —— (a) `offset=-depth/2` 时 `rUtilPct` 与 `offset=+depth/2` 相等；(b) `offset=-200,depth=100` 时 `bValid=FALSE` 或 `rUtilPct>0`。

## 四、逻辑级复核发现（分级）

### MAJOR（阻断）
1. **BeamToppleRiskChk L70** 带符号偏心 → 利用率低估/负值，倾覆风险漏报。见上节修法。

### MINOR（记录挂账，不阻断）
| 文件 | 行 | 问题 |
|---|---|---|
| ReceiverPressureDropCalc | L81 | Nm³/min 未按 P_atm≈1.013 bar 归一（或未把表压转绝压），系统偏差 ≈1.3%；公式已声明为近似 |
| SuctionFlowEst | L96 | `rFlowNm3h := _rQm3s * 3600` 为实际状态 m³/h，非标态，输出名与口径不符 |
| FoamSuppressDutyCalc | L70 | 占空比缺「泵额定投加量」输入，mL/L×L/min/100 量纲不闭环；L62/L65 复用 `DL_DUTY_LO` 作液位/速率下界，常量名实不符 |
| PadWearIndexCalc | L80 | 0.7×[%] + 0.3×[mm]×10 混量纲加权，10 倍增益无物理出处（口径已声明） |
| StocktakeVarianceCalc | L89 | 账面为负时差异率为负（建议分母取 `ABS(_rBook)`） |
| CellOccupyRateCalc | L83 | 超占（used>avail）时占用率可 >100%，未限幅亦未置异常位 |
| SipResidueVolumeEst | L93 | sin(坡度)×0.5 作用于全长管容，90° 时残留=50% 管容，物理不可信（建议乘 sin 后按坡度段长加权） |
| LifterCycleTimeEst | L78 | `rCap=3600/rCycle` 隐含 1 件/循环，而「一取一放」实为 2 件/循环，产能可能低算 2 倍（口径待明确） |
| LineSpeedMatchRatio | L74 | 设定速比仅 >EPS 即放行，设定值极小时偏差百分比爆炸（建议设定速比下界取 0.1） |
| 6 件 | — | **死常量（声明未用）**：CellOccupyRateCalc:DL_R_MAX、ForkExtendSafeChk:DL_EPS、FoamSuppressDutyCalc:DL_EPS、BottleNeckLevelMargin:DL_EPS、AirQualityClassifyCalc:DL_EPS、SheetPeelForceCalc:DL_EPS |

### 通过项（值得记入正面结论）
- 36/36 件「段 1 出口预置」均位于首个 `RETURN` 之前，**无 bValid/bErr 未赋值即返回**的情形（R80 类缺陷零复发）。
- 36/36 件所有除法均为「先闸后除、同段前置」，未出现依赖短路求值的写法。
- 量纲链逐件重算通过：RinseWater / Sip / VacuumPad / SuctionFlow / SheetPeel / SkateWheel / LaneDiverter 的 mm→m、kPa→Pa、L/min→m³/s、m/min→m/s 全部正确。
- 限幅上下界均为手工 IF/ELSIF 顺序判定，未见 MIN/MAX 反序。

## 五、待办与门禁状态

| 门 | 状态 |
|---|---|
| L1 增量语法/红线 | 本轮以逻辑复核为主；死常量与名实不符已按 MINOR 列出，未跑 `dl_gate.py --changed-only`（建议注册前补跑一次） |
| L2 真编译（RuSTy 串行） | **36/36 PASS，无 E004 假阳性**（严格 jobs=1） |
| L3 向量 | 未建：本批 36 件均无 `_TESTS\<Name>.json`，建议对 5 件安全类（BeamToppleRiskChk、ForkExtendSafeChk、VacHoldDecayChk、VacuumPadForceCalc、SuctionCupCountCalc）优先补向量 |
| 码段唯一 / registry 版本头 | 36 件均**尚未入 registry**（1490 件存量中查无），故唯一性与版本一致性只能在注册脚本写入时校验 |
| 综合判决 | **BLOCK**：放行 35 件，扣留 FC_DL_BeamToppleRiskChk 回派编码专家 |
