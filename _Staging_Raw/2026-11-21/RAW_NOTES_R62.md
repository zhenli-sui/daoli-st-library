# RAW_NOTES_R62 — 源留痕与合规台账（2026-11-21）

> 本轮**零检索**（WebSearch 0/3）。11 件全部为「标准语义 / 公开分类」驱动的 clean-room 实现，无任何第三方代码行进入 `C:\Library`。
> 格式：来源 / 类型 / URL 或标识 / 许可证 / 提取点 / 复制度 / 商用结论。

---

## 一、T0 族内深化（8 件，`iec-std-wrapper`）——零检索，无外部源

| 组件 | 参考 | 许可证 | 提取点 | 复制度 |
|---|---|---|---|---|
| `FC_DL_SaturateMul` | IEC 61131-3:2013 §6.6 算术运算符（MULT）+ LINT 域极限定义 | 标准公开语义 | 饱和语义与溢出前置判定策略 | 0 行 |
| `FC_DL_SaturateDiv` | IEC 61131-3:2013 §6.6（DIV，向零截断） | 同上 | 截断语义与除零判据顺序 | 0 行 |
| `FC_DL_ShiftArithEx` | IEC 61131-3:2013 §6.6（SHR 仅逻辑）；算术语义为通用补码事实 | 同上 | 符号位扩展定义 | 0 行 |
| `FC_DL_SignExtendEx` | IEC 61131-3:2013 位串类型与掩码运算 | 同上 | 符号 / 零扩展定义 | 0 行 |
| `FC_DL_RealToIntSat` | IEC 61131-3:2013 §6.5 类型转换（TRUNC 族） | 同上 | 向零截断语义 | 0 行 |
| `FC_DL_SignedToUdintSat` | IEC 61131-3:2013 有 / 无符号域包含关系 | 同上 | 域包含证明 `[0, 2^31−1] ⊂ [0, 2^32−1]` | 0 行 |
| `FC_DL_DtToTodWrap` | IEC 61131-3:2013 DT / TOD 类型定义 | 同上 | 日模 86400 与基准闸 | 0 行 |
| `FC_DL_PercentileRank` | 统计学公开定义（弱 / 强 / 中位排名三口径） | 公共知识 | 三口径公式 | 0 行 |

- **结论**：无可商用性风险。全部实现为本库自有防御性包装（域闸 / 钳位 / 三件套码位），与公开标准文本无逐字对应。
- **内联禁令遵守**：`DtToTodWrap` 未重写日期算法，`PercentileRank` 未内联排序（均委托同子库既有属主件，R216）。

---

## 二、T1-8 GitHub topics（`dsp-public-cookbook`）——1 件

| 项 | 内容 |
|---|---|
| 组件 | `FB_DL_BiquadFilter`（DL_Algo） |
| 来源类型 | 公开 DSP 教科书 / 公开滤波器设计手册的**通用公式结构**（RBJ Audio EQ Cookbook 类二阶节设计公式） |
| URL | 未取原文页（零检索轮）；公式属**公开数学定义**（双二阶直接 I 型差分方程、极点在单位圆的稳定性判据），非某仓库的独创表达 |
| 许可证 | 公式本身不可版权（idea/expression 二分）；未复制任何实现代码、注释或系数表 |
| 提取点 | ① 直接 I 型差分方程 `w = x − a1·w1 − a2·w2`、`y = b0·w + b1·w1 + b2·w2`；② 极点落单位圆内的稳定性条件（Jury 三条不等式）；③ 归一化 `a0 = 1` 的系数下发约定 |
| 复制度 | **0 行代码**。闸门（四成因四码）、变更沿清状态、抗 windup 回写、首拍初始化、出口三件套全部本库自有 |
| 商用结论 | **可商用**（MIT 出口）。**注意**：本版判据实现不充分（REVIEW_R62 D2，严重），属实现缺陷非许可证问题 |

---

## 三、T2-1 LGF Measurement（`lgf-measurement`）——1 件（闭源源）

| 项 | 内容 |
|---|---|
| 组件 | `FB_DL_VfdDcBusRipple`（DL_Device） |
| 来源 | Siemens LGF（Library of General Functions）V5.3.0，文档 ID 109479728 —— **免费使用但闭源版权** |
| 提取点 | 仅「Measurement 组」的**分类骨架**：① 电气量监视按「均值 / 峰峰值（纹波）」两级统计组织；② 双限值（欠 / 过）+ 迟滞判据的接口参数域；③ 组内组件粒度（监视件只测不驱动） |
| 复制度 | **0 行代码、0 行注释、0 个 DB 结构**。均值 / 极值 / 迟滞 / 环形窗 / 半满门限 / 码位分段全部本库自有实现；与 LGF 的差异（`_nFill` 除子、变窗长全窗清、非有限样本丢充计数）为本库 R61-D4 教训的产物 |
| 合规依据 | `SOURCE_HUNTING_MATRIX` 第 11 条「只借骨，不抄肉」；本件头注释 `开源溯源` 段已写明「分类借鉴，零代码复制」 |
| 商用结论 | **可商用**（clean-room）。闭源文档事实（组划分、参数域）不作为版权对象 |

---

## 四、T2-8 ISA / NE107（`isa-ne107`）——1 件（公开规范）

| 项 | 内容 |
|---|---|
| 组件 | `FB_DL_IonFanInterlock`（DL_Device） |
| 来源 | NAMUR NE107 诊断分级公开语义（Failure / OutOfSpec / Maintenance / Check Function 四类）+ 离子风机效能判据的公开 ESD 工程口径 |
| URL | 未取原文（零检索轮）；NE107 分级语义属**公开标准条款**，本库只借「分级 → 处置人」的映射关系 |
| 许可证 | 标准条款引用（合理使用）；未复制任何标准原文段落、图表或厂商实现 |
| 提取点 | ① 三级映射：风机反馈丧失 → Failure 级；风速 / 平衡超限 → OutOfSpec 级；② 「测点坏 vs 真超标」必须分码的处置人论证（仪表工 / 工艺工程师）；③ 迟滞两方向分别定义 |
| 复制度 | **0 行代码**。非对称许可（发放可延迟 / 撤除零延时）、三判据合取、`E_DL_IonFanPhase` 四态机、码位 0717~071C 全部本库自有 |
| 商用结论 | **可商用**（MIT 出口） |

---

## 五、拒单留痕（7 条，防下轮重复提案）

| 候选 | 拒因 | 处置 |
|---|---|---|
| `FC_DL_ShlDwordEx` / `ShrDwordEx` | 与存量 `FC_DL_ShlEx` / `ShrEx` 语义差未实测 | R63 P0 出「输入域 × 移位量」边界差表，有差立项 / 无差并入 |
| `FC_DL_StringToDintChk` | `FC_DL_StringToDint` 已存（同义） | 永拒，除非口径实测有别 |
| `FB_DL_ToolLifeCounter` | `FB_DL_ToolLifeBudget` 已存（同义） | 永拒 |
| `FC_DL_MuxEx` | `Mux2Ex` / `Mux4Ex` / `MuxIntEx` 已覆盖 | 永拒 |
| `FB_DL_PassboxInterlockSeq` | **已入库**（ROADMAP L1087 本轮勾销） | 回写 ROADMAP 防再提 |
| `FB_DL_GowningRoomSeq` | **已入库**（同上） | 回写 ROADMAP 防再提 |
| `RealToIntSat` 的 LREAL 姊妹件 | 同一件 LREAL 入参已覆盖，拆件即凑数 | 永拒（并入口径） |

---

*R62 源留痕 ｜ 零检索轮 ｜ 11 件全部 clean-room ｜ 商用结论：全部可商用（MIT）*
