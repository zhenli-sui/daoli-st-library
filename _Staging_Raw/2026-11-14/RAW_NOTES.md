# RAW_NOTES ｜ 2026-11-14 首轮狩猎原始情报笔记

> 用途：本轮 14 个 Level 0 组件的算法溯源与参考要点。**本文件只记录「算法思路 + 出处」，不存放任何待入库源码**。
> 纪律：凡 LGPL/GPL 来源，一律「读懂算法后独立实现」，禁止逐行改写搬运（避免衍生作品传染）。
> 采集时间：2026-11-14 ｜ 采集方式：定向 WebSearch（5 次）｜ 采集人：Daoli Library Director

---

## 一、共识性结论（跨来源交叉验证，可直接写入实现约束）

| # | 结论 | 影响组件 |
|---|---|---|
| C1 | 除零保护不能用 `IF fDen <> 0.0`，必须用绝对容差 `ABS(fDen) > 1E-6` | LinearScale / MovingAverage / Deadband |
| C2 | 位运算移位必须用 `SHR` / `SHL` 标准函数，禁用 `%X0`、`>>`、`%B0` 等厂商方言 | BitGet / BitSet / BitCount / Gray / Crc16 |
| C3 | 循环 `FOR` 的边界必须由**输入长度参数 + 数组上下界**双重夹紧，且 `FOR` 上下界反转时不得执行循环体 | Crc16 / BitCount / UnpackWord |
| C4 | 边沿检测必须对**滤波后的稳定值**做，禁止对原始抖动值做（否则下游计数器按数量级过计） | SignalDebounce / DualEdgeTrig |
| C5 | 纯函数（FC）不得持有跨周期记忆；需要记忆的「伪函数」（迟滞比较）必须用 `VAR_IN_OUT` 把状态交还调用方 | Hysteresis |
| C6 | 滤波/平均必然引入相位滞后，滞后量 ≈ (N-1)/2 个采样周期；窗口未填满阶段与填满阶段必须分两态处理 | MovingAverage |

---

## 二、来源 1 ｜ OSCAT Basic（含 FILTER_DEBOUNCE / FILTER_MAV / DEAD_BAND）

- **来源 URL**
  - OSCAT 官方文档（PDF）：https://eclipse-oscat.github.io/oscat-basic-docs/en/pdf/oscat-basic-docs-en.pdf
  - OSCAT 项目主页镜像：https://wiki.kontron.ch/kchcdsv3/oscat
  - OSCAT 组件目录速查：https://goplc.app/guides/goplc_oscat_guide
  - OSCAT 滤波族在 Modicon 平台的移植说明：https://industrialmonitordirect.com/blogs/knowledgebase/oscat-digital-filter-implementation-in-modicon-tm172-controllers
- **版本锚点**：OSCAT Basic v3.31（GoPLC 分发包口径，30,514 行 / 550 个 POU）
- **原始协议**：**LGPL-3.0**（强传染性）
- **商用结论**：可商用，但**禁止逐行改写**。本项目仅提取「接口命名习惯 + 算法语义」，实现代码 100% 独立编写，不复制其变量名、不复制其语句顺序、不复制其内部结构体。
- **算法要点**
  1. `FILTER_DEBOUNCE`（BOOL→BOOL，约 12 字节状态）：基于时间的触点消抖，本质是「输入变化即重置计时器，稳定持续达预设时间才更新目标值」；官方语义约定 **`RST` 上升沿清空缓冲与输出**。
  2. `FILTER_MAV` 系（滑动平均族）：参数 `N` 合法域 **1..255**，窗口长度超界需夹紧而非报错；`RST` 上升沿清缓冲。内存代价 `N × 4 byte`（REAL）。
  3. `DEAD_BAND(X, L)`：**移位型死区**语义 —— `|X| > L` 时 `Y = X - SGN(X) × L`，`|X| ≤ L` 时 `Y = 0`。用途原文：「防止控制器持续小幅切换而导致执行机构过度磨损」。
  4. `DEAD_BAND_A`：自适应死区，用低通提取高频分量幅值动态算 `L`，`KL` 合理域 1~5，并用 `LM` 上限硬夹紧 `L`（**防止极端工况下死区自我放大到失控**——这条对本项目 `FC_DL_Deadband` 的参数钳位设计有直接借鉴价值）。
- **道莅处置**：`FB_DL_SignalDebounce`、`FB_DL_MovingAverage`、`FC_DL_Deadband` 三个组件**仅借鉴算法语义**，接口与实现全部重写。

---

## 三、来源 2 ｜ 离散量消抖工程实践（DEBOUNCE 状态机 + 边沿纪律）

- **来源 URL**
  - https://jhqkkr-kd.myshopify.com/blogs/knowledgebase/selecting-discrete-input-debounce-filters-for-ecus-and-plcs
  - https://industrialmonitordirect.com/fi/blogs/knowledgebase/iec-61131-3-sfc-programming-actions-qualifiers-and-training
- **原始协议**：技术文章（非代码仓库），无传染性
- **算法要点**
  1. **累加器型消抖**：输入每次跳变即清零计数器，输入稳定则计数器递增，达到预设值后把新值写入目标并置 `Done`。等价的 IEC 实现是 `TON` + 「输入变化则复位」，专用 DEBOUNCE 块的价值在于**避免每个输入点各占一个定时器实例**。
  2. **时序纪律**：`TOF/TON` 的 `PT` 若为 10ms、任务周期 5ms，则实际消抖窗口 = 10ms（**消抖时间是绝对时间，与扫描周期无关；但采样分辨率受扫描周期限制**）。
  3. **边沿纪律（最重要）**：`Rising = 当前 AND NOT 上一周期`，且**必须基于已消抖值**。"Edge detection must always be performed on the debounced value, not the raw value. Otherwise every bounce during the make period generates a spurious edge and downstream counters over-count by an order of magnitude."
  4. **不该做软件消抖的场合**（写入手册「误用警告」）：固态/光电/霍尔输入、编码器正交信号、高速计数器输入、已过安全级硬件滤波通道、PWM/调制信号。**软件消抖只对机械触点有意义。**
  5. **ASIL 级状态机消抖**：边沿事件由「进入 STABLE_1 / STABLE_0 状态」这一跃迁产生，并由消费者清除事件标志（事件锁存而非电平）。→ 本项目 `FB_DL_SignalDebounce` 采用 **ENUM 状态机 + 单周期事件脉冲** 结构。

---

## 四、来源 3 ｜ Modbus CRC-16 算法（含工业级实现细节与陷阱）

- **来源 URL**
  - https://jhqkkr-kd.myshopify.com/blogs/knowledgebase/implementing-crc-16-modbus-rtu-on-mitsubishi-fx3u-plc-in-st
  - https://industrialmonitordirect.com/web-pixels@610a19cewf693d529pf324840bm6169d9b4/custom/web-pixel-205717656@5/sandbox/modern/blogs/knowledgebase/modbus-crc-16-algorithm-step-by-step-implementation
  - 西门子官方论坛 SCL 实例（中文）：https://wap.siemens.com.cn/club/bbs/post/1962863.html
- **原始协议**：技术文章 / 厂商论坛帖（算法本身为公有领域数学），无传染性
- **算法要点（可直接作为验收基准）**
  1. **参数集**：多项式 `0x8005`（反向表示 `0xA001`）、初值 `0xFFFF`、输入反射 YES、输出反射 YES、末异或 `0x0000`、宽度 16 位。
  2. **逐位算法**：`CRC ^= byte` → 8 次「右移 1 位，若移出位为 1 则 `CRC ^= 0xA001`」。
  3. **报文附加顺序**：**CRC 低字节在前、高字节在后**（Modbus RTU 规定）。这是现场最高频的调试坑，必须写入手册。
  4. **已知测试向量（用于单元自检）**：
     - 单字节 `0x0C` → CRC `0x911E`（来源给出完整逐位移位过程，可用于手算校验）
     - 标准帧 `01 03 00 00 00 02` → CRC 应为 `C4 0B`（低字节 `0xC4` 先发，即寄存器值 `0x0BC4`）
  5. **西门子 SCL 参考里两个值得抄的「防御设计」**（不含其方言语法）：
     - 用 `LOWER_BOUND` / `UPPER_BOUND` 取数组真实边界，再 `IF 请求长度 > 0 AND 请求长度 <= (上界-下界+1) THEN` 才调整上界 → **长度参数越界不崩溃、不静默截断**。
     - 明确区分「数组下界可能不为 0」的情形。
  6. **明确剔除的方言**：西门子示例中的 `#wTempCRC.%X0`、`.%B0`、`#` 前缀、`VAR CONSTANT cwXor` 命名法 → 一律换为 `SHR()` + `AND 16#0001` + 道莅命名法。
  7. **查表法 vs 计算法**：256 项表（512 字节）快但占内存且需在 `VAR CONSTANT` 内做常量初始化，跨平台常量数组初始化行为不完全一致 → 首版采用**纯逐位计算法**（确定性好、零常量表风险），查表法列入 `ROADMAP` 的 PATCH 级性能优化候选。

---

## 五、来源 4 ｜ 格雷码 / 绝对值编码器（含 Excess 偏移与动态读值陷阱）

- **来源 URL**
  - https://industrialmonitordirect.com/blogs/knowledgebase/converting-absolute-encoder-gray-code-to-position-in-plc
  - https://jhqkkr-kd.myshopify.com/blogs/knowledgebase/understanding-gray-code-encoders-in-industrial-position-feedback
  - 编码器之家（中文工程视角）：https://www.bmq123.com/1853.html
- **原始协议**：技术文章，无传染性
- **算法要点**
  1. **Gray → Binary**：`B[n-1] = G[n-1]`；`B[i] = B[i+1] XOR G[i]`（逐位递推）。等价高速写法（单条链路 XOR）：`B = G XOR (G>>1) XOR (G>>2) XOR ... XOR (G>>n-1)`，可用 `SHR` 倍增法 5 步完成 32 位（`>>1, >>2, >>4, >>8, >>16`）。
  2. **Binary → Gray**：`G = B XOR (B >> 1)`（一条语句）。
  3. **位宽掩码**：编码器实际分辨率常为 10/12/13/17/19 位，转换后必须按位宽掩码，否则高位残留会污染结果 → 本项目增加 `uBitWidth` 输入（1..32），并在超界时夹紧 + 报 `uErrorId`。
  4. **Excess 偏移**：常见 360° 绝对值旋转编码器取 9 位（512 步）码表的中间 360 码，输出范围 76..435，即 `角度 = 格雷值 - 76`。**转换函数本身不承担偏移补偿**（职责单一），但手册必须写清「先转二进制、再减 Excess 偏移、再乘分辨率系数」的正确调用顺序，否则现场必出「角度差 76°」类事故。
  5. **动态读值陷阱**：格雷码只保证「相邻编码仅 1 位变化」，**不保证并行读取瞬间的位偏斜为零**。若编码器处于高速旋转，仍需「读两次比对一致」或使用 SSI 同步串行接口。手册需给出该警告。
  6. **确诊手法**（写入手册排障节）：匀速转动时数值若出现大幅不规则跳变（而非平滑递增），即为「把格雷码当二进制直接使用」。

---

## 六、来源 5 ｜ 施密特迟滞（Hysteresis）工业实现

- **来源 URL**
  - https://industrialmonitordirect.com/es/blogs/knowledgebase/schneider-m221-schmitt-trigger-hysteresis-ladder-logic
  - https://industrialmonitordirect.com/blogs/knowledgebase/implementing-hysteresis-in-studio-5000-function-block-diagrams
  - https://baike.baidu.com/item/滞环/8222111
- **原始协议**：技术文章 / 百科，无传染性
- **算法要点**
  1. **核心判断**：「迟滞无法靠抬高或降低单一阈值实现，必须用**锁存（latch）**表达」。IEC 61131-3 的 `SR` 双稳态元件是迟滞的规范载体：`S1` 由「> 上阈值」驱动，`R` 由「< 下阈值」驱动，两者皆 FALSE 时保持原态。
  2. **双阈值定义**：以设定点 `SP` 为中心、回差带宽 `H` 为总宽度 → 上阈值 `SP + H/2`、下阈值 `SP - H/2`；亦可用「上阈值 + 回差量」定义（两种约定都常见，**接口必须只选一种并在注释中写死**，本项目采用「中心 + 半带宽」）。
  3. **现场病因**：无回差时输出在设定点附近高频通断（chatter），继电器/接触器/电磁阀寿命断崖式下降；回差过大则稳态误差超差。参数需可调。
  4. **工程增强（可选，非默认）**：阈值确认延时（`TON` 二次确认），用于极噪声环境下再压一道。
  5. **有状态本质**：迟滞输出取决于「上周期输出」，因此**不可能用无状态纯函数实现**——这是本项目 `FC_DL_Hysteresis` 必须带 `VAR_IN_OUT bState` 的根本原因（见 C5）。

---

## 七、来源 6 ｜ 滑动平均 O(1) 递推（含启动阶段陷阱）

- **来源 URL**
  - TIA 博途 SCL 滑动平均实战（中文，最贴近本项目缺陷描述）：https://www.hqwc.cn/a/1476494.html
  - 算法性能分析（中文）：https://www.cnblogs.com/52algorithm/p/20587740/moving_average_filter
  - ST 原生实现：https://www.tskau.com/docs/content/770.html
  - S7 滚动平均 30 点缓冲区：https://industrialmonitordirect.com/hu/blogs/knowledgebase/s7-analog-rolling-average-implement-30-sample-buffer-in-siemens
- **原始协议**：技术文章，无传染性
- **算法要点**
  1. **O(1) 递推**：`fSum := fSum - afBuffer[idx] + fNew; afBuffer[idx] := fNew; idx := (idx + 1) MOD N; fAvg := fSum / N`。计算量与窗口 N 无关，扫描周期恒定，避免 `FOR` 循环导致的扫描抖动。
  2. **【最关键缺陷】启动阶段必须分两态**：窗口未填满时只能「累加、不替换」，窗口填满后才允许「减最旧 + 加最新」。原文作者自述：「第一版没有区分未满/已满两个阶段，上电头几秒输出比原始信号还剧烈」。→ 本项目以 `uFilledCount` + `bBufferFull` 双输出暴露该状态，并为 `N` 运行时变更设计「变更即重建」策略。
  3. **浮点累加漂移**：长周期运行后 `fSum` 会累积舍入误差（与真实窗口和缓慢偏离）。缓解手段：每满 `K × N` 次采样做一次「全窗口重算校正」（`FOR` 重算 + 防死锁计数器），K 提为常量。
  4. **窗口长度选择经验**：`实际滤波时间 = N × 采样周期`；相位滞后 ≈ `(N-1)/2` 个采样周期。**联锁/安全回路禁止使用大窗口滤波值**（滞后会吃掉安全响应时间），只允许用原始值或 N≤3。
  5. **奇偶性**：部分资料建议 N 取奇数以避免半采样相位偏移；本项目不作强制，仅作手册建议。
  6. **断电保持**：缓冲区、写指针、累加和若不设为 RETAIN，重新上电后会重新经历「未满阶段」——需在手册明示。
  7. **采样节拍**：滚动平均只有在采样间隔恒定时才是真正的数字滤波器；建议在固定周期任务中调用（本项目以 `bSample` 上升沿触发采样，把节拍控制权交还调用方）。

---

## 八、来源 7 ｜ 死区函数两种语义（必须二选一并写死）

- **来源 URL**
  - 施耐德 Machine Expert `FB_DeadBand` 帮助：https://product-help.schneider-electric.com/Machine Expert/V2.0/en/TbAppLib/TbAppLib/FB_DeadBand/FB_DeadBand-2.htm
  - 西门子 SIMATIC 模块化 PID 控制手册 DEADBAND 节（中文）：https://support.industry.siemens.com/cs/attachments/1137082/Mod_PID_Control_CN.pdf
  - 西门子英文版（参数域更清晰）：https://support.industry.siemens.com/cs/attachments/1137082/Pid_e.pdf
- **原始协议**：厂商公开文档，算法为通用数学，无传染性
- **两种语义（互斥，混用是事故源）**
  | 语义 | 表达式 | 代表实现 | 输出特性 |
  |---|---|---|---|
  | **A 归零型** | `|X| < L` → `Y = 0`；否则 `Y = X` | 施耐德 `FB_DeadBand` | 死区内输出**跳变为 0**，适合「抑制小信号、不让它进积分器」 |
  | **B 移位型** | `|X| > L` → `Y = X - SGN(X)·L`；否则 `Y = 0` | OSCAT `DEAD_BAND`、西门子 `DEADBAND` | 传递函数**连续无跳变**，适合串在 PID 误差通道上 |
- **采纳决策**：`FC_DL_Deadband` 采用**移位型（B）**为默认，并通过 `bZeroMode` 输入提供归零型（A）切换（默认 `FALSE` = 移位型）。理由：移位型连续、可串入闭环不引入阶跃扰动；归零型更接近「阈值开关」直觉。
- **参数域约束（来自西门子手册）**：死区宽度 `DEADB_W` **只能为正值**，推荐下限 0.01；死区偏移 `DEADB_O` 任意实数，用于「零点不在 0」的场合（如 4~20mA 换算后零点偏移）。国产现场常见错误是传负数宽度导致传递函数反向 → 本项目对 `fWidth < 0` 取绝对值并置 `uErrorId` 警告。
- **重要警示（西门子原文）**：死区会**使信号失真，失真量恰为死区宽度**；若用于「误差信号整形」，偏移必须设为 0.0，否则零点被人为搬移。

---

## 九、本轮合规台账

| 来源 | 协议 | 处置 | 是否可商用 |
|---|---|---|---|
| OSCAT Basic v3.31 | LGPL-3.0 | 仅借鉴算法语义与接口习惯，独立实现，不复制代码 | 可商用（无衍生） |
| 西门子 SIMATIC 手册 / SCL 论坛帖 | 文档版权 | 仅参考算法参数域与防御设计，代码独立实现 | 可商用 |
| 施耐德 Machine Expert 帮助 | 文档版权 | 仅参考语义定义 | 可商用 |
| Industrial Monitor Direct 系列文章 | 文章版权 | 仅参考工程实践要点 | 可商用 |
| 中文技术博客（CSDN/博客园/电工电气） | 文章版权 | 仅参考陷阱清单 | 可商用 |

> 本轮**未抓取任何仓库源码文件**，`_Staging_Raw` 内不产生 `original_*.st`。因此不构成任何开源协议的衍生作品风险，`README_SOURCE.md` 可省略（无源码即无协议载体），以本笔记作为溯源凭证。

---

## 十、遗留待查（写入 ROADMAP 待办）

1. 查表法 CRC-16 在 InoProShop 下 `VAR CONSTANT` 大数组初始化的兼容性（影响是否提供 `FC_DL_Crc16ModbusTable`）。
2. `LWORD`（64 位）在汇川 InoProShop 的实际支持情况 → 决定是否出 64 位版 `FC_DL_BitGet64`。
3. 迟滞比较是否需要独立 FB 封装（带 `TON` 二次确认 + 故障锁存），当前仅出 FC + `VAR_IN_OUT` 状态版。
4. OSCAT `FILTER_DEBOUNCE` 的 `RST` 语义与本项目 `bReset` 语义对齐度需在下一轮做接口互操作核对。
