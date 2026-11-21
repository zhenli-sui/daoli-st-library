(*==============================================================================
 * 组件名称 (Component)  : FB_DL_Differentiator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LIMIT / MIN / MAX / ABS），零厂商方言
 * 功能描述 (Function)   : 带一阶低通滤波的实用微分器：差分商 (fIn - fInPrev)/fDt
 *                         计算变化率，后接一阶低通抑制高频噪声放大（纯差分对
 *                         采样噪声增益 1/fDt，会放大毛刺）。输出变化率限幅
 *                         （rRateMin/rRateMax）防异常尖峰误触发趋势报警。
 *                         现场用途：温度变化速率监控（趋势报警前级）、压装
 *                         速度计算、液位升降速率。
 * 开源溯源 (Origin)     : 原创实现。组合语义对应西门子 LGF 的差分商块与
 *                         PT1 滤波器串联的公开行为定义，clean-room 编写，
 *                         未复制任何厂商私有库源码。
 * 本文件内含       : TYPE  E_DL_DiffState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_Differentiator
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LIMIT / MIN / MAX / ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+非有限值拒绝
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器/边沿实例）
 * 【边界披露 / Boundary disclosure】
 *   B1 除零防御：fDt 走公共钳位（<10ms 钳位 10ms 置 16#0002_0002），恒大于零。
 *   B2 tFiltTime 超上限 60s：钳位并置 16#0002_1401；tFiltTime=0 为合法直通
 *      （输出原始差分商，不置故障）。
 *   B3 rRateMin > rRateMax：自动对调并置 16#0002_0001。
 *   B4 输入非有限值：本拍拒绝、清历史（bHistValid=FALSE）、输出归零，置
 *      16#0002_0004；下一有效拍重新同步端点，绝不输出伪造速率。
 *   B5 首扫同步 fInPrev := fIn、输出 0，防上电尖峰。
 *   B6 低通系数 fAlpha 显式钳位 0..1；fTfEff + fDt 恒 > 0（分母安全）。
 * 【验收向量 / Acceptance vectors】
 *   V1  fIn 每拍 +1.0（tSampleTime=100MS，即 10 EU/s 恒速）→ fRawRate=10 EU/s，
 *       fRateOut 数拍内收敛到 10 EU/s、bValid=TRUE
 *   V2  fIn 阶跃 +50 一拍 → fRawRate=500 EU/s 单拍尖峰，fRateOut 按
 *       tFiltTime=500MS 平滑，峰值明显低于 500（噪声抑制效果）
 *   V3  fIn 恒定 → fRateOut 收敛到 0
 *   V4  rRateMax=20，V1 → fRateOut 钳位 20 EU/s
 *   V5  tFiltTime=0 → fRateOut=fRawRate（直通，无故障码）
 *   V6  tFiltTime=65S → 钳位 60S、16#0002_1401
 *   V7  fIn=NaN → 16#0002_0004，fRateOut=0、bValid=FALSE
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *   2026-11-15  v1.0.1  阶段五终审精修：首扫初始化标志判据修复（原判据恒假
 *                       为死代码），首扫同步端点改为显式可审计路径
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DiffState（归属 DL_Algo，与 FB_DL_Differentiator 同文件）
 * 含义: 微分器状态机离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_DiffState :
(
    eInit  := 0,   // 初始化态：首扫或失历史，同步端点、输出清零 / Init state, sync endpoint, output zero
    eRun   := 10,  // 运行态：差分商 + 低通滤波逐拍计算 / Run state, difference quotient with low-pass per scan
    eTrack := 20,  // 跟踪态：输出立即跟随 fTrackValue / Track state, output follows track value instantly
    eFault := 99   // 故障兜底态：非法状态拦截，自动回初始化 / Fault fallback, auto recover to init
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_Differentiator
 * 调用约定: 每个扫描周期无条件调用一次；bTrack 使能时输出立即跟随 fTrackValue。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，可多实例并行互不影响。
 * 噪声披露: 输出滞后 ≈ tFiltTime；tFiltTime 越小噪声抑制越弱，建议
 *           tFiltTime >= 5 × 采样周期（本块默认 500ms @ 100ms 采样）。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_Differentiator
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能标志，FALSE 时输出 0 / Enable flag, FALSE forces output to zero
    fIn         : REAL := 0.0;        // 被微分量 [EU]，如温度/位置/液位 / Differentiated input [EU]
    tFiltTime   : TIME := T#500MS;    // 速率低通时间常数 [s]，0 = 原始差分直通 / Rate low-pass time constant [s], 0 = raw pass
    rRateMin    : REAL := -1.0E10;    // 速率下限 [EU/s]，大于上限时自动对调 / Rate lower limit [EU/s], swapped if greater
    rRateMax    : REAL := 1.0E10;     // 速率上限 [EU/s]，小于下限时自动对调 / Rate upper limit [EU/s], swapped if smaller
    bTrack      : BOOL := FALSE;      // 跟踪使能，TRUE 时输出立即跟随 fTrackValue / Track enable, output follows track value
    fTrackValue : REAL := 0.0;        // 跟踪值 [EU/s]，投切无扰动基准 / Track value [EU/s], bumpless transfer reference
    tSampleTime : TIME := T#100MS;    // 采样周期 [s]，小于 10ms 钳位为 10ms / Sample time [s], clamped to 10ms
END_VAR
VAR_OUTPUT
    fRateOut    : REAL;               // 变化率输出 [EU/s]，滤波并限幅 / Rate output [EU/s], filtered and limited
    fRawRate    : REAL;               // 未滤波原始速率 [EU/s]，诊断 / Raw unfiltered rate [EU/s] for diagnostics
    bValid      : BOOL;               // 输出有效标志（端点已同步且有真实差分）/ Output valid flag
    bError      : BOOL;               // 故障标志（瞬时，逐拍重算） / Fault flag, transient, recomputed every scan
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fInPrev     : REAL;               // 上一拍被微分量 [EU]，差分端点 / Previous input [EU], difference endpoint
    fTfEff      : REAL;               // 钳位后滤波时间常数 [s] / Clamped filter time constant [s]
    fAlpha      : REAL;               // 低通滤波系数 [0..1] / Low-pass filter coefficient [0..1]
    fDt         : REAL;               // 折算后的采样周期 [s] / Converted sample period [s]
    bInFinite   : BOOL;               // 本拍输入有限值标志 / Input finite validity flag this scan
    bHistValid  : BOOL;               // 端点历史有效标志 / Endpoint history valid flag
    bInit       : BOOL;               // 首扫标志 / First scan flag
    eState      : E_DL_DiffState;     // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR CONSTANT
    DL_DIFF_TF_MAX : REAL := 60.0;    // 滤波时间常数上限 [s] / Filter time constant upper limit [s]
    DL_DIFF_EPS    : REAL := 1.0E-6;  // 分母安全容差 / Denominator safety tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜公共参数处理（通用约定 0-1/0-2/0-3）：周期钳位、滤波常数钳位、量程对调
 *      Common handling: sample time clamp, filter constant clamp, limit swap
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;               // 故障码逐拍重算 / Error code recomputed every scan
bError   := FALSE;                      // 故障标志逐拍重算 / Fault flag recomputed every scan

IF tSampleTime < T#10MS THEN
    fDt      := TIME_TO_REAL(T#10MS) / 1000.0; // 非法周期钳位为 10ms（边界 B1 防除零）/ Illegal period clamped to 10ms
    uErrorId := 16#0002_0002;           // 采样周期非法已钳位 / Sample time illegal, clamped
ELSE
    fDt      := TIME_TO_REAL(tSampleTime) / 1000.0; // 周期换算为秒 [s] / Period converted to seconds [s]
END_IF

fTfEff := TIME_TO_REAL(tFiltTime) / 1000.0; // 滤波常数换算为秒 [s] / Filter constant converted to seconds [s]
IF fTfEff < 0.0 THEN
    fTfEff   := 0.0;                    // 负值钳位为直通 / Negative clamped to pass-through
    uErrorId := 16#0002_1401;           // 滤波时间常数非法已钳位 / Filter time constant illegal, clamped
END_IF
IF fTfEff > DL_DIFF_TF_MAX THEN
    fTfEff   := DL_DIFF_TF_MAX;         // 超上限钳位（边界 B2）/ Over-limit clamped
    uErrorId := 16#0002_1401;           // 滤波时间常数非法已钳位 / Filter time constant illegal, clamped
END_IF

IF rRateMin > rRateMax THEN
    rRateMin := rRateMin + rRateMax;    // 三步对调第一步：求和 / Swap step one: sum
    rRateMax := rRateMin - rRateMax;    // 三步对调第二步：得旧下限 / Swap step two: old lower limit
    rRateMin := rRateMin - rRateMax;    // 三步对调第三步：得旧上限 / Swap step three: old upper limit
    uErrorId := 16#0002_0001;           // 参数越界已对调 / Limits out of order, swapped
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜输入合法性（边界 B4）：非有限值拒绝并清历史，输出归零防伪造速率
 *      Input validity: non-finite rejected, history cleared, output zeroed
 *-----------------------------------------------------------------------------*)
bInFinite := NOT (fIn <> fIn) AND (ABS(fIn) <= 1.0E30); // NaN 判别 + 幅值防御 / NaN check plus magnitude guard

IF NOT bInFinite THEN
    uErrorId   := 16#0002_0004;         // 输入非有限值已拒绝 / Non-finite input rejected
    bHistValid := FALSE;                // 清历史端点 / Clear endpoint history
    fRateOut   := 0.0;                  // 输出归零 / Output zeroed
    fRawRate   := 0.0;                  // 原始速率归零 / Raw rate zeroed
    bValid     := FALSE;                // 有效标志清零 / Valid flag cleared
    eState     := eInit;                // 回初始化态重新同步 / Back to init for re-sync
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜跟踪与首扫（约定 0-6）：端点同步、输出归零，防上电尖峰（边界 B5）
 *      Tracking and first scan: endpoint synced, output zeroed against power-up spike
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    IF bInFinite THEN
        fInPrev := fIn;                 // 端点同步当前输入 / Endpoint synced to current input
        bHistValid := TRUE;             // 历史有效 / History valid
    END_IF
    fRateOut := 0.0;                    // 输出清零 / Output zeroed
    fRawRate := 0.0;                    // 原始速率清零 / Raw rate zeroed
    bValid   := FALSE;                  // 首扫无真实差分 / No real difference on first scan
    eState   := eInit;                  // 回初始化态 / Back to init state
    bInit    := TRUE;                   // 首扫标志置位 / First scan flag set
END_IF

IF bTrack THEN
    fRateOut := LIMIT(rRateMin, fTrackValue, rRateMax); // 输出立即跟随跟踪值并限幅 / Output follows track value with limits
    IF bInFinite THEN
        fInPrev := fIn;                 // 端点同步当前输入 / Endpoint synced to current input
    END_IF
    bHistValid := TRUE;                 // 历史有效 / History valid
    bValid     := TRUE;                 // 跟踪输出视为有效 / Tracked output considered valid
    eState     := eTrack;               // 跟踪态 / Track state
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜使能失效语义：输出归零、清历史，恢复后从初始化态重新同步
 *      Disabled semantics: output zeroed, history cleared, re-sync after enable
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    fRateOut   := 0.0;                  // 输出归零 / Output zeroed
    fRawRate   := 0.0;                  // 原始速率归零 / Raw rate zeroed
    bValid     := FALSE;                // 有效标志清零 / Valid flag cleared
    bHistValid := FALSE;                // 清历史端点 / Clear endpoint history
    eState     := eInit;                // 回初始化态 / Back to init state
ELSE
    (*--------------------------------------------------------------------------
     * 段 5｜主状态机（红线 R6）：四态 ENUM + CASE + ELSE 兜底
     *     Main state machine: four-state ENUM + CASE with mandatory ELSE fallback
     *-------------------------------------------------------------------------*)
    CASE eState OF

        eInit:  // 初始化态：端点同步、输出 0，下拍进入运行态（边界 B5）/ Init: sync endpoint, output zero
            IF bInFinite THEN
                fInPrev := fIn;             // 端点同步当前输入 / Endpoint synced to current input
                bHistValid := TRUE;         // 历史有效 / History valid
            END_IF
            fRateOut := 0.0;                // 输出清零 / Output zeroed
            fRawRate := 0.0;                // 原始速率清零 / Raw rate zeroed
            bValid   := FALSE;              // 本拍无真实差分 / No real difference this scan
            eState   := eRun;               // 进入运行态 / Enter run state

        eRun:  // 运行态：差分商 + 低通滤波（边界 B1 分母安全）/ Run: difference quotient with low-pass
            IF NOT bHistValid THEN
                fInPrev := fIn;             // 历史失效先重建端点 / Rebuild endpoint when history invalid
                bHistValid := TRUE;         // 历史恢复有效 / History restored
                fRateOut := 0.0;            // 输出先归零防尖峰 / Output zeroed against spike
                fRawRate := 0.0;            // 原始速率归零 / Raw rate zeroed
            ELSE
                fRawRate := (fIn - fInPrev) / fDt; // 原始差分商 [EU/s] / Raw difference quotient [EU/s]
                IF fTfEff <= DL_DIFF_EPS THEN
                    fAlpha := 1.0;          // 零滤波常数直通（边界 B2 合法）/ Zero constant pass-through
                ELSE
                    fAlpha := fDt / (fTfEff + fDt); // 一阶低通系数 [0..1] / First-order low-pass coefficient
                    fAlpha := MIN(MAX(fAlpha, 0.0), 1.0); // 系数显式钳位（边界 B6）/ Coefficient explicitly clamped
                END_IF
                fRateOut := fRateOut + fAlpha * (fRawRate - fRateOut); // 低通递推 [EU/s] / Low-pass recursion [EU/s]
                fRateOut := LIMIT(rRateMin, fRateOut, rRateMax); // 速率限幅 / Rate limited
                fInPrev  := fIn;            // 端点更新 / Endpoint updated
                bValid   := TRUE;           // 输出有效 / Output valid
            END_IF

        eTrack:  // 跟踪态：输出已由段 3 跟随，释放后回运行态 / Track: output follows, resume run after release
            IF NOT bTrack THEN
                eState := eRun;             // 释放跟踪，恢复计算 / Tracking released, resume computing
            END_IF

        eFault:  // 故障兜底态：输出归零并回初始化态（无锁死）/ Fault fallback: output zeroed, recover to init
            fRateOut := 0.0;                // 输出归零 / Output zeroed
            eState   := eInit;              // 自动恢复初始化 / Auto recover to init

        ELSE  // 非法状态拦截：任何未定义状态一律进故障态并置码 / Illegal state interception
            eState   := eFault;             // 强制故障态 / Force fault state
            uErrorId := 16#0002_0005;       // 非法状态兜底 / Illegal state fallback
            bError   := TRUE;               // 故障标志置位 / Fault flag set

    END_CASE;
END_IF
END_FUNCTION_BLOCK
