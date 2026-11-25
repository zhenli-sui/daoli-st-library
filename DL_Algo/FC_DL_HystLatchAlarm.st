(*==============================================================================
 * 名称 : FC_DL_HystLatchAlarm —— 迟滞触发 + 手动复位锁存报警（状态经 VAR_IN_OUT 由调用方持有）
 * 分类 / 前缀 / 版本 : DL_Algo / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : fIn 上穿 fOn 置位报警并锁存；降到 fOff 以下不自动清除，仅当
 *            bReset=TRUE 才复位（复位后若 fIn 仍 >= fOn 则同拍重新置位，
 *            天然防「复位即复报」盲区）。锁存状态 nState 经 VAR_IN_OUT 由
 *            调用方持有（0=正常 / 1=报警锁存），返回值 = 报警有效电平。
 *            边界处理：fOn<fOff 判参数非法（迟滞反向无意义）；输入非有限
 *            （NaN/±Inf）置 eErr，两种故障下 nState 保持原值不误动。
 * 错误码 : 16#0001_1C02 = 门限次序非法（fOn<fOff），或输入非有限（NaN/±Inf）
 *          eErr=0 且 bValid=TRUE 表示报警电平与 nState 可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，锁存态由调用方经 nState 持有，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/门限校验 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_HystLatchAlarm : BOOL
VAR_INPUT
    fIn    : LREAL;    // 被监视输入量 [工程单位] / monitored input value
    fOn    : LREAL;    // 报警置位门限 [工程单位] / alarm set threshold
    fOff   : LREAL;    // 迟滞参考门限（仅作参数校验：要求 fOn >= fOff）[工程单位] / hysteresis reference, param check only
    bReset : BOOL;     // 复位指令（沿/电平均可，调用方决定）/ reset command
END_VAR
VAR_IN_OUT
    nState : INT;      // 锁存状态 0=正常 1=报警（调用方持有回写）/ latched state, caller-held
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1C02=参数非法或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=报警电平可用 / TRUE when alarm level is usable
END_VAR

FC_DL_HystLatchAlarm := FALSE;               // 报警电平预设 FALSE / preset alarm to FALSE
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn))          // fIn 非有限 / NaN or infinite
   OR (fOn <> fOn) OR ((fOn - fOn) <> (fOn - fOn))        // fOn 非有限 / NaN or infinite
   OR (fOff <> fOff) OR ((fOff - fOff) <> (fOff - fOff)) THEN  // fOff 非有限 / NaN or infinite
    eErr   := 16#0001_1C02;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // nState 冻结原值，不误动 / freeze state unchanged
END_IF

IF fOn < fOff THEN                           // 迟滞反向：参数非法 / reversed hysteresis invalid
    eErr   := 16#0001_1C02;                  // 置参数非法码 / set invalid-parameter code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // nState 冻结原值 / freeze state unchanged
END_IF

IF bReset THEN                               // 手动复位优先（先清后判）/ reset first, judge after
    nState := 0;                             // 清除锁存 / clear latch
END_IF
IF nState = 0 THEN                           // 非锁存态才可置位 / only unlatched state can set
    IF fIn >= fOn THEN                       // 上穿置位门限 / rising past set threshold
        nState := 1;                         // 置位并锁存 / set and latch
    END_IF
END_IF

FC_DL_HystLatchAlarm := (nState = 1);        // 回写报警电平 / write back alarm level

END_FUNCTION
