(*
    组件名称 : FB_DL_PulseWidthFilter
    所属子库 : DL_Base
    当前版本 : 1.0.1
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 窄脉冲抑制，脉宽小于 tMinWidth 的整段脉冲不出现在输出上，合格脉冲的宽度不失真。
              取舍 ①（本件最容易写错的地方）：必须是「双侧确认窗」—— 上升沿与下降沿各用一只 TON 确认，
              输出相对输入整体滞后 tMinWidth。若只延迟上升沿（单侧确认），每个合格脉冲都会被削掉
              tMinWidth 的宽度，长信号看着正常、短脉冲悄悄变形，是现场最难查的一类错。
              本件用 fbOnDelay 确认高电平、fbOffDelay 确认低电平，两只看守各自一侧，于是宽度守恒。
              取舍 ②：窄脉冲「整段吞掉」而不是「压窄」—— 输出只在输入稳定维持 tMinWidth 后才跟随，
              未维持到确认完成的电平从来不落到输出上，抑制计数在「输入已回落但确认未完成」那拍递增。
              取舍 ③：失能即直通（bOut := bIn）—— 旁路时不得留门控残影；两只看守定时器的 IN 都串入 bEnable，
              保证失能期间它们同步复位，重新使能时从零开始确认，不会带着旧完成位直接放行。
              取舍 ④：与 FB_DL_SignalDebounce 的边界 —— 去抖是「延迟跳变并对两侧同宽」，本件是
              「短于宽度的整段丢弃且合格脉宽不失真」，两者判据与后果都不同，不可互相替代。
    开源溯源 : 原创实现（T0-1 变体线）。无外部源码参考，码位、抑制计数策略、双侧确认结构 100% 自有。；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
    本文件内含 : FUNCTION_BLOCK FB_DL_PulseWidthFilter（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG / F_TRIG
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 宽度闸 + 计数饱和闸 + 单拍标志先销后置 + 失能直通
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 本件为纯时序件，无顺序状态机（不引入枚举），
              故 03A7 保留预留并在头注释写明理由；7 项红线中「ENUM + CASE + ELSE」对无状态机件为 N/A
              R7 ✓ TON / R_TRIG / F_TRIG 全部在主体最前部无条件刷新，位于任何 IF 之外
              R8 ✓ 最小宽度、告警代理阈值、计数上限全常量化
    错误码   : 16#0001_045A [信息级] 确认窗小于两倍最小任务周期的代理阈值（2ms），只提示不改参数，bError = FALSE
               16#0001_045B [信息级] 预留禁用（不得挪用；本件信息级只用 1 槽，不加强加码 —— R90）
               16#0001_03A5 [故障级] 最小宽度非法已钳至 1ms 继续，bError = TRUE
               16#0001_03A6 [故障级] 抑制计数饱和，统计已失真需复位，bError = TRUE
               16#0001_03A7 [故障级] 预留禁用（本件无状态机，无非法状态分支，故不占实现）
    码位总账 : 16#0001_045A 用 / 16#0001_045B 预留 ｜ 16#0001_03A5 用 / 16#0001_03A6 用 / 16#0001_03A7 预留
    遗留假设 :
        ① 【代理阈值的口径必须明说】库内没有扫描周期引脚（扫描周期由调用方注入的 tDelta 只在
        FB_DL_SamplingTrigger 里出现，本件按派单引脚表不得新增），故无法真正判「tMinWidth < 2 × 扫描周期」。
        本件以 DL_PWF_WARN_MIN = T#2MS（1ms 任务的极限确认窗）作为代理阈值发 045A，
        该代理不能覆盖更慢的任务（如 10ms 任务），须由调用方在参数整定阶段自行核对 —— 未实测，编译门槛未闭合。
        ② 确认窗依赖 TON 的 PT 语义（IN 断开立即清零 ET），为 IEC 语义推导，未逐平台实测。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 4 入库
        2026-11-16  v1.0.1  R21 终审修复（轻微）：bReset 的引脚注释承诺「上升沿清抑制计数」，主体却写成
                            电平清零 `IF bReset`。HMI 上按住复位按钮不放是常态，此时抑制计数被持续压零，
                            现场会以为「一个窄脉冲都没发生」，而 bRejected 单拍标志仍在正常翻转。
                            现补 rtReset : R_TRIG 实例（与其余实例同段无条件刷新，满足红线 R4）并改为沿判定；
                            同时把引脚注释里并不存在的「饱和标志」措辞改成实情（饱和只为当拍 eErr 报码）。
*)
FUNCTION_BLOCK FB_DL_PulseWidthFilter
VAR_INPUT
    bEnable         : BOOL := TRUE;      // 使能，FALSE 时输出直通输入（旁路）/ enable, FALSE bypasses the filter and follows the input
    bIn             : BOOL;              // 原始信号 / raw input signal
    tMinWidth       : TIME := T#20MS;    // 允许通过的最小脉冲宽度，≤ 0 时钳 1ms [ms] / minimum pulse width that may pass, clamped to one millisecond [ms]
    bReset          : BOOL;              // 上升沿清抑制计数（饱和只是当拍报码，随段 0 预置自动销）/ rising edge clears the reject count, the saturation notice is single scan and clears itself
END_VAR
VAR_OUTPUT
    bOut            : BOOL;              // 过滤后的输出，合格脉冲宽度不失真 / filtered output, the width of an accepted pulse is preserved
    uRejectCount    : UDINT;             // 被吞掉的窄脉冲数 [次] / number of suppressed narrow pulses [count]
    bRejected       : BOOL;              // 本拍是否发生抑制（单拍，恒只活一个扫描周期）/ TRUE on the scan a pulse was suppressed, single scan only
    eErr            : UDINT;             // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;              // 故障级标志 / fault flag
END_VAR
VAR
    fbOnDelay       : TON;               // 上升沿确认窗，主体最前部无条件刷新 / high level confirmation timer, refreshed unconditionally at the top
    fbOffDelay      : TON;               // 下降沿确认窗，主体最前部无条件刷新 / low level confirmation timer, refreshed unconditionally at the top
    rtIn            : R_TRIG;            // 输入上升沿，主体最前部无条件刷新 / input rising edge, refreshed unconditionally at the top
    ftIn            : F_TRIG;            // 输入下降沿，主体最前部无条件刷新 / input falling edge, refreshed unconditionally at the top
    rtReset         : R_TRIG;            // 复位上升沿，主体最前部无条件刷新 / reset rising edge, refreshed unconditionally at the top
    bInRaw          : BOOL;              // 使能掩蔽后的输入 / input masked by the enable
    tMinEff         : TIME;              // 钳位后的最小宽度 [ms] / clamped minimum width [ms]
END_VAR
VAR CONSTANT
    DL_PWF_MIN          : TIME := T#1MS;                 // 最小宽度下限 [ms] / minimum width lower bound [ms]
    DL_PWF_WARN_MIN     : TIME := T#2MS;                 // 代理告警阈值（1ms 任务的极限确认窗）[ms] / proxy warning threshold [ms]
    DL_TIME_ZERO        : TIME := T#0S;                  // 零时长哨兵 [ms] / zero duration sentinel [ms]
    DL_UDINT_MAX        : UDINT := 16#FFFF_FFFF;         // 抑制计数上限 [次] / reject count upper bound [count]
    DL_ERR_NONE         : UDINT := 16#0000_0000;         // 无故障 / no error
END_VAR

// 段 0｜错误状态预置与单拍标志清销 / segment 0, preset the error state and clear the single scan flag
eErr      := DL_ERR_NONE;                 // 预置无错误 / preset no error
bError    := FALSE;                       // 预置无故障 / preset no fault
bRejected := FALSE;                       // 单拍标志每拍先销，防「只置不销」/ the single scan flag is cleared first

// 段 1｜宽度闸：非法钳 1ms 继续，不停机 / segment 1, width gate with clamping
IF tMinWidth <= DL_TIME_ZERO THEN
    tMinEff := DL_PWF_MIN;                // 钳到最小宽度 / clamp to the smallest width
    eErr    := 16#0001_03A5;              // 最小宽度非法已钳位（故障级）/ illegal minimum width clamped, fault level
    bError  := TRUE;                      // 置故障标志 / raise the fault flag
ELSE
    tMinEff := tMinWidth;                 // 正常值 / a healthy value
END_IF

// 段 2｜代理阈值提示：确认窗过小时扫描周期可能吃掉确认过程 / segment 2, proxy hint for a very short confirmation window
IF (tMinEff < DL_PWF_WARN_MIN) AND (eErr = DL_ERR_NONE) THEN
    eErr := 16#0001_045A;                 // 确认窗过小提示（信息级，不置 bError）/ short confirmation window hint, info level
END_IF

// 段 3｜定时器与边沿无条件刷新：两只看守的 IN 都串入 bEnable，失能即同步复位 / segment 3, unconditional refresh
bInRaw := bEnable AND bIn;                                    // 使能掩蔽 / mask by the enable
fbOnDelay ( IN := bInRaw,                PT := tMinEff );      // 高电平确认窗 / high level confirmation
fbOffDelay( IN := (NOT bInRaw) AND bEnable, PT := tMinEff );   // 低电平确认窗，失能时同步复位 / low level confirmation, reset while disabled
rtIn      ( CLK := bInRaw );                                   // 输入上升沿 / input rising edge
ftIn      ( CLK := bInRaw );                                   // 输入下降沿 / input falling edge
rtReset   ( CLK := bReset );                                   // 复位上升沿，与其余实例同段无条件刷新 / reset rising edge, refreshed unconditionally in the same segment

// 段 4｜复位沿：清抑制统计（引脚注释承诺「上升沿」，故必须真做沿判定，禁用电平清零）/ segment 4, the reset edge clears the suppression statistics
IF rtReset.Q THEN
    uRejectCount := 0;                    // 计数清零 / clear the count
END_IF

// 段 5｜失能直通：旁路时不得留门控残影 / segment 5, bypass without any residual gating
IF NOT bEnable THEN
    bOut := bIn;                          // 直通输入 / follow the input directly
ELSE
    // 段 6｜双侧确认搬运：高电平确认满才置高，低电平确认满才置低，故输出宽度与输入同宽 / segment 6, two sided transfer
    IF fbOnDelay.Q THEN
        bOut := TRUE;                     // 高电平已维持满最小宽度 / the high level lasted long enough
    END_IF
    IF fbOffDelay.Q THEN
        bOut := FALSE;                    // 低电平已维持满最小宽度 / the low level lasted long enough
    END_IF

    // 段 7｜窄脉冲判定：高电平未确认即回落 → 窄高脉冲；低电平未确认即回升 → 窄低脉冲 / segment 7, narrow pulse detection
    IF ftIn.Q AND (NOT bOut) THEN
        bRejected := TRUE;                // 窄高脉冲：上升后未确认就掉了 / a narrow high pulse fell before confirmation
    END_IF
    IF rtIn.Q AND bOut THEN
        bRejected := TRUE;                // 窄低脉冲：下降后未确认就回来了 / a narrow low pulse rose before confirmation
    END_IF

    // 段 8｜抑制计数：饱和后不再递增并报故障（统计已失真需复位）/ segment 8, reject counting with saturation
    IF bRejected THEN
        IF uRejectCount >= DL_UDINT_MAX THEN
            eErr   := 16#0001_03A6;       // 抑制计数饱和（故障级）/ reject count saturated, fault level
            bError := TRUE;               // 置故障标志 / raise the fault flag
        ELSE
            uRejectCount := uRejectCount + 1;   // 计数递增 / increment the count
        END_IF
    END_IF
END_IF
END_FUNCTION_BLOCK
