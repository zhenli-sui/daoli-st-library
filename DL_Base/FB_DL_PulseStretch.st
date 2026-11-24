(*
    FB_DL_PulseStretch —— 脉冲展宽（最小脉宽保持）
    ------------------------------------------------------------------
    分类      : DL_Base / Signal
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T0-2 定时器族变体（ADR：TON 语义 + 最小脉宽工况）；
                T1-1 OSCAT Basic 信号整形惯例为次源，只借「最小脉宽保持」这一
                整形分类事实，不复制任何函数体；clean-room 重写，未复制任何
                闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 现场窄脉冲（< 执行机构最小响应时间）会被下游设备吃掉，本件把输出
                保持到满足最小脉宽 tMinPulse 才释放；双模：可重触发（保持期内新沿
                重新计时）与不可重触发（计时不重启）；
                tMinPulse 非法（0 或 < 1 ms）退化为直通，绝不把 TON 置于非法 PT；
                tMinPulse 超上限先钳位到 10 s 再进定时器；
                与 FB_DL_SignalDebounce（去抖）职责互补，本件不做滤波。
    错误码    : 16#0001_0237 tMinPulse 超上限已钳位到 10 s——信息级，正常防御
                16#0001_0238 预留禁用（信息级，不得挪用）
                16#0001_0309 tMinPulse 非法（< 1 ms 或 0）——故障级，本拍退化为直通
                16#0001_030A 预留禁用（故障级，不得挪用）
                16#0001_030B 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0237 用 / 16#0001_0238 预留 ｜ 16#0001_0309 用 / 16#0001_030A 预留 / 16#0001_030B 预留
    状态机    : 无 CASE，保持期由 TON 的 ET 与单比特 bHoldActive 承载，非法状态不可能出现
    采样约定  : fbTrigIn / fbHold 两个实例在本体首部无条件调用，ET 不会冻结；
                输入脉冲短于一个扫描周期不可见（与库内 SineGenerator 同口径），
                低于任务频率一半的脉冲必须先经硬件或高速任务采样。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_PulseStretch
VAR_INPUT
    bEnable        : BOOL;                     // 使能，FALSE 输出立即复位 / enable, FALSE resets the output immediately
    bIn            : BOOL;                     // 脉冲输入，已在别处去抖时可直接连接 / pulse input, connect directly when debounced upstream
    tMinPulse      : TIME := T#50MS;           // 最小输出脉宽 [ms]，范围 1~10000，0 非法 / minimum output pulse width [ms], range 1~10000, 0 illegal
    bRetriggerable : BOOL := TRUE;             // TRUE 重触发 / FALSE 保持期内不重启计时 / TRUE retriggerable, FALSE keeps the running timer
END_VAR
VAR_OUTPUT
    bOut        : BOOL;                        // 展宽后的输出 / stretched output
    bStretching : BOOL;                        // 正在展宽（保持期） / currently stretching (hold phase)
    tRemain     : TIME;                        // 保持期剩余时间 [ms] / remaining hold time [ms]
    uStretchCnt : UDINT;                       // 累计展宽次数，饱和计数 [次] / accumulated stretch count, saturating [times]
    eErr        : UDINT;                       // 错误码，0=正常 / error id, 0=ok
    bError      : BOOL;                        // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigIn    : R_TRIG;                      // 输入上升沿检测实例，本体首部无条件刷新 / input rising edge instance, refreshed unconditionally
    fbHold      : TON;                         // 保持期定时器实例，本体首部无条件刷新 / hold phase timer, refreshed unconditionally
    bHoldActive : BOOL;                        // 保持期有效位，下一拍作为定时器 IN / hold phase active bit, fed to the timer input next cycle
    bPassThru   : BOOL;                        // 直通退化标志，脉宽参数非法时为 TRUE / pass-through fallback flag, TRUE when the width parameter is illegal
    bRestart    : BOOL;                        // 重触发请求标志，单拍 / retrigger request flag, single cycle
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    tEffMin     : TIME := T#50MS;              // 生效最小脉宽，钳位后进入定时器 [ms] / effective minimum width fed to the timer [ms]
    tRem        : TIME;                        // 剩余时间中间量 [ms] / remaining time intermediate [ms]
END_VAR
VAR CONSTANT
    DL_STRETCH_MIN     : TIME := T#1MS;        // 最小脉宽下限 [ms] / lower bound of the pulse width [ms]
    DL_STRETCH_MAX     : TIME := T#10S;        // 最小脉宽上限 [ms] / upper bound of the pulse width [ms]
    DL_STRETCH_CNT_MAX : UDINT := 16#FFFF_FFFE;// 展宽计数饱和值，防回绕 [次] / stretch counter saturation value, no wrap-around [times]
END_VAR

// 段 1｜输出与错误状态预置 / segment 1, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
tRemain := T#0MS;                              // 剩余时间先归零 / remaining time to zero
bPassThru := FALSE;                            // 直通标志先清 / clear the pass-through flag

// 段 2｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 2, first-scan initialisation
IF NOT bInit THEN
    bHoldActive := FALSE;                      // 首扫不得处于保持期 / no hold phase may survive the first scan
    uStretchCnt := 0;                          // 计数从 0 起 / counter starts at zero
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 3｜脉宽参数闸：先判非法（退化直通），再判超限（钳位后进定时器）/ segment 3, pulse width parameter gate
tEffMin := tMinPulse;                          // 默认沿用输入值 / default to the input value
IF tMinPulse < DL_STRETCH_MIN THEN
    tEffMin := DL_STRETCH_MIN;                 // 定时器必须拿到合法 PT / the timer must receive a legal preset
    bPassThru := TRUE;                         // 退化为直通 / degrade to pass-through
    eErr := 16#0001_0309;                      // 脉宽非法故障码 / illegal pulse width fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
ELSIF tMinPulse > DL_STRETCH_MAX THEN
    tEffMin := DL_STRETCH_MAX;                 // 超上限先钳位 / clamp to the upper bound first
    eErr := 16#0001_0237;                      // 钳位提示（信息级不置故障）/ clamp hint, info level never raises a fault
END_IF

// 段 4｜边沿与定时器实例无条件周期刷新（红线：ET 绝不冻结）/ segment 4, unconditional refresh of the edge and timer instances
fbTrigIn(CLK := bIn);                          // 输入沿 / input edge
fbHold(IN := bHoldActive, PT := tEffMin);      // 保持期定时器，本拍 IN 取上一拍有效位 / hold timer, input uses the previous cycle value

// 段 5｜失能闸：立即复位输出并清保持期 / segment 5, enable gate resets the output immediately
IF NOT bEnable THEN
    bHoldActive := FALSE;                      // 清保持期 / clear the hold phase
    bOut := FALSE;                             // 输出复位 / reset the output
    bStretching := FALSE;                      // 非展宽态 / not stretching
    tRemain := T#0MS;                          // 剩余时间归零 / remaining time to zero
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 6｜直通退化：参数非法时不进定时器 / segment 6, pass-through fallback bypasses the timer
IF bPassThru THEN
    bHoldActive := FALSE;                      // 直通不维持保持期 / no hold phase in pass-through mode
    bOut := bIn;                               // 输出等于输入 / output equals input
    bStretching := FALSE;                      // 非展宽态 / not stretching
    tRemain := T#0MS;                          // 剩余时间归零 / remaining time to zero
    RETURN;                                    // 直通即出口 / pass-through is the exit
END_IF

// 段 7｜重触发判定：本拍先掉 IN 一拍以让 TON 复位，下一拍重新计时 / segment 7, retrigger drops the timer input for one cycle
bRestart := fbTrigIn.Q AND bRetriggerable AND bHoldActive; // 仅可重触发且已在保持期时成立 / only in retriggerable mode while already holding
IF bIn THEN
    bHoldActive := TRUE;                       // 输入到来即进入保持期 / an active input starts the hold phase
END_IF
IF bRestart THEN
    bHoldActive := FALSE;                      // 单拍掉 IN，ET 归零，下一拍重新计时 / drop the input for one cycle so ET restarts next cycle
END_IF

// 段 8｜保持期满释放 / segment 8, release after the hold phase expires
IF fbHold.Q THEN
    bHoldActive := FALSE;                      // 期满释放 / release when the preset is reached
END_IF

// 段 9｜展宽次数统计（饱和，不回绕）/ segment 9, stretch counter with saturation
IF fbTrigIn.Q AND (NOT bRestart) THEN
    IF uStretchCnt < DL_STRETCH_CNT_MAX THEN
        uStretchCnt := uStretchCnt + 1;        // 饱和加一，绝不回绕 / saturating increment, never wraps
    END_IF
END_IF

// 段 10｜输出与剩余时间：剩余时间用 PT 减 ET，ET 不小于 PT 时归零 / segment 10, output and remaining time
bStretching := bHoldActive;                    // 保持期镜像 / hold phase mirror
bOut := bIn OR bHoldActive;                    // 输入为真或仍在保持期则输出为真 / TRUE while the input is on or the hold phase runs
IF fbHold.ET < tEffMin THEN
    tRem := tEffMin - fbHold.ET;               // 剩余 = 最小脉宽减已保持 / remaining = preset minus elapsed
ELSE
    tRem := T#0MS;                             // 已到期，剩余归零 / expired, remaining is zero
END_IF
tRemain := tRem;                               // 对外镜像 / publish the remaining time
END_FUNCTION_BLOCK
