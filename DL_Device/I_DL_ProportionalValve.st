(*==============================================================================
 * 组件名称 (Component)  : I_DL_ProportionalValve
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 模拟量比例阀/调节阀（开度指令-反馈型）标准抽象
 *                         契约。定义状态读取属性组（GET）与阀位设定/停止/
 *                         复位方法组，供温度、流量、压力等过程调节回路
 *                         做依赖注入与解耦调用；指令整形、限幅域映射与
 *                         反馈诊断由实现块（如 FB_DL_AnalogValve）完成，
 *                         接口层不做任何过程映像读写，仅承载纯软件契约。
 * 开源溯源 (Origin)     : 来源标签 lbp-basic-process / lbp-device
 *                         （RAW_NOTES_R6 S-1：比例调节阀开度指令-反馈控制
 *                         惯例、偏差报警语义等行业公知工程惯例，公开教学
 *                         资料，仅借鉴通用工程语义；接口命名、方法签名按
 *                         本库红线独立设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R5 全成员中英双语同行注释 ✓
 *                         R18 接口以 END_INTERFACE 成对终结 ✓
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_ValveState 枚举定义，该枚举
 *                         归属接口 I_DL_ProportionalValve，与其同文件发布。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ValveState（归属接口 I_DL_ProportionalValve，与其同文件）
 * 含义: 比例调节阀状态机离散状态。数值步长 10 留空位，便于后续插态
 *       而不破坏已有工程的持久化数值；eFault 取 99 保证排序末位。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ValveState :
(
    eIdle        := 0,    // 空闲稳态：调节使能撤除或输出冻结，保持当前阀位 / Idle steady state, modulating disabled or output frozen, holds position
    eModulating  := 10,   // 调节中：调节使能有效，阀位指令整形后正常输出 / Modulating, enable active, position command shaping and output active
    eFault       := 99    // 故障锁存态：反馈失效/非法状态，仅复位可清 / Latched fault state (feedback loss), cleared only by reset
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_ProportionalValve
 * 契约结构: 属性（PROPERTY GET）+ 方法（METHOD）两段式；方法总数 3 个，
 *           满足接口方法 ≤6 的拆分红线。所有方法均为非阻塞单发语义，
 *           不含跨扫描周期状态驻留；返回值仅表示"指令是否被受理/
 *           参数是否合法"，实际阀位以属性 fPosCmd/fPosFeedback 为准。
 * 边界防错: 设定方法在故障态拒绝并返回 FALSE；停止方法冻结输出保持
 *           当前阀位；实现块负责指令整形与反馈诊断的全部过程映像
 *           交互，本接口不涉及。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_ProportionalValve

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY eState          : E_DL_ValveState // 当前状态机状态（Current state）
PROPERTY fPosCmd         : REAL            // 当前阀位指令（Current position command）[%]，整形钳位后生效值 / Effective position command [%] after shaping
PROPERTY fPosFeedback    : REAL            // 阀位反馈（Position feedback）[%]，非有限值时保持末次有效值 / Position feedback [%], holds last valid on non-finite input
PROPERTY bDeviationAlarm : BOOL            // 偏差报警激活中（Deviation alarm），瞬时型每拍重算 / Transient deviation alarm, recomputed each cycle
PROPERTY bFault          : BOOL            // 故障锁存中（Fault latched），TRUE=存在未复位故障 / TRUE = latched fault present
PROPERTY uErrorId        : UDINT           // 末次事件码（Last error code），0=无，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理/合法性结果）--------------------------------

METHOD SetPosition : BOOL // 阀位指令设定（Position set）[%]，越界/非有限值拒绝并返回 FALSE / Position set command, out-of-range or non-finite returns FALSE
VAR_INPUT
    fPos : REAL; // 阀位设定值（Position value）[%]，域 0..100 / Position value [%], range 0..100
END_VAR

    END_METHOD

METHOD CmdStop : BOOL // 停止指令（Stop command）：冻结输出保持当前阀位，直至下次设定或使能撤除；故障态拒绝返回 FALSE / Freeze output until next set or enable drop, rejected in fault
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdReset : BOOL // 复位指令（Reset command），返回是否可复位（存在故障时为 TRUE）/ Returns TRUE only when resettable
VAR_INPUT
END_VAR

    END_METHOD
END_INTERFACE
