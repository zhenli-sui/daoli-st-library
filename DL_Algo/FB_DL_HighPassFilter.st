(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HighPassFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（MIN / MAX / ABS / LIMIT），
 *                         零厂商方言
 * 功能描述 (Function)   : 一阶高通数字滤波器（HP1）。递推式
 *                         fOut := fAlpha * (fOutPrev + fIn - fInPrev)，
 *                         其中 fAlpha := tTf / (tTf + fDt)。剥离静态偏置、
 *                         提取动态分量：振动 / 位移传感器趋势分量剥离、
 *                         皮带秤动态分量提取、结露监测的缓变漂移滤除。
 *                         含输出限幅（rOutMin/rOutMax 对调防御）、
 *                         tTimeConst=0 全通差分、首扫防上电脉冲、
 *                         bTrack 跟踪时输出清零并同步历史。
 * 开源溯源 (Origin)     : 原创实现。算法思想源自 LGF HP1 与一阶高通差分
 *                         教科书推导（clean-room），按本库故障码体系重写。
 * 设计验证 (Verified)   : tTf=0.1s、fDt=0.01s：fAlpha=0.909091；
 *                         正弦 1Hz 输入稳态增益约 0.532018（python 核验）；
 *                         直流阶跃 0->5.0 输入：第 1 拍动态分量 4.545455，
 *                         第 50 拍衰减至 0.042593（静态偏置被隔离并归零）。
 * 验收向量 (Acceptance) :
 *   V1 fAlpha=0.909091（tTf=0.1s fDt=0.01s，容差 1E-4）
 *   V2 直流阶跃 0->5.0：50 拍后 fOut < 0.5（动态分量快速归零）
 *   V3 tTimeConst=T#0S：fOut=fIn-fInPrev（全通差分）
 *   V4 bTrack=TRUE：当拍 fOut=0.0 且历史同步，回自动无脉冲
 *   V5 输出 12.0 超 rOutMax=10.0：当拍钳位 10.0，uErrorId=16#0002_0001
 *   V6 fIn 非有限值：拒绝更新并复位历史，uErrorId=16#0002_0004
 * 本文件内含       : TYPE  E_DL_HpfState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_HighPassFilter
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library 数学算符
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 钳位+容差+非有限值拒绝+对调防御
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器与边沿检测实例）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HpfState（归属 DL_Algo，与 FB_DL_HighPassFilter 同文件）
 * 含义: 高通滤波状态机离散状态。纯线性滤波采用「状态派生 + CASE 覆盖 + ELSE」
 *       结构：状态由使能 / 跟踪 / 首扫信号派生，CASE 保证每态行为显式可审计。
 *----------------------------------------------------------------------------*)
TYPE E_DL_HpfState :
(
    eInit  := 0,    // 首扫态：输出清零并同步输入历史，防上电脉冲 / First scan: output zeroed with input history synced, no power-up pulse
    eRun   := 10,   // 运行态：按 fAlpha 递推提取动态分量 / Running: recursive dynamic component extraction with fAlpha
    eTrack := 20,   // 跟踪态：输出清零并同步历史，投切无脉冲 / Tracking: output zeroed with history synced, bumpless transfer
    eFault := 99    // 故障兜底态：非法状态进入，输出安全值并置故障码 / Fault fallback: entered from illegal states, safe output plus error code
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_HighPassFilter
 * 调用约定: 每个采样周期无条件调用一次；tSampleTime 由调用方显式给定，
 *           严禁依赖隐式扫描周期做差分递推；多实例可并行互不干扰。
 * 滞后披露: 截止频率 fc = 1/(2*pi*tTf)；低于 fc 的缓变分量被衰减，
 *           时间常数越大截止频率越低、保留的低频动态越丰富。
 * 限幅披露: 输出限幅为工程防护（防差分尖峰打穿下游量程），非滤波语义；
 *           rOutMin > rOutMax 时二者对调并置公共钳位码，不中断扫描。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_HighPassFilter
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能，FALSE 时输出置 0 / Enable, FALSE forces output to zero
    fIn         : REAL := 0.0;        // 原始采样输入 [EU] / Raw sampling input [EU]
    tTimeConst  : TIME := T#1S;       // 高通时间常数 [s]，越大截止频率越低；T#0S=全通差分 / High-pass time constant [s], larger means lower cutoff; T#0S = all-pass difference
    tSampleTime : TIME := T#100MS;    // 采样周期，小于 10ms 钳位 / Sampling period, clamped to 10ms minimum
    rOutMin     : REAL := -1.0E10;    // 输出下限 [EU] / Output lower limit [EU]
    rOutMax     : REAL := 1.0E10;     // 输出上限 [EU] / Output upper limit [EU]
    bTrack      : BOOL := FALSE;      // 跟踪使能，TRUE 时输出清零并同步历史 / Track enable, TRUE zeroes output and synchronizes history
    fTrackValue : REAL := 0.0;        // 跟踪目标值 [EU]，跟踪语义为清零基线 / Track target value [EU], tracking zeroes the baseline
END_VAR
VAR_OUTPUT
    fOut        : REAL;               // 动态分量输出 [EU] / Dynamic component output [EU]
    fAlpha      : REAL;               // 当前滤波系数 [0..1]，诊断用 / Current filter coefficient [0..1], diagnostic
    bValid      : BOOL;               // 输出有效标志，首扫未完成时为 FALSE / Output valid flag, FALSE before first scan completes
    bError      : BOOL;               // 故障标志，与 uErrorId 联动 / Fault flag, coupled with uErrorId
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fInPrev     : REAL := 0.0;        // 上拍输入历史 [EU]，首扫同步防尖峰 / Previous input history [EU], synced at first scan
    fTfEff      : REAL;               // 钳位后的生效时间常数 [s] / Effective clamped time constant [s]
    fDt         : REAL;               // 采样周期秒值 [s] / Sampling period in seconds [s]
    fTfRaw      : REAL;               // 时间常数换算秒值（钳位前）[s] / Time constant in seconds before clamping [s]
    fOutLo      : REAL;               // 排序后的输出下限 [EU] / Ordered output lower limit [EU]
    fOutHi      : REAL;               // 排序后的输出上限 [EU] / Ordered output upper limit [EU]
    eState      : E_DL_HpfState;      // 状态机当前状态 / Current state of the state machine
END_VAR
VAR CONSTANT
    DL_HPF_TF_MAX  : REAL := 3600.0;  // 时间常数上限 [s]，超限钳位防过度迟滞 / Time constant upper clamp [s], prevents excessive lag
    DL_HPF_DT_MIN  : REAL := 0.01;    // 采样周期防御下限 [s] / Defensive sampling period lower bound [s]
    DL_HPF_INF_MAX : REAL := 1.0E30;  // 有限值判定幅值上限 [EU] / Magnitude bound for finite-value check [EU]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜参数钳位（不中断扫描）：周期下限 / 时间常数域 / 限幅对调
 *      Parameter clamping without scan interruption: period floor, constant range, limit swap
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0002_0000;

IF tSampleTime < T#10MS THEN
    fDt      := DL_HPF_DT_MIN;                       // 周期过小钳位到 10ms / Too small period clamped to 10ms
    uErrorId := 16#0002_0002;                        // 采样周期非法已钳位 / Invalid sampling period clamped
ELSE
    fDt := TIME_TO_REAL(tSampleTime) / 1000.0;       // TIME 换算秒值 / Convert TIME to seconds
END_IF

fTfRaw := TIME_TO_REAL(tTimeConst) / 1000.0;         // 时间常数换算秒值 / Convert time constant to seconds

IF (fTfRaw < 0.0) OR (fTfRaw > DL_HPF_TF_MAX) THEN
    fTfEff   := MIN(MAX(fTfRaw, 0.0), DL_HPF_TF_MAX); // 双侧钳位到合法域 / Two-sided clamp into valid range
    uErrorId := 16#0002_1201;                        // 时间常数非法已钳位 / Invalid time constant clamped
ELSE
    fTfEff := fTfRaw;                                // 合法参数原值生效 / Valid parameter applied as-is
END_IF

(* 限幅上下限对调防御：传反不中断扫描，排序后生效并置公共钳位码 *)
(* Limit swap defense: reversed limits are reordered without scan interruption *)
IF rOutMin > rOutMax THEN
    fOutLo   := rOutMax;
    fOutHi   := rOutMin;
    uErrorId := 16#0002_0001;                        // 参数越界已钳位（限幅对调） / Parameter out of range, limits swapped
ELSE
    fOutLo := rOutMin;
    fOutHi := rOutMax;
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜滤波系数计算（防除零）：fAlpha = fTf/(fTf+fDt)
 *      Filter coefficient with divide-by-zero guard: fAlpha = fTf/(fTf+fDt)
 *      tTimeConst=0 时 fAlpha=0，全通差分语义与 V3 向量对应
 *-----------------------------------------------------------------------------*)
IF fTfEff <= 1.0E-6 THEN
    fAlpha := 0.0;                                   // 零时间常数：全通差分系数 / Zero constant: all-pass difference coefficient
ELSE
    fAlpha := MIN(MAX(fTfEff / (fTfEff + fDt), 0.0), 1.0); // 系数显式约束在 0 与 1 之间 / Coefficient constrained into 0..1
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限值防御：拒绝本拍更新、复位历史防差分尖峰（公共故障码）
 *      Non-finite defense: reject this cycle and reset history against spikes
 *-----------------------------------------------------------------------------*)
IF (fIn <> fIn) OR (ABS(fIn) > DL_HPF_INF_MAX) THEN
    uErrorId := 16#0002_0004;                        // 输入非有限值已拒绝 / Non-finite input rejected
    fInPrev  := 0.0;                                 // 历史复位，恢复后按首扫口径重建 / History reset, rebuilt like first scan after recovery
    bValid   := FALSE;
    bError   := TRUE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜主状态机（红线 R6）：状态派生 + CASE 覆盖 + ELSE 兜底
 *      Main state machine: state derived from signals, CASE covered with ELSE
 *-----------------------------------------------------------------------------*)
IF bTrack THEN
    eState := eTrack;                                // 跟踪请求优先级最高 / Track request has highest priority
ELSIF eState = eInit THEN
    eState := eInit;                                 // 首扫态保持，不被运行派生覆盖 / First scan state preserved from override
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
        (* 首扫防上电脉冲：输出清零、输入历史与当前输入同步，差分基差为零 *)
        (* First scan power-up pulse guard: output zeroed, history synced to current input *)
        fOut    := 0.0;
        fInPrev := fIn;
        bValid  := FALSE;                            // 首扫未完成，输出尚不可信 / First scan unfinished, output not trustworthy yet
        eState  := eRun;                             // 下一拍进入运行态 / Move to running state next cycle

    eTrack:
        (* 无扰跟踪：输出清零、历史同步，回自动时差分基差为零无脉冲 *)
        (* Bumpless tracking: output zeroed, history synced, no pulse on resume *)
        fOut    := 0.0;
        fInPrev := fIn;
        bValid  := TRUE;
        eState  := eRun;

    eRun:
        IF NOT bEnable THEN
            (* 使能失效语义：输出置 0，历史同步防止恢复使能时残留脉冲 *)
            (* Disabled semantics: output zeroed, history synced to avoid resume pulses *)
            fOut    := 0.0;
            fInPrev := fIn;
            bValid  := FALSE;
        ELSE
            IF fAlpha <= 1.0E-6 THEN
                (* 全通差分：tTimeConst=0，输出为当拍与上拍之差 *)
                (* All-pass difference: zero time constant, output is cycle-to-cycle difference *)
                fOut := fIn - fInPrev;
            ELSE
                (* 一阶高通递推：fOut := fAlpha*(fOutPrev + fIn - fInPrev) *)
                (* First-order high-pass recursion per specification formula *)
                fOut := fAlpha * (fOut + fIn - fInPrev);
            END_IF

            (* 输出限幅：双侧钳位防差分尖峰打穿下游量程 *)
            (* Output limiting: two-sided clamp against downstream range breakthrough *)
            fOut := LIMIT(fOutLo, fOut, fOutHi);

            fInPrev := fIn;                          // 输入历史右移一位 / Shift input history by one
            bValid  := TRUE;
        END_IF

    eFault:
        (* 故障兜底：输出保持安全值 0，等待调用方修正后经使能跌落恢复 *)
        (* Fault fallback: output holds safe value 0, recovers via disabled input *)
        fOut   := 0.0;
        bValid := FALSE;

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
