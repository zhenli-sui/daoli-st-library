# OPEN SOURCE SHOWCASE — 明星组件与技术推广

> 从十二轮 186 个组件中提炼 35 个「有话题、有对比、有实测」的明星组件，供 GitHub README、技术社区、公众号与行业分享使用。
> 文案均为中英双语，可直接复制；技术描述已与代码实现逐条核对。R3 批次（Phase 1 Level 0 收口）新增第 7~10 篇，R4 批次（Level 1 DL_Algo 开库收口）新增第 11~14 篇，R6 批次（组深化四线并进）新增第 18~19 篇，R7 批次（设备件十件套 + 工艺/运动深化）新增第 20~21 篇，R8 批次（同步耦合 + 工艺六件）新增第 22~23 篇，R9 批次（调度抽象 + 步进族 + 安灯）新增第 24~26 篇，R10 批次（拾放工站 + 卷绕排线 + ISO 周序号）新增第 27~29 篇，R11 批次（压装工站 + 端口诊断 + 分位数）新增第 30~32 篇，R12 批次（太阳位置 + 两轴插补 + 批次相底座）新增第 33~35 篇。

---

## 1. `FB_DL_MovingAverage` ｜ 两阶段启动的 O(1) 滑动平均

**一句话 / One-liner**：窗口 1~100 可运行时切换，扫描周期恒定，上电不再「比原始信号还抖」。

### 亮点 / Highlights

- **O(1) 递推**：一个指针同时承担「写入位」与「淘汰位」，计算量与窗口长度完全无关。20 点窗口不再跑 20 次加法。
- **两阶段启动**：窗口未满只追加不淘汰，填满后才进入递推替换。这条区分消除了滑动平均最经典的缺陷——上电头几秒滤波值比原始信号更剧烈。
- **窗口运行时重建**：`nWindowSize` 变化即清空缓冲重走填充阶段，避免新旧样本混算产生输出台阶。
- **浮点漂移校正**：每 10,000 次采样做一次全窗口重算，循环带迭代上限与 `EXIT`，不会把扫描周期拖死。
- **滞后写入文档**：相位滞后 ≈ `(N-1)/2` 个采样周期，明确警告安全联锁回路禁止使用大窗口值。

### 推广文案 / Promo Copy

> **中文**：滑动平均几乎所有 PLC 项目都写过，但很少有人写对。最常见的两个坑：一是每周期 `FOR` 循环累加，窗口一大扫描周期就飘；二是上电初期窗口没填满，代码照样执行「减去最旧值」，减掉的是还没写进去的 0，输出被系统性压低——现场表现就是「滤波器反而让信号更抖」。这个功能块用 O(1) 递推解决第一个坑，用「填充态 / 运行态」两阶段解决第二个坑，还顺手做了窗口运行时重建、浮点累加漂移校正，以及最容易被忽略的一件事：把相位滞后量写进文档，明确告诉你哪些回路不许用它。窗口 1~100，任意平台编译。

> **English**: Almost every PLC project has a moving average, and almost none of them are right. Two classic traps: a per-scan `FOR` loop whose cost grows with the window, and a startup phase where the code still "subtracts the oldest" — subtracting a zero that was never written, systematically dragging the output down and making the filter look noisier than the raw signal. This block fixes both: O(1) recursion for constant scan time, and an explicit filling/running two-phase design for a clean startup. It also rebuilds the buffer when the window changes at runtime, corrects floating-point drift with a bounded full recalculation, and documents the phase lag so you know which safety loops must never use a wide window.

**适合渠道**：GitHub README 头条、知乎/公众号「PLC 滤波的坑」长文、ST 社区代码评审帖。

---

## 2. `FC_DL_Crc16Modbus` ｜ 带实算验收向量的 Modbus CRC-16

**一句话 / One-liner**：不只是一段 CRC 代码，还带 4 条可复算的验收向量和一条「别人给错了」的勘误记录。

### 亮点 / Highlights

- **逐位法，零常量表**：只用 `SHR` + `XOR` + `AND`，没有 256 项常量数组，跨平台行为可预期。
- **顺序硬约束写进代码**：先取最低位 → 再右移 → 最后按标志异或多项式，这三步的顺序写反是最常见的实现错误，注释直接标明。
- **长度防御**：为零返回初值 `16#FFFF` 而非 `0`（`0` 是合法 CRC 值，返回它会让上层把「没算」当成「算对了」）；超限钳到 256 后继续计算，便于现场边通信边排错。
- **4 条实算向量**：`01 03 00 00 00 02 → 0BC4`、`01 03 00 00 00 0A → CDC5`、`11 03 00 6B 00 03 → 8776`、单字节 `0x0C → 45BF`，全部复核并验证唯一性。
- **勘误公开**：需求文档里流传的 `0x0C → 0x911E` 经穷举 0..255 无法复现，代码头注释留档说明，避免错误向量进入单测。

### 推广文案 / Promo Copy

> **中文**：找 CRC-16/Modbus 的 ST 实现，网上能搜到几十份，但几乎没有一份告诉你「怎么证明它是对的」。这个函数附带 4 条实算验收向量，其中一条还是「勘误」：广泛流传的单字节向量 `0x0C → 0x911E`，把 0..255 全部穷举一遍都算不出来，真实结果是 `0x45BF`。我们把这件事写进了源码注释——因为一条错误的测试向量，比没有测试更能摧毁信任：算法明明是对的，单测却永远红着。另外两个细节值得看：长度为零时返回初值而不是 0（0 是合法 CRC，返回它等于骗过上层），以及移位优先用 `SHR` 而不是 `/2`（整数除法在无符号与有符号上的平台差异，是跨平台移植的经典暗坑）。

> **English**: There are dozens of CRC-16/Modbus implementations in Structured Text online, and almost none of them tell you how to prove they are correct. This one ships four verified acceptance vectors — including an erratum: the widely circulated single-byte vector `0x0C → 0x911E` cannot be reproduced by exhaustive search over 0..255; the actual value is `0x45BF`. We documented that in the source header, because a wrong test vector destroys trust more thoroughly than no test at all: the algorithm is right and the test is permanently red. Two more details worth reading: a zero length returns the initial value rather than `0` (zero is a legal CRC, returning it would fool the caller), and shifting uses `SHR` instead of `/2` (integer division semantics for unsigned versus signed differ across platforms — a classic portability trap).

**适合渠道**：GitHub issue/讨论区「测试向量勘误」帖、Modbus 调试经验长文、嵌入式/工控交叉社区。

---

## 3. `FB_DL_SignalDebounce` ｜ 首扫零假边沿的触点消抖

**一句话 / One-liner**：上升/下降延时独立可调，上电不产生假边沿，边沿只脉冲一个周期。

### 亮点 / Highlights

- **双延时独立**：按下抖 5 次与松手抖 8 次是两种物理现象，用同一个延时是在将就。
- **首扫零假边沿**：`eInit` 态直接采样并把「稳定值」与「上一稳定值」同时赋值，边沿差恒为零。
- **边沿单一出口**：边沿在状态机之后统一计算，任何分支改写 `bStable` 都只产生一个脉冲，杜绝重发。
- **零延时合法**：`T#0S` 走直通快速通道，不会因 `PT := T#0S` 导致输出恒 `FALSE`。
- **抖动不累积**：输入回落时 `TON.IN` 变 `FALSE` 自动清 `ET`，计时不会跨抖动周期累加。
- **五态状态机 + `ELSE` 兜底**：非法状态一律进故障锁定，输出回安全值。
- **误用警告**：明确写出「软件消抖只对机械触点有意义」，固态/光电/霍尔/编码器/高速计数一律不适用。

### 推广文案 / Promo Copy

> **中文**：「按下按钮，HMI 上停机次数加了 4 次」——这是工控现场最经典的信号完整性问题。消抖代码人人会写，但几个细节决定了它是能用还是能坑人：上电第一次扫描要不要产生边沿？延时填成 0 会不会导致输出永远不动？输入反复抖动时定时器会不会偷偷累积计时？边沿事件会不会在一个周期里连发两次？这个功能块把四个问题都做成了结构性保证，而不是靠调用方小心。上升与下降延时独立可调，因为按下与松手的抖动是两回事。附带一句必须在手册里说的话：软件消抖只对机械触点有意义，光电、霍尔、编码器和高速计数输入不该用软件消抖。

> **English**: "I pressed the button once and the HMI counted four stops." That is the most classic signal-integrity problem on a machine floor. Everyone can write debounce code; what separates a usable block from a trap is the details. Does the first scan after power-up emit a phantom edge? Does a zero delay freeze the output forever? When the contact chatters, does the timer quietly accumulate time across bounces? Can the edge event fire twice in one scan? This block turns all four into structural guarantees instead of caller discipline. Rise and fall delays are independently adjustable, because pressing and releasing bounce differently. And one warning that belongs in every manual: software debounce is only meaningful for mechanical contacts — never for photoelectric, Hall, encoder or high-speed counter inputs.

**适合渠道**：公众号「现场故障复盘」系列、PLC 培训教材案例、Stack Overflow / 工控论坛问答引用。

---

## 4. `FC_DL_LinearScale` ｜ 反向量程也不出错的模拟量标定

**一句话 / One-liner**：量程填反、超量程、跨度为零——三种让现场停机的输入，它都不停机。

### 亮点 / Highlights

- **防除零**：跨度为 0 时返回工程量下限 + `16#0001_0002`，不抛异常、不产生 NaN 扩散。
- **反向量程合法**：`fInMax < fInMin`（20 mA → 0%、4 mA → 100%）是正常配置，不报错。
- **钳位前先排序**：输出量程传反时先 `MIN`/`MAX` 排序再钳位，避免把结果压到错误端点——这是本组件最隐蔽的失效模式。
- **双侧钳位**：只做上限是安全红线错误，负向冲击会直接打穿执行机构。
- **容差判等**：钳位判定用 `ABS(diff) > 1E-6`，不做浮点判等。
- **百分比旁路输出**：`fPercent` 可超 0..100，便于上位机画超量程趋势。

### 推广文案 / Promo Copy

> **中文**：模拟量标定是每个项目的第一行代码，也是现场最容易出事的一行。量程上下限填反、传感器断线导致跨度为 0、超压时数值冲到量程外——这三种输入里，有两种会让「标准写法」直接除零或输出越界值。这个函数把三种都处理了：跨度为零时返回安全值并给故障码；反向量程当作正常配置（4~20 mA 反向标定是真实需求，不是错误）；超量程时做双侧钳位，并且钳位前先给输出量程排序——因为输出量程填反时，不排序的钳位会把结果压到错误端点，现象是「钳位看起来生效了，输出全错」。还有一个常被忽略的细节：钳位是否发生，判定要用浮点容差，不能用 `<>`。

> **English**: Analog scaling is the first line of code in every project, and the one most likely to bite you on site. Reversed range limits, a dead transmitter producing zero span, an over-pressure value shooting past the range — two of these three will make the "standard" formula divide by zero or emit an out-of-range number. This function handles all three: a zero span returns a safe value with an error code; reversed ranges are treated as legitimate configuration (reverse 4..20 mA calibration is a real requirement, not a mistake); out-of-range inputs are clamped on both sides, and the output range is sorted before clamping — because with a reversed output range, unsorted clamping pushes the result to the wrong endpoint, and the symptom is "clamping looks like it works, but every value is wrong". One more detail people miss: whether clamping occurred must be decided with a float tolerance, never with `<>`.

**适合渠道**：GitHub README「Why another ST library」章节、工控社区「模拟量那些坑」专题、售前技术白皮书。

---

## 5. `FB_DL_StepSequencer` ｜ 把顺控逻辑从 14 层嵌套 IF 里救出来

**一句话 / One-liner**：动作外置、只推进步号；每步独立超时；换步屏蔽一拍，从结构上杜绝连环跳步。

### 亮点 / Highlights

- **动作不在块里**：块只输出 `nCurrentStep`，调用方在该步执行动作、把完成位填进 `abStepDone`。同一个块可以服务上百个工站，工艺改动只改调用方——这是它成为「基类」而不是「某工站代码」的唯一原因。
- **每步独立超时**：传感器坏了导致条件永假时，唯一能让现场看出「卡在第几步」的信息就是故障步号。`eFault` 刻意不清 `nCurrentStep` / `nFaultStep`。
- **换步屏蔽一拍**：完成位是电平，换步瞬间旧步的位可能还亮着。推进时置一个屏蔽请求、延后一拍提交，让换步后的第一个完整周期既不推进也不计时——旧位的残留正好被这个窗口吃掉（不稳定转换的结构性解法）。
- **步号只有一个写入点**：推进动作统一在状态机之后执行一次，从结构上排除跳步与重入。
- **暂停 / 单步 / 中止三件事分开**：`bHold` 冻结推进与超时；`bSingleStep` 完成即停等推进沿；`bAbort` 回空闲且**不设故障码**（操作员主动中止不是故障）。
- **故障码锁存**：`bError = TRUE` 期间 `uErrorId` 稳定可读，不会下一拍读回 0（v1.0.1 修复）。

### 推广文案 / Promo Copy

> **中文**：几乎每条产线的顺控逻辑都是这么长出来的——先写两个 `IF`，再嵌三个，一年后变成 14 层嵌套，改一个工步要在 300 行里找。更糟的是它**不可诊断**：某个工位的到位光纤坏了，机器就死死卡在第 7 步，HMI 上什么都不显示，班长只能凭经验猜。这个功能块换了个思路：**它不管动作，只管步**。你告诉它 16 个完成位和每步的超时时间，它告诉你现在在第几步、这一步跑了多久、卡住的是第几步。动作在你的代码里，工艺改动不动库；步号和计时在库里，现场诊断有据可查。还顺手解决了顺控里最阴的一个坑——**不稳定转换**：完成位是电平信号，换步那一刻旧步的位还亮着，照直读新步就会连跳两步。做法是推进时置一个屏蔽请求、延后一拍生效，让换步后的第一个完整周期既不推进也不计时，旧位的残留正好被这个窗口吃掉。附带暂停（冻结超时）、单步（维护工程师逐段验证）、中止（回空闲且不算故障）三种调试手段。

> **English**: Most production lines grow their sequence logic the same way: two `IF`s, then three more nested inside, and a year later it is fourteen levels deep — changing one step means hunting through 300 lines. Worse, it is undiagnosable: when an in-position sensor dies, the machine simply stops at step 7 and the HMI shows nothing. This block takes a different angle: **it does not run the actions, it runs the steps.** You hand it sixteen done-bits and a per-step timeout; it tells you which step is active, how long it has been there, and exactly which step is stuck. Your actions stay in your code, so process changes never touch the library; the step index and the timing live in the library, so diagnosis has evidence. It also kills the nastiest trap in sequencing — **unstable transitions**: done-bits are levels, so at the instant of a switch the old step's bit may still be TRUE, and reading the new step immediately would double-step the sequence. The fix is a mask request raised on advance and committed one scan later, so the first full scan after a switch neither advances nor times — the stale bit dies inside that window. Hold (freezes the timeout), single-step (segment-by-segment commissioning) and abort (back to idle, not a fault) come built in.

**适合渠道**：公众号「顺控逻辑重构」长文、GitHub README 架构章节、PLC 培训课程的状态机案例、技术社区「为什么你的顺控不可诊断」讨论帖。

---

## 6. `FB_DL_AlarmManager` ｜ 16 通道报警仲裁与首出锁存

**一句话 / One-liner**：停机级 / 警告级 / 提示级三级仲裁 + 先到先得首出锁存，确认只清锁存、不清激活。

### 亮点 / Highlights

- **首出靠「序号」而不是「扫描顺序」**：每通道激活时取一个全局递增序号，首出即序号最小者。低位通道不会因为「先被扫到」而永远抢先——这是 ISA-18.2 现场落地时最容易做错的一步。
- **确认三态正交**：激活（Active）/ 已确认（Acknowledged）/ 首出锁存（First-Out）是三个独立信号。`bAck` 只推进序号水位，不改变任何通道的激活态——「消音」和「故障消失」必须分开。
- **首出可补位**：确认后若还有更新的报警，按序号顺序自动成为新首出；已确认但仍在报警的通道不会重复抢占首出，直到它消失后重新激活。
- **报警字是最终事实**：禁用通道（优先级 0）对应位强制 0，即使该通道确实跳了。避免上位机看到的位图与 PLC 的仲裁结果互相矛盾。
- **冷启动行为写进文档**：上电即处于报警态的通道按扫描顺序依次取号，谁先被扫到谁是首出。这是电平敏感方案的固有行为，**披露比掩盖重要**。

### 推广文案 / Promo Copy

> **中文**：一个真实的现场故事：包装机 16 个工位的报警几乎同时涌进 HMI，操作工每次都先处理跳得最欢的那个警告级（料仓低），把真正让它停机的伺服过载放过十几秒，事后查不出「第一个跳出来的到底是谁」。这不是 HMI 的问题，是 PLC 里根本没有「首出」这个概念——大多数人只做了一个 `IF anyAlarm THEN ...`，把所有报警揉成一个布尔。这个功能块做三件事：**分级**（停机/警告/提示，停机级单独出联锁位）、**首出**（每通道激活时取一个递增序号，首出就是序号最小者，与通道物理位置无关）、**确认**（确认只推进水位、清掉首出锁存，绝不改变激活态）。这三件事分开之后，HMI 才能同时回答「现在有什么在报警」「谁先报的」「我确认过了但故障还在不在」。另外两个容易忽略的细节也做了：禁用通道在报警字里强制为 0（避免上位机和 PLC 各说一套），以及冷启动时已报警通道按扫描顺序取号——这是电平敏感方案的固有行为，我们写进文档而不是假装它不存在。

> **English**: A real shop-floor story: sixteen station alarms hit the HMI almost simultaneously on a packaging machine. The operator chased the loudest one — a low-level warning — and let the servo overload that actually stopped the machine sit for another fifteen seconds. Afterwards nobody could tell which alarm came first. That is not an HMI problem: the PLC simply had no concept of first-out, because the code was `IF anyAlarm THEN ...` collapsing everything into one boolean. This block does three separate things: **priority** (stop / warning / info, with the stop level exposed as its own interlock bit), **first-out** (each channel takes an incrementing sequence number when it activates, so the first-out is the smallest sequence — independent of channel position on the rack), and **acknowledge** (advancing a watermark and clearing the first-out latch, never touching the active states). Once those three are separated, the HMI can answer all three questions at once: what is alarming now, which one was first, and is it still there after I acknowledged it. Two details that usually get skipped are handled too: disabled channels are forced to zero in the bitmap (so the HMI and the PLC never disagree), and channels already alarming at cold start take their numbers in scan order — an inherent property of level-sensitive detection that we document instead of pretending it does not exist.

**适合渠道**：公众号「报警管理为什么总做不好」系列、ISA-18.2 学习笔记引用、GitHub README 的功能对比表、售前技术交流（对 OEM 讲首出价值最有效）。

---

## 7. `FC_DL_Crc32Ethernet` ｜ 能分块接力的以太网 CRC-32

**一句话 / One-liner**：逐位法零查表，附「链式种子契约」——固件包分批校验不用造中间缓冲。

### 亮点 / Highlights

- **分块链式种子契约**：`uCrcSeed` 入参 + `bFinalXor` 末块标志。前 n-1 块传 `FALSE`，把返回值直接当下一块的种子；末块置 `TRUE` 收口。分块大小任意（含单字节），链式结果与整包一次性计算**逐位一致**（验收向量 V4 实测："1234"+"56789" 分两块 = "123456789" 整包）。
- **多项式方向警示写进头注释**：反射多项式 `16#EDB8_8320` 配右移才是 CRC-32/ISO-HDLC；用 `16#04C11DB7` 配左移得到的是 BZIP2，混搭的错误结果毫无规律可排查——这是 CRC 实现第一大错。
- **中间块误置 `bFinalXor := TRUE` 的后果显式披露**：整包多异或一次终值，校验必失败且极难定位。
- **扫描周期披露**：256 字节 = 2048 次内层循环，明示放慢任务/事件触发，不进 1 ms 高速任务。
- **为什么比开源同类更适合现场**：OSCAT Network 的 CRC 家族按协议独立成函数（组织方式我们吸收了），但入参用地址指针、且没有分块语义——校验一个 64 KB 固件包就得先在 PLC 里攒出 64 KB 连续缓冲。链式契约让「边收帧边算」成为一行一个调用的接力，RAM 零额外开销；查表提速则按扩产规则另立查表变体，块内不加模式开关（禁止巨无霸）。

### 推广文案 / Promo Copy

> **中文**：以太网 FCS、ZIP、PNG 用的同一个 CRC-32，ST 实现不少，但几乎没有一个回答了现场的真问题：**报文不是一次到的，怎么办？** 大多数实现的答案是「先把整包攒进一个大数组再算」——在 PLC 里攒 64 KB 连续缓冲，既费内存又拖扫描周期。这个函数把「分块计算」做成了接口契约：种子入参接力、末块标志收口，链式结果与整包逐位一致，且有验收向量证明。头注释还写了两件别人不写的事：反射多项式配右移、正向多项式配左移混搭会算出另一个 CRC 变体（错误结果毫无规律），以及中间块误置末块标志的失败模式。逐位实现零查表、零 RAM 开销，要提速另立查表变体，绝不在一个函数里塞模式开关。
>
> **English**: This is the same CRC-32 that guards Ethernet FCS, ZIP and PNG, but the ST implementations you find online rarely answer the real field question: **the frame arrives in chunks — now what?** Most implementations say "buffer the whole message first", which means holding a 64 KB contiguous buffer inside a PLC. This function makes chunking an interface contract: the seed is an input, a final-XOR flag marks the last chunk, and the chained result is bit-identical to a one-shot computation over the whole message — proven by an acceptance vector. The header also documents what nobody else does: reflected polynomial with right shift versus the forward polynomial with left shift are two different CRCs, and mixing them produces garbage with no discernible pattern. Bit-wise implementation, zero lookup tables, zero extra RAM; a table-driven variant comes later as a separate component, never as a MODE switch inside this one.

**适合渠道**：GitHub README「OTA 固件校验」章节、EtherCAT/Profinet 诊断长文、工控社区「CRC 家族对比」帖。

---

## 8. `FC_DL_QuickSortLReal` ｜ 无递归的显式栈快排

**一句话 / One-liner**：显式栈替代递归 + 三数取中 + 小区间降级插入排序——实验室跑得通的递归快排，现场栈溢出；这一版不溢。

### 亮点 / Highlights

- **零递归**：ST 递归在部分嵌入式运行时与汇川 InoProShop 上栈深受限甚至不支持。64 元素最坏分区递归深度可达 64，实验室跑得通、现场爆栈——属不可交付实现。本实现用显式栈（深 16）+ WHILE 主循环承载分治。
- **先压大区间、后压小区间**是栈深 O(log n) 的唯一保证：小区间先被处理，大区间在栈中等待，栈内区间逐层减半。顺序写反，全等值数组会把 16 深栈打爆——这条顺序约束写进了头注释。
- **三数取中必须换位（对规格书的实算勘误）**：规格原文认为枢轴「只取值不必换位」，实算证伪——尾元素为三数中最小者时该元素永久错位。实现改为先把中值交换到区间末位再做标准 Lomuto。
- **双重降级**：显式栈溢出时子区间转插入排序兜底并置 `bUsedFallback` 诊断位；区间 < 8 元素自动走插入排序（小数组更快且无退化风险）。
- **失败不伪装成功**：NaN 预扫描拒绝时数组保持原样；保护触发时返回 `FALSE` 并声明「数组内容未定义，调用方丢弃本轮结果」。
- **为什么比开源同类更适合现场**：OSCAT 的排序用地址指针入参（本库红线禁指针，改数组引脚），LGF 用希尔排序但闭源；而网上流传的 ST 快排几乎都是递归版。这一版把「能不能在任何一家平台编译并跑到底」当成设计约束，而不是碰运气。
- **可复用范式**：显式栈模板可直接移植给其它分治算法（最近点对、凸包），已在头注释声明。

### 推广文案 / Promo Copy

> **中文**：网上能搜到的 ST 快速排序几乎都是递归版，而且「看起来能跑」。但 ST 递归在不少平台是二等公民：嵌入式运行时栈深受限，汇川 InoProShop 直接不支持——64 个元素最坏分区递归深度 64，实验室小样跑通了，产线上一跑全等值数组就爆栈。这个函数从头就不写递归：分治用显式栈承载，先压大区间后压小区间保证栈深对数级，栈万一满了还有插入排序兜底并亮诊断位，绝不静默。枢轴三数取中防退化，且我们实算抓出了规格书的一处想当然（「枢轴只取值不换位」会让最小元素永久错位），勘误留档。比较计数、交换计数、降级标志全部外露，性能可诊断，失败不伪装成功。
>
> **English**: Nearly every Quicksort in Structured Text online is recursive, and it "seems to work". But recursion in ST is a second-class citizen: embedded runtimes cap the stack depth, and InoProShop does not support it at all — worst-case partitioning of 64 elements recurses 64 deep, and an all-equal array will blow the stack on the production floor even though the lab demo ran fine. This function never recurses: divide-and-conquer rides on an explicit stack, larger subintervals are pushed first so stack depth stays logarithmic, and if the stack still fills up, an insertion-sort fallback finishes the job with a diagnostic flag — never silently. Median-of-three prevents the sorted-input degenerate case, and we even caught an erratum in our own spec ("take the pivot value without swapping it into place" permanently misplaces the smallest element) with the recomputation documented. Comparison and swap counters are exposed, and failure never masquerades as success.

**适合渠道**：GitHub README「为什么我们禁递归」章节、ST 社区「分治怎么写」技术帖、PLC 培训课程算法案例。

---

## 9. `FB_DL_DutyStandbyRotation` ｜ 8 台泵的主备轮值调度

**一句话 / One-liner**：按运行时间均衡轮值 + 双向最小时长保护 + 试验序列可行性检查——治「2 号泵锈死」和「接触器半年一换」两种对立顽疾。

### 亮点 / Highlights

- **试验序列可行性检查**：每拍先算「目标组合可达性」——可用台数、双向最小时长约束；轮值不可达时保持当前组合、置 `bRotatePending` 挂起并逐拍重试，绝不强行切到半途。无可用机组时，**已在运行的机组绝不因此被停**——现场把「就绪」信号摘掉时，停掉正在供压的泵比少启一台危险得多。
- **命令-反馈分离（借 LBP 聚合体粒度与 cmd/ind 思想）**：只发启动命令（cmd，FALSE = 停），运行一律以 `abUnitRunning` 反馈为准，绝不假设「发了命令等于在转」。
- **先启后停，刻意收紧**：停机放行条件是「目标集中已在运行台数 ≥ 需求」，比「在运行台数 ≥ 需求」更严，消除换机场景的压力/流量掉一拍。
- **双向最小时长**：最小运行时长防「刚启就停」，最小停机时长防「接触器高频动作」；故障机越权立即停机是唯一例外。
- **tie-break 陷阱实勘**：排序同运行时间的平局取「上一拍序列位置」而非索引升序——死守索引升序，刚做完的轮值下一拍就被原样排回去，轮值永不生效。本批实测踩到，勘误留档。
- **为什么比开源同类更适合现场**：OSCAT 与各家示例里的泵轮换多是「按时间轮流点名」的简化版，既不管运行反馈，也不管最小时长，更没有「目标组合切不过去怎么办」的概念——现场表现为切换瞬间掉压、或轮值条件永远不满足而无人知晓。这一版把「切不动的轮值」显式挂起、可诊断（`bRotatePending` / `abBlockedByMinRun` / `abBlockedByMinStop` 全部外露），运行小时与启动次数逐台可查。

### 推广文案 / Promo Copy

> **中文**：多泵系统有两种死法：一种叫「2 号泵锈死」——轮换逻辑从来没轮到它，检修时一开阀全是泥；另一种叫「接触器半年一换」——轮换切得太勤，最小时长没人管。市面上能抄的轮换代码基本是「按时间点名」的简化版：不看运行反馈、不管最小时长、更没有「这轮切不过去怎么办」。这个功能块把轮值当成一个调度问题做：按累计运行时间排序分派需求台数，每台机受最小运行/停机时长双重保护，故障机跳过且允许越权停机；关键的第四条安全语义是——**无可用机组时绝不停掉在运行的机组**，因为停掉正在供压的泵比少启一台危险得多。切不动的轮值显式挂起、逐拍重试、全部可诊断：谁被最小时长挡住、谁的启动被最小停机挡住，HMI 上一目了然。命令与反馈分离，「发了命令就当在转」这种假设从接口层就被禁止。
>
> **English**: Multi-pump systems die two ways: pump #2 rusts shut because rotation never reaches it, or contactors die in six months because rotation switches too eagerly. The rotation code you can copy from open sources is a "call names by schedule" simplification: no running feedback, no minimum-time protection, and no concept of "what if this rotation cannot complete". This block treats rotation as a scheduling problem: units are ranked by accumulated runtime, protected by bidirectional minimum run/stop times, faulty units are skipped and may be force-stopped. The fourth safety rule matters most: **when no unit is available, running units are never stopped because of it** — dropping a pump that is holding pressure is far more dangerous than starting one fewer. Impossible rotations latch into a pending state and retry every scan, fully diagnosable: which unit is blocked by minimum run time, which start is blocked by minimum stop time — all exposed. Commands and feedback are separated at the interface; "I sent a start so it must be running" is a forbidden assumption.

**适合渠道**：水处理/暖通行业公众号、GitHub README「泵站调度」章节、售前交流（对水处理 OEM 价值最高）。

---

## 10. `FB_DL_TwoHandSafety` ｜ 500 ms 同步窗 + 卡死诊断的双手启动

**一句话 / One-liner**：同步窗、释放窗、卡死判定三时分离；按钮被胶带缠住时，HMI 能说出「这是旁路嫌疑」而不是「操作不规范」。

### 亮点 / Highlights

- **三时分离**：同步窗（默认 500 ms，双手先后按下的最大间隔）、释放窗（100 ms，循环结束双手释放的最大间隔）、卡死判定（5 s，单侧持续按下即旁路嫌疑）是三个独立参数、三种物理现象，不在一个延时里将就。
- **卡死跨状态持续计时**：卡死按钮通常先以「同步超时」或「释放不同步」的面貌出现；本块跨状态持续计时，到卡死时限把故障码升级为旁路嫌疑并置 `bLeftStuck` / `bRightStuck`——HMI 才能区分「操作不规范」与「按钮被短接/被工件压住」。
- **一循环一武装**：一个循环结束后必须双手都释放才允许下一次启动（防单手按住不放连发），`bArmed` 外露。
- **定时器 Q 判时，不做时刻减法**：规避各平台 TIME 减法语义差异；五个实例（一边沿 + 四计时）主体最前部无条件刷新。
- **合规披露不删改**：明示这是标准 PLC 上的逻辑结构实现，ISO 13851 Type IIIC 的安全功能必须由安全继电器/安全 PLC 承担；定位是安全 PLC 中的逻辑骨架或标准 PLC 上的工艺互锁。**披露比伪装更重要**。
- **为什么比开源同类更适合现场**：网上流传的双手按钮示例基本是 `IF left AND right THEN out := TRUE`，同步窗都没有——两只手隔 3 秒按下也算「同步」，防旁路无从谈起；而且输入常带防抖，蚕食同步窗余量。本块刻意**不做防抖**并在文档写明「防抖由调用方前置、防抖时间计入同步窗，属串联而非替代」——输入是否防抖这种影响安全余量的决策，不该藏在块内部。

### 推广文案 / Promo Copy

> **中文**：双手启动按钮的示例代码网上很多，核心一行：`IF 左 AND 右 THEN 输出`。这一行防不住任何真实事故：两手隔 3 秒先后按下也算「同步」；按钮被胶带缠住后块永远不知道；一个循环没松手就能连发下一次。这个功能块把三件事拆开：**同步窗**（500 ms 内双手先后按下才算）、**释放窗**（循环结束双手都要松开才能再武装）、**卡死诊断**（单侧持续按下超 5 s 升级为旁路嫌疑并分侧锁存指示）。卡死的狡猾之处在于它先伪装成操作不规范——同步超时、释放不同步，所以卡死计时必须跨状态持续。还有一个反直觉的设计：输入刻意不防抖，因为防抖延时蚕食同步窗余量，这个影响安全余量的决策必须在调用方显式做，块内不悄悄代劳。最后是一段不删改的合规披露：这是逻辑结构实现，不是安全认证功能块——标准 PLC 上它做工艺互锁，安全功能请交给安全继电器。
>
> **English**: Sample code for two-hand start controls is everywhere, and the core is one line: `IF left AND right THEN out`. That line prevents nothing: presses 3 seconds apart count as "synchronous"; a taped button is invisible forever; one cycle can fire the next without releasing. This block separates three phenomena into three timers: a **sync window** (both hands within 500 ms), a **release window** (both released before re-arming), and **stuck-button diagnostics** (one side held beyond 5 s escalates to a bypass suspicion, latched per side). The cunning part of a stuck button is that it first masquerades as operator error — a sync timeout, an asymmetric release — so stuck timing must persist across states. One counter-intuitive choice: inputs are deliberately **not** debounced, because debounce delay eats into the sync window margin — a decision that affects safety margin belongs to the caller, done explicitly, never silently inside the block. And a non-negotiable compliance disclosure: this is a logic structure, not a certified safety function; the safety role belongs to safety relays or safety PLCs.

**适合渠道**：公众号「压机安全复盘」长文、IEC 60204 / ISO 13851 学习笔记引用、安全培训教材案例。

---

## 11. `FB_DL_PidController` ｜ 两级抗饱和 + 手自动真无扰的 PID

**一句话 / One-liner**：触限停积分 + 限幅反算回填两级抗饱和；手动期逐拍回填积分与历史，切回自动那一拍输出数学上保证连续。

### 亮点 / Highlights

- **两级抗积分饱和**：第一级「触限停积分」（条件积分）拦住九成饱和；仍超限的第二级做**限幅反算回填**（`fInt := fLim - fP - fD`），让积分器永远不藏「不可能兑现」的电量。比 OSCAT FT_PIWL 单级方案多一道闸，比只做钳位的实现多一份可解释性。
- **手自动无扰是数学保证，不是巧合**：手动期不是「冻结等回来」，而是每拍执行 `fInt := fManualOut - fP - fD`，并同步滚动全部历史偏差变量——切回自动首拍的增量恒为 0。这是终审修出来的关键：手动期不同步历史，切回瞬间微分/增量项会踢腿（v1.0.1 修复）。
- **位置式/增量式用独立布尔表达**：不搞模式枚举堆功能，`bIncremental := TRUE` 即增量式；块名即行为。
- **积分分离与死区可独立配置**：大偏差时切出积分防超调，小偏差死区抑制执行器抖动；Ti=0 / Td=0 有明确语义（关闭该项，非非法）。
- **信息级码与故障码分离**：输出饱和（0002_0101）是调节常态，只进趋势不进 `bError` 报警链——报警链只留给真故障（终审修复）。

### 推广文案 / Promo Copy

> **中文**：PID 是工控界写得最多的算法，也是坑藏得最深的。两个经典翻车现场：加热到 95 °C 时输出早就饱和在 100%，积分器却还在偷偷累加「永远兑现不了」的电量，等温度终于回落，积分器的存货让输出在上限死死顶住好几分钟——这是抗饱和没做对。手自动切换回自动的那一拍，输出突然跳 30% 执行器猛冲——这是手动期积分和历史没同步。这个块把两件事都做成了数学保证：饱和用「停积分 + 限幅反算回填」双级处理，积分器永远不会背着不可能的电量；手动期每拍把积分反算到位、把四个历史变量逐拍滚动，切回自动首拍的增量在数学上恒为零。另外一件小事很值得看：输出饱和被明确标为「信息级」而非故障——正常调节不该触发报警，否则报警链迟早被现场学会无视。
>
> **English**: PID is the most-written and most-broken algorithm in industrial control. Two classic failures: the output saturates at 100% while the integrator keeps banking credit it can never spend, so when the temperature finally falls the output stays pinned for minutes — anti-windup done wrong. And the instant you switch back to auto, the output jumps 30% — manual mode never synchronized the integrator and the history variables. This block turns both into mathematical guarantees: two-stage windup protection (conditional integration plus back-calculation `fInt := fLim - fP - fD`) so the integrator never holds impossible credit, and per-scan synchronization of the integrator and all history variables during manual mode, so the first auto scan contributes exactly zero increment. One subtle detail worth noting: output saturation is classified as an *information* code, not a fault — normal regulation must not trip the alarm chain, or operators learn to ignore it.

**适合渠道**：GitHub README「PID 做对了什么」章节、公众号「抗积分饱和的两种死法」长文、温控 OEM 售前技术包。

---

## 12. `FB_DL_SCurveGenerator` ｜ 七段式 jerk 限制轨迹规划器

**一句话 / One-liner**：jerk→加速度→速度→位移四级积分链、七段相变控制，每拍按剩余距离自适应截断减速行程——柔性冲击从算法层被消除。

### 亮点 / Highlights

- **完整的 jerk 限制链**：不规划梯形速度曲线，而是从加加速度（Jerk）起四级积分——jerk 积分出加速度、加速度积分出速度、速度积分出位移。七段相变（加加速/匀加速/减加速/匀速/加减速/匀减速/减减速）全部由显式状态机驱动，机械冲击被限制在 `fMaxJerk` 以内。
- **自适应减速截断披露在案**：340 行预算内不做全量闭式解，改为**每拍估算剩余距离所需减速行程（含 1.05 裕量系数），不足即提前进入减速段**——最大速度/加速度/Jerk 三约束仍然全部满足。这个近似写进了头注释，没有伪装成精确解。
- **新目标必须先判后吸附**：eDone 分支先判「距新目标是否超容差」再吸附输出（终审修出的缺陷：先吸附再判则恒差 0，到位后换目标永远不动）。
- **相位卡死兜底**：同一段持续超 10⁴ 拍强制进故障态——轨迹规划器的死锁不该表现为「永远不动且不报错」。
- **零依赖**：不依赖任何轴接口与厂商运动库，纯算法块——伺服点位给定前级、升降机构、注液泵平滑启停都能用。

### 推广文案 / Promo Copy

> **中文**：梯形加减速「能用」，但启动和停止那一瞬间的加速度突变，就是产线上听得到的「哐」一声。S 型轨迹难写不是难在概念，是难在细节：七段相位的切换条件互相耦合，一段写错整条轨迹就锁死。这个块用 jerk→acc→vel→pos 四级积分链承载七段状态机，把「剩余距离不够减速」做成每拍自适应截断——不是精确闭式解，这个近似我们写在头注释里，但速度/加速度/Jerk 三个上限一个都不破。还有一个终审抓出来的坑值得所有人看：到位状态里「先吸附输出再判断是否到达新目标」，恒差为零，永远判定已到达——换目标从此失灵。事件判定的比较基准必须是上一拍的记忆，这条教训比 S 曲线本身更值钱。
>
> **English**: Trapezoidal motion "works", but the acceleration steps at start and stop are the bang you hear on the floor. S-curves are hard not in concept but in detail: the seven phase-transition conditions are coupled, and one wrong branch locks the whole trajectory. This block rides a jerk→acc→vel→pos quadruple integration chain with an explicit seven-state machine, and handles "not enough distance left to decelerate" with a per-scan adaptive truncation — not a closed-form solution (the approximation is documented in the header), but all three limits — velocity, acceleration, jerk — are still respected. One audit find everyone should see: in the done state, "snap the output first, then check if a new target arrived" compares a value against itself — always zero, so a new target is never detected. The comparison basis of an event must be last scan's memory. That lesson outlives the S-curve itself.

**适合渠道**：GitHub README 运动控制章节、公众号「为什么你的 S 曲线不动」复盘文、伺服集成商技术交流。

---

## 13. `FB_DL_SmithPredictor` ｜ 给大滞后对象一个「提前看到未来」的 PID

**一句话 / One-liner**：内嵌一阶+纯滞后模型实时仿真「如果没有滞后过程会怎样」，用补偿后误差驱动内嵌 PID；模型偏差在线自适应校正，学习态退化不阻塞控制。

### 亮点 / Highlights

- **纯滞后用队列，不用延时函数**：20 槽实数环形队列承载模型纯滞后（tModelLag / tSampleTime 折算槽深），控制量先过模型再过队列，`fErrComp := fPv - (fModelDelayed + fModelBias)`——补偿后误差驱动内嵌 PID，等效把环路里的纯滞后摘掉。
- **模型误差在线自适应**：`fModelBias += fKb * (fPv - fModelDelayed - fModelBias) * fDt` 小增益缓慢校正模型静态偏差——模型永远不准，重要的是它知道自己差多少。
- **学习态是工程亮点**：上电后队列未填满时自动退化为普通 PID（用原始误差闭环），队列满了才切全补偿——**从不阻塞控制**，不会因为「模型没准备好」让回路裸奔或停摆。
- **截断是自愈不是故障**：模型滞后超队列上限时钳位截断并置信息级码 0002_0502，不置 bError——终审修出的缺陷：把自愈钳位当故障报，等于鼓励现场关诊断。
- **内嵌 PID 复用 PidController**：抗饱和、手自动无扰、信息级码分离全部继承，不自写 PID 律——组合优先范式的实证。

### 推广文案 / Promo Copy

> **中文**：长管道加热、烘箱、生化反应釜这类对象，调 PID 的痛苦不在参数难整，在纯滞后：你把加热开大，一分钟之后温度才有反应，等温度超调了你再减，反应又在路上——环路增益被滞后逼得很低，响应慢得没法看。史密斯预估器是教科书答案，但现场实现少，因为坑多：模型永远不准怎么办？上电时模型还没「热身」怎么办？这个块的答案是：模型偏差用小增益在线缓慢校正（模型知道自己差多少）；上电后队列没填满就自动退化成普通 PID，绝不阻塞控制，热身完毕自动切全补偿；模型滞后超过队列容量时截断并亮「信息级」灯——自愈行为不该报故障。内嵌的 PID 直接复用我们带两级抗饱和的 PidController，一处改进处处受益。
>
> **English**: For long-pipe heating, ovens and bioreactors, tuning PID hurts not because parameters are hard but because of dead time: you raise the heat, the temperature answers a minute later, and by the time you react your correction is already in the pipe — loop gain gets crushed by lag and response crawls. The Smith predictor is the textbook answer but rare in the field because it is full of traps. This block answers the traps: model bias is slowly corrected online with a small adaptation gain (the model knows how wrong it is); during queue fill-up after power-on it degrades to a plain PID — never blocks control — and switches to full compensation automatically; when the model lag exceeds the queue it truncates and raises an *information* code, because self-healing behavior must not be reported as a fault. The embedded PID reuses our two-stage anti-windup PidController — one improvement benefits everywhere.

**适合渠道**：过程控制行业公众号「大滞后回路急救」长文、GitHub README 过程算法章节、热工/化工 OEM 技术白皮书。

---

## 14. `FB_DL_CascadePid` ｜ 串级不是两个 PID 串联，是一组边界条件的合集

**一句话 / One-liner**：组合两个 PidController 实例的串级块——主输出先钳到副设定域、采样周期与限幅由本块统一注入、手动期主环跟踪副设定，回自动零跳变。

### 亮点 / Highlights

- **不自写 PID 律**：内部组合 `FB_DL_PidMaster` / `fbPidSlave` 两个实例——单回路的抗饱和、无扰切换、信息级码分离自动继承，串级层只负责**串级独有的边界条件**。组合优先范式的样板。
- **主输出钳到副设定域**：主回路输出先钳位 `rSpSlaveMin..rSpSlaveMax` 再进副回路——防副设定飞出量程导致副回路长期饱和（这是串级现场翻车第一名）。
- **参数单点注入**：两个实例的 tSampleTime / rOutMin / rOutMax 由本块统一注入，**禁止调用方双份配置**——否则两个回路的采样周期不一致，串级相位差是查不出来的隐形病。
- **手动期主环跟踪副设定**：手动时副环直接手动输出，主环经 bTrack 跟随 `fSpSlave`——切回自动时主环从「副环正在的实际工作点」出发，零跳变。
- **典型组合即文档**：温控（主温度/副加热功率）、张力（主张力/副速度）两种接法写进手册典型组态——串级的难点从来不在块内，在「怎么接」。

### 推广文案 / Promo Copy

> **中文**：很多人以为串级 PID 就是把两个 PID 串起来，第一个的输出接第二个的设定。真正让它翻车的是三个边界条件：主环输出没钳位，副设定飞出量程，副回路长期饱和无人知晓；两个回路的采样周期各自配置，相位差是隐形病，故障时查不出原因；手动切自动的那一拍，主环从旧设定出发而不是从副环的实际工作点出发，输出跳变执行器猛冲。这个串级块把三件事全部内建：主输出先进副设定域钳位；采样周期与限幅由块统一注入、调用方不许双份配置；手动期主环跟踪副设定值，回自动零跳变。而 PID 本体直接组合两个 PidController 实例——单回路做对了的事，串级层一行都不重写。
>
> **English**: Cascade PID is not "two PIDs in series" — that's the part everyone gets right. What actually breaks it are three boundary conditions: the master output is not clamped to the slave setpoint range, so the slave saturates forever; the two loops carry independently configured sample times, a phase-lag disease that no one can diagnose later; and the bumpless transfer starts the master from its old setpoint instead of the slave's actual operating point, producing a jump. This block builds all three in: master output is clamped to the slave setpoint domain first; sample time and limits are injected by the cascade block itself, double configuration is forbidden; in manual mode the master tracks the slave setpoint via tracking inputs, so the return to auto starts exactly where the loop physically is. And the PID core is simply two composed PidController instances — whatever the single loop does right, the cascade inherits without rewriting a line.

**适合渠道**：GitHub README「组合优先」架构章节、温控/张力 OEM 售前包、公众号「串级翻车三连」复盘文。

---

## 15. `FB_DL_PackMlStateMachine` ｜ 十七态框架：让机台层只派发动作，不管理状态

**一句话 / One-liner**：PackML / ISA-TR88.00.02 十七态 + 11 命令的纯状态机框架——acting 态自动推进、wait 态等命令，机内保持与机外挂起正交出口，工艺动作零内嵌。

### 亮点 / Highlights

- **acting/wait 二分写进枚举注释**：Clearing/Starting/Holding 等 10 个 acting 态由 `bStateComplete` 单发自动推进，Stopped/Idle/Execute/Held 等 7 个 wait 态等命令——跃迁表一眼可审计，交接文档不用另画状态图。
- **Held ≠ Suspended，OEE 根因从此不扯皮**：`bHeldByMachine`（机内原因，联锁失失）与 `bSuspendedByLine`（机外原因，线体/供料）两个正交输出位，停机归因数据质量直接决定 MES 的 OEE 统计能不能用。
- **Aborting 最高优先级出口 + 强制去污步**：`bProcessAbort` 电平任意态直达 eAborting；恢复链必经 Clear→Clearing→Stopped——「急停后不许原地续跑」是包装机安全审核的硬门槛。
- **模式切换稳态门禁**：仅 eStopped/eIdle/eCompleted 三个稳态允许切 Production/Maintenance/Manual，其余态变更被拒并置信息级码（不置故障）——拒绝也是带原因码的拒绝。
- **纯框架零工艺**：本块不编排任何具体动作，调用方按 eState 分态派发；与 `FB_DL_PackMlCmdDecoder` 组合即得「多命令源仲裁 + 单发化 + 冲突丢弃」的完整命令入口。

### 推广文案 / Promo Copy

> **中文**：机台程序最难维护的不是工艺逻辑，是状态管理——急停从哪个态都能进吗？保持和挂起是一回事吗？批次完成后怎么回空闲？PackML 花了二十年回答这三个问题，我们把它做成了一个不掺任何工艺的状态机框架：十七个状态、十一个标准命令、acting 态自动推进，机内保持（联锁断了）和机外挂起（线上没料了）分开指示，急停必经去污步才能恢复生产。你的机台代码从此只剩一件事：看状态、派动作。
>
> **English**: The hardest part of machine code is not the process logic — it is state management. Can abort fire from any state? Are "held" and "suspended" the same thing? How does a completed batch get back to idle? PackML spent twenty years answering these; we turned the answers into a state-machine framework with zero process logic baked in: 17 states, 11 standard commands, acting states auto-advance, machine-internal holds and line-external suspends are reported as orthogonal bits, and abort always passes a cleanup step before production resumes. Your machine code is left with exactly one job: watch the state, dispatch the action.

**适合渠道**：包装/锂电/食品 OEM 技术方案书、ISA-TR88 落地实践公众号长文、GitHub README「Level 2 机台模板」章节。

---

## 16. `FB_DL_SingleAxis` ｜ 一套状态机，仿真与真机通吃

**一句话 / One-liner**：PLCopen 轴状态机（六态 + Disabled）clean-room 实装——虚拟运动学开关一键切换仿真积分与真实注入，指令仲裁、软限位预判、故障锁存全部内建。

### 亮点 / Highlights

- **同一状态机适配真实驱动与仿真**：`bUseVirtualKinematics=TRUE` 时位置由内部梯形段积分器生成（无硬件也能跑 HMI/逻辑联调）；FALSE 时直接采纳上层每拍注入的实际位置——逻辑先行、驱动后接，现场调试少一次「等设备」。
- **指令仲裁 Absolute > Relative > Velocity**：同拍多指令按优先级落选丢弃并置信息级码（安全侧「不猜」）；eStopping/eErrorStop 态拒绝一切运动指令，严格 MC_Stop 语义。
- **软限位两道防线**：目标位越限在指令受理时直接拒绝；连续运动中按当前速度现算制动距离，进入警戒区提前减速停车——而不是撞了再说。
- **指令全部单发化**：6 个方法（Enable/Reset/Stop/MoveAbsolute/MoveRelative/MoveVelocity）达接口红线临界但一个不多——回零拆给后续 FB_DL_AxisHomingSeq，职责不膨胀。
- **bError 派生式严格 R21**：驱动故障 → eErrorStop 锁存仅 Reset 可清；指令丢弃、参数修复等信息级码只进 uErrorId 趋势，不污染报警链。

### 推广文案 / Promo Copy

> **中文**：买不到伺服也能把机器逻辑写完吗？这个单轴块用 bUseVirtualKinematics 一个布尔量回答：TRUE 时位置由内部积分器仿真生成，HMI、联锁、节拍逻辑全部先跑起来；驱动到货后翻成 FALSE，同一套状态机直接接真实反馈。PLCopen 六态状态机、指令仲裁、软限位制动距离预判、故障锁存与复位语义，都是现场验收单上的常客——我们只是把它们一次做齐。
>
> **English**: Can you finish the machine logic before the servos arrive? One boolean answers it: with bUseVirtualKinematics on, position comes from an internal trapezoidal integrator, so HMI, interlocks and cycle logic all run today; flip it off when the drive lands and the same state machine takes real feedback. A PLCopen six-state model, command arbitration, braking-distance soft-limit anticipation and latched fault semantics — the items every commissioning checklist asks for, delivered in one block.

**适合渠道**：运动控制入门教学专栏、设备厂商「逻辑先行」开发流程白皮书、GitHub README 运动章节。

---

## 17. `FB_DL_HeatCoolZone` ｜ R4 算法族的第一个「上桌消费者」

**一句话 / One-liner**：双通道温控区——注入式 PID → 分程分配 → 双路 PWM SSR，断偶按安全方向切断并锁存，R4 的 PID/PWM 算法件在这里第一次组成完整的温控方案。

### 亮点 / Highlights

- **零内嵌组态的组装范式**：`fbPid` / `fbPwmHeat` / `fbPwmCool` 三个实例全部经 IN_OUT 引脚注入，参数外置——本块只做「控制律的编排」，不做「参数的保管」，同一块适配 1 kW 加热棒与 50 kW 模温机。
- **分程 + 中性带防双通道同开**：PID 输出低于 fSplitLow 进加热段、高于 fSplitHigh 进冷却段、中间为热平衡中性带；分程点越界/对调自修复（信息级），跨度不足的通道自动禁用（防除零）。
- **断偶安全方向可配置**：`eBreakAction` 按对象安全策略选切断加热还是切断冷却；锁存期间双通道全断为最终安全态，退出需 CmdReset 且信号质量恢复 eGood——「方向选错比不断偶更危险」的教训写进了接口。
- **温度信号源走接口契约**：`iTempSensor : I_DL_AnalogSensor` 引用注入，NE43 四段诊断（断线/欠量程/有效/超量程）由 FB_DL_AnalogTransmitter 供给——设备层组件互相组合而非互相复制。
- **无扰三重奏**：投运首拍、故障复位回投、外部跟踪（bTrack/fTrackValue）三处跃迁全部走无扰同步，输出功率 [-100..100 %] 正负号即加热/冷却方向，量纲注释与限幅域严格一致（R20）。

### 推广文案 / Promo Copy

> **中文**：一热一冷两个执行器，中间夹着一段既不能加热也不能冷却的安全区——这就是加热/冷却温控区的全部难点：分程点怎么定？断偶了先停哪一路？PID 参数放在块里还是块外？这个块给出的是组装件答案：PID 和两路 PWM 全部注入（参数外置，换机型不动代码），分程带与中性带防双阀同开，断偶方向按你的对象安全策略配置、锁存后双通道全断，复位还要求信号质量先恢复。R4 辛苦打磨的算法件，在这里第一次组成了能直接进机柜的方案。
>
> **English**: One heater, one chiller, and a dead band where neither may act — that is the whole difficulty of a heat/cool zone. Where do the split-range crossovers go? Which channel trips first when the sensor breaks? Do PID parameters live inside the block or outside? This block answers with composition: PID and both PWM channels are injected instances with external tuning, crossover and neutral bands prevent both actuators firing together, break action follows your object's safety policy with a full-channel shutdown latch, and reset demands the signal quality back to Good first. The Level-1 algorithm family finally sits at the table as a panel-ready solution.

**适合渠道**：暖通/注塑/半导体温控 OEM 售前包、公众号「分程控制实战」、GitHub README「组合优先」章节压轴案例。

---

## 18. `FB_DL_AxisHomingSeq` ｜ 回零不是一条指令，是一个带双护栏的序列状态机

**一句话 / One-liner**：限位开关/原点开关/Z 相脉冲/扭矩堵转四模式回零——逼近-回退-爬行再逼近-标定的公开时序 + 超时·行程双护栏 + 终态可重启，步号全程外露。

### 亮点 / Highlights

- **四模式一套状态机**：PLCopen 把回零模式定义为「方向 × 信号源 × 终点」的组合矩阵（各家手册的模式编号从 1 到 35 不等）——本库只取四种高频模式入册，模式编号用自有枚举而非任何厂商魔法数；其余组合按矩阵规则扩产，绝不塞进带 35 分支 CASE 的巨无霸。
- **时序是公开语义，护栏是本库加严**：「快速逼近-回退-爬行再逼近-标定」三段式是各家文档完全一致的公开时序，clean-room 无争议；在此外加两道护栏——回零总超时 + 行程超限（启动点距离护栏，防堵转回零无限行程），故障锁存码 `0004_0210/0211` 分立可辨。
- **终态死锁的教训写进了实现**：初版完成/中止/故障三终态无迁出路径，首次回零后永远无法再次回零（生产节拍内第二次回零必失效）——终审逐拍推演抓出后改为「终态重启借道」：三终态收到新启动沿回空闲并由门禁分支同拍受理，不吞沿、不要求操作员双击。
- **全部经轴接口驱动**：序列的每一段运动都经 `I_DL_MotionAxis` 的 MoveVelocity/MoveRelative/Stop 组合发出，本块绝不产生自有速度输出——换真实驱动、换仿真轴、换第三方轴封装，回零序列一行不改。
- **坐标系建立不越权**：标定成功后暂存 `fHomePosition`，不直接写轴内部状态——`bHomed` 与坐标系写入由上层联动，「谁拥有轴状态」的边界画在接口上。

### 推广文案 / Promo Copy

> **中文**：伺服调试第一天必碰的问题就是回零，而回零恰恰是「看起来一条指令、实际一个状态机」的典型。这个回零序列块把四种高频模式（限位开关、原点开关、Z 相脉冲、扭矩堵转）做成一套九态状态机：快速逼近、回退脱离、爬行再逼近、标定原点、受控停车，每一步的步号都外露给 HMI——「卡在哪一步、是超时还是行程超限」直接可读，不用接示波器猜。运动指令全部经轴接口发出，序列本身不产生任何速度输出，所以换驱动不用改它。还有一条用真金白银换来的教训：初版的完成/中止/故障三个终态没有出口，首次回零后永远无法第二次回零——现在终态收到新启动沿会自动重启，不吞沿。超时和行程双护栏是标配，堵转回零不再有「无限行程」的隐患。
>
> **English**: Homing is the first thing every servo commissioning meets, and it is never "one instruction" — it is a state machine. This homing block implements the four high-frequency modes (limit switch, home switch, encoder zero pulse, torque block) as one nine-step state machine: approach, retreat, creep re-approach, calibrate, controlled stop — with the step index exposed to the HMI, so "stuck at which step, timed out or travel-exceeded" is readable without an oscilloscope. Every motion goes through the axis interface; the sequence itself emits no velocity of its own, so swapping drives changes nothing. One lesson paid for in real debugging: the first version's three terminal states had no exit, so the second homing of the shift could never run — terminal states now restart on a new start edge. Timeout and travel guards are standard, and torque-block homing no longer risks an endless run.

**适合渠道**：运动控制调试专栏「回零失败复盘」长文、伺服集成商技术交流、GitHub README 运动控制章节、PLC 培训课程状态机案例。

---

## 19. `FB_DL_EnthalpyCompareCtrl` ｜ 把「干球低 ≠ 焓低」写成一行判据的经济器执行块

**一句话 / One-liner**：新风/回风温湿度 → 双侧湿空气焓值实时计算 → 差分焓值施密特迟滞判据 → 新风阀位指令；最小新风位硬下限 + ASHRAE 90.1 高限停机内建，失效方向显式落在保守安全侧。

### 亮点 / Highlights

- **差分焓值判据内建为可复用块**：固定干球切换在湿工况是经典翻车——70°F 近饱和新风的焓可以高于 75°F/50% 回风，干球切换反而增冷负荷。本块每拍调用两次湿空气焓值函数计算双侧比焓，按「新风焓 < 回风焓 − 死区开 / > 回风焓 + 死区关」的施密特迟滞判据出阀位指令，临界抖动被迟滞半宽吸收。
- **卫生通风底线是硬下限不是建议**：经济器关闭时新风阀不得低于最小新风位——输出恒有「阀位指令 ≥ fMinOaPos」的钳位，ASHRAE 90.1 焓值高限停机做成可选门限（默认禁用），暖湿气候按气候区整定。
- **失效方向显式披露（D4 裁定）**：负干球温度经焓值计算链钳位至 0 摄氏度——新风焓偏高估计 → 经济器少开 → 不会引入高焓空气，误差方向恒为保守安全侧，仅损失潜在免费冷量（能效项非安全项）；取舍通道写在头注释里，是否放行负干球由调用方决定。
- **输入失效安全侧冻结**：任一温湿度非有限值/越域 → 阀位回最小新风位兜底值 + 故障锁存（参数类 REAL 输入经终审补齐非有限值防御，含自比检测）——传感器坏掉时经济器安静地退回最小新风，而不是跟着坏数据开大阀。
- **Level 1 → Level 2 链路示范**：直接消费算法库的焓值函数、输出直连设备库的模拟量阀整形块——三行代码组成完整新风控制链，是「组件组合而非复制」的样板。

### 推广文案 / Promo Copy

> **中文**：「今天 15 度比昨天 20 度凉爽，为什么空调反而更费电？」——因为干球温度低不代表空气总热含量低：湿度一上来，15 度近饱和的空气焓值完全可能高于 25 度的干燥回风。按干球切换新风阀的经济器在阴雨天会主动把又湿又「贵」的空气往机房里引。这个执行块把正确判据做成了即插即用件：每拍实时算新风和回风的湿空气焓值，焓差判据带施密特迟滞防临界抖动，最小新风位（卫生通风底线）是硬下限而不是文档建议，ASHRAE 90.1 高限停机可选启用。更值得看的是失效设计：传感器失效时阀位安静退回最小新风位并锁存故障码，负干球域的焓值估计误差被证明恒落在「少开、不多开」的保守侧——暖通控制里，「失效时往哪边错」比「平时多准」更值钱。
>
> **English**: "Why does the AHU use more cooling on a cool humid day than on a warm dry one?" Because a low dry-bulb does not mean low heat content: near-saturated air at 15 °C can carry more enthalpy than 25 °C return air, and a dry-bulb economizer happily pulls that expensive air inside on rainy days. This block makes the correct criterion plug-and-play: outdoor and return-air enthalpies computed every scan, a differential-enthalpy Schmitt band that absorbs chatter, a minimum-position hard floor (the ventilation bottom line, not a suggestion) and an optional ASHRAE 90.1 high-limit trip. The failure design matters most: on sensor failure the damper quietly returns to minimum position with a latched code, and the negative-dry-bulb estimation error is proven to always fall on the "open less, never more" conservative side — in HVAC control, which way a failure errs matters more than how precise it is on a good day.

**适合渠道**：暖通自控公众号「经济器为什么总在阴天失灵」长文、ASHRAE 90.1 落地实践帖、绿色建筑/数据中心节能售前包、GitHub README 过程控制章节。


---

## 20. `FB_DL_SafetyLightCurtain` ｜ 序列式屏蔽：光幕不是「挡住就停」，是一台有方向的状态机

**一句话 / One-liner**：2/4 传感器序列屏蔽 + 错乱即故障 + override 硬帽，`bSafeStop` 永不因屏蔽置假——把 SICK mut_p 与西门子 Sequential Muting 的公开语义 clean-room 落成一个可审计的状态机。

### 亮点 / Highlights
- **方向是有语义的**：屏蔽序列由「首遮挡传感器」判向（M2/M4 先遮挡 = 反向），一经判定锁定至本序列结束——物料从左进右出还是右进左出，状态机都知道。反向分支与正向分支逐条镜像，错乱（序列步与传感器实际状态不符）立即退出屏蔽并故障锁存，`bSafeStop` 按光幕实际 OSSD 状态输出，绝不因「屏蔽中」就放行。
- **安全镜像位出口断言**：`bSafeStop`（应停机输出）在屏蔽/override 态恒 FALSE——「屏蔽」这个功能本身永远不会伪造一个「安全」的假象。这是接口级契约，实现块出口断言承载。
- **三层时间护栏**：屏蔽总时长上限（首末传感器间隔超限即故障）、滞留清除 override 硬帽（钥匙开关不能永久旁路）、OSSD 双通道容差窗（不一致超时即故障）——屏蔽功能的三种经典失效模式各自有独立码位。
- **定位诚实**：头注释公约 0.13 明确「本块为逻辑编排与诊断镜像层，不构成 ISO 13849 / IEC 62061 认证安全功能」——安全回路在认证安全控制器，本块把编排与诊断做扎实，不越界。
- **v1.0.1 修复留痕**：反向判向条件曾与正向恒等（死代码）——镜像式状态机的反向分支必须用反向输入向量单独推演，这条教训已写进修订历史。

**适合渠道**：机器安全公众号「屏蔽（Muting）为什么总是被审出问题」长文、ISO 13849 落地实践帖、包装/物流输送线售前包、GitHub README 安全件章节。

---

## 21. `FB_DL_SoftLimitGuard` ｜ 制动距离预判：软限位不是一条比较线，是一道随速度收缩的围栏

**一句话 / One-liner**：按当前速度实时计算双向制动距离（含扫描/IO/驱动时延项），预警/拦截两级输出，超程后只允许「向内」恢复——固定阈值的软限位在高速轴上形同虚设，这道围栏会随速度收缩。

### 亮点 / Highlights
- **预判公式公开可复算**：`fStopDist = fSpeed × tLatency + fSpeed² / (2 × fDecel)`；默认时延 23 ms 有三项来源（扫描 10 + IO 5 + 驱动 8 ms），且第一拍就提示「请实测整定」——验收向量 V1 直接给数值：100 mm/s、500 mm/s²、23 ms → **12.3 mm**。
- **两级带域，保守侧设计**：拦截带 ⊇ 预警带（拦截含安全裕量、更早触发）——预警给操作员反应时间，拦截给调用方硬禁止；两带重合于裕量 = 0。
- **向内恢复豁免**：正向拦截置位期间仅允许负向指令——「撞了限位之后连退都退不了」是固定软限位的经典死锁，方向性豁免从语义层面解决。
- **职责边界写死**：本块输出为建议信号，拦截执行在调用方（公约 0.13）——建议信号与执行解耦，真实驱动适配层 / 安全控制器可按同一语义接入。
- **接口消费而非重复实现**：位置/速度经既有 `I_DL_MotionAxis` 接口引用读取，零新增引脚——R4 轴状态机族的一个直接受益者，Level 1 内部复用的示范件。

**适合渠道**：运动控制公众号「软限位为什么不许用固定阈值」长文、PLCopen 集成实践帖、数控/压装机/机器人对接售前包、GitHub README 运动安全章节。

---

## 22. `FB_DL_ElectronicCam` ｜ 电子凸轮：不是一条位置曲线，是一张带相位治理的查找表

**一句话 / One-liner**：主轴相位归一化 → 16 点表分段线性插值 → 缩放与偏移，周期/非周期双模式、飞剪切点在线微调——相位归一化用「截断取整 + 条件加减」，绝不对负数取模。

### 亮点 / Highlights
- **整数比值对与负数取模禁令的双落地**：相位小数部分用截断取整 + 条件加减实现，负向主轴时相位仍精确落在 0.0..1.0——负数取 MOD 三平台行为不一致，这是本库「跨平台歧义禁令」家族的第二处落地（第一处是 R7 EventCounter 条件加减法回绕）。
- **表校验一次完成，运行期零全表扫描**：啮合沿对全表做一次性校验（点数 / 单调性 / 非有限值），运行中只校验当前区间——「校验在耦合沿一次完成 + 相位归一化」是本块对 PLCopen CamIn/CamTableSelect 语义的工程化收口，避免每拍全表扫描拖长任务周期。
- **配方偏移与在线微调分层**：`fMasterOffset`（配方级固定偏移）与 `fPhaseShift`（运行中飞剪切点补偿）在块内相加互不覆盖——切点补偿是印刷/包装行业凸轮应用的高频刚需，且只提示突变不代为滤波（平滑义务显式交还调用方）。
- **每拍至多一次轴方法调用**：从轴定位经 `I_DL_MotionAxis` 下发带重发去抖，定位与减速指令同拍互斥——连续耦合块不把接口配额撑爆的公共模式。
- **诚实的定位声明**：逻辑层同步而非硬实时插补，高速飞剪必须由驱动侧凸轮功能或实时总线承载——能力边界写进头注释，不夸大不误导。

**适合渠道**：印刷包装公众号「飞剪切点为什么总是差半毫米」长文、PLCopen CamIn 集成实践帖、凸轮表调试避坑清单、切割/追剪/印刷套准售前包。

---

## 23. `FB_DL_CipCleaningSeq` ｜ CIP 清洗：合格时间不等于墙钟时间

**一句话 / One-liner**：六相清洗序列（预冲/碱/中冲/酸/终冲/消毒），各相温度/电导/流量三路 TACT 联锁——未达标时段计时暂停，脏水凑不够时长；终冲以回液电导率到达终点收口，完成许可直供生产放行。

### 亮点 / Highlights
- **「暂停不计时」是本块的灵魂**：各相目标时长只对 TACT 全部达标的时段累计，联锁暂停期间计时冻结、暂停超上限判该相失败——把「清洗是否合格」从墙钟语义纠正为「合格时间」语义，脏水流量、温度未达标时段统统不算数，清洁验证审计（`nDeviationCount` + `tPhaseElapsed`）直接可追溯。
- **六相可按工艺裁剪**：`abPhaseEnable` 启用数组在启动拍做快照，运行中改写不生效（跳相请求被拒并提示）——防「清洗中途改配方」的流程漏洞，启用相目标时长为零直接判故障级 0272。
- **电导率终点 + 超时兜底双收口**：终冲以回液电导率到达 `fRinseCondTarget` 为退出条件，`tRinseMax` 防呆兜底防「水质太差永远冲不完」把产线挂死。
- **设备侧五个指令出口齐备**：供液泵/回液泵/加药泵/加热/排空全部为电平指令输出，加药按电导率低于下限脉冲式请求；换相停泵间隔防酸碱混液（信息级 0173 显式暴露）。
- **与 ISA-88 相语义一脉相承**：R7 BatchDosing（投加）→ 本块（清洗）→ R8 MixRecipeControl（搅拌），相结构 = 前置确认 → 执行 → 终点判据 → 完成四段式在三类工艺上复用验证——Level 2 工艺层的「相语义底座」初步成形。

**适合渠道**：食品/制药公众号「CIP 验证为什么不能看计时器」长文、GMP/HACCP 清洁验证帖、ISA-88 相语义系列第三篇、乳品/饮料/生物反应器售前包。

---

## 24. `FB_DL_ModbusPollMaster` ｜ Modbus 主站：调度归调度，传输归传输

**一句话 / One-liner**：站表轮询、超时重试、异常台账全在调度层；RTU 还是 TCP 由派生块覆盖三个抽象桩说了算——换传输层，上层逻辑一行不改。

### 亮点 / Highlights
- **调度与传输彻底分层**：`DoTransaction` / `SendFrame` / `RecvFrame` 三个默认实现为抽象桩（返回 FALSE 并锁故障码 0290），派生块覆盖后落地真实传输——多数字开源自带的 Modbus 库把调度和串口收发焊死在一起，想换 RTU→TCP 只能重写整个状态机；这里换传输只派生一个块。
- **站表由调用方持有（VAR_IN_OUT）**：`ST_DL_PollItem` 的功能码/地址/数量全部透传不解析，成功/异常计数由调度层维护，HMI 直接读结构体——「台账即监控」，哪个从站老掉线一屏可见。
- **重试耗尽记账不停摆**：单站重试上限耗尽只累加异常计数并翻下一站，绝不用一个「死从站」拖停整条轮询链——「宁漏不拖」的快速巡检语义显式可组态（`uMaxRetry = 0`）。
- **现场纪律写进头注释**：响应超时必须大于最慢从站（填小了会「其实成功但判超时」造成重复点名）、站表全跳过按间隔空转不是死机、同一物理链路禁止挂两个实例——五条 Field notes 全部来自真实现场事故模式。
- **CRC 不在本块**：校验属于传输层职责（本库 `FC_DL_Crc16Modbus` 单独成件），调度层不解析帧内容——分层即分责，测试面随之缩小。

**适合渠道**：Modbus 集成避坑长文「为什么你的轮询主站总被一个死从站拖停」、工业网关售前包、RTU/TCP 双形态产品线通用底座帖。

---

## 25. `FB_DL_PulseDirStepper` ｜ 开环步进：没有编码器，就要为「丢步」设计出口

**一句话 / One-liner**：梯形加减速短行程自动退化三角型、限位同向停发锁故障、堵转按「理论耗时 × 1.5 + 裕度」判定——减速段残差不足一个脉冲时按到位处理，绝不静默卡死。

### 亮点 / Highlights
- **短行程自动退化三角型**：加速段即减速段，调用方无须判断行程长度——开源 stepper 库普遍要求调用方自己算梯形/三角切换，这里规划器内部收口。
- **v1.0.1 致命修复的第二出口（D-02）**：原减速段只有「步数归零」一个出口，残差为小数（当量换算后非整脉冲）时频率永远降不到出口条件——现场表现为静默卡死、无故障码。修复后新增「频率归零即收尾」（信息级 0137），残差不足一脉冲按到位处理。**开环语义的必然推论：丢步后的位置是推算值，一切出口都必须有兜底**。
- **堵转判据可整定**：理论耗时由梯形公式实时推算，乘 1.5 裕度系数 + 组态超时——「转不动」不是靠电流检测，是靠「该走完的时间没走完」，经济型方案零额外硬件。
- **限位是方向语义**：同向指令被拒并锁故障、反方向恒受理——入侵后必须反向退出再复位，杜绝「限位报警了还能继续往里顶」的野蛮操作。
- **契约-实现对双件**：上层只依赖 `I_DL_StepperOpenLoop` 接口编程，未来换闭环步进/伺服只换实现块——接口注入骨架与全库设备件一脉相承。

**适合渠道**：公众号长文「步进电机为什么总是『走完了』却没到位」、经济型轴方案（3C/包装/滑台）售前包、开源 stepper 库对比评测帖。

---

## 26. `FB_DL_AndonCallSystem` ｜ 安灯仲裁：呼叫链路是一场带优先级的资源竞争

**一句话 / One-liner**：四级呼叫优先仲裁、高优先级可抢占重锁低优先级、同拍多源高者胜、未应答即解除不计入应答统计——把车间「呼叫-应答-升级」人因流程建模成状态机。

### 亮点 / Highlights
- **仲裁语义三律**：高优先级抢占重锁（单拍提示 01A1）、同拍多源高者胜、呼叫级别内部一致性破坏判故障级（02A0）——多数安灯实现是「谁呼叫亮谁的灯」，多源同拍时行为未定义；这里仲裁结果确定可复现。
- **未应答解除不计入应答统计**：操作工「还没人理就自己把灯按灭了」的呼叫不计入响应 KPI——统计口径的错误比没有统计更危险，这条语义直接保护班组绩效数据的公正性。
- **锁存与仲裁由组件保证**：呼叫线不绕过组件直连声光输出——与 R8 塔灯「安全事件不受消音约束」构成「人因链路安全侧豁免」家族，安灯语义库内两件互相补位。
- **等级映射现场可配**：四级优先级与现场呼叫等级表（缺料/品质/维修/设备）一一对应，等级越界在入口拒绝而非静默降级。
- **OMAC 语义 clean-room**：借「呼叫-应答-升级」的组织骨架，仲裁表与统计口径为本库自有加严——许可证明干净，行业分享无合规顾虑。

**适合渠道**：精益生产公众号「你的安灯系统为什么形同虚设」长文、MES/Andon 集成售前包、班组绩效数据治理帖。

---

## 27. `FB_DL_PickAndPlaceStation` ｜ 九步序拾放工站：把「工站」当成一个有状态的物理对象

**一句话 / One-liner**：注入三轴 + 真空接口，九步序单件搬运；业务态（缺料/占位/吸盘老化）进安灯不锁故障，只有掉件与超时才停线——工站模板的第一原则是「别把常态当故障」。

### 亮点 / Highlights

- **七态最小子集，不抢 PackML 的活**：本块只做待机 / 启动自检 / 执行 / 保持中 / 已保持 / 中止收尾 / 故障七态，执行态内再分九步序（确认原点 → 取料位 → 下降 → 吸取确认 → 抬升 → 横移 → 下降 → 破真空 → 抬升回原点）。15 态、17 态全集由 `FB_DL_PackMlStateMachine` 承担——同一工站里跑两套全状态机必然打架，这是刻意不做全集。
- **单步三段式：下发一次 → 等条件 → 单拍推进**：动作指令绝不每拍重发，轴指令不会被重复触发；保持态不重发任何运动指令，释放后从当前步继续，已完成步不重做。
- **到位判据不依赖厂商属性**：既有 `I_DL_MotionAxis` 没有「到位布尔位」，判据写死为「轴处于待机态 且 位置落在容差窗口内」——等价于驱动到位位，却能在仿真轴与三种平台的真机上同样成立。
- **故障分级是工艺判断，不是代码判断**：缺料、放料位占用 → 信息级码 + 安灯，产线继续等待上料（停线代价大于等待）；真空未建立 → NG 计数 + 回步一（吸盘老化是常态）；搬运中掉件 → 立即中止收尾（抬 Z + 破真空），把工件当已损坏，避免二次撞机。
- **步超时统一门控 + 步号映射码位**：一个定时器监视全步序，进故障前把步号映射为对应故障码——现场看到码就知道停在第几步，不用翻代码。
- **v1.0.1 的致命修复（D-01）**：主 CASE 曾漏 `eExecute` 标签，执行态落 `ELSE` 兜底被判「非法状态」并锁故障，工站从 eReady 推进到 eExecute 的当拍即自杀、九步序一行不执行。修法不是把动作搬进 CASE，而是**保留空标签分支 + 原因注释**，防止维护者再删。这条修复直接催生规则 **R31 枚举→CASE 双向映射完备性**。

**适合渠道**：公众号长文「工站模板为什么不能写成一个大 CASE」、锂电/3C 上下料方案售前包、PackML 与工站模板分层关系科普帖。

---

## 28. `FB_DL_WindingTraverse` ｜ 卷径递推 + 横动排线：一个物理对象，一个块

**一句话 / One-liner**：层厚积分递推卷径、节距积分驱动排线、端点换向带停留；卷径有内部递推与外部注入双源，切换不跳变——两个职责同属一根排线轴，拆成两个块只会让状态共享变成灾难。

### 亮点 / Highlights

- **按物理对象划界，而不是按函数划界**：卷径与排线共享同一根轴、同一个卷径状态，故合成一个块、内部分两个子段；反过来，`FC_DL_CoilDiameterCalc`（纯函数、瞬时几何反算、无状态）单独成件，两者互为校验但不互相调用（泳道零跨层调用）。
- **圈增量只积分一次**：排线位移只从该拍圈增量派生，禁止两处各积一次——否则排线节距被静默放大一倍，现场表现为「排线越走越宽」。
- **双数据源仲裁用布尔而非模式枚举**：`bUseInjectedDia` 选择「注入卷径」还是「内部递推」，且**内部递推在任何情况下继续累积**，切回内部时不会出现卷径跳变；单一布尔数据源选择，语义单一，不构成多职责巨无霸块。
- **拍数计数代替时间累加**：排线到位超时用固定任务周期下的拍数计数，避免 `TIME` 类型转换，跨平台无歧义——与全库「定时器无条件刷新」纪律互补。
- **停止优先于一切运行态**：`bStop` 在状态机之前判，任何运行态都能停；卷径与位移全部有 MAX 守卫，分母绝不为 0。
- **v1.0.1 的致命修复（D-02）**：待机分支曾每拍无条件 `nDirInt := 0`，转卷绕后从不赋回 ±1，端点只做 `-nDirInt`（0 取反仍是 0）→ 排线位移恒 0、轴不动而状态在 eWinding/eDwell 间空转抖动；现场后果是叠线报废。修法是把方向赋值移进「启动成功」分支。这条修复催生规则 **R32 内部状态量写入点全拍排序审计**：清零是状态迁移动作，不是待机态装饰。

**适合渠道**：薄膜/锂电/线缆收卷专题长文「排线为什么会叠线：三个每拍赋值的陷阱」、卷绕工艺包售前、与 `FC_DL_CoilDiameterCalc` 的组合用法帖。

---

## 29. `FC_DL_WeekOfYearCalc` ｜ ISO 周序号：不查表、不浮点，也不信规格书里的速算式

**一句话 / One-liner**：输入年月日，输出 ISO 周年 + 周序号（1~53）+ 周内日；周四归属法定归属、Zeller 同余定星期，全程整数，跨年归属（12-31 属次年第 1 周、01-01 属上年第 53 周）一次算对。

### 亮点 / Highlights

- **周四归属法**：一个 ISO 周归属于其周四所在的年份——先求当日周内日，再推算本周周四的年内序日，跨年归属自然落位，不需要为 12 月末/1 月初写特例分支。
- **Zeller 重排式规避闰年偏置**：把 1 月、2 月折算为上一年的 13 月、14 月是 Zeller 原式的关键约定，不可省；省掉它，闰年 1~2 月整体偏一天，而且只在特定年份暴露。
- **长年判据显式化**：ISO 周年 1 月 1 日为周四，或该年为闰年且 1 月 1 日为周三 → 该年含第 53 周。
- **零依赖、零浮点、零查表**：除法除数全为常量（4/100/400/7/5），被除数恒非负，不触发除零、不依赖负数截断方向——三平台同源。
- **一次「规格书错了」的公开勘误**：规格 1.2 节给的速算式 `nDow0 = (nDoy + 5 + y + y/4 - y/100 + y/400) MOD 7` 对 2026-01-01 算得 3（实际是周四），且闰年 1~2 月未折算 13/14 月会整体偏一天。本件改用等价无偏置的 Zeller 重排式，V1~V5 向量全部命中，勘误按 O-5 留档并要求**修订规格模板**——这是「文档每句话都是可证伪命题」的最好例证：公式看起来对，向量一算就露。
- **边界语义独立不合并**：与 `FC_DL_DayOfWeekCalc` 职责分离——一个给星期几，一个给周序号与 ISO 周年；合并会让「周排产」和「星期几判断」互相绑死。

**适合渠道**：公众号长文「周排产第一坑：ISO 周数算错，整年的计划都错位」、MES 周报/周计划集成帖、代码评审「规格书里的公式也要验算」范例。

---

## 30. `FB_DL_PressFitStation` ｜ 包络窗口 + 四特征点：把压装曲线变成一张可审的合格证

**一句话 / One-liner**：八态只负责推进，包络与特征点只在判定态出一次结论；NG 不是一个布尔位，而是五个可分辨的原因位。

### 工艺痛点 / Process Pain

- **一条判据管不住一条曲线**：伺服压装长期只判「终点压力是否落在窗口内」。压偏、压歪、压到异物、材料软化四种失效在终点压力上高度相似，全部归成同一句「压力不对」，返修只能拆机复测。
- **判据散落在各步里**：接近段判下限、压入段判上限、保压段判压降，阈值一改要翻整个状态机；更麻烦的是「走到哪一步」与「这一步合不合格」写进同一个变量，事后无法复盘。
- **组态表被代码改写**：上下限对调、点数超限这类组态错误，很多实现是「顺手把表改了继续算」，下一件产品拿到的是被污染的包络。

### 架构亮点 / Architecture

- **命令-监视-判定三段分离**（借鉴 LBP 工艺块三段式，只借分层不借代码）：八态只描述「走到哪一步」（待机 / 接近 / 压入 / 保压 / 回退 / 判定 / 完成 / 故障），判定集中在 `eEvaluate` 一次锁存，合格与不合格同循环闭环，绝不在各步散写 NG 位。
- **包络表只读 + 镜像修复**：注入表一律不改写；上下限对调在块内镜像里纠正并置信息级 `01C1`；点数超限钳位 32 并置 `01C0`。组态数据永不被代码污染，两次调用看到的是同一张表。
- **二分定位 + 防死锁**：带计数守卫的二分查找（节点上限 32，最多五轮），区间内比例钳到 `0..1`；跨度小于保护阈值时退化取左节点，绝不进入除法。
- **四特征点各自锁存**：接触点（阈值两侧线性插值）、屈服点（斜率回落至峰值斜率的指定比例）、峰值点、终点。未提取到就保持 `0.0`，由 NG 原因位解释「为什么没有」——缺失本身是信息，不是错误。
- **屈服判据不依赖过峰**：现场屈服多为斜率软化而非压力下降（铝壳与塑料件尤甚），强求「压力过峰」会让单调上升的曲线永远判不出屈服，故判据取斜率比例，过峰另有独立标志。

### 现场价值 / Field Value

- 「这件为什么 NG」从一句争论变成一个位掩码：**bit0 上包络越界 ｜ bit1 下包络越界 ｜ bit2 终点未达 ｜ bit3 接触未建立 ｜ bit4 保压压降超限**，五类可同时置位，返修工位按位分诊。
- `fEnvDevMax` 给出全程最大偏差量：趋势图上能区分「模具磨损」（偏差缓慢单调上升）与「来料变化」（批次间跳变）。
- 回退快照在进回退首拍取终点特征，位置最多滞后一个扫描，回退动作不会把终点数据冲掉。
- 阶段超时三段共用 `02C2`，配 `eState` 一读即知卡在接近、压入还是保压。

### 代码片段 / Snippet

```iecst
// 包络窗口校验：二分定位 + 线性插值（仅压入与保压段；接近段压力天然低于下限故不判）
nLo := 1;  nHi := _nEnvPts;  nGuard := 0;
WHILE ((nHi - nLo) > 1) AND (nGuard < DL_MAX_LOOP) DO
    nGuard := nGuard + 1;                       // 防死锁计数
    nMid   := (nLo + nHi) / 2;
    IF fActPos >= afPosUse[nMid] THEN
        nLo := nMid;                            // 落在右半区
    ELSE
        nHi := nMid;                            // 落在左半区
    END_IF
END_WHILE
_fSpan := afPosUse[nHi] - afPosUse[nLo];
IF ABS(_fSpan) > DL_SLOPE_MIN_DELTA THEN
    _fRatio := LIMIT(0.0, (fActPos - afPosUse[nLo]) / _fSpan, 1.0);   // 区间外钳位
    _fUp := afUpperUse[nLo] + _fRatio * (afUpperUse[nHi] - afUpperUse[nLo]);
    _fLo := afLowerUse[nLo] + _fRatio * (afLowerUse[nHi] - afLowerUse[nLo]);
ELSE
    _fUp := afUpperUse[nLo];  _fLo := afLowerUse[nLo];   // 退化区间取左节点
END_IF
IF fActForce > (_fUp + DL_FLOAT_EPS) THEN uNgReason := uNgReason OR DL_NG_ENV_HIGH; END_IF
IF fActForce < (_fLo - DL_FLOAT_EPS) THEN uNgReason := uNgReason OR DL_NG_ENV_LOW;  END_IF
```

**适合渠道**：锂电 / 3C 精密压装工艺专题、工站模板分层关系科普帖、「压装曲线怎么判合格」长文、质量追溯（曲线归档）售前包。

---

## 31. `FB_DL_PortDiagAggregator` ｜ 端口诊断聚合：一屏回答「哪几个坏了、谁先坏、什么码」

**一句话 / One-liner**：8 个通讯端口的链路、诊断码与错误计数聚合成「掩码 + 首出端口 + 首出码 + 风暴标志」，多端口同时报警不再只看到最后一条。

### 工艺痛点 / Process Pain

- **多端口同时报警只留最后一条**：HMI 上端口故障是逐条刷新的，现场看到的永远是「最后发生的那条」，而排故需要的是「最早发生的那条」——因果顺序被显示顺序吞掉。
- **累加计数没有趋势语义**：CRC 错误计数是累加器，16#0000_0100 到底算正常还是「错误风暴」，光看绝对值无法判断（不同端口、不同运行时长不可比）。
- **端口级与模块级混账**：把「端口链路断」与「背板模块故障」写进同一个码段，HMI 按码分组时必然归错类。

### 架构亮点 / Architecture

- **四元组 + 三出口**：端口号 / 链路状态 / 端口诊断码 / 错误计数四元组进，故障掩码 + 首出端口号 + 首出诊断码出；掩码位 n 对应端口 n+1，末段再与全端口掩码相与，屏蔽高位脏数据。
- **首出语义三律**：只在无锁存时仲裁；同拍多端口故障取**端口号最小**者（低号端口更靠近主站，符合现场因果顺序）；锁存后不再更新，只有复位上升沿可清——且**复位处理放在仲裁之后**，保证复位当拍首出即为空、下一拍重新仲裁。
- **窗口差分把累加器变成速率**：每拍算「当前计数 − 上窗基准」，窗口结束拍与阈值比较出「错误风暴」；**硬拍序**是先转出快照、后装载基准，否则窗口结束拍装载当拍增量恒为 0。
- **回绕按归零处理**：当前值小于基准即判计数器回绕或复位，增量取当前值，绝不出现「几百亿」的假风暴。
- **去抖对全部 8 端口无条件刷新**：`FOR i := 1 TO DL_PORT_MAX` 全程跑，不因实际端口数少而漏刷定时器（漏刷会让旧端口残留 `Q` 位）。
- **风暴是趋势事件，不锁存**：`eBurst` 只停一拍并置单拍标志，不进 `bError`；端口数超上限钳 8 只出信息级 `0140`。

### 现场价值 / Field Value

- 三问一屏可答：**哪几个端口坏**（掩码）、**谁先坏**（首出端口）、**什么码**（首出诊断码）；复位后首出自动清空，不需要额外「清报警」逻辑。
- 风暴标志可直接驱动「降低总线负载 / 提升重试间隔」的自适应策略，而不用等总线彻底崩掉。
- 端口级码段（`014x` / `030x`）与模块级件（背板诊断锁存）分段，HMI 按类分组不会串台。

### 代码片段 / Snippet

```iecst
// 段 5｜增量差分（回绕按归零处理，UDINT 语义不产生负数）——只读基准，装载只在窗口结束拍
FOR i := 1 TO DL_PORT_MAX DO
    IF i > nPortClamped THEN
        auRawDelta[i] := 0;  auOutDelta[i] := 0;              // 超出实际端口数一律记 0
    ELSIF auPortCrcErrCnt[i] < stState.auPrevCnt[i] THEN
        auRawDelta[i] := auPortCrcErrCnt[i];                   // 回绕或复位：按归零处理
        auOutDelta[i] := auRawDelta[i];
    ELSE
        auRawDelta[i] := auPortCrcErrCnt[i] - stState.auPrevCnt[i];
        auOutDelta[i] := auRawDelta[i];                        // 先转出快照
    END_IF
END_FOR

// 段 6｜端口故障判定与逐端口去抖（掩码装配）——定时器组对全部端口无条件刷新
uMaskBuild := 16#0000;
FOR i := 1 TO DL_PORT_MAX DO
    abRawFault[i] := bEnable AND (i <= nPortClamped)
                     AND ((NOT abPortLinkOk[i]) OR (auPortErrCode[i] <> UDINT#0));
    afbDebounce[i](IN := abRawFault[i], PT := tDebUse);
    IF afbDebounce[i].Q THEN
        uMaskBuild := uMaskBuild OR SHL(DL_MASK_ONE, i - 1);    // 去抖成立才进位
    END_IF
END_FOR
uPortFaultMask := uMaskBuild AND DL_PORT_MASK_ALL;              // 屏蔽高位脏数据
```

**适合渠道**：PROFINET / EtherCAT 总线诊断专题长文、「首出故障为什么比报警数量重要」讨论帖、机架诊断看板售前包。

---

## 32. `FC_DL_PercentileLReal` ｜ 分位数：节拍瓶颈看 P95，不看平均值

**一句话 / One-liner**：任意分位（P0~P100）一次算出，拷贝排序不改调用方数组，非有限样本前置剔除，排序未完成按空集返回而非给半成品。

### 工艺痛点 / Process Pain

- **平均值治不了瓶颈**：节拍分布是右偏的，均值漂亮但 P95 才是真实的「多久卡一次」；称重偏差、温度分布同理，现场真正关心的是尾部。
- **「最大值」又太脆**：单次异常样本（人为干预、传感器毛刺）就能把最大值顶死，用它做判据等于把偶发事件当稳态。
- **统计函数改坏现场数据**：很多实现直接在调用方数组上就地排序，调用完样本顺序变了；若同一份样本还要算均值/极差，结果就不可复算。

### 架构亮点 / Architecture

- **口径写死防漂移**：采用业界主流的「排序 + 线性插值」（R-7 定义），`pos = P × (n − 1)`，`nLo` 为整数部分、`fFrac` 为小数部分；口径写在头注释里，换人维护不会悄悄改成另一种分位定义。
- **拷贝排序，数组不变**：全部排序在块内私有数组上完成，调用方数据帧后不变——与库内「就地快排」件语义刻意相反：统计取值不应破坏现场数据，复算其他统计量时更需要原数组完好。
- **先剔除再排序**：非有限样本（NaN / 无穷）在拷贝阶段就剔除。NaN 参与比较会让整个排序失去传递性，**排序后再过滤等于让一次 NaN 污染全局次序**。
- **插入排序是刻意的**：样本上限 64，插入排序常数项小于快排且无递归、无栈深风险；两层循环共用同一防死锁计数，触顶即判「排序未完成」并**按空集返回**，绝不把「部分有序」冒充成功。
- **末位不外插**：`nLo + 1 >= nN` 时直接取最大样本，P100 恒等于最大值；插值下标由该分支反证不越界。
- **`nGuard` 兼作性能诊断**：累计循环次数出口暴露给调用方，扫描周期紧张时可据此判断统计开销。

### 现场价值 / Field Value

- 节拍 P95 / 称重偏差 P99 / 温度分布 P50 直接可得，配合既有窗口统计件（均值、方差、极值）构成完整的分布画像。
- 空集语义明确：返回 `0.0` + `bEmpty := TRUE` + 信息级码，**不伪装成「分位值就是 0」**——0 在温度与重量场景都是合法工况值，伪值会掩盖「样本根本没采到」。
- `fActualP` 输出钳位后的实际分位点：HMI 上能显示「你填的是 1.2，实际按 1.0 算的」，组态越界不再无声。
- 纯函数、无实例、无跨拍状态：同一份样本可以在不同任务里反复取值，结果只取决于输入。

### 代码片段 / Snippet

```iecst
// 段 5｜插入排序（两层循环共用防死锁计数；触顶即判未完成，绝不返回部分有序结果）
FOR nI := 2 TO nN DO
    IF nGuard > DL_GUARD_MAX THEN bSortOk := FALSE; EXIT; END_IF
    fKey := afSorted[nI];  nJ := nI - 1;  bShift := TRUE;
    WHILE bShift AND (nJ >= 1) DO
        nGuard := nGuard + 1;
        IF nGuard > DL_GUARD_MAX THEN
            bShift := FALSE;  bSortOk := FALSE;
        ELSIF afSorted[nJ] > fKey THEN
            afSorted[nJ + 1] := afSorted[nJ];  nJ := nJ - 1;
        ELSE
            bShift := FALSE;
        END_IF
    END_WHILE
    afSorted[nJ + 1] := fKey;
END_FOR
IF NOT bSortOk THEN                        // 排序未完成 → 按空集处理
    bEmpty := TRUE;  uErrorId := DL_ERR_EMPTY;  RETURN;
END_IF

// 段 6~7｜位置计算与线性插值（pos = P × (n − 1)；pos 非负故截断即向下取整）
fPos  := REAL_TO_LREAL(fActualP) * (INT_TO_LREAL(nN) - DL_LL_ONE);
nLo   := LREAL_TO_INT(fPos);
fFrac := fPos - INT_TO_LREAL(nLo);
IF (nLo + 1) >= nN THEN
    fResult := afSorted[nN];               // 末位不外插，P100 恒为最大值
ELSE
    fLo := afSorted[nLo + 1];              // 数组 1 起，第 k 个样本在下标 k+1
    fHi := afSorted[nLo + 2];
    fResult := fLo + fFrac * (fHi - fLo);  // 线性插值
END_IF
```

**适合渠道**：公众号长文「你的节拍统计为什么看不出瓶颈：平均值、最大值与 P95」、SPC / 质量分析集成帖、MES 班次报表数据口径讨论。

---

## 33. `FC_DL_SolarPositionCalc` ｜ 太阳位置：借的是参数域，公式回到公共领域

**一句话 / One-liner**：本地时间 + 经纬度 + 时区偏移 → 赤纬、均时差、真太阳时、时角、高度角、方位角六出口，天顶不可辨时明确给「正南」而不是猜。

### 解决什么现场问题 / Field Problem

- **光伏跟踪支架的逆跟踪（Backtracking）没有可信的角度源**：多数项目用「固定表 + 线性插值」近似太阳轨迹，冬夏偏差可达数度，排间距在低太阳角时互相遮挡，发电量损失被算成「天气不好」。
- **建筑遮阳帘与日光温室的补光窗口是按钟点开关的**：真太阳时与本地标准时最大可差 ±16 分钟（均时差）再叠加经度偏移，新疆与黑龙江同用北京时间，日落时刻差近两小时，按钟点控制必然有一端错。
- **日照辐射计的姿态修正需要一个独立的太阳位置源**：不能反查云台编码器（那会把跟踪误差算进辐射值）。

### 设计亮点 / Design Highlights

- **一个纯函数，六个出口，零状态**：赤纬、均时差、真太阳时、时角、高度角、方位角同拍全出，调用方按需取用；同一组输入在任何任务、任何周期里复算结果完全一致。
- **公式取 NOAA 公开傅里叶级数**（赤纬 7 项、均时差 5 项，公共领域），在 1970~2100 年、纬度绝对值 ≤ 90° 域内高度角误差优于 0.5°；精度承诺与适用域写死在头注释，不做「看起来更准」的过度承诺。
- **归一化全程用条件加减，绝不用 `MOD`**：时角与方位角的负值取余在三平台口径不一致（这是本库 R11 起反复出现的老坑），本件用两条带守卫的 `WHILE` 折叠，负角自然落回 `[−180, 180)` 与 `[0, 360)`。
- **年内日序用逐月累加而不用常量数组**：规避各平台常量数组初始化的差异，代价是 12 次加法，换来「拷到哪个平台都算同一个数」。
- **参数域借自 LGF，实现一行不借**：只承认 LGF 把「日历天数 / 周数 / 天文钟 / 多段定时」并列的分类，以及天文钟「本地时间 + 经纬度」的参数域。

### 边界处理 / Edge Cases

- **三处域闸门早退**：年月时分越界（0136）、经纬度或时区非有限值（0136）、日超出当月实际天数（0137，含 4/100/400 三级闰年判定）——一律返回 `0.0` + `bValid := FALSE`，**绝不输出「看起来合理」的错值**。
- **经纬度闸门写成「正向区间取反」形式**：`IF NOT (fLat >= −90.0 AND fLat <= 90.0)`，NaN 参与任何比较都为假，于是自然被拒，不必单独写 NaN 判据。
- **`ASIN` 入参先 `LIMIT` 到 ±`DL_SIN_LIM`**：高度角正弦因浮点误差可能算出 1.0000001，直接喂 `ASIN` 会得 NaN 并污染下游全部出口。
- **`ATAN2` 双零守护**：分子分母同时趋零时方位角无定义，置 0 后由后续归一与天顶判据接管，不让平台返回未定义值。
- **天顶不可辨显式声明**：高度角 > 89.5° 或高度角余弦 < 0.00873 时，方位角物理上不可辨，统一置 180.0（正南）**并把这个约定写进头注释**，要求上层如另有偏好必须在调用侧追加判别，不得依赖本件给「就近方位」。
- **`bSunUp` 只表示几何高度角为正**，不做大气折射修正（地平线附近折射可达 0.5°）；日出日落判据要的是「几何出地平」还是「可见日面出地平」，由调用方自己决定。

### 与开源同类对比 / Versus Open Source

| 维度 | 常见开源实现 | 本件 |
|---|---|---|
| 角度约定 | 各家不一（有的以南为 0、有的以东为 0），文档常缺 | **正北 0、顺时针递增**，写进头注释与验收向量 |
| 负角归一 | `MOD` 或 `fmod` 直接取余 | **条件加减 + 守卫**，负数取余跨平台歧义零容忍 |
| 天顶附近 | 输出跳变或除零 | **显式置正南 + 声明不可辨**，不让下游猜 |
| 日出判据 | 混用「几何高度」与「可见日面」 | 明确只给几何高度，折射修正交调用方 |
| 依赖 | 常带查表常量或第三方数学库 | **仅 `Standard.library` 的 SIN/COS/TAN/ASIN/ATAN2** |

### 调用片段 / Snippet

```iecst
// 段 7｜真太阳时与时角：经度按每度四分钟折算，时区偏移直接扣减
fTstMin := INT_TO_REAL(nHour * 60 + nMinute) + fEotMin + 4.0 * fLongitude - INT_TO_REAL(nUtcOffsetMin);
fHaDeg  := 15.0 * (fTstMin / 60.0 - 12.0);

// 时角归一：条件加减，禁用取模（负数取余在各平台口径不一致）
nGuard := 0;
WHILE (fHaDeg > DL_HA_LIM) AND (nGuard < DL_GUARD_MAX) DO
    fHaDeg := fHaDeg - DL_AZ_FULL;  nGuard := nGuard + 1;
END_WHILE
WHILE (fHaDeg < -DL_HA_LIM) AND (nGuard < DL_GUARD_MAX) DO
    fHaDeg := fHaDeg + DL_AZ_FULL;  nGuard := nGuard + 1;
END_WHILE
fHourAngle := fHaDeg;

// 段 8｜高度角：先钳正弦到定义域，再取反正弦，杜绝 NaN 传播
fSinElev := SIN(fLatRad) * SIN(fDeclRad)
          + COS(fLatRad) * COS(fDeclRad) * COS(fHaDeg * DL_DEG2RAD);
fSinElev := LIMIT(-DL_SIN_LIM, fSinElev, DL_SIN_LIM);
fElevation := ASIN(fSinElev) * DL_RAD2DEG;

// 段 9｜方位角：反正切求「相对正南」偏角，再加 180 度换算到正北起算
fY := SIN(fHaDeg * DL_DEG2RAD);
fX := COS(fHaDeg * DL_DEG2RAD) * SIN(fLatRad) - TAN(fDeclRad) * COS(fLatRad);
IF (ABS(fX) < DL_EPS) AND (ABS(fY) < DL_EPS) THEN
    fAzRad := 0.0;                          // 双零守护：不让平台返回未定义值
ELSE
    fAzRad := ATAN2(fY, fX);
END_IF
fAzimuth := fAzRad * DL_RAD2DEG + 180.0;
IF (fElevation > DL_ZENITH_DEG) OR (fCosElev < DL_COS_MIN) THEN
    fAzimuth := 180.0;                      // 天顶不可辨：统一置正南并保持该约定
END_IF
```

**适合渠道**：光伏跟踪支架算法长文、「北京时间不等于真太阳时」科普帖、建筑遮阳与温室补光的工程选型文。

---

## 34. `FB_DL_LineInterp2Axis` ｜ 两轴直线插补：暂停恢复不是「接着走」，是「重算该走哪一段」

**一句话 / One-liner**：单位向量分解 + 单轴速度折算 + 梯形/三角自适应，八态状态机；暂停恢复按剩余量分流，**位置连续的同时速度也连续**。

### 解决什么现场问题 / Field Problem

- **经济型两轴平台（点胶、锁螺丝、切割、上下料）不愿为插补付运动控制卡的钱**：PLC 自己算位置给定是最省成本的方案，但「自己算」的实现普遍只保证位置连续，不保证速度连续。
- **暂停/恢复是这类机台最高频的操作**：换料、清废、处理报警都要暂停再恢复。恢复瞬间速度从 0 跳到峰值，伺服按位置给定跟随会报跟随误差、丢步甚至过流——现场表现是「一按恢复就报警」。
- **短行程抖动**：行程只有几十毫米时，梯形曲线根本跑不出匀速段，还按梯形算会让峰值速度与位移互相矛盾。

### 设计亮点 / Design Highlights

- **只输出位置给定，不碰使能/回零/报警复位，也不驱动物理轴**：两轴的闭环由各自单轴块承担，本件给出给定值，上层接到 `MC_MoveRelative` / `MC_MoveAbsolute`。职责边界写进「分层声明」，避免变成第二套轴管理。
- **时间增量由引脚注入，不读系统时钟**：插补结果可复现、跨平台一致；同时**明确要求放固定周期任务**（变周期任务会造成速度与位置偏差），这条纪律写在头注释「周期纪律」段。
- **单轴限速参与折算**：合成速度按 `fMaxSpeedX / |Ux|`、`fMaxSpeedY / |Uy|` 取最小，V2 向量验证「X 分量恰好等于 50、不超限」；限速生效时置信息码 010B，HMI 能看到「为什么走不到设定速度」。
- **临界判据显式定支**：两侧加速距离之和**恰等于**路径长时判梯形（此时峰值与期望合成速度相等，两种判法结果一致、不跳变），只有**严格大于**才降为三角——临界点在注释里写死，防维护者改写成 `>=` 造成峰值跳变。
- **端点钳位 + 收尾速度下限**：减速段出口强制把已走距离钳到路径长、进度置 100，避免离散步长越过终点导致给定超程；收尾保留峰值的一定比例，防「速度指数衰减、永远差最后一点」的爬行。

### 边界处理 / Edge Cases

- **零长度路径**：当拍完成、给定等于起点、进度 100、信息码 0109——不进入任何运动段，避免除零。
- **参数非法**：速度/加速度/单轴限速/最大路径长非法（含 NaN/Inf 与 `fAccel = 0`）→ 前置拦截、故障锁 0204、`bBusy` 为假；路径超上限 0205；非法状态兜底 0207（终端安全态）。
- **暂停（B-D04 修复点，本轮最值钱的一条）**：加速段出口原只判 `fS >= fAccDist`，恢复时位移早已超过加速距离，加速段当拍即判完成 → 速度由 0 直接赋成峰值。修法两条并用：出口改 **双条件** `(fS >= fAccDist) AND (fV >= fPeak)`；恢复时**按剩余量分流**——剩余 ≤ 加速距离直接进减速段（不再从零速加速冲过终点），否则回加速段从当前位移重新爬坡。
- **零长度路径的进度矛盾（B-D07）**：段 9 的 `fLen <= DL_LEN_MIN` 分支原来无条件写 0，覆盖了 `eDone` 的进度赋值，画面在「已完成」与「0%」间打架；补「完成相满值」判定。
- **偏离留档两条**：① 暂停不做时间补偿（恢复后从当前速度重新加速，但时间增量仍按标称周期推进，故暂停不造成位置瞬跳）；② 减速出口额外把进度强制置 100，防浮点除法在末拍给 99.9999 让画面闪烁。

### 与开源同类对比 / Versus Open Source

| 维度 | 常见开源实现 | 本件 |
|---|---|---|
| 速度连续性 | 只保证位置连续，恢复后速度阶跃 | **位移与速度双条件转出 + 恢复分流**，速度连续 |
| 时间基准 | 内部取任务周期或墙钟 | **周期由引脚注入**，结果可复现 |
| 临界点 | 用 `>=` 或 `>` 随手写，峰值在临界处跳变 | **显式定支并注释理由**，V4 向量锁死 |
| 端点 | 直接钳位，进度 99.99% | 钳位 + 进度强制 100 + 收尾速度下限 |
| 分层 | 顺带管使能与报警 | **只管位置给定**，轴状态归运动层 |

### 调用片段 / Snippet

```iecst
// 准备相：单位向量 + 单轴限速折算 + 梯形/三角自适应
fUx := fDx / fLen;  fUy := fDy / fLen;      // 除数已过判零闸门
fVLimit := fPathSpeed;                       // 先与期望合成速度取最小
IF ABS(fUx) > DL_LEN_MIN THEN
    fTmpX := fMaxSpeedX / ABS(fUx);
    IF fTmpX < fVLimit THEN fVLimit := fTmpX; bSpeedCapped := TRUE; END_IF
END_IF
fVEff    := fVLimit;
fAccDist := (fVEff * fVEff) / (DL_TWO * fAccUse);
IF (DL_TWO * fAccDist) > fLen THEN           // 严格大于才降三角
    bTriangular := TRUE;  fPeak := SQRT(fAccUse * fLen);  fAccDist := fLen * 0.5;
ELSE
    bTriangular := FALSE; fPeak := fVEff;    // 临界相等仍判梯形，不跳变
END_IF

// 加速段：出口双条件 —— 只看位移会让暂停恢复当拍跳进匀速段、速度从 0 到峰值
fV := MIN(fPeak, fV + (fAccUse * fDt));
fS := fS + (fV * fDt);
IF (fS >= fAccDist) AND (fV >= fPeak) THEN
    IF bTriangular THEN ePhase := E_DL_LineInterpPhase.eDecel;
    ELSE                ePhase := E_DL_LineInterpPhase.eCruise; END_IF
END_IF

// 暂停相：剩余量分流 —— 剩余已落在减速窗内就直接减速，不再加速冲过终点
E_DL_LineInterpPhase.eHeld:
    fV := 0.0;
    IF NOT bHold THEN
        IF (fLen - fS) <= fAccDist THEN
            ePhase := E_DL_LineInterpPhase.eDecel;
        ELSE
            ePhase := E_DL_LineInterpPhase.eAccel;
        END_IF
    END_IF
```

**适合渠道**：经济型两轴平台方案文、PLCopen 之外的「自己算插补」技术帖、「为什么一按恢复伺服就报警」故障复盘。

---

## 35. `FB_DL_BatchPhaseBase` ｜ 批次相底座：暂停只在步骤边界生效，超时按步重计时

**一句话 / One-liner**：ISA-88 公开相模型的 11 态底座，动作全部外置；五级命令优先且不排队，暂停在步骤边界生效，单步超时按步重计时。

### 解决什么现场问题 / Field Problem

- **「暂停」在工艺上不是「停一下」，而是「停在一个安全点」**：反应釜滴加、配料称重、清洗循环，如果在动作中途切断，物料半投、管路半冲、批次数据作废——现场事故报告里最常见的描述是「操作员按了暂停，阀门停在半开」。
- **每个项目的批次状态机都要重写一遍**：写的人不同、态名不同、命令优先级不同，MES 对接时每家都要重新对表；而 ISA-88 早就定义了相状态集合与两条关键语义。
- **单步超时是批次最容易写错的地方**：把「整相超时」当成「单步超时」写，合规批次也会被误判中止（本轮真实缺陷 B-D01）。

### 设计亮点 / Design Highlights

- **底座而非模板**：不实现任何工艺动作（投料、升温、搅拌、清洗都在调用方），不定义配方与流程结构，不驱动设备。它只裁决状态与命令——**调用方按「步骤执行请求」外置实现，完成或失败再回送反馈**。
- **命令优先级严格且不排队**：中止 > 停止 > 暂停 > 恢复 > 启动；同拍多命令高优先者胜，**低优先直接丢弃且不排队**。排队会让操作员的「停止」在几拍之后突然生效，这比不响应更危险。丢弃时置信息码 0105，HMI 可查「你按的键被谁盖掉了」。
- **暂停只在步骤边界生效**：暂停请求先登记（`eHolding`），等当前步骤完成反馈被消费、或步骤请求尚未发出时才真正进 `eHeld`。**绝不在动作执行中途切断**——这是相语义的核心。
- **恢复不重头**：恢复时步骤号保持不变，重新发当前步骤的执行请求（信息码 0106），MES 侧看到的 `nStepNo` 连续。
- **相净运行时间**：只在执行相累加，暂停相与其余相不计入；这个值就是 MES 算相耗时与产能要的那个「合格时间」，不是墙钟时间。
- **掉使能冻结而不清零**：状态与全部输出保持，批次报表需要看到最后相状态。

### 边界处理 / Edge Cases

- **单步超时跨步累加（B-D01，本轮最典型的「文本全绿、语义全错」）**：`fbStepWatch` 的 `IN` 在执行/收尾/停止三相之间连续为真，步骤推进（`nStep+1`）不断输入，`ET` 跨步累加——「单步超时」退化成「相内累计超时」，3 步各 30 s、超时 60 s 的合规批次在第 3 步被判 0203 中止。修法：段边界置 `bStepWatchBreak`，`IN` 串入 `NOT bStepWatchBreak`，**实例调用之后自清**。验收必须含「N 段 × 每段 < 超时 < N 段总耗时」这一路向量——只有它能复现。
- **完成反馈常高卡死**：只靠电平消费时，反馈常高会让新步骤永远等不到下降沿。加「完成反馈上升沿实例 + 已消费标志」双保险：沿负责触发，标志负责防一步多次完成。
- **恢复时把「已消费标志」置真还是置假**：规格写「置真」，照写会把恢复后本步的完成反馈永久屏蔽——按语义改为**置假**（恢复后重新等待本步反馈），并把这条规格偏离写进头注释。
- **停止请求后收尾无反馈**：单步超时会把相带进中止（宁停不悬），不让相永久悬挂。
- **已终止态（完成/已停/已中止）只接受复位**：不接受启动与中止；`bStart` 注释原写「空闲与已终止态受理」，与实现不符（B-D08），按实现更正注释。
- **非法状态兜底 0206**：直接进已中止、不回空闲——一个不认识的态，最安全的去处是「已中止」，不是「空闲」。

### 与开源同类对比 / Versus Open Source

| 维度 | 常见开源实现 | 本件 |
|---|---|---|
| 态集合 | 各家自定义 5~8 态，MES 侧逐项对表 | **ISA-88 公开 11 态**，编号 0 起跳步长 10、已中止取 99 排末位 |
| 命令仲裁 | 布尔量各判各的，同拍冲突结果不定 | **五级优先 + 不排队 + 丢弃码 0105** |
| 暂停语义 | 立即切断动作 | **只在步骤边界生效**，动作中途绝不断 |
| 单步超时 | 常写成相内累计 | **步骤边界断输入一拍，按步重计时**（R40） |
| 动作耦合 | 块内直接开阀/下发设定值 | **动作外置**，底座只管状态与命令 |
| 合规声明 | 常宣称「符合 ISA-88」 | 只写「采用公开相状态模型」，**不声明认证** |

### 调用片段 / Snippet

```iecst
// 单步超时监控：段边界断输入一拍 —— 否则 ET 跨步累加，"单步超时"变成"相内累计"
fbStepWatch(IN := bEnable AND bStepMon AND (NOT bStepWatchBreak) AND
                 ((eState = E_DL_BatchPhaseState.eRunning) OR
                  (eState = E_DL_BatchPhaseState.eCompleting) OR
                  (eState = E_DL_BatchPhaseState.eStopping)),
             PT := tStepUse);
bStepTo         := fbStepWatch.Q;   // 超时判定在实例调用后取用
bStepWatchBreak := FALSE;           // 断输入脉冲在实例调用后自清

// 暂停请求：只在步骤边界真正暂停（动作中途绝不切断）
E_DL_BatchPhaseState.eHolding:
    IF NOT bStepIssued THEN
        eState := E_DL_BatchPhaseState.eHeld;      // 本步尚未开始：直接暂停，安全
    ELSIF fbTrigStepDone.Q AND (NOT bStepAcked) THEN
        bStepAcked      := TRUE;                  // 当前步完成反馈到达：边界已到
        bStepWatchBreak := TRUE;                  // 顺带把监控按步重计时
        eState          := E_DL_BatchPhaseState.eHeld;
    END_IF

// 恢复：步骤号不重置，重新等本步的完成反馈
E_DL_BatchPhaseState.eRestarting:
    IF ... THEN
        bStepAcked := FALSE;                      // 置假：恢复后重新等待本步完成
        eState     := E_DL_BatchPhaseState.eRunning;
    END_IF
```

**适合渠道**：ISA-88 落地实践长文、「批次暂停为什么必须停在步骤边界」事故复盘、MES 对接的相状态对表指南、制药/锂电/食品三条线的批次平台售前包。

---

## 36. `FB_DL_ValveStictionDetect` ｜ 阀门黏滞：文献说「没有单一判据可信」，我们就三判据并发

**一句话 / One-liner**：三判据并发（方向性滞后带 + 停滞拍计数 + 反转确认延迟）的非侵入式阀门黏滞趋势诊断，输出定位为趋势判据而非计量量化——把学术文献的反向结论如实写进契约。

### 解决什么现场问题 / Field Problem

- **过程工业 20~30% 的控制回路振荡源于阀门非线性，其中黏滞最常见**（Choudhury & Shah 等文献共识）——但现场绝大多数回路对黏滞只有「手感」，没有码位。
- **单卡滞位不够用**：一个「阀门可能卡了」的布尔位无法区分「完全不动」「动而未达」「偶发迟滞」，维护人员到现场前无法备件、无法定级。
- **误报的代价高于漏报**：把纯跟随滞后算成黏滞，会让维护团队反复拆检好阀。

### 设计亮点 / Design Highlights

- **先读文献的失效边界，再决定做什么**：文献综述明确——Horch 互相关法在含积分环节或可压缩流体回路失效（需长窗 FFT，违背 O(1) 内存红线）；PV-OP 椭圆拟合法受控制器整定影响、只能给量级（需二维最小二乘迭代，不可逐拍复算）；**2023 综述结论：没有单一技术能 100% 置信判定，须多判据并用**。本件据此只做三判据并发，且「Moderate 及以上必须有停滞或反转证据」——判据 (a) 为充分条件、(b)(c) 为必要佐证的合取式，不会因单点指标越限判重度。
- **三判据各有独立证据量**：① 同一 OP 处上升/下降行程的 PV 差 → 黏滞带估计；② 指令变化超阈而阀位移动小于阈、持续超时 → 停滞计次；③ 方向反转后阀位开始移动的滞后 → 反转确认。
- **诚实契约**：头注释写死「本件输出为趋势判据，不作黏滞量的计量级量化」——把文献的「不可能」如实写进契约，而不是包装成精度承诺。
- **保守盲区优于误报路径**：全行程单向斜坡下判据 (a) 无可比反转点、黏滞带恒 0——终审裁定保留该保守盲区（任何「同 OP 差分」在持续运动上都会把纯跟随滞后误算成黏滞），并在头注释写明替代做法。

### 边界处理 / Edge Cases

- **跨相复验（R42）**：判定拍 `bPosValid=FALSE` 时不发布新等级、置 015D，等级与黏滞带均不动。
- **恢复不重头（R41）**：挂起恢复后样本从 0 重建、置 `_bRebuildWin`，首窗只重建不发布——比规格更严。
- **停滞不重复计次**：停滞定时器事件后立刻断输入重启，同一停滞只计一次。
- **非有限输入**：fCmd=NaN → 031D 锁存，黏滞带保持且夹 0~100，不输出毒值。

### 与开源同类对比 / Versus Open Source

| 维度 | 常见学术/开源实现 | 本件 |
|---|---|---|
| 判据 | 单一方法（互相关或椭圆拟合）为主 | **三判据并发 + 合取升级** |
| 资源 | 长窗 FFT / 二维迭代，O(n) 内存 | **O(1) 内存 + 定长数组 + 逐拍可复算** |
| 精度承诺 | 常隐含「可量化」 | **显式声明为趋势判据，不承诺计量精度** |
| 输出 | 连续指标 | 四级等级（eNone/eSlight/eModerate/eSevere）+ NE107 健康映射 |

---

## 37. `I_DL_DeviceHealth` + `FB_DL_ModbusPowerMeter` ｜ 全库统一 NE107 健康出口语言的第一个落地对

**一句话 / One-liner**：契约件 `I_DL_DeviceHealth` 以 NAMUR NE107 四态（F/C/S/M）定义全库唯一权威健康枚举，实现件 `FB_DL_ModbusPowerMeter` 成为第一个消费者——设备诊断从此有了统一语言。

### 解决什么现场问题 / Field Problem

- **44 个设备件各有各的健康表达**：有的给 bError、有的给 eState、有的给码位，HMI 每接一个新设备就要重写一套图标映射。
- **「优先级」与「严重度」被混为一谈**：NE107 明确两者不同——Function Check（C）严重度低但处置优先级高于 Maintenance Required（M）。
- **电表数据「看着有数、不可信」**：跨相时序、字序错配、轻载 PF 失真，都需要分层判据而不是单一阈值。

### 设计亮点 / Design Highlights

- **四态 + 编号即优先级**：`eFailure 0 / eCheckFunction 10 / eMaintenanceReq 20 / eOutOfSpec 30 / eOk 40 / eUnknown 99`，头注释显式声明「编号表达优先级，不表达 NE107 官方图标顺序」，并告警「按图标改号会让全部实现块仲裁方向静默反转」。
- **单一属主纪律**：`E_DL_Ne107Status` 全库仅此一处 TYPE（实扫确认），其余件只引用不重复声明——重复声明会让两个枚举在 CASE 里互不认识。
- **实现件分层判据**：跨相全零 4 s 内 eDegraded（降级不锁存）、5 s 转 eFault+0317；32 位电能按四种字序拼装，回绕与换表同路径处理（重载基准 + 计次 + 维护码，头注释分层声明）；PF 复算交叉校验（复算值 vs 表值偏差 > 3% → 015A）。
- **修复的元教训**：`_bPfMismatch` 只有置位没有清零点，一次 015A 即永久 eDegraded——「每拍判据」被误当「锁存量」（R34 违例）；以及跨文件枚举比较基准必须在声明区（语句段直写裸类型名会让子集机检误报，A3-D2）。

### 边界处理 / Edge Cases

- **首拍只装基准不判回退（R19）**：电能累计上电首拍只装基准，不把「上电寄存器非零」判成换表。
- **V5 域外**：fKwhPerLsb=0 → 0316 锁存，电能保持上次值且在有效域内。
- **契约侧自洽缺口显式留档**：规格表头「11 条」与表体 12 行矛盾 → 按表体实现并双向留档；CmdResetEnergy 的 bLatched 前置语义由实现块等同 bError 并写明理由（故障期清零会同时抹掉读数与基准）。

### 与开源同类对比 / Versus Open Source

| 维度 | 常见实现 | 本对 |
|---|---|---|
| 健康模型 | 各件自定义 BOOL/枚举 | **NE107 四态统一枚举，编号即优先级** |
| 属主 | 枚举散落各文件 | **单一属主 + 全库只引用** |
| 电能可信度 | 拼完即用 | **字序参数化 + 换表/回绕分层 + PF 交叉校验 + 确认窗** |
| 合规声明 | 常宣称「符合 NE107」 | 只借四态语义与优先级，**不声明认证** |

---

## 38. `FC_DL_Matrix3Inverse` ｜ 3×3 求逆：相对奇异判据救了绝对判据必失守的场景

**一句话 / One-liner**：伴随矩阵法 3×3 求逆，相对奇异判据（|det| ≤ ε·maxAbs³）+ 500 组 A×A⁻¹≈I 随机对拍——LGF Matrix 子族开族首件。

### 解决什么现场问题 / Field Problem

- **坐标变换、最小二乘、传感器融合都要 3×3 求逆**，但纯 ST 库里长期缺位，现场要么抄 C 代码带指针、要么手解克莱姆法则写错符号。
- **绝对奇异判据跨量纲失守**：`|det| < 1e-9` 对元素 ~1 的矩阵合理，对元素 ~1e-6 的矩阵，det 本身就在 1e-18 量级——正常矩阵被判奇异。

### 设计亮点 / Design Highlights

- **相对判据**：`|det| ≤ fDetEps × maxAbs³` 把阈值随矩阵量纲缩放——V4 实算确认：矩阵整体 ×1E-6 后 |det|≈1.2E-32（纯舍入噪声），相对判据 1.7E-17 ≤ 1E-9 正确拦截，**绝对判据在此量纲下必失守**。
- **伴随九元逐项可审**：aW[1..9] 与代数余子式转置（adj = Cᵀ）逐项对应，终审手算复核无符号写反、无转置错位——3×3 是「手算可全查」的最后规模，选伴随法而非高斯消元正是为了让正确性可逐项审计。
- **500 组随机对拍**：A×A⁻¹≈I（容差 1E-6）全数通过——伴随分子与行列式联合正确性的最强实证。
- **病态提示路径**：条件数粗估落在「超 10 倍容差、低于 1e-3」区间时给 014A 提示码，逆照常发布——让调用方知道「算得出，但别太信」。

### 边界处理 / Edge Cases

- **非有限元素**：014B + FALSE + afInv 全 0（逐元素预置保证，不输出 NaN）。
- **容差 0**：014C 提示 + 默认 1E-9 继续。
- **精确奇异**：V3 行列式精确为 0，相对判据判奇异、逆全 0。
- **已知边界（留档）**：元素 ~±1E150 时余子式乘积可溢出 LREAL，现有有限性检查使输出归零不出毒值，是否立「行列式溢出」信息码留 ROADMAP。

### 与开源同类对比 / Versus Open Source

| 维度 | 常见实现 | 本件 |
|---|---|---|
| 算法 | 高斯消元（中间态不可审） | **伴随矩阵法，九元逐项手算可审** |
| 奇异判据 | 绝对阈值 `|det| < eps` | **相对判据 ε·maxAbs³，跨量纲稳健** |
| 验证 | 单向量 | **500 组随机 A×A⁻¹≈I 对拍 + V4 量纲专测** |
| 依赖 | 常带指针/动态内存 | 纯 IEC 定长数组，三平台可移植 |

---

## 附：一句话版本（用于仓库描述与社交简介）

| 组件 / Component | 中文一句话 | English one-liner |
|---|---|---|
| `FB_DL_MovingAverage` | O(1) 递推滑动平均，两阶段启动，窗口可运行时切换 | O(1) recursive moving average with a clean two-phase startup |
| `FC_DL_Crc16Modbus` | Modbus CRC-16，附 4 条实算向量与一条公开勘误 | Modbus CRC-16 with four verified vectors and a documented erratum |
| `FB_DL_SignalDebounce` | 双延时独立可调，上电首扫零假边沿 | Independent rise/fall delays with zero phantom edge on first scan |
| `FC_DL_LinearScale` | 反向量程、零跨度、超量程三种现场输入都不停机 | Survives reversed ranges, zero span and over-range inputs |
| `FB_DL_StepSequencer` | 动作外置的顺控基类，逐步超时 + 换步屏蔽杜绝连环跳步 | Action-external step engine with per-step timeouts and a one-scan switch mask |
| `FB_DL_AlarmManager` | 三级优先 + 先到先得首出，激活/确认/首出三态正交 | Three-level arbitration with arrival-order first-out and orthogonal states |
| `FC_DL_Crc32Ethernet` | 以太网 CRC-32，链式种子契约支持任意分块接力 | Ethernet CRC-32 with a chained-seed contract for arbitrary chunking |
| `FC_DL_QuickSortLReal` | 显式栈快排零递归，三数取中 + 降级插入排序，不爆栈 | Recursive-free stack-based quicksort with median-of-three and fallback |
| `FB_DL_DutyStandbyRotation` | 8 台泵主备轮值，试验序列可行性检查 + 双向最小时长保护 | 8-unit duty/standby rotation with feasibility check and min-time guards |
| `FB_DL_TwoHandSafety` | 双手同步窗 500 ms，卡死跨状态计时升级旁路嫌疑 | Two-hand sync window with cross-state stuck-button diagnostics |
| `FB_DL_PidController` | 两级抗饱和 + 手动期逐拍回填，切自动首拍增量恒为零 | Two-stage anti-windup with per-scan manual backfill for a true bumpless transfer |
| `FB_DL_SCurveGenerator` | 七段 jerk 限制轨迹，剩余距离自适应截断减速行程 | Seven-phase jerk-limited trajectory with adaptive deceleration truncation |
| `FB_DL_SmithPredictor` | 一阶+纯滞后模型补偿，学习态退化不阻塞控制 | Smith predictor with online bias adaptation and non-blocking learning state |
| `FB_DL_CascadePid` | 串级边界三件套：副设定域钳位 + 参数单点注入 + 主环跟踪副设定 | Cascade boundary kit: slave-domain clamping, single-point injection, master tracking |
| `FB_DL_PackMlStateMachine` | 十七态纯框架，Held/Suspended 正交归因，急停必经去污步 | Pure 17-state frame with orthogonal Held/Suspended attribution and mandatory cleanup on abort |
| `FB_DL_SingleAxis` | 一套状态机仿真真机通吃，软限位按制动距离提前收油 | One state machine for simulation and real drives, soft limits decelerate by braking distance |
| `FB_DL_HeatCoolZone` | 注入式 PID+双 PWM 组装件，断偶方向按对象安全策略锁存 | Composed zone of injected PID and dual PWM with policy-configured sensor-break latch |
| `FB_DL_AxisHomingSeq` | 四模式回零序列状态机，超时·行程双护栏，终态可重启 | Four-mode homing sequence state machine with dual guards and restartable terminal states |
| `FB_DL_EnthalpyCompareCtrl` | 差分焓值迟滞判据 + 最小新风位硬下限，失效方向恒落保守侧 | Differential-enthalpy economizer with hard minimum-position floor and conservative failure bias |
| `FB_DL_SafetyLightCurtain` | 序列式屏蔽有方向、错乱即故障，bSafeStop 永不因屏蔽置假 | Sequential muting with direction-aware state machine; bSafeStop never faked by muting |
| `FB_DL_SoftLimitGuard` | 制动距离随速度收缩的电子围栏，超程后仅允许向内恢复 | Braking-distance fence that shrinks with speed; after overtravel only inward moves allowed |
| `FB_DL_ElectronicCam` | 16 点凸轮表 + 相位治理，负向主轴零取模歧义，切点在线微调 | 16-point cam table with negative-MOD-free phase normalization and inline cut-point tuning |
| `FB_DL_CipCleaningSeq` | TACT 联锁暂停不计时，合格时间 ≠ 墙钟时间，清洁许可直供放行 | TACT interlocks freeze the timer — qualified time, not wall-clock, with clean-status release |
| `FB_DL_ModbusPollMaster` | 调度归调度、传输归传输：站表台账即监控，换 RTU/TCP 上层零改动 | Scheduler and transport split: poll table doubles as a monitor, swap RTU/TCP with zero upper-layer changes |
| `FB_DL_PulseDirStepper` | 开环步进为丢步设计出口：堵转按理论耗时判定，减速残差按到位收尾 | Open-loop stepper designed for lost steps: stall by theoretical time, decel residual settles as arrival |
| `FB_DL_AndonCallSystem` | 四级呼叫仲裁可抢占重锁，未应答解除不计入应答统计 | Four-level andon arbitration with preemptive re-lock; unanswered clears never count as responses |
| `FB_DL_PickAndPlaceStation` | 九步序七态工站模板，业务态进安灯不锁故障，只有掉件与超时才停线 | Nine-step pick-and-place station: business states light the andon, only dropped parts and timeouts stop the line |
| `FB_DL_WindingTraverse` | 卷径递推与排线同属一个物理对象，圈增量单次积分，双源切换卷径不跳变 | Winding diameter and traverse share one physical object; single-integration per revolution with bumpless dual-source arbitration |
| `FC_DL_WeekOfYearCalc` | 周四归属 + Zeller 整数式，跨年归属一次算对，顺手勘误了规格书速算式 | Thursday-based ISO week numbering with an integer Zeller form and a documented erratum in the spec formula |
| `FB_DL_PressFitStation` | 八态推进 + 包络二分插值 + 四特征点，NG 拆成五个可分辨原因位 | Eight-state press cycle with interpolated envelope checks, four curve features, and five separable NG bits |
| `FB_DL_PortDiagAggregator` | 8 端口掩码 + 首出端口 + 首出码 + 窗口差分风暴，复位当拍首出即空 | Eight-port mask, first-out port and code, window-differenced burst flag; first-out clears on the reset scan |
| `FC_DL_PercentileLReal` | R-7 分位，拷贝排序不动调用方数组，非有限样本前置剔除 | R-7 percentile on a private sorted copy, with non-finite samples dropped before sorting |
| `FC_DL_SolarPositionCalc` | 六出口太阳位置，负角归一不用 MOD，天顶不可辨显式置正南 | Six-output solar position; negative-angle normalisation without MOD and an explicit south fallback at zenith |
| `FB_DL_LineInterp2Axis` | 两轴插补八态，恢复按剩余量分流，位置与速度同时连续 | Eight-state two-axis interpolation with resume-by-remaining-distance so both position and speed stay continuous |
| `FB_DL_BatchPhaseBase` | ISA-88 十一态相底座，命令优先不排队，暂停只在步骤边界生效 | Eleven-state ISA-88 phase base: priority command arbitration without queuing, hold only at step boundaries |
| `FB_DL_ValveStictionDetect` | 三判据并发黏滞趋势诊断，文献反向结论写进契约：不承诺计量精度 | Three-criteria valve stiction trend diagnosis; the literature's "no single test is trustworthy" becomes the contract |
| `I_DL_DeviceHealth` + `FB_DL_ModbusPowerMeter` | NE107 四态统一健康出口首个落地对，枚举单属主、编号即优先级 | First NE107 four-state health pair: single-owner enum where the number is the priority |
| `FC_DL_Matrix3Inverse` | 伴随矩阵法九元逐项可审，相对奇异判据跨量纲稳健，500 组对拍 | Adjugate-based 3×3 inverse with scale-relative singularity test, verified by 500 random products |


---

*Last updated: 2026-11-16（R13 追加 #36~#38 ｜ 累计 38 篇）｜ 道莅工控代码库产品总监*
