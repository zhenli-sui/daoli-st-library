# 道莅（Daoli）工业自动化标准代码库 — 演进路线图 (ROADMAP)

> **战略总目标**：构建全网规模最大（**≥ 10,000 个高质量组件**）、架构最规范、100% 跨平台兼容（CODESYS / TwinCAT 3 / 汇川等）的 IEC 61131-3 ST 开源代码库，同步沉淀工业级 AI 编程大模型微调数据集（SFT / CoT）。
>   
> **日产吞吐目标**：≥ 200 个独立标准组件 / 天
>   
> **当前库规模**：`186 / 10,000`（Phase 1：首批 100 个核心高频组件，已完成 186 项，达成率 **186%**）｜ 总库版本 **v2.1.0**（INDEX_REGISTRY.json 一致）
> **Level 0 进度**：`DL_Base 38`（20 项规划收口 + R5/R7/R9/R10/R11/R12 补强 18 项 ✅ 收口+扩容）｜ `DL_MathData 38`（20 项规划收口 + R9/R10/R11/R12 回补 18 项 ✅ 收口）（合计 **76**）
> **Level 1 进度**：`DL_Algo 27 ✅ 开库`｜ `DL_Device 44 ✅ 开库`（R5 四件套 + R6 阀门/驱动族 10 + R7 设备件十件套 + R8~R12 扩族）｜ `DL_Motion 17 ✅ 开库`
> **Level 2 进度**：`DL_Process 22 ✅ 开库`（R5 PackML 框架 + R6 焓差/排程 + R7 OEE/输送/配料 + R8 搅拌/CIP + R9 安灯 + R10 拾放 + **R11 压装/分度/AGV 对接/节能四条 P0 待办清零** + **R12 批次相底座 + 温控轮询采集行**）
> **R2 计划（2026-11-14）**：✅ **已完成**。12 项（DL_Base 7 + DL_MathData 5，P0 四件套 ExtendedTimer / AlarmManager / StepSequencer / WatchdogMonitor 全部落地）见 `_Staging_Raw/2026-11-14/ROUND_PLAN_R2.md`，狩猎情报见 `RAW_NOTES_R2.md`，战报见 `BATTLE_REPORT_R2.md`。终审：0 违规、3 处实现级缺陷已修复（DualEdgeTrig / PulseGenerator / StepSequencer 均 → v1.0.1）、8 条偏离全部裁定 PASS。
> **R3 计划（2026-11-14 23:37 → 2026-11-15 00:15）**：✅ **已完成**。14 项（DL_Base 4 + DL_MathData 10），**Level 0 全线收口 40/40**，库版本 v1.1.0 → **v1.2.0**；新增代码 4272 行，7 项红线机检全 0 命中；终审发现并完成**库级缺陷修复**——全库 40 个 POU 补齐 `END_FUNCTION` / `END_FUNCTION_BLOCK` 终结符（详见 `CHANGELOG.md` v1.2.0 Fixed）。本轮为**兜底模式**执行（原生 daoli-library-director / plc-programming-expert 均报 not available，两次尝试 + 身份探测后仍失败）。
> **R4 计划（2026-11-15 01:35 → 02:0x）**：✅ **已完成**。16 项 **DL_Algo 开库**（原计划 15 + 矩阵扩产补充项 RateLimiter），新增代码 4035 行，库版本 v1.2.0 → **v1.3.0**。终审 16/16 PASS，修复缺陷 16 处（其中 **2 处致命**：Integrator / SCurveGenerator 首扫判据反向导致一次跟踪后永久锁死），新范式 **R8 首扫标志唯一合法范式**（正式入册编号 R19~R21，见 `AGENT_EVOLUTION_LOG.md`）。本轮为**兜底模式**执行（原生两位专家两次尝试均 not available）。计划与终审见 `_Staging_Raw/2026-11-15/ROUND_PLAN_R4.md`、`AUDIT_R4.md`，战报见 `BATTLE_REPORT_R4.md`。
> **R5 计划（2026-11-15）**：✅ **已完成（文档线）**。16 项 **三目录开库**（DL_Device 8 + DL_Motion 3 + DL_Process 2 + DL_Base 补强 2 + DL_Algo 补强 1），库版本 v1.3.0 → **v1.4.0**；故障码段位扩展至 `16#0003/0004/0005` 三段（公约 0.7）；R5 收口完成**跨文件去重修复**（`FB_DL_HeatCoolZone` 就地重复声明删除、统一引用正式契约文件）。计划见 `_Staging_Raw/2026-11-15/ROUND_PLAN_R5.md`。本轮为**兜底模式**执行。
> **R6 计划（2026-11-15）**：✅ **已完成**。16 项 **组深化四线并进**（DL_Device 阀门/驱动族 10 + DL_Motion 回零/定位族 3，**T1-6 PLCopen Motion 首次开组** + DL_Process 行业池 9.5 节 P0 两件 + DL_Algo Ramp/Soak 1），新增代码 4,461 行，库版本 v1.4.0 → **v1.5.0**。终审 16/16 PASS（8 个修后 v1.0.1），修复缺陷 6 处（**致命 2**：VacuumEjector/VfdGeneric TP 自清时序同模板；**严重 1**：AxisHomingSeq 三终态死锁；工程语义 2：AnalogValve/EnthalpyCompareCtrl 非有限值穿透；逻辑级 1：StarDeltaMotor 码位归一 `0003_0208`），新范式 **R24「TP/定宽脉冲触发范式」** 入册；故障码族段裁定 Ramp/Soak 独立 `18xx`；D4 裁定（负干球钳位保守性）维持 PASS。本轮为**兜底模式**执行（原生两位专家 2×2 尝试均 not available）。计划与终审见 `_Staging_Raw/2026-11-15/ROUND_PLAN_R6.md`、`AUDIT_R6.md`，狩猎留痕 `RAW_NOTES_R6.md`，战报 `BATTLE_REPORT_R6.md`。
> **R7 计划（2026-11-15）**：✅ **已完成**。16 项 **设备件十件套 + 计数器组开组 + 工艺/运动深化**（DL_Device 扫码枪/安全门/光幕/流量计/料位开关十件套 10 + DL_Base LGF Counter 组 2 + DL_Process OEE/输送线/配料 3 + DL_Motion 软限位 1），新增代码 3,960 行，库版本 v1.5.0 → **v1.6.0**，**Phase 1 达成率 104%（超额收口）**。终审 16/16 PASS（8 个修后 v1.0.1），修复缺陷 14 处（**致命 2**：SerialScanner 重试链断裂、BatchDosing 判稳死锁——R24「单拍标志」家族第二例），新范式 **R25「单拍标志生命周期三律」** 入册（R24 扩展至一切单拍标志）。本轮为**兜底模式**执行（原生两位专家均 not available）。计划与狩猎留痕见 `_Staging_Raw/2026-11-15/ROUND_PLAN_R7.md`、`RAW_NOTES_R7.md`，战报 `BATTLE_REPORT_R7.md`。
> **R8~R10 计划（2026-11-15）**：✅ **均已完成**。三轮各 16 项（R8 同步耦合开族 + 工艺六件；R9 Level 0 六组回补 + 调度抽象 + 步进族 + 安灯；R10 Level 0 三组补强 + 信号发生 + 卷绕工艺 + RFID 与总线诊断 + 拾放工站），收口登记分别见第十二节（R9）、第十四节（R10），战报见同目录 `BATTLE_REPORT_R8~R10.md`。
> **R11 计划（2026-11-15）**：✅ **已完成**。16 项 **工站四件套收口 + 端口诊断深化 + Level 0 年窗/回绕/区间 + 统计三件**（DL_Process 4 + DL_Device 4 + DL_Base 2 + DL_MathData 4 + DL_Algo 1 + DL_Motion 1），新增代码 **6,310 行**，registry 152 → **168**（v1.9.0 → **v2.0.0**），总库 **48,827 行**；**ROADMAP §6 四条 P0 工站待办全部清零**。终审 16/16 PASS（2 件修复后 v1.0.1），缺陷 **4 条（致命 2 / 严重 1 / 轻微 1）**——全部集中在锥度张力件与 NTC 巡检件；同期修复 **7 件存量**（3 处编译阻断族：漏声明 / 变量名笔误 / 枚举成员单冒号 5 行）。新范式 **R33 枚举成员分隔符语法 / R34 状态量生命周期四律 / R35 饱和计数器守卫与判据同向 / R36 跨件调用须手算退出跟踪首拍** 入册。本轮为**兜底模式**执行（原生双专家 2×2 均 not available）。计划与终审见 `_Staging_Raw/2026-11-15/ROUND_PLAN_R11.md`、`FINAL_REVIEW_R11.md`、`AUDIT_R11.md`，狩猎留痕 `RAW_NOTES_R11.md`，战报 `BATTLE_REPORT_R11.md`。
> **R12 计划（2026-11-15）**：✅ **已完成**。18 项 **批量位段补全 + 协议诊断落地 + 参数域校验 + 批次相底座**（DL_Base 4 + DL_MathData 5 + DL_Algo 2 + DL_Device 4 + DL_Motion 1 + DL_Process 2），送审 **5,777 行** → 终审修复后 **5,880 行**（`wc -l` 实测），registry 168 → **186**（v2.0.0 → **v2.1.0**）；六子库连续两轮全部有新增。终审 **PASS with fixes**（A 线「有条件 PASS」+ B 线「PASS with fixes」），缺陷 **15 条（致命 3 ／ 严重 5 ／ 中等 3 ／ 注释级 4）**，10 件升 **v1.0.1**（实扫；派单记 12），规格勘误 13 处；**§16.3 P0 `FB_DL_PortDiagBoard` 与 §13.6 P0 `FB_DL_PollTempBank` 双双清零**。新范式 **R37 定长串截断必须显式置位 / R38 锁存副本与实时镜像量禁同名混用 / R39 停机掉使能分支不得屏蔽故障复位通道 / R40 分段监控定时器必须按段断输入一拍 / R41 恢复相转出判据不得只看已完成量 / R42 跨相取值必须本拍复验数据源 / R43 以保持替代回零时保持值须夹进有效域 / R44 周期核对件信息码按核对周期清除** 八条入册。本轮为**兜底模式**执行（原生 `daoli-library-director` / `plc-programming-expert` 各召唤 2 次含探测重试，均 not available）。计划与终审见 `_Staging_Raw/2026-11-15/ROUND_PLAN_R12.md`、`FINAL_REVIEW_R12_A.md`、`FINAL_REVIEW_R12_B.md`，狩猎留痕 `RAW_NOTES_R12.md`，战报 `BATTLE_REPORT_R12.md`。

---

## 📊 依赖层级与构建优先级说明

- **Level 0 (`DL_Base`, `DL_MathData`)**：零外部依赖，仅基于纯 IEC 61131-3 标准指令与 `Standard.library`，必须最先构建。
- **Level 1 (`DL_Algo`, `DL_Device`, `DL_Motion`)**：仅允许依赖 Level 0，封装核心控制算法、设备 OOP 接口与运动控制状态机。
- **Level 2 (`DL_Process`)**：通过 `INTERFACE`（`I_DL_*`）依赖注入调用 Level 1 组件，实现彻底解耦的行业工艺与产线调度模板。

---

## 一、 [Level 0] `DL_Base` — 基础逻辑、时序与系统诊断库（Phase 1 20 项收口 + R5 补强 2 项 + R7 计数器组 2 项 + R9 六组回补 5 项 + R10 位段/日历/计数 3 项 + R11 年窗/回绕 2 项 + R12 跨字位段/区间 4 项 = 38）

> 优先级：**P0（最高，所有上层库的基石）**

- [x] `FB_DL_SignalDebounce`：双边沿可调时间输入信号数字滤波防抖功能块（支持独立上升/下降延时）
- [x] `FB_DL_PulseGenerator`：可调占空比与频率的精密方波脉冲发生器（支持外部使能与相位复位）
- [x] `FB_DL_DualEdgeTrig`：双边沿检测增强功能块（单块同时输出上升沿 `bRising`、下降沿 `bFalling` 及任意跳变 `bChanged`）
- [x] `FB_DL_ExtendedTimer`：多功能工业定时器（支持通电延时 TON、断电延时 TOF、脉冲 TP、保持型累加计时 RTO 模式切换）
- [x] `FB_DL_WatchdogMonitor`：外部心跳信号看门狗监控块（用于检测上位机/HMI/从站通信掉线超时）
- [x] `FB_DL_CycleTimeMeasure`：PLC 任务真实扫描周期与最大/最小/平均执行耗时统计功能块（微秒级精度）
- [x] `FB_DL_RuntimeMeter`：设备累计运行时间（小时/分钟/秒）与启停次数统计器（支持断电保持参数映射与保养到期预警）
- [x] `FB_DL_StepSequencer`：通用工业顺控状态机管理基类（内置步序超时监控、单步暂停、步序跳转与故障锁存）
- [x] `FC_DL_BitGet`：提取 `DWORD` / `LWORD` 指定位状态的防越界安全函数（位索引范围自动保护）
- [x] `FC_DL_BitSet`：设置或清除 `DWORD` / `LWORD` 指定位的安全纯函数
- [x] `FC_DL_BitCount`：统计 32 位/64 位字中为 `TRUE` 的激活位总数（Hamming Weight 算法，用于多传感器投票表决）
- [x] `FC_DL_PackBitsToWord`：将 16 个离散 `BOOL` 状态信号打包为标准工业报警字 `WORD`
- [x] `FB_DL_UnpackWordToBits`：将通信接收的状态字 `WORD` 解包为 16 个独立 `BOOL` 信号
- [x] `FB_DL_AlarmManager`：多通道工业报警优先级仲裁器（区分停机级故障、警告级提示与首出故障 First-Out 锁存）
- [x] `FB_DL_TwoHandSafety`：双手安全启动按钮同步性校验功能块（IEC 60204 标准，要求双按钮在 500ms 内同时按下）
- [x] `FB_DL_InterlockMatrix`：多条件安全联锁汇总与首因追踪器（自动锁定导致停机的第一个联锁条件编号）
- [x] `FB_DL_RedundantSwitch`：双传感器/双执行器主备冗余无扰动切换控制器（支持故障自动切换与手动强制切换）
- [x] `FB_DL_DutyStandbyRotation`：多泵/多风机轮值均衡运行调度器（按累计运行时间自动分配主备机启动顺序）
- [x] `FC_DL_GrayToBinary`：绝对值编码器格雷码（Gray Code）转标准二进制无符号整数函数
- [x] `FC_DL_BinaryToGray`：标准二进制无符号整数转格雷码函数

---

## 二、 [Level 0] `DL_MathData` — 数学运算、数据结构与协议解析库 (20 项收口 + R9 六件回补 + R10 数学族 3 件 + R11 区间/几何/随机/分位 4 件 + R12 字符串/数组比对/太阳位置/异常帧 5 件 = 38)

> 优先级：**P0（最高，数据处理与算法支撑）**

- [x] `FC_DL_LinearScale`：模拟量工程量线性标定函数（含除零保护与可选上下限钳位 Clamping）
- [x] `FC_DL_Deadband`：带死区抑制的信号处理函数（消除传感器零点微弱漂移抖动）
- [x] `FC_DL_Hysteresis`：带施密特触发器迟滞回差的比较器函数（防止临界阈值附近继电器高频振荡）
- [x] `FC_DL_MultiPointLinear`：多段折线查表线性插值函数（用于非线性传感器如热电偶、异形液位罐标定，支持二分查找）
- [x] `FC_DL_PolygonArea`：平面多边形面积与质心坐标计算函数（视觉定位与物料尺寸校验）
- [x] `FC_DL_LineIntersection`：二维平面两直线交点坐标计算函数（含平行线除零防御）
- [x] `FC_DL_SwapBytes16`：16 位无符号整数大小端字节序交换（Big-Endian / Little-Endian 转换）
- [x] `FC_DL_SwapBytes32`：32 位整数/浮点数 4 种工业字节序（ABCD / DCBA / BADC / CDAB）通用转换函数
- [x] `FC_DL_Crc16Modbus`：标准 Modbus RTU CRC-16 校验码计算纯函数（支持查表法/计算法）
- [x] `FC_DL_Crc32Ethernet`：标准 IEEE 802.3 CRC-32 数据完整性校验函数
- [x] `FC_DL_LrcChecksum`：Modbus ASCII 纵向冗余校验（LRC）计算函数
- [x] `FB_DL_RingBufferLReal`：定长环形队列（FIFO 循环缓冲区），支持压入、弹出、窥视（Peek）及清空操作
- [x] `FB_DL_LifoStack`：后进先出堆栈（LIFO）数据结构功能块（适用于缓存库位与路径回溯）
- [x] `FB_DL_MovingAverage`：高效滑动窗口算术平均滤波器（O(1) 复杂度递推实现，不随窗口增大增加扫描耗时）
- [x] `FB_DL_MedianFilter`：中值滤波器功能块（专用于剔除模拟量采集中的脉冲毛刺/尖峰干扰）
- [x] `FB_DL_SignalStatistics`：采样数据流实时统计分析器（输出窗口内最大值、最小值、均值、方差与标准差）
- [x] `FC_DL_QuickSortLReal`：定长浮点数数组原地快速排序函数（内置防栈溢出递归深度保护）
- [x] `FC_DL_StringTrim`：字符串首尾空白字符（空格、制表符、回车换行）清理函数
- [x] `FC_DL_StringSplit`：按指定分隔符拆分工业通信报文（如 CSV / 扫码枪 / 视觉结果字符串解析）
- [x] `FC_DL_HexStringToBytes`：十六进制 ASCII 字符串（如 `"1A2B3C"`）转字节数组解析函数

---

## 三、 [Level 1] `DL_Algo` — 工业控制算法与过程控制库（16 项收口 + R5 补强 1 项 + R8 峰值/分级 2 项 + R10 信号发生与工艺算法 4 项 + R11 R2R 微调 1 项 + R12 水焓值/阀特性 2 项 = 27）

> 优先级：**P1（核心技术壁垒模块）**
> **R4 开库说明**：原规划 15 项；Round 04 按源矩阵扩产规则（T2-1 LGF Technology 组 LimRateOfChange 语义）追加补充项 `FB_DL_RateLimiter`，并入本清单，实际 16/16 全部落地收口。

- [x] `FB_DL_PidController`：工业级增量/位置式离散 PID 控制器（含积分分离、抗积分饱和 Anti-Windup、微分先行及手自动无扰动切换）
- [x] `FB_DL_CascadePid`：双闭环串级 PID 控制器（适用于高精度温控、张力控制与压力流量串级调节）
- [x] `FB_DL_LowPassFilter`：离散一阶低通数字滤波器（支持初始化无滞后跟踪与运行中时间常数动态调节）
- [x] `FB_DL_SecondOrderFilter`：二阶巴特沃斯（Butterworth）低通数字滤波器（更陡峭的高频噪声衰减特性）
- [x] `FB_DL_HighPassFilter`：离散一阶高通滤波器（用于提取信号动态变化分量与振动监测）
- [x] `FB_DL_RampGenerator`：线性斜坡发生器（设定值平滑升降速控制，支持独立上升/下降斜率与暂停保持）
- [x] `FB_DL_SCurveGenerator`：七段式 S 型平滑加减速轨迹规划器（限制加加速度 Jerk，消除柔性机械冲击）
- [x] `FB_DL_PwmDutyController`：时间比例慢速 PWM 输出控制器（适用于固态继电器 SSR 加热炉功率调节）
- [x] `FB_DL_SplitRangeControl`：分程控制算法块（单 PID 输出自动分配至加热阀与冷却阀双执行机构）
- [x] `FB_DL_FeedforwardComp`：前馈补偿器（结合一阶惯性与纯滞后环节，提升抗负载扰动响应速度）
- [x] `FB_DL_SmithPredictor`：史密斯预估器（专用于长管道传输、大滞后热工对象的纯滞后补偿控制）
- [x] `FB_DL_Integrator`：梯形法高精度离散积分器（支持上下限限幅、外部复位与保持，用于流量累计与速度积分）
- [x] `FB_DL_Differentiator`：带低通滤波的实用微分器（计算物理量变化率 dX/dt，抑制高频测量噪声放大）
- [x] `FC_DL_DewPointCalc`：基于 Magnus-Tetens 公式的温湿度露点温度计算函数（适用于洁净室/干燥房环控）
- [x] `FC_DL_FlowCompensate`：气体/蒸汽流量温压补偿计算函数（将工况体积流量转换为标准状态 Nm³/h 流量）
- [x] `FB_DL_RateLimiter`：变化率限制器（R4 矩阵扩产补充项，源自 T2-1 LGF Technology 组 LimRateOfChange 语义；上升/下降速率独立，0=该方向不限速直通，保护执行器免受给定值阶跃冲击）
- [x] `FB_DL_PeakDetector`：峰值/谷值时域极值跟踪与保持（衰减率 + 双阈值事件 + 更新计数，与 `FB_DL_SignalStatistics` 的窗口统计量职责分离）（R8 立项，T2-1 LGF Math 组统计-峰值族深化）
- [x] `FB_DL_StepController`：分级步进控制器（偏差 → 级数 + 双向迟滞 + 最小驻留 + 均衡轮换，支持多级加热组累积输出与多台泵/机组单级互斥输出）（R8 立项，T2-2 LBP `CtrlStp` 语义 clean-room）

---

## 四、 [Level 1] `DL_Device` — 标准物理设备 OOP 抽象接口与驱动库 (规划 18 项起步，R6~R12 扩至 44 项已交付，余电表 1 项待办)

> 优先级：**P1（OOP 面向对象核心资产，含 `I_DL_*` 接口与 `FB_DL_*` 实现）**

- [x] `I_DL_Cylinder` & `FB_DL_PneumaticCylinder`：双电控磁性开关气缸标准接口与状态机驱动实现
- [x] `FB_DL_SingleSolenoidCyl`：单电控弹簧复位气缸驱动实现（实现同一 `I_DL_Cylinder` 接口，支持无传感器纯时间模式）（R6）
- [x] `I_DL_VacuumGenerator` & `FB_DL_VacuumEjector`：真空吸盘发生器标准接口与驱动（含真空建立超时、破真空吹气脉冲与负压表反馈校验）（R6）
- [x] `I_DL_MotorDriver` & `FB_DL_DolMotor`：直接启动工频电机驱动器（含接触器反馈校验、热继电器过载报警与防频繁启停保护）
- [x] `FB_DL_StarDeltaMotor`：星三角降压启动电机控制功能块（内置星角切换安全死区时间互锁）（R6）
- [x] `I_DL_VfdDrive` & `FB_DL_VfdGeneric`：通用变频器标准抽象接口与控制块（支持频率设定、正反转、点动、多段速与故障代码映射）（R6）
- [x] `I_DL_ProportionalValve` & `FB_DL_AnalogValve`：模拟量比例阀/调节阀驱动器（含阀位反馈偏差报警与零点死区补偿）（R6）
- [x] `I_DL_MotorizedValve` & `FB_DL_ThreePointValve`：三点浮点式电动调节阀控制器（自动积分估算当前开度百分比）（R6）
- [x] `I_DL_AnalogSensor` & `FB_DL_AnalogTransmitter`：工业 4~~20mA / 0~~10V 变送器通用封装（集成量程标定、滤波、高高/高/低/低低四级报警及断线/超量程硬件诊断）
- [x] `I_DL_TemperatureZone` & `FB_DL_HeatCoolZone`：标准温控区域对象（集成热电偶滤波、PID 加热/冷却调节、SSR 驱动与断偶保护）
- [x] `I_DL_StepperOpenLoop` & `FB_DL_PulseDirStepper`：脉冲+方向型开环步进电机控制器（内置加减速脉冲规划与限位开关保护）（R9，T1-8 GitHub topics 开组 stepper 线；梯形加减速短行程退化三角型 + 堵转超时判据；v1.0.1 修复减速段残差死锁致命缺陷）
- [x] `I_DL_TowerLight` & `FB_DL_SignalTower`：三色/四色工业安灯塔（红/黄/绿/蓝 + 蜂鸣器）多状态闪烁模式驱动器
- [x] `I_DL_BarcodeScanner` & `FB_DL_SerialScanner`：固定式工业扫码枪异步触发与超时重试封装接口（R7，T1-5 TcOpen 开组；SerialScanner v1.0.1 修复重试链断裂致命缺陷）
- [x] `I_DL_SafetyDoor` & `FB_DL_GuardLockDoor`：带电磁锁扣的安全门联锁控制器（R7；ISO 14119 语义 clean-room，遵循“先请求停机 -> 确认安全静止 -> 解锁开门”时序）
- [x] `I_DL_LightCurtain` & `FB_DL_SafetyLightCurtain`：安全光幕监控与屏蔽（Muting）时序控制器（R7；2/4 传感器序列式屏蔽，v1.0.1 修复反向判向死代码）
- [x] `I_DL_FlowMeter` & `FB_DL_PulseFlowMeter`：脉冲型流量计瞬时流量与累计总量计量功能块（R7；总量脉冲计数法双缓冲无撕裂）
- [x] `I_DL_PowerMeter` & `FB_DL_ModbusPowerMeter`：三相智能电表电能质量与能耗统计抽象数据模型（**R13 交付**；契约 12 属性 + 3 方法，`E_DL_Ne107Status` 健康语言；实现块四字序 32 位电能拼装 + 需量窗 + PF 复算交叉校验 + 全零表失联判定；998 行，v1.0.1 修复 PF 失配锁存无清零点 A3-D1）
- [x] `I_DL_RfidReader` & `FB_DL_RfidTagHandler`：载具 RFID 读写头状态机接口与防重复读取防抖控制（R10，T2-6 Rockwell AOI 开组：参数四分段 → 方法/只读属性/诊断结构/局部；契约 `I_DL_RfidReader` + 实现 `FB_DL_RfidTagHandler`）

---

## 五、 [Level 1] `DL_Motion` — 运动控制 OOP 封装库 (规划 12 项起步，R6~R12 扩至 17 项已交付，其中张力件登记于 §7.1)

> 优先级：**P1（基于 PLCopen Motion Control 标准规范）**

- [x] `I_DL_MotionAxis` & `FB_DL_SingleAxis`：标准单轴运动控制器（封装 `MC_Power`, `MC_MoveAbsolute`, `MC_Stop`, `MC_Reset` 及位置容差校验）
- [x] `FB_DL_AxisRelativeMove`：单轴相对定位（`MC_MoveRelative`）与连续累加步进控制扩展块（R6）
- [x] `FB_DL_AxisVelocityMove`：单轴速度模式（`MC_MoveVelocity`）与动态变速控制封装（R6）
- [x] `FB_DL_AxisJogController`：点动与寸动（Jog / Inch）手动调试控制器（支持低速点动自动切换高速点动及软限位拦截）
- [x] `FB_DL_AxisHomingSeq`：标准工业回零序列控制器（支持限位开关回零、原点开关回零、Z相脉冲精定位及扭矩堵转回零模式）（R6，T1-6 PLCopen Motion 首次开组）
- [x] `FB_DL_ElectronicGear`：电子齿轮同步控制封装（封装 `MC_GearIn` / `MC_GearOut`，支持动态传动比平滑切换）
- [x] `FB_DL_ElectronicCam`：电子凸轮主从同步控制器（封装 `MC_CamTableSelect` / `MC_CamIn`，支持飞剪与追剪同步相位补偿）
- [x] `FB_DL_GantrySyncAxis`：双驱龙门同步轴控制与偏斜保护器（实时监控主从轴位置跟随误差，超差立即双轴硬急停）
- [x] `FB_DL_TorqueLimitControl`：伺服力矩限制与压装到位检测控制器（结合位置窗口与扭矩阈值判断压装合格性）
- [x] `FB_DL_SuperimposedMove`：运动叠加补偿控制器（封装 `MC_MoveSuperimposed`，用于视觉纠偏动态微调）（R9，T2-4 S7-1500 Motion 叠加语义；偏移指令限速斜坡削顶平移不跳变）
- [x] `FC_DL_CalcMoveTime`：梯形速度曲线点到点定位理论耗时估算函数（用于产线节拍仿真）
- [x] `FB_DL_SoftLimitGuard`：软限位安全电子围栏预判器（根据当前速度与减速度实时计算制动距离，提前拦截超程指令）（R7，T1-6 PLCopen 深化；v1.0.1）
- [x] `FB_DL_MarkPositionLatch`：外部标记（色标/探针/光电）位置锁存器（触发沿锁存位置与速度 + 与上次锁存的增量 + 布防窗与缺失诊断 + 历史环形缓冲，飞剪切点校正与定长计米的数据源）（R8 立项，T1-6 PLCopen 相位补偿前置件）

> **R8 已评估不采纳（留档防重复立项）**：① 位置跟随误差监视块——驱动器/NC（V90 `p2546`、S120、TO `FollowingError.Tolerance`）已内置且门限随速度线性放大，本库接口无「指令位置」属性，PLC 侧实现只能得伪量；轴间偏差已由 `FB_DL_GantrySyncAxis` 覆盖。② 纯函数版卷径估算——行业池已有 `FB_DL_UnwinderDiameterCalc`（层数积分）与 `FB_DL_WindingTraverse`（卷径 + 排线）两条更完整待办，且卷径依赖轴角速度属运动侧状态量，留 R9 在 DL_Motion 统一落地。详见 `_Staging_Raw/2026-11-15/RAW_NOTES_R8.md` S-5 / S-12。

---

## 六、 [Level 2] `DL_Process` — 行业工艺与通用工站架构模板库 (18 项已交付，待办 0 项；子库合计 22 项，另 4 项登记于 §8 / §9.5 / 第十二节)

> 优先级：**P2（通过 `I_DL_*` 接口依赖注入组装，打造行业旗舰影响力）**

- [x] `FB_DL_PackMlStateMachine`：完整符合 **ISA-88 / OMAC PackML** 国际标准的包装与自动化产线状态机框架（涵盖 `Stopped`, `Idle`, `Starting`, `Execute`, `Holding`, `Held`, `Suspending`, `Aborted` 等全 17 种标准状态跃迁）
- [x] `FB_DL_OeeCalculator`：设备综合效率（OEE = 时间开动率 × 性能开动率 × 合格品率）实时统计与班次报表引擎（R7，直接消费 PackML 根因位；v1.0.1）
- [x] `FB_DL_ConveyorZone`：单段皮带/滚筒输送线控制器（支持上游要料、下游防堵料积放 Accumulation 逻辑与超时卡料报警）（R7，消费 I_DL_VfdDrive；v1.0.1）
- [x] `FB_DL_ConveyorLineLink`：多段输送线级联握手协调器（实现标准 SMEMA / 工业上下游握手信号解耦）
- [x] `FB_DL_PickAndPlaceStation`：标准三轴/气动拾放（Pick & Place）上下料工站面向对象模板（注入 `I_DL_MotionAxis` 与 `I_DL_VacuumGenerator`）（R10，PackML/OMAC 工站 7 态最小子集 + 执行态内九步序；v1.0.1 修复 D-01 致命——CASE 漏 `eExecute` 标签被 ELSE 兜底锁故障）
- [x] `FB_DL_RotaryIndexTable`：多工位凸轮分割器/直驱转盘调度框架（管理工位映射表、分度到位联锁与空跑清洗模式）（**R11 交付**，DL_Process；五态最小子集 + 工位掩码逐位构位规避 64 位移位 + `nI` 钳 1~24；404 行）
- [x] `FB_DL_RecipeManager`：通用多品种生产配方管理器（支持配方校验、切换防呆、参数边界合法性检查及变更审计记录）
- [x] `FB_DL_BatchDosingControl`：多原料自动配料称重控制器（支持快加/慢加双速控制、落差提前量（In-Flight）自动学习修正）（R7，ISA-88 批次相语义；v1.0.1 修复判稳死锁致命缺陷）
- [x] `FB_DL_CipCleaningSeq`：食品/制药/锂电行业标准 **CIP 原位清洗**顺控工艺模板（酸洗 -> 水洗 -> 碱洗 -> 终洗电导率与温度闭环）
- [x] `FB_DL_LeakTestStation`：气密性差压检漏测试工站模板（充气 -> 稳压 -> 保压测试 -> 压降泄漏率计算 -> 排气与 OK/NG 判定）
- [x] `FB_DL_PressFitStation`：伺服精密压装工艺控制模板（支持包络线窗口监控、位移-压力曲线特征点提取与合格判定）（**R11 交付**，DL_Process；八态 + 包络二分插值 + 四特征点（接触/屈服/峰值/终点）+ 五 NG 原因位；580 行）
- [x] `FB_DL_BufferMagazine`：多层料仓/弹夹（Magazine）升降存取调度器（自动追踪各层料槽状态：空/满/已加工/NG）
- [x] `FB_DL_AgvDockingHandshake`：产线工站与移动机器人（AGV/AMR）自动对接物料交接状态机模板（**R11 交付**，DL_Process；七态 + 到位/交接双超时窗 + 提前完成 02E3 直判故障；385 行）
- [x] `FB_DL_AndonCallSystem`：车间安灯（Andon）呼叫与响应时间统计模块（缺料、品质异常、设备维修分级上报）（R9，T2-7/8 OMAC 安灯族；四级优先仲裁 + 多源重锁 + 未应答解除不计入应答统计）
- [x] `FB_DL_EnergySavingMode`：产线空闲智能节能模式管理器（无料超时自动降低气源压力、关闭加热保温及休眠空闲伺服）（**R11 交付**，DL_Process；五态 + 三出口（气压/保温/伺服）先清后置无锁存残留 + 唤醒门限带容差；400 行）
- [x] `FB_DL_MixRecipeControl`：混合/搅拌工艺相控制器（ISA-88 单相语义：投料就绪 → 定速/正反交替搅拌 → 时间或扭矩上升终点判据 → 出料许可 → 停转；扭矩超限保护 + 转速建立确认 + 出料超时诊断，消费 `I_DL_VfdDrive`）（R8 立项，LBP 实测无混合组后改走 ISA-88 相语义，见 RAW_NOTES_R8 S-9）

---

## 🔄 自我进化与批处理追踪记录（由 WorkBuddy 自动维护）

- **R13 已完成**（2026-11-16）：18 件收口（DL_Device 6 + DL_Base 2 + DL_MathData 4 + DL_Algo 1 + DL_Motion 1 + DL_Process 4），**7,949 行**（`wc -l` 实测），registry 186 → **204**（v2.1.0 → **v2.2.0**）；终审 **18/18 PASS**（8 件升 v1.0.1；缺陷 16 条记录：中等 8 / 中高 1 / 提示 4 / 文档级 1，A4-D2 判断项裁定保留；规格侧勘误 4 处）；泳道 B 六件经总监 Python **独立验算**逐位复现（CRC 逐位 / 位旋转 3000 组对拍 / 矩阵 500 组对拍）；机检 16 条规则全 PASS；JSONL 同步 204 条、全量 sha256 204/204 一致；池子扩容 **30 条**（总 356）。本轮为**专家召唤兜底模式**执行。收口登记见第二十节，池子见第二十一节。
- **下一批重点（Round 14）**：① **R39 规则豁免机制改进**——本轮机检产生 3 处误报（复位判据文本先于前置块 / 无故障态件被按有故障态口径检查），需在**规则层**区分「CASE 前置改状态」与「CASE 前置复位通道/参数锁存」「契约件无故障态」两类合法形态，**不为变绿而硬改代码语义**（R13 三份终审报告均已留痕误报样本，供规则层取证）；② **P0 编译验证第十三次提醒**——本机无 CODESYS / TwinCAT 环境，替代验证方案（机检 + 逐拍推演 + 关键字配平 + 泳道 B 独立数值验算）已按 R12 承诺落文档，风险清单持续挂账：空 `ELSIF` 分支、`LOWER_BOUND/UPPER_BOUND` 在汇川 InoProShop 的可用性、`STRING(16)` 属性在 TwinCAT 的接口实现一致性；③ **候选组件方向**——行业池 R13 扩容 30 条中 **P1 十七条**为首批候选（主线：时序台账族 / 本体健康族二批 / 真空与气氛族 / 趋势终点族），另优先承接 R13 观察项（需量时间加权口径开关、行列式溢出信息码、`E_DL_Ne107Status` 实现块仲裁件）。
- **R12 已完成**（2026-11-15）：18 件收口（DL_Base 4 + DL_MathData 5 + DL_Algo 2 + DL_Device 4 + DL_Motion 1 + DL_Process 2），送审 **5,777 行** → 修后 **5,880 行**（`wc -l` 实测），registry 168 → **186**（v2.0.0 → **v2.1.0**）；终审 **PASS with fixes**（缺陷 15 条：致命 3 / 严重 5 / 中等 3 / 注释级 4；**10 件升 v1.0.1**〔实扫，派单记 12〕；规格勘误 13 处）；新范式 **R37 定长串截断必须显式置位 / R38 锁存副本与实时镜像量禁同名混用 / R39 停机掉使能分支不得屏蔽故障复位通道 / R40 分段监控定时器必须按段断输入一拍 / R41 恢复相转出判据不得只看已完成量 / R42 跨相取值必须本拍复验数据源 / R43 以保持替代回零时保持值须夹进有效域 / R44 周期核对件信息码按核对周期清除** 八条入册；**§13.6 与 §16.3 两条 P0 双双清零（行业池 P0 待办降为零）**；本轮为**专家召唤兜底模式**执行（原生双专家各 2 次含探测重试均 not available）。收口登记见第十八节，今日累计 **160 / 200（80.0%）**。
- **R11 已完成**（2026-11-15）：16 件收口（DL_Process 4 + DL_Device 4 + DL_Base 2 + DL_MathData 4 + DL_Algo 1 + DL_Motion 1），新增 **6,310 行**，registry 152 → **168**（v1.9.0 → **v2.0.0**），总库 **48,827 行**；同期修复 **7 件存量**（3 处编译阻断族）；终审 **16/16 PASS**（2 件修复后 v1.0.1，缺陷 4 条：致命 2 / 严重 1 / 轻微 1；全库机检 168/168 PASS、硬缺陷 0）；新范式 **R33 枚举成员分隔符语法 / R34 状态量生命周期四律 / R35 饱和计数器守卫与判据同向 / R36 跨件调用须手算退出跟踪首拍** 入册；**§6 四条 P0 工站待办清零**；本轮为**专家召唤兜底模式**执行（原生双专家 2×2 均 not available）。收口登记见第十七节，今日累计 **142 / 200（71.0%）**。
- **R10 已完成**（2026-11-15）：16 件收口（DL_Base 3 + DL_MathData 3 + DL_Algo 4 + DL_Device 4 + DL_Motion 1 + DL_Process 1），送审 5,385 行 → 修后 **5,528 行**，registry 136 → **152**（v1.8.0 → **v1.9.0**）；终审 **PASS with fixes**（缺陷 17 条：致命 2 ／ 严重 3 ／ 中等 6 ／ 注释级 6；8 件升 v1.0.1）；新范式 **R31 枚举→CASE 双向映射完备性 / R32 内部状态量写入点全拍排序审计** 入册；T1-7 PLCnext 与 T2-6 Rockwell AOI **双源同时开组**；本轮为**专家召唤兜底模式**执行。收口登记见第十四节，今日累计 **126 / 200（63.0%）**。
- **R9 已完成**（2026-11-15）：16 件收口（Level 0 六组回补 11 + 步进族 2 + 叠加运动 1 + Modbus 调度抽象 1 + 安灯仲裁 1），新增 5,051 行，registry 120 → **136**（v1.7.0 → **v1.8.0**）；终审 **PASS with fixes**（缺陷 13 条：致命 2 ／ 严重 8 ／ 轻微 3；码位改判 6 件 15 处，修后跨文件重叠 = 0）；新范式 **R28 注释不可嵌套 / R29 赋值目标声明性检查 / R30 码位自证循环禁令** 入册；本轮为**专家召唤兜底模式**执行。收口登记见第十二节。
- **批处理进度**：**已完成 204 / 100 首批（204% 超额）**（2026-11-16 ｜ Round 01~13 ｜ Level 0 **82**（`DL_Base` 40 + `DL_MathData` 42）｜ Level 1 `DL_Algo` **28** ｜ `DL_Device` **50** ｜ `DL_Motion` **18** ｜ Level 2 `DL_Process` **26**）。R13 后 `DL_Device` 电表契约件收尾完成（§4 全勾）；六子库既有待办仅余历史池，新增需求全部走行业方向待办池。
- **下一批重点（Round 13）**：**P0 编译验证第十二次提醒、升级为「交付资格项」**——连续十二轮静态全过后 R12 再出 3 条致命（隐式截断丢字段 / 分段定时器跨段累加 / 跨相取值不复验）+ 5 条严重，R13 起手式固定为 CODESYS V3.5 SP19 最小工程导入全库 **186** 个 POU 真实编译 + 本轮 6 条修复件的验收向量逐拍回放（必含 `BatchPhaseBase` 的「3 步 × 30 s / 超时 60 s」与 `StringReplaceAll` 的 V5 超长两路）；若环境仍不可得，须输出「替代验证方案 + 无法替代的风险清单」，并在 `README` / `LIBRARY_MANUAL` 显著位置标注「未经编译验证」。**P0 边界向量强制集**：每件至少四类向量——域外早退（含 NaN/Inf）／上限截断（R37）／跨段跨相时序（R40/R42）／恢复复位首拍（R41/R43），缺任一类不放行。**P1 机检四项增强**：定长串回夹检测（R37）／镜像量双重来源扫描（R38）／`CASE` 前置无条件状态改写检测（R39）／`TON` 的 `IN` 跨段恒真检测（R40）。**P1 规格整改**：A 线 E-1/E-2 与 B 线 E-05/E-10 四条落规格模板；`BitArrayExtract/Insert` 的「给 `VAR_INPUT` 直接赋值」可移植性风险全库排查。**P2 立项**：`DL_Device` 电表契约件（`I_DL_PowerMeter` + `FB_DL_ModbusPowerMeter`，数据模型已由 `FB_DL_EnergyMeterAccum` 跑通）；行业池 R12 扩容 31 条中 **P1 十四条**为首批候选（首选 `ValveStictionDetect` / `ChamberSeasoningTrack` / `CapperTorqueTrend` / `AhuDamperStuckDiag` / `EscHeLeakCheck`）；吞吐目标 **18~20 件/轮**。
- **吞吐缺口**：2026-11-15 今日 **160 / 200**，**达成率 80.0%**，缺口 40。R7~R11 连续五轮 16 项/轮、R12 升至 18 项/轮（+12.5%）；若维持 18 件/轮，R13 一轮（178）仍需两轮才能摸到日目标，实际需「18 + 22」的两轮组合。瓶颈排序不变：「真实编译验证缺失（P0，第十二次提醒，已升交付资格项）」＞「规格自身数值可行性核算（本轮 13 处勘误，其中 3 处规格算法本身出错）」＞「手册双语文档」。
- **AI 训练集同步状态**：每合入 1 个 `.st` 组件，同步在 `_AI_Training_Dataset\daoli_st_sft_dataset.jsonl` 生成 1 条高质量微调语料。当前累计 **204 条**，与索引 204 条、文件 204 个三方一致（INDEX_REGISTRY.json total=204, version 2.2.0）；R13 新增 18 条按终审修复后的 v1.0.1 源码注入（8 件升版件均在后注入），存量再同步 20 条（点名 2 件升版件 + 历史注释级漂移 18 件），全量 sha256 逐件比对 204/204 一致（脚本口径：bytes 级注入 → encode 回比）。
- **最近一轮复盘**：见 `AGENT_EVOLUTION_LOG.md` Round 12（R37~R44 八范式入册 + LGF 组内三层粒度在数组批量位段上的验证 / Data Handling 与 Converter 的分类学分界 / Comparator 开闭区间升级为枚举成员 / 天文钟借参数域不借公式 / OSCAT 诊断帧独立成族 / Forge 许可不明的最严处置 / GitHub topics 社区共识写法判定）；本轮战报 `BATTLE_REPORT_R12.md`、终审 `FINAL_REVIEW_R12_A.md` / `_B.md`、播报 `DAILY_STATS_R12.md` 已落盘 `_Staging_Raw/2026-11-15/`。

---

## 七、行业方向待办池 / Industry Backlog Pool（103 项基础池 + R5 扩容 32 项 + R6 扩容 32 项 + R7 扩容 32 项（见第十一节）+ R9 扩容 32 项（见第十三节）+ R10 扩容 32 项（见第十五节）+ R11 扩容 32 项（见第十六节）+ R12 扩容 31 项（见第十九节）= 326 项；不计入 Phase 1 的 100 项配额）

> **产品经理确认**：Round 04 起待办充足——未勾选的 Phase 1 项 **44 项** + 本草稿池 **103 项** = **147 项**候选，远超「≥30 个」的门槛。
> 本草稿池解决的是**行业语汇缺失**问题：现有 Phase 1 未勾选项偏「通用机电」，缺锂电、光伏、半导体、包装、暖通、过程控制这些高毛利行业的专用语汇。这些行业客户的采购决策往往由「有没有我这个行业的东西」触发，而不是由组件数量触发。
> v1.2.0（R3 批次）起待办池在既有 36 条基础上扩容 **34 条**，六个行业各补 5~6 条，全部不与已有条目重名。
> v1.3.0（R4 批次）待办池再扩容 **33 条**（总 103 条）：本轮 DL_Algo 开库后重读矩阵第 2 节，发现 Level 1 的 `DL_Device` / `DL_Motion` 尚未开库，行业池里「工艺层（DL_Process）」条目偏重而「设备层/运动层」底座条目不足——R4 新增条目刻意向 `DL_Device` / `DL_Motion` / 依赖 R4 新算法族的 `DL_Process` 缺口倾斜（如卷径估算、真空计融合、防喘振、三冲量给水等），让每条行业待办立项时都能直接挂上已收口的 Level 0/1 能力。
> 归入 `DL_Process`（Level 2）或 `DL_Device`（Level 1），立项时按分层归属重新判定。

### 7.1 锂电 / Lithium Battery（18 项）

- [x] `FB_DL_WindingTensionCtrl`：卷绕张力闭环（张力摆辊 + 锥度张力曲线），依赖 `FB_DL_PidController`（**R11 交付**，DL_Motion；锥度乘子 → 摆辊修正 → 输出限幅三层 + 降级开环；v1.0.1 修复 2 处致命（跟踪计数只置不销、跟踪窗过程值取真实反馈）+ 1 处严重（02D1 判据与饱和封顶反向）；598 行）
- [x] `FB_DL_CoatingThicknessCtrl`：涂布面密度闭环（β 射线/红外测厚反馈 + 模头调节） ✅ R29
- [x] `FB_DL_FormationChannelMgr`：化成/分容柜多通道调度与工步编排（通道级配方、异常通道隔离） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_StackingAlignCtrl`：叠片对位（CCD 偏差 → 纠偏轴，含超差 NG 判据） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_DryingOvenZone`：烘箱多温区串级控温（含风量联动与超温联锁） ✅ R29
- [x] `FB_DL_TabWeldingMonitor`：极耳焊接过程监控（能量/位移/压力包络窗口判定）
- [x `FB_DL_ElectrolyteFillCtrl`：注液量闭环（称重罐减量法 + 静置浸润计时）→ `DL_Process`
- [x] `FB_DL_StakingPressCtrl`：预压/全压两段压芯控制（压力-位移包络窗口判定）→ `DL_Process`
- [x] `FB_DL_BatteryTestCycler`：充放电循环工步机（CC/CV/恒流放电切换与容量统计）→ `DL_Process` ｜ **R25 落地 v1.0.1**
- [x] `FB_DL_LaserWeldPowerSeq`：激光焊接功率斜坡序列（预焊-满焊-收弧三段配方）→ `DL_Process`
- [x] `FB_DL_OcvGradingBin`：OCV 分档机（电压/内阻双判据落料调度）→ `DL_Process`
- [x] `FB_DL_PouchVacuumSeal`：软包封装真空袋封口顺控（真空度-温度-压力联锁）→ `DL_Process`
- [x] `FB_DL_RollerGapAdjust`：涂布模头/辊距电动缸间隙伺服微调（面密度反馈联动，依赖 `I_DL_Cylinder`）→ `DL_Device`（**R11 交付**；五态 + 背隙两阶段逼近（阶段 A 预留背隙 / 保持段补偿）+ 上下限倒置自动换位；410 行）
- [x] `FB_DL_SlurryStirrerCtrl`：浆料搅拌双电机同步与扭矩监视（粘度趋势判据，依赖 `FB_DL_Differentiator`）→ `DL_Device`
- [x] `FB_DL_CalenderRollPress`：辊压压力-位移包络窗口（伺服压辊两段压装，复用 `FB_DL_StepSequencer`）→ `DL_Process`
- [x] `FB_DL_CellFeederVacuum`：电芯真空吸盘上料工站模板（注入 `I_DL_VacuumGenerator` 与 `I_DL_Cylinder`）→ `DL_Process`
- [x] `FB_DL_WindingTraverse`：收卷卷径实时估算与横动排线（卷径 → 线速度前馈，梯形积分）→ `DL_Motion`（R10，主源 T2-1 LGF Technology、次源 T2-4；v1.0.1 修复 D-02 致命——待机分支每拍清零方向量致排线位移恒 0）
- [x] `FB_DL_NtcTempScan`：电芯 NTC 多通道温度巡检（通道轮询、超温排序报警，复用 `FB_DL_AlarmManager`）→ `DL_Device`（**R11 交付**；1~16 路一块覆盖 + B 值方程三步守卫 + 断线/短路保持上次温度并进掩码；v1.0.1 补全扫圈数饱和守卫；476 行）

### 7.2 光伏 / Photovoltaics（17 项）

- [x] `FB_DL_StringIVTrace`：组串 IV 曲线扫描与特征点提取（Voc / Isc / Pmax / FF） ｜ **R25 收口补勾（R24 已落地、此前漏勾）**
- [x] `FB_DL_ElTestStation`：EL 检测工站（相机触发、缺陷坐标映射、OK/NG 归档）
- [x] `FB_DL_LaminatorTempProfile`：层压机温区曲线跟随（多段升温/保温/降温配方）
- [x] `FB_DL_CellSortingBin`：电池片分选落料（效率/色差分档 + 料仓满溢调度）
- [x] `FB_DL_TrackerSolarAngle`：跟踪支架太阳角计算（时角/赤纬，含逆跟踪防阴影）
- [x] `FB_DL_InverterGridSync`：并网逆变器同步检查（电压/频率/相序窗判定，仅监视不控） ｜ **R25 落地 v1.0.0**
- [x `FB_DL_HjtPvdSeq`：PVD 镀膜腔体顺控（本底真空-基片预热-工艺-取片联锁）→ `DL_Process`
- [x] `FB_DL_ScreenPrintAlign`：丝网印刷对位与印刷压力补偿（相机偏差 → 工作台纠偏）→ `DL_Process` ✅ R29
- [x] `FB_DL_FiringFurnaceZone`：烧结炉多温区峰值温度跟随（与链速联动）→ `DL_Process`
- [x] `FB_DL_PlatingCurrentCtrl`：电镀槽位电流密度闭环与液位联锁（镀铜设备）→ `DL_Process`
- [x] `FB_DL_ModuleLamVacuumSeq`：组件层压真空顺控（抽气-加热-加压-放气四段曲线）→ `DL_Process`
- [x] `FB_DL_StringSolderQuality`：串焊焊接质量在线判据（红外温度曲线 + 拉力抽检窗口）→ `DL_Process`
- [x `FB_DL_LaminatorPressCtrl`：层压机压力-时间闭环（真空段/加压段分离，复用 `FB_DL_CascadePid`）→ `DL_Process`
- [x] `FB_DL_TrackerWindStow`：跟踪支架大风保护收拢（风速阈值 → 安全角度，含风速趋势判据）→ `DL_Process`
- [x] `FB_DL_StringCutAlign`：串焊裁切对位（相机偏差 → 切割轴微调，依赖 `I_DL_MotionAxis`）→ `DL_Motion` ✔R27
- [x] `FB_DL_PottingDispenseCtrl`：接线盒灌胶定量（称重减量法 + 双组份混合比闭环）→ `DL_Process`
- [x] `FB_DL_FurnaceBeltTension`：烧结炉网带张力与跑偏监视（摆辊张力闭环 + 边缘纠偏）→ `DL_Device` ✅ R29

### 7.3 半导体 / Semiconductor（17 项）

- [x] `FB_DL_VacuumChamberSeq`：真空腔体抽气/放气顺控（粗抽→精抽→检漏→放气，含真空度联锁）
- [x] `FB_DL_MfcFlowCtrl`：质量流量控制器（MFC）设定与回读校验（含斜率与超调判据）
- [x] `FB_DL_CleanRoomPressure`：洁净室正压梯级控制（多房间压差联动，防倒流）
- [x] `FB_DL_WaferMapping`：晶圆盒片位映射（Mapping 传感器序列解析与错片识别） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_EfEmoInterlock`：EFEM 机械手互锁矩阵（门/阀/真空/位置四类条件）
- [x] `FB_DL_ParticleCounterStat`：尘埃粒子计数统计（分级报警与趋势判定） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_R2rEwmaTuner`：Run-to-Run 工艺参数 EWMA 自动微调（指数加权移动平均）→ `DL_Algo`（**R11 交付**；λ 双向钳位 + 非有限回默认（1F01）+ 修正量限幅（1F03）+ `LIMIT` 保证参数域；389 行）
- [x] `FB_DL_ChamberLeakRate`：腔体升压率检漏（压升法漏率计算与判定）→ `DL_Process`
- [x] `FB_DL_RfReflectedMonitor`：射频电源功率/反射比监视与匹配器联动告警（仅监视）→ `DL_Process`
- [x] `FB_DL_SlitValveInterlock`（R22 已落地）：真空闸阀/传输门互锁矩阵扩展（真空侧多门互斥）→ `DL_Device`
- [x] `FB_DL_WaferHandoffSeq`：晶圆传输机械手交接时序（双机械手防碰撞握手）→ `DL_Device`
- [x] `FB_DL_ChillerTempStab`：冷却水温度稳定性监视（均值/标准差趋势，PID 整定用）→ `DL_Process` ｜ ✅ R26 落地（2026-11-17）
- [x] `FB_DL_CvdTempRamp`：CVD/扩散炉多段升温曲线跟随（Ramp/Soak 曲线 + 均匀性判据，复用 `FB_DL_RampSoakProfile`）→ `DL_Process`
- [x] `FB_DL_LoadPortSeq`：LoadPort 载具对接与 Wafer Map 校验顺控（FOUP 开合、片位映射比对）→ `DL_Process` ✔R27
- [x] `FB_DL_VacuumGaugeMux`：多量程真空计选择与读数融合（皮拉尼/电容膜片自动切换与交叉校验）→ `DL_Device`（**R12 交付**；四态 + 十倍程交叉校验 + 迟滞切换 + 融合发布前**本拍复验取值表可用性**；412 行，v1.0.1 修复跨相失效 B-D02）
- [x] `FB_DL_ChamberPurgeDry`：腔体干燥吹扫顺控（露点判据收敛，复用 `FC_DL_DewPointCalc`）→ `DL_Process`
- [x] `FB_DL_EtchEndpointTrend`：刻蚀终点趋势检测（变化率检测，复用 `FB_DL_Differentiator`）→ `DL_Process`

### 7.4 包装 / Packaging（16 项）

- [x] `FB_DL_FilmTensionDancer`：包装膜张力摆辊控制（放卷/收卷双工位切换）
- [x] `FB_DL_HeatSealProfile`：热封温度-压力-时间三参数曲线管理（配方化）
- [x] `FB_DL_CartonErectSeq`：开箱机顺控（吸箱→成型→折底→输送，含卡箱检测）
- [x] `FB_DL_LabelApplySync`：贴标同步（编码器跟随 + 出标提前量补偿） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_WeightCheckReject`：称重剔除（动态称重滤波 + 剔除确认反馈） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_CasePackerPattern`：装箱排列模式管理（多规格排列矩阵与抓取序列生成） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_FillWeightCtrl`：灌装净重闭环（快/细灌两段 + 落差提前量自动学习）→ `DL_Process` ✔R27
- [x] `FB_DL_VffsBagLength`：立式制袋充填机袋长控制（色标同步 + 切刀相位对齐）→ `DL_Process`
- [x] `FB_DL_ShrinkTunnelCtrl`：热收缩炉温区与网速联动（收缩膜工艺窗口）→ `DL_Process`
- [x] `FB_DL_SealIntegrityMonitor`：外包装封口完整性监视（温度/压力/时间三参数趋势判定）→ `DL_Device` ✔R27
- [x] `FB_DL_PalletizerLayerSeq`：码垛机层排布序列（多规格层模式与夹手取放编排）→ `DL_Process` ｜ **R25 收口补勾（双处登记合并 / R24 已落地）**
- [x] `FB_DL_UnwinderDiameterCalc`：放卷卷径实时估算（膜厚层数积分递推，张力前馈数据源）→ `DL_Motion` ✔R27
- [x] `FB_DL_SplicerAutoJoint`：自动接膜顺控（旧卷余量预警 → 新卷预加速 → 裁切切换零停机）→ `DL_Process` ｜ **R25 落地 v1.0.1**
- [x] `FB_DL_DateCoderSync`：喷码/打码同步（编码器分频 + 字符间距偏移补偿）→ `DL_Device` ✔R27
- [x] `FB_DL_MachineGuardAudit`：防护门开启审计与批次锁定（PackML Holding/Held 联动，复用 `FB_DL_AlarmManager`）→ `DL_Process`
- [x] `FB_DL_RollChangeoverSeq`：换卷换规格一键切换顺控（张力回零 + 参数配方合法性校验，复用 `FB_DL_RecipeManager`）→ `DL_Process`

### 7.5 暖通 / HVAC（16 项）

- [x] `FB_DL_AhuEconomizer`：空调箱新风经济器（焓值比较 + 混风阀联动）
- [x] `FB_DL_ChillerSeqMgr`：冷水机组群控（加减机序列、轮值均衡、防频繁启停） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_VavBoxCtrl`：变风量末端（风量闭环 + 最小新风位限制） ｜ **R25 落地 v1.0.1**
- [x] `FB_DL_HeatPumpDefrost`：热泵除霜判据（温差/时长/环境温度三条件） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_DuctStaticReset`：风管静压重置（最不利末端阀位反馈 → 风机频率） ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_CoolingTowerOpt`：冷却塔群控与逼近度优化（湿球逼近度优先）
- [x] `FB_DL_DewpointReset`：露点重置控制（依据露点重置冷冻水温度设定）→ `DL_Process` ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_FanPressureTrim`：风机变频静压微调（最不利末端阀位比例积分修正）→ `DL_Process`
- [x] `FB_DL_TerminalReheatSeq`：末端再热联锁（最小风量 + 再热极限级联）→ `DL_Process`
- [x] `FB_DL_PumpChangeoverSeq`：冷冻/冷却水泵加减机与温差优化（一次泵变流量）→ `DL_Process` ✔R27
- [x] `FB_DL_HumidityOverride`：除湿优先模式仲裁（湿度超限时覆盖温度控制优先级）→ `DL_Process`（**R23 交付**）
- [x] `FB_DL_FrostProtectFreeze`：防冻保护（低温断路器联动新风阀/盘管阀，复用 `FB_DL_Hysteresis`）→ `DL_Device` ✔R27
- [x] `FB_DL_ChillerApproachTrend`：冷机逼近度趋势诊断（复用 `FB_DL_SignalStatistics`，性能衰减预警）→ `DL_Process`
- [x] `FB_DL_VavDischargeAirReset`：送风温度重置（末端阀位加权平均 → 送风设定值）→ `DL_Process`
- [x] `FB_DL_HydronicDeltaTGuard`：水系统大/小温差失衡诊断（复用 `FB_DL_Differentiator`，旁通与失衡判据）→ `DL_Process`
- [x] `FB_DL_FanArrayStageCtrl`：风机阵列分级启停（N+1 冗余、轮值均衡，复用 `FB_DL_DutyStandbyRotation`）→ `DL_Device` ✔R27

### 7.6 过程控制 / Process（19 项）

- [x] `FB_DL_TankLevelCtrl`：储罐液位双泵控制（交替轮值 + 高高/低低联锁）
- [x] `FB_DL_HeatExchangerCtrl`：换热器出口温度串级（蒸汽阀 + 凝水阀分程） ✅ R29
- [x] `FB_DL_FlowTotalizer`：流量累积与批控（瞬时→累积，批次切换零点）
- [x] `FB_DL_ValveCharacteristic`：调节阀流量特性补偿（等百分比/线性切换）→ `DL_Algo`（**R12 交付**；三特性反解 + 可调比/死区钳位 + 三态；308 行，v1.0.1 改「保持上次阀位并夹进有效行程」修复突跳 B-D05）
- [x] `FB_DL_ReactorStepCtrl`：反应釜工步控制（升温/保温/滴加/冷却，含超温超压）
- [x] `FB_DL_UtilitiesLoadMgr`：公用工程负荷分配（多台空压机/冷冻机按需投切）
- [x] `FB_DL_BatchPhaseBase`：批次反应相结构基类（ISA-88 相/步骤抽象，动作外置）→ `DL_Process`（**R12 交付**；11 态相模型 + 五级命令优先不排队 + 暂停在步骤边界 + 恢复不重头 + 相净运行时间；530 行，v1.0.1 修复单步超时跨步累加 B-D01）
- [x] `FB_DL_InertPurgeSeq`（R22 已落地）：容器氮气置换顺控（O₂ 含量降到目标值判据）→ `DL_Process`
- [x] `FB_DL_SteamTrapMonitor`（R22 已落地）：疏水阀状态监视（温度差判据，仅诊断不联锁）→ `DL_Device`
- [x] `FB_DL_BatchTransferSeq`（R22 已落地）：批次物料转移顺控（泵-阀序列与管道排空验证）→ `DL_Process`
- [x] `FB_DL_AnalyzerSampleSeq`：在线分析仪取样顺控（取样-吹扫-标定三态轮换）→ `DL_Process`
- [x] `FB_DL_ColumnDpCtrl`（R22 已落地）：精馏塔压差控制（ΔP 定值调节回流/再沸）→ `DL_Process`
- [x] `FB_DL_PressureReliefMonitor`（R22 已落地）：泄压/安全阀状态监视（前后压差判据 + 动作记录，复用 `FB_DL_AlarmManager`）→ `DL_Device`
- [x] `FB_DL_SteamHeaderSplit`：蒸汽母管多支路分程分配（复用 `FB_DL_SplitRangeControl`，按支路优先级映射）→ `DL_Process`
- [x] `FB_DL_LevelRadarValidate`（R22 已落地）：雷达液位计回波质量校验（置信度 + 挂料/泡沫判据）→ `DL_Device`
- [x] `FB_DL_CompressorSurgeGuard`（R22 已落地）：压缩机防喘振（最小流量线 + 放空阀快开，复用 `FB_DL_RateLimiter`）→ `DL_Process`
- [x] `FB_DL_BoilerThreeElement`：锅炉三冲量给水控制（汽包水位/蒸汽流量/给水流量，主回路 + 双前馈）→ `DL_Process`（**R23 交付**）
- [x] `FB_DL_HydrostaticLevelComp`：静压式液位介质密度补偿（温度 → 密度修正，复用 `FC_DL_MultiPointLinear`）→ `DL_Process`

### 7.7 池子运营规则

1. **不进 Phase 1 的 100 项配额**：Phase 1 只做跨行业通用的 Level 0/1 基础件，行业模板在其后按客户订单拉动。
2. **立项前置条件**：必须有一个真实客户场景（OEM 或终端厂）能提供验收判据，否则只是「看起来有用」。
3. **复用优先**：行业模板只允许编排 Level 0/1 已有能力，不得内联实现 PID、滤波、字节序等底层逻辑（`LIBRARY_MANUAL.md` 第一节硬规则 2）。

---

## 八、R5 新增（Round 05 补强件，2026-11-15，ROADMAP 既有清单无对应条目，收口登记于此）

- [x] `FB_DL_PackMlCmdDecoder`（DL_Process）：PackML 标准命令解码器（十个离散命令源 + 可选命令字入口，R_TRIG + 最小脉宽单发化，同拍多命令冲突位全丢弃，职责单一不做跃迁判断）
- [x] `FC_DL_DayOfWeekCalc`（DL_Base）：年月日 → 星期几换算原子函数（ISO-8601 序周一=1，Sakamoto/蔡勒 clean-room，闰年 4/100/400 判定，越界返回 eInvalid）
- [x] `FB_DL_TimeWindowCheck`（DL_Base）：每日时间窗判定功能块（支持跨零点窗、24h 全开语义、星期使能表 ISO 序、窗口开/闭沿单发；时刻注入禁读 CPU 钟）
- [x] `FC_DL_HumidAirEnthalpy`（DL_Algo）
- [x] `FB_DL_RampSoakProfile`（DL_Algo）：多段 Ramp/Soak 程序曲线发生器（1..16 段，段目标+斜坡+保温三数组，段切换沿/暂停/跳段/循环/中途跟踪无扰重启；温控区设定源，烘箱/烧结炉/化成工步共用；R6 按 R5 先例登记于此，故障码归独立 `18xx` 族段）

---

## 九、行业方向待办池 R5 扩容 / Industry Backlog Pool R5 Expansion（+32 项，总 103 → 135 项，不计入 Phase 1 的 100 项配额）

> **产品经理确认（R5 文档线）**：R5 三目录开库后，`DL_Device` / `DL_Motion` / `DL_Process` 底座已通，行业池里原本「无底座可挂」的条目现在全部可立项。本轮扩容 **32 条**（总 103 → **135 条**），六行业各 5~6 条，全部不与既有 103 条重名；每条标注**拟入目录**与**优先级**（P0=下一轮候选 / P1=1~2 轮内 / P2=观察池），并注明可复用的已收口 Level 0/1 能力。
> 立项前置条件与复用优先规则沿用 7.7 节池子运营规则；行业模板只允许编排 Level 0/1 已有能力，不得内联实现底层逻辑。

### 9.1 锂电 / Lithium Battery（+6 项）

- [x] `FB_DL_ElectrolyteTankLevel`：电解液储罐液位与氮封联锁（液位双限 + 微正压监视，复用 `I_DL_AnalogSensor` 四级报警）→ **DL_Device** ｜ **P1** ｜ ✅ R26 落地（2026-11-17）
- [x] `FB_DL_NailMachineSeq`：极耳裁切/模切机顺控（放卷-裁切-收料节拍链，复用 `FB_DL_StepSequencer` + `I_DL_Cylinder`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_SocketPressTrend`：电芯入壳压装压力-位移趋势监视（复用 `FB_DL_SignalStatistics`，超差预警）→ **DL_Motion** ｜ **P2** ✅ R29
- [x] `FB_DL_TrayerNestingCtrl`：电芯托盘堆叠嵌套调度（层数/列数/NG 通道避让，复用 `FB_DL_LifoStack`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_OvenDoorInterlock`：烘箱炉门-氮气-温区三联锁（先氮气置换后开门，复用 `FB_DL_InterlockMatrix`）→ **DL_Device** ｜ **P1**（**R23 交付**）
- [x] `FB_DL_CoinCellAssembler`：扣电组装工位模板（叠片-压紧-封口，注入 `I_DL_Cylinder` + `I_DL_TemperatureZone`）→ **DL_Process** ｜ **P2**

### 9.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_StringerTrend`：串焊机焊接温度曲线在线监视（多通道趋势 + 峰值窗口，复用 `FB_DL_SignalStatistics` + `FB_DL_AlarmManager`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_TrackerBacktrackCalc`：跟踪支架逆跟踪角度修正计算（阵列阴影几何，纯函数）→ **DL_Motion** ｜ **P2** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_LamCtrlDualZone` ✔ R28 入库：层压机上下腔真空差压协调控制（双腔独立抽速 + 差压保护，复用 `FB_DL_CascadePid`）→ **DL_Device** ｜ **P1**
- [x] `FB_DL_QuarterCellCutSeq`：半片/叠瓦裁切顺控（激光-吸附-裁切时序，复用 `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_DustFreehoodPress`：洁净风帽正压梯度监视（多房间压差排序报警，复用 `FC_DL_Hysteresis`）→ **DL_Device** ｜ **P2** ｜ ✅ R26 落地（2026-11-17）

### 9.3 半导体 / Semiconductor（+6 项）

- [x] `FB_DL_RfMatcherTune`：射频匹配器自动调谐顺控（反射比最小化步进搜索，复用 `FB_DL_Differentiator`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_CoolantLoopBal`：机台冷却水多支路流量均衡（支路阀位 PI 均衡，复用 `FB_DL_PidController`）→ **DL_Device** ｜ **P1** ✅ R29
- [x] `FB_DL_WaferCountAxis`：晶圆计数轴（编码器分频 + 片位同步，复用 `I_DL_MotionAxis`）→ **DL_Motion** ｜ **P1**（**R23 交付**）
- [x] `FB_DL_VentPurgeDuty`：尾气处理单元轮值切换（双塔吸附切换 + 穿透预警，复用 `FB_DL_DutyStandbyRotation`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_AmcMonitorStat`：气态分子污染物（AMC）在线统计分级（复用 `FB_DL_SignalStatistics` + `FB_DL_AlarmManager`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_RobotGripVerify`：机械手夹持确认与掉片判据（真空/夹爪双反馈与置位校验，复用 `I_DL_Cylinder`）→ **DL_Device** ｜ **P1**（**R23 交付**）

### 9.4 包装 / Packaging（+5 项）

- [x] `FB_DL_TrapSealTrend`：枕式包装机封口温度随线速重置（线速前馈 + PID 重置，复用 `FB_DL_PidController`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_BagFeedDancerSync`：制袋供膜摆辊同步（摆辊位置 + 线速前馈，复用 `FB_DL_FeedforwardComp`）→ **DL_Motion** ｜ **P1**（**R23 交付**）
- [x `FB_DL_CartonDenestPush`：纸箱分离-推箱顺控（料仓分离 + 推杆节拍，复用 `I_DL_Cylinder` + `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_InlineCheckweighGauge` ✔ R28 入库：在线称重 SPG 判据（动态称重窗口 + 标准差控制图，复用 `FB_DL_SignalStatistics`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_FilmSpliceTensionHold`：接膜瞬间张力保持（张力双回路无扰交接，复用 `FB_DL_RedundantSwitch` 思想 + `I_DL_AnalogSensor`）→ **DL_Motion** ｜ **P2** ✅ R29

### 9.5 暖通 / HVAC（+5 项）

- [x] `FB_DL_EnthalpyCompareCtrl`：焓差比较控制执行块（直接消费 `FC_DL_HumidAirEnthalpy` 焓值：新风/回风焓差 → 新风阀位）→ **DL_Process** ｜ **P0**（本轮焓值组件的直接上层消费者，链路闭环示范）✅ **R6 已交付**
- [x] `FB_DL_ChillerStagingCurve` ✔ R28 入库：冷机加减机效率曲线选点（部分负荷率排序，复用 `FC_DL_MultiPointLinear`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_CoilFreezeStat`：盘管防冻统计判据（低温时长累积 + 趋势，复用 `FB_DL_Integrator` + `FC_DL_Hysteresis`）→ **DL_Device** ｜ **P1** ✅ R29
- [x] `FB_DL_BypassValveTrim`：旁通阀压差微调（供回水压差 PI，复用 `FB_DL_PidController`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_OccScheduleWindow`：多时区作息窗排程（每块每日窗矩阵组合，复用 `FB_DL_TimeWindowCheck` + `FC_DL_DayOfWeekCalc`）→ **DL_Process** ｜ **P0**（本轮日历/时间窗两件的直接上层消费者，链路闭环示范）✅ **R6 已交付**

### 9.6 过程控制 / Process Control（+5 项）

- [x] `FB_DL_SteamCondensatePot`：凝液罐液位-排放顺控（液位双限 + 排水阀间歇，复用 `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P1**（**R23 交付**）
- [x] `FB_DL_AirCompDutyN2`：空压机/制氮机组联产轮值（负荷排序 + 优先级投切，复用 `FB_DL_DutyStandbyRotation`）→ **DL_Process** ｜ **P1**（**R23 交付**）
- [x] `FB_DL_FilterDpMonitor`：过滤器压差寿命监视（压差趋势 + 滤芯更换预警，复用 `FB_DL_SignalStatistics`）→ **DL_Device** ｜ **P1**（**R23 交付**）
- [x] `FB_DL_DosingPumpCalib`：计量泵标定与脉冲当量校验（标定量程 + 反向校验，复用 `FC_DL_LinearScale`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_TankN2BlanketCtrl`：储罐氮封压力双分程控制（低压补氮/高压泄放，复用 `FB_DL_SplitRangeControl` + `FB_DL_PidController`）→ **DL_Device** ｜ **P1**：湿空气比焓计算函数（Magnus-Tetens 饱和蒸汽压 + 含湿量 + 焓公式链，对标 OSCAT Building AIR_ENTHALPY / PsychroLib 语义，大气压引脚注入非魔法数）（**R23 交付**）

---

## 十、行业方向待办池 R6 扩容 / Industry Backlog Pool R6 Expansion（+32 项，总 135 → 167 项，不计入 Phase 1 的 100 项配额）

> **产品经理确认（R6 文档线）**：R6 阀门三分法/变频器/回零族落地后，行业池里「驱动执行层无标准件可挂」的条目全部解锁（焓差经济器/作息排程两条 P0 已示范消费链路）。本轮扩容 **32 条**（总 135 → **167 条**），六行业各 5~6 条，全部不与既有 135 条重名；每条标注**拟入目录**与**优先级**（P0=下一轮候选 / P1=1~2 轮内 / P2=观察池），并注明可复用的已收口 Level 0/1 能力。
> 立项前置条件与复用优先规则沿用 7.7 节池子运营规则；行业模板只允许编排 Level 0/1 已有能力，不得内联实现底层逻辑。

### 10.1 锂电 / Lithium Battery（+6 项）

- [x] `FB_DL_PileClampCtrl`：堆叠压紧板压力-位移两段控制（预压/全压，复用 `FB_DL_StepSequencer` + `I_DL_Cylinder`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_OcvProbeDock`：OCV 探针台对接下压与接触校验（压力窗 + 接触电阻判据，复用 `I_DL_Cylinder`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_ElectrolyteDosingSeq`：电解液定量注液顺控（抽液-称重-注液-静置节拍链，复用 `FB_DL_StepSequencer` + `FB_DL_Integrator`）→ **DL_Process** ｜ **P1**（**R23 交付**）
- [x] `FB_DL_GloveBoxAtmoCtrl`：手套箱气氛联锁（水氧含量越限禁开门，复用 `FB_DL_InterlockMatrix`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_ModulePottingVac`：模组灌胶真空脱泡顺控（抽真空-灌注-保压-释放，复用 `I_DL_VacuumGenerator`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_PackHousingTighten`：Pack 箱体螺栓拧紧轴序管理（对角顺序 + 扭矩窗口，复用 `FB_DL_StepSequencer` + `I_DL_MotionAxis`）→ **DL_Process** ｜ **P2**

### 10.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_LamHeaterZoneSync`：层压机加热板多温区同步跟随（区差阈值 + 链速联动，复用 `FB_DL_RampSoakProfile`）→ **DL_Process** ｜ **P1**（**R23 交付**）
- [x] `FB_DL_FramingPressSeq`：装框机压装顺控（涂胶-组框-压合节拍，复用 `FB_DL_StepSequencer` + `I_DL_Cylinder`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_TrayLoadVacuum`：电池片花篮真空取放（破真空吹气定宽脉冲，复用 `I_DL_VacuumGenerator`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_InvInsulTestSeq`：逆变器绝缘测试顺控（加压-保持-泄放联锁，复用 `FB_DL_InterlockMatrix`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_TrackerMotDiag`：跟踪支架回转减速机诊断（电流/位置跟随误差趋势，复用 `FB_DL_SignalStatistics` + `I_DL_MotionAxis`）→ **DL_Motion** ｜ **P2** ✅ R29

### 10.3 半导体 / Semiconductor（+6 项）

- [x] `FB_DL_ChamberGateValve`（既有件：11-17 roadmap-p1 泳道已注册实现，R35 撞名报备跳过重写）：腔体闸阀双位置互锁驱动（开/关到位双反馈 + 抽气侧联锁，复用 `I_DL_MotorizedValve`）→ **DL_Device** ｜ **P1**
- [x] `FB_DL_ForelinePressureCtrl`：前级管路压力稳定（调节阀位 PI，复用 `FB_DL_PidController` + `FB_DL_AnalogValve`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_WaferCoolChuck`：静电卡盘吸附-温控联锁（吸附确认后允许温控投运，复用 `I_DL_VacuumGenerator` + `I_DL_TemperatureZone`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_ProcessKitTimer`：腔体部件保养计时器（累计工艺拍数/时长双口径，复用 `FB_DL_RuntimeMeter`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_CassetteMapVerify`：花篮片位映射比对校验（Mapping 序列解析 + 错片定位，复用 `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_ExhaustDpTrend`：尾气管路压差趋势监视（堵塞预警，复用 `FB_DL_SignalStatistics`）→ **DL_Device** ｜ **P2**

### 10.4 包装 / Packaging（+5 项）

- [x] `FB_DL_VacCupRingCtrl`（R19 收口）：多吸盘吸盘组分档拾放（独立通道吸附确认 + 分档释放，复用 `I_DL_VacuumGenerator` 多实例）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_FilmWebCenter`（R19 收口）：膜卷纠偏（边缘传感器 → 纠偏辊位置环，复用 `FB_DL_PidController` + `I_DL_MotionAxis`）→ **DL_Motion** ｜ **P1**
- [x] `FB_DL_CupFillDenest`：杯装灌装机取杯-灌装-封口节拍链（复用 `FB_DL_StepSequencer` + `I_DL_Cylinder`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_CaseSealTapeMonitor`：封箱胶带缺料/断带监视（张力 + 光电双判据，复用 `FB_DL_SignalDebounce`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_PalletGripperSafe`：码垛夹手区域安全互锁（夹爪压力 + 区域扫描双条件，复用 `FB_DL_InterlockMatrix`）→ **DL_Process** ｜ **P2**

### 10.5 暖通 / HVAC（+5 项）

- [x] `FB_DL_AhuFilterDpBank`：空调箱过滤段压差分级报警与更换预警（复用 `FB_DL_SignalStatistics`）→ **DL_Device** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x `FB_DL_RadiatorZoneValve`：散热器末端温控阀脉冲控制（三点浮点阀典型消费场景，复用 `FB_DL_ThreePointValve`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_HumidifierAdiabat`：绝热加湿器补水顺控（水位双限 + 排水周期，复用 `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_ChillerCondReset`：冷机冷凝温度重置（冷却塔出水温度跟随，复用 `FC_DL_MultiPointLinear`）→ **DL_Process** ｜ **P2**
- [x `FB_DL_DoorInterlockHvac`：机房门禁-风机联锁（开门降频/停机恢复策略，复用 `FB_DL_Hysteresis`）→ **DL_Device** ｜ **P2**

### 10.6 过程控制 / Process Control（+5 项）

- [x] `FB_DL_DrumLevelThreeElem`（R19 收口）：汽包水位三冲量轻量版（单泵场合，复用 `FB_DL_FeedforwardComp` + `FB_DL_PidController`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_PigLauncherSeq`：清管器收发球筒顺控（发球-跟踪-接收联锁，复用 `FB_DL_StepSequencer` + `FB_DL_InterlockMatrix`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_SampleLoopPurge`：分析取样环快速回路吹扫（切换阀序列 + 吹扫计时，复用 `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_PumpDryRunGuard`：泵干转保护（功率/流量双判据 + 最短运行时间，复用 `FB_DL_DutyStandbyRotation` 范式）→ **DL_Device** ｜ **P1**
- [x] `FB_DL_TankBlanketPrCtrl`：储罐氮封压差监测联动（复用 `FB_DL_RedundantSwitch` 双表冗余判据）→ **DL_Device** ｜ **P2**

> **扩容统计**：R6 扩容 32 条（锂电 6 / 光伏 5 / 半导体 6 / 包装 5 / 暖通 5 / 过程控制 5），全部不与既有 135 条重名；`DL_Device` 10 条（受益于 R6 阀门/变频/真空契约）、`DL_Motion` 2 条、`DL_Process` 20 条——行业模板层已成为池子主体，与「Level 2 全解锁」的底座状态一致。

---

## 十一、行业方向待办池 R7 扩容 / Industry Backlog Pool R7 Expansion（+32 项，总 167 → 199 项，不计入 Phase 1 的 100 项配额）

> **产品经理确认（R7 文档线）**：R7 设备件十件套（扫码枪/安全门/光幕/流量计/料位开关）+ 配料称重 + 输送积放 + 软限位围栏落地后，行业池里「识别/安全/计量/给料类工艺无标准件可挂」的条目全部解锁。本轮扩容 **32 条**（总 167 → **199 条**），六行业各 5~6 条，全部不与既有 167 条重名；每条标注**拟入目录**与**优先级**（P0=下一轮候选 / P1=1~2 轮内 / P2=观察池），并注明可复用的已收口 Level 0/1 能力。含**终审立项 2 条 P2**（安全门 eUnlocked 保持超时 tUnlockHold、ConveyorZone 停机方向失配独立窗）。
> 立项前置条件与复用优先规则沿用 7.7 节池子运营规则；行业模板只允许编排 Level 0/1 已有能力，不得内联实现底层逻辑。

### 11.1 锂电 / Lithium Battery（+6 项）

- [x] `FB_DL_BinderFeederSeq`：Binders/绝缘件振动盘供料顺控（满料/缺料双光电 + 卡料窗，复用 `FB_DL_StepSequencer` + `FB_DL_LevelSwitchVib`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_ElectrolyteDosingTrend`：注液量趋势 SPG 判据（多批次重量差统计，复用 `FB_DL_SignalStatistics` + `FB_DL_BatchDosingControl` 结算值）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_SafetyDoorAuditBank`：化成柜多安全门审计汇总（开门次数/批次锁定，复用 `FB_DL_GuardLockDoor` 的 `uOpenCount`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_TrackBarcodeTrace`：托盘条码路由追溯（扫码枪契约 + 分道判据，复用 `I_DL_BarcodeScanner`）→ **DL_Process** ｜ **P0**
- [x] `FB_DL_CellVolumeCheck`：电芯厚度/体积激光测距校验（超差分档，复用 `I_DL_AnalogSensor` NE43 诊断）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_NgBinDosing`：NG 料返投称重定量（复用 `FB_DL_BatchDosingControl` 单料相 + 学习禁用组态）→ **DL_Process** ｜ **P2**

### 11.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_StringBarcodeTrace`：电池串条码绑定与工位路由（复用 `I_DL_BarcodeScanner` + `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P0**
- [x] `FB_DL_LamDoorInterlock`：层压机炉门-真空-温度三联锁（复用 `FB_DL_GuardLockDoor` 解锁时序 + `FB_DL_InterlockMatrix`）→ **DL_Device** ｜ **P1**
- [x] `FB_DL_GlassFeederAccum`：玻璃上料输送积放（复用 `FB_DL_ConveyorZone` 多区级联）→ **DL_Process** ｜ **P1**
- [x `FB_DL_ElMutingGantry`：EL 检测龙门进出屏蔽（复用 `FB_DL_SafetyLightCurtain` 4 传感器序列）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_EvaDosingTare`：EVA 膜裁剪称重定量（复用 `FB_DL_BatchDosingControl` + 皮重自动 tare 策略）→ **DL_Process** ｜ **P2**

### 11.3 半导体 / Semiconductor（+6 项）

- [x] `FB_DL_FoupDoorSeq`：FOUP 开合门与载具联锁（复用 `FB_DL_GuardLockDoor` 再锁定确认窗语义）→ **DL_Device** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_CurtainEFEMZone`：EFEM 机械手作业区光幕分区屏蔽（复用 `FB_DL_SafetyLightCurtain` 序列判向）→ **DL_Device** ｜ **P1**
- [x] `FB_DL_ChemDosingGrav`：化学液定量补给称重（复用 `FB_DL_BatchDosingControl`，密度温度补偿外置）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_WaferScanRouter`：晶圆盒扫码路由（复用 `I_DL_BarcodeScanner` + `FB_DL_ModuloCounter` 工位索引）→ **DL_Process** ｜ **P0** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_CoolantFlowAudit`：机台冷却水多支路流量审计（复用 `FB_DL_PulseFlowMeter` 多实例 + `FB_DL_AlarmManager`）→ **DL_Device** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_SlurryLevelBank`：浆料罐点式料位巡检组（复用 `FB_DL_LevelSwitchVib` 多实例 + fail-safe 组态审查）→ **DL_Device** ｜ **P2**

### 11.4 包装 / Packaging（+5 项）

- [x] `FB_DL_CartonScannerSort`：纸箱扫码分道（复用 `I_DL_BarcodeScanner` + `FB_DL_ConveyorZone` 分道放行）→ **DL_Process** ｜ **P0**
- [x] `FB_DL_FilmSpliceCurtain`：接膜工位光幕屏蔽序列（复用 `FB_DL_SafetyLightCurtain` 2 传感器模式）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_PowderDosingLoss`：粉料失重秤配料（增量式，复用 `FB_DL_BatchDosingControl` 结算/学习链）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_PalletZoneMerge`：码垛前多线合流积放（复用 `FB_DL_ConveyorZone` + 上区补跑语义）→ **DL_Process** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_RotaryIndexModulo`：转盘工位索引与入料联锁（复用 `FB_DL_ModuloCounter` + `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P1**

### 11.5 暖通 / HVAC（+5 项）

- [x] `FB_DL_FilterSwitchLevel`：过滤器液位/料位联锁（再生系统盐罐，复用 `FB_DL_LevelSwitchVib` fail-safe LOW）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_MakeupWaterDosing`：补水定量加药（复用 `FB_DL_BatchDosingControl` + `FB_DL_Integrator` 流量累计）→ **DL_Process** ｜ **P2**（R52 已落地 v1.0.0，v2.44.0）
- [x] `FB_DL_BeltHeatRecovery`：转轮热回收输送联锁（复用 `FB_DL_ConveyorZone` + 温差判据外置）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_RoofUnitDoorSw`：屋顶机检修门-风机联锁（复用 `FB_DL_GuardLockDoor` 重启抑制语义轻量组态）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_HydronicMeterAudit`：冷冻水/冷却水能量审计（复用 `FB_DL_PulseFlowMeter` + `FC_DL_HumidAirEnthalpy` 侧焓差）→ **DL_Process** ｜ **P1**

### 11.6 过程控制 / Process Control（+5 项，含终审立项 2 条 P2）

- [x] `FB_DL_UnlockHoldTimeout`：安全门 eUnlocked 保持超时监视（解锁输出有效但门未开超 `tUnlockHold` → 提示电磁铁/机械卡滞；终审对 `FB_DL_GuardLockDoor` 的立项增强，复用其解锁时序）→ **DL_Device** ｜ **P2**（终审立项）
- [x] `FB_DL_ConveyorDirMismatch`：输送线停机方向失配独立窗（停机后出口光电变化但方向与运行方向不符 → 反窜/倒滑独立诊断窗；终审对 `FB_DL_ConveyorZone` 的立项增强，复用其光电与 run-on 语义）→ **DL_Process** ｜ **P2**（终审立项）
- [x] `FB_DL_TankDosingMulti`：多罐轮流定量投加（复用 `FB_DL_BatchDosingControl` 多实例 + `FB_DL_DutyStandbyRotation` 罐序）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_PipeScannerRoute`：管输批次的扫码分输（复用 `I_DL_BarcodeScanner` + `FB_DL_StepSequencer` 阀序）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_SiloLevelInterlock`：料仓高低料位-输送联锁（防溢仓/空跑，复用 `FB_DL_LevelSwitchVib` 双联锁 + `FB_DL_ConveyorZone` 卡料窗）→ **DL_Process** ｜ **P1** → **已落地 R30（v2.19.0）**

> **扩容统计**：R7 扩容 32 条（锂电 6 / 光伏 5 / 半导体 6 / 包装 5 / 暖通 5 / 过程控制 5），全部不与既有 167 条重名；`DL_Device` 9 条（受益于 R7 安全门/光幕/扫码/流量/料位契约）、`DL_Process` 23 条——识别/安全/计量/给料四类工艺语汇是本轮扩容主线，其中 2 条为终审立项增强件（P2）。

---

## 十二、R9 新增（Round 09 收口件，2026-11-15，ROADMAP 既有清单无对应条目，收口登记于此）

> 本轮 16 件收口：其中 `I_DL_StepperOpenLoop` & `FB_DL_PulseDirStepper`（第四节）、`FB_DL_SuperimposedMove`（第五节）、`FB_DL_AndonCallSystem`（第六节）3 条既有待办行已就地勾选；以下 12 件既有清单无对应条目，收口登记。

- [x] `FB_DL_ToleranceWindow`（DL_Base）：公差窗判定（目标带迟滞 + 中带豁免 + 判定方向四态，测量/判合格共用骨架）（R9 立项，T2-1 LGF 公差族）
- [x] `FC_DL_LimitClassify`（DL_Base）：四阈值分级器 LL/L/H/HH（纯函数判据表驱动，闭区间归属逐档固定）（R9 立项，T2-1 LGF 限值族）
- [x] `FC_DL_WordBitPack`（DL_Base）：多位段打包进 WORD（域校验 + 守护计数 + 序比较双闸，v1.0.1 修复 USINT 回绕绕过判界）（R9 立项，T2-1 LGF 位段族）
- [x] `FB_DL_MonthWindowCheck`（DL_Base）：月度生效窗判定（日窗 + 月窗双闸，参数钳位照算）（R9 立项，T2-1 LGF 日历族，TimeWindowCheck/DayOfWeekCalc 的月粒度上位件）
- [x] `FB_DL_PresetCounterSat`（DL_Base）：预设饱和计数器（上/下限双预设，倒置冻结锁存，复位前置条件文档化）（R9 立项，T2-1 LGF 计数族）
- [x] `FB_DL_FifoBuffer`（DL_MathData）：定长 FIFO 队列（**先弹后压**时序 + 满队丢新 + 指针一致性自愈）（R9 立项，T2-1 LGF 缓冲族，与 RingBufferLReal/LifoStack 三件套收口）
- [x] `FB_DL_ArraySearchFirst`（DL_MathData）：数组线性首搜（返回首个命中下标 + nCount 钳位）（R9 立项，T2-1 LGF 检索族）
- [x] `FC_DL_BinarySearchLReal`（DL_MathData）：LREAL 有序数组二分查找（纯函数 + 守护兜底强制未命中；v1.0.1 补 uErrorId 声明 D-01 致命修复）（R9 立项，T2-1 LGF 检索族）
- [x] `FC_DL_TempUnitConvert`（DL_MathData）：四温标互转 C/F/K/R（双向枚举 + 绝对零度守卫）（R9 立项，T2-1 LGF 换算族）
- [x] `FC_DL_BcdToWord`（DL_MathData）：BCD16 → WORD（半字节逐位校验；v1.0.1 改显式标准转换 USINT_TO_UINT）（R9 立项，T2-1 LGF 数制族）
- [x] `FC_DL_WordToBcd`（DL_MathData）：WORD → BCD16（除基守卫 + 9999 溢出饱和）（R9 立项，T2-1 LGF 数制族）
- [x] `FB_DL_ModbusPollMaster`（DL_Process）：Modbus 轮询主站调度抽象（站表轮询 + 重试台账 + DoTransaction/SendFrame/RecvFrame 抽象桩派生覆盖，换 RTU/TCP 调度层零改动）（R9 立项，T1-4 CODESYS Forge Modbus 族深化）

> **收口统计**：R9 共 16 件 5,051 行，registry 120 → 136（v1.8.0）；终审 PASS with fixes（致命 2 / 严重 8 / 轻微 3），码位改判 6 件 15 处（跨文件重叠归零），新范式 R28/R29/R30 入册。

---

## 十三、行业方向待办池 R9 扩容 / Industry Backlog Pool R9 Expansion（+32 项，总 199 → 231 项，不计入 Phase 1 的 100 项配额）

> **产品经理确认（R9 文档线）**：R9 落地步进开环族 / 叠加运动 / Modbus 轮询调度抽象 / 安灯四级仲裁 + Level 0 六组回补（FIFO/检索/温标/BCD/公差/限值/位段/日历/预设计数）后，行业池里「经济型轴方案 / 多温标工艺 / 轮询采集 / 人因呼叫链路」类条目全部解锁。本轮扩容 **32 条**（总 199 → **231 条**），六行业各 5~6 条，全部不与既有 199 条重名；每条标注**拟入目录**与**优先级**（P0=下一轮候选 / P1=1~2 轮内 / P2=观察池），并注明可复用的已收口 Level 0/1 能力。含**终审立项 2 条 P2**（PulseDirStepper 细分脉冲当量换算件、AndonCallSystem 响应时长统计报表件）。
> 立项前置条件与复用优先规则沿用 7.7 节池子运营规则；行业模板只允许编排 Level 0/1 已有能力，不得内联实现底层逻辑。

### 13.1 锂电 / Lithium Battery（+6 项）

- [x] `FB_DL_StepperXyzGantry` ✔ R28 入库：点胶/贴片三轴步进开环龙门（复用 `I_DL_StepperOpenLoop` 三实例 + `FB_DL_ToleranceWindow` 落点判定）→ **DL_Motion** ｜ **P1**
- [x] `FB_DL_OcvTempNormalize`：OCV 测试温度归一判据（复用 `FC_DL_TempUnitConvert` + `FB_DL_ToleranceWindow` 判合格带）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_RollPressBitWord`：辊压压力报警字位段打包（复用 `FC_DL_WordBitPack` + `FB_DL_AlarmManager` 通道映射）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_FormatMonthAudit`：化成/分容月度窗排产审计（复用 `FB_DL_MonthWindowCheck` + `FB_DL_OeeCalculator` 班次根因）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_ElectrolyteFifoTrace`：注液批次 FIFO 追溯队列（复用 `FB_DL_FifoBuffer` 批次结构体队列 + 条码绑定）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_PilePressLimitClass`：堆叠压力四档分级与 NG 分道（复用 `FC_DL_LimitClassify` + `FB_DL_ConveyorZone` 分道放行）→ **DL_Process** ｜ **P1**

### 13.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_LamStepperFeed`：层压机铺膜步进送料（复用 `I_DL_StepperOpenLoop` + `FB_DL_MonthWindowCheck` 保养窗）→ **DL_Motion** ｜ **P2** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_IvBcdExport`：IV 测试仪 BCD 拨码设定导出（复用 `FC_DL_WordToBcd` / `FC_DL_BcdToWord` 面板互转）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_StringFifoRetry`：电池串缓存队列重试出站（复用 `FB_DL_FifoBuffer` 丢新策略 + `FB_DL_StepSequencer`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_TempCompClassify`：组件功率温度补偿分档（复用 `FC_DL_TempUnitConvert` + `FC_DL_LimitClassify` 四档）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_TrayMonthRotate`：托盘月度轮换保养排程（复用 `FB_DL_MonthWindowCheck` + `FB_DL_DutyStandbyRotation` 轮值）→ **DL_Process** ｜ **P2**

### 13.3 半导体 / Semiconductor（+6 项）

- [x] `FB_DL_StepperZLiftMicron`：Z 轴微米级步进升降（复用 `I_DL_StepperOpenLoop` + 细分当量组态 + `FB_DL_SoftLimitGuard`）→ **DL_Motion** ｜ **P1** ✔R27
- [x] `FB_DL_ChamberTempUnitBank`：多腔室温标统一换算行（复用 `FC_DL_TempUnitConvert` 多实例 + `FB_DL_HeatCoolZone`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_WaferCountPreset`：晶圆计数预置饱和（复用 `FB_DL_PresetCounterSat` + `FB_DL_ModuloCounter` 花篮位）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_PollTempBank`：温控器轮询采集行（复用 `FB_DL_ModbusPollMaster` 派生 RTU 传输块 + `FB_DL_MovingAverage`）→ **DL_Process** ｜ **P0**（**R12 交付·P0 清零**；行级编排 + 通道质量掩码 + 连续失败摘除/恢复 + 最差通道偏差；449 行，终审 PASS 零修改）
- [x] `FB_DL_EmoAndonFab`：洁净室 EMO-安灯联动呼叫（复用 `FB_DL_AndonCallSystem` 四级仲裁 + `FB_DL_GuardLockDoor` 审计）→ **DL_Process** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_CassetteBcdLabel`：花篮 BCD 拨码标签机联动（复用 `FC_DL_WordToBcd` + `I_DL_BarcodeScanner`）→ **DL_Device** ｜ **P2**

### 13.4 包装 / Packaging（+5 项）

- [x] `FB_DL_StepperFeederBelt` ✔ R28 入库：步进供料带间歇送料（复用 `I_DL_StepperOpenLoop` MoveRelative + `FB_DL_MarkPositionLatch` 色标校正）→ **DL_Motion** ｜ **P1**
- [x] `FB_DL_WeightClassifySort`：重量四档分级剔除（复用 `FC_DL_LimitClassify` + `FB_DL_ConveyorZone` 剔除口）→ **DL_Process** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_ShiftMonthReport`：班次/月度窗口产量报表闸（复用 `FB_DL_MonthWindowCheck` + `FB_DL_OeeCalculator`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_FilmTensionStepper`：收卷步进张力微调（复用 `FB_DL_SuperimposedMove` 叠加微调 + `FB_DL_ToleranceWindow` 张力带）→ **DL_Motion** ｜ **P2**
- [x] `FB_DL_AndonLinePack`：包装线安灯分级呼叫与响应报表（复用 `FB_DL_AndonCallSystem` + `FB_DL_RuntimeMeter`）→ **DL_Process** ｜ **P1**

### 13.5 暖通 / HVAC（+5 项）

- [x] `FB_DL_RoomTempClassify`：房间温度舒适带分级（复用 `FC_DL_TempUnitConvert` + `FC_DL_LimitClassify` 舒适四档）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_SeasonMonthSched`：供暖/制冷季月度切换窗（复用 `FB_DL_MonthWindowCheck` + `FB_DL_OccScheduleWindow`）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_BacdHvacPoll`：BA 顺控 BACnet/Modbus 轮询行（复用 `FB_DL_ModbusPollMaster` 派生 TCP 传输块）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_FreshAirStepperDamper`：新风阀步进执行器开环驱动（复用 `I_DL_StepperOpenLoop` + `FB_DL_ToleranceWindow` 开度带）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_EnergyMonthPreset`：月度能耗预算预置计数（复用 `FB_DL_PresetCounterSat` + `FB_DL_Integrator` 累计）→ **DL_Process** ｜ **P2**

### 13.6 过程控制 / Process Control（+5 项，含终审立项 2 条 P2）

- [x] `FB_DL_StepperMicroFeedPulseEquiv`：步进细分脉冲当量换算件（细分 × 丝距 → 当量/反向间隙组态表；终审对 `FB_DL_PulseDirStepper` 的立项增强，复用其组态域校验）→ **DL_Device** ｜ **P2**（终审立项）
- [x] `FB_DL_AndonRespTimeReport`：安灯响应时长分档统计报表（呼叫→应答→解除分段计时 + 四级分档；终审对 `FB_DL_AndonCallSystem` 的立项增强，复用其仲裁锁存）→ **DL_Process** ｜ **P2**（终审立项）
- [x `FB_DL_BcdFieldPanelIO`：面板 BCD 拨码阵列采集（复用 `FC_DL_BcdToWord` 多路 + `FB_DL_SignalDebounce`）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_PollAuditBank`：多链路轮询异常台账汇总（复用 `FB_DL_ModbusPollMaster` 多实例 + `FB_DL_AlarmManager` 首出）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_RecipeSearchFifo`：配方请求 FIFO 排队（复用 `FB_DL_FifoBuffer` + `FB_DL_RecipeManager` 校验链）→ **DL_Process** ｜ **P1**

> **扩容统计**：R9 扩容 32 条（锂电 6 / 光伏 5 / 半导体 6 / 包装 5 / 暖通 5 / 过程控制 5），全部不与既有 199 条重名；`DL_Motion` 5 条（受益于 R9 步进族/叠加运动）、`DL_Process` 21 条、`DL_Device` 6 条（受益于 R9 轮询调度抽象/温标/BCD 换算）——步进开环经济型方案与轮询采集是本轮扩容主线，其中 2 条为终审立项增强件（P2）。

---

## 十四、R10 新增（Round 10 收口件，2026-11-15，ROADMAP 既有清单无对应条目，收口登记于此）

> 本轮 16 件收口：其中 `I_DL_RfidReader` & `FB_DL_RfidTagHandler`（第四节）、`FB_DL_PickAndPlaceStation`（第六节）、`FB_DL_WindingTraverse`（第五节）3 条既有待办行已就地勾选（覆盖 4 件）；以下 **12 件**既有清单无对应条目，收口登记。

- [x] `FC_DL_BitFieldExtract`（DL_Base）：位段提取（域校验 + `nWidth=32` 走常量掩码规避 `SHL(x,32)` 未定义行为，与 `FC_DL_WordBitPack` 构成打包-提取逆运算对）（R10 立项，T2-1 LGF Bit Logic 组）
- [x] `FC_DL_WeekOfYearCalc`（DL_Base）：ISO-8601 周数与周年计算（**Zeller 同余 + 周四归属法**，无查表、无浮点；跨年归属为独立语义，不与 `DayOfWeekCalc` 合并）（R10 立项，T2-1 LGF Date and Timer 组；规格偏离 O-5 已采纳并要求修订规格模板）
- [x] `FB_DL_BidirectionalCounter`（DL_Base）：CTUD 全语义双向计数器（CU/CD 双沿 + 双预设 + `bAtMax` 三律；与 `PresetCounterSat` 的「倒置冻结 vs 锁故障」策略差异已文档化）（R10 立项，T2-1 LGF Counter 组）
- [x] `FC_DL_SearchMinMax`（DL_MathData）：数组极值搜索（值 + 双索引同出；NaN 用 `x <> x` 判定，全量非有限不返回 0 号位以免伪命中）（R10 立项，T2-1 LGF Math 组）
- [x] `FC_DL_NthRoot`（DL_MathData）：N 次根（奇偶次分治 + Newton 迭代后有限性复检；n 域 0~12 与 LGF 官方域一致但码位自有）（R10 立项，T2-1 LGF Math 组）
- [x] `FC_DL_FactorialSat`（DL_MathData）：阶乘饱和（12!/13! 边界，超域置 `bSat` 而非报错——饱和与故障是两种业务语义，库不替调用方选）（R10 立项，T2-1 LGF Math 组；v1.0.1 修复 D-17 隐式类型提升）
- [x] `FB_DL_SineGenerator`（DL_Algo）：正弦波发生器（三态 待机/运行/故障 + CASE 兜底；失能与频率 0 均冻结相位不归零；**一拍固有延迟**已写入采样约定段）（R10 立项，T2-1 LGF Signal Generators 组，码位带 `1B`）
- [x] `FB_DL_SawtoothGenerator`（DL_Algo）：锯齿波发生器（逐拍序列 `0 → 50 → 100 → 50`；与正弦分件而非 `eWaveform` 枚举合并）（R10 立项，T2-1 LGF Signal Generators 组，码位带 `1C`）
- [x] `FC_DL_CoilDiameterCalc`（DL_Algo）：卷径瞬时几何反算（`D = v·i/(π·n)` + `fPrevDia` 注入上次值；**层厚递推与排线执行归 `FB_DL_WindingTraverse`**，职责按「算一个值 / 做一件事」切开）（R10 立项，T2-1 LGF Technology 组 + S-4 公开公式，码位带 `1D`）
- [x] `FC_DL_AirDensity`（DL_Algo）：湿空气密度（T/P/RH → kg/m³，Magnus-Tetens + 分压叠加；精度承诺收窄至 **-10~50 °C**，域外标趋势参考）（R10 立项，T1-2 OSCAT Building 行为定义 + 公开公式，码位带 `1E`）
- [x] `FB_DL_AxiolineDiagLatch`（DL_Device）：Axioline F 诊断寄存器锁存与语义拆解（`PF/PW/BUS/RUN/ACT/RDY/SYSFAIL` 七位 + **128 特例不得伪装成 128 号槽**；不绑定任何厂商系统变量名，经引脚注入）（R10 立项，T1-7 PLCnext 开组）
- [x] `FB_DL_PdiReadScheduler`（DL_Device）：PDI 对象读取调度（**PDI = Parameters/Diagnostics/Information**；单拍只发一条 + 忙时拒绝不排队，对应 RSC「长耗时不得在实时任务直接调用」纪律）（R10 立项，T1-7 PLCnext 开组；Q5 证伪后立项方向已改写）

> **收口统计**：R10 共 16 件，送审 5,385 行 → 修后 **5,528 行**，registry 136 → **152**（v1.9.0）；终审 PASS with fixes（致命 2 ／ 严重 3 ／ 中等 6 ／ 注释级 6，17 条全部机检零捕获）；8 件升 v1.0.1；新范式 **R31/R32** 入册；T1-7 与 T2-6 双源同时开组。

---

## 十五、行业方向待办池 R10 扩容 / Industry Backlog Pool R10 Expansion（+32 项，总 231 → 263 项，不计入 Phase 1 的 100 项配额）

> **产品经理确认（R10 文档线）**：R10 落地位段提取 / 周数 / 双向计数 / 数学三件（极值·开方·阶乘）/ 信号发生两件 / 卷径与排线 / 空气密度 / RFID 契约族 / 总线诊断两件 / 拾放工站后，行业池里「卷绕张力给定 / 载具身份路由 / 机架诊断汇总 / 工站骨架复用 / 周粒度计划窗」类条目全部解锁。本轮扩容 **32 条**（总 231 → **263 条**），六行业各 5~6 条，全部不与既有 231 条重名；每条标注**拟入目录**与**优先级**（P0=下一轮候选 / P1=1~2 轮内 / P2=观察池），并注明可复用的已收口 Level 0/1 能力。
> 立项前置条件与复用优先规则沿用 7.7 节池子运营规则；行业模板只允许编排 Level 0/1 已有能力，不得内联实现底层逻辑。

### 15.1 锂电 / Lithium Battery（+6 项）

- [x] `FB_DL_ElectrodeGapMark`：极片留白区（Gap）位置标记与对齐判定（复用 `FC_DL_BitFieldExtract` 取视觉标志位 + `FB_DL_ToleranceWindow` 留白带）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_WindingLayerCounter`（R19 收口）：卷绕层数与剩余层数计数（复用 `FB_DL_BidirectionalCounter` 正反向层计数 + `FC_DL_CoilDiameterCalc` 卷径交叉校核）→ **DL_Motion** ｜ **P1**
- [x] `FB_DL_SlurryViscosityComp`：浆料粘度温补换算（复用 `FC_DL_TempUnitConvert` + `FC_DL_LinearScale` 温-粘曲线）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_RfidTrayRoute`：载具 RFID 身份驱动的路径路由（复用 `FB_DL_RfidTagHandler` 读码 + `FB_DL_ConveyorLineLink` 段间握手）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_FormationWeekPlan`：化成/分容周计划窗（复用 `FC_DL_WeekOfYearCalc` 周序号 + `FB_DL_MonthWindowCheck` 月窗双闸）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_ElectrodeRollDiameter`：极卷直径跟踪与换卷预警（复用 `FC_DL_CoilDiameterCalc` + `FB_DL_WindingTraverse` 排线位置）→ **DL_Motion** ｜ **P2** → **已落地 R30（v2.19.0）**

### 15.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_StringIrrNormalize`：组串电流辐照归一化（复用 `FC_DL_LinearScale` 辐照标定 + `FB_DL_SignalStatistics` 窗口统计）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_WaferCassetteSlot` ✔ R28 入库：花篮槽位占用计数（复用 `FB_DL_BidirectionalCounter` 进出双向计数 + `FB_DL_BufferMagazine` 槽位台账）→ **DL_Device** ｜ **P1**
- [x] `FB_DL_InverterPdiPoll`：逆变器 PDI 参数周期读取（复用 `FB_DL_PdiReadScheduler` 单拍单发 + `FB_DL_ModbusPollMaster` 站表台账）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_EdgeTrimTraverse` ✔ R28 入库：修边刀架横动定位（复用 `FB_DL_WindingTraverse` 往复骨架简化 + `FB_DL_SoftLimitGuard` 行程拦截）→ **DL_Motion** ｜ **P2**
- [x] `FB_DL_LaminatorZoneSync`：层压机多温区联动升温（复用 `FB_DL_StepController` 分级 + `FB_DL_CascadePid` 串级）→ **DL_Process** ｜ **P1**

### 15.3 半导体 / Semiconductor（+6 项）

- [x] `FB_DL_FoupRfidCheck`：晶圆盒（FOUP）RFID 身份校验与配方放行（复用 `FB_DL_RfidTagHandler` + `FB_DL_RecipeManager` 校验链）→ **DL_Process** ｜ **P1**
- [x] `FB_DL_ChuckVacuumSeq`：卡盘真空吸附/释放序（复用 `FB_DL_PickAndPlaceStation` 步骤骨架 + `I_DL_VacuumGenerator` 到位判据）→ **DL_Process** ｜ **P1**
- [x] `FC_DL_GasFlowSqrt`：特气差压流量开方换算（复用 `FC_DL_NthRoot` + `FC_DL_FlowCompensate` 温压补偿）→ **DL_Algo** ｜ **P2**
- [x] `FB_DL_RackDiagSummary`：机架 Axioline 诊断汇总与首出定位（复用 `FB_DL_AxiolineDiagLatch` 多实例 + `FB_DL_AlarmManager` 首出）→ **DL_Device** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_DieBinCounter`：晶粒分箱计数与满箱切换（复用 `FB_DL_BidirectionalCounter` + `FC_DL_LimitClassify` 分档）→ **DL_Process** ｜ **P2**（R52 已落地 v1.0.0，v2.44.0）
- [x] `FB_DL_CleanRoomRhTrim`：洁净室相对湿度微调（复用 `FC_DL_DewPointCalc` + `FB_DL_HumidityOverride` 优先级）→ **DL_Process** ｜ **P2**

### 15.4 包装 / Packaging（+5 项）

- [x] `FB_DL_CartonErectorStation`：开箱（Carton Erector）工站模板（复用 `FB_DL_PickAndPlaceStation` 七态九步骨架 + `FB_DL_StepSequencer` 步超时）→ **DL_Process** ｜ **P0**
- [x] `FB_DL_PalletizerStation`：码垛工站模板（复用 `FB_DL_PickAndPlaceStation` + `FB_DL_PalletizerLayerSeq` 层排布 + `FB_DL_GantrySyncAxis` 龙门）→ **DL_Process** ｜ **P0**
- [x] `FB_DL_LabelWeekCode`：标签周码/批码打印窗（复用 `FC_DL_WeekOfYearCalc` + `FB_DL_DateCoderSync` 打印同步）→ **DL_Process** ｜ **P2** ｜ 【R55 补勾】盘点实测 registry 已在册且 .st 已落盘（三查双证），ROADMAP 漏勾就地补记
- [x] `FB_DL_FilmTaperTension`：薄膜锥度张力给定曲线（复用 `FC_DL_CoilDiameterCalc` 卷径 + `FB_DL_WindingTensionCtrl` 闭环）→ **DL_Motion** ｜ **P2**
- [x] `FB_DL_CaseShiftTally`：班次箱数台账与差异告警（复用 `FB_DL_BidirectionalCounter` + `FB_DL_OeeCalculator` 班次报表）→ **DL_Process** ｜ **P2** ｜ 【R55 补勾】盘点实测 registry 已在册且 .st 已落盘（三查双证），ROADMAP 漏勾就地补记

### 15.5 暖通 / HVAC（+5 项）

- [x] `FC_DL_AirDensityFanPower`：风机功率的空气密度修正（复用 `FC_DL_AirDensity` + `FC_DL_LinearScale` 标定）→ **DL_Algo** ｜ **P2**
- [x] `FB_DL_FanLawRootCalc`：风机定律开方/立方换算（复用 `FC_DL_NthRoot` + `FB_DL_FanPressureTrim` 压力微调）→ **DL_Algo** ｜ **P1**  ✔ R28 入库（实现件名 `FC_DL_FanLawMultiExpCalc`：原规划名与 DL_MathData 存量件跨子库同名，属编译阻断级，另立名）
- [x] `FB_DL_FilterWeekWindow`：过滤器周维护窗与压差累计（复用 `FC_DL_WeekOfYearCalc` + `FB_DL_RuntimeMeter` 累计）→ **DL_Process** ｜ **P2** ｜ 【R55 补勾】盘点实测 registry 已在册且 .st 已落盘（三查双证），ROADMAP 漏勾就地补记
- [x] `FB_DL_BmsPdiGateway`：楼宇侧 PDI 对象网关轮询（复用 `FB_DL_PdiReadScheduler` 调度 + `FB_DL_AlarmManager` 异常上报）→ **DL_Device** ｜ **P2**
- [x] `FB_DL_DamperBitDiag`：风阀执行器位诊断打包/解包（复用 `FC_DL_BitFieldExtract` + `FB_DL_UnpackWordToBits`）→ **DL_Device** ｜ **P2**

### 15.6 过程控制 / Process Control（+5 项）

- [x] `FB_DL_FlowSqrtExtract`（R19 收口）：差压流量开方与低切（复用 `FC_DL_NthRoot` + `FC_DL_FlowCompensate`）→ **DL_Algo** ｜ **P1**
- [x] `FB_DL_BatchWeekReport`：批次周报闸与周批号生成（复用 `FC_DL_WeekOfYearCalc` + `FB_DL_OeeCalculator`）→ **DL_Process** ｜ **P2**
- [x] `FB_DL_GasDensityComp`：反应釜气体密度补偿（复用 `FC_DL_AirDensity` 骨架换介质常量 + `FB_DL_PidController` 压力闭环）→ **DL_Algo** ｜ **P2**
- [x] `FB_DL_ValvePdiSched`：阀门岛 PDI 批量读取调度（复用 `FB_DL_PdiReadScheduler` 多实例分槽）→ **DL_Device** ｜ **P1** → **已落地 R30（v2.19.0）**
- [x] `FB_DL_LoopWaveInject`：回路波形注入测试（复用 `FB_DL_SineGenerator` 激励 + `FB_DL_RateLimiter` 斜率保护）→ **DL_Algo** ｜ **P2**

> **扩容统计**：R10 扩容 32 条（锂电 6 / 光伏 5 / 半导体 6 / 包装 5 / 暖通 5 / 过程控制 5），全部不与既有 231 条重名；`DL_Process` 13 条、`DL_Device` 6 条、`DL_Motion` 3 条、`DL_Algo` 5 条、`DL_Base`/`DL_MathData` 0 条（本轮 Level 0 已补至 61 件，暂不缺件）。**主线两条**：① RFID 契约族 + PDI 调度族解锁「身份路由 / 机架诊断 / 网关轮询」类设备侧条目 6 条；② 拾放工站骨架解锁「开箱 / 码垛 / 卡盘真空」等工站模板 13 条（其中 P0 两条为 R11 首批候选）。

---

## 十六、行业方向待办池 R11 扩容 / Industry Backlog Pool R11 Expansion（+32 项，总 263 → 295 项，不计入 Phase 1 的 100 项配额）

> **产品经理确认（R11 文档线）**：R11 计划（见 `_Staging_Raw/2026-11-15/ROUND_PLAN_R11.md`）落地位段表解码 / 端口级诊断聚合 / 年窗判定 / 回绕计数 / 区间关系 / 3D 距离 / 确定性随机 / 分位数 / 多通道 NTC / 辊距背隙微调 / R2R EWMA / 锥度张力 / 压装·分度·AGV 对接·节能四件工站后，行业池中四类「新底座驱动」的条目全部解锁：
> ① **年窗族**（`FB_DL_YearWindowCheck`）解锁「年周期生效 / 年度保养闸 / 跨年窗口」类；
> ② **设备级粗粒度 + 通道诊断族**（`FB_DL_NtcTempScan` / `FB_DL_StatusWordSegDecoder` / `FB_DL_PortDiagAggregator`）解锁「多通道设备健康度 / 状态字字段路由 / 端口看板」类；
> ③ **工站四件套**（压装 / 分度 / 对接 / 节能）解锁「曲线归档 / 通道排队 / 年度清洗 / 批次偏差」类；
> ④ **区间关系 + 分位数**（`FC_DL_RangeOverlapCheck` / `FC_DL_PercentileLReal`）解锁「模式防错 / 节拍分布判据」类。
> 本轮扩容 **32 条**（总 263 → **295 条**），六行业各 5~6 条，全部不与既有 263 条重名；每条标注**拟入目录**与**优先级**（P0=下一轮候选 / P1=1~2 轮内 / P2=观察池），并注明可复用的已收口 Level 0/1 能力。
> 立项前置条件与复用优先规则沿用 7.7 节池子运营规则；行业模板只允许编排 Level 0/1 已有能力，不得内联实现底层逻辑。**凡引用尚未落地的组件（如 `FB_DL_SteamTrapMonitor` / `FB_DL_FanArrayStageCtrl`），该前置件必须先立项，不得在本条内内联其算法。**

### 16.1 锂电 / Lithium Battery（+6 项）

- [x] `FB_DL_PressFitCurveArchive`：压装曲线特征点归档与批次追溯（复用 `FB_DL_PressFitStation` 的 `stResult` 四特征点 + `FB_DL_RingBufferLReal` 曲线缓存，按批次号索引）→ **DL_Process** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_NtcChannelHealth` ✔ R28 入库：NTC 通道健康度评分与断线预警（复用 `FB_DL_NtcTempScan` 通道故障掩码 + `FB_DL_SignalStatistics` 长期漂移统计，输出 0~100 健康分）→ **DL_Device** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_ElectrodeTabBendCtrl`：极耳折弯角度与回弹补偿（复用 `FB_DL_RollerGapAdjust` 的单向逼近骨架 + `FC_DL_CalcDistance3D` 视觉测距，回弹量按批次学习）→ **DL_Device** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_ElectrolyteMoistureGuard`：注液间露点/湿度联锁（复用 `FC_DL_DewPointCalc` 露点判据 + `FB_DL_InterlockMatrix` 首因锁定，超露点禁止注液）→ **DL_Device** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_FormationChannelQueue`：化成柜通道排队与优先级抢占（复用 `FB_DL_LifoStack` 优先栈 + `FB_DL_RecipeManager` 工步校验，通道故障自动摘除）→ **DL_Process** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_SlurryDensityTrim`：浆料面密度与密度交叉校核（复用 `FC_DL_LinearScale` 标定 + `FB_DL_ToleranceWindow` 公差带，双源偏差分档告警）→ **DL_Process** ｜ **P2** `[R11 新增]`

### 16.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_StringElImageMap`：EL 图像缺陷坐标归档与批次比对（复用 `FB_DL_BufferMagazine` 槽位台账 + `FB_DL_RingBufferLReal` 图像索引缓存）→ **DL_Process** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_LaminatorVacLeakTrend` ✔ R28 入库：层压机真空泄漏率趋势诊断（复用 `FB_DL_Differentiator` 压降速率 + `FB_DL_SignalStatistics` 窗口基线，越基线报警）→ **DL_Process** ｜ **P1** `[R11 新增]`
- [x `FB_DL_WaferBreakDetect`：电池片隐裂/碎片在线判据（复用 `FC_DL_BitFieldExtract` 取视觉结果位 + `FB_DL_PeakDetector` 突发峰值捕获）→ **DL_Process** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_TrackerAngleYearWin`：跟踪支架年度角度表切换（复用 `FB_DL_YearWindowCheck` 年窗 + `FB_DL_MonthWindowCheck` 月窗双闸，按季节切换角度表）→ **DL_Motion** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_SolderRibbonTension`：焊带放卷张力与蛇形纠偏（复用 `FB_DL_WindingTensionCtrl` 锥度张力 + `FB_DL_SoftLimitGuard` 横动行程拦截）→ **DL_Motion** ｜ **P1** `[R11 新增]`

### 16.3 半导体 / Semiconductor（+6 项）

- [x] `FB_DL_R2rRunLogAudit`：R2R 调参与批次审计算账（复用 `FB_DL_R2rEwmaTuner` 的 `uLotCount`/`fEwmaDev` + `FB_DL_RecipeManager` 变更留痕，形成可追溯调参台账）→ **DL_Process** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_ChamberPumpDownProfile` ✔ R28 入库（撞名另立名：`FB_DL_PumpDownEnvelopeMonitor`）：腔体抽气曲线包络监视（复用 `FB_DL_SignalStatistics` 窗口统计 + `FB_DL_RateLimiter` 斜率判据，抽速异常早停）→ **DL_Process** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_EfEmDoorInterlockPlus` ✔ R28 入库：EFEM 门/阀/真空三域互斥扩展（复用 `FB_DL_StatusWordSegDecoder` 解门状态字 + `FB_DL_InterlockMatrix` 首因）→ **DL_Device** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_MfcSetpointRamp`：MFC 设定值斜坡与超调抑制（复用 `FB_DL_RateLimiter` 斜率限制 + `FC_DL_LinearScale` 量程换算）→ **DL_Device** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_PortDiagBoard`：机架端口诊断看板与首出定位（复用 `FB_DL_PortDiagAggregator` 多实例分端口组 + `FB_DL_AlarmManager` 首出汇总）→ **DL_Device** ｜ **P0** `[R11 新增]`（**R12 交付·P0 清零**；8 组 × 32 端口掩码屏蔽 + Top3 稳定排序 + 越界端口逐位清零 + 两拍扫描节拍；459 行，终审 PASS 零修改）
- [x] `FC_DL_WaferCountYield`：晶圆计数与良率折算（纯函数：投入/产出/返工三计数 → 良率百分比与损失分档，复用 `FC_DL_LinearScale` 归一化）→ **DL_MathData** ｜ **P2** `[R11 新增]`

### 16.4 包装 / Packaging（+5 项）

- [x] `FB_DL_SealJawDwellTrim` ✔ R28 入库：热封刀驻留时间随线速自整定（复用 `FB_DL_PidController` 线速-驻留闭环 + `FB_DL_RateLimiter` 变化率保护）→ **DL_Process** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_CartonErectVacMonitor`：开箱吸盘真空建立趋势诊断（复用 `I_DL_VacuumGenerator` 契约语义 + `FB_DL_SignalStatistics` 建立时长统计，吸盘老化预警）→ **DL_Device** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_FilmSpliceWeekPlan`：接膜保养周窗与耗材台账（复用 `FC_DL_WeekOfYearCalc` 周序号 + `FB_DL_RuntimeMeter` 膜长累计，到周窗提醒接膜）→ **DL_Process** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_CheckweighZeroTrack` ✔ R28 入库：动态称重零点跟踪与温漂补偿（复用 `FB_DL_MedianFilter` 剔除冲击样本 + `FC_DL_LinearScale` 温漂线性修正）→ **DL_Device** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_CasePackerPatternVerify`：装箱排列模式校验与防错（复用 `FC_DL_RangeOverlapCheck` 判断相邻箱位重叠 + `FB_DL_RecipeManager` 模式放行，重叠即拒启）→ **DL_Process** ｜ **P2** `[R11 新增]`

### 16.5 暖通 / HVAC（+5 项）

- [x] `FB_DL_AhuFanArrayTrim`：空调箱风机阵列静压微调（复用 `FB_DL_FanArrayStageCtrl` 分级投切〔前置待办件〕 + `FB_DL_PidController` 静压闭环）→ **DL_Process** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_ChillerYearWinStart`：冷机年度启停窗与保养互锁（复用 `FB_DL_YearWindowCheck` 年窗 + `FB_DL_DutyStandbyRotation` 轮值，非窗期禁启）→ **DL_Process** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_DuctLeakRateEst`：风管泄漏率估算与能耗分摊（复用 `FC_DL_AirDensity` 空气密度修正 + `FB_DL_Integrator` 风量积分，泄漏率按区段分摊）→ **DL_Process** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_CoilFrostWindow`：盘管结霜窗口判定与除霜请求（复用 `FB_DL_ToleranceWindow` 霜层窗口 + `FC_DL_DewPointCalc` 露点判据，双条件才请求除霜）→ **DL_Device** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_VavBoxZeroCal`：变风量末端风量零点标定（复用 `FC_DL_LinearScale` 零点标定 + `FB_DL_SignalDebounce` 稳定判据，标定期间冻结调节）→ **DL_Device** ｜ **P2** `[R11 新增]`

### 16.6 过程控制 / Process Control（+5 项）

- [x] `FB_DL_SteamTrapDiagTrend`：疏水阀诊断趋势与批量台账（复用 `FB_DL_SteamTrapMonitor`〔§7.6 前置待办件〕 + `FB_DL_SignalStatistics` 温差趋势，台账按管网区段汇总）→ **DL_Device** ｜ **P1** `[R11 新增]`
- [x] `FB_DL_ReactorYearWinClean`：反应釜年度清洗窗与批次闸门（复用 `FB_DL_YearWindowCheck` 年窗 + `FB_DL_CipCleaningSeq` 清洗顺控，过窗未洗禁投料）→ **DL_Process** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_BatchDeviationAlarm` ✔ R28 入库（撞名另立名：`FB_DL_BatchDeviationTierAlarm`）：批次偏差分级报警与首出归因（复用 `FC_DL_LimitClassify` 四档分级 + `FB_DL_AlarmManager` 首出锁存，偏差超档自动升 P1）→ **DL_Process** ｜ **P1** `[R11 新增]`
- [x `FB_DL_OrificeDpZeroTrim`：孔板差压零点漂移补偿（复用 `FC_DL_Deadband` 零点死区 + `FB_DL_MedianFilter` 静流时段取样，长期零点跟踪）→ **DL_Device** ｜ **P2** `[R11 新增]`
- [x] `FB_DL_LoopAuditTrailWindow`：回路整定审计时间窗与变更留痕（复用 `FB_DL_TimeWindowCheck` 维护窗 + `FB_DL_RecipeManager` 参数集快照，窗内变更需双人确认位）→ **DL_Process** ｜ **P2** `[R11 新增]`

> **扩容统计**：R11 扩容 32 条（锂电 6 / 光伏 5 / 半导体 6 / 包装 5 / 暖通 5 / 过程控制 5），全部不与既有 263 条重名；`DL_Process` 15 条、`DL_Device` 10 条、`DL_Motion` 3 条、`DL_MathData` 1 条、`DL_Algo` 0 条、`DL_Base` 0 条（Level 0 本轮已补 6 件，年窗/回绕/区间/几何/随机/分位齐备，暂不缺件）。**主线三条**：① **年窗族**解锁 6 条「年度生效 / 年度保养 / 跨年窗口」类（`ChillerYearWinStart` / `ReactorYearWinClean` / `TrackerAngleYearWin` 等）；② **设备级粗粒度 + 通道诊断族**解锁 5 条「多通道健康度 / 状态字字段 / 端口看板」类；③ **工站四件套**解锁 6 条「曲线归档 / 通道排队 / 批次偏差 / 排列防错」类。其中 P0 一条（`FB_DL_PortDiagBoard`）为 R12 首批候选。

---

## 十七、R11 新增（Round 11 收口件，2026-11-15，ROADMAP 既有清单无对应条目，收口登记于此）

> 本轮 16 件收口：其中 `FB_DL_PressFitStation` / `FB_DL_RotaryIndexTable` / `FB_DL_AgvDockingHandshake` / `FB_DL_EnergySavingMode`（第六节）、`FB_DL_NtcTempScan` / `FB_DL_RollerGapAdjust` / `FB_DL_WindingTensionCtrl`（第七节）、`FB_DL_R2rEwmaTuner`（第七节）共 **8 条既有待办行已就地勾选**；以下 **8 件**既有清单无对应条目，收口登记。

- [x] `FB_DL_PortDiagAggregator`（DL_Device）：端口级诊断聚合与首出定位（8 端口 → 故障掩码 + 首出端口 + 首出诊断码 + 窗口差分错误风暴；风暴只单拍置位、不进 bError）（R11 立项，T1-7 PLCnext port-based 诊断族深化，414 行）
- [x] `FB_DL_StatusWordSegDecoder`（DL_Device）：设备状态字多字段解包（段表驱动 = 批量粒度层级；宽 64 段取常量掩码、**全程无 64 位移位**；重叠用占位掩码；先拒后移）（R11 立项，T2-1 LGF Bit Logic 批量位段开组 + T2-6 AOI 次源，383 行）
- [x] `FB_DL_YearWindowCheck`（DL_Base）：年度生效窗判定（年内序数法 + LINT 中间量防 INT 溢出 + 闰年 4/100/400 三级判定 + 两条 WHILE 折叠带 `DL_GUARD_MAX` 守卫；跨度整周期钳位）（R11 立项，T2-1 LGF Date and Timer 年粒度收口，494 行）
- [x] `FB_DL_RolloverCounter`（DL_Base）：回绕型计数器（回绕用「比较 + 赋值」**禁用 MOD**；圈数饱和 ±上限；上限非法退化冻结 + 0218；0120 为信息级不置 bError）（R11 立项，T2-1 LGF Counter 回绕族收口，383 行）
- [x] `FC_DL_RangeOverlapCheck`（DL_MathData）：两区间关系判定（相等 → 相离 → 相接 → 包含 → 部分 五分支有序 + 兜底；重叠长度前置非负保护；无除法无循环）（R11 立项，T2-1 LGF Comparator 组；254 行。**规格原记 DL_Base，终审 E-01 改判 DL_MathData 并已同步索引**）
- [x] `FC_DL_CalcDistance3D`（DL_MathData）：三维两点距离（六输入有限性闸门 + 按最大分量归一化防平方溢出 + 后置守卫与非负钳位；**只做 3D，2D 为 `fZ1 = fZ2` 退化情形，拒绝拆变体**）（R11 立项，T2-1 LGF Math 组，227 行）
- [x] `FC_DL_RandomNext`（DL_MathData）：确定性伪随机下一值（种子进 / 种子出、无实例内存、同种子同序列；LCG 公开参数；零种子照常递推并置 `bZeroSeed` 提示）（R11 立项，T2-1 LGF Math 组 + T1-8 无状态 PRNG 接口形态，210 行）
- [x] `FC_DL_PercentileLReal`（DL_MathData）：样本分位值（R-7「排序 + 线性插值」口径；**拷贝排序不改调用方数组**；非有限样本前置剔除；末位不外插；排序未完成按空集返回）（R11 立项，T2-1 LGF Math 统计族深化，303 行）

> **收口统计**：R11 共 16 件 **6,310 行**，registry 152 → **168**（v2.0.0），总库 **48,827 行**；终审 **16/16 PASS**（修复后 PASS 2 件升 v1.0.1；缺陷 4 条：致命 2 / 严重 1 / 轻微 1）；同期修复**存量 7 件**（3 处编译阻断族）；新范式 **R33 / R34 / R35 / R36** 入册。

### 17.1 R11 收口说明（勾选与池子计数自洽）

1. **本轮勾选 8 条**：第六节 4 条（压装 / 分度盘 / AGV 对接 / 节能）+ 第七节 4 条（NTC 巡检 / 辊距微调 / 锥度张力 / R2R 微调），逐条 grep 确认条目存在后才由 `- [ ]` 改为 `- [x]`，并附「R11 交付 + 子库 + 关键技术点 + 行数」注记。
2. **本轮 8 件无对应行**（端口诊断聚合 / 状态字段解码 / 年窗 / 回绕计数 / 区间关系 / 3D 距离 / 随机下一值 / 分位数）**不新增勾选行**，统一登记于本节上方——与 R9（第十二节）、R10（第十四节）同一处置口径：通用原子件不为凑勾选而写入行业语汇池。
3. **池子计数**：行业待办池六批合计 **295 条**（103 + R5 32 + R6 32 + R7 32 + R9 32 + R10 32 + R11 32）；已勾选 **7 条**（`FB_DL_WindingTraverse`、`FB_DL_EnthalpyCompareCtrl`、`FB_DL_OccScheduleWindow` 三条历史项 + 本轮 4 条），**未勾选 288 条**。注：`§9.6` 末行因历史排版把两条候选合写在一行（`FB_DL_TankN2BlanketCtrl` 与焓值函数的说明文字并排），故**行计数 294、条目计数 295**，本轮未动该行以免误伤历史记录。
4. **Phase 1 六节（§1~§6）**：`DL_Process` 四条 P0 勾选后第六节 **16 项全部交付、待办 0**（子库合计 20 项全部落地，另 4 项分别登记于 §8 / §9.5 / 第十二节）；`DL_Device` 仅余电表 1 项未勾选（立项前需先定「数据模型 + 冻结/非冻结寄存器」契约）。
5. **库规模抬头**：`168 / 10,000`、总库 `v2.0.0`、六子库计数 34 / 33 / 25 / 40 / 16 / 20，与 `INDEX_REGISTRY.json`（total_components=168）逐项一致。


---

## 十八、R12 新增（Round 12 收口件，2026-11-15，ROADMAP 既有清单无对应条目，收口登记于此）

> 本轮 18 件收口：其中 `FB_DL_VacuumGaugeMux`（§7.3）、`FB_DL_ValveCharacteristic` / `FB_DL_BatchPhaseBase`（§7.6）、`FB_DL_PollTempBank`（§13.6 P0）、`FB_DL_PortDiagBoard`（§16.3 P0）共 **5 条既有待办行已就地勾选**；以下 **13 件**既有清单无对应条目（Level 0 原子算子与 Level 1 底座件，按 R9/R10/R11 同一口径不为凑勾选而写入行业语汇池），收口登记于此。

- [x] `FC_DL_BitArrayExtract`（DL_Base）：跨字位窗提取（起位 0~127、宽度 1~64，最多跨两字拼接；`SHL/SHR` 移位量一律 `MOD 32` 保证 0~31，宽 64 走常量掩码分支**全程无 64 位移位**；有效宽度按 `64 − 偏移 mod 32` 截断并置 0127）（R12 立项，T2-1 LGF Bit Logic 数组批量位段开组，237 行）
- [x] `FC_DL_BitArrayInsert`（DL_Base）：跨字位窗读改写（先算掩码再读旧值、改动计数**只在值真变时递增**、值未变的字既不计数也不写——「宁可一字不写，不写半个字」；早退路径零写入）（R12 立项，T2-1 同族，247 行）
- [x] `FC_DL_IntervalMembership`（DL_Base）：区间成员判定（`E_DL_IntervalKind` 四组合显式成员 + 兜底；端点用 `fEps` 容差判「贴界」，否则浮点误差会让 `[60,80)` 在 `60.000000001` 上判出不在区间；退化区间单列判据；裕量输出为「到最近有效边界的带符号距离」）（R12 立项，T2-1 LGF Comparator 组开闭区间语义 + 本库加严容差，214 行）
- [x] `FB_DL_BitArrayChangeWatch`（DL_Base）：跨字位图变化监视（异或 + 汉明重单趟扫描 + 首变位定位（`(字序号−1)×32 + 位号`）+ 无变化判稳计数 + 跳变计数饱和；三态 `eIdle/eSampling/eFault`）（R12 立项，T2-1 同族；320 行，v1.0.1 修复掉使能抢在 CASE 前强置空闲致故障复位无效 A-D03）
- [x] `FC_DL_ArrayDiffSummary`（FC，DL_MathData）：数组逐项偏差汇总（偏差数 / 首差下标 / 最大偏差及其下标；非有限输入**与**非有限中间量双判据——有限减有限仍可能溢出为无穷；并列取先出现）（R12 立项，T2-1 LGF Comparator 数组批量比较，204 行）
- [x] `FC_DL_StringReplaceAll`（DL_MathData）：字符串全模式替换（模式串空硬闸先于任何 `FIND`；游标严格前进防「替换串含模式串」死循环；双闸退出＝用户次数上限 0131 / 串型上限 0132）（R12 立项，T2-1 LGF Data Handling 字符串族；264 行，v1.0.1 修复 `LEFT` 隐性回夹致截断标志恒假 A-D01）
- [x] `FB_DL_StringTokenStream`（DL_MathData）：报文流式分词（四态 `eIdle/eReady/eDraining/eFault`；连续分隔符产生**空段且空段仍占序号**；`nMaxTokens` 上限锁 021D；取段一律以**锁存副本**长度为准）（R12 立项，T2-1 同族，本件为新形态；317 行，v1.0.1 修复实时帧长与锁存副本混用 A-D02）
- [x] `FC_DL_SolarPositionCalc`（DL_MathData）：太阳位置计算（NOAA 公开傅里叶级数：赤纬 7 项 + 均时差 5 项；输入本地标准时 + 经纬度 + 时区偏移，输出赤纬/均时差/真太阳时/时角/高度角/方位角；方位角正北 0 顺时针，天顶不可辨统一置正南 180；`ASIN` 入参先 `LIMIT`、时角与方位角归一用**条件加减不用 MOD**）（R12 立项，T2-1 LGF Date and Timer 天文钟族收口，301 行）
- [x] `FC_DL_ModbusExceptionParse`（DL_MathData）：Modbus 异常响应解析（功能码 bit7 判异常帧 → 取低 7 位原功能码 → 查 01/02/03/04/05/06/08/0A/0B 语义 → 中文名 + 严重度 + 可重试性三出口；分级判据本库自有：01/02/03 与 0B 归 eFault，其余归 eWarn 可重试）（R12 立项，T1-3 OSCAT Network 诊断帧解析开组 + Modbus 规范 V1.1b3 公开条款，210 行）
- [x] `FC_DL_WaterEnthalpy`（DL_Algo）：饱和液水比焓与平均比热（三点比热拟合成多项式，0 °C 基准；温度落零度点走常量分支并置 2102；域外早退保持安全侧；精度承诺与适用域写死在头注释）（R12 立项，T1-2 OSCAT Building `WATER_ENTHALPY` 行为定义 clean-room，131 行）
- [x] `FB_DL_DeviceParamVerify`（DL_Device）：设备参数回读校验（六态 `eIdle/eWaiting/eComparing/eMatch/eMismatch/eFault`；逐项容差 + 明细偏差 + 首差下标 + 最大偏差；结论锁存 + 核对超时；**信息码按核对周期清除**，防首轮码永久压住后续码）（R12 立项，T1-4 CODESYS Forge `DeviceReader` 读-比-判三段骨架，许可不明按最严口径零复制；368 行，v1.0.1 修复 014E 驻留 B-D06）
- [x] `FB_DL_EnergyMeterAccum`（DL_Device）：电表累计与窗口需量（32 位高低字拼装 + 单调性判据 + **换表识别＝累计值回退即重载基准**（按累计值比例而非满量程比例）+ 窗口需量/峰值需量；四态 `eIdle/eSampling/eHeld/eFault`，掉使能进 `eHeld` 并保持累计）（R12 立项，NAMUR NE43「原始值域诊断与工程量分离」原则；433 行，v1.0.1 修复暂停恢复后剩余窗基准错位 B-D03）
- [x] `FB_DL_LineInterp2Axis`（DL_Motion）：两轴直线插补（八态 `eIdle/ePrep/eAccel/eCruise/eDecel/eDone/eHeld/eFault`；单位向量分解 → 合成速度按单轴上限折算 → 梯形/三角自适应（两侧加速距离和**恰等于**路径长时判梯形）；端点钳位 + 收尾速度下限防爬行；**恢复时按剩余量分流**并按位移与速度双条件转出）（R12 立项，T1-8 GitHub topics motion 线开组，社区共识写法；476 行，v1.0.1 修复暂停恢复速度阶跃 B-D04）

> **收口统计**：R12 共 18 件 **5,880 行**（`wc -l` 实测，送审 5,777 → 修复后 5,880），registry 168 → **186**（v2.1.0）；终审 **PASS with fixes**（10 件升 v1.0.1），缺陷 **15 条：致命 3 ／ 严重 5 ／ 中等 3 ／ 注释级 4**；规格勘误 13 处；新范式 **R37 / R38 / R39 / R40 / R41 / R42 / R43 / R44** 八条入册。

### 18.1 R12 收口说明（勾选与池子计数自洽）

1. **本轮勾选 5 条既有待办**：§7.3 真空计融合、§7.6 阀特性补偿与批次相基类、§13.6 温控轮询采集行（P0）、§16.3 端口诊断看板（P0）。逐条 grep 确认行存在后才由 `- [ ]` 改为 `- [x]`，并附「R12 交付 + 子库 + 关键技术点 + 实测行数」注记。**两条 P0 就此清零，行业池 P0 待办降为零。**
2. **本轮 13 件无对应行**（跨字位段读/写/监视、区间成员、数组比对、字符串全替换与分词、太阳位置、Modbus 异常帧、水焓值、参数回读校验、电表累计、两轴插补）**不写入行业语汇池**，统一登记于本节上方——与 R9（第十二节）、R10（第十四节）、R11（第十七节）同一口径。
3. **池子计数**：行业待办池合计 **326 条**（103 + R5 32 + R6 32 + R7 32 + R9 32 + R10 32 + R11 32 + R12 31）；已勾选 **12 条**（`FB_DL_WindingTraverse`、`FB_DL_EnthalpyCompareCtrl`、`FB_DL_OccScheduleWindow` 三条历史项 + R11 四条 + R12 五条），**未勾选 314 条**。历史口径遗留：`§9.6` 末行把两条候选合写在一行，故行计数比条目计数少 1（该行本轮未动）。
4. **Phase 1 六节（§1~§6）**：`DL_Process` 本轮再补两件后第六节 **18 项全部交付、待办 0**（子库合计 22 项全部落地）；`DL_Device` 仅余电表契约件 1 项未勾选（`I_DL_PowerMeter` + `FB_DL_ModbusPowerMeter`，数据模型已由本轮 `FB_DL_EnergyMeterAccum` 跑通，R13 可顺势立项）。
5. **库规模抬头**：`186 / 10,000`、总库 `v2.1.0`、六子库计数 38 / 38 / 27 / 44 / 17 / 22，与 `INDEX_REGISTRY.json`（total_components=186）逐项一致。

---

## 十九、行业方向待办池 R12 扩容 / Industry Backlog Pool R12 Expansion（+31 项，总 295 → 326 项，不计入 Phase 1 的 100 项配额）

> **扩容依据**：本轮 18 件把 Level 0/1 的「跨字位段 / 定长字符串 / 区间关系 / 天文钟 / 参数回读 / 电表累计 / 两轴插补 / 批次相」八类底座补齐，行业池据此新开六个方向：**涂布与卷绕几何量、组串级电学一致性、腔体与载具气氛、封口与标签可追溯、水路与风阀诊断、阀门与换热器本体健康**。全部条目**只编排既有 Level 0/1 能力**，不内联底层算法。

### 19.1 锂电 / Lithium Battery（+5 项）

- [x] `FB_DL_CoatingGapMeasure`：涂布留白（Gap）宽度与边缘对齐偏差判定（复用 `FC_DL_LinearScale` 像素→毫米标定 + `FC_DL_IntervalMembership` 上下限带判定 + `FB_DL_SignalStatistics` 窗口一致性）→ **DL_Process** ｜ **P1** `[R12 新增]` → **已落地 R30（v2.19.0）**
- [x] `FB_DL_RollCompressForceBalance`：辊压机两侧轧制力平衡监视与液压纠偏（复用 `FB_DL_ToleranceWindow` 左右压差窗 + `FB_DL_PidController` 纠偏闭环 + `FB_DL_RateLimiter` 纠偏限速）→ **DL_Process** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_WindingAlignEdge`：卷绕极片边缘跟随与蛇形抑制（复用 `FB_DL_MarkPositionLatch` 边缘位置锁存 + `FB_DL_LowPassFilter` 边缘滤波 + `FB_DL_SoftLimitGuard` 纠偏行程拦截）→ **DL_Motion** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_FormationTempRiseRate`：化成温升速率监视与异常电芯截断（复用 `FB_DL_Differentiator` 温升速率 + `FB_DL_IntervalMembership` 工艺窗口 + `FB_DL_AlarmManager` 分级报警）→ **DL_Process** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_SelfDischargeScreen`：电芯自放电（OCV 压降）分选判据（复用 `FC_DL_LinearScale` 压降归一 + `FC_DL_PercentileLReal` 批次分位基线 + `FB_DL_ToleranceWindow` 分档判定）→ **DL_Process** ｜ **P2** `[R12 新增]`

### 19.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_TrackerSnowShedAngle`：跟踪支架雪载卸荷角与复位（复用 `FB_DL_YearWindowCheck` 采暖季窗 + `FC_DL_SolarPositionCalc` 太阳高度角 + `FB_DL_RateLimiter` 置角限速）→ **DL_Motion** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_StringCurrentMismatch`：组串电流失配诊断与遮挡定位（复用 `FB_DL_SignalStatistics` 组串电流分布 + `FC_DL_PercentileLReal` 中位基线 + `FC_DL_LimitClassify` 失配分级）→ **DL_Process** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_LamEvaGelContent`：层压 EVA 交联度（凝胶含量）估算（复用 `FB_DL_Integrator` 温度-时间积分 + `FC_DL_MultiPointLinear` 交联度标定曲线 + `FB_DL_ToleranceWindow` 合格窗）→ **DL_Process** ｜ **P2** `[R12 新增]`
- [x] `FB_DL_InverterDeratingCtrl`：逆变器温度/电压分段降额与功率限值（复用 `FB_DL_StepController` 分级降额 + `FB_DL_RateLimiter` 功率爬坡限速 + `FB_DL_AlarmManager` 降额原因上报）→ **DL_Device** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_JunctionBoxPottingCheck`：接线盒灌胶量与固化判定（复用 `FB_DL_DeviceParamVerify` 工艺参数回读比对 + `FB_DL_Integrator` 灌胶流量积分 + `FC_DL_IntervalMembership` 胶量窗）→ **DL_Process** ｜ **P2** `[R12 新增]`

### 19.3 半导体 / Semiconductor（+5 项）

- [x] `FB_DL_EscHeLeakCheck`：静电吸盘（ESC）氦背冷泄漏率判定（复用 `FC_DL_LinearScale` 流量→漏率换算 + `FB_DL_RateLimiter` 升压斜率限制 + `FB_DL_ToleranceWindow` 漏率门限分级）→ **DL_Process** ｜ **P1** `[R12 新增]`（**R13 交付**；升压/稳压/测量三段定时器逐段断输入 + 稳压延长窗独立裁决 + 温漂修正带温差门限；564 行，v1.0.1 修复稳压延长窗提前进测量 D-C4-1）
- [x] `FB_DL_ChamberSeasoningTrack`：腔体 seasoning 片数与膜厚台账及放行（复用 `FB_DL_RecipeManager` seasoning 配方 + `FB_DL_RuntimeMeter` 累计工艺时长 + `FB_DL_ToleranceWindow` 膜厚窗放行）→ **DL_Process** ｜ **P1** `[R12 新增]`（**R13 交付**；片数 ∧ 时长双判据放行 + 累计制工艺时长台账 + 连续越窗降级 + 溢出守卫；435 行，终审 PASS 零修改）
- [x] `FB_DL_PrecursorCanisterWeight`：前驱体源瓶称重与余量预测（复用 `FB_DL_MedianFilter` 称重去毛刺 + `FB_DL_Integrator` 消耗速率积分 + `FB_DL_DeviceParamVerify` 换瓶参数核对）→ **DL_Device** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_NotchAlignSeq` ✔ R28 入库：晶圆缺口（Notch）对位顺控（复用 `FB_DL_MarkPositionLatch` 缺口位置锁存 + `FB_DL_AxisRelativeMove` 对位微调 + `FB_DL_StepSequencer` 步序与超时）→ **DL_Motion** ｜ **P2** `[R12 新增]`
- [x] `FB_DL_FoupPurgeN2Flow`：FOUP 氮气吹扫流量与湿度监视（复用 `FB_DL_PulseFlowMeter` 流量计量 + `FC_DL_DewPointCalc` 露点判据 + `FB_DL_ToleranceWindow` 吹扫合格窗）→ **DL_Device** ｜ **P2** `[R12 新增]`

### 19.4 包装 / Packaging（+5 项）

- [x] `FB_DL_CapperTorqueTrend`：旋盖扭矩曲线与滑牙/歪盖判据（复用 `FB_DL_SignalStatistics` 扭矩峰值统计 + `FC_DL_PercentileLReal` 批次分位 + `FB_DL_AlarmManager` 滑牙分级）→ **DL_Process** ｜ **P1** `[R12 新增]`（**R13 交付**；五类 NG 判据主判定优先级（滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常）+ 双枚举 + 分位引脚注入不内联；617 行，v1.0.1 修复评估中故障不转故障态 D-C3-1）
- [x] `FB_DL_CoderRibbonLife`：打码色带寿命与浓度衰减监视（复用 `FB_DL_RuntimeMeter` 打印次数累计 + `FB_DL_SignalStatistics` 浓度趋势 + `FB_DL_DeviceParamVerify` 打码参数核对）→ **DL_Device** ｜ **P2** `[R12 新增]`
- [x] `FB_DL_ConveyorMetalDetect`：金属检测机剔除联动与过检率统计（复用 `FB_DL_AlarmManager` 检出首出 + `FB_DL_ConveyorZone` 剔除段放行 + `FB_DL_EventCounter` 过检计数）→ **DL_Process** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_ShrinkFilmUsageCalc`：收缩膜单包耗量与成本核算（复用 `FC_DL_LinearScale` 膜长→重量换算 + `FB_DL_Integrator` 膜长积分 + `FB_DL_OeeCalculator` 产量口径对齐）→ **DL_Process** ｜ **P2** `[R12 新增]`
- [x] `FB_DL_PalletLabelVerify`：托盘标签/EAN 校验与错标拦截（复用 `FC_DL_StringTrim` 与 `FC_DL_StringSplit` 条码分段 + `FC_DL_Crc16Modbus` 校验位复算 + `FB_DL_InterlockMatrix` 错标拦截）→ **DL_Process** ｜ **P2** `[R12 新增]`

### 19.5 暖通 / HVAC（+5 项）

- [x] `FB_DL_StratificationGuard`：水箱/风管温度分层监视与混温抑制（复用 `FB_DL_SignalStatistics` 上下点温差 + `FB_DL_ToleranceWindow` 分层门限 + `FB_DL_PidController` 混水泵调节）→ **DL_Process** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_ChwDifferentialPressureReset`：冷冻水最不利环路压差重置（复用 `FB_DL_MovingAverage` 压差平滑 + `FB_DL_PidController` 压差闭环 + `FB_DL_RateLimiter` 设定值重置限速）→ **DL_Process** ｜ **P1** `[R12 新增]`〔注：已由 R30 序 18 `FB_DL_ChwDifferentialPressure` 并案（设定值重置限速引脚已纳入），不另立——R30 收口注记〕
- [x] `FB_DL_AhuDamperStuckDiag`：风阀执行器卡滞诊断（复用 `FB_DL_DeviceParamVerify` 指令-反馈偏差比对 + `FB_DL_Differentiator` 反馈停滞判据 + `FB_DL_AlarmManager` 卡滞告警）→ **DL_Device** ｜ **P1** `[R12 新增]`（**R13 交付**；Rockwell AOI 三分类借用（全卡滞/过渡卡滞/I-O 失效）+ 两工艺级（偏差/迟缓）+ 三分类判据各带独立确认窗；615 行，v1.0.1 修复 I-O 失效绕过确认窗 A5-D1）
- [x] `FB_DL_BoilerFlueCondenseGuard`：冷凝锅炉烟气冷凝与回水温度保护（复用 `FC_DL_DewPointCalc` 露点判据 + `FB_DL_Hysteresis` 回水温度迟滞 + `FB_DL_ThreePointValve` 混水阀调节）→ **DL_Process** ｜ **P2** `[R12 新增]`
- [x `FB_DL_RoomCo2DemandVent`：CO₂ 需量通风与新风阀联动（复用 `FC_DL_LinearScale` 浓度标定 + `FB_DL_PidController` 需量闭环 + `FB_DL_TimeWindowCheck` 非工作时段下限）→ **DL_Process** ｜ **P2** `[R12 新增]`

### 19.6 过程控制 / Process Control（+6 项）

- [x] `FB_DL_ValveStictionDetect`：调节阀黏滞（Stiction）检测（复用 `FB_DL_MarkPositionLatch` 指令-阀位对锁存 + `FC_DL_IntervalMembership` 椭圆判据带 + `FB_DL_PeakDetector` 跳变捕获）→ **DL_Device** ｜ **P1** `[R12 新增]`（**R13 交付**；黏滞带/停滞/反转三判据合取升级 + 等级→NE107 健康映射（黏滞是退化不是失效）+ 挂起恢复首窗只重建不发布；735 行，v1.0.1 修复裸时间字面量 A4-D1）
- [x] `FC_DL_OrificeFlowCalc`：孔板差压流量计算（复用 `FC_DL_FlowCompensate` 温压补偿 + `FC_DL_NthRoot` 开方 + `FC_DL_LinearScale` 量程换算；纯函数，无状态）→ **DL_MathData** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_HeatExchangerFoulingTrend`：换热器结垢趋势（传热系数衰减）诊断（复用 `FB_DL_SignalStatistics` 传热系数窗口基线 + `FB_DL_Differentiator` 衰减速率 + `FB_DL_AlarmManager` 清洗提醒）→ **DL_Process** ｜ **P1** `[R12 新增]`
- [x] `FB_DL_PumpCavitationGuard`：泵汽蚀判据与保护（复用 `FB_DL_SignalStatistics` 流量/扬程偏离 + `FB_DL_PeakDetector` 振动峰值 + `FB_DL_RateLimiter` 降速保护）→ **DL_Device** ｜ **P2** `[R12 新增]`（**R13 交付**；三判据同拍持续确认 + 只出降速请求不写变频频率（每次 −1 步不自动回升）+ 抑制窗「整个降速相」语义；559 行，v1.0.1 修复 5 处含兜底值污染判据门 A6-D2）
- [x] `FB_DL_ReactorJacketDeltaT`：反应釜夹套温差控温（放热反应抑制）（复用 `FB_DL_CascadePid` 釜温-夹套串级 + `FB_DL_SplitRangeControl` 冷/热媒分程 + `FB_DL_RateLimiter` 温差变化限速）→ **DL_Process** ｜ **P1** `[R12 新增]`（**R13 交付**；约束层 + 分程层组合，PID 输出引脚注入不内联；温差触限 0.5 K 回差锁存 + 冻结升温侧经限速器斜坡回 0；487 行，终审 PASS 零修改）
- [x] `FB_DL_FlowMeterKFactorDrift`：流量计 K 系数漂移核对（复用 `FB_DL_DeviceParamVerify` K 系数回读 + `FB_DL_FlowTotalizer` 批次总量比对 + `FC_DL_LinearScale` 漂移折算）→ **DL_Device** ｜ **P2** `[R12 新增]`
  - **注记（R68）**：§19.6 漂移件已于 R68 重建并注册（registry `source=r68-plan`，DL_Device v1.0.1；R68 终审就地修「组态锁存解除路径不可达」后升版）。原「已勾未注册」漂移差额就此清零。

> **扩容统计**：R12 扩容 **31 条**（锂电 5 / 光伏 5 / 半导体 5 / 包装 5 / 暖通 5 / 过程控制 6），全部不与既有 295 条及全库 186 个 POU 重名（逐条 grep 核验，命中数均为 0）；归属分布 `DL_Process` 14 条、`DL_Device` 8 条、`DL_Motion` 4 条、`DL_MathData` 1 条、`DL_Algo` 0 条、`DL_Base` 0 条（Level 0 本轮补 9 件，跨字位段/区间/字符串/天文钟四族已收口，暂不缺件）。**主线四条**：① **几何量在线测量族**（涂布留白 / 边缘跟随 / 极片蛇形）解锁 3 条，全部消费本轮新增的区间成员与锁存件；② **电学一致性族**（组串失配 / 自放电 / 降额）解锁 3 条，消费分位与分级件；③ **气氛与洁净族**（ESC 氦检 / FOUP 吹扫 / FOUP 前驱体）解锁 3 条，消费露点与流量件；④ **本体健康族**（阀门黏滞 / 换热器结垢 / 泵汽蚀）解锁 3 条，是本库第一次把「设备本体退化」而非「工艺偏差」作为立项对象。**本轮扩容 P0 为零**，P1 十四条为 R13 首批候选。

---

## 二十、R13 新增（Round 13 收口件，2026-11-16，ROADMAP 既有清单无对应条目，收口登记于此）

> 本轮 18 件收口：其中 `I_DL_PowerMeter` & `FB_DL_ModbusPowerMeter`（§4）、`FB_DL_EscHeLeakCheck`（§19.3）、`FB_DL_ChamberSeasoningTrack`（§19.3）、`FB_DL_CapperTorqueTrend`（§19.4）、`FB_DL_AhuDamperStuckDiag`（§19.5）、`FB_DL_ValveStictionDetect` / `FB_DL_PumpCavitationGuard` / `FB_DL_ReactorJacketDeltaT`（§19.6）共 **9 条既有待办行已就地勾选**；以下 **9 件**既有清单无对应条目（接口契约件 + Level 0 原子件 + Level 1 底座件，按 R9/R10/R11/R12 同一口径不为凑勾选而写入行业语汇池），收口登记于此。

- [x] `I_DL_DeviceHealth`（DL_Device）：设备健康 NE107 契约接口（同文件 `E_DL_Ne107Status` 六态枚举 `eFailure/eCheckFunction/eMaintenanceReq/eOutOfSpec/eOk/eUnknown`，**编号即仲裁优先级**（0 最优先，与 NE107 图标序刻意不同——按图改号会让全部实现块仲裁方向静默反转）；10 条只读属性 + 2 指令方法；CmdAck 不得应答 eFailure、CmdReset 仅锁存态受理；全库唯一属主，实现块只引用不重复声明）（R13 立项，NAMUR NE107「设备健康与故障处理状态」语言落地开族，146 行）
- [x] `FC_DL_BitArrayRotate`（DL_Base）：跨字位数组循环旋转（「整字偏移 k + 字内偏移 r」双移位合成路径；方向归一负值恒右移；|nShift|>127 **或**跨整圈均置 013D 归约提示；`SHL/SHR` 移位量结构性限制 1~31，全程无 64 位移位；nWords=0 早退零写入）（R13 立项，T2-1 LGF Bit Logic 位旋转开族；3000 组随机位守恒与参考实现逐组对拍；252 行）
- [x] `FC_DL_MaskCompare`（DL_Base）：带掩码比较与首差定位（判据 `(uValue XOR uExpect) AND uMaskEff` 与规格「掩码域相等」数学等价；差位图 + 差异位数 + 首差位号；位宽 32 走常量掩码分支**全程无 `SHL(1,32)`**；零掩码恒匹配置 0140 提示）（R13 立项，T2-1 LGF Bit Logic + LGF Comparator 双源；191 行）
- [x] `FC_DL_Crc8`（DL_MathData）：CRC-8 三变体校验（同文件 `E_DL_Crc8Variant`：ATM 07/00/00、SAE-J1850 1D/FF/FF、HITAG 1D/FF/00；`"123456789"` 校验值 F4/4B/B4 与公开 CRC 目录三方一致；反射型 MAXIM-DOW 明确不并入本枚举（反射是另一套位序算法族，留独立件）；超长先置 bTruncated 再钳 128、非法变体回退 ATM + 0142）（R13 立项，T2-1 LGF Data Handling 校验族 + T1-3 OSCAT Network 双源，233 行）
- [x] `FC_DL_StringToLReal`（DL_MathData）：字符串转 LREAL 容错解析（逐字符状态机：符号/整数/小数/指数四段；终态校验拦「只有符号 / 只有小数点 / 只有指数标记」半截输入；指数域 ±38 保护、超界夹 fMax 不出 Inf；有效数字 18 位封顶只损失超精度位；错误位置精确到字符）（R13 立项，T2-1 LGF Data Handling 数值解析开族，417 行）
- [x] `FC_DL_StringFixedField`（DL_MathData）：定宽字符串字段构造（**R37 四步样板件**：LEN 一次锁存 → 宽度比较 → `bTruncated` 先于任何写入 → 按 `bAllowTrunc` 分「截断写出 / 拒绝构造」；裁剪段逐字符 CONCAT 路径唯一；连续调用入口先清残留）（R13 立项，T2-1 LGF Data Handling 定宽族；245 行）
- [x] `FC_DL_Matrix3Inverse`（DL_MathData）：三阶矩阵求逆（Matrix 子族开族）与规格 V7 一致；500 组随机 A×A⁻¹≈I 逐组对拍；291 行，v1.0.1 修复头注释 V7 条件数数值勘误 B6-D1）
- [x] `FB_DL_FoulingResistanceEstimator`（DL_Algo）：换热器污垢热阻估计（Q = 流量×密度×比热×ΔT÷3600 量纲链复核对齐 kW；LMTD 等端差退化算术平均、温度交叉置 0 → 2211；传热系数倒数判零三重守卫；流量门限每拍对实时入参复验、不合格拒绝更新趋势样本；五态 `eIdle/ePrime/eTrack/eAdvice/eFault`）（R13 立项，T1-2 OSCAT Building 换热健康线 + 传热工程手册 K = 1/(1/h₁ + Rf + 1/h₂) 骨架 clean-room；558 行）
- [x] `FB_DL_PassiveHomingMonitor`（DL_Motion）：被动回零过程监视器（不定义轴状态、不发运动指令、不自造轴状态枚举——只消费实时位置/速度快照与上层事件；方向反转 + 位置超容差双判据一致性计数；布防超时/无运动检测双定时器逐段断输入；事件受理串 `bEnable AND NOT _bFaultCond` 防脏值直达 bReferenced 保持位）（R13 立项，T1-6 PLCopen Motion 被动回零语义 clean-room；464 行，v1.0.1 修复故障拍零化快照仍被采信 D-C2-1）

> **收口统计**：R13 共 18 件 **7,949 行**（`wc -l` 实测），registry 186 → **204**（v2.1.0 → **v2.2.0**）；终审 **18/18 PASS**（8 件升 v1.0.1；缺陷 16 条记录：中等 8 ／ 中高 1 ／ 提示 4 ／ 文档级 1，另 A4-D2 判断项裁定保留、规格侧勘误 4 处）；机检 16 条规则 0 FAIL 0 WARN；泳道 B 全部 6 件经总监 Python 独立验算逐位复现（CRC 逐位、位旋转 3000 组对拍、矩阵 500 组 A×A⁻¹≈I）。AI 训练集 JSONL 186 → **204 条**（新增 18 条 output 字节级注入；存量再同步 **20 条**，其中点名 2 件〔`FB_DL_InterlockMatrix` / `FB_DL_AgvDockingHandshake` 均升 v1.0.1〕+ 历史注释级漂移 18 件〔孤立分号清理与省略号润色，磁盘为终审后真值〕），全量 sha256 **204/204 一致**。下一批重点见「自我进化与批处理追踪记录」Round 14 段。

---

## 二十一、行业方向待办池 R13 扩容 / Industry Backlog Pool R13 Expansion（+30 项，总 326 → 356 项，不计入 Phase 1 的 100 项配额）

> **扩容依据**：本轮 18 件把「NE107 健康语言 / 位旋转 / 掩码比较 / CRC-8 / 数值解析 / 定宽字段 / 三阶矩阵 / 污垢热阻 / 被动回零监视」九类底座补齐，行业池据此新开六个方向：**电芯制造时序、光伏电站维护、半导体真空与配比、包装缺陷与剔除、暖通设备本体健康、过程稳态监视**。全部条目**只编排既有 Level 0/1 能力**，不内联底层算法；30 条均逐条 grep 核验与既有 316 条待办及全库 204 个 POU 不重名。

### 21.1 锂电 / Lithium Battery（+5 项）

- [x] `FB_DL_ElectrolyteFillVacuum`：注液真空度与静置计时台账（复用 `FB_DL_TimeWindowCheck` 静置窗 + `FB_DL_ToleranceWindow` 真空度门限 + `FB_DL_EventCounter` 批次计数）→ **DL_Process** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_StackPressureProfile`：叠片压力曲线与保压判定（复用 `FB_DL_RampSoakProfile` 压力段轮廓 + `FB_DL_ToleranceWindow` 保压窗 + `FB_DL_AlarmManager` 越窗分级）→ **DL_Process** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_CellOcvBinSort`：电芯 OCV 压差分档与落料位决策（复用 `FB_DL_ToleranceWindow` 档位带 + `FC_DL_LimitClassify` 档位归类 + `FB_DL_EventCounter` 档位计数）→ **DL_Process** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_LaserTabWeldTrack` ✔ R28 入库：极耳激光焊位移轨迹与虚焊特征监视（复用 `FB_DL_MarkPositionLatch` 焊点位置锁存 + `FB_DL_SignalStatistics` 轨迹窗口基线 + `FB_DL_Differentiator` 突变判据）→ **DL_Motion** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_PouchSwellingGauge`：软包电芯鼓胀厚度巡检与分级（复用 `FC_DL_LinearScale` 厚度标定 + `FC_DL_LimitClassify` 鼓胀分级 + `FB_DL_ToleranceWindow` 批次一致性）→ **DL_Device** ｜ **P2** `[R13 新增]`

### 21.2 光伏 / Photovoltaics（+5 项）

- [x] `FB_DL_LamTempUniformity`：层压板面温度均匀性诊断（复用 `FB_DL_SignalStatistics` 多点温度分布 + `FB_DL_ToleranceWindow` 均匀性窗 + `FB_DL_AlarmManager` 分区告警）→ **DL_Process** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_PvSoilingLossRate`：组件积灰（Soiling）损失率估算与清洗提醒（复用 `FB_DL_SignalStatistics` 组串功率基线 + `FB_DL_Differentiator` 衰减速率 + `FB_DL_ToleranceWindow` 清洗阈值）→ **DL_Process** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_CombinerArcDetect`：汇流箱直流拉弧特征判据（复用 `FB_DL_HighPassFilter` 高频分量提取 + `FB_DL_SignalStatistics` 波动窗 + `FB_DL_AlarmManager` 拉弧分级）→ **DL_Device** ｜ **P1** `[R13 新增]`
- [x `FB_DL_CleaningBrushWear`：清扫机器人刷辊磨损与换刷里程（复用 `FB_DL_EventCounter` 行程累计 + `FB_DL_SignalStatistics` 电流趋势 + `FB_DL_DeviceParamVerify` 换刷参数核对）→ **DL_Device** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_IvCurveScan`：IV 曲线扫描步进与异常拐点定位（复用 `FB_DL_RampGenerator` 电压步进 + `FB_DL_SignalStatistics` 电流采样一致性 + `FC_DL_LimitClassify` 拐点分级）→ **DL_Process** ｜ **P2** `[R13 新增]`

### 21.3 半导体 / Semiconductor（+5 项）

- [x] `FB_DL_VacuumPumpBasePress`：真空泵本底压强与恢复时间台账（复用 `FB_DL_MovingAverage` 压强平滑 + `FB_DL_ToleranceWindow` 本底门限 + `FB_DL_EventCounter` 恢复超时计数）→ **DL_Device** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_MfcRatioCheck`：MFC 流量配比偏差核对（复用 `FC_DL_LinearScale` 流量标定 + `FB_DL_ToleranceWindow` 配比窗 + `FB_DL_DeviceParamVerify` 配方参数回读）→ **DL_Device** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_ChamberPumpDownSeq`：腔体抽真空顺控与漏率复测（复用 `FB_DL_TimeWindowCheck` 段时序 + `FB_DL_ToleranceWindow` 压降判据 + `FB_DL_RateLimiter` 放气限速）→ **DL_Process** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_RobotArmVibrationWatch`：晶圆传送机械手振动特征监视（复用 `FB_DL_HighPassFilter` 振动分量 + `FB_DL_SignalStatistics` 特征窗 + `FB_DL_AlarmManager` 预警分级）→ **DL_Device** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_LoadlockPressureCross`：Loadlock 压力交叉校验与误开拦截（复用 `FB_DL_ToleranceWindow` 双表偏差窗 + `FB_DL_InterlockMatrix` 误开联锁 + `FB_DL_AlarmManager` 首出定位）→ **DL_Process** ｜ **P2** `[R13 新增]`

### 21.4 包装 / Packaging（+5 项）

- [x] `FB_DL_FilmSpliceDetect`：薄膜接料（Splice）自动检测与降速通过（复用 `FB_DL_MarkPositionLatch` 接口位置锁存 + `FB_DL_ConveyorZone` 降速段放行 + `FB_DL_EventCounter` 接料计数）→ **DL_Process** ｜ **P1** `[R13 新增]` → **已落地 R30（v2.19.0）**
- [x] `FB_DL_FillWeightCheckweigher`：动态称重剔除与均偏自校准（复用 `FB_DL_MovingAverage` 重量平滑 + `FC_DL_LimitClassify` 欠/超重分级 + `FB_DL_EventCounter` 剔除计数）→ **DL_Process** ｜ **P1** `[R13 新增]` → **已落地 R30（v2.19.0）**
- [x] `FB_DL_BundleShrinkTemp`：热收缩炉温区曲线与停留时间窗（复用 `FB_DL_RampSoakProfile` 温区轮廓 + `FB_DL_TimeWindowCheck` 停留窗 + `FB_DL_ToleranceWindow` 温差门限）→ **DL_Process** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_CaseErectFaultSeq`：开箱成型失败重试与吸盘堵塞诊断（复用 `FB_DL_VacuumEjector` 真空判据 + `FB_DL_EventCounter` 重试计数 + `FB_DL_AlarmManager` 堵塞告警）→ **DL_Device** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_DateCoderPosition`：喷码日期位置偏移与缺失检测（复用 `FB_DL_MarkPositionLatch` 喷印位锁存 + `FC_DL_StringFixedField` 字段定宽解析 + `FB_DL_ToleranceWindow` 位置容差）→ **DL_Process** ｜ **P2** `[R13 新增]`

### 21.5 暖通 / HVAC（+5 项）

- [x] `FB_DL_ChillerLiftOptimize`：冷机 Lift（冷凝-蒸发温差）优化限值（复用 `FB_DL_SignalStatistics` 温差窗口基线 + `FB_DL_RateLimiter` 设定值限速 + `FB_DL_ToleranceWindow` 优化带）→ **DL_Process** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_VavPressureReset`：VAV 变风量系统静压重置（复用 `FB_DL_MovingAverage` 静压平滑 + `FB_DL_PidController` 静压闭环 + `FB_DL_RateLimiter` 重置限速）→ **DL_Process** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_HumidifierWaterQual`：加湿器水质电导率监视与排水联锁（复用 `FC_DL_LinearScale` 电导标定 + `FB_DL_TimeWindowCheck` 排水窗 + `FB_DL_ToleranceWindow` 水质门限）→ **DL_Device** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_FanBeltSlipDetect`：风机皮带打滑判据（转速-频率偏差）（复用 `FB_DL_Differentiator` 偏差速率 + `FB_DL_ToleranceWindow` 打滑窗 + `FB_DL_AlarmManager` 维护提醒）→ **DL_Device** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_FreezeStatGuard`：表冷器防冻保护与低温联锁（复用 `FB_DL_ToleranceWindow` 低温门限 + `FB_DL_ThreePointValve` 预热阀调节 + `FB_DL_AlarmManager` 冻结告警）→ **DL_Process** ｜ **P1** `[R13 新增]`

### 21.6 过程控制 / Process Control（+5 项）

- [x] `FB_DL_ColumnDpSteadyWatch`：精馏塔压差稳态监视与液泛预警（复用 `FB_DL_MovingAverage` 压差平滑 + `FB_DL_SignalStatistics` 稳态窗 + `FB_DL_ToleranceWindow` 液泛判据）→ **DL_Process** ｜ **P1** `[R13 新增]`
- [x] `FB_DL_SteamTrapSurvey`：疏水阀温度周期特征普查（复用 `FB_DL_SignalStatistics` 温度周期基线 + `FB_DL_TimeWindowCheck` 周期窗 + `FC_DL_LimitClassify` 失效分级）→ **DL_Device** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_PhaseNeutralImbalance`：三相不平衡度与中性线电流判据（复用 `FB_DL_SignalStatistics` 三相分布 + `FC_DL_LimitClassify` 不平衡分级 + `FB_DL_AlarmManager` 告警）→ **DL_Device** ｜ **P1** `[R13 新增]`
- [x `FB_DL_TankLevelStrapping`：储罐液位-容积分层标定与体积折算（复用 `FC_DL_LinearScale` 液位标定 + `FB_DL_ToleranceWindow` 标定核对 + `FB_DL_EventCounter` 收发油计数）→ **DL_Process** ｜ **P2** `[R13 新增]`
- [x] `FB_DL_BatchEndPointTrend`：批次反应终点趋势判据（复用 `FB_DL_Differentiator` 终点趋势 + `FB_DL_ToleranceWindow` 终点窗 + `FB_DL_AlarmManager` 终点超时）→ **DL_Process** ｜ **P1** `[R13 新增]`

> **扩容统计**：R13 扩容 **30 条**（锂电 5 / 光伏 5 / 半导体 5 / 包装 5 / 暖通 5 / 过程控制 5），全部不与既有 316 条及全库 204 个 POU 重名（逐条 grep 核验，命中数均为 0）；归属分布 `DL_Process` 18 条、`DL_Device` 11 条、`DL_Motion` 1 条（Level 0/1 本轮已收口九类底座，暂不缺件）。**主线四条**：① **时序台账族**（注液静置 / 保压 / 收缩停留）解锁 3 条，消费时窗与轮廓件；② **本体健康族二批**（皮带打滑 / 疏水阀 / 防冻 / 拉弧）延续 R13「设备本体退化」立项对象，消费 NE107 健康语言底座；③ **真空与气氛族**（泵本底 / 抽真空顺控 / Loadlock 交叉）消费半导体 ESC 语言与容差件；④ **趋势终点族**（积灰损失 / 终点趋势 / 均偏自校准）消费差分与统计件。**本轮扩容 P0 为零**，P1 十七条为 R14 首批候选。

---

*R13 收口 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监（注册与语料收口线）*

---

## 二十二、R17 路线图增量 / Roadmap R17 Addendum（2026-11-16）

> **R17 收口核对**：本轮 20 件（LogEx / LogBaseEx / AmpDbToRatio / RatioToAmpDb / PwrDbToRatio / TimeToDintMs / DintMsToTime / TimeToLrealSec / LrealSecToTime / TodToDintMs / DintToRealChk / UdintToRealChk / LintToDintSat / RealToLintSat / LrealToLintSat / LwordToLrealChk / ShlLwordEx / ShrLwordEx / RolLwordEx / RorLwordEx）**均不在既有待办池**（T0 纯函数线第 4 轮新立变体），无需勾选，勾选不适用。以下为 R17 复盘补条（≤10 条）：

### 22.1 P0 码位治理专项（R18 必办，先于任何新件）

- [ ] **R18 码位改判专项**：修复 R17 收口实测发现的 7 组存量-R17 交叉撞车——LintToDintSat `0201→0220`、RealToLintSat `0202→0215`/预留 `0210→0216`、LrealToLintSat `0211→0213`/预留 `021B→0214`、ShlLwordEx `021D→0217`/预留 `021E→0218`、ShrLwordEx `0208→0219`；同步改 8 个 `.st` 头注释与正文码、registry code_segment、JSONL 对应 5 条 output（逐行替换 + sha256 复验）、两份 VERSION 台账与两份 MANUAL；改判后游标 **信息级 `0221` / 故障级 `0306`**。执行依据 R61「码位游标注册表实测」与 R58「源码是唯一事实源」。

### 22.2 T0 纯函数/变体线补位组（零检索，沿用 R14 三判据）

- [x] **（R20 收口）** `FC_DL_DtToDintEpoch` / `FC_DL_DintEpochToDt`：DT/DTL 日历族防御包装（Unix 纪元秒↔DATE_AND_TIME，秒域先判后算）→ **DL_MathData** ｜ **P0**（R17 被编译门槛评估拦下，R20 以「正向饱和 / 反解不饱和」分立策略落地，内建口径假设写进编译门槛段；实测验证仍挂在编译验证债）
- [x] `FC_DL_DintMsToTod`（R19 收口）：DINT 当日毫秒→TOD 反向转换（与 `FC_DL_TodToDintMs` 构成双向对，钳 0~86399999 ms）→ **DL_MathData** ｜ **P0**
- [x] `FC_DL_TimeRatioCalc`（R19 收口）：TIME 比值计算（tA/tB → LREAL 百分比，除子 tB=0 故障闸，LREAL 承载防溢出）→ **DL_MathData** ｜ **P0**（节拍/稼动率算法高频入口，现有 TimeDivChk 只出 TIME 不出比值）
- [x] `FC_DL_RatioToPwrDb`（R19 收口）：功率型反向件（dB = 10·log10(P)，与 `FC_DL_PwrDbToRatio` 构成双向对；R17 只落了幅值型反向 `RatioToAmpDb`，功率型反向缺位）→ **DL_MathData** ｜ **P0**
- [x] `FC_DL_LintToUdintSat`（R19 收口） / `FC_DL_UdintToLintChk`：LINT↔UDINT 交叉域饱和/告警对（补齐 R17 饱和族 LINT-DINT 后的交叉域缺口）→ **DL_MathData** ｜ **P1**
- [x] `FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx`：~~DWORD 32 位域补位~~ **拒立项定案（R63 实测）**：与存量 `FC_DL_ShlEx`/`ShrEx` 同义（后者头注释明示 DWORD 主类型实现，BYTE/WORD 显式转换后调用），显式命名对属凑数变体，不立项；L1122 防撞名注记同步注销（R14 已有 ShlEx/ShrEx 但落在 FC_DL_<Name>Ex 通用命名，如需 DWORD 显式命名对再评估，防重复立项先查重）→ **DL_Base** ｜ **P2**（疑似与存量同义，立项前必过 R61 式实测查重）

### 22.3 结构性缺口（非本轮产生，挂账防遗忘）

- [x] **编译验证债（连续 15 轮悬置）**：`FC_DL_TodToDintMs` 依赖 TOD_TO_TIME 链、`FC_DL_LrealSecToTime` 依赖 LREAL_TO_TIME 链，两件已在头注释声明三平台交付门槛；R18 起凡涉日历/TOD 内建链的新件一律先做编译门槛评估再派单。

---

*R17 收口 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监*

---

## 二十三、R20 路线图增量 / Roadmap R20 Addendum（2026-11-16）

> **R20 收口核对**：本轮 20 件（DtToDintEpoch / DintEpochToDt / DateToDintDays / DintDaysToDate / UdintToLintChk / WordToIntSat / DwordToIntSat / LwordToLintSat / BcdToByte / ByteToBcd / TodAddWrap / TodDiffWrap / SwapBytes64 / DintToStringTrim / LrealToStringTrim / DateAddDays / DateDiffDays / TimeAbsSat / LeapYearChk / SemaMutex）中，
> **§22.2 的「纪元对等」待办已于本轮勾选收口**（`DtToDintEpoch` / `DintEpochToDt`），其余 18 件为 T0 变体线新立变体、不在既有待办池，勾选不适用。

### 23.1 P0（R21 必办，先于任何新件）

- [ ] **编译验证债立项（连续 15 轮悬置，债务已扩大）**：R20 又新增 3 条日历内建链假设（`DT_TO_DINT` / `DINT_TO_DT` / `DATE_TO_DINT`），全库依赖平台内建口径的件已达两位数。R21 必须产出「最小 CODESYS V3.5 工程 + 二十件抽样编译」的一次性验证记录（含失败清单与替代实现），否则后续所有「委托内建」件都只有文本推演背书。
- [ ] **台账卫生断言脚本化（R86 + 两项元数据债）**：产出 `_verify_counts.py`，一次跑三项断言——① 六库 VERSION 组件数 vs `registry.counts`（杜绝 107/130 这类漂移）；② `registry.line_count` 口径统一（全库现存两种历史口径：102 条物理行 / 56 条含尾空行，R20 批内亦不一致，统一为物理行并回写）；③ 码位唯一性按「专用码零重叠 + 公共码子带白名单」双规则判（`DL_Algo 16#0002_00xx` 为 R3~R4 遗留公共码，建白名单而非改码——改码会破坏已发布契约）。
- [x] **JSONL 两条 CRLF 遗留归一化**：`FB_DL_SCurveGenerator` / `FB_DL_PulseDirStepper` 源码为 CRLF、语料为 LF，字节级 sha 不匹配（内容一致）。需一次性统一换行风格并复验 344/344 字节级 MATCH。

### 23.2 P1（下两轮，与主线并行）

- [ ] **三本 Level 1 手册历史件接口表续补**：`DL_Device` 余 53 件 / `DL_Motion` 余 21 件 / `DL_Process` 余 28 件；按 ≤10 件/轮、倒序推进（R88）。
- [x] `FC_DL_SwapBytes16` / `32` 的 64 位族反向复核：`SwapBytes64` 已复用 32 位件，需回头确认 16/32 位件的枚举域 `E_DL_ByteOrder` 是否覆盖 ABDC/BADC 等剩余排布，避免「64 位齐备而 32 位不全」的认知错觉。
- [x] `FB_DL_SemaMutex` 所有权审计扩展（v1.1 候选）：超时强制归还后，记录「被谁持过、持了多久、归还后是否被同一调用方立刻重申」，供现场定位死锁根因。
- [ ] 日历族 `DTL` 变体评估：本批只做 `DATE_AND_TIME`（秒精度），毫秒级 `DTL` 是否需要独立件，取决于 MES 台账的时间戳精度要求，先给验收粒度再立项。

### 23.3 P2（观察池，不占本轮配额）

- [x] `FC_DL_WordToIntSat` 故障槽全预留（只发信息级）：是否需要 `bRequireStrict` 引脚把「补码解释」升为故障级，看现场是否存在「超域即必须停机」的用例。
- [ ] `DateAddDays` 的 `DL_DATE_DAYS_MAX = 65535` 保守容器口径：三平台实测锚定后若 DATE 以秒承载，此常量需整体重定（连带四件日历/日期件），列入编译验证债的后续动作。
- [ ] `LIBRARY_MANUAL.md` 的 R18 / R19 两章仍缺（本轮只补 R20 章），按「增量优先」纪律留 R21 一并补齐。

---

---

## 24 R22 追加待办（2026-11-16 终审与产品复盘产物，≤10 条）

### 24.1 P0（R23 必办）

- [x] `FB_DL_SlitValveInterlock` / `FB_DL_PressureReliefMonitor` / `FB_DL_SteamTrapMonitor` / `FB_DL_LevelRadarValidate` / `FB_DL_CompressorSurgeGuard` / `FB_DL_ColumnDpCtrl` / `FB_DL_InertPurgeSeq` / `FB_DL_BatchTransferSeq`——R22 已落地（见 §7.x 对应行勾选）。
- [x] `FB_DL_BatchTransferSeq` 中止时序修复（v1.0.2 已修复）：v1.0.1 终审发现 bAbort 路径「先停泵后关阀」仅在单拍赋值次序上成立，泵停与关阀指令同拍发出，缺真实物理时序分隔——需增「泵惰转时间」引脚（默认值带单位注释）+ eAbort 两段化（停泵保持阀开 → 惰转窗满 → 关阀），并补中止时序验收向量。**R23 已修复（v1.0.2：bAbort 两段化 xCoastStop + tPumpCoastTime 惰转窗→关阀，新故障码 0005_0317，五条验收向量推演通过）**。
- [ ] 编译验证债破题（连续 18 轮悬置）：R22 起把「最小空工程编译 1 个子库」列为交付资格项——建议从 DL_Motion（本轮 +5 件、历史欠账 21 件未补手册）开始建空工程。

### 24.2 P1（R23~R24）

- [x] `FB_DL_MotionCmdQueue` 去重语义复核（v1.1 候选）：当前去重基准含「已发令条目」，对「重复定位到同一目标」的合法连发指令会误合并（01DA）——须给出「仅对队内未发条目去重」的改法或保留现状的理由段，二选一留痕。
- [ ] 三本 Level 1 手册历史件补录：Device 约 57 件 / Motion 约 26 件 / Process 约 30 件（R20/R21 两轮零触及，R22 已补本批 13 件）——每轮 ≤10 件倒序推进（R88 纪律）。
- [x] `FB_DL_SteamTrapDiagTrend`（§7.6 前置件 `FB_DL_SteamTrapMonitor` 已于 R22 落地，前置解除，可立项）。
- [x] `FB_DL_ColumnDpSteadyWatch`（R13 待办，前置压差调节件 `FB_DL_ColumnDpCtrl` 已落地，可立项）。

### 24.3 P2（观察池）

- [x] `FB_DL_InertPurgeSeq` 抽真空读数 `fVacMeas` 非有限门禁显式化：当前 NaN 经「判据恒假」走保守失败路径（行为安全但静默），若 R23 触碰本件则补 0311 复用门禁 + 注释。
- [ ] R22 终审暴露的「全量 sha 校验」口径升级：R19-2/R87 的重注入四步/五步之外，固化「每轮收口必须全量 384→N 行校验」——已在本轮修复 2 件历史换行漂移（SCurveGenerator / PulseDirStepper），规则 R102 留档。

---

*R22 收口 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监*

---

## R24 行业池增补（2026-11-17，总监终审线追加 6 条）

> 来源：本轮终审复盘中暴露的高频刚需缺口（暖通排湿 / 锂电超声焊 / 公用工程逼近度 / 热处理吹扫 / 包装码垛 / 光伏绝缘）。

- [x] `FB_DL_DryerExhaustHumidityCtl`：干燥排湿热回收风门（排湿焓值判据 + 回风混风域闸）→ `DL_Process`
- [x] `FB_DL_BusbarWeldMonitor`：Busbar 超声焊接能量包络监视（功率-振幅-时间三维窗口）→ `DL_Process`
- [x] `FB_DL_CoolingTowerApproachCalc`：冷却塔逼近度计算与风机台数优化（湿球基准，依赖 `FC_DL_WetBulbTempCalc` v1.1.0）→ `DL_Algo` ｜ **R25 落地 v1.0.0**
- [x] `FB_DL_NitrideFurnaceAmmoniaPurge`：氮化炉氨吹扫顺控（氨分解率判据 + 残氨排放联锁）→ `DL_Process`
- [x] `FB_DL_PalletizerLayerSeq`：码垛层排布顺控（奇偶层旋转矩阵，复用仿射族）→ `DL_Process` ｜ **R25 落地 v1.0.1**
- [x] `FB_DL_SolarStringGroundFault`：组串对地阻抗绝缘检测（不平衡电桥法，仅监视）→ `DL_Process` ｜ **R25 落地 v1.0.1**

---

## R25 认领与池子卫生注记（2026-11-17，总监规划线）

> 认领：本轮 18 条已在上文逐条标注「**R25 认领**」（§7.1×3 / §7.2×1 / §7.3×2 / §7.4×4 / §7.5×5 / R24 增补×3）。另 2 件不在本池立项：`FC_DL_Affine2DInvert`（T2-1 LGF Math 仿射子族补口）、`FB_DL_RoomClimateCtrl`（T1-2 OSCAT ROOM_CONTROL 开族），按源矩阵入口立项，避免池内重复登记（R85 不虚账）。

去重与卫生裁定（4 条，详见 `_Staging_Raw/2026-11-17/RAW_NOTES_R25.md` §3）：

- `FB_DL_PalletizerLayerSeq` 在 §7.4 与 R24 增补**双处登记**，按「一语义一件」合并，收口时两处一并勾选。
- `FB_DL_StringIVTrace`（§7.2）已于 R24 落地，属**已完成未勾选**项，收口时直接补勾。
- `FB_DL_CoolingTowerOpt`（§7.5）与 `FB_DL_CoolingTowerApproachCalc`（R24 增补）同语义 → 由后者承载，前者不再立项。
- `FB_DL_BusbarWeldMonitor`（R24 增补）与 `FB_DL_TabWeldingMonitor`（§7.1）同为三维包络窗机制 → 合并，R26 立 1 件；`FB_DL_DryerExhaustHumidityCtl`（R24 增补）与既有 `FB_DL_EnthalpyCompareCtrl` 重叠 → 缓议，须先出能量守恒边界表。

待办池实测：**337 条未勾选**（远超 30 条阈值），本轮按纪律只认领、不扩写。

*R25 规划线 ｜ 2026-11-17 08:29 ｜ 道莅工控代码库产品总监*

---

## R25 增补（2026-11-17，总监终审线追加 10 条）

> 来源：R25 终审（8 件定向推演 + 20 件交叉扫描）暴露的缺陷族与派单缺口；前 2 条为本轮挂账的收口项（R106 第二档），其余为产品视角的高频刚需补齐。

- [x] **P0｜`FB_DL_SplicerAutoJoint` 同步相超时收口**：`eSyncWait` 无自有计时器，新卷就绪但速度差持续超容差时无限期停留（`tPreAccelMax` 只在预加速相计时）。方案：新增 `tSyncMax : TIME := T#30S` 引脚（MINOR，v1.1.0），超时置 0351 并中止且绝不裁切；验收向量：速度差恒定 5%、容差 2% → `tSyncMax` 后 0351 且 `bCutCmd` 全程 FALSE。
- [ ] **P0｜批次共性清理：`eFault` 枚举无 CASE 标签（6 件）**：`ParticleCounterStat` / `CoolingTowerApproachCalc` / `InverterGridSync` / `HeatPumpDefrost` / `DuctStaticReset` / `DewpointReset`——激励消失后 ELSE 兜底码覆盖真因码（安全侧不变、故障仍锁存，属诊断保真缺陷）。方案：逐件补 `eFault:` 标签（安全侧输出照抄 ELSE、码保持、零码兜底留统一出口）+ 新增机检规则「枚举成员集合 ⊆ CASE 标签集合」（R128）。
- [ ] **P0｜机检规则口径分型修复**：码位槽数规则「5~6 槽」须按 POU 类型分型（`FC_` 纯函数 4 槽合法 / `FB_` 5~6 槽），并补「枚举成员 ⊆ CASE 标签」「安全侧赋值不得引用本闸判定集合内的量」（R124/R127）三条规则，上线前跑全库回归要求纯函数件假阳性 = 0。
- [x] **P1｜`FB_DL_PalletizerStation` 工站模板**（§653）：在层排布件（`FB_DL_PalletizerLayerSeq` v1.0.1）之上做整跺工站编排（进料/分层/缠膜/出跺），把本轮修好的旋转落点与脉冲契约直接复用，避免工站层重写几何。
- [x] **P1｜`FB_DL_VavBoxCtrl` 反馈诊断细化**：本轮终审留档 `fFbTolPct` 未纳入非有限闸（NaN 容差会使卡滞诊断静默失效，安全侧不动作），下轮补闸并把「诊断闸门覆盖数 = 声明输入数」纳入机检 G6 差集断言。
- [x] **P1｜暖通族横向补位（保持本轮族密度）**：`FB_DL_FanArraySeq`（风机阵列轮值 + 变频/工频混拖）、`FB_DL_ChwDifferentialPressure`（冷冻水差压旁通阀控制）——与本轮 `ChillerSeqMgr` / `VavBoxCtrl` / `DuctStaticReset` 同族，便于整站示例。 → **已落地 R30（v2.19.0）**
- [x] **P1｜`FB_DL_RoomClimateCtrl` 增补露点件降级可观测**：露点件不可用时现以降干球保守估计（联锁偏紧、方向正确），但无出口标志；下轮新增 `bDewDegraded` 输出（MINOR）让现场能区分「真结露风险」与「估算偏紧」。
- [x] **P2｜`FB_DL_EnergyMeterAccum` 类计量件的量纲链模板化**：把本轮 SolarString 的「量纲链 + 两端极限」头注释结构固化为模板片段，供后续公式类派单直接引用（R123/R131 落地载体）。
- [x] **P2｜`FB_DL_SolarStringGroundFault` 哨兵可区分性**：完全平衡退化分支与真实测量饱和（1.0E9 kΩ）当前不可区分，建议下轮评估新增 `bInsSaturated` 输出或用 `eState` 子相区分，避免上位趋势把哨兵当实测。
- [ ] **P2｜批次质量台账自动化**：本轮发现「eFault 标签缺失」在 7/20 件重复出现，说明编码自检清单缺项。下轮把「枚举成员 ⊆ CASE 标签」「单拍脉冲撤销点」「安全侧取值来源」三项加入派单内嵌自检清单（§5.4 七项 → 十项）。

*R25 终审线 ｜ 2026-11-17 ｜ 道莅工控代码库产品总监*


> **R27 勾选记录（10/19 条）**：本轮已实现且已勾选上表 10 条；余 9 条（L249 / L270 / L275 / L282 / L645 / L660 / L672 / L712 / L845）同为 R27 已入库件，按单轮勾选上限 ≤10 条规则于 R28 批量勾选，不在本轮追加新条目。
- [x] `FC_DL_SaturateAdd`：饱和加减 LINT 宽域钳制 → `DL_Base`（R38 新立并落地，`16#01_0_00`）
- [x] `FB_DL_ToggleButtonBank`：多路按钮组解算三模式 → `DL_Base`（R38 新立并落地，`16#01_0_01`）
- [x] `FC_DL_LinearRegression2Var`：二元回归 + 共线性判据 → `DL_MathData`（R38 新立并落地，`16#05_0_02`）
- [x] `FC_DL_OscillationIndex`：回路振荡指数 → `DL_MathData`（R38 新立并落地，`16#05_0_03`）
- [x] `FC_DL_PidLambdaTune`：IMC/λ 整定纯换算 → `DL_Algo`（R38 新立并落地，`16#02_3_83`）
- [x] `FC_DL_HeatExchangerLmtd`：LMTD + ε-NTU → `DL_Algo`（R38 新立并落地，`16#02_3_84`）
- [x] `FB_DL_CrossCorrelationDelay`：互相关时延估计 → `DL_Algo`（R38 新立并落地，`16#02_3_85`）
- [x] `FB_DL_SpindleOrientationStop`：主轴定向停止 → `DL_Motion`（R38 新立并落地，`16#04_0_A4`）
- [x] `FB_DL_ElectronicCamSwitchBank`：电子凸轮开关组 → `DL_Motion`（R38 新立并落地，`16#04_0_A5`）

---

## R56 增补（2026-11-20，总监规划线追加 ≤10 条）

> 来源：R56 规划线选题复盘（20 件新立真缺口 + R55 五抽返修承接口径）；当前未勾待办仅 14 条（低于 30 条阈值），按规则追加本节。逐件派单见 `_Staging_Raw/2026-11-20/ROUND_PLAN_R56.md`，来源留痕见同目录 `RAW_NOTES_R56.md`。

- [ ] **P0｜全库「先引用后声明」专项机检**：承接 R55 下轮排程首位（`FB_DL_BacdHvacPoll` 补 `_nCurRetry` 声明后），对全库 997 件跑标识符「引用先于声明」扫描（VAR 区外首次出现即报），产出失败清单挂返修账——防 `_nCurRetry` 型编译阻断族再犯（R55 扩检条款落地载体）。
- [ ] **P0｜R55 五件返修 JSONL 重注入核验**：`FB_DL_BacdHvacPoll` / `FB_DL_FopdtStepIdent` / `FB_DL_CoinCellAssembler` / `FB_DL_StringElImageMap` / `FB_DL_PackMlUnitMode` 五件统一 v1.0.1 返修后，对应语料行 sha256 逐行复验 + 全量 384→N 行校验（R102 口径），行为变更处在 CHANGELOG 标 MINOR 说明。
- [ ] **P1｜插值族三件选型对照表**：`FC_DL_HermiteInterp`（R56 新立）/ `FC_DL_CubicSplineInterp` / `FC_DL_LagrangeInterp` 在 MANUAL 中补「等距性 / 导数可得性 / 区间数」选型对照段，并在三件头注释互引分工声明（R216）。
- [ ] **P1｜2-DOF PID 选型指引**：`FB_DL_TwoDofPid`（R56 新立）落地后在 MANUAL_DL_Algo 补「设定值加权 β/γ 选型指引」，与 `FB_DL_PidController` 头注释互引分工声明（单自由度 vs 二自由度适用域）。
- [ ] **P1｜温度传感器线性化族补口评估**：`FC_DL_RtdLinearization`（R56 新立，Pt100/Pt1000 CVD）落地后，评估热电偶多项式线性化件（K/N/S 型 NIST ITS-90 公开系数）立项；与 `FC_DL_TempUnitConvert`（纯单位换算）、`FB_DL_NtcTempScan`（NTC B 值）三分工边界写死。
- [ ] **P2｜失重给料与批次定量选型段**：`FB_DL_LossInWeightFeeder`（R56 新立）与 `FB_DL_BatchDosingControl` 在 MANUAL 补「连续失重 vs 批次定量」选型段，防现场误用。
- [ ] **P2｜探针测量循环分工注记**：`FB_DL_AxisProbeMeasCycle`（R56 新立）与 `FB_DL_MarkPositionLatch` 头注释互引分工声明（锁存原子 vs 完整测量循环）补齐（R216 口径）。
- [x] **P2｜ESD 设备族扩位评估**：`FB_DL_VacIonizerBalance`（R56 新立）落地后评估「离子风机风速联锁」「ESD 接地连续性监视」两件是否立项（半导体 ESC 自研线延续，先拆可验收粒度）。——**R62 勾销**：两件均已立项并注册入册（`FB_DL_EsdGroundMonitor` R57 入库 / `FB_DL_IonFanInterlock` R62 入库，DL_Device），族内三项（平衡测量 / 接地连续 / 风机效能）齐备；R62 终审 D3（失能相报警未清零）挂 R63 首位。
- [x] **P2｜洁净室物流联锁族扩位评估**：`FB_DL_AirShowerInterlockSeq`（R56 新立）落地后评估「传递窗（Passbox）三段联锁」「更衣序列」两件是否立项。——**R62 勾销**：两件均已注册（`FB_DL_PassboxInterlockSeq` / `FB_DL_GowningRoomSeq`，DL_Process），R62 派单 §2.3 拒单留痕复核为「均已入库」，本项评估结论 = 不重复立项。
- [ ] **P2｜Kalman 双件 MANUAL 对照段**：`FC_DL_Kalman2DSmoother`（R56 新立）与 `FB_DL_KalmanFilter1D` 补「1D 标量 vs 2D 常速」对照段与适用域声明。

*R56 规划线 ｜ 2026-11-20 ｜ 道莅工控代码库产品总监*

- [ ] **P0｜失重给料件 v1.0.1 返修（R57 五抽严重项）**：`FB_DL_LossInWeightFeeder` eIdle 相输出清零 + eDose 失能迁移前归零 + 段 6 故障锁存拍安全侧归零（补丁见 `REVIEW_R57_R56SAMPLE.md`，v1.0.1 + JSONL 重注入复验）。（R57 新立）
- [ ] **P0｜「停机/空闲相输出清零」家族扫描**：以 Lwf 缺陷为引，全库扫描「CASE 相位机中 eIdle/eStop 分支不清零执行输出」模式（机检规则候选：安全侧赋值覆盖检查 R124 增补），产出失败清单挂返修账。（R57 新立）
- [ ] **P1｜TwoDofPid v1.0.1 手动相有限性闸**：`fManOut` 非有限拦截（NaN 直通 + 积分项永久污染，中缺陷），与输入闸 R151 全覆盖口径对齐。（R57 新立）
- [ ] **P1｜AxisAccelFeedforward v1.0.1 信息级成因恢复撤销**：有效拍回写 `_eFaulC := eNone`，对齐 TwoDofPid 段 10 范式（家族内一致性）。（R57 新立）
- [ ] **P1｜HydraulicAccumPreChg 温度域上界补口**：段 3 域闸补 `fTempC > 150.0 [摄氏度]` 上界（常量提级），防伪过充归因。（R57 新立）
- [ ] **P2｜TpRetrigger 与 PulseStretch 分工声明**：MANUAL_DL_Base 补「可重触发定时语义 vs 脉宽拉伸滤波」对照段，头注释互引（R216 口径）。（R57 新立）
- [ ] **P2｜EncoderQuadCount 与 ExternalEncoder 族分工声明**：DL_Base 计数原子 vs DL_Motion 轴侧编码器件的属主边界表（R31 家族高危区声明）。（R57 新立）
- [ ] **P2｜NightPurgeSeq 与 FrostProtectFreeze 分工声明**：冷量利用 vs 防冻保护双向分工，MANUAL 选型段补齐。（R57 新立）
- [ ] **P2｜T0 候选「Ex 系三后缀预查」流程固化**：候选生成前必跑 `StringXxxEx / XxxEx / XxxSat` 正交扫描（本轮 36 拟 19 拒，命中率 47%，R214 三查前置化）。（R57 新立）

*R57 规划线 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监*

## §R61 增补（2026-11-21，10 条）

- [ ] **P1｜TurretToolSelect 反向防抖落地**：旋转中反向请求应拒绝而非排队，补 `bRevRejected` 输出与 MANUAL 说明。（R61 新立）
- [ ] **P1｜SensorPairPlausibility 共因故障分级**：双侧同时跳变当前只报单一故障码，按 NE107 分「共因/单侧」两级。（R61 新立）
- [ ] **P1｜LineClearanceVerify 清线窗末退出**：窗到期仍在确认相时应转失败态并清放行，与 NightPurgeSeq 范式对齐。（R61 新立）
- [ ] **P2｜PhaseLossGuard 启动掩蔽窗参数化**：掩蔽时长当前固定，改为输入并加域闸。（R61 新立）
- [ ] **P2｜PidParamGuard 与 PidParamDriftAudit 对照段**：MANUAL_DL_Algo 补「在线闸 vs 离线审计」适用域对照表。（R61 新立）
- [ ] **P2｜WeightedPercentile 权重归零分支**：权重全零时应返回 eConfig 而非静默 0，补显式码。（R61 新立）
- [ ] **P2｜SortIndexLReal NaN 排序口径**：NaN 置末尾的口径需在 MANUAL 声明，与 MathData 族横比统一。（R61 新立）
- [ ] **P2｜RailPowerSequence 分级上电互锁矩阵化**：级间互锁当前写死 ELSIF，宜改常量矩阵便于扩级。（R61 新立）
- [ ] **P2｜AirDryerDiag 露点保持时长声明**：探头非有限时保持上次有效值，需声明最长保持窗口防陈旧数据误判。（R61 新立）
- [ ] **P2｜族避让台账单列**：R267 族避让（Algo/Process）执行结果按族单列一行，纳入矩阵拒单台账。（R61 新立）

*R61 规划线 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监*

*R62 规划线 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监*

- **【防撞名注记 ①】** `FC_DL_IntToUdintSat` **语义并入 `FC_DL_SignedToUdintSat` 重载，禁新增文件**：R62 已在 `FC_DL_SignedToUdintSat` 头注释写死该并入口径（16 位入口若需要，按重载而非新建，防同义邻件）。后续任何派单不得再以「INT→UDINT 饱和」为名立项，选题三查（R214）命中即拒。
- **【防撞名注记 ②】** `FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx` 与存量 `FC_DL_ShlEx` / `ShrEx` **语义差未实测**：本轮按 ROADMAP L948 自标「疑似同义」继续回避，**不立项**；下轮（R63）出「输入域 × 移位量」边界差表（DWORD 广域 vs DWORD 有符号解释、移位量 >31 行为、结果截断位宽三行逐列），**有差才立项，无差则并入 `ShlEx`/`ShrEx` 并注销本注记**。→ 已列 R63 P0。
- **【R62 P0 接续】** ① 终审 7 处 × 4 件挂账（严重 2：`FB_DL_VfdDcBusRipple` 除零不早退 / `FB_DL_BiquadFilter` 稳定判据不充分；中 2；轻 3），R63 配额 16→13（R193 扩面）；② 编译验证债：连欠 ≥3 轮，R63 首位实编译抽样（R195），闸未开不得新增编解码/数学/转换类高复杂度件；③ LGF 组内剩余件清单试点（`SOURCE_HUNTING_MATRIX` ◐ 组按剩余量降序取前 3 组出清单）。

## R66 终审挂账与新增待办（2026-11-22，详见 _Staging_Raw/2026-11-22/REVIEW_R66.md）

- [ ] **`FC_DL_QuadPolyFit` v1.0.1（R67 P0 点修，R67 批 1 认领）**：段 7 前补 `aM[2,2]` 舒尔补主元闸（两值 x 可达奇异落码 03 而非 02，REVIEW_R66 M2）＋段 4 ABS 溢出复核扩展至全部矩量（L1，合并点修）。
- [ ] **`FB_DL_LotMergeGate` v1.0.1（R67 P1 点修，R67 批 1 认领）**：eFault 分支死迁出式（`IF NOT _bFaultLatch → eIdle`）删除（L3）；eIdle 留档型防御保留并按统一口径在头注登记（L2）。
- [ ] **`FB_DL_TaktPaceMonitor` v1.0.2（R67 P2，R67 批 1 认领）**：fExpectR 闸界由 4.294967295E9 前移至 DINT 域 2147483647（转换链域界对齐，L4）。
- [ ] `FB_DL_AnalogOutFailsafe` / `FB_DL_TaktPaceMonitor` v1.0.1 **JSONL 语料重注入**（R248 返修闭环语料侧，挂 R67 收口）。
- [ ] 时间注入引脚「三形态选型表」固化进 coding-standard（UDINT ms 历史件 / TIME KPI 件 / LREAL s 斜坡件，REVIEW_R66 裁决 1）。
- [ ] 机检锚点三项评估入库：TON 极性断言 / CASE 外层守卫与段内强制回写互斥 / 解除式禁沿式唯一载体（REVIEW_R66 §四）。
- [ ] 值守轮事项（不占编码配额）：MatIEC CI 裁决 71 方言件 ｜ GATE MAJOR 存量人核 ｜ oss_harvest GITHUB_TOKEN 注入 + 单仓试跑（ROUND_PLAN_R66 §3）。

> **R66 小结**：10 新件（Base 2 / MathData 4 / Device 1 / Motion 1 / Process 2）+ 终审就地修 2 件 v1.0.1；总库 1,145→1,155（143/272/134/207/121/278），SFT 1,177；机检 10/10 PASS；零检索轮 8 组取材，撞名拒 15；游标 R324；R67 配额 12（R309 分散型下调）。


## R68 构建轮小结与新增待办（2026-11-22，详见 _Staging_Raw/2026-11-22/REVIEW_R68.md）

> **R68 小结**：16 新件（Base 3 / MathData 2 / Device 6 / Process 4 / Motion 1）全部入册并注册，总库 1,163→**1,179**（148/280/134/213/122/282，sum 断言过），v2.60.0；SFT 语料 1,190→**1,206** 条（bad=0）；机检 16/16 PASS。**终审 5+1 抽 + 定向全量扩面**：抽件严重 6 / 中 3 / 轻 3 / 纯 PASS 0，扩面再命中 3 严重 → **就地修 9 件 10 处（全部 v1.0.1，单文件机检复跑 9/9 PASS）**，挂账 7 项转 R69。零检索轮（WebSearch 0/3）、撞名拒 20 条（含精确同名 3 条）、9 组源取材。游标 R346 → **R356**（编号基线订正：任务书 R328 / 实测 R346，取 R347~R356）。

### 本轮勾选（仅本轮实际完成项）

- [x] **FB_DL_FlowMeterKFactorDrift 漂移件重建并注册**（§19.6 已勾未注册的真缺口，registry `source=r68-plan`，R68 批 2）。→ 见 §19.6 注记行。
- [x] **R68 16 目标全部注册**（ROUND_PLAN_R68 §2 总表逐行核对 registry，0 缺件、0 重名）。

### R69 待办（P0 优先，按 REVIEW_R68 §4 挂账 + 值守三项）

- [ ] **P0｜FB_DL_InterlockBypassAudit v1.0.1**：组态故障打断旁路后 `bBypassOn` 残留 TRUE（TON.IN 常真）→ 修复后首次旁路立即到期 04B1；迁相/回 eIdle 时补 `bBypassOn := FALSE`。（REVIEW_R68 M1）
- [ ] **P0｜FB_DL_StretchWrapSeq v1.0.2**：`eCut` 相无失败出口 —— `bCutDone` 永不到则永久驻留且 `bCutOut` 常励磁；需产品决策「切膜失败出口 + 新码位」后实施。（M2）
- [ ] **P1｜FB_DL_FlowMeterKFactorDrift v1.0.2**：头注「组态故障 → eFailure」未实现，补 `eHealth := eFailure`（或按 R350 订正注释二选一）。（M3）
- [ ] **P1｜FB_DL_TruckScaleSeq v1.0.2**：`fWeight<>fWeight` 混入组态闸并锁存，与边界披露 5 矛盾；拆为信号闸 + 保持不锁存。（M4）
- [ ] **P2｜轻项三处**：InterlockBypassAudit 信息码 04B1/04B2 无回落（L1）｜RotaryAirlockCtrl `bJogRevOut` 取上拍 `bRunOut` 反相（L2）｜StretchWrapSeq `bPreClampOut` 仅预压相有效（L3，待工艺确认）。
- [ ] **P0｜编译验证硬闸（R195）**：连欠 5 轮；R69 首位实编译抽样，闸未开不得新增编解码/数学/转换类高复杂度件。
- [ ] 值守轮三项（不占编码配额）：MatIEC CI 裁决 71 方言件 ｜ GATE MAJOR 存量人核 ｜ oss_harvest GITHUB_TOKEN 注入 + 单仓试跑。
- [ ] 固化窗口：本轮为 FB-51 后**第 8 轮**且新增 **10 条 ≥10** → **达到窗口但本轮不执行**（固化需改写 Skill 规范文件，位于 `C:\Library` 之外，超出写入根契约）；转出「固化候选包」6 条可判定规则（R347/R348/R349/R351 + R353/R355），待人格/Skill 维护方落库。

*R68 收口 ｜ 2026-11-22 ｜ 道莅工控代码库产品总监（主控直跑 R335）*

### R69 小结（2026-11-22）
- 挂账 7 项全清（R68 全部点修收口）；新增 10 件入库。编码超时（约 70′ > 50′ 硬顶）→ R70 配额按超时判据再下调（基线 13 → 建议 10）。
- 未尽事项挂账：① 实编译债连欠 6 轮（本轮仅伪编译抽样，无本地 IEC 编译器）；② oss_harvest GITHUB_TOKEN 注入 + 单仓试跑（值守项顺延）；③ MatIEC CI 裁决 71 方言件（值守项顺延）；④ 固化候选包 6 条（R347~R355）待 Skill 文件落库。
- R70 选题：值守轮优先（编译环境建设为主，编码减配），行业池延续。

## R70 构建轮小结（2026-11-22）

> **R70 小结**：10 新件（MathData 3 / Device 3 / Process 2 / Motion 1 / Base 1），总库 1,189→**1,199**，v2.62.0，SFT 1,221→**1,231**，机检 10/10 PASS。配额 10（R362 超时判据 −20 个百分点），对 20 目标如实少报，零注水。待办 55 > 30，本轮不补写新待办。
> **R71 待办（P0）**：① **L2 编译闸修复**（RuSTy 已下载 C:/Library/_tools/rusty/plc.exe，缺 UCRT API-set 转发 DLL；装 VC++2015-2022 x64 运行库后跑 plc.exe --help 验证，通即可对存量件抽样真编译）；② FB_DL_ScaleRangeWatch 量程零域复核（本轮组态闸仅判 rawMax-rawMin）；③ 值守：oss_harvest GITHUB_TOKEN 单仓试跑｜MatIEC CI 71 方言件裁决。

## R72 构建轮小结（2026-11-23）

> **R72 小结**：12 新件（MathData 5 / Base 2 / Device 1 / Motion 1 / Process 2）+ 1 点修（AirSpecificVolume v1.0.1 E032 全回执），总库 1,206→**1,218**，v2.64.0，SFT 1,239→**1,252**，机检 13/13 PASS，L2 闸 12/13 PASS（OilLevelWatch 覆盖面缺口①留档）。零检索轮，撞名拒 14 条。对 20 目标如实少报 13，零注水。待办 55 > 30，本轮不补写新待办。
> **R73 待办（P0）**：① VaporPressureSat 族 8 处缺 `bValid =>` 回执点修（HumidityRatioCalc×2 / MixAirStateCalc / RhFromDewPoint×2 / DewPointToPpmV / NightPurgeCtrl×2）；② 扩展复核 ~20 处多出参 FC 零回执调用点挂账候审（DryerExhaustHumidityCtl / ChamberPurgeDry / WeightClassifySort 等，R333 口径）；③ L2 闸每轮交付资格项常态化；④ 值守三项顺延第 4 轮（oss_harvest token 试跑 / MatIEC 71 方言件 / GATE MAJOR 存量人核）。
