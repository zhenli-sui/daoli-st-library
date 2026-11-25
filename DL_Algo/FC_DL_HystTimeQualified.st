(*==============================================================================
 * 名称 : FC_DL_HystTimeQualified —— 迟滞 + 时间确认翻转（确认计时由调用方 TON 持有）
 * 分类 / 前缀 / 版本 : DL_Algo / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 输出翻转需时间确认：bRawIn=FALSE 时输出立即 FALSE 且确认计时
 *            清零（tNewElapsed=T#0s）；bRawIn=TRUE 且输出当前 FALSE 时，仅当
 *            调用方 TON 累计 tElapsed >= tQual 才翻转 TRUE；输出已 TRUE 且
 *            原始输入仍 TRUE 则保持。tElapsed 语义 = 调用方 TON.ET（bRawIn
 *            期间单调增长），tNewElapsed 回传给调用方供下一拍使用。
 *            边界处理：tQual<=T#0s 视为立即确认（0 时延合法用法）；
 *            bPrevOut=TRUE 而 bRawIn=FALSE 时立即翻 FALSE（OFF 无延时）。
 * 错误码 : 16#0001_1C04 为本件预留码位（当前实现无故障路径），eErr 恒 0、bValid 恒 TRUE
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，确认计时由调用方 TON 持有，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 时间比较口径明确 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_HystTimeQualified : BOOL
VAR_INPUT
    bRawIn   : BOOL;   // 原始输入（未经确认）/ raw input before qualification
    tQual    : TIME;   // 确认时长门限 [ms] / qualification duration threshold
    bPrevOut : BOOL;   // 上一拍输出（调用方持有）/ previous output, caller-held
    tElapsed : TIME;   // 调用方 TON 累计确认时间 [ms] / caller-held TON elapsed time
END_VAR
VAR_OUTPUT
    tNewElapsed : TIME;    // 回传确认时间（供调用方下一拍使用）/ elapsed time passed back to caller
    eErr        : UDINT;   // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError      : BOOL;    // 故障标志，恒 FALSE / error flag, always FALSE
    bValid      : BOOL;    // TRUE=输出与计时可用，恒 TRUE / TRUE when outputs are usable
END_VAR

eErr        := 16#0000_0000;             // 故障码清零 / clear error code
bError      := FALSE;                    // 故障标志清零 / clear error flag
bValid      := TRUE;                     // 本件无故障路径，恒可用 / always valid
tNewElapsed := T#0s;                     // 确认计时预设清零 / preset elapsed to zero

IF NOT bRawIn THEN                       // 原始输入失效：OFF 无延时 / raw input low: immediate off
    FC_DL_HystTimeQualified := FALSE;    // 输出立即 FALSE / output FALSE immediately
    tNewElapsed := T#0s;                 // 确认计时清零（调用方应同步复位 TON）/ reset qualification timer
    RETURN;                              // 提前收口 / early exit
END_IF

tNewElapsed := tElapsed;                 // 原始输入有效：计时透传 / raw high: pass timer through

IF bPrevOut THEN                         // 输出已 TRUE 且原始输入仍 TRUE / already on and raw high
    FC_DL_HystTimeQualified := TRUE;     // 保持 TRUE / keep TRUE
ELSIF tElapsed >= tQual THEN             // 确认计时到限 / qualification time reached
    FC_DL_HystTimeQualified := TRUE;     // 翻转为 TRUE / flip to TRUE
ELSE                                     // 确认时间未到 / qualification not reached
    FC_DL_HystTimeQualified := FALSE;    // 维持 FALSE / keep FALSE
END_IF

END_FUNCTION
