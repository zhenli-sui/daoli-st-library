(*==============================================================================
 * 组件名称 (Component)  : I_DL_VfdDrive
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 通用变频器抽象契约（端子型/通信型均可适配）。
 *                         定义状态读取属性组（GET）与运行/停止/点动/频率
 *                         设定/多段速选择/复位方法组，供风机泵类与输送线
 *                         驱动层做依赖注入与解耦调用；端子输出、模拟量
 *                         给定与反馈采集由实现块（如 FB_DL_VfdGeneric）
 *                         完成，接口层不做任何过程映像读写。
 * 开源溯源 (Origin)     : 来源标签 lbp-basic-process / lbp-device
 *                         （RAW_NOTES_R6 S-1 + S-4：变频器控制标准信号集
 *                         ——运行/正反转/点动/多段速/频率到达/故障复位
 *                         端子语义，公开技术资料，仅借鉴通用信号域语义；
 *                         接口命名、方法签名按本库红线独立设计，clean-room
 *                         未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R5 全成员中英双语同行注释 ✓
 *                         R18 接口以 END_INTERFACE 成对终结 ✓
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_VfdState 枚举定义，该枚举
 *                         归属接口 I_DL_VfdDrive，与其同文件发布。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_VfdState（归属接口 I_DL_VfdDrive，与其同文件）
 * 含义: 变频器状态机离散状态。数值步长 10 留空位，便于后续插态
 *       而不破坏已有工程的持久化数值；eFault 取 99 保证排序末位。
 *----------------------------------------------------------------------------*)
TYPE E_DL_VfdState :
(
    eDisabled    := 0,    // 未使能态：驱动未上电/未使能，全部输出切断 / Disabled, drive not enabled, all outputs cut off
    eReady       := 10,   // 就绪态：使能完成，等待运行/点动指令 / Ready, enabled and awaiting run or jog commands
    eRunningFwd  := 20,   // 正转运行态：正转端子输出有效 / Running forward, forward terminal active
    eRunningRev  := 30,   // 反转运行态：反转端子输出有效 / Running reverse, reverse terminal active
    eJogging     := 40,   // 点动态：点动端子输出有效，优先级高于运行 / Jogging, jog terminal active with priority over run
    eFault       := 99    // 故障锁存态：驱动故障/反馈超时/非法状态，复位脉冲可尝试恢复 / Latched fault state (drive fault, feedback timeout), reset pulse may recover
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_VfdDrive
 * 契约结构: 属性（PROPERTY GET）+ 方法（METHOD）两段式；方法总数 6 个，
 *           达接口方法 ≤6 拆分红线的临界值。所有方法均为非阻塞单发
 *           语义，不含跨扫描周期状态驻留；返回值仅表示"指令是否被
 *           受理/参数是否合法"，实际运行状态以属性 eState/bRunning
 *           为准。
 * 边界防错: 故障态下运行/点动/设定类方法一律拒绝并返回 FALSE；复位
 *           方法返回是否受理；实现块负责端子输出与反馈采集的全部
 *           过程映像交互，本接口不涉及。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_VfdDrive

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY eState       : E_DL_VfdState // 当前状态机状态（Current state）
PROPERTY fFreqSetpoint : REAL         // 频率设定（Frequency setpoint）[Hz]，钳位后生效值 / Effective frequency setpoint [Hz] after clamping
PROPERTY fFreqActual  : REAL          // 频率反馈（Frequency feedback）[Hz]，非有限值时保持末次有效值 / Frequency feedback [Hz], holds last valid on non-finite input
PROPERTY bRunning     : BOOL          // 运行反馈（Running feedback），正转/反转/点动态输出运行中 / TRUE while running forward/reverse or jogging
PROPERTY bFault       : BOOL          // 故障锁存中（Fault latched），TRUE=存在未复位故障 / TRUE = latched fault present
PROPERTY uErrorId     : UDINT         // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理/合法性结果）--------------------------------

METHOD CmdRun : BOOL // 正/反转运行指令（Run command，bFwd=TRUE 正转 / FALSE 反转），电平语义受理为保持锁存；故障态拒绝返回 FALSE / Run command, held latch accepted, rejected in fault
VAR_INPUT
    bFwd : BOOL; // 方向选择（Direction select），TRUE=正转 / FALSE=反转 / TRUE = forward, FALSE = reverse
END_VAR

    END_METHOD

METHOD CmdStop : BOOL // 停止指令（Stop command）：撤销运行/点动锁存；无条件受理 / Stop command, revokes run and jog latches, unconditionally accepted
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdJog : BOOL // 点动指令（Jog command，bFwd=TRUE 正向点动），优先级高于运行；故障态拒绝返回 FALSE / Jog command with priority over run, rejected in fault
VAR_INPUT
    bFwd : BOOL; // 点动方向（Jog direction），TRUE=正向 / FALSE=撤销点动保持 / TRUE = jog forward, FALSE = release jog hold
END_VAR

    END_METHOD

METHOD SetFrequency : BOOL // 频率设定（Frequency set）[Hz]，越界/非有限值拒绝并返回 FALSE / Frequency set command, out-of-range or non-finite returns FALSE
VAR_INPUT
    fHz : REAL; // 频率设定值（Frequency value）[Hz]，域 0..fFreqMax / Frequency value [Hz], range 0..fFreqMax
END_VAR

    END_METHOD

METHOD SelectPresetSpeed : BOOL // 多段速选择（Preset speed select），0=模拟量给定、1..7=段速；越界拒绝返回 FALSE / Preset speed select, 0 = analog reference, 1..7 = preset steps, out-of-range returns FALSE
VAR_INPUT
    nIdx : USINT; // 段速索引（Preset index），0=模拟量给定 / 1..7=段速 / Preset index, 0 = analog reference, 1..7 = preset steps
END_VAR

    END_METHOD

METHOD CmdReset : BOOL // 复位指令（Reset command），返回是否受理（存在故障时为 TRUE）/ Returns TRUE only when accepted
VAR_INPUT
END_VAR

    END_METHOD
END_INTERFACE
