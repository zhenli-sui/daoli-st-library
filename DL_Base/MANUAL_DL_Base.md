# MANUAL — DL_Base 基础逻辑子库使用手册

> **Sublibrary**：`DL_Base` ｜ **Version**：v1.8.0 ｜ **Level**：0（零依赖）｜ **Components**：38（Phase 1 20 项收口 + R5 补强 2 项 + R7 计数器组 2 项 + R9 LGF 四组深化 5 项 + R10 位段/周历/双向计数 3 项 + R11 年窗/环形回绕 2 项 + R12 跨字位段/区间成员/位图变化 4 项）
> **Platforms**：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert
> **Depends**：`Standard.library` only（`TON`、`R_TRIG`、`F_TRIG`、`SHR`、`SHL`）
> 配套版本记录见 `DL_Base/VERSION.md`；全库导航见 `C:\Library\README.md`。

---

## 0. 使用前必读 / Before You Start

1. **位序全库统一**：数组索引 `0` 恒等于 `bit0`（LSB）。本库不提供位序配置开关，需要反向位序的 OEM 请在外层自行反转数组。
2. **位宽全库统一**：位运算组件首版覆盖 32 位域（`DWORD` / `UDINT`），64 位版尚未发布。
3. **故障码全库统一**：`uErrorId = 0` 表示无故障；非零码含义见第 23 节，禁止在调用方重新定义语义。
4. **`bValid = FALSE` 不等于输出无效**：本库多数组件遵循「越界钳位后继续计算」策略，`bValid = FALSE` 表示「参数曾被钳位」，返回值仍是可用值。置 `bValid = FALSE` 且输出归零的组件会在各节显式说明。
5. **软件消抖只对机械触点有意义**：固态/光电/霍尔输入、编码器正交信号、高速计数、已过安全级硬件滤波的通道、PWM 调制信号，一律不得软件消抖。
6. **时间类组件的分辨率等于任务周期**：`FB_DL_PulseGenerator` 的周期下限 2 ms、步超时与看门狗窗口的判定粒度都受扫描周期限制。把时间类组件放在慢任务（如 20 ms）里，1 ms 级参数没有意义。

---

## 1. FB_DL_SignalDebounce ｜ 触点消抖

**定位**：机械触点（按钮、限位、继电器辅助触点）的软件消抖，上升与下降确认延时独立可调。

### 1.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bRawInput` | `BOOL` | IN | 原始输入信号，未经消抖 / Raw input, not debounced |
| `tRiseDelay` | `TIME` | IN | 上升沿确认延时，默认 `T#20MS`，`T#0S` = 直通 / Rising confirmation delay, default 20 ms, `T#0S` bypasses |
| `tFallDelay` | `TIME` | IN | 下降沿确认延时，默认 `T#20MS`，`T#0S` = 直通 / Falling confirmation delay, default 20 ms, `T#0S` bypasses |
| `bEnable` | `BOOL` | IN | 使能，默认 `TRUE`；`FALSE` 时输出直通原始值且事件清零 / Enable, default `TRUE`; `FALSE` bypasses to raw and clears events |
| `bReset` | `BOOL` | IN | 上升沿复位：回 `eInit`、清故障与事件 / Rising edge re-initializes the filter and clears faults |
| `bStable` | `BOOL` | OUT | 消抖后的稳定输出 / Debounced stable output |
| `bRiseEvent` | `BOOL` | OUT | 稳定上升沿，单扫描周期脉冲 / Stable rising edge, one-scan pulse |
| `bFallEvent` | `BOOL` | OUT | 稳定下降沿，单扫描周期脉冲 / Stable falling edge, one-scan pulse |
| `bFiltering` | `BOOL` | OUT | 正在消抖（处于确认态）/ Debounce in progress |
| `bError` | `BOOL` | OUT | 故障标志，需 `bReset` 清除 / Fault flag, cleared by `bReset` |
| `uErrorId` | `UDINT` | OUT | 故障码，0 = 无故障 / Error code, 0 = no error |
| `DL_DEBOUNCE_MAX_DELAY` | `TIME` | CONST | 延时上限 `T#10S`，超限钳位并告警 / Max delay clamp, over-limit clamps and warns |

状态枚举 `E_DL_DebounceState`：`eInit(0)` / `eStable(10)` / `eRiseWait(20)` / `eFallWait(30)` / `eFault(99)`。

### 1.2 调用示例 / Example

```iecst
VAR
    fbDebounceStop : FB_DL_SignalDebounce;   // 急停按钮消抖实例 / E-stop button debounce instance
    bStopRaw       : BOOL;                   // 原始急停触点，常闭，FALSE = 按下 / Raw E-stop contact, normally closed
    bStopStable    : BOOL;                   // 消抖后急停状态 / Debounced E-stop state
    nStopCount     : UDINT;                  // 停机次数统计 / Stop event counter
END_VAR

(* 每周期无条件调用，延时参数按现场触点质量设置 / Called unconditionally every scan *)
fbDebounceStop(
    bRawInput  := bStopRaw,
    tRiseDelay := T#30MS,      // 按下抖动较大，上升延时给 30ms / Longer rise delay for bounce
    tFallDelay := T#50MS,      // 松手抖动更大 / Even longer fall delay
    bEnable    := TRUE,
    bReset     := FALSE );

bStopStable := fbDebounceStop.bStable;

(* 只对消抖后的稳定边沿计数，禁止对原始值取沿 / Count only debounced edges *)
IF fbDebounceStop.bFallEvent THEN
    nStopCount := nStopCount + 1;
END_IF
```

### 1.3 要点 / Notes

- 三个实例（`fbTonRise` / `fbTonFall` / `fbTrigReset`）均在主体最前部无条件刷新，输入回落时 `TON.IN` 变 `FALSE` 自动清 `ET`，抖动不会累积计时。
- 上电首扫直接采样，`bStable` 与 `bLastStable` 同时赋值，边沿差恒为零，不产生假事件。
- 边沿在状态机之后统一出口计算，任何分支改写 `bStable` 都只产生一个脉冲。
- 禁用期间不补发历史边沿；恢复使能时按 `eInit` 重新采样。

---

## 2. FB_DL_DualEdgeTrig ｜ 双边沿检测

**定位**：一个实例同时给出上升沿、下降沿、任意跳变三种单周期脉冲 + 当前电平 + 累计计数，统一多工位取沿语义。

### 2.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bSignal` | `BOOL` | IN | 待检测信号，建议已消抖 / Signal to detect, pre-debounced recommended |
| `bEnable` | `BOOL` | IN | 使能，默认 `TRUE`；`FALSE` 时事件清零但电平仍直通 / Enable; `FALSE` clears events, level still passes through |
| `bReset` | `BOOL` | IN | 上升沿清计数并抑制当周期事件 / Rising edge clears counters and suppresses current-scan events |
| `bLevel` | `BOOL` | OUT | 当前电平，始终直通 / Current level, always pass-through |
| `bRising` | `BOOL` | OUT | 上升沿，单周期脉冲 / Rising edge, one-scan pulse |
| `bFalling` | `BOOL` | OUT | 下降沿，单周期脉冲 / Falling edge, one-scan pulse |
| `bChanged` | `BOOL` | OUT | 任意跳变 = `bRising OR bFalling` / Any transition |
| `uRiseCount` | `UDINT` | OUT | 累计上升沿次数 / Accumulated rising edges |
| `uFallCount` | `UDINT` | OUT | 累计下降沿次数 / Accumulated falling edges |
| `uErrorId` | `UDINT` | OUT | 仅计数器饱和告警（`16#0001_0007`）/ Counter saturation warning only |
| `DL_EDGE_COUNT_MAX` | `UDINT` | CONST | 饱和上限 `16#FFFF_FFFE`，达上限停增不回绕 / Saturation limit, no wrap-around |

### 2.2 调用示例 / Example

```iecst
VAR
    fbEdgeAtPos : FB_DL_DualEdgeTrig;   // 到位信号取沿实例 / In-position edge instance
    bAtPos      : BOOL;                 // 到位传感器 / In-position sensor
    nCycleCount : UDINT;                // 工位循环次数 / Station cycle count
END_VAR

fbEdgeAtPos(bSignal := bAtPos, bEnable := TRUE, bReset := bResetCycle);

IF fbEdgeAtPos.bRising THEN
    nCycleCount := nCycleCount + 1;     // 到位即计数，与下降沿无关 / Count on arrival only
END_IF
```

### 2.3 要点 / Notes

- 计数器**饱和停增**，绝不回绕归零——回绕会让基于计数的上层逻辑静默错乱。
- 首扫用显式 `bFirstScan` 抑制一周期，避免 `R_TRIG` 在 `CLK` 初始为 `TRUE` 时输出假沿。
- 使能关闭时事件清零，但 `bLastLevel` 继续跟踪，恢复使能不会补发假边沿。
- 本组件无顺序状态机（仅有沿锁存与计数），R6 标注 N/A。
- **v1.0.1 修复（重要）**：事件的「上一周期电平」校正极性曾接反——真实上升沿那一拍 `bLastLevel` 必为 `FALSE`，
  写成 `AND bLastLevel` 会把自己屏蔽，导致 `bRising` / `bFalling` **恒为 `FALSE`**、计数永不增长，
  而代码语法完全合法、静态审查看不出来。现已改为 `bRising := Q AND NOT bLastLevel` / `bFalling := Q AND bLastLevel`。
  升级时无需改调用代码；若你的工程里曾为「取不到沿」写过 `NOT bRising` 之类的绕行，请一并删除。

---

## 3. FC_DL_BitGet ｜ 位提取

**定位**：从 32 位状态字安全取位，越界「先判后算」，绝不把非法移位量交给 `SHR`。

### 3.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uValue` | `DWORD` | IN | 待检测的 32 位状态字 / Source 32-bit status word |
| `uBitIndex` | `USINT` | IN | 位序号，`0` = LSB，合法域 0..31 / Bit index, `0` = LSB, valid 0..31 |
| `bValid` | `BOOL` | OUT | 索引合法标志；`FALSE` 时返回值为保底 `FALSE` / Index valid flag; returns safe `FALSE` when invalid |
| `uErrorId` | `UDINT` | OUT | 越界返回 `16#0001_0001` / `16#0001_0001` on out-of-range index |
| 返回值 / Return | `BOOL` | RET | 目标位状态；任何异常路径返回 `FALSE` / Target bit state; `FALSE` on every error path |
| `DL_BIT_INDEX_MAX` | `USINT` | CONST | 31，最大合法位索引 / Max legal bit index |

### 3.2 调用示例 / Example

```iecst
VAR
    uStatusWord : DWORD := 16#0000_2000;   // Modbus 读回的状态字 / Status word read from Modbus
    bCylinderHome : BOOL;                  // 第 13 位 = 气缸原点 / Bit 13 = cylinder home
    bIdxValid     : BOOL;
    uErr          : UDINT;
END_VAR

bCylinderHome := FC_DL_BitGet(uValue := uStatusWord, uBitIndex := 13, bValid => bIdxValid, uErrorId => uErr);

IF NOT bIdxValid THEN
    ; (* 索引写错时这里能立刻发现，而不是等气缸误动作 *) 
END_IF
```

### 3.3 要点 / Notes

- 位提取统一提升到 `UDINT` 后移位，再 `AND 16#0000_0001` 显式取最低位，不使用任何点号位访问语法。
- 返回值在函数入口即置 `FALSE`，规避部分平台「未赋值返回上次残值」的行为。

---

## 4. FC_DL_BitSet ｜ 位置位 / 清零

**定位**：纯函数式置位/清零，输入原值、返回新值，不修改入参、无副作用，可链式嵌入表达式。

### 4.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uValue` | `DWORD` | IN | 原始状态字，函数内只读 / Source word, read-only inside |
| `uBitIndex` | `USINT` | IN | 位序号，`0` = LSB，合法域 0..31 / Bit index, `0` = LSB, valid 0..31 |
| `bSetValue` | `BOOL` | IN | `TRUE` = 置 1，`FALSE` = 清 0，默认 `TRUE` / `TRUE` sets, `FALSE` clears, default `TRUE` |
| `bValid` | `BOOL` | OUT | 索引合法标志；`FALSE` 时原样返回入参 / Index valid flag; input returned unchanged when invalid |
| `uErrorId` | `UDINT` | OUT | 越界返回 `16#0001_0001` / `16#0001_0001` on out-of-range index |
| 返回值 / Return | `DWORD` | RET | 处理后的新字；越界时为原值 / New word; the original value on illegal index |
| `DL_BIT_INDEX_MAX` | `USINT` | CONST | 31，最大合法位索引 / Max legal bit index |

### 4.2 调用示例 / Example

```iecst
VAR
    uAlarmWord : DWORD := 16#0000_0000;   // 报警字 / Alarm word
    bTestMode  : BOOL;                    // HMI 强制测试位 / HMI forced test bit
END_VAR

(* 先校验后构造掩码；越界时原样返回，绝不会把报警字整体清零 *)
uAlarmWord := FC_DL_BitSet(uValue := uAlarmWord, uBitIndex := 7, bSetValue := bTestMode);
```

### 4.3 要点 / Notes

- 越界返回**原值**而不是 0：报警字场景下返回 0 等同于「全部报警消失」，属危险静默失败。
- 清零路径用 `AND NOT mask`，`NOT` 作用于 32 位全域，不会误伤其它位。
- 入参声明为 `VAR_INPUT` 而非 `VAR_IN_OUT`，因此可直接出现在表达式与 `CASE` 分支中。

---

## 5. FC_DL_BitCount ｜ 置位计数

**定位**：统计 32 位字中置 1 的位数（Hamming Weight），用于多传感器投票、工位占用统计、报警严重度分级。

### 5.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uValue` | `DWORD` | IN | 待统计的 32 位字 / Word to count |
| `bValid` | `BOOL` | OUT | 计算完整标志；`FALSE` 表示循环保护被触发 / Complete flag; `FALSE` means the loop guard tripped |
| `uErrorId` | `UDINT` | OUT | 循环超限返回 `16#0001_0004` / `16#0001_0004` when the guard trips |
| 返回值 / Return | `USINT` | RET | 置位数，值域 0..32 / Population count, 0..32 |
| `DL_POPCOUNT_MAX_LOOP` | `DINT` | CONST | 32，迭代上限 / Iteration limit |

### 5.2 调用示例 / Example

```iecst
VAR
    uSensorWord : DWORD;    // 32 路传感器输入字 / 32 sensor inputs
    nActive     : USINT;    // 激活传感器数量 / Number of active sensors
    bVote2oo3   : BOOL;     // 2oo3 表决结果 / 2-out-of-3 vote result
END_VAR

nActive := FC_DL_BitCount(uValue := uSensorWord);

(* 三取二：至少两路激活才允许启动 / 2-out-of-3: at least two active *)
bVote2oo3 := (nActive >= 2);
```

### 5.3 要点 / Notes

- Brian Kernighan 法：`uTemp AND (uTemp - 1)` 每次精确清除最低位的 1，迭代次数 = 置位数；全 0 输入零次迭代，全 1 输入恰好 32 次。
- `uTemp <> 0` 写在 `WHILE` 条件里成为循环不变式，保证无符号减法不下溢。
- 完整性判据取「残值是否归零」而非「计数器是否到顶」——全 1 输入会同时触及两者，只比计数器会误报循环保护。

---

## 6. FC_DL_PackBitsToWord ｜ 位打包

**定位**：16 路离散 BOOL 打包为标准报警字 `WORD`，供 Modbus / PROFINET 上传。

### 6.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `abBits` | `ARRAY[0..15] OF BOOL` | IN | 16 路离散状态，索引 0 → bit0（LSB）/ 16 states, index 0 maps to bit0 (LSB) |
| `bInvertAll` | `BOOL` | IN | 整体取反，适配低电平有效报警点，默认 `FALSE` / Invert all bits for active-low alarms, default `FALSE` |
| 返回值 / Return | `WORD` | RET | 打包后的报警字 / Packed alarm word |
| `DL_PACK_BIT_COUNT` | `INT` | CONST | 16，必须与数组维度一致 / Must equal the array dimension |

> **本函数无 `uErrorId`**：唯一可能的失败态（数组维度与循环上界不一致）已被编译期定长数组 + `VAR CONSTANT` 双重消除，不存在运行期失败路径。此为显式豁免（决策 P3），见源码头注释。

### 6.2 调用示例 / Example

```iecst
VAR
    abCylinderHome : ARRAY[0..15] OF BOOL;   // 16 个气缸原点信号 / 16 cylinder home signals
    uAlarmWordOut  : WORD;                   // 上传给上位机的报警字 / Alarm word sent to the HMI
END_VAR

(* 调用前必须显式初始化数组，不得依赖平台默认 FALSE *)
uAlarmWordOut := FC_DL_PackBitsToWord(abBits := abCylinderHome, bInvertAll := FALSE);
```

### 6.3 要点 / Notes

- 位序写死「索引 i → bit i」，不提供配置开关：两种位序并存是本库最大的长期维护负担。
- 组装在 `UDINT` 域完成再截断到 `WORD`，避免 `WORD` 移位溢出。
- 取反在组装完成后一次性执行，语义清晰且少 16 次分支。

---

## 7. FB_DL_UnpackWordToBits ｜ 状态字解包

**定位**：把通信收到的 `WORD` 解包成 16 个 BOOL，支持位取反掩码，输出整字变化脉冲与置位总数。

### 7.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uWord` | `WORD` | IN | 待解包状态字，原始值 / Source status word, raw value |
| `uInvertMask` | `WORD` | IN | 位取反掩码，1 = 该位取反，默认 `16#0000` / Invert mask, 1 inverts that bit, default `16#0000` |
| `bEnable` | `BOOL` | IN | 使能，`FALSE` 时输出位全 `FALSE`、计数清零 / Enable; `FALSE` forces all bits `FALSE` and clears the count |
| `abBits` | `ARRAY[0..15] OF BOOL` | OUT | 解包结果，索引 0 = bit0 / Unpacked bits, index 0 = bit0 |
| `bChanged` | `BOOL` | OUT | 整字内容变化，单周期脉冲 / Word changed, one-scan pulse |
| `uBitCount` | `USINT` | OUT | 取反后的置位总数 0..16 / Popcount of post-invert bits, 0..16 |
| `uErrorId` | `UDINT` | OUT | 故障码，0 = 无故障 / Error code, 0 = no error |
| `DL_UNPACK_BIT_COUNT` | `INT` | CONST | 16，解包位数 / Unpacked bit count |

### 7.2 调用示例 / Example

```iecst
VAR
    fbUnpack : FB_DL_UnpackWordToBits;   // 状态字解包实例 / Status word unpacker
    uRxWord  : WORD;                     // 通信收到的状态字 / Received status word
    abValve  : ARRAY[0..15] OF BOOL;     // 阀位反馈，其中 4 路常闭 / Valve feedback, 4 normally-closed
    bWordChanged : BOOL;
END_VAR

fbUnpack(
    uWord       := uRxWord,
    uInvertMask := 16#00F0,      // 高 4 位常闭点取反 / Invert the four normally-closed bits
    bEnable     := TRUE );

abValve      := fbUnpack.abBits;
bWordChanged := fbUnpack.bChanged;
```

### 7.3 要点 / Notes

- 变化检测比较的是**原始 `uWord`**，取反掩码只作用于输出位——掩码参与比较会把组态改动误报成现场信号跳变。
- `R_TRIG` 在主体最前部无条件刷新；`uLastWord` 在输出赋值之后更新，顺序反了变化事件会永久失效。
- 禁用期间差异由 `uLastWord` 继续吸收，恢复使能不会补发假事件。
- `uBitCount` 统计的是**取反后**的位，保证 HMI 看到的位与计数同源。

---

## 8. FC_DL_GrayToBinary ｜ 格雷码解码

**定位**：绝对值编码器格雷码 → 标准二进制，支持 1~32 位可变位宽，越界钳位后继续计算。

### 8.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uGrayValue` | `UDINT` | IN | 格雷码原始值，高位脏数据由掩码剔除 / Raw Gray code, dirty high bits removed by the mask |
| `uBitWidth` | `USINT` | IN | 有效位宽 1..32，默认 32，越界钳位 / Valid width 1..32, default 32, clamped |
| `bValid` | `BOOL` | OUT | 位宽合法标志；`FALSE` 表示已钳位 / Width valid flag; `FALSE` means clamped |
| `uErrorId` | `UDINT` | OUT | 位宽越界返回 `16#0001_0001` / `16#0001_0001` on illegal width |
| 返回值 / Return | `UDINT` | RET | 二进制结果，已按位宽掩码 / Binary result, masked to the width |
| `DL_GRAY_WIDTH_MIN` / `DL_GRAY_WIDTH_MAX` | `USINT` | CONST | 1 / 32 / Min and max width |

### 8.2 调用示例 / Example

```iecst
VAR
    uEncoderGray : UDINT;    // 编码器格雷码读数 / Raw encoder Gray value
    uPosition    : UDINT;    // 转换后的二进制位置 / Converted binary position
    fAngleDeg    : REAL;     // 工程量角度 [deg] / Engineering angle [deg]
    bWidthOk     : BOOL;
END_VAR

uPosition := FC_DL_GrayToBinary(uGrayValue := uEncoderGray, uBitWidth := 17, bValid => bWidthOk);

(* 正确调用顺序：转二进制 → 减 Excess 偏移 → 乘分辨率系数 *)
fAngleDeg := (UDINT_TO_REAL(uPosition) - 76.0) * 0.01;   // 9 位 360° 编码器示例 / 9-bit 360° encoder example
```

### 8.3 要点 / Notes

- 位宽 32 时 `SHL(1, 32)` 属未定义行为，实现内特判为 `16#FFFF_FFFF`，绝不进入移位语句。
- 位宽越界**钳位后继续计算**，不返回 0：返回 0 会让上位机看到「位置突然归零」的假故障。
- 本函数**不负责** Excess 偏移补偿（职责单一），调用顺序写错会出现「角度恒定差 76°」类事故。
- 动态读值警告：格雷码只保证相邻编码差 1 位，高速旋转时并行读取仍可能有位偏斜，需「读两次比对」或使用 SSI 同步串行接口。
- 排障手法：匀速转动时数值大幅不规则跳变（而非平滑递增），即为「把格雷码当二进制直接用」。

---

## 9. FC_DL_BinaryToGray ｜ 格雷码编码

**定位**：二进制 → 格雷码，与 `FC_DL_GrayToBinary` 严格互逆，用于向编码器写目标位置或生成测试序列。

### 9.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uBinaryValue` | `UDINT` | IN | 二进制原始值，允许带高位脏数据 / Raw binary value, dirty high bits tolerated |
| `uBitWidth` | `USINT` | IN | 有效位宽 1..32，默认 32，越界钳位 / Valid width 1..32, default 32, clamped |
| `bValid` | `BOOL` | OUT | 位宽合法标志 / Width valid flag |
| `uErrorId` | `UDINT` | OUT | 位宽越界返回 `16#0001_0001` / `16#0001_0001` on illegal width |
| 返回值 / Return | `UDINT` | RET | 格雷码结果 / Gray code result |
| `DL_GRAY_WIDTH_MIN` / `DL_GRAY_WIDTH_MAX` | `USINT` | CONST | 1 / 32 / Min and max width |

### 9.2 调用示例 / Example

```iecst
VAR
    uTargetPos  : UDINT;    // 目标位置，二进制 / Target position in binary
    uTargetGray : UDINT;    // 写给编码器的格雷码 / Gray code written to the encoder
END_VAR

uTargetGray := FC_DL_BinaryToGray(uBinaryValue := uTargetPos, uBitWidth := 17);
```

### 9.3 互逆性自检 / Round-trip verification

单条表达式 `(B XOR SHR(B,1)) AND mask`，无循环。对任意位宽 `w` 与任意 `x ∈ [0, 2^w)`，恒有 `FC_DL_GrayToBinary(FC_DL_BinaryToGray(x, w), w) = x`；已对 `w ∈ {1,2,3,4,10,12,16,17,19,32}` 全序列实测通过（见 `AGENT_EVOLUTION_LOG.md`）。

### 9.4 要点 / Notes

- 输入**必须先 `AND uMask` 再异或**：先异或后掩码时脏高位会经右移渗入有效位区间，掩码只能截断结果而无法还原已被污染的低位。

---

## 10. FB_DL_ExtendedTimer ｜ 四模式工业定时器

**定位**：一个实例覆盖通电延时（TON）/ 断电延时（TOF）/ 单脉冲（TP）/ 保持型累加（RTO）四种现场时序，消除「同一延时需求在项目里散落四种实现、改造时漏改某处」的维护风险。RTO 是 AB / Omron 生态的高频模式，IEC 标准库缺失，由本块补齐。

### 10.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bIn` | `BOOL` | IN | — | — | 输入信号，电平语义 / Input signal, level semantics |
| `eMode` | `E_DL_TimerMode` | IN | `eTon` | — | 工作模式：`eTon` / `eTof` / `eTp` / `eRto` / Operating mode |
| `tPreset` | `TIME` | IN | `T#10S` | ms | 预设时间，合法域 `T#0S` ~ `T#12H`，超限钳位告警 / Preset time, clamped to 12 h |
| `bReset` | `BOOL` | IN | — | — | 上升沿：清零 RTO 累计与故障 / Rising edge clears the RTO accumulation and the fault |
| `bQ` | `BOOL` | OUT | — | — | 输出，语义随模式（见 10.2）/ Output, semantics per mode |
| `bTiming` | `BOOL` | OUT | — | — | 计时进行中 / Timing in progress |
| `tElapsed` | `TIME` | OUT | — | ms | 当前模式已计时；RTO 为累计值 / Elapsed, accumulated in RTO |
| `tRemaining` | `TIME` | OUT | — | ms | 距完成剩余，完成或待机为 `T#0S` / Remaining time |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码 / Error code |

### 10.2 四模式输出语义 / Four-Mode Semantics

| 模式 / Mode | `bQ = TRUE` 的条件 / When `bQ` is TRUE | 输入掉电行为 / On input drop |
|---|---|---|
| `eTon` 通电延时 | 输入保持 `TRUE` 满 `PT` / input TRUE for PT | 输出立即 `FALSE`，`tElapsed` 清零 / drops immediately, elapsed cleared |
| `eTof` 断电延时 | 输入 `TRUE` 期间，及输入掉电后的延时保持期 / while TRUE and during the off-delay hold | 保持 `TRUE` 计时满 `PT` 才复位；中途恢复输入则延时作废 / holds TRUE for PT, recovery voids the delay |
| `eTp` 单脉冲 | 上升沿触发后持续 `PT` / PT after a rising edge | 期间输入变化不打断；新上升沿重触发并重新计时 / not interrupted, a new edge retriggers |
| `eRto` 保持型 | 累计达 `PT` 后锁存 / accumulated PT reached | `tAccum` 保留不清零；**未达 `PT` 时输出仍为 `FALSE`**，达 `PT` 后输出锁存、不再受输入影响；仅 `bReset` 清零 / progress kept, output latches only after PT, reset only |

> 运行中改写 `eMode` **立即作废当前计时**（回待机、清零累计），这是操作语义而不是故障，**不产生故障码**。

### 10.3 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | `tPreset` 超上限，已钳到 `T#12H` 并继续计时 / Preset clamped | 检查配方/参数来源，钳位不中断计时 |
| `16#0001_0005` | 主状态机进入非法状态 / Illegal state hit | 断电重启；复现后上报枚举被强制写入的路径 |
| `16#0001_000E` | `eMode` 被写入枚举域外值 / Mode enum out of domain | 检查 HMI 模式写入与配方映射；需 `bReset` 退出故障 |

### 10.4 调用示例 / Example

```iecst
VAR
    fbSealDelay : FB_DL_ExtendedTimer;   // 封口延时实例 / Sealing delay instance
    bSealCmd    : BOOL;                  // 封口指令 / Seal command
END_VAR

(* 每周期无条件调用；换模式自动作废当前计时 *)
fbSealDelay(
    bIn     := bSealCmd,
    eMode   := E_DL_TimerMode.eTon,
    tPreset := T#1S500MS,
    bReset  := bAlarmReset
);

bSealDone := fbSealDelay.bQ;
```

### 10.5 联调要点 / Commissioning Notes

- **模式切换即作废**：HMI 上改模式会让正在计时的动作立刻中断，切换前必须先让设备回安全位，否则表现为「改完参数设备停了一下」。
- **RTO 用差分累加**：块内部把相位定时器的 `ET` 增量并入累计，不直读 `ET` 当累计值——标准定时器在输入断开时会清 `ET`，直读会当场丢进度。现场不要试图用 `tElapsed` 反推「还剩多久」，RTO 的 `tRemaining` 才是完成判据。
- **`tPreset = T#0S` 合法**：表示立即完成，不占一个扫描周期的启动延迟。
- **`bTiming` 与 `bQ` 不等价**：TOF 在延时保持期间 `bTiming = TRUE`、`bQ = TRUE`；TP 在脉冲期间两者同真；TON 在计时期间 `bTiming = TRUE` 而 `bQ` 仍为 `FALSE`。

---

## 11. FB_DL_AlarmManager ｜ 16 通道报警优先级仲裁

**定位**：区分停机级 / 警告级 / 提示级三级优先，输出激活位图报警字与首出通道，确认只清首出锁存、不清激活态——解决「几十个报警同时跳出、操作工不知道该先处理哪个、首出原因被后续连锁淹没」的 ISA-18.2 典型痛点。**只做仲裁与锁存**，不做事件历史与抑制管理（属上位机职责）。

### 11.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `abAlarmActive` | `ARRAY[0..15] OF BOOL` | IN | — | 16 路报警激活态，电平敏感，`TRUE` = 报警中 / Alarm levels, level-sensitive |
| `auPriority` | `ARRAY[0..15] OF USINT` | IN | — | 0 = 禁用，1 = 停机级，2 = 警告级，3 = 提示级 / 0 disabled, 1 stop, 2 warning, 3 info |
| `bAck` | `BOOL` | IN | — | 上升沿确认：推进序号水位并清首出锁存 / Rising edge acknowledges the first-out latch |
| `bEnable` | `BOOL` | IN | `TRUE` | `FALSE` 时输出与序号表全部清零 / `FALSE` clears outputs and the sequence table |
| `uAlarmWord` | `WORD` | OUT | — | 激活报警位图，`bit0` = 通道 0，仅含启用通道 / Active bitmap, enabled channels only |
| `uActiveCount` | `USINT` | OUT | — | 激活通道数 0..16 / Active channel count |
| `bAnyActive` | `BOOL` | OUT | — | 存在任意激活报警 / Any alarm active |
| `bShutdown` | `BOOL` | OUT | — | 存在停机级激活报警（联锁用）/ Any stop-level alarm, for interlocking |
| `nFirstOutIdx` | `INT` | OUT | — | 首出通道索引，`-1` = 无 / First-out index, `-1` = none |
| `bFirstOutAck` | `BOOL` | OUT | — | 首出已确认标志 / First-out acknowledged |
| `nTopPrioIdx` | `INT` | OUT | — | 当前最高优先级激活通道（同级先到先得），`-1` = 无 / Top-priority channel |
| `uErrorId` | `UDINT` | OUT | — | 故障码 / Error code |

### 11.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 某通道优先级 > 3，按 3（提示级）处理，**每周期持续告警** / Priority clamped | 修正 `auPriority` 配置表；持续告警是刻意的，防止配置错误被漏看 |
| `16#0001_0007` | 序号发生器饱和（`16#FFFF_FFFE`），停止取号 / Sequence saturated | 出现即说明实例运行了数十亿次激活而不复位，检查是否把 `bEnable` 当作清表手段 |

### 11.3 调用示例 / Example

```iecst
VAR
    fbAlarm  : FB_DL_AlarmManager;
    abAlm    : ARRAY[0..15] OF BOOL;    // 现场报警位 / Field alarm bits
    auPrio   : ARRAY[0..15] OF USINT := [1,1,2,2,3,0,0,0,0,0,0,0,0,0,0,0];
    bAckBtn  : BOOL;                    // HMI 确认按钮 / HMI acknowledge
END_VAR

fbAlarm(abAlarmActive := abAlm, auPriority := auPrio, bAck := bAckBtn, bEnable := TRUE);

IF fbAlarm.bShutdown THEN
    bLineStop := TRUE;                  // 停机级联锁 / Stop-level interlock
END_IF

sFirstOutMsg := CONCAT('First out: CH', INT_TO_STRING(fbAlarm.nFirstOutIdx));
```

### 11.4 联调要点 / Commissioning Notes

- **首出是电平敏感的**：输入即「正在报警」，冷启动时已处于报警态的通道会在首扫按扫描顺序依次取号，**谁先被扫到谁是首出**。需要「相对已知良好起点」判定的场合，请在输入侧做沿处理（例如用 `FB_DL_DualEdgeTrig` 锁存激活事件）。
- **确认不清除激活**：`bAck` 只推进水位，`bAnyActive` / `uAlarmWord` 不受影响。HMI 上的「消音」和「故障消失」是两件事，不要合并到一个按钮。
- **禁用即清场**：`bEnable := FALSE` 会清空序号表，重新使能视同冷启动重扫——避免禁用期间积压的报警在恢复瞬间集中爆发、首出指向历史事件。
- **报警字是最终事实**：禁用通道（优先级 0）对应位强制 0，即使该通道确实跳了，避免上位机与 PLC 仲裁结果互相矛盾。

---

## 12. FB_DL_StepSequencer ｜ 通用顺控步引擎

**定位**：Grafcet / SFC 的 ST 基类形态。只管理「当前步号、步内计时、步超时、推进、暂停、单步、故障锁存」，**动作不写死在块内**：调用方按 `nCurrentStep` 执行动作、按 `abStepDone[nCurrentStep]` 回报完成。因此同一个块可供上百个工站复用，而不是某个工站的专用代码。

### 12.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bStart` | `BOOL` | IN | — | — | 上升沿：从 0 号步启动（`eIdle` / `eDone` 有效）/ Rising edge starts at step 0 |
| `abStepDone` | `ARRAY[0..15] OF BOOL` | IN | — | — | 步完成信号，电平语义，调用方按当前步维护 / Step-done levels, caller-maintained |
| `auStepTimeout` | `ARRAY[0..15] OF TIME` | IN | — | ms | 每步超时，`T#0S` = 该步不监控 / Per-step timeout, 0 = not monitored |
| `bHold` | `BOOL` | IN | `FALSE` | — | `TRUE` = 暂停：冻结推进与超时计时 / Holds advancing and the timeout |
| `bSingleStep` | `BOOL` | IN | `FALSE` | — | `TRUE` = 单步调试模式 / Single-step commissioning mode |
| `bAdvance` | `BOOL` | IN | — | — | 单步模式下上升沿推进一步 / Rising edge advances one step |
| `bAbort` | `BOOL` | IN | — | — | 上升沿：中止回空闲，不设故障码 / Abort to idle without an error |
| `bReset` | `BOOL` | IN | — | — | 上升沿：清除故障回空闲（仅 `eFault` 有效）/ Clears the fault, fault state only |
| `nCurrentStep` | `INT` | OUT | — | 步 | 当前步号 0..15，`-1` = 未运行 / Current step, `-1` = inactive |
| `bRunning` | `BOOL` | OUT | — | — | 运行状态标志 / Running flag |
| `bDone` | `BOOL` | OUT | — | — | 全部步完成 / All steps done |
| `bError` | `BOOL` | OUT | — | — | 故障标志，`bReset` 清除 / Fault flag |
| `nFaultStep` | `INT` | OUT | — | 步 | 超时故障发生步号，`-1` = 无 / Fault step index |
| `tStepElapsed` | `TIME` | OUT | — | ms | 当前步已运行时间 / Elapsed in the current step |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码（锁存到复位）/ Error code, latched until reset |

### 12.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 某步超时 > `T#12H`，已钳位 / Step timeout clamped | 修正 `auStepTimeout` 配置 |
| `16#0001_0005` | 主状态机进入非法状态 / Illegal state hit | 断电重启并上报枚举被强制写入的路径 |
| `16#0001_000B` | **步超时故障**，`nFaultStep` 记录故障步号 / Step timeout | 检查该步的传感器、气路、上游互锁；`bReset` 复位后从 `eIdle` 重来 |

> `uErrorId` **锁存到复位**（v1.0.1 修正）：故障期间 `bError = TRUE` 且故障码稳定可读，不会在下一拍读回 0。

### 12.3 调用示例 / Example

```iecst
VAR
    fbSeq     : FB_DL_StepSequencer;
    abDone    : ARRAY[0..15] OF BOOL;    // 步完成位 / Step-done bits
    atTout    : ARRAY[0..15] OF TIME;    // 每步超时 / Per-step timeouts
    bStartSeq : BOOL;
    bFaultRst : BOOL;
END_VAR

atTout[0] := T#3S;  atTout[1] := T#5S;  atTout[2] := T#2S;

fbSeq(bStart := bStartSeq, abStepDone := abDone, auStepTimeout := atTout,
      bHold := bHoldBtn, bSingleStep := bJogMode, bAdvance := bJogStep,
      bAbort := bAbortBtn, bReset := bFaultRst);

(* 动作由调用方按步号执行，块内不含任何工艺 *)
CASE fbSeq.nCurrentStep OF
    0:  bClampClose := TRUE;  abDone[0] := bClampClosedSw;
    1:  bClampClose := FALSE; abDone[1] := bWeldDone;
    2:  abDone[2] := fbSeq.tStepElapsed >= T#1S;
END_CASE

(* 离开某步时务必撤销该步的完成位与动作 *)
```

### 12.4 联调要点 / Commissioning Notes

- **完成位必须由调用方撤销**：块只在换步后的第一个完整周期屏蔽完成判定（`bJustAdvanced`），若旧步的完成位长期保持 `TRUE` 且新步恰好也读该索引，仍会被判成立。这是本块唯一的调用方纪律，务必写进工站规范。
- **暂停 ≠ 续算**：`bHold` 期间定时器输入断开、`ET` 清零，恢复后**重新计时**而不是续算。理由是「续算」需要差分补偿，会让定时器语义复杂化；代价是本块明确披露「暂停不算超时」。需要累计型超时的场合，请在调用方另设 `FB_DL_RuntimeMeter`。
- **单步模式先判超时再推进**：`bSingleStep` 下每步完成即进 `eHold`，`bAdvance` 上升沿才真正换步；`eHold` 期间超时计时冻结，因此单步调试不会被超时打断。
- **故障保留步号**：`eFault` 不清 `nCurrentStep` / `nFaultStep`，「卡在第几步」是现场唯一可用的定位信息。
- **`bDone` 后动作由调用方收回**：块只负责置 `bDone`，不会替调用方关阀、停电机。

---

## 13. FB_DL_WatchdogMonitor ｜ 心跳看门狗

**定位**：监控外部心跳（上位机 / HMI / 从站）的**跳变间隔**是否超窗——解决「通信断了但 PLC 还在用旧值保持输出」「上位机脚本死循环但 TCP 连接还在，查连接状态查不出来」的静默失效。监控对象是跳变，不是电平。

### 13.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bHeartbeat` | `BOOL` | IN | — | — | 被监控心跳信号，期望周期性跳变 / Monitored heartbeat |
| `tMaxInterval` | `TIME` | IN | `T#2S` | ms | 最大允许跳变间隔，上限钳到 `T#1H` / Max allowed interval |
| `tMinInterval` | `TIME` | IN | `T#5MS` | ms | 最小合法间隔，低于视为接线抖动 / Min legal interval |
| `bEnable` | `BOOL` | IN | `TRUE` | — | 使能，`FALSE` 时输出全清 / Enable |
| `bReset` | `BOOL` | IN | — | — | 上升沿：清故障并重新武装 / Rising edge clears the fault and re-arms |
| `bAlive` | `BOOL` | OUT | — | — | 心跳健康（未超时、无频率异常、窗口合法）/ Heartbeat healthy |
| `bTimeout` | `BOOL` | OUT | — | — | 心跳超时锁存 / Timeout latched |
| `tSinceToggle` | `TIME` | OUT | — | ms | 距上次跳变的时长，故障态显示冻结值 / Time since the last toggle |
| `uToggleCount` | `UDINT` | OUT | — | 次 | 累计跳变次数（诊断）/ Accumulated toggles |
| `bError` | `BOOL` | OUT | — | — | 故障标志，`bReset` 清除 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码 / Error code |

### 13.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | `tMaxInterval` 为 0 或超 `T#1H` / Window illegal or clamped | 零窗口按「立即超时」受理并告警，检查参数来源 |
| `16#0001_0005` | 状态机非法状态 / Illegal state hit | 断电重启并上报 |
| `16#0001_0007` | 跳变计数饱和 / Toggle count saturated | 计数器已到 `16#FFFF_FFFE`，需复位或重新使能 |
| `16#0001_0008` | 心跳跳变过快（间隔 < `tMinInterval`）/ Toggle too fast | 接线抖动或心跳被写成恒振荡；**不锁存**，间隔恢复即自动消除 |
| `16#0001_000C` | **心跳超时（看门狗触发锁定）** / Heartbeat timeout | 证明对端已死；`bReset` 上升沿重新武装，故障期间输出保持 |

### 13.3 调用示例 / Example

```iecst
VAR
    fbWdt     : FB_DL_WatchdogMonitor;
    bHbFromHmi: BOOL;                    // 上位机心跳位 / HMI heartbeat bit
    bWdtReset : BOOL;
END_VAR

fbWdt(bHeartbeat := bHbFromHmi, tMaxInterval := T#3S, tMinInterval := T#20MS,
      bEnable := TRUE, bReset := bWdtReset);

IF fbWdt.bTimeout THEN
    bRemoteCmdAllowed := FALSE;          // 心跳丢失即撤除远程控制权 / Revoke remote authority
    bUseLocalRecipe   := TRUE;
END_IF
```

### 13.4 联调要点 / Commissioning Notes

- **上电即武装**：窗口内没有第一个跳变就按时超时。这是刻意设计——心跳必须**先证明自己活着**，否则「通信从未建立」也会被当成健康。
- **重新使能视同首次武装**：`bEnable` 从 `FALSE` 回 `TRUE` 后不会立刻 `bAlive`，要等第一个跳变（手册与代码口径一致）。
- **依赖收窄说明**：本块依赖 `FB_DL_DualEdgeTrig`，但**只取其电平输出**，跳变判定在本地以电平差分完成（上游 v1.0.0 的事件输出存在极性缺陷，v1.0.1 已修复；本地派生与上游等价，故保留）。饱和口径与故障码与上游一致（`16#0001_0007`）。
- **`bTimeout` 与 `bError` 同源**：`bError` 即 `bTimeout`，为与其他组件统一输出命名而并列提供，不要当成两个独立故障。
- **HMI 侧建议**：把 `tSinceToggle` 画成趋势，比一个布尔灯更能看出「心跳正在变慢」的早期征兆。

---

## 14. FB_DL_PulseGenerator ｜ 方波 / 占空比发生器

**定位**：周期与占空比运行时可调的方波，用于间歇喷吹、闪烁灯、步进节拍。用「ENUM 相位状态机 + 单个 TON」实现，不引入任何平台时刻函数，行为与扫描周期严格耦合、可预期。

### 14.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `TRUE` | — | 使能，`FALSE` 时输出 `FALSE` 并复位相位 / Enable |
| `tPeriod` | `TIME` | IN | `T#1S` | ms | 周期，合法域 `T#2MS` ~ `T#12H`，越界钳位告警 / Period, clamped |
| `fDutyCycle` | `REAL` | IN | `0.5` | — | 占空比 0.0~1.0，0 = 恒低，1 = 恒高 / Duty ratio |
| `bPhaseReset` | `BOOL` | IN | — | — | 上升沿：相位回高电平起点 / Rising edge restarts at the high phase |
| `bPulseOut` | `BOOL` | OUT | — | — | 方波输出 / Square-wave output |
| `fProgress` | `REAL` | OUT | — | — | 当前周期进度 0.0~1.0 / Cycle progress |
| `bError` | `BOOL` | OUT | — | — | 参数钳位或非法状态告警 / Warning or fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码 / Error code |

### 14.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 占空比越界（< 0 或 > 1）或周期越界，已钳位继续运行 / Parameter clamped | 检查 HMI 参数上下限；钳位不中断输出 |
| `16#0001_0005` | 相位状态机进入非法状态 / Illegal phase | 断电重启并上报枚举被强制写入的路径 |

### 14.3 调用示例 / Example

```iecst
VAR
    fbPurge : FB_DL_PulseGenerator;
END_VAR

(* 0.3 s 喷吹 / 0.7 s 间歇：周期 1 s、占空比 0.3 *)
fbPurge(bEnable := bAutoMode, tPeriod := T#1S, fDutyCycle := 0.3, bPhaseReset := bPurgeRestart);

bPulseValve := fbPurge.bPulseOut;
```

### 14.4 联调要点 / Commissioning Notes

- **周期下限 2 ms 的理由**：脉冲窄于两个任务周期时，下游边沿检测在扫描采样下必然丢沿，表现为「下游偶尔少计一次」。任务周期大于 1 ms 的工程请把 `tPeriod` 设到 ≥ 两个任务周期。
- **换相必须断一拍（v1.0.1 修正）**：标准定时器只在输入为 `FALSE` 时清已计时，换相时只改预设值不会清零。块内在换相后追加一个扫描周期断开定时器输入（`bRestartMask` 延后一拍提交），使相位时长严格等于设计值。
  - 修复前实测：占空比 0.5 / 周期 1000 ms 时，高相位 500 ms，**低相位只有 1 个扫描周期**；占空比 0.3 时实际周期 700 ms 而非 1000 ms。
  - 修复后实测：0.5 → 500 / 500 ms；0.3 → 300 / 700 ms；0.7 / 600 ms → 420 / 180 ms。
- **占空比 0 与 1 走显式分支**：不穿过相位机，避免「进入高相位当周期即判期满」产生的单扫描假脉冲。
- **禁用后重新使能从高相位起步**：不从中途相位续跑，避免与外设节拍错位；需要相位对齐时用 `bPhaseReset`。
- **`fProgress` 在断拍扫描为 0**：这是换相瞬间的正常值，不要用它做「周期是否正常运行」的判据（用 `bPulseOut` 的跳变或 `bError`）。

---

## 15. FB_DL_CycleTimeMeasure ｜ 扫描周期统计

**定位**：任务周期统计（最近 / 最小 / 最大 / 平均 / 样本数），用于发现「加了几个滤波块和通信轮询后周期悄悄超时、抖动峰值查不到」。**自身不读任何平台时刻**，时间增量由调用方注入，因此三平台零差异。

### 15.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `uDeltaTimeMs` | `UDINT` | IN | — | ms | 本任务周期实际耗时，调用方注入 / Cycle time injected by the caller |
| `bCapture` | `BOOL` | IN | `TRUE` | — | `TRUE` = 本周期计入统计 / Include this cycle |
| `bReset` | `BOOL` | IN | — | — | 上升沿清空全部统计 / Rising edge clears statistics |
| `uCycleLast` | `UDINT` | OUT | — | ms | 最近一个有效周期 / Last valid cycle |
| `uCycleMin` | `UDINT` | OUT | — | ms | 统计窗内最小值 / Minimum in the window |
| `uCycleMax` | `UDINT` | OUT | — | ms | 统计窗内最大值 / Maximum in the window |
| `fCycleMean` | `REAL` | OUT | — | ms | 统计窗内平均值 / Mean in the window |
| `nSampleCount` | `UDINT` | OUT | — | 个 | 统计窗内样本数 / Sample count |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码 / Error code |

### 15.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0007` | 样本数达 1,000,000，统计窗自动重开 / Window reopened | 正常的长跑保护；`uCycleLast` 保留，min/max/均值为新窗口值 |
| `16#0001_0008` | 增量无效（0 或 > 3,600,000 ms），本周期拒收 / Invalid delta | 调用方没取到时刻或取错基准，检查注入代码 |

### 15.3 调用示例 / Example

```iecst
VAR
    fbCycle   : FB_DL_CycleTimeMeasure;
    tNow      : TIME;                    // 调用方取到的系统时刻 / Caller-provided time
    tPrev     : TIME;
    uDelta    : UDINT;
END_VAR

(* 调用方负责取时刻：当前时刻 − 上周期时刻 *)
tNow   := TIME();                        // 平台相关的唯一点位 / The only platform-specific line
uDelta := TIME_TO_UDINT(tNow - tPrev);
tPrev  := tNow;

fbCycle(uDeltaTimeMs := uDelta, bCapture := TRUE, bReset := FALSE);

IF fbCycle.uCycleMax > 8000 THEN
    bPerfWarning := TRUE;                // 峰值超过 8 ms 报警 / Peak over 8 ms
END_IF
```

### 15.4 联调要点 / Commissioning Notes

- **首扫必须跳过或注入已知值**：上电第一次调用时 `tPrev` 为 0，差值会是「从 0 到现在」的巨值，会被判为超限样本并告警（`16#0001_0008`）。正确做法是首扫只赋 `tPrev` 不计入。
- **一个任务一个实例**：块不做跨任务共享，多任务各自声明实例。
- **最小值从首个样本初始化**：不是从 0 开始比较，所以 `uCycleMin` 不会永远显示 0（这是同类实现最常见的缺陷）。
- **重开窗保留 `uCycleLast`**：HMI 上「最近值」不会因为重开窗而跳变。

---

## 16. FB_DL_RuntimeMeter ｜ 运行时长与保养计时

**定位**：累计运行分钟 / 小时、启动次数与保养到期预警，为预测性维护提供基础数据。时间增量注入同第 15 节；累加采用「秒 + 毫秒进位缓存」的整数化方案，不做逐周期浮点累加，从根上消除漂移。

### 16.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bRunning` | `BOOL` | IN | — | — | 设备运行反馈，`TRUE` 期间累计 / Running feedback |
| `uDeltaTimeMs` | `UDINT` | IN | — | ms | 本任务周期耗时，调用方注入 / Cycle time injected |
| `uMaintIntervalMin` | `UDINT` | IN | `UDINT#0` | min | 保养间隔，0 = 关闭预警，上限 525600（1 年）/ Maintenance interval |
| `bMaintAck` | `BOOL` | IN | — | — | 上升沿：保养确认，重置保养计时 / Acknowledge maintenance |
| `bReset` | `BOOL` | IN | — | — | 上升沿：清零全部累计 / Clear all totals |
| `uRunTotalMin` | `UDINT` | OUT | — | min | 累计运行分钟（下取整）/ Total runtime, truncated |
| `fRunHours` | `REAL` | OUT | — | h | 累计运行小时（HMI 直显口径）/ Total runtime in hours |
| `nStartCount` | `UDINT` | OUT | — | 次 | 累计启动次数，饱和不回绕 / Start count, saturating |
| `bMaintDue` | `BOOL` | OUT | — | — | 保养到期，锁存至确认 / Maintenance due, latched |
| `uMaintRemainMin` | `UDINT` | OUT | — | min | 距下次保养剩余，未启用为 0 / Minutes to next maintenance |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码 / Error code |

### 16.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | `uMaintIntervalMin` 超 525600（1 年），已钳位 / Interval clamped | 修正保养间隔配置 |
| `16#0001_0007` | 启动次数饱和 / Start count saturated | 达到 `16#FFFF_FFFE`，需复位重新计数 |
| `16#0001_0008` | 增量无效（0 或 > 3,600,000 ms），本周期不计入 / Invalid delta | 检查注入代码 |

### 16.3 调用示例 / Example

```iecst
VAR RETAIN
    fbPumpRun : FB_DL_RuntimeMeter;      // 必须 RETAIN，否则断电归零 / Must be RETAIN
END_VAR

fbPumpRun(bRunning := bPumpRunning, uDeltaTimeMs := uDelta,
          uMaintIntervalMin := 5000,        // 5000 h ≈ 300,000 min
          bMaintAck := bMaintDone, bReset := FALSE);

IF fbPumpRun.bMaintDue THEN
    bMaintLamp := TRUE;                     // 保养灯常亮直到确认 / Latched maintenance lamp
END_IF
```

### 16.4 联调要点 / Commissioning Notes

- **必须声明为断电保持变量**：`VAR RETAIN fbPumpRun : FB_DL_RuntimeMeter;`。不声明则每次上电全部归零，保养预警与启动次数一起丢失——这是本块唯一的强纪律。
- **整数化累加**：毫秒先进位缓存，攒满 1000 ms 才折算整秒，因此长期运行不会出现「小时数缓慢偏小」的浮点漂移。
- **保养到期锁存**：`bMaintDue` 只有 `bMaintAck` 上升沿能清；保养后忘记按确认，灯会一直亮——这是刻意的。
- **`uMaintIntervalMin = 0` 是功能开关**，不是「立即到期」：此时 `bMaintDue = FALSE`、`uMaintRemainMin = 0`。

---

## 17. FB_DL_TwoHandSafety ｜ 双手安全启动校验

**定位**：压力机 / 压装机 / 封口机的双手启动同步性校验与防旁路状态机。左右按钮须在同步窗（默认 500 ms）内先后按下才给安全输出；一个循环结束后必须双手全释放才允许下一次启动；单侧持续按下超时升级为「旁路嫌疑」并锁存故障——区分「操作不规范」与「按钮被胶带缠住/短接」。

> **合规披露（重要）**：本块是标准 PLC 上的**逻辑结构实现，不是安全认证功能块**。ISO 13851:2019 Type IIIC 要求的安全功能必须由安全继电器或安全 PLC 承担；标准 PLC 输出存在短路失效后静默失效风险，不得作为唯一安全措施。

### 17.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bLeftPressed` | `BOOL` | IN | — | — | 左按钮，TRUE = 按下（常闭接线由调用方取反）/ Left pressed |
| `bRightPressed` | `BOOL` | IN | — | — | 右按钮，TRUE = 按下 / Right pressed |
| `bEnable` | `BOOL` | IN | `TRUE` | — | 使能，FALSE 时输出复位且状态回待机 / Enable |
| `tSyncWindow` | `TIME` | IN | `T#500MS` | ms | 双手同步窗，合法域 0..500 ms，只向下钳位 / Sync window, clamp down only |
| `tReleaseWindow` | `TIME` | IN | `T#100MS` | ms | 双手释放差允许窗，合法域 0..500 ms / Release difference window |
| `tStuckTime` | `TIME` | IN | `T#5S` | s | 单侧持续按下判卡死时间，下限 1 s / Stuck detection time, min 1 s |
| `bReset` | `BOOL` | IN | — | — | 上升沿故障复位（须双手已释放）/ Fault reset, both released required |
| `bSafeOutput` | `BOOL` | OUT | — | — | 安全输出，仅双手同步按下期间 TRUE / Safe output |
| `bBothPressed` | `BOOL` | OUT | — | — | 双手同时按下（无同步含义）/ Both pressed, no synchronism |
| `bSynced` | `BOOL` | OUT | — | — | 本次启动满足同步窗 / This actuation was synchronous |
| `bArmed` | `BOOL` | OUT | — | — | 已武装（自上次全释放后尚未启动）/ Armed |
| `bLeftStuck` / `bRightStuck` | `BOOL` | OUT | — | — | 左/右按钮卡死嫌疑，锁存至复位 / Stuck suspicion, latched |
| `bError` / `uErrorId` | `BOOL` / `UDINT` | OUT | — | — | 故障标志与故障码（锁存）/ Fault flag and code, latched |
| `uCycleCount` / `uAbortCount` | `UDINT` | OUT | — | 次 | 完成循环数 / 放弃次数（饱和）/ Completed / aborted cycles, saturating |
| `eState` | `E_DL_TwoHandState` | OUT | — | — | 状态：`eIdle(0)` / `eWaitSecond(10)` / `eBothPressed(20)` / `eWaitRelease(30)` / `eFault(99)` / State |

### 17.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 时间参数越界已钳位（同步窗只向下钳）/ Parameter clamped | 检查 HMI 参数；放宽窗等于放宽安全，不提供向上放宽 |
| `16#0001_0005` | 状态机非法状态 / Illegal state hit | 断电重启并上报 |
| `16#0001_0007` | 计数器饱和 / Counter saturation | 达 `16#FFFF_FFFE` 停增 |
| `16#0002_0001` | 同步超时（第二手未在同步窗内按下）/ Sync timeout | 多为操作不规范；反复出现检查按钮行程 |
| `16#0002_0002` | 释放不同步 / Release desynchronised | 检查是否有手在循环结束前提前离开 |
| `16#0002_0003` | **旁路嫌疑（按钮卡死）** / Bypass suspicion (stuck) | 持续按下超 `tStuckTime` 升级至此；检查按钮是否被缠住/压住/短接 |

### 17.3 调用示例 / Example

```iecst
VAR
    fbTwoHand : FB_DL_TwoHandSafety;   // 双手启动实例 / Two-hand instance
    bBtnL_Raw : BOOL;                  // 左按钮原始触点 / Left raw contact
    bBtnR_Raw : BOOL;                  // 右按钮原始触点 / Right raw contact
    fbDebL    : FB_DL_SignalDebounce;  // 前置消抖（防抖延时计入同步窗）/ Pre-debounce
    fbDebR    : FB_DL_SignalDebounce;
END_VAR

(* 常闭按钮先消抖再取反，本块只接收 TRUE = 按下 / Debounce, invert, then feed *)
fbTwoHand(
    bLeftPressed  := NOT fbDebL.bStable,
    bRightPressed := NOT fbDebR.bStable,
    tSyncWindow   := T#500MS,
    tReleaseWindow:= T#100MS,
    tStuckTime    := T#5S,
    bReset        := bFaultReset );

bPressAllow := fbTwoHand.bSafeOutput;    // 唯一安全位，直接进压力机使能链 / Single safe bit
```

### 17.4 联调要点 / Commissioning Notes

- **上电武装锁存必须 FALSE**：上电双手已被压住/短接时第一拍就放行是最危险缺省，块内已用显式首扫防线消除，请勿在调用方再加「上电自动启动」逻辑破坏它。
- **防抖与同步窗是串联关系**：防抖延时吃掉同步窗余量，`tSyncWindow` 按剩余余量设置，不要两个都给 500 ms。
- **复位前提校验**：双手未全释放时复位沿无效——「按住一手 + 复位」在块内就是旁路，永远不成立。
- **卡死判定跨状态持续计时**：卡死按钮通常先以同步超时面貌出现，HMI 必须同时展示 `uErrorId` 与 `bLeftStuck`/`bRightStuck` 才能区分两类事件。

---

## 18. FB_DL_InterlockMatrix ｜ 16 路联锁汇总与首因追踪

**定位**：全部停机级条件满足才给出唯一运行许可位；条件失效瞬间锁存「第一个失效通道号 + 完整位图 + 全局序号」；复位后条件未恢复则复位挂起、不清根因。解决「停机后十条联锁同时报、复位键一按就放行根因被掩盖」两类顽疾。只回答「能不能开机」，「先看哪条报警」由 `FB_DL_AlarmManager` 负责。

> **修订记录 / Revision**：**v1.0.1（2026-11-16，R13 存量 R39 修复）**——禁用（未使能）期间按下的复位沿原先被前置的 `eDisabled` 无条件覆盖整拍吞掉，首因锁存与配置故障需**二次复位**才清除。修复后 `eLatched` / `eFault` 两个持有复位沿的状态不再被禁用覆盖，其余状态行为不变；接口表与故障码表零变化，行为影响仅为「禁用期复位沿一次生效」，且禁用期 `eState` 显示更真实。

### 18.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `abConditionOk` | `ARRAY[0..15] OF BOOL` | IN | — | 16 路原始条件，TRUE = 满足，每拍整体刷新 / Raw conditions, refresh every scan |
| `auInvertMask` | `WORD` | IN | `16#0000` | 取反掩码：常闭接线（急停/安全门/油压低）必须置 1 / Invert mask for normally-closed devices |
| `auTripMask` | `WORD` | IN | `16#FFFF` | 停机级掩码：bit=1 停机级，bit=0 提示级（不参与首因、不阻断许可）/ Trip-class mask |
| `bEnable` | `BOOL` | IN | `TRUE` | 使能，FALSE 时许可 FALSE 但**不清锁存**（使能不是复位）/ Enable is not reset |
| `bReset` | `BOOL` | IN | — | 上升沿清除首因锁存（条件未恢复则挂起）/ First-out reset with pending |
| `bPermitToRun` | `BOOL` | OUT | — | 运行许可（唯一放行信号）/ Run permit, the only release |
| `bFirstOutValid` / `nFirstOutIndex` | `BOOL` / `INT` | OUT | — | 首因有效 / 通道号 0..15，-1 = 无 / First-out index |
| `uFirstOutMask` / `uFirstOutSeq` | `WORD` / `UDINT` | OUT | — | 首因位图（同拍多点时多 bit）/ 全局序号（单调递增）/ First-out bitmap and sequence |
| `bFirstOutSimult` | `BOOL` | OUT | — | 首因为同拍多点失效，扫描粒度内不可排序 / Simultaneous, unorderable |
| `bLatchedAtStartup` | `BOOL` | OUT | — | 首因发生在上电首扫（区分「本来就断着」）/ Latched during the first scan |
| `uTripActiveMask` / `uWarnActiveMask` | `WORD` | OUT | — | 当前失效的停机级 / 提示级位图 / Active trip / warning bitmaps |
| `bResetPending` | `BOOL` | OUT | — | 已按复位但条件未恢复 / Reset pending |
| `bError` / `uErrorId` | `BOOL` / `UDINT` | OUT | — | 故障标志与故障码 / Fault flag and code |
| `eState` | `E_DL_InterlockState` | OUT | — | `eDisabled(0)` / `eBlocked(10)` / `ePermitted(20)` / `eLatched(30)` / `eFault(99)` / State |

### 18.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0005` | 状态机非法状态 / Illegal state hit | 断电重启并上报 |
| `16#0001_0007` | 首因序号饱和 / Sequence saturated | 达 `16#FFFF_FFFE` 停止取号 |
| `16#0002_0004` | **配置非法：无任何停机级通道（`auTripMask = 0`）** / No trip-class channel | fail-safe：无配置即禁放行；改对掩码后按复位退出 |

### 18.3 调用示例 / Example

```iecst
VAR
    fbIlk      : FB_DL_InterlockMatrix;
    abCond     : ARRAY[0..15] OF BOOL;   // 16 路联锁条件 / Interlock conditions
    bEstopOk   : BOOL;                   // 急停回路（常闭接线，TRUE = 未拍下）/ E-stop healthy
    bGuardOk   : BOOL;                   // 安全门 / Guard closed
END_VAR

abCond[0] := bEstopOk;                   // CH0 急停，常闭 → 掩码置 1 / NC e-stop
abCond[1] := bGuardOk;                   // CH1 安全门
abCond[2] := bOilPressOk;                // CH2 油压，常闭 → 掩码置 1

fbIlk(
    abConditionOk := abCond,
    auInvertMask  := 16#0005,            // CH0/CH2 常闭取反 / NC devices inverted
    auTripMask    := 16#0007,            // CH3.. 为提示级，不阻断许可 / CH3+ warning class
    bEnable       := TRUE,
    bReset        := bIlkReset );

bMainContactor := fbIlk.bPermitToRun;    // 唯一放行 / Single permit
```

### 18.4 联调要点 / Commissioning Notes

- **常闭接线必须置 invert 位**：有效值 = 原始 XOR 取反位。漏置掩码时「拍下急停」会被判为条件满足——这是本块最危险的组态错误，交付前逐通道核对。
- **首因只在停机级位图 0 → 非 0 的沿捕获**，锁存后不被新故障覆盖；同拍多路失效取最低索引 + 完整位图，HMI 上严禁编造「谁先谁后」。
- **上电首扫即锁存**（不等沿）：`bLatchedAtStartup` 用于区分「冷启动本来就不满足」与「运行中失效」，两者处理路径不同。
- **复位挂起是特性不是缺陷**：条件未恢复时按复位只置 `bResetPending`，根因保留到条件恢复才清——第二天同一故障再现时，首因记录还在。

---

## 19. FB_DL_RedundantSwitch ｜ 双通道冗余选择器

**定位**：双传感器 / 双执行器反馈的冗余选择。持续比较 A/B 偏差，超限延时确认后报警；单通道失效按停留时间与速率限制无扰切换；切换过频判定抖振并锁定。核心语义：**两路传感器打架时，程序没有资格替工艺判断谁对**——默认 `eHoldLast` 保持最后有效值，要自动跟随某一路必须显式改 `eDevPolicy` 并在设计文件留档。

### 19.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `fChannelA` / `fChannelB` | `REAL` | IN | — | EU | 通道 A / B 测量值 / Channel values |
| `bChannelAValid` / `bChannelBValid` | `BOOL` | IN | `TRUE` | — | 通道健康（无断线、无超量程）/ Channel health |
| `fDeviationLimit` | `REAL` | IN | `1.0` | EU | 偏差限，合法域 > 0，下限钳到 1E-6 / Deviation limit |
| `tDeviationDelay` | `TIME` | IN | `T#2S` | s | 偏差确认延时，T#0S = 立即确认 / Confirmation delay |
| `ePreferred` | `E_DL_RedundancyPriority` | IN | `eAuto` | — | 首选通道：`eAuto` / `eForceA` / `eForceB` / Preferred channel |
| `eDevPolicy` | `E_DL_DeviationPolicy` | IN | `eHoldLast` | — | 偏差处置：`eHoldLast` / `eUseA` / `eUseB` / `eFault` / Deviation policy |
| `tSwitchDwell` | `TIME` | IN | `T#500MS` | ms | 切换后抑制再次切换的停留时间，上限 1 h / Post-switch dwell |
| `fMaxSlewRate` | `REAL` | IN | `0.0` | EU/s | 无扰过渡最大变化率，**0 = 直接切换**（不是禁用）/ Max slew, 0 = direct switch |
| `uDeltaTimeMs` | `UDINT` | IN | — | ms | 调用方注入扫描间隔 / Injected scan delta |
| `fSafeValue` | `REAL` | IN | `0.0` | EU | 双通道失效时的安全值 / Safe value |
| `bReset` | `BOOL` | IN | — | — | 上升沿复位锁存故障与偏差报警 / Reset latched faults |
| `fSelected` | `REAL` | OUT | — | EU | 选择后输出 / Selected output |
| `eActive` | `E_DL_ActiveChannel` | OUT | — | — | 当前生效通道 `eNone(0)` / `eA(1)` / `eB(2)` / Active channel |
| `bOutputValid` | `BOOL` | OUT | — | — | 输出有效（非安全值替代）/ Output valid |
| `fDeviation` | `REAL` | OUT | — | EU | 当前偏差 \|A−B\|，单通道时恒为 0 / Current deviation |
| `bDeviationAlarm` | `BOOL` | OUT | — | — | 偏差报警（确认后保持到回落或复位）/ Deviation alarm, latched |
| `bRamping` / `uSwitchCount` | `BOOL` / `UDINT` | OUT | — | — | 过渡进行中 / 累计切换次数（饱和）/ Ramping / switch count |
| `bError` / `uErrorId` | `BOOL` / `UDINT` | OUT | — | — | 故障标志与故障码（锁存）/ Fault flag and code |
| `eState` | `E_DL_RedundState` | OUT | — | — | `eInit(0)` / `eNormal(10)` / `eSuspect(20)` / `eRamping(30)` / `eFault(99)` / State |

### 19.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 偏差限越界已钳位 / Deviation limit clamped | 检查参数来源 |
| `16#0001_0005` | 状态机非法状态 / Illegal state hit | 断电重启并上报 |
| `16#0001_0007` | 切换计数饱和 / Switch count saturated | 达 `16#FFFF_FFFE` 停增 |
| `16#0001_0008` | 时间增量无效（0 或 > 60000 ms）已钳位 / Invalid scan delta | 检查注入代码 |
| `16#0002_0005` | **无可用通道**（双失效 / `eDevPolicy = eFault` 且矛盾）/ No usable source | 输出安全值；复位需至少一路恢复有效 |
| `16#0002_0006` | **切换抖振锁定**（10 s 窗口内切换 > 5 次）/ Chatter latched | 设定错误或信号在临界点抖动；排除后复位 |

### 19.3 调用示例 / Example

```iecst
VAR
    fbRedun  : FB_DL_RedundantSwitch;    // 双温度传感器冗余 / Dual-sensor redundancy
    fTempA   : REAL;                     // A 传感器 [degC] / Sensor A
    fTempB   : REAL;                     // B 传感器 [degC] / Sensor B
    bValidA  : BOOL;
    bValidB  : BOOL;
END_VAR

fbRedun(
    fChannelA       := fTempA,
    fChannelB       := fTempB,
    bChannelAValid  := bValidA,
    bChannelBValid  := bValidB,
    fDeviationLimit := 2.0,              // 容差 2 degC / 2 degC tolerance
    tDeviationDelay := T#2S,
    fMaxSlewRate    := 5.0,              // 5 degC/s 无扰过渡 / bumpless at 5 degC/s
    uDeltaTimeMs    := uTaskDelta,
    fSafeValue      := 25.0,             // 双失效安全值 / safe fallback
    bReset          := bFaultReset );

fTempUsed := fbRedun.fSelected;
```

### 19.4 联调要点 / Commissioning Notes

- **`eHoldLast` 是默认策略且不可静默覆盖**：偏差确认后输出冻结在最后有效值并报警，等工程师到现场。若现场表现为「输出不动」，先查 `eState = eSuspect` 与 `bDeviationAlarm`，不要盲目改策略。
- **`fMaxSlewRate = 0` = 直接切换**：现场若按「0 = 禁用」理解会误判切换失效；无扰过渡必须给正值速率。
- **过渡期间目标值每拍刷新**：目标通道物理值仍在变化，块内不会爬向陈旧值；过渡途中目标失效则中止并退回，不计第二次切换。
- **抖振判据**：10 s 窗口内切换次数 > 5 即锁定故障——切换频繁通常是偏差限设得太小或信号在临界点抖动。
- **本块不做 NaN/Inf 检测**（刻意失真）：通道含 NaN 会污染输出，调用方必须前置量程与断线校验。

---

## 20. FB_DL_DutyStandbyRotation ｜ 多泵主备轮值调度

**定位**：8 台泵 / 风机 / 压缩机的主备轮值与均衡调度。按累计运行时间排序分配「需求台数」；周期性把领机降为备机；故障机立即跳过并越权停机；每台机受最小运行时长与最小停机时长双重保护。解决「永远只跑 1 号泵、2 号泵锈死」与「轮值切得太勤、接触器半年一换」两类对立顽疾。

### 20.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `abUnitReady` | `ARRAY[0..7] OF BOOL` | IN | — | — | 机组就绪（无故障、无就地、无禁止）/ Unit ready |
| `abUnitRunning` | `ARRAY[0..7] OF BOOL` | IN | — | — | 运行反馈（接触器辅助触点或流量开关），**命令-反馈分离，调度只认反馈** / Running feedback |
| `abUnitFault` | `ARRAY[0..7] OF BOOL` | IN | — | — | 机组故障（跳过并允许立即停机）/ Unit fault |
| `nDemand` | `INT` | IN | `0` | 台 | 需求运行台数，合法域 0..8，越界钳位 / Required count, 0..8 |
| `bEnable` | `BOOL` | IN | `TRUE` | — | 使能，FALSE 时命令全撤（运行时间账继续累加）/ Enable |
| `uDeltaTimeMs` | `UDINT` | IN | — | ms | 调用方注入扫描间隔 / Injected scan delta |
| `tMinRunTime` | `TIME` | IN | `T#10M` | min | 最小连续运行时长，防刚启就停 / Minimum run time |
| `tMinStopTime` | `TIME` | IN | `T#5M` | min | 最小停机时长，防接触器高频动作 / Minimum stop time |
| `tRotateInterval` | `TIME` | IN | `T#24H` | h | 轮值周期，合法域 1 s..8760 h / Rotation interval |
| `bForceRotate` | `BOOL` | IN | — | — | 上升沿请求立即轮值（仍受最小时长约束）/ Force one rotation |
| `bReset` | `BOOL` | IN | — | — | 上升沿复位参数冲突**并清零运行时间账** / Reset clears config fault and runtimes |
| `abStartCmd` | `ARRAY[0..7] OF BOOL` | OUT | — | — | 启动命令（cmd 语义，FALSE = 停）/ Start command per unit |
| `anRank` | `ARRAY[0..7] OF INT` | OUT | — | — | 本轮优先顺序，0 = 最高 / Priority rank |
| `nLeadUnit` | `INT` | OUT | — | — | 领机号 0..7，-1 = 无 / Lead unit |
| `afRuntimeHours` | `ARRAY[0..7] OF LREAL` | OUT | — | h | 累计运行小时（轮值依据）/ Accumulated runtime |
| `abBlockedByMinRun` / `abBlockedByMinStop` | `ARRAY[0..7] OF BOOL` | OUT | — | — | 因最小运行 / 停机时长被阻止停机 / 启动 / Stop / start blocked flags |
| `auStartCount` | `ARRAY[0..7] OF UDINT` | OUT | — | 次 | 各机启动次数（饱和）/ Start count per unit |
| `bRotatePending` / `bNoAvailableUnit` | `BOOL` | OUT | — | — | 轮值挂起中 / 无可用机组（瞬时）/ Rotation pending / no unit |
| `uRotateCount` | `UDINT` | OUT | — | 次 | 已完成轮值次数（饱和）/ Completed rotations |
| `bError` / `uErrorId` | `BOOL` / `UDINT` | OUT | — | — | 故障标志与故障码 / Fault flag and code |
| `eState` | `E_DL_RotationState` | OUT | — | — | `eIdle(0)` / `eRunning(10)` / `eRotatePending(20)` / `eFault(99)` / State |

### 20.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 时间参数越界已钳位（轮值周期 1 s..8760 h）/ Time parameter clamped | 检查参数来源 |
| `16#0001_0005` | 状态机非法状态 / Illegal state hit | 断电重启并上报 |
| `16#0001_0007` | 计数器饱和 / Counter saturation | 达 `16#FFFF_FFFE` 停增 |
| `16#0001_0008` | 时间增量无效（0 或 > 60000 ms）已钳位 / Invalid scan delta | 检查注入代码 |

### 20.3 调用示例 / Example

```iecst
VAR RETAIN
    fbDuty : FB_DL_DutyStandbyRotation;  // 运行时间账建议 RETAIN / runtime account RETAIN recommended
END_VAR

fbDuty(
    abUnitReady     := abPumpsReady,     // 8 台泵就绪位 / 8 pump ready bits
    abUnitRunning   := abPumpsRunFb,     // 接触器辅助触点反馈 / contactor feedback
    abUnitFault     := abPumpsFault,
    nDemand         := 2,                // 需求 2 台在运行 / 2 units required
    uDeltaTimeMs    := uTaskDelta,
    tMinRunTime     := T#10M,
    tMinStopTime    := T#5M,
    tRotateInterval := T#24H,            // 每 24 h 轮值一次 / rotate daily
    bForceRotate    := bRotateBtn,
    bReset          := bFaultReset );

abPumpStartCmd := fbDuty.abStartCmd;     // 命令侧，反馈侧只读 / cmd side only
```

### 20.4 联调要点 / Commissioning Notes

- **命令-反馈分离是硬纪律**：块只发命令（FALSE = 停），运行状态一律以 `abUnitRunning` 反馈为准；把命令回环接进反馈会破坏「先启后停」判定。
- **先启后停**：停机放行条件是「目标集中已在运行的台数 ≥ 需求台数」，比「在运行台数 ≥ 需求」更严——换机场景下不会出现压力/流量掉一拍。
- **无可用机组时绝不全停**：需求 > 0 且可用 = 0 时冻结全部停机（可能只是「就绪」信号被就地/检修摘掉），停掉正在供压的泵比少启一台危险。
- **运行时间账保持策略必须显式选择**：不 RETAIN 则每次上电从 0 号机开始轮；RETAIN 后轮值顺序跨班次延续。
- **复位清账要慎重**：参数冲突故障的复位沿会清零运行时间账（等同重置最小时长约束），复位前确认机组处于稳定工况。

---

## 21. FC_DL_DayOfWeekCalc ｜ 星期几换算（R5 补强）

**定位**：年月日 → 星期几换算原子函数，ISO-8601 序（周一=1 … 周日=7，与 GB/T 7408、MES 排产惯例一致）；Sakamoto 公开算法 clean-room，纯整数分段计算，无浮点无循环。

### 21.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uYear` | `UINT` | IN | 年份 [年]，有效域 1980..2099，越界返回 `eInvalid` / Year, 1980..2099 |
| `uMonth` | `USINT` | IN | 月 [月]，有效域 1..12 / Month |
| `uDay` | `USINT` | IN | 日 [日]，1..当月天数（含闰年 2 月 29 日）/ Day incl. leap-year rules |
| 返回值 | `E_DL_Weekday` | RETURN | 星期几（ISO-8601 序），越界返回 `eInvalid(0)` / Day of week |
| `uErrorId` | `UDINT` | OUT | `16#0001_0201` 日期参数越界（信息级）；0=合法 / Date out of range |

> 枚举 `E_DL_Weekday`（随本文件发布）：`eInvalid=0 / eMonday=1 … eSunday=7`。

### 21.2 调用示例 / Call Example

```iecst
VAR
    eWd : E_DL_Weekday;
    uErr : UDINT;
END_VAR
eWd := FC_DL_DayOfWeekCalc(uYear := 2026, uMonth := 11, uDay := 15, uErrorId => uErr);
// 2026-11-15 → eSunday(7)，uErr = 0 / 2026-11-15 is Sunday(7)
IF uErr <> 0 THEN ; END_IF  // 越界日期，eWd = eInvalid(0) / Out-of-range date
```

---

## 22. FB_DL_TimeWindowCheck ｜ 每日时间窗判定（R5 补强）

**定位**：每日时间窗单一语义判定块（不做 MODE 巨无霸）：判定 = 本日使能 AND 星期表当日位 AND 时刻窗；支持跨零点窗（22:00→06:00）与开=关 24h 全开语义；窗口开/闭沿单发；时刻/星期引脚注入禁读 CPU 钟（公约 0.9），典型与 `FC_DL_DayOfWeekCalc` 输出直连。

### 22.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uHourNow` | `USINT` | IN | 当前时刻-时 [h] 0..23，越界按不在窗处理 / Injected hour |
| `uMinNow` | `USINT` | IN | 当前时刻-分 [min] 0..59 / Injected minute |
| `bEnableDay` | `BOOL` | IN | 本日窗总使能，FALSE 恒不在窗 / Day window enable |
| `aWeekdayEnable` | `ARRAY[1..7] OF BOOL` | IN | 周一~周日各日使能表，索引 1=周一（ISO 序）/ Weekday enable table |
| `uWeekdayNow` | `USINT` | IN | 当前星期注入 1=周一..7=周日，越界不读表（R11 偏离 D1 新增）/ Injected weekday |
| `uHourOn` / `uMinOn` | `USINT` | IN | 窗口开启时刻，越界钳位后照算 / Window on time |
| `uHourOff` / `uMinOff` | `USINT` | IN | 窗口关闭时刻，支持跨零点 / Window off time, midnight-crossing supported |
| `bReset` | `BOOL` | IN | 上升沿清除当拍信息级码并重新评估（R11 偏离 D2）/ Reset edge clears info codes |
| `bInWindow` | `BOOL` | OUT | 当前处于窗口内 / In window |
| `bPulseOnWindowOpen` | `BOOL` | OUT | 窗口开启沿单发，TRUE 持续一拍 / Window open edge pulse |
| `bPulseOnWindowClose` | `BOOL` | OUT | 窗口关闭沿单发 / Window close edge pulse |
| `uErrorId` | `UDINT` | OUT | `16#0001_0202` 时刻/星期参数越界（信息级：当前时刻越界按 FALSE、窗口参数越界钳位照算）；0=无 / Out-of-range info code |

### 22.2 调用示例 / Call Example

```iecst
VAR
    fbWin : FB_DL_TimeWindowCheck;       // 时间窗实例 / Time-window instance
    aDays : ARRAY[1..7] OF BOOL := [TRUE,TRUE,TRUE,TRUE,TRUE,FALSE,FALSE]; // 工作日 / Weekdays
END_VAR
fbWin(uHourNow := uClockHour, uMinNow := uClockMin,   // 引脚注入，禁读 CPU 钟 / Injected time
      bEnableDay := TRUE, aWeekdayEnable := aDays,
      uWeekdayNow := UDINT_TO_USINT(eWd),             // 直连 DayOfWeekCalc / Chained
      uHourOn := 8, uMinOn := 0, uHourOff := 22, uMinOff := 0);
xBlowerRun := fbWin.bInWindow;                        // 风机时段输出 / Window output
IF fbWin.bPulseOnWindowOpen THEN bStartSeq := TRUE; END_IF  // 开窗沿一次触发 / Open edge
```

---

## 23. FB_DL_EventCounter ｜ 双向事件计数器（R7，v1.0.1）

**功能**：DINT 域双向事件计数。递增/递减脉冲沿独立计数，双脉冲同拍抵消（净变化 0，信息级）；预置装载 `bLoad` 沿优先级最高（同拍覆盖计数脉冲，信息级）；高/低阈值比较输出每拍重算非锁存；越界支持回绕（越过 nMax 回 nMin）/饱和（钳位 + 一拍溢出事件）双模式；参数非法（nMin ≥ nMax）故障锁存，计数值冻结；复位沿清零计数与故障。与 `FC_DL_BitCount`（位统计）、`FB_DL_RuntimeMeter`（时间累计）职责分离。

**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop（仅依赖 `Standard.library` R_TRIG）

### 23.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bCntUp` | BOOL | 输入 | — | — | 递增计数脉冲，R_TRIG 上升沿 +1 |
| `bCntDown` | BOOL | 输入 | — | — | 递减计数脉冲，R_TRIG 上升沿 -1 |
| `bLoad` | BOOL | 输入 | — | — | 预置装载指令，上升沿把 nPreset 写入计数值 |
| `nPreset` | DINT | 输入 | — | - | 预置值，任意 DINT 域 |
| `bWrap` | BOOL | 输入 | — | — | TRUE=上溢回 nMin/nMax 循环；FALSE=饱和钳位 |
| `nMin` | DINT | 输入 | -2147483648 | - | 计数下限，默认 DINT 域下界 |
| `nMax` | DINT | 输入 | 2147483647 | - | 计数上限，默认 DINT 域上界 |
| `nCompHigh` | DINT | 输入 | — | - | 高阈值，`bCompHigh` 判据 nCount >= nCompHigh |
| `nCompLow` | DINT | 输入 | — | - | 低阈值，`bCompLow` 判据 nCount <= nCompLow |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障与清零计数值 |
| `nCount` | DINT | 输出 | — | - | 当前计数值 |
| `bCompHigh` / `bCompLow` | BOOL | 输出 | — | — | 高/低阈值比较结果，每拍重算非锁存 |
| `bOverflow` / `bUnderflow` | BOOL | 输出 | — | — | 上溢/下溢事件标志，本拍置位一拍 |
| `bFault` / `uErrorId` | BOOL / UDINT | 输出 | — | — | 故障标志（显式排除信息级）/ 故障码 `16#0001_xxxx` 段 |

### 23.2 故障码表 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0001_0101` | 信息级 | 双脉冲同拍抵消（净变化 0） |
| `16#0001_0102` | 信息级 | 装载覆盖计数（bLoad 优先级最高） |
| `16#0001_0210` | 故障级 | 计数下限 ≥ 上限（锁存，仅复位路径清码） |

### 23.3 调用示例 / Example

```iecst
fbCnt(bCntUp := bSensorPulse, bCntDown := bRejectPulse,
      bWrap := TRUE, nMin := 0, nMax := 999,
      nCompHigh := 900, bReset := bBtnReset);
IF fbCnt.bCompHigh THEN bTrayAlmostFull := TRUE; END_IF
```

### 23.4 要点 / Notes

- **DINT 极值先判界后运算**（v1.0.1）：nCount 已达 nMax 直接走越界语义，杜绝 +1 回绕为负后 `> nMax` 判据失效；复位拍最高优先，同拍计数/装载脉冲被覆盖。
- 阈值比较是「>= / <=」判据语义（注释写死）；事件标志为一拍脉冲不锁存。

---

## 24. FB_DL_ModuloCounter ｜ 取模工位索引计数器（R7）

**功能**：转盘/弹夹工位索引循环计数。0..(nMod-1) 取模回绕（条件加减法实现，禁用取余运算符对负数的平台差异——DINT 域运算后显式转回 UINT，三平台行为一致）；支持双向步进、带合法性校验的跳步（目标越界拒绝置信级）、双向同拍抵消、跨零点回绕事件一拍；模数 <2 故障锁存。

**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop（仅依赖 `Standard.library` R_TRIG）

### 24.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bStepFwd` | BOOL | 输入 | — | — | 前进步进脉冲，R_TRIG 上升沿 +1 取模 |
| `bStepRev` | BOOL | 输入 | — | — | 后退步进脉冲，R_TRIG 上升沿 -1 取模 |
| `bJump` | BOOL | 输入 | — | — | 跳步指令，上升沿装载 nJumpTo（带合法性校验） |
| `nJumpTo` | UINT | 输入 | — | - | 跳步目标工位号，域 0..nMod-1，越界拒绝 |
| `nMod` | UINT | 输入 | 8 | - | 循环模数（工位数），域 2..65535，禁止 0/1 |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障与清零 |
| `uIndex` | UINT | 输出 | — | - | 当前工位索引，0..nMod-1 |
| `bWrapped` | BOOL | 输出 | — | — | 回绕事件标志，跨零点步进置位一拍 |
| `bFault` / `uErrorId` | BOOL / UDINT | 输出 | — | — | 故障标志 / 故障码 `16#0001_xxxx` 段 |

### 24.2 故障码表 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0001_0103` | 信息级 | 跳步目标越界拒绝（索引保持） |
| `16#0001_0104` | 信息级 | 双向步进同拍抵消（索引不变） |
| `16#0001_0211` | 故障级 | 模数非法 nMod < 2（锁存，仅复位路径清码） |

### 24.3 调用示例 / Example

```iecst
fbIdx(bStepFwd := fbTrigSensor.Q, nMod := 8,
      bJump := bCmdGoto, nJumpTo := 5, bReset := bBtnReset);
IF fbIdx.bWrapped THEN bLapComplete := TRUE; END_IF   // 转盘单圈计数
```

### 24.4 要点 / Notes

- 回绕用条件加减法（减 nMod / 加 nMod）而非 MOD 运算符——负数取余在三平台行为不一致，跨平台意图在头注释留档。
- 故障期索引输出安全零；`bWrapped` 是转盘单圈计数的标准事件源。

---

## 25. 故障码总表 / Error Code Table

| ErrorID | 含义 / Meaning | 本子库适用组件 / Components |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | 全部 |
| `16#0001_0001` | 参数越界（位索引 / 位宽 / 延时 / 预设 / 周期 / 占空比 / 优先级 / 步超时 / 心跳窗 / 同步窗）/ Parameter out of range | SignalDebounce、BitGet、BitSet、Gray×2、ExtendedTimer、AlarmManager、StepSequencer、PulseGenerator、WatchdogMonitor、RuntimeMeter、TwoHandSafety、InterlockMatrix、RedundantSwitch、DutyStandbyRotation |
| `16#0001_0002` | 量程 / 分母为零或近零 / Span or denominator near zero | （DL_MathData） |
| `16#0001_0003` | 参数符号非法（负宽度 / 负量程）/ Illegal sign | （DL_MathData） |
| `16#0001_0004` | 循环保护触发 / Loop guard tripped | BitCount |
| `16#0001_0005` | 状态机进入非法状态 / Illegal state hit | SignalDebounce、ExtendedTimer、StepSequencer、WatchdogMonitor、PulseGenerator、TwoHandSafety、InterlockMatrix、RedundantSwitch、DutyStandbyRotation |
| `16#0001_0006` | 输入数据非法（NaN / Inf）/ Invalid input data | （DL_MathData，预留） |
| `16#0001_0007` | 数值溢出或计数饱和 / Overflow or counter saturation | DualEdgeTrig、UnpackWordToBits、AlarmManager、WatchdogMonitor、CycleTimeMeasure、RuntimeMeter、TwoHandSafety、InterlockMatrix、RedundantSwitch、DutyStandbyRotation |
| `16#0001_0008` | 输入数据非法（负/零时间增量、心跳跳变过快）/ Invalid input data | WatchdogMonitor、CycleTimeMeasure、RuntimeMeter、RedundantSwitch、DutyStandbyRotation |
| `16#0001_0009` | 缓冲区满，写入被拒绝 / Buffer full, write rejected | （DL_MathData: RingBufferLReal） |
| `16#0001_000A` | 缓冲区空，读取被拒绝 / Buffer empty, read rejected | （DL_MathData: RingBufferLReal） |
| `16#0001_000B` | 顺控步超时故障 / Step timeout | StepSequencer |
| `16#0001_000C` | 心跳超时（看门狗触发锁定）/ Heartbeat timeout | WatchdogMonitor |
| `16#0001_000D` | 拆分字段数超缓冲，结果被截断 / Fields truncated | （DL_MathData: StringSplit） |
| `16#0001_000E` | 输入模式 / 枚举值非法 / Invalid mode or enum value | ExtendedTimer、WatchdogMonitor（继承）、（DL_MathData: SwapBytes32） |
| `16#0002_0001` | 双手同步超时 / Two-hand sync timeout | TwoHandSafety |
| `16#0002_0002` | 双手释放不同步 / Two-hand release desynchronised | TwoHandSafety |
| `16#0002_0003` | 旁路嫌疑：按钮卡死 / Bypass suspicion: button stuck | TwoHandSafety |
| `16#0002_0004` | 联锁配置非法（无停机级通道）/ Interlock config invalid | InterlockMatrix |
| `16#0002_0005` | 冗余无可用通道 / Redundancy: no usable source | RedundantSwitch |
| `16#0002_0006` | 冗余切换抖振锁定 / Redundancy chatter latched | RedundantSwitch |
| `16#0001_0101` | 双脉冲同拍抵消（信息级，净变化 0）/ Dual-pulse cancellation (info) | EventCounter |
| `16#0001_0102` | 装载覆盖计数（信息级）/ Load overrides counting (info) | EventCounter |
| `16#0001_0103` | 跳步目标越界拒绝（信息级）/ Jump target rejected (info) | ModuloCounter |
| `16#0001_0104` | 双向步进同拍抵消（信息级）/ Dual-step cancellation (info) | ModuloCounter |
| `16#0001_0210` | 计数下限 ≥ 上限（故障级锁存）/ Count lower >= upper (fault) | EventCounter |
| `16#0001_0211` | 模数非法 nMod < 2（故障级锁存）/ Invalid modulo (fault) | ModuloCounter |

> `16#0002_xxxx` 为 v1.2.0 新启用的故障码段（业务/工艺类语义），与 `16#0001_xxxx` 参数/循环段并行分配，全库登记于 `LIBRARY_MANUAL.md` 第四节。

---

## 26. 红线自检结论 / Redline Conformance

| 红线 / Rule | 判定 | 说明 / Note |
|---|---|---|
| R1 零全局变量表与外部变量引用 | PASS | 20 个 `.st` 全文机检 0 命中 |
| R2 零物理 IO 地址直写 | PASS | 0 命中 |
| R3 纯 IEC 61131-3 | PASS | 无指针、无引用传参关键字、无厂商专有对象、无点号位访问、显式类型转换 |
| R4 防除零 / 防越界 / 浮点容差 | PASS | 位索引与步号先判后算；`WHILE`/`FOR` 带防死锁或常量上界；数组下标双检 |
| R5 中英双语同行注释 | PASS | 声明行 100% 双语带单位 |
| R6 状态机 ENUM + CASE + ELSE | PASS | SignalDebounce / ExtendedTimer / StepSequencer / WatchdogMonitor / PulseGenerator 五态齐全；AlarmManager 等标注 N/A 并说明 |
| R7 定时器 / 边沿无条件刷新 | PASS | 全部 `TON` / `R_TRIG` / `F_TRIG` 实例位于主体最前部（StepSequencer 五实例、ExtendedTimer 四实例） |
| R8 无魔法数 | PASS | 步数、超时上限、窗口上限、周期上下限全部常量化 |
| R9 声明行三要素 | PASS | 物理意义 + 英文术语 + 单位，逐行齐全 |
| R10 语义描述式自检 | PASS | 头注释不引用被禁符号，机检不自伤 |
| R11 偏离留档 | PASS | WatchdogMonitor 依赖收窄、ExtendedTimer 复位沿实例增补均在头注释留档 |
| R12 验收向量可复算 | PASS | PulseGenerator 相位时长、DualEdgeTrig 计数序列已构造输入复算 |
| R13 POU 终结符成对 / Terminator pairing | PASS | v1.2.0 库级补全后 20 个 `.st` 全部含 `END_FUNCTION` / `END_FUNCTION_BLOCK`（见 `VERSION.md` v1.2.0 Fixed 节） |

---

## 27. FB_DL_ToleranceWindow ｜ 公差窗口三态判定（R9，v1.0.1）

**定位 / Positioning**：目标值 ± 公差带三态判定（合格 / 低于下差 / 高于上差），带可配置迟滞回差防临界抖动，输出双向越差单拍告警。面向压装深度、定位停位精度、温控点位偏差分档等质检 / 定位容差窗场景。

**与同类组件选型 / Selection**：分档选本块（三态分类 + 方向信息）；回路通断控制选 `FC_DL_Hysteresis`（二值迟滞）；显示净化选 `FC_DL_Deadband`（死区抑制）——三块互不替代。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 电平使能，FALSE 输出回安全态 eUnKnown / Level enable, FALSE returns to safe state |
| `fTarget` | LREAL | IN | 目标值 [工程单位随应用] / Target value [EU by application] |
| `fActual` | LREAL | IN | 实际值 [工程单位随应用] / Actual value [EU by application] |
| `fTolerance` | LREAL | IN | 公差半带宽（图纸 ±0.5 填 0.5），必须 > 0 / Half tolerance band, must be positive |
| `fHysteresis` | LREAL | IN | 迟滞回差，自动钳位 0..半带宽 / Hysteresis band, clamped to 0..half band |
| `eJudge` | E_DL_TolJudge | OUT | 三态判定（保持型）：eUnKnown(0)/eOk(1)/eLowOut(2)/eHighOut(3) / Three-state judgement, held |
| `bOk` | BOOL | OUT | 合格位（保持型，可参与联锁） / In-tolerance flag, held |
| `bLowOut` | BOOL | OUT | 低于下差（保持型）/ Below lower deviation, held |
| `bHighOut` | BOOL | OUT | 高于上差（保持型）/ Above upper deviation, held |
| `bDeviation` | BOOL | OUT | 越窗事件（单拍脉冲，从合格迁出到越差） / Deviation event, one-scan pulse |
| `uErrorId` | UDINT | OUT | 故障码：0001_0112 回差越界钳位（信息级）/ 0001_0213 公差带宽非法（故障级锁 eUnKnown） / Error code |

### 调用示例 / Example

```iecst
VAR
    fbPosWin : FB_DL_ToleranceWindow;   // 定位停位精度窗实例 / Positioning tolerance window instance
    bInTol   : BOOL;                    // 合格位（参与联锁）/ In-tolerance flag for interlock
END_VAR

// 每周期无条件调用；公差按图纸单边带宽组态 / Called unconditionally every scan
fbPosWin(bEnable := bAtPositionCheck, fTarget := 120.0,
         fActual := fAxisPos, fTolerance := 0.5, fHysteresis := 0.05);

IF fbPosWin.bDeviation THEN
    // 单拍事件：从合格迁出到越差，触发复检登记 / One-scan event: leave ok state
END_IF
bInTol := fbPosWin.bOk;                 // 保持型合格位 / Held in-tolerance flag
```

**要点 / Notes**：迟滞语义为「进窗阈窄（|偏差| <= 公差）、出窗阈宽（> 公差 + 回差）」，回差带内保持原态；`bOk` 参与联锁建议串入 `uErrorId = 0` 条件（失效导向安全）；动作类响应用保持型 `bLowOut/bHighOut`，勿用单拍 `bDeviation` 直接驱动执行器。O-09：跨侧直跳（-0.6 → +0.6）需经 eOk 中转一拍，属迟滞语义推论非缺陷。

---

## 28. FC_DL_LimitClassify ｜ 四阈值五档限值分档（R9，v1.0.1）

**定位 / Positioning**：下限 / 下警告 / 上警告 / 上限四阈值五档判定（低低 / 低 / 正常 / 高 / 高高），非对称四级限值仪表分档。液位五档分级联锁、液压站压力分档告警、烘箱温度分区治理专用；与 ToleranceWindow（对称公差窗）职责分离。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| 返回值 / Return | E_DL_LimitBand | RET | 档位判定结果；阈值序非法恒为 eInvalid / Band verdict, eInvalid on illegal order |
| `fVal` | LREAL | IN | 被判定值 [工程单位随应用] / Value under test [EU] |
| `fLowLimit` | LREAL | IN | 低低限（停机级）/ Low-low limit (trip level) |
| `fLowWarn` | LREAL | IN | 低警告限 / Low warning limit |
| `fUpWarn` | LREAL | IN | 高警告限 / High warning limit |
| `fUpLimit` | LREAL | IN | 高高限（停机级）/ High-high limit (trip level) |
| `uErrorId` | UDINT | OUT | 故障码：0001_0214 阈值序非法（拒绝路径，禁止静默分档） / Error code |

枚举 `E_DL_LimitBand`：eLowTripped(0) / eLowWarn(1) / eNormal(2) / eUpWarn(3) / eUpTripped(4) / eInvalid(9)。

### 调用示例 / Example

```iecst
VAR
    eTankLevel : E_DL_LimitBand;        // 液位档位 / Tank level band
    nErr       : UDINT;                 // 诊断码 / Diagnostic code
END_VAR

eTankLevel := FC_DL_LimitClassify(fVal := fLevel,
                 fLowLimit := 10.0, fLowWarn := 20.0,
                 fUpWarn := 80.0, fUpLimit := 90.0, uErrorId => nErr);
IF nErr <> 0 THEN
    // 阈值组态非法：档位不可信（恒 eInvalid），走组态报警流程
END_IF
```

**要点 / Notes**：边界值闭区间归属——等于阈值归更严档（贴线即触发，仪表联锁安全侧惯例）；相邻阈值相等合法（档位退化），fLowWarn = fUpWarn = 50 时正常档为**空集**（v1.0.1 勘误，代码正确）；停机级两档 → 联锁 + 声光急告警，警告级两档 → 登记不联锁；档位枚举可直接驱动 `FB_DL_SignalTower` 分档显示。

---

## 29. FC_DL_WordBitPack ｜ WORD 位段参数化打包 / 解包（R9，v1.0.1）

**定位 / Positioning**：按位偏移 + 位宽参数把字段值合入目标字（打包），同拍经输出引脚回读该位段旧值（解包），一函数完成「读-改-写」原子语义。与 `FC_DL_PackBitsToWord` / `FB_DL_UnpackWordToBits`（16 点 BOOL 全字打包解包）职责分离——本块是任意位段参数化版本。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| 返回值 / Return | WORD | RET | 合成后的字；拒绝路径返回原字不动 / Assembled word; input unchanged on rejection |
| `uTarget` | WORD | IN | 目标载体字（旧内容）/ Target carrier word |
| `uField` | WORD | IN | 待合入字段值（右对齐，超出位宽的高位被忽略）/ Field value, right-aligned |
| `nOffset` | USINT | IN | 位段起始偏移 [bit]，合法域 0~15 / Field start offset [bit] |
| `nWidth` | USINT | IN | 位段宽度 [bit]，合法域 1~16 / Field width [bit] |
| `uExtracted` | WORD | OUT | 该位段旧值（右对齐回读，即解包结果）/ Extracted old field value |
| `uErrorId` | UDINT | OUT | 故障码：0001_0108 位段越界拒绝（宽度 0 / 宽度>16 / 偏移>=16 / 求和>16） / Error code |

### 调用示例 / Example

```iecst
VAR
    wStatus  : WORD;                    // 状态字（模式号在 bit4~7）/ Status word, mode in bits 4..7
    wOldMode : WORD;                    // 改动前的旧模式留档 / Previous mode archived
    uErr     : UDINT;                   // 诊断码 / Diagnostic code
END_VAR

// 把模式号 3 写入 bit4~bit7，同时留档旧模式 / Write mode 3 into bits 4..7
wStatus := FC_DL_WordBitPack(uTarget := wStatus, uField := 3,
                             nOffset := 4, nWidth := 4,
                             uExtracted => wOldMode, uErrorId => uErr);
```

**要点 / Notes**：v1.0.1 补齐四项单项判界——USINT 域 `15 + 250` 回绕为 9 可绕过「求和 > 16」原判界，随后 `SHL(1, 250)` 落入平台未定义行为；单项判界置于求和判界之前（验收 V7 固化）。宽度 16 走满宽度显式分支，全部移位计数严格小于 16，不触发平台移位方言。WordBitPack V5 验收向量经终审裁定计划表笔误（16#1264 → 16#12A4），实现零改动。

---

## 30. FB_DL_MonthWindowCheck ｜ 月度 / 年度时间窗判定（R9，v1.0.0）

**定位 / Positioning**：月内第 N 天 / 月末倒数第 N 天的日期窗判定（窗口宽度可配，跨月末不跨月截断），可选年度模式（仅指定月生效）——月度保养窗 / 月末盘点窗 / 年度大保养。与 `FB_DL_TimeWindowCheck`（日内时窗）正交；日期全部引脚注入，不读平台时钟。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE 输出复位 / Enable, FALSE resets outputs |
| `nYear` | DINT | IN | 当前年份 [公元年]，>= 1 / Current year [calendar year] |
| `nMonth` | DINT | IN | 当前月份 [月]，1~12 / Current month |
| `nDay` | DINT | IN | 当前日 [日]，1~当月天数 / Current day |
| `nTargetDay` | DINT | IN | 目标日：正 = 月内第 N 天（1~31），负 = 月末倒数第 N 天（-1~-31），0 非法 / Target day, positive or negative anchor |
| `nWindowDays` | DINT | IN | 窗口宽度 [日]，1~31，目标日起连续 n 天，越界钳位 / Window width in days |
| `bYearly` | BOOL | IN | TRUE = 年度窗：仅 nYearMonth 指定月生效 / Yearly window mode |
| `nYearMonth` | DINT | IN | 年度窗生效月份 [月]，1~12 / Yearly-window month |
| `bInWindow` | BOOL | OUT | 当前日在窗口内（保持型）/ Day in window, held |
| `bWindowOpen` | BOOL | OUT | 窗口开启单拍脉冲（R25 三律）/ Window-open one-scan pulse |
| `nDaysToTarget` | DINT | OUT | 窗口内 = 当前日 − 目标日（首日 0 递增），窗口外恒 -1 / Days offset, -1 outside |
| `uErrorId` | UDINT | OUT | 故障码：0001_0109 参数钳位（信息级）/ 0001_0203 日期参数非法 / Error code |

### 调用示例 / Example

```iecst
VAR
    fbMonthWin  : FB_DL_MonthWindowCheck;   // 月度保养窗实例 / Monthly maintenance window
    bMaintWin   : BOOL;                     // 窗口内标志 / In-window flag
    bWinOpen    : BOOL;                     // 开窗单拍 / Window-open pulse
    nToTarget   : DINT;                     // 窗口第 N 天 / Day offset in window
END_VAR

// 月末倒数第 3 天起开 5 天保养窗（仅 12 月生效）/ Last-3rd day, 5-day window, December only
fbMonthWin(bEnable := TRUE, nYear := 2026, nMonth := 12, nDay := nToday,
           nTargetDay := -3, nWindowDays := 5, bYearly := TRUE,
           nYearMonth := 12, bInWindow => bMaintWin, bWindowOpen => bWinOpen,
           nDaysToTarget => nToTarget, uErrorId => uWinErr);
```

**要点 / Notes**：月末倒数口径 = 月长 − |nTargetDay| + 1（倒数第 1 天 = 月末日），|nTargetDay| 超当月天数自动收缩（31 在 2 月钳到 28/29，置信息级）；窗口右端超月长截断到月末（口径而非错误）；年度模式非生效月直接 FALSE 且不置故障码；闰年独立实现（4/100/400 规则）。

---

## 31. FB_DL_PresetCounterSat ｜ 带饱和预设计数器（R9，v1.0.1）

**定位 / Positioning**：上/下双向计数，到达上限（nPreset）或下限（nLowLimit）**饱和不回绕**——批次计数 / 托盘满载场景回绕是危险行为，设计上直接删除该自由度。装载优先级最高；与 `FB_DL_EventCounter`（回绕 + 比较输出）、`FB_DL_ModuloCounter`（取模工位索引）职责分离。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bCountUp` | BOOL | IN | 上计数脉冲输入，上升沿 +1 / Count-up pulse, rising edge |
| `bCountDown` | BOOL | IN | 下计数脉冲输入，上升沿 -1 / Count-down pulse, rising edge |
| `bLoad` | BOOL | IN | 装载预设值（写 nPreset 现值），上升沿生效，优先级最高 / Load preset, highest priority |
| `nPreset` | DINT | IN | 上限预设值 [个]，默认 100，>= nLowLimit / Upper preset |
| `nLowLimit` | DINT | IN | 下限预设值 [个]，默认 0，<= nPreset / Lower preset |
| `bReset` | BOOL | IN | 复位到下限 + 故障解除，上升沿生效 / Reset to lower limit, rising edge |
| `nCount` | DINT | OUT | 当前计数值 [个]，饱和域 [nLowLimit, nPreset] / Current count, saturated |
| `bSatHigh` | BOOL | OUT | 已达上限饱和（保持型）/ At upper saturation, held |
| `bSatLow` | BOOL | OUT | 已达下限饱和（保持型）/ At lower saturation, held |
| `bDone` | BOOL | OUT | 计数到达上限（保持型）/ Upper limit reached, held |
| `bThreshold` | BOOL | OUT | 首次到达上限单拍脉冲（R25 三律）/ First-arrival one-scan pulse |
| `uErrorId` | UDINT | OUT | 故障码：0001_0212 nPreset < nLowLimit（锁存，仅复位沿解除） / Error code |

### 调用示例 / Example

```iecst
VAR
    fbPalletCnt : FB_DL_PresetCounterSat;   // 托盘满载计数实例 / Pallet full-count instance
    nPalletCount: DINT;                     // 当前计件数 / Current count
    bPalletFull : BOOL;                     // 满托保持位 / Pallet full flag
    bFullPulse  : BOOL;                     // 满托单拍（驱动打印/报文）/ One-scan full pulse
END_VAR

// 装满 100 件给满托信号，人工换托后复位 / 100 parts per pallet, reset on change
fbPalletCnt(bCountUp := bPartInFeed, bCountDown := bPartRejectOut,
            bLoad := FALSE, nPreset := 100, nLowLimit := 0,
            bReset := bPalletChanged,
            nCount => nPalletCount, bDone => bPalletFull,
            bThreshold => bFullPulse, uErrorId => uCntErr);
```

**要点 / Notes**：先判界后加减，DINT 极值 +1/-1 回绕从写法上根除；同拍双计数互相抵消不偏置；装载语义 = 「写入 nPreset 引脚现值」而非独立预置寄存器（O-10，与部分品牌直觉不同已在手册声明）；参数非法锁存解除前置条件 = 先修正参数再复位（同拍重锁，v1.0.1 勘误 C6 表述）；`bSatHigh` 与 `bDone` 判据相同但语义分层（停走状态 vs 任务完成），分开联锁。

---

## 32. FC_DL_BitFieldExtract ｜ DWORD 任意位段提取（R10，v1.0.0）

**定位 / Positioning**：按「偏移 + 宽度」从 DWORD 中取出任意位段，右对齐输出，同拍给出本次实际生效掩码。用于通信状态字 / 驱动器控制字 / 报警字中「某个字段在第几位、几位宽」的现场解读。与 `FC_DL_WordBitPack`（位段读-改-写）、`FC_DL_BitGet`（单 bit）、`FC_DL_PackBitsToWord` / `FB_DL_UnpackWordToBits`（16 点 BOOL 全字）四点正交。

**与同类组件选型 / Selection**：只读提取本件；需要写回同一字段选 `FC_DL_WordBitPack`；只需要单个 bit 选 `FC_DL_BitGet`（开销最小）；BOOL 数组 ↔ WORD 全字转换选 `FC_DL_PackBitsToWord` / `FB_DL_UnpackWordToBits`。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| 返回值 / Return | DWORD | RET | — | 提取结果，bit0 起 `nActualW` 位有效（右对齐）/ Extracted field, right-aligned from bit0 |
| `uSource` | DWORD | IN | — | 源字，任意 32 位值，不做符号解释 [位串] / Source word, raw 32-bit |
| `nOffset` | INT | IN | 0 | 位段起始偏移，0 = LSB，有效域 0~31 [bit] / Start bit offset, valid 0..31 |
| `nWidth` | INT | IN | 1 | 位段宽度，有效域 1~32 [bit] / Field width, valid 1..32 |
| `uField` | DWORD | OUT | — | 提取结果（与返回值同值，供 ST 调用形式直接读）/ Extracted field, same as return value |
| `uMask` | DWORD | OUT | — | 本次实际生效掩码，已右对齐，可直接与结果做位与 [位串] / Effective right-aligned mask |
| `nActualW` | INT | OUT | — | 实际生效宽度，越界截断后的值，1~32 [bit] / Effective width after truncation |
| `uErrorId` | UDINT | OUT | — | 事件码：`0001_0113` 偏移越界 / `0001_0114` 宽度越界 / `0001_0115` 跨字截断 / Event code |
| `bValid` | BOOL | OUT | — | 入参域全部合法 = TRUE；发生截断 = FALSE（结果仍可用）/ All inputs legal, FALSE means truncated |

### 调用示例 / Example

```iecst
VAR
    wDriveStatus : DWORD := 16#DEAD_BEEF;   // 驱动器状态字 / Drive status word
    wErrField    : DWORD;                   // 提取的错误子域 / Extracted error sub-field
    wMask        : DWORD;                   // 生效掩码 / Effective mask
    nWidthUsed   : INT;                     // 实际宽度 / Effective width
    bFieldOk     : BOOL;                    // 域合法 / Domain legal
    uExtractErr  : UDINT;                   // 事件码 / Event code
END_VAR

// 取 bit8 起 8 位（字节 1）/ Extract 8 bits starting at bit 8
wErrField := FC_DL_BitFieldExtract(uSource := wDriveStatus, nOffset := 8, nWidth := 8,
                                   uMask => wMask, nActualW => nWidthUsed,
                                   uErrorId => uExtractErr, bValid => bFieldOk);
// 结果 16#0000_00BE，掩码 16#0000_00FF
```

**要点 / Notes**：`nWidth = 32` 走 `16#FFFF_FFFF` 常量掩码分支，**从写法上规避 `SHL(x, 32)` 的跨平台未定义行为**（ARM/x86 结果不同，是三平台移植的经典坑）；`nWidth = 0` 与偏移/宽度越界双重拒绝（结果 0 + 置码）；`nOffset + nWidth > 32` 按可用位截断（`nActualW` 回读实际值），不静默给全 0。位序约定全库统一「索引 0 = LSB」。

---

## 33. FC_DL_WeekOfYearCalc ｜ ISO-8601 周数与归属年（R10，v1.0.0）

**定位 / Positioning**：年月日 → ISO-8601 的「周年 / 周序 / 周内日」，并把**跨年归属**写死为周四原则。MES 周报、按周排产、周保养窗、批次周编号的日期底座。与 `FC_DL_DayOfWeekCalc`（星期几，单值）互补：本件给出「第几周 + 属哪一年」。

**与同类组件选型 / Selection**：需要「第几周」本件；只判星期几用 `FC_DL_DayOfWeekCalc`（更轻）；需要「日期是否落在某个日期窗」用 `FB_DL_MonthWindowCheck` / `FB_DL_TimeWindowCheck`。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| 返回值 / Return | BOOL | RET | — | 入参域合法且可算 = TRUE；越界 = FALSE（输出全 0）/ Domain legal and computable |
| `nYear` | INT | IN | 2026 | 公历年，有效域 1970~2099 [年] / Calendar year, 1970..2099 |
| `nMonth` | INT | IN | 1 | 公历月，有效域 1~12 [月] / Calendar month, 1..12 |
| `nDay` | INT | IN | 1 | 公历日，有效域 1~该月天数 [日] / Day of month |
| `nIsoYear` | INT | OUT | — | ISO 周年，**可能不等于 `nYear`**（跨年归属所致）[年] / ISO week-numbering year |
| `nIsoWeek` | INT | OUT | — | ISO 周序号，1~53 [周] / ISO week number |
| `nIsoDow` | INT | OUT | — | ISO 周内日，周一 = 1，周日 = 7 [1~7] / ISO day of week |
| `nWeek53En` | BOOL | OUT | — | 该 ISO 周年是否含第 53 周（长年判据）[布尔] / TRUE if that ISO year is a 53-week year |
| `uErrorId` | UDINT | OUT | — | 事件码：`0001_0116` 年份越界 / `0001_0117` 月日非法（含平年 2/29）/ Event code |

### 调用示例 / Example

```iecst
VAR
    nWeekYear : INT;        // ISO 周年（可能跨年）/ ISO week-numbering year
    nWeekNo   : INT;        // 周序号 / Week number
    nDow      : INT;        // 周内日 1..7 / Day of week
    bLongYear : BOOL;       // 是否 53 周年 / 53-week year flag
    bWeekOk   : BOOL;       // 入参合法 / Inputs legal
    uWeekErr  : UDINT;      // 事件码 / Event code
END_VAR

bWeekOk := FC_DL_WeekOfYearCalc(nYear := nTodayYear, nMonth := nTodayMonth, nDay := nTodayDay,
                                nIsoYear => nWeekYear, nIsoWeek => nWeekNo,
                                nIsoDow => nDow, nWeek53En => bLongYear, uErrorId => uWeekErr);

// 跨年归属的经典情形：2021-01-01（周五）→ 周年 2020、第 53 周
// 2026-01-01（周四）→ 周年 2026、第 1 周
```

**要点 / Notes**：
- **算法**：Zeller 同余求星期（无查表、无浮点、无平台差异）+ 周四归属法判定归属年 + 序日差求周数；闰年 1/2 月做 31/30 折算前置。**规格速算式有两处硬错**（对 2026-01-01 得 3，实际为 4；未对闰年 1/2 月折算），本实现按「规格与正确性冲突以正确性为准 + 留档」处理，偏离说明与 V1~V5 向量写在该文件头 Deviations 段。
- **跨年归属是独立语义**：12-31 可能属次年第 1 周，1-1 可能属上年第 52/53 周，故 `nIsoYear` 必须与 `nYear` 分开取用，HMI 上不要默认两者相同。
- **周报口径**：`nWeek53En` 给出「该 ISO 周年是否长年」，用于周报统计的年度总周数校验（52 vs 53）。

---

## 34. FB_DL_BidirectionalCounter ｜ CTUD 全语义双向计数器（R10，v1.0.0）

**定位 / Positioning**：加 / 减 / 装载 / 复位四输入 + 上/下双预设的 DINT 双向计数器，饱和不回绕。覆盖 IEC CTUD 的完整语义域（含双预设与同时计数仲裁），批次计数、双向计米、上下限产量统计。

**与同类组件选型 / Selection**：需要回绕或「双模越界策略」选 `FB_DL_EventCounter`；需要取模工位索引选 `FB_DL_ModuloCounter`；需要「单预设 + 预设倒置冻结」选 `FB_DL_PresetCounterSat`；**本件 = CTUD 全语义 + 双预设 + 饱和 + 加优先仲裁**。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bCountUp` | BOOL | IN | — | 加计数输入，上升沿 +1 [−] / Count-up input, rising edge increments |
| `bCountDown` | BOOL | IN | — | 减计数输入，上升沿 −1；与加计数同拍时**加优先** [−] / Count-down input, up wins on the same scan |
| `bLoad` | BOOL | IN | — | 装载请求，上升沿装载，装载拍跳过计数 [−] / Load request, skips counting on that scan |
| `nLoadValue` | DINT | IN | 0 | 装载值，域 `DL_COUNT_MIN`~`DL_COUNT_MAX` [计数值] / Load value |
| `bReset` | BOOL | IN | — | 复位，电平有效：CV 归 0、清 QU/QD 与锁存 [−] / Reset, level active |
| `nPresetUp` | DINT | IN | 100 | 加预设 PV_UP，CV ≥ 此值时 `bQu` 为 TRUE [计数值] / Preset up |
| `nPresetDn` | DINT | IN | 0 | 减预设 PV_DN，CV ≤ 此值时 `bQd` 为 TRUE [计数值] / Preset down |
| `bEnable` | BOOL | IN | TRUE | 使能，FALSE 冻结计数并清 QU/QD，CV 保持 [−] / Enable |
| `nCv` | DINT | OUT | — | 当前计数值 CV，饱和域内不回绕 [计数值] / Current count value, saturated |
| `bQu` | BOOL | OUT | — | 加预设到达，**保持型**（CV ≥ PV_UP 期间持续为真）[−] / Up preset reached, holding |
| `bQd` | BOOL | OUT | — | 减预设到达，**保持型**（CV ≤ PV_DN 期间持续为真）[−] / Down preset reached, holding |
| `bAtMax` | BOOL | OUT | — | 已达上限饱和，再加 1 被拒 [−] / Upper saturation reached |
| `bAtMin` | BOOL | OUT | — | 已达下限饱和，再减 1 被拒 [−] / Lower saturation reached |
| `bUpPulse` | BOOL | OUT | — | 本次实际加计数成功，**单拍脉冲** [−] / Increment applied this cycle |
| `bDnPulse` | BOOL | OUT | — | 本次实际减计数成功，**单拍脉冲** [−] / Decrement applied this cycle |
| `bLoadDone` | BOOL | OUT | — | 装载完成，单拍脉冲 [−] / Load completed, one-scan pulse |
| `uErrorId` | UDINT | OUT | — | 事件码：`0001_0118` 装载值钳位（信息级）/ `0001_0215` 预设倒置（故障级）/ `0001_0216` 防御式默认码 / Event code |
| `bError` | BOOL | OUT | — | 故障锁存，仅故障级码置位，复位清除 [−] / Fault latch |

### 调用示例 / Example

```iecst
VAR
    fbMeter    : FB_DL_BidirectionalCounter;   // 双向计米实例 / Bidirectional metre counter
    nMetres    : DINT;                         // 净长度 [米] / Net metres
    nForward   : DINT;                         // 正向量 [米] / Forward metres
    nReverse   : DINT;                         // 反向量 [米] / Reverse metres
    bUpperHit  : BOOL;                         // 达上预设 / Upper preset reached
    bLocked    : BOOL;                         // 故障锁存 / Fault latch
END_VAR

// 每周期无条件调用；正转加、反转减，满 500 m 给一次「达上预设」保持位
fbMeter(bCountUp := bEncoderPulseFwd, bCountDown := bEncoderPulseRev,
        bLoad := bMetrePreset, nLoadValue := nPresetMetres,
        bReset := bShiftReset, nPresetUp := 500, nPresetDn := 0,
        bEnable := TRUE,
        nCv => nMetres, bQu => bUpperHit, bError => bLocked);

// 正向/反向分账（同拍双脉冲互相抵消，两路都不出脉冲）
IF fbMeter.bUpPulse THEN nForward := nForward + 1; END_IF
IF fbMeter.bDnPulse THEN nReverse := nReverse + 1; END_IF
```

**要点 / Notes**：
- **优先级链**：`bReset`（电平）> `bLoad`（上升沿）> 加/减计数；装载拍跳过计数（不叠加）；加/减同拍时**加优先**，并按「净变化一个步长」结算（两路 `bUpPulse`/`bDnPulse` 都不出）。
- **饱和语义（与 R7 EventCounter 的差别）**：本件**永不回绕**，到界即停并置 `bAtMax`/`bAtMin`；`DL_COUNT_MAX/MIN` 距 DINT 极值留 147 的安全裕度，使 `+1 / −1` 在任何路径都不会溢出。
- **`bAtMax` 三律（R27 输出保持）**：每拍先清零 → 命中置位 → 保持态每拍重写；不要用单拍事件位判读饱和状态。
- **预设倒置**（PV_UP ≤ PV_DN）锁 `bError` 与 `0001_0215`，参数修正后复位解除；注意与 `FB_DL_PresetCounterSat` 的「倒置冻结」策略不同——本件是「锁故障 + 拒绝计数」，那里是「冻结但不断言故障」，两块手册均已写明，选型时按现场报警策略取舍。

---

## 35. FB_DL_YearWindowCheck ｜ 年粒度区间窗判定（R11，v1.0.0）

**定位 / Positioning**：判定「当前日期是否落在年度生效区间内」，是**年粒度**的第三级时间窗——与日内时刻窗（`FB_DL_TimeWindowCheck`）、月度日窗（`FB_DL_MonthWindowCheck`）构成「时分秒 / 日 / 年」三层，粒度互补而非替代。典型用途：采暖季/空调季放行、年度强制检定窗、汛期/旱季配方切换、年末库存冻结。

**跨年与按年重复 / Cross-year and repetition**：结束日早于起始日（同年比月日，或结束年小于起始年）即按**跨年窗**处理并自动补一个年度周期（如 11 月 1 日至次年 2 月末）；判定时把当前位置折叠到以窗起点为原点的单周期内，因此同一月日组合每年自动生效，多年度组态（2026 至 2031）**一次配置即可**，无需逐年填。跨度超过一个周期时钳到「整周期覆盖」（等价恒在窗内），属口径而非错误、不置码。

**日期口径 / Date basis**：整数日序数法——把日期折成「相对 2000 年 1 月 1 日的连续日数」，闰日累计用格里高利历公开定义（`(年−1)/4 − (年−1)/100 + (年−1)/400`），全部中间量为 `LINT`（2099 年序数约 3.6 万，绝无溢出）。相邻日之差即真实天数差，月末、年末、闰日由序数法自动对齐，**零浮点、零时间类型、不读平台时钟、不猜时区、不做夏令时换算**。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能；`FALSE` 时 `bInWindow` 强制 `FALSE`、状态回空闲、不输出脉冲 / Enable; FALSE forces the verdict low |
| `bReset` | BOOL | IN | — | — | 上升沿清组态非法态（**仅组态已修正时有效**）/ Rising edge clears the invalid state once fixed |
| `nYear` | INT | IN | — | 年 | 当前年，有效域 1970~2099，越界钳位照算 / Current year |
| `nMonth` | INT | IN | — | 月 | 当前月 1~12，越界钳位照算 / Current month |
| `nDay` | INT | IN | — | 日 | 当前日 1~31，超当月天数钳到月末照算 / Current day |
| `nStartYear` | INT | IN | — | 年 | 窗口起始年 1970~2099 / Window start year |
| `nStartMonth` | INT | IN | — | 月 | 窗口起始月 1~12 / Window start month |
| `nStartDay` | INT | IN | — | 日 | 窗口起始日 1~31 / Window start day |
| `nEndYear` | INT | IN | — | 年 | 窗口结束年 1970~2099 / Window end year |
| `nEndMonth` | INT | IN | — | 月 | 窗口结束月 1~12 / Window end month |
| `nEndDay` | INT | IN | — | 日 | 窗口结束日 1~31 / Window end day |
| `bIncludeEnd` | BOOL | IN | `TRUE` | — | 结束日是否含当天（`TRUE` = 闭区间）/ Include the end day |
| `bInWindow` | BOOL | OUT | — | — | 当前日在窗内，逐拍重算非锁存；失效态期间**宁可不开窗** / Today inside the window |
| `bEdgeOpen` | BOOL | OUT | — | — | 入窗单拍脉冲 / One-shot pulse on window entry |
| `bEdgeClose` | BOOL | OUT | — | — | 出窗单拍脉冲（离开窗口 / 入窗后失效 / 使能撤除三路均发）/ One-shot pulse on exit |
| `bInvalidConfig` | BOOL | OUT | — | — | 组态非法（归一后空窗），本拍按空窗处理 / Invalid configuration |
| `nDaysUntilEdge` | INT | OUT | — | 日 | 距下一次窗沿天数：窗内 = 距关沿，窗外 = 距开沿 / Days to the next edge |
| `eState` | E_DL_YearWinPhase | OUT | — | — | 主状态机态：`eIdle` 0 / `eOutWindow` 10 / `eInWindow` 20 / `eInvalid` 30 / Main phase |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无；本块**全部信息级**，不置报警位 / Event code, informational only |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_011E` | 信息级 | 日期参数越界已钳位照算（年 / 月 / 日越界，或折叠循环触顶），扫描不中断 | HMI 显示「日期被修正」；核对 HMI 年份写入是否被 16 位截断 |
| `0001_011F` | 信息级 | 窗口归一后为空（跨度小于零，如起止同日且不含尾），`bInvalidConfig` 置位 | 按空窗运行（不放行）；修正组态后给 `bReset` 上升沿退出 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_HeatSeasonWindow
VAR
    fbHeatWin          : FB_DL_YearWindowCheck;  // 采暖季年窗实例 / Heating-season window
    nHmiYear           : INT := 2026;            // HMI 注入年份 / Year from HMI
    nHmiMonth          : INT := 11;              // HMI 注入月份 / Month from HMI
    nHmiDay            : INT := 15;              // HMI 注入日 / Day from HMI
    bSystemRun         : BOOL := TRUE;           // 系统运行 / System running
    bCfgReset          : BOOL;                   // 组态修正后复位 / Reset after a config fix
    bHeatSeason        : BOOL;                   // 在采暖季内 / Inside the season
    bHeatOn            : BOOL;                   // 采暖季开始单拍 / Season start pulse
    bHeatOff           : BOOL;                   // 采暖季结束单拍 / Season end pulse
    nDaysToHeatEdge    : INT;                    // 距窗沿天数 / Days to the edge
    bHeatCfgBad        : BOOL;                   // 组态非法 / Bad configuration
    eHeatState         : E_DL_YearWinPhase;      // 状态观测 / Phase observation
    uHeatErr           : UDINT;                  // 事件码 / Event code
    bBoilerGroupEnable : BOOL := FALSE;          // 锅炉群控放行 / Boiler group permit
    bFrostOnlyMode     : BOOL := TRUE;           // 非采暖季防冻模式 / Frost-protection only
END_VAR

// 每周期无条件调用；三个日期全部由 HMI 注入，本块不读平台时钟
fbHeatWin(bEnable := bSystemRun, bReset := bCfgReset,
          nYear := nHmiYear, nMonth := nHmiMonth, nDay := nHmiDay,
          nStartYear := 2026, nStartMonth := 11, nStartDay := 1,
          nEndYear := 2027, nEndMonth := 3, nEndDay := 15,
          bIncludeEnd := TRUE,
          bInWindow => bHeatSeason, bEdgeOpen => bHeatOn, bEdgeClose => bHeatOff,
          nDaysUntilEdge => nDaysToHeatEdge, bInvalidConfig => bHeatCfgBad,
          eState => eHeatState, uErrorId => uHeatErr);

// 窗沿脉冲驱动模式切换；组态非法时一律按空窗（不放行采暖）
IF bHeatOn AND (NOT bHeatCfgBad) THEN
    bBoilerGroupEnable := TRUE;
    bFrostOnlyMode     := FALSE;
END_IF
IF bHeatOff THEN
    bBoilerGroupEnable := FALSE;
    bFrostOnlyMode     := TRUE;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **不能替代`FB_DL_MonthWindowCheck`**：年窗允许跨年、月窗跨月非法，两者方向相反。需要「每年 11 月 1 日到次年 2 月末」用本件；需要「每月 25 日到月末」用月窗件。混用必然错判。
- **失能即关窗**：`bEnable = FALSE` 时 `bInWindow` 强制 `FALSE` 并补发 `bEdgeClose`，避免「失能前一拍还开着、失能后下游仍按开窗动作」。
- **组态非法不自动恢复**：`eInvalid` 只认 `bReset` 上升沿且组态已修正，杜绝「参数刚改好一刹那误开窗」。
- **验收锚点**：2026-03-01 至 2026-06-30 窗、当前 2026-04-15 → 窗内且距关沿 76 天；2028-02-29 落在 2028-02-01 至 2028-03-01 窗内 → 闰日自动生效。

---

## 36. FB_DL_RolloverCounter ｜ 环形回绕计数与净圈数（R11，v1.0.0）

**定位 / Positioning**：在 `0 ~ 上限（含）` 的环形域内上下计数，到顶再加回 `0`、到底再减回上限，并输出**净回绕圈数**（可负）。服务对象是「只关心绕了多少圈」的场合：分度盘圈数、编码器溢出圈数、料盘循环计数、卷绕层数。

**与四件计数器的边界 / Family separation（五件互斥）**：`FB_DL_EventCounter` 单向事件累加 / `FB_DL_ModuloCounter` 取模工位索引 / `FB_DL_PresetCounterSat` 单预设饱和冻结 / `FB_DL_BidirectionalCounter` CTUD 双预设比较 / **本件** 环形回绕 + 净圈数（**无任何预设比较**）。本件刻意不实现「到限冻结」（饱和件语义）与「取模」（无符号域与有符号域行为不一致的历史坑），回绕一律用「比较 + 赋值」完成，`ADD 1` 不会溢出、`SUB 1` 不会下溢。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能；`FALSE` 冻结计数（值保持、圈数保持、无脉冲），**不清零** / Enable; FALSE freezes, does not clear |
| `bReset` | BOOL | IN | — | — | 上升沿清零计数与圈数（任意状态生效，并解除饱和）/ Rising edge clears count and turns |
| `bCountUp` | BOOL | IN | — | — | 上升沿加计数（电平保持不重复计数）/ Rising edge increments |
| `bCountDown` | BOOL | IN | — | — | 上升沿减计数 / Rising edge decrements |
| `bLoad` | BOOL | IN | — | — | **电平**有效装载，优先级最高（高于复位沿与计数沿）/ Level-true load, highest priority |
| `uLoadValue` | UDINT | IN | — | cnt | 装载值，超上限钳位并置 `0120` / Load value, clamped |
| `uPreset` | UDINT | IN | — | cnt | 回绕上限（**含端点**），有效域 1~16#FFFF_FFFE / Wrap bound, inclusive |
| `uCount` | UDINT | OUT | — | cnt | 当前计数值，0 ~ 上限 / Current count |
| `bWrapped` | BOOL | OUT | — | — | 本拍回绕单拍脉冲（上下回绕均置位）/ One-shot wrap pulse |
| `nTurns` | DINT | OUT | — | 圈 | 净回绕圈数，上加下减、可负、带饱和保护 / Net wrap turns |
| `bAtPreset` | BOOL | OUT | — | — | 当前值已达上限（逐拍重算，**非锁存**）/ Count reached the bound |
| `eState` | E_DL_RolloverPhase | OUT | — | — | `eIdle` 0 / `eCount` 10 / `eFrozen` 20 / Main phase |
| `bError` | BOOL | OUT | — | — | 故障锁存：回绕上限退化（< 1），计数冻结 / Latched fault on a degenerate bound |
| `uErrorId` | UDINT | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0120` | 信息级 | 装载值超上限已钳位 / 上下限超域已钳位 / 同拍双向已丢弃 / 圈数饱和已停止累加 | 四种情形共用一码，均为「已安全处理」；参数类情形查组态，饱和类情形按量程换批时复位 |
| `0001_0218` | 故障级 | 回绕上限小于 1（退化），计数冻结并锁存 `bError` | 上限必须 ≥ 1；改为合法值后需复位沿退出 `eFrozen` |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_IndexTableTurns
VAR
    fbTurn          : FB_DL_RolloverCounter;  // 圈数统计实例 / Turn counter instance
    bIdxRun         : BOOL := TRUE;           // 分度盘运行 / Indexer running
    bIdxReset       : BOOL;                   // 复位计数 / Reset the count
    bStationPulse   : BOOL;                   // 每工位一个脉冲 / One pulse per station
    bHomingDone     : BOOL;                   // 回零完成 / Homing finished
    uHomePos        : UDINT := 0;             // 回零位置（0 号工位）/ Home position
    uStationNo      : UDINT;                  // 当前工位号 0~59 / Station number
    bLapDone        : BOOL;                   // 一圈完成单拍 / Lap done pulse
    nLapCount       : DINT;                   // 已转圈数 / Laps counted
    bLastStation    : BOOL;                   // 已达末工位 / Last station reached
    eTurnState      : E_DL_RolloverPhase;     // 状态观测 / Phase observation
    bTurnErr        : BOOL;                   // 故障 / Fault
    uTurnErrId      : UDINT;                  // 事件码 / Event code
    nTotalAngleDeg  : DINT;                   // 累计角度 [度] / Accumulated angle
END_VAR

// 60 工位一圈：上限取「一圈格数 − 1」（上限含端点）
fbTurn(bEnable := bIdxRun, bReset := bIdxReset,
       bCountUp := bStationPulse, bCountDown := FALSE,
       bLoad := bHomingDone, uLoadValue := uHomePos, uPreset := 59,
       uCount => uStationNo, bWrapped => bLapDone, nTurns => nLapCount,
       bAtPreset => bLastStation, eState => eTurnState,
       bError => bTurnErr, uErrorId => uTurnErrId);

// 真实位移 = 圈数 × 一圈当量 + 当前值 × 单格当量（一圈 360 度、单格 6 度）
nTotalAngleDeg := nLapCount * 360 + UDINT_TO_DINT(uStationNo) * 6;
END_PROGRAM
```

**要点 / Notes**

- **上限含端点**：`uPreset` 是「最大计数值」而非「格数」。60 格分度盘填 `59`，填 `60` 会让回绕脉冲少一次（一圈只有 0~59 共 60 个值，`bWrapped` 在 59 → 0 那一拍出现）。
- **空载校核法**：手转一圈观察 `bWrapped` 是否**恰好一次**——出现两次说明上限设小，一次都不出现说明上限大于实际格数（脉冲被吃掉）。
- **失能只冻结不清零**：产线短暂停机不丢圈数；清零只认 `bReset`。掉电重启后圈数从 0 起算，需要绝对位置时用 `bLoad` 写已知位置并自行保存圈数。
- **只认沿不滤波**：本件不做任何防抖，上游脉冲若被滤波削沿会导致漏计；脉冲源需要防抖时请在源侧先做（`FB_DL_SignalDebounce`）。

---

## 37. FC_DL_BitArrayExtract ｜ 跨字位流窗口提取（R12，v1.0.0）

**定位 / Positioning**：把 `DWORD` 数组当作一条连续位流（第 1 元素承载位 0~31，第 2 元素承载位 32~63，位号自低向高），按「起始位 + 位宽」取出一个可跨 2 个双字、宽度上限 64 位的位窗并右对齐输出。服务对象是「一个字段横跨两个保持寄存器」的场合：64 位设备状态字、跨 4 个双字存放的凸轮表位图、远程 IO 跨字位图里的报警位段。

**与三件单字件的边界 / Family separation（四件互斥）**：`FC_DL_BitGet` 取单字内**单个位** ｜ `FC_DL_BitFieldExtract` 取单字内 **1~32 位段** ｜ `FB_DL_UnpackWordToBits` 把单字拆成 **16 个固定位** ｜ **本件** 取**跨字位流窗口**，位窗可跨 2 个双字、宽度可达 64 位。四者职责正交，本件不复用也不替代其中任何一件。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `auSource` | `ARRAY[1..8] OF DWORD` | IN_OUT | — | 位串 | 源位流数组，第 1 元素为位 0~31、第 2 元素为位 32~63 / Source bit stream, element 1 holds bits 0 to 31 |
| `nSourceCount` | `INT` | IN | `1` | 个 | 源有效字数，域 1~8，越界钳位 / Effective source word count, clamped to 1..8 |
| `nOffset` | `INT` | IN | `0` | bit | 位窗起始位（0 起），域 0 ~ 32×字数−1 / Window start bit, zero based |
| `nWidth` | `INT` | IN | `1` | bit | 位窗宽度，域 1~64 / Window width, 1..64 |
| `uField` | `LWORD` | OUT | — | 位串 | 右对齐提取结果，自 bit0 起 `nActualW` 位有效 / Extracted field, right aligned |
| `uMask` | `LWORD` | OUT | — | 位串 | 本次实际生效掩码，已右对齐，可直接与结果位与 / Effective right aligned mask |
| `nActualW` | `INT` | OUT | — | bit | 越界截断后的实际生效宽度 / Effective width after truncation |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code, zero means none |
| `bValid` | `BOOL` | OUT | — | — | 入参域全合法为真；截断时为假但**结果仍可用** / Inputs legal, false when truncated but the value is still usable |

状态枚举：无（纯函数，无状态机）。函数返回值：`bValid` 同值（`TRUE` = 全合法）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0125` | 信息级 | 起始位越界（负偏移或 ≥ 位流总位数），早退，输出全零 | 核对偏移是否按「位」而非「字」填写；位号从 0 起算 |
| `0001_0126` | 信息级 | 宽度越界（< 1 或 > 64），早退，输出全零 | 宽度必须落在 1~64；单字取段请改用 `FC_DL_BitFieldExtract` |
| `0001_0127` | 信息级 | 跨字截断：窗口越过位流末端，或伸展到第三个字，按可用位截断后继续计算 | 结果只含可用低位，完整度看 `bValid`；核对字数与位宽是否匹配协议 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_DeviceStatusDecode
VAR
    aStatus        : ARRAY[1..8] OF DWORD;  // 64 位设备状态位流（两个保持寄存器）/ 64-bit device status
    nWords         : INT := 2;              // 有效字数 / Effective word count
    uModeField     : LWORD;                 // 运行模式字段 / Operating mode field
    uModeMask      : LWORD;                 // 该字段掩码 / Field mask
    nModeWidth     : INT;                   // 实际位宽 / Effective width
    uDecErr        : UDINT;                 // 事件码 / Event code
    bDecOk         : BOOL;                  // 入参合法 / Inputs legal
    bDecDone       : BOOL;                  // 函数返回值 / Return value
    nMode          : INT;                   // 模式号 / Mode number
    bModeTrusted   : BOOL;                  // 模式可信（位宽完整）/ Mode is trusted
END_VAR

// 例：起始位 28、位宽 8，窗口横跨两个双字的接缝
bDecDone := FC_DL_BitArrayExtract(
                auSource     := aStatus,
                nSourceCount := nWords,
                nOffset      := 28,
                nWidth       := 8,
                uField       => uModeField,
                uMask        => uModeMask,
                nActualW     => nModeWidth,
                uErrorId     => uDecErr,
                bValid       => bDecOk);

// 右对齐取值；位宽被截断时该字段不完整，不参与模式判定
nMode        := LWORD_TO_INT(uModeField AND uModeMask);
bModeTrusted := bDecOk AND (nModeWidth = 8);
END_PROGRAM
```

**要点 / Notes**

- **位序口径**：数组第 1 元素的 bit0 是整条位流的位 0，第 2 元素的 bit0 是位 32。若协议是「高字在前」，请在调用前自行交换数组元素顺序——本件不做字序归一，也不读任何字序配置。
- **截断不返空值**：`0001_0127` 触发时结果仍含可用低位，`bValid = FALSE`。这是有意的工程取舍：现场宁可读到半段有效位再判断，也不愿因一个越界参数整条解码链断掉。判定完整度请看 `bValid` 或 `nActualW`。
- **第三个字不读**：移位中间量是 64 位，起点非零时最多只能覆盖到第二个字末尾；窗口伸长到第三个字时**显式截断并报码**，而不是让高位静默读成零。
- **契约式前置条件**：函数内无法探测数组实际长度，`nSourceCount` 不得大于调用方实际数组长度，由组态保证（全库唯一允许的契约式前置条件，已登记于源码头注释）。
- **验收锚点**：`auSource[1] = 16#1234_5678`、`auSource[2] = 16#9ABC_DEF0`，起始 28、位宽 8 → 结果 `16#01`、掩码 `16#FF`；起始 20、位宽 16 → `16#0123`。

---

## 38. FC_DL_BitArrayInsert ｜ 跨字位段原子写入（R12，v1.0.0）

**定位 / Positioning**：与第 37 节严格成对——提取件读窗口，本件写窗口。把 64 位值按「起始位 + 位宽」写入 `DWORD` 数组位流的指定窗口，**只改窗口内的位**，窗口外的位原样保留；窗口跨字时先算出两个字的完整新值再一次性写回，避免「先写低字、高字失败」的半写状态。

**回报实际改动字数 / nChanged**：`nChanged` 只统计**值真的变了**的字。上位机可用它判断「这次写入是否真起作用」——装配参数在配方切换时常常写入同值，把同值写入当成「已生效」会掩盖通讯假成功。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `auTarget` | `ARRAY[1..8] OF DWORD` | IN_OUT | — | 位串 | 被写入的目标位流数组，本函数**原地修改**窗口内位 / Target bit stream, window bits modified in place |
| `uValue` | `LWORD` | IN | — | 位串 | 待写入值，只用低 `nWidth` 位，超宽位忽略 / Value to write, only the low window bits are used |
| `nTargetCount` | `INT` | IN | `1` | 个 | 目标有效字数，域 1~8，越界钳位 / Effective target word count, clamped to 1..8 |
| `nOffset` | `INT` | IN | `0` | bit | 写入窗口起始位（0 起）/ Window start bit, zero based |
| `nWidth` | `INT` | IN | `8` | bit | 写入窗口宽度，域 1~64 / Window width, 1..64 |
| `nChanged` | `INT` | OUT | — | 个 | 实际发生改动的字数，值未变的字不计入 / Words actually modified |
| `uApplied` | `LWORD` | OUT | — | 位串 | 实际写入的右对齐值，已按宽度截断 / Value actually applied |
| `uMask` | `LWORD` | OUT | — | 位串 | 本次生效掩码，右对齐 / Effective right aligned mask |
| `nActualW` | `INT` | OUT | — | bit | 越界截断后的实际生效宽度 / Effective width after truncation |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code, zero means none |
| `bValid` | `BOOL` | OUT | — | — | 全合法为真；截断或越界为假 / All inputs legal, false when truncated |

状态枚举：无（纯函数）。函数返回值：`bValid` 同值。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0128` | 信息级 | 写入起始位越界，目标数组**一字未动** | 核对偏移口径（位 vs 字）；负偏移按越界处理 |
| `0001_0129` | 信息级 | 写入宽度越界，目标数组**一字未动** | 宽度必须落在 1~64 |
| `0001_012A` | 信息级 | 跨字截断：窗口越过位流末端，只写入可用位，`bValid` 为假 | 核对字数与位宽是否匹配协议；`nActualW` 给出真实写入宽度 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_WriteSpeedPreset
VAR
    aDriveCfg      : ARRAY[1..8] OF DWORD;  // 驱动参数位流（跨两个字）/ Drive parameter bit stream
    nWords         : INT := 2;              // 目标有效字数 / Effective word count
    nSpeedPreset   : INT := 1450;           // 速度预设（rpm）/ Speed preset
    nChangedWords  : INT;                   // 实际改动字数 / Words actually changed
    uAppliedVal    : LWORD;                 // 实际写入值 / Value applied
    uWriteMask     : LWORD;                 // 生效掩码 / Effective mask
    nAppliedWidth  : INT;                   // 实际宽度 / Effective width
    uWrErr         : UDINT;                 // 事件码 / Event code
    bWrOk          : BOOL;                  // 入参合法 / Inputs legal
    bWrDone        : BOOL;                  // 函数返回值 / Return value
    bPresetApplied : BOOL;                  // 预设确实写进去了 / Preset really applied
END_VAR

// 例：起始位 28、位宽 16 —— 把速度预设写进跨字窗口
bWrDone := FC_DL_BitArrayInsert(
               auTarget     := aDriveCfg,
               uValue       := INT_TO_LWORD(nSpeedPreset),
               nTargetCount := nWords,
               nOffset      := 28,
               nWidth       := 16,
               nChanged     => nChangedWords,
               uApplied     => uAppliedVal,
               uMask        => uWriteMask,
               nActualW     => nAppliedWidth,
               uErrorId     => uWrErr,
               bValid       => bWrOk);

// 同值写入时 nChanged = 0，不能当成「已生效」上报
bPresetApplied := bWrOk AND (nChangedWords > 0);
END_PROGRAM
```

**要点 / Notes**

- **原子性口径**：跨字窗口的两个字在**同一拍**内先算新值再写回，不存在「低字已改高字未改」的中间态；但本件保证的是「单次调用的原子性」，不保证与总线传输的原子性——需要端到端一致时请配合参数回读核对件（`MANUAL_DL_Device.md` 中的 `FB_DL_DeviceParamVerify`）。
- **超宽位忽略**：`uValue` 高于 `nWidth` 的位被掩码丢弃，不报错。若上位机把 32 位值误写进 8 位窗口，高位会**静默丢失**，请用 `uApplied` 回显核对。
- **同值不写**：`nChanged = 0` 时目标数组保持原值、不发写动作。这是本件与「无脑覆盖写」的关键差别，也是识别通讯假成功的唯一手段。
- **与提取件成对使用**：读-改-写全套流程请按「提取 → 修改 → 插入」顺序，勿先插入再提取（插入已含掩码，重复掩码无害但会让 `nChanged` 失真）。

---

## 39. FC_DL_IntervalMembership ｜ 开闭区间成员判定与有符号裕量（R12，v1.0.0）

**定位 / Positioning**：判定一个实数是否落在指定**开闭组合**的区间内，同时给出到最近边界的有符号裕量（内正、外负、恰在边界为零）与「恰在边界」标志。工艺窗口有大量半开约定——温度 60~80 左闭右开、压力 0.4~0.6 左开右闭——把开闭组合做成独立枚举，可以避免每个项目手写比较时把 `>=` 写成 `>`。

**与公差窗件的边界 / Boundary**：`FB_DL_ToleranceWindow` 给的是「三态判定 + 迟滞回差 + 越差单拍告警」，带状态；本件是**纯几何判定**，无状态、无迟滞、可放进任意表达式。需要防抖与越差事件时用公差窗件；只需要「在不在里面、离边界多远」用本件。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `fValue` | `LREAL` | IN | — | 工程单位 | 被判定值，单位由调用方决定 / Value under test, unit defined by the caller |
| `fLower` | `LREAL` | IN | — | 工程单位 | 区间下限 / Lower bound |
| `fUpper` | `LREAL` | IN | — | 工程单位 | 区间上限 / Upper bound |
| `eKind` | `E_DL_IntervalKind` | IN | `eClosedOpen` | — | 开闭组合：`eClosedClosed` 0 ／ `eClosedOpen` 10 ／ `eOpenClosed` 20 ／ `eOpenOpen` 30 / Openness combination |
| `fEps` | `LREAL` | IN | `1.0E-9` | 工程单位 | 边界判定容差，非正时按最小值生效 / Boundary tolerance, non positive falls back to the minimum |
| `bInside` | `BOOL` | OUT | — | — | 落在区间内为真 / Inside the interval |
| `bOnBoundary` | `BOOL` | OUT | — | — | 与某端点距离小于容差为真 / Within tolerance of an endpoint |
| `fMargin` | `LREAL` | OUT | — | 工程单位 | 到最近边界的有符号裕量，内正外负，临界为零 / Signed margin to the nearest bound |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code, zero means none |
| `bValid` | `BOOL` | OUT | — | — | 端点有序且三值有限为真 / Bounds ordered and all values finite |

状态枚举：无（纯函数）。函数返回值：`bInside` 同值。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_012B` | 信息级 | 端点倒置（下限 > 上限），判定为「不在区间内」，**不静默交换** | 倒置几乎总是组态笔误；请修参数，不要依赖自动交换（交换会掩盖上下限填反） |
| `0001_012C` | 信息级 | 端点或被测值为非数 / 非有限，判定不可信 | 上游传感器掉线常表现为 NaN；请在数据源侧先做有效性判定 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_CoolingWindow
VAR
    fTempC      : LREAL := 72.5;             // 实测温度 [℃] / Measured temperature
    bInBand     : BOOL;                      // 在工艺带内 / Inside the process band
    bAtEdge     : BOOL;                      // 贴边（容差内）/ At the edge
    fEdgeMargin : LREAL;                     // 到边界裕量 [℃] / Margin to the bound
    uBandErr    : UDINT;                     // 事件码 / Event code
    bBandOk     : BOOL;                      // 参数可信 / Parameters legal
    bBandDone   : BOOL;                      // 返回值（= bInBand）/ Return value
    bCoolingOn  : BOOL;                      // 冷却阀放行 / Cooling valve permit
END_VAR

// 工艺带 60~80 ℃，左闭右开（60 算合格、80 不算）
bBandDone := FC_DL_IntervalMembership(
                 fValue := fTempC, fLower := 60.0, fUpper := 80.0,
                 eKind  := E_DL_IntervalKind.eClosedOpen, fEps := 0.001,
                 bInside => bInBand, bOnBoundary => bAtEdge, fMargin => fEdgeMargin,
                 uErrorId => uBandErr, bValid => bBandOk);

// 贴边时不允许开冷却（避免边界抖动反复启停），参数不可信时按不放行处理
bCoolingOn := bBandOk AND (NOT bInBand) AND (NOT bAtEdge) AND (fEdgeMargin > 0.0);
END_PROGRAM
```

**要点 / Notes**

- **容差不改判据**：`fEps` 只影响 `bOnBoundary`（「贴边」标志），不改变 `bInside` 的归属。把容差当比较松紧用会得到「明明在区间外却说在里面」的反直觉结果。
- **退化区间**：上下限相等时，只有 `eClosedClosed` 含该单点，其余三种组合都判空集——这是集合论的定义，不是实现取舍。
- **裕量符号**：区间内为正、区间外为负、恰在边界为零，可直接用作「离超温还有多少度」的余量上报。裕量取「到最近边界」的距离，两端对称。
- **倒数第二道闸**：本件不做量程裁剪，也不读平台量程。若被测值来自 4~20 mA 通道，请先做断线判定再送进来，否则 0 mA 会被当成一个合法低温值判定为「区间外」。

---

## 40. FB_DL_BitArrayChangeWatch ｜ 位图变化监视与判稳（R12，v1.0.1）

**定位 / Positioning**：逐拍监视 `DWORD` 数组位图的**位级**变化，输出本拍变化掩码、变化位数、首个变化位的绝对位号，并累计跳变位数、给出「连续无变化」判稳标志与三相状态机。服务对象是「上位机只显示有变化、定位不到是哪一位」的场合：接触不良的端子表现为某一位反复抖动，必须单独统计跳变次数才能定位到端子。

**判稳口径 / Settle**：连续 `nSettleCycles` 拍**无任何位变化**才置 `bSteady`；任何一位变化立即清零计数。判稳窗取 1~100 拍，越界钳位。首拍不比较（无上拍快照），故装载拍恒判「无变化」。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；为假时变化掩码、变化位数、首变位清零并回空闲，**跳变累计保留** / Enable, clears the change family but keeps the toggle count |
| `bReset` | `BOOL` | IN | — | — | 上升沿清跳变累计与判稳计时（故障态下由故障分支自行处理）/ Rising edge resets toggle count and settle timer |
| `nWordCount` | `INT` | IN | `1` | 个 | 监视字数，域 1~8，超上限钳位、小于 1 判故障 / Watched word count, 1..8 |
| `auWatch` | `ARRAY[1..8] OF DWORD` | IN | — | 位串 | 当前位图快照，位 0 在最低位 / Current bitmap snapshot |
| `nSettleCycles` | `INT` | IN | `2` | 拍 | 判稳所需连续无变化拍数，域 1~100 / Cycles required to declare steady |
| `auChangeMask` | `ARRAY[1..8] OF DWORD` | OUT | — | 位串 | 本拍变化位掩码，按字对齐，未监视的字为零 / Per word change mask of this cycle |
| `nChangeBits` | `INT` | OUT | — | 位 | 本拍变化位总数（逐字位计数之和）/ Total changed bits this cycle |
| `nFirstBit` | `INT` | OUT | — | bit | 首个变化位绝对位号，`-1` 表示本拍无变化 / First changed absolute bit, minus one when none |
| `uToggleCount` | `UDINT` | OUT | — | 位次 | 累计跳变位数，由复位沿清零，饱和于 `16#FFFF_FFFE` / Accumulated toggled bits |
| `bSteady` | `BOOL` | OUT | — | — | 连续无变化拍数达到门限 / No change for the settle window |
| `eState` | `E_DL_BitWatchState` | OUT | — | — | `eIdle` 0 ／ `eSampling` 10 ／ `eFault` 99 / Current phase |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `021A` / `021B` 置位 / Latched fault, only the two fault codes set it |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_012D` | 信息级 | 监视字数超上限已钳位到 8 并照常服务 | 组态超出单组 8 字时请拆成两个实例 |
| `0001_012E` | 信息级 | 判稳拍数越界已钳位到 1~100 | 判稳窗应大于最长机械抖动周期，否则永远判不稳 |
| `0001_012F` | 信息级 | 跳变累计饱和（到 `16#FFFF_FFFE` 停值不回绕） | 出现即说明该位长期抖动；按端子接触不良排故后复位 |
| `0001_021A` | 故障级 | 监视字数小于 1（组态错），锁存 `bError`，变化族清零 | 字数至少为 1；改正后给 `bReset` 上升沿退出故障 |
| `0001_021B` | 故障级 | 非法状态兜底（枚举被在线改坏或跨版本不兼容），冻结输出 | 检查在线修改与库版本是否匹配，复位后恢复 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_TerminalJitterWatch
VAR
    fbWatch        : FB_DL_BitArrayChangeWatch;  // 位图监视实例 / Bitmap watch instance
    aTerminalBits  : ARRAY[1..8] OF DWORD;       // 端子排位图（2 个字）/ Terminal bitmap
    bWatchRun      : BOOL := TRUE;               // 监视使能 / Watch enabled
    bWatchReset    : BOOL;                       // 人工复位 / Manual reset
    aChangedMask   : ARRAY[1..8] OF DWORD;       // 本拍变化掩码 / Change masks
    nChangedBits   : INT;                        // 本拍变化位数 / Changed bits
    nFirstChanged  : INT;                        // 首变位绝对位号 / First changed bit
    uJitterTotal   : UDINT;                      // 累计跳变 / Accumulated toggles
    bAllSteady     : BOOL;                       // 判稳 / Settled
    eWatchState    : E_DL_BitWatchState;         // 状态观测 / Phase
    bWatchFault    : BOOL;                       // 故障 / Fault
    uWatchErr      : UDINT;                      // 事件码 / Event code
    nSuspectTerm   : INT;                        // 可疑端子号 / Suspect terminal
END_VAR

// 每周期无条件调用；字数 2、判稳窗 3 拍
fbWatch(bEnable := bWatchRun, bReset := bWatchReset,
        nWordCount := 2, auWatch := aTerminalBits, nSettleCycles := 3,
        auChangeMask => aChangedMask, nChangeBits => nChangedBits,
        nFirstBit => nFirstChanged, uToggleCount => uJitterTotal,
        bSteady => bAllSteady, eState => eWatchState,
        bError => bWatchFault, uErrorId => uWatchErr);

// 首变位直接给出端子坐标（每字 32 位），供维护屏高亮
IF nFirstChanged >= 0 THEN
    nSuspectTerm := nFirstChanged / 32 + 1;   // 字号，1 起
END_IF
END_PROGRAM
```

**要点 / Notes**

- **掉使能不清跳变累计**：`bEnable = FALSE` 只清掩码、变化位数与首变位并回空闲，`uToggleCount` **刻意保留**——跳变次数是排故证据，停机时清掉等于毁证。清零只认 `bReset`。
- **故障态必须能被复位**：`eFault` 的复位判据每拍都有机会执行。本件 v1.0.1 修的正是这条——原实现把「掉使能统一回空闲」写成无条件前置分支，使 `eFault` 主体整拍被跳过，"停机 → 按复位 → 上使能" 序列下故障永不清除（范式 R39）。
- **位号口径**：`nFirstBit` 是**绝对位号**（0 起，跨字连续），不是字内位号。换算端子坐标时字号 = `nFirstBit / 32 + 1`。
- **未监视的字一定读零**：`nWordCount` 缩小后，超出范围的掩码字被显式清零，绝不会让调用方读到上一组态的残留位。
- **判稳不等于健康**：`bSteady` 只说明「这段时间没变」，不能推断值正确。要判「值对不对」请配 `FC_DL_ArrayDiffSummary`（见 `MANUAL_DL_MathData.md`）或参数回读核对件。

---

## 41. FC_DL_BitArrayRotate ｜ 跨字位串整串循环旋转（R13，v1.0.0）

**定位**：把 1~4 个 `DWORD` 视为一条 32~128 位的位串做整体循环旋转，移出最高字的位回卷到最低字。与 `FC_DL_BitArrayExtract`（「抽」）/ `FC_DL_BitArrayInsert`（「插」）构成位段族三件套：前两件按位窗口局部读写，本件只做整条位串循环平移，**位序总量守恒、位宽不变**。典型用途：多字报警位图的时段轮转显示、4 字 128 点位图交接班整体顺延、循环缓冲区位索引整体平移、旋转编码器多字计数的位窗口对齐。

**为什么不用标准 ROL**：IEC 的 `ROL` 只在单字内循环，跨字无定义；把多字拼成 64/128 位中间量再移位，移位量等于位宽时属未定义行为，且各平台对超宽中间量支持不一。本件按字就地运算，移位量一律落在 1~31 的合法域。

### 41.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `aSrc` | `ARRAY[1..4] OF DWORD` | IN | — | 位串 | 源位图，第 1 元素承载位 0~31，未用字填 0 / Source bitmap, element 1 holds bits 0..31 |
| `nWords` | `INT` | IN | — | 个 | 有效字数，域 1~4；小于 1 判故障早退，大于 4 钳到 4 继续算 / Effective word count, clamped above 4 |
| `nShift` | `INT` | IN | — | bit | 移位位数，负值**恒为右移**（方向归一裁定）；先取绝对值再对总宽取模 / Shift amount, negative always means right |
| `bLeft` | `BOOL` | IN | — | — | 方向选择，TRUE 左移；`nShift` 为负时本引脚被忽略 / TRUE rotates left, ignored when nShift is negative |
| `aDst` | `ARRAY[1..4] OF DWORD` | IN_OUT | — | 位串 | 目标位图，**允许与源同址**（别名安全：结果先落暂存区再整体写回）；失败路径不写入 / Destination, may alias the source, untouched on failure |
| 返回值 | `BOOL` | 返回 | — | — | TRUE = 已计算（归约与钳位属信息级，结果仍可用） / TRUE when computed |
| `nEffectiveShift` | `INT` | OUT | — | bit | 归一后实际左旋量，域 0~总宽−1；是归约值不是入参原值 / Effective left rotation after normalisation |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 表示无事件 / Event code |

**方向归一表 / Direction normalisation**：`nShift < 0` → 右移（取绝对值，`bLeft` 被忽略）；`nShift ≥ 0 且 bLeft` → 左移；`nShift ≥ 0 且 bLeft = FALSE` → 右移。

### 41.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无事件 / No event | — |
| `16#0001_013D` | 信息级：移位量已归约（超 127 位上限**或跨越整圈**——整圈也是「被归约」，必须有人说一声）/ Shift reduced or wrapped a whole turn | 判「有没有整圈」请比对本码，而不是比对 `nShift` 与总宽 |
| `16#0001_013E` | 信息级：字数超上限，已钳到 4 / Word count clamped to 4 | 检查调用方数组维度与 `nWords` 来源 |
| `16#0001_021F` | 故障级：有效字数 < 1（逻辑错误） / Illegal word count | 修正组态；**目标数组保持原样**（不写半张图） |

### 41.3 调用示例 / Example

```iecst
PROGRAM PRG_AlarmShift
VAR
    aAlarmMap        : ARRAY[1..4] OF DWORD;  // 当前报警位图（128 点）/ Current alarm bitmap
    aAlarmMapShifted : ARRAY[1..4] OF DWORD;  // 轮转后的位图 / Rotated bitmap
    nUsed            : INT;                   // 归一后实际左旋量 / Effective rotation
    uCode            : UDINT;                 // 事件码 / Event code
    bOk              : BOOL;                  // 返回值 / Return value
END_VAR

// 交接班整体顺延 8 位（左移），nWords = 4
bOk := FC_DL_BitArrayRotate(
           aSrc            := aAlarmMap,
           nWords          := 4,
           nShift          := 8,
           bLeft           := TRUE,
           aDst            := aAlarmMapShifted,
           nEffectiveShift => nUsed,
           uErrorId        => uCode);
END_PROGRAM
```

### 41.4 要点 / Notes

- **`nEffectiveShift` 是归约后的左旋量**，不是入参原值；右移 1 位在 64 位串上会报 `nEffectiveShift = 63`（右移 n 等价左旋 总宽−n）。
- **整圈也报 013D**：`nShift = 64` 归约后输出等于输入，但「移位量被归约」这件事必须可见——不然现场永远不知道配置里那个 64 是怎么变成 0 的。
- **别名安全**：`aDst` 与 `aSrc` 同址合法，结果先落暂存区、全部算完才写回；但直接旋转当前生效的报警位图仍建议旋转到独立数组，便于保留原始证据。
- **契约前置条件**：函数无法探测调用方数组实际长度，「`nWords` 不大于数组长度」由调用方在组态时保证。
- 纯函数：无内部状态、无跨周期残留，同入参同结果。

---

## 42. FC_DL_MaskCompare ｜ 状态字掩码比较与差异定位（R13，v1.0.0）

**定位**：判「值按掩码比较是否等于期望」，并给出差异位图、差异位数与首个差异位号，供报警直接定位到具体那一位。掩码为 0 的位不参与比较（don't-care 位），位宽参数把高于 `nWidth − 1` 的位排除在外。典型用途：变频器状态字只看「运行、故障、就绪」三位组合、远程 IO 模块状态字忽略保留位整字比对、多轴使能位图期望态一致性检查、报警诊断直接报「差在第几位」。

**与既有件边界**：`FC_DL_BitFieldExtract` 是「取一段」（取出后调用方自行比较）；`FB_DL_StatusWordSegDecoder` 是「段表批量解码」；本件是「判等 + 差异定位」，一次调用既回答「是否匹配」又回答「差在哪几位」。

### 42.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `uValue` | `DWORD` | IN | — | 位串 | 待比较值 / Value under test |
| `uExpect` | `DWORD` | IN | — | 位串 | 期望值 / Expected value |
| `uMask` | `DWORD` | IN | `16#FFFF_FFFF` | 位串 | 参与比较的位，1 比较、0 不关心 / Care mask |
| `nWidth` | `INT` | IN | `32` | bit | 有效位宽，域 1~32；小于 1 判故障早退，大于 32 钳到 32 / Effective width |
| 返回值 | `BOOL` | 返回 | — | — | TRUE = 按契约位域完全一致 / TRUE on full match |
| `uDiffBits` | `DWORD` | OUT | — | 位串 | 差异位图，已按位宽与掩码双重屏蔽 / Difference bitmap after both masks |
| `nDiffCount` | `INT` | OUT | — | 个 | 差异位数，域 0~32 / Difference bit count |
| `nFirstDiff` | `INT` | OUT | — | bit | 首个差异位号（低位向高位扫描，报最低差异位），无差异为 −1 / First differing bit, −1 when none |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码 / Event code |

**双重屏蔽**：先按位宽裁出低位域掩码，再与调用方掩码相与，两道屏蔽同时生效——不存在「宽掩码压过窄位宽」的漏判；反之掩码被位宽吃掉（有效掩码为 0）时按恒匹配处理并置 0140 提示。

### 42.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无事件 / No event | — |
| `16#0001_013F` | 信息级：位宽超上限已钳到 32 / Width clamped | 检查位宽来源 |
| `16#0001_0140` | 信息级：生效掩码为 0（恒匹配，提示掩码与位宽矛盾）/ Zero mask, matches anything | 掩码位全被位宽裁掉或掩码填了 0，检查掩码语义 |
| `16#0001_0220` | 故障级：位宽 < 1（逻辑错误）/ Illegal width | 修正组态；差异位图保持 0（不输出脏位图） |

### 42.3 调用示例 / Example

```iecst
PROGRAM PRG_VfdStatusWatch
VAR
    uVfdStatus  : DWORD;   // 变频器状态字（通讯卡写入）/ VFD status word
    uVfdExpect  : DWORD;   // 期望态：运行 + 就绪（bit1 + bit3）/ Expected state
    uVfdMask    : DWORD := 16#0000_000A;   // 只看 bit1 与 bit3，其余 don't-care
    uDiff       : DWORD;   // 差异位图 / Difference bitmap
    nDiffBits   : INT;     // 差异位数 / Difference count
    nDiffFirst  : INT;     // 首差位 / First differing bit
    uMskCode    : UDINT;   // 事件码 / Event code
    bVfdOk      : BOOL;    // 匹配结论 / Match verdict
END_VAR

// 只比 bit1/bit3：保留位与速度位的变化不会误报
bVfdOk := FC_DL_MaskCompare(
              uValue     := uVfdStatus,
              uExpect    := uVfdExpect,
              uMask      := uVfdMask,
              nWidth     := 32,
              uDiffBits  => uDiff,
              nDiffCount => nDiffBits,
              nFirstDiff => nDiffFirst,
              uErrorId   => uMskCode);

// 不匹配时首差位直接给出「差在哪一位」，报警不再只说「状态字不对」
IF NOT bVfdOk AND nDiffFirst >= 0 THEN
    ;   // HMI 按 nDiffFirst 高亮具体状态位
END_IF
END_PROGRAM
```

### 42.4 要点 / Notes

- **首差位号是绝对位号**（0 起），与 `FB_DL_BitArrayChangeWatch` 的 `nFirstBit` 同口径，跨字换算端子坐标时字号 = `位号 / 32 + 1`。
- **判据等价性**：实现用 `(uValue XOR uExpect) AND uMaskEff` 判差，与规格字面的「各自与掩码相与再判等」数学等价（异或差为零 ⇔ 掩码域相等），终审裁定采纳。
- **位宽 32 走常量分支**：禁 `SHL(DWORD#1, 32)`（移位量等于位宽在部分编译器为未定义行为）；`nWidth ≥ 32` 直接取满一常量。
- **0140 不是故障**：掩码为 0 时判据天然成立（全 don't-care 必匹配），但「掩码没生效」这件事必须提示，否则现场会把「掩码填错但总是 PASS」当成状态字真的正常。
- 纯函数：无内部状态、同入参同结果。

---

---

## 43. R14 T0 快车道增量：IEC 标准件防御性包装（#43~#57，15 件）

> **组归属**：T0-1 双稳态/边沿（#43~#46）｜ T0-2 定时器（#47~#50，RTO 为通用语义 clean-room）｜ T0-3 计数器（#51~#53）｜ T0-7 位串移位（#54~#57）。**四组收口**。标准原型：SR/RS/R_TRIG/F_TRIG/TON/TOF/TP/RTO/CTU/CTD/CTUD/SHL/SHR/ROL/ROR。

### 43.1 组件速览 / Quick Reference

| # | 组件 | 标准原型 | 防御要点 | 码位 |
|---|---|---|---|---|
| 43 | `FB_DL_SRBistable` | SR | S1/R 同拍置位优先 + 仲裁诊断 | `014D` |
| 44 | `FB_DL_RSBistable` | RS | S/R1 同拍复位优先 + 仲裁诊断 | `014E` |
| 45 | `FB_DL_RTrigEx` | R_TRIG | 首扫不假触发、单拍输出 | 无 |
| 46 | `FB_DL_FTrigEx` | F_TRIG | 首扫不假触发、单拍输出 | 无 |
| 47 | `FB_DL_TonEx` | TON | PT 负钳 0、跨段语义统一 | `014F` |
| 48 | `FB_DL_TofEx` | TOF | 首扫零假触发 | `0150` |
| 49 | `FB_DL_TpEx` | TP | 不可重触发语义显式化 | `0151` |
| 50 | `FB_DL_RtoEx` | RTO | 复位>使能优先链、末拍快照冻结累加 | `0152` |
| 51 | `FB_DL_CtuEx` | CTU | PV 负钳 0、上溢饱和不回绕 | `0153` |
| 52 | `FB_DL_CtdEx` | CTD | 下溢饱和不回绕 | `0154` |
| 53 | `FB_DL_CtudEx` | CTUD | 净额抵消法 + 双向饱和锁定 | `0155`/`0226` |
| 54 | `FC_DL_ShlEx` | SHL | n ≥ 32 常量置 0 不调内建 | `0156` |
| 55 | `FC_DL_ShrEx` | SHR | 同上 | `0157` |
| 56 | `FC_DL_RolEx` | ROL | MOD 32 归一 + 位合成 | `0158` |
| 57 | `FC_DL_RorEx` | ROR | 同上 | `0159` |

### 43.2 通用防御范式（15 件共用）

- **四段式**（R45）：返回值/码预置 → 域闸门早退 → 委托内建内核 → 结果复检。
- **内核委托**：定时器/沿检测全部委托内建 TON/TOF/TP/R_TRIG 局部实例（无条件周期刷新）；CTUD 计数本体为显式判界 ±1（内建 CTUD 无双向饱和锁定能力），与 `FB_DL_BidirectionalCounter` 划界互引；SR/RS 为单拍锁存语义，无内建内核可委托。
- **首扫初始化前置**：无首扫假输出（历史教训④口径）。
- **诊断字 UDINT**：码位段 `16#0001_xxxx` 为 32 位段超 WORD 容量（头注释「类型裁定」节留档）。

### 43.3 要点 / Notes

- **RTO 末拍快照冻结**（R46）：bIN 断开拍内建 TON 的 ET 已被清零，须用上一拍 `tETLast` 累入保持量，杜绝丢拍；tET 只增不减至复位。
- **CTUD 净额抵消**（R47）：CU/CD 同拍 net=0 一次性施加，消灭先加后减的顺序歧义；复位 > 装载 > 计数优先级链写死。
- **移位量归一**（R48/R10）：循环移位 MOD 32 归一后 0 直通；非循环移位 n ≥ 32 走常量路径置 0，禁超宽内建调用。
- PT/PV 负值钳 0 置**信息码**不置故障码；饱和为正常防御行为，仅 CTUD 双向饱和置故障码 `0226`。

---


---

## 44. R17 T0 纯函数第 4 轮增量：LWORD 64 位域防御包装（#58~#61，4 件）

> **组归属**：T0-7 位串操作 LWORD 64 位变体（R14 已收 32 位 DWORD 口径 4 件，本节扩至 64 位 LWORD 口径）。全部为 `FC_` 纯函数（R60 N/A 口径），输出契约三件套 `eErr/bError/bValid`。标准原型：SHL/SHR/ROL/ROR（LWORD）。

### 44.1 组件速览 / Quick Reference

| # | 组件 | 标准原型 | 防御要点 | 码位 |
|---|---|---|---|---|
| 58 | `FC_DL_ShlLwordEx` | SHL（LWORD） | nN ≥ 64 常量路径置全零不调内建（64 位口径同源 R14 32 位 ShlEx）；nN 为 USINT 天然非负 | `021D` |
| 59 | `FC_DL_ShrLwordEx` | SHR（LWORD） | nN ≥ 64 常量路径置全零；无符号位串不做符号位扩展 | `0208` |
| 60 | `FC_DL_RolLwordEx` | ROL（LWORD） | nN ≥ 64 按 MOD 64 归一（与移位件「置零」口径刻意相反，头注释互引声明）；归一后零移位直通不调内建 | `020A` |
| 61 | `FC_DL_RorLwordEx` | ROR（LWORD） | MOD 64 归一同口径，零移位直通；MOD 除子 64 编译期恒非零 | `020C` |

### 44.2 要点 / Notes

- **64 位口径**：LWORD 位宽 64 提为常量 `DL_LW_WIDTH`；移位量 USINT（0~255）天然非负，负移位结构性不可能，无负值防御分支。
- **置零 vs 归一口径**：非循环移位（SHL/SHR）超宽结果恒为 0 → 置零；循环移位（ROL/ROR）超宽对位宽取模仍等价 → 归一。二者语义不可混用，头注释显式互引。
- **码位警示**：`0208`/`021D`/`021E` 经 R17 收口全库正则复测与存量件撞车（`FC_DL_TempUnitConvert` / `FB_DL_StringTokenStream`），R18 改判专项方案已列明（ShlLwordEx→0217/0218、ShrLwordEx→0219），执行前本节码位暂维持源码现状。

### R18 新件接口一览（2026-11-16 追加）/ Round 18 Interface Summary

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FB_DL_EdgeDivider` | 每 N 个上升沿出一个单周期脉冲，供双作用气缸交替动作 | `bIn` / `uDivide` / `bOut` |
| `FB_DL_FirstOutLatch` | 16 路故障源首出锁存，只认第一个到来的原因 | `aSrcFault` / `bReset` / `uFirstOutNo` |
| `FB_DL_PulseStretch` | 窄脉冲展宽到下游最小响应时间以上 | `bIn` / `tMinPulse` / `bOut` |
| `FC_DL_BitSegmentBlockMove` | 段表驱动搬移源 128 位窗口内至多 8 个位段 | `auDstBit` / `auWidth` / `auSrcBits` |

> 用法要点：`FirstOutLatch` 的输入端必须一次性给全 16 路（未用的置 FALSE），否则「首出」语义失真；`PulseStretch` 的 `tMinPulse` 取下位执行机构最小响应时间的 1.5 倍。


---


---

## R19 追加组件接口表（2026-11-16，本子库 1 件）

### `FB_DL_BitShiftRegister`
- **功能**：宽度 1~32 可组态位串逐拍移位寄存器（溢出位/置位数/饱和计数，清空优先，T2-1 LGF Bit Logic 时序层）
- **输入引脚**：bEnable、bReset、bShift、bShiftIn、uWidth、bClearAll、bDirLeft（语义与单位见 .st 头注释）
- **输出引脚**：uReg、bShiftOut、bAnySet、uSetCount、uShiftCnt、eErr、bError
- **码位**：16#0001_0408 用 / 16#0001_0409 预留 ｜ 16#0001_032A 用 / 16#0001_032B 用 / 16#0001_032C 预留


---

## R20 追加组件接口表（2026-11-16，本子库 2 件）

### `FC_DL_LeapYearChk`
- **功能**：闰年原子判定，供年窗 / 天数族共用，不做纯算术的重复实现。`bFullRule` 显式选择两律（仅 4 年整除，LGF / OSCAT 部分实现的默认口径）与三律（4/100/400，ISO-8601 口径）。
- **输入引脚**：`nYear`（1900~2099 窗口）、`bFullRule`
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0430`（整百年——两律与三律在此处分歧，必须让调用方看得见）｜ 故障 `16#0001_0366`（年份超窗口）

### `FB_DL_SemaMutex`
- **功能**：IEC 标准 SEMA 的防御包装，解决「标准 SEMA 不带超时、持锁方卡死会永久锁死产线」。**三态状态机**（`eFree` / `eHeld` / `eTimedOutRelease`）+ `ELSE` 兜底；超时**强制归还**并按故障级 0369 上报；释放沿优先于申请沿（安全侧：宁可多还一次，不可错持一次）；`TON` + 两只 `R_TRIG` 三实例在本体首部无条件周期刷新。
- **输入引脚**：`bClaim`、`bRelease`（均上升沿有效）、`tHoldMax`（默认 `T#5S`，`0` = 禁用超时监视）
- **输出引脚**：`bBusy`（由状态派生，不独立锁存）、`bTimedOut`（单周期脉冲）、`uClaimCnt`、`uReleaseCnt`（饱和计数）
- **码位**：信息 `16#0001_0432`（同拍仲裁释放优先 / 监视被禁用）｜ 故障 `16#0001_0369`（超时强制归还）、`036A`（非法状态兜底）、`036B`（计数饱和）
- **用法要点**：超时归还的时序是「超时拍 N 进 `eTimedOutRelease` → 拍 N+1 回 `eFree` 并恢复受理」，过渡态恰占**一个**扫描拍且此拍申请被拒——上层重试节拍按 1 拍延迟设计，别按同拍设计；实例必须每周期无条件调用。

---

## R21 追加接口表 / R21 Interface Tables

> R21 守卫 FB 族 5 件（v1.16.0 追加）。以下引脚表由源码声明区**自动抽取**（`_Staging_Raw/2026-11-16/_r21_doc.py`），不做人工转述，避免文档与代码漂移。

### `FB_DL_MinOnOffGuard`
- **功能**：最短运行 / 最短停止双守卫，防压缩机、热泵、泵轮值与冷水机组频繁启停的公共原子。（v1.0.0，R21 入库）
- **输入引脚**：`bEnable`、`bReq`、`tMinOn`、`tMinOff`、`bReset`
- **输出引脚**：`bOut`、`bHoldOn`、`bHoldOff`、`tRemaining`、`eState`、`eErr`、`bError`
- **码位**：信息 `16#0001_0452`/`16#0001_0453` ｜ 故障 `16#0001_0399`/`16#0001_039A`/`16#0001_039B`

### `FB_DL_SignalChangeCounter`
- **功能**：带死区与最小间隔的模拟量变化次数统计，用于阀动作次数、执行机构寿命台账、工艺参数漂移审计。（v1.0.0，R21 入库）
- **输入引脚**：`bEnable`、`fValue`、`fDeadband`、`tMinInterval`、`bReset`
- **输出引脚**：`uCount`、`uChatterCount`、`fLastAccepted`、`tSinceLast`、`bSaturated`、`eErr`、`bError`
- **码位**：信息 `16#0001_0454`/`16#0001_0455` ｜ 故障 `16#0001_039C`/`16#0001_039D`/`16#0001_039E`

### `FB_DL_SamplingTrigger`
- **功能**：均匀采样节拍源，输出单拍采样沿 + 样本序号 + 理论/实际时基账目 + 漂移告警，供趋势记录使用。（v1.0.0，R21 入库）
- **输入引脚**：`bEnable`、`tInterval`、`tDelta`、`bReset`
- **输出引脚**：`bSample`、`uSampleNo`、`tTheoretical`、`tActual`、`bDrift`、`eErr`、`bError`
- **码位**：信息 `16#0001_0456`/`16#0001_0457` ｜ 故障 `16#0001_039F`/`16#0001_03A0`/`16#0001_03A1`

### `FB_DL_SignalFrozenDetect`
- **功能**：信号冻结检测，窗内极差小于死区即判传感器卡死；NE107 的 eCheckFunction（功能自检）判据原子。（v1.0.0，R21 入库）
- **输入引脚**：`bEnable`、`fValue`、`fMoveEps`、`tWindow`、`bReset`
- **输出引脚**：`bFrozen`、`tFrozenFor`、`fSpan`、`bInvalidInput`、`eErr`、`bError`
- **码位**：信息 `16#0001_0458`/`16#0001_0459` ｜ 故障 `16#0001_03A2`/`16#0001_03A3`/`16#0001_03A4`

### `FB_DL_PulseWidthFilter`
- **功能**：窄脉冲抑制，脉宽小于 tMinWidth 的整段脉冲不出现在输出上，合格脉冲的宽度不失真。（v1.0.1，R21 入库）
- **输入引脚**：`bEnable`、`bIn`、`tMinWidth`、`bReset`
- **输出引脚**：`bOut`、`uRejectCount`、`bRejected`、`eErr`、`bError`
- **码位**：信息 `16#0001_045A`/`16#0001_045B` ｜ 故障 `16#0001_03A5`/`16#0001_03A6`/`16#0001_03A7`
---

## R22 批次接口表（R22 追加 · 2 件）

### FC_DL_FirstSetBit ｜ 首个置位位定位（DL_Base / BitString ｜ FUNCTION → BOOL）
- **输入引脚**：`uValue`（LWORD 待扫位串）、`uWidth`（UINT 有效位宽 8/16/32/64，缺省 64）、`bHighFirst`（BOOL TRUE 高位优先）
- **输出引脚**：`uBitIndex`（UINT 0 基位号）、`bFound`（BOOL）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0462`（全零无置位位）/ `0463`（位宽已钳位）｜ 故障 `16#0001_03B1`（位宽为 0）
- **典型用例**：状态字→首个故障位号、IO 字→首个空位；宽 64 走常量掩码，全程无 `SHL(x,64)`。

### FB_DL_FrequencyMeasure ｜ 门时计数测频（DL_Base / Timing）
- **输入引脚**：`bPulse`、`bEnable`、`tGateTime`（TIME 缺省 T#100MS，1 ms~10 s 钳位）、`fLowFreqDead`（REAL Hz 缺省 0.5）
- **输出引脚**：`fFreq`（REAL Hz，分辨率 1/tGateTime）、`fFreqRes`、`uLastCount`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0001_0464`（门时间已钳位）/ `0465`（低于死区按 0 输出）｜ 故障 `16#0001_03B4`（门时间为 0）/ `03B5`（计数回退不可信，含状态机兜底复用）
- **遗留假设**：门切换拍不确定度 ±1 计数（±1/tGateTime Hz），不得声称精确。


*Last updated: 2026-11-16（R22 追加接口表）｜ 道莅工控代码库产品总监*

## R68 新增件与终审就地修（2026-11-22）

- `FB_DL_InterlockBypassAudit` / `FB_DL_ClockDriftMonitor` / `FB_DL_DiagTextLookup`（R68）：旁路审计 / 漂移监视 / 诊断文本查表；`ClockDriftMonitor` 于 R68 终审升 v1.0.1（组态锁存解除式补可达）。
