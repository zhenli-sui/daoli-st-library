(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CusumMonitor
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS / MAX），零厂商私有库
 * 功能描述 (Function)   : 双侧 CUSUM 累积和监视（Page 型决策区间）：
 *                           fCpos = MAX(0, fCpos + (fSample − fTarget − fK))
 *                           fCneg = MAX(0, fCneg + (fTarget − fSample − fK))
 *                         正/负决策区间下限钳零（防负累加，规格指定）；累计和
 *                         达决策限 fH（>= 容差判）置 bPosAlarm / bNegAlarm
 *                         （电平输出，回落自动撤销，不锁存）；bReset 上升沿清
 *                         双累计与计数。非有限样本跳过递推并计数置信息码
 *                         eSampleSkip（规格指定）。
 * 接口     (Interface)  : 输入 fSample 观测样本、fTarget 目标均值、fK 容许限
 *                         （域 > 0）、fH 决策限（域 > 0）、bReset 复位；
 *                         输出 fCpos 正向累计和、fCneg 负向累计和、bPosAlarm
 *                         正偏报警（电平）、bNegAlarm 负偏报警（电平）、
 *                         uSkipCnt 非有限样本跳过计数、eErrCode 错误码、
 *                         bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做 CUSUM 递推与双侧判限，
 *                         不接管报警管理、不归一化样本**；报警归集归
 *                         `FB_DL_AlarmManager`。
 *                         ② 递推钳零：MAX(0, ·) 使区间单调不下降且非负，
 *                         结构性防负累加（规格指定口径）。
 *                         ③ 报警判据 fCpos >= fH 用容差比较（禁浮点 =），
 *                         电平语义（回落撤销）写入头注释，非锁存。
 *                         ④ 非有限样本（R79 双判）跳过递推：双累计不被污染，
 *                         uSkipCnt 防回绕递增，信息码不置 bError。
 *                         ⑤ 组态闸：fK <= 0 或 fH <= 0 → 锁存故障，双累计
 *                         冻结、报警出口安全侧 FALSE，解除沿 = bReset 上升沿
 *                         （故障级码配对 bError，R45）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_Integrator` 分工：无界积分归那件、钳零双侧
 *                         决策区间归本件；与 `FB_DL_EtchEndpointTrend` 分工：
 *                         工艺终点趋势归那件。
 * 来源标签 (Source Tag) : 自研线（Page CUSUM 为公开统计过程控制定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 累计组 +
 *                         BOOL 报警组 + UDINT 计数 + ENUM 错误码；数字码位待
 *                         主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 钳零递推 + 非有限跳过 + 组态锁存 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 2 · 序号 6）
 * 验收向量 (Acceptance) : ① fTarget=10, fK=0.5, fH=5，样本 12,12,12,12 →
 *                         fCpos = 1.5, 3.0, 4.5, 6.0，第 4 拍 6.0 >= 5 →
 *                         bPosAlarm=TRUE，fCneg 恒 0；② 样本 8,8 → fCneg =
 *                         2.5, 5.0，第 2 拍 bNegAlarm=TRUE，fCpos 恒 0；
 *                         ③ fK=0 → 锁存故障 eCfgBad，出口冻结；
 *                         ④ 样本 NaN → uSkipCnt+1，eErrCode=eSampleSkip，
 *                         累计不变。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CusumErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CusumErr :
(
    eOk         := 0,   // 正常 / Normal
    eCfgBad     := 1,   // 故障级：组态非法（fK/fH 域） / Fault: illegal configuration
    eSampleSkip := 2    // 信息级：非有限样本跳过（见 uSkipCnt） / Info: non-finite sample skipped
);
END_TYPE

FUNCTION_BLOCK FB_DL_CusumMonitor
VAR_INPUT
    fSample : LREAL := 0.0;           // 观测样本 [工程单位] / Observed sample
    fTarget : LREAL := 0.0;           // 目标均值（与样本同工程单位） / Target mean, same engineering unit
    fK      : LREAL := 0.5;           // 容许限（偏移容忍），域 > 0 [工程单位] / Allowance, must be > 0
    fH      : LREAL := 5.0;           // 决策限（累计和阈值），域 > 0 [工程单位] / Decision limit, must be > 0
    bReset  : BOOL := FALSE;          // 复位，上升沿清双累计与跳过计数 [-] / Reset, rising edge clears accumulators
END_VAR
VAR_OUTPUT
    fCpos     : LREAL;                // 正向累计和（下限钳零） [工程单位] / Positive cumulative sum, floored at zero
    fCneg     : LREAL;                // 负向累计和（下限钳零） [工程单位] / Negative cumulative sum, floored at zero
    bPosAlarm : BOOL;                 // 正偏报警电平（fCpos >= fH） [-] / Positive alarm level
    bNegAlarm : BOOL;                 // 负偏报警电平（fCneg >= fH） [-] / Negative alarm level
    uSkipCnt  : UDINT := 0;           // 非有限样本跳过计数（防回绕） [个] / Skipped-sample counter
    eErrCode  : E_DL_CusumErr;        // 错误码出口 / Error code outlet
    bError    : BOOL;                 // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _fCpos    : LREAL := 0.0;         // 正向累计锁存（冻结源，与出口同源） / Positive sum latch
    _fCneg    : LREAL := 0.0;         // 负向累计锁存 / Negative sum latch
    _bNonFin  : BOOL;                 // 样本非有限当拍量 [-] / Sample non-finite this scan
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration this scan
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_CSM_ZERO : LREAL := 0.0;       // 钳零下限与判零基准 [工程单位] / Zero floor and non-finite base
    DL_CSM_UDMAX: UDINT := 4294967295;   // 跳过计数饱和点（防回绕） [个] / Skip counter saturation ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 沿刷新 —— *)
_bNonFin := (fSample <> fSample) OR ((fSample - fSample) <> DL_CSM_ZERO);   // 样本非有限（R79 双判） / Sample non-finite
_bCfgBad := (fK <= DL_CSM_ZERO) OR (fH <= DL_CSM_ZERO);                     // 组态域闸（fK/fH 须正） / Configuration gate
rtReset(CLK := bReset);                            // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿（清双累计与跳过计数；先于故障锁存判定，复位语义优先） —— *)
IF rtReset.Q THEN
    _fCpos := DL_CSM_ZERO;                         // 清正向累计（规格：复位沿清双累计） / Clear positive sum
    _fCneg := DL_CSM_ZERO;                         // 清负向累计 / Clear negative sum
    uSkipCnt := 0;                                 // 清跳过计数 / Clear skip counter
    _bErrLatch := FALSE;                           // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;                            // 锁存 / Latch
END_IF

(* —— 段 2：CUSUM 递推（组态故障期冻结；非有限样本跳过） —— *)
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fCpos := MAX(DL_CSM_ZERO, _fCpos + (fSample - fTarget - fK));   // 正向递推钳零 / Positive recursion floored
    _fCneg := MAX(DL_CSM_ZERO, _fCneg + (fTarget - fSample - fK));   // 负向递推钳零 / Negative recursion floored
ELSIF (NOT _bErrLatch) AND _bNonFin THEN
    IF uSkipCnt < DL_CSM_UDMAX THEN
        uSkipCnt := uSkipCnt + 1;                  // 跳过计数防回绕递增 / Skip counter increment
    END_IF
END_IF

(* —— 段 3：出口单点映射（名实双出口同源，R191） —— *)
fCpos := _fCpos;                                   // 正向累计出口 / Positive sum outlet
fCneg := _fCneg;                                   // 负向累计出口 / Negative sum outlet
IF _bErrLatch THEN
    bPosAlarm := FALSE;                            // 故障安全侧：报警出口 FALSE / Fault safe side
    bNegAlarm := FALSE;                            // 故障安全侧：负偏报警出口 FALSE / Fault safe side for negative alarm
    bError := TRUE;                                // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_CusumErr.eCfgBad;             // 故障级码 / Fault code
ELSE
    bPosAlarm := _fCpos >= fH;                     // 报警电平（容差域 >= 判，禁 =） / Positive alarm level
    bNegAlarm := _fCneg >= fH;                     // 负偏报警电平 / Negative alarm level
    IF _bNonFin THEN
        eErrCode := E_DL_CusumErr.eSampleSkip;     // 信息级（不置 bError） / Info code
    ELSE
        eErrCode := E_DL_CusumErr.eOk;             // 正常 / Normal
    END_IF
    bError := FALSE;                               // 无故障级条件 / No fault
END_IF

END_FUNCTION_BLOCK
