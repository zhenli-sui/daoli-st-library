(*==============================================================================
 * 组件名称 (Component)  : I_DL_MotorDriver
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 直接启动（DOL）电机驱动器标准抽象契约。定义状态
 *                         读取属性组（GET，含重启抑制指示）与启停/复位方法组，
 *                         供机站动作层与配电监控层做依赖注入与解耦调用；
 *                         接触器线圈驱动与反馈采集由实现块（如 FB_DL_DolMotor）
 *                         完成，接口层不做任何过程映像读写。
 * 开源溯源 (Origin)     : 来源标签 lbp-device（RAW_NOTES_R5 S-4：DOL 电机保护
 *                         惯例——接触器反馈校验窗、热继电器过载锁存、防频繁
 *                         启停与重启抑制冷却时间为行业公知语义，公开教学
 *                         资料，仅借鉴通用工程语义；接口命名、方法签名按
 *                         本库红线独立设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R5 全成员中英双语同行注释 ✓
 *                         R18 接口以 END_INTERFACE 成对终结 ✓
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_MotorState 枚举定义，
 *                         该枚举归属接口 I_DL_MotorDriver，与其同文件发布。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R5 轮 · DL_Device 开库）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MotorState（归属接口 I_DL_MotorDriver，与其同文件）
 * 含义: DOL 电机驱动状态机离散状态。数值步长 10 留空位，便于后续插态
 *       而不破坏已有工程的持久化数值；eFault 取 99 保证排序末位。
 *----------------------------------------------------------------------------*)
TYPE E_DL_MotorState :
(
    eIdle          := 0,    // 空闲停机态：接触器断开，可受理启动指令 / Idle stopped state, contactor open, start commands accepted
    eStarting      := 10,   // 启动校验态：线圈已得电，等待反馈窗内触点吸合确认 / Starting, coil energized, awaiting contactor pick-up confirmation within feedback window
    eRunning       := 20,   // 运行态：反馈吸合确认，正常带载运行 / Running, contactor feedback confirmed, loaded operation
    eStopping      := 30,   // 停机过渡态：线圈已断，等待反馈触点分断确认 / Stopping transition, coil de-energized, awaiting contactor drop-out confirmation
    eTripOverload  := 40,   // 过载脱扣态：热继电器动作锁存，仅复位且过载信号消失后可清 / Overload tripped and latched, cleared only by reset with overload signal removed
    eFault         := 99    // 故障锁存态：拒动/失反馈等故障，仅复位可清 / Latched fault state (refusal, feedback loss), cleared only by reset
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_MotorDriver
 * 契约结构: 属性（PROPERTY GET）+ 方法（METHOD）两段式；方法总数 3 个，
 *           满足接口方法 ≤6 的拆分红线。所有方法均为非阻塞单发语义，
 *           不含跨扫描周期状态驻留；启动/复位方法返回值表示"指令是否
 *           被受理"，实际运行状态以属性 eState/bRunning 为准。
 * 边界防错: 启动方法在被抑制（重启抑制/次数超限）或故障态一律返回 FALSE；
 *           停止为无条件安全指令；实现块负责线圈驱动与触点反馈采集的
 *           全部过程映像交互，本接口不涉及。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_MotorDriver

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY eState          : E_DL_MotorState // 当前状态机状态（Current state）
PROPERTY bRunning        : BOOL            // 运行反馈（Running feedback），TRUE=反馈吸合确认运行中 / TRUE = running confirmed by contactor feedback
PROPERTY bFault          : BOOL            // 故障锁存中（Fault latched），TRUE=存在未复位故障（含过载脱扣）/ TRUE = latched fault incl. overload trip
PROPERTY uErrorId        : UDINT           // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx
PROPERTY bRestartInhibit : BOOL            // 重启抑制激活中（Restart inhibit active），TRUE=冷却期内拒绝启动 / TRUE = start refused during cooling period

// ---- 方法段（单发指令，返回受理结果）--------------------------------------

METHOD CmdStart : BOOL // 启动指令（Start command），单发；被抑制/故障态返回 FALSE / Rejected with FALSE when inhibited or faulty
VAR_INPUT
END_VAR

METHOD CmdStop // 停止指令（Stop command），无条件安全动作，双线圈全断 / Unconditional safe stop command
VAR_INPUT
END_VAR

METHOD CmdReset : BOOL // 复位过载/故障（Reset overload and fault），返回是否可复位 / Returns TRUE only when resettable
VAR_INPUT
END_VAR

END_INTERFACE
