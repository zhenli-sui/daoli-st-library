(*
    组件名称 : FB_DL_SignalChangeCounter
    所属子库 : DL_Base
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 带死区与最小间隔的模拟量变化次数统计，用于阀动作次数、执行机构寿命台账、工艺参数漂移审计。
              取舍 ①：判据带死区且禁浮点判等 —— 阀位从 32.0 抖到 32.0001 不是「动作」；
              本件一律 ABS(现值 − 基准) > 死区，绝不用 = / <>。
              取舍 ②（本件核心）：抖动也刷新基准 —— 若「间隔不足」时只加抖动计数而不更新基准，
              同一段连续爬升会被逐拍重复判为抖动，一次真实动作被拆成上千次抖动，主计数永远不涨。
              这是本件最容易被写错的地方，也是它与「简单沿计数」的根本差别。
              取舍 ③：复位沿不清基准值 —— 清基准会让下一拍在「基准 = 0」与「现值 = 当前值」之间
              凭空产生一次虚假变化，台账凭空多一次动作。计数可清、基准不可清。
              取舍 ④：间隔用 TON 的 ET 自建「距上次接受的时间」，靠单拍踢一脚（IN 拉低一拍）复位；
              不引入平台时刻函数，跨平台口径一致。
    开源溯源 : T0-1 变体线 + T2-1 LGF 计数与边沿子族（只借「变化次数审计」这一语义）。模拟量 + 死区 +；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              抖动分流的形态为自有扩展，码位、分级、饱和策略 100% 自有，零代码行与注释复制。
    本文件内含 : FUNCTION_BLOCK FB_DL_SignalChangeCounter（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 死区闸 + 非有限闸 + 计数饱和 + 首拍种子（防虚假首变化）
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 无顺序状态机（判据累加型），头注释已写明理由
              R7 ✓ TON / R_TRIG 实例在主体最前部无条件刷新，位于任何 IF 之外
              R8 ✓ 上限、饱和值、计时上限全常量化
    错误码   : 16#0001_0454 [信息级] 输入非有限，基准保持不变，窗内判定跳过，bError = FALSE
               16#0001_0455 [信息级] 主计数饱和（不再递增），bSaturated = TRUE，bError = FALSE
               16#0001_039C [故障级] 死区为负或非有限，按绝对值/零继续，bError = TRUE
               16#0001_039D [故障级] 预留禁用（不得挪用）
               16#0001_039E [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0454 用 / 16#0001_0455 用 ｜ 16#0001_039C 用 / 16#0001_039D 预留 / 16#0001_039E 预留
    遗留假设 : ① 距上次接受的时长由 TON 的 ET 提供，ET 上限为 PT（=T#24D）；超过 24 天不变化的设备，
              tSinceLast 会封顶在 24 天，间隔判据退化为「恒满足」——对寿命台账无实质影响，此口径未实测。
              ② 抖动计数与主计数共用 bSaturated 观测（同族计数饱和不另设码，避免凑槽，R90）。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 4 入库
*)
FUNCTION_BLOCK FB_DL_SignalChangeCounter
VAR_INPUT
    bEnable         : BOOL := TRUE;      // 使能，FALSE 时冻结计数与基准，不产生新事件 / enable, FALSE freezes both the counts and the baseline
    fValue          : LREAL;             // 被监视量，如阀位 [%] / monitored value, e.g. valve position [percent]
    fDeadband       : LREAL := 1.0;      // 变化死区，同工程单位；负值按绝对值、非有限按 0 / change deadband in the same unit, negative is taken by magnitude
    tMinInterval    : TIME := T#1S;      // 最小有效变化间隔，短于此间隔的变化计入抖动 [ms] / minimum interval of an accepted change [ms]
    bReset          : BOOL;              // 上升沿清零主计数与抖动计数（不清基准）/ rising edge clears both counts but never the baseline
END_VAR
VAR_OUTPUT
    uCount          : UDINT;             // 有效变化次数，饱和后停止递增 [次] / accepted change count, stops at saturation [count]
    uChatterCount   : UDINT;             // 抖动次数（间隔不足的变化），不计入主计数 [次] / chatter count for changes inside the minimum interval [count]
    fLastAccepted   : LREAL;             // 上次被接受（或判为抖动）的值，即当前基准 [工程单位] / the baseline value, updated on every judged change [engineering unit]
    tSinceLast      : TIME;              // 距上次接受/判抖的时长，封顶 T#24D [ms] / time since the last judged change, capped at one day [ms]
    bSaturated      : BOOL;              // 任一同族计数已达上限 / at least one counter reached its upper bound
    eErr            : UDINT;             // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;              // 故障级标志 / fault flag
END_VAR
VAR
    fbElapsed       : TON;               // 间隔计时器，主体最前部无条件刷新 / interval timer, refreshed unconditionally at the top
    rtReset         : R_TRIG;            // 复位上升沿，主体最前部无条件刷新 / reset rising edge, refreshed unconditionally at the top
    bTimerKick      : BOOL;              // 计时器复位脉冲，置位后下一扫描周期 ET 归零 / reset pulse, the elapsed time restarts on the next scan
    fDeadbandEff    : LREAL;             // 生效死区，恒非负 [工程单位] / effective deadband, always non-negative [engineering unit]
    bValueFin       : BOOL;              // 当前输入是否有限 / whether the current input is finite
    bInitDone       : BOOL := FALSE;     // 首扫基准种子标志，防「0 → 当前值」的虚假首变化 / first scan seeding flag
END_VAR
VAR CONSTANT
    DL_UDINT_MAX        : UDINT := 16#FFFF_FFFF;               // 计数上限 [次] / counter upper bound [count]
    DL_TON_PT_MAX       : TIME := T#24D;                       // 计时器上限，同时是 tSinceLast 的封顶值 [ms] / timer bound and the cap of tSinceLast [ms]
    DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308;     // LREAL 最大有限值 [无量纲] / largest finite LREAL [dimensionless]
    DL_LREAL_ZERO       : LREAL := 0.0;                        // 零哨兵 [工程单位] / zero sentinel [engineering unit]
    DL_UDINT_ZERO       : UDINT := 0;                          // 计数零哨兵 [次] / counter zero sentinel [count]
    DL_ERR_NONE         : UDINT := 16#0000_0000;               // 无故障 / no error
END_VAR

// 段 0｜错误状态预置 / segment 0, preset the error state
eErr   := DL_ERR_NONE;                       // 预置无错误 / preset no error
bError := FALSE;                             // 预置无故障 / preset no fault

// 段 1｜定时器与边沿无条件刷新（任何 IF 之前）；踢一脚即复位 ET / segment 1, unconditional refresh, a kick restarts the elapsed time
fbElapsed( IN := NOT bTimerKick, PT := DL_TON_PT_MAX );
rtReset  ( CLK := bReset );
IF bTimerKick THEN
    bTimerKick := FALSE;                     // 复位脉冲只活一拍，本拍用完即销 / the kick lives exactly one scan
END_IF
tSinceLast := fbElapsed.ET;                  // 距上次判定变化的时长 / elapsed time since the last judged change

// 段 2｜死区参数闸：负值取绝对值、非有限按 0，不停机 / segment 2, deadband gate, never stops the machine
IF (fDeadband <> fDeadband) OR (ABS(fDeadband) > DL_LREAL_MAX_FINITE) THEN
    fDeadbandEff := DL_LREAL_ZERO;           // 非有限按零处理 / a non-finite deadband is treated as zero
    eErr   := 16#0001_039C;                  // 死区非法（故障级）/ illegal deadband, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
ELSIF fDeadband < DL_LREAL_ZERO THEN
    fDeadbandEff := -fDeadband;              // 负值取绝对值继续 / take the magnitude and carry on
    eErr   := 16#0001_039C;                  // 死区非法（故障级）/ illegal deadband, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
ELSE
    fDeadbandEff := fDeadband;               // 正常值 / a healthy value
END_IF

// 段 3｜复位沿：只清计数，不清基准 / segment 3, the reset edge clears the counts but never the baseline
IF rtReset.Q THEN
    uCount        := DL_UDINT_ZERO;          // 主计数清零 / clear the accepted count
    uChatterCount := DL_UDINT_ZERO;          // 抖动计数清零 / clear the chatter count
    bSaturated    := FALSE;                  // 解除饱和 / release the saturation flag
END_IF

// 段 4｜输入有限性判定 / segment 4, input finiteness
bValueFin := (fValue = fValue) AND (ABS(fValue) <= DL_LREAL_MAX_FINITE);   // 自比较判 NaN，幅值判 INF / self compare for NaN, magnitude for INF
IF NOT bValueFin THEN
    IF eErr = DL_ERR_NONE THEN
        eErr := 16#0001_0454;                // 输入非有限，基准保持不变（信息级）/ non-finite input, the baseline is untouched, info level
    END_IF
END_IF

// 段 5｜首扫种子：不种子就会把「0 → 当前值」记成一次虚假动作 / segment 5, first scan seeding avoids a phantom change
IF NOT bInitDone THEN
    IF bValueFin THEN
        fLastAccepted := fValue;             // 基准取首拍值 / seed the baseline with the first sample
    END_IF
    bInitDone := TRUE;                       // 种子只做一次 / seed exactly once
ELSIF bEnable AND bValueFin THEN
    // 段 6｜死区判据 + 间隔分流（核心：抖动也刷新基准）/ segment 6, deadband test and interval split, chatter updates the baseline too
    IF ABS(fValue - fLastAccepted) > fDeadbandEff THEN
        IF fbElapsed.ET >= tMinInterval THEN
            IF uCount >= DL_UDINT_MAX THEN
                bSaturated := TRUE;          // 主计数饱和 / the accepted count is saturated
                IF eErr = DL_ERR_NONE THEN
                    eErr := 16#0001_0455;    // 计数饱和（信息级）/ counter saturated, info level
                END_IF
            ELSE
                uCount := uCount + 1;        // 有效变化计数 / count the accepted change
            END_IF
        ELSE
            IF uChatterCount >= DL_UDINT_MAX THEN
                bSaturated := TRUE;          // 抖动计数饱和，同族观测 / the chatter count saturates, same observation flag
            ELSE
                uChatterCount := uChatterCount + 1;   // 间隔不足计入抖动 / a change inside the interval counts as chatter
            END_IF
        END_IF
        fLastAccepted := fValue;             // 关键：无论接受还是抖动，基准一律刷新 / the baseline is refreshed in both branches
        bTimerKick    := TRUE;               // 下一扫描周期重新起算间隔 / the interval restarts on the next scan
    END_IF
END_IF
END_FUNCTION_BLOCK
