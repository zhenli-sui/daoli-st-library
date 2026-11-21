# RAW_NOTES_R39 — 第 39 轮源使用记录（零检索轮，WebSearch 0 次）

> **检索预算**：WebSearch **0 / 0**（本轮未执行任何网络检索；全部来源为 `SOURCE_HUNTING_MATRIX.md` 既有 ◐ 行待挖子项 + `ROADMAP.md` 未勾真缺口，同源零重复检索，复用既有 RAW_NOTES 语义）。
> 逐件来源标签归属如下（批次顺序，与 `ROUND_PLAN_R39.md` §1 一致）。

## 批 1（Base/MathData/Algo 原子）

| 组件 | 来源标签 | 提取点（clean-room 声明） |
|---|---|---|
| `FB_DL_MutexOwnerAudit` | `t0-8-sema` | 矩阵 T0-8 行待挖②「超时归还后的所有权审计」原文立项；审计出口语义自有，`FB_DL_SemaMutex` 状态枚举仅语义对齐，零代码行 |
| `FC_DL_TrendSlopeCalc` | `t2-1-lgf-math` | LGF Math 组统计语义深化；最小二乘公式为公开数学，实现与守卫自有；与 `FB_DL_Differentiator`（瞬时微分）分工已在计划表写明 |
| `FC_DL_SphericalDistance` | `t2-1-lgf-math` | Math「三角方向」待挖项；haversine 为公开领域公式（源自公开球面三角文献），仅借参数域（经纬度 → km） |
| `FB_DL_FrequencyGenerator` | `t2-1-lgf-siggen` | Signal Generators 行明文待挖「频率发生族」；与 `FB_DL_PulseGenerator`（发单发/脉宽）、`FB_DL_FrequencyMeasure`（测）两侧分工沿用矩阵 R22 记载 |
| `FB_DL_TriangleGenerator` | `t2-1-lgf-siggen` | 同行「按波形形状切块」纪律的第三基本波形（Sine/Sawtooth 已收口）；禁 eWaveform 合并的组纪律沿用 |

## 批 2（Algo 闭环 / Motion / Device 前段）

| 组件 | 来源标签 | 提取点 |
|---|---|---|
| `FB_DL_LaminatorPressCtrl` | `t2-2-lbp` | LBP「命令-监视-判定」三段分层骨架借用（R11 先例）；压力曲线闭环为 clean-room；ROADMAP 原记 Process 按分层判定改判 Algo，已在计划表留痕 |
| `FB_DL_CamOverrideTrim` | `t1-6-plcopen` | T1-6 行明文待挖「凸轮动态修调」；仅借 PLCopen CamIn/输出语义事实，修调叠加机制 100% 自有 |
| `FB_DL_AxisLimitRecovery` | `t1-6-plcopen`（t2-4-s7-motion 次源） | 安全限位（Safety-limited）公开语义的事件侧延伸——硬限位触发后恢复顺控为自研设计，仅借「限位方向性」语义事实 |
| `FB_DL_BcdFieldPanelIO` | `t2-1-lgf-converter` | Converter 组 BCD 家族（R9 双向件）的设备级阵列应用组装；转换原子全部复用库内 `FC_DL_BcdToWord`/`FC_DL_WordToBcd`，零重复实现 |
| `FB_DL_DoorInterlockHvac` | `t2-2-lbp` | 借「命令 → 监视 → 判定」分层与降频-恢复策略组织方式；炉门互锁族（全停互锁）与 HVAC 降频联锁的语义区分已在计划表写明 |

## 批 3（Device 诊断 / Process 前段）

| 组件 | 来源标签 | 提取点 |
|---|---|---|
| `FB_DL_ElMutingGantry` | `t1-5-tcopen` | TcOpen 安全组件族（光幕/安全门）深化；muting 4 传感器时序为公开行业惯例（EN ISO 13849 仅参考联锁逻辑结构，不实现安全认证功能），仲裁机制自有 |
| `FB_DL_CleaningBrushWear` | `t2-6-rockwell-aoi` | AOI 三分类诊断结构借用（R13 AhuDamperStuckDiag 先例：里程类/电流类/组态类各带独立确认窗）；判据与码位 100% 自有 |
| `FB_DL_OrificeDpZeroTrim` | `t2-8-ne43` | NE43 信号质量契约（原始域诊断不重标定）的零点漂移应用；静流判据/长期跟踪机制自有；与 `FC_DL_OrificeFlowCalc` 分工已写明 |
| `FB_DL_HjtPvdSeq` | 自研线（半导体/光伏工艺） | HJT PVD 四段顺控为工艺专家需求 clean-room 自研；段超时升级/双到位联锁沿用库内 `FB_DL_StepSequencer` 范式 |
| `FB_DL_ElectrolyteFillCtrl` | `t2-2-lbp` | LBP 定量族语义深化：减量法闭环注液为独立工艺语义（与 `FB_DL_ElectrolyteDosingSeq` 投加顺控分工），浸润驻留相语义次源 `t2-8-isa88` 不重复记账 |

## 批 4（Process 后段）

| 组件 | 来源标签 | 提取点 |
|---|---|---|
| `FB_DL_CartonDenestPush` | `t2-7-packml` | 工站级「最小子集 + 明确终止态」状态模型（R11 只借态命名先例）；分离-推箱节拍逻辑自有 |
| `FB_DL_RadiatorZoneValve` | `t2-2-lbp` | 三点浮点阀 `FB_DL_ThreePointValve` 的公开典型消费场景；房间温度闭环与最小启停间隔判据自有 |
| `FB_DL_TankLevelStrapping` | 自研线（`t2-1-lgf-math` 次源） | 容积表分层折算复用 `FC_DL_MultiPointLinear` 原子；标定核对与罐型组态语义自有 |
| `FB_DL_WaferBreakDetect` | `t2-1-lgf-measurement` | Measurement 组峰值检测（`FB_DL_PeakDetector`）+ Bit Logic（`FC_DL_BitFieldExtract`）双原子的判据消费件；「批内突发异常」分级口径自有，次源 `t2-6-aoi` 不重复记账 |
| `FB_DL_RoomCo2DemandVent` | `t1-2-oscat-building` | OSCAT Building ROOM_CONTROL 子族深化（R25 开族未挖尽：需量通风为待挖方向之一）；只借行为定义与参数域，零代码行 |

## 合规结论

- 全部 20 件声明「道莅自研 clean-room（参考 <来源标签> 分类/参数域/行为定义）」，零源码行复制、零闭源符号引用，可商用；
- T0 件（`MutexOwnerAudit`）按 T0-8 行待挖项立项，属 IEC 标准语义延伸的自研防御件；
- 状态列影响：本轮全部为既有 ✔/◐ 行深化，无 ☐→◐ 开组、无整行收口；R39 编码收尾时按惯例回写矩阵 §4/§5 对应行备注（规划线不改矩阵）。
- 判弃 17 条（防凑数变体）见 `ROUND_PLAN_R39.md` §5，逐条带 registry 实测撞车证据。

*编制：道莅工控代码库产品总监（R39 阶段一）｜ 2026-11-19 01:48*
