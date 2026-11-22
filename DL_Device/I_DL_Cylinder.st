(*==============================================================================
 * 组件名称 (Component)  : I_DL_Cylinder
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 双电控气缸标准抽象契约。定义状态读取属性组（GET）与
 *                         动作指令方法组（Extend/Retract/Stop/Reset），供
 *                         DL_Process 全部机站动作层做依赖注入与解耦调用；
 *                         具体电磁阀输出与传感器采集由实现块（如
 *                         FB_DL_PneumaticCylinder）完成，接口层不做任何
 *                         过程映像读写，仅承载纯软件契约。
 * 开源溯源 (Origin)     : 来源标签 lbp-device（RAW_NOTES_R5 S-4：工业气动气缸
 *                         FB 设计指南 / LOGO! 气缸应用帖 / 双线圈互锁惯例，
 *                         公开教学文章，仅借鉴状态集合与故障分类等通用工程
 *                         语义；接口命名、方法签名按本库红线独立设计，
 *                         clean-room 未复制任何源码行）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R5 全成员中英双语同行注释 ✓
 *                         R18 接口以 END_INTERFACE 成对终结 ✓
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_CylinderState 枚举定义，
 *                         该枚举归属接口 I_DL_Cylinder，与其同文件发布。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R5 轮 · DL_Device 开库）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CylinderState（归属接口 I_DL_Cylinder，与其同文件）
 * 含义: 双电控气缸状态机离散状态。数值步长 10 留空位，便于后续插态
 *       而不破坏已有工程的持久化数值；eFault 取 99 保证排序末位。
 *----------------------------------------------------------------------------*)
TYPE E_DL_CylinderState :
(
    eIdle       := 0,    // 空闲稳态：双线圈全断，气缸保持当前位置 / Idle steady state, both coils off, cylinder holds position
    eExtending  := 10,   // 伸出动作中：伸出线圈得电，等待伸出到位反馈 / Extending, extend coil energized, waiting for extended feedback
    eExtended   := 20,   // 已伸出到位：伸出到位磁开确认的稳定终态 / Fully extended, confirmed by extended reed switch
    eRetracting := 30,   // 缩回动作中：缩回线圈得电，等待缩回到位反馈 / Retracting, retract coil energized, waiting for retracted feedback
    eRetracted  := 40,   // 已缩回到位：缩回到位磁开确认的稳定终态 / Fully retracted, confirmed by retracted reed switch
    eFault      := 99    // 故障锁存态：超时/传感器冲突/非法状态，仅复位可清 / Latched fault state, cleared only by reset
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_Cylinder
 * 契约结构: 属性（PROPERTY GET）+ 方法（METHOD）两段式；方法总数 4 个，
 *           满足接口方法 ≤6 的拆分红线。所有方法均为非阻塞单发语义，
 *           不含跨扫描周期状态驻留；返回值仅表示"指令是否被受理"，
 *           实际动作完成以属性 eState/bExtended/bRetracted 为准。
 * 边界防错: 任何动作方法在故障锁存态一律拒绝并返回 FALSE；实现块负责
 *           信号采集与线圈驱动的全部过程映像交互，本接口不涉及。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_Cylinder

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY eState     : E_DL_CylinderState // 当前状态机状态（Current state）
PROPERTY bExtended  : BOOL               // 伸出到位磁开反馈（Extended reed feedback），TRUE=伸出到位
PROPERTY bRetracted : BOOL               // 缩回到位磁开反馈（Retracted reed feedback），TRUE=缩回到位
PROPERTY bFault     : BOOL               // 故障锁存中（Fault latched），TRUE=存在未复位故障
PROPERTY uErrorId   : UDINT              // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx

// ---- 方法段（单发指令，返回受理结果）--------------------------------------

METHOD CmdExtend : BOOL // 伸出指令（Extend command），单发；故障态拒绝返回 FALSE
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdRetract : BOOL // 缩回指令（Retract command），单发；故障态拒绝返回 FALSE
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdStop : BOOL // 停止指令（Stop command）：双线圈全断、保持当前位置；故障态拒绝返回 FALSE
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdReset : BOOL // 复位指令（Reset command），返回是否可复位（存在故障时为 TRUE）
VAR_INPUT
END_VAR

    END_METHOD
END_INTERFACE
