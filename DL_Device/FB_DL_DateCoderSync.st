(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DateCoderSync
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 喷码/打码同步：R_TRIG 采编码器脉冲 → 计数器带偏移
 *                         → 计满修正分频比触发一拍喷印（TP 成形脉宽）；产品检测
 *                         丢失超时 → 跳过本袋并计数；偏移限幅后合成目标（以
 *                         >= 比较替代取模，杜绝负余数）；相位诊断委托 FC_DL_ModPos。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_CoderErr / FUNCTION_BLOCK FB_DL_DateCoderSync
 * 依赖 (Depends)        : DL_MathData/FC_DL_ModPos
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         分频比下限钳 1 防除零 ｜ 偏移双向限幅 ｜ 枚举成员全部显式赋值
 *                         R_TRIG/TP/TON 实例每周期无条件调用（仅输入条件化）｜
 *                         负余数防御：目标合成用 >= 比较，不裸用取模
 * 错误码表 (Codes)      : 16#0003_039D 就绪
 *                         16#0003_039E 信息级 分频比非法(已钳 1)
 *                         16#0003_039F 信息级 偏移越界(已钳制)
 *                         16#0003_03A0 信息级 产品信号超时(已跳过)
 *                         16#0003_03A1 信息级 正常喷印中
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 2
 * 验收向量 (Acceptance) : 分频 10，偏移 0：第 10 个编码脉冲 → bPrintTrig 一拍脉宽；
 *                         偏移 +3 → 第 13 个脉冲触发；分频 0 → 钳 1 且 039E；
 *                         产品信号丢失超 tProdMax → 跳过且 03A0
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CoderErr（归属 DL_Device，与 FB_DL_DateCoderSync 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CoderErr :
(
    eReady      := 16#0003_039D,   // 就绪 / Ready
    eDivClamped := 16#0003_039E,   // 信息级：分频比非法已钳 1 / Info: division ratio clamped to 1
    eOffsetClamp:= 16#0003_039F,   // 信息级：偏移越界已钳制 / Info: offset clamped
    eProdSkip   := 16#0003_03A0,   // 信息级：产品信号超时已跳过 / Info: product timeout, skipped
    ePrinting   := 16#0003_03A1    // 信息级：正常喷印中 / Info: printing active
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_DateCoderSync
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_DateCoderSync
VAR_INPUT
    bEncoderPulse  : BOOL;             // 编码器脉冲输入 / Encoder pulse input
    uDivRatio      : UINT;             // 分频比 [脉冲每触发]，有效域 1~10000 / Division ratio [pulses per trigger]
    nOffsetCounts  : DINT;             // 偏移补偿 [脉冲]，有效域 -1000~1000 / Offset compensation [pulses]
    bProductDetect : BOOL;             // 产品到位信号 / Product present signal
    tPulseWidth    : TIME := T#10MS;   // 喷印触发脉宽 [毫秒] / Print trigger pulse width [ms]
    tProdMax       : TIME := T#5S;     // 产品信号丢失超时 [秒] / Product signal timeout [s]
END_VAR
VAR_OUTPUT
    bPrintTrig     : BOOL;             // 喷印触发（TP 成形脉宽）/ Print trigger, TP-formed pulse
    uPulseCount    : UDINT;            // 累计编码脉冲 [个]，诊断 / Accumulated pulse count [pcs]
    uSkipCount     : UDINT;            // 跳过计数 [次]，诊断 / Skipped-product count [pcs]
    nPhaseDiag     : DINT;             // 相位诊断（当前计数对目标取正余数）/ Phase diagnostic, positive remainder
    eErr           : E_DL_CoderErr;    // 错误码 / Error code
END_VAR
VAR
    fbEncTrig      : R_TRIG;           // 编码脉冲上升沿实例（无条件调用）/ Encoder pulse edge instance
    fbPrintPulse   : TP;               // 喷印脉宽定时器实例（无条件调用）/ Print pulse timer instance
    bTrigReq       : BOOL;             // 触发请求锁存（TP 输入条件源）/ Trigger request latch, TP input source
    tonProdLost    : TON;              // 产品信号丢失计时器（无条件调用）/ Product-lost timer
    nCount         : DINT;             // 本袋脉冲计数 [个] / Pulse count for the current bag [pcs]
    nTarget        : DINT;             // 合成触发目标（分频+偏移，下限 1）/ Composite trigger target [pulses]
    uDivUse        : UINT;             // 生效分频比（钳位后）[脉冲每触发] / Effective division ratio
    nOffsetUse     : DINT;             // 生效偏移（限幅后）[脉冲] / Effective offset [pulses]
    uPulseAcc      : UDINT;            // 累计脉冲工作副本（饱和自增）[个] / Accumulated pulse working copy [pcs]
    uSkipAcc       : UDINT;            // 跳过计数工作副本（饱和自增）[次] / Skip count working copy [pcs]
    uPhaseErr      : UDINT;            // 委托取模错误码（0 = 无错）/ Delegate modulo error id
END_VAR
VAR CONSTANT
    DL_COD_DIV_MAX    : UINT := 10000;          // 分频比上限 [脉冲每触发] / Division ratio upper bound
    DL_COD_OFF_MIN    : DINT := -1000;          // 偏移下限 [脉冲] / Offset lower bound [pulses]
    DL_COD_OFF_MAX    : DINT := 1000;           // 偏移上限 [脉冲] / Offset upper bound [pulses]
    DL_COD_TARGET_MIN : DINT := 1;              // 触发目标下限 [脉冲]（防除零与零目标死锁）/ Target lower bound [pulses]
    DL_COD_CNT_SAT    : UDINT := 16#FFFF_FFFE;  // 累计计数饱和值 [个] / Count saturation [pcs]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测/TP/TON 实例每周期无条件调用（仅输入条件化）
 *----------------------------------------------------------------------------*)
fbEncTrig(CLK := bEncoderPulse);                      // 编码脉冲沿检测无条件刷新 / encoder edge refreshed unconditionally
fbPrintPulse(IN := bTrigReq AND bProductDetect, PT := tPulseWidth);   // 喷印脉宽成形（IN 条件化，请求锁存源）/ print pulse formed
tonProdLost(IN := NOT bProductDetect, PT := tProdMax);   // 产品信号丢失计时 / product-lost timing

(*------------------------------------------------------------------------------
 * 段 2｜分频比钳位（下限 1 防除零与零目标死锁）与偏移双向限幅
 *----------------------------------------------------------------------------*)
eErr := E_DL_CoderErr.eReady;                         // 预置就绪 / preset ready
uDivUse := uDivRatio;                                 // 分频工作副本 / division working copy
IF (uDivUse < 1) OR (uDivUse > DL_COD_DIV_MAX) THEN
    uDivUse := 1;                                     // 分频非法钳 1 / division clamped to 1
    eErr := E_DL_CoderErr.eDivClamped;                // 信息级：分频比非法 / info: ratio clamped
END_IF
nOffsetUse := nOffsetCounts;                          // 偏移工作副本 / offset working copy
IF nOffsetUse < DL_COD_OFF_MIN THEN
    nOffsetUse := DL_COD_OFF_MIN;                    // 偏移下限钳位 / offset floored
    IF eErr = E_DL_CoderErr.eReady THEN
        eErr := E_DL_CoderErr.eOffsetClamp;          // 信息级：偏移越界 / info: offset clamped
    END_IF
ELSIF nOffsetUse > DL_COD_OFF_MAX THEN
    nOffsetUse := DL_COD_OFF_MAX;                    // 偏移上限钳位 / offset capped
    IF eErr = E_DL_CoderErr.eReady THEN
        eErr := E_DL_CoderErr.eOffsetClamp;          // 信息级：偏移越界 / info: offset clamped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜合成触发目标：分频 + 偏移，下限 1；以 >= 比较替代取模，杜绝负余数
 *----------------------------------------------------------------------------*)
nTarget := UINT_TO_DINT(uDivUse) + nOffsetUse;        // 合成目标 [脉冲] / composite target [pulses]
IF nTarget < DL_COD_TARGET_MIN THEN
    nTarget := DL_COD_TARGET_MIN;                    // 目标下限钳位 / target floored
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜产品信号丢失超时：跳过本袋计数并清计数器（信息级 03A0）
 *----------------------------------------------------------------------------*)
IF tonProdLost.Q THEN
    IF nCount > 0 THEN
        nCount := 0;                                 // 跳过本袋：计数清零 / skip bag: counter cleared
        IF uSkipAcc < DL_COD_CNT_SAT THEN
            uSkipAcc := uSkipAcc + 1;                // 跳过计数饱和自增 [次] / saturating skip increment
        END_IF
        IF eErr = E_DL_CoderErr.eReady THEN
            eErr := E_DL_CoderErr.eProdSkip;         // 信息级：产品信号超时 / info: product timeout
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜编码脉冲计数与触发：计满合成目标即触发（TP 已在段 1 成形脉宽）
 *----------------------------------------------------------------------------*)
IF fbEncTrig.Q THEN
    nCount := nCount + 1;                            // 脉冲计数 [个] / pulse counted
    IF uPulseAcc < DL_COD_CNT_SAT THEN
        uPulseAcc := uPulseAcc + 1;                  // 累计脉冲饱和自增 [个] / saturating pulse increment
    END_IF
    IF nCount >= nTarget THEN
        bTrigReq := TRUE;                            // 触发请求锁存（TP 下拍成形脉宽）/ trigger request latched
        nCount := 0;                                 // 触发后计数清零 / counter cleared after trigger
    END_IF
END_IF
IF fbPrintPulse.Q THEN
    bTrigReq := FALSE;                               // 脉宽完成：请求解锁 / pulse done: request released
END_IF
bPrintTrig := fbPrintPulse.Q;                        // 喷印触发输出（TP 成形）/ print trigger output
IF bPrintTrig THEN
    IF eErr = E_DL_CoderErr.eReady THEN
        eErr := E_DL_CoderErr.ePrinting;             // 信息级：正常喷印中 / info: printing active
    END_IF
END_IF
uPulseCount := uPulseAcc;                            // 累计脉冲输出 [个] / accumulated pulse output
uSkipCount := uSkipAcc;                              // 跳过计数输出 [次] / skip count output

(*------------------------------------------------------------------------------
 * 段 6｜相位诊断：委托 FC_DL_ModPos 防负余数（计数为非负，防御仍委托）
 *----------------------------------------------------------------------------*)
nPhaseDiag := FC_DL_ModPos(nValue := nCount, nModulus := nTarget, eErr => uPhaseErr);   // 正余数诊断 [个] / positive-remainder diagnostic
IF uPhaseErr <> 0 THEN
    nPhaseDiag := 0;                                 // 委托异常诊断归零 / diagnostic zeroed on delegate error
END_IF
END_FUNCTION_BLOCK
