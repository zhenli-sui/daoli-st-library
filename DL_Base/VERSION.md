# DL_Base — 版本记录 / Version History

> **子库定位 / Role**：Level 0 基础逻辑层，零外部依赖，只做信号整形、位运算、字打包与编码换算。
> **兼容平台 / Platforms**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop ｜ Schneider Machine Expert
> **依赖 / Depends**：仅 `Standard.library`（`TON` / `R_TRIG` / `SHR` / `SHL`），不引用任何 `DL_` 内其他子库。

---

## v1.31 — 2026-11-22（R71）

- R71 新增 1 件：`FC_DL_DurationFormat`（TIME → 天/时/分/秒 四分量，HMI 显示纯函数，常量除子级联零除零面，毫秒余量置 `bTruncated`）。累计 152 件。

---
## v1.30 — 2026-11-21（R59）

R59 新增 TimerFailSafe / TwoStepConfirm / MultiSegmentTimer 三件（看门狗失效安全、两步确认、多段时序），补足基础控制时序家族。

## 当前版本 / Current Version

| 项 / Item | 值 / Value |
|---|---|
| 子库版本 / Sublibrary Version | **v1.20.0** |
| 组件总数 / Components | **77**（registry 实测口径，R30 新增见下方增量行：74→75） |
| 发布日期 / Release Date | 2026-11-18 |
| 库总版本 / Library Version | 2.30.0 |
| 故障码段 / Error Code Family | **`16#0001_xxxx`**（信息级 `16#0001_01xx` ｜ 故障级 `16#0001_02xx`，R13 本批占用 `013D`~`013F` 与 `021F`~`0220`；R14 本批占用 `014D`~`0159` 与 `0226`；**R17 本批占用 `0208`~`0209`、`020A`~`020B`、`020C`~`020D`、`021D`~`021E` 与故障级 `02F7`~`02FC`**；⚠️ R17 收口实测 `0208`/`021D`/`021E` 与存量件交叉撞车（见 v1.11.0 节码位台账），R18 改判专项待执行） |


## v1.19.0 ｜ 2026-11-18 ｜ R38：2 件（SaturateAdd / ToggleButtonBank）

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 1 | FC_DL_SaturateAdd | FC | `16#01_0_00` | t2-1-lgf-math | 饱和加减：以 LINT 中间量计算后按目标区间钳制，禁 DINT 相加后判回绕 |
| 2 | FB_DL_ToggleButtonBank | FB | `16#01_0_01` | t1-5-tcopen | 多路按钮组解算：Toggle / SingleAct / Selector3 三模式 + 通道互斥 + 上电恢复策略 |

> R38 增量行：组件总数 → **77**（registry 实测口径）；库总版本 2.30.0。

## v1.18.0 ｜ 2026-11-18 ｜ R30 位段族补件：1 件

- `FC_DL_BitArraySegCopy`：位段数组多段一次搬（源→目标 DWORD 数组 N 段批量复制，先整体校验后统一搬移〔整段原子性：任一段非法则零段搬移〕；跨字窗口读改写沿用 R12 Extract/Insert 范式，全程无 64 位移位）（0001_048E~0491，FC 纯函数 4 槽）。

> R30 增量行：组件总数 74→**75**（registry 实测口径）；源矩阵「DWORD/LWORD 数组批量位段族——多段一次搬」待挖子项收口。

---

## v1.16.0 ｜ 2026-11-16 ｜ R21 守卫 FB 族 5 件 / R21 Guard Function Blocks — 5 Components

**批次**：批4 守卫 FB（最短运行/停止、信号变化计数、采样触发、信号冻结检测、脉宽抑制）
**总行数**：本子库本轮 5 件合计 **688 行**（全库 20 件 2,802 行）
**机检**：5/5 PASS fail=0
**终审**：本子库抽 2 件（`FB_DL_MinOnOffGuard` / `FB_DL_PulseWidthFilter`），修复 1 件轻微（`bReset` 电平清零与引脚注释「上升沿」不符 → 补 `rtReset` 沿判定）；`MinOnOffGuard` 两处主动偏离**裁定采纳**（详见 `_Staging_Raw/2026-11-16/BATTLE_REPORT_R21.md`）
**码位游标（跨子库共用，注册表实测）**：信息级 **`045C`** ｜ 故障级 **`03A8`**

| 组件 | 版本 | 类型 | 说明 |
|---|---|---|---|
| `FB_DL_MinOnOffGuard` | 1.0.0 | FB | 最短运行/停止双守卫；六态机 + ELSE 兜底；`eRunning` 纳入最短运行计时、`eIdle` 只看 `bReq`（修正样板死锁形态） |
| `FB_DL_SignalChangeCounter` | 1.0.0 | FB | 信号变化计数；饱和锁存 + 复位沿 |
| `FB_DL_SamplingTrigger` | 1.0.0 | FB | 采样触发；节拍由引脚注入，不假设扫描周期 |
| `FB_DL_SignalFrozenDetect` | 1.0.0 | FB | 信号冻结检测；超时无变化置报警 |
| `FB_DL_PulseWidthFilter` | **1.0.1** | FB | 窄脉冲抑制；**双侧确认窗**保证合格脉宽守恒，输出整体滞后 `tMinWidth`；失能直通 |

### 码位台账（R21 新增，本子库 5 件）

| 码位 | 级别 | 语义 | 组件 |
|---|---|---|---|
---

## v1.14.0 ｜ 2026-11-16 ｜ R20 T0 闰年原子 + 同步族互斥防御包装 2 件 / R20 T0 Leap-Year Atom and the Sync-Family Mutual-Exclusion Wrapper — 2 Components

**变更性质**：MINOR（新增 2 件），无破坏性变更，无迁移动作。**终审**：8 件高风险抽样，本子库命中 1 件并修复（`FB_DL_SemaMutex` 过渡态跨拍时序表述，注释级，升 v1.0.1，逻辑与引脚零变更）。

### 新增组件（2 件）/ Added Components

| 组件 / Component | 行 | 类型 | 防御要点 / Defense |
|---|---|---|---|
| `FC_DL_LeapYearChk` | 107 | FC·日历原子 | 闰年判定：4/100/400 三级规则，`bFullRule` 显式选择两律（仅 4 年）与三律（含整百例外）；整百年 0430 信息级——两律与三律在此处分歧，必须让调用方看得见；年份超 1900~2099 窗口判故障级 0366 |
| `FB_DL_SemaMutex` | 186 | FB·同步 | IEC 标准 SEMA 的防御包装：ENUM+CASE **三态**（`eFree` / `eHeld` / `eTimedOutRelease`）+ `ELSE` 兜底复位；超时**强制归还**并置**故障级** 0369（死锁拦截 ≠ 正常防御，必须进报警）；释放沿优先于申请沿（同拍 0432 信息级）；`TON` / 两只 `R_TRIG` 三实例本体首部无条件刷新；申请/释放计数饱和 036B，非法状态 036A |

### 终审修复（v1.0.1）/ Fixed in Final Review

- `FB_DL_SemaMutex` v1.0.0→**v1.0.1**（**注释级**）：头注释状态机段「`eTimedOutRelease` 本拍即回 `eFree`」易被读成**同拍**回零；实际为超时拍 N 进过渡态、拍 N+1 回 `eFree` 并恢复受理（过渡态恰占一个扫描拍，其间申请被拒）。逻辑零变更，仅表述改为跨拍显式口径——时序描述错一拍会让上层按错误延迟设计重试节拍。同步修正 JSONL `architecture_thought` 中「超时判 036A」的错记（应为 0369；036A 是非法状态兜底）。

### 码位台账追加（R20，经终审全库求差断言复核）

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `16#0001_0430` | 信息 | 整百年（`y MOD 100 = 0`），两律与三律在此处分歧，结论取决于 `bFullRule` | `FC_DL_LeapYearChk` |
| `16#0001_0431` | 信息 | 预留禁用 | — |
| `16#0001_0432` | 信息 | 同拍申请与释放（已按释放优先）或超时监视被禁用（`tHoldMax = 0`） | `FB_DL_SemaMutex` |
| `16#0001_0433` | 信息 | 预留禁用 | — |
| `16#0001_0366` | 故障 | 年份超出 1900~2099 窗口 | `FC_DL_LeapYearChk` |
| `16#0001_0367` | 故障 | 预留 | — |
| `16#0001_0368` | 故障 | 预留禁用 | — |
| `16#0001_0369` | 故障 | 占用超时，已强制归还（调用方必须处理） | `FB_DL_SemaMutex` |
| `16#0001_036A` | 故障 | 非法状态兜底，已复位 `eFree` | `FB_DL_SemaMutex` |
| `16#0001_036B` | 故障 | 申请或释放计数达饱和值，统计不可信（互斥本体仍工作） | `FB_DL_SemaMutex` |

> **R20 批次 100 槽（20 件 × 5 槽）跨文件零重叠**，终审求差断言复跑通过；`16#0001_` 段游标推进至 **信息级 `0434` / 故障级 `036C`**（两库共用同一游标）。
> **口径说明（R20 诚实更正）**：全库并非绝对零重叠——`DL_Algo` 自 R3~R4 起存在 `16#0002_00xx` **公共码子带**（参数越界已钳位等通用语义，被多件刻意共享），与 `0001_` 段的专用码体系不冲突，但「全库零重叠」这一表述在该子带上不成立。已在 `ROADMAP.md §23.1` 挂账审计。

---

## v1.13.0 ｜ 2026-11-16 ｜ R19 位串扩族时序层：FB_DL_BitShiftRegister 1 件 + 终审修复

- `FB_DL_BitShiftRegister`：宽度 1~32 可组态位串逐拍移位寄存器（溢出位/置位数/饱和计数，清空优先，T2-1 LGF Bit Logic 时序层）（码位见 .st 头注释码位总账）。
- **终审修复（v1.0.1）**：`FB_DL_BitShiftRegister` 溢出位提取改为跟随移位方向（右移取 bit0）；v1.0.0 右移方向误用最高有效位掩码，bShiftOut 输出错误（R19 终审）。

> `16#0001_` 段游标：信息级下件起点 **040C**（04xx 子带）｜故障级下件起点 **0330**（本轮 Base+MathData 共用，6 件 30 槽）。

---

## v1.12.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：边沿分频 + 首出锁存 + 脉冲展宽 + 位段块搬移 4 件 / R18 Scenario Lane — 4 Signal-Shaping Components

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。终审 4/4 通过，机检 16 规则全 PASS。

### 新增组件（4 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_EdgeDivider` | FB | 每 N 个上升沿输出一个单周期脉冲（双作用气缸交替动作） | `bIn` / `uDivide` |
| `FB_DL_FirstOutLatch` | FB | 16 路故障源并行输入，首个到来者锁存为唯一首出原因 | `aSrcFault` / `bReset` |
| `FB_DL_PulseStretch` | FB | 窄脉冲展宽到下游最小响应时间以上 | `bIn` / `tMinPulse` |
| `FC_DL_BitSegmentBlockMove` | FC | 段表驱动，一次调用搬移源 128 位窗口内至多 8 个位段 | `auDstBit` / `auWidth` |

### 码位台账追加（R18）/ Error Code Ledger Additions (R18)

> 本轮 4 件码位逐件映射以 `INDEX_REGISTRY.json` 的 `code_segment` 为准（已登记）；全库跨文件重叠复测 = 0（CLASH=NONE）。本子库不新增封存带。

## v1.11.0 ｜ 2026-11-16 ｜ R17 T0 纯函数第 4 轮：LWORD 64 位域防御包装 4 件 / R17 T0 Pure-Function Lane #4 — 4 LWORD 64-bit Field Wrappers

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。终审 **4/4 件级零缺陷 PASS**（Shl/ShrLwordEx 闸后调用、nN ≥ 64 常量路径置全零不调内建；Rol/RorLwordEx MOD 64 归一 + 归一后零移位直通；循环移位「归一」与移位件「置零」口径刻意相反且头注释互引声明）。机检 16 规则 4/4 PASS fail=0。

### 新增组件（4 件）/ Added Components

| 组件 / Component | T0 组 | 标准原型 | 防御要点 / Defense |
|---|---|---|---|
| `FC_DL_ShlLwordEx` | T0-7 | SHL（LWORD） | nN ≥ 64 常量路径置 0，不调内建（64 位口径同源 R14 32 位 ShlEx） |
| `FC_DL_ShrLwordEx` | T0-7 | SHR（LWORD） | 同上；无符号位串不做符号位扩展 |
| `FC_DL_RolLwordEx` | T0-7 | ROL（LWORD） | MOD 64 归一 + 零移位直通（R48 64 位版） |
| `FC_DL_RorLwordEx` | T0-7 | ROR（LWORD） | 同上 |

### 码位台账追加（R17 收口实测口径，全库正则复测）/ Error Code Ledger Additions (R17, registry-regex-verified)

| 码位 | 级别 | 语义 / Meaning | 组件 | 状态 |
|---|---|---|---|---|
| `16#0001_0208` | 信息 | 移位量 ≥ 64 超宽置 0 | `FC_DL_ShrLwordEx` | ⚠️ 与存量 `FC_DL_TempUnitConvert` 故障级 `0207~0208` 撞车 |
| `16#0001_0209` | 信息 | 预留禁用 | `FC_DL_ShrLwordEx` | 空闲独占 |
| `16#0001_020A` | 信息 | 移位量 ≥ 64 MOD 64 归一 | `FC_DL_RolLwordEx` | 空闲独占 |
| `16#0001_020B` | 信息 | 预留禁用 | `FC_DL_RolLwordEx` | 空闲独占 |
| `16#0001_020C` | 信息 | 移位量 ≥ 64 MOD 64 归一 | `FC_DL_RorLwordEx` | 空闲独占 |
| `16#0001_020D` | 信息 | 预留禁用 | `FC_DL_RorLwordEx` | 空闲独占 |
| `16#0001_021D` | 信息 | 移位量 ≥ 64 超宽置 0 | `FC_DL_ShlLwordEx` | ⚠️ 与存量 `FB_DL_StringTokenStream` 故障级 `021C~021E` 撞车 |
| `16#0001_021E` | 信息 | 预留禁用 | `FC_DL_ShlLwordEx` | ⚠️ 同上撞车 |
| `16#0001_02F7`~`02F9` | 故障 | 预留禁用 | `FC_DL_ShlLwordEx` | 空闲独占 |
| `16#0001_02FA`~`02FC` | 故障 | 预留禁用 | `FC_DL_ShrLwordEx` | 空闲独占 |

> **R18 改判专项（实测落点全空闲，待执行）**：ShlLwordEx `021D→0217`/预留 `021E→0218`；ShrLwordEx `0208→0219`。改判后 R18 新件码位游标：**信息级 `0221` 起**（`0213`~`0219` + `0220` 8 码由改判专项占用：LintToDintSat→0220、RealToLintSat→0215/0216、LrealToLintSat→0213/0214、ShlLwordEx→0217/0218、ShrLwordEx→0219），**故障级 `0306` 起**（`02CA`~`0305` 全占用）。**立规 R61：码位游标必须以注册表正则实测为准，不得沿用上一轮战报口头交接值。**

---

## v1.9.0 ｜ 2026-11-16 ｜ R13 跨字位串整串循环旋转 + 状态字掩码比较与差异定位（LGF Bit Logic / Comparator 组收口，2 件）+ 存量 R39 修复 1 件 / R13 Bit-String Rotation, Mask Compare & Legacy R39 Fix

**变更性质**：MINOR（新增 2 个组件）+ PATCH（存量 `FB_DL_InterlockMatrix` v1.0.0 → v1.0.1，R39 语义修复，引脚契约零变化）。终审 **2 件新增零修改 PASS**（泳道 B 独立验算：位旋转 3000 组随机对拍位守恒且与参考实现一致；掩码比较全向量实算一致），存量修复件经人工逐拍推演裁定后升版。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 39 | `FC_DL_BitArrayRotate` | FC | 252 | 1.0.0 | lgf-bitlogic | 跨字位串整体循环旋转：1~4 个 `DWORD` 视为 32~128 位位串，左移或右移 n 位、移出位回卷（与 BitArrayExtract 的「抽」/Insert 的「插」构成位段族三件套）；移位量先取绝对值再对总宽取模，永不做超宽移位；负值恒右移、方向归一表写死；结果先落暂存区再整体写回，源与目标同址（别名）安全；整圈也报「被归约」信息码 013D / Cross-word bit-string rotation with alias-safe staging |
| 40 | `FC_DL_MaskCompare` | FC | 191 | 1.0.0 | lgf-bitlogic / lgf-comparator | 状态字掩码比较与差异定位：判「值按掩码比较是否等于期望」，同出差异位图、差异位数与首个差异位号（低位向高位扫描），报警可直接定位到具体那一位；位宽掩码与调用方掩码双重屏蔽严格串联；位宽 32 走满一常量分支禁 `SHL(x,32)`；掩码为 0 恒匹配但置 0140 提示 / Mask compare with difference bitmap and first differing bit |

### 修复 / Fixed

| 组件 | 版本变化 | 内容 |
|---|---|---|
| `FB_DL_InterlockMatrix` | 1.0.0 → **1.0.1** | **R39 存量修复**（R13 存量专案）：段 8 未使能覆盖原先把 `eStateInt` 无条件改写为 `eDisabled`，而 `eLatched` / `eFault` 两态的复位沿消化位于其后段 9 的 CASE 分支内——禁用期间按下的复位沿被整拍吞掉，首因锁存与配置故障均需二次复位才清除。改为两个持有复位沿的状态不被禁用覆盖，其余态行为不变；引脚契约与码位零变化 |

### 故障码台账追加（R13 码位登记，经终审全库复核 0 重叠）/ Error Code Ledger Additions (R13)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_013D` | 信息级 | 移位量已归约（超 127 位上限或跨越整圈） | FC_DL_BitArrayRotate |
| `0001_013E` | 信息级 | 字数超上限已钳到 4 | FC_DL_BitArrayRotate |
| `0001_013F` | 信息级 | 位宽超上限已钳到 32 | FC_DL_MaskCompare |
| `0001_0140` | 信息级 | 生效掩码为 0（恒匹配，提示掩码与位宽矛盾） | FC_DL_MaskCompare |
| `0001_021F` | 故障级 | 有效字数小于 1（逻辑错误，目标数组不写入） | FC_DL_BitArrayRotate |
| `0001_0220` | 故障级 | 有效位宽小于 1（逻辑错误，差异位图保持 0） | FC_DL_MaskCompare |

---

## v1.8.0 ｜ 2026-11-15 ｜ R12 跨字位流窗口读写 + 开闭区间成员判定 + 位图变化监视（LGF Bit Logic 数组批量族落地，4 件）/ R12 Cross-Word Bit Window & Bitmap Change Watch

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。对应 Round 12「Level 0 位/区间原子算子从单字推到跨字数组」定位（来源标签 lgf-bitlogic / lgf-comparator，仅借鉴分组骨架与「源 / 起位 / 位宽」参数域，clean-room 未复制源码）。终审 **4 件中 3 件零修改 PASS，1 件修复后 PASS**（`FB_DL_BitArrayChangeWatch` 1 条严重缺陷，升 v1.0.1）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 35 | `FC_DL_BitArrayExtract` | FC | 237 | 1.0.0 | lgf-bitlogic | 跨字位流窗口提取：`DWORD` 数组第 1 元素承载位 0 到 31，按「起始位 + 位宽」取出可达 64 位的位窗并右对齐，同出本次生效掩码与截断后实际宽度；闸门顺序固定「字数 → 偏移 → 宽度 → 越界截断」，非法移位量绝不进入 `SHL`/`SHR`；宽度 64 走满宽常量分支，禁 `SHL(x, 64)` / Cross-word bit window extraction with right-aligned output and effective mask |
| 36 | `FC_DL_BitArrayInsert` | FC | 247 | 1.0.0 | lgf-bitlogic | 跨字位段原子写入：与提取件严格成对，窗口跨字时先算两个字完整新值再一次性落盘，只改窗口内的位；回报实际改动字数 `nChanged`（值未变的字不计入），供上游判「是否真的写了」 / Atomic cross-word bit-field write reporting the number of words actually changed |
| 37 | `FC_DL_IntervalMembership` | FC | 214 | 1.0.0 | lgf-comparator | 开闭区间成员判定：开闭组合做成独立枚举（左闭右开 / 左开右闭 / 双闭 / 双开），同出到最近边界的有符号裕量（内正外负、临界为零）与「恰在边界」标志；端点倒置判非法不交换，容差非正回落最小值（浮点判等永不相等） / Interval membership with four openness combinations and signed margin |
| 38 | `FB_DL_BitArrayChangeWatch` | FB | 320 | **1.0.1** | lgf-bitlogic | **v1.0.1** —— 位图变化监视：逐拍对 `DWORD` 数组位图做位级异或，输出本拍变化掩码、变化位数、首个变化位绝对位号，并累计跳变位数、给出连续判稳标志与四相状态机；跳变计数饱和不回绕，判稳拍数钳到 1~100 / Bitmap change watch with per-word mask, population count, first changed bit and settle detection |

### 故障码台账追加（R12 码位登记，经终审全库复核）/ Error Code Ledger Additions (R12)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0125` | 信息级 | 位窗起始位越界（负偏移或 ≥ 位流总位数），早退并输出全零 | FC_DL_BitArrayExtract |
| `0001_0126` | 信息级 | 位窗宽度越界（小于 1 或大于 64），早退并输出全零 | FC_DL_BitArrayExtract |
| `0001_0127` | 信息级 | 位窗跨字截断（越过位流末端，或窗口伸展到第三个字），按可用位截断后继续计算 | FC_DL_BitArrayExtract |
| `0001_0128` | 信息级 | 写入窗口起始位越界，目标数组保持不变 | FC_DL_BitArrayInsert |
| `0001_0129` | 信息级 | 写入窗口宽度越界，目标数组保持不变 | FC_DL_BitArrayInsert |
| `0001_012A` | 信息级 | 写入窗口跨字截断，按可用位写入 | FC_DL_BitArrayInsert |
| `0001_012B` | 信息级 | 区间端点倒置（下限大于上限），判非法不交换、`bValid` 置假 | FC_DL_IntervalMembership |
| `0001_012C` | 信息级 | 端点或被测值非有限（NaN / 无穷），判非法 | FC_DL_IntervalMembership |
| `0001_012D` | 信息级 | 监视字数超上限已钳位到 8 并照常服务（小于 1 走 `021A` 故障） | FB_DL_BitArrayChangeWatch |
| `0001_012E` | 信息级 | 判稳拍数越界已钳位到 1~100 | FB_DL_BitArrayChangeWatch |
| `0001_012F` | 信息级 | 跳变累计饱和（到 `16#FFFF_FFFE` 停值不回绕） | FB_DL_BitArrayChangeWatch |
| `0001_021A` | 故障级 | 监视字数小于 1（组态错），锁存 `bError`，掩码与计数清零 | FB_DL_BitArrayChangeWatch |
| `0001_021B` | 故障级 | 非法状态兜底（枚举被在线改坏或跨版本不兼容），锁存并冻结输出 | FB_DL_BitArrayChangeWatch |

**号段占用声明**：本批 `DL_Base` 占用信息级 `0001_0125`~`0001_012F`（连续 11 码，`0124` 及以前为 R11 及以前的存量占用，其中 `0111` / `0209` 仍为历史空置位）与故障级 `0001_021A`~`021B`（`0218` 为 R11 存量、`0219` 归 `DL_MathData`）。终审逐码求差：与全库既有码位零重叠。

### 缺陷修复 / Fixed

| 组件 / Component | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| `FB_DL_BitArrayChangeWatch` | **严重** | 使能为假的同一拍按复位：段 4 在 CASE 之前无条件把 `eStateInt` 改回 `eIdle`，故 CASE 只进 eIdle 分支（该分支见 `bError` 又置回 `eFault`），**eFault 主体整拍被跳过、`fbTrigReset.Q` 只亮一拍即失**，故障永不清除。现场「停机（掉使能）→ 按复位 → 上使能」序列必然踩中，需二次复位 | 判据补 `AND (eStateInt <> E_DL_BitWatchState.eFault)`；故障态由自身复位沿出口，掉使能的清态职责在故障态由 eFault 分支承担（掩码、计数、首变位同样清零），正常态行为不变 |

### 变更说明 / Change Notes

- **跨字件与单字件四件互斥**：`FC_DL_BitGet`（单字内单个位）/ `FC_DL_BitFieldExtract`（单字内 1~32 位段）/ `FB_DL_UnpackWordToBits`（单字拆 16 位）/ **本批 `FC_DL_BitArrayExtract` + `FC_DL_BitArrayInsert`**（跨字位流窗口，宽度可达 64 位）。四者职责正交，本批不复用也不替代其中任何一件。
- **区间件不替代公差件**：`FC_DL_IntervalMembership` 给「是否在区间内 + 到边界裕量」，`FB_DL_ToleranceWindow` 给「三态判定 + 迟滞回差 + 越差单拍告警」。前者是纯几何、后者带状态，二者不互相调用。
- **新增允许的契约式前置条件**：`FC_DL_BitArrayExtract` / `FC_DL_BitArrayInsert` 的数组形参在函数内无法探测实际长度，「`nSourceCount` / `nTargetCount` 不得大于调用方实际数组长度」由调用方在组态时保证；此为全库唯一允许的契约式前置条件，已在两文件头注释显式登记。
- **红线状态**：R1~R44 全部通过，机检 0 命中；全库码位跨文件重叠 = 0（终审断言脚本复跑）。

---

## v1.7.0 ｜ 2026-11-15 ｜ R11 年粒度区间窗 + 环形回绕计数（LGF Date and Timer / Counter 组续深，2 件）/ R11 Year Window & Rollover Counter

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 11 泳道 A「LGF Date and Timer / Counter 组续深」（来源标签 lgf-datetime / lgf-counter，仅借鉴 LGF 各组的组件切分与参数域，clean-room 未复制源码）。终审 **PASS 14 件批次中的本库 2 件均为零修改 PASS**，无版本升级、无缺陷修复。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 33 | `FB_DL_YearWindowCheck` | FB | 494 | 1.0.0 | lgf-datetime | 年粒度区间窗判定（允许跨年、按年循环重复）：整数日序数法（相对 2000 年 1 月 1 日的连续日序，LINT 中间量）代替浮点与时间类型；结束日早于起始日自动识别为跨年窗并补一个年度周期；把当前日期折叠到以窗起点为原点的单周期内，多年度组态（2026~2031）一次配置即按年生效；输出入窗/出窗单拍、距下次窗沿天数、空窗组态非法标志；三日期全部引脚注入，不读平台时钟、不猜时区 / Year-granularity window with cross-year support and ordinal-day arithmetic |
| 34 | `FB_DL_RolloverCounter` | FB | 383 | 1.0.0 | lgf-counter | 环形回绕可逆计数器（0~上限闭区间）：到顶加回 0、到底减回上限，同时输出回绕单拍脉冲与可负的净回绕圈数，圈数饱和不静默回绕；回绕一律「比较 + 赋值」，禁 `MOD`（无符号域取模跨平台行为不一致的历史坑）；装载电平优先于复位沿与计数沿，双向同拍净变化 0 只置信息码；不做任何预设比较（「到限冻结」属饱和件语义） / Ring-domain reversible counter with net turn counting and MOD-free wrap |

### 故障码台账追加（R11 码位登记，经终审全库复核）/ Error Code Ledger Additions (R11)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_011E` | 信息级 | 日期参数越界已钳位照算（年越界 / 月越界 / 日超当月天数 / 折叠循环触顶），扫描不中断 | FB_DL_YearWindowCheck |
| `0001_011F` | 信息级 | 窗口归一后为空（跨度小于零，如起止同日且不含尾），`bInvalidConfig` 置位、`bInWindow` 强制 FALSE | FB_DL_YearWindowCheck |
| `0001_0120` | 信息级 | 装载值超上限已钳位 / 上下限超域已钳位 / 同拍双向已丢弃 / 圈数饱和已停止累加，均只进事件码 | FB_DL_RolloverCounter |
| `0001_0218` | 故障级 | 回绕上限小于 1（退化），计数冻结并锁存 `bError` | FB_DL_RolloverCounter |

**号段占用声明**：本批 `DL_Base` 占用信息级 `0001_011E`~`0001_0120`（连续三码，`011D` 及以前为 R10 及以前的存量占用）与故障级 `0001_0218`（`0217` 为 R10 存量，本批未占 `0219`——`0219` 归 `DL_MathData` 本批 `FC_DL_CalcDistance3D`）。终审逐码求差：与全库既有码位零重叠。

### 变更说明 / Change Notes

- **年窗不复用月窗**：`FB_DL_YearWindowCheck`（年粒度、跨年合法）与 `FB_DL_MonthWindowCheck`（月粒度、跨月非法，窗口截断不跨月）、`FB_DL_TimeWindowCheck`（日内时分秒粒度）、`FB_DL_OccScheduleWindow`（多时刻窗排程）四件日历族语义相反、互斥且零互相调用；复用必然错判（跨年合法 vs 跨月非法的方向相反）。
- **计数器族现已五件**：`FB_DL_EventCounter`（单向事件累加）/ `FB_DL_ModuloCounter`（取模工位索引）/ `FB_DL_PresetCounterSat`（单预设饱和冻结）/ `FB_DL_BidirectionalCounter`（CTUD 双预设比较）/ `FB_DL_RolloverCounter`（环形回绕 + 净圈数）。本块刻意不实现「到限冻结」与「取模」，与四件存量件职责正交。
- **零浮点声明**：本批两件全部为整数域运算（LINT / DINT / UDINT），浮点判等容差红线不适用，已在两文件头注释显式声明。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0（终审断言脚本复跑）。

---

## v1.6.0 ｜ 2026-11-15 ｜ R10 LGF Bit Logic / Date and Timer / Counter 三组横向补强（3 件）/ R10 Three-Group Extension

**变更性质**：MINOR（新增 3 个组件），无破坏性变更，无迁移动作。对应 Round 10「DL_Base 三组横向补强」（来源标签 lgf-bitlogic / lgf-datetime / lgf-counter，RAW_NOTES_R10 S-3：仅借鉴 LGF 各组功能分类与参数域，clean-room 未复制源码）。终审 **PASS with fixes**：3 件全部零修改 PASS，无版本升级、无缺陷修复。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 30 | `FC_DL_BitFieldExtract` | FC | 216 | 1.0.0 | lgf-bitlogic | DWORD 任意位段提取（偏移 + 宽度参数化，右对齐输出 + 生效掩码同出）：`nWidth = 32` 走常量掩码分支规避 `SHL(x, 32)` 跨平台未定义行为；`nWidth = 0` 与越界双重拒绝，跨字按可用位截断并置信息级码 / Parameterised DWORD bit-field extraction with wrap-safe full-width branch |
| 31 | `FC_DL_WeekOfYearCalc` | FC | 316 | 1.0.0 | lgf-datetime | 年月日 → ISO-8601 周年/周序/周内日（Zeller 同余求星期 + 周四归属法）：跨年归属（12-31 属次年第 1 周、1-1 属上年第 52/53 周）独立语义；闰年 1/2 月 31/30 折算前置；年域 1970~2099 / Date to ISO week date with Thursday attribution and Zeller congruence |
| 32 | `FB_DL_BidirectionalCounter` | FB | 387 | 1.0.0 | lgf-counter | CTUD 全语义双向计数器（DINT 域，加/减/装载/复位四输入 + 双预设）：加计数同拍优先、装载拍跳过计数、饱和不回绕、`bAtMax`/`bAtMin` 三律（预清零-置位-保持）、预设倒置锁存 / Full CTUD-semantics bidirectional counter with dual presets and saturation |

### 故障码台账追加（R10 码位登记，经终审全库复核）/ Error Code Ledger Additions (R10)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0113` | 信息级 | 位偏移越界（须 0~31），结果 0，`bValid = FALSE` | FC_DL_BitFieldExtract |
| `0001_0114` | 信息级 | 位宽越界（须 1~32），结果 0，`bValid = FALSE` | FC_DL_BitFieldExtract |
| `0001_0115` | 信息级 | 跨字截断，按可用位计算，`bValid = FALSE` | FC_DL_BitFieldExtract |
| `0001_0116` | 信息级 | 年份越界（须 1970~2099），输出全 0 | FC_DL_WeekOfYearCalc |
| `0001_0117` | 信息级 | 月份或日非法（含平年 2 月 29 日），输出全 0 | FC_DL_WeekOfYearCalc |
| `0001_0118` | 信息级 | 装载值越界被钳位，装载照常完成 | FB_DL_BidirectionalCounter |
| `0001_0215` | 故障级 | 预设倒置（PV_UP ≤ PV_DN），锁存 `bError` | FB_DL_BidirectionalCounter |
| `0001_0216` | 故障级 | 保留位，本块无 CASE 主状态机，仅作防御式默认码 | FB_DL_BidirectionalCounter |

### 变更说明 / Change Notes

- **职责分离**：`FC_DL_BitFieldExtract`（任意位段提取，只读）与既有 `FC_DL_WordBitPack`（位段读-改-写）、`FC_DL_BitGet`（单位提取）、`FC_DL_PackBitsToWord` / `FB_DL_UnpackWordToBits`（16 点 BOOL 全字）四点正交，互不替代；`FB_DL_BidirectionalCounter`（CTUD 全语义、饱和）与既有 `FB_DL_PresetCounterSat`（单预设、倒置冻结）、`FB_DL_EventCounter`（回绕/饱和双模、比较输出）、`FB_DL_ModuloCounter`（取模索引）职责分离，**「倒置冻结 vs 倒置不冻结」策略差异已在两处手册写明**。
- **规格偏离留档（R11）**：`FC_DL_WeekOfYearCalc` 的算法由规格的「速算式」整体替换为 **Zeller 同余 + 周四归属法**——规格速算式有两处硬错（对 2026-01-01 得 3，正确为 4；未对闰年 1/2 月做 31/30 折算）。总监独立复算 V1~V5 全部命中后裁定**采纳**，并要求修订 `ROUND_PLAN` 规格模板（观察项 O-5）。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0（终审断言脚本复跑）。

---

## v1.5.0 ｜ 2026-11-15 ｜ R9 LGF Comparator / Bit Logic / Date and Timer / Counter 四组深化（5 件）/ R9 Four-Group Deepening

**变更性质**：MINOR（新增 5 个组件），无破坏性变更，无迁移动作。对应 Round 09「DL_Base LGF 四组回补」交付（来源标签 lgf-comparator / lgf-bitlogic / lgf-datetime / lgf-counter，RAW_NOTES_R9 S-2/S-4/S-5/S-6：仅借鉴 LGF 各组功能分类与参数域，clean-room 未复制源码）。终审 **PASS with fixes**：5 件中 4 件修复后 v1.0.1（缺陷 6 处：D-07 码位越段撞设备族 ×2、D-08 码位冲突 ×1、D-09 USINT 回绕绕过判界、D-11 退化组态文档语义错、D-12 C6 推演表述勘误），MonthWindowCheck 零修改 PASS。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 25 | `FB_DL_ToleranceWindow` | FB | 358 | **1.0.1** | lgf-comparator | 公差窗口三态判定（合格/低于下差/高于上差）+ 可配置迟滞回差防临界抖动 + 双向越差单拍告警；与 FC_DL_Hysteresis / FC_DL_Deadband 职责分离（对称公差窗 vs 二值通断 vs 死区抑制） / Tolerance-window three-state judge with hysteresis |
| 26 | `FC_DL_LimitClassify` | FC | 210 | **1.0.1** | lgf-comparator | 四阈值五档限值分档（低低/低/正常/高/高高）：闭区间归属贴线归严档 + 阈值序非法拒绝（eInvalid + 置码，禁止静默分档）；退化组态语义终审勘误（双警告限相等时正常档为空集） / Four-limit five-band classification with reject path |
| 27 | `FC_DL_WordBitPack` | FC | 231 | **1.0.1** | lgf-bitlogic | WORD 位段参数化打包/解包（偏移+宽度一函数完成读-改-写原子语义）：越界拒绝禁半写；v1.0.1 补 nWidth>16 / nOffset>=16 两项单项判界（USINT 域 15+250 回绕为 9 可绕过原判界）；WordBitPack V5 向量经总监逐位验算裁定计划表笔误（16#1264 → 16#12A4） / Parameterized bit-field pack/unpack with wrap-safe bounds |
| 28 | `FB_DL_MonthWindowCheck` | FB | 370 | 1.0.0 | lgf-datetime | 月内第 N 天 / 月末倒数第 N 天日期窗判定（窗口宽度可配、窗口跨月末不跨月截断）+ 年度模式（仅指定月生效）；闰年月长独立实现，日期全部引脚注入；与 FB_DL_TimeWindowCheck（日内时窗）正交 / Monthly/annual day-window check with leap-year handling |
| 29 | `FB_DL_PresetCounterSat` | FB | 358 | **1.0.1** | lgf-counter | 带饱和预设计数器：上/下双向计数到达上下限饱和不回绕（批次/满载场景），装载优先级最高、同拍双计数抵消、bThreshold 首达单拍（R25 三律）；与 EventCounter（回绕+比较）和 ModuloCounter（取模索引）职责分离 / Saturating preset counter for batch/pallet counting |

### 故障码台账追加（R9 码位登记，经终审全库复核）/ Error Code Ledger Additions (R9)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0112` | 信息级 | 迟滞回差越界，已钳位到 0..fTolerance/2 | FB_DL_ToleranceWindow |
| `0001_0213` | 故障级 | 公差带宽 <= 0 参数非法，判定锁 eUnKnown | FB_DL_ToleranceWindow |
| `0001_0214` | 故障级 | 四阈值序非法（倒置/容差内倒置），返回 eInvalid | FC_DL_LimitClassify |
| `0001_0108` | 故障级 | 位段越界拒绝（宽度 0 / 宽度>16 / 偏移>=16 / 求和>16） | FC_DL_WordBitPack |
| `0001_0109` | 信息级 | 参数钳位（目标日超月长 / 窗宽越界 / 生效月越界） | FB_DL_MonthWindowCheck |
| `0001_0203` | 信息级 | 日期参数非法（年/月/日越界、目标日为 0） | FB_DL_MonthWindowCheck |
| `0001_0212` | 故障级 | 上限预设 < 下限预设，计数冻结锁存 | FB_DL_PresetCounterSat |

**码位终审改判（本子库 3 处）**：`FB_DL_ToleranceWindow` 原拟 `0003_0101/0201` 属 DL_Device 段位且与设备族「参数钳位 / 非法状态」共用码冲突，`FC_DL_LimitClassify` 原拟 `0003_0201` 同理——均改归 `0001_xxxx` 段顺延（010A~010F、0204~0206 为本轮 DL_MathData 占用，逐条比对无冲突）。

### 变更说明 / Change Notes

- **职责分离**：ToleranceWindow（对称三态窗）与 LimitClassify（非对称四限值五档）同为比较器但语义正交；WordBitPack（任意位段偏移+宽度）与既有 PackBitsToWord / UnpackWordToBits（16 点 BOOL 全字打包解包）互不替代。
- **终审致命教训（D-01 关联）**：本轮编码者与机检脚本的「码表核对未占用」结论全部不可采信（6 件 15 处冲突中 4 处编码者注释明确写了「经核对未占用」）——码位唯一性必须以脚本对全库求差断言（进化日志 R30）。
- **USINT 回绕绕过判界（D-09）**：`FC_DL_WordBitPack` 原判界只查 `nOffset + nWidth > 16`，USINT 域 15+250=265 回绕为 9 漏判 → `SHL(1,250)` 平台未定义行为；已扩为四项单项判界并新增验收 V7 固化。
- **红线状态**：R1~R8 全部通过，机检 0 命中；全库码位跨文件重叠 = 0（终审断言脚本复跑）。

---

## v1.4.0 ｜ 2026-11-15 ｜ R7 计数器组开组（T2-1 LGF Counter ☐→◐）/ R7 Counter Group Opened

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 07「DL_Base LGF Counter 组」交付（来源标签 lgf-counter，RAW_NOTES_R7 S-1：仅借鉴 LGF 计数器族功能域语义——双向计数、预置装载、比较输出、取模回绕，clean-room 未复制源码）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 23 | `FB_DL_EventCounter` | FB | 6 | 1.0.1 | lgf-counter | 双向事件计数器（DINT 域）：递增/递减脉冲沿独立计数、预置装载（bLoad 优先级最高，同拍覆盖计数脉冲置信级）、高/低阈值比较输出每拍重算、回绕/饱和两种越界模式可选；双脉冲同拍抵消置信级；DINT 极值先判界后运算（v1.0.1 杜绝 +1/-1 回绕穿透）与复位拍最高优先 / Bidirectional DINT event counter with preset load, wrap/saturate modes and boundary pre-check |
| 24 | `FB_DL_ModuloCounter` | FB | 5 | 1.0.0 | lgf-counter | 取模工位索引计数器（转盘/弹夹）：0..nMod-1 条件加减法回绕（禁用取余运算符对负数的平台差异，DINT 域运算后显式转回 UINT，三平台行为一致）、带合法性校验的跳步（越界拒绝置信级）、双向同拍抵消、跨零点回绕事件一拍；模数 <2 故障锁存 / Modulo station-index counter with conditional wrap arithmetic and validated jump |

### 变更说明 / Change Notes

- **职责分离**：与 `FC_DL_BitCount`（位统计）、`FB_DL_RuntimeMeter`（时间累计）职责正交；`FB_DL_EventCounter`（通用事件计数）与 `FB_DL_ModuloCounter`（取模工位索引）同为计数器但语义不同，非重复组件。
- **接口契约**：全部引脚名称、类型、方向、默认值与 `ROUND_PLAN_R7.md` 逐字一致；R23 口径——两块均为事件型，免首扫，无 bInit。
- **故障码台账追加（R7）**：见上节故障码表（0001_0101~0104 / 0001_0210~0211），经 DL_Base 码表核对未占用。
- **终审修复（v1.0.1）**：`FB_DL_EventCounter` 2 处——① DINT 极值 +1/-1 回绕穿透饱和/回绕判据（改先判界后运算）；② 复位与计数脉冲同拍时计数覆盖复位（复位拍最高优先前置分支）。
- **红线状态**：R1~R7 全部通过，机检 0 命中。

---

## v1.3.0 ｜ 2026-11-15 ｜ R5 日历与时间窗补强 / R5 Date & Time-Window Reinforcement

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 05（R5）「DL_Base 补强族」交付（来源标签 lgf-datetime）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 21 | `FC_DL_DayOfWeekCalc` | FC | 3 | 1.0.0 | lgf-datetime | 年月日 → 星期几换算原子函数（ISO-8601 序周一=1…周日=7，与 GB/T 7408 / MES 排产一致）：Sakamoto 公开算法 clean-room，闰年 4/100/400 判定，参数域校验（年 1980..2099），越界返回 `eInvalid(0)` / Day-of-week atomic function, ISO-8601 numbering, Sakamoto clean-room |
| 22 | `FB_DL_TimeWindowCheck` | FB | 4 | 1.0.0 | lgf-datetime | 每日时间窗判定块（单一语义，不做 MODE 巨无霸）：支持跨零点窗（22:00→06:00）、开=关 24h 全开语义、星期使能表（ISO 序）、窗口开/闭沿单发；时刻/星期引脚注入禁读 CPU 钟 / Daily time-window check with midnight-crossing and weekday table |

### 变更说明 / Change Notes

- **接口契约**：`E_DL_Weekday` 枚举随 `FC_DL_DayOfWeekCalc` 同文件发布（`eInvalid=0 / eMonday=1 … eSunday=7`）。
- **故障码**：沿用 DL_Base 既有 `16#0001_xxxx` 段，新增 `0001_0201`（日期参数越界，信息级）、`0001_0202`（时刻/星期参数越界，信息级：当前时刻越界按 FALSE 处理、窗口参数越界钳位照算），与既有码表无冲突。
- **规格偏离留档（R11）**：`FB_DL_TimeWindowCheck` 新增 `uWeekdayNow : USINT := 1` 输入引脚（规格未提供星期索引注入，`aWeekdayEnable` 表无法自索引）；`bReset` 语义定义为上升沿清除当拍信息级码并重新评估窗口。

### 故障码台账追加（R7 码位登记）/ Error Code Ledger Additions (R7)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0101` | 信息级 | 双脉冲同拍抵消（净变化 0，瞬时型） | FB_DL_EventCounter |
| `0001_0102` | 信息级 | 装载覆盖计数（bLoad 优先级最高） | FB_DL_EventCounter |
| `0001_0103` | 信息级 | 跳步目标越界拒绝（索引保持） | FB_DL_ModuloCounter |
| `0001_0104` | 信息级 | 双向步进同拍抵消（索引不变） | FB_DL_ModuloCounter |
| `0001_0210` | 故障级 | 计数下限 ≥ 上限（锁存，仅复位路径清码） | FB_DL_EventCounter |
| `0001_0211` | 故障级 | 模数非法（nMod < 2，锁存，仅复位路径清码） | FB_DL_ModuloCounter |

- **红线状态**：R1~R7 全部通过，机检 0 命中。

### 已知限制 / Known Limitations

1. `FC_DL_DayOfWeekCalc` 年域固定 1980..2099（规格口径）；超出域的 MES 需求须由调用方换算。
2. `FB_DL_TimeWindowCheck` 只做每日窗单一语义；每周/每月/每年窗按矩阵扩产规则拆独立块（ROADMAP 扩产条目），禁止塞 MODE 参数。

---

## v1.2.0 ｜ 2026-11-15 ｜ 安全联锁与冗余调度，Level 0 收口 / Safety, Interlock and Redundancy — Level 0 Closure

**变更性质**：MINOR（新增 4 个组件）+ 库级语法补全（Fixed，见下），无破坏性变更，无迁移动作。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 17 | `FB_DL_TwoHandSafety` | FB | 6 | 1.0.0 | iec60204+iso13851 | 双手同步校验与防旁路状态机：同步窗/释放窗/卡死判定三级递进，卡死按钮升级为旁路嫌疑并锁存 / Two-hand synchronism check with anti-bypass, stuck-button escalation latched |
| 18 | `FB_DL_InterlockMatrix` | FB | 7 | 1.0.0 | isa18-2+lgf-bitlogic | 16 路联锁汇总与首因追踪：停机级/提示级双掩码，首因通道号+位图+全局序号，复位挂起不清根因 / 16-channel interlock matrix with first-out tracking and reset pending |
| 19 | `FB_DL_RedundantSwitch` | FB | 8 | 1.0.0 | lgf-comparator | 双通道冗余选择器：偏差延时确认、限速无扰切换、抖振锁定，两路矛盾时默认保持最后有效值 / Dual-channel redundancy selector with bumpless switchover and chatter lock |
| 20 | `FB_DL_DutyStandbyRotation` | FB | 9 | 1.0.0 | lbp-basic-process+lead-lag | 8 台泵/风机主备轮值均衡调度：按累计运行时间排序、先启后停、双向最小时长保护、故障机越权停机 / Duty/standby rotation scheduler with run-first-stop-later discipline |

### 修复 / Fixed（库级语法补全 / Library-level syntax completion）

**全库 40 个 POU 缺 `END_FUNCTION` / `END_FUNCTION_BLOCK` 终结符**：IEC 61131-3 / CODESYS 关键字规范要求 POU 声明与终结符成对出现（`FUNCTION_BLOCK … END_FUNCTION_BLOCK`、`FUNCTION … END_FUNCTION`），缺失即无法通过编译器解析。该缺陷由本轮终审机检发现，属 **R1/R2 两个批次 26 个旧组件的库级遗留**，已全库补齐；旧组件逐文件逻辑未变，故版本号不变，JSONL 语料 `output` 已同步重建（字节级一致，机检 0 偏差）。本子库 v1.2.0 起 20 个 `.st` 全部含成对终结符。

### 变更说明 / Change Notes

- **接口契约**：4 个新组件的引脚与 `ROADMAP.md` 第一、二章逐字一致；`E_DL_TwoHandState`、`E_DL_InterlockState`、`E_DL_RedundancyPriority`、`E_DL_DeviationPolicy`、`E_DL_ActiveChannel`、`E_DL_RedundState`、`E_DL_RotationState` 七个枚举随宿主组件同文件发布。
- **故障码**：本轮起新启用 `16#0002_xxxx` 故障码段（0002_0001 同步超时 ~ 0002_0006 切换抖振，全部登记于 `LIBRARY_MANUAL.md` 故障码总表），与既有 `16#0001_xxxx` 参数/循环段并行分配，无组件自造码。
- **安全语义**：`FB_DL_TwoHandSafety` 为标准 PLC 上的逻辑结构实现，非安全认证功能块，合规披露见该文件头注释（不得删改段）。
- **红线状态**：R1~R12 全部通过，机检 0 命中（含终结符成对性检查）。

### 已知限制 / Known Limitations

1. `FB_DL_TwoHandSafety` 不做输入防抖（刻意失真）：防抖延时计入同步窗，调用方须前置 `FB_DL_SignalDebounce`。
2. `FB_DL_InterlockMatrix` 固定 16 路（数组维度硬绑定）；同拍多路失效时只给最低索引 + 完整位图，扫描粒度内无法排序。
3. `FB_DL_RedundantSwitch` 不做 NaN/Inf 检测；`fMaxSlewRate = 0` 的定义是「直接切换」而非「禁止切换」。
4. `FB_DL_DutyStandbyRotation` 固定 8 台；运行时间账（`afRuntimeHours` / `auStartCount`）是否断电保持由调用方 `RETAIN` 声明决定；参数冲突复位沿会清零运行时间账。

---

## v1.1.0 ｜ 2026-11-14 ｜ 时序引擎与诊断补齐 / Timing Engines and Diagnostics

**变更性质**：MINOR（新增 7 个组件）+ PATCH（3 个组件缺陷修复），无破坏性变更，无迁移动作。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 10 | `FB_DL_ExtendedTimer` | FB | 5 | 1.0.0 | 四模式定时器（通电延时/断电延时/单脉冲/保持型累加），运行中换模式即作废计时 / Four-mode timer (TON/TOF/TP/RTO) that voids the timing on a mode switch |
| 11 | `FB_DL_AlarmManager` | FB | 7 | 1.0.0 | 16 通道报警三级优先仲裁 + 先到先得首出锁存，激活/已确认/首出三态正交 / 16-channel priority arbitration with arrival-order first-out, active and acknowledged kept orthogonal |
| 12 | `FB_DL_StepSequencer` | FB | 8 | **1.0.1** | 通用顺控步引擎：步号外置、逐步超时、暂停/单步/中止，换步屏蔽一拍杜绝连环跳步 / Generic step engine with per-step timeout, hold, single-step and a one-scan switch mask |
| 13 | `FB_DL_WatchdogMonitor` | FB | 4 | 1.0.0 | 心跳跳变间隔看门狗 + 跳变过快告警，上电即武装 / Heartbeat-interval watchdog with a too-fast toggle alarm, armed at power-up |
| 14 | `FB_DL_PulseGenerator` | FB | 5 | **1.0.1** | 周期/占空比运行时可调的方波发生器，占空比 0/1 退化为恒低/恒高 / Runtime-adjustable square wave, duty 0 and 1 degenerate to constant low/high |
| 15 | `FB_DL_CycleTimeMeasure` | FB | 3 | 1.0.0 | 扫描周期统计（最近/最小/最大/平均/样本数），时间增量由调用方注入 / Scan-cycle statistics with caller-injected time delta |
| 16 | `FB_DL_RuntimeMeter` | FB | 4 | 1.0.0 | 累计运行分钟/小时 + 启动次数 + 保养到期预警，整数化累加无漂移 / Runtime hours, start count and maintenance-due warning with integer accumulation |

### 修复组件 / Fixed

| 组件 | 旧 → 新 | 缺陷 / Defect |
|---|---|---|
| `FB_DL_DualEdgeTrig` | 1.0.0 → **1.0.1** | 事件校正极性反接：上升沿与「上周期为低」的与项被写反，真实跳变周期被自身屏蔽，`bRising` / `bFalling` 恒为 `FALSE`、计数永不增长 / Inverted qualification polarity suppressed every genuine edge |
| `FB_DL_PulseGenerator` | 1.0.0 → **1.0.1** | 换相后相位定时器不清零（只改 `PT` 不会清 `ET`），占空比 0.5 时低相位塌缩为一个扫描周期、占空比 0.3 时周期由 1000ms 变成 700ms / Phase timer not restarted on switch, collapsing the low phase |
| `FB_DL_StepSequencer` | 1.0.0 → **1.0.1** | 故障码不锁存：主体开头无条件清零而故障态不再重写，进故障后下一拍 `bError = TRUE` 而 `uErrorId` 读回 0 / Fault code erased one scan after the fault was latched |

### 变更说明 / Change Notes

- **接口契约**：7 个新组件的引脚与 `ROUND_PLAN_R2.md` 第 2 章逐字一致；`E_DL_TimerMode`、`E_DL_ExtTimerState`、`E_DL_SeqState`、`E_DL_WdtState`、`E_DL_PulsePhase` 五个枚举随宿主组件同文件发布。
- **组件内部依赖**：`FB_DL_WatchdogMonitor` 引用 `FB_DL_DualEdgeTrig`（规格书 §1.2 唯一批准的依赖），且只取其电平输出，理由与影响见该文件头注释「依赖收窄留档」。
- **故障码**：全部使用库级分配表 `16#0001_0001` ~ `16#0001_000E`，本轮新增 `0008` ~ `000E` 七码，无组件自造码。
- **红线状态**：R1~R12 全部通过；3 个 PATCH 均未改动引脚，属实现级修正。

### 已知限制 / Known Limitations

1. `FB_DL_StepSequencer` 步号上限 16（数组维度硬绑定），超过 16 步的产线需串联两级或用调用方状态编址；`auStepTimeout` 为 `T#0S` 的步不监控超时，挂死风险由调用方承担。
2. `FB_DL_PulseGenerator` 的周期下限 2ms 是「至少两个任务周期可辨」的保守值：任务周期大于 1ms 时，更短的周期设定仍会丢沿。
3. `FB_DL_CycleTimeMeasure` / `FB_DL_RuntimeMeter` 自身不读平台时刻，调用方必须注入 `uDeltaTimeMs`；注入 0 会被判为无效样本并告警。
4. `FB_DL_WatchdogMonitor` 的频率告警不锁存（间隔恢复即自动消除），但计数饱和告警一旦触发即保持到复位。

---

## v0.1.0 ｜ 2026-11-14 ｜ 首版冷启动 / Initial Seed Release

**变更性质**：初始发布（Initial release），无破坏性变更，无迁移动作。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 一句话说明 / Summary |
|---|---|---|---|---|
| 1 | `FB_DL_SignalDebounce` | FB | 5 | 上升/下降延时独立可调的触点消抖，首扫零假边沿 / Debounce with independent rise & fall delays, zero false edge on first scan |
| 2 | `FB_DL_DualEdgeTrig` | FB | 2 | 上升/下降/跳变三事件 + 饱和计数器 / Rising, falling and any-transition events with saturating counters |
| 3 | `FC_DL_BitGet` | FC | 2 | 带索引校验的位提取，越界先判后算 / Bounds-checked bit extraction, validated before shifting |
| 4 | `FC_DL_BitSet` | FC | 3 | 纯函数置位/清零，越界原样返回 / Pure set/clear, returns input unchanged on illegal index |
| 5 | `FC_DL_BitCount` | FC | 3 | Brian Kernighan 置位计数，带防死锁 / Kernighan popcount with deadlock guard |
| 6 | `FC_DL_PackBitsToWord` | FC | 2 | 16 路 BOOL 打包为 WORD，索引 0 = bit0 / Packs 16 BOOLs into a WORD, index 0 = bit0 |
| 7 | `FB_DL_UnpackWordToBits` | FB | 2 | 状态字解包 + 取反掩码 + 变化脉冲 / Word unpacking with invert mask and change pulse |
| 8 | `FC_DL_GrayToBinary` | FC | 4 | 1~32 位可变位宽格雷码解码 / 1..32-bit variable-width Gray decoding |
| 9 | `FC_DL_BinaryToGray` | FC | 3 | 与 #8 严格互逆的格雷码编码 / Strict inverse of #8, verified over full sequences |

### 变更说明 / Change Notes

- **接口契约**：全部 9 个组件的引脚名称、类型、方向、默认值与 `ROUND_PLAN.md` 第 2 章逐字一致；`E_DL_DebounceState` 枚举随 `FB_DL_SignalDebounce` 同文件发布。
- **无内部依赖**：9 个组件彼此零引用，可单独编译与单独入库，编译顺序不受限。
- **故障码**：统一使用库级分配表 `16#0001_0001` ~ `16#0001_0007`，无组件自造码。
- **显式豁免**：`FC_DL_PackBitsToWord` 不设 `uErrorId`（编译期无失败路径），已在源码头注释与手册备案。
- **红线状态**：R1~R7 全部通过，机检 0 命中（详见 `MANUAL_DL_Base.md` 第 9 节）。

### 已知限制 / Known Limitations

1. 位运算组件首版只覆盖 32 位域（`DWORD` / `UDINT`），`LWORD` 64 位版待验证汇川 InoProShop 支持情况后发布。
2. `FC_DL_GrayToBinary` 不承担编码器 Excess 偏移补偿，调用方须按「先转二进制 → 减偏移 → 乘分辨率」顺序串联。
3. 位序约定全库写死为「索引 0 = LSB」，不提供配置开关。

---

## 版本号约定 / Versioning Policy

子库遵循 SemVer，且与库总版本联动：

- **MAJOR**：任一组件删除引脚、改引脚语义、改默认值、改故障码含义。
- **MINOR**：新增组件，或为已有组件新增可选输入（带默认值）。
- **PATCH**：内部实现修正、注释与手册补全、性能优化，接口与行为不变。

破坏性变更必须在本文档写明迁移指引（旧调用 → 新调用）与影响的组件清单。

---

## 后续计划 / Next

`DL_Base` 已于 v1.2.0 完成 Phase 1 全部 20 项，**Level 0 `DL_Base` 收口（20/20）**；v1.3.0（R5）补强日历/时间窗两件，v1.4.0（R7）LGF Counter 组开组（事件计数 + 取模索引），v1.5.0（R9）LGF 四组深化（公差窗 / 限值分档 / 位段打包 / 月窗 / 饱和计数），v1.6.0（R10）三组横向补强（位段提取 / ISO 周数 / CTUD 双向计数），v1.7.0（R11）年月日三粒度时间窗闭环（年窗）+ 环形回绕计数，v1.8.0（R12）Bit Logic 组跨字位段族收官（跨字提取 / 跨字插入 / 区间归属 / 位数组变更监视），v1.9.0（R13）位段族三件套补齐「转」（整串旋转 + 掩码比较），现 40 项。

后续按矩阵扩产规则推进：Date and Timer 组天文钟/倒计时族、Counter 组预置变体（见 `ROADMAP.md` 待办池）、Comparator 组开闭区间变体；位数组族已有监视件，**不再扩充同类批量件**，其余新增能力进入 Level 1。本子库对既有组件只接受 PATCH 级修正与可选引脚扩展。

---

## v1.10.0 ｜ 2026-11-16 ｜ R14 T0 快车道：IEC 标准件防御性包装 15 件（触发器/定时器/计数器/移位四组收口）/ R14 T0 Fast Lane — 15 IEC Standard Wrappers

**变更性质**：MINOR（新增 15 个组件），无破坏性变更，无迁移动作。终审 **15/15 PASS**（提示级 1 处留档：CTUD 计数本体为显式判界 ±1 而非委托内建 CTUD——内建 CTUD 无双向饱和锁定能力，头注释「边界声明」节已与 `FB_DL_BidirectionalCounter` 划界互引；`FB_DL_RTrigEx`/`FB_DL_FTrigEx` 为纯语义包装无域可校验，头注释声明「无错误码」不占码位）。

### 新增组件（15 件）/ Added Components

| 组件 / Component | T0 组 | 标准原型 | 防御要点 / Defense |
|---|---|---|---|
| `FB_DL_SRBistable` | T0-1 | SR | S1/R 同拍置位优先 + 仲裁诊断码 |
| `FB_DL_RSBistable` | T0-1 | RS | S/R1 同拍复位优先 + 仲裁诊断码 |
| `FB_DL_RTrigEx` | T0-1 | R_TRIG | 首扫不假触发、单拍输出 |
| `FB_DL_FTrigEx` | T0-1 | F_TRIG | 首扫不假触发、单拍输出 |
| `FB_DL_TonEx` | T0-2 | TON | PT 负钳 0、跨段语义统一，委托内建 TON |
| `FB_DL_TofEx` | T0-2 | TOF | 首扫零假触发，委托内建 TOF |
| `FB_DL_TpEx` | T0-2 | TP | 不可重触发语义显式化，委托内建 TP |
| `FB_DL_RtoEx` | T0-2 | RTO（通用语义） | 复位>使能优先链、末拍快照冻结累加（R46） |
| `FB_DL_CtuEx` | T0-3 | CTU | PV 负钳 0、上溢饱和不回绕 |
| `FB_DL_CtdEx` | T0-3 | CTD | 下溢饱和不回绕 |
| `FB_DL_CtudEx` | T0-3 | CTUD | 净额抵消法（R47）+ 双向饱和锁定 |
| `FC_DL_ShlEx` | T0-7 | SHL | n ≥ 32 常量路径置 0，不调内建 |
| `FC_DL_ShrEx` | T0-7 | SHR | 同上 |
| `FC_DL_RolEx` | T0-7 | ROL | MOD 32 归一 + SHL/SHR 位合成（R48） |
| `FC_DL_RorEx` | T0-7 | ROR | 同上 |

### 码位台账追加（R14 码位登记，经终审全库求差断言复核）/ Error Code Ledger Additions (R14)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `16#0001_014D` | 信息 | S1/R 同拍置位胜出仲裁记录 | `FB_DL_SRBistable` |
| `16#0001_014E` | 信息 | S/R1 同拍复位胜出仲裁记录 | `FB_DL_RSBistable` |
| `16#0001_014F` | 信息 | tPT 负值钳 0 | `FB_DL_TonEx` |
| `16#0001_0150` | 信息 | tPT 负值钳 0 | `FB_DL_TofEx` |
| `16#0001_0151` | 信息 | tPT 负值钳 0 / 不可重触发记录 | `FB_DL_TpEx` |
| `16#0001_0152` | 信息 | tPT 负值钳 0 | `FB_DL_RtoEx` |
| `16#0001_0153` | 信息 | nPV 负钳 0 / CV 上限饱和记录 | `FB_DL_CtuEx` |
| `16#0001_0154` | 信息 | nPV 负钳 0 / CV 下限饱和记录 | `FB_DL_CtdEx` |
| `16#0001_0155` | 信息 | nPV 负钳 0 / CU-CD 同拍抵消记录 | `FB_DL_CtudEx` |
| `16#0001_0156` | 信息 | 移位量 ≥ 32 超宽置 0 | `FC_DL_ShlEx` |
| `16#0001_0157` | 信息 | 移位量 ≥ 32 超宽置 0 | `FC_DL_ShrEx` |
| `16#0001_0158` | 信息 | MOD 32 归一（循环移位量归一记录） | `FC_DL_RolEx` |
| `16#0001_0159` | 信息 | MOD 32 归一（循环移位量归一记录） | `FC_DL_RorEx` |
| `16#0001_0226` | 故障 | CV 达 DINT 上/下限饱和锁定（不回绕） | `FB_DL_CtudEx` |

> 全库码位跨文件重叠 = 0（终审脚本求差断言复跑）；本批信息级 `014D`~`0159`、故障级 `0226` 由本子库独占，`015A`~`015D` 与 `0227`~`022B` 归 `DL_MathData`。

| `16#0001_0452` | 信息 | 时间参数超 24h 已钳上限 | `FB_DL_MinOnOffGuard` |
| `16#0001_0453` | 信息 | 停机请求被最短运行推迟（进入 eHolding） | `FB_DL_MinOnOffGuard` |
| `16#0001_0399` | 故障 | 时间参数为负已钳零 | `FB_DL_MinOnOffGuard` |
| `16#0001_039A` | 故障 | 非法状态（枚举被改写） | `FB_DL_MinOnOffGuard` |
| `16#0001_039B` | 故障 | 预留禁用（不得挪用） | `FB_DL_MinOnOffGuard` |
| `16#0001_0454` | 信息 | 输入非有限 | `FB_DL_SignalChangeCounter` |
| `16#0001_0455` | 信息 | 主计数饱和（不再递增） | `FB_DL_SignalChangeCounter` |
| `16#0001_039C` | 故障 | 死区为负或非有限 | `FB_DL_SignalChangeCounter` |
| `16#0001_039D` | 故障 | 预留禁用（不得挪用） | `FB_DL_SignalChangeCounter` |
| `16#0001_039E` | 故障 | 预留禁用（不得挪用） | `FB_DL_SignalChangeCounter` |
| `16#0001_0456` | 信息 | 累计漂移超阈值 | `FB_DL_SamplingTrigger` |
| `16#0001_0457` | 信息 | 样本序号回绕归零 | `FB_DL_SamplingTrigger` |
| `16#0001_039F` | 故障 | 采样周期非法已钳至 1ms 继续 | `FB_DL_SamplingTrigger` |
| `16#0001_03A0` | 故障 | 扫描周期增量非法（≤ 0 或超上限） | `FB_DL_SamplingTrigger` |
| `16#0001_03A1` | 故障 | 预留禁用（不得挪用） | `FB_DL_SamplingTrigger` |
| `16#0001_0458` | 信息 | 输入非有限 | `FB_DL_SignalFrozenDetect` |
| `16#0001_0459` | 信息 | 窗内极差为零（完全无抖动） | `FB_DL_SignalFrozenDetect` |
| `16#0001_03A2` | 故障 | 窗口时长或死区非法 | `FB_DL_SignalFrozenDetect` |
| `16#0001_03A3` | 故障 | 连续非有限超过一个窗口 | `FB_DL_SignalFrozenDetect` |
| `16#0001_03A4` | 故障 | 预留禁用（不得挪用） | `FB_DL_SignalFrozenDetect` |
| `16#0001_045A` | 信息 | 确认窗小于两倍最小任务周期的代理阈值（2ms） | `FB_DL_PulseWidthFilter` |
| `16#0001_045B` | 信息 | 预留禁用（不得挪用 | `FB_DL_PulseWidthFilter` |
| `16#0001_03A5` | 故障 | 最小宽度非法已钳至 1ms 继续 | `FB_DL_PulseWidthFilter` |
| `16#0001_03A6` | 故障 | 抑制计数饱和 | `FB_DL_PulseWidthFilter` |
| `16#0001_03A7` | 故障 | 预留禁用（本件无状态机 | `FB_DL_PulseWidthFilter` |
> 全库码位跨文件重叠 = **0**（机检 + 注册表正则求差断言 CLASH=NONE 复跑）；本轮信息级至 `045C`、故障级至 `03A8`，与另一 Level 0 子库共用游标无交叉占用。
> **码位游标（注册表实测于 2026-11-16）**：信息级 `045C` ｜ 故障级 `03A8`（下一轮从 `045D` / `03A9` 起分配）。


---

## v1.17.0 ｜ 2026-11-16 ｜ R22 结构补位轮 2 件

**批次**：本子库 R22 新增 2 件（全库 20 件 6,618 行；机检 20/20 PASS fail=0）
**码位**：本子库本轮占用见各件头注释「码位总账」；收口后全库游标（注册表实测 2026-11-16）：`0001` 信息 `0466` / 故障 `03B7`、`0002` 下一 CC `2D`、`0003` 信息 `017A` / 故障 `0348`、`0004` 信息 `01DF` / 故障 `02F9`、`0005` 信息 `01E2` / 故障 `0317`
**终审结论**：R22 抽检 12 件高风险件，4 件轻微缺陷修复升 v1.0.1（MotionCmdQueue / VirtualMasterAxis / AxisBrakeSeq / BatchTransferSeq），1 件中等安全相关挂账 R23（BatchTransferSeq 中止时序），其余零缺陷 PASS
**码位跨文件冲突断言**：R22 100 槽定向复测 CLASH=NONE；JSONL 384 条全量 sha256 MATCH（本轮另修复 2 件历史换行口径漂移）

- `FC_DL_FirstSetBit`：首个置位位定位（低位/高位优先，8/16/32/64 有效位宽，宽 64 用 `DL_MASK64_ALL` 常量掩码全程无 `SHL(x,64)`，WHILE + nGuard 防死锁；T0-7 变体线零检索）。
- `FB_DL_FrequencyMeasure`：门时计数测频（TON 门 + R_TRIG 计沿，门时间 1 ms~10 s 钳位，低频死区显式化，门切换拍 ±1 计数不确定度写进遗留假设段；T0-2 变体线零检索）。

**终审**：本子库 2 件抽检推演零缺陷 PASS。

## R39（2026-11-19）— +1（FB_DL_MutexOwnerAudit）

- 本轮增量已入册（registry v2.31.0），机检全 PASS；详见 CHANGELOG v2.31.0。

## R40（2026-11-19）— +2（FB_DL_SrEx / FB_DL_RsEx）

- 本轮增量已入册（registry v2.32.0），机检全 PASS；详见 CHANGELOG v2.32.0。

## v1.20.0 — 2026-11-19（R41 · 20 新件批次 1/2）
- 新增 3 件：FB_DL_SignalQualify（模拟量信号有效性三态联合判定）/ FB_DL_MultiClickDetect（短按/长按/双击三形态）/ FB_DL_ValueHoldMonitor（域外/超时保持最后有效值 + 掩码标记）；组件总数 80 → 83。
- 码位：段 0001（Base/MathData 共用 Level 0 游标）推进——故障 16#0001_03DB~03E6、信息 16#0001_049E~04A9（本子库占用部分）。

### v1.20.0 — 2026-11-19（R43）
- 新增组件 1 件；码位窗口 0102 零冲突。
- 由 v1.19.0 升位，向后兼容（纯新增，无接口破坏）。

## v1.21.0 — 2026-11-19（R45）

- R45：+3 新件（Vote2oo3 / EdgeOrderCheck / AlarmFloodLimiter）｜码位 16#0001_03EA~03ED / 04AD~04B0｜机检 3/3 PASS


## v1.22.0 — 2026-11-19（R46）

- R46：+2 新件（FC_DL_IntCeilDiv〔T0 防御包装〕/ FB_DL_WatchdogPulseMon〔T1-7 ◐〕）｜本件零码位硬编码：BOOL+ENUM 出口，码位待主控统一派号｜机检 2/2 PASS
- 向后兼容（纯新增，无接口破坏）。

## v1.22.1 — 2026-11-19（R47）

- R47：+2 新件（FC_DL_IntFloorDiv〔T0 防御包装，与 IntCeilDiv 成对〕/ FC_DL_ByteArrayXor〔T0〕）｜零码位硬编码：BOOL+ENUM 出口，码位待主控统一派号｜机检 2/2 PASS
- 向后兼容（纯新增，无接口破坏）。
---

## v1.20.0 — 2026-11-20（R48）

- 新增组件 3 件：FC_DL_SaturateSub / FB_DL_ModeArbiter / FB_DL_HoldRepeatButton
- 子库组件总数：**94**（registry 实测口径）
- 机检：本轮 21/21 PASS（含 FB_DL_ModulePottingVac v1.0.1 轻返修）

## v1.21.0 — 2026-11-20（R49）

- 新增组件 4 件：FB_DL_HeartbeatGen / FB_DL_PulseSeqVerify / FB_DL_StepTimeRecorder / FB_DL_CycleBarrierGate
- 子库组件总数：**98**（registry 实测口径）
- 机检：本轮 20/20 PASS（增量仅扫本轮新增件）

## v2.42.0（R49 批次入册 · R50 收口，2026-11-20）
- 新增组件 4 件：FB_DL_HeartbeatGen / FB_DL_PulseSeqVerify / FB_DL_StepTimeRecorder / FB_DL_CycleBarrierGate
- 子库组件总数：**102**（registry v2.42.0 counts 口径）
- 机检 25/25 PASS；R50 终审无本子库挂账件

## v1.22 — 2026-11-20（R52）
- 变更：+4（BitCountOnes 位串置1计数 / PriorityEncodeWord 优先编码 / SchmittTriggerGap 回差整形 / EdgeIntervalMeter 沿间隔占空比测量）
- 子库计数：**106 件**（全库 945 / v2.44.0）
- 机检：本子库本轮新增/返修件全部 PASS（audit_r52.py，22/22 全绿）

## v1.23 — 2026-11-20（R53）

- +2：FB_DL_SignalStuckWatch / FB_DL_PulseTrainDecoder（信号卡死双判据 + 脉冲串宽窄解码）
- 机检：本轮 20/20 PASS（含 4 件 v1.0.1 返修）；JSONL 同步 962 条。

## R54 追加（2026-11-20，子库 v1.24）
- 新增：FB_DL_BitArrayMultiSegMove / FB_DL_PrbsSignal / FB_DL_SweepFreqGen
- 子库存量：111 件

## v1.25 — 2026-11-21（R56 追加）
- 新增 2 件（EStopDualChannel / SignalSeqGuard）。
- 子库累计 113 件。
## v1.28 — 2026-11-21（R57 追加）
- 新增 5 件：FB_DL_TpRetrigger / FB_DL_EdgeMasterSlaveSync / FB_DL_EncoderQuadCount / FB_DL_SignalStagnationWatch / FB_DL_SensorDropoutHold（可重触发脉冲 / 主从沿同步 / 正交四倍频 / 信号呆滞 / 掉线保持）
- 子库累计 118 件。

## v1.29 — 2026-11-21（R58 追加）
- 2 件（VoteKooN / SimInputBank）+ EncoderQuadCount v1.0.1 返修。
- 子库累计 120 件。

## v1.31 — 2026-11-21（R60 追加）
- 新增 3 件：FB_DL_RolloverCounterUdint（UDINT 回绕安全累计） / FB_DL_ReqAckHandshake（请求-应答握手原子） / FC_DL_BitFieldExtractLword（64 位位域提取）
- 子库累计 126 件。

## v1.32 — 2026-11-21（R61 追加）
- 新增 4 件：ReverseBitsLword / BitScanLword / LongPressButton / RailPowerSequence
- 子库累计 130 件。

## v1.33 — 2026-11-21（R62 追加）
- 新增 4 件（T0 算术 / 位串族补口）：`FC_DL_SaturateMul`（LINT 宽域饱和乘，四象限溢出前置判定 + `bOvF`/`bClamped` 双标志可分）、`FC_DL_SaturateDiv`（饱和除，除零三段码 + 向零截断口径 + `MIN÷-1` 特判）、`FC_DL_ShiftArithEx`（算术右移，32 项常量掩码表结构性规避 `SHL(x,32)`）、`FC_DL_SignExtendEx`（任意窄位宽符号 / 零扩展，位宽越域早退不钳）。
- 返修 1 件：`FB_DL_RailPowerSequence` v1.0.1 → **v1.0.2**（D1 空轨断电早退 + D2 单轨超时门控；R61 挂账关闭）。
- 子库累计 134 件。

## v1.34 — 2026-11-21（R63 追加）
- 返修 1 件：`FB_DL_RailPowerSequence` v1.0.2 → **v1.0.3**（R62-D4 中：eRampUp 推进判据改「沿 OR 电平」双路 `rtFb.Q OR abRailFb[_nStep]`，反馈预闭合轨电平直过消除静默挂死；头注释补「反馈预闭合」处置口径与向量 V6；R61 挂账全清）。
- 子库累计 134 件（本轮无新件）。
## v1.35 — 2026-11-21（R64 追加）

- 新增 `FC_DL_TriStateCompare`（v1.0.0，T2-1 LGF Comparator 深化 +1）：三态比较器（小于 / 相等 / 大于，带 `fEps` 容差与 NaN 前置闸），返回 `E_DL_TriState`；供区间/分级/表决类调用方统一比较口径。
- 主库合计 135 件（+1）。本子库仍为 Level 0 纯基础件，零依赖。

## v1.36 — 2026-11-22（R65 追加）

- 新增 6 件：`FC_DL_StringEditDistance`（Levenshtein 滚动单行 DP）/ `FC_DL_StringWildMatch`（通配符双指针回溯）/ `FC_DL_ArrFillEx` / `FC_DL_ArrCopySeg`（LGF DataHandling clean-room）/ `FC_DL_SortIndexInt`（稳定排序索引）/ `FB_DL_HysteresisBandMon`（LGF Comparator clean-room，与 FC_DL_Hysteresis 互引分工）。
- 子库累计 141 件。

## v1.37 — 2026-11-22（R66 追加）

- 新增 2 件：`FC_DL_HammingDist`（LWORD 两位串汉明距离，逐位异或 + 1 计数）/ `FB_DL_DutyCycleMeasure`（BOOL 周期 + 占空比在线测量，fCallCycleMs 时间注入）。
- 子库累计 143 件。

## v1.38 — 2026-11-22（R67 追加）

- 新增 2 件：`FB_DL_LastGoodValueHold`（失效值保持 + 陈旧置码，ne43 族）｜`FB_DL_ImpulseRelay`（沿触发定宽脉冲，oscat-basic 借鉴 clean-room）。
- 子库累计 145 件。

## v1.39 — 2026-11-22（R68 追加）

- 新增 3 件：`FB_DL_InterlockBypassAudit`（旁路全生命周期审计：申请/解除/超时三类事件 8 条环形台账 + 旁路计数 255 饱和；联锁本体归 `FB_DL_InterlockMatrix`）｜`FB_DL_ClockDriftMonitor`（RTC vs 标准钟漂移率 [ms/h] + 需校钟标志，只监视不写钟）｜`FB_DL_DiagTextLookup`（诊断码→双语文本查表，VAR_IN_OUT 数组注入零全局耦合）。
- 终审就地修：`FB_DL_ClockDriftMonitor` v1.0.1（组态锁存解除路径可达化，原 eFault 相不可达）。
- 子库累计 148 件。

## v1.40 — 2026-11-22（R69 追加）
- 新增 2 件：`FB_DL_AlarmShelveMgmt`（ISA-18.2 搁置生命周期）｜`FB_DL_SignalFreeze`（批量/报表期信号冻结采样）。
- 点修：`FB_DL_InterlockBypassAudit` v1.0.0 → **v1.0.1**（迁相补 bBypassOn 清零 + 04B1/04B2 回落口径，R68 挂账）。

## v1.31 — 2026-11-22（R70 追加）
- 新增：FB_DL_RecipeStepExec（配方步序执行器）。
- 子库累计 151 件。

## v1.32 — 2026-11-23（R72 追加）

- `FC_DL_DaysInMonthChk` / `FB_DL_BlinkOutput` 两件入册（日历原子复用 LeapYearChk 单源；OSCAT BLINK 行为定义借鉴，零值组态锁存防静默失效）。
