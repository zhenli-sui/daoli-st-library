# RAW NOTES R22 —— 狩猎记录、许可边界与矩阵回写建议

> 轮次：**R22** ｜ 时间：2026-11-16 23:06 ｜ 编制：道莅工控代码库产品总监（daoli-library-director / 召唤模式：原生）
> 检索预算：**2 次 WebSearch / 3 次**（T0 变体线 2 件零检索；T2-1 LGF 子族**复用 R21 留痕，同源不重复检索**）
> 结论先行：**本轮零代码行入库**。2 次检索均为「公开规范条款 + 公开工程判据」核对，**未下载任何库文件、未取得任何闭源厂商 ST 源码**；所有实现（状态机 / 码位 / 阈值 / 判据 / 错误码）100 % clean-room 自有。

---

## 1 检索执行记录（逐条原文，可复现）

| # | 查询语句（原文照录） | 目的 | 结果可用性 |
|---|---|---|---|
| 1 | `PLCopen Motion Control Part 1 BufferMode Aborting Buffered Blending semantics MC_MoveAbsolute` | 核对 `MC_BUFFERMODE` 的**枚举成员全集与 Buffered 语义**，为 #14 `FB_DL_MotionCmdQueue` 立「只做 Buffered、不做 Blending」的边界 | **可用**：命中 PLCopen TC2 规范原文条款 + 官方 PDF + 两家实现文档，枚举成员与语义三处一致 |
| 2 | `蒸汽疏水阀 故障诊断 判据 上下游温差 堵塞 泄漏 疏水阀监测` | 核对疏水阀「温差判据」的**公开工程数值区间**（正常温差 / 泄漏温差），用于 #10 `FB_DL_SteamTrapMonitor` 的**引脚缺省值选取**（不写死） | **可用**：四份公开资料相互印证，但门限存在 **10 K / 20 K 两说**，故一律做成引脚 |

**零检索件（4 件）**：`#4 FC_DL_FirstSetBit`、`#5 FB_DL_FrequencyMeasure`（T0 变体线，R14 三判据准入：逐引脚对应标准语义 + 委托 `Standard.library` 语义 + clean-room）；`#6/#7`（燃烧控制律，公开过程控制惯例 + `T2-5` 参数域纪律，无新外部检索必要）。

**复用既有留痕（不重复检索）**：
- `T2-1 LGF` 分类事实与参数域：复用 **R21 `RAW_NOTES_R21.md` §1 的 S1~S5**（LGF V4.0.2 官方手册摘录 + 26 分类第三方索引 + CRC/位操作组详解）。R21 已核实的「类型转换 19 件 / 合并拆分 12 件 / 数据处理 6 件 / 字符串 5 件」组粒度，直接支撑 #1~#3 的立项依据。
- `T0-2 / T0-7` 变体线纪律：复用 **R16 / R17 / R20** 三轮的准入结论与游标治理（R61~R64）。

### 1.1 访问到的公开资料

| 编号 | 类型 | 地址 | 许可证 / 版权状态 | 用途 |
|---|---|---|---|---|
| Q1 | PLCopen TC2 规范原文 PDF（第三方镜像） | `http://fs.gongkong.com/files/technicalData/200706/3-9769-965BA20E1919.pdf` | **PLCopen 规范免费公开**（可引用条款，不可作为代码来源） | `MC_BUFFERMODE` 六种模式定义原文：Aborting / Buffered / BlendingLow / BlendingPrevious / BlendingNext / BlendingHigh |
| Q2 | PLCopen 官方下载页（PDF） | `https://www.plcopen.org/download_file/view/f005ffef-47b8-4423-9664-52a29529ac36/` | 同上 | 交叉印证 Buffered 语义（「等前一条 `Done` 后新 FB 才影响轴」）与 `InPosition`/`InVelocity` 作为 buffered 触发输出的合法用法 |
| Q3 | 厂商实现文档（RexControls `RM_Axis`） | `https://www.rexcontrols.com/media/2.50.1/doc/ENGLISH/MANUALS/BRef/RM_Axis.html` | 厂商文档（版权）；**只读语义，零引用** | 印证「轴状态机 + BufferMode 混合过渡」的实现侧常见组织；**未采用其任何命名与代码** |
| Q4 | 厂商应用说明（S7-200 SMART G2 BufferMode） | `https://www.ad.siemens.com.cn/DOWNLOAD/materialaggregation_5653.html` | 厂商文档（版权）；**只借枚举语义** | 印证「缓冲模式 = 打断 vs 排队」二分，以及现场常见「每轴缓冲 8 条」工程惯例（本库队列深度取 8 的**唯一**外部依据，非代码来源） |
| Q5 | 疏水阀故障分析（行业站） | `http://haijianfm.com/news/show-955.html` | 网页文档（版权）；**只借公开判据区间** | 温差判据：「正常进出口温差 ≥ 10 ℃；温差 ≤ 5 ℃ 判严重蒸汽泄漏；进出口均偏低无温差判堵塞」 |
| Q6 | 疏水阀判断方法（阀门厂商技术页） | `http://www.hldfm.com/service/detail/303.html` | 同上 | 交叉印证：温差不足（另一来源给 < 20 ℃）提示关闭不严致蒸汽泄漏 —— **两说并存，故门限做引脚** |
| Q7 | 疏水阀检测（检测机构技术页） | `https://www.yjssi.com/showinfo-4-61568-0.html` | 同上 | 交叉印证「热静力型阀体应有温度梯度 / 出口温度过高提示泄漏」 |
| Q8 | 疏水阀体检（阀门厂商技术页） | `https://www.vmv-valves.com/...` | 同上 | 交叉印证「温差 5~6 ℃、2~3 ℃ 以内判泄漏较大」——进一步说明**必须参数化** |

> **检索纪律自查**：两次检索均属「同源不重复」——PLCopen（T1-6）本轮首次检索；疏水阀判据（公开工程惯例，自研线）本轮首次检索。`T2-1 LGF` 与 `T0` 各线**未发起任何新检索**，全部复用既有留痕。

---

## 2 许可与合规结论（三条铁律执行）

| 项 | 结论 |
|---|---|
| **PLCopen 规范（Q1/Q2）** | 规范条款**免费公开可引用**，但**不可作为代码来源**。本轮只取：① `MC_BUFFERMODE` 枚举成员**语义名称**；② 「Buffered = 等 `Done`」这一条**行为定义**；③ `InPosition`/`Standstill` 作为**输出语义**的存在事实（#16 立项依据）。**未复制**其 XML schema、FB 引脚表排版、状态图编号、示例码。 |
| **西门子文档（Q4）** | 闭源版权。只借「缓冲 vs 打断」二分语义与「8 条」这一工程惯例量级；**零代码行、零注释引用、零块名**（不含 `LGF_` 前缀与任何派生名）。 |
| **RexControls（Q3）** | 厂商文档版权。仅用于确认「混合过渡在实现侧如何处理」的**存在性**，**未采用其轴状态机结构、命名或码位**。 |
| **疏水阀资料（Q5~Q8）** | 网页文档版权。只借「温差判据」这一**公开工程口径**与门限量级区间；判据结构（三分类 + 三独立确认窗）、状态机、健康映射、码位 100 % 自有。 |
| **T2-1 LGF（复用 R21 留痕）** | 免费使用但**非开源**。取最严口径：只借「分类事实 + 参数域 + 行为定义」；**零代码行、零符号名、零块头格式**。#1~#3 的填充策略、对齐规则、饱和口径、`nErrPos` 定位语义全部自有。 |
| **T1-1 / T1-2 OSCAT（次源）** | #10/#11 只借「**域外行为显式化**」这一**写法纪律**（域外保持上次有效值并在掩码/健康出口标出，而不是塞伪值），与 R11 `NtcTempScan` 同一口径。**未复制任何函数体、函数名、常量名**。 |
| 可商用结论 | 道莅 R22 产出 100 % 自有实现，**商用无限制**；无 GPL/AGPL 传染风险（本轮未接触任何开源 ST 源码） |

---

## 3 提取点与「借 / 不借」判定（逐件对应）

### 3.1 采用的提取点

| 组件 | 借什么（分类级 / 参数级 / 行为定义级） | 不借什么（自有部分） |
|---|---|---|
| `#1 FC_DL_IntToFixedField` | **分类事实**：LGF「类型转换 19 件 + 合并拆分 12 件」把「数值 ↔ 定宽文本」独立成族（R21 S2 留痕）；**行为定义**：`LGF_IntToString` 证明「整数 → 文本」是标准需求形态 | 填充字符分型（零/空格）、对齐方向、符号强制开关、**负域取模防 `DINT_MIN` 溢出**、宽度不足拒绝编码策略、码位 `045C`/`03A8` |
| `#2 FC_DL_FixedFieldToInt` | 同上（编码对的反向） | `LEN` 一次锁存（R37）、前导填充剥离规则、`nErrPos` 精确到字符、负域累乘、饱和哨兵 `±2147483647`、码位 `045E`/`045F`/`03AB`/`03AC` |
| `#3 FC_DL_LrealToFixedField` | **行为定义**：LGF `TimeToString` / `DTLtoString` 证明「数值/时间 → **定宽文本**」是独立需求形态（与「去空格」的 `IntToString` 相反方向） | 禁 `LREAL_TO_STRING` 的自行逐位分解、绝对值域取整、`(x−x)<>(x−x)` 非有限判据（R79）、15 位十进制精度声明、码位 `0460`/`0461`/`03AE`/`03AF` |
| `#6 FB_DL_CrossLimitSelect` | **参数域纪律**（T2-5）：限值/死区/抗饱和三件套的参数面组织方式 | 双交叉限幅的**选择律本身**（先行裕度乘子、受约束侧判定、双侧钳位）、五态状态机、安全侧方向（参数非法即双给 0）、码位 `2B01/2B02/2B10-2B12` |
| `#14 FB_DL_MotionCmdQueue` | **行为定义**（T1-6）：`MC_BUFFERMODE` 的 `Buffered` 一条 —— 「新指令等前一条 `Done` 后才影响轴」；**工程量级**：每轴 8 条缓冲（Q4 惯例） | 环形队列结构、指针一致性自愈、满队双策略（丢最旧 / 拒绝新入）、去重判据、单拍发令、`uDropped` 台账、码位 `01D9/01DA/02F0-02F2`；**Blending 系列明确不立** |
| `#15 FC_DL_CamTableValidate` | **行为定义**（T1-6）：`MC_CamTableSelect` 需先给合法凸轮表这一**前置校验**事实 | 四项判据（相位单调 / 值有限 / 首尾闭合 / 斜率上限）、掩码不早退、`Δphase` 前置除零闸、码位 `01DB/01DC/02F3-02F5` |
| `#16 FB_DL_AxisInPosMonitor` | **输出语义**（T1-6）：`InPosition` 是 PLCopen 正式输出（并在 buffered 语义中可作触发条件，Q2 已核） | 「到位稳定」判定（位置窗 + 速度阈 + 稳定时间 + 抖振计数）、六态状态机、与驱动器跟随误差监视的职责划界、码位 `01DD/01DE/02F6-02F8` |
| `#10 FB_DL_SteamTrapMonitor` | **公开工程判据**（Q5~Q8）：温差三分类与门限量级；**写法纪律**（T1-1 次源）：域外行为显式化 | 三独立确认窗、冷态冻结语义（`fTin < fTinMin` 不进故障）、健康映射（泄漏→`eOutOfSpec` / 堵塞→`eMaintenanceReq`）、门限全部引脚化、码位 `0176/0177/0342-0344` |
| `#11 FB_DL_LevelRadarValidate` | **信号质量契约**（NAMUR NE43 家族）：有效域之外的值不得静默进联锁；**写法纪律**（T1-2 次源）：域外保持上次有效值并在掩码标出 | 四判据全量掩码、初始无历史值时 `bValid := FALSE`（0 m 不得当可信）、发布值/实时值分离、变化率单拍剔除、码位 `0178/0179/0345-0347` |
| `#8 FB_DL_SlitValveInterlock` | **互锁语义组织**（T2-8 次源，与存量 `InterlockMatrix` 同源分类）：多条件与、首因可追溯 | 门类语义（大气/真空侧、机械臂在位）、阻塞掩码位定义、保守侧默认（反馈矛盾按门未关、真空非法按不足）、码位 `0172/0173/033C-033E` |
| `#9 FB_DL_PressureReliefMonitor` | **健康分级语言**（T2-8 NE107 次源）：`eMaintenanceReq` / `eFailure` / `eOk` 三态出口，且**引用唯一属主 `E_DL_Ne107Status` 不重声明**（R70） | 起跳/回座判据（回座比迟滞）、最短起跳时长过滤、动作次数与累计时长台账、饱和守卫（R35）、码位 `0174/0175/033F-0341` |
| `#12 FB_DL_AxisBrakeSeq` | **使能时序纪律**（T1-6 `MC_Power` Enable/Status 语义）+ **抱闸组织**（T2-4 次源：工艺对象的使能/禁用外部接口） | 两条序列的**顺序本身**（先释放后使能 / 先静止后抱闸再断使能）、拒绝断使能策略、七态状态机、码位 `01D5/01D6/02EA-02EC` |
| `#13 FB_DL_VirtualMasterAxis` | **工艺对象分型**（T2-4 次源）：SynchronousAxis 需要一个主值源 | 速度斜坡 + 位置 `LREAL` 累加、保持走减速斜坡、相位复位优先于失能、精度门限冻结、码位 `01D7/01D8/02ED-02EF` |
| `#17 FB_DL_CompressorSurgeGuard` | **变化率限幅语义**（T2-1 LGF Technology 次源）+ **公开喘振判据惯例**（流量低于危险线即放空） | 危险线按压比线性修正的公式与系数、快开慢关非对称斜率、回差退出、「参数非法→全开 / 坏值→保持」两条反向安全方向、码位 `01DA/01DB/030B-030D` |
| `#18 FB_DL_ColumnDpCtrl` | **参数域**（T2-5 次源）：死区 + 抗饱和 + 双侧钳位 | 增量式双向调节、钳位后不再累加、`bDpHigh` 期间再沸强制落底、五态状态机、码位 `01DC/01DD/030E-0310` |
| `#19 FB_DL_InertPurgeSeq` | **态命名**（T2-7 次源，不作主源）：最小子集 + 明确终止态 | 三相循环结构、每相独立 `TON`（R40）、`bAbort` 任意拍生效不排队、`bO2SensorOk = FALSE` 禁止放行、码位 `01DE/01DF/0311-0313` |
| `#20 FB_DL_BatchTransferSeq` | **相/步骤语义**（T2-8 次源，公开条款）：前置确认 → 执行 → 终点判据 → 完成 | 阀位确认先于启泵、先停泵后关阀、排空验证窗、累计量外部注入（复用优先）、码位 `01E0/01E1/0314-0316` |
| `#4 FC_DL_FirstSetBit` | **零检索**（T0-7 变体线）：位串标准语义（置位位定位）+ 常量掩码避 `SHL(x,64)` | 全部自有 |
| `#5 FB_DL_FrequencyMeasure` | **零检索**（T0-2 变体线）：`TON` 门时 + `R_TRIG` 边沿计数均为标准语义 | 全部自有 |

### 3.2 明确**不立项**的提取点（防下轮重复立项，R85 纪律）

| 候选 | 不立项理由 | 库内落点 |
|---|---|---|
| `FB_DL_WaferHandoffSeq`（晶圆双机械手交接） | 与已收口 `FB_DL_PickAndPlaceStation`（执行态九步序）+ `FB_DL_ParallelGripper`（夹持确认）叠加即得，独立成件属「换皮」 | 存量两件 |
| `FB_DL_UnwinderDiameterCalc`（放卷卷径层厚递推） | 层厚递推已由 `FB_DL_WindingLayerCounter` 覆盖、速度比法已由 `FC_DL_CoilDiameterCalc` 覆盖，三重重复 | 存量两件 |
| `FC_DL_SearchMinMaxDint` / `FC_DL_SearchMinMaxUdint` | R21 已判「仅差数据类型的伪重载」，本轮不翻案；LGF 存在该重载**不构成**立项理由 | 存量 `FC_DL_SearchMinMax` |
| `FC_DL_ModbusAsciiFrameCheck`（T1-3 剩余项「ASCII 帧 LRC 定位」） | ASCII 帧 = `':'` 起始 + 十六进制字符域 + `CRLF` 结束 + LRC，`LRC` 已由 `FC_DL_LrcChecksum` 占位、十六进制解析已由 `FC_DL_HexStringToBytes` 占位，剩两行判据属**框架解析薄件** | 存量两件 |
| `FB_DL_DebounceBank`（多通道去抖阵列） | 与存量 `FB_DL_SignalDebounce` 语义完全重合，仅「多实例打包」，数组化收益不抵配额 | 存量 |
| `FC_DL_NibbleSwap`（半字节交换） | `FC_DL_SwapBytes16` + 掩码一行可合成，薄包装 | 存量 |
| `FB_DL_MotionBlendingQueue`（Blending 混合过渡排队） | PLCopen `BlendingLow/High/Previous/Next` 需**指令速度融合**，本库轴接口无「指令速度」反馈通道，实现只能是伪量（与 R8 否「跟随误差监视」同一律） | 不立（写入 `#14` 头注释「职责边界」段） |
| `FB_DL_TrapSteamFlowEstimate`（疏水阀凝水量估算） | 需阀前压力/阀口径/流量系数，属选型计算而非监视；无现场可验收判据 | 不立 |
| `FC_DL_FieldToLreal`（定宽字段 → 浮点） | 与 `#2` + 平台 `*_TO_*` 组合即可，且定点解析的小数点/千分位口径跨行业不统一，属业务规则 | 不立 |

---

## 4 对源矩阵的记账建议（供收口阶段回写；**本阶段不动矩阵**）

> 依据 M-E5 裁定：**零检索轮不得改 T2/T1 行状态列**（虚账即误导下轮）；本轮 2 件 T0 变体线属零检索，**只回写备注不改 ✔**。

| 矩阵行 | 建议动作 | 回写文案（可直接粘贴） |
|---|---|---|
| **T0-2 定时器** | 备注追加（状态列不动） | 「**R22 变体线扩族 1 件**：`FB_DL_FrequencyMeasure`（门时计数测频：`TON` 门 + `R_TRIG` 计数，低频死区与 `±1/tGateTime` 不确定度显式声明）；**测 ≠ 生**——R21 判「LGF `Frequency` 发生器不立」不覆盖测量侧」 |
| **T0-7 位串操作** | 备注追加（状态列不动） | 「**R22 变体线扩族 1 件**：`FC_DL_FirstSetBit`（位串族第四轴「搜索」：低位/高位优先 + 8/16/32/64 有效位宽 + 常量掩码避 `SHL(x,64)`）；族内轴线现为 读/写/统计/提取/批量/旋转/掩码比较/**搜索** 八条」 |
| **T2-1 LGF · Converter** | 备注追加；**子族级**由「待挖」转 **✔ 收口** | 「**R22 定宽数值字段编解码族 3 件**：`IntToFixedField` / `FixedFieldToInt`（逆运算对，round-trip 验收）/ `LrealToFixedField`（固定小数位定点文本，禁 `LREAL_TO_STRING`）；「数值 → 定宽字段对齐」子族由 R21 的「仍待挖」转 **✔ 收口**；`StringToDTL` 仍待挖（挂编译债）」 |
| **T2-1 LGF · Data Handling** | 备注追加（**不重复记账**） | 「R22 定宽字段族主源记 Converter 行，本行**不重复记账**（同 LGF 组内交叉语义只记一次，R12 先例）」 |
| **T2-1 LGF · Technology** | 备注追加（次源） | 「R22 次源 1 件：`CompressorSurgeGuard` 借「变化率限幅」语义（快开慢关非对称斜率），组合调用 `FB_DL_RateLimiter`；主源记自研线，本行不重复记账」 |
| **T1-6 PLCopen Motion** | 备注追加（◐ 深化，**次源 4 件**） | 「**R22 轴侧安全层开层 4 件**：`AxisBrakeSeq`（`MC_Power` 使能时序纪律）/ `MotionCmdQueue`（`MC_BUFFERMODE` 的 Buffered 语义，Blending 系列**明确不立**）/ `CamTableValidate`（CamTableSelect 前置校验事实）/ `AxisInPosMonitor`（`InPosition`/`Standstill` 输出语义）；四件均为**次源**（借语义不借实现），主源分别记 T2-4 / 自研 | 
| **T2-4 S7 Motion** | 备注追加（次源 2 件） | 「R22 次源 2 件：`AxisBrakeSeq`（工艺对象使能/禁用外部接口组织）、`VirtualMasterAxis`（SynchronousAxis 主值源分型）；主源不重复记账」 |
| **T2-5 Mod_PID_Control** | 备注追加（次源 3 件） | 「R22 次源 3 件（`CrossLimitSelect` / `ExcessAirTrim` / `ColumnDpCtrl`）只借「死区 + 抗饱和 + 双侧钳位」参数域组织；**参数域已被取尽**的结论不变，本轮无新参数面引入」 |
| **T2-7 PackML / OMAC** | 备注追加（次源 1 件） | 「R22 次源 1 件：`InertPurgeSeq` 只借「最小子集 + 明确终止态」命名组织，不作主源；17 态全集属主仍为 `FB_DL_PackMlStateMachine`」 |
| **T2-8 ISA-88 / ISA-18.2 / NE107** | 备注追加（次源 3 件） | 「R22 次源 3 件：`SlitValveInterlock`（互锁语义组织）、`PressureReliefMonitor`（NE107 `eOutOfSpec`/`eMaintenanceReq` 判据原子，引用唯一属主 `E_DL_Ne107Status`）、`BatchTransferSeq`（公开相/步骤语义）；三件状态机/码位/判据 100 % 自有」 |
| **T1-1 OSCAT Basic** | 备注追加（次源 1 件） | 「R22 次源 1 件：`SteamTrapMonitor` 借「域外行为显式化」写法纪律（冷态冻结判定而非塞伪值），未复制任何函数体/函数名/常量名」 |
| **T1-2 OSCAT Building** | 备注追加（次源 1 件） | 「R22 次源 1 件：`LevelRadarValidate` 借同一纪律（域外保持上次有效值 + 掩码标出）；与 R11 `NtcTempScan` 同口径」 |
| **半导体 ESC 自研线** | 备注追加（深化 1 件） | 「R22 深化 1 件：`SlitValveInterlock`（真空侧多门互斥 + 机械臂在位联锁，保守侧默认：反馈矛盾按门未关、真空非法按不足）；ESC 电流/颗粒族仍待挖」 |
| **T1-3 OSCAT Network** | **建议**由 `◐` 改 **`✔` 收口**（需总监在收口阶段签字） | 「RTU 帧长/字节数一致性已由 R19 `FC_DL_ModbusRtuFrameCheck` 收口（四路互校实测）；ASCII 帧 LRC 定位经 R22 判定为**薄件不立**（理由见 `RAW_NOTES_R22.md` §3.2）。**两条待挖项均已闭环，本行可判定收口**」 |
| **T2-1 LGF · Bit Logic** | **不动** | R22 的 `FirstSetBit` 属 T0 零检索变体线，按 M-E5 **不得**记入 LGF 行（否则虚账）；「LWORD 多段一次搬」已由 R18 `FC_DL_BitSegmentBlockMove` 覆盖，R22 不重复立项 |

### 4.1 码位游标交接值勘误（R22 实测，4 处）

| 交接声称 | 实测 | 差 | 处置 |
|---|---|---|---|
| `0001` 信息级用至 `045A` | `045B` | +1 | 本轮起点取 `045C`（实测 +1） |
| `0003` 信息级用至 `0170` | `0171` | +1 | 本轮起点取 `0172` |
| `0004` 信息级用至 `01D3` | `01D4` | +1 | 本轮起点取 `01D5` |
| `0005` 信息级用至 `01D8` | `01D9` | +1 | 本轮起点取 `01DA` |

> **四差同向「+1」的成因推断**：交接值取自**上一轮派单规划时的游标**，而非上一轮**收口后**的实测游标——每轮收口都把规划值用满，故规划游标恒比实际少 1。**建议写入规则**：轮次交接一律给「收口后实测游标」，且必须标注"由 X 脚本实测"；派单前仍须当场复测（R61 铁律）。本轮 20 件 100 槽已用实测值重算，**`CLASH: []`**。

---

## 5 下轮狩猎提示（R23 用，不占本轮）

1. **T2-1 LGF 剩余子族**（均已细到可验收粒度）：① `StringToDTL`（需先闭合 `DTL` 编译债，否则只能挂账）；② 「Counter INT/UDINT 变体」——**建议不立**（与 `SearchMinMaxDint` 同属伪重载，除非能给出「INT 域回绕在 16 位现场设备的真实用例」）；③ Signal Generators「频率发生族」——须先给出与 `FB_DL_PulseGenerator` + `FB_DL_FrequencyMeasure` 的职责边界表，否则重复。
2. **T1-7 PLCnext 剩余**：PROFINET 诊断（`PN_ALARM_DIAG`）族。**立项前必须先查证** ChannelErrorType 解码表的公开性（R19 已用过一次该表），并复核 R10 Q5 教训（PDI ≠ 质量码）。
3. **DL_Motion 下一层缺口**（本轮只开了安全层）：① 轴组插补（三轴以上圆弧/直线组）；② 凸轮**动态修调**（`CamPhaseTrim` 已在，缺「在线改表」）；③ 外部编码器多轴同步。三项均须先给「与 `SingleAxis` 的职责边界表」。
4. **DL_Process 下一层缺口**：① 完整批次模型（Procedure/Unit/Recipe）——R12 已判「须先给与 `RecipeManager` / `BatchPhaseBase` 的职责边界表」方能立；② 报警管理族本体（ISA-18.2 生命周期）。
5. **源已无 ☐ 可开**——后续轮次一律按「◐ 深化」或「新增自研线」记账，矩阵状态列**不得出现新的 ✔**（除非整组挖尽并给出「不再挖」的理由段；本轮 T1-3 的建议收口即按此口径给出）。

---

*RAW_NOTES_R22 ｜ 2026-11-16 23:06 ｜ 2 次检索 / 零代码行入库 / 17 件 T2·T1 关联件全 clean-room / 15 条矩阵回写建议*
