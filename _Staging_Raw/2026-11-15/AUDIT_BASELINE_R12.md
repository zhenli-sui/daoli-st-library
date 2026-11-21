# R12 全库机检基线 / AUDIT BASELINE R12

> **脚本**：`C:\Library\_Staging_Raw\2026-11-15\audit_library_r12.py`
> **运行**：`python audit_library_r12.py`（全库）｜`python audit_library_r12.py --files a.st b.st`（指定文件）｜`--rules case_else,undefined_identifier`（选规则）
> **基线时间**：2026-11-15 ｜ **样本**：全库 168 件 `.st`（DL_Base 34 / DL_MathData 33 / DL_Algo 25 / DL_Device 40 / DL_Motion 16 / DL_Process 20）
> **规模**：48,827 行 / 2,569,596 字符 ｜ **末行**：`SUMMARY: files=168 fail=28`

## 1. 计数总表

| # | 规则 | 结论 | 命中 | 说明 |
|---|---|---|---|---|
| 1 | `banned_hits` | PASS | 0 | GVL / VAR_EXTERNAL / VAR_GLOBAL / %I / %Q / %M 零命中 |
| 2 | `placeholder` | FAIL | 4 | 全部为头注释里的 `...` 省略符（含 2 处代码骨架示例） |
| 3 | `terminator` | PASS | 0 | 151 个 POU + 17 个 INTERFACE 全部成对，终结符均在文件末行 |
| 4 | `bilingual_comment` | PASS | 0 | VAR 区 100% 中英双语同行注释 |
| 5 | `case_else` | PASS | **0** | 存量 168 件无缺 ELSE 的 CASE 块 |
| 6 | `enum_case_completeness` | PASS | 0 | 文件内 ENUM 成员 100% 被 CASE 标签覆盖（含限定写法与多行并列标签） |
| 7 | `enum_separator` | PASS | 0 | 无 `成员:` 单冒号畸形枚举 |
| 8 | `nested_comment` | PASS | 0 | 无 `(*` 嵌套 |
| 9 | `undefined_identifier` | PASS | **0** | 存量 168 件无未声明赋值目标/表达式标识符 |
| 10 | `single_colon_or_semicolon` | FAIL | 24 | 13 件 24 处 `;` 独占行（CASE 分支体空语句） |
| 11 | `line_count` / `char_count` | INFO | — | 见上「规模」行 |
| 12 | `duplicate_pou_name` | PASS | 0 | 151 个 POU 名全库唯一 |

**噪声判定**：两条最易误报的规则在存量上均为 0 命中（`undefined_identifier` 0 / `case_else` 0），
其余规则命中数均远低于「>20 条即判定过宽」的收紧阈值，除 `single_colon_or_semicolon` 的 24 条
—— 该 24 条经逐条核对**全部为真实孤立分号**（非误报），属存量遗留缺陷，详见 §3。

## 2. 命中明细

### 2.1 `placeholder`（4 处，头注释省略符）

| 文件 | 行 | 上下文 |
|---|---|---|
| `DL_Base/FC_DL_GrayToBinary.st` | 12 | `算法: 递推式 B = G XOR (G>>1) XOR (G>>2) ... XOR (G>>(w-1))`（数学递推记号） |
| `DL_MathData/FB_DL_MovingAverage.st` | 31 | `两阶段判据…在采样段用 IF bBufferFull THEN ... ELSE ... END_IF`（代码骨架示例） |
| `DL_Motion/FB_DL_AxisHomingSeq.st` | 66 | `IF fbHome.bDone THEN ... 上层联动…`（代码骨架示例） |
| `DL_Process/FB_DL_OccScheduleWindow.st` | 97 | `fbOcc.aWinEnable[1] := TRUE; ... // 窗组`（窗组赋值示例） |

> 判定口径：`...` 一律视为省略符（排除 `0...9` 之类数值上下文，中文 `…` 不计）。4 处均在注释中，
> 建议改写为 `…` 或加「（示例省略）」字样，不改动代码语义。

### 2.2 `single_colon_or_semicolon`（24 处，13 件）

| 文件 | 行 | 文件 | 行 |
|---|---|---|---|
| `DL_Algo/FB_DL_RampSoakProfile.st` | 226, 245, 257 | `DL_Device/FB_DL_VacuumEjector.st` | 199 |
| `DL_Algo/FB_DL_SplitRangeControl.st` | 159 | `DL_Device/FB_DL_VfdGeneric.st` | 248 |
| `DL_Device/FB_DL_AnalogValve.st` | 249 | `DL_MathData/FB_DL_LifoStack.st` | 205 |
| `DL_Device/FB_DL_GuardLockDoor.st` | 242 | `DL_MathData/FB_DL_MedianFilter.st` | 247, 252, 256, 260 |
| `DL_Device/FB_DL_SerialScanner.st` | 277 | `DL_MathData/FB_DL_SignalStatistics.st` | 283, 288, 292, 296 |
| `DL_Device/FB_DL_StarDeltaMotor.st` | 171, 173 | `DL_Motion/FB_DL_SoftLimitGuard.st` | 192, 197 |
| `DL_Device/FB_DL_ThreePointValve.st` | 262 | `DL_Process/FB_DL_BatchDosingControl.st` | 384 |

> 形态统一：CASE 分支体只写了一个 `;`（空语句占位）。R26 要求终端态用**纯注释占位**，故判 FAIL。
> 这是本轮唯一的存量硬缺陷族，修复动作极小（`;` → `(* 无动作 / No action *)`）。

## 3. 规则收紧记录（防误报口径，脚本头注释同步）

| 规则 | 初版命中 | 收紧动作 | 收紧后 |
|---|---|---|---|
| `undefined_identifier` | 680 | ① `{attribute ...}` 编译指示整体置空；② 建**全库级类型表**（TYPE / INTERFACE / POU / 枚举成员跨文件放行）；③ 只查标识符根，`.` 与 `^` 右侧不查；④ 调用名与调用内 `形参 :=` / `=>` 不查；⑤ 全大写标识符放行；⑥ 字面量（`T#`、`16#`、字符串）先置空 | 0 |
| `enum_case_completeness` | 53 | 只对「被 CASE 选择子实际使用」的文件内 ENUM 判覆盖；标签提取支持限定写法 `Type.member:` 与跨行逗号并列标签 | 0 |
| `enum_separator` | 1477 | TYPE 枚举体正则禁止跨 `;` `(` `)` 匹配（原版吞掉了后续 VAR 块） | 0 |
| `terminator` | 17 | 识别 `INTERFACE ... END_INTERFACE`（17 个接口件不是 POU，不该要求 END_FUNCTION） | 0 |
| `bilingual_comment` | 0 | 纯注释行 / `END_VAR` 跳过；英文判定要求 ≥2 连续 ASCII 字母 | 0 |

## 4. 未覆盖项（本轮明确不检，留给下一环节）

- **码位跨文件撞号**：需与 `CODE_SEGMENT_LEDGER_R12.md` 求差断言，非文本规则。
- **语义类**：单拍脉冲闭环、首扫历史同步、无扰切换、量纲一致性 —— 文本机检无能为力（R10 的 17 个缺陷无一可文本捕获）。
- **编译验证**：连续多轮无真实编译器，`undefined_identifier` 只是弱替身（白名单放行全大写标识符）。
