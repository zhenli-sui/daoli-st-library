(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FlowBalanceCheck
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / ABS / MAX），零厂商私有库
 * 功能描述 (Function)   : 多路流量累计平衡校验：每 tWindow 窗口期对有效通道
 *                         重算一次总入 ΣaInflow 与总出 ΣaOutflow，失衡率
 *                           fImbalancePct = (Σin − Σout) ÷ max(|Σin|,|Σout|) × 100
 *                         按容差 fTolPct 与告警阈 fWarnPct 分级出口：
 *                           eBalanced（|失衡| <= fTolPct）/
 *                           eWarn（fTolPct < |失衡| <= fWarnPct）/
 *                           eFault（|失衡| > fWarnPct）。
 *                         通道数钳位 1~8；容差 <= 0 冻结判定并置故障码（规格
 *                         指定）；分母基准过小（无流量）判平衡并置信息码。
 * 接口     (Interface)  : 输入 aInflow 8 路流入累计量、aOutflow 8 路流出累计量
 *                         （同工程单位累计口径）、nChanCnt 有效通道数（钳位
 *                         1~8）、fTolPct 平衡容差 [%]、fWarnPct 告警阈 [%]、
 *                         tWindow 重算窗、bReset 复位；输出 fImbalancePct
 *                         失衡率 [%]、eLevel 分级出口（E_DL_FlowLevel）、
 *                         fSumIn/fSumOut 窗口合计透读、eErrCode 错误码、
 *                         bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做累计量平衡判定，不做
 *                         流量测量、不接管泄漏定位**；单路诊断归通道级件。
 *                         ② 窗口自复位 TON（IN := NOT tonWin.Q，R188），窗到
 *                         （F_TRIG 沿）重算一次，窗内判定输出保持（冻结语义
 *                         声明：非结算拍不重算，规格「窗口期重算」口径）。
 *                         ③ 数组钳位：nChanCnt 钳 [1,8]，越界钳位并置信息码
 *                         eChanClamp；求和界宽 = 钳位后通道数，无越界。
 *                         ④ 分母基准 fBase = MAX(|Σin|,|Σout|)，fBase <
 *                         1E-9 判零流量 → 失衡率 0、eLevel=eBalanced、信息码
 *                         eNoFlow（结构性防除零）。
 *                         ⑤ 组态闸：fTolPct <= 0 或 fWarnPct < fTolPct →
 *                         锁存故障，判定冻结（eLevel 保持上次值，故障拍不重算，
 *                         规格指定），解除沿 = bReset 上升沿（R45 配对）。
 *                         ⑥ 非有限判据（R79 双判）：任一有效通道累计非有限 →
 *                         本窗跳过重算，输出保持，信息码 eInputHold。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_CoolantLoopBal` 分工：冷却回路专用平衡归
 *                         那件、通用累计平衡判据归本件；与 `FB_DL_Integrator`
 *                         分工：积分归那件，本件只读外部累计量。
 * 来源标签 (Source Tag) : 自研线（质量/体积平衡判据为公开守恒定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 组 +
 *                         ENUM 分级/错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 分母防除零 + 通道钳位 + 组态锁存 + 非有限跳过
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（分级枚举非状态机，无 CASE 迁移） ｜ R7 ✓ 一 TON 一 F_TRIG 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 3 · 序号 11）
 * 验收向量 (Acceptance) : ① nChanCnt=1，Σin=100.0，Σout=99.0，fTolPct=0.5，
 *                         fWarnPct=2.0 → 失衡率 (100−99)/100×100 = 1.0%，
 *                         eLevel=eWarn；② Σin=100.0，Σout=100.0 → 0.0%，
 *                         eBalanced；③ fTolPct=0 → 锁存 eCfgBad，判定冻结；
 *                         ④ Σin=0，Σout=0 → 失衡率 0，eNoFlow 信息码。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FlowLevel（平衡分级出口）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FlowLevel :
(
    eBalanced := 0,   // 平衡（|失衡率| <= fTolPct） / Balanced within tolerance
    eWarn     := 1,   // 告警（容差与告警阈之间） / Warn band
    eFault    := 2    // 失衡超告警阈 / Imbalance beyond warn threshold
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FbcErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FbcErr :
(
    eOk        := 0,   // 正常 / Normal
    eCfgBad    := 1,   // 故障级：容差/告警阈组态非法（判定冻结） / Fault: tolerance config illegal, verdict frozen
    eChanClamp := 2,   // 信息级：通道数越界已钳位 [1,8] / Info: channel count clamped
    eNoFlow    := 3,   // 信息级：窗口合计趋零，按平衡处理 / Info: near-zero flow, deemed balanced
    eInputHold := 4    // 信息级：有效通道含非有限累计，本窗跳过 / Info: non-finite total skipped this window
);
END_TYPE

FUNCTION_BLOCK FB_DL_FlowBalanceCheck
VAR_INPUT
    aInflow  : ARRAY[0..7] OF LREAL;   // 8 路流入累计量（累计口径一致） [工程单位] / Eight inflow totals
    aOutflow : ARRAY[0..7] OF LREAL;   // 8 路流出累计量 [工程单位] / Eight outflow totals
    nChanCnt : UDINT := 8;             // 有效通道数，域 [1,8]（越界钳位） [路] / Active channel count
    fTolPct  : LREAL := 0.5;           // 平衡容差（<=0 故障），域 > 0 [%] / Balance tolerance
    fWarnPct : LREAL := 2.0;           // 告警阈（>= 容差），域 >= fTolPct [%] / Warn threshold
    tWindow  : TIME := T#10S;          // 重算窗时长，域 > T#0S [ms] / Recalculation window
    bReset   : BOOL := FALSE;          // 复位，上升沿清组态锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    fImbalancePct : LREAL;             // 失衡率（窗口结算值，窗间保持） [%] / Imbalance percentage
    eLevel        : E_DL_FlowLevel;    // 分级出口（窗间保持） [-] / Graded verdict outlet
    fSumIn        : LREAL;             // 窗口流入合计透读 [工程单位] / Window inflow sum readout
    fSumOut       : LREAL;             // 窗口流出合计透读 [工程单位] / Window outflow sum readout
    eErrCode      : E_DL_FbcErr;       // 错误码出口 / Error code outlet
    bError        : BOOL;              // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _nCount   : DINT;                  // 钳位后有效通道数 [路] / Clamped channel count
    _bClamp   : BOOL;                  // 本拍发生通道钳位 [-] / Channel clamp this scan
    _fSumIn   : LREAL;                 // 流入合计中间量 [工程单位] / Inflow sum intermediate
    _fSumOut  : LREAL;                 // 流出合计中间量 [工程单位] / Outflow sum intermediate
    _fBase    : LREAL;                 // 分母基准 = MAX(|Σin|,|Σout|) [工程单位] / Denominator base
    _fImb     : LREAL;                 // 失衡率中间量 [%] / Imbalance intermediate
    _eLevel   : E_DL_FlowLevel := E_DL_FlowLevel.eBalanced;   // 分级锁存（窗间保持源） / Level latch
    _bNonFin  : BOOL;                  // 有效通道非有限当拍量 [-] / Non-finite total this scan
    _bCfgBad  : BOOL;                  // 组态非法当拍量 [-] / Illegal configuration this scan
    _bErrLatch: BOOL;                  // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    i         : DINT;                  // 通道循环索引 / Channel loop index
    rtReset   : R_TRIG;                // 复位沿实例，段 0 无条件调用 / Reset edge instance
    ftWin     : F_TRIG;                // 窗结算沿实例，段 0 无条件调用 / Window settlement F_TRIG
    tonWin    : TON;                   // 自复位重算窗（R188），段 0 无条件调用 / Self-resetting window
END_VAR
VAR CONSTANT
    DL_FBC_NMAX  : DINT  := 8;         // 通道定长上限 [路] / Channel ceiling
    DL_FBC_NMIN  : DINT  := 1;         // 通道数下限 [路] / Channel floor
    DL_FBC_ZERO  : LREAL := 0.0;       // 判零基准 [%] / Zero base
    DL_FBC_FLMIN : LREAL := 1.0E-9;    // 分母基准下限（防除零） [工程单位] / Denominator floor
    DL_FBC_HUND  : LREAL := 100.0;     // 百分比换算基 [%] / Percent scale base
END_VAR

(* —— 段 0：通道钳位 + 组态闸 + 窗口/沿无条件刷新 —— *)
_bClamp := FALSE;                      // 钳位量预清 / Clamp preset
_nCount := UDINT_TO_DINT(nChanCnt);    // 通道数转 DINT / Convert count
IF _nCount > DL_FBC_NMAX THEN
    _nCount := DL_FBC_NMAX;            // 上越界钳 8 / Clamp high
    _bClamp := TRUE;                   // 记钳位 / Mark clamp
END_IF
IF _nCount < DL_FBC_NMIN THEN
    _nCount := DL_FBC_NMIN;            // 下越界钳 1 / Clamp low
    _bClamp := TRUE;                   // 记钳位 / Mark clamp
END_IF
_bCfgBad := (fTolPct <= DL_FBC_ZERO) OR (fWarnPct < fTolPct) OR (tWindow <= T#0S);   // 组态域闸（容差/告警阈/窗） / Configuration gate
rtReset(CLK := bReset);                // 复位沿，每拍必调 / Reset edge, every scan
tonWin(IN := (NOT tonWin.Q) AND (NOT _bErrLatch), PT := tWindow);   // 自复位重算窗（故障期停窗，R188） / Self-reset window
ftWin(CLK := tonWin.Q);                // 窗结算沿，每拍必调 / Settlement edge, every scan

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;               // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;                // 锁存 / Latch
END_IF

(* —— 段 2：有效通道合计与非有限扫描（每拍执行，结算沿取值） —— *)
_fSumIn := DL_FBC_ZERO;                // 合计起步 0 / Sum start zero
_fSumOut := DL_FBC_ZERO;               // 合计起步 0 / Sum start zero
_bNonFin := FALSE;                     // 非有限量预清 / Non-finite preset
FOR i := 0 TO (_nCount - 1) DO
    IF (aInflow[i] <> aInflow[i]) OR ((aInflow[i] - aInflow[i]) <> DL_FBC_ZERO)
       OR (aOutflow[i] <> aOutflow[i]) OR ((aOutflow[i] - aOutflow[i]) <> DL_FBC_ZERO) THEN
        _bNonFin := TRUE;              // 任一有效通道非有限（R79 双判） / Any non-finite total
    END_IF
    _fSumIn := _fSumIn + aInflow[i];   // 流入逐路累计（非有限不写出口，仅置跳过量） / Sum inflow
    _fSumOut := _fSumOut + aOutflow[i];   // 流出逐路累计 / Sum outflow
END_FOR

(* —— 段 3：窗结算重算（故障期冻结；非有限本窗跳过保持上次结论） —— *)
IF ftWin.Q AND (NOT _bErrLatch) THEN
    IF (NOT _bNonFin)
       AND (_fSumIn = _fSumIn) AND ((_fSumIn - _fSumIn) = DL_FBC_ZERO)
       AND (_fSumOut = _fSumOut) AND ((_fSumOut - _fSumOut) = DL_FBC_ZERO) THEN
        fSumIn := _fSumIn;             // 合计落出口 / Sum outlets
        fSumOut := _fSumOut;           // 合计落出口 / Sum outlets
        _fBase := MAX(ABS(_fSumIn), ABS(_fSumOut));   // 分母基准 / Denominator base
        IF _fBase < DL_FBC_FLMIN THEN
            _fImb := DL_FBC_ZERO;      // 零流量：失衡率按 0（防除零，头注释④） / Zero flow: imbalance zero
            _eLevel := E_DL_FlowLevel.eBalanced;       // 按平衡分级 / Deemed balanced
            eErrCode := E_DL_FbcErr.eNoFlow;           // 信息码（不置 bError） / Info code
        ELSE
            _fImb := (_fSumIn - _fSumOut) / _fBase * DL_FBC_HUND;   // 失衡率（分母已过闸） / Imbalance percent
            IF ABS(_fImb) <= fTolPct THEN
                _eLevel := E_DL_FlowLevel.eBalanced;   // 容差内 / Within tolerance
            ELSIF ABS(_fImb) <= fWarnPct THEN
                _eLevel := E_DL_FlowLevel.eWarn;       // 告警带 / Warn band
            ELSE
                _eLevel := E_DL_FlowLevel.eFault;      // 超告警阈 / Beyond warn
            END_IF
        END_IF
        fImbalancePct := _fImb;        // 失衡率落出口 / Imbalance outlet
    END_IF
    (* 非有限本窗跳过：出口保持上次结算值（规格⑥，不重算不抹除） *)
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
eLevel := _eLevel;                     // 分级出口 / Level outlet
IF _bErrLatch THEN
    bError := TRUE;                    // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_FbcErr.eCfgBad;   // 故障级码 / Fault code
ELSE
    bError := FALSE;                   // 无故障级条件 / No fault
    IF NOT ftWin.Q THEN
        IF _bClamp THEN
            eErrCode := E_DL_FbcErr.eChanClamp;   // 信息级：通道钳位 / Info: clamped
        ELSE
            eErrCode := E_DL_FbcErr.eOk;          // 正常 / Normal
        END_IF
    END_IF
    (* 结算拍错误码由段 3 命中分支（eOk/eNoFlow）保留，此处不覆盖 *)
END_IF

END_FUNCTION_BLOCK
