(*==============================================================================
 * 组件名称 (Component)  : I_DL_VacuumGenerator
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 真空发生器（负压吸盘供气）标准抽象契约。定义状态
 *                         读取属性组（GET）与真空建立/破真空/停止/复位方法
 *                         组，供 DL_Process 拾放工站（PickAndPlaceStation /
 *                         CellFeederVacuum）做依赖注入与解耦调用；具体电磁
 *                         阀驱动、负压采集与吹气脉冲由实现块（如
 *                         FB_DL_VacuumEjector）完成，接口层不做任何过程
 *                         映像读写，仅承载纯软件契约。
 * 开源溯源 (Origin)     : 来源标签 lbp-device（RAW_NOTES_R6 S-1：真空吸拾
 *                         放的建立-保持-破真空三段操作惯例、负压域压力
 *                         反馈语义等行业公知工程惯例，公开教学资料，仅借鉴
 *                         通用工程语义；接口命名、方法签名按本库红线独立
 *                         设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R5 全成员中英双语同行注释 ✓
 *                         R18 接口以 END_INTERFACE 成对终结 ✓
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_VacuumState 枚举定义，该枚举
 *                         归属接口 I_DL_VacuumGenerator，与其同文件发布。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_VacuumState（归属接口 I_DL_VacuumGenerator，与其同文件）
 * 含义: 真空发生器状态机离散状态。数值步长 10 留空位，便于后续插态
 *       而不破坏已有工程的持久化数值；eFault 取 99 保证排序末位。
 *----------------------------------------------------------------------------*)
TYPE E_DL_VacuumState :
(
    eIdle       := 0,    // 空闲稳态：双阀全断，不吸附不吹气 / Idle steady state, both valves off, no evacuate or blow-off
    eEvacuating := 10,   // 抽真空中：真空阀开，等待负压建立确认 / Evacuating, vacuum valve open, awaiting vacuum establishment confirmation
    eVacuumOk   := 20,   // 真空建立确认：负压阈值（及可选开关）确认的吸附保持态 / Vacuum established, holding state confirmed by threshold and optional switch
    eBlowing    := 30,   // 破真空吹气中：吹气阀定宽脉冲输出，真空阀强制断 / Blowing, blow-off valve in fixed-width pulse, vacuum valve forced off
    eFault      := 99    // 故障锁存态：超时/反馈失效/非法状态，仅复位可清 / Latched fault state (timeout, feedback loss), cleared only by reset
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_VacuumGenerator
 * 契约结构: 属性（PROPERTY GET）+ 方法（METHOD）两段式；方法总数 4 个，
 *           满足接口方法 ≤6 的拆分红线。所有方法均为非阻塞单发语义，
 *           不含跨扫描周期状态驻留；返回值仅表示"指令是否被受理"，
 *           实际真空状态以属性 eState/bVacuumOk 为准。
 * 边界防错: 任何动作方法在故障锁存态一律拒绝并返回 FALSE；实现块负责
 *           阀输出与负压采集的全部过程映像交互，本接口不涉及。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_VacuumGenerator

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY eState    : E_DL_VacuumState // 当前状态机状态（Current state）
PROPERTY bVacuumOk : BOOL             // 真空建立确认（Vacuum established），TRUE=吸附保持中 / TRUE = vacuum established and holding
PROPERTY fPressure : REAL             // 负压反馈值（Pressure feedback）[kPa]，0=大气压，负值=真空度 / Pressure feedback [kPa], 0 = atmospheric, negative = vacuum
PROPERTY bFault    : BOOL             // 故障锁存中（Fault latched），TRUE=存在未复位故障 / TRUE = latched fault present
PROPERTY uErrorId  : UDINT            // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理结果）--------------------------------------

METHOD CmdEvacuate : BOOL // 建立真空指令（Evacuate command），单发；故障态拒绝返回 FALSE / Rejected with FALSE in fault state
VAR_INPUT
END_VAR

METHOD CmdBlowOff : BOOL // 破真空吹气指令（Blow-off command），单发，实现块输出定宽脉冲 / One-shot blow-off, fixed-width pulse by implementation
VAR_INPUT
END_VAR

METHOD CmdStop : BOOL // 双阀全断保持现状（Stop command, both valves off, hold state）；故障态拒绝返回 FALSE / Rejected with FALSE in fault state
VAR_INPUT
END_VAR

METHOD CmdReset : BOOL // 复位指令（Reset command），返回是否可复位（存在故障时为 TRUE）/ Returns TRUE only when resettable
VAR_INPUT
END_VAR

END_INTERFACE
