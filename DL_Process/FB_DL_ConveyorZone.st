(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ConveyorZone
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / TP），零厂商方言
 * 分类     (Category)   : 工艺段功能块（Function Block · 输送线积放单区）
 * 功能简述 (Function)   : 单段皮带/滚筒输送线积放控制器（Zero-Pressure
 *                         Accumulation 单区）。积放单句规则：有料且下游允
 *                         许才走；卡料窗判定；run-on 清区；级联放行信号；
 *                         浪涌防护（使能沿后延迟发运行指令）；驱动控制经
 *                         I_DL_VfdDrive 接口引用（既有契约，引脚注入）。
 * 接口消费 (Consumes)   : I_DL_VfdDrive（既有接口，R6 已入库，仅引用契约文
 *                         件，零修改零新增 DUT）：运行指令 iDrive.CmdRun()/
 *                         iDrive.CmdStop()，反馈读 iDrive.bRunning/bFault。
 * 枚举归属 (Enum note)  : E_DL_ZoneState 随本块同文件发布（公约 0.11 口径：
 *                         配套枚举与主块同文件，头注释注明归属）。
 * 公约遵循 (Convention) : 0.1/R23 显式使能/指令沿驱动（无自动首扫初始化语
 *                         义），免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 全部实例
 *                         主体最前部无条件刷新；0.7/R15 卡料与故障锁存仅复
 *                         位路径清码；0.13 每拍至多一次接口方法调用。
 *                         0.8 故障码段位 16#0005_xxxx（经 DL_Process
 *                         VERSION.md 码表核对：规格建议 0005_0210/0211 已被
 *                         FB_DL_OccScheduleWindow 占用、0005_0103 已被
 *                         FB_DL_EnthalpyCompareCtrl 占用，依公约冲突顺延）：
 *                         【故障级】0005_0212 驱动指令-反馈失配、0005_0213
 *                         下游驱动故障透传、0005_0214 非法状态兜底；
 *                         【信息级】0005_0113 卡料预警（计时中未到窗）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 时序窗防御/锁存复位路径 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 九实例（R_TRIG×4/TON×5）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 积放核心：RunReq = 使能 AND 无卡料 AND 无故障
 *                           AND（有料 OR 上区补跑）AND（下游允许 OR 出口空）；
 *                           末区特殊语义由调用方接线决定（bDownstreamReady
 *                           接工序就绪），本块不内判末区；
 *                         ② 驱动控制经 iDrive：RunReq 沿发 CmdRun、撤令发
 *                           CmdStop；指令-反馈失配超 tStartDelay → 故障；
 *                           方法返回 FALSE 且 iDrive.bFault → 故障透传；
 *                         ③ 卡料：RunReq 持续 + 出口光电持续遮挡超
 *                           tJamWindow → bJam 锁存（仅 bReset 清）；计时中
 *                           未到窗 → 信息级预警；
 *                         ④ 浪涌防护：使能上升沿后延迟 tStartDelay 再发运
 *                           行指令（多区级联间隔释放由各区 bZoneReady 天然
 *                           承载）；
 *                         ⑤ 手动放行：bCmdRelease 沿 → 短时放行 tRunOn
 *                           （绕过下游条件，调试用）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 码位顺延：规格建议 0005_0210/0211/0103 与既有
 *                           组件冲突，依公约 0.8 顺延为 0005_0212/0213/0214
 *                           与 0005_0113（核对结果优先于建议值）。
 * 开源溯源 (Origin)     : 来源标签 conveyor-accumulation（RAW_NOTES_R7 S-9：
 *                         零积压积放（ZPA）输送线公开工程惯例——有料且下游
 *                         允许才走、run-on 清区、卡料窗、间隔释放（提取点
 *                         ⑤⑥），公开技术资料，仅借鉴规则域；状态机、接口
 *                         消费模式、码位与引脚契约 100% 本库独立设计，
 *                         clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 有料放行/积存/清区 run-on 逐拍：bPEEntry→下游允许→运行；bPEDischarge
 *      清空后 run-on 窗停机；
 *   V2 下游阻断积放充满：bDownstreamReady=FALSE → 积存态 eAccumulating；
 *   V3 卡料窗锁存+复位：RunReq+出口遮挡超 tJamWindow → bJam + eJamFault，
 *      仅 bReset 清；
 *   V4 驱动失配：CmdRun 发出后 iDrive.bRunning 迟到超 tStartDelay → 故障
 *      0005_0212；
 *   V5 上区补跑：bUpstreamOcc=TRUE 且本区空 → 补跑合拢；
 *   V6 手动放行：bCmdRelease 沿 → tRunOn 短时放行。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Process 输送线积放件）
 *   2026-11-15  v1.0.1  终审修复 2 处：① 手动放行覆盖式赋值连使能/卡料/故
 *                       障/浪涌门控一并绕过（禁用区被发出运行指令），改为仅
 *                       绕过下游条件、保留门控；② tRunOn 清区延续窗未按契
 *                       约 V1 实现（仅用于手动放行），新增 run-on 保持逻辑
 *                       （清空沿 + tRunOn 延续，使能/卡料/故障终止）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ZoneState（归属 FB_DL_ConveyorZone，与其同文件）
 * 含义: 积放区状态机离散状态。编号步长 10 留空位，eJamFault 取 99 保证排
 *       序末位（全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ZoneState :
(
    eStopped      := 0,   // 停止：无运行指令 / Stopped, no run command
    eRunning      := 10,  // 运行：运行指令有效且驱动反馈确认 / Running, command active and drive feedback confirmed
    eAccumulating := 20,  // 积存：有料但放行条件不满足 / Accumulating, product present but release conditions unmet
    eJamFault     := 99   // 卡料/故障锁存：仅 bReset 可退出 / Jam or fault latched, only reset exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ConveyorZone
VAR_INPUT
    bPEEntry        : BOOL;             // 入口光电（Entry photoeye），TRUE=有料进入本区 / Entry photoeye, TRUE = product entering
    bPEDischarge    : BOOL;             // 出口光电（Discharge photoeye），TRUE=料仍在本区出口未清 / Discharge photoeye, TRUE = product at exit
    bDownstreamReady: BOOL;             // 下游允许放行（Downstream ready），末区接下游工序就绪；中区接下区 bZoneReady / Downstream ready, last zone ties to process ready
    bZoneEnable     : BOOL;             // 本区使能（Zone enable），FALSE=驱动停止且请求清零 / Zone enable, FALSE stops the drive
    bUpstreamOcc    : BOOL;             // 上区有料（Upstream occupied，可选过渡联动），TRUE=本区为空也补跑合拢 / Upstream occupied, gap-closing run when empty
    tRunOn          : TIME := T#1S;     // 清区延续时间（Run-on time），默认 T#1S；出口光电清空后再运行此窗 / Run-on time after the exit photoeye clears
    tJamWindow      : TIME := T#8S;     // 卡料判定窗（Jam window），默认 T#8S；按区长度/带速整定 / Jam window, tune per zone length and belt speed
    tStartDelay     : TIME := T#500MS;  // 启动确认延迟（Start feedback delay），默认 T#500MS；兼作使能沿浪涌延迟 / Start feedback delay, also the enable-edge surge delay
    bCmdRelease     : BOOL;             // 手动放行指令（Manual release，调试用），上升沿短时放行 / Manual release edge, short bypass release
    bReset          : BOOL;             // 上升沿复位卡料与故障（Reset edge clears jam and fault）/ Rising edge resets jam and fault
END_VAR
VAR_OUTPUT
    bZoneReady  : BOOL;                 // 本区就绪（Zone ready），使能无故障无卡料且本区空可接收上游来料 / Zone ready to accept upstream product
    bOccupied   : BOOL;                 // 本区有料（Zone occupied），入口或出口光电任一遮挡 / Zone occupied by either photoeye
    bJam        : BOOL;                 // 卡料锁存（Jam latched），仅 bReset 清 / Jam latched, cleared only by reset
    bFault      : BOOL;                 // 故障标志（Fault flag），显式排除信息级 / Fault flag, info codes excluded
    uErrorId    : UDINT;                // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, family 16#0005_xxxx
END_VAR
VAR_IN_OUT
    iDrive      : I_DL_VfdDrive;        // 本区驱动接口引用（Zone drive），由上层注入实例（既有契约 I_DL_VfdDrive）/ Zone drive interface reference injected by caller
END_VAR
VAR
    _eState        : E_DL_ZoneState := E_DL_ZoneState.eStopped; // 内部区状态（Internal zone state） / Internal state
    _bFaultLatch   : BOOL;             // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt   : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode     : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bOccupiedInt  : BOOL;             // 内部有料派生（Internal occupied derived）/ Internal occupied derived
    _bRunReq       : BOOL;             // 积放运行请求（Accumulation run request）/ Accumulation run request
    _bRunCmdSent   : BOOL;             // 运行指令已发出锁存（Run command sent latch）/ Run command sent latch
    _bEnableDelay  : BOOL;             // 使能沿浪涌延迟激活（Enable-edge surge delay active）/ Enable-edge surge delay active
    _bManualReq    : BOOL;             // 手动放行请求（Manual release request）/ Manual release request
    _bRunOnHold    : BOOL;             // run-on 清区延续保持（Run-on sustain hold）/ Run-on sustain hold flag
    _bDriveFwd     : BOOL;             // 驱动方向登记（Drive direction registered），恒正向 / Drive direction, always forward
    _fbTrigEnable  : R_TRIG;           // 使能上升沿（Enable rising edge）/ Enable edge detector
    _fbTrigRelease : R_TRIG;           // 手动放行沿（Manual release edge）/ Manual release edge detector
    _fbTrigReset   : R_TRIG;           // 复位沿（Reset edge）/ Reset edge detector
    _fbTrigClear   : R_TRIG;           // 清空沿（Occupied falling edge），run-on 启动判据 / Occupied falling edge detector
    _fbTonJam      : TON;              // 卡料判定窗（Jam window timer）/ Jam window timer
    _fbTonFbWindow : TON;              // 指令-反馈失配窗（Command-feedback mismatch window）/ Mismatch window
    _fbTonEnable   : TON;              // 使能沿浪涌延迟（Enable-edge surge delay）/ Enable-edge surge delay
    _fbTonManual   : TON;              // 手动放行延续（Manual release sustain）/ Manual release sustain
    _fbTonRunOn    : TON;              // run-on 清区延续窗（Run-on sustain window）/ Run-on sustain window timer
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigEnable(CLK := bZoneEnable);
_fbTrigRelease(CLK := bCmdRelease);
_fbTrigReset(CLK := bReset);
_fbTonJam(IN := _bRunReq AND bPEDischarge AND (NOT _bFaultLatch) AND (NOT bJam), PT := tJamWindow);   // 卡料窗（Jam window）
_fbTonFbWindow(IN := _bRunCmdSent XOR iDrive.bRunning, PT := tStartDelay);                            // 失配窗（Mismatch window）
_fbTonEnable(IN := _bEnableDelay, PT := tStartDelay);                                                 // 浪涌延迟（Surge delay）
_fbTonManual(IN := _bManualReq, PT := tRunOn);                                                        // 手动放行延续（Manual sustain）
_fbTrigClear(CLK := (NOT _bOccupiedInt));                                                             // 清空沿（Occupied falling edge）
_fbTonRunOn(IN := _bRunOnHold, PT := tRunOn);                                                         // run-on 清区延续窗（Run-on sustain window）

// ============================================================================
// 段 2｜信息级预清零 + 复位路径（R15：卡料与故障锁存仅复位路径清码）
//      Info preset + reset path (R15)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）

IF _fbTrigReset.Q THEN
    bJam := FALSE;                // 卡料锁存解除（Jam released）
    _bFaultLatch := FALSE;        // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
END_IF

// ============================================================================
// 段 3｜故障全局监视（优先级最高）：失配 / 驱动故障透传
//      Global fault monitors: command-feedback mismatch / drive fault pass-through
// ============================================================================
IF _fbTonFbWindow.Q AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;         // 指令-反馈失配锁存（Mismatch latch）
    _uErrorIdInt := 16#0005_0212; // 0005_0212 驱动指令-反馈失配【故障级】/ Drive command-feedback mismatch, fault level
    _eState := E_DL_ZoneState.eJamFault;
END_IF
IF iDrive.bFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;         // 下游驱动故障透传锁存（Drive fault pass-through latch）
    _uErrorIdInt := 16#0005_0213; // 0005_0213 下游驱动故障透传【故障级】/ Downstream drive fault pass-through, fault level
    _eState := E_DL_ZoneState.eJamFault;
END_IF

// ============================================================================
// 段 4｜核心积放状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core accumulation state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
_bOccupiedInt := bPEEntry OR bPEDischarge;  // 有料派生（Occupied derived）
bOccupied := _bOccupiedInt;                 // 有料出口（Occupied outlet）

IF _fbTrigEnable.Q THEN
    _bEnableDelay := TRUE;        // 使能沿启动浪涌延迟（Enable edge arms surge delay）
END_IF
IF _fbTonEnable.Q THEN
    _bEnableDelay := FALSE;       // 浪涌延迟结束（Surge delay finished）
END_IF
IF NOT bZoneEnable THEN
    _bEnableDelay := FALSE;       // 使能撤销延迟作废（Delay voided on disable）
END_IF

IF _fbTrigRelease.Q THEN
    _bManualReq := TRUE;          // 手动放行沿登记（Manual release armed）
END_IF
IF _fbTonManual.Q THEN
    _bManualReq := FALSE;         // 手动放行延续结束（Manual sustain finished）
END_IF

// run-on 清区延续（v1.0.1 新增，契约 V1 落地）：运行中出口/入口光电全清空沿
// 启动 tRunOn 延续窗，窗内保持运行请求确保物料完全清出区段；使能撤销/卡料/
// 故障立即终止（Run-on hold: keep running tRunOn after the product clears,
// cancelled by disable/jam/fault, v1.0.1）
IF _fbTrigClear.Q AND _bRunCmdSent AND bZoneEnable AND (NOT bJam) AND (NOT _bFaultLatch) THEN
    _bRunOnHold := TRUE;          // 运行中清空沿启动延续窗（Clear edge while running arms the hold）
END_IF
IF _fbTonRunOn.Q OR (NOT bZoneEnable) OR bJam OR _bFaultLatch THEN
    _bRunOnHold := FALSE;         // 延续窗到期或门控撤销终止（Hold released on expiry or gating loss）
END_IF

// 积放单句规则：有料（或上区补跑）且下游允许（或出口空）才走（末区语义由接
// 线承担，本块不内判末区）；run-on 清区延续：出口光电清空后继续运行 tRunOn
// 窗确保完全清出（v1.0.1 按契约 V1 落地）
// ZPA rule: run when occupied (or gap-closing) AND downstream ready (or exit clear);
// run-on hold keeps the belt running tRunOn after the product clears (v1.0.1)
_bRunReq := bZoneEnable AND (NOT bJam) AND (NOT _bFaultLatch)
        AND (_bOccupiedInt OR bUpstreamOcc OR _bRunOnHold)
        AND (bDownstreamReady OR (NOT bPEDischarge))
        AND (NOT _bEnableDelay);  // 浪涌延迟未过不发令（No command before surge delay elapses）
IF _bManualReq THEN
    // 手动放行仅绕过下游条件（v1.0.1 修复：原覆盖式赋值连使能/卡料/故障/浪涌
    // 门控一并绕过，禁用区会被发出运行指令）/ Manual release bypasses the
    // downstream condition ONLY, gating preserved (v1.0.1 fix)
    _bRunReq := bZoneEnable AND (NOT bJam) AND (NOT _bFaultLatch) AND (NOT _bEnableDelay);
END_IF

IF bJam OR _bFaultLatch THEN
    CASE _eState OF
        E_DL_ZoneState.eJamFault: ; // 锁存态等待复位（Latched, awaiting reset）
        ELSE
            _eState := E_DL_ZoneState.eJamFault; // 锁存标志同步（Latch state sync）
    END_CASE
ELSIF NOT bZoneEnable THEN
    _eState := E_DL_ZoneState.eStopped; // 未使能停止（Disabled stop）
    _bRunCmdSent := FALSE;              // 撤销指令锁存（Command latch revoked）
ELSE
    CASE _eState OF

        E_DL_ZoneState.eStopped: // 停止态：评估运行请求
            IF _bRunReq THEN
                _eState := E_DL_ZoneState.eRunning; // 受理运行（Run accepted）
            END_IF

        E_DL_ZoneState.eRunning: // 运行态：撤令回停止/积存
            IF NOT _bRunReq THEN
                IF _bOccupiedInt THEN
                    _eState := E_DL_ZoneState.eAccumulating; // 有料积存（Accumulate）
                ELSE
                    _eState := E_DL_ZoneState.eStopped;      // 空区停止（Stopped when empty）
                END_IF
            END_IF

        E_DL_ZoneState.eAccumulating: // 积存态：等待放行条件
            IF _bRunReq THEN
                _eState := E_DL_ZoneState.eRunning; // 放行（Release）
            ELSIF NOT _bOccupiedInt THEN
                _eState := E_DL_ZoneState.eStopped; // 清空停止（Stopped when cleared）
            END_IF

        E_DL_ZoneState.eJamFault: // 卡料/故障态：复位路径见段 2
            IF NOT bJam THEN
                _eState := E_DL_ZoneState.eStopped; // 复位后回停止（Back to stopped after reset）
            END_IF

        ELSE
            // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
            _bFaultLatch := TRUE;             // 故障锁存（Fault latch）
            _uErrorIdInt := 16#0005_0214;     // 0005_0214 非法状态兜底【故障级】/ Illegal state, fault level
            _eState := E_DL_ZoneState.eJamFault;
    END_CASE
END_IF

// ============================================================================
// 段 5｜驱动接口编排（0.13：每拍至多一次方法调用）+ 卡料锁存 + 信息级预警
//      Drive orchestration (max one method call per scan) + jam latch + info
// ============================================================================
IF _bRunReq AND (NOT _bRunCmdSent) THEN
    _bDriveFwd := TRUE;                                 // 方向登记恒正向（Direction always forward）
    IF NOT iDrive.CmdRun(bFwd := _bDriveFwd) THEN       // 发运行指令（Issue run command）
        IF iDrive.bFault THEN
            _bFaultLatch := TRUE;                       // 指令被拒且驱动故障：透传锁存（Rejected with drive fault: pass-through latch）
            _uErrorIdInt := 16#0005_0213;               // 0005_0213 下游驱动故障透传【故障级】/ Drive fault pass-through, fault level
            _eState := E_DL_ZoneState.eJamFault;
        END_IF
    ELSE
        _bRunCmdSent := TRUE;                           // 指令发出锁存（Command sent latch）
    END_IF
ELSIF (NOT _bRunReq) AND _bRunCmdSent THEN
    iDrive.CmdStop();                                   // 撤令停机（Issue stop command）
    _bRunCmdSent := FALSE;                              // 撤销锁存（Latch revoked）
END_IF

IF (_fbTonJam.ET > T#0S) AND _fbTonJam.IN THEN
    _uInfoCode := 16#0005_0113;   // 0005_0113 卡料预警（计时中未到窗）【信息级】/ Jam warning (timing, below window), info level
END_IF
IF _fbTonJam.Q THEN
    bJam := TRUE;                 // 卡料窗到锁存（Jam window reached, latch）
    _eState := E_DL_ZoneState.eJamFault;
END_IF

bZoneReady := bZoneEnable AND (NOT bJam) AND (NOT _bFaultLatch) AND (NOT _bOccupiedInt); // 就绪派生（Ready derived form）

// ============================================================================
// 段 6｜bFault/uErrorId 出口（R21：bFault 显式排除信息级）
//      Outlets: bFault excludes info codes (R21)
// ============================================================================
bFault := _bFaultLatch;           // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK
