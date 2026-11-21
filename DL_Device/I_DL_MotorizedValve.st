(*==============================================================================
 * 组件名称 (Component)  : I_DL_MotorizedValve
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 电动调节阀（开/关脉冲输出、无阀位变送器）标准
 *                         抽象契约。定义状态读取属性组（GET）与开阀/关阀/
 *                         停止/复位方法组，供暖通水路与工艺管路的调节
 *                         回路做依赖注入与解耦调用；双脉冲输出、行程时间
 *                         积分估算与限位保护由实现块（如
 *                         FB_DL_ThreePointValve）完成，接口层不做任何
 *                         过程映像读写，仅承载纯软件契约。
 * 开源溯源 (Origin)     : 来源标签 lbp-basic-process / lbp-device
 *                         （RAW_NOTES_R6 S-1 + S-5：三点浮点式电动阀的开/
 *                         关脉冲控制惯例、行程时间开度估算语义等行业
 *                         公知工程惯例，公开教学资料，仅借鉴通用工程语义；
 *                         接口命名、方法签名按本库红线独立设计，clean-room
 *                         未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R5 全成员中英双语同行注释 ✓
 *                         R18 接口以 END_INTERFACE 成对终结 ✓
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_MotorValveState 枚举定义，
 *                         该枚举归属接口 I_DL_MotorizedValve，与其同文件
 *                         发布。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MotorValveState（归属接口 I_DL_MotorizedValve，与其同文件）
 * 含义: 电动调节阀状态机离散状态。数值步长 10 留空位，便于后续插态
 *       而不破坏已有工程的持久化数值；eFault 取 99 保证排序末位。
 *----------------------------------------------------------------------------*)
TYPE E_DL_MotorValveState :
(
    eIdle    := 0,    // 空闲稳态：双脉冲全断，阀停在当前位置 / Idle steady state, both pulses off, valve holds position
    eOpening := 10,   // 开阀中：开阀脉冲输出，行程时间积分估算开度 / Opening, open pulse active, position integrated from stroke time
    eClosing := 20,   // 关阀中：关阀脉冲输出，行程时间积分估算开度 / Closing, close pulse active, position integrated from stroke time
    eOpened  := 30,   // 全开确认：全开限位反馈确认的端点稳态 / Fully opened, endpoint confirmed by open limit switch
    eClosed  := 40,   // 全关确认：全关限位反馈确认的端点稳态 / Fully closed, endpoint confirmed by closed limit switch
    eFault   := 99    // 故障锁存态：估算失准/限位冲突/非法状态，仅复位可清 / Latched fault state, cleared only by reset
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_MotorizedValve
 * 契约结构: 属性（PROPERTY GET）+ 方法（METHOD）两段式；方法总数 4 个，
 *           满足接口方法 ≤6 的拆分红线。所有方法均为非阻塞单发语义，
 *           不含跨扫描周期状态驻留；返回值仅表示"指令是否被受理"，
 *           实际阀位以属性 eState/fPosEstimate 为准。
 * 边界防错: 故障态下动作方法一律拒绝并返回 FALSE；已在端点（限位确认）
 *           的指令受理但由实现块拒绝执行并置信息级；实现块负责双脉冲
 *           输出与限位采集的全部过程映像交互，本接口不涉及。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_MotorizedValve

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY eState       : E_DL_MotorValveState // 当前状态机状态（Current state）
PROPERTY fPosEstimate : REAL          // 估算开度（Estimated position）[%]，0~100，由行程时间积分自动估算 / Estimated position [%], integrated from stroke time
PROPERTY bLimOpen     : BOOL          // 全开限位反馈（Open limit switch），TRUE=已到全开端点 / TRUE = at fully-open endpoint
PROPERTY bLimClosed   : BOOL          // 全关限位反馈（Closed limit switch），TRUE=已到全关端点 / TRUE = at fully-closed endpoint
PROPERTY bFault       : BOOL          // 故障锁存中（Fault latched），TRUE=存在未复位故障 / TRUE = latched fault present
PROPERTY uErrorId     : UDINT         // 末次事件码（Last error code），0=无，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理结果）--------------------------------------

METHOD CmdOpen : BOOL // 开阀指令（Open command），电平语义受理为保持锁存；故障态拒绝返回 FALSE / Open command held as latch, rejected in fault
VAR_INPUT
END_VAR

METHOD CmdClose : BOOL // 关阀指令（Close command），电平语义受理为保持锁存；故障态拒绝返回 FALSE / Close command held as latch, rejected in fault
VAR_INPUT
END_VAR

METHOD CmdStop : BOOL // 双脉冲全断保持（Stop command, both pulses off, hold position）；无条件受理 / Unconditionally accepted
VAR_INPUT
END_VAR

METHOD CmdReset : BOOL // 复位指令（Reset command），返回是否可复位（存在故障时为 TRUE）/ Returns TRUE only when resettable
VAR_INPUT
END_VAR

END_INTERFACE
