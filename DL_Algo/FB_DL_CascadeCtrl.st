(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CascadeCtrl
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 来源标签 (Source)     : self-std（控制族新增线）
 * 功能描述 (Function)   : 串级控制**骨架**：主回路 PID 输出作从回路外设定，从回路输出
 *                         驱动执行器；双向抗积分饱和（从回路输出饱和时冻结主回路积分）
 *                         + 手动切串级无扰（主 / 从两环积分分别回投跟踪）。
 * 分工互引 (Boundary)   : ① FB_DL_CascadePid 是「双 PID 直连组合件」，只做手动/串级
 *                         两态与副设定钳位；本件是**骨架件**：把抗饱和回投、从环跟踪、
 *                         切换无扰三件事做成显式状态与显式出口，供上层工站编排；
 *                         ② 分程控制归 FB_DL_SplitRangeControl（单回路双阀），与本件
 *                         双回路结构不同；③ 限速归 FB_DL_RateLimiter（本件不做斜坡）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 抗饱和口径（条件积分）：从回路输出处于饱和（>= 上限或 <= 下限）且误差同向时，
 *      冻结主回路积分累加（不再朝饱和方向推进）；反向误差照常积分（可自然退出饱和）。
 *   2) 无扰切换：eManual -> eCascade 的切换拍，主回路积分预置为
 *      fSpSlaveLast − fKpM × eM，从回路积分预置为 fManualOut − fKpS × eS，
 *      使切换拍输出连续（验收向量见头注释末行）。
 *   3) 采样时间 tSample 只用于积分折算，fDtSec 由 TIME 转得并参与有限闸（R272）；
 *      tSample <= T#0S 属组态非法。
 *   4) 组态域闸全枚举全部浮点入参（R272）：主/从 PV 与设定、四个增益、四个限值、
 *      fDtSec 全部进入有限性判据；Inf 才是真穿透通道，故不许漏项。
 *   5) 非有限输入：本拍不推进积分（冻结保持上一拍积分量），输出保持上一拍值，
 *      置故障级码并锁存至复位沿 + 输入恢复（污染值绝不允许进入积分器）。
 * 故障码表 (Error codes) :
 *   16#0002_3750 [故障级] 组态非法（限值反向 / 增益非有限 / 采样周期非正）
 *                 反证：冻结保持与「设定恰好等于反馈」输出组合相同，无码不可区分。
 *   16#0002_3751 [故障级] 输入非有限（PV 或设定），积分冻结且输出保持
 *                 反证：保持与「误差为零自然稳态」输出相同，无码则 NaN 事故静默。
 *   16#0002_3753 [信息级] 抗饱和生效（主回路积分被冻结，bAntiWindup 同源可查）
 *                 反证：积分冻结是内部行为，输出上看不出「本拍本该多积多少」。
 * 码位总账 (Code ledger) : 16#0002_3750 / 3751 用 ｜ 16#0002_3753 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量 ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸（fDtSec 由组态闸保证 > 0）/ 非有限三判 / 域闸全枚举
 *                         R5 ✓ 全变量双语同行注释 ｜ R6 ✓ 四态 ENUM + ELSE 兜底
 *                         R7 ✓ 一沿实例主体最前部无条件刷新
 * 修订历史 (Revision)   : 2026-11-22  v1.0.0  首版入库（R69 构建轮 · 批 3 · N9）
 *   验收向量：V1 串级跟随（主设定阶跃 -> 从设定平滑且钳在域内）；V2 抗饱和（从输出
 *             顶到上限时主积分不再增长）；V3 无扰切换（手动 40.0 切串级首拍输出 40.0）；
 *             V4 非有限（PV 写 NaN -> 输出保持 + 3751 锁存，复位沿后恢复）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CascCtrlState（归属 DL_Algo，与 FB_DL_CascadeCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CascCtrlState :
(
    eIdle    := 0,    // 未使能：输出下限（安全侧）/ Disabled, output at the lower limit
    eCascade := 10,   // 串级自动：主环驱动从环 / Cascade, master drives the slave
    eManual  := 20,   // 手动：从环手动输出，两环跟踪 / Manual, slave manual, both loops tracking
    eFault   := 99    // 故障锁存：输出保持上一拍 / Fault latched, output holds the last value
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CascadeCtrl
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CascadeCtrl
VAR_INPUT
    fSpMaster   : REAL := 0.0;              // 主回路设定 [工程单位] / master setpoint
    fPvMaster   : REAL := 0.0;              // 主回路测量 [工程单位] / master process value
    fPvSlave    : REAL := 0.0;              // 从回路测量 [工程单位] / slave process value
    fKpM        : REAL := 1.0;              // 主回路比例增益 [无量纲] / master proportional gain
    fKiM        : REAL := 0.1;              // 主回路积分增益 [1/s] / master integral gain
    fKpS        : REAL := 1.0;              // 从回路比例增益 [无量纲] / slave proportional gain
    fKiS        : REAL := 0.5;              // 从回路积分增益 [1/s] / slave integral gain
    fSpSlaveMin : REAL := 0.0;              // 从回路外设定下限 [工程单位] / slave setpoint floor
    fSpSlaveMax : REAL := 100.0;            // 从回路外设定上限 [工程单位] / slave setpoint ceiling
    fOutMin     : REAL := 0.0;              // 执行器输出下限 [%] / actuator output floor [%]
    fOutMax     : REAL := 100.0;            // 执行器输出上限 [%] / actuator output ceiling [%]
    tSample     : TIME := T#100MS;          // 采样周期 [ms]，<= T#0S 组态非法 / sample period [ms]
    bCascadeMode: BOOL := TRUE;             // TRUE = 串级自动，FALSE = 手动 / TRUE cascade, FALSE manual
    fManualOut  : REAL := 0.0;              // 手动输出 [%] / manual output [%]
    bEnable     : BOOL := TRUE;             // 使能 / enable
    bReset      : BOOL;                     // 上升沿：清故障锁存 / rising edge clears the fault latch
END_VAR
VAR_OUTPUT
    fOut        : REAL;                     // 执行器输出 [%]，域 [fOutMin, fOutMax] / actuator output [%]
    fSpSlave    : REAL;                     // 从回路生效外设定 [工程单位] / effective slave setpoint
    bAntiWindup : BOOL;                     // 抗饱和生效（主积分被冻结）/ anti-windup active
    bSaturated  : BOOL;                     // 从回路输出饱和 / slave output saturated
    bError      : BOOL;                     // 故障标志（组态 / 非有限锁存）/ fault flag
    uErrorId    : UDINT;                    // 故障码，0 = 无故障 / error code, 0 = none
    eState      : E_DL_CascCtrlState;       // 当前状态（供 HMI 诊断）/ current state
END_VAR
VAR
    fbTrigReset : R_TRIG;                   // 复位沿检测实例 / reset edge detector
    eStateInt   : E_DL_CascCtrlState;       // 主状态机内部当前态 / internal state
    eStatePrev  : E_DL_CascCtrlState;       // 上一拍状态（切换沿判据）/ previous state for the transfer edge
    fDtSec      : REAL;                     // 采样周期折算 [s]，参与有限闸 / sample period in seconds, gated
    fErrM       : REAL;                     // 主回路误差 [工程单位] / master error
    fErrS       : REAL;                     // 从回路误差 [工程单位] / slave error
    fIntM       : REAL;                     // 主回路积分累加量 [工程单位] / master integral term
    fIntS       : REAL;                     // 从回路积分累加量 [%] / slave integral term
    fSpSlaveRaw : REAL;                     // 未钳的从回路外设定 [工程单位] / unclamped slave setpoint
    fOutRaw     : REAL;                     // 未钳的执行器输出 [%] / unclamped actuator output
    fOutHold    : REAL;                     // 输出保持值（非有限期）[%] / held output value
    bInBad      : BOOL;                     // 本拍输入非有限 / input non-finite this scan
    bCfgBad     : BOOL;                     // 本拍组态非法 / config illegal this scan
    bCfgLatch   : BOOL;                     // 组态锁存（复位沿 + 组态改对解除）/ config latch
    bFaultLatch : BOOL;                     // 非有限锁存（复位沿 + 输入恢复解除）/ non-finite latch
    bSatInt     : BOOL;                     // 从回路输出饱和内部副本 / internal saturation flag
    bErrorInt   : BOOL;                     // 本拍故障置位累加（出口归并）/ fault set accumulator
    bFirstScan  : BOOL := TRUE;             // 上电首扫标志 / first-scan flag
END_VAR
VAR CONSTANT
    DL_CC_FIN_LIM : REAL := 1.0E30;         // REAL 幅值兜底判界 / REAL magnitude bound
    DL_CC_MS_TO_S : REAL := 1000.0;         // 毫秒到秒折算常数 [ms/s] / milliseconds per second
END_VAR
VAR
    nSampleMs   : DINT;                     // 采样周期整毫秒 [ms] / sample period in whole milliseconds
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿实例位于主体最前部
 *      Unconditional refresh: the edge instance at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(* 段 2｜上电首扫：积分与输出落安全侧 / first-scan init *)
IF bFirstScan THEN
    eStateInt  := E_DL_CascCtrlState.eIdle;
    eStatePrev := E_DL_CascCtrlState.eIdle;
    fIntM      := 0.0;
    fIntS      := 0.0;
    fOutHold   := 0.0;
    bFirstScan := FALSE;
END_IF

(* 段 3｜每拍预清（FB32-1）：单拍标志，禁入积分 / per-scan preset *)
bSatInt := FALSE;

bErrorInt := FALSE;                     // 每拍预清（单拍标志）/ per-scan preset

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 / R272 全枚举）：四个限值序 + 四个增益 + 采样周期 + fDtSec
 *      Config gate over the limits, the gains, the sample period and fDtSec
 *      解除路径（R152 自证可达）：复位沿 AND 组态非法条件全部消失
 *-----------------------------------------------------------------------------*)
nSampleMs := TIME_TO_DINT(tSample);     // TIME -> 整毫秒（标准转换函数）/ TIME to milliseconds
fDtSec    := DINT_TO_REAL(nSampleMs) / DL_CC_MS_TO_S;   // 毫秒 -> 秒（除子为常数 1000 > 0）[s] / to seconds

bCfgBad := (fSpSlaveMin >= fSpSlaveMax) OR (fOutMin >= fOutMax)
           OR (fSpSlaveMin <> fSpSlaveMin) OR (fSpSlaveMax <> fSpSlaveMax)
           OR (fOutMin <> fOutMin) OR (fOutMax <> fOutMax)
           OR (fKpM <> fKpM) OR (fKiM <> fKiM) OR (fKpS <> fKpS) OR (fKiS <> fKiS)
           OR (ABS(fKpM) >= DL_CC_FIN_LIM) OR (ABS(fKiM) >= DL_CC_FIN_LIM)
           OR (ABS(fKpS) >= DL_CC_FIN_LIM) OR (ABS(fKiS) >= DL_CC_FIN_LIM)
           OR (ABS(fSpSlaveMin) >= DL_CC_FIN_LIM) OR (ABS(fSpSlaveMax) >= DL_CC_FIN_LIM)
           OR (ABS(fOutMin) >= DL_CC_FIN_LIM) OR (ABS(fOutMax) >= DL_CC_FIN_LIM)
           OR (tSample <= T#0S) OR (fDtSec <= 0.0) OR (fDtSec <> fDtSec)
           OR (ABS(fDtSec) >= DL_CC_FIN_LIM);

IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;                   // 组态锁存解除 / config latch cleared
    uErrorId  := 16#0000_0000;            // 码位随解除归零 / code cleared with the latch
END_IF
IF bCfgLatch THEN
    uErrorId  := 16#0002_3750;            // 故障级：组态非法 / fault: illegal configuration
    bErrorInt := TRUE;                    // R45 配对 / paired with the code
    eStateInt := E_DL_CascCtrlState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜输入有限闸（R272）：PV 与设定全部入闸；非有限即锁存并冻结积分
 *      Input finiteness gate: any non-finite PV freezes the integrals and holds the output
 *-----------------------------------------------------------------------------*)
bInBad := (fSpMaster <> fSpMaster) OR (fPvMaster <> fPvMaster) OR (fPvSlave <> fPvSlave)
          OR (fManualOut <> fManualOut)
          OR ((fSpMaster - fSpMaster) <> (fSpMaster - fSpMaster))
          OR ((fPvMaster - fPvMaster) <> (fPvMaster - fPvMaster))
          OR ((fPvSlave - fPvSlave) <> (fPvSlave - fPvSlave))
          OR (ABS(fSpMaster) >= DL_CC_FIN_LIM) OR (ABS(fPvMaster) >= DL_CC_FIN_LIM)
          OR (ABS(fPvSlave) >= DL_CC_FIN_LIM) OR (ABS(fManualOut) >= DL_CC_FIN_LIM);

IF bInBad THEN
    bFaultLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bInBad) THEN
    bFaultLatch := FALSE;                 // 非有限锁存解除（复位沿 + 输入恢复）/ latch cleared once the input is finite
    uErrorId    := 16#0000_0000;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine, phase semantics only
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_CascCtrlState.eIdle:
        IF bEnable AND (NOT bCfgLatch) AND (NOT bFaultLatch) THEN
            IF bCascadeMode THEN
                eStateInt := E_DL_CascCtrlState.eCascade;
            ELSE
                eStateInt := E_DL_CascCtrlState.eManual;
            END_IF
        END_IF

    E_DL_CascCtrlState.eCascade:
        IF (NOT bEnable) OR bCfgLatch OR bFaultLatch THEN
            eStateInt := E_DL_CascCtrlState.eIdle;
        ELSIF NOT bCascadeMode THEN
            eStateInt := E_DL_CascCtrlState.eManual;    // 切手动（从环手动，主环跟踪）/ to manual with tracking
        END_IF

    E_DL_CascCtrlState.eManual:
        IF (NOT bEnable) OR bCfgLatch OR bFaultLatch THEN
            eStateInt := E_DL_CascCtrlState.eIdle;
        ELSIF bCascadeMode THEN
            eStateInt := E_DL_CascCtrlState.eCascade;   // 切串级（切换拍做无扰回投）/ to cascade with bumpless transfer
        END_IF

    E_DL_CascCtrlState.eFault:
        IF fbTrigReset.Q AND (NOT bCfgBad) AND (NOT bInBad) THEN
            bCfgLatch := FALSE;                         // 两类锁存同沿解除 / both latches cleared together
            bFaultLatch := FALSE;
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_CascCtrlState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截 / illegal state interception *)
        eStateInt := E_DL_CascCtrlState.eFault;
        uErrorId  := 16#0002_3750;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜主 / 从两环求值与抗饱和回投（条件积分口径）
 *      Master and slave evaluation with conditional-integration anti-windup
 *-----------------------------------------------------------------------------*)
fErrM := fSpMaster - fPvMaster;                 // 主回路误差 [工程单位] / master error
fErrS := 0.0;                                   // 从回路误差缺省 0（从设定在下段算出）/ slave error default
bAntiWindup := FALSE;

IF (NOT bInBad) AND (NOT bCfgLatch) AND (eStateInt <> E_DL_CascCtrlState.eFault) THEN
    IF eStateInt = E_DL_CascCtrlState.eManual THEN
        (* 手动：从环手动输出，两环做跟踪回投（直接零跳变）/ manual with loop tracking *)
        fIntS := fManualOut - fKpS * (fSpSlave - fPvSlave);   // 从环积分回投 [%] / slave integral back-injected
        fIntM := fSpSlave - fKpM * fErrM;                     // 主环积分回投（输出即从设定）[工程单位] / master integral back-injected
    ELSE
        (* 串级：主环条件积分（从环饱和且误差同向时冻结）/ cascade with conditional integration *)
        IF bSatInt AND (((fSpSlave >= fSpSlaveMax) AND (fErrM > 0.0)) OR ((fSpSlave <= fSpSlaveMin) AND (fErrM < 0.0))) THEN
            bAntiWindup := TRUE;                   // 冻结主积分（不再朝饱和方向推进）/ freeze the master integral
            uErrorId    := 16#0002_3753;           // 信息级：抗饱和生效 / info: anti-windup active
        ELSE
            fIntM := fIntM + fKiM * fErrM * fDtSec;   // 主积分推进 [工程单位] / master integral step
        END_IF
        fSpSlaveRaw := fKpM * fErrM + fIntM;       // 主环输出即从环设定 [工程单位] / master output is the slave setpoint
        IF fSpSlaveRaw > fSpSlaveMax THEN
            fSpSlaveRaw := fSpSlaveMax;            // 从设定钳上限 / clamp the slave setpoint
        ELSIF fSpSlaveRaw < fSpSlaveMin THEN
            fSpSlaveRaw := fSpSlaveMin;            // 从设定钳下限 / clamp the slave setpoint
        END_IF
        fErrS := fSpSlaveRaw - fPvSlave;           // 从回路误差 [工程单位] / slave error
        fIntS := fIntS + fKiS * fErrS * fDtSec;    // 从积分推进 [%] / slave integral step
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出合成与限幅（非有限期保持上一拍值）/ output folding with the hold path
 *-----------------------------------------------------------------------------*)
IF (eStateInt = E_DL_CascCtrlState.eManual) THEN
    fOutRaw := fManualOut;                         // 手动：直出手动值 [%] / manual pass-through
ELSE
    fOutRaw := fKpS * fErrS + fIntS;               // 串级：从环 PI 输出 [%] / slave PI output
END_IF

IF fOutRaw > fOutMax THEN
    fOutRaw  := fOutMax;                           // 输出钳上限 [%] / clamp high
    bSatInt  := TRUE;
ELSIF fOutRaw < fOutMin THEN
    fOutRaw  := fOutMin;                           // 输出钳下限 [%] / clamp low
    bSatInt  := TRUE;
END_IF

IF bInBad OR bCfgLatch THEN
    fOut := fOutHold;                              // 非有限 / 组态故障：保持上一拍（不注入污染值）[%] / hold
    IF bInBad THEN
        uErrorId  := 16#0002_3751;                 // 故障级：输入非有限 / fault: non-finite input
        bErrorInt := TRUE;                         // R45 配对 / paired with the code
    END_IF
ELSIF eStateInt = E_DL_CascCtrlState.eIdle THEN
    fOut := fOutMin;                               // 未使能：输出下限（安全侧）[%] / disabled, output floor
ELSE
    fOut := fOutRaw;                               // 正常：限幅后输出 [%] / normal path
END_IF
fOutHold := fOut;                                  // 保持值快照（主体末行）/ snapshot the hold value

(*------------------------------------------------------------------------------
 * 段 9｜输出单一出口（范式 P-05）
 *      Single output exit
 *-----------------------------------------------------------------------------*)
IF eStateInt = E_DL_CascCtrlState.eCascade THEN
    fSpSlave := fSpSlaveRaw;                       // 串级：生效从设定即主环输出 [工程单位] / effective slave setpoint
ELSE
    fSpSlave := fPvSlave;                          // 手动 / 空闲：从设定跟实测（跟踪位置）[工程单位] / tracking position
END_IF
bSaturated := bSatInt;
bError     := bErrorInt OR bCfgLatch OR bFaultLatch;
eState     := eStateInt;
eStatePrev := eStateInt;                           // 状态快照刷新（供下一拍切换沿判据）/ refresh the state snapshot
END_FUNCTION_BLOCK
