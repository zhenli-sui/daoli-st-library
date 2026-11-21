# RAW_NOTES_R14（R14 轮次留痕）

> 时间：2026-11-16 02:05~02:15 ｜ 轮次性质：500 冲刺 T0 快车道

## 1. 检索留痕

**本轮纯 T0 快车道，0 次检索，500 冲刺减配合规。** T0 组接口语义由 IEC 61131-3 标准定义、不构成版权文本，无外部源下载，`_Staging_Raw\2026-11-16\` 内无原始代码备份，仅存 `ROUND_PLAN_R14.md` 与本留痕。开源协议合规结论：不适用（无第三方代码接触面）。

## 2. 分类归属裁定（三处，详见 ROUND_PLAN_R14.md §2）

1. **定时器/计数器 → DL_Base**：依 registry 惯例（ExtendedTimer、Counter 族五件均在 DL_Base）+ 矩阵 T0-2/T0-3。
2. **字符串 → DL_MathData（改判）**：任务书初拟「字符串类归 DL_Base」，实查 registry 中 StringTrim/Split/ReplaceAll/TokenStream/ToLReal/FixedField 六件全在 DL_MathData，且 R12 已确立「LGF 把字符串归 Data Handling」的分类学结论，矩阵 T0-6 亦归 DL_MathData——**改判为 DL_MathData，保持字符串族单库聚居**。
3. **FB_DL_CtudEx 与 FB_DL_BidirectionalCounter 并存不冲突**：前者为标准 CTUD 等义防御包装（委托内建 + 钳位 + 错误码），后者为 LGF 语义扩展块（双预设/三律），MANUAL 互引声明边界。

## 3. 码位基线事实（供编码阶段终审）

- DL_Base / DL_MathData 共享 `16#0001_xxxx` 段；R13 后最大占用：信息级 **014C**（MathData）、故障级 **0225**（MathData）。
- R14 建议起点：信息级 **014D**、故障级 **0226**（ROUND_PLAN_R14.md §5 已按序预分 014D~015D / 0226~022B）。
- 历史空置 0111 / 0209 不回填。
- **终审必须走全库求差脚本**（R30 教训：注释声明「未占用」不可采信）。

## 4. ROADMAP 处置

待办池规模远超 30 条（P0/P1/P2 条目提及 286 行）→ **按本轮指令不补写 ROADMAP**。

## 5. 未竟事项（移交下一轮）

- T0 剩余候选：SIN/COS/ASIN/ACOS/ATAN/EXP/LOG/ABS/EXPT（数学余 8）、TRUNC/FLOOR/CEIL（取整余 3）、字符串八函数（LEN/LEFT/RIGHT/CONCAT/INSERT/DELETE/REPLACE/FIND）、移位变体（BYTE/WORD/LWORD 位宽版本）——R15 可直接按本计划模板续作。
- TON/TOF/TP/RTO 与既有 `FB_DL_ExtendedTimer`（四合一巨块）的 MANUAL 边界声明需在 R14 编码阶段同步写入两件头注释。
