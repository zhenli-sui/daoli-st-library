(*
  DL Factory R84 | FB_DL_ReactorRunawayGuard
  功能：间歇反应釜放热失控五级联锁：温升速率、绝热温升外推 MTSR、冷却能力失效三判据并行分档，合成 0~5 级动作需求；升级立即生效、降级按延时逐级回落，五级动作位互斥且可降级；L5 全停锁存至复位沿。
  开源溯源：无（clean-room 自研，依据公开工艺公式与安全设计惯例，来源=行业通用公式+工程实践，许可证=MIT，借鉴点=公式结构与联锁分层）
  规则：R1-R16 全遵守
  ------------------------------------------------------------------
  分类 DL_Process ｜ 复杂度 cx5 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（TON、R_TRIG、LREAL、ENUM、CASE）
  边界一：只出分级动作位与诊断量，不驱动泄放阀、冷却阀与投料阀本体，不采集变送器（属主边界，执行由下层 PRG 完成）。
  边界二：三判据分档——判据①温升速率按 fRateTripKmin 的 0.50/0.65/0.80/0.92/1.00 五档；判据②MTSR 按安全裕度 fMtsrMarginK 的已耗比例 0.50/0.35/0.20/0.08/0.00 五档；
          判据③冷却能力按流量下限与夹套-进水温差反向分 3 档与 4 档，温差反向且流量低于半限时直接判 5 档。
  边界三：MTSR 公式＝反应温度 ＋ 累积投料若全部反应的绝热温升：ΔTad [K]＝|ΔH| [kJ/mol] × 1000 [mol/kmol] × 累积摩尔数 [kmol] ÷（批量 [kg] × cp [kJ/(kg·K)]），
          累积摩尔数 [kmol]＝累积投料 [kg] ÷ 平均摩尔质量 [kg/kmol]；ΔTad 上限兜底 300 K 防外推发散。
  边界四：平均摩尔质量 DL_RAG_MOLAR_KGKMOL 为物料体系代理常量——代理值是反应主料的平均摩尔质量、覆盖 100~200 g/mol 的常规精细化工体系、
          体系外（聚合/无机盐）由上层以实测绝热温升标定后换算入参负责（R95 三句齐备，代理假设挂编译验证债）。
  边界五：分级互斥与可降级——iStage 为唯一权威（0~5 整数），五级位按 xStageN＝(iStage ≥ N) 单源派生；升级无延时（安全侧优先），
          降级由 tDegrade 周期窗逐级回落，窗为自复位形式（IN 串 NOT 自身 Q，R188），故不存在同拍双窗，R100 配比约束不适用（本件只有一件定时器）。
  边界六：相位由分级单源映射、零滞后（R191 名实同源），不设独立相位状态机与分级机双权威。
  安全侧：任一浮点入参非有限、组态越域、或任一判据达 5 档 → 立即迁 eTrip 并锁存 xTripLatched；锁存唯一解除路径为 bReset 上升沿（R188），其余路径（失能、条件消失）均不解锁。
  码表：故障级 2711 入参非有限、2712 组态越域、2713 温升速率达 5 档、2714 MTSR 达 5 档、2715 冷却完全失效、2716 非法分级值（防御性保留）；
        以上六码锁存回放且置 bError（R45 配对）；信息级 2701~2705＝当前分级（1~5 级）之动作码，每拍重算且不置 bError。
  输出契约：xStage1..xStage5 为累积电平（N 级生效则 1..N 位全真，互斥性由 iStage 单源保证）；xAlarmOut/xFeedStop/xMaxCool/xVentCmd/xTotalStop 与分级同源派生；
          fMtsrC/fRateKmin/fDtAdK 为诊断连续量，非有限时出零不外抛；xValid 在锁存或闸不过时为假。
  修订记录：2026-11-24 v1.0.0 R84 首版（批 R84 · 序号 42）
*)

TYPE E_DL_RagState :
(
    eNormal   := 0, // 正常：零级，无动作 / normal, level zero, no action
    eWarn     := 1, // 报警：一级，仅告知 / warn, level one, notification only
    eStopFeed := 2, // 停止投料：二级 / stop feeding, level two
    eMaxCool  := 3, // 加大冷却：三级 / maximum cooling, level three
    eVent     := 4, // 紧急泄放：四级 / emergency venting, level four
    eTrip     := 5  // 全停：五级，锁存至复位沿 / total trip, level five, latched until the reset edge
);
END_TYPE

TYPE E_DL_RagCause :
(
    eNone      := 0, // 无成因 / no cause
    eNotFinite := 1, // 入参非有限（故障级 2711）/ a non-finite input, fault grade 2711
    eCfgBad    := 2, // 组态越域（故障级 2712）/ the configuration is out of its domain, fault grade 2712
    eRateHigh  := 3, // 温升速率达五档（故障级 2713）/ the temperature rate reached level five, fault grade 2713
    eMtsrHigh  := 4, // MTSR 达五档（故障级 2714）/ the MTSR reached level five, fault grade 2714
    eCoolLoss  := 5, // 冷却完全失效（故障级 2715）/ the cooling capability was lost, fault grade 2715
    eStageBad  := 6  // 非法分级值（故障级 2716，防御性保留）/ an illegal stage value, fault grade 2716
);
END_TYPE

FUNCTION_BLOCK FB_DL_ReactorRunawayGuard
VAR CONSTANT
    DL_RAG_SEC_MIN     : LREAL := 60.0;    // 秒到分钟折算系数 [s/min] / the second to minute factor [s/min]
    DL_RAG_DT_MIN      : LREAL := 0.001;   // 采样周期下限（速率分母零闸）[s] / the sample period lower bound [s]
    DL_RAG_RATE_ALPHA  : LREAL := 0.30;    // 速率一阶滤波系数 [-] / the first order gain of the rate filter [-]
    DL_RAG_L1_FRAC     : LREAL := 0.50;    // 判据①一级档位系数（跳闸速率的倍数）[-] / the level one factor of the rate criterion [-]
    DL_RAG_L2_FRAC     : LREAL := 0.65;    // 判据①二级档位系数 [-] / the level two factor of the rate criterion [-]
    DL_RAG_L3_FRAC     : LREAL := 0.80;    // 判据①三级档位系数 [-] / the level three factor of the rate criterion [-]
    DL_RAG_L4_FRAC     : LREAL := 0.92;    // 判据①四级档位系数 [-] / the level four factor of the rate criterion [-]
    DL_RAG_M1_FRAC     : LREAL := 0.50;    // 判据②一级档位（裕度已耗比例）[-] / the level one factor of the MTSR criterion [-]
    DL_RAG_M2_FRAC     : LREAL := 0.35;    // 判据②二级档位 [-] / the level two factor of the MTSR criterion [-]
    DL_RAG_M3_FRAC     : LREAL := 0.20;    // 判据②三级档位 [-] / the level three factor of the MTSR criterion [-]
    DL_RAG_M4_FRAC     : LREAL := 0.08;    // 判据②四级档位 [-] / the level four factor of the MTSR criterion [-]
    DL_RAG_COOL_DT_MIN : LREAL := 2.0;     // 夹套与进水温差下限（低于即冷却不足）[K] / the jacket to inlet temperature difference floor [K]
    DL_RAG_FLOW_L4_FRAC: LREAL := 0.50;    // 判据③四级档位流量系数（下限倍数）[-] / the level four flow factor of the cooling criterion [-]
    DL_RAG_DTAD_MAX    : LREAL := 300.0;   // 绝热温升外推上限兜底 [K] / the adiabatic rise extrapolation upper clamp [K]
    DL_RAG_FRAC_MAX    : LREAL := 1.50;    // 已投料占比上限（外推兜底）[-] / the charged fraction upper clamp [-]
    DL_RAG_MOLAR_KGKMOL: LREAL := 100.0;   // 平均摩尔质量代理常量 [kg/kmol] / the mean molar mass proxy [kg/kmol]
    DL_RAG_MOL_PER_KMOL: LREAL := 1000.0;  // 摩尔到千摩尔折算系数 [mol/kmol] / the mole to kilomole factor [mol/kmol]
    DL_RAG_EPS         : LREAL := 1.0E-9;  // 除法零闸与零判定门限 [-] / the division guard and zero test threshold [-]
END_VAR
VAR_INPUT
    bEnable      : BOOL := TRUE;     // 使能，失能只回零级不解除锁存 [-] / enable, a disable only clears the stage and never the latch
    bReset       : BOOL := FALSE;   // 复位上升沿清全停锁存（唯一解除路径）[-] / reset rising edge clears the trip latch, the only release path
    xStirRun     : BOOL := TRUE;    // 搅拌运行反馈，停搅即二级以上 [-] / the agitator running feedback, a stop forces level two or higher
    fTreactC     : LREAL := 25.0;   // 反应温度 [°C] / the reaction temperature [°C]
    fTjacketC    : LREAL := 25.0;   // 夹套温度 [°C] / the jacket temperature [°C]
    fCoolFlowM3h : LREAL := 10.0;   // 冷却水流量 [m³/h] / the cooling water flow [m3/h]
    fCoolInC     : LREAL := 20.0;   // 冷却水进水温度 [°C] / the cooling water inlet temperature [°C]
    fAccumKg     : LREAL := 0.0;    // 累积投料质量（尚未反应部分）[kg] / the accumulated charged mass still unreacted [kg]
    fBatchKg     : LREAL := 1000.0; // 批量总质量 [kg] / the total batch mass [kg]
    fDhKjMol     : LREAL := 80.0;   // 反应焓变（取绝对值参与外推）[kJ/mol] / the reaction enthalpy, the absolute value is used [kJ/mol]
    fCpKjKgK     : LREAL := 3.50;   // 反应液比热容 [kJ/(kg·K)] / the reaction mixture specific heat [kJ/(kg*K)]
    fRateTripKmin: LREAL := 3.00;   // 温升速率跳闸值（五档基准）[K/min] / the rate trip value, the level five base [K/min]
    fMtsrLimitC  : LREAL := 180.0;  // MTSR 安全极限温度 [°C] / the MTSR safety limit temperature [°C]
    fMtsrMarginK : LREAL := 20.0;   // MTSR 安全裕度（分级带宽）[K] / the MTSR safety margin, the staging band [K]
    fFlowMinM3h  : LREAL := 4.00;   // 冷却水流量下限 [m³/h] / the cooling water flow floor [m3/h]
    fDtSec       : LREAL := 0.10;   // 温度采样周期（速率分母）[s] / the temperature sample period, the rate denominator [s]
    tDegrade     : TIME := T#30S;   // 分级降级延时（逐级回落窗）[毫秒] / the stage downgrade delay per step [ms]
END_VAR
VAR_OUTPUT
    eState       : E_DL_RagState := E_DL_RagState.eNormal; // 相位出口（由分级单源映射）[枚举] / the phase outlet mapped from the stage [enum]
    iStage       : INT := 0;      // 当前动作级（0~5，唯一权威）[级] / the active stage, the single authority [level]
    iErrCode     : INT := 0;      // 错误码（故障级锁存回放，信息级每拍重算）[码] / the error code, latched faults and scan info [code]
    bError       : BOOL := FALSE; // 故障标志（与故障级码同源）[-] / the fault flag sharing the fault code source
    xTripLatched : BOOL := FALSE; // 全停锁存（仅复位沿清除）[-] / the trip latch, cleared by the reset edge only
    xValid       : BOOL := FALSE; // 本拍输入与组态可信 [-] / the inputs and the configuration are trustworthy
    xStage1      : BOOL := FALSE; // 一级动作位：报警 [-] / level one action, the alarm
    xStage2      : BOOL := FALSE; // 二级动作位：停止投料 [-] / level two action, stop the feed
    xStage3      : BOOL := FALSE; // 三级动作位：加大冷却 [-] / level three action, maximum cooling
    xStage4      : BOOL := FALSE; // 四级动作位：紧急泄放 [-] / level four action, emergency venting
    xStage5      : BOOL := FALSE; // 五级动作位：全停 [-] / level five action, total trip
    xAlarmOut    : BOOL := FALSE; // 报警输出（一级及以上）[-] / the alarm output from level one on
    xFeedStop    : BOOL := FALSE; // 停止投料输出（二级及以上）[-] / the feed stop output from level two on
    xMaxCool     : BOOL := FALSE; // 加大冷却输出（三级及以上）[-] / the maximum cooling output from level three on
    xVentCmd     : BOOL := FALSE; // 紧急泄放输出（四级及以上）[-] / the emergency vent output from level four on
    xTotalStop   : BOOL := FALSE; // 全停输出（五级）[-] / the total stop output at level five
    fMtsrC       : LREAL := 0.0;  // MTSR 外推值 [°C] / the extrapolated MTSR [°C]
    fRateKmin    : LREAL := 0.0;  // 滤波后温升速率 [K/min] / the filtered temperature rise rate [K/min]
    fDtAdK       : LREAL := 0.0;  // 绝热温升外推量 [K] / the adiabatic rise extrapolation [K]
END_VAR
VAR
    rtReset    : R_TRIG; // 复位沿实例（无量纲）[-] / the reset edge refreshed unconditionally
    tonDown    : TON;    // 降级窗实例（无量纲）[-] / the self resetting downgrade window, its own output inverted
    _eState    : E_DL_RagState := E_DL_RagState.eNormal; // 内部相位（枚举，无量纲）[-] / the internal phase
    _eCause    : E_DL_RagCause := E_DL_RagCause.eNone; // 故障级成因（枚举，无量纲）[-] / the fault cause latched until the reset edge
    _iStage    : INT := 0;  // 内部分级（唯一权威）[级] / the internal stage, the single authority [level]
    _iReq      : INT := 0;  // 三判据合成后的动作需求级 [级] / the aggregated stage demand [level]
    _iNeed     : INT := 0;  // 单判据档位暂存 [级] / the per criterion stage scratch [level]
    _iErrTmp   : INT := 0;  // 本拍码位暂存 [码] / the scan code scratch [code]
    _iErrLch   : INT := 0;  // 故障级码位锁存槽 [码] / the latched fault code [code]
    _bTrip     : BOOL := FALSE; // 全停锁存位 [-] / the trip latch
    _bInit     : BOOL := FALSE; // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag
    _bFinOk    : BOOL := FALSE; // 全部浮点入参有限 [-] / every floating input is finite
    _bCfgOk    : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside its domain
    _bRateL5   : BOOL := FALSE; // 判据①达五档（独立成因标志，R190）[-] / criterion one reached level five
    _bMtsrL5   : BOOL := FALSE; // 判据②达五档（独立成因标志）[-] / criterion two reached level five
    _bCoolL5   : BOOL := FALSE; // 判据③冷却完全失效（独立成因标志）[-] / criterion three lost the cooling entirely
    _bRateL1   : BOOL := FALSE; // 判据①达一档 [-] / criterion one reached level one
    _bRateL2   : BOOL := FALSE; // 判据①达二档 [-] / criterion one reached level two
    _bRateL3   : BOOL := FALSE; // 判据①达三档 [-] / criterion one reached level three
    _bRateL4   : BOOL := FALSE; // 判据①达四档 [-] / criterion one reached level four
    _fTprev    : LREAL := 0.0;  // 上拍反应温度快照（差分用）[°C] / the previous scan temperature snapshot [°C]
    _fRateRaw  : LREAL := 0.0;  // 原始温升速率（差分值）[K/min] / the raw temperature rise rate [K/min]
    _fRateFilt : LREAL := 0.0;  // 滤波后温升速率（保持槽）[K/min] / the filtered rate, a hold slot [K/min]
    _fFrac     : LREAL := 0.0;  // 累积投料占批量比（钳定后）[-] / the charged fraction after clamping [-]
    _fMoles    : LREAL := 0.0;  // 累积投料摩尔数 [kmol] / the accumulated moles [kmol]
    _fHeatKj   : LREAL := 0.0;  // 累积物料若全部反应放热 [kJ] / the heat if all charged mass reacted [kJ]
    _fDtAd     : LREAL := 0.0;  // 绝热温升外推量（钳定后）[K] / the adiabatic rise after clamping [K]
    _fMtsr     : LREAL := 0.0;  // MTSR 外推温度 [°C] / the extrapolated MTSR [°C]
    _fCoolDt   : LREAL := 0.0;  // 夹套与冷却水进水温差 [K] / the jacket to inlet difference [K]
    _fRateThr1 : LREAL := 0.0;  // 判据①一档门限 [K/min] / the level one rate threshold [K/min]
    _fRateThr2 : LREAL := 0.0;  // 判据①二档门限 [K/min] / the level two rate threshold [K/min]
    _fRateThr3 : LREAL := 0.0;  // 判据①三档门限 [K/min] / the level three rate threshold [K/min]
    _fRateThr4 : LREAL := 0.0;  // 判据①四档门限 [K/min] / the level four rate threshold [K/min]
    _fMtsrThr1 : LREAL := 0.0;  // 判据②一档门限 [°C] / the level one MTSR threshold [°C]
    _fMtsrThr2 : LREAL := 0.0;  // 判据②二档门限 [°C] / the level two MTSR threshold [°C]
    _fMtsrThr3 : LREAL := 0.0;  // 判据②三档门限 [°C] / the level three MTSR threshold [°C]
    _fMtsrThr4 : LREAL := 0.0;  // 判据②四档门限 [°C] / the level four MTSR threshold [°C]
    _tDegrade  : TIME := T#1S;  // 降级窗实参（钳定后）[毫秒] / the downgrade window passed to the timer [ms]
END_VAR
// 段 0｜出口预置：全部出口先赋安全侧值，任何路径不留未初始化输出（安全侧＝全停动作位）/
xValid := FALSE; // 有效性预置假 / validity preset false
xStage1 := FALSE; xStage2 := FALSE; xStage3 := FALSE; // 一至三级位预置假 / levels one to three preset false
xStage4 := FALSE; xStage5 := FALSE; // 四至五级位预置假 / levels four and five preset false
xAlarmOut := FALSE; xFeedStop := FALSE; xMaxCool := FALSE; xVentCmd := FALSE; xTotalStop := FALSE; // 五个动作输出预置假 / the five action outputs preset false
xTripLatched := _bTrip; // 全停锁存回放 / replay the trip latch
iStage := 0; // 分级预置零级，段 11 单点覆盖 / the stage preset zero and overwritten at the outlet
iErrCode := 0; // 码位预置零 / the code preset zero
bError := FALSE; // 故障标志预置假 / the fault flag preset false
fMtsrC := 0.0; fRateKmin := 0.0; fDtAdK := 0.0; // 三个连续量出口预置零 / the three continuous outlets preset zero
eState := E_DL_RagState.eNormal; // 相位预置正常相 / the phase preset normal
_iErrTmp := 0; _iNeed := 0; _iReq := 0; // 单拍暂存预清零（FB32-1：仅单拍变量可预清）/ preclear the scan scratches only
// 段 1｜非有限闸：NaN 自反比较、Inf 差值自减双判，逐项枚举十个浮点入参与两个换算量（R79、R272）
_bFinOk := (fTreactC = fTreactC) AND ((fTreactC - fTreactC) = (fTreactC - fTreactC)) // 反应温度有限 [-] / the reaction temperature is finite
    AND (fTjacketC = fTjacketC) AND ((fTjacketC - fTjacketC) = (fTjacketC - fTjacketC)) // 夹套温度有限 [-] / the jacket temperature is finite
    AND (fCoolFlowM3h = fCoolFlowM3h) AND ((fCoolFlowM3h - fCoolFlowM3h) = (fCoolFlowM3h - fCoolFlowM3h)) // 冷却流量有限 [-] / the cooling flow is finite
    AND (fCoolInC = fCoolInC) AND ((fCoolInC - fCoolInC) = (fCoolInC - fCoolInC)) // 进水温度有限 [-] / the inlet temperature is finite
    AND (fAccumKg = fAccumKg) AND ((fAccumKg - fAccumKg) = (fAccumKg - fAccumKg)) // 累积投料有限 [-] / the accumulated mass is finite
    AND (fBatchKg = fBatchKg) AND ((fBatchKg - fBatchKg) = (fBatchKg - fBatchKg)) // 批量有限 [-] / the batch mass is finite
    AND (fDhKjMol = fDhKjMol) AND ((fDhKjMol - fDhKjMol) = (fDhKjMol - fDhKjMol)) // 焓变有限 [-] / the enthalpy is finite
    AND (fCpKjKgK = fCpKjKgK) AND ((fCpKjKgK - fCpKjKgK) = (fCpKjKgK - fCpKjKgK)) // 比热容有限 [-] / the specific heat is finite
    AND (fRateTripKmin = fRateTripKmin) AND ((fRateTripKmin - fRateTripKmin) = (fRateTripKmin - fRateTripKmin)) // 速率跳闸值有限 [-] / the rate trip value is finite
    AND (fMtsrLimitC = fMtsrLimitC) AND ((fMtsrLimitC - fMtsrLimitC) = (fMtsrLimitC - fMtsrLimitC)) // MTSR 极限有限 [-] / the MTSR limit is finite
    AND (fMtsrMarginK = fMtsrMarginK) AND ((fMtsrMarginK - fMtsrMarginK) = (fMtsrMarginK - fMtsrMarginK)) // 裕度有限 [-] / the margin is finite
    AND (fFlowMinM3h = fFlowMinM3h) AND ((fFlowMinM3h - fFlowMinM3h) = (fFlowMinM3h - fFlowMinM3h)) // 流量下限有限 [-] / the flow floor is finite
    AND (fDtSec = fDtSec) AND ((fDtSec - fDtSec) = (fDtSec - fDtSec)); // 采样周期有限 [-] / the sample period is finite
// 段 2｜组态域闸：全部参与判据换算的限值引脚（R151、FB51-2）
_bCfgOk := (ABS(fRateTripKmin) > DL_RAG_EPS) AND (fMtsrMarginK > DL_RAG_EPS) // 速率跳闸值与裕度非零 [-] / the rate trip and the margin are non zero
    AND (ABS(fFlowMinM3h) > DL_RAG_EPS) AND (fBatchKg > DL_RAG_EPS) // 流量下限与批量非零 [-] / the flow floor and the batch are non zero
    AND (fCpKjKgK > DL_RAG_EPS) AND (fDtSec > DL_RAG_DT_MIN) // 比热容与采样周期域闸 [-] / the specific heat and the sample period gates
    AND (fMtsrLimitC > DL_RAG_EPS) AND (tDegrade > T#0S); // MTSR 极限与降级窗域闸 [-] / the MTSR limit and the window gates
_tDegrade := tDegrade; // 降级窗一级回退：取引脚值 [ms] / level one fallback, take the pin value [ms]
IF _tDegrade <= T#0S THEN _tDegrade := T#1S; END_IF // 降级窗二级回退：按有效域钳定（最小一窗）/ level two, clamp into the valid domain
// 段 3｜首扫初始化与复位沿同块，作用域逐项声明（R310、R311、R152）
IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位沿 / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志（复位沿重复置位同效）/ the first scan flag, the same effect on reset
    _bTrip := FALSE; _eCause := E_DL_RagCause.eNone; _iErrLch := 0; // 作用域一：清全停锁存、清成因、清故障码槽 / scope one, clear the latch, the cause and the fault code
    _iStage := 0; _iReq := 0; // 作用域二：分级回零级 / scope two, the stage returns to zero
    _eState := E_DL_RagState.eNormal; // 作用域二：迁回正常相 / scope two, migrate to normal
    _fTprev := fTreactC; // 作用域三：温度快照重取（首拍不产生假速率）/ scope three, re-take the snapshot
    _fRateFilt := 0.0; // 作用域三：清速率滤波保持槽 / scope three, clear the rate filter hold slot
END_IF
// 段 4｜定时器与沿检测无条件周期刷新（R7），降级窗自复位（R188）
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonDown(IN := (_iReq < _iStage) AND (NOT _bTrip) AND (NOT tonDown.Q), PT := _tDegrade); // 降级窗：需求低于当前级才计时，到期自复位 / the downgrade window with its own output inverted
// 段 5｜判据①温升速率：一阶差分 + 一阶指数滤波，分母零闸后计算（R4、R45 ②）
IF fDtSec > DL_RAG_DT_MIN THEN // 分母零闸 / the denominator gate
    _fRateRaw := (fTreactC - _fTprev) * DL_RAG_SEC_MIN / fDtSec; // 原始速率 [K/min] / the raw rate [K/min]
ELSE // 采样周期非法 / an illegal sample period
    _fRateRaw := 0.0; // 速率出零（不外推）/ the rate goes to zero
END_IF
IF NOT (_fRateRaw = _fRateRaw) THEN _fRateRaw := 0.0; END_IF // 速率 NaN 兜底 / the NaN fallback
IF (_fRateRaw - _fRateRaw) <> (_fRateRaw - _fRateRaw) THEN _fRateRaw := 0.0; END_IF // 速率 Inf 兜底 / the Inf fallback
_fTprev := fTreactC; // 上拍温度快照（差分用，用完立即赋值）/ the snapshot taken right after the difference
_fRateFilt := _fRateFilt + DL_RAG_RATE_ALPHA * (_fRateRaw - _fRateFilt); // 一阶指数滤波 [K/min] / the first order exponential filter [K/min]
IF NOT (_fRateFilt = _fRateFilt) THEN _fRateFilt := _fRateRaw; END_IF // 滤波结果 NaN 兜底 / the NaN fallback
IF (_fRateFilt - _fRateFilt) <> (_fRateFilt - _fRateFilt) THEN _fRateFilt := _fRateRaw; END_IF // 滤波结果 Inf 兜底 / the Inf fallback
// 段 6｜判据②绝热温升外推 MTSR：分母双零闸，外推上限兜底防发散（R4、R133）
IF (fBatchKg > DL_RAG_EPS) AND (fCpKjKgK > DL_RAG_EPS) THEN // 双分母零闸 / both denominators guarded
    _fFrac := fAccumKg / fBatchKg; // 已投料占比 [-] / the charged fraction [-]
    IF _fFrac < 0.0 THEN _fFrac := 0.0; ELSIF _fFrac > DL_RAG_FRAC_MAX THEN _fFrac := DL_RAG_FRAC_MAX; END_IF // 占比双向夹取 / clamp the fraction both ways
    _fMoles := fAccumKg / DL_RAG_MOLAR_KGKMOL; // 累积摩尔数 [kmol] / the accumulated moles [kmol]
    _fHeatKj := ABS(fDhKjMol) * DL_RAG_MOL_PER_KMOL * _fMoles; // 潜在放热量 [kJ] / the potential heat [kJ]
    _fDtAd := _fHeatKj / (fBatchKg * fCpKjKgK); // 绝热温升 [K] / the adiabatic rise [K]
    IF _fDtAd < 0.0 THEN _fDtAd := 0.0; ELSIF _fDtAd > DL_RAG_DTAD_MAX THEN _fDtAd := DL_RAG_DTAD_MAX; END_IF // 外推上限兜底 [K] / the extrapolation clamp [K]
ELSE // 组态越域 / the configuration is out of domain
    _fDtAd := 0.0; // 温升外推出零（不放大风险）/ the rise goes to zero and never inflates the risk
END_IF
_fMtsr := fTreactC + _fDtAd; // MTSR [°C] / the MTSR [°C]
// 段 7｜判据③冷却能力：温差与流量双源，温差反向加流量半限判完全失效
_fCoolDt := fTjacketC - fCoolInC; // 夹套与进水温差 [K] / the jacket to inlet difference [K]
_bCoolL5 := (_fCoolDt < 0.0) AND (fCoolFlowM3h < (fFlowMinM3h * DL_RAG_FLOW_L4_FRAC)); // 温差反向且流量低于半限＝冷却完全失效 / a reversed difference with less than half flow means no cooling
// 段 8｜三判据分档：逐判据独立档位与独立标志，成因不共用（R190）
_fRateThr1 := fRateTripKmin * DL_RAG_L1_FRAC; // 一档门限 [K/min] / the level one threshold [K/min]
_fRateThr2 := fRateTripKmin * DL_RAG_L2_FRAC; // 二档门限 [K/min] / the level two threshold [K/min]
_fRateThr3 := fRateTripKmin * DL_RAG_L3_FRAC; // 三档门限 [K/min] / the level three threshold [K/min]
_fRateThr4 := fRateTripKmin * DL_RAG_L4_FRAC; // 四档门限 [K/min] / the level four threshold [K/min]
_fMtsrThr1 := fMtsrLimitC - (fMtsrMarginK * DL_RAG_M1_FRAC); // 一档门限 [°C] / the level one threshold [°C]
_fMtsrThr2 := fMtsrLimitC - (fMtsrMarginK * DL_RAG_M2_FRAC); // 二档门限 [°C] / the level two threshold [°C]
_fMtsrThr3 := fMtsrLimitC - (fMtsrMarginK * DL_RAG_M3_FRAC); // 三档门限 [°C] / the level three threshold [°C]
_fMtsrThr4 := fMtsrLimitC - (fMtsrMarginK * DL_RAG_M4_FRAC); // 四档门限 [°C] / the level four threshold [°C]
_bRateL1 := _fRateFilt > _fRateThr1; // 判据①达一档 / criterion one at level one
_bRateL2 := _fRateFilt > _fRateThr2; // 判据①达二档 / criterion one at level two
_bRateL3 := _fRateFilt > _fRateThr3; // 判据①达三档 / criterion one at level three
_bRateL4 := _fRateFilt > _fRateThr4; // 判据①达四档 / criterion one at level four
_bRateL5 := _fRateFilt > fRateTripKmin; // 判据①达五档（独立成因标志）/ criterion one at level five
_iNeed := 0; // 判据①档位暂存清零 / clear the criterion one scratch
IF _bRateL5 THEN _iNeed := 5; ELSIF _bRateL4 THEN _iNeed := 4; ELSIF _bRateL3 THEN _iNeed := 3; ELSIF _bRateL2 THEN _iNeed := 2; ELSIF _bRateL1 THEN _iNeed := 1; END_IF // 判据①档位 / the criterion one level
IF _iNeed > _iReq THEN _iReq := _iNeed; END_IF // 合成取大 / aggregate by the maximum
_iNeed := 0; // 判据②档位暂存清零 / clear the criterion two scratch
IF _fMtsr > fMtsrLimitC THEN _iNeed := 5; // 判据②五档：超安全极限 / level five, the safety limit was passed
ELSIF _fMtsr > _fMtsrThr4 THEN _iNeed := 4; ELSIF _fMtsr > _fMtsrThr3 THEN _iNeed := 3; ELSIF _fMtsr > _fMtsrThr2 THEN _iNeed := 2; ELSIF _fMtsr > _fMtsrThr1 THEN _iNeed := 1; END_IF // 判据②一至四档 / the criterion two levels one to four
IF _iNeed > _iReq THEN _iReq := _iNeed; END_IF // 合成取大 / aggregate by the maximum
_iNeed := 0; // 判据③档位暂存清零 / clear the criterion three scratch
IF _bCoolL5 THEN // 冷却完全失效：直接五档（独立成因）/ a total cooling loss goes straight to level five
    _iNeed := 5; // 判据③五档 / criterion three at level five
ELSIF (_fCoolDt < 0.0) OR (fCoolFlowM3h < (fFlowMinM3h * DL_RAG_FLOW_L4_FRAC)) THEN // 温差反向或流量低于半限 / a reversed difference or less than half flow
    _iNeed := 4; // 判据③四档 / criterion three at level four
ELSIF (_fCoolDt < DL_RAG_COOL_DT_MIN) OR (fCoolFlowM3h < fFlowMinM3h) THEN // 温差不足或流量低于下限 / an insufficient difference or a flow below the floor
    _iNeed := 3; // 判据③三档 / criterion three at level three
END_IF
IF _iNeed > _iReq THEN _iReq := _iNeed; END_IF // 合成取大 / aggregate by the maximum
IF NOT xStirRun THEN // 搅拌停止：至少二级（独立于冷却与温度判据）/ a stopped agitator forces level two
    IF _iReq < 2 THEN _iReq := 2; END_IF // 二级下限 / the level two floor
END_IF
IF NOT bEnable THEN _iReq := 0; END_IF // 失能只清需求级，不解除全停锁存（R191 边界六）/ a disable clears the demand and never the latch
// 段 9｜故障锁存：每个成因独立枚举成员与独立码值，命中即置 bError 并同拍锁存（R45、R190）
IF NOT _bTrip THEN // 未锁存才判（锁存后一律回放，R152）/ judge only while unlatched
    IF NOT _bFinOk THEN // 入参非有限 / a non-finite input
        _eCause := E_DL_RagCause.eNotFinite; _iErrTmp := 2711; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF NOT _bCfgOk THEN // 组态越域 / the configuration is out of domain
        _eCause := E_DL_RagCause.eCfgBad; _iErrTmp := 2712; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF _bRateL5 THEN // 温升速率达五档 / the rate reached level five
        _eCause := E_DL_RagCause.eRateHigh; _iErrTmp := 2713; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF _fMtsr > fMtsrLimitC THEN // MTSR 达五档 / the MTSR reached level five
        _eCause := E_DL_RagCause.eMtsrHigh; _iErrTmp := 2714; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF _bCoolL5 THEN // 冷却完全失效 / the cooling was lost entirely
        _eCause := E_DL_RagCause.eCoolLoss; _iErrTmp := 2715; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    END_IF
    IF _iErrTmp <> 0 THEN // 存在故障级请求 / a fault grade request exists
        _iErrLch := _iErrTmp; _bTrip := TRUE; // 锁存码与锁存位单点写入 / the single write point of the code and the latch
    END_IF
END_IF
// 段 10｜分级仲裁：升级立即（安全侧优先）、降级按窗逐级（不跳级、不抖动）
IF _bTrip THEN // 已锁存 / already latched
    _iStage := 5; // 强制五级（锁存期内不降级）/ forced to level five while latched
ELSIF _iReq > _iStage THEN // 需求高于当前级：立即升级 / immediate escalation
    _iStage := _iReq; // 升级无延时（安全侧优先）/ escalation without delay
ELSIF (_iReq < _iStage) AND tonDown.Q THEN // 需求低于当前级且降级窗到期 / the demand is lower and the window expired
    _iStage := _iStage - 1; // 逐级降一级（每窗一级，禁跳级）/ one step per window
END_IF
IF _iStage < 0 THEN _iStage := 0; ELSIF _iStage > 5 THEN _iStage := 5; END_IF // 分级域夹取（防御性）/ clamp the stage domain
// 段 11｜相位映射：由分级单源映射、零滞后（R191），ELSE 落全停（R6）
CASE _iStage OF // 分级唯一权威 → 相位 / the single stage authority drives the phase
0: _eState := E_DL_RagState.eNormal; // 零级：正常 / level zero maps to normal
1: _eState := E_DL_RagState.eWarn; // 一级：报警 / level one maps to warn
2: _eState := E_DL_RagState.eStopFeed; // 二级：停止投料 / level two maps to stop feed
3: _eState := E_DL_RagState.eMaxCool; // 三级：加大冷却 / level three maps to maximum cooling
4: _eState := E_DL_RagState.eVent; // 四级：紧急泄放 / level four maps to venting
5: _eState := E_DL_RagState.eTrip; // 五级：全停 / level five maps to trip
ELSE // 非法分级值兜底（值域已夹取，防御性保留，R6、R128）
    _eState := E_DL_RagState.eTrip; // 落全停安全相 / fall back to the trip phase
    IF NOT _bTrip THEN // 未锁存才补锁存 / latch only while unlatched
        _eCause := E_DL_RagCause.eStageBad; _iErrLch := 2716; _bTrip := TRUE; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    END_IF
END_CASE
// 段 12｜统一出口：分级与五级位单源派生，连续量做非有限防护（R191、FB51-3）
iStage := _iStage; // 分级单点映射 / the single point mapping of the stage
xStage1 := _iStage >= 1; xStage2 := _iStage >= 2; xStage3 := _iStage >= 3; // 一至三级位（累积电平）/ levels one to three as accumulated levels
xStage4 := _iStage >= 4; xStage5 := _iStage >= 5; // 四至五级位（累积电平）/ levels four and five as accumulated levels
xAlarmOut := _iStage >= 1; xFeedStop := _iStage >= 2; xMaxCool := _iStage >= 3; // 一至三级动作输出 / the action outputs of levels one to three
xVentCmd := _iStage >= 4; xTotalStop := _iStage >= 5; // 四至五级动作输出 / the action outputs of levels four and five
xTripLatched := _bTrip; // 全停锁存回放 / replay the trip latch
eState := _eState; // 相位单点映射 / the single point mapping of the phase
fMtsrC := _fMtsr; // MTSR 单点映射 [°C] / the single point mapping of the MTSR [°C]
IF NOT (_fMtsr = _fMtsr) THEN fMtsrC := 0.0; END_IF // 出口 NaN 防护（安全侧出零）/ the NaN guard on the outlet
IF (_fMtsr - _fMtsr) <> (_fMtsr - _fMtsr) THEN fMtsrC := 0.0; END_IF // 出口 Inf 防护 / the Inf guard on the outlet
fRateKmin := _fRateFilt; // 速率单点映射 [K/min] / the single point mapping of the rate [K/min]
IF NOT (_fRateFilt = _fRateFilt) THEN fRateKmin := 0.0; END_IF // 出口 NaN 防护 / the NaN guard on the outlet
IF (_fRateFilt - _fRateFilt) <> (_fRateFilt - _fRateFilt) THEN fRateKmin := 0.0; END_IF // 出口 Inf 防护 / the Inf guard on the outlet
fDtAdK := _fDtAd; // 绝热温升单点映射 [K] / the single point mapping of the adiabatic rise [K]
xValid := _bFinOk AND _bCfgOk AND (NOT _bTrip); // 有效性：双闸通过且未锁存 / valid when both gates pass and nothing is latched
IF _bTrip THEN // 锁存期：故障级码回放，不按当下输入重推（R152）
    iErrCode := _iErrLch; bError := TRUE; // 锁存码回放、故障标志同源 / replay the code and share the latch source
ELSIF _iStage > 0 THEN // 未锁存但分级非零 / unlatched but a stage is active
    iErrCode := 2700 + _iStage; bError := FALSE; // 信息级动作码（每拍重算，不置故障标志，R45）/ the info action code without the fault flag
ELSE // 零级且未锁存 / level zero and unlatched
    iErrCode := 0; bError := FALSE; // 无码无标志 / no code and no flag
END_IF
END_FUNCTION_BLOCK
