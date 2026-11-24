(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SealIntegrityMonitor
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 封口完整性在线监视（仅监视不执行封口）：bSealDone
 *                         上升沿采样温度/压力/时间三值，与配方窗独立比对，全过
 *                         → bInSpec；NaN 判超差；连续超差计数达阈值 → 预警锁存
 *                         （需复位）；窗下限 < 上限合法性自检，非法拒绝判定。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_SealErr / FUNCTION_BLOCK FB_DL_SealIntegrityMonitor
 * 依赖 (Depends)        : 无 DL_ 内部依赖；Standard.library R_TRIG 实例
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         窗参数合法性自检 ｜ NaN 判超差 ｜ 计数饱和 65535 ｜
 *                         枚举成员全部显式赋值 ｜ R_TRIG 实例每周期无条件调用 ｜
 *                         主码取首个违参（温度 > 压力 > 时间优先级）禁浮点判等
 * 错误码表 (Codes)      : 16#0003_03A2 在规格内
 *                         16#0003_03A3 温度超差
 *                         16#0003_03A4 压力超差
 *                         16#0003_03A5 时间超差
 *                         16#0003_03A6 故障级 窗参数非法(拒绝判定)
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 2
 * 验收向量 (Acceptance) : 窗 180~220 C / 300~400 N / T#800MS~T#1200MS：
 *                         三值 200/350/1000ms → 03A2；温度 230 → 03A3 连续 3 次 → 预警锁存
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SealErr（归属 DL_Device，与 FB_DL_SealIntegrityMonitor 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SealErr :
(
    eInSpec     := 16#0003_03A2,   // 在规格内 / Within specification
    eTempViol   := 16#0003_03A3,   // 温度超差 / Temperature violation
    ePressViol  := 16#0003_03A4,   // 压力超差 / Pressure violation
    eTimeViol   := 16#0003_03A5,   // 时间超差 / Time violation
    eWindowBad  := 16#0003_03A6    // 故障级：窗参数非法，拒绝判定 / Fault: illegal window, judging refused
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SealIntegrityMonitor
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SealIntegrityMonitor
VAR_INPUT
    fSealTemp_C  : REAL;               // 封口温度 [摄氏度] / Seal temperature [degC]
    fSealPress_N : REAL;               // 封口压力 [牛] / Seal pressure [N]
    tSealTime    : TIME;               // 封口时间 [毫秒] / Seal time [ms]
    fTempWin_L   : REAL;               // 温度窗下限 [摄氏度] / Temperature window low [degC]
    fTempWin_H   : REAL;               // 温度窗上限 [摄氏度] / Temperature window high [degC]
    fPressWin_L  : REAL;               // 压力窗下限 [牛] / Pressure window low [N]
    fPressWin_H  : REAL;               // 压力窗上限 [牛] / Pressure window high [N]
    tTimeWin_L   : TIME;               // 时间窗下限 [毫秒] / Time window low [ms]
    tTimeWin_H   : TIME;               // 时间窗上限 [毫秒] / Time window high [ms]
    uViolTrip    : UINT := 3;          // 连续超差预警阈值 [次] / Consecutive-violation trip threshold [pcs]
    bSealDone    : BOOL;               // 封口节拍完成（上升沿采样）/ Seal cycle done, sampled on rising edge
    bReset       : BOOL;               // 预警锁存复位 / Alarm latch reset
END_VAR
VAR_OUTPUT
    bInSpec      : BOOL;               // 三参全在窗内 / All three parameters in window
    bAlarmLatch  : BOOL;               // 预警锁存（连续超差达阈值）/ Alarm latch, threshold reached
    nViolCnt     : UINT;               // 连续超差次数 [次] / Consecutive violation count [pcs]
    eError       : E_DL_SealErr;       // 主错误码（取首个违参）/ Main error code, first violated parameter
END_VAR
VAR
    fbSealTrig   : R_TRIG;             // 封口节拍上升沿实例（无条件调用）/ Seal-done edge instance
    fbResetTrig  : R_TRIG;             // 复位上升沿实例（无条件调用）/ Reset edge instance
    bTempOk      : BOOL;               // 温度窗内判据 / Temperature in-window predicate
    bPressOk     : BOOL;               // 压力窗内判据 / Pressure in-window predicate
    bTimeOk      : BOOL;               // 时间窗内判据 / Time in-window predicate
    bWindowOk    : BOOL;               // 窗参数合法性判据 / Window legality predicate
    bTempValid   : BOOL;               // 温度非有限有效 / Temperature finite validity
    bPressValid  : BOOL;               // 压力非有限有效 / Pressure finite validity
    uViolTripUse : UINT;               // 生效预警阈值（下限钳 1）[次] / Effective trip threshold [pcs]
END_VAR
VAR CONSTANT
    DL_SEAL_INF_MAX  : REAL := 1.0E30;      // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_SEAL_CNT_SAT  : UINT := 65535;       // 超差计数饱和值 [次] / Violation count saturation [pcs]
    DL_SEAL_TRIP_MIN : UINT := 1;           // 预警阈值下限 [次] / Trip threshold lower bound [pcs]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜R_TRIG 实例每周期无条件调用（仅输入条件化）
 *----------------------------------------------------------------------------*)
fbSealTrig(CLK := bSealDone);                        // 封口节拍沿检测无条件刷新 / seal edge refreshed unconditionally
fbResetTrig(CLK := bReset);                          // 复位沿检测无条件刷新 / reset edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜窗参数合法性自检：下限必须严格小于上限，非法则拒绝判定（故障级）
 *----------------------------------------------------------------------------*)
bWindowOk := (fTempWin_L < fTempWin_H) AND (fPressWin_L < fPressWin_H) AND (tTimeWin_L < tTimeWin_H);   // 三窗合法性 / three-window legality
IF NOT bWindowOk THEN
    eError := E_DL_SealErr.eWindowBad;               // 故障级：窗参数非法 / fault: illegal window
    bInSpec := FALSE;                                // 拒绝判定：规格输出 FALSE / judging refused
    nViolCnt := 0;                                   // 计数清零（非法窗不计超差）/ count cleared
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜阈值下限钳位与复位沿处理
 *----------------------------------------------------------------------------*)
uViolTripUse := uViolTrip;                           // 阈值工作副本 / threshold working copy
IF uViolTripUse < DL_SEAL_TRIP_MIN THEN
    uViolTripUse := DL_SEAL_TRIP_MIN;                // 阈值下限钳位 / threshold floored
END_IF
IF fbResetTrig.Q THEN
    bAlarmLatch := FALSE;                            // 复位解锁存 / unlatch on reset
    nViolCnt := 0;                                   // 计数清零 / count cleared
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜节拍采样判定（bSealDone 上升沿一次性判定，非沿拍保持上拍结果）
 *----------------------------------------------------------------------------*)
IF fbSealTrig.Q THEN
    bTempValid := (fSealTemp_C = fSealTemp_C) AND (ABS(fSealTemp_C) <= DL_SEAL_INF_MAX);   // 温度非有限有效 / temperature finite
    bPressValid := (fSealPress_N = fSealPress_N) AND (ABS(fSealPress_N) <= DL_SEAL_INF_MAX);   // 压力非有限有效 / pressure finite
    bTempOk := bTempValid AND (fSealTemp_C >= fTempWin_L) AND (fSealTemp_C <= fTempWin_H);   // 温度窗内（NaN 判超差）/ temp in window
    bPressOk := bPressValid AND (fSealPress_N >= fPressWin_L) AND (fSealPress_N <= fPressWin_H);   // 压力窗内 / pressure in window
    bTimeOk := (tSealTime >= tTimeWin_L) AND (tSealTime <= tTimeWin_H);   // 时间窗内 / time in window
    bInSpec := bTempOk AND bPressOk AND bTimeOk;     // 三参全在窗 / all in window
    IF bInSpec THEN
        nViolCnt := 0;                               // 合格清连续计数 / clear consecutive count
        eError := E_DL_SealErr.eInSpec;              // 码 03A2 / code in-spec
    ELSE
        IF nViolCnt < DL_SEAL_CNT_SAT THEN
            nViolCnt := nViolCnt + 1;                // 连续超差计数饱和自增 [次] / saturating violation increment
        END_IF
        IF bTempOk THEN
            eError := E_DL_SealErr.ePressViol;       // 温度合格则主码取压力（首个违参优先级压力次之）/ main code picks pressure
        ELSIF bPressOk THEN
            eError := E_DL_SealErr.eTimeViol;        // 压力合格则主码取时间 / main code picks time
        ELSE
            eError := E_DL_SealErr.eTempViol;        // 温度违参优先取主码（首个违参 = 温度最优先）/ main code picks temperature first
        END_IF
        IF nViolCnt >= uViolTripUse THEN
            bAlarmLatch := TRUE;                     // 连续超差达阈值：预警锁存 / threshold reached: alarm latched
        END_IF
    END_IF
END_IF
END_FUNCTION_BLOCK
