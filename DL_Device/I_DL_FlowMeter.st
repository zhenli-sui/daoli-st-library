(*==============================================================================
 * 组件名称 (Component)  : I_DL_FlowMeter
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 流量计标准抽象契约（脉冲型/模拟型均可适配）。定义
 *                         瞬时流量/累计总量读取属性组（GET）与总量清零/预置/
 *                         复位方法组，供批控与计量工站做依赖注入；脉冲采集
 *                         与频率估计由实现块（如 FB_DL_PulseFlowMeter）完成，
 *                         接口层不读物理输入。
 * 契约结构 (Structure)  : 公约 0.11 接口三段式——状态枚举（本文件承载）+
 *                         属性（PROPERTY GET）+ 方法（METHOD）；方法共 3 个
 *                         （≤6 红线内）。故障态一律拒绝方法。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / flow-totalizer
 *                         （RAW_NOTES_R7 S-2/S-6：TcOpen 组件接口分层思想与
 *                         工业流量计量公开语义域——瞬时流量/累计总量/低流
 *                         量截止，公开资料，仅借鉴语义域；接口命名、枚举编
 *                         号、方法签名 100% 本库独立设计，clean-room 未复
 *                         制源码）。
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_FlowMeterState 枚举定义，该枚
 *                         举归属接口 I_DL_FlowMeter，与其同文件发布（公约
 *                         0.11；禁止异文件同名异型重复定义）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 N/A（契约件无运算）
 *                         R5 全成员中英双语同行注释 ✓｜R6 N/A（接口无状态机）
 *                         R7 N/A（无实例调用）｜R18 INTERFACE/END_INTERFACE
 *                         成对终结 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 流量计族接口件）
 *   2026-11-15  v1.0.1  R11 修复：枚举成员分隔符笔误，eFlowOk / eLowCutoff 两行误写单冒号 `:`（枚举成员赋值须用 `:=`），三平台编译阻断已消除，数值与语义不变。
 *                       R11 fix: enum member separator erratum, `:` -> `:=` on two members.
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FlowMeterState（归属接口 I_DL_FlowMeter，与其同文件）
 * 含义: 流量计量离散状态。编号步长 10 留空位，eFault 取 99 保证排序末位
 *       （全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_FlowMeterState :
(
    eIdle      := 0,   // 空闲：未建窗或脉冲丢失超时后的静默态 / Idle, no window yet or silent after pulse timeout
    eMeasuring := 10,   // 测量中：采样窗运行中，流量待有效判定 / Measuring, sample window running, flow pending validation
    eFlowOk    := 20,  // 流量正常：高于低流量截止阈值的有效流量 / Flow OK, flow above the low-flow cutoff
    eLowCutoff := 30,  // 低流量截止：有效但低于阈值被截零（信息级）/ Low-flow cutoff, valid but zeroed below threshold (info)
    eFault     := 99   // 故障锁存：K 系数非法/非法状态，复位可尝试恢复 / Latched fault, reset may recover
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_FlowMeter
 * 边界防错: 故障态一律拒绝方法并返回 FALSE；接口层不读物理输入；累计溢出
 *           防护（LREAL 整数精度边界预警）在实现块承载。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_FlowMeter

// ---- 属性段（全部只读 GET，实现块一一落地）----------------------------------

PROPERTY eState     : E_DL_FlowMeterState // 当前计量状态（Current metering state），枚举见 E_DL_FlowMeterState
PROPERTY fFlowRate  : REAL                // 瞬时流量（Flow rate）[L/min]，按 K 系数域换算 / Instantaneous flow rate [L/min], K-factor domain
PROPERTY fTotal     : LREAL               // 累计总量（Totalized volume）[L]，LREAL 防累计精度丢失 / Totalized volume [L], LREAL against precision loss
PROPERTY nPulseCount: UDINT               // 窗口内脉冲计数原始值（Pulse count of last window）/ Raw pulse count of the last window
PROPERTY bFault     : BOOL                // 故障锁存中（Fault latched），显式排除信息级码（R21）/ TRUE = latched fault, info codes excluded
PROPERTY uErrorId   : UDINT               // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理/合法性结果）----------------------------------

METHOD CmdTotalReset : BOOL // 总量清零（Total reset），批控切换零点；故障态拒绝 / Total reset, rejected in fault
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdTotalPreset : BOOL // 总量预置（Total preset），非有限值/负值拒绝 / Total preset, non-finite or negative rejected
VAR_INPUT
    fPreset : LREAL; // 预置总量（Preset volume）[L]，域 ≥0 / Preset volume [L], range >= 0
END_VAR

    END_METHOD

METHOD CmdReset : BOOL // 复位故障（Reset fault），仅故障态受理 / Reset accepted only in fault state
VAR_INPUT
END_VAR

    END_METHOD
END_INTERFACE
