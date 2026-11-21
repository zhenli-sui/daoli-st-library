(*==============================================================================
 * 组件名称 (Component)  : FB_DL_Integrator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（MIN / MAX / ABS / LREAL_TO_REAL），零厂商方言
 * 功能描述 (Function)   : 梯形法离散积分器：fSum += (fIn + fInPrev)/2 · fDt，
 *                         精度高于矩形法，对缓变信号无系统偏差。内部以 LREAL
 *                         双精度累加、输出转 REAL，防长时累计的舍入漂移。
 *                         带上下限限幅（触限保持）、保持（bHold）、电平复位
 *                         （bReset）、跟踪回投（bTrack）。现场用途：流量累计
 *                         （总量表）、速度→位移、电量/电能累计。
 * 开源溯源 (Origin)     : 原创实现。双精度累加思想源自 OSCAT Basic 的
 *                         FT_INT2 误差抑制行为定义（EPL-2.0），clean-room
 *                         编写，未复制任何源码。
 * 本文件内含       : TYPE  E_DL_IntState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_Integrator
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LREAL_TO_REAL
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 量程对调+溢出钳位+非有限值拒绝
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器/边沿实例）
 * 【边界披露 / Boundary disclosure】
 *   B1 rOutMin > rOutMax：自动对调并置 16#0002_0001，不中断扫描。
 *   B2 复位优先于积分：bReset 电平触发，复位拍不积分（先判 bReset）。
 *   B3 输入非有限值（NaN 或幅值超 1.0E30）：本拍拒绝积分、保持累加器、
 *      fInPrev 不同步，置 16#0002_0004。
 *   B4 累加器幅值超 1.0E30：强制钳位防 LREAL 溢出，置 16#0002_0001。
 *   B5 保持期（bHold 或未使能）不积分，fInPrev 亦不更新，恢复时无历史跳变。
 *   B6 触限后每拍仍尝试积分：输入反向或限幅放宽时自动恢复，无需复位。
 * 【验收向量 / Acceptance vectors】
 *   V1  fIn=10 EU 恒定，tSampleTime=100MS，1s 后 fOut≈10 EU·s（梯形法与
 *       解析值一致，矩形法会偏 0.5 EU·s，对比可见梯形优势）
 *   V2  fIn 由 0 线性升至 10（每拍 +1），1s 后 fOut≈5.05 EU·s（与解析积分一致）
 *   V3  rOutMax=3，V1 持续 → fOut 钳位 3、bLimitHigh=TRUE、状态 eLimited
 *   V4  bHold=TRUE → fOut 冻结；释放后从冻结值继续
 *   V5  bReset 一拍 → fOut=0、fInPrev 同步当前输入（防复位后首拍尖峰）
 *   V6  bTrack 一拍（fTrackValue=100）→ fOut=100，无扰动回投
 *   V7  fIn=NaN → 16#0002_0004，fOut 保持，累加器不动
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *   2026-11-15  v1.0.1  阶段五终审精修：首扫自动跟踪判据修复（原 bInit 判据
 *                       反向，bTrack 一次后累加器被永久锁死为跟踪值）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_IntState（归属 DL_Algo，与 FB_DL_Integrator 同文件）
 * 含义: 积分器状态机离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_IntState :
(
    eIdle        := 0,   // 空闲态：未使能，累加器保持 / Idle state, accumulator held
    eHold        := 10,  // 保持态：操作员请求冻结累加 / Hold state, accumulation frozen on request
    eIntegrating := 20,  // 积分态：梯形法逐拍累加 / Integrating, trapezoidal accumulation
    eLimited     := 30,  // 触限态：累加器停在限幅值，反向输入自动恢复 / Limited, auto recovers on reverse input
    eFault       := 99   // 故障兜底态：非法状态拦截，自动回空闲 / Fault fallback, auto recover to idle
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_Integrator
 * 调用约定: 每个扫描周期无条件调用一次；bReset 电平触发（保持 TRUE 即持续清零）。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，可多实例并行互不影响。
 * 精度披露: 内部 LREAL 双精度累加、每拍输出转 REAL；单位为 [EU·s]
 *           （被积量 [EU] × 时间 [s]），总表类应用注意换算口径。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_Integrator
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能标志，FALSE 保持累加器 / Enable flag, FALSE holds accumulator
    fIn         : REAL := 0.0;        // 被积量 [EU]，如流量/速度/电流 / Integrated input [EU]
    rOutMin     : REAL := 0.0;        // 积分下限 [EU·s]，大于上限时自动对调 / Integral lower limit [EU·s], swapped if greater
    rOutMax     : REAL := 1.0E12;     // 积分上限 [EU·s]，长时累计防溢出 / Integral upper limit [EU·s]
    bHold       : BOOL := FALSE;      // 保持请求，TRUE 冻结累加 / Hold request, TRUE freezes accumulation
    bReset      : BOOL := FALSE;      // 复位信号，电平触发清零 / Reset signal, level triggered clear
    bTrack      : BOOL := FALSE;      // 跟踪使能，TRUE 时累加器立即跟随 fTrackValue / Track enable, accumulator follows track value
    fTrackValue : REAL := 0.0;        // 跟踪值 [EU·s]，投切无扰动基准 / Track value [EU·s], bumpless transfer reference
    tSampleTime : TIME := T#100MS;    // 采样周期 [s]，小于 10ms 钳位为 10ms / Sample time [s], clamped to 10ms
END_VAR
VAR_OUTPUT
    fOut        : REAL;               // 积分结果 [EU·s] / Integration result [EU·s]
    bLimitHigh  : BOOL;               // 触上限标志 / Upper limit reached flag
    bLimitLow   : BOOL;               // 触下限标志 / Lower limit reached flag
    bError      : BOOL;               // 故障标志（瞬时，逐拍重算） / Fault flag, transient, recomputed every scan
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fSumLReal   : LREAL;              // 双精度累加器 [EU·s] / Double precision accumulator [EU·s]
    fInPrev     : REAL;               // 上一拍被积量 [EU]，梯形法端点 / Previous input [EU], trapezoid endpoint
    fDt         : REAL;               // 折算后的采样周期 [s] / Converted sample period [s]
    bInFinite   : BOOL;               // 本拍输入有限值标志 / Input finite validity flag this scan
    bInit       : BOOL;               // 首扫标志：首扫自动跟踪 / First scan flag, auto track on first scan
    eState      : E_DL_IntState;      // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR CONSTANT
    DL_INT_ABS_MAX : LREAL := 1.0E30; // 累加器幅值上限 [EU·s]，防溢出 / Accumulator magnitude limit [EU·s]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜公共参数处理（通用约定 0-1/0-2）：周期钳位、量程对调、故障码瞬时清零
 *      Common handling: sample time clamp, limit swap, transient code reset
 *-----------------------------------------------------------------------------*)
uErrorId   := 16#0000_0000;         // 故障码逐拍重算 / Error code recomputed every scan
bError     := FALSE;                // 故障标志逐拍重算 / Fault flag recomputed every scan
bLimitHigh := FALSE;                // 触限标志逐拍重算 / Limit flags recomputed every scan
bLimitLow  := FALSE;                // 触限标志逐拍重算 / Limit flags recomputed every scan

IF tSampleTime < T#10MS THEN
    fDt      := TIME_TO_REAL(T#10MS) / 1000.0; // 非法周期钳位为 10ms / Illegal period clamped to 10ms
    uErrorId := 16#0002_0002;           // 采样周期非法已钳位 / Sample time illegal, clamped
ELSE
    fDt      := TIME_TO_REAL(tSampleTime) / 1000.0; // 周期换算为秒 [s] / Period converted to seconds [s]
END_IF

IF rOutMin > rOutMax THEN
    rOutMin   := rOutMin + rOutMax;     // 三步对调第一步：求和 / Swap step one: sum
    rOutMax   := rOutMin - rOutMax;     // 三步对调第二步：得旧下限 / Swap step two: old lower limit
    rOutMin   := rOutMin - rOutMax;     // 三步对调第三步：得旧上限 / Swap step three: old upper limit
    uErrorId  := 16#0002_0001;          // 参数越界已对调 / Limits out of order, swapped
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜输入合法性与复位/跟踪（边界 B2/B3、约定 0-6）
 *      Input validity and reset/track handling
 *-----------------------------------------------------------------------------*)
bInFinite := NOT (fIn <> fIn) AND (ABS(fIn) <= 1.0E30); // NaN 判别 + 幅值防御 / NaN check plus magnitude guard

IF NOT bInFinite THEN
    uErrorId := 16#0002_0004;           // 输入非有限值已拒绝 / Non-finite input rejected
END_IF

IF bTrack OR (NOT bInit) THEN
    fSumLReal := MIN(MAX(fTrackValue, rOutMin), rOutMax); // 累加器立即跟随跟踪值并限幅 / Accumulator follows track value with limits
    IF bInFinite THEN
        fInPrev := fIn;                 // 端点同步当前输入 / Endpoint synced to current input
    END_IF
    eState := eIdle;                    // 回空闲重新评估 / Back to idle for re-evaluation
    bInit  := TRUE;                     // 首扫标志置位 / First scan flag set
END_IF

IF bReset THEN
    fSumLReal := 0.0;                   // 复位优先：累加器清零 / Reset priority: accumulator cleared
    IF bInFinite THEN
        fInPrev := fIn;                 // 端点同步当前输入，防复位后尖峰 / Endpoint synced, prevents post-reset spike
    END_IF
    eState := eIdle;                    // 复位后回空闲 / Back to idle after reset
END_IF

IF NOT bEnable THEN
    eState := eIdle;                    // 未使能：强制空闲、累加器保持 / Disabled: force idle, accumulator held
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜主状态机（红线 R6）：五态 ENUM + CASE + ELSE 兜底
 *      Main state machine: five-state ENUM + CASE with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eState OF

    eIdle:  // 空闲态：使能且输入有效且未复位未保持 → 进入积分态 / Idle: enter integrating when conditions met
        IF bEnable AND bInFinite AND (NOT bReset) AND (NOT bHold) THEN
            eState := eIntegrating;     // 进入积分态（本拍先迁移，下拍起积分）/ Enter integrating, integrate from next scan
        END_IF

    eHold:  // 保持态：释放后回积分态 / Hold: resume integrating after release
        IF bEnable AND bInFinite AND (NOT bReset) AND (NOT bHold) THEN
            eState := eIntegrating;     // 恢复积分 / Resume integration
        ELSIF NOT bEnable THEN
            eState := eIdle;            // 使能跌落回空闲 / Back to idle when disabled
        END_IF

    eIntegrating:  // 积分态：梯形法逐拍累加（边界 B3 拒绝非有限值）/ Integrating: trapezoidal accumulation
        IF NOT bEnable THEN
            eState := eIdle;            // 使能跌落回空闲 / Back to idle when disabled
        ELSIF bHold THEN
            eState := eHold;            // 保持请求 / Hold request
        ELSIF bInFinite THEN
            fSumLReal := fSumLReal + (fIn + fInPrev) / 2.0 * fDt; // 梯形法累加 [EU·s] / Trapezoidal accumulation [EU·s]
            fInPrev    := fIn;          // 端点更新 / Endpoint updated
        END_IF

    eLimited:  // 触限态：每拍仍尝试积分，反向输入或限幅放宽时自动恢复（边界 B6）/ Limited: retry every scan, auto recover
        IF NOT bEnable THEN
            eState := eIdle;            // 使能跌落回空闲 / Back to idle when disabled
        ELSIF bHold THEN
            eState := eHold;            // 保持请求 / Hold request
        ELSIF bInFinite THEN
            fSumLReal := fSumLReal + (fIn + fInPrev) / 2.0 * fDt; // 继续累加（限幅兜底）/ Keep accumulating, clamp guards
            fInPrev    := fIn;          // 端点更新 / Endpoint updated
        END_IF

    eFault:  // 故障兜底态：累加器保持，自动回空闲（无锁死）/ Fault fallback: accumulator held, recover to idle
        eState := eIdle;                // 自动恢复空闲 / Auto recover to idle

    ELSE  // 非法状态拦截：任何未定义状态一律进故障态并置码 / Illegal state interception
        eState   := eFault;             // 强制故障态 / Force fault state
        uErrorId := 16#0002_0005;       // 非法状态兜底 / Illegal state fallback
        bError   := TRUE;               // 故障标志置位 / Fault flag set

END_CASE;

(*------------------------------------------------------------------------------
 * 段 4｜溢出钳位与量程限幅、输出整形（边界 B4/B1）
 *      Overflow clamp, range limiting and output shaping
 *-----------------------------------------------------------------------------*)
IF fSumLReal > DL_INT_ABS_MAX THEN
    fSumLReal := DL_INT_ABS_MAX;        // 幅值超限钳位防溢出 / Magnitude clamped against overflow
    uErrorId  := 16#0002_0001;          // 参数越界已钳位 / Value out of range, clamped
END_IF
IF fSumLReal < -DL_INT_ABS_MAX THEN
    fSumLReal := -DL_INT_ABS_MAX;       // 负向幅值钳位 / Negative magnitude clamped
    uErrorId  := 16#0002_0001;          // 参数越界已钳位 / Value out of range, clamped
END_IF

IF fSumLReal >= rOutMax THEN
    fSumLReal   := rOutMax;             // 触上限钳位 / Clamped at upper limit
    bLimitHigh  := TRUE;                // 触上限标志 / Upper limit flag
    IF bEnable AND (NOT bHold) THEN
        eState := eLimited;             // 进入触限态 / Enter limited state
    END_IF
END_IF
IF fSumLReal <= rOutMin THEN
    fSumLReal  := rOutMin;              // 触下限钳位 / Clamped at lower limit
    bLimitLow  := TRUE;                 // 触下限标志 / Lower limit flag
    IF bEnable AND (NOT bHold) THEN
        eState := eLimited;             // 进入触限态 / Enter limited state
    END_IF
END_IF

fOut := LREAL_TO_REAL(fSumLReal);       // 双精度累加器转 REAL 输出 [EU·s] / Accumulator converted to REAL output [EU·s]
END_FUNCTION_BLOCK
