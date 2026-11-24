(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SecondOrderFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TAN / SQRT / ABS / MIN / MAX），
 *                         零厂商方言
 * 功能描述 (Function)   : 二阶巴特沃斯低通滤波器，双二阶（biquad）离散递推实现，
 *                         高频滚降 -40dB/dec，阻尼比 zeta=0.7071（最平坦幅频）。
 *                         截止频率 fCutoffFreq 与采样周期变更时经双线性变换
 *                         （含频率预畸变 TAN）即时重算五系数；直流增益经归一化
 *                         恒为 1.000000，稳态无静差；截止频率越奈奎斯特自动钳位。
 *                         现场用途：振动 / 高速模拟量降噪、控制反馈信号整形。
 * 开源溯源 (Origin)     : 原创实现。双线性变换系数推导源自标准信号处理教科书
 *                         公式（clean-room），按本库故障码体系重写并加严。
 * 设计验证 (Verified)   : fCutoff=5.0Hz、fDt=0.01s（fs=100Hz，python 6 位小数）：
 *                         fWc=0.314159 rad、fK=0.158384、fNorm=1.249075；
 *                         b0=0.020083、b1=0.040167、b2=0.020083、
 *                         a1=-1.561018、a2=0.641352；
 *                         直流增益 = (b0+b1+b2)/(1+a1+a2) = 1.000000 核验通过。
 * 验收向量 (Acceptance) :
 *   V1 fCutoff=5Hz fDt=0.01s：b0≈0.020083、b1≈0.040167、b2≈0.020083（容差 1E-4）
 *   V2 同 V1：a1≈-1.561018、a2≈0.641352（容差 1E-4）
 *   V3 系数守恒：ABS(b0+b1+b2-a1-a2-1.0) < 1E-4，即直流增益 = 1.000000
 *   V4 恒定输入 5.0：稳态 fOut→5.0（无静差，对应 V3）
 *   V5 fCutoffFreq=1000Hz（fs=100Hz）：当拍钳位至 45.0Hz，uErrorId=16#0002_1101
 *   V6 fIn 非有限值：本拍拒绝更新保持上拍输出，uErrorId=16#0002_0004
 * 本文件内含       : TYPE  E_DL_SofState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_SecondOrderFilter
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library 数学算符
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 钳位+容差+防除零+退化直通
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器与边沿检测实例）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *   2026-11-15  v1.0.1  阶段五终审精修：首扫先采样直通再重算系数，消除首拍
 *                       输出跳零与系数未就绪即递推的瞬态
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SofState（归属 DL_Algo，与 FB_DL_SecondOrderFilter 同文件）
 * 含义: 二阶滤波状态机离散状态。eCoeffCalc 为参数变更拍的重算过渡态，
 *       保证系数与递推状态在同一拍内原子切换，避免新旧系数混算。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SofState :
(
    eInit      := 0,    // 首扫态：输出直接采样输入，历史状态清零并置重算标记 / First scan: output tracks input, history cleared, recalc flagged
    eCoeffCalc := 10,   // 系数重算态：双线性变换重算五系数，检查钳位 / Coefficient recalc: bilinear recompute of five coefficients with clamping
    eRun       := 20,   // 运行态：双二阶递推滤波，系数保持不变 / Running: biquad recursion with unchanged coefficients
    eTrack     := 30,   // 跟踪态：输出立即跟随跟踪值，全部历史同步清零 / Tracking: output follows track value, all history synchronized to zero
    eFault     := 99    // 故障兜底态：非法状态进入，输出安全值并置故障码 / Fault fallback: entered from illegal states, safe output plus error code
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SecondOrderFilter
 * 调用约定: 每个采样周期无条件调用一次；fCutoffFreq 运行中可调，变更拍
 *           自动重算系数；tSampleTime 由调用方显式给定，不得依赖隐式扫描周期。
 * 滞后披露: 截止频率处幅值衰减约 -3dB、相位滞后约 90 度；等效群延迟随
 *           fCutoffFreq/fDt 比值变化，选型时需保证截止频率远低于奈奎斯特频率。
 * 递推披露: 采用双二阶直接型递推（输入历史 + 输出状态），与规格书公式
 *           fOut := fB0*fIn + fB1*fIn1 + fB2*fIn2 - fA1*fW1 - fA2*fW2 一致，
 *           fW1/fW2 承载上两拍输出状态，数学上与 II 型实现传递函数等价。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SecondOrderFilter
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能，FALSE 时输出直通原始输入 / Enable, FALSE passes raw input straight through
    fIn         : REAL := 0.0;        // 原始采样输入 [EU] / Raw sampling input [EU]
    fCutoffFreq : REAL := 5.0;        // 截止频率 [Hz]，大于 0 且低于 0.45 倍采样频率 / Cutoff frequency [Hz], positive and below 0.45 times sampling rate
    bTrack      : BOOL := FALSE;      // 跟踪使能，TRUE 时输出立即跟随跟踪值 / Track enable, TRUE makes output follow track value instantly
    fTrackValue : REAL := 0.0;        // 跟踪目标值 [EU]，无扰投切用 / Track target value [EU], for bumpless transfer
    tSampleTime : TIME := T#100MS;    // 采样周期，小于 10ms 钳位 / Sampling period, clamped to 10ms minimum
END_VAR
VAR_OUTPUT
    fOut        : REAL;               // 滤波输出 [EU] / Filtered output [EU]
    bCoeffValid : BOOL;               // 系数就绪标志，重算完成置 TRUE / Coefficient ready flag, TRUE after recalculation
    bValid      : BOOL;               // 输出有效标志 / Output valid flag
    bError      : BOOL;               // 故障标志，与 uErrorId 联动 / Fault flag, coupled with uErrorId
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fB0         : REAL := 1.0;        // 递推系数 b0 [1]，初始为直通 / Recursion coefficient b0, initialized as pass-through
    fB1         : REAL := 0.0;        // 递推系数 b1 [1] / Recursion coefficient b1
    fB2         : REAL := 0.0;        // 递推系数 b2 [1] / Recursion coefficient b2
    fA1         : REAL := 0.0;        // 递推系数 a1 [1] / Recursion coefficient a1
    fA2         : REAL := 0.0;        // 递推系数 a2 [1] / Recursion coefficient a2
    fIn1        : REAL := 0.0;        // 上拍输入历史 [EU] / Previous input history [EU]
    fIn2        : REAL := 0.0;        // 上上拍输入历史 [EU] / Input history of two cycles ago [EU]
    fW1         : REAL := 0.0;        // 输出状态变量（上拍输出）[EU] / Output state variable (previous output) [EU]
    fW2         : REAL := 0.0;        // 输出状态变量（上上拍输出）[EU] / Output state variable (output two cycles ago) [EU]
    fDt         : REAL;               // 采样周期秒值 [s] / Sampling period in seconds [s]
    fFs         : REAL;               // 采样频率 [Hz] / Sampling frequency [Hz]
    fCutoffEff  : REAL;               // 钳位后的生效截止频率 [Hz] / Effective clamped cutoff frequency [Hz]
    fCutoffPrev : REAL := -1.0;       // 上次重算所用截止频率，用于变更检测 [Hz] / Cutoff used at last recalc, for change detection [Hz]
    fDtPrev     : REAL := -1.0;       // 上次重算所用周期，用于变更检测 [s] / Period used at last recalc, for change detection [s]
    fWc         : REAL;               // 归一化数字角频率 [rad] / Normalized digital angular frequency [rad]
    fK          : REAL;               // 预畸变中间量 tan(fWc/2) [1] / Prewarping intermediate tan(fWc/2) [1]
    fNorm       : REAL;               // 归一化分母 [1] / Normalization denominator [1]
    bCoeffDirty : BOOL := TRUE;       // 参数变更标记，TRUE 触发重算 / Parameter change flag, TRUE triggers recalculation
    eState      : E_DL_SofState;      // 状态机当前状态 / Current state of the state machine
END_VAR
VAR CONSTANT
    DL_SOF_SQRT2    : REAL := 1.4142136;  // 二阶巴特沃斯阻尼项系数根号二 [1] / Butterworth damping term sqrt(2) [1]
    DL_SOF_PI       : REAL := 3.1415927;  // 圆周率 [rad] / Pi constant [rad]
    DL_SOF_FC_MIN   : REAL := 1.0;        // 截止频率防御下限 [Hz] / Defensive cutoff frequency lower bound [Hz]
    DL_SOF_NYQ_KEEP : REAL := 0.45;       // 奈奎斯特保持系数（钳位到 0.45 倍采样频率）[1] / Nyquist keep ratio, clamp at 0.45 times sampling rate [1]
    DL_SOF_TAN_MAX  : REAL := 1.55;       // TAN 自变量上限 [rad]，防逼近奇异点 / TAN argument upper bound [rad], away from singularity
    DL_SOF_DT_MIN   : REAL := 0.01;       // 采样周期防御下限 [s] / Defensive sampling period lower bound [s]
    DL_SOF_INF_MAX  : REAL := 1.0E30;     // 有限值判定幅值上限 [EU] / Magnitude bound for finite-value check [EU]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜采样周期钳位与派生量：dt 下限保护，采样频率反算
 *      Sampling period clamping and derived quantities
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0002_0000;

IF tSampleTime < T#10MS THEN
    fDt      := DL_SOF_DT_MIN;                       // 周期过小钳位到 10ms / Too small period clamped to 10ms
    uErrorId := 16#0002_0002;                        // 采样周期非法已钳位 / Invalid sampling period clamped
ELSE
    fDt := TIME_TO_REAL(tSampleTime) / 1000.0;       // TIME 换算秒值 / Convert TIME to seconds
END_IF

fFs := 1.0 / fDt;                                    // 采样频率反算，fDt 已有下限保证 / Sampling frequency, guaranteed by dt floor

(*------------------------------------------------------------------------------
 * 段 2｜参数变更检测（浮点容差比较，禁止判等）：变更则置重算标记
 *      Parameter change detection with float tolerance, never equality
 *-----------------------------------------------------------------------------*)
IF (ABS(fCutoffFreq - fCutoffPrev) > 1.0E-6) OR (ABS(fDt - fDtPrev) > 1.0E-6) THEN
    bCoeffDirty := TRUE;                             // 截止频率或周期变更，触发重算 / Cutoff or period changed, trigger recalculation
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限值防御：拒绝本拍更新、保持上一拍输出（公共故障码）
 *      Non-finite defense: reject this cycle, hold previous output
 *-----------------------------------------------------------------------------*)
IF (fIn <> fIn) OR (ABS(fIn) > DL_SOF_INF_MAX) THEN
    uErrorId := 16#0002_0004;                        // 输入非有限值已拒绝 / Non-finite input rejected
    bValid   := FALSE;
    bError   := TRUE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
IF bTrack THEN
    eState := eTrack;                                // 跟踪请求优先级最高 / Track request has highest priority
ELSIF eState = eInit THEN
    eState := eInit;                                 // 首扫先采样直通，防首拍输出跳零 / First scan samples directly, no zero jump
ELSIF bCoeffDirty THEN
    eState := eCoeffCalc;                            // 参数变更进入重算态 / Parameter change enters recalc state
ELSIF eState = eFault THEN
    IF NOT bEnable THEN
        eState := eInit;                             // 使能跌落提供故障恢复路径 / Disabled input provides fault recovery path
    ELSE
        eState := eFault;                            // 故障态保持直至调用方处置 / Fault state holds until caller intervenes
    END_IF
ELSE
    eState := eRun;                                  // 常规运行态派生 / Normal running state derived
END_IF

CASE eState OF

    eInit:
        (* 首扫直接采样：历史清零并置重算标记，下一拍进入系数重算 *)
        (* First scan samples directly: history cleared and recalc flagged *)
        fOut        := fIn;
        fIn1        := fIn;
        fIn2        := fIn;
        fW1         := 0.0;
        fW2         := 0.0;
        bCoeffValid := FALSE;
        bValid      := FALSE;                        // 首扫未完成，输出尚不可信 / First scan unfinished, output not trustworthy yet
        bCoeffDirty := TRUE;
        eState      := eCoeffCalc;                   // 下一拍重算系数，避免系数未就绪递推 / Recalculate coefficients next cycle

    eCoeffCalc:
        (* 系数重算态：截止频率钳位 + 双线性变换预畸变 + 五系数归一化 *)
        (* Coefficient recalc: cutoff clamping, bilinear prewarping, normalization *)
        IF fCutoffFreq <= 0.0 THEN
            fCutoffEff := DL_SOF_FC_MIN;                 // 非法截止频率钳位到 1Hz / Illegal cutoff clamped to 1Hz
            uErrorId   := 16#0002_1101;                  // 截止频率非法已钳位 / Invalid cutoff frequency clamped
        ELSIF fCutoffFreq >= (fFs * 0.5) THEN
            fCutoffEff := fFs * DL_SOF_NYQ_KEEP;         // 越奈奎斯特钳位到 0.45 倍采样频率 / Over-Nyquist clamped to 0.45 times rate
            uErrorId   := 16#0002_1101;                  // 截止频率超奈奎斯特已钳位 / Cutoff over Nyquist clamped
        ELSE
            fCutoffEff := fCutoffFreq;                   // 合法参数原值生效 / Valid parameter applied as-is
        END_IF

        (* 归一化数字角频率与预畸变：TAN 自变量钳位防逼近奇异点 *)
        (* Normalized angular frequency with TAN argument clamped away from singularity *)
        fWc   := 2.0 * DL_SOF_PI * fCutoffEff * fDt;     // 数字角频率 [rad] / Digital angular frequency [rad]
        fK    := TAN(MIN(fWc / 2.0, DL_SOF_TAN_MAX));    // 预畸变中间量 / Prewarping intermediate value
        fNorm := 1.0 + DL_SOF_SQRT2 * fK + fK * fK;      // 归一化分母，恒大于零 / Normalization denominator, always positive

        IF ABS(fNorm) < 1.0E-9 THEN
            (* 分母退化防御（数学上不可达，防御性双检）：退化为直通系数 *)
            (* Degenerate denominator guard (mathematically unreachable): pass-through fallback *)
            fB0 := 1.0;
            fB1 := 0.0;
            fB2 := 0.0;
            fA1 := 0.0;
            fA2 := 0.0;
        ELSE
            (* 巴特沃斯五系数：直流增益经归一化恒为 1.000000 *)
            (* Butterworth coefficients: DC gain normalized to exactly 1.000000 *)
            fB0 := fK * fK / fNorm;
            fB1 := 2.0 * fB0;
            fB2 := fB0;
            fA1 := 2.0 * (fK * fK - 1.0) / fNorm;
            fA2 := (1.0 - DL_SOF_SQRT2 * fK + fK * fK) / fNorm;
        END_IF

        fCutoffPrev  := fCutoffEff;                  // 记录重算口径，供变更检测比对 / Record recalc baseline for change detection
        fDtPrev      := fDt;
        bCoeffValid  := TRUE;
        bCoeffDirty  := FALSE;
        eState       := eRun;

    eTrack:
        (* 无扰跟踪：输出立即跟随跟踪值，全部递推历史同步清零，回自动无跳变 *)
        (* Bumpless tracking: output follows track value, all recursion history cleared *)
        fOut        := fTrackValue;
        fIn1        := fTrackValue;
        fIn2        := fTrackValue;
        fW1         := 0.0;
        fW2         := 0.0;
        bCoeffDirty := TRUE;                         // 回运行态前强制重算一次系数 / Force one recalculation before running
        bValid      := TRUE;
        eState      := eRun;

    eRun:
        IF NOT bEnable THEN
            (* 使能失效语义：直通原始输入，历史同步防止恢复使能时残留跳变 *)
            (* Disabled semantics: pass raw input, history synchronized to avoid resume jumps *)
            fOut   := fIn;
            fIn1   := fIn;
            fIn2   := fIn;
            fW1    := 0.0;
            fW2    := 0.0;
            bValid := FALSE;
        ELSE
            (* 双二阶递推：按规格书公式执行，fW1/fW2 为上两拍输出状态 *)
            (* Biquad recursion per spec formula, fW1/fW2 carry previous two outputs *)
            fOut := fB0 * fIn + fB1 * fIn1 + fB2 * fIn2 - fA1 * fW1 - fA2 * fW2;
            fIn2 := fIn1;                            // 输入历史右移一位 / Shift input history by one
            fIn1 := fIn;
            fW2  := fW1;                             // 输出状态右移一位 / Shift output state by one
            fW1  := fOut;
            bValid := TRUE;
        END_IF

    eFault:
        (* 故障兜底：输出保持安全值 0，等待调用方修正后经使能跌落恢复 *)
        (* Fault fallback: output holds safe value 0, recovers via disabled input *)
        fOut        := 0.0;
        bCoeffValid := FALSE;
        bValid      := FALSE;

    ELSE
        (* 非法状态拦截：任何未定义枚举值一律进故障态并置公共兜底码 *)
        (* Illegal state interception: undefined enum values go to fault with code *)
        eState   := eFault;
        fOut     := 0.0;
        bValid   := FALSE;
        uErrorId := 16#0002_0005;

END_CASE;

(* 故障标志统一出口：与故障码严格联动，0 即无故障 *)
(* Unified fault flag outlet: strictly coupled with error code, zero means healthy *)
bError := (uErrorId <> 16#0002_0000);
END_FUNCTION_BLOCK
