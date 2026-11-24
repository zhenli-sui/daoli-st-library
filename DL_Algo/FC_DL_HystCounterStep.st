(*==============================================================================
 * 名称 : FC_DL_HystCounterStep —— 迟滞跨带计数器（上穿 +1 下穿 -1，带位记忆经 nBand 回写）
 * 分类 / 前缀 / 版本 : DL_Algo / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 以 fUpTh/fDnTh 构成上下带界、fHyst 为校验用回差参考：fIn 上穿
 *            fUpTh 计数 +1，下穿 fDnTh 计数 -1，两界之间不动作（迟滞死区）。
 *            带位记忆 nBand（-1/0/+1）经 VAR_IN_OUT 由调用方持有，保证停在
 *            界外不重复计数、须先穿越对侧门限才反向计数。计数钳位 [nMin,nMax]。
 *            边界处理：fDnTh>=fUpTh、fHyst<0、nMin>nMax 判参数非法；输入
 *            非有限（NaN/±Inf）置 eErr，两种故障下 nBand 保持原值不误动。
 * 错误码 : 16#0001_1C03 = 门限/回差/钳位区间参数非法，或输入非有限（NaN/±Inf）
 *          eErr=0 且 bValid=TRUE 表示计数结果可用（调用方须把返回值写回计数变量）
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，带位记忆由调用方经 nBand 持有，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/门限校验 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_HystCounterStep : INT
VAR_INPUT
    nCount : INT;      // 当前计数（调用方持有，返回值须写回）/ current count, caller-held
    fIn    : LREAL;    // 被监视输入量 [工程单位] / monitored input value
    fUpTh  : LREAL;    // 上穿计数门限 [工程单位] / up-cross counting threshold
    fDnTh  : LREAL;    // 下穿计数门限 [工程单位] / down-cross counting threshold
    fHyst  : LREAL;    // 回差参考量（须 >=0）[工程单位] / hysteresis reference, must be >= 0
    nMin   : INT;      // 计数下限 [次] / count lower clamp
    nMax   : INT;      // 计数上限 [次] / count upper clamp
END_VAR
VAR_IN_OUT
    nBand  : INT;      // 带位记忆 -1/0/+1（调用方持有回写）/ band memory, caller-held
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1C03=参数非法或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=计数结果可用 / TRUE when count result is usable
END_VAR
VAR
    _nRet : INT;       // 计数中间值 / count intermediate
END_VAR

FC_DL_HystCounterStep := nCount;             // 返回值预设原计数 / preset return to input count
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn))          // fIn 非有限 / NaN or infinite
   OR (fUpTh <> fUpTh) OR ((fUpTh - fUpTh) <> (fUpTh - fUpTh))   // fUpTh 非有限 / NaN or infinite
   OR (fDnTh <> fDnTh) OR ((fDnTh - fDnTh) <> (fDnTh - fDnTh))   // fDnTh 非有限 / NaN or infinite
   OR (fHyst <> fHyst) OR ((fHyst - fHyst) <> (fHyst - fHyst)) THEN  // fHyst 非有限 / NaN or infinite
    eErr   := 16#0001_1C03;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // nBand 冻结原值 / freeze band unchanged
END_IF

IF (fDnTh >= fUpTh) OR (fHyst < 0.0) OR (nMin > nMax) THEN    // 参数合法性校验 / parameter validity check
    eErr   := 16#0001_1C03;                  // 置参数非法码 / set invalid-parameter code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // nBand 冻结原值 / freeze band unchanged
END_IF

_nRet := nCount;                             // 取当前计数 / take current count

IF (fIn >= fUpTh) AND (nBand < 1) THEN       // 上穿且非已在高带 / up-cross and not already high
    _nRet := _nRet + 1;                      // 计数 +1 / bump count up
    nBand := 1;                              // 记忆进入高带 / memorize high band
ELSIF (fIn <= fDnTh) AND (nBand > -1) THEN   // 下穿且非已在低带 / down-cross and not already low
    _nRet := _nRet - 1;                      // 计数 -1 / bump count down
    nBand := -1;                             // 记忆进入低带 / memorize low band
ELSIF (fIn > fDnTh) AND (fIn < fUpTh) THEN   // 落入迟滞死区 / inside hysteresis deadband
    nBand := 0;                              // 记忆回到中性带 / memorize neutral band
END_IF

IF _nRet < nMin THEN                         // 计数下限钳位 / clamp lower
    _nRet := nMin;                           // 钳到下限 / clamp to lower
END_IF
IF _nRet > nMax THEN                         // 计数上限钳位 / clamp upper
    _nRet := nMax;                           // 钳到上限 / clamp to upper
END_IF

FC_DL_HystCounterStep := _nRet;              // 回写计数结果 / write back count

END_FUNCTION
