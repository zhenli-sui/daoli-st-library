(*==============================================================================
 * 组件名称 (Component)  : I_DL_PowerMeter
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）接口语法
 * 组件分类 (Category)   : 三相电表读侧抽象接口（INTERFACE）+ 同文件枚举 1 个
 * 功能描述 (Function)   : 三相电表的**读侧契约**——电量（电压/电流/功率/功率
 *                         因数/频率）、电能质量（由实现块给出）、累计电能（正
 *                         反向）、需量峰值与健康出口。上层能耗看板、需量控制、
 *                         电能质量监视三件只需持有本接口引用，即可适配 Modbus
 *                         表、PROFIBUS 表、脉冲表与虚拟表四类实现，而无需感知
 *                         寄存器排布与通信调度方式。
 * 分层声明 (Layering)   : ①**不含写侧**：费率切换、需量窗口写入、CT/PT 变比
 *                         下装均属配置层，另件承担——读侧契约一旦开口写侧，配置
 *                         错误就会污染测量数据；②**不含通信调度**：何时读寄存器
 *                         由轮询主站件决定，本契约只描述「读完之后的模型」；
 *                         ③**不含累计算法**：累计口径由实现块自行声明并在其头
 *                         注释写明，契约只承诺「单位 kWh 与单调不减的语义」。
 * 接口三段式 (Contract): ①状态枚举：E_DL_PowerMeterState（随本文件发布）；
 *                         ②属性：12 条，全部只读 GET；
 *                         ③方法：CmdResetEnergy / CmdReset / CmdAck 共 3 个。
 * 枚举映射 (Enum map)   : eIdle(0) 未使能 → eSampling(10) 正常计量 →
 *                         eDegraded(20) 越规但可读 → eFault(99) 锁存。
 *                         四个成员覆盖实现块计量相位机的全部取值，无隐藏成员；
 *                         eFault 取 99 与健康枚举的未知哨兵同带，便于 HMI 用
 *                         同一套「异常带」着色规则处理两套枚举。
 * 健康出口 (Health)     : eHealth 的类型 E_DL_Ne107Status **来自 I_DL_DeviceHealth
 *                         文件**，本文件只引用、**不重复声明枚举体**。重复定义会
 *                         造成跨文件同名异型，属本库明令禁止的编译隐患；实现块
 *                         须同时实现两个接口的能力（属性名在本契约内的 11 条
 *                         与健康契约的 10 条不冲突，可在同一功能块内并存）。
 * 边界防错 (Boundary)   : ①全部电气量均为**已换算的工程量**，原始寄存器与标定
 *                         系数不进契约——契约层不做换算，避免「同一物理量两种
 *                         单位」的双口径；②fActivePowerTotal **有符号**（负=反
 *                         送），实现块不得做绝对值化，否则反送电永远看不见；
 *                         ③fPowerFactorTotal 口径为 P/S（含符号），不是表内直接
 *                         读取的寄存器值；④fDemandPeak 只能被复位清除，实现块
 *                         不得在窗口切换时清零（否则峰值失去意义）。
 * 数据契约 (Semantics)  : CmdResetEnergy 仅在无故障锁存时受理（bLatched 语义由
 *                         实现块等同于 bError），因为故障期清零会把「表读数」与
 *                         「累计基准」同时抹掉，事后无法追溯是否真的换表；
 *                         CmdAck 与 CmdReset 的受理语义与 I_DL_DeviceHealth 对齐，
 *                         保证两个契约在实现块内的行为一致。
 * 开源溯源 (Origin)     : 来源标签 namur-ne107 / forge-devicereader /
 *                         meter-contract。本文件为**原创 clean-room 实现**：
 *                         仅借鉴 NAMUR NE107（公开推荐规范）的健康出口语义，以
 *                         及本库既有的「契约三段式」内部惯例（状态枚举 + 只读
 *                         属性 + 指令方法，见 I_DL_TowerLight / I_DL_Cylinder）。
 *                         forge-devicereader 为本库来源矩阵内的开源设备读取器
 *                         检索线索，仅用于确认「电表读侧契约应有哪几类量」这一
 *                         功能分类，未复制其任何源码行、未沿用其命名体系。属性
 *                         集合、类型选择、枚举取值与注释 100% 本库独立设计。
 * 验收向量 (Acceptance) : 本文件为纯契约、无执行体，行为验收下沉到实现块
 *                         FB_DL_ModbusPowerMeter 的 V1 至 V5。契约级自查四条：
 *                         C1 属性共 12 条且全部只读 GET（无 SET）；
 *                         C2 方法共 3 个且均带 BOOL 受理返回值；
 *                         C3 枚举 4 个成员取值 0/10/20/99 互不重复且升序；
 *                         C4 eHealth 的类型引用自 I_DL_DeviceHealth，本文件不含
 *                            任何以 TYPE 开头、以 E_DL_Ne107Status 为名的定义体。
 * 已知限制 (Limits)     : ①单表单契约——多表并联（进线与馈线分别计量）由上层持
 *                         多个接口引用，契约不做聚合；②不含分相功率——分相功率
 *                         仅在实现块以扩展引脚给出，契约只承诺三相合计，避免
 *                         强迫脉冲表等无分相能力的实现伪造分相值；③不含事件
 *                         顺序记录——事件时标与顺序属归档件职责。
 * 规格偏离 (Deviation)  : ①规格表头写「属性段（11 条）」，但其下方表格实际列出
 *                         12 条（含 eState 与 fDemandPeak），本文件按**表格 12 条**
 *                         实现并在 C1 中自证；②规格正文提及实现块状态机枚举名
 *                         E_DL_PowerMeterPhase，本契约已发布成员完全同构的
 *                         E_DL_PowerMeterState（0/10/20/99），实现块直接复用本
 *                         枚举，不再声明第二个同构枚举（详见该实现件偏离留档）。
 * 红线自检 (Redline)    : 零全局变量表访问 ✓｜零外部变量声明 ✓｜零物理地址直写 ✓
 *                         纯 IEC 61131-3 ✓｜全成员中英双语同行注释 ✓
 *                         INTERFACE 与 END_INTERFACE 成对 ✓｜TYPE 与 END_TYPE 成对 ✓
 *                         枚举成员一律 := 赋值 ✓｜无孤立分号空语句 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R13 · 泳道 A · Phase 1 电表读侧契约补齐）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PowerMeterState（归属接口 I_DL_PowerMeter，与其同文件）
 * 含义: 电表计量相位。eDegraded 与 eFault 的分界是本枚举的核心语义——
 *       **越规不改数据可信度 → Degraded；数据不可信 → Fault**。这条分界对应
 *       NE107 的 S（Out of specification）与 F（Failure）之别，现场最常见的
 *       误判就是把「电压偏高」当故障停机，把「表掉线」当越规只做提示。
 *----------------------------------------------------------------------------*)
TYPE E_DL_PowerMeterState :
(
    eIdle     := 0,    // 待机：未使能或标定未通过，输出保持 / Idle, disabled or calibration not yet accepted
    eSampling := 10,   // 正常计量：数据可用，判据全部在限内 / Sampling, data usable and all criteria within limits
    eDegraded := 20,   // 降级：越规但数据仍可信，继续计量并提示 / Degraded, out of spec yet still trustworthy
    eFault    := 99    // 故障：数据不可信或自相矛盾，锁存待复位 / Fault, data untrustworthy, latched until reset
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_PowerMeter
 * 契约结构: 属性（只读 GET，12 条）+ 方法（3 个）两段式。方法均为非阻塞单发
 *           语义：只做受理判定与请求登记，实际清零动作由实现块主体下一拍执行。
 * 受理语义: CmdResetEnergy 在故障锁存期返回 FALSE（故障期清零会同时抹掉读数与
 *           基准，事后无法追溯换表真伪）；CmdReset 仅在锁存存在时返回 TRUE；
 *           CmdAck 仅受理维护与越规两类可继续运行的等级，对失效返回 FALSE。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_PowerMeter

// ---- 属性段（全部只读 GET，共 12 条）--------------------------------------

PROPERTY eState             : E_DL_PowerMeterState // 计量状态（Metering state），eIdle/eSampling/eDegraded/eFault
PROPERTY eHealth            : E_DL_Ne107Status     // NE107 健康态（NE107 health），类型引用自 I_DL_DeviceHealth
PROPERTY uDiagCode          : UDINT                // 诊断码（Diagnostic code），0=无码，段位 16#0003_xxxx
PROPERTY fVoltageAvg        : REAL                 // 三相平均相电压（Average phase voltage）[V]，范围 0~400
PROPERTY fCurrentAvg        : REAL                 // 三相平均电流（Average phase current）[A]，范围 0~10000
PROPERTY fActivePowerTotal  : REAL                 // 三相总有功（Total active power）[kW]，有符号，负=反送
PROPERTY fReactivePowerTotal: REAL                 // 三相总无功（Total reactive power）[kvar]，范围 0~30000
PROPERTY fPowerFactorTotal  : REAL                 // 总功率因数（Total power factor）[-]，范围 -1.0~1.0
PROPERTY fFrequency         : REAL                 // 电网频率（Grid frequency）[Hz]，范围 45~65
PROPERTY fEnergyImport      : LREAL                // 正向累计电能（Import energy）[kWh]，单调不减（换表除外）
PROPERTY fEnergyExport      : LREAL                // 反向累计电能（Export energy）[kWh]，单调不减（换表除外）
PROPERTY fDemandPeak        : REAL                 // 历史峰值需量（Peak demand）[kW]，仅复位可清

// ---- 方法段（单发指令，返回受理结果，共 3 个）-----------------------------

(* 清零累计电能（Reset the accumulated energy）。仅在无故障锁存时受理：
 * 故障期清零会把表读数与累计基准同时抹掉，事后无法追溯是否真的换表。
 * 方法内只登记请求，实际清零由实现块主体下一拍执行。 *)
METHOD CmdResetEnergy : BOOL
VAR_INPUT
END_VAR

(* 复位锁存（Reset the latch）。仅存在锁存时返回 TRUE，否则 FALSE。
 * 方法内只登记请求，锁存清除与状态回退由实现块主体下一拍执行。 *)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR

(* 应答维护与越规提示（Acknowledge maintenance and out-of-spec）。
 * 仅受理 eMaintenanceReq 与 eOutOfSpec，对 eFailure 返回 FALSE。 *)
    END_METHOD

METHOD CmdAck : BOOL
VAR_INPUT
END_VAR

    END_METHOD
END_INTERFACE
