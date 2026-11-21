# R24 检索留痕（RAW NOTES R24）

> 生成：2026-11-17 ｜ 生成人：工控代码库产品总监 ｜ **WebSearch 使用：0 / 3 次（零检索轮）**

## 1. 检索判定依据（零检索轮合规声明）

本轮 20 个新组件 + 2 个修复件**全部零外部检索**立项，判定依据如下：

1. **T2 配额件（序号 1/2 仿射变换族）**：源矩阵 `SOURCE_HUNTING_MATRIX.md` §5 **T2-1 LGF · Math 行** R13 备注已明确登记「矩阵乘法/特征值方向不立（PLC 侧无用例），**仿射变换组合族待挖**」——该「待挖」描述粒度满足 R13 方法论勘误的「可独立验收粒度」要求（2D 仿射合成 = 平移/旋转/缩放/剪切矩阵按序相乘 + 行列式可逆性校验，验收向量可独立复算）。矩阵台账本身即留痕，无需重复检索 LGF 手册（同源不得重复检索铁律；R10/R11/R13 已多次实测 LGF Math 组参数域）。
2. **ROADMAP 行业池 18 件**：全部取自 `ROADMAP.md` §7 行业待办池**未勾选条目**（P0 ×3：§228/§469/§652；P1 ×13；P2 ×2）+ 终审立项件 §588。这些条目在历轮扩容时已按行业语汇建立并查重，本轮仅做「未注册」（registry=0、文件=0 双实测）与分类归属复核。
3. **公开公式线（免检索依据）**：风机相似定律（流量比∝转速比、压力比∝平方、功率比∝立方）、逆跟踪阴影几何、气体密度理想气体换算、Magnus-Tetens（修复件沿用 R23 已核原文）均为公开物理/工程公式，且 R23 已用 1 次检索预算核对 Stull 2011 原文并留痕 `RAW_NOTES_R23.md`，本轮不重复检索。

**结论**：本轮符合「若全部来自 ROADMAP 行业池可豁免」条款，且实际超配额满足（T2-1 仿射族 2 件为 T1/T2 源组件族）。

## 2. 修复件实物勘误（派单记忆 vs 库内实测）

| 项 | 主控派单口径 | 库内实测 | 处置 |
|---|---|---|---|
| 湿球件 POU 名/路径 | FB_DL_WetBulbTempCalc @ C:\Library\DL_Algo\FB_DL_WetBulbTempCalc.st | **FC_DL_WetBulbTempCalc** @ C:\Library\DL_Algo\FC_DL_WetBulbTempCalc.st（Glob 实测，FB 路径不存在） | 按实物 FC 名下发修复规格（纯函数、保留原引脚契约），计划书 §2 已注明 |
| WetBulb 版本 | v1.0.1 挂账 | 头注释确认 v1.0.1 挂账警示（γ 量纲错位 + 定点发散，禁用于生产） | v1.0.1 → v1.1.0 二分法重写 ✔ |
| TankN2 版本/码位 | v1.0.0 | 头注释确认 v1.0.0；信息码 0003_0184 + 0185 预留禁用、故障码 0357~0359 | v1.0.0 → v1.0.1 迟滞回差 ✔，不新占码位（0184 语义扩展留档） |

## 3. 码位游标实测记录（2026-11-17，脚本口径：grep DL_*/*.st 提取 16#XXXX_XXXX，tr 大写，sort -u 唯一）

| 段 | 提取数（唯一码） | 信息级 max | 故障级 max | 下一游标 | 主控提示值 | 偏差处置 |
|---|---|---|---|---|---|---|
| 0001 | 672 | 0465（04xx 信息带） | 03B6 | 信息 **0466** / 故障 **03B7** | 0001_04 起 | 提示与实测一致（0466 起空闲，逐点复验） |
| 0002 | 157 | —（CC 制） | —（CC 制） | 下一 CC **0x32**（已用至 0x31，32xx 零占用） | 0033 起 | **提示偏 +1**（R105 同向偏差再现）：0x32 实测空闲，按 0x32 下发，留痕 |
| 0003 | 258 | 0185 | 0359 | 信息 **0186** / 故障 **035A** | 0187/035B | 提示偏 +1：0186/035A 实测空闲，按实测下发 |
| 0004 | 171 | 01E2 | 02FE | 信息 **01E3** / 故障 **0300**（02FF 空闲但按十年带对齐从 0300 启用） | 01E4/0300 | 信息偏 +1，故障与提示一致 |
| 0005 | 241 | 01EF | 032C | 信息 **01F0** / 故障 **032D** | 01F1/032E | 提示偏 +1：01F0/032D 实测空闲，按实测下发 |

> 全部偏差为「主控交接取规划值、实测值更小」的同向 +1 型（R105 既判），本轮一律以实测胜，派单规格 §0 已内嵌实测表。

## 4. 候选查重记录

20 个组件名逐一 `grep -c` INDEX_REGISTRY.json + `ls DL_*/*名.st` 双查：**registry=0 且 files=0，零撞名**（详见 ROUND_PLAN_R24.md §1 核验行，2026-11-17 实测）。

## 5. 本轮使用源清单（战报回写素材）

| 来源标签 | 类型 | 用途 | 件数 |
|---|---|---|---|
| T2-1 LGF Math（仿射变换组合族） | T2 非 ST 借鉴 | 仿射矩阵合成/应用 2 件（只借分类事实与参数域，公式取公开线性代数，clean-room） | 2 |
| ROADMAP §7 行业池（锂电/光伏/半导体/包装/暖通/过程/水处理） | 自有路线图 | 其余 18 件立项源 | 18 |
| R23 终审挂账 | 库内 | 2 个 P0 修复件 | 2（不计入 20） |

检索预算：0/3 次使用；未触碰任何已收口组存量语义；T2-1 Math 行回写动作见 ROUND_PLAN_R24.md §6。

## 6. R24 增量机检记录（收口方，2026-11-17）

机检：audit_library_r12.py --files 扫 22 件（20 新件 + 2 修复件）。首轮 fail=7，处置如下：

| # | 文件 | 规则 | 判定 | 处置 |
|---|---|---|---|---|
| 1 | FB_DL_CoilFrostWindow.st:L44 `eDefrost : 30` | enum_separator（R33） | 真缺陷（编译阻断级：枚举单冒号） | 当场改 `:=`，复检 PASS |
| 2 | FB_DL_TankDosingMulti.st:L41 `eDosing : 20` | enum_separator | 真缺陷（同上） | 当场改 `:=`，复检 PASS |
| 3 | FB_DL_TankDosingMulti.st:L42 `eStable : 30` | enum_separator | 真缺陷（同上） | 当场改 `:=`，复检 PASS |
| 4 | FB_DL_MfcSetpointRamp.st:L158 孤立 `;` | single_colon_or_semicolon（R26） | 真缺陷 | 改显式自持 `fSpRampedSccm := fSpRampedSccm`（语义零变化），复检 PASS |
| 5 | FB_DL_PumpDryRunGuard.st:L158 孤立 `;` | single_colon_or_semicolon | 真缺陷 | 改显式自持 `_eState := _eState`，复检 PASS |
| 6 | FB_DL_TrackBarcodeTrace.st:L208 孤立 `;` | single_colon_or_semicolon | 真缺陷 | 改显式自持 `_eVerdict := _eVerdict`（输出全清由 CASE 前预置承担），复检 PASS |
| 7 | FB_DL_TrackBarcodeTrace.st ENUM E_DL_LaneRoute 成员 eNone 未被 CASE 标签覆盖 | enum_case_completeness（R31） | **误报**（逐件推演裁定） | 留档不修 |

误报裁定推演（#7）：R31 目的是拦截「CASE 分支未覆盖的枚举成员落入未定义路径」的致命缺陷。E_DL_LaneRoute.eNone 语义为「无判定/未路由」，该件 CASE（对 _eVerdict 选择子）含 ELSE 兜底，ELSE 分支行为 = 输出全清（安全侧），且 L212 显式比较 `_eVerdict <> E_DL_LaneRoute.eNone` 二次防御；判定赋值仅在 eRouted 相位出口处消费（L212 附近），eNone 态判定出口保持预置 eNone（L101）。eNone 落 ELSE 是设计意图（与 ELSE 注释「无判定：输出全清」一致），非缺陷，裁定为误报。

已知豁免核对：E_DL_Ne107Status「未声明」属主误报（属主 I_DL_DeviceHealth.st）本轮 22 件未触发 undefined_identifier 命中，无需豁免。

复检终态：SUMMARY: files=22 fail=1（唯一 fail 即上表 #7 误报）。

补充处置：FB_DL_SolderRibbonTension.st 头注释「所属子库」误写 DL_Device，与实物路径 DL_Motion 及派单计划 §1 分类不符，收口时改为 DL_Motion（文档级修正，机检规则不覆盖，留档）。

交接偏差留痕：主控指令中 counts（Motion 35/Process 47）与件数清点不符（Motion 32+4=36、Process 41+7=48），且 35/47 合计 422 与 total=424 矛盾；按实配落账 Motion 36/Process 48，保 total_components=424 与 counts 合计自洽（closeout_r24.py 内注释留痕）。

