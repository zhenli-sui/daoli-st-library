(*==============================================================================
 * 组件名称 (Component)  : I_DL_LightCurtain
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 安全光幕监控与屏蔽（Muting）标准抽象契约。定义光
 *                         幕状态读取属性组（GET）与滞留清除/确认/复位方法
 *                         组，供上层工站做依赖注入；OSSD 采集与屏蔽传感器
 *                         接线由实现块（如 FB_DL_SafetyLightCurtain）完成，
 *                         接口层不读物理输入。
 * 定位声明 (Positioning): 公约 0.13——本接口及其实现块为标准 PLC 逻辑编排
 *                         与诊断镜像层，不构成 ISO 13849 / IEC 62061 认证
 *                         安全功能，安全回路由认证安全控制器/安全 PLC 承载；
 *                         光幕本体 OSSD 的安全判断在认证安全光幕内部完成。
 * 契约结构 (Structure)  : 公约 0.11 接口三段式——状态枚举（本文件承载）+
 *                         属性（PROPERTY GET）+ 方法（METHOD）；方法共 3 个
 *                         （≤6 红线内）。故障态一律拒绝方法。
 * 边界防错 (Guard)      : bSafeStop 输出永不因屏蔽/override 置假——屏蔽态下
 *                         bSafeStop 断言恒 FALSE（光幕正常），实现块出口断
 *                         言承载。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / light-curtain-muting
 *                         （RAW_NOTES_R7 S-2/S-5：TcOpen 组件接口分层思想与
 *                         安全光幕屏蔽公开语义——OSSD 镜像、Muting/Override
 *                         状态域，公开资料，仅借鉴状态域语义；接口命名、枚
 *                         举编号、方法签名 100% 本库独立设计，clean-room 未
 *                         复制源码）。
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_CurtainState 枚举定义，该枚举
 *                         归属接口 I_DL_LightCurtain，与其同文件发布（公约
 *                         0.11；禁止异文件同名异型重复定义）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 N/A（契约件无运算）
 *                         R5 全成员中英双语同行注释 ✓｜R6 N/A（接口无状态机）
 *                         R7 N/A（无实例调用）｜R18 INTERFACE/END_INTERFACE
 *                         成对终结 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 光幕族接口件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CurtainState（归属接口 I_DL_LightCurtain，与其同文件）
 * 含义: 光幕监控/屏蔽离散状态。编号步长 10 留空位，eFault 取 99 保证排序末
 *       位（全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_CurtainState :
(
    eClear    := 0,   // 通光：光幕未被遮挡且无屏蔽活动 / Clear, curtain unblocked and no muting activity
    eBlocked  := 10,  // 遮挡：光幕被遮挡且未屏蔽（应停机镜像态）/ Blocked, curtain interrupted without muting (safe-stop mirror)
    eMuting   := 20,  // 屏蔽进行中：合法屏蔽序列屏蔽中 / Muting, a legal muting sequence is active
    eOverride := 30,   // 滞留清除进行中：钥匙开关滞留物清除 / Override, key-switch residual-object clearing active
    eFault    := 99   // 故障锁存：序列错误/屏蔽超时/OSSD 不一致/非法状态 / Latched fault
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_LightCurtain
 * 边界防错: 故障态一律拒绝方法并返回 FALSE；bSafeStop 永不因屏蔽/override
 *           置假（屏蔽态下断言恒 FALSE，实现块承载）。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_LightCurtain

// ---- 属性段（全部只读 GET，实现块一一落地）----------------------------------

PROPERTY eState         : E_DL_CurtainState // 当前光幕状态（Current curtain state），枚举见 E_DL_CurtainState
PROPERTY bClear         : BOOL              // 光幕通光（Clear），OSSD 双通道全通光 / OSSD both channels clear
PROPERTY bMutingActive  : BOOL              // 屏蔽进行中（Muting active），合法屏蔽序列屏蔽中 / TRUE = legal muting sequence active
PROPERTY bOverrideActive: BOOL              // 滞留清除进行中（Override active），滞留物清除中 / TRUE = override clearing active
PROPERTY bSafeStop      : BOOL              // 应停机输出（Safe stop），光幕被遮挡且未屏蔽——本接口核心安全镜像位 / Curtain blocked and not muted, core safe-stop mirror
PROPERTY bFault         : BOOL              // 故障锁存中（Fault latched），显式排除信息级码（R21）/ TRUE = latched fault, info codes excluded
PROPERTY uErrorId       : UDINT             // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理/合法性结果）----------------------------------

METHOD CmdOverride : BOOL // 滞留物清除请求（Override request），前提至少一个屏蔽传感器仍遮挡，否则拒绝 / Override accepted only with at least one muting sensor blocked
VAR_INPUT
END_VAR

METHOD CmdAck : BOOL // 屏蔽/故障确认复位（Acknowledge of muting abort/fault），屏蔽序列中止后回评估态受理 / Ack after a muting abort, back to evaluation
VAR_INPUT
END_VAR

METHOD CmdReset : BOOL // 复位故障与重启联锁（Reset fault and restart interlock），仅故障态受理 / Reset accepted only in fault state
VAR_INPUT
END_VAR

END_INTERFACE
