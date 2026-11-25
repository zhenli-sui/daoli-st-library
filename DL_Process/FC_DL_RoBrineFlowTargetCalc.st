(*
  Name: FC_DL_RoBrineFlowTargetCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 按目标回收率反算浓水排放流量的前馈目标值：容积守恒下浓水 = 进水 × (1 − 回收率/100)。
           回收率是「产水占进水的百分比」，故 (1 − 回收率/100) 是「浓水占进水的比例」，
           两者互补且归一化到 0~1，方向固定不可交换（写反会把浓水目标算成产水目标）。
        2) 对反算结果做最小浓水流量下限保护：RO 膜必须维持最低浓水排放以带走盐分并维持横流，
           若反算值低于 fMinBrineFlowM3h，则输出被抬到该下限。此保护是设计动作而非故障，
           故不置 xValid=FALSE；下游若需判别是否被接管，可用
           fFeedFlowM3h × (1 − fTargetRecoveryPct/100) 回算后与 fBrineTargetM3h 比对。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fBrineTargetM3h 强制 0.0）并置无效（R19）。
        2) 进水流量零闸：ABS(fFeedFlowM3h) > DL_EPS 才允许相乘得到有意义的目标值，
           否则判无效；进水量为负同样判无效（不取 ABS 掩盖反向）。
        3) 目标回收率窄闸：须落在 0.0 ~ 99.99 % 的闭开区间内。回收率 = 100 % 时浓水目标为 0，
           与膜必须维持最小浓水流量的物理事实矛盾，故一律判无效而不输出 0。
        4) 最小浓水流量为负判无效（组态错误）；为 0 表示不设下限保护，属合法组态。
        5) 输出饱和钳制：fBrineTargetM3h 钳到 0 ~ DL_BIG，防极端进水流量导致溢出。
        6) 无回差环节：纯函数无状态，不做迟滞。
  量纲自证：fBrineTargetM3h = (m3/h) × (1 − %/100) = (m3/h) × [-] = m3/h；
           「回收率/100」是无因次归一比例，「1 − 比例」仍为无因次，量纲关系合法。
*)

FUNCTION FC_DL_RoBrineFlowTargetCalc : BOOL
VAR_INPUT
    fFeedFlowM3h        : REAL;   // 系统进水体积流量 [m3/h] / Feed volumetric flow [m3/h]
    fTargetRecoveryPct  : REAL;   // 目标回收率 [%] / Target recovery ratio [%]
    fMinBrineFlowM3h    : REAL;   // 最小浓水排放流量下限 [m3/h] / Minimum brine flow limit [m3/h]
END_VAR
VAR_OUTPUT
    fBrineTargetM3h     : REAL;   // 浓水排放流量目标值 [m3/h] / Brine flow target [m3/h]
    xValid              : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fBrineRatio        : REAL;   // 浓水占进水的归一比例 [-] / Brine fraction of feed [-]
    _fBrineRawM3h       : REAL;   // 下限保护前的浓水目标 [m3/h] / Brine target before floor [m3/h]
    _fBrineFloorM3h     : REAL;   // 下限保护后的浓水目标 [m3/h] / Brine target after floor [m3/h]
END_VAR
VAR CONSTANT
    DL_EPS              : REAL := 1.0E-9;   // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG              : REAL := 1.0E12;   // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT              : REAL := 100.0;    // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_REC_OPEN_HI_PCT  : REAL := 99.99;    // 回收率开区间上限 [%] / Recovery open upper bound [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不得乘进目标值） —— *)
IF NOT (fFeedFlowM3h > -DL_BIG AND fFeedFlowM3h < DL_BIG)
   OR NOT (fTargetRecoveryPct > -DL_BIG AND fTargetRecoveryPct < DL_BIG)
   OR NOT (fMinBrineFlowM3h > -DL_BIG AND fMinBrineFlowM3h < DL_BIG) THEN
    fBrineTargetM3h := 0.0;                 // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoBrineFlowTargetCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：进水零闸（R4：容积基准量为 0 则目标值无意义） —— *)
IF ABS(fFeedFlowM3h) <= DL_EPS THEN
    fBrineTargetM3h := 0.0;                 // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoBrineFlowTargetCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（R22 方向自核：1 − 回收率/100 是浓水比例，不是产水比例） —— *)
_fBrineRatio := 1.0 - fTargetRecoveryPct / DL_PCT;              // 浓水占比 [-]
_fBrineRawM3h := fFeedFlowM3h * _fBrineRatio;                   // 反算浓水目标 [m3/h]

(* —— 段 4：最小浓水流量下限保护（设计动作，抬高到下限，不判无效） —— *)
_fBrineFloorM3h := MAX(_fBrineRawM3h, fMinBrineFlowM3h);        // 取反算值与下限的较大者 [m3/h]

(* —— 段 5：有效位单点聚合（进水为正 + 回收率窄闸 + 下限组态合法） —— *)
xValid := (fFeedFlowM3h > DL_EPS)                               // 进水必须为正
          AND (fTargetRecoveryPct >= 0.0)                       // 回收率不越下限
          AND (fTargetRecoveryPct <= DL_REC_OPEN_HI_PCT)        // 回收率不得达 100 %
          AND (fMinBrineFlowM3h >= 0.0);                        // 最小浓水流量不得为负

(* —— 段 6：输出单点写盘（饱和钳制后写，禁同拍二次赋值） —— *)
fBrineTargetM3h := LIMIT(0.0, _fBrineFloorM3h, DL_BIG);         // 浓水目标钳 0..DL_BIG [m3/h]
FC_DL_RoBrineFlowTargetCalc := xValid;                          // 返回码：TRUE = 计算可信

END_FUNCTION
