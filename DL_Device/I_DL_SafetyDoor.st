(*==============================================================================
 * 组件名称 (Component)  : I_DL_SafetyDoor
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 安全门联锁标准抽象契约（电磁锁扣门）。定义解锁时
 *                         序状态读取属性组（GET）与请求解锁/重新闭锁/复位/
 *                         审计清除方法组，供上层工站做依赖注入；电磁铁输出、
 *                         反馈采集与物理输出全部由实现块（如
 *                         FB_DL_GuardLockDoor）完成，接口层不写物理输出。
 * 定位声明 (Positioning): 公约 0.13——本接口及其实现块为标准 PLC 逻辑编排
 *                         与诊断镜像层，不构成 ISO 13849 / IEC 62061 认证
 *                         安全功能，安全回路由认证安全控制器/安全 PLC 承载。
 * 契约结构 (Structure)  : 公约 0.11 接口三段式——状态枚举（本文件承载）+
 *                         属性（PROPERTY GET）+ 方法（METHOD）；方法共 4 个
 *                         （≤6 红线内）。故障态一律拒绝方法；门开态下拒绝
 *                         CmdRelock 之外的全部动作。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / safety-interlock
 *                         （RAW_NOTES_R7 S-2/S-4：TcOpen 组件接口分层思想
 *                         与 ISO 14119 电磁锁扣门联锁公开语义——解锁时序
 *                         状态域、静止确认、审计计数，公开标准资料，仅借
 *                         鉴状态域语义；接口命名、枚举编号、方法签名 100%
 *                         本库独立设计，clean-room 未复制源码）。
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_SafetyDoorState 枚举定义，该
 *                         枚举归属接口 I_DL_SafetyDoor，与其同文件发布
 *                         （公约 0.11；禁止异文件同名异型重复定义）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 N/A（契约件无运算）
 *                         R5 全成员中英双语同行注释 ✓｜R6 N/A（接口无状态机）
 *                         R7 N/A（无实例调用）｜R18 INTERFACE/END_INTERFACE
 *                         成对终结 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 安全门族接口件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SafetyDoorState（归属接口 I_DL_SafetyDoor，与其同文件）
 * 含义: 电磁锁扣门解锁时序离散状态。编号步长 10 留空位，eFault 取 99 保证
 *       排序末位（全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SafetyDoorState :
(
    eIdle               := 0,   // 待机：门锁全确认，可受理解锁请求 / Idle, door and lock fully confirmed, unlock acceptable
    eLocked             := 10,  // 已闭锁：关门再锁定确认中或重启抑制保持 / Locked, relock confirming or restart inhibit held
    eStopRequested      := 20,  // 已请求停机：解锁时序中停机请求输出有效 / Stop requested, stop-request output active in the unlock sequence
    eStandstillConfirmed:= 30,  // 静止已确认：零速反馈或 run-down 计时达成 / Standstill confirmed by zero-speed feedback or run-down timer
    eUnlocked           := 40,  // 已解锁：解锁电磁铁输出有效，等待开门 / Unlocked, solenoid energized, awaiting door opening
    eOpened             := 50,  // 门已开启：审计计数已累加，等待关门再锁定 / Opened, audit count incremented, awaiting relock
    eFault              := 99   // 故障锁存：静止超时/防篡改冲突/再锁定超时/非法状态 / Latched fault
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_SafetyDoor
 * 边界防错: 故障态一律拒绝方法并返回 FALSE；门开态下拒绝 CmdRelock 之外的
 *           全部动作；接口层不写物理输出（电磁铁/停机请求由实现块承载）。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_SafetyDoor

// ---- 属性段（全部只读 GET，实现块一一落地）----------------------------------

PROPERTY eState          : E_DL_SafetyDoorState // 当前解锁时序状态（Current sequence state），枚举见 E_DL_SafetyDoorState
PROPERTY bClosed         : BOOL                 // 门已关闭（Door closed），门关闭反馈镜像 / Door-closed feedback mirror
PROPERTY bLocked         : BOOL                 // 锁已闭锁（Lock engaged），锁闭反馈镜像 / Lock-engaged feedback mirror
PROPERTY bUnlockPermitted: BOOL                 // 允许解锁（Unlock permitted），无故障、无重启抑制且门锁全确认 / Unlock permitted: no fault, no inhibit, door and lock confirmed
PROPERTY bOpened         : BOOL                 // 门开启（Door open），门开启诊断镜像 / Door-open diagnostic mirror
PROPERTY bFault          : BOOL                 // 故障锁存中（Fault latched），显式排除信息级码（R21）/ TRUE = latched fault, info codes excluded
PROPERTY uErrorId        : UDINT                // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理/合法性结果）----------------------------------

METHOD CmdRequestUnlock : BOOL // 请求解锁（Request unlock）：发起停机请求并进入解锁时序；故障态/门开态拒绝 / Starts the unlock sequence, rejected in fault or door-open
VAR_INPUT
END_VAR

METHOD CmdRelock : BOOL // 重新闭锁指令（Relock command）：门开态下关门确认后受理 / Relock, accepted when the door is closed again
VAR_INPUT
END_VAR

METHOD CmdReset : BOOL // 复位故障（Reset fault），仅故障态受理返回 TRUE / Reset accepted only in fault state
VAR_INPUT
END_VAR

METHOD CmdAuditClear : BOOL // 清除开门审计记录（Clear the open audit count），供批次收尾调用；故障态拒绝 / Clears the open audit count, rejected in fault
VAR_INPUT
END_VAR

END_INTERFACE
