//==============================================================================
// 功能块：FB_DL_MfcSetpointRamp ｜ 中文名称：MFC 设定值斜坡与超调抑制
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：质量流量控制器（MFC）设定值斜坡——目标值先钳量程域
//           [0, fRangeSccm]，再按恒定斜率 fSlewRateSccmS 向目标逼近
//           （每拍步进 = 斜率 x 扫描周期秒），到达即锁存 bRampDone 并
//           同步输出占量程百分比设定（fSpPctOut，模拟量给定位）。bHold
//           冻结当前值（保持，不回零）。斜坡中组态漂移（量程/斜率/周期
//           变非法）→ 冻结当前值安全侧并报故障。斜率限制即超调抑制的
//           上游手段（阶跃目标被强制线性化，下游 PID 不再追大阶跃）。
// 遗留假设（R95 代理阈值三句）：① 代理值 = fCycleTimeS 组态扫描周期
//           [秒]；② 覆盖 0.001~0.1 秒（1~100 ms）任务周期范围；③
//           覆盖不到的区间（更长周期或变周期任务）由调用方按实际任务
//           周期重设 fCycleTimeS 引脚负责，该假设挂编译验证债。
// 开源溯源 (Origin)：道莅原创实现（参考 MFC 流量控制与斜坡设定工程惯例 分类与参数域）
// 单位表：设定值[标准毫升每分钟 sccm] / 量程[sccm] / 斜率[sccm每秒] /
//         扫描周期[秒] / 百分比[%] / 时间[ms]
// 错误码表：16#0003_018E 信息级（斜坡完成：目标到达，不置 bError）/
//           16#0003_018F 信息级（目标超量程已钳位照算，不置 bError）/
//           16#0003_0366 故障级（组态非法：量程/斜率/周期 <= 0 或任一
//           输入非有限，置 bError）/ 16#0003_0367 故障级（斜坡中组态
//           漂移：运行态参数变非法，冻结当前值安全侧，置 bError——
//           该场景不可由 0366 的「触发前组态」路径观测，属运行中漂移
//           独立域）/ 16#0003_0368 故障级兜底（状态机落 ELSE，置
//           bError）
// 状态机：E_DL_MfcRampState（四态：eIdle=0 / eRamping=10 / eDone=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 0368 并冻结输出
// 边界行为：① 触发前组态非法 → 故障态锁存，bReset 复位；② 目标超
//           [0, 量程] → 双侧钳位照算 + 信息 018F；③ 斜坡中 bHold →
//           冻结当前值（保持非清零），撤销后续走；④ 到达锁存：目标
//           变更须新触发沿才重启斜坡（防每拍抖动重启）；⑤ 斜坡中
//           组态漂移 → 冻结当前值 + 故障 0367；⑥ 安全侧 = 故障态
//           fSpRampedSccm 冻结为进入故障前的最后合法值，禁止跳变
//           到 0 冲击工艺腔（MFC 设定跳变比保持更危险）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P2 §710）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_MfcRampState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 斜坡相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_MfcRampState :
(
    eIdle    := 0,   // 空闲：等触发沿 / Idle, awaiting trigger edge
    eRamping := 10,  // 斜坡中：恒斜率逼近目标 / Ramping, constant slew toward the target
    eDone    := 20,  // 完成：目标到达锁存 / Done, arrival latched
    eFault   := 99   // 故障：组态非法/漂移/非法状态 / Fault, config, drift or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_MfcSetpointRamp
VAR_INPUT
    bExecute      : BOOL;                   // 触发斜坡 [—]，上升沿生效 / Trigger the ramp, rising edge
    bHold         : BOOL;                   // 冻结保持 [—]，电平生效 / Freeze hold, level effective
    bReset        : BOOL;                   // 故障复位 [—]，上升沿清故障态 / Fault reset, rising edge clears the fault state
    fSpTargetSccm : LREAL;                  // 目标设定值 [标准毫升每分钟]，域外钳量程照算 / Target setpoint [sccm], clamped to the range
    fRangeSccm    : LREAL := 100.0;         // MFC 量程 [标准毫升每分钟]，须 > 0 / MFC full range [sccm], must be > 0
    fSlewRateSccmS: LREAL := 10.0;          // 斜率 [标准毫升每分钟每秒]，须 > 0 / Slew rate [sccm per second], must be > 0
    fCycleTimeS   : LREAL := 0.01;          // 任务扫描周期 [秒]，须 > 0（R95 代理阈值） / Task scan cycle [s], must be > 0, R95 proxy
END_VAR
VAR_OUTPUT
    fSpRampedSccm : LREAL;                  // 斜坡后设定值 [标准毫升每分钟] / Ramped setpoint [sccm]
    fSpPctOut     : LREAL;                  // 占量程百分比 [百分数]，0..100 / Percent of range [percent], 0..100
    bRampDone     : BOOL;                   // 斜坡完成 [—]（到达态电平） / Ramp done, arrival level
    eState        : E_DL_MfcRampState;      // 相位出口 [—] / Phase outlet
    eErr          : UDINT;                  // 错误码，0 = 无错，码位 16#0003_018E 起信息级、16#0003_0366 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError        : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbTrig    : R_TRIG;                     // 触发沿检测（待机/完成分支同样无条件刷新） / Trigger edge detector, refreshed unconditionally
    _eState   : E_DL_MfcRampState := E_DL_MfcRampState.eIdle; // 当前相位 / Current phase
    _bCfgBad  : BOOL;                       // 触发前组态非法锁存 / Pre-trigger config fault latch
    _bDriftBad: BOOL;                       // 运行中组态漂移锁存 / In-run config drift latch
    _bInfoClamp: BOOL;                      // 目标钳位信息当拍标志 / Target-clamp info flag of this scan
    _bInfoDone: BOOL;                       // 完成信息当拍标志 / Done info flag of this scan
    _fTarget  : LREAL;                      // 生效目标（已钳量程）[标准毫升每分钟] / Effective target, clamped [sccm]
    _fStep    : LREAL;                      // 本拍步进量 [标准毫升每分钟] / Per-scan step [sccm]
    _bIllegal : BOOL;                       // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_MSR_INF    : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_MSR_EPS    : LREAL := 1.0E-6;        // 浮点判零/到达容差 [标准毫升每分钟] / Zero and arrival tolerance [sccm]
    DL_MSR_ZERO   : LREAL := 0.0;           // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
    DL_MSR_PCT    : LREAL := 100.0;         // 百分比满量程 [百分数] / Full scale percent
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出保持语义的标志预清（设定值不在预置段清零，
 *       故障态须冻结而非清零——MFC 设定跳变比保持更危险）
 *      Flags pre-cleared, setpoint deliberately not cleared here
 *-----------------------------------------------------------------------------*)
fSpPctOut  := DL_MSR_ZERO;               // 百分比先清（段 5 重算） / Percent cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
bRampDone := FALSE;                      // 完成电平先清（段 5 重置） / Done level cleared first
_bInfoClamp := FALSE;                    // 钳位信息预清零 / Clamp info pre-cleared
_bInfoDone  := FALSE;                    // 完成信息预清零 / Done info pre-cleared
_bIllegal   := FALSE;                    // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState  := E_DL_MfcRampState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    fSpRampedSccm := DL_MSR_ZERO;        // 设定值从零起步 / Setpoint starts at zero
    _bInit  := TRUE;                     // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜触发沿无条件刷新（R40：CASE 之外每拍必调）
 *      Trigger edge refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbTrig(CLK := bExecute);                 // 触发沿检测 / Trigger edge detection

(*------------------------------------------------------------------------------
 * 段 4｜组态防御闸：非有限（R79）+ 量程/斜率/周期域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fSpTargetSccm <> fSpTargetSccm) OR (ABS(fSpTargetSccm) > DL_MSR_INF)
   OR (fRangeSccm <> fRangeSccm) OR (ABS(fRangeSccm) > DL_MSR_INF)
   OR (fSlewRateSccmS <> fSlewRateSccmS) OR (ABS(fSlewRateSccmS) > DL_MSR_INF)
   OR (fCycleTimeS <> fCycleTimeS) OR (ABS(fCycleTimeS) > DL_MSR_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fRangeSccm <= DL_MSR_EPS) OR (fSlewRateSccmS <= DL_MSR_EPS)
   OR (fCycleTimeS <= DL_MSR_EPS)) THEN
    _bCfgBad := TRUE;                    // 量程/斜率/周期域非法锁存 / Range, slew and cycle domains latched
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_MfcRampState.eIdle:               // 空闲：触发沿且组态合法进斜坡
        IF fbTrig.Q AND (NOT _bCfgBad) THEN
            _fTarget := MIN(MAX(fSpTargetSccm, DL_MSR_ZERO), fRangeSccm); // 目标钳量程域 / Target clamped to the range
            IF ABS(_fTarget - fSpTargetSccm) > DL_MSR_EPS THEN
                _bInfoClamp := TRUE;       // 目标超量程钳位提示（信息级） / Target clamped, info
            END_IF
            _eState := E_DL_MfcRampState.eRamping; // 进斜坡 / To ramping
        ELSIF fbTrig.Q AND _bCfgBad THEN
            _eState := E_DL_MfcRampState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_MfcRampState.eRamping:            // 斜坡：恒斜率逼近；bHold 冻结；漂移落故障
        // 拍 N 进入（触发沿）/ 本拍行为：步进 = 斜率 x 周期，向目标逼近 / 拍 N+1 转出：到达进 eDone
        IF _bCfgBad THEN
            _bDriftBad := TRUE;            // 运行中组态漂移锁存（冻结当前值） / In-run drift latched, value frozen
            _eState := E_DL_MfcRampState.eFault; // 进故障 / To fault
        ELSIF bHold THEN
            fSpRampedSccm := fSpRampedSccm; // 冻结保持：本拍不动（显式自持） / Hold, no movement this scan (explicit self-hold)
        ELSE
            _fStep := fSlewRateSccmS * fCycleTimeS; // 本拍步进量 [sccm] / Per-scan step
            IF fSpRampedSccm < (_fTarget - DL_MSR_EPS) THEN
                fSpRampedSccm := MIN(fSpRampedSccm + _fStep, _fTarget); // 上行逼近（饱和于目标） / Upward approach, saturated at the target
            ELSIF fSpRampedSccm > (_fTarget + DL_MSR_EPS) THEN
                fSpRampedSccm := MAX(fSpRampedSccm - _fStep, _fTarget); // 下行逼近（饱和于目标） / Downward approach, saturated at the target
            ELSE
                _bInfoDone := TRUE;        // 目标到达（信息级，拍 N 进入） / Target reached, info
                _eState := E_DL_MfcRampState.eDone; // 拍 N+1 转出：进完成锁存 / To done, latched
            END_IF
        END_IF

    E_DL_MfcRampState.eDone:               // 完成：锁存保持，新沿才重算
        IF _bCfgBad THEN
            _bDriftBad := TRUE;            // 完成态组态漂移同域锁存 / Drift latched in done
            _eState := E_DL_MfcRampState.eFault; // 进故障 / To fault
        ELSIF fbTrig.Q THEN
            _fTarget := MIN(MAX(fSpTargetSccm, DL_MSR_ZERO), fRangeSccm); // 新目标钳量程 / New target clamped
            IF ABS(_fTarget - fSpTargetSccm) > DL_MSR_EPS THEN
                _bInfoClamp := TRUE;       // 新目标钳位提示 / New target clamped, info
            END_IF
            _eState := E_DL_MfcRampState.eRamping; // 新沿重斜坡 / New edge re-ramps
        END_IF

    E_DL_MfcRampState.eFault:              // 故障：复位沿且组态恢复回空闲（设定值保持冻结值）
        IF bReset AND (NOT _bCfgBad) AND (NOT _bDriftBad) THEN
            _bDriftBad := FALSE;           // 复位清漂移锁存 / Reset clears the drift latch
            _eState := E_DL_MfcRampState.eIdle; // 回空闲（冻结值保持） / Back to idle, frozen value held
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_MfcRampState.eFault; // 回故障态（设定值冻结） / Back to fault, value frozen
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜输出换算与码位出口（故障级码 3 行内置 bError，R45/R101 配对）
 *      Output scaling and code outlet, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF ABS(fRangeSccm) > DL_MSR_EPS THEN
    fSpPctOut := MIN(MAX(fSpRampedSccm / fRangeSccm, DL_MSR_ZERO), 1.0) * DL_MSR_PCT; // 占量程百分比 [百分数]，分母已闸 / Percent of range, denominator gated
ELSE
    fSpPctOut := DL_MSR_ZERO;              // 量程退化兜底（组态闸已挡，防御路径） / Degenerate range fallback
END_IF
fSpRampedSccm := MIN(MAX(fSpRampedSccm, DL_MSR_ZERO), fRangeSccm); // 输出终值钳量程域 / Final setpoint clamped to the range
bRampDone := (_eState = E_DL_MfcRampState.eDone); // 完成电平挂状态量（R99） / Done level bound to the state

IF _bIllegal THEN
    eErr   := 16#0003_0368;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bDriftBad THEN
    eErr   := 16#0003_0367;                // 故障级：斜坡中组态漂移（冻结安全侧） / Fault: in-run config drift, frozen safe side
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0003_0366;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoClamp THEN
    eErr := 16#0003_018F;                  // 信息级：目标超量程已钳位 / Info: target clamped to the range
ELSIF _bInfoDone THEN
    eErr := 16#0003_018E;                  // 信息级：斜坡完成 / Info: ramp done
END_IF

bValid := (NOT bError) AND (_eState <> E_DL_MfcRampState.eIdle); // 空闲/故障输出不可用 / Outputs unusable in idle or fault
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
