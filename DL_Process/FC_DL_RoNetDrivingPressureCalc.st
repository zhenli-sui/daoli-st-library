(*
  Name: FC_DL_RoNetDrivingPressureCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 净驱动压按「推动水穿过膜的有效压差」计算，工程口径为
           NDP = (给水压力 + 浓水压力) / 2 − 渗透压 − 浓水侧流道压降。
           平均给水压取首末端两点的算术均值（膜元件内压力沿线近似线性下降），
           减渗透压扣除浓水侧的化学势反压，再减流道压降扣除沿程损失。
        2) NDP <= 0 表示驱动力消失，膜段无法产水（且存在浓差极化与结垢风险），
           判失效并输出 0.0，禁止输出负的驱动压给下游做乘法（会翻转通量符号）。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fNdpBar 强制 0.0）并置无效（R19）。
        2) 压力量程窄闸 0 ~ DL_P_BAR_MAX（0 ~ 120 bar）：单点越域判无效（变送器故障或超量程），
           越域值钳到量程边界后再参与运算，避免单点异常把 NDP 拉成极端值。
        3) 负压判定：任一路表压为负判无效（RO 系统不允许负压，负压意味着抽真空或量程零点漂移）。
        4) NDP <= 0 判无效并输出 0.0（驱动力消失，非数值问题而是工艺失效）。
        5) 无回差环节：纯函数无状态，迟滞由下游报警件承担。
  量纲自证：fNdpBar = (bar + bar)/2 − bar − bar = bar，四项全部为 bar，量纲一致；
           平均值为 (P_feed + P_conc) / 2，除数 2 是无因次算术平均点数，不引入量纲。
*)

FUNCTION FC_DL_RoNetDrivingPressureCalc : BOOL
VAR_INPUT
    fFeedBar          : REAL;   // 给水侧压力 [bar] / Feed side pressure [bar]
    fConcentrateBar   : REAL;   // 浓水侧压力 [bar] / Concentrate side pressure [bar]
    fOsmoticBar       : REAL;   // 渗透压（已按给水/浓水均值折算）[bar] / Osmotic pressure [bar]
    fChannelDropBar   : REAL;   // 浓水侧流道压降 [bar] / Concentrate channel pressure drop [bar]
END_VAR
VAR_OUTPUT
    fNdpBar           : REAL;   // 净驱动压 [bar] / Net driving pressure [bar]
    xValid            : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fFeedClampBar    : REAL;   // 钳制后的给水压力 [bar] / Clamped feed pressure [bar]
    _fConcClampBar    : REAL;   // 钳制后的浓水压力 [bar] / Clamped concentrate pressure [bar]
    _fOsmClampBar     : REAL;   // 钳制后的渗透压 [bar] / Clamped osmotic pressure [bar]
    _fDropClampBar    : REAL;   // 钳制后的流道压降 [bar] / Clamped channel pressure drop [bar]
    _fMeanFeedBar     : REAL;   // 首末端平均给水压力 [bar] / Mean feed pressure [bar]
    _fNdpRawBar       : REAL;   // 未饱和的原始净驱动压 [bar] / Raw NDP before limiting [bar]
END_VAR
VAR CONSTANT
    DL_EPS            : REAL := 1.0E-9;   // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG            : REAL := 1.0E12;   // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_P_BAR_MAX      : REAL := 120.0;    // 压力变送器量程上限 [bar] / Pressure transmitter span high [bar]
    DL_MEAN_POINTS    : REAL := 2.0;      // 平均给水压的取点数 [-] / Averaging point count [-]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fFeedBar > -DL_BIG AND fFeedBar < DL_BIG)
   OR NOT (fConcentrateBar > -DL_BIG AND fConcentrateBar < DL_BIG)
   OR NOT (fOsmoticBar > -DL_BIG AND fOsmoticBar < DL_BIG)
   OR NOT (fChannelDropBar > -DL_BIG AND fChannelDropBar < DL_BIG) THEN
    fNdpBar := 0.0;                         // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoNetDrivingPressureCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：负压闸（RO 系统不允许负表压：抽真空或零点漂移均为故障） —— *)
IF (fFeedBar < 0.0) OR (fConcentrateBar < 0.0) OR (fOsmoticBar < 0.0) OR (fChannelDropBar < 0.0) THEN
    fNdpBar := 0.0;                         // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoNetDrivingPressureCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：量程钳制（单点越量程钳到边界，避免异常点污染整式） —— *)
_fFeedClampBar := LIMIT(0.0, fFeedBar, DL_P_BAR_MAX);            // 给水压力钳 [bar]
_fConcClampBar := LIMIT(0.0, fConcentrateBar, DL_P_BAR_MAX);     // 浓水压力钳 [bar]
_fOsmClampBar := LIMIT(0.0, fOsmoticBar, DL_P_BAR_MAX);          // 渗透压钳 [bar]
_fDropClampBar := LIMIT(0.0, fChannelDropBar, DL_P_BAR_MAX);     // 流道压降钳 [bar]

(* —— 段 4：主算式（R22 方向自核：先平均值，再逐项扣减，扣减项全部为正相加） —— *)
_fMeanFeedBar := (_fFeedClampBar + _fConcClampBar) / DL_MEAN_POINTS;   // 算术均值 [bar]
_fNdpRawBar := _fMeanFeedBar - _fOsmClampBar - _fDropClampBar;         // 净驱动压 [bar]

(* —— 段 5：有效位单点聚合（量程 + 驱动力存在性） —— *)
xValid := (fFeedBar <= DL_P_BAR_MAX)                            // 给水不越量程
          AND (fConcentrateBar <= DL_P_BAR_MAX)                 // 浓水不越量程
          AND (fOsmoticBar <= DL_P_BAR_MAX)                     // 渗透压不越量程
          AND (fChannelDropBar <= DL_P_BAR_MAX)                 // 流道压降不越量程
          AND (_fNdpRawBar > 0.0);                              // 驱动力必须严格为正

(* —— 段 6：输出单点写盘（负值不得流出，否则下游乘法会翻转通量符号） —— *)
fNdpBar := MAX(0.0, _fNdpRawBar);                               // 净驱动压钳 >= 0 [bar]
FC_DL_RoNetDrivingPressureCalc := xValid;                       // 返回码：TRUE = 计算可信

END_FUNCTION
