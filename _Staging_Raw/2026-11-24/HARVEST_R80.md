# HARVEST R80 — 语义空白定向采集（成组设备 / 物流 / 机器人）

- 轮次：R80 ｜ 日期：2026-11-24 ｜ 执行：dlf-oss-hunter
- 通道：codeload.github.com 整仓 tar.gz（零 REST 配额）；GitHub repo search 匿名 10/min 用于定向找仓
- 备份：`candidate_queue.jsonl.backup_R80.jsonl`（92 条原样）

## 1 规模

| 项 | 值 |
|---|---|
| 尝试仓 | 10 |
| 成功解包 | 10 |
| 有效出料（有 ST 且语义可借） | 4 |
| 扫描文件（ST/SCL/exp/TcPOU/…） | 1012（SRCI 989 + ayran 15 + WengerAG 6 + FluidPyPLC 1 + HomeAutomation 1） |
| 抽取签名 | 23（研读后筛选） |
| 进入队列 | 15（净增 15，拒收 0，重复 0） |
| 队列终态 | **107 条（绿 84 / 黄 23 / 红 0）** |

## 2 尝试仓清单与判定

| 仓 | 许可 | ST 文件 | 判定 |
|---|---|---|---|
| ★menes97/ayran-mini-fabrika | MIT | 15 | 采纳 7 件（整线节拍/灌装/罐区/立库/AGV/收缩/码垛） |
| ★ThorstenBrach/SRCI_CLIENT_PLC | MIT | 989 | 采纳 8 件（MC_* 附加块接口骨与状态机语义；枚举族 R75/R78 已入队，不重复） |
| WengerAG/structured-text-utilities | MIT | 6 | 0 采纳：字符串/时间函数与 T0-6 族饱和重合 |
| MrLostInTheInternet/FluidPyPLC | **GPL-3.0** | 1 | **红区：零代码拉取入队**，仅记思想（气动 A+/B-/C+ 行程序列的可达性判定思路） |
| Aliazzzz/Applied-Design-Patterns-in-CODESYS-V3 | MIT | 0 | 设计模式项目，ST 在导出包内，无独立文本块 |
| Aliazzzz/OOP-Concept-Examples-in-CODESYS-V3 | MIT | 0 | 同上 |
| MichielVanwelsenaere/HomeAutomation.CoDeSys3 | MIT | 1 | 单文件占位，无块 |
| guicasagrandem/OEE_Calculator_S7-1200 | 无 LICENSE | 0 | TIA 二进制工程（.ap19），**unknown → 拒收** |
| kibelin/TIA-Portal-Chiller-Control-System | 无 LICENSE | 0 | TIA 二进制工程，unknown → 拒收（制冷方向因此 0 命中） |
| mrvluiz/OEE | 无 LICENSE | 0 | TIA 二进制工程，unknown → 拒收 |

## 3 许可证分布（本轮入队 15 条）

| 许可 | 条数 | tier |
|---|---|---|
| MIT | 15 | green |
| Apache/BSD/MPL | 0 | — |
| EPL/OSCAT/NOASSERTION | 0 | — |
| GPL/AGPL/LGPL | 0（红区仅记录，0 行代码） | red=0 |

进队累计分布：绿 84 / 黄 23 / 红 0。

## 4 七个方向命中情况

| # | 方向 | 命中 | 说明 |
|---|---|---|---|
| 1 | 称重配料 / 多斗秤 / 失重秤 | ◐ | `FB_DL_FillPreactSelfLearn`（下落量 preact + 粗/细流切点自学习，称重配料核心）；失重秤 registry 已有 LossInWeightFeeder，未重复 |
| 2 | 液压气动执行器计算 | ✗ | 唯一可用源 FluidPyPLC 为 GPL-3.0，红区零复用；蓄能器/Cv/耗气量开源 ST 生态无件 |
| 3 | 制冷与冷媒 | ✗ | 定向 2 仓均为 TIA 二进制且无 LICENSE（unknown 拒收）；过热度/过冷度全网 ST 0 命中 |
| 4 | OEE / 节拍 / 稼动率 / 换型 | ◐ | 取节拍侧：`FB_DL_CupFillSealIndexer`（8 工位并行节拍）、`FB_DL_ShrinkFilmLaneBalance`（多通道节拍均衡）；OEE 指标侧仍 0（OEE 仓均无证/二进制） |
| 5 | 电池/涂布/卷绕 | ✗ | registry 已有 ElectrolyteFill* 3 件；本轮无新源 |
| 6 | 灌装/包装线节拍 | ✔ | 5 件：CupFillSealIndexer / ShrinkFilmLaneBalance / PalletSlotJobQueue / AsrsSlotAllocSeq / AgvOppChargeDock |
| 7 | 水处理（加药/膜通量/污泥龄） | ✗ | 开源 ST 生态 0 命中（膜通量、污泥龄属工艺公式，非设备逻辑） |

额外命中（非 7 方向但语义空白）：机器人运动安全 8 件（奇异/碰撞/抱闸测试/轨迹精度档位/TCP 软限位/坐标偏移/探针锁存/自由驱动）——registry robot 仅 3 命中。

## 5 合规异常

1. **红区**：`MrLostInTheInternet/FluidPyPLC` 为 GPL-3.0 → 仅记录「气动行程序列可达性判定」思想，**0 行代码入队**（铁律 1 合规）。
2. **unknown 许可拒收 3 例**：guicasagrandem/OEE_Calculator_S7-1200、kibelin/TIA-Portal-Chiller-Control-System、mrvluiz/OEE（均无 LICENSE + TIA 二进制）。

## 6 给总监的建议

1. **停止在「公式类工艺」方向招标采集**：制冷过热度、湿空气焓湿、液压 Cv/蓄能器、膜通量/污泥龄在开源 ST 生态为真空，继续扫是负收益；建议改为「工程公式 clean-room 自研」立项（附 ASHRAE/ISO 公式来源）。
2. **下一批优先挖「整机节拍 + 安全」两侧**：GitHub 上 ST 存量集中在代码生成工具与协议库，整机逻辑只有仿真/教学项目（ayran 类）才有；建议按 `factory simulation plc`、`digital twin codesys`、`conveyor IEC61131` 检索，同时补 SRCI/OPC UA Robotics 类规范仓。
3. **队列 107 条 < 200 警戒线**：按 300 件/日 × 50% 语料占比估算，当前仅够约 0.7 天生产。建议 R81 起每次召唤固定交付 ≥25 条，并放开「成组设备整机（多 FB 同仓）」的采纳上限——单仓多族提取是当前唯一可规模化路径。
