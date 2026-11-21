# DISPATCH_R38 — 第 38 轮编码派单（20 件 + 2 返修，单次调用内 4 批按序完成）

> 派单：主控 2026-11-18 23:16。**需求规格全文在 `C:\Library\_Staging_Raw\2026-11-18\ROUND_PLAN_R38.md` §4（每批一张表，逐件 6~10 行规格）**，本文件只定纪律、码位与红线，规格不复述以防两处不一致。
> 返修任务书另见 `C:\Library\_Staging_Raw\2026-11-18\DISPATCH_R38_REPAIR.md`（2 件，**最后做**）。

## 0 执行纪律（违反即返工）

1. **一次调用内按序完成 4 批 × 5 件**，批 1 → 批 2 → 批 3 → 批 4；批内 1→5 顺序写盘，**禁止并行交错写同一文件**。
2. **禁占位符**：不得出现 `TODO`/`FIXME`/`...`/`(* 待补 *)`；每个 POU 必须自洽可编译。
3. **每件写完立刻落盘**（不要攒到最后一次性写），路径固定 `C:\Library\DL_<Category>\<Name>.st`。
4. **码位写死，不得越窗**：见 §2 表；件内信息码/故障码只能在本件格内 `+0x10` 子码步进（如 `16#0001_0000`、`16#0001_0100`、`16#0001_0200`），**不得跨入下一件格**。
5. **写前查重**：若目标文件已存在，**立即停止该件并向主控上报**，禁止覆盖（R172/R182）。
6. **依赖只用已注册件**：见 ROUND_PLAN §3 批内依赖列。`E_DL_AxisState` 不存在于 registry（枚举随 `I_DL_MotionAxis` 发布，直接引用即可）；`FB_DL_Hysteresis` **实为 `FC_DL_Hysteresis`**。
7. **时长纪律**：单件目标 ≤ 90 秒思考+写盘；20 件整体控制在 28 分钟内。若第 3 批中途已明显超时，**优先保证已写件完整可编译**，不要为凑数写半成品。

## 1 批次表（20 件）

| 批 | 序号 | 组件名 | 分类 | 类型 | 码位 |
|---|---|---|---|---|---|
| 1 | 1 | `FC_DL_SaturateAdd` | DL_Base | FC | `16#01_0_00` |
| 1 | 2 | `FB_DL_ToggleButtonBank` | DL_Base | FB | `16#01_0_01` |
| 1 | 3 | `FC_DL_LinearRegression2Var` | DL_MathData | FC | `16#05_0_02` |
| 1 | 4 | `FC_DL_OscillationIndex` | DL_MathData | FC | `16#05_0_03` |
| 1 | 5 | `FC_DL_PidLambdaTune` | DL_Algo | FC | `16#02_3_83` |
| 2 | 6 | `FC_DL_HeatExchangerLmtd` | DL_Algo | FC | `16#02_3_84` |
| 2 | 7 | `FB_DL_CrossCorrelationDelay` | DL_Algo | FB | `16#02_3_85` |
| 2 | 8 | `FB_DL_SpindleOrientationStop` | DL_Motion | FB | `16#04_0_A4` |
| 2 | 9 | `FB_DL_ElectronicCamSwitchBank` | DL_Motion | FB | `16#04_0_A5` |
| 2 | 10 | `FB_DL_VavBoxZeroCal` | DL_Device | FB | `16#03_2_12` |
| 3 | 11 | `FB_DL_ElectrodeTabBendCtrl` | DL_Device | FB | `16#03_2_13` |
| 3 | 12 | `FB_DL_JunctionBoxPottingCheck` | DL_Device | FB | `16#03_2_14` |
| 3 | 13 | `FB_DL_PouchSwellingGauge` | DL_Device | FB | `16#03_2_15` |
| 3 | 14 | `FB_DL_FreshAirStepperDamper` | DL_Device | FB | `16#03_2_16` |
| 3 | 15 | `FB_DL_HeatSealProfile` | DL_Process | FB | `16#06_0_B0` |
| 4 | 16 | `FB_DL_AhuEconomizer` | DL_Process | FB | `16#06_0_B1` |
| 4 | 17 | `FB_DL_TerminalReheatSeq` | DL_Process | FB | `16#06_0_B2` |
| 4 | 18 | `FB_DL_RfReflectedMonitor` | DL_Process | FB | `16#06_0_B3` |
| 4 | 19 | `FB_DL_StringSolderQuality` | DL_Process | FB | `16#06_0_B4` |
| 4 | 20 | `FB_DL_ModuleLamVacuumSeq` | DL_Process | FB | `16#06_0_B5` |

## 2 码位窗口与段位说明

| 段 | 已占（实测） | 本轮占用 | 说明 |
|---|---|---|---|
| `01_0` | 全空（DL_Base 首开码位体系） | `00`~`01` | 从 00 起连续给号 |
| `05_0` | `00`/`01` | `02`~`03` | 紧接续号 |
| `02_3` | 至 `82` | `83`~`85` | 续号 |
| `04_0` | `6C`、`A0`~`A3` | `A4`~`A5` | 沿用 A 段体例 |
| `03_2` | `00~04`、`06~11` | `12`~`16` | **序号 10~14 须在头注释「码位 Code」下另加一行「段位说明」**：`03_2` 低半字节 `00~0F` 已满（`05` 为历史空穴留存），进位 `12` 段续号 |
| `06_0` | `00`~`40` 稠密、`80~99` 满 | `B0`~`B5` | `B*` 段全库 0 命中，R35 撞码整改后的新段 |

## 3 文件格式（与既有件严格一致，先读 1 件样例再动笔）

**样例**：`C:\Library\DL_Device\FB_DL_CurtainEFEMZone.st`（头注释 + ENUM + POU 三段式）。要求：

1. **头注释块** `(* ... *)` 必含字段（顺序同样例）：`<Name> — <中文名> / <English>`、`分类 Category`、`码位 Code`、`版本 Version : 1.0.0`、`来源 Source`（**必须含字面**「IEC 61131-3 标准语义的道莅防御性实现」）、`溯源 Origin`（clean-room 声明）、`功能 Function`（1) 2) 3)…）、`边界 Boundary`（① ② ③… 含「解除式自证」一条）、`依赖 Depends`、`码表 Error codes`（逐条列 `16#xxxxxxxx` 十六进制 **含分类位全 8 位**）、`修订历史 Revision : 2026-11-18 v1.0.0 R38 首版`。
2. **枚举**：`TYPE E_DL_Xxx : ( eA := 0, // 中英双语注释 ... ); END_TYPE` —— **成员用 `:=` 带值**，**严禁单冒号**（R33/R34 复发点）。
3. **声明区**：`VAR_INPUT` / `VAR_OUTPUT` / `VAR_IN_OUT`（注入接口）/ `VAR`（内部）/ `VAR CONSTANT` 各块齐全；**每个变量声明后必须同行中英双语注释**（`// 中文 / English`）。
4. **`VAR_OUTPUT` 必须全声明**：凡函数体内赋值的输出名，必须先在 `VAR_OUTPUT` 声明（R29 复发点）。
5. **段 0 = 定时器与边沿无条件周期刷新**：所有 `TON`/`TOF`/`R_TRIG`/`F_TRIG` 实例必须在段 0 无条件调用（条件写进表达式入参，不写进 `IF`）；**`TON` 必须有自复位路径**（`IN := ... AND NOT tonX.Q` 或等效），禁 `IN := TRUE` 字面（N1）。
6. **`CASE` 必须全态覆盖 + `ELSE` 兜底**（兜底置故障码并回安全相）；**禁在 `CASE` 分支内给输出枚举直接赋值**（N2，改内部 `_eState` 变量，段尾单点映射）。
7. **单拍量预清零**：信息码、`bError`、各输出缺省值在段 1 统一清零/赋缺省，段尾单点映射（禁同拍抹除锁存，R33 事故族）。
8. **注释禁用嵌套** `(* (* *) *)` —— 注释体内不得出现 `(*`。
9. **编码**：UTF-8 无 BOM、**CRLF** 行尾。
10. **纯 IEC 61131-3**：禁 `VAR_EXTERNAL`/`GVL`/`%I`/`%Q`/`AT %` 地址/`__ISVALIDREF`/`REF=`/`ORD`/`CHR`；只用 `Standard.library` 的 `TON`/`TOF`/`TP`/`R_TRIG`/`F_TRIG`/`ABS`/`MIN`/`MAX`/`LIMIT`/`LN`/`EXP`/`SQRT`/`TRUNC`/`SHL`/`SHR`/`TIME_TO_REAL`/`REAL_TO_TIME` 等。
11. **防错三闸**：除零（分母先判 > 0 或钳位）、越界（数组下标先判、循环带上限计数器）、浮点容差（比较用容差而非 `=`）；NaN/Inf 输入须有 `NOT (x = x)` 或范围判据兜。
12. **FC 纯函数件**（序号 1/3/4/5/6）：无状态、无 `VAR` 记忆量、无定时器；`bClamped`/`bValid` 等标志每调用重算。

## 4 七项红线（自检清单，逐件过）

① 零 `GVL`/`VAR_EXTERNAL`；② 零 `%I`/`%Q` 地址；③ 纯 IEC 61131-3 跨平台（无厂商库）；④ 防除零/越界/浮点容差全覆盖；⑤ 变量声明同行中英双语注释；⑥ ENUM + `CASE` 含 `ELSE` 兜底；⑦ `TON`/`R_TRIG` 实例无条件周期刷新。

**历史高频返工点（重点防）**：漏声明 `VAR_OUTPUT`｜注释嵌套 `(* *)`｜枚举单冒号（应为 `:=`）｜隐性回夹（完成脉冲同拍被清零）｜锁存副本与实时镜像混用｜`TON` 不自复位致错峰/计时失效（R32 事故族）｜完成标志在置位相同拍被段尾清（R33 `RollChangeoverSeq` 族）。

## 5 交付与回报

- 20 件全部落盘后，回一段**逐件清单**：序号 / 名称 / 行数 / 码位 / 是否含 ENUM / 依赖引用名。**不要贴源码**。
- 若某件因规格自相矛盾或依赖缺失无法完成，**跳过并单列**（写清原因），其余继续，禁止占位充数。
- 最后执行 §6 两件返修（`DISPATCH_R38_REPAIR.md`），修复后回报改动点行号。
