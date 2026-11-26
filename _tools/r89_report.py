import json, datetime, os
D = r'C:\Library\_Staging_Raw\2026-11-25'
now = datetime.datetime.now()
TODAY = '2026-11-25'
TOTAL, TODAY_N, SFT = 1842, 78, 1881
L2P, L2F, L2E = 40, 0, 0
CX, SIMPLE = 4, 35

report = f"""# BATTLE REPORT R89（{TODAY} 第 2 轮 · 冲刺模式）

## 1. 总量与达成
| 指标 | 数值 |
|---|---|
| 总库 | **{TOTAL}/10,000（18.42%）** |
| 今日 | **{TODAY_N}/300（26.0%）** |
| 本轮入库 | **39 件**（复杂 {CX} / 简单 {SIMPLE}，简单占比 89.7%） |
| 计划 | 40 件（复杂 4 + 简单 36） |
| 拒收 | **1 件**（`FB_DL_CoilTaperTensionSeq`，判重，移 `_quarantine/R89/`） |
| 存量修复件 | **0**（非当日首轮，配额归零） |
| 本轮新件回修 | 5 件（不计修复配额） |
| 训练语料 | **{SFT} 行** |

## 2. 逐席召唤模式（如实）
| 席位 | 实际 ID | 模式 |
|---|---|---|
| 主控 dlf-lead | 本会话 | 原生 |
| 开源供料 | `daoli-oss-hunter` | **原名回退**（`dlf-oss-hunter` 不可用） |
| 编码 | `plc-programming-expert` | **原名回退** |
| 编译闸 | `daoli-compile-verifier` ×2 | **原名回退**（首裁 + 返修复裁） |
| 审校去重 | `daoli-qa-dedup` | **原名回退** |

- 团队包 `daoli-lib-factory` **连续第 7 轮未生效**，`settings.json` 五席 `enabledPlugins=true` 但运行时 not available → **需重启 WorkBuddy**。
- 零 `general-purpose` 兜底（连续第 66 轮）。子代理 **5 次**（猎人/编码/闸/审校/闸复裁），达预算上限，**修复由主控直改**（见 §4 披露）。WebSearch 0/3。

## 3. 编译闸（编译验证席原生裁决）
| 项 | 结果 |
|---|---|
| 首裁 L2 | **40/40 PASS，FAIL 0，EXEMPT 0**（连续第 12 轮零豁免） |
| 耗时 | 38.76 s 串行 jobs=1（0.97 s/件） |
| 返修复裁 | 40/40 PASS 回归，变化 0 件 |
| 负向对照 | **5 组**：缺 END_METHOD→E006、未知类型→E052、语法错→E006、E007 可达性探针、真实件投毒副本→E007 **全部命中** |
| 总裁决 | 首轮 BLOCK（跨文件符号表）→ 复裁 **RELEASE** |
| L1 静态门 | 40 PASS / 0 BLOCK，`--selftest` PASS |
| 红线抽检 | R10 构造转换 0 / R14 PROPERTY 0 / R11 分号 0 / R6 CASE 缺 ELSE 0 / 除法未守卫 0 |

**★ 本轮闸的新发现（价值最高）**：单件 L2 全 PASS，但**跨文件符号表**抓到 1 处新冲突——`FB_DL_BoothExhaustDamperSeq` 的 `E_DL_BdsPhase` 与存量 `FB_DL_BatchDoseSeq` 同名异义（成员 4 vs 8，eFault 90 vs 70）。单件编译结构上看不见，全库/MatIEC 编译必炸。已改名 `E_DL_BedsPhase` 并复裁 PASS。**旧账 11 处仍在，总数 12。**

## 4. 审校（全量 40 件，非抽样）
- 结论：**PASS 15 / BLOCK 6 / MAJOR 6（6 件）/ MINOR 19**，拒收建议 1。
- **主控复核 6 条 BLOCK：6/6 成立，误判率 0%**（R87 为 50%，本轮回训见效）。
- 已修（**主控直改，子代理预算已满 5 次，披露**；改后 `l2_check` 复跑 5/5 PASS，**标注为回归确认、非正式裁决**）：
  1. `FC_DL_ScreenEfficiencyCalc:56-62` — 效率式分母 `(1−O)(F+U−1)` 系统性把 η 放大 1/(F+U−1) 倍、四组工艺向量全饱和 100% → 改标准二产品式 `E = U(F−O)/(F(U−O))`。
  2. `FB_DL_BoothExhaustDamperSeq:101` — `_fStep` 未闸，速率入参 NaN → `fDamperOutPct` 直穿 NaN → 加 `NOT((_fStep>=0) AND (_fStep<=100))` 归零闸。
  3. `FB_DL_PaintRobotPathSeq:117` — 补偿量无出口闸 → 出口加 `NOT((_fComp<=±1000))` 归零闸。
  4. `FB_DL_ElectronicLineShaftSeq:129` — 故障锁存期仍跟随主轴 + 主轴转速 NaN 直穿 → 加 `NOT _bFaultLatch` 与 `_bMasterOk` 单点有效性位（段 0 算定）。
  5. `FB_DL_CamSlavePhaseOffsetSeq:97/180` — `fOffsetActDeg` NaN 播种后永久冻结 → 播种与出口各加 ±360° 非有限闸。
- 拒收 1：`FB_DL_CoilTaperTensionSeq` ↔ 在册 `FB_DL_WinderTensionTaperCtrl`（DL_Motion，内圈张力+锥度系数+卷径外推+斜坡限速输出完全重合，同族已 4 件）。
- 三道去重：道 1 名称命中 9（真重复 0，最高 0.851）｜道 2 指纹复合键（类型序列+参数数+首三入参语义名）**零同组**，纯类型序列 4 组 11 件为 `REAL×n` 假阳性（第 4 次复现）｜道 3 语义 **拒收 1 + 存疑放行 4**。
- **系统性缺陷（本轮最重要教训）**：5 件同一根因——**非有限闸只写在判据层（xValid/xFault），没闸断实值通路**，NaN 一路直穿 REAL 输出，占比 12.5%。已提为机检锚点候选。

## 5. 开源供料（猎人真跑）
- 队列 223 → **232 行 / 有效 228**（绿 168 / 黄 60 / 红 0），净增 **+7**（全 BSD-2-Clause），dropped 4 未删行。
- 可借码 **7/7 = 100%**（BSD-2，commit `3b729434`，`code_excerpt` 全 null）；**溯源进件 0/39 = 0%**（未虚报）。
- 四族命中（逐词单测口径）：**A 破碎筛分 0｜B 剪切卷取 3 真件但两仓全无证→入队 0｜C 锻造退火 6（`PTW-TUDa/FB_AnnealingOven` BSD-2 绿→入队 7）｜D 涂装喷涂 0**。
- **★ 方法论纠正（推翻前 7 轮结论）**：`extension:` 与 OR 组合会**静默吞结果返 0**——`extension:TcPOU crusher OR screen` 全 0，逐词单测得 spray=8/paint=16/slitter=72/annealing=6。前 7 轮「垂直族真空」结论被判为**检索式污染**，须重新逐词复核。
- 合规：红区 0 拉取；无证仓 2（`shysee/JSZW1000` 614 ST 含真 slitter、`danielfhnw/Spreizanlage_IKT` 含真 winder）**零代码零下载**。
- 队列 228 已逼近 200 红警线（≈1.5 天）。

## 6. 三方对账
| 项 | 数 | 一致性 |
|---|---|---|
| registry | **{TOTAL}** | — |
| 磁盘 `.st` | **{TOTAL}** | 双向差集 **0** |
| JSONL | **{SFT}** | 高 39 行 = R70 前遗留（历轮恒定） |
| counts | Base223 / Mat454 / Algo194 / Dev329 / Motion171 / Proc471 | sum={TOTAL} 断言过 |

## 7. 产能铁律四线
| 铁律 | 要求 | 实际 | 判定 |
|---|---|---|---|
| 修复与新增分轨 | 非首轮修复 0 | 0 | ✔ |
| 简单件占七成 | ≥28 | 35（89.7%） | ✔ |
| 族模板批量 | 一次调用写全批 | 5 族 36 件 **1 次调用** + 复杂 4 件同批 | ✔ |
| 里程碑 | T+15/40/50/60 | 规划 T+8′ / 40 件落盘 T+19′ / 闸裁 T+36′ / 入库 T+57′ | ✔（后两点延后） |

## 8. 里程碑与墙钟
| 检查点 | 目标 | 实际 | 偏差 |
|---|---|---|---|
| 规划表落盘 | T+15′ | T+8′ | −7′ |
| 编码 40 件 | T+40′ | T+19′ | −21′ |
| 闸裁完成 | T+50′ | T+36′ | −14′ |
| 入库+战报 | T+60′ | **T+62′** | **+2′ 超时** |
- 墙钟 **≈62′**，超 60′ 硬顶 2′。超时归因：闸首裁出跨文件 BLOCK → 追加第 2 次召唤复裁（+8′），叠加主控直改 5 件（+7′）。

## 9. 进化
- 五席追加 **20 条**：DIRECTOR R665-R667 / PLC R668-R671 / OSS R672-R674 / COMPILE R675-R678 / QA R679-R683。
- 游标 **R664 → R684**，本轮**零撞号**（R86 起「同轮只允许一席起号」生效）。

## 10. 下轮（R90）P0
1. **跨文件符号表并入常驻 L1**（`_r89_symtab.py` 的 TYPE 抽取逻辑），否则每轮都要手跑。
2. **旧账 11 处 ENUM 冲突清账专项**（脚本批量改名 + 全量 L2 回归）。
3. **非有限闸扩面**：本轮 5 件同型缺陷，全库扫「REAL 输出是否只写 xValid 未闸实值」。
4. **四族检索式重测**：OR 组合吞结果，须逐词单测重判「垂直族真空」结论（影响 7 轮结论）。
5. 队列补仓 ≥240（228 临界）；B 族两条真件被许可卡死，建议向作者发许可询问。
6. CI：本轮 39 件**未推送**（收口超时），R90 首件 + 改 `workflow_dispatch`。
7. 看板：本轮**不同步**（非当日末轮）。

## 11. 风险一句话
**通过率 100% 与真实可编译性仍脱钩**——单件 L2 看不见跨文件符号冲突（本轮已抓 1 例、旧账 11 例），这是当前最大的质量盲区。
"""
open(os.path.join(D, 'BATTLE_REPORT_R89.md'), 'w', encoding='utf-8').write(report)
print('battle report', len(report.splitlines()), 'lines')
