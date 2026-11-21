# ROUND PLAN — Round 09（R9）

> 日期：2026-11-15 ｜ 轮次类型：Phase 1 第九轮批处理（Level 0 回补 + 运动叠加 + 开环步进 + Modbus 轮询调度 + 安灯呼叫）
> 本轮目标：**16 件**（完成后今日累计 110 / 200）｜ 库规模：120 → 132 ｜ 总库版本：v1.7.0 → v1.8.0（入库后）
> 执行人：道莅工控代码库产品总监（Daoli Library Director）
> 规范依据：`daoli-st-standard` SKILL.md + references 全部三件（编码红线 / 目录契约 / 文档模板）+ templates 三骨架

---

## 〇、阶段一盘点结论

| 检查项 | 结论 |
|---|---|
| INDEX_REGISTRY.json | total=120（v1.7.0），counts：DL_Base 24 / DL_MathData 20 / DL_Algo 20 / DL_Device 30 / DL_Motion 13 / DL_Process 13，与 R8 战报一致 |
| 今日进度 | 94 / 200（R3 14 + R4 16 + R5 16 + R6 16 + R7 16 + R8 16） |
| 源矩阵挖掘状态 | T2-1 LGF 六组均为◐未挖尽（Data Handling 2 项 / Comparator 1 项 / Converter 1 项 / Bit Logic 1 项 / Date and Timer 3 项 / Counter 2 项）；T1-4 仅 1 项；T2-7/8 待挖安灯族；T2-4 待挖叠加运动；T1-8 GitHub topics 尚未开组 |
| 查重结论 | 本轮 16 个名称逐一比对 registry **零重名**；AlarmManager / RingBufferLReal / Gray 双转换 / PackBitsToWord / UnpackWordToBits / EventCounter / ModuloCounter / DayOfWeekCalc / TimeWindowCheck 已存在，全部规避 |
| 配额检查 | T2 非 ST 源 ≥ 1 组件族：本组第 4~11 项（T2-1 LGF 七组）、第 12 项（T2-4）、第 16 项（T2-7/8）满足；T1 ST 原生源 ≥ 1 组件族：第 13/14 项（T1-8 stepper）、第 15 项（T1-4）、第 12 项（T1-6 PLCopen）满足 |
| 历史范式带入 | R24 定宽脉冲范式（第 14 项脉冲输出必须单拍/定宽可控）、R25 单拍标志生命周期三律（第 1/11/16 项事件脉冲）、R27 输出保持语义（第 16 项判定保持）、R26 禁孤立分号、R8 首扫标志唯一合法范式（第 11/12/14/15/16 项初始化） |

## 〇.1 泳道分配（3 条泳道，禁止跨泳道依赖本轮新组件）

| 泳道 | 组件 | 说明 |
|---|---|---|
| **A · Level 0 原子族回补（11 件）** | ①FB_DL_FifoBuffer ②FB_DL_ArraySearchFirst ③FC_DL_BinarySearchLReal ④FB_DL_ToleranceWindow ⑤FC_DL_LimitClassify ⑥FC_DL_TempUnitConvert ⑦FC_DL_BcdToWord ⑧FC_DL_WordToBcd ⑨FC_DL_WordBitPack ⑩FB_DL_MonthWindowCheck ⑪FB_DL_PresetCounterSat | 全部落 DL_Base / DL_MathData，泳道内**零互相依赖**（仅依赖 Standard.library 与已入库组件；DayOfWeekCalc 思想只在注释中引用，不做调用）。A 泳道最先落盘，为全库 Level 0 回补（R7 起零新增） |
| **B · 运动叠加 + 开环步进族（3 件）** | ⑫FB_DL_SuperimposedMove ⑬I_DL_StepperOpenLoop ⑭FB_DL_PulseDirStepper | ⑫ 仅依赖已入库 FB_DL_RateLimiter（DL_Algo，R4 入库），零新依赖；⑬⑭ 为同一组件族的「契约-实现」对，**泳道内串行**：⑬ 先落盘 → ⑭ 后落盘（IMPLEMENTS ⑬），除该单条族内链外无其他互相依赖 |
| **C · Level 2 工艺/通信调度族（2 件）** | ⑮FB_DL_ModbusPollMaster ⑯FB_DL_AndonCallSystem | 均为调度抽象层，**只依赖已入库组件与 Standard.library**（CRC 校验归传输层实现，调度层不触碰帧内容），与 A/B 泳道零耦合，可与 A/B 并行 |

**硬性禁令**：A/B/C 三泳道之间禁止任何「依赖本轮新组件」的引用；若某组件实现中发现必须引用他泳道新组件，回退改设计并在规格备注登记，禁止带病落盘。

## 〇.2 行数配额口径

FB 350~550 行 / FC 200~320 行 / 接口 120~180 行（`wc -l` 口径，含头部注释块与故障码表注释）。本轮预估合计约 **5,920 行**。

---

## 一、组件规格（16 件）

> 通用要求（对全部 16 件生效，正文不再重复）：
> 1. 头部注释块七项齐全（名称/子库/版本 1.0.0/兼容性/功能/开源溯源/修订历史），溯源措辞统一为「参考 XXX 公开手册的**功能分类与参数域**，只借分类/参数域/命名，clean-room 实现」。
> 2. 全文严禁出现被禁记号字面（机检按全文命中为 0 口径）：全局变量声明类记号、外部变量声明类记号、绝对地址记号一律零出现；外部数据一律经引脚或接口注入。
> 3. 100% 中文注释；声明区每变量/每枚举项同行注释，含物理意义、工程单位、取值范围、默认行为。
> 4. 状态机 ENUM + CASE + ELSE 兜底；TON / R_TRIG / F_TRIG 在主周期无条件刷新；浮点禁用判等（用 ABS 差值与容差比较）；除法防零；数组访问边界保护；WHILE 带防死锁计数器。
> 5. 阈值/限幅/超时/重试一律 VAR CONSTANT 或引脚，禁止魔法数；故障统一 uErrorId 输出，故障码表写入手册注释。
> 6. 枚举 TYPE 段随主 POU 同文件声明（沿用库内既有惯例），枚举名 E_DL_ 前缀。

---

### 1. FB_DL_FifoBuffer —— LREAL 先进先出环形队列

- 子库：DL_MathData ｜ 类型：FB ｜ 预计行数：420 ｜ 来源标签：lgf-datahandling
- 功能描述：定长槽位 FIFO 环形队列，支持压入/弹出/窥视/清空，头尾指针管理，满/空/溢出/下溢标志齐备；与已入库 FB_DL_RingBufferLReal（历史缓存语义、LREAL 单值环形窗）职责分离——本块是**通用元素队列**（离散事件/物料号/批号缓存），RingBuffer 是**时间序列窗**。
- 引脚规格：

```iecst
VAR_INPUT
    bPush      : BOOL;                  // 压入请求，上升沿生效
    fPushVal   : LREAL := 0.0;          // 待压入元素值 [工程单位随应用]
    bPop       : BOOL;                  // 弹出请求，上升沿生效
    bPeek      : BOOL;                  // 窥视请求（读队头不弹出），上升沿生效
    bClear     : BOOL;                  // 清空请求，电平生效
    uCapacity  : UINT := 16;            // 队列容量 [槽位]，范围 2~DL_FIFO_MAX
END_VAR
VAR_OUTPUT
    fOutVal    : LREAL;                 // 弹出/窥视结果值
    bDone      : BOOL;                  // 本次操作完成，单拍脉冲（R25 三律：仅操作拍置位）
    bFound     : BOOL;                  // 弹出/窥视成功标志（空队列弹出时为 FALSE）
    bFull      : BOOL;                  // 队列满保持型标志
    bEmpty     : BOOL;                  // 队列空保持型标志
    bOverflow  : BOOL;                  // 满队压入被拒绝，单拍脉冲（丢新策略）
    bUnderflow : BOOL;                  // 空队弹出被拒绝，单拍脉冲
    uCount     : UINT;                  // 当前元素数 [个]
    uErrorId   : UDINT;                 // 故障码，0 = 无故障
END_VAR
VAR_IN_OUT
    afData     : ARRAY[0..DL_FIFO_MAX-1] OF LREAL;  // 存储体，由调用方持有并注入
END_VAR
VAR
    fbTrigPush : R_TRIG;                // 压入边沿
    fbTrigPop  : R_TRIG;                // 弹出边沿
    fbTrigPeek : R_TRIG;                // 窥视边沿
    uHead      : UINT := 0;             // 队头读指针 [槽位索引]
    uTail      : UINT := 0;             // 队尾写指针 [槽位索引]
    uCnt       : UINT := 0;             // 内部计数 [个]
END_VAR
VAR CONSTANT
    DL_FIFO_MAX   : UINT := 256;        // 存储体最大容量 [槽位]
    DL_FLOAT_EPS  : LREAL := 1.0E-9;    // LREAL 判等容差
END_VAR
```

- 状态机：无主状态机（数据结构块），以指针一致性断言替代：每周期校验 uCnt <= uCapacity 且 uHead/uTail < uCapacity，越界即写 uErrorId 并清空重建（自愈）。
- 边界防错：①容量引脚在使能拍钳位到 2..DL_FIFO_MAX；②满队压入拒绝并置 bOverflow（丢新策略，不覆盖旧数据）；③空队弹出拒绝并置 bUnderflow；④bPush/bPop 同拍同时请求按「先弹后压」固定次序；⑤数组下标全部经取模回绕且先判边界。

---

### 2. FB_DL_ArraySearchFirst —— 数组线性搜索首个命中值

- 子库：DL_MathData ｜ 类型：FB ｜ 预计行数：380 ｜ 来源标签：lgf-datahandling
- 功能描述：在注入数组前 nCount 个元素中线性搜索首个命中目标值的索引；可选全量计数模式统计命中总数。与 FC_DL_BinarySearchLReal 职责分离：本块不要求有序、O(n) 单遍；二分块要求升序、O(log n)。
- 引脚规格：

```iecst
VAR_INPUT
    bExecute    : BOOL;                 // 执行搜索，上升沿触发
    fTarget     : LREAL := 0.0;         // 目标值 [工程单位随应用]
    nCount      : DINT := 0;            // 搜索范围 [元素数]，0~DL_SRH_MAX
    bSearchAll  : BOOL := FALSE;        // TRUE = 继续全量扫描统计命中总数
END_VAR
VAR_OUTPUT
    bDone       : BOOL;                 // 搜索完成，单拍脉冲
    bFound      : BOOL;                 // 至少命中一个
    nIndex      : DINT := -1;           // 首个命中索引 [元素下标]，未命中 = -1
    uHitCount   : UINT := 0;            // 命中总数 [个]（bSearchAll = FALSE 时为 0/1）
    uErrorId    : UDINT;                // 故障码，0 = 无故障
END_VAR
VAR_IN_OUT
    afData      : ARRAY[0..DL_SRH_MAX-1] OF LREAL;  // 搜索数据体，调用方注入
END_VAR
VAR
    fbTrigExec  : R_TRIG;               // 执行边沿
    nGuard      : DINT;                 // 循环防死锁计数器
END_VAR
VAR CONSTANT
    DL_SRH_MAX  : DINT := 1024;         // 数组容量上限 [元素]
    DL_FLOAT_EPS: LREAL := 1.0E-9;      // LREAL 判等容差
END_VAR
```

- 状态机：无主状态机；边沿触发 + 扫描完成即停。
- 边界防错：①nCount 钳位 0..DL_SRH_MAX；②命中判据用 ABS(afData[i] - fTarget) < 容差，禁用浮点判等；③FOR 循环等效于带计数上限（DL_SRH_MAX 即防死锁上限），超限置 uErrorId 跳出；④未命中时 nIndex 固定 -1、bFound FALSE，不残留上拍结果（每拍先清）。

---

### 3. FC_DL_BinarySearchLReal —— LREAL 升序数组二分查找（纯函数）

- 子库：DL_MathData ｜ 类型：FC（返回值 DINT 索引）｜ 预计行数：230 ｜ 来源标签：lgf-datahandling
- 功能描述：对升序 LREAL 数组做经典二分查找，返回首个命中索引（元素下标），未命中返回 -1；无状态、无副作用。
- 引脚规格：

```iecst
FUNCTION FC_DL_BinarySearchLReal : DINT    // 返回命中索引 [元素下标]，未命中 = -1
VAR_IN_OUT
    afSorted   : ARRAY[0..DL_BS_MAX-1] OF LREAL;    // 升序数组（调用方保证有序，本函数不校验全序）
END_VAR
VAR_INPUT
    nCount     : DINT;                 // 有效元素数 [个]，0~DL_BS_MAX
    fTarget    : LREAL;                // 目标值
END_VAR
VAR_OUTPUT
    bFound     : BOOL;                 // 命中标志
END_VAR
VAR
    nLo        : DINT;                 // 区间下界索引
    nHi        : DINT;                 // 区间上界索引
    nMid       : DINT;                 // 中点索引
    nGuard     : DINT;                 // 循环防死锁计数器
END_VAR
VAR CONSTANT
    DL_BS_MAX   : DINT := 1024;        // 数组容量上限 [元素]
    DL_FLOAT_EPS: LREAL := 1.0E-9;     // 判等容差
END_VAR
```

- 边界防错：①nCount 钳位 0..DL_BS_MAX；②nMid := nLo + (nHi - nLo) / 2 防溢出写法；③循环上限 DINT 32 次足够覆盖 DL_BS_MAX，仍设防死锁计数器（超限置 bFound FALSE 返回 -1）；④判等用容差比较；⑤空数组（nCount = 0）直接返回 -1。
- **验收向量（终审逐组验算）**（afSorted = {1.5, 2.5, 3.5, 4.5, 5.5}，nCount = 5）：

| 向量 | 输入 fTarget | 期望返回 | 期望 bFound |
|---|---|---|---|
| V1 | 3.5 | 2 | TRUE |
| V2 | 1.5 | 0 | TRUE |
| V3 | 5.5 | 4 | TRUE |
| V4 | 3.6 | -1 | FALSE |
| V5 | 0.5 | -1 | FALSE |

---

### 4. FB_DL_ToleranceWindow —— 公差窗口三态判定（带迟滞）

- 子库：DL_Base ｜ 类型：FB ｜ 预计行数：400 ｜ 来源标签：lgf-comparator
- 功能描述：目标值 ± 公差带三态判定（合格 / 低于下差 / 高于上差），带可配置迟滞回差防止临界抖动；与已入库 FC_DL_Hysteresis（双阈值通断迟滞）和 FC_DL_Deadband（死区抑制输出）职责分离——本块输出**三态分类 + 双向越差告警**，面向质检/定位容差窗场景。
- 引脚规格：

```iecst
VAR_INPUT
    bEnable      : BOOL;                // 使能，FALSE 时输出回安全态 eUnKnown
    fTarget      : LREAL := 0.0;        // 目标值 [工程单位随应用]
    fActual      : LREAL := 0.0;        // 实际值 [工程单位随应用]
    fTolerance   : LREAL := 0.5;        // 公差半带宽 [工程单位]，必须 > 0
    fHysteresis  : LREAL := 0.05;       // 迟滞回差 [工程单位]，0~fTolerance/2
END_VAR
VAR_OUTPUT
    eJudge       : E_DL_TolJudge;       // 三态判定结果（保持型）
    bOk          : BOOL;                // 合格（|实际-目标| <= 公差带）
    bLowOut      : BOOL;                // 低于下差
    bHighOut     : BOOL;                // 高于上差
    bDeviation   : BOOL;                // 偏差越窗事件，单拍脉冲（从合格越出到越差）
    uErrorId     : UDINT;               // 故障码，0 = 无故障
END_VAR
VAR
    eLast        : E_DL_TolJudge;       // 上拍判定状态（迟滞与越窗边沿基准）
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : LREAL := 1.0E-9;     // 判等容差
END_VAR
```

- 配套枚举（同文件 TYPE 段）：E_DL_TolJudge { eUnKnown := 0 // 未使能/非法参数 , eOk := 1 // 合格窗内 , eLowOut := 2 // 低于下差 , eHighOut := 3 // 高于上差 }
- 状态机跃迁：eOk → eLowOut：偏差 > fTolerance + fHysteresis 且实际 < 目标；eLowOut → eOk：偏差 <= fTolerance（进入阈窄、退出阈宽，双向迟滞）；eHighOut 对称；eUnKnown → 三态任一：bEnable 上升且参数合法。
- 边界防错：①fTolerance <= 0 → uErrorId 置参数非法、输出锁 eUnKnown；②fHysteresis 钳位 0..fTolerance/2；③判据全部用 ABS 差值与容差比较；④bDeviation 单拍脉冲遵循 R25 三律（置位/自清/边沿基准单一来源）。

---

### 5. FC_DL_LimitClassify —— 四阈值五档限值分档（纯函数）

- 子库：DL_Base ｜ 类型：FC（返回值 E_DL_LimitBand）｜ 预计行数：260 ｜ 来源标签：lgf-comparator
- 功能描述：下限 / 下警告 / 上警告 / 上限四阈值五档判定（低低 / 低 / 正常 / 高 / 高高）；与 FB_DL_ToleranceWindow（对称公差窗）职责分离——本块是**非对称四级限值仪表分档**。返回档位枚举并经输出引脚给出阈值序非法诊断。
- 引脚规格：

```iecst
FUNCTION FC_DL_LimitClassify : E_DL_LimitBand   // 返回档位判定结果
VAR_INPUT
    fVal      : LREAL;                  // 被判定值 [工程单位随应用]
    fLowLimit : LREAL;                  // 低低限（停机级）[工程单位]
    fLowWarn  : LREAL;                  // 低警告限 [工程单位]
    fUpWarn   : LREAL;                  // 高警告限 [工程单位]
    fUpLimit  : LREAL;                  // 高高限（停机级）[工程单位]
END_VAR
VAR_OUTPUT
    uErrorId  : UDINT;                  // 故障码，0 = 无故障；阈值序非法时置码
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : LREAL := 1.0E-9;     // 判等容差（阈值相邻判非法）
END_VAR
```

- 配套枚举：E_DL_LimitBand { eLowTripped := 0 // 低低档（<= 低低限）, eLowWarn := 1 // 低档 , eNormal := 2 // 正常档 , eUpWarn := 3 // 高档 , eUpTripped := 4 // 高高档 , eInvalid := 9 // 参数非法兜底档 }
- 边界防错：①阈值序校验：fLowLimit <= fLowWarn <= fUpWarn <= fUpLimit（相邻相等视为合法但容差内相等视为非法由终审裁定，默认允许相等档位退化）；②序非法时返回 eInvalid 并置 uErrorId，**禁止静默返回档位**；③边界值归属：等于阈值归更严档（<= 与 >= 闭区间口径，规格注释写死）。
- **验收向量（fLowLimit=10, fLowWarn=20, fUpWarn=80, fUpLimit=90）**：

| 向量 | fVal | 期望返回 | 期望 uErrorId |
|---|---|---|---|
| V1 | 5.0 | eLowTripped | 0 |
| V2 | 15.0 | eLowWarn | 0 |
| V3 | 50.0 | eNormal | 0 |
| V4 | 85.0 | eUpWarn | 0 |
| V5 | 95.0 | eUpTripped | 0 |
| V6 | 阈值组 90/80/20/10（序倒置） | eInvalid | 非 0 |

---

### 6. FC_DL_TempUnitConvert —— ℃ / ℉ / K 三单位互转（纯函数）

- 子库：DL_MathData ｜ 类型：FC（返回值 LREAL）｜ 预计行数：280 ｜ 来源标签：lgf-converter
- 功能描述：摄氏 / 华氏 / 开尔文三温标两两互转，源/目标由枚举单向选择（非 MODE 巨无霸：仅 3×3 查表映射，公式域固定）；物理无效（低于绝对零度）置信息级诊断不阻断返回。
- 引脚规格：

```iecst
FUNCTION FC_DL_TempUnitConvert : LREAL    // 返回换算结果 [目标温标单位]
VAR_INPUT
    fVal    : LREAL;                    // 输入温度 [源温标单位]
    eSrc    : E_DL_TempUnit;            // 源温标选择
    eDst    : E_DL_TempUnit;            // 目标温标选择
END_VAR
VAR_OUTPUT
    uErrorId: UDINT;                    // 故障码，0 = 无故障；结果低于绝对零度置信息级
END_VAR
VAR CONSTANT
    DL_ABS_ZERO_C : LREAL := -273.15;   // 绝对零度 [摄氏度]
END_VAR
```

- 配套枚举：E_DL_TempUnit { eCelsius := 0 // 摄氏度 , eFahrenheit := 1 // 华氏度 , eKelvin := 2 // 开尔文 }
- 换算基准链：一律先归一到摄氏（K → C 减 273.15；F → C 按公开温标定义式），再从摄氏到目标；同标转换直通。
- 边界防错：①枚举越界值（非 0/1/2）→ 置 uErrorId 并返回 0.0；②归一后低于绝对零度 → 置信息级码，返回值照算输出（不截断，便于诊断链追溯）；③显式类型转换、无常量魔法数（273.15 提为常量）。
- **验收向量**：

| 向量 | 输入 | 期望返回 | 备注 |
|---|---|---|---|
| V1 | 100.0, C → K | 373.15 | 沸点 |
| V2 | 100.0, C → F | 212.0 | 沸点华氏 |
| V3 | 32.0, F → C | 0.0 | 冰点 |
| V4 | 300.0, K → C | 26.85 | 常温 |
| V5 | -40.0, C → F | -40.0 | 双温标交点 |

---

### 7. FC_DL_BcdToWord —— BCD 码转 UINT（纯函数）

- 子库：DL_MathData ｜ 类型：FC（返回值 UINT）｜ 预计行数：240 ｜ 来源标签：lgf-converter
- 功能描述：16 位 BCD 码字（4 个十进制半字节）转 UINT 数值；非法半字节（> 9）检测置故障并返回 0。
- 引脚规格：

```iecst
FUNCTION FC_DL_BcdToWord : UINT           // 返回十进制数值 [0~9999]
VAR_INPUT
    uBcd    : WORD;                     // BCD 码字，每个 4 位半字节代表一位十进制数 0~9
END_VAR
VAR_OUTPUT
    uErrorId: UDINT;                    // 故障码，0 = 无故障；非法半字节置故障
END_VAR
VAR
    nNib    : USINT;                    // 半字节序号 0~3
    uDigit  : USINT;                    // 当前半字节十进制值 [0~15]
    uResult : UINT;                     // 累加结果
END_VAR
VAR CONSTANT
    DL_BCD_NIBS   : USINT := 4;         // WORD 含半字节数
    DL_BCD_RADIX  : UINT := 10;         // 十进制权基数
END_VAR
```

- 边界防错：①逐半字节校验 > 9 即置故障返回 0（不返回部分结果，防静默错值）；②无移位魔法数（移位量由半字节序号 × 4 推导并注释）。
- **验收向量**：

| 向量 | uBcd | 期望返回 | 期望 uErrorId |
|---|---|---|---|
| V1 | 16#0123 | 123 | 0 |
| V2 | 16#9999 | 9999 | 0 |
| V3 | 16#0000 | 0 | 0 |
| V4 | 16#001A | 0 | 非 0（非法半字节 A） |
| V5 | 16#0999 | 999 | 0 |

---

### 8. FC_DL_WordToBcd —— UINT 转 BCD 码（纯函数）

- 子库：DL_MathData ｜ 类型：FC（返回值 WORD）｜ 预计行数：240 ｜ 来源标签：lgf-converter
- 功能描述：UINT（0~9999）转 16 位 BCD 码字；超 9999 溢出检测置故障并返回 16#9999 饱和值。
- 引脚规格：

```iecst
FUNCTION FC_DL_WordToBcd : WORD           // 返回 BCD 码字 [每半字节一位十进制]
VAR_INPUT
    uVal    : UINT;                     // 十进制输入值 [0~9999]
END_VAR
VAR_OUTPUT
    uErrorId: UDINT;                    // 故障码，0 = 无故障；超 9999 置溢出
END_VAR
VAR
    nNib    : USINT;                    // 半字节序号 0~3
    uDigit  : UINT;                     // 当前位十进制余数 [0~9]
    uWork   : UINT;                     // 除法工作副本
END_VAR
VAR CONSTANT
    DL_BCD_MAX    : UINT := 9999;       // BCD 可表示上限
    DL_BCD_NIBS   : USINT := 4;         // 半字节数
    DL_BCD_RADIX  : UINT := 10;         // 十进制权基数
END_VAR
```

- 边界防错：①uVal > 9999 → 置故障并返回 16#9999（饱和输出，明确注释不回绕）；②除法基数为常量 10，无除零风险但仍写守卫；③逐位提取用除/取余显式运算并注释位权。
- **验收向量**：

| 向量 | uVal | 期望返回 | 期望 uErrorId |
|---|---|---|---|
| V1 | 123 | 16#0123 | 0 |
| V2 | 9999 | 16#9999 | 0 |
| V3 | 10000 | 16#9999 | 非 0（溢出饱和） |
| V4 | 0 | 16#0000 | 0 |
| V5 | 4096 | 16#4096 | 0 |

---

### 9. FC_DL_WordBitPack —— WORD 位段参数化打包 / 解包（纯函数）

- 子库：DL_Base ｜ 类型：FC（返回值 WORD 合成结果）｜ 预计行数：300 ｜ 来源标签：lgf-bitlogic
- 功能描述：按位偏移 + 位宽参数把字段值合入目标字（打包），同拍经输出引脚回读该位段旧值（解包），一函数完成「读-改-写」原子语义；与已入库 FC_DL_PackBitsToWord（16 点 BOOL 打包为整字）与 FB_DL_UnpackWordToBits（整字展开 16 点）职责分离——本块是**任意位段（偏移/宽度参数化）**的打包解包。
- 引脚规格：

```iecst
FUNCTION FC_DL_WordBitPack : WORD         // 返回合成后的字
VAR_INPUT
    uTarget  : WORD;                    // 目标载体字（旧内容）
    uField   : WORD;                    // 待合入字段值（右对齐，超出位宽的高位被忽略）
    nOffset  : USINT;                   // 位段起始偏移 [bit]，0~15
    nWidth   : USINT;                   // 位段宽度 [bit]，1~16
END_VAR
VAR_OUTPUT
    uExtracted : WORD;                  // 该位段的旧值（右对齐回读，即解包结果）
    uErrorId   : UDINT;                 // 故障码，0 = 无故障；偏移+宽度越界或宽度 0 置码
END_VAR
VAR
    uMask      : WORD;                  // 位段掩码（width 个 1 左移 offset）
    uMaskInv   : WORD;                  // 掩码反相
END_VAR
VAR CONSTANT
    DL_WORD_BITS : USINT := 16;         // WORD 位宽
END_VAR
```

- 边界防错：①nWidth = 0 或 nOffset + nWidth > 16 → 置故障，返回原字不动、uExtracted 返回 0（禁止半写）；②掩码构造宽度 16 时左移 16 位行为按「先构造满宽度掩码再回绕」显式写法处理并注释（避免依赖平台移位语义）；③纯函数无状态，同输入同输出。
- **验收向量**：

| 向量 | uTarget | uField | nOffset | nWidth | 期望返回 | 期望 uExtracted |
|---|---|---|---|---|---|---|
| V1 | 16#0000 | 16#3 | 4 | 4 | 16#0030 | 16#0000 |
| V2 | 16#00FF | 16#0 | 0 | 8 | 16#0000 | 16#00FF |
| V3 | 16#0000 | 16#F | 12 | 4 | 16#F000 | 16#0000 |
| V4 | 16#1234 | 16#A | 4 | 4 | 16#12A4 | 16#0003 |
| V5 | 16#1234 | 16#AA | 4 | 5 | 16#12A4 | 16#0003（高位越宽忽略） |
| V6 | 16#1234 | 16#1 | 15 | 2 | 16#1234 且 uErrorId 非 0 | 0（越界拒绝） |

> **【勘误 · 2026-11-15 终审裁定】** V5 原载期望返回 `16#1264`，经总监逐位独立验算
> 判定为**计划向量笔误**，已更正为 `16#12A4`（代码实现正确，未改动）。验算过程：
> `uMask = (1<<5)-1 << 4 = 16#01F0`；`uExtracted = (16#1234 AND 16#01F0) >> 4 = 16#0003`；
> `uFieldTrim = 16#AA AND SHR(16#01F0,4)=16#1F → 16#0A`；`uFieldAlgn = 16#0A << 4 = 16#00A0`；
> `uBase = 16#1234 AND NOT 16#01F0 = 16#1204`；合成 `16#1204 OR 16#00A0 = 16#12A4`。
> `16#1264` 的位 4~8 = `0_0110`（字段值 6），与本组入参 `16#AA / width 5 / offset 4`
> 无任何推导路径，故判计划表笔误。此留痕沿用 R8「公式对、向量错」勘误口径。

---

### 10. FB_DL_MonthWindowCheck —— 月度 / 年度时间窗判定

- 子库：DL_Base ｜ 类型：FB ｜ 预计行数：430 ｜ 来源标签：lgf-datetime
- 功能描述：月内第 N 天 / 月末倒数第 N 天的日期窗判定（支持窗口宽度天数），可选年度模式（仅指定月份生效，用于年度保养窗/年度盘点窗）。复用已入库 FC_DL_DayOfWeekCalc 的**闰年与月长思想**但独立实现（本块仅需月长计算，不做星期推导）；日期全部由引脚注入（沿用 R5「时间由引脚注入」修正，不读平台时钟）。与已入库 FB_DL_TimeWindowCheck（日内时窗）职责分离——本块是**日粒度月窗**。
- 引脚规格：

```iecst
VAR_INPUT
    bEnable      : BOOL;                // 使能，FALSE 时输出复位
    nYear        : DINT;                // 当前年份 [公元年]，如 2026
    nMonth       : DINT;                // 当前月份 [月]，1~12
    nDay         : DINT;                // 当前日 [日]，1~31
    nTargetDay   : DINT;                // 目标日 [日]：正数 = 月内第 N 天（1~31）；负数 = 月末倒数第 N 天（-1~-31）
    nWindowDays  : DINT := 1;           // 窗口宽度 [日]，1~31，目标日起连续 n 天
    bYearly      : BOOL := FALSE;       // TRUE = 年度窗：仅 nYearMonth 引脚指定月生效（配合 eYearMonth）
    nYearMonth   : DINT := 1;           // 年度窗生效月份 [月]，1~12（bYearly = FALSE 时忽略）
END_VAR
VAR_OUTPUT
    bInWindow    : BOOL;                // 当前日在窗口内（保持型）
    bWindowOpen  : BOOL;                // 窗口开启单拍脉冲（R25 三律）
    nDaysToTarget: DINT := -1;          // 距目标日剩余天数 [日]，窗口外为 -1，窗内为 0 及以上
    uErrorId     : UDINT;               // 故障码，0 = 无故障
END_VAR
VAR
    fbTrigOpen   : R_TRIG;              // 窗口开启边沿（主周期无条件刷新）
    nMonthLen    : DINT;                // 当月天数 [日]
    nTargetAbs   : DINT;                // 目标日绝对日号（第 N 天口径）
    nTodayAbs    : DINT;                // 今日绝对日号
END_VAR
VAR CONSTANT
    DL_MONTH_MAX : DINT := 12;          // 年度月数上限
END_VAR
```

- 状态机：无主状态机，窗判定为纯组合逻辑 + 边沿脉冲；闰年规则独立实现（能被 4 整除且非整百，或被 400 整除 → 二月 29 天），注释中与 FC_DL_DayOfWeekCalc 思想同源声明。
- 边界防错：①nMonth/nDay 越界（月 1~12、日 1~当月长）→ uErrorId 置日期非法、bInWindow FALSE；②nTargetDay 绝对值钳位 1~当月长（31 在 2 月自动收缩）；③月末倒数口径 = 月长 - |nTargetDay| + 1，窗口跨月末不跨月（注释声明）；④bYearly 时非指定月直接 FALSE 且不置故障；⑤bWindowOpen 单拍遵循 R25（R_TRIG 主周期无条件刷新）。

---

### 11. FB_DL_PresetCounterSat —— 带饱和预设计数器

- 子库：DL_Base ｜ 类型：FB ｜ 预计行数：380 ｜ 来源标签：lgf-counter
- 功能描述：上/下双向计数，到达上限（预设值）或下限（下限预设）**饱和不回绕**，到达上限输出保持型完成标志与单拍阈值事件；装载引脚优先级最高。与已入库 FB_DL_EventCounter（回绕 + 比较输出通用事件计数）、FB_DL_ModuloCounter（取模工位索引）职责分离——本块是**饱和计数**（批次计数/托盘满载场景）。
- 引脚规格：

```iecst
VAR_INPUT
    bCountUp   : BOOL;                  // 上计数脉冲输入，上升沿生效
    bCountDown : BOOL;                  // 下计数脉冲输入，上升沿生效
    bLoad      : BOOL;                  // 装载预设值，上升沿生效（优先级最高）
    nPreset    : DINT := 100;           // 上限预设值 [个]，>= nLowLimit
    nLowLimit  : DINT := 0;             // 下限预设值 [个]，<= nPreset
    bReset     : BOOL;                  // 复位到下限，上升沿生效
END_VAR
VAR_OUTPUT
    nCount     : DINT := 0;             // 当前计数值 [个]
    bSatHigh   : BOOL;                  // 已达上限饱和（保持型）
    bSatLow    : BOOL;                  // 已达下限饱和（保持型）
    bDone      : BOOL;                  // 计数到达上限，保持型
    bThreshold : BOOL;                  // 首次到达上限单拍脉冲（R25 三律）
    uErrorId   : UDINT;                 // 故障码，0 = 无故障
END_VAR
VAR
    fbTrigUp   : R_TRIG;                // 上计数边沿
    fbTrigDn   : R_TRIG;                // 下计数边沿
    fbTrigLoad : R_TRIG;                // 装载边沿
    fbTrigRst  : R_TRIG;                // 复位边沿
    bReached   : BOOL := FALSE;         // 内部到达标志（阈值事件边沿基准）
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : DINT := 0;           // 无浮点；整数比较无需容差（占位常量删除，见规格注）
END_VAR
```

- 状态机：无主状态机；优先级序写死：装载 > 复位 > 同拍双计数（互相抵消）> 单向计数；饱和边界：上计数在 nCount >= nPreset 时拒绝递增并保持 bSatHigh，下计数在 nCount <= nLowLimit 时拒绝递减并保持 bSatLow。
- 边界防错：①nPreset < nLowLimit → uErrorId 置参数非法、计数钳到 nLowLimit；②bThreshold 单拍事件遵循 R25 三律，边沿基准 bReached 单一来源；③同拍 bCountUp/bCountDown 同时有效 → 计数不变（不偏置任何方向）。

---

### 12. FB_DL_SuperimposedMove —— 运动叠加补偿（MC_MoveSuperimposed 语义）

- 子库：DL_Motion ｜ 类型：FB ｜ 预计行数：520 ｜ 来源标签：plcopen-motion / s7-motion（T1-6 + T2-4）
- 功能描述：叠加运动补偿——在基础轴运行的同时叠加一个动态偏移（视觉纠偏/张力微调场景）：偏移指令经斜坡限速与幅值限幅后叠加到基础位置上输出合成位置；零偏移指令时偏移量平滑归零。只做**叠加律与限幅**，不触碰轴本体指令（轴驱动由上层用合成位置下发）。
- 引脚规格：

```iecst
VAR_INPUT
    bEnable        : BOOL;              // 使能，FALSE 时偏移输出立即冻结（保持型安全）
    fBasePos       : LREAL;             // 基础轴实际位置 [mm]，每拍由上层注入
    fOffsetCmd     : LREAL := 0.0;      // 叠加偏移指令 [mm]，正负双向
    fMaxOffset     : LREAL := 5.0;      // 偏移幅值限幅 [mm]，> 0
    fMaxOffsetSpeed: LREAL := 10.0;     // 偏移斜坡限速 [mm/s]，0 = 不限速直通
    fTaskCycle     : LREAL := 0.01;     // 任务周期 [s]，斜坡积分步长基准
    bZeroNow       : BOOL;              // 强制归零请求（偏移目标置 0，仍走斜坡）
END_VAR
VAR_OUTPUT
    fSuperPos      : LREAL;             // 合成位置 [mm] = 基础位置 + 偏移实际值
    fOffsetAct     : LREAL;             // 偏移实际值 [mm]
    bActive        : BOOL;              // 叠加生效中
    bInSync        : BOOL;              // 偏移已收敛（|指令-实际| < 容差）
    bError         : BOOL;              // 故障保持型
    uErrorId       : UDINT;             // 故障码，0 = 无故障
END_VAR
VAR
    fbSlew         : FB_DL_RateLimiter; // 已入库组件（R4），偏移指令斜坡限速
    fOffsetTarget  : LREAL;             // 偏移目标值（限幅后）[mm]
    fOffsetLast    : LREAL;             // 上拍偏移实际值（收敛判据基准）[mm]
    bFirstScan     : BOOL := TRUE;      // 首扫标志（R19 唯一合法范式：仅初始化用）
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : LREAL := 1.0E-6;   // 收敛判等容差 [mm]
END_VAR
```

- 状态机跃迁：eIdle →（bEnable 且参数合法）→ eActive；eActive →（bZeroNow 或 |fOffsetCmd| 收敛到 0 且持续时间达窗口）→ 保持 eActive 但 bInSync TRUE（叠加层不退出，语义：零偏移归零即常态跟踪）；参数非法或 fbSlew 故障 → eFault（偏移输出冻结为最后安全值，禁止跳变）；eFault →（bEnable 下降沿重建）→ eIdle。
- 边界防错：①fMaxOffset <= 0 或 fTaskCycle <= 0 → 置故障锁 eFault；②偏移目标先幅值限幅（MIN/MAX 双向）再进斜坡；③收敛判据 ABS 差值比较，禁浮点判等；④首扫 fOffsetLast 跟踪 fBasePos + 0 防上电跳变（R19 范式）；⑤复用已入库 FB_DL_RateLimiter，禁止跨泳道引入本轮新组件。
- 建议码位：16#0004_01A0~01A2（信息级/参数钳位）/ 16#0004_02B0~02B2（故障级），终审可裁定。

---

### 13. I_DL_StepperOpenLoop —— 开环步进电机接口契约

- 子库：DL_Device ｜ 类型：接口（INTERFACE）｜ 预计行数：150 ｜ 来源标签：stepper（T1-8 GitHub topics 开组）+ TcOpen 分层思想（T1-5，已开组）
- 功能描述：开环步进电机（脉冲 + 方向）抽象契约：只声明能力（使能 / 相对位移 / 急停 / 复位 / 状态查询），不做实现；限位与报警状态经属性回读。方法数 <= 6（红线），状态细节由实现块承载。
- 契约规格（沿用库内 TcOpen 三段式惯例）：

```iecst
INTERFACE I_DL_StepperOpenLoop

// ---- 属性声明（实现者必须全部实现） ----
// bReady : BOOL            // 就绪（已使能且无故障）
// fPosition : LREAL        // 指令位置累计 [mm]（开环 = 指令推算值，非编码器反馈）
// uAlarmWord : WORD        // 报警字 [bit]：bit0 正限位 / bit1 负限位 / bit2 驱动器报警 / bit3 堵转超时 / bit4~15 保留

// ---- 方法声明（实现者必须全部实现，禁止空实现） ----

// 初始化：注入步进组态（脉冲当量/加减速/堵转判据），返回是否成功
METHOD Init : BOOL
VAR_IN_OUT
    stCfg : ST_DL_StepperCfg;       // 步进组态结构体（同族内定义，调用方持有）
END_VAR

// 使能/去使能（电平语义：TRUE 使能，FALSE 去使能并冻结脉冲输出）
METHOD Enable : BOOL
VAR_INPUT
    bEnable : BOOL;                 // 使能指令
END_VAR

// 相对位移指令：从当前位置移动指定距离（梯形加减速由实现块规划）
METHOD MoveRelative : BOOL
VAR_INPUT
    fDistance : LREAL;              // 目标位移 [mm]，正负双向
    fSpeed    : LREAL;              // 运行速度 [mm/s]，> 0
END_VAR

// 急停：按减速度斜停并清除当前运动指令
METHOD Stop : BOOL

// 故障复位
METHOD Reset : BOOL

// 故障码查询：0 = 无故障
METHOD GetErrorId : UDINT

END_INTERFACE
```

- 边界防错（契约层声明，实现块必须遵守）：①fPosition 为开环推算值，注释强制声明「非反馈位置，禁止当编码器用」；②限位触发后 MoveRelative 必须拒绝同方向指令；③方法返回 FALSE 必须同时可通过 GetErrorId 取得非零码，禁止静默失败。
- 配套结构体 ST_DL_StepperCfg（随本接口同文件声明）：uStepsPerMm : UINT // 脉冲当量 [脉冲/mm]、fMaxSpeed : LREAL // 最大速度 [mm/s]、fAccel : LREAL // 加速度 [mm/s^2]、tStallTimeout : TIME // 运动超时裕度 [ms]、uMicrostep : UINT // 细分数 [细分]，字段注释齐全。

---

### 14. FB_DL_PulseDirStepper —— 脉冲 + 方向开环步进控制器

- 子库：DL_Device ｜ 类型：FB（IMPLEMENTS I_DL_StepperOpenLoop）｜ 预计行数：550 ｜ 来源标签：stepper（T1-8 开组）+ plcopen-motion 梯形规划语义（T1-6，已开组）
- 功能描述：脉冲 + 方向开环步进控制器：梯形加减速脉冲频率规划、限位保护（到位即停并拒绝同向再动）、堵转超时判据（运动耗时超过理论耗时 × 裕度系数或驱动器报警输入 → 故障锁定）。实现 I_DL_StepperOpenLoop 全部属性与方法；物理脉冲经 bPulse/bDir 输出引脚交由上层映射到输出口（零硬编码地址）。
- 引脚规格（接口方法之外的实体引脚）：

```iecst
VAR_INPUT
    bLimitPos   : BOOL;                 // 正限位开关输入（TRUE = 触发），常闭型安全侧由调用方反相
    bLimitNeg   : BOOL;                 // 负限位开关输入（TRUE = 触发）
    bAlarmIn    : BOOL;                 // 驱动器报警输入（TRUE = 报警）
    fJogSpeed   : LREAL := 5.0;         // 点动速度 [mm/s]（预留，本版不启用点动方法）
END_VAR
VAR_OUTPUT
    bPulse      : BOOL;                 // 脉冲输出（由梯形规划按当前频率翻转）
    bDir        : BOOL;                 // 方向输出（TRUE = 正向）
    bEnableOut  : BOOL;                 // 使能输出（透传 Enable 状态）
    fFreqNow    : LREAL;                // 当前脉冲频率 [Hz]（诊断用）
    uAlarmWord  : WORD;                 // 报警字（接口属性实现）
    bReady      : BOOL;                 // 就绪（接口属性实现）
    fPosition   : LREAL;                // 指令位置累计 [mm]（接口属性实现）
    bError      : BOOL;                 // 故障保持型
    uErrorId    : UDINT;                // 故障码，0 = 无故障
END_VAR
VAR
    stCfg       : ST_DL_StepperCfg;     // 组态副本（Init 注入）
    eState      : E_DL_StepperState;    // 主状态机
    fFreqTarget : LREAL;                // 目标脉冲频率 [Hz]
    fStepsRemain: LREAL;                // 剩余步数 [脉冲]
    fStepsAccel : LREAL;                // 加速段步数 [脉冲]
    fStepsDecel : LREAL;                // 减速段步数 [脉冲]
    fbMoveTimer : TON;                  // 运动耗时监控（主周期无条件刷新）
    tMoveExpect : TIME;                 // 理论运动耗时 [ms]（由位移/速度/加减速推算）
    bDirNow     : BOOL;                 // 当前运动方向
    bFirstScan  : BOOL := TRUE;         // 首扫标志（R19）
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : LREAL := 1.0E-6;   // 浮点容差 [mm]
    DL_FREQ_EPS    : LREAL := 0.1;      // 频率容差 [Hz]
    DL_TIMEOUT_GAIN: LREAL := 1.5;      // 堵转判据裕度系数（理论耗时 × 1.5）
END_VAR
```

- 配套枚举：E_DL_StepperState { eIdle := 0 // 空闲待机 , eAccel := 10 // 加速段 , eRun := 20 // 匀速段 , eDecel := 30 // 减速段 , eFault := 99 // 故障锁定 }
- 状态机跃迁：eIdle →（Enable + MoveRelative 且限位未触发且方向可行）→ eAccel；eAccel →（fFreqNow 达目标频率）→ eRun →（剩余步数 <= 减速段步数）→ eDecel →（剩余步数归零）→ eIdle（bReady 保持）；任一运行态 →（限位触发同向 / bAlarmIn / fbMoveTimer 超时）→ eFault；eFault →（Reset 且故障源消失）→ eIdle。ELSE 兜底进 eFault。
- 边界防错：①限位触发瞬间立即停发脉冲并锁方向拒绝位（恢复需反方向指令且 R24 范式：停发为定宽拍内完成，不留半脉冲）；②堵转判据：fbMoveTimer 到达理论耗时 × 裕度系数即故障（理论耗时由梯形段解析式推算，注释给公式）；③fSpeed 钳位 0 < fSpeed <= fMaxSpeed；④脉冲翻转步长由 fTaskCycle（cfg 注入）与频率求导，禁止裸魔法数；⑤TP/定宽脉冲遵循 R24 范式——脉冲最小宽度 >= 一个任务周期，频率上限校验（频率 > 1/(2×周期) 时置码降速）。
- 建议码位：16#0003_0130~0135（信息级/参数钳位）/ 16#0003_0230~0235（故障级），终审可裁定。
- 执行顺序约束：必须在本泳道第 13 项 I_DL_StepperOpenLoop 落盘后编写（族内串行）。

---

### 15. FB_DL_ModbusPollMaster —— Modbus RTU 轮询主站调度器（传输抽象层）

- 子库：DL_Process ｜ 类型：FB ｜ 预计行数：540 ｜ 来源标签：codesys-forge-modbus（T1-4 开族）
- 功能描述：多从站轮询队列调度器：按站表顺序轮询、响应超时重试、异常/成功计数台账；**只做调度抽象层**——帧构造、CRC 校验、字节收发全部由传输层承载：本块内置「执行事务」抽象方法（虚方法，派生块覆盖实现 RTU/TCP 传输），抽象层零触碰内部寄存器与帧内容；CRC 思想复用已入库 FC_DL_Crc16Modbus 的**公开算法定义**但调度层不调用、不内联任何校验逻辑。
- 引脚规格：

```iecst
VAR_INPUT
    bEnable       : BOOL;               // 调度使能，FALSE 时队列暂停并保持现场
    uStationCount : UINT := 4;          // 轮询站数 [站]，1~DL_MB_MAX_STN
    tRespTimeout  : TIME := T#500MS;    // 单事务响应超时 [ms]
    uMaxRetry     : UINT := 3;          // 超时重试上限 [次]，0 = 不重试
    tPollInterval : TIME := T#100MS;    // 相邻事务最小间隔 [ms]
END_VAR
VAR_OUTPUT
    bBusy         : BOOL;               // 有事务执行中
    uActiveStation: UINT;               // 当前轮询站号 [索引 0~n-1]
    uActiveRetry  : UINT;               // 当前站累计重试数 [次]
    bDone         : BOOL;               // 单站事务完成，单拍脉冲（R25 三律）
    bError        : BOOL;               // 故障保持型
    uErrorId      : UDINT;              // 故障码，0 = 无故障
END_VAR
VAR_IN_OUT
    aPollTable    : ARRAY[0..DL_MB_MAX_STN-1] OF ST_DL_PollItem;  // 轮询站表，调用方持有
END_VAR
VAR
    eState        : E_DL_PollState;     // 主状态机
    uStnIdx       : UINT;               // 当前站索引 [0~n-1]
    uRetryCnt     : UINT;               // 重试计数 [次]
    fbPollTick    : TON;                // 轮询间隔定时器（主周期无条件刷新）
    fbRespWatch   : TON;                // 响应超时定时器（主周期无条件刷新）
    fbTrigDone    : R_TRIG;             // 完成边沿
    bReqActive    : BOOL;               // 事务发起标志
END_VAR
VAR CONSTANT
    DL_MB_MAX_STN : UINT := 16;         // 最大站数 [站]
END_VAR
```

- 配套结构体 ST_DL_PollItem（同文件声明）：uSlaveAddr : USINT // 从站地址 [1~247]、uFuncCode : USINT // 功能码（抽象层不解析，仅透传）、uStartAddr : UINT // 起始地址（透传）、uQuantity : UINT // 数量（透传）、uStatOk : UDINT // 成功计数 [次]、uStatErr : UDINT // 异常计数 [次]、bSkip : BOOL // 本站跳过使能。
- 抽象方法：METHOD DoTransaction : BOOL（虚方法桩——抽象层默认实现返回 FALSE 并置 uErrorId「传输层未实现」；派生块覆盖实现真实收发；参数经 VAR_IN_OUT 注入站表项与应答缓冲，不在规格内展开帧格式）。
- 状态机跃迁：eIdle →（bEnable 且站数合法）→ eNextStn（选下一个未跳过站）→ eRequest（调 DoTransaction，启动双定时器）→ eWaitResp →（应答成功）→ eSttUpdate（uStatOk 递增、uRetryCnt 清零）→ eNextStn；eWaitResp →（fbRespWatch 超时且 uRetryCnt < uMaxRetry）→ eRequest（uRetryCnt + 1）；超时且重试耗尽 → eSttUpdate（uStatErr 递增）→ eNextStn（不全局故障，继续轮询，异常台账留证）；全部站表越界 / DoTransaction 桩未覆盖 → eFault；eFault →（bEnable 下降沿重建）→ eIdle。ELSE 兜底进 eFault。
- 边界防错：①uStationCount 钳位 1~DL_MB_MAX_STN；②轮询间隔定时器与超时定时器主周期无条件刷新（红线）；③bDone 单拍脉冲 R25 三律；④调度层禁止解析/改写帧内容（规格红线，注释强制）；⑤WHILE 找下一站带防死锁计数器（跳过站全跳时退出置码）。
- 建议码位：16#0005_0190~0193（信息级/参数钳位）/ 16#0005_0290~0293（故障级），终审可裁定。

---

### 16. FB_DL_AndonCallSystem —— 安灯呼叫系统

- 子库：DL_Process ｜ 类型：FB ｜ 预计行数：500 ｜ 来源标签：andon / omac（T2-7 PackML / T2-8 OMAC 语义，开族）
- 功能描述：车间安灯四级呼叫（缺料 / 品质 / 设备 / 维修）：多源呼叫仲裁（维修 > 设备 > 品质 > 缺料 固定优先级）、应答计时统计（最近/平均应答时长、应答笔数）、超时升级上报位、班次清零。呼叫状态机独立于已入库 FB_DL_SignalTower（三色塔灯驱动，本块不依赖亦可配套）与 FB_DL_PackMlStateMachine（设备级 17 态，安灯为人员响应域，二者正交）。
- 引脚规格：

```iecst
VAR_INPUT
    bCallMat    : BOOL;                 // 缺料呼叫（最低优先级 4）
    bCallQual   : BOOL;                 // 品质呼叫（优先级 3）
    bCallDev    : BOOL;                 // 设备呼叫（优先级 2）
    bCallMaint  : BOOL;                 // 维修呼叫（最高优先级 1）
    bAcknowledge: BOOL;                 // 呼叫应答（上升沿，对当前激活呼叫应答）
    bClear      : BOOL;                 // 呼叫解除（上升沿，清除当前激活呼叫）
    bShiftReset : BOOL;                 // 班次清零（上升沿，统计台账清零，不清激活呼叫）
    tEscalate   : TIME := T#120S;       // 升级上报阈值 [s]，0 = 不升级
END_VAR
VAR_OUTPUT
    eActiveCall : E_DL_AndonLevel;      // 当前激活呼叫级别（eNone = 无）
    bCallActive : BOOL;                 // 有未应答激活呼叫
    bAcked      : BOOL;                 // 已应答未解除（保持型）
    bEscalate   : BOOL;                 // 升级上报（未应答超阈值，保持型直到应答/解除）
    tAckLast    : TIME := T#0MS;        // 最近一次应答耗时 [ms]
    tAckAvg     : TIME := T#0MS;        // 平均应答耗时 [ms]（滚动均值）
    uAckCount   : UDINT := 0;           // 累计应答笔数 [笔]
    uErrorId    : UDINT;                // 故障码，0 = 无故障
END_VAR
VAR
    eCallState  : E_DL_AndonState;      // 呼叫主状态机
    fbEscTimer  : TON;                  // 升级计时定时器（主周期无条件刷新）
    fbTrigAck   : R_TRIG;               // 应答边沿
    fbTrigClear : R_TRIG;               // 解除边沿
    fbTrigShift : R_TRIG;               // 班次清零边沿
    tAckStart   : TIME := T#0MS;        // 呼叫发起时刻耗时基准（内部累加起点）
    tAccum      : TIME := T#0MS;        // 应答耗时累加 [ms]（均值分子）
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : LREAL := 1.0E-6;     // 均值计算守卫
END_VAR
```

- 配套枚举：E_DL_AndonLevel { eNone := 0 // 无呼叫 , eMaterial := 4 // 缺料 , eQuality := 3 // 品质 , eDevice := 2 // 设备 , eMaint := 1 // 维修 }（数值即仲裁权重，小者胜）；E_DL_AndonState { eIdle := 0 // 无呼叫 , eCalled := 10 // 已呼叫待应答 , eAcked := 20 // 已应答待解除 , eFault := 99 // 内部异常 }
- 状态机跃迁：eIdle →（任一呼叫位 TRUE，取最高优先级）→ eCalled（锁存 eActiveCall，启动 fbEscTimer）；eCalled →（bAcknowledge 上升沿）→ eAcked（记录 tAckLast、滚动更新 tAckAvg/uAckCount、bEscalate 复位）；eAcked →（bClear 上升沿）→ eIdle（回 eNone）；eCalled/eAcked 期间更高优先级呼叫到来 → 抢占重锁（当前呼叫统计按已发生笔数落地，防止升级统计丢失，注释写死）；fbEscTimer 到阈值 → bEscalate 保持型置位（升级上报，不改变状态）；eFault →（bShiftReset）→ eIdle。ELSE 兜底进 eFault。
- 边界防错：①多呼叫同拍仲裁固定优先级（枚举数值序），不轮转不随机；②fbEscTimer 主周期无条件刷新；③tAckAvg 滚动均值防除零（uAckCount = 0 时均值保持 0）；④班次清零不清激活呼叫（注释写死语义）；⑤抢占场景 bEscalate 复位重建；⑥R25 单拍三律作用于全部事件输出。
- 建议码位：16#0005_01A0~01A1（信息级）/ 16#0005_02A0~02A1（故障级），终审可裁定。

---

## 二、验收向量汇总（纯函数 FC 6 件，共 31 组）

| 组件 | 向量数 | 位置 |
|---|---|---|
| FC_DL_BinarySearchLReal | 5 | 第 3 节（V1~V5） |
| FC_DL_LimitClassify | 6（含 1 组非法序） | 第 5 节 |
| FC_DL_TempUnitConvert | 5 | 第 6 节 |
| FC_DL_BcdToWord | 5 | 第 7 节 |
| FC_DL_WordToBcd | 5 | 第 8 节 |
| FC_DL_WordBitPack | 6（含 1 组越界拒绝） | 第 9 节 |

> 终审要求：向量必须逐组代回实现逐拍验算（R8 教训：公式对、向量错）——验算记录写入 AUDIT_R9.md；带非法参数组的向量（V6 × 2）必须验证「拒绝路径」而非仅验正常路径。

## 三、终审与本轮特殊注意

1. **机检口径**：全部 .st 全文禁记号命中必须为 0；禁孤立分号空语句（R26）；终结符成对（END_FUNCTION / END_FUNCTION_BLOCK 齐全）。
2. **P0 编译验证**：R8 战报已第七次提醒，本轮组件完成后若编译验证仍未启动，战报中显式升级为库级 P0 风险。
3. **单拍标志家族**（R24/R25）：第 1、11、14、15、16 项均含单拍脉冲输出，终审逐拍推演置位/自清/边沿基准。
4. **抽象方法桩**：第 15 项 DoTransaction 默认桩返回 FALSE + 置码，属抽象层合法形态（非空实现漏填），终审按此口径裁定。
5. 文档同步：入库后按规范更新两子库 VERSION/MANUAL（DL_Base、DL_MathData、DL_Device、DL_Motion、DL_Process 共五个子库本轮均有新增）+ 总库五件套 + JSONL。

---

*Round 09 计划 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监*
