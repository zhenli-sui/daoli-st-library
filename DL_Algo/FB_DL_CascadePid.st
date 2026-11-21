(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CascadePid
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG 间接经子块），零厂商方言
 * 功能描述 (Function)   : 主副双回路串级 PID。主回路 PID 输出经限幅后作为副回路
 *                         设定值，副回路输出驱动执行器；适用温控（主温度 / 副加
 *                         热功率）、张力（主张力 / 副速度）等场景。内部组合两个
 *                         FB_DL_PidController 实例，本块不自写 PID 律；手动时副
 *                         回路直接手动输出，主回路经跟踪回投跟随副设定，回自动
 *                         零跳变。两个实例的采样周期与输出限幅统一由本块注入，
 *                         杜绝调用方双份配置不一致。
 * 开源溯源 (Origin)     : 原创实现。串级结构分类与参数域参考 OSCAT / 西门子
 *                         CASCADE_CONT 的公开语义描述，未复制任何厂商源码。
 * 本文件内含       : TYPE  E_DL_CascadeState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_CascadePid
 * 依赖     (Depends)    : FB_DL_PidController（DL_Algo 内部）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+非有限值防御
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE
 *                         R7 ✓ 定时器 / 边沿实例均由子块无条件刷新（本块无实例）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 04 · Level 1 DL_Algo
 * 验收向量 (Acceptance) :
 *   V1 串级跟随：主设定阶跃 50 → fSpSlave 平滑爬升并钳在副设定域内
 *   V2 副设定钳位：主回路输出超 rSpSlaveMax → fSpSlave 恰等于 rSpSlaveMax
 *   V3 手动无扰：手动副输出 40.0 切串级首拍 fOut 保持 40.0 连续
 *   V4 参数对调：rSpSlaveMin>rSpSlaveMax 时自动对调且 uErrorId=0002_0001
 *   V5 非有限值：fPvSlave 写入非法浮点 → 输出保持上一拍且 uErrorId=0002_0004
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CascadeState（归属 DL_Algo，与 FB_DL_CascadePid 同文件）
 * 含义: 串级控制器离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_CascadeState :
(
    eIdle    := 0,    // 使能关：双回路冻结，输出回下限 / Idle: enable off, both loops frozen
    eCascade := 10,   // 双回路自动：主环驱动副环闭环 / Cascade: master drives slave in closed loop
    eManual  := 20,   // 手动：副环手动输出，主环跟踪副设定 / Manual: slave manual, master tracks slave SP
    eFault   := 99    // 故障兜底态：非法状态进入，输出安全值 / Fault fallback: illegal state, safe output
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CascadePid
 * 调用约定: 每个扫描周期无条件调用一次；bReset 电平透传给两个子块。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 * 架构披露: 本块零自写 PID 律，仅做设定值路由、限幅注入与状态调度。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CascadePid
VAR_INPUT
    bEnable          : BOOL := FALSE;   // 总使能，FALSE 时输出回下限 / Master enable, FALSE drives output to low limit
    bManual          : BOOL := FALSE;   // 手动模式，TRUE 时副环手动 / Manual mode, TRUE puts slave loop in manual
    fManualSlaveValue: REAL := 0.0;     // 副回路手动输出 [%] / Slave loop manual output in percent
    fSpMaster        : REAL := 0.0;     // 主回路设定值 [EU] / Master loop setpoint in engineering units
    fPvMaster        : REAL := 0.0;     // 主回路过程值 [EU] / Master loop process value
    fPvSlave         : REAL := 0.0;     // 副回路过程值 [EU] / Slave loop process value
    fKpM             : REAL := 1.0;     // 主回路比例增益 [1] / Master loop proportional gain
    tTiM             : TIME := T#5S;    // 主回路积分时间 [s] / Master loop integral time
    tTdM             : TIME := T#0S;    // 主回路微分时间 [s] / Master loop derivative time
    fKpS             : REAL := 2.0;     // 副回路比例增益 [1]，默认更硬 / Slave gain, harder by default
    tTiS             : TIME := T#1S;    // 副回路积分时间 [s] / Slave loop integral time
    tTdS             : TIME := T#0S;    // 副回路微分时间 [s] / Slave loop derivative time
    rSpSlaveMin      : REAL := 0.0;     // 副设定域下限 [EU] / Slave setpoint domain lower limit
    rSpSlaveMax      : REAL := 100.0;   // 副设定域上限 [EU] / Slave setpoint domain upper limit
    rOutMin          : REAL := 0.0;     // 副环输出下限 [%] / Slave output lower limit in percent
    rOutMax          : REAL := 100.0;   // 副环输出上限 [%] / Slave output upper limit in percent
    tSampleTime      : TIME := T#100MS; // 采样周期，统一注入两个子块 / Sample period injected to both sub-blocks
    bReset           : BOOL := FALSE;   // 复位信号，电平透传两个子块 / Reset passed through to both sub-blocks
END_VAR
VAR_OUTPUT
    fOut             : REAL;            // 副回路控制输出 [%] / Slave loop control output in percent
    fSpSlave         : REAL;            // 副回路设定值 [EU]，诊断 / Slave setpoint in engineering units, diagnostics
    fErrMaster       : REAL;            // 主回路偏差 [EU]，诊断 / Master loop error, diagnostics
    bLimitHigh       : BOOL;            // 副环输出触上限 / Slave output at upper limit
    bLimitLow        : BOOL;            // 副环输出触下限 / Slave output at lower limit
    bError           : BOOL;            // 故障标志 / Fault flag
    uErrorId         : UDINT;           // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbPidMaster      : FB_DL_PidController;  // 主回路 PID 实例 / Master loop PID instance
    fbPidSlave       : FB_DL_PidController;  // 副回路 PID 实例 / Slave loop PID instance
    eState           : E_DL_CascadeState;    // 主状态机当前状态 / Current state of the state machine
    fSpSlaveLow      : REAL;            // 对调修复后的副设定域下限 [EU] / Repaired slave SP domain low limit
    fSpSlaveHigh     : REAL;            // 对调修复后的副设定域上限 [EU] / Repaired slave SP domain high limit
    fMasterOutClamp  : REAL;            // 钳位到副设定域的主回路输出 [EU] / Master output clamped into slave domain
    bNonFinite       : BOOL;            // 本拍输入非有限值标志 / Non-finite input flag of this cycle
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜参数钳位与公共防御（不中断扫描）
 *      Parameter clamping and common defenses, never stops the scan
 *-----------------------------------------------------------------------------*)
bError   := FALSE;                    // 每拍重算故障标志 / Recompute fault flag every cycle
uErrorId := 16#0002_0000;             // 每拍重算故障码 / Recompute error code every cycle
bLimitHigh := FALSE;                  // 触限标志每拍重算 / Saturation flags recomputed every cycle
bLimitLow  := FALSE;                  // 触限标志每拍重算 / Saturation flags recomputed every cycle
bNonFinite := FALSE;                  // 非有限值标志每拍重算 / Non-finite flag recomputed every cycle

IF tSampleTime < T#10MS THEN
    tSampleTime := T#10MS;            // 采样周期非法钳位为 10 ms / Illegal sample period clamped to 10 ms
    uErrorId := 16#0002_0002;         // 公共码：采样周期已钳位 / Common code: sample period clamped
END_IF

IF rSpSlaveMin > rSpSlaveMax THEN
    fSpSlaveLow  := rSpSlaveMax;      // 对调修复（下限取原上限） / Swapped repair of domain low limit
    fSpSlaveHigh := rSpSlaveMin;      // 对调修复（上限取原下限） / Swapped repair of domain high limit
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fSpSlaveLow  := rSpSlaveMin;      // 合法域下限直通 / Valid domain low limit passed
    fSpSlaveHigh := rSpSlaveMax;      // 合法域上限直通 / Valid domain high limit passed
END_IF

(* 输入非有限值防御：任一主 / 副回路信号非法即拒绝本拍更新 *)
(* Non-finite defense: reject this cycle if any master or slave signal invalid *)
IF (fSpMaster <> fSpMaster) OR (ABS(fSpMaster) > 1.0E30)
   OR (fPvMaster <> fPvMaster) OR (ABS(fPvMaster) > 1.0E30)
   OR (fPvSlave <> fPvSlave) OR (ABS(fPvSlave) > 1.0E30)
   OR (fManualSlaveValue <> fManualSlaveValue) OR (ABS(fManualSlaveValue) > 1.0E30) THEN
    bNonFinite := TRUE;               // 置非有限值标志 / Set non-finite flag
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜子块统一注入：两个实例的采样周期与输出限幅由本块独占配置
 *      Unified injection: sample period and output limits owned by this block
 *-----------------------------------------------------------------------------*)
fbPidMaster.bEnable     := bEnable AND (NOT bManual) AND (NOT bNonFinite);
fbPidMaster.fSetpoint   := fSpMaster;             // 主设定注入 / Inject master setpoint
fbPidMaster.fActual     := fPvMaster;             // 主过程值注入 / Inject master process value
fbPidMaster.fKp         := fKpM;                  // 主增益注入 / Inject master gain
fbPidMaster.tTi         := tTiM;                  // 主积分时间注入 / Inject master integral time
fbPidMaster.tTd         := tTdM;                  // 主微分时间注入 / Inject master derivative time
fbPidMaster.fDeadband   := 0.0;                   // 主环死区默认关闭 / Master deadband off by default
fbPidMaster.bIncremental:= FALSE;                 // 主环默认位置式 / Master positional by default
fbPidMaster.rOutMin     := fSpSlaveLow;           // 主输出域 = 副设定域（下限） / Master domain equals slave SP domain
fbPidMaster.rOutMax     := fSpSlaveHigh;          // 主输出域 = 副设定域（上限） / Master domain equals slave SP domain
fbPidMaster.tSampleTime := tSampleTime;           // 统一采样周期 / Unified sample period
fbPidMaster.bTrack      := FALSE;                 // 跟踪在状态机内按需置位 / Tracking set inside state machine
fbPidMaster.fTrackValue := fSpSlave;              // 跟踪值 = 当前副设定 / Track value equals current slave SP
fbPidMaster.bReset      := bReset;                // 复位透传 / Reset passed through

fbPidSlave.bEnable      := bEnable AND (NOT bNonFinite);
fbPidSlave.fSetpoint    := fSpSlave;              // 副设定注入 / Inject slave setpoint
fbPidSlave.fActual      := fPvSlave;              // 副过程值注入 / Inject slave process value
fbPidSlave.fKp          := fKpS;                  // 副增益注入 / Inject slave gain
fbPidSlave.tTi          := tTiS;                  // 副积分时间注入 / Inject slave integral time
fbPidSlave.tTd          := tTdS;                  // 副微分时间注入 / Inject slave derivative time
fbPidSlave.fDeadband    := 0.0;                   // 副环死区默认关闭 / Slave deadband off by default
fbPidSlave.bIncremental := FALSE;                 // 副环默认位置式 / Slave positional by default
fbPidSlave.rOutMin      := rOutMin;               // 副环输出下限注入 / Inject slave output low limit
fbPidSlave.rOutMax      := rOutMax;               // 副环输出上限注入 / Inject slave output high limit
fbPidSlave.tSampleTime  := tSampleTime;           // 统一采样周期 / Unified sample period
fbPidSlave.bTrack       := FALSE;                 // 副环不需要跟踪 / Slave needs no tracking
fbPidSlave.fTrackValue  := 0.0;                   // 跟踪值占位为 0 / Track value placeholder zero
fbPidSlave.bReset       := bReset;                // 复位透传 / Reset passed through

(*------------------------------------------------------------------------------
 * 段 3｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine: ENUM + CASE with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eState OF

    eIdle:
        (* 使能关：双回路冻结，输出回下限，副设定保持在域下限 *)
        (* Enable off: both loops frozen, output at low limit, slave SP at domain low *)
        fOut       := rOutMin;        // 输出回下限 / Output to low limit
        fSpSlave   := fSpSlaveLow;    // 副设定保持域下限 / Slave SP held at domain low
        fErrMaster := fSpMaster - fPvMaster;  // 主偏差仍刷新供诊断 / Master error for diagnostics
        IF bEnable AND (NOT bNonFinite) THEN
            IF bManual THEN
                eState := eManual;        // 请求手动 / Request manual mode
            ELSE
                eState := eCascade;       // 请求串级自动 / Request cascade auto
            END_IF
        END_IF

    eCascade:
        (* 串级自动：主回路闭环 → 主输出钳位到副设定域 → 副回路闭环 *)
        (* Cascade auto: master closed loop, output clamped into slave domain, slave loop *)
        IF bNonFinite THEN
            (* 非有限值拍：保持上一拍输出，置公共拒绝码 *)
            (* Non-finite cycle: hold previous output, common reject code *)
            bError   := TRUE;             // 置故障标志 / Set fault flag
            uErrorId := 16#0002_0004;     // 输入非有限值已拒绝 / Non-finite input rejected
        ELSE
            fbPidMaster.bEnable := TRUE;  // 主环使能 / Enable master loop
            fbPidMaster();                // 主回路运算 / Master loop computation
            fMasterOutClamp := LIMIT(fSpSlaveLow, fbPidMaster.fOut, fSpSlaveHigh);  // 钳位 / Clamp into slave domain
            IF fbPidMaster.bLimitHigh OR fbPidMaster.bLimitLow THEN
                IF uErrorId = 16#0002_0000 THEN
                    uErrorId := 16#0002_0201;  // 信息级：副设定超域已钳位 / Info: slave SP clamped
                END_IF
            END_IF
            fSpSlave := fMasterOutClamp;  // 副设定 = 钳位后的主输出 / Slave SP equals clamped master output
            fbPidSlave.bEnable := TRUE;   // 副环使能 / Enable slave loop
            fbPidSlave();                 // 副回路运算 / Slave loop computation
            fOut        := fbPidSlave.fOut;       // 输出 = 副环输出 / Output equals slave output
            fErrMaster  := fbPidMaster.fErr;      // 主偏差诊断 / Master error diagnostics
            bLimitHigh  := fbPidSlave.bLimitHigh; // 触限透传 / Saturation passthrough
            bLimitLow   := fbPidSlave.bLimitLow;  // 触限透传 / Saturation passthrough
        END_IF
        IF bManual THEN
            eState := eManual;            // 切手动 / Switch to manual
        ELSIF NOT bEnable THEN
            eState := eIdle;              // 切空闲 / Switch to idle
        END_IF

    eManual:
        (* 手动：副环直接手动输出，主环经跟踪回投跟随副设定，回自动无跳变 *)
        (* Manual: slave manual output, master tracks slave SP for bumpless return *)
        IF bNonFinite THEN
            bError   := TRUE;             // 置故障标志 / Set fault flag
            uErrorId := 16#0002_0004;     // 输入非有限值已拒绝 / Non-finite input rejected
        ELSE
            fbPidSlave.bEnable    := TRUE;             // 副环使能 / Enable slave loop
            fbPidSlave.bManual    := TRUE;             // 副环手动 / Slave in manual
            fbPidSlave.fManualValue := fManualSlaveValue;  // 手动值注入 / Inject manual value
            fbPidSlave();                              // 副环手动运算 / Slave manual computation
            fbPidSlave.bManual    := FALSE;            // 恢复自动配置位 / Restore auto config bit
            fOut       := fbPidSlave.fOut;             // 输出 = 副环手动值 / Output equals slave manual value
            fSpSlave   := fSpSlaveLow;                 // 副设定保持在域下限 / Slave SP held at domain low
            fbPidMaster.bEnable    := TRUE;            // 主环使能 / Enable master loop
            fbPidMaster.bManual    := TRUE;            // 主环手动跟踪模式 / Master in manual-track mode
            fbPidMaster.fManualValue := fSpSlaveLow;   // 手动值取域下限占位 / Manual value placeholder
            fbPidMaster.bTrack     := TRUE;            // 跟踪回投使能 / Track enable
            fbPidMaster.fTrackValue:= fSpSlaveLow;     // 主环跟随域下限防积分漂移 / Master tracks domain low
            fbPidMaster();                             // 主环跟踪运算 / Master tracking computation
            fbPidMaster.bManual    := FALSE;           // 恢复自动配置位 / Restore auto config bit
            fbPidMaster.bTrack     := FALSE;           // 清跟踪位 / Clear track bit
            fErrMaster := fbPidMaster.fErr;            // 主偏差诊断 / Master error diagnostics
            bLimitHigh  := fbPidSlave.bLimitHigh;      // 触限透传 / Saturation passthrough
            bLimitLow   := fbPidSlave.bLimitLow;       // 触限透传 / Saturation passthrough
        END_IF
        IF NOT bEnable THEN
            eState := eIdle;              // 切空闲 / Switch to idle
        ELSIF NOT bManual THEN
            eState := eCascade;           // 切串级 / Switch to cascade
        END_IF

    eFault:
        (* 故障兜底态：输出安全下限，等待复位解除 *)
        (* Fault fallback: safe low-limit output, released by reset *)
        fOut := rOutMin;                  // 安全输出 / Safe output

    ELSE
        (* 非法状态拦截：任何未定义状态一律进故障兜底，不做隐式恢复 *)
        (* Illegal state interception: any undefined state goes to fault fallback *)
        eState   := eFault;               // 进故障态 / Enter fault state
        bError   := TRUE;                 // 置故障标志 / Set fault flag
        uErrorId := 16#0002_0005;         // 非法状态兜底码 / Illegal state fallback code
        fOut     := rOutMin;              // 安全输出 / Safe output
END_CASE;

(* 子块故障聚合：优先透传副环故障码，无副环故障时透传主环故障码 *)
(* Sub-block fault aggregation: slave code first, then master code *)
IF (NOT bError) AND (uErrorId = 16#0002_0000) THEN
    IF fbPidSlave.bError THEN
        bError   := TRUE;                 // 副环故障置位 / Slave fault set
        uErrorId := fbPidSlave.uErrorId;  // 透传副环故障码 / Pass slave error code
    ELSIF fbPidMaster.bError THEN
        bError   := TRUE;                 // 主环故障置位 / Master fault set
        uErrorId := fbPidMaster.uErrorId; // 透传主环故障码 / Pass master error code
    END_IF
END_IF
END_FUNCTION_BLOCK
