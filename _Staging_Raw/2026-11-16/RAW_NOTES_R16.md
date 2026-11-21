# R16 原始狩猎笔记（RAW_NOTES_R16）—— T0 快车道零检索轮

## 1 T0 零检索声明
- 本轮 20 件全部为 **T0 组（IEC 61131-3 标准函数/功能块防御性包装）**，**零 WebSearch**。接口语义由 IEC 61131-3 标准定义，不构成版权文本；实现 clean-room，文件头溯源统一标注「IEC 61131-3 标准语义的道莅防御性实现」。
- 依据 SOURCE_HUNTING_MATRIX.md 第 5 节 T0-5 行：R14 收 ROUND、R15 收 TRUNC/FLOOR/CEIL，「防御型 `*_TO_*` 族与 BCD↔INT 越界族移交 T0 变体线（R16 开线）」——本轮即为该移交的落地轮。

## 2 样板提取来源（逐字样板已嵌入派单文本）
- `C:\Library\DL_MathData\FC_DL_StringFindEx.st`（R15）：FC 紧凑式文件头样板、VAR_INPUT/OUTPUT/eErr 声明样板、段注释 `// 段 N｜中文 / English` 样板、闸门段（置码 + RETURN）样板。
- `C:\Library\DL_Base\FB_DL_TonEx.st`（R14）：横幅式文件头样板、信息级码位「钳位不置故障」口径、R6 状态机 N/A 说明口径（本轮全部为纯 FC 无状态机，R6 一律标注 N/A 并说明）。
- **注意**：R15 存量样板内含 `(* 中文 EN: xxx *)` 行内写法，**本轮禁用**——注释统一 `// 中文 / English` 一行一条，禁止 (* *) 与任何嵌套注释。

## 3 码位游标确认
- R15 实占（DL_MathData/VERSION.md v1.9.0 台账）：信息级 `015E~01BD`（24 码）、故障级 `024B~028B`（10 码）。
- 全库游标（本轮交接口径）：**信息级止于 01BF、故障级止于 028D**（01BE/01BF 与 028C/028D 为 DL_Base 侧 R15 余量，终审以脚本对全库求差断言为准）。
- R16 分配：**信息级 01C0~01E7（40 码）、故障级 028E~02C9（60 码）**，每件 5 槽（信息 2 + 故障 3）；R17 游标顺延 **01E8 / 02CA**。

## 4 立项否决/调整记录
- 16 位 BCD 双向件（BcdToInt/WordToBcd 类）否决重复：`FC_DL_BcdToWord` / `FC_DL_WordToBcd` 已于 R9 入库；改立 32 位 BCD 双向件 2 件。
- 有符号 `IntToBcd` 否决：有符号 BCD 符号约定平台分歧，无法给出统一防御语义。
- 补位 **TIME 算术防御族 4 件**（+/−/×/÷ 的溢出与负值行为平台不一致，与 TON 负 PT 同类防御域）。

## 5 不动清单
- 本轮不修改任何 `.st`、`INDEX_REGISTRY.json`、JSONL；只产出 `ROUND_PLAN_R16.md` 与本文件。
