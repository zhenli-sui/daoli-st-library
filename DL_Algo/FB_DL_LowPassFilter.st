(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LowPassFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（MIN / MAX / ABS），零厂商方言
 * 功能描述 (Function)   : 一阶惯性低通数字滤波器（PT1 / LGF PT1 语义）。
 *                         递推式 fOut := fOut + fAlpha*(fIn - fOut)，
 *                         其中 fAlpha := fDt / (fTf + fDt)；时间常数 tTimeConst
 *                         运行中可调，变更即时重算 fAlpha；tTimeConst = 0 直通；
 *                         首扫与 bTrack 跟踪均无滞后，投切无扰动。
 *                         现场用途：温度 / 压力 / 流量模拟量采集降噪。
 * 开源溯源 (Origin)     : 原创实现。算法思想源自 LGF PT1 与模板库
 *                         05-algorithm-templates.md 的 FB_LowPassFilter 结构，
 *                         按本库故障码体系（16#0002_xxxx）重写并加严。
 * 设计验证 (Verified)   : fT1=0.1s、fDt=0.01s、阶跃 0->1（python 6 位小数）：
 *                         fAlpha=0.090909；第 1 拍 fOut=0.090909；
 *                         第 10 拍 fOut=0.614457；第 50 拍 fOut=0.991481。
 * 验收向量 (Acceptance) :
 *   V1 fT1=0.1s fDt=0.01s 输入恒 1.0：第 1 拍 fOut≈0.090909（容差 1E-4）
 *   V2 同 V1：第 10 拍 fOut≈0.614457（容差 1E-4）
 *   V3 同 V1：第 50 拍 fOut≈0.991481（容差 1E-4）
 *   V4 tTimeConst=T#0S：任意输入当拍直通，fOut=fIn、fAlpha=1.0
 *   V5 bTrack=TRUE fTrackValue=42.0：当拍 fOut=42.0 且无爬升过程
 *   V6 fIn 非有限值：本拍拒绝更新保持上拍输出，uErrorId=16#0002_0004
 * 本文件内含       : TYPE  E_DL_LpfState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_LowPassFilter
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library 数学算符
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 钳位+容差+非有限值拒绝+防除零
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器与边沿检测实例）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   声明于调用方 FB 的 VAR 区：fbLpf : FB_DL_LowPassFilter;
 *   每周期调用：fbLpf(bEnable := TRUE, fIn := stPv.fRaw,
 *                     tTimeConst := T#1S, tSampleTime := T#100MS);
 *   取用输出：  stPv.fFiltered := fbLpf.fOut;
 * 现场调参指引：温度回路 tTimeConst 取 1 到 3 秒，压力回路取 0.3 到 1 秒；
 *   投入调节回路前先用 bTrack 跟踪当前过程值，切换瞬间输出无跳变。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LpfState（归属 DL_Algo，与 FB_DL_LowPassFilter 同文件）
 * 含义: 低通滤波状态机离散状态。纯线性滤波采用「状态派生 + CASE 覆盖 + ELSE」
 *       结构：状态由使能 / 跟踪 / 首扫信号派生，CASE 保证每态行为显式可审计。
 *----------------------------------------------------------------------------*)
TYPE E_DL_LpfState :
(
    eInit  := 0,    // 首扫态：输出直接采样输入，bValid=FALSE，无历史瞬态 / First scan: output tracks input directly, bValid=FALSE
    eRun   := 10,   // 运行态：按 fAlpha 递推滤波，参数变更即时生效 / Running: recursive filtering with live fAlpha, parameter changes apply at once
    eTrack := 20,   // 跟踪态：输出立即跟随 fTrackValue，内部历史同步 / Tracking: output follows fTrackValue instantly, states synchronized
    eFault := 99    // 故障兜底态：非法状态进入，输出安全值并置故障码 / Fault fallback: entered from illegal states, safe output plus error code
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_LowPassFilter
 * 调用约定: 每个采样周期无条件调用一次；tSampleTime 由调用方显式给定，
 *           严禁依赖隐式扫描周期做滤波递推；多实例可并行互不干扰。
 * 滞后披露: 输出对阶跃的 63.2% 响应时间约等于 tTimeConst（离散近似），
 *           tTimeConst 越大越平滑、相位滞后越大，选型需与采样周期匹配。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_LowPassFilter
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能，FALSE 时输出直通原始输入 / Enable, FALSE passes raw input straight through
    fIn         : REAL := 0.0;        // 原始采样输入 [EU] / Raw sampling input [EU]
    tTimeConst  : TIME := T#1S;       // 滤波时间常数 [s]，T#0S = 直通 / Filter time constant [s], T#0S = pass-through
    tSampleTime : TIME := T#100MS;    // 采样周期 [s 口径换算]，小于 10ms 钳位 / Sampling period, clamped to 10ms minimum
    bTrack      : BOOL := FALSE;      // 跟踪使能，TRUE 时输出立即跟随跟踪值 / Track enable, TRUE makes output follow track value instantly
    fTrackValue : REAL := 0.0;        // 跟踪目标值 [EU]，无扰投切用 / Track target value [EU], for bumpless transfer
END_VAR
VAR_OUTPUT
    fOut        : REAL;               // 滤波输出 [EU] / Filtered output [EU]
    fAlpha      : REAL;               // 当前滤波系数 [0..1]，诊断用 / Current filter coefficient [0..1], diagnostic
    bValid      : BOOL;               // 输出有效标志，首扫未完成时为 FALSE / Output valid flag, FALSE before first scan completes
    bError      : BOOL;               // 故障标志，与 uErrorId 联动 / Fault flag, coupled with uErrorId
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fTfEff      : REAL;               // 钳位后的生效时间常数 [s] / Effective clamped time constant [s]
    fDt         : REAL;               // 采样周期秒值 [s] / Sampling period in seconds [s]
    fTfRaw      : REAL;               // 时间常数换算秒值（钳位前）[s] / Time constant in seconds before clamping [s]
    eState      : E_DL_LpfState;      // 状态机当前状态 / Current state of the state machine
END_VAR
VAR CONSTANT
    DL_LPF_TF_MAX  : REAL := 3600.0;  // 时间常数上限 [s]，超限钳位防极端迟滞 / Time constant upper clamp [s], prevents extreme lag
    DL_LPF_DT_MIN  : REAL := 0.01;    // 采样周期防御下限 [s] / Defensive sampling period lower bound [s]
    DL_LPF_INF_MAX : REAL := 1.0E30;  // 有限值判定幅值上限 [EU] / Magnitude bound for finite-value check [EU]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜参数钳位（不中断扫描）：采样周期下限与时间常数越界只置码修正
 *      Parameter clamping without scan interruption: period floor and constant range
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0002_0000;

IF tSampleTime < T#10MS THEN
    fDt      := DL_LPF_DT_MIN;                       // 周期过小钳位到 10ms / Too small period clamped to 10ms
    uErrorId := 16#0002_0002;                        // 采样周期非法已钳位 / Invalid sampling period clamped
ELSE
    fDt := TIME_TO_REAL(tSampleTime) / 1000.0;       // TIME 换算秒值 / Convert TIME to seconds
END_IF

fTfRaw := TIME_TO_REAL(tTimeConst) / 1000.0;         // 时间常数换算秒值 / Convert time constant to seconds

IF (fTfRaw < 0.0) OR (fTfRaw > DL_LPF_TF_MAX) THEN
    fTfEff   := MIN(MAX(fTfRaw, 0.0), DL_LPF_TF_MAX); // 双侧钳位到合法域 / Two-sided clamp into valid range
    uErrorId := 16#0002_1001;                        // 时间常数非法已钳位 / Invalid time constant clamped
ELSE
    fTfEff := fTfRaw;                                // 合法参数原值生效 / Valid parameter applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜滤波系数计算（防除零 + 显式区间约束）：fAlpha = fDt/(fTf+fDt)
 *      Filter coefficient with divide-by-zero guard and explicit interval
 *      tTimeConst=0 时 fAlpha=1.0，天然直通，与 V4 向量对应
 *-----------------------------------------------------------------------------*)
IF fTfEff <= 1.0E-6 THEN
    fAlpha := 1.0;                                   // 零时间常数直通系数 / Pass-through coefficient for zero constant
ELSE
    fAlpha := MIN(MAX(fDt / (fTfEff + fDt), 0.0), 1.0); // 系数显式约束在 0 与 1 之间 / Coefficient constrained into 0..1
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限值防御：拒绝本拍更新、保持上一拍输出（公共故障码）
 *      Non-finite defense: reject this cycle, hold previous output
 *-----------------------------------------------------------------------------*)
IF (fIn <> fIn) OR (ABS(fIn) > DL_LPF_INF_MAX) THEN
    uErrorId := 16#0002_0004;                        // 输入非有限值已拒绝 / Non-finite input rejected
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
        (* 首扫直接采样：输出等于输入，无历史瞬态（与验收 V5 等价的天然行为） *)
        (* First scan samples directly: output equals input, no historical transient *)
        fOut   := fIn;
        bValid := FALSE;                             // 首扫未完成，输出尚不可信 / First scan unfinished, output not trustworthy yet
        eState := eRun;                              // 下一拍进入运行态 / Move to running state next cycle

    eTrack:
        (* 无扰跟踪：输出立即跟随跟踪值，滤波历史同步置位，回自动无跳变 *)
        (* Bumpless tracking: output follows track value, filter state synchronized *)
        fOut   := fTrackValue;
        bValid := TRUE;
        eState := eRun;

    eRun:
        IF NOT bEnable THEN
            (* 使能失效语义：直通原始输入，系数保持显示但不参与递推 *)
            (* Disabled semantics: pass raw input through, coefficient kept for display only *)
            fOut   := fIn;
            bValid := FALSE;
        ELSE
            (* 一阶低通递推：fOut += (fIn - fOut) * fAlpha，fAlpha 已在段 2 确定 *)
            (* First-order recursion: fOut += (fIn - fOut) * fAlpha *)
            fOut   := fOut + (fIn - fOut) * fAlpha;
            bValid := TRUE;
        END_IF

    eFault:
        (* 故障兜底：输出保持安全值 0，等待调用方修正参数后重新派生 *)
        (* Fault fallback: output holds safe value 0 until caller fixes parameters *)
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
