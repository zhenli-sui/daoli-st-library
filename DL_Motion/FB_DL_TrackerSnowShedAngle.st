//==============================================================================
// 功能块：FB_DL_TrackerSnowShedAngle ｜ 中文名称：跟踪支架雪载卸荷角与复位
// 所属子库：DL_Motion ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：雪载卸荷顺控——采暖季窗有效（bHeatSeason 电平，由上层日历
//           窗给出）且雪载超阈值 → 目标角切卸荷角（限速逼近，保护减速
//           机与雪载静摩擦）；卸荷保持最短时间后才允许退出（防雪未滑
//           落即回摆重复触发）；退出条件 = 雪载 < 阈值 - 回差 或 采暖季
//           结束，且保持最短时间已满 → 目标角切回正常跟踪角（透传输入，
//           限速逼近）。角反馈全程跟踪校验：反馈与命令偏差超容差持续
//           超窗 → 判跟踪失败，冻结命令安全侧并报故障。
// 遗留假设（R95 代理阈值三句）：① 代理值 = fCycleTimeS 组态扫描周期
//           [秒]（限速积分基量）；② 覆盖 0.001~0.1 秒任务周期范围；
//           ③ 覆盖不到的区间由调用方按实际任务周期重设该引脚负责，
//           该假设挂编译验证债。同拍多窗配比约束（R100）：
//           tTrackTimeout > tShedHoldMin 不作要求（两窗职责独立：跟踪
//           失败窗对准伺服响应量级，卸荷保持窗对准雪滑落量级）。
// 开源溯源 (Origin)：道莅原创实现（参考跟踪支架雪载卸荷工程惯例 分类与参数域）
// 单位表：角度[度] / 角速度[度每秒] / 雪载[千克每平方米] / 阈值与回差
//         [千克每平方米] / 时间[ms] / 扫描周期[秒]
// 错误码表：16#0004_01E9 信息级（卸荷角到位提示，不置 bError）/
//           16#0004_01EA 信息级（复位角到位提示，不置 bError）/
//           16#0004_0309 故障级（组态非法：卸荷/复位角域、阈值/回差域、
//           限速/周期 <= 0 或任一输入非有限，置 bError）/ 16#0004_030A
//           故障级（角度反馈跟踪失败：反馈与命令偏差超容差持续超窗，
//           冻结命令安全侧，置 bError——该场景不可由 0309 的组态类
//           判据观测，属伺服跟踪独立域）/ 16#0004_030B 故障级兜底
//           （状态机落 ELSE，置 bError）
// 状态机：E_DL_SnowShedState（六态：eIdle=0 / eTrack=10 / eShedding=20 /
//           eShedHold=30 / eReturning=40 / eFault=99），CASE 含 ELSE
//           兜底，ELSE 置 030B 并冻结命令
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 限速逼近双向
//           适用（卸荷与复位均限速，防机构冲击）；③ 雪载回差防抖
//           （退出阈值 = 阈值 - 回差，阈值附近抖动防频动，R23 教训）；
//           ④ 卸荷保持最短时间未满不退出（防雪未滑落即回摆）；⑤ 故障
//           态命令冻结为最后合法值（跟踪失败时跳变比保持更危险）；
//           ⑥ 未使能命令冻结为 0 度并 bValid := FALSE。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §812）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_SnowShedState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 雪载卸荷相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SnowShedState :
(
    eIdle      := 0,   // 空闲：未使能 / Idle, not enabled
    eTrack     := 10,  // 跟踪：命令透传正常跟踪角 / Track, pass-through to the tracking angle
    eShedding  := 20,  // 卸荷中：限速逼近卸荷角 / Shedding, slewing to the shed angle
    eShedHold  := 30,  // 卸荷保持：最短保持计时 / Shed hold, minimum hold counting
    eReturning := 40,  // 复位中：限速逼近跟踪角 / Returning, slewing back to the tracking angle
    eFault     := 99   // 故障：组态非法/跟踪失败/非法状态 / Fault, config, tracking loss or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrackerSnowShedAngle
VAR_INPUT
    bEnable        : BOOL;                  // 卸荷控制使能 [—] / Shed control enable
    bReset         : BOOL;                  // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    bHeatSeason    : BOOL;                  // 采暖季窗有效 [—]（上层日历窗电平） / Heating-season window level
    fSnowLoadKgm2  : LREAL;                 // 雪载实测/估测 [千克每平方米] / Snow load [kg/m2]
    fTrackAngleDeg : LREAL;                 // 正常跟踪角 [度]（上层跟踪器透传） / Normal tracking angle [deg], pass-through
    fAngleFbDeg    : LREAL;                 // 角度反馈 [度] / Angle feedback [deg]
    fSnowThreshKgm2: LREAL := 5.0;          // 卸荷雪载阈 [千克每平方米]，须 > 0 / Shed threshold [kg/m2]
    fSnowHystKgm2  : LREAL := 1.0;          // 退出回差 [千克每平方米]，须 >= 0 且 < 阈值 / Exit hysteresis [kg/m2]
    fShedAngleDeg  : LREAL := 60.0;         // 卸荷角 [度]，域 [0, 90] / Shed angle [deg], domain 0..90
    fMaxSlewDegS   : LREAL := 2.0;          // 限速 [度每秒]，须 > 0 / Max slew rate [deg/s]
    fCycleTimeS    : LREAL := 0.01;         // 任务扫描周期 [秒]，须 > 0（R95 代理阈值） / Task scan cycle [s], must be > 0, R95 proxy
    tShedHoldMin   : TIME  := T#30S;        // 卸荷最短保持 [ms]，须 > 0 / Minimum shed hold [ms]
    fTrackTolDeg   : LREAL := 5.0;          // 反馈跟踪容差 [度]，须 > 0 / Feedback tracking tolerance [deg]
    tTrackTimeout  : TIME  := T#30S;        // 跟踪失败窗 [ms]，须 > 0 / Tracking-loss window [ms]
END_VAR
VAR_OUTPUT
    fAngleCmdDeg   : LREAL;                 // 角度命令 [度]（限速后，给驱动层） / Angle command [deg], post-slew
    bShedActive    : BOOL;                  // 卸荷活动 [—]（卸荷/保持态电平） / Shed active level
    eState         : E_DL_SnowShedState;    // 相位出口 [—] / Phase outlet
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0004_01E9 起信息级、16#0004_0309 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbHold   : TON;                         // 卸荷保持计时（每拍无条件刷新）[ms] / Hold timer, refreshed unconditionally
    fbTrack  : TON;                         // 跟踪失败窗计时（每拍无条件刷新）[ms] / Tracking-loss timer, refreshed unconditionally
    _eState  : E_DL_SnowShedState := E_DL_SnowShedState.eIdle; // 当前相位 / Current phase
    _bCfgBad : BOOL;                        // 组态非法锁存 / Illegal config latch
    _bTrackBad: BOOL;                       // 跟踪失败锁存 / Tracking-loss latch
    _bInfoShed: BOOL;                       // 卸荷到位信息当拍标志 / Shed-arrival info flag of this scan
    _bInfoRet : BOOL;                       // 复位到位信息当拍标志 / Return-arrival info flag of this scan
    _fTarget  : LREAL;                      // 当前目标角 [度] / Current target angle [deg]
    _fStep    : LREAL;                      // 本拍限速步进 [度] / Per-scan slew step [deg]
    _bIllegal : BOOL;                       // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_TSS_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_TSS_EPS     : LREAL := 1.0E-6;       // 浮点判零/到位容差 [度] / Zero and arrival tolerance [deg]
    DL_TSS_SHED_MAX: LREAL := 90.0;         // 卸荷角域上限 [度] / Shed angle domain ceiling [deg]
    DL_TSS_ZERO    : LREAL := 0.0;          // 零值常量，避免裸字面量 [度] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：命令角保持语义（预置不清零，故障须冻结），标志预清零
 *      Command kept by design (frozen in fault), flags pre-cleared
 *-----------------------------------------------------------------------------*)
bShedActive := FALSE;                    // 卸荷电平先清（段 5 重置） / Shed level cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoShed := FALSE;                     // 卸荷信息预清零 / Shed info pre-cleared
_bInfoRet  := FALSE;                     // 复位信息预清零 / Return info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState   := E_DL_SnowShedState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad  := FALSE;                  // 组态锁存清零 / Config latch cleared
    _bTrackBad := FALSE;                 // 跟踪锁存清零 / Tracking latch cleared
    fAngleCmdDeg := DL_TSS_ZERO;         // 命令角从零起步 / Command starts at zero
    _bInit   := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 角度/阈值/限速/周期/时间窗域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fSnowLoadKgm2 <> fSnowLoadKgm2) OR (ABS(fSnowLoadKgm2) > DL_TSS_INF)
   OR (fTrackAngleDeg <> fTrackAngleDeg) OR (ABS(fTrackAngleDeg) > DL_TSS_INF)
   OR (fAngleFbDeg <> fAngleFbDeg) OR (ABS(fAngleFbDeg) > DL_TSS_INF)
   OR (fSnowThreshKgm2 <> fSnowThreshKgm2) OR (ABS(fSnowThreshKgm2) > DL_TSS_INF)
   OR (fSnowHystKgm2 <> fSnowHystKgm2) OR (ABS(fSnowHystKgm2) > DL_TSS_INF)
   OR (fShedAngleDeg <> fShedAngleDeg) OR (ABS(fShedAngleDeg) > DL_TSS_INF)
   OR (fMaxSlewDegS <> fMaxSlewDegS) OR (ABS(fMaxSlewDegS) > DL_TSS_INF)
   OR (fCycleTimeS <> fCycleTimeS) OR (ABS(fCycleTimeS) > DL_TSS_INF)
   OR (fTrackTolDeg <> fTrackTolDeg) OR (ABS(fTrackTolDeg) > DL_TSS_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fSnowThreshKgm2 <= DL_TSS_EPS) OR (fSnowHystKgm2 < DL_TSS_ZERO)
   OR (fSnowHystKgm2 >= fSnowThreshKgm2) OR (fShedAngleDeg < DL_TSS_ZERO)
   OR (fShedAngleDeg > DL_TSS_SHED_MAX) OR (fMaxSlewDegS <= DL_TSS_EPS)
   OR (fCycleTimeS <= DL_TSS_EPS) OR (fTrackTolDeg <= DL_TSS_EPS)
   OR (tShedHoldMin <= T#0MS) OR (tTrackTimeout <= T#0MS)) THEN
    _bCfgBad := TRUE;                    // 角度/阈值/限速/周期/时间窗域非法锁存 / Angle, threshold, slew, cycle and window domains latched
END_IF
IF bReset THEN
    _bCfgBad   := FALSE;                 // 复位清组态锁存 / Reset clears the config latch
    _bTrackBad := FALSE;                 // 复位清跟踪锁存 / Reset clears the tracking latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜双计时无条件刷新（R40：CASE 之外每拍必调）
 *      Two timers refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbHold(IN := (_eState = E_DL_SnowShedState.eShedHold), PT := tShedHoldMin); // 卸荷保持窗 / Shed hold window
fbTrack(IN := (_eState = E_DL_SnowShedState.eShedding)
             OR (_eState = E_DL_SnowShedState.eReturning)
             OR (_eState = E_DL_SnowShedState.eTrack), PT := tTrackTimeout); // 跟踪失败窗（由段 5 IN 复判有效） / Tracking-loss window

(*------------------------------------------------------------------------------
 * 段 5｜相位机与限速逼近（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine and the slew approach
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_SnowShedState.eIdle:              // 空闲：使能且组态合法进跟踪态
        IF bEnable AND (NOT _bCfgBad) THEN
            _eState := E_DL_SnowShedState.eTrack; // 进跟踪 / To track
        ELSIF bEnable AND _bCfgBad THEN
            _eState := E_DL_SnowShedState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_SnowShedState.eTrack:             // 跟踪：透传正常角；采暖季且雪超阈进卸荷
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_SnowShedState.eFault; // 异常转故障 / Anomaly, fault
        ELSE
            _fTarget := fTrackAngleDeg;    // 目标 = 正常跟踪角 / Target is the tracking angle
            IF bHeatSeason AND (fSnowLoadKgm2 > fSnowThreshKgm2) THEN
                _fTarget := fShedAngleDeg; // 目标切卸荷角 / Target switches to the shed angle
                _eState := E_DL_SnowShedState.eShedding; // 进卸荷 / To shedding
            END_IF
        END_IF

    E_DL_SnowShedState.eShedding:          // 卸荷：限速逼近；到位进保持；反馈失跟落故障
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_SnowShedState.eFault; // 异常转故障 / Anomaly, fault
        ELSE
            _fTarget := fShedAngleDeg;     // 目标 = 卸荷角 / Target is the shed angle
            IF ABS(fAngleFbDeg - fAngleCmdDeg) > fTrackTolDeg THEN
                IF fbTrack.Q THEN
                    _bTrackBad := TRUE;    // 跟踪失败锁存（拍 N 进入） / Tracking loss latched
                    _eState := E_DL_SnowShedState.eFault; // 本拍转出：进故障冻结 / To fault, frozen
                END_IF
            ELSE
                _fTarget := fShedAngleDeg; // 到位判据仍按命令目标 / Arrival judged on the command target
                IF ABS(fAngleCmdDeg - _fTarget) <= DL_TSS_EPS THEN
                    _bInfoShed := TRUE;    // 卸荷角到位（信息级，拍 N 进入） / Shed angle reached, info
                    _eState := E_DL_SnowShedState.eShedHold; // 本拍转出：进保持 / To hold
                END_IF
            END_IF
        END_IF

    E_DL_SnowShedState.eShedHold:          // 保持：最短时间未满不退出；退出条件两判据 + 保持满
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_SnowShedState.eFault; // 异常转故障 / Anomaly, fault
        ELSIF fbHold.Q AND (NOT bHeatSeason
               OR (fSnowLoadKgm2 < (fSnowThreshKgm2 - fSnowHystKgm2))) THEN
            _eState := E_DL_SnowShedState.eReturning; // 保持满且（季末或雪回差退出）进复位 / To returning
        END_IF

    E_DL_SnowShedState.eReturning:         // 复位：限速回跟踪角；到位进跟踪态
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_SnowShedState.eFault; // 异常转故障 / Anomaly, fault
        ELSE
            _fTarget := fTrackAngleDeg;    // 目标 = 正常跟踪角 / Target is the tracking angle
            IF ABS(fAngleFbDeg - fAngleCmdDeg) > fTrackTolDeg THEN
                IF fbTrack.Q THEN
                    _bTrackBad := TRUE;    // 跟踪失败锁存 / Tracking loss latched
                    _eState := E_DL_SnowShedState.eFault; // 进故障冻结 / To fault, frozen
                END_IF
            ELSE
                IF ABS(fAngleCmdDeg - _fTarget) <= DL_TSS_EPS THEN
                    _bInfoRet := TRUE;     // 复位角到位（信息级） / Return angle reached, info
                    _eState := E_DL_SnowShedState.eTrack; // 进跟踪态 / To track
                END_IF
            END_IF
        END_IF

    E_DL_SnowShedState.eFault:             // 故障：复位沿且原因消失回跟踪态（命令保持冻结值）
        IF bReset AND (NOT _bCfgBad) AND (NOT _bTrackBad) THEN
            _eState := E_DL_SnowShedState.eTrack; // 回跟踪 / Back to track
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState := E_DL_SnowShedState.eFault; // 回故障态（命令冻结） / Back to fault, command frozen
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜限速逼近（跟踪/卸荷/复位态执行；故障/空闲冻结，不跳变）
 *      Slew approach in motion phases, frozen in fault and idle
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_SnowShedState.eTrack)
   OR (_eState = E_DL_SnowShedState.eShedding)
   OR (_eState = E_DL_SnowShedState.eReturning)
   OR (_eState = E_DL_SnowShedState.eShedHold) THEN
    _fStep := fMaxSlewDegS * fCycleTimeS;  // 本拍限速步进 [度] / Per-scan slew step
    IF fAngleCmdDeg < (_fTarget - DL_TSS_EPS) THEN
        fAngleCmdDeg := MIN(fAngleCmdDeg + _fStep, _fTarget); // 上行限速逼近（饱和于目标） / Upward slew, saturated at the target
    ELSIF fAngleCmdDeg > (_fTarget + DL_TSS_EPS) THEN
        fAngleCmdDeg := MAX(fAngleCmdDeg - _fStep, _fTarget); // 下行限速逼近 / Downward slew
    END_IF
ELSIF _eState = E_DL_SnowShedState.eIdle THEN
    fAngleCmdDeg := DL_TSS_ZERO;           // 未使能命令归零（安全侧） / Not enabled, command to zero
END_IF
bShedActive := (_eState = E_DL_SnowShedState.eShedding)
            OR (_eState = E_DL_SnowShedState.eShedHold); // 卸荷活动电平挂状态量（R99） / Shed level bound to the states

(*------------------------------------------------------------------------------
 * 段 7｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0004_030B;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bTrackBad THEN
    eErr   := 16#0004_030A;                // 故障级：角度反馈跟踪失败（命令冻结安全侧） / Fault: tracking loss, command frozen
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0004_0309;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoRet THEN
    eErr := 16#0004_01EA;                  // 信息级：复位角到位 / Info: return angle reached
ELSIF _bInfoShed THEN
    eErr := 16#0004_01E9;                  // 信息级：卸荷角到位 / Info: shed angle reached
END_IF

bValid := (NOT bError) AND bEnable AND (_eState <> E_DL_SnowShedState.eIdle); // 空闲/故障/未使能输出不可用 / Outputs unusable in idle, fault or disabled
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
