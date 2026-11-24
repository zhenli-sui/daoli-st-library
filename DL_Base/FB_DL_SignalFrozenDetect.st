(*
    组件名称 : FB_DL_SignalFrozenDetect
    所属子库 : DL_Base
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 信号冻结检测，窗内极差小于死区即判传感器卡死；NE107 的 eCheckFunction（功能自检）判据原子。
              取舍 ①：窗内只跟踪极值（fMin / fMax 增量更新），不开数组 —— 观察窗可能长达数分钟，
              按扫描周期存样本要几千个 LREAL，用极差判冻结只需两个数，内存与扫描开销都降到常数。
              取舍 ②：非有限输入不推进窗、不更新极值 —— NaN / INF 不是「冻结」也不是「变化」，
              把它们塞进极值会让整窗作废；本件暂停窗并发信息码，同时用第二只定时器累计「连续非有限」时长，
              超窗即判信号失效（03A3），与「冻结」严格区分：一个是传感器卡住，一个是信号链断了。
              取舍 ③：暂停窗的实现是定时器失电复位（保守侧）—— 严格「暂停」需要保存已累计时长，
              那就要引入额外时基量并面对漂移；宁可让窗重新起算，也只在「推迟判定」这个安全方向上让步。
              取舍 ④：解冻条件用「本拍增量超死区」而不是「极差超死区」—— 极差在窗满之后已经没用了，
              只有新增变化才说明传感器又开始动了，判据必须落在增量上。
    开源溯源 : T2-8 NE107 语义（eCheckFunction 需要功能自检判据）+ T0-1 变体线。判据、阈值、码位、；本件为道莅 clean-room 防御性实现（仅借 NE107 eCheckFunction 判据语义，零代码复制）。
              状态组织 100% 自有，零代码行与注释复制。
    本文件内含 : FUNCTION_BLOCK FB_DL_SignalFrozenDetect（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 参数闸 + 非有限闸 + 窗定时器 + 失效时长闸 + 极差容差判据
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 无顺序状态机（判据累加型），头注释已写明理由
              R7 ✓ 三只 TON 与 R_TRIG 全部在主体最前部无条件刷新，位于任何 IF 之外
              R8 ✓ 窗口缺省值、容差、计时上限全常量化
    错误码   : 16#0001_0458 [信息级] 输入非有限，窗暂停且极值不更新，bError = FALSE
               16#0001_0459 [信息级] 窗内极差为零（完全无抖动），bError = FALSE
               16#0001_03A2 [故障级] 窗口时长或死区非法，已钳缺省值继续，bError = TRUE
               16#0001_03A3 [故障级] 连续非有限超过一个窗口，判信号失效（区别于冻结），bError = TRUE
               16#0001_03A4 [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0458 用 / 16#0001_0459 用 ｜ 16#0001_03A2 用 / 16#0001_03A3 用 / 16#0001_03A4 预留
    遗留假设 : ① tFrozenFor 由一只 TON 的 ET 提供，封顶 T#24H；冻结超过 24 小时的极端工况下该值封顶，
              判定本身不受影响（bFrozen 已锁存）。此口径未实测。
              ② 窗定时器在非有限拍失电复位（保守侧），已在取舍 ③ 声明；若工艺要求「严格暂停」，
              应改由调用方注入 tDelta 自建计时，属后续变体，不在本版范围。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 4 入库
*)
FUNCTION_BLOCK FB_DL_SignalFrozenDetect
VAR_INPUT
    bEnable         : BOOL := TRUE;      // 使能，FALSE 时窗停走但不改变已锁存的冻结判定 / enable, FALSE stops the window but keeps the latched verdict
    fValue          : LREAL;             // 被监视量，同死区工程单位 [工程单位] / monitored value in the deadband unit [engineering unit]
    fMoveEps        : LREAL := 0.05;     // 判定「有变化」的最小增量，负值钳缺省 [工程单位] / smallest increment that counts as movement [engineering unit]
    tWindow         : TIME := T#30S;     // 观察窗时长，≤ 0 时钳缺省 [ms] / observation window length, clamped when not positive [ms]
    bReset          : BOOL;              // 上升沿清冻结判定与窗 / rising edge clears the verdict and the window
END_VAR
VAR_OUTPUT
    bFrozen         : BOOL;              // 冻结判定，锁存至输入恢复变化或复位 / frozen verdict latched until movement or reset
    tFrozenFor      : TIME;              // 已冻结时长，封顶 T#24H [ms] / time already frozen, capped at one day [ms]
    fSpan           : LREAL;             // 窗内极差 = 最大 − 最小 [工程单位] / span inside the window [engineering unit]
    bInvalidInput   : BOOL;              // 输入非有限标志（与冻结区分）/ non-finite input flag, distinct from the frozen verdict
    eErr            : UDINT;             // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;              // 故障级标志 / fault flag
END_VAR
VAR
    fbWindow        : TON;               // 观察窗定时器，主体最前部无条件刷新 / window timer, refreshed unconditionally at the top
    fbInvalid       : TON;               // 连续非有限时长定时器，主体最前部无条件刷新 / invalid duration timer, refreshed unconditionally at the top
    fbFrozen        : TON;               // 冻结时长定时器，主体最前部无条件刷新 / frozen duration timer, refreshed unconditionally at the top
    rtReset         : R_TRIG;            // 复位上升沿，主体最前部无条件刷新 / reset rising edge, refreshed unconditionally at the top
    bWinKick        : BOOL;              // 窗复位脉冲，置位后下一扫描周期窗重新起算 / window restart pulse, effective on the next scan
    fMinVal         : LREAL;             // 窗内最小值 [工程单位] / minimum inside the window [engineering unit]
    fMaxVal         : LREAL;             // 窗内最大值 [工程单位] / maximum inside the window [engineering unit]
    fPrevValue      : LREAL;             // 上一拍输入，用于增量判据 [工程单位] / previous sample used by the movement test [engineering unit]
    fMoveEpsEff     : LREAL;             // 生效死区，恒非负 [工程单位] / effective deadband, always non-negative [engineering unit]
    tWindowEff      : TIME;              // 生效窗口时长 [ms] / effective window length [ms]
    bValueFin       : BOOL;              // 当前输入是否有限 / whether the current input is finite
    bMoved          : BOOL;              // 本拍是否检出真实变化 / whether real movement was detected this scan
    bInitDone       : BOOL := FALSE;     // 首扫极值种子标志 / first scan seeding flag
END_VAR
VAR CONSTANT
    DL_MOVE_EPS_DEF     : LREAL := 0.05;                       // 死区缺省值 [工程单位] / default deadband [engineering unit]
    DL_WINDOW_DEF       : TIME := T#30S;                       // 窗口缺省值 [ms] / default window length [ms]
    DL_TIME_ZERO        : TIME := T#0S;                        // 零时长哨兵 [ms] / zero duration sentinel [ms]
    DL_FROZEN_PT_MAX    : TIME := T#24H;                       // 冻结时长上限 [ms] / frozen duration bound [ms]
    DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308;      // LREAL 最大有限值 [无量纲] / largest finite LREAL [dimensionless]
    DL_LREAL_ZERO       : LREAL := 0.0;                        // 零哨兵 [工程单位] / zero sentinel [engineering unit]
    DL_FLOAT_EPS        : LREAL := 1.0E-12;                    // 极差判零容差，禁用 = 判等 [工程单位] / tolerance of the zero span test [engineering unit]
    DL_ERR_NONE         : UDINT := 16#0000_0000;               // 无故障 / no error
END_VAR

// 段 0｜错误状态预置 / segment 0, preset the error state
eErr   := DL_ERR_NONE;                    // 预置无错误 / preset no error
bError := FALSE;                          // 预置无故障 / preset no fault
bMoved := FALSE;                          // 本拍未检出变化 / no movement detected this scan

// 段 1｜参数闸：窗口与死区非法时钳缺省值继续 / segment 1, parameter gate with clamping
IF tWindow <= DL_TIME_ZERO THEN
    tWindowEff := DL_WINDOW_DEF;          // 钳缺省窗口 / clamp to the default window
    eErr   := 16#0001_03A2;               // 参数非法（故障级）/ illegal parameter, fault level
    bError := TRUE;                       // 置故障标志 / raise the fault flag
ELSE
    tWindowEff := tWindow;                // 正常值 / a healthy value
END_IF
IF (fMoveEps <> fMoveEps) OR (ABS(fMoveEps) > DL_LREAL_MAX_FINITE) OR (fMoveEps < DL_LREAL_ZERO) THEN
    fMoveEpsEff := DL_MOVE_EPS_DEF;       // 非有限或负值钳缺省 / a non-finite or negative deadband falls back to the default
    eErr   := 16#0001_03A2;               // 参数非法（故障级）/ illegal parameter, fault level
    bError := TRUE;                       // 置故障标志 / raise the fault flag
ELSE
    fMoveEpsEff := fMoveEps;              // 正常值 / a healthy value
END_IF

// 段 2｜三只定时器与边沿无条件刷新（任何 IF 之前）/ segment 2, three timers and the edge refreshed unconditionally
bValueFin := (fValue = fValue) AND (ABS(fValue) <= DL_LREAL_MAX_FINITE);   // 有限性判定 / finiteness test
bInvalidInput := NOT bValueFin;                                            // 对外暴露非有限标志 / publish the non-finite flag
fbWindow ( IN := bEnable AND bValueFin AND NOT bWinKick, PT := tWindowEff );
fbInvalid( IN := bInvalidInput,                          PT := tWindowEff );
fbFrozen ( IN := bFrozen AND bEnable,                    PT := DL_FROZEN_PT_MAX );
rtReset  ( CLK := bReset );
IF bWinKick THEN
    bWinKick := FALSE;                    // 复位脉冲只活一拍，本拍用完即销 / the restart pulse lives exactly one scan
END_IF
tFrozenFor := fbFrozen.ET;                // 已冻结时长 / elapsed frozen time

// 段 3｜非有限处理：不更新极值、不推进窗，并累计失效时长 / segment 3, non-finite handling, the window is not advanced
IF bInvalidInput THEN
    IF eErr = DL_ERR_NONE THEN
        eErr := 16#0001_0458;             // 输入非有限，窗暂停（信息级）/ non-finite input, the window pauses, info level
    END_IF
    IF fbInvalid.Q THEN
        eErr   := 16#0001_03A3;           // 连续非有限超一个窗口，判信号失效（故障级）/ invalid for a full window, fault level
        bError := TRUE;                   // 置故障标志 / raise the fault flag
    END_IF
END_IF

// 段 4｜首扫种子：极值与上拍值同时落定，防「0 → 当前值」被当成一次变化 / segment 4, first scan seeding
IF NOT bInitDone THEN
    IF bValueFin THEN
        fMinVal    := fValue;             // 最小值种子 / seed the minimum
        fMaxVal    := fValue;             // 最大值种子 / seed the maximum
        fPrevValue := fValue;             // 上拍值种子 / seed the previous sample
    END_IF
    bInitDone := TRUE;                    // 种子只做一次 / seed exactly once
    fSpan     := DL_LREAL_ZERO;           // 首扫极差为 0 / the span starts at zero
ELSIF bValueFin THEN
    // 段 5｜极值增量更新 / segment 5, incremental extreme tracking
    IF fValue < fMinVal THEN
        fMinVal := fValue;                // 刷新最小 / refresh the minimum
    END_IF
    IF fValue > fMaxVal THEN
        fMaxVal := fValue;                // 刷新最大 / refresh the maximum
    END_IF
    fSpan := fMaxVal - fMinVal;           // 窗内极差 / the span inside the window

    // 段 6｜增量判据：本拍真实变化即解冻、清窗、重种极值 / segment 6, movement releases the verdict and restarts the window
    IF ABS(fValue - fPrevValue) > fMoveEpsEff THEN
        bMoved := TRUE;                   // 检出真实变化 / real movement detected
    END_IF
    fPrevValue := fValue;                 // 上拍值无条件刷新 / the previous sample is always refreshed
    IF bMoved THEN
        bFrozen := FALSE;                 // 解冻 / release the verdict
        bWinKick := TRUE;                 // 窗从下一扫描周期重新起算 / the window restarts on the next scan
        fMinVal := fValue;                // 极值以当前值重种 / re-seed the extremes with the current sample
        fMaxVal := fValue;                // 极值基准取当前值 / extrema baseline takes current value
        fSpan   := DL_LREAL_ZERO;         // 极差归零 / reset the span
    ELSE
        // 段 7｜冻结判定：窗满且极差小于死区 / segment 7, frozen verdict when the window is full and the span is tiny
        IF fbWindow.Q AND (fSpan < fMoveEpsEff) THEN
            bFrozen := TRUE;              // 锁存冻结判定 / latch the frozen verdict
        END_IF
        IF (ABS(fSpan) < DL_FLOAT_EPS) AND (eErr = DL_ERR_NONE) THEN
            eErr := 16#0001_0459;         // 窗内极差为零（信息级）/ zero span inside the window, info level
        END_IF
    END_IF
END_IF

// 段 8｜复位沿：清判定与窗（放在判定之后，保证本拍先诊断再清）/ segment 8, reset edge after the diagnosis
IF rtReset.Q THEN
    bFrozen := FALSE;                     // 清冻结判定 / clear the verdict
    bWinKick := TRUE;                     // 窗重新起算 / restart the window
    fSpan := DL_LREAL_ZERO;               // 极差归零 / reset the span
    IF bValueFin THEN
        fMinVal := fValue;                // 极值重种 / re-seed the extremes
        fMaxVal := fValue;                // 极值基准取当前值 / extrema baseline takes current value
    END_IF
END_IF
END_FUNCTION_BLOCK
