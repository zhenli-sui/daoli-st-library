(*==============================================================================
 * 组件名称 (Component)  : I_DL_DeviceHealth
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）接口语法，
 *                         无任何厂商方言、无标准库依赖（纯契约件）
 * 组件分类 (Category)   : 设备健康抽象接口（INTERFACE）+ 同文件枚举 1 个
 * 功能描述 (Function)   : 定义「任何设备都能回答的三个问题」的统一健康语言——
 *                         ① 我现在健康吗（NE107 四态 + 未知 + 功能检查 六态）；
 *                         ② 我的证据是什么（诊断码 + 证据来源槽号）；
 *                         ③ 这个状态持续多久了（当前态时长 + 锁存位）。
 *                         本契约**只定义提问方式，不定义判据**：NE107 明确把
 *                         判据留给实现者（不同设备失效机理不同，统一判据反而
 *                         会把正确行为判错），也不定义视觉呈现（图标与颜色属
 *                         HMI 层，本契约只给语义枚举）。
 * 接口三段式 (Contract): ①状态枚举：E_DL_Ne107Status（随本文件发布）；
 *                         ②属性：10 条，全部只读 GET；
 *                         ③方法：CmdAck / CmdReset 共 2 个（满足接口方法
 *                         不超过 6 个的拆分红线）。
 * 枚举映射 (Enum map)   : 按优先级升序（数值小者优先），每一个成员均为实现块
 *                         健康出口的合法取值，无隐藏成员：
 *                         eFailure(0) → eCheckFunction(10) → eMaintenanceReq(20)
 *                         → eOutOfSpec(30) → eOk(40) → eUnknown(99)。
 *                         上位机做等级仲裁时按数值取小者即为最严等级。
 * 优先级声明 (Priority) : 本枚举**编号即优先级序（0 最优先）**，该编号是本库
 *                         自行约定的仲裁序，**不等于** NAMUR NE107 官方图标的
 *                         排列顺序，也不等于现场灯排的物理左右顺序。后续维护
 *                         者严禁「按图改号」——改号会让全部实现块的仲裁方向
 *                         静默反转，且编译期无法发现。
 * 归属说明 (Ownership)  : 本文件同时承载枚举 E_DL_Ne107Status 的定义，枚举归属
 *                         本接口，与其同文件发布（公约 0.11：一文件一 POU，枚举
 *                         随宿主发布）。**全库唯一属主是本文件**：其余实现块
 *                         （FB_DL_ModbusPowerMeter / FB_DL_ValveStictionDetect /
 *                         FB_DL_AhuDamperStuckDiag / FB_DL_PumpCavitationGuard 等）
 *                         只允许引用本类型，禁止复制枚举体；重复定义会造成跨文件
 *                         同名异型，属本库明令禁止的编译隐患。
 * 边界防错 (Boundary)   : ①接口不声明任何变量段（IEC 接口只允许属性与方法），
 *                         故本契约天然不携带状态，实现块无需担心契约侧写冲突；
 *                         ②接口不约束判据阈值、不约束采样周期、不约束码位分配
 *                         （码位由实现块承担，沿用 I_DL_TowerLight 先例）；
 *                         ③bDataValid 与 eHealth **正交**：健康但数据陈旧是合法
 *                         组合（TRUE 健康 + FALSE 数据），实现者不得用数据有效性
 *                         去覆盖健康态，反之亦然；④sDeviceClass 为定长 16 字符，
 *                         实现块写入前须自行预判长度（超长即截断并置信息码），
 *                         契约层不做长度校验。
 * 数据契约 (Semantics)  : tDuration 语义为「当前态已持续时长」，态切换当拍清零，
 *                         实现块须保证同一拍内不与 bLatched 的清除冲突；fQuality
 *                         为趋势参考量（1.0 最佳），**不得作为报警判据**，仅供
 *                         HMI 画趋势与维护排程评估；nCodeHistory 只计数不存表，
 *                         掉电不保持（存储策略属实现块与上层归档件职责）。
 * 开源溯源 (Origin)     : 来源标签 namur-ne107 / device-abstraction /
 *                         interface-contract。本文件为**原创 clean-room 实现**：
 *                         仅借鉴 NAMUR NE107 推荐规范（公开的推荐性实践文件，
 *                         非代码、非开源软件）中「四态诊断分类 + 诊断码 + 来源
 *                         位」的公开语义框架，以及本库既有 I_DL_TowerLight 的
 *                         接口三段式组织惯例。枚举取值、属性与方法签名、注释与
 *                         全部实现细节 100% 本库独立设计，未复制任何源码行；
 *                         NE107 为公开推荐规范，无许可证传染问题。设备抽象层
 *                         （device-abstraction）为工业软件通行架构模式，属公有
 *                         领域思想，不构成版权标的。
 * 验收向量 (Acceptance) : 本文件为纯契约、无执行体，行为验收下沉到实现块。契约级
 *                         自查四条：
 *                         C1 属性共 10 条且全部为只读 GET（无 SET）；
 *                         C2 方法共 2 个且均带 BOOL 受理返回值；
 *                         C3 枚举 6 个成员取值互不重复且升序排列（0/10/20/30/40/99）；
 *                         C4 引用本契约的 4 个实现块其 eHealth 出口只出现本枚举的
 *                            6 个成员，无自造等级。
 * 已知限制 (Limits)     : ①单设备单健康出口——多子部件设备（如带 3 个阀腔的
 *                         组合阀）需由上层聚合件做等级取最严，本契约不提供树形
 *                         聚合；②不含时间戳——当前态起始时刻由实现块以 tDuration
 *                         反推，契约不给绝对时刻，避免引入日期类型依赖；
 *                         ③不含文本描述——诊断文本属 HMI 多语言资源，不进契约。
 * 规格偏离 (Deviation)  : 无。枚举 6 个成员取值、10 条属性类型与 2 个方法签名与
 *                         ROUND_PLAN_R13 第 3.1 节 A1 逐条一致。
 * 红线自检 (Redline)    : 零全局变量表访问 ✓｜零外部变量声明 ✓｜零物理地址直写 ✓
 *                         纯 IEC 61131-3 ✓｜全成员中英双语同行注释 ✓
 *                         INTERFACE 与 END_INTERFACE 成对 ✓｜TYPE 与 END_TYPE 成对 ✓
 *                         枚举成员一律 := 赋值 ✓｜无孤立分号空语句 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R13 · 泳道 A · NE107 设备健康语言契约）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_Ne107Status（归属接口 I_DL_DeviceHealth，与其同文件）
 * 含义: 设备健康的统一语义分级。数值即仲裁优先级（小者优先），步长 10 留空位
 *       便于后续插入细分等级而不影响既有工程持久化数值；99 为「未知」哨兵，
 *       刻意远离常规带（0~40），使任何「忘记处理未知态」的取小仲裁都会自然
 *       落到正常带之外，便于现场发现漏判。
 *----------------------------------------------------------------------------*)
TYPE E_DL_Ne107Status :
(
    eFailure        := 0,    // 失效：信号不可信，须立即处理 / Failure, signal invalid, immediate action
    eCheckFunction  := 10,   // 功能检查：回路测试/仿真/标定中，信号暂时无效 / Function check, signal temporarily invalid
    eMaintenanceReq := 20,   // 需要维护：仍有效但已劣化，排入维护计划 / Maintenance required, still valid but degraded
    eOutOfSpec      := 30,   // 超出规格：工艺/环境越界，测量不确定度上升 / Out of specification, uncertainty increased
    eOk             := 40,   // 正常：无诊断激活 / OK, no diagnostic active
    eUnknown        := 99    // 未知：尚未取得有效数据（冷启动首拍）/ Unknown, no valid data yet
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_DeviceHealth
 * 契约结构: 属性（只读 GET，10 条）+ 方法（2 个）两段式，方法总数满足不超过 6
 *           个的拆分红线。方法均为非阻塞单发语义，不含跨扫描周期状态驻留：
 *           方法只做「受理判定 + 登记请求」，实际动作由实现块主体状态机在下一拍
 *           执行（若在方法内直接改状态，会与主体状态机同拍写冲突）。
 * 受理语义: CmdAck  仅受理 eMaintenanceReq 与 eOutOfSpec 两类「可继续运行」的
 *                     等级，对 eFailure 一律返回 FALSE（失效不能被应答掉，只能
 *                     被修复或被复位，这是 NE107 的安全底线）；
 *           CmdReset 仅在 bLatched 为 TRUE 时受理，否则返回 FALSE（无锁存时复位
 *                     无对象，返回 TRUE 会掩盖上层逻辑错误）。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_DeviceHealth

// ---- 属性段（全部只读 GET，共 10 条）--------------------------------------

PROPERTY eHealth      : E_DL_Ne107Status  // 当前健康态（Current health state），取值为仲裁后最严等级
PROPERTY uDiagCode    : UDINT              // 当前诊断码（Active diagnostic code），0=无码，段位 16#0003_xxxx
PROPERTY uSourceId    : UINT               // 证据来源槽号（Evidence source slot），0=未定义，1~65535 由实现块自定义
PROPERTY tDuration    : TIME               // 当前态已持续时长（Duration of the current state）[毫秒]，态切换即清零
PROPERTY bLatched     : BOOL               // 是否锁存（Latched flag），TRUE 时只能经 CmdReset 退出
PROPERTY bDataValid   : BOOL               // 本拍数据是否可用（Data valid this scan），与健康态正交
PROPERTY fQuality     : REAL               // 数据质量因子（Quality factor），0.0~1.0，1.0 最佳，仅作趋势参考
PROPERTY nCodeHistory : UINT               // 历史码计数（Code change count），仅计数不存表
PROPERTY sDeviceClass : STRING(16)         // 设备类别短名（Device class tag），如 VALVE / METER，定长不超 16 字符
PROPERTY bSimulated   : BOOL               // 仿真或强制模式（Simulation or forced mode），eCheckFunction 的典型来源

// ---- 方法段（单发指令，返回受理结果，共 2 个）-----------------------------

(* 应答维护请求与越规提示（Acknowledge maintenance and out-of-spec）。
 * 仅受理 eMaintenanceReq 与 eOutOfSpec，其余等级返回 FALSE——失效（eFailure）
 * 不可被应答，功能检查（eCheckFunction）与未知（eUnknown）无需应答。
 * 方法内只登记请求标志，实际清码动作由实现块主体在下一拍执行。 *)
METHOD CmdAck : BOOL
VAR_INPUT
END_VAR

(* 复位锁存（Reset the latch）。仅 bLatched 为 TRUE 时受理，返回 TRUE；
 * 无锁存时返回 FALSE。方法内只登记请求标志，锁存清除与状态回退由实现块主体
 * 在下一拍执行，避免与主体状态机同拍写冲突。 *)
METHOD CmdReset : BOOL
VAR_INPUT
END_VAR

END_INTERFACE
