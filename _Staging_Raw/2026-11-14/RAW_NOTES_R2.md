# RAW_NOTES_R2 ｜ 道莅万级工业代码库 · 第二轮狩猎笔记

> **文档编号**：DL-RN-2026-11-14-002
> **轮次**：Round 02 ｜ Level 0（DL_Base + DL_MathData）｜ 目标 12 组件
> **撰写人**：道莅工控代码库产品总监（Daoli Library Director）
> **检索日期**：2026-11-14 ｜ 共执行 5 次针对性 WebSearch
> **性质**：情报记录，不落任何 .st 源码文件；本目录原始资料永不被正式目录引用

---

## 0 本轮狩猎目标对应表

| 本轮组件 | 狩猎关键词 | 主要参考来源 |
|---|---|---|
| FB_DL_ExtendedTimer / PulseGenerator | OSCAT GEN_PULSE / TP_X / CLK_PRG / PWM_DC | 检索 1（OSCAT Timing & Signal Generation） |
| FB_DL_CycleTimeMeasure / RuntimeMeter | OSCAT CYCLE_TIME / TC_MS / T_PLC_MS | 检索 1 |
| FB_DL_AlarmManager | ISA-18.2 / First-Out / 编码器扫描法 | 检索 2 |
| FB_DL_StepSequencer | Grafcet / SFC / CASE 状态机 / 步超时 | 检索 3 |
| FC_DL_SwapBytes16 / FC_DL_SwapBytes32 | Modbus ABCD / CDAB / BADC / DCBA | 检索 4 |
| FB_DL_RingBufferLReal | 环形缓冲 FIFO 模式 / O(1) 递推 | 检索 5 |
| FC_DL_StringTrim / FC_DL_StringSplit | IEC 标准串函数 LEN/MID/FIND/DELETE | 检索 5 |
| FB_DL_WatchdogMonitor | 心跳监控 / TON 看门狗模式 | 检索 2 + 检索 5（间接） |

---

## 1 检索 1 ｜ OSCAT 库的定时与信号发生子系统

**来源**：
- DeepWiki simsum/oscat《Timing and Signal Generation》与《Signal Generators and Timers》（GitHub simsum/oscat 镜像文档）
- oscat.readthedocs.io（OSCAT 官方文档站，协议 Eclipse Public License 2.0）
- CODESYS 官方帮助「Other useful resources」对 OSCAT Basic / Building 的推荐条目

**关键发现**：

1. **OSCAT 全部时基依赖平台函数 `T_PLC_MS()` / `T_PLC_US()`**（返回自启动以来的自由运行毫秒/微秒 DWORD 计数器）。这不是 IEC 61131-3 标准函数，是平台注入点——CODESYS/Beckhoff 有，但**汇川 InoProShop 不保证存在**。
2. **delta-time 计数器模式（TC_MS / TC_US）**：`tx := T_PLC_US(); tc := tx - last; last := tx;`，利用 DWORD 无符号回绕自动处理溢出，首扫用 `init` 标志跳过。
3. **CYCLE_TIME 性能监控块**：输出 `ct_min / ct_max / ct_last / systime / cycles`，RST 复位——这是扫描周期统计的成熟参考。
4. **GEN_PULSE / GEN_SQ / CLK_PRG**：方波发生器的惯用实现是「记录上次翻转时刻 + 与周期比较」，`CLK_PRG` 首脉冲立即发出（`last := tx - pt` 预置技巧），周期运行时可改。
5. **TP_X 可重触发脉冲定时器**：上升沿记录 `start := tx`，`ET := tx - start`，Q 在 PT 期间为 TRUE——比标准 TP 多了重触发与异步 RST。
6. **PWM_DC**：占空比调制走「周期内比较 elapsed 与 duty×period」。

**OSCAT 协议结论**：Eclipse Public License 2.0，可商用；本库仅借鉴算法语义，全部独立重构，不构成衍生作品。

**道莅差异化决策（借语义不借实现）**：
- **D-R2-01**：OSCAT 的 `T_PLC_MS()` 平台依赖被道莅**拒绝引入 Level 0**。本轮 `FB_DL_CycleTimeMeasure` 与 `FB_DL_RuntimeMeter` 改为**调用方注入时间增量**（`uDeltaTimeMs : UDINT` 输入引脚），组件内部零平台函数调用，保持 R3 纯标准语法三平台可编译。OSCAT 的「首扫跳过 + 无符号回绕」思想由调用方负责，手册中给出调用侧获取示例说明（非交付代码）。
- **D-R2-02**：`FB_DL_PulseGenerator` 不采用 OSCAT 的「时刻比较」法（依赖系统时间），改用 **ENUM(eHigh/eLow) + TON** 状态机实现——TON 是 Standard.library 标准实例，天然满足 R6/R7 红线，且行为与扫描周期耦合可预期。
- **D-R2-03**：`FB_DL_ExtendedTimer` 综合借鉴 OSCAT `TP_X`（可重触发、异步复位）与 IEC 标准 TON/TOF/TP 三态语义，增加第四模式 RTO（保持型累加计时，Omron/AB 生态高频需求，OSCAT Basic 中对应较弱）。

---

## 2 检索 2 ｜ 报警管理与 First-Out 仲裁

**来源**：
- industrialmonitordirect.com《PLC First-Out Alarm Ladder Logic》《Error and Alarm Handling in PLC Programming》
- plcprogramming.io《What Is Alarm Management? ISA-18.2 Lifecycle Explained》
- powerfabric.org《SCADA Alarm Management per ISA 18.2》

**关键发现**：

1. **First-Out 两大实现语义**（这是本轮最重要的语义发现）：
   - **电平敏感（level-sensitive）**：输入为「报警态信号」（High/High-High/Trip），从 TRUE 跳变即仲裁；冷启动时已在报警态的输入会在首扫被锁存为首出。
   - **边沿敏感（edge-sensitive）**：输入为「正常态信号」（OK/Healthy），从 FALSE 跳变才仲裁，相对于「已知良好起点」。
   - 两者的首出结论在「启动时已处于降级状态」的工况下**会给出不同答案**——必须显式二选一。
2. **N 路输入的「最低索引优先」编码器扫描法**（对 8 路以上推荐）：`FOR i := 0 TO N-1` 顺序扫描，第一个命中的索引获胜后跳出——固定优先级仲裁的标准写法，天然防竞态。
3. **时序锁存（First-In-Fault Logging）**：`IF Fault_x AND FaultRegister = 0 THEN FaultRegister := x;` 的锁存模式 + ACK 复位。
4. **ISA-18.2 核心纪律**：优先级由「后果 × 可用响应时间」决定而非工程师直觉；关键级报警占比应 <5%；报警防抖用死区/延时；报警 ≠ 安全功能（IEC 61511 边界）；PLC 负责确定性检测与锁存，HMI 负责呈现与确认流程。
5. **HMI 呈现约定**：首出指示 1~2Hz 闪烁直至确认（ISA-18.2 优先级颜色编码）——属 HMI 侧职责，PLC 只需给出稳定的首出锁存信号。

**道莅差异化决策**：
- **D-R2-04**：`FB_DL_AlarmManager` 的首出语义**锁定为电平敏感**（输入即报警态），理由：道莅的用户是 OEM 设备厂，输入来源多为「条件成立=故障」的联锁信号，边沿敏感方案需调用方再做一层取反，易错。手册必须写明该语义与冷启动行为（首扫已 TRUE 的通道会成为首出）。
- **D-R2-05**：优先级仲裁采用「**数值最小者获胜 + 同级先到先得**」：`auPriority` 1=停机级 2=警告级 3=提示级 0=通道禁用；同级之间用**激活序号计数器**（每通道一个 UDINT，激活时取全局递增序号）实现先到先得，避免「最低索引优先」造成的通道位置偏差，也避免为时间戳引入平台时钟依赖。
- **D-R2-06**：本组件只做**仲裁与锁存**，不做事件历史、不做 shelving/suppression（ISA-18.2 明确那属操作管理层面）——防大而空。报警字打包**复用首轮已入库的 `FC_DL_PackBitsToWord`**（依赖声明，见规格书 §1.2），验证首轮组件的复用闭环。
- **D-R2-07**：确认（Ack）语义遵循 ISA-18.2 三态分离：报警激活（Active）、已确认（Acknowledged）、首出锁存（First-Out Latched）三个正交信号分别输出，Ack 只清除首出锁存，不掩盖激活态。

---

## 3 检索 3 ｜ Grafcet/SFC 与顺控状态机

**来源**：
- industrialmonitordirect.com《批次控制中 PLC 设备阶段的实现》（中英繁三版）
- kaifayun.com《标准状态机在工业自动化中的应用》
- industrialautomation.net《How Do You Design, Program, and Debug State-Machine Logic》
- jhqkkr-kd.myshopify.com《Grafcet/SFC 编程教程》

**关键发现**：

1. **ST 实现 SFC 的通用范式**：`CASE Step OF 0: 空闲→启动; 1: 动作+转换条件; ...; ELSE 兜底`——与道莅 R6 红线完全一致，业界已是事实标准。
2. **步号间隔惯例**：步号按 10 递增（0,10,20,30）而非 1 递增，为未来插入中间步留位——道莅首轮 SignalDebounce 枚举已采用同惯例（0/10/20/30/99），本轮 StepSequencer 的内部枚举沿用。
3. **步超时监控（Timeout Guard）是Grafcet 最佳实践明确要求**：每个步应配最大持续时间监控，TON 在**进入步时初始化**；整体序列另有主超时。遗漏它是「序列挂死在丢失的反馈信号上」的头号原因。
4. **不稳定转换（unstable transition）陷阱**：转换条件保持为 TRUE 时会立即再次触发——需要边沿检测或在转换后清除条件来源；步完成信号建议由调用方做成单周期脉冲，或顺控器内部对完成信号做「进入新步后才重新采样」的处理。
5. **死锁防护**：所有转换条件必须可达；并行分支调试复杂度剧增——道莅首版 StepSequencer 明确**不做并行分支**（选择序列串行版），并行分支列入 R3+ 规划。
6. **手动/单步调试**：维护工程师需要「单步推进」模式做现场调试（增量测试），这是量产设备顺控块的隐性刚需。

**道莅差异化决策**：
- **D-R2-08**：`FB_DL_StepSequencer` 采用**通用步引擎**而非「把动作写死在 CASE 里」的模板式顺控：动作由调用方按当前步号执行，顺控器只管理「当前步号、步内计时、步超时、跳转、暂停、单步、故障锁存」——这样才能成为 10000 个组件里的可复用基类，而不是某个具体工站的专用代码。
- **D-R2-09**：步完成信号约定为**电平语义**（调用方在当前步的条件满足时把对应位保持 TRUE，顺控器在步推进瞬间清除对它的采样），并在规格书 B 系列防御点中显式处理「完成信号跨步残留」问题：推进后立即忽略旧步的完成位，防止不稳定转换。
- **D-R2-10**：单步模式（`bSingleStep`）内建：暂停时步内 TON 继续无条件刷新但超时判定冻结（暂停不算超时）——暂停语义必须明确，否则调试时步超时误报。

---

## 4 检索 4 ｜ Modbus 字节序与 32 位量组装

**来源**：
- modbus.org 官方《An Introduction to Modbus》（浮点表示章节）
- scadaprotocols.com《Modbus Byte Order and Word Order: Fix Your 32-Bit Values》《Modbus Float Converter》
- modbus.app《Modbus Showing Wrong Values? It's the Byte Order》
- ssautomationllc.com《How-To: Reading Modbus Registers》

**关键发现**：

1. **Modbus 标准只定义 16 位寄存器内部为大端（A 先发）**，多寄存器组成 32 位量的字序完全未定义——四种排布 ABCD / CDAB / BADC / DCBA 全部存在于现场，这是「新设备一接就出 1e38 天文数字」的唯一主因。
2. **四种排布的标准定义**（以 0x12345678，A=0x12 最高字节）：
   | 名称 | 字节序 | 别名 | 典型设备 |
   |---|---|---|---|
   | ABCD | A B C D | 大端·大字 | Modicon 血统（施耐德、ABB 继电器、Janitza） |
   | CDAB | C D A B | 字交换 | 西门子 PAC3200、Socomec、安川驱动 |
   | BADC | B A D C | 寄存器内字节互换 | ABB 部分驱动 |
   | DCBA | D C B A | 全反序 | Intel 小端 CPU 直出的薄协议栈设备 |
3. **五分钟现场判定法**：找已知值寄存器（如 IEEE 754 的 1.0 = 0x3F800000），读原始十六进制，四排布对照。
4. **写回纪律**：32 位量必须用 FC16（功能码 16）一次双寄存器写入；拆成两次 FC6 写会存在「半更新窗口」，设备即时生效时出怪事。
5. **识别寄存器/数值寄存器字序可能不同**（同一设备字符串寄存器与浮点寄存器各自为准）——库组件不应内置「自动猜测」，显式枚举入参是唯一正确设计。

**道莅差异化决策**：
- **D-R2-11**：`FC_DL_SwapBytes32` 的语义锁定为「**归一化**」：输入 `uRaw : DWORD`（通信侧收到的原始 32 位拼接值）+ `eRawOrder : E_DL_ByteOrder`（声明原始值属于哪种排布），输出统一为 ABCD 归一化 DWORD。不做「输出任意目标排布」的双向转换（功能翻倍但调用面混乱，需要反向时调用方以 eRawOrder 对称使用即可——四函数互逆性写入手册单测）。
- **D-R2-12**：字节提取一律 `SHR + AND 16#0000_00FF` 再重装，**禁止任何 `%B`/内存切片/联合体语法**（C 语言的 union 技巧在 ST 无对应物，且 R3 禁指针）。
- **D-R2-13**：`FC_DL_SwapBytes16` 单独成组件而非 32 位版的退化情形：16 位寄存器内字节互换是 BADC/DCBA 的构件，也是 Profibus/串口仪器独立高频需求，原子化复用（符合「禁巨无霸」纪律）。
- **D-R2-14**：与首轮 `FC_DL_Crc16Modbus` 的「低字节先发」勘误结论（Round 01 案例 1）形成呼应：手册统一给「CRC 字节序 × 数据字序」两张表，本库通信族组件的字节序口径一次说清。

---

## 5 检索 5 ｜ 环形缓冲、字符串解析与看门狗模式

**来源**：
- plccode.ai《A ring buffer in structured text》《String handling in PLCs》
- industrialmonitordirect.com《TwinCAT 3 Split String by Delimiter Using FIND LEFT DELETE》
- doc.coldwave.io《String Functions》（IEC 标准串函数行为定义）

**关键发现**：

1. **环形缓冲 O(1) 模式**：写指针 `Idx` 前进 + `(Idx + 1) MOD SIZE` 回绕；`Count` 区分未满/已满两阶段；求平均用运行和递推。**三个隐蔽坑被点名**：
   - **负数 MOD 陷阱**：`(Idx - Count + SIZE) MOD SIZE` 必须先加 SIZE 再取模——部分平台负数 MOD 结果为负，直接索引出界。这是道莅 R4「数组双检」必须吸收的新案例。
   - **运行和浮点漂移**：REAL 累加数天后漂移，需定期全量重算——与首轮 `FB_DL_MovingAverage` B6 决策完全一致，验证既有范式。
   - **故障快照**：故障发生时停写（`Store AND NOT Fault_Latched`），保住故障前现场。
2. **PLC 字符串的存储模型**：CODESYS/TwinCAT `STRING(n)` 为「最大长度 + 当前长度 + 字符 + NUL」；**CODESYS 默认 STRING 只有 80 字节**——不显式 `STRING(255)` 就会被静默截断。位置参数一律 1 起始（不是 0）。
3. **IEC 标准串函数清单**（三平台齐备，可作为 R3 合规工具箱）：`LEN / LEFT / RIGHT / MID / FIND / CONCAT / INSERT / DELETE / REPLACE`；`FIND` 未命中返回 0；`MID` 越界返回空串（不同平台可能截断到串尾，防御性写法必须自行钳位）。
4. **TwinCAT 无内置 SPLIT**：惯用「FIND 定位 → LEFT 取字段 → DELETE 吃掉已处理段」循环；分隔符长度用 `LEN(sDelimiter)` 而非硬编码 1。
5. **报文解析五步纪律**（validate → locate → extract → convert → use）：先验总长度与终止符，再定位各字段，`MID` 前做长度钳位检查，转换前逐字符校验。
6. **看门狗惯用模式**（检索 2/5 间接印证）：`TON(IN := 心跳稳定, PT := 超时窗)` + 心跳**跳变沿复位 TON**——监控的对象是「跳变间隔」而非电平，TON 超时即判掉线；配合锁存故障与显式复位。

**道莅差异化决策**：
- **D-R2-15**：`FB_DL_RingBufferLReal` 采用**定长 64 容量 + 编译期固定数组**（`ARRAY[0..63] OF LREAL`），不做运行时容量参数（动态数组跨平台行为不一，且首轮 MovingAverage 已确立「定长数组 + MOD 回绕」范式）。负数 MOD 陷阱写入 B 系列防御点：所有「回退读取」必须 `+ DL_RB_CAP` 后再 MOD。
- **D-R2-16**：容量 64 与窗口 100（MovingAverage）异构——64 是 FIFO 通用惯例值，两组件各按各自场景定型，不为「统一常量」而扭曲场景容量。
- **D-R2-17**：`FC_DL_StringTrim` / `FC_DL_StringSplit` 的字符串长度**显式声明 `STRING(255)`** 并在头注释警告 CODESYS 默认 80；空格/制表/回车/换行四类空白字符用 IEC 转义字面量比较；所有循环带防死锁计数器（R4），`MID`/`LEFT` 调用前先做长度钳位（先判后算，P-02 范式）。
- **D-R2-18**：`FC_DL_StringSplit` 输出经 `VAR_IN_OUT aFields`（调用方提供 `ARRAY[0..15] OF STRING(255)`），函数返回实际字段数；输出缓冲不足时**截断 + 独立故障码**（16#0001_000D），不静默丢字段。
- **D-R2-19**：`FB_DL_WatchdogMonitor` 监控语义锁定「**跳变间隔**」：内部 R_TRIG 捕捉心跳沿并复位看门狗 TON；TON 无条件刷新（R7）；超时锁存至 bReset。附加防御：心跳频率过高（< 最小合法间隔）视为接线/程序错误告警——上位机把心跳写成恒振荡时能被发现。

---

## 6 合规台账

| 来源 | 性质 | 协议 | 商用合规 | 本库取用方式 |
|---|---|---|---|---|
| OSCAT Basic/Building（oscat.de、simsum/oscat 文档镜像） | 开源函数库 | Eclipse Public License 2.0 | 可商用 | 仅借鉴算法语义与行为定义，全部独立重构 |
| modbus.org 官方介绍 | 协议说明文档 | 公开资料 | 可引用 | 字节序事实标准与术语 |
| ISA-18.2 / IEC 62682 相关技术文章 | 方法论文献 | 概念性参考 | 不涉及代码 | 优先级/确认/首出方法论 |
| Grafcet/IEC 61131-3 SFC 教程类文章 | 教学资料 | 概念性参考 | 不涉及代码 | 状态机实现范式 |
| scadaprotocols.com / modbus.app / plccode.ai / industrialmonitordirect.com | 技术博客 | 概念性参考 | 不涉及代码 | 模式与陷阱清单 |

**结论**：本轮 12 个组件全部为**语义借鉴 + 独立重构**，无任何源码级复制，头部注释「开源溯源」段按此表述；未检索到需要落盘 `_Staging_Raw` 的原始源码文件（检索要点已记录，符合任务要求不下载源码）。

---

## 7 交给规格书的输入清单（与 ROUND_PLAN_R2 决策编号对应）

1. 平台时间函数一律不入库（D-R2-01）→ CycleTimeMeasure/RuntimeMeter 用 `uDeltaTimeMs` 注入。
2. 首出电平敏感语义 + 数值最小优先 + 激活序号（D-R2-04/05）→ AlarmManager。
3. 通用步引擎 + 电平完成信号 + 暂停冻结超时（D-R2-08/09/10）→ StepSequencer。
4. 归一化单向量 + 枚举显式入参 + SHR/AND 重装（D-R2-11/12）→ SwapBytes32。
5. 定长 64 + 负 MOD 防御 + 故障快照思想（D-R2-15）→ RingBufferLReal。
6. STRING(255) 显式长度 + 五步解析纪律 + VAR_IN_OUT 输出缓冲（D-R2-17/18）→ String 族。
7. 跳变间隔语义 + 高频心跳告警（D-R2-19）→ WatchdogMonitor。

*Round 02 ｜ 2026-11-14 ｜ 道莅工控代码库产品总监*
