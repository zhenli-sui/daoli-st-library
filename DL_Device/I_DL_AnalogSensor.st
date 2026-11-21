(*==============================================================================
 * 组件名称 (Component)  : I_DL_AnalogSensor
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套质量枚举（DUT）
 * 功能简述 (Function)   : 模拟量变送器标准抽象契约（NAMUR NE43 语义域）。
 *                         定义工程量当前值、信号质量分级、HH/H/L/LL 四级
 *                         报警位与故障码的只读属性组，供温控区（如
 *                         FB_DL_HeatCoolZone）等上层工艺块做依赖注入；
 *                         原始信号采集、标定与诊断由实现块
 *                         （如 FB_DL_AnalogTransmitter）完成。
 * 开源溯源 (Origin)     : 来源标签 namur-ne43（RAW_NOTES_R5 S-5：NAMUR NE43
 *                         信号电平域为公开推荐实践，多来源交叉印证——
 *                         有效测量域 3.8~20.5 mA、故障域 <3.6 / >21 mA、
 *                         0 mA 回路断线、超量程标记而非剔除；仅借鉴公开
 *                         标准语义，接口命名、质量分级枚举按本库红线独立
 *                         设计，clean-room 未复制任何源码行）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R5 全成员中英双语同行注释 ✓
 *                         R18 接口以 END_INTERFACE 成对终结 ✓
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_SignalQuality 枚举定义，
 *                         该枚举归属接口 I_DL_AnalogSensor，与其同文件发布。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R5 轮 · DL_Device 开库）
 *   2026-11-15  v1.0.1  R11 修复：枚举成员分隔符笔误，eWireBreakLow / eWireBreakHigh 两行误写单冒号 `:`（IEC 61131-3 枚举成员赋值须用 `:=`），三平台编译阻断已消除，数值与语义不变。
 *                       R11 fix: enum member separator erratum, `:` -> `:=` on two members.
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SignalQuality（归属接口 I_DL_AnalogSensor，与其同文件）
 * 含义: NAMUR NE43 信号质量分级。数值步长 10 留空位，便于后续插态；
 *       断线/开路三个诊断态取 30/40/50 依严重度递增排序。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SignalQuality :
(
    eGood         := 0,    // 信号良好：原始值位于有效测量域内 / Signal good, raw value inside valid measurement span
    eUnderRange   := 10,   // 欠量程：原始值低于量程下限但在故障门限之上（如 3.8~4.0 mA 段）/ Under-range, raw below span low but above fault threshold
    eOverRange    := 20,   // 超量程：原始值高于量程上限但在故障门限之下（如 20.0~20.5 mA 段）/ Over-range, raw above span high but below fault threshold
    eWireBreakLow := 30,   // 低侧断线：原始值低于故障下门限（如 <3.6 mA，按配置方向判定）/ Wire break low side, raw below low fault threshold per configured direction
    eWireBreakHigh := 40,  // 高侧断线：原始值高于故障上门限（如 >21 mA，按配置方向判定）/ Wire break high side, raw above high fault threshold per configured direction
    eOpenLoop     := 50    // 回路开路：原始值接近 0 域（0 mA/0 V），变送器失电或回路断开 / Open loop, raw near zero domain, loop broken or transmitter unpowered
) USINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_AnalogSensor
 * 契约结构: 属性（PROPERTY GET）单段式，方法总数 0 个，远低于 ≤6 红线；
 *           纯只读数据契约——诊断与标定逻辑全部驻留实现块内部。
 * 边界防错: fValue 输出承诺经非有限值防御（输入为非数时保持末次有效值），
 *           调用方无需再做空值判护；故障态下 fValue 保持末次有效工程量
 *           并由 eQuality 与 uErrorId 显式标注，杜绝把故障电流当过程值。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_AnalogSensor

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY fValue    : REAL              // 工程量当前值（Current engineering value），单位由调用方标定组态约定，故障态保持末次有效值 / Current value, unit per caller scaling config, holds last good value in fault
PROPERTY eQuality  : E_DL_SignalQuality // 信号质量分级（Signal quality grade），NE43 四段诊断结果 / NE43 diagnostic grade
PROPERTY bAlarmHH  : BOOL              // 上上限报警（High-high alarm），TRUE=工程量越上上限门限 / TRUE = value above high-high limit
PROPERTY bAlarmH   : BOOL              // 上限报警（High alarm），TRUE=工程量越上限门限 / TRUE = value above high limit
PROPERTY bAlarmL   : BOOL              // 下限报警（Low alarm），TRUE=工程量越下限门限 / TRUE = value below low limit
PROPERTY bAlarmLL  : BOOL              // 下下限报警（Low-low alarm），TRUE=工程量越下下限门限 / TRUE = value below low-low limit
PROPERTY uErrorId  : UDINT             // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx

END_INTERFACE
