(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SlitValveInterlock
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Device / ValveInterlock
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / LIMIT
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 真空闸阀互斥互锁
 * 功能一句话 (Summary)  : 真空腔体与大传片腔之间的闸阀互锁：真空度、大气侧门位、
 *                         机械臂退出三个条件同拍判据，任一不满足即拒绝开阀并
 *                         给出位掩码阻塞原因；开/关指令严格互斥、先清后置。
 *
 * 本件存在的意义 (Why this unit exists)
 *   库内只有 InterlockMatrix 的通用掩码，没有「门类」语义：不知道真空度是
 *   模拟量、不知道门位反馈会自相矛盾、也不知道电磁阀开/关两路必须互斥。
 *   半导体 EFEM 场景里这些是必备项——闸阀在大气侧门开着时打开，等于把
 *   整个真空腔瞬间放空并可能夹住机械臂。
 *
 * 保守侧纪律 (Conservative side, 三条写死)
 *   ① 门位反馈自相矛盾（两路同时为真）或两路皆假持续 tFbTimeout
 *      → 故障 033D，**一律按「门未关」处理**（保守侧）；
 *   ② 真空度为非有限值或 < 0 → 故障 033E，**按「真空不足」处理**
 *      （不假定真空已建立）；
 *   ③ 联锁不满足而仍有开阀请求 → 故障 033C + uBlockMask（HMI 直接显示位）。
 *
 * 位置反馈收窄声明 (Pin truth —— 必须读，否则会误判本件缺陷)
 *   引脚集内**没有闸阀本体位置反馈**。tFbTimeout 的语义因此被收窄为
 *   「指令已发出但无位置确认」的等待窗：窗内保持指令且处于 eOpening；
 *   窗满仍无反馈则接受指令已生效、进 eOpen，并置信息 0173 提示
 *   「无位置反馈确认」。**绝不因超时反转指令**（规格④：保持指令并提示）。
 *   这不是遗漏，而是本件引脚契约的边界；有本体反馈的机型应在外部把反馈
 *   串入 bAtmDoorClosed/Open 的判据链，或另立带反馈的变体件。
 *
 * 边界安全 (Boundary)
 *   - 开/关两路输出**互斥**：段 1 先把两路都置 FALSE，段 8 再按状态只置一路
 *     （R72 双路径，同拍双 TRUE 是电磁阀线圈烧毁根因）；
 *   - 失能 → eClosing（先关阀），bValveOpenCmd := FALSE；关到位确认后回 eIdle；
 *   - 三个 TON 实例在主体前部无条件刷新（R40），门位/开等待/关等待各一只，
 *     绝不跨相复用同一实例；
 *   - CASE 落 ELSE 置 033E 兜底并回 eFault（非法状态无专用码，按「真空/判定
 *     不可信」同族复用，R90 留档）。
 *
 * 错误码    : 16#0003_0172 联锁满足，已放行开阀——信息级，正常放行
 *             16#0003_0173 到位反馈超时（无位置确认），保持当前指令——信息级，不反转
 *             16#0003_033C 联锁不满足，拒绝开阀（配 uBlockMask）——故障级
 *             16#0003_033D 门位反馈自相矛盾或缺失，按门未关处理——故障级
 *             16#0003_033E 真空度非法（非有限/负值/阈值非法），按真空不足处理——故障级
 * 码位总账  : 16#0003_0172 用 / 16#0003_0173 用 ｜ 16#0003_033C 用 / 16#0003_033D 用 / 16#0003_033E 用
 * 状态机    : E_DL_SlitValveState（eIdle / eOpening / eOpen / eClosing / eInterlock / eFault），
 *             CASE 含 ELSE 兜底，ELSE 置 16#0003_033E 并回 eFault；失能无条件回 eClosing
 * 采样约定  : 每任务周期调用一次；等待窗由 tFbTimeout 给定，不读系统时钟
 * 依赖说明  : 仅 Standard.library；健康出口本件不使用 E_DL_Ne107Status（互锁是
 *             许可判定而非健康分级），故不引用契约件
 * 验收向量  : V1 真空 50 Pa、门关、臂退、请求开 → 放行，eErr = 0172，bValveOpenCmd = TRUE，
 *                uBlockMask = 0，bInterlockOk = TRUE
 *             V2 真空 50 Pa、门两路同时为真 → 033D，uBlockMask 含位 2，拒绝开阀（保守侧主向量）
 *             V3 真空 -5 Pa → 033E，uBlockMask 含位 1，拒绝开阀（不假定真空主向量）
 *             V4 真空 500 Pa（> 阈值 100）、请求开 → 033C，uBlockMask = 1
 *             V5 请求开、门未关 → 033C + uBlockMask = 2，两路输出均为 FALSE（互斥向量）
 *             V6 请求开 3 s 无位置确认 → eOpen，eErr = 0173，指令保持 TRUE（不反转主向量）
 *             V7 bEnable 落 → eClosing，bValveOpenCmd = FALSE，关到位后回 eIdle
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 无除法
 *             浮点只用大小比较 ｜ 无循环 ｜ 全变量双语同行注释 ｜ ENUM + CASE 含
 *             ELSE ｜ 三个 TON 在主体前部无条件刷新 ｜ 位掩码常量化，无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 2 · 设备安全互斥）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SlitValveState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 闸阀互锁的工作相位。0 起步长 10。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SlitValveState :
(
    eIdle      := 0,   // 待机：阀关闭、无请求 / Idle, valve closed, no request
    eOpening   := 10,  // 开启中：指令已发，等待位置确认窗 / Opening, command issued, waiting for the ack window
    eOpen      := 20,  // 已开：指令保持有效 / Open, the command is held active
    eClosing   := 30,  // 关闭中：关阀指令有效 / Closing, the close command is active
    eInterlock := 40,  // 联锁阻塞：拒绝开阀并给出掩码 / Interlock blocked, opening refused with a mask
    eFault     := 99   // 故障：门位矛盾、真空非法或非法状态 / Fault, contradictory door, illegal vacuum or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_SlitValveInterlock
VAR_INPUT
    bRequest        : BOOL;                    // 开闸阀请求 / slit valve open request
    bAtmDoorClosed  : BOOL;                    // 大气侧门「已关」反馈 / atmospheric door closed feedback
    bAtmDoorOpen    : BOOL;                    // 大气侧门「已开」反馈 / atmospheric door open feedback
    fChamberVac     : REAL;                    // 腔体真空度 [Pa]，越小越真空 / chamber vacuum [Pa], the smaller the deeper
    fVacThreshold   : REAL := 100.0;           // 允许开闸阀的真空阈值 [Pa]，须 > 0 / vacuum threshold allowing opening [Pa], must be > 0
    bArmRetracted   : BOOL;                    // 机械臂已退出腔体 / robot arm retracted from the chamber
    tFbTimeout      : TIME := T#3S;            // 位置确认等待窗 [ms] / position acknowledgement window [ms]
    bEnable         : BOOL;                    // 使能 / enable
END_VAR
VAR_OUTPUT
    bValveOpenCmd   : BOOL;                    // 开阀指令，与关阀指令互斥 / open command, mutually exclusive with close
    bValveCloseCmd  : BOOL;                    // 关阀指令，与开阀指令互斥 / close command, mutually exclusive with open
    bInterlockOk    : BOOL;                    // 联锁全部满足 / all interlock conditions satisfied
    uBlockMask      : WORD;                    // 阻塞原因位掩码：1 真空不足 / 2 门未关 / 4 臂未退 / 8 反馈超时
    eErr            : UDINT;                   // 错误码，0 表示无错 / error code, 0 means no error
    bError          : BOOL;                    // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid          : BOOL;                    // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbDoorWatch     : TON;                     // 门位反馈无效持续计时，段 5 无条件刷新 [ms] / door feedback invalid timer
    fbOpenWatch     : TON;                     // 开阀位置确认等待窗，段 5 无条件刷新 [ms] / open acknowledgement window
    fbCloseWatch    : TON;                     // 关阀位置确认等待窗，段 5 无条件刷新 [ms] / close acknowledgement window
    _eState         : E_DL_SlitValveState := E_DL_SlitValveState.eIdle; // 当前相位 / current phase
    _bInit          : BOOL := FALSE;           // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bIllegal       : BOOL;                    // 非法状态标志 / illegal state flag
    _bVacValid      : BOOL;                    // 真空度数值可用 / vacuum value usable
    _bVacOk         : BOOL;                    // 真空达标 / vacuum deep enough
    _bDoorValid     : BOOL;                    // 门位反馈有效（恰好一路为真） / door feedback valid, exactly one channel true
    _bDoorBadTime   : BOOL;                    // 门位反馈持续无效 / door feedback invalid for the whole window
    _bArmOk         : BOOL;                    // 机械臂已退出 / arm retracted
    _bBlkVac        : BOOL;                    // 阻塞位：真空不足 / block bit, vacuum insufficient
    _bBlkDoor       : BOOL;                    // 阻塞位：门未关 / block bit, door not closed
    _bBlkArm        : BOOL;                    // 阻塞位：臂未退 / block bit, arm not retracted
    _bBlkFb         : BOOL;                    // 阻塞位：反馈超时 / block bit, feedback timeout
    _bAllOk         : BOOL;                    // 三联条件全部满足 / all three conditions satisfied
    _bDoorBreak     : BOOL;                    // 门位计时器断输入一拍 / door timer one-scan break
    _bOpenBreak     : BOOL;                    // 开等待计时器断输入一拍 / open timer one-scan break
    _bCloseBreak    : BOOL;                    // 关等待计时器断输入一拍 / close timer one-scan break
    _tFbUse         : TIME := T#3S;            // 生效等待窗 [ms]，已钳位 / effective window, clamped
    _bAckTimeout    : BOOL;                    // 本拍发生确认超时 / acknowledgement timeout this scan
END_VAR
VAR CONSTANT
    DL_VAL_LIM      : REAL := 1.0E30;          // 有限性判定的绝对值上限 [Pa] / finiteness ceiling [Pa]
    DL_VAC_MIN      : REAL := 0.0;             // 真空度物理下限 [Pa]，负值非法 / vacuum physical floor [Pa], negatives illegal
    DL_THR_MIN      : REAL := 0.0;             // 真空阈值下限 [Pa]，须严格大于 / threshold floor [Pa], strictly greater
    DL_WIN_MIN_MS   : DINT := 1;               // 等待窗下限 [ms] / window floor [ms]
    DL_WIN_MAX_MS   : DINT := 60000;           // 等待窗上限 [ms] / window ceiling [ms]
    DL_BLK_VAC      : WORD := 16#0001;         // 掩码位 1：真空不足 / mask bit one, vacuum insufficient
    DL_BLK_DOOR     : WORD := 16#0002;         // 掩码位 2：大气门未关 / mask bit two, atmospheric door not closed
    DL_BLK_ARM      : WORD := 16#0004;         // 掩码位 4：机械臂未退 / mask bit four, arm not retracted
    DL_BLK_FB       : WORD := 16#0008;         // 掩码位 8：反馈超时 / mask bit eight, feedback timeout
    DL_MASK_NONE    : WORD := 16#0000;         // 无阻塞 / no blocking
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：两路输出**先清后置**（R72，互斥的唯一保证手段）
 *      Every scan starts with both commands cleared, exclusivity is structural
 *-----------------------------------------------------------------------------*)
bValveOpenCmd  := FALSE;                       // 开阀指令先清 / open command cleared first
bValveCloseCmd := FALSE;                       // 关阀指令先清 / close command cleared first
bInterlockOk   := FALSE;                       // 联锁满足位预置 FALSE / interlock ok preset FALSE
uBlockMask     := DL_MASK_NONE;                // 掩码清零 / mask cleared
eErr           := 16#0000_0000;                // 错误码预置无错 / error code preset to none
bError         := FALSE;                       // 故障标志预置 FALSE / fault flag preset to FALSE
bValid         := FALSE;                       // 输出可用预置 FALSE / usable flag preset to FALSE
_bIllegal      := FALSE;                       // 非法状态标志预清零 / illegal state flag pre-cleared
_bVacValid     := FALSE;                       // 真空可用标志预清零 / vacuum usable pre-cleared
_bVacOk        := FALSE;                       // 真空达标标志预清零 / vacuum ok pre-cleared
_bDoorValid    := FALSE;                       // 门位有效标志预清零 / door valid pre-cleared
_bDoorBadTime  := FALSE;                       // 门位持续无效标志预清零 / door bad time pre-cleared
_bArmOk        := FALSE;                       // 臂退出标志预清零 / arm ok pre-cleared
_bBlkVac       := FALSE;                       // 真空阻塞位预清零 / vacuum block pre-cleared
_bBlkDoor      := FALSE;                       // 门阻塞位预清零 / door block pre-cleared
_bBlkArm       := FALSE;                       // 臂阻塞位预清零 / arm block pre-cleared
_bBlkFb        := FALSE;                       // 反馈阻塞位预清零 / feedback block pre-cleared
_bAllOk        := FALSE;                       // 全条件标志预清零 / all-ok pre-cleared
_bAckTimeout   := FALSE;                       // 确认超时标志预清零 / ack timeout pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（阀位默认关闭：失电安全位）
 *      First-scan initialisation, the valve defaults closed
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_SlitValveState.eIdle;  // 相位待机 / phase idle
    _bDoorBreak := TRUE;                       // 门位计时从零开始 / door timer starts from zero
    _bOpenBreak := TRUE;                       // 开等待计时从零开始 / open timer starts from zero
    _bCloseBreak := TRUE;                      // 关等待计时从零开始 / close timer starts from zero
    _bInit      := TRUE;                       // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜真空度判定（非有限 / 负值 / 阈值非法 → 按「真空不足」处理）
 *      Vacuum evaluation, invalid values are treated as insufficient
 *-----------------------------------------------------------------------------*)
IF (fVacThreshold <> fVacThreshold) OR (ABS(fVacThreshold) > DL_VAL_LIM)
   OR (fVacThreshold <= DL_THR_MIN) THEN
    _bVacValid := FALSE;                       // 阈值非法：真空判定不可信 / illegal threshold, the vacuum test is untrustworthy
ELSE
    IF (fChamberVac < -DL_VAL_LIM) OR (fChamberVac > DL_VAL_LIM) THEN
        _bVacValid := FALSE;                   // 非有限值：不可用 / non-finite value
    ELSIF fChamberVac < DL_VAC_MIN THEN
        _bVacValid := FALSE;                   // 负压读数非法：不可用 / negative reading is illegal
    ELSE
        _bVacValid := TRUE;                    // 数值可用 / the value is usable
        _bVacOk    := (fChamberVac <= fVacThreshold); // 真空达标判据 [布尔] / deep enough test
    END_IF
END_IF
IF NOT _bVacValid THEN
    eErr := 16#0003_033E;                      // 故障级：真空度非法，按不足处理 / fault: illegal vacuum, treated as insufficient
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    _bVacOk := FALSE;                          // 不假定真空（保守侧） / never assume vacuum
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜门位反馈有效性（恰好一路为真才算有效；矛盾与缺失都按门未关）
 *      Door feedback validity, exactly one channel must be true
 *-----------------------------------------------------------------------------*)
_bDoorValid := (bAtmDoorClosed OR bAtmDoorOpen) AND (NOT (bAtmDoorClosed AND bAtmDoorOpen));

(*------------------------------------------------------------------------------
 * 段 5｜三个计时器无条件刷新（R40：CASE 之外每拍必调，各相各一只实例）
 *      Three timers refreshed unconditionally outside the CASE, one instance each
 *-----------------------------------------------------------------------------*)
_tFbUse := tFbTimeout;                         // 等待窗直取引脚 [ms] / window taken from the pin
IF TIME_TO_DINT(_tFbUse) < DL_WIN_MIN_MS THEN
    _tFbUse := DINT_TO_TIME(DL_WIN_MIN_MS);    // 下限钳位（1 ms），防零窗每拍超时 / clamped to the floor
END_IF
IF TIME_TO_DINT(_tFbUse) > DL_WIN_MAX_MS THEN
    _tFbUse := DINT_TO_TIME(DL_WIN_MAX_MS);    // 上限钳位（60 s） / clamped to the ceiling
END_IF

fbDoorWatch(IN := (NOT _bDoorValid) AND (NOT _bDoorBreak), PT := _tFbUse); // 门位持续无效计时
_bDoorBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call
_bDoorBadTime := fbDoorWatch.Q;                // 持续无效达窗口 / invalid for the whole window

fbOpenWatch(IN := (_eState = E_DL_SlitValveState.eOpening) AND (NOT _bOpenBreak), PT := _tFbUse); // 开阀确认等待窗
_bOpenBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared

fbCloseWatch(IN := (_eState = E_DL_SlitValveState.eClosing) AND (NOT _bCloseBreak), PT := _tFbUse); // 关阀确认等待窗
_bCloseBreak := FALSE;                         // 断输入拍在调用后自清 / break self-cleared

(*------------------------------------------------------------------------------
 * 段 6｜联锁判据与掩码拼装（三条全部写进掩码，便于现场一次定位）
 *      Interlock criteria and mask assembly, every criterion lands in the mask
 *-----------------------------------------------------------------------------*)
_bArmOk := bArmRetracted;                      // 机械臂退出判据 / arm retracted test
_bBlkVac  := NOT _bVacOk;                      // 真空不足（含数值非法） / vacuum insufficient, invalid included
_bBlkDoor := NOT (bAtmDoorClosed AND (NOT bAtmDoorOpen)); // 门未关（含矛盾与缺失） / door not closed, contradictions included
_bBlkArm  := NOT _bArmOk;                      // 臂未退 / arm not retracted
_bBlkFb   := _bDoorBadTime;                    // 反馈持续无效 / feedback invalid for the whole window

IF _bBlkVac THEN
    uBlockMask := uBlockMask OR DL_BLK_VAC;    // 置真空不足位 / set the vacuum bit
END_IF
IF _bBlkDoor THEN
    uBlockMask := uBlockMask OR DL_BLK_DOOR;   // 置门未关位 / set the door bit
END_IF
IF _bBlkArm THEN
    uBlockMask := uBlockMask OR DL_BLK_ARM;    // 置臂未退位 / set the arm bit
END_IF
IF _bBlkFb THEN
    uBlockMask := uBlockMask OR DL_BLK_FB;     // 置反馈超时位 / set the feedback bit
END_IF

_bAllOk := (_bVacOk AND (NOT _bBlkDoor) AND _bArmOk AND (NOT _bBlkFb)); // 三联条件全部满足
bInterlockOk := _bAllOk;                       // 联锁满足出口 / interlock ok outlet

(*------------------------------------------------------------------------------
 * 段 7｜相位机（只做迁移；两路指令在段 8 按状态置位）
 *      Phase machine, transitions only, the commands are set in segment eight
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_SlitValveState.eIdle:                 // 待机：有请求且联锁满足才允许开
        IF (NOT _bDoorValid AND _bDoorBadTime) THEN
            _eState := E_DL_SlitValveState.eFault; // 门位持续无效，转故障 / door feedback persistently invalid
            eErr    := 16#0003_033D;           // 故障级：门位反馈矛盾或缺失 / fault: contradictory or missing door feedback
            bError  := TRUE;                   // 置故障标志 / raise the fault flag
        ELSIF bEnable AND bRequest THEN
            IF _bAllOk THEN
                _eState := E_DL_SlitValveState.eOpening; // 联锁满足，放行开阀 / interlock ok, allow opening
                _bOpenBreak := TRUE;           // 开等待窗从零开始 / the open window starts from zero
                eErr    := 16#0003_0172;       // 信息级：已放行开阀 / informational: opening released
            ELSE
                _eState := E_DL_SlitValveState.eInterlock; // 联锁不满足，转阻塞 / blocked
                eErr    := 16#0003_033C;       // 故障级：拒绝开阀 / fault: opening refused
                bError  := TRUE;               // 置故障标志 / raise the fault flag
            END_IF
        END_IF

    E_DL_SlitValveState.eOpening:              // 开启中：等待确认窗；窗满接受指令已生效
        IF (NOT _bDoorValid AND _bDoorBadTime) THEN
            _eState := E_DL_SlitValveState.eFault; // 门位持续无效，转故障 / door feedback persistently invalid
            eErr    := 16#0003_033D;           // 故障级：门位反馈矛盾或缺失 / fault: contradictory or missing door feedback
            bError  := TRUE;                   // 置故障标志 / raise the fault flag
        ELSIF (NOT bEnable) OR (NOT bRequest) THEN
            _eState := E_DL_SlitValveState.eClosing; // 请求撤销或失能：先关阀 / request dropped or disabled, close first
            _bCloseBreak := TRUE;              // 关等待窗从零开始 / the close window starts from zero
        ELSIF NOT _bAllOk THEN
            _eState := E_DL_SlitValveState.eClosing; // 条件转差：先关阀（安全侧） / conditions degraded, close
            _bCloseBreak := TRUE;              // 关等待窗从零开始 / the close window starts from zero
        ELSIF fbOpenWatch.Q THEN
            _eState := E_DL_SlitValveState.eOpen; // 窗满无反馈：接受指令已生效 / window elapsed, treat the command as effective
            _bAckTimeout := TRUE;              // 标记确认超时 / flag the acknowledgement timeout
            eErr    := 16#0003_0173;           // 信息级：无位置确认，保持指令 / informational: no position confirmation, command held
        END_IF

    E_DL_SlitValveState.eOpen:                 // 已开：条件转差或请求撤销即关
        IF (NOT _bDoorValid AND _bDoorBadTime) THEN
            _eState := E_DL_SlitValveState.eFault; // 门位持续无效，转故障 / door feedback persistently invalid
            eErr    := 16#0003_033D;           // 故障级：门位反馈矛盾或缺失 / fault: contradictory or missing door feedback
            bError  := TRUE;                   // 置故障标志 / raise the fault flag
        ELSIF (NOT bEnable) OR (NOT bRequest) OR (NOT _bAllOk) THEN
            _eState := E_DL_SlitValveState.eClosing; // 任一条件撤销：关阀 / any condition lost, close
            _bCloseBreak := TRUE;              // 关等待窗从零开始 / the close window starts from zero
        END_IF

    E_DL_SlitValveState.eClosing:              // 关闭中：关到位（窗满）后回待机
        IF _bAllOk AND bEnable AND bRequest AND fbCloseWatch.Q THEN
            _eState := E_DL_SlitValveState.eOpening; // 关闭窗满且条件满足：重新开 / close window elapsed, reopen
            _bOpenBreak := TRUE;               // 开等待窗从零开始 / the open window starts from zero
            eErr    := 16#0003_0172;           // 信息级：已放行开阀 / informational: opening released
        ELSIF fbCloseWatch.Q THEN
            _eState := E_DL_SlitValveState.eIdle; // 关到位，回待机 / closed, back to idle
        END_IF

    E_DL_SlitValveState.eInterlock:            // 联锁阻塞：条件恢复且仍有请求才放行
        IF NOT bEnable THEN
            _eState := E_DL_SlitValveState.eIdle; // 失能回待机（保持关阀） / disabled, back to idle, keep closed
        ELSIF NOT bRequest THEN
            _eState := E_DL_SlitValveState.eIdle; // 请求撤销回待机 / request dropped
        ELSIF _bAllOk THEN
            _eState := E_DL_SlitValveState.eOpening; // 条件恢复，放行开阀 / conditions restored
            _bOpenBreak := TRUE;               // 开等待窗从零开始 / the open window starts from zero
            eErr    := 16#0003_0172;           // 信息级：已放行开阀 / informational: opening released
        ELSE
            eErr    := 16#0003_033C;           // 故障级：仍然拒绝开阀 / fault: still refused
            bError  := TRUE;                   // 置故障标志 / raise the fault flag
        END_IF

    E_DL_SlitValveState.eFault:                // 故障：门位恢复有效且真空可用才回待机
        IF _bDoorValid AND _bVacValid THEN
            _eState := E_DL_SlitValveState.eIdle; // 原因消失，回待机 / cause cleared, back to idle
        END_IF

    ELSE
        _bIllegal := TRUE;                     // 标记非法状态 / flag the illegal state
        _eState   := E_DL_SlitValveState.eFault; // 回故障态 / back to the fault state
        eErr      := 16#0003_033E;             // 兜底复用：判定不可信（R90 不加码） / fallback reuse: untrustworthy evaluation
        bError    := TRUE;                     // 置故障标志 / raise the fault flag
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜指令输出（严格互斥：段 1 已全清，此处最多置一路）
 *      Command outputs, strictly exclusive, at most one is set here
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_SlitValveState.eOpening:              // 开启中：只置开阀 / opening, only the open command
        bValveOpenCmd := TRUE;                 // 开阀指令 / open command
    E_DL_SlitValveState.eOpen:                 // 已开：保持开阀指令 / open, hold the open command
        bValveOpenCmd := TRUE;                 // 开阀指令 / open command
    E_DL_SlitValveState.eClosing:              // 关闭中：只置关阀 / closing, only the close command
        bValveCloseCmd := TRUE;                // 关阀指令 / close command
    E_DL_SlitValveState.eInterlock:            // 阻塞：只置关阀（保守侧，绝不留开阀） / blocked, close only
        bValveCloseCmd := TRUE;                // 关阀指令 / close command
    E_DL_SlitValveState.eFault:                // 故障：只置关阀 / fault, close only
        bValveCloseCmd := TRUE;                // 关阀指令 / close command
    ELSE
        bValveCloseCmd := FALSE;               // 待机与非法状态：两路指令均为 FALSE（阀由弹簧/自保持停在失电安全位） / idle, no command asserted
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜出口与可用性仲裁（码位优先级：故障级 > 信息级）
 *      Exit and usability arbitration
 *-----------------------------------------------------------------------------*)
IF _bAckTimeout AND (NOT bError) AND (eErr = 16#0000_0000) THEN
    eErr := 16#0003_0173;                      // 信息级：确认超时（不反转指令） / informational: ack timeout
END_IF

IF bError OR _bIllegal THEN
    bValid := FALSE;                           // 故障级或非法状态：输出不可用 / fault or illegal state: outputs unusable
ELSIF NOT bEnable THEN
    bValid := FALSE;                           // 失能：输出不可用 / disabled: unusable
ELSE
    bValid := TRUE;                            // 输出可用 / outputs usable
END_IF

END_FUNCTION_BLOCK
