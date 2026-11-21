# RAW_NOTES_R48（第 48 轮 · 2026-11-20 · 规划与狩猎轮，零 .st 落盘）

> 本轮 **零检索（WebSearch 0/3）**，无新增外部源抓取；全部来源复用 `SOURCE_HUNTING_MATRIX.md` 与 R39~R47 既有 RAW_NOTES。
> 交付 = 3 个规划文件（ROUND_PLAN / DISPATCH / 本文件）+ 1 件返修规格（FB_DL_ModulePottingVac v1.0.1，R47 终审挂账）。**本轮不写任何 .st、不改 INDEX_REGISTRY.json / README / CHANGELOG / ROADMAP / MATRIX / VERSION / JSONL。**

## 1 源使用台账（20 件规划，全部 clean-room）

| 序号 | 组件 | 分类 | 来源 / 矩阵行号 | URL | 许可证 / 合规口径 | 提取点（clean-room 边界声明） |
|---|---|---|---|---|---|---|
| 1 | FC_DL_SaturateSub | DL_Base | 自研线（成对补口，对标 MATRIX §T0-5 参数域惯例，T0 件数不占） | — | 无外部源 | 只对齐 SaturateAdd 引脚组织，实现自写 |
| 2 | FC_DL_SimpsonQuad | DL_MathData | T2-1 LGF · Math 数学子族（MATRIX §2） | 文档 ID 109479728 | 免费但闭源：只借分类与参数域 | 公开数学定义（复合辛普森 1/3），零代码行参照 |
| 3 | FC_DL_LagrangeInterp | DL_MathData | T2-1 LGF · Math 数学子族 | 同上 | 同上 | 公开数学定义（拉格朗日基函数），零代码参照 |
| 4 | FB_DL_ModeArbiter | DL_Base | 自研线 | — | 无外部源 | 抢占不自动回退语义为本库自有纪律 |
| 5 | FB_DL_HoldRepeatButton | DL_Base | 自研线 | — | 无外部源 | 初延+周期连发参数域为通用 HMI 惯例 |
| 6 | FB_DL_SensorFusion2 | DL_Algo | 自研线 | — | 无外部源 | 公开逆方差加权公式（行为定义），实现自写 |
| 7 | FB_DL_BiasAdaptiveTrim | DL_Algo | 自研线 | — | 无外部源 | 死区/泄漏/限幅三参数域为闭环修调通用惯例 |
| 8 | FB_DL_FuzzyTrim2In | DL_Algo | 自研线（T2-5 参数域只借） | MATRIX §1 T2-5 行 | 文档版权：只借参数域 | Mamdani 三角隶属+重心法公开结构，规则表数值自定 |
| 9 | FB_DL_Decouple2x2 | DL_Algo | 自研线 | — | 无外部源 | 公开 Bristol RGA / 静态解耦网公式（行为定义） |
| 10 | FB_DL_SolenoidCoilHealth | DL_Device | T2-6 Rockwell AOI · 设备诊断粒度（MATRIX §1 T2-6 行） | MATRIX 行 | 文档版权：只借功能分类与粒度 | 吸合窗/保持段分域诊断分类，判据与实现 clean-room |
| 11 | FB_DL_HeaterBreakDetect | DL_Device | T2-6 Rockwell AOI · 设备诊断粒度 | 同上 | 同上 | 电+温双判据分类事实，介入次序纪律为本库自有 |
| 12 | FB_DL_VibZoneClassify | DL_Device | T2-8 ISO 10816-3 公开分区（MATRIX §1 T2-8 行） | — | 公开标准：只借分区限值事实，无文本复制 | 四等级×四区限值表数值（mm/s），实现 clean-room |
| 13 | FB_DL_GapForceSwitchover | DL_Algo | T2-2 LBP · 压机工艺分类（MATRIX §1 T2-2 行） | MATRIX 行 | 闭源：只借分类 | 位置/压力切换结构分类，切换律与保持衔接自研 |
| 14 | FB_DL_LoadShareDroop | DL_Motion | T1-6 PLCopen MC 语义（MATRIX §1 T1-6 行） | MATRIX 行 | 公开规范：只借语义 | droop 调差公式为传动通用惯例（行为定义） |
| 15 | FB_DL_ZoneSpeedTrim | DL_Motion | T1-6 PLCopen MC 语义 | 同上 | 同上 | 区段限速结构分类，区段表契约自研 |
| 16 | FB_DL_ContourCrossCouple | DL_Motion | T1-6 PLCopen MC 语义 | 同上 | 同上 | 公开交叉耦合控制律（Koren 式行为定义），实现自写 |
| 17 | FB_DL_LookaheadVelPlanner | DL_Motion | T1-6 PLCopen MC 语义 | 同上 | 同上 | 拐角限速 √(a·R) 与回溯-前传两遍法公开算法式 |
| 18 | FB_DL_AutoclaveSterilSeq | DL_Process | T2-2 LBP 工艺分层 | MATRIX 行 | 闭源：只借分类 | 脉动置换-升温-保压-排干段序分类；F0 累计为公开制药合规口径 |
| 19 | FB_DL_TunnelPasteurizerSeq | DL_Process | T2-2 LBP 工艺分层 | 同上 | 同上 | 预热-杀菌-冷却段序分类，带驻留与温降联锁自研 |
| 20 | FB_DL_PumpPrimingSeq | DL_Process | T2-2 LBP 工艺分层 | 同上 | 同上 | 引水-排气-确认-主运段序分类，重试纪律自研 |

**T1/T2 覆盖**：本轮覆盖 T1-6（Motion 4 件）与 T2-1 / T2-2 / T2-5 / T2-6 / T2-8 五个 T2 族 ≥1 的要求（实际 5 族 10 件）。**零 GPL/AGPL 触碰；零闭源代码行复制；零 T0 件（矩阵 T0 余量 0，不硬凑）。**

## 2 返修规格台账（第 21 项）

- `FB_DL_ModulePottingVac`（DL_Process）v1.0.0 → **v1.0.1**：R47 终审 5 抽唯一挂账轻项——到位脉冲先于超时 TON 到 Q 消失 → 过相判据恒假误报超时。修法四要点（沿锁存 + 判据改锁存量 + 迁出链清锁存 + 头注释边界⑥）与三条验收向量已写入 `ROUND_PLAN_R48.md` §4 与 `DISPATCH_R48.md` 附节。**引脚契约零变更**；不占 20 件新件额度。

## 3 编译验证债（P1，连挂 44 轮）：DL_Algo 最小工程实编译 5 件抽样可行性与障碍清单

1. **可行**：本轮 Algo 5 件（Decouple2x2 / FuzzyTrim2In / SensorFusion2 / BiasAdaptiveTrim / GapForceSwitchover）仅依赖 Standard.library + 自有 ENUM/ST_ DUT，可在 CODESYS 3.5 空 POU 工程内单件导入编译，无外部依赖障碍。
2. **障碍一（DUT 前置）**：件内 `E_DL_*` / `ST_DL_*` 类型须先建 DUT，最小工程需按批成组导入 6~10 个 TYPE 声明，收口脚本须支持「DUT 先于 POU」的导入顺序。
3. **障碍二（告警口径）**：机检「CASE 内禁实例调用」等规则对应编译器仅是告警级（不阻断），须先固化「告警白名单 = 机检红线清单」对照表，否则编译 PASS 与机检 FAIL 并存时闸口径失据。
4. **障碍三（平台单一）**：TwinCAT 3 / InoProShop 无可用授权环境时仅 CODESYS 单平台可真编译，跨平台一致性仍只能静态保证，须在债台账注明「单平台开闸 ≠ 全平台清债」。
5. **结论**：CODESYS 单平台 5 件抽样技术可行，开闸动作归收口环节（建 compile_gate_v1 最小工程脚本）；本轮不动。

## 4 遗留债延续（P2，1 行）

- code_segment 回填 583 件 + MANUAL 补录：延续至下轮，本轮零动作、零变化。

## 5 本轮合规声明

- 三铁律核验：闭源/版权源（LGF / LBP / AOI / 日系手册）只借分类、参数域、命名组织，全部 clean-room；GPL/AGPL 零触碰；来源/URL/许可/提取点逐件留痕如上表。
- 本轮未写入任何正式目录文件；三个交付文件均在 `_Staging_Raw\2026-11-20\`；未触碰 README / CHANGELOG / ROADMAP / MATRIX / VERSION / INDEX_REGISTRY.json / JSONL。
