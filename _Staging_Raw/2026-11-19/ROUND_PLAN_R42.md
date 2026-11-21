# ROUND_PLAN_R42（第 42 轮无人值守构建规划 · 2026-11-19 10:10）

> 本轮性质：**阶段一盘点 + 20 目标锁定 + 4 件 P0 返修派发**。规划轮禁止编码。
> 检索预算：WebSearch 0/3（**零检索轮**），全部取自 ROADMAP 实证真缺口（锚定正则重查版）+ 源矩阵既有 ◐ 组深化。

## 1. 盘点统计

| 项 | 数值 |
|---|---|
| 总库规模 | **725 / 10,000（7.25%）**，registry v2.33.0，last_updated 2026-11-19T07:55 |
| 今日产出 | **55 / 200**（11-19 当日，R41 已交）；500 件阶段计划已超额（725 ≥ 500） |
| 各池 counts | Base 83 / MathData 197 / Algo 74 / Device 140 / Motion 70 / Process 161 |
| ROADMAP 未勾项 | 155 条（其中带组件名 128 条；**锚定正则重查后真缺口 98 / 伪缺口 30**——R41 批量脚本首列名提取缺陷已修，改用行首锚定 `^- \[ \] \`NAME\`：` 口径） |
| 源矩阵覆盖 | 状态列标注行 110：✔ 已收口 33 / ◐ 深化中 61 / ☐ 待挖 16 → **全收口率 30%，含部分挖掘覆盖 85.5%**；T0 七组 7/7 ✔，无未收口 T0 组 |
| 进化游标 | R257（下一条新规则从 R258 编号） |

## 2. P0 返修 4 件（registry 实测路径，R203 口径）

| # | 组件 | registry 实测路径 | 严重度 | 缺陷与行号线索 |
|---|---|---|---|---|
| P0-1 | FB_DL_ConveyorDirMismatch | `C:\Library\DL_Process\FB_DL_ConveyorDirMismatch.st` | 严重 | 沿直连 TON 结构性永不到时：反窜/倒滑诊断窗（tonDiagBack/tonDiagSlide）IN 门控沿与静置窗时序冲突，行号线索：段 4「光电沿实例无条件周期刷新 + TON IN 门控」节，诊断窗刷新段 |
| P0-2 | FB_DL_AxisInposGuard | `C:\Library\DL_Motion\FB_DL_AxisInposGuard.st` | 中 | 监视 TON 跨故障相不复位：tWatch 监视相迁出后计时基残留，行号线索：段 3「使能后 tWatch 未到位 → 03AF」监视 TON 刷新与故障相退出路径 |
| P0-3 | FB_DL_CascadeWindupLink | `C:\Library\DL_Algo\FB_DL_CascadeWindupLink.st` | 中 | 故障期 bTrack 名实不一：跟踪标志在故障相未随外环输出钳制同步，行号线索：bTrack 赋值点与故障相分支（镜像钳制仅 bTrack=FALSE 相生效的 R242 前提失效） |
| P0-4 | FB_DL_AxisAbortSafeSeq | `C:\Library\DL_Motion\FB_DL_AxisAbortSafeSeq.st` | 轻 | eAbortStop 单拍迁出超时不可达：超时迁出边条件含单拍量，行号线索：eAbortStop 相超时 TON.Q 消费扫描段 |

返修不占 20 新件名额；版本 1.0.0 → 1.0.1，VERSION/MANUAL 同步，语料按 registry 索引原地重注入。

## 3. 20 新目标总表（每名已过三段查重）

双查方法（R41-1 修正版）：① registry 精确名匹配（`_names_r42.txt` 全量 725 名）；② 全库 `.st` 文件名集合（磁盘优先 R242）；③ 同义词干扫描。**首版批量脚本因「取行内首个反引号名」漏检 6 条伪缺口（PumpDryRunGuard/TrackBarcodeTrace/StringBarcodeTrace/SolderRibbonTension/WindingAlignEdge/RollCompressForceBalance 均已在册）——已按行首锚定正则重查修正**，本轮 20 名全部 REG 0 命中 / 磁盘 0 命中。

| 序 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 | 码位窗口（六段式） |
|---|---|---|---|---|---|---|---|---|
| 1 | FB_DL_OcvProbeDock | DL_Process | FB | OCV 探针台对接下压与接触校验（压力窗 + 接触电阻判据） | roadmap-li-p1 | 6 | 1 | 05_3_70~72 / 05_4_98~9A |
| 2 | FB_DL_FramingPressSeq | DL_Process | FB | 装框机压装顺控（涂胶-组框-压合节拍） | t2-2-lbp | 6 | 1 | 05_3_73~75 / 05_4_9B~9D |
| 3 | FB_DL_BinderFeederSeq | DL_Process | FB | 绝缘件振动盘供料顺控（满料/缺料双光电 + 卡料窗） | t2-2-lbp | 5 | 1 | 05_3_76~78 / 05_4_9E~A0 |
| 4 | FB_DL_SafetyDoorAuditBank | DL_Process | FB | 化成柜多安全门审计汇总（开门次数/批次锁定） | t2-8-isa182 | 4 | 1 | 05_3_79~7B / 05_4_A1~A3 |
| 5 | FB_DL_GlassFeederAccum | DL_Process | FB | 玻璃上料输送积放（多区级联积放协调） | t2-2-lbp | 5 | 1 | 05_3_7C~7E / 05_4_A4~A6 |
| 6 | FB_DL_WaferCountPreset | DL_Process | FB | 晶圆计数预置饱和（预置计满 + 花篮位模计数） | t2-1-lgf-counter | 4 | 2 | 05_3_7F~81 / 05_4_A7~A9 |
| 7 | FB_DL_SeasonMonthSched | DL_Process | FB | 供暖/制冷季月度切换窗 | t1-2-oscat-building | 5 | 2 | 05_3_82~84 / 05_4_AA~AC |
| 8 | FB_DL_HydronicMeterAudit | DL_Process | FB | 冷冻水/冷却水能量审计（流量累计 × 侧焓差） | t1-2-oscat-building | 6 | 2 | 05_3_85~87 / 05_4_AD~AF |
| 9 | FB_DL_PipeScannerRoute | DL_Process | FB | 管输批次扫码分输（扫码枪契约 + 阀序分道） | t2-2-lbp | 6 | 2 | 05_3_88~8A / 05_4_B0~B2 |
| 10 | FB_DL_RecipeSearchFifo | DL_Process | FB | 配方请求 FIFO 排队（队列 + 校验链） | t1-4-codesys-forge | 4 | 2 | 05_3_8B~8D / 05_4_B3~B5 |
| 11 | FB_DL_PollAuditBank | DL_Process | FB | 多链路轮询异常台账汇总（多实例轮询 + 首出） | t1-3-oscat-network | 5 | 3 | 05_3_8E~90 / 05_4_B6~B8 |
| 12 | FB_DL_CassetteMapVerify | DL_Process | FB | 花篮片位映射比对校验（Mapping 序列解析 + 错片定位） | roadmap-semi-p2 | 6 | 3 | 05_3_91~93 / 05_4_B9~BB |
| 13 | FB_DL_PalletGripperSafe | DL_Process | FB | 码垛夹手区域安全互锁（夹爪压力 + 区域扫描双条件） | t2-7-packml | 4 | 3 | 05_3_94~96 / 05_4_BC~BE |
| 14 | FB_DL_ElTestStation | DL_Process | FB | EL 检测工站（相机触发、缺陷坐标映射、OK/NG 归档） | roadmap-pv-p2 | 7 | 3 | 05_3_97~99 / 05_4_BF~C1 |
| 15 | FB_DL_HeatExchangerFoulingTrend | DL_Process | FB | 换热器结垢趋势诊断（传热系数衰减速率） | t1-2-oscat-building | 6 | 3 | 05_3_9A~9C / 05_4_C2~C4 |
| 16 | FB_DL_RobotArmVibrationWatch | DL_Device | FB | 晶圆传送机械手振动特征监视（高通分量 + 特征窗分级） | t2-6-rockwell-aoi | 6 | 4 | 03_5_1C~1E / 03_4_22~24 |
| 17 | FB_DL_RoofUnitDoorSw | DL_Device | FB | 屋顶机检修门-风机联锁（重启抑制轻量组态） | t1-2-oscat-building | 4 | 4 | 03_5_1F~21 / 03_4_25~27 |
| 18 | FB_DL_FilmSpliceCurtain | DL_Device | FB | 接膜工位光幕屏蔽序列（2 传感器模式屏蔽时序） | t2-8-isa182 | 5 | 4 | 03_5_22~24 / 03_4_28~2A |
| 19 | FB_DL_DamperBitDiag | DL_Device | FB | 风阀执行器位诊断打包/解包（位段提取 + 位打包复用） | t2-1-lgf-bitlogic | 4 | 4 | 03_5_25~27 / 03_4_2B~2D |
| 20 | FB_DL_BmsPdiGateway | DL_Device | FB | 楼宇侧 PDI 对象网关轮询（调度 + 异常上报） | t1-4-codesys-forge | 6 | 4 | 03_5_28~2A / 03_4_2E~30 |

分布：Process 15 / Device 5 / Motion 0 / Algo 0 —— 真缺口池 Process 独大，按 R35「不跨池凑数」如实记账；Motion/Algo 补池转下轮狩猎专项。
T2/T1 配额：满足（t2-x 8 件、t1-x 5 件、roadmap 行业池 7 件）。

### 每名反证句（R244/R40 强制）

1 OcvProbeDock：registry 0 命中；磁盘 0；词干 Ocv 命中 OcvGradingBin（分选落料，非探针对接压装）——判非同义。
2 FramingPressSeq：registry 0；磁盘 0；词干 Framing 0（Frame* 无在册名）。
3 BinderFeederSeq：registry 0；磁盘 0；词干 Binder 0。
4 SafetyDoorAuditBank：registry 0；磁盘 0；词干 SafetyDoor 命中 I_DL_SafetyDoor（单门设备接口，本件为多门审计汇总件）——判非同义。
5 GlassFeederAccum：registry 0；磁盘 0；词干 GlassFeeder 0。
6 WaferCountPreset：registry 0；磁盘 0；词干 WaferCount 命中 WaferCountAxis（计数轴）/WaferCountYield（良率统计），本件为预置饱和计数——判非同义。
7 SeasonMonthSched：registry 0；磁盘 0；词干 SeasonMonth 0。
8 HydronicMeterAudit：registry 0；磁盘 0；词干 HydronicMeter 0。
9 PipeScannerRoute：registry 0；磁盘 0；词干 PipeScan 0。
10 RecipeSearchFifo：registry 0；磁盘 0；词干 RecipeSearch 0（RecipeManager 为配方主件）。
11 PollAuditBank：registry 0；磁盘 0；词干 PollAudit 0。
12 CassetteMapVerify：registry 0；磁盘 0；词干 Cassette 命中 WaferCassetteSlot（槽位监视），本件为 Mapping 序列比对——判非同义。
13 PalletGripperSafe：registry 0；磁盘 0；词干 PalletGripper 0。
14 ElTestStation：registry 0；磁盘 0；词干 ElTest 0。
15 HeatExchangerFoulingTrend：registry 0；磁盘 0；词干 HeatExchanger 命中 HeatExchangerCtrl（控制）/HeatExchangerLmtd（LMTD 计算），本件为结垢趋势诊断——判非同义。
16 RobotArmVibrationWatch：registry 0；磁盘 0；词干 RobotArm 0。
17 RoofUnitDoorSw：registry 0；磁盘 0；词干 RoofUnit 0。
18 FilmSpliceCurtain：registry 0；磁盘 0；词干 FilmSplice 命中 FilmSpliceTensionHold/FilmSpliceDetect（张力保持/接膜检测），本件为光幕屏蔽序列——判非同义。
19 DamperBitDiag：registry 0；磁盘 0；词干 Damper 命中 AhuDamperStuckDiag（卡滞诊断）/FreshAirStepperDamper（步进执行器），本件为位诊断打包/解包——判非同义。
20 BmsPdiGateway：registry 0；磁盘 0；词干 Bms 0（PdiReadScheduler 为调度底座，本件为楼宇网关应用件）。

### 本轮剔除候选（留档防重提，R40/R41 纪律）

- FB_DL_TrackBarcodeTrace / FB_DL_StringBarcodeTrace / FB_DL_PumpDryRunGuard / FB_DL_SolderRibbonTension / FB_DL_WindingAlignEdge / FB_DL_RollCompressForceBalance：首版脚本漏检，实际已在册（6 条伪缺口）。
- FB_DL_TankBlanketPrCtrl：R41 已判 ≈TankN2BlanketCtrl 同义在册，不得更名重提。
- FB_DL_LaminatorZoneSync：R41 已判 ≈LamHeaterZoneSync 同义在册。
- FB_DL_ChamberPumpDownSeq：词干与在册 ChamberPumpDownProfile / PumpDownEnvelopeMonitor 高重叠，按「词干命中即拒」保守剔除，转下轮狩猎重立名。
- FC_DL_ShlDwordEx：ROADMAP 自注「防重复立项先查重」（ShlEx/ShrEx 在册），剔除。

## 4. 码位窗口实测与分配（口径：头部 1504 字节 ∪ 全文，R39 定档）

全库实扫实测占用上限（`grep 0005_/0003_` 全文件验证）：
- DL_Process 段 0005：故障 03xx → **036F**；信息 04xx → **0497**（R41 收口后实测）。
- DL_Device 段 0003：故障 03xx → **03FF 已满**；信息 04xx → **0421**；05xx 副带 → **051B**。

本轮分配：
- **Process 15 件**：故障 0370~039C（45 槽，`05_3_70`~`05_3_9C`），信息 0498~04C4（`05_4_98`~`05_4_C4`），逐件窗口见 §3 表。
- **Device 5 件**：03xx 故障带已满 → **启用 05xx 副带 051C~052A**（`03_5_1C`~`03_5_2A`），头注释必须写明分段理由（R192：「段 0003 故障带 03A0~03FF 于 R42 用尽，启用 05xx 副带续编，避开 0590~0599 判错位段」）；信息 0422~0430（`03_4_22`~`03_4_30`）。
- 派单前须再次以 .st 头部 1504 字节正则复扫（R75②），派单侧与编码侧两值不一致即拒单。
- 本轮 Base/MathData/Algo/Motion 零新件，不占窗口；R41 遗留全库码位普查（含 MutexOwnerAudit 4 处存量冲突）**继续挂账 P1，不阻塞主线**。

## 5. 4 批 × 5 件切分（依赖无关，直接均分）

- **批 1**：#1~#5（Process 行业池 + t2-2-lbp 骨架件）
- **批 2**：#6~#10（计数/季节窗/能量审计/分输/FIFO）
- **批 3**：#11~#15（审计/映射/安全/工站/趋势）
- **批 4**：#16~#20（Device 全部 5 件，含 05xx 副带首批启用件，头注释分段理由为必检项）

## 6. 编码派单要点（每批派单书必含）

1. **七项红线**：命名前缀与变量类型前缀；零全局耦合（禁 GVL/VAR_EXTERNAL/%I/%Q/%M）；纯 IEC 61131-3 标准类型与 Standard.library；ENUM+CASE 全覆盖含 ELSE 兜底；防御性编程（浮点禁 = 判等、防除零、数组边界、WHILE 防死锁计数器）；100% 双语文注释 + 头部七要素（含开源溯源 Origin 与修订历史）；无魔法数（阈值/限幅/超时提为带单位常量或输入引脚）。
2. **来源标签**：T0 系（本轮无）用 `iec-std-wrapper`；本批 T1/T2 标签按 §3 表逐件写入头注释 `来源 Source` 字段；ROADMAP 行业池件写 `roadmap-<行业>-p<N>`。
3. **行尾 CRLF**、**双语文注释**（每行中文 + / English）、**ENUM := 单冒号体例**（R34 口径：`eState : E_DL_Xxx := eIdle`）。
4. **故障码避让**：不得落入 `03_2_00` 存量段 / `05_0_90~99` 判错位段 / `06_0_90~99` 判错位段；本轮 Process 用 `05_3_70~9C`，Device 用 `03_5_1C~2A`（05xx 副带首启用，分段理由入头注释）。
5. **锁存解除式自证**（R28/R240）：每个故障锁存位先写解除式再写置位，解除式全当拍量，逐 BOOL 标注锁存量/当拍量。
6. **TON 纪律**：跨相复位显式化（R232）；周期语义禁 `TON(IN:=TRUE)` 恒真（R176）；沿直连 TON 结构审查（P0-1 教训：门控沿与计时基不得同拍互斥）。
7. **整数进位点向量**：ceil/round/钳制在「正好整除」与「上限+1」两点各一条验收向量（R28-2）。

## 7. ROADMAP 补写裁定

未勾待办 155 条 ≥ 30 → **本轮不补写新待办**（R41 口径延续）。勾选回写仅限本轮触及的 20 条 + 4 返修涉及行。

## 8. 挂账续转（R244：逐条续转不得静默清账）

- P1｜全库码位冲突普查（含 Device 05xx 副带启用后的全带核对、MutexOwnerAudit 4 处存量冲突）→ 第 3 次挂账，转 R43 首位（若 R43 仍超时则出专项回写，R192 三向一致口径）。
- P1｜编译验证债（连续多轮悬置）→ 续挂，下轮若仍不开闸则冻结高复杂度件（R195）。
