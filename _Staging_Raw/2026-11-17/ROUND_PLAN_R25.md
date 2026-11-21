# R25 轮次派单计划（ROUND PLAN R25）

> 生成：2026-11-17 08:29+ ｜ 生成人：工控代码库产品总监（阶段一盘点 + 阶段二源矩阵狩猎/去重裁定）
> 基线：`INDEX_REGISTRY.json` v2.13.0 / total=424（Base 73 / MathData 151 / Algo 44 / Device 72 / Motion 36 / Process 48）
> 本轮规模：**20 个新组件**（4 批 × 5 件，批次内按序号编写），**无修复件**（R24 无新增挂账）
> 编码者须知：本规格为唯一事实源，不读记忆只读本文件；引脚契约、码位、溯源短语一律照抄本文件与各件派单段，禁止自造惯例（R50/R59 教训）。

---

## 0. 盘点与码位游标实测

### 0.1 库账盘点（2026-11-17 08:29 实测）

| 指标 | 数值 | 说明 |
|---|---|---|
| 总库组件数 | **424** | `registry.total_components` = `counts` 六库合计 = 424（自洽，R118） |
| 今日（registered_at = 2026-11-17）入库 | **40** | 即 R23 的 20 件 + R24 的 20 件，今日目标 200 |
| 距 500 冲刺目标差额 | **76** | R25 交付 20 件后 = 444，尚余 56 ≈ 3 轮（R26/R27/R28） |
| 距 10,000 总目标 | 9,576 | 长期线，不作为本轮约束 |
| 源矩阵覆盖率 | T1 八组全部开组（T1-1/T1-2/T1-3✔/T1-4/T1-5/T1-6/T1-7/T1-8）；T2 八组全部开组；T0 八行全部 ✔ 收口；**整组收口仅 3 行**（T0 全行、T1-3、T2-1 Converter 子族） | 覆盖率不等于进度：14 个 ◐ 行仍在挖 |

### 0.2 码位游标实测（grep 全库 `DL_*/*.st` 反算，R61/R105/R111 铁律）

| 段 | 归属 | 信息级实测最大 | **下一信息游标** | 故障级实测最大 | **下一故障游标** |
|---|---|---|---|---|---|
| 0001 | DL_Base + DL_MathData | `0001_046E`（04xx 延伸带） | **046F** | `0001_03BC` | **03BD** |
| 0002 | DL_Algo（CC 制） | 实测 CC 已用至 **0x32** | **下一 CC = 0x33** | 同左，CC 内 5 槽 `xx01/xx02/xx05/xx10/xx11/xx12` | — |
| 0003 | DL_Device | `0003_018F` | **0190** | `0003_0368` | **0369** |
| 0004 | DL_Motion | `0004_01EA` | **01EB** | `0004_030B` | **030C** |
| 0005 | DL_Process | `0005_01FD`（01xx 主带仅余 01FE/01FF 两码） | **0400（启用 04xx 延伸带，见 §0.3）** | `0005_0341` | **0342** |

> **交接值勘误（R105 第二次同向偏差，留痕）**：主控本轮交接值（0001 信息 048C / 故障 03B7；0003 信息 0186 / 故障 035A；0004 信息 01E3 / 故障 02FF；0005 信息 01F0 / 故障 032D；0002 CC≈32）**三项领先、两项落后于实测**：信息侧交接值为 R24 派单时的「规划游标」而非「收口实测」——R24 实际用满 046E / 0190 前一位 / 01EA / 01FD，故交接值在信息侧一律偏小 1~2；而 `0001` 故障带交接值 03B7 反被 R24 实际用至 03BC 而落后。**结论：以本表实测值为唯一事实源**，任何后续轮次交接必须给「收口后实测游标 + 实测脚本」双要素（R111）。

### 0.3 裁定：0005 段信息带迁移至 04xx 延伸带（本轮新增治理决定）

- 事实：`0005` 信息主带 `01xx` 已用到 `01FD`，仅余 `01FE`/`01FF` 两码；`02xx` 子带被 R3~R8 遗留「每组件自占小段」的公共码占用（实测 `0200~0214` 有主），不可续用；故障带 `03xx` 至 `0341`。
- 裁定：按 R79 立下的「**双游标子带纪律（信息 04xx / 故障 03xx 不跨用）**」，`0005` 自 R25 起把信息级新码迁入 **`04xx` 延伸带，起始 `0400`**；故障级继续在 `03xx` 顺延（`0342` 起）。`01FE`/`01FF` 两码**冻结保留**，作为 `0005` 主带的最后两枚应急槽，不分配给本轮。
- 影响：本轮 9 件 Process 件信息码落 `0400~0411`；故障码落 `0342~035C`。收口后 `0005` 游标 = 信息 `0412` / 故障 `035D`。
- 该裁定同时适用于后续所有 Process 新件，直至 `04xx` 用尽（余 0x0400~0x04FF，共 256 槽，按 18 码/轮估算可支撑 14 轮）。

---

## 1. 20 组件目标清单（总表）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_Affine2DInvert` | DL_MathData | FC | 二维仿射矩阵求逆（线性块 2×2 伴随 + 平移列反算，与 Compose/Apply 构成定义-应用-逆三元闭环） | `t2-lgf-math-affine`（T2-1 LGF Math 仿射子族深化，矩阵 R24 备注「齐次/逆映射仍待挖」） | 4 | 1 |
| 2 | `FB_DL_ParticleCounterStat` | DL_Algo | FB | 洁净室尘埃粒子 6 通道计数 → 浓度 → ISO 14644-1 等级判定 + 连续超限确认 + 失采检测 | `roadmap-p1-semi`（§7.3 半导体）+ `iso14644-1` | 6 | 1 |
| 3 | `FB_DL_CoolingTowerApproachCalc` | DL_Algo | FB | 冷却塔逼近度（湿球基准）计算 + 滑动均值 + 风机台数优化建议（N+1、防频繁换台） | `roadmap-r24-p0`（R24 终审线增补）+ `roadmap-p1-hvac` | 6 | 1 |
| 4 | `FB_DL_InverterGridSync` | DL_Device | FB | 并网同步四窗监视（电压/频率/相角/相序）+ 确认延时 + 阻塞掩码，仅出许可建议不控 | `roadmap-p0-pv`（§7.2） | 5 | 1 |
| 5 | `FB_DL_HeatPumpDefrost` | DL_Device | FB | 空气源热泵除霜三条件进入判据 + 除霜态时序 + 盘管温退出 + 最小间隔防频繁 | `roadmap-p1-hvac`（§7.5） | 6 | 1 |
| 6 | `FB_DL_VavBoxCtrl` | DL_Device | FB | 压力无关型 VAV 末端风量闭环（PI）+ 最小/最大风量位 + 开度限幅 + 指令-反馈偏差诊断 | `roadmap-p1-hvac`（§7.5） | 7 | 2 |
| 7 | `FB_DL_WaferMapping` | DL_Device | FB | Mapping 传感器序列解析 → 25 槽片位图 + 空位/双片/斜插识别 + 片数统计 | `roadmap-p1-semi`（§7.3） | 6 | 2 |
| 8 | `FB_DL_DuctStaticReset` | DL_Algo | FB | 风管静压重置（最不利末端阀位 → 静压设定，带死区/限斜率/上下限） | `roadmap-p1-hvac`（§7.5） | 5 | 2 |
| 9 | `FB_DL_DewpointReset` | DL_Algo | FB | 露点重置冷冻水供水温度设定（露点 + 安全余量 + 限斜率 + 防结露下限） | `t1-2-oscat-building`（ROOM_CONTROL 族）+ `roadmap-p1-hvac`（§7.5） | 5 | 2 |
| 10 | `FB_DL_RoomClimateCtrl` | DL_Process | FB | 房间温湿度双回路耦合控制 + 四阀分程 + 防结露联锁 + 温湿互斥仲裁 | `t1-2-oscat-building`（ROOM_CONTROL 行为定义，族内第 2 件） | 9 | 2 |
| 11 | `FB_DL_StackingAlignCtrl` | DL_Motion | FB | 叠片对位（CCD 像素偏差 → 标定逆映射 → 双轴纠偏量 + 超差 NG + 行程限幅） | `roadmap-p0-lithium`（§7.1） | 7 | 3 |
| 12 | `FB_DL_WeightCheckReject` | DL_Process | FB | 动态称重滤波 + 欠重/合格/超重分级 + 剔除指令-反馈握手 + 拒动/漏剔检测 | `roadmap-p0-pack`（§7.4） | 6 | 3 |
| 13 | `FB_DL_LabelApplySync` | DL_Motion | FB | 贴标同步（编码器差分分频 → 出标触发 + 提前量补偿 + 漏标检测），不触轴状态 | `roadmap-p1-pack`（§7.4） | 7 | 3 |
| 14 | `FB_DL_CasePackerPattern` | DL_Process | FB | 装箱排列模式生成（多规格行列层/交错/层旋转）→ 盒号到目标位姿的抓取序列 | `roadmap-p1-pack`（§7.4） | 7 | 3 |
| 15 | `FB_DL_BatteryTestCycler` | DL_Process | FB | 单通道充放电工步机（CC→CV→静置→放电→静置）+ 容量积分 + 终止判据 + 越限保护 | `roadmap-p1-lithium`（§7.1） | 9 | 3 |
| 16 | `FB_DL_PalletizerLayerSeq` | DL_Process | FB | 码垛层排布顺控（奇偶层旋转矩阵 + 层内位置序列 + 取放编排 + 满垛判定） | `roadmap-r24-p0`（R24 增补 + §7.4 重复登记去重） | 8 | 4 |
| 17 | `FB_DL_SplicerAutoJoint` | DL_Process | FB | 自动接膜零停机顺控（余量预警 → 新卷预加速 → 速度同步 → 裁切压合） | `roadmap-p1-pack`（§7.4） | 8 | 4 |
| 18 | `FB_DL_ChillerSeqMgr` | DL_Process | FB | 冷水机组群控（负荷加减机 + 轮值均衡 + 防频繁启停 + 故障切备），复用 DutyStandbyRotation | `roadmap-p0-hvac`（§7.5） | 9 | 4 |
| 19 | `FB_DL_FormationChannelMgr` | DL_Process | FB | 化成/分容柜多通道调度（空闲分配 / 异常通道隔离 / 批次台账），不内联工步机 | `roadmap-p1-lithium`（§7.1） | 7 | 4 |
| 20 | `FB_DL_SolarStringGroundFault` | DL_Process | FB | 组串对地绝缘阻抗检测（不平衡电桥法）+ 分级告警，仅监视不控 | `roadmap-r24-p0`（R24 增补） | 7 | 4 |

### 1.1 准入核验

- **撞名核验**：20 名经 `INDEX_REGISTRY.json` 全量 + 六库 `.st` 文件名 + 枚举名表三重查重，**0 撞名**（2026-11-17 实测）。
- **T1/T2 配额**（源矩阵 §4 硬性要求）：
  - **T1-2 OSCAT Building**（◐ 深化，`ROOM_CONTROL` 子族开族）→ 序号 9/10 两件构成「房间气候与露点重置族」；
  - **T2-1 LGF Math**（◐ 深化，仿射子族补口）→ 序号 1 一件；
  - 满足「≥1 个组件族来自 T1 源」且「≥1 个组件族来自 T2 源」，且两行均为**深化**、未触碰已收口组存量语义。
- **T0 线**：八行已于 R14~R20 全部 ✔ 收口，本轮**零 T0 件**（不越界再造变体）。
- **宁少勿滥**：20 件各对应独立工程语义词条，逐件在 §2 给出与既有 424 件的职责边界；被判定「同机制 / 职责重叠 / 薄件」的候选已在 §2 明示不立，**未凑数**。

### 1.2 分类改判留痕（分层判据 > ROADMAP 原标注）

| 组件 | ROADMAP 原标注 | 本轮定层 | 改判理由 |
|---|---|---|---|
| `FB_DL_DewpointReset` | §7.5 line 293 记 `DL_Process` | **`DL_Algo`** | 本质是「设定值重置律」（露点 → 供水设定 + 余量 + 限斜率），无工艺状态机、无顺序推进；与 `FC_DL_DewPointCalc` / `FB_DL_RateLimiter` 同层可直接复用，工艺层通过组合调用消费。**分层判据优先于池子原标注**（R24 `FC_DL_RangeOverlapCheck` 改判先例） |
| `FB_DL_DuctStaticReset` | §7.5 line 291 未标注 | **`DL_Algo`** | 同上（最不利阀位 → 静压设定重置律）；与 line 294 `FanPressureTrim` 原记 Process 的标注差异，按「同一机关同一层」统一到 Algo |
| `FB_DL_StackingAlignCtrl` | §7.1 line 210 未标注 | **`DL_Motion`** | 输出纠偏量并受行程限幅约束，属运动层纠偏件（与 `FB_DL_WindingAlignEdge` 同层）；工艺站只消费纠偏结果 |
| `FB_DL_InverterGridSync` / `FB_DL_WaferMapping` / `FB_DL_VavBoxCtrl` / `FB_DL_HeatPumpDefrost` | §7.2/§7.3/§7.5 未标注 | **`DL_Device`** | 均为「单台物理设备的状态判定/闭环」，符合「抽象一个真实物理器件」判据 |
| `FB_DL_ParticleCounterStat` | §7.3 line 253 未标注 | **`DL_Algo`** | 纯统计与分级算法（计数 → 浓度 → 等级），不绑定任何设备实例 |

> 分类改判一律在收口时回写 `MANUAL_DL_*.md` 的归属说明，避免下一轮把同一件在两个子库重复立项。

---

## 2. 查重与去重裁定（本轮不立清单，含理由）

| 候选（ROADMAP/矩阵原文） | 裁定 | 理由 |
|---|---|---|
| `FB_DL_CoolingTowerOpt`（§7.5） | **合并，不另立** | 与 R24 增补 `CoolingTowerApproachCalc` 同一工程语义（逼近度 + 台数优化）。一件承载，回写 ROADMAP 标注「已由 ApproachCalc 承载」 |
| `FB_DL_PalletizerLayerSeq`（§7.4 与 R24 增补**重复登记两处**） | **只立 1 件** | ROADMAP 同一名字出现两次（line 278 / line 1022），按「一语义一件」合并，回写去重注记 |
| `FB_DL_DryerExhaustHumidityCtl`（R24 增补） | **缓议** | 与既有 `FB_DL_EnthalpyCompareCtrl`（R6，焓差经济器：焓值比较 + 最小新风位硬下限 + 高限停机）职责重叠；须先出「排湿热回收 vs 新风经济器」边界表（对比排风/回风/新风的能量守恒口径），否则必成变体 |
| `FB_DL_BusbarWeldMonitor`（R24 增补） vs `FB_DL_TabWeldingMonitor`（§7.1） | **合并，本轮均不立** | 同机制（功率/能量 × 振幅/位移 × 时间的三维包络窗），一件即可；本轮不占配额，留 R26 立 1 件 |
| `FB_DL_DateCoderSync`（§7.4 喷码同步） | **不立** | 机制（编码器差分分频 + 相位偏移）已由本轮 `FB_DL_LabelApplySync` 覆盖，单独成件属机构变体 |
| `FB_DL_MfcFlowCtrl`（§7.3） | **不立** | 与既有 `FB_DL_MfcSetpointRamp`（R24 落地：设定斜坡 + 超调抑制 + 量程换算）职责重叠，剩余部分属设备层闭环，价值密度不足 |
| `FB_DL_TrackerWindStow`（§7.2） | **不立** | 与既有 `FB_DL_TrackerSnowShedAngle`（雪载卸荷角）+ `FC_DL_TrackerBacktrackCalc`（逆跟踪）同属「保护置角」族，仅判据源不同，判为凑数变体 |
| `FB_DL_VacuumChamberSeq`（§7.3） | **不立** | 已由 R24 `FB_DL_ChamberPumpDownProfile`（抽气曲线包络）覆盖主要语义 |
| `FB_DL_CartonErectSeq`（§7.4） | **不立** | 已由 R24 `FB_DL_CartonErectorStation`（七态九步骨架）覆盖 |
| `FB_DL_StringIVTrace`（§7.2） | **不立** | R24 已落地同名件（`FB_DL_StringIVTrace`），ROADMAP 待勾选即为重复项 |
| `FC_DL_ShlDwordEx`/`ShrDwordEx`（§22.2） | **不立** | 与 R14 `FC_DL_ShlEx/ShrEx` 同义（ROADMAP 自身已注「疑似与存量同义，立项前必过实测查重」），查重结论：同义 |
| `FC_DL_Affine2DInvert`（本轮序号 1，需防「变体」质疑） | **立** | 与 Compose/Apply 构成**定义 → 应用 → 逆**三元闭环，且现场有独立用例（视觉标定逆映射：机械坐标回算像素以核对标定；纠偏量反算）；非参数化变体、非精度变体 |

---

## 3. 码位分配表（每件 2 信息 + 3 故障，预留槽显式标注）

### 3.1 DL_MathData（0001 段）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| `FC_DL_Affine2DInvert` | `0001_046F`（线性块奇异 → 输出零矩阵、`bValid := FALSE`）/ `0001_0470` 预留禁用 | `0001_03BD`（任一输入元素非有限）/ `0001_03BE` 预留禁用 |

### 3.2 DL_Algo（0002 段，CC 制）

| 组件 | CC | 信息级 | 故障级 | 预留 |
|---|---|---|---|---|
| `FB_DL_ParticleCounterStat` | `0x33` | `3301`（采样失采，等级不可判）/ `3302`（等级超 9 或 0.1 μm 通道在 7~9 级无限制，表驱动跳过） | `3310`（采样体积 ≤ 0 或组态非法）/ `3311`（输入非有限） | `3305`/`3312` 预留禁用 |
| `FB_DL_CoolingTowerApproachCalc` | `0x34` | `3401`（逼近度 < 0，出水低于湿球，传感器可疑）/ `3402`（换台请求被最小时长阻延） | `3410`（台数/组态非法）/ `3411`（输入非有限或湿球件故障透传） | `3405`/`3412` 预留禁用 |
| `FB_DL_DuctStaticReset` | `0x35` | `3501`（静压设定已顶上限且阀位仍全开，能力不足）/ `3502`（阀位反馈无效，保持上次设定） | `3510`（静压上下限倒置）/ `3511`（输入非有限） | `3505`/`3512` 预留禁用 |
| `FB_DL_DewpointReset` | `0x36` | `3601`（露点/供水温度域外钳位）/ `3602`（防结露下限生效，供水被抬高，除湿能力不足） | `3610`（供水上下限倒置）/ `3611`（输入非有限或露点件故障透传） | `3605`/`3612` 预留禁用 |

### 3.3 DL_Device（0003 段）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| `FB_DL_InverterGridSync` | `0190`（网侧频率 ≤ 0：断线/停机，频率差不判）/ `0191`（相角差跨 ±180 归一提示） | `0369`（输入非有限）/ `036A`（容差组态非法）/ `036B`（非法状态兜底） |
| `FB_DL_HeatPumpDefrost` | `0192`（除霜请求被最小间隔阻延）/ `0193`（除霜超时强制退出，计数累计） | `036C`（参数组态非法，含环境窗倒置）/ `036D`（输入非有限）/ `036E`（非法状态兜底） |
| `FB_DL_VavBoxCtrl` | `0194`（风阀反馈无效：保持上次开度，不塞伪值）/ `0195`（风量设定域外钳位） | `036F`（风量上下限倒置或开度界倒置）/ `0370`（输入非有限）/ `0371`（非法状态兜底） |
| `FB_DL_WaferMapping` | `0196`（存在空位/双片异常但映射整体可判）/ `0197`（序列含噪跳变提示） | `0372`（槽数非法或传感器全通道同时跳变）/ `0373`（片位索引越界）/ `0374`（非法状态兜底） |

### 3.4 DL_Motion（0004 段）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| `FB_DL_StackingAlignCtrl` | `01EB`（纠偏量被行程限幅）/ `01EC`（标定矩阵退化：沿用上次有效矩阵） | `030C`（标定矩阵非法/不可逆且无历史有效值）/ `030D`（输入非有限）/ `030E`（非法状态兜底） |
| `FB_DL_LabelApplySync` | `01ED`（提前量饱和钳位）/ `01EE`（编码器低速，无法同步，暂停出标） | `030F`（线速度/节距组态非法）/ `0310`（输入非有限）/ `0311`（非法状态兜底） |

### 3.5 DL_Process（0005 段，信息带 04xx 延伸）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| `FB_DL_RoomClimateCtrl` | `0400`（温湿回路同拍冲突被互斥仲裁）/ `0401`（防结露联锁限制降温） | `0342`（设定域/带宽组态非法）/ `0343`（输入非有限）/ `0344`（非法状态兜底） |
| `FB_DL_WeightCheckReject` | `0402`（滤波窗有效样本不足，本拍不判）/ `0403`（无料在位，跳过称重） | `0345`（上下限倒置）/ `0346`（剔除器拒动，窗内无反馈）/ `0347`（非法状态兜底） |
| `FB_DL_CasePackerPattern` | `0404`（装箱容量大于本箱数量，末层留空位）/ `0405`（交错/层旋转配置被规格钳位） | `0348`（排列容量 < 数量或行列层域非法）/ `0349`（尺寸非法/非有限）/ `034A`（非法状态兜底） |
| `FB_DL_BatteryTestCycler` | `0406`（工步切相提示）/ `0407`（容量统计饱和或工步提前终止于终止判据） | `034B`（温度/电压越限，强制断流）/ `034C`（工步超时，工艺卡死）/ `034D`（非法状态兜底） |
| `FB_DL_PalletizerLayerSeq` | `0408`（末层不满垛，留空位）/ `0409`（取放超时重试） | `034E`（层容量不足，规格不匹配）/ `034F`（取放超时耗尽，垛型中断）/ `0350`（非法状态兜底） |
| `FB_DL_SplicerAutoJoint` | `040A`（余量预警触发）/ `040B`（同步窗未达，裁切挂起） | `0351`（预加速超时，中止且不裁切）/ `0352`（胶带未就绪/刀未归零，禁止接膜）/ `0353`（非法状态兜底） |
| `FB_DL_ChillerSeqMgr` | `040C`（加/减机延迟计时中）/ `040D`（供水温度低限保护强制减机） | `0354`（无可用机组）/ `0355`（负荷/台数组态非法）/ `0356`（非法状态兜底） |
| `FB_DL_FormationChannelMgr` | `040E`（无空闲通道，分配挂起）/ `040F`（异常通道已隔离并记账） | `0357`（通道数非法/数组域越界）/ `0358`（重复分配硬件通道）/ `0359`（非法状态兜底） |
| `FB_DL_SolarStringGroundFault` | `0410`（母线电压 ≤ 0 或 Vp+Vn 近零，绝缘推算不可判）/ `0411`（单极对地阻抗失衡提示） | `035A`（桥阻/阈值组态非法）/ `035B`（输入非有限）/ `035C`（非法状态兜底） |

> **收口后预计游标**（供主控核对，一律以收口实测为准）：`0001` 信息 `0471` / 故障 `03BF`；`0002` 下一 CC `0x37`；`0003` 信息 `0198` / 故障 `0375`；`0004` 信息 `01EF` / 故障 `0312`；`0005` 信息 `0412` / 故障 `035D`。

---

## 4. 逐件引脚级规格摘要

> 通用约定：所有功能块错误出口统一 `eErr : UDINT` + `bError : BOOL` + `bValid : BOOL`；许可类输出（`bValid`/`bReady`/`bPermit*`）在失能闸与故障闸 RETURN 路径显式赋 `FALSE`（R72）；模拟量一律 `LREAL` + 单位注释；扫描间隔由调用方 `uDeltaTimeMs : UDINT` 注入，**禁用系统时间函数**；阈值/限幅/超时一律 `VAR CONSTANT` 或输入引脚（无魔法数）。

### 4.1 序号 1 ｜ `FC_DL_Affine2DInvert`（DL_MathData，批次 1，复杂度 4）

- **功能**：3×3 仿射矩阵求逆。线性块取 2×2 伴随/行列式，平移列按 `t' = −A⁻¹·t` 反算；点变换约定沿用 R24「`p' = M × p`，列向量右乘、行主序存储」。与 `FC_DL_Affine2DCompose` / `FC_DL_Affine2DApply` 构成定义-应用-逆三元闭环。
- **VAR_INPUT**：`afM : ARRAY[0..2,0..2] OF LREAL`（待求逆矩阵，行主序）｜`fDetEps : LREAL := 1.0E-6`（相对奇异判据，非正回退默认）。
- **VAR_OUTPUT**：`afMInv : ARRAY[0..2,0..2] OF LREAL`（逆矩阵，失败时全 0）｜`fDet : LREAL`（线性块行列式）｜`eErr`｜`bError`｜`bValid`。
- **边界安全**：① 任一输入非有限（NaN 用自反判、Inf 用幅值上限，R79）→ `03BD`，`afMInv` 全 0，`bValid := FALSE`；② `|det| ≤ fDetEps × maxAbs²`（相对判据，R13 Matrix3Inverse 口径）→ 信息 `046F`，`afMInv` 全 0，`bValid := FALSE`——**不可逆时禁止半逆外泄**，与 Compose 的「降级照算」策略分立并在头注释写明差异；③ **第三行不参与**（R90）：行列式与逆只按 2×2 线性块 + 平移列计算，第三行原样回填 `0/0/1` 之外的输入值不做校验；④ **不委托 `FC_DL_Matrix3Inverse`**：其行列式含第三行，与仿射语义不等价——「库内委托须等价」纪律留档于头注释（R90 家族）。
- **状态机**：N/A（R60 固定文本豁免）。
- **验收向量建议**：① `M = 平移(10,0)` → 逆 = 平移(−10,0)；② 旋转 90° × 缩放(2,0.5) 复合矩阵 → `M × M⁻¹ ≈ I`（容差 1E-9）；③ `det = 0`（退化）→ 信息 `046F` + 零矩阵；④ 随机 500 组 A×A⁻¹≈I 对拍（沿用 R13 矩阵族验算口径）。

### 4.2 序号 2 ｜ `FB_DL_ParticleCounterStat`（DL_Algo，批次 1，复杂度 6）

- **功能**：6 路粒径计数 → 浓度（颗/m³）→ ISO 14644-1 等级判定（`Cn = 10^N × (0.1/D)^2.08`，N 允许 0.5 步进）→ 连续 N 个采样超限才报警 → 失采检测。**只统计与判定，不控净化设备**。
- **VAR_INPUT**：`auCounts : ARRAY[0..5] OF UDINT`（本采样周期各粒径计数 [颗]）｜`fSampleVolL : LREAL := 1.0`（采样体积 [L]，域 > 0）｜`bSamplePulse : BOOL`（采样周期完成脉冲，上升沿取数）｜`fClassTarget : LREAL := 7.0`（目标等级 1.0~9.0，0.5 步进）｜`nConfirmSamples : INT := 3`（连续超限确认数，1~10）｜`tSampleTime : TIME := T#1M`（采样周期 [min]，用于失采判定）｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`afConcM3 : ARRAY[0..5] OF LREAL`（各粒径浓度 [颗/m³]）｜`fClassMeasured : LREAL`（实测等级，0.0 = 不可判）｜`bClassOk`｜`bOverLimit`（确认后置位）｜`bSampleLost`｜`tSinceSample : TIME`｜`uSampleCount`/`uOverCount`（饱和计数）｜`eErr`/`bError`/`bValid`｜`eState : E_DL_ParticleStatState`。
- **边界安全**：① `fSampleVolL ≤ 0` → 故障 `3310`（防除零：先判后除）；② 全通道计数为 0 且脉冲到达 = 合法「0 浓度」，**不判失采**（失采只由时间判据裁决）；③ 失采（`tSinceSample > 2 × tSampleTime`）→ 信息 `3301` + `fClassMeasured := 0.0` + `bValid := FALSE`，**禁止沿用旧等级**（旧等级会让洁净室误报达标）；④ 等级 > 9 → 判 9.0 并信息 `3302`；⑤ 粒径上限表按 ISO 14644-1 Table 1 常量表驱动（`D = 0.1/0.2/0.3/0.5/1.0/5.0 μm`），「—」（无限制）格跳过不参与判定，不做除法、不做幂运算越界；⑥ 上电首拍 `bValid := FALSE`。
- **错误码**：`3301`/`3302` 信息，`3310`/`3311` 故障，`3305`/`3312` 预留。
- **验收向量建议**：① ≥0.5 μm 计 3520 颗/m³（体积 1 L）→ 实测等级 5.0，`bClassOk` 随目标走；② 单通道超限其余达标 → 等级取最严（小数值优先）；③ 失采 3 个周期 → `3301` + 等级清零；④ 采样体积 0 → `3310`。
- **公法依据**：`Cn = 10^N × (0.1/D)^2.08`（ISO 14644-1:2015 Table 1 生成式，**本轮 1 次检索核对，见 RAW_NOTES_R25 §2**）；等级上限用**常量表**而非实时幂运算（公共领域数值，避免 `**` 运算符跨平台不可用）。

### 4.3 序号 3 ｜ `FB_DL_CoolingTowerApproachCalc`（DL_Algo，批次 1，复杂度 6）

- **功能**：逼近度 `= 冷却水出水温度 − 湿球温度`；滑动均值 + 风机台数优化**建议**（逼近度优先、N+1 冗余、最小时长、防频繁换台）。**只出建议，不直接控风机**。
- **VAR_INPUT**：`fCondOutC`（冷却水出水 [℃]）｜`fAmbDryC`（干球 [℃]）｜`fRhPct`（相对湿度 [%]）｜`fPressPa := 101325.0`（大气压 [Pa]）｜`nFanTotal : INT`（可投台数 1~8）｜`nFanRunning : INT`（当前运行台数 0~8）｜`fApproachTargetK := 4.0`（目标逼近度 [K]）｜`fApproachTolK := 0.5`（带宽 [K]）｜`tMinStageTime := T#5M`（换台最小间隔 [min]）｜`nWinSamples : INT := 10`（均值窗 1~60）｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`fWetBulbC`（湿球 [℃]）｜`fApproachK`｜`fApproachAvgK`｜`nFanCmd : INT`（建议台数）｜`bIncReq`/`bDecReq`（增减建议，单拍脉冲）｜`bNoFurtherGain`（湿球已贴限，加机无益，禁止建议加机）｜`bWetBulbFault`（下游件故障透传）｜`eErr`/`bError`/`bValid`｜`eState : E_DL_ApproachState`。
- **边界安全**：① 湿球由 `FC_DL_WetBulbTempCalc` v1.1.0 计算（R24 已重写，**组合调用不内联**），其 `bError`/`bClamped` 必须透传——**下游锁存型错误标志透传且限故障相**（R115）；② `fApproachK < 0`（出水低于湿球，热力学不可能）→ 信息 `3401` + `bValid := FALSE` + **不给任何换台建议**（传感器可疑时禁止动作）；③ `nFanRunning > nFanTotal` 或 `nFanTotal < 1` → 故障 `3410`；④ 换台请求受 `tMinStageTime` 约束，被阻延 → 信息 `3402`（上升沿发一次，不每拍刷）；⑤ 失能 → 建议台数保持、`bValid := FALSE`、不动作。
- **状态机**：`E_DL_ApproachState`（`eIdle` / `eWarmup`（均值窗未满）/ `eMonitor` / `eStageUpPending` / `eStageDownPending` / `eFault`）+ `CASE` 含 `ELSE` 兜底。
- **验收向量建议**：① 出水 32 ℃ / 干球 30 ℃ / RH 60% / 101325 Pa → 湿球 ≈ 23.9 ℃、逼近度 ≈ 8.1 K > 目标 + 带宽 → `bIncReq`；② 逼近度落 `[target−tol, target+tol]` → 建议保持；③ 出水 20 ℃ 而湿球 24 ℃ → `3401` 且无建议。

### 4.4 序号 4 ｜ `FB_DL_InverterGridSync`（DL_Device，批次 1，复杂度 5）

- **功能**：并网前/并网中同步条件监视：电压幅值差（%）、频率差（Hz）、相角差（°）、相序四窗 + 确认延时，输出**许可建议**与阻塞掩码。**仅监视不控合闸**。
- **VAR_INPUT**：`afGridVoltV : ARRAY[0..2] OF LREAL`（网侧三相电压 [V]）｜`fGridFreqHz`/`fInvFreqHz`（[Hz]）｜`fGridPhaseDeg`/`fInvPhaseDeg`（[°]）｜`fVoltTolPct := 10.0`｜`fFreqTolHz := 0.2`｜`fPhaseTolDeg := 10.0`｜`tConfirm := T#2S`｜`bPhaseSeqOk : BOOL`（相序判定由上游给出）｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`bSyncOk`｜`bPermitClose`（合闸许可建议，只读语义）｜`fVoltDiffPct`｜`fFreqDiffHz`｜`fPhaseDiffDeg`（归一 ±180）｜`uBlockMask : WORD`（bit0 电压 / bit1 频率 / bit2 相角 / bit3 相序 / bit4 输入非法）｜`eErr`/`bError`/`bValid`｜`eState : E_DL_GridSyncState`。
- **边界安全**：① 任一输入非有限 → 故障 `0369` + 掩码 bit4 + `bPermitClose := FALSE`；② `fGridFreqHz ≤ 0` 或 `fInvFreqHz ≤ 0` → 信息 `0190`，**频率差不判**（防除零/防伪同步）；③ 相角差归一用**条件加减**，禁 `MOD`（负数取余三平台不一致，R10 家族）；④ 相序不 OK → 掩码 bit3；⑤ 失能 → `bPermitClose := FALSE`（R72）；⑥ 容差 ≤ 0 或相角容差 ≥ 180 → 故障 `036A`。
- **验收向量建议**：① 三窗全在容差内并持续 `tConfirm` → `bSyncOk`/`bPermitClose`；② 相角差 350° 与 −10° 等价 → 归一后判通过；③ 频率 0 → `0190` 且不许可；④ 电压差 12% → 掩码 bit0。

### 4.5 序号 5 ｜ `FB_DL_HeatPumpDefrost`（DL_Device，批次 1，复杂度 6）

- **功能**：空气源热泵除霜判据与除霜态时序。进入三条件（盘管−环境温差、压缩机连续运行时长、环境温度窗口 ∧ 湿度）；退出（盘管温升至退出阈值 **或** 除霜超时）；最小间隔防频繁；超时连续累计供检修判据。**安全侧：任何异常退出都回制热**（除霜卡死会让蒸发器彻底结冰）。
- **VAR_INPUT**：`fCoilC`（盘管温 [℃]）｜`fAmbC`（环境温 [℃]）｜`fAmbRhPct`（环境湿度 [%]）｜`bCompRunning`｜`fCoilAmbDeltaK := 8.0`（进入温差 [K]）｜`fAmbWinLowC := -5.0` / `fAmbWinHighC := 15.0`（环境窗 [℃]）｜`fRhMinPct := 50.0`（湿度门限 [%]）｜`fExitCoilC := 12.0`（退出盘管温 [℃]）｜`tMinCompRun := T#45M`｜`tDefrostMax := T#10M`｜`tDefrostGap := T#30M`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`bDefrostReq`/`bDefrostActive`｜`tDefrostElapsed : TIME`｜`fDeltaK`｜`bBlockedByGap`｜`bOutOfWindow`｜`uDefrostCount : UDINT`（饱和）｜`uTimeoutCount : UDINT`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_DefrostState`。
- **边界安全**：① 除霜超时 → 信息 `0193` + **强制退出回制热** + `uTimeoutCount` 累计（连续 3 次由 MANUAL 建议检修，**不锁故障**：锁死会使机组彻底停机，现场代价高于结霜）；② 环境窗倒置（低 > 高）或任一时长 ≤ 0 → 故障 `036C`；③ 最小间隔未到 → `bBlockedByGap := TRUE` + 信息 `0192`（请求上升沿发一次）；④ 非有限 → 故障 `036D`；⑤ 失能 → 立即退出除霜（安全侧）+ `bValid := FALSE`；⑥ `TON` 实例在待机/故障/除霜各分支**无条件周期刷新**（R40 家族：单步超时禁相内累计）。
- **验收向量建议**：① 盘管 −6 ℃、环境 2 ℃（Δ=8 K）、湿度 85%、压机运行 50 min → 进入除霜；② 盘管升至 12 ℃ → 退出；③ 除霜 10 min 未达 12 ℃ → `0193` + 退出 + 计数；④ 退出后 20 min 内再满足条件 → `bBlockedByGap`。

### 4.6 序号 6 ｜ `FB_DL_VavBoxCtrl`（DL_Device，批次 2，复杂度 7）

- **功能**：压力无关型 VAV 末端风量闭环（PI）+ 最小/最大风量位限制 + 风阀开度限幅 + 指令-反馈偏差诊断。**失能安全侧 = 回最小开度**（保最小新风，绝不落到全关）。
- **VAR_INPUT**：`fFlowSetM3h`/`fFlowMeasM3h`（设定/实测风量 [m³/h]）｜`fFlowMinM3h`/`fFlowMaxM3h`（最小/最大风量位 [m³/h]）｜`fKpPctPerM3h := 0.02`（比例增益 [%/(m³/h)]）｜`fTiS := 120.0`（积分时间 [s]，0 = 纯比例）｜`fOpenMinPct := 20.0` / `fOpenMaxPct := 100.0`（开度界 [%]）｜`fDamperFbPct`（开度反馈 [%]）｜`bDamperFbValid`｜`fFbTolPct := 10.0`｜`tFbDelay := T#10S`｜`uDeltaTimeMs`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`fDamperCmdPct`（开度指令 [%]）｜`bAtMin`/`bAtMax`｜`fFlowErrM3h`｜`bFbMismatch`（卡滞/拒动诊断）｜`eErr`/`bError`/`bValid`｜`eState : E_DL_VavState`。
- **边界安全**：① 设定先钳入 `[fFlowMin, fFlowMax]`；`fFlowMin > fFlowMax` 或 `fOpenMin > fOpenMax` → 故障 `036F`（**默认参数必须过自身组态闸，R114**：出厂默认值不算例外）；② 反馈无效 → **保持上次开度** + 信息 `0194`（R42 家族：禁止塞 0% 或伪值，那会让末端全关）；③ 设定域外钳位 → 信息 `0195`；④ 积分抗饱和用限幅反算（不内联 PID：`VAR` 内 `fbPid : FB_DL_PidController` 组合调用，引脚契约以 `MANUAL_DL_Algo.md` 为准）；⑤ 非有限 → 故障 `0370`；⑥ 失能 → `fDamperCmdPct := fOpenMinPct`（安全侧保最小新风）+ `bValid := FALSE`；⑦ `tFbDelay` 内不判 `bFbMismatch`（防启动瞬态误报，R100 同拍起算约束显式化）。
- **验收向量建议**：① 设定 800、实测 400、min 200/max 1200 → 开度上升且不超 100%；② 反馈恒 0 而指令 60% 超 `tFbDelay` → `bFbMismatch`；③ 反馈无效 3 拍 → 开度不变 + `0194`；④ min > max → `036F`。

### 4.7 序号 7 ｜ `FB_DL_WaferMapping`（DL_Device，批次 2，复杂度 6）

- **功能**：Mapping 传感器序列解析 → 25 槽片位图 + 空位/单片/双片（斜插）识别 + 片数统计。**只解析与判定，不做机械手动作**。
- **VAR_INPUT**：`abSlotSensor : ARRAY[0..24] OF BOOL`（逐槽在位信号，长度固定 25）｜`nSlotCount : INT := 25`（在用槽数 1~25）｜`fDoubleThickPct := 1.5`（厚度倍率判双片 [倍]，用于厚度型传感器）｜`tScanTimeout := T#10S`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`abSlotOccupied : ARRAY[0..24] OF BOOL`｜`aeSlotKind : ARRAY[0..24] OF E_DL_SlotKind`（`eEmpty`/`eSingle`/`eDouble`/`eCross`（斜插）/`eUnknown`）｜`nOccupiedCount : INT`｜`bMapValid`｜`bAnyAnomaly`｜`nAnomalyCount : INT`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_WaferMapState`。
- **边界安全**：① `nSlotCount` 域 1~25，越界 → 故障 `0372`；数组访问统一 `IF nIdx >= 0 AND nIdx < nSlotCount`；② 全槽 0 = 合法空盒（**不判故障**，空 FOUP 正常工况）；③ 斜插判据：相邻槽位同时置位且非双片厚度模式 → `eCross`（相邻判定必须做 `i−1`/`i+1` 边界防护）；④ 全通道同拍跳变（相邻两拍全 0 ↔ 全 1）→ 故障 `0372`（传感器串扰/接线）；⑤ 异常但可判 → 信息 `0196`，含噪跳变 → 信息 `0197`；⑥ 槽索引越界 → 故障 `0373`。
- **验收向量建议**：① 25 槽中 1/3/5 置位 → 3 片、无异常；② 相邻 7/8 置位且厚度倍率 < 1.5 → 7/8 判 `eCross`；③ 全 0 → 合法空盒；④ `nSlotCount = 30` → `0372`。

### 4.8 序号 8 ｜ `FB_DL_DuctStaticReset`（DL_Algo，批次 2，复杂度 5）

- **功能**：风管静压设定重置：最不利末端阀位偏离目标带 → 静压设定按增益微调，带死区、限斜率、上下限。**只算设定值，不控变频器**。
- **VAR_INPUT**：`fWorstDamperPct`（最不利末端阀位 [%]）｜`fStaticMinPa`/`fStaticMaxPa`（静压设定上下限 [Pa]）｜`fBandPct := 10.0`（阀位目标带 [%]，阀位落在 `[100−band, 100]` 视为合适）｜`fGainPaPerPct := 2.0`（增益 [Pa/%]）｜`fRatePaPerS := 5.0`（设定斜率 [Pa/s]）｜`uDeltaTimeMs`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`fStaticSetPa`｜`bAtLimit`｜`fErrPct`（带偏差 [%]）｜`bFbInvalid`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_DuctStaticState`。
- **边界安全**：① `fStaticMinPa ≥ fStaticMaxPa` → 故障 `3510`；② 阀位域钳 0~100；③ 阀位反馈无效（上游标 `bFbInvalid`）→ **保持上次设定** + 信息 `3502`；④ 设定已顶上限而阀位仍 100% → 信息 `3501`（能力不足，风机满载），**不再继续抬设定**；⑤ 斜率限制用 `uDeltaTimeMs` 显式积分（`LREAL` 中间量，禁系统时间）；⑥ 非有限 → 故障 `3511`；⑦ 失能 → 保持设定（静压突变会导致末端振荡）+ `bValid := FALSE`。
- **验收向量建议**：① 阀位 100%（超带）→ 设定按斜率上升；② 阀位 85%（带内）→ 设定不动；③ 设定已达上限且阀位仍 100% → `3501` + `bAtLimit`；④ min ≥ max → `3510`。

### 4.9 序号 9 ｜ `FB_DL_DewpointReset`（DL_Algo，批次 2，复杂度 5，T1-2 族第 1 件）

- **功能**：依据室内露点重置冷冻水供水温度设定：`设定 = max(露点 + 安全余量, 下限)`，带斜率限制与上下限；结露风险与「除湿能力不足」双出口。
- **VAR_INPUT**：`fRoomTempC`（室内温 [℃]）｜`fRoomRhPct`（室内相对湿度 [%]）｜`fChwMinC := 7.0` / `fChwMaxC := 18.0`（供水设定界 [℃]）｜`fDewMarginK := 1.5`（安全余量 [K]）｜`fRateKPerS := 0.05`（斜率 [K/s]）｜`uDeltaTimeMs`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`fChwSetC`｜`fDewPointC`｜`fMarginK`｜`bCondRisk`（露点超出可调范围，除湿能力不足）｜`bAtMin`/`bAtMax`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_DewpointResetState`。
- **边界安全**：① 露点由 `FC_DL_DewPointCalc` 计算（Magnus-Tetens 常数唯一属主 `FC_DL_VaporPressureSat`，R23 裁定）——**只调用不复制**；其错误透传（R115）；② RH 域钳 1~100，钳位 → 信息 `3601`；③ 露点 + 余量 > `fChwMaxC` → `bCondRisk := TRUE` + 信息 `3602`，设定被顶到上限（**如实反映「制冷量再低也压不住露点」**，不静默）；④ `fChwMinC ≥ fChwMaxC` → 故障 `3610`；⑤ 非有限 → 故障 `3611`；⑥ 失能 → 保持设定 + `bValid := FALSE`。
- **验收向量建议**：① 24 ℃ / 55%RH → 露点 ≈ 14.6 ℃，设定 ≈ 16.1 ℃；② 26 ℃ / 80%RH → 露点 ≈ 22.3 ℃ > 上限 18 → `bCondRisk` + `3602` + 设定 = 18；③ RH = 0 → 钳 1 + `3601`。

### 4.10 序号 10 ｜ `FB_DL_RoomClimateCtrl`（DL_Process，批次 2，复杂度 9，T1-2 族第 2 件）

- **功能**：房间温湿度双回路耦合控制。温度回路 → 冷/热阀**分程**；湿度回路 → 除湿/加湿阀；防结露联锁（供水温度低于「露点 + 余量」时限制降温/除湿）；温湿同拍冲突互斥仲裁；带宽死区。
- **VAR_INPUT**：`fTempSetC`/`fTempMeasC`（[℃]）｜`fRhSetPct`/`fRhMeasPct`（[%]）｜`fTempBandK := 0.5`（温度带宽 [K]）｜`fRhBandPct := 3.0`（湿度带宽 [%]）｜`fChwSupplyC`（冷冻水供水温 [℃]，防结露用）｜`fDewMarginK := 1.5`｜`fKpValvePctPerK := 12.0`（温度回路比例 [%/K]）｜`fTiTempS := 180.0`｜`fKpDehumPctPerPct := 5.0`（湿度回路比例 [%/%]）｜`fTiRhS := 240.0`｜`uDeltaTimeMs`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`fCoolValvePct`/`fHeatValvePct`/`fDehumValvePct`/`fHumValvePct`（四阀指令 [%]）｜`bCondensationRisk`｜`bConflictArbitrated`（同拍冲突被仲裁）｜`fDewPointC`｜`bAtLimit`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_RoomClimateState`。
- **边界安全**：① 冷/热阀**互斥**（同拍只允许一侧非零，仲裁优先冷侧并置 `bConflictArbitrated` + 信息 `0400`）；② 防结露：`fChwSupplyC < 露点 + fDewMarginK` → 限制 `fCoolValvePct` 与 `fDehumValvePct` 上限并置 `bCondensationRisk` + 信息 `0401`（**这是安全联锁而非优化**，头注释写明物理后果：结露滴水导致洁净室污染）；③ 温湿回路分别用 `VAR` 内两个 `FB_DL_PidController` 实例（组合调用，**不内联**）；④ 带宽死区内输出保持（防阀频繁动作）；⑤ 设定/带宽非法（带宽 ≤ 0 或温度设定超 0~45 ℃、湿度设定超 10~95%）→ 故障 `0342`；⑥ 非有限 → 故障 `0343`；⑦ 失能 → 四阀回 0% + `bValid := FALSE`（安全侧：不制冷不加热不加湿）。
- **验收向量建议**：① 设定 22 ℃ / 50%，实测 25 ℃ / 60%，供水 7 ℃ 露点 14.6 ℃（供水低于露点 + 余量）→ `bCondensationRisk` + 降温/除湿指令被限；② 温度低于设定且湿度高于设定 → 同拍冲突 → 冷侧优先 + `0400`；③ 实测在带宽内 → 四阀保持；④ 湿度设定 99% → `0342`。

### 4.11 序号 11 ｜ `FB_DL_StackingAlignCtrl`（DL_Motion，批次 3，复杂度 7）

- **功能**：叠片对位：CCD 像素偏差 + 角度偏差 → 经标定矩阵**逆映射**得机械纠偏量（mm / mrad）→ 双轴纠偏指令 + 超差 NG + 行程限幅。**不定义轴状态、不发运动指令**（T1-6 纪律：轴状态只由运动层拥有）。
- **VAR_INPUT**：`fOffsetXPx`/`fOffsetYPx`（像素偏差 [像素]）｜`fAngleMrad`（角度偏差 [mrad]）｜`afPixelToMachine : ARRAY[0..2,0..2] OF LREAL`（像素→机械标定矩阵，行主序）｜`fAxisXMinMm`/`fAxisXMaxMm`/`fAxisYMinMm`/`fAxisYMaxMm`（纠偏行程 [mm]）｜`fNgTolMm := 0.05`（超差门限 [mm]）｜`fNgTolMrad := 2.0`（角度超差 [mrad]）｜`bCamValid`｜`bAxisInPos`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`fCorrXMm`/`fCorrYMm`（纠偏量 [mm]）｜`fCorrAngleMrad`｜`bNg`（超差判定，锁存至 `bReset`）｜`bClamped`（行程限幅生效）｜`bReady`（允许上层下发纠偏）｜`bMatrixFallback`（沿用上次有效矩阵）｜`eErr`/`bError`/`bValid`｜`eState : E_DL_StackAlignState`。
- **边界安全**：① 标定矩阵经 `FC_DL_Affine2DInvert` 求逆（组合调用；矩阵奇异 → 信息 `01EC` + 沿用上次有效矩阵 + `bMatrixFallback := TRUE`；无历史有效值 → 故障 `030C`）；② 纠偏量限幅到行程 → `bClamped` + 信息 `01EB`（**限幅后不许再当作正常纠偏计数**，须 HMI 可辨）；③ 超差 → `bNg := TRUE` **锁存**（超差件不允许因下一拍合格而自动放行）；④ `bCamValid := FALSE` → 不纠偏、`bReady := FALSE`、不改 `bNg`；⑤ 非有限 → 故障 `030D`；⑥ 失能 → 纠偏量清零 + `bReady := FALSE`（R72）。
- **验收向量建议**：① 恒等标定 + 偏差 (10,5) px → 纠偏 (10,5) mm；② 偏差 (5,0) px 但行程仅 ±3 mm → 纠偏 3 mm + `bClamped` + `01EB`；③ 偏差超 `fNgTolMm` → `bNg` 锁存；④ 标定矩阵全 0 → `01EC`（有历史）或 `030C`（无历史）。

### 4.12 序号 12 ｜ `FB_DL_WeightCheckReject`（DL_Process，批次 3，复杂度 6）

- **功能**：动态称重：滑动窗滤波 → 欠重/合格/超重分级 → 剔除指令与反馈握手 → 剔除器拒动检测。**无料在位不称重**（否则 0 g 会把空秤判成欠重并剔除）。
- **VAR_INPUT**：`fWeightG`（毛重 [g]）｜`fWeightMinG`/`fWeightMaxG`（合格域 [g]）｜`nFilterSamples : INT := 5`（滤波窗 1~15）｜`bProductPresent`（产品在位）｜`bRejectFb`（剔除完成反馈）｜`tRejectWindow := T#500MS`（反馈窗）｜`tSettle := T#200MS`（称重稳定等待）｜`uDeltaTimeMs`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`fWeightFilteredG`｜`bPass`｜`bRejectCmd`｜`nUnderCount`/`nOverCount`/`nRejectCount`（UDINT 饱和）｜`bRejectFailed`（窗内无反馈）｜`bNoProduct`｜`bStopLine`（拒动建议停线，只建议）｜`eErr`/`bError`/`bValid`｜`eState : E_DL_WeightRejectState`。
- **边界安全**：① `bProductPresent := FALSE` → 跳过判定 + 信息 `0403`（**并清滤波窗**，防止空秤样本污染下一件）；② 有效样本 < `nFilterSamples` → `bValid := FALSE` + 信息 `0402`（本拍不判，不给剔除命令）；③ `fWeightMinG ≥ fWeightMaxG` → 故障 `0345`；④ 剔除指令发出后 `tRejectWindow` 内无反馈 → 故障 `0346` + `bRejectFailed` + `bStopLine := TRUE`（漏剔会流入下游，属安全级）；⑤ 非有限 → 故障 `0347` 前一级？—— 非有限归 `0347` 兜底不当，**非有限置 `0347`（非法状态兜底）之前必须先有专门分支**：本件非有限走 `0346` 之外的独立分支并入 `0347` 兜底，头注释须写明映射（R45：`bError` 置位必须能在 `eErr` 找到对应码）。
- **验收向量建议**：① 500 g / 域 [495,505] → 合格；② 490 g → 欠重 + 剔除 + 反馈在窗内 → 正常；③ 剔除无反馈 → `0346` + `bStopLine`；④ 无料在位 3 拍 → `0403` 且无剔除命令。

### 4.13 序号 13 ｜ `FB_DL_LabelApplySync`（DL_Motion，批次 3，复杂度 7）

- **功能**：贴标同步：编码器累计脉冲差分求位移 → 按标签节距分频出标触发 → 提前量补偿 → 漏标检测。**不改轴状态、不发运动指令**。
- **VAR_INPUT**：`nEncoderPulse : DINT`（编码器累计脉冲，允许 32 位回绕）｜`fPulsePerMm := 100.0`（脉冲当量 [脉冲/mm]，> 0）｜`fLabelPitchMm := 50.0`（标签节距 [mm]）｜`fLeadMm := 2.0`（出标提前量 [mm]）｜`fSpeedMinMpm := 5.0`（最低同步线速度 [m/min]）｜`bLabelPresent`（标签在位）｜`tTriggerHold := T#20MS`（触发脉宽）｜`uDeltaTimeMs`｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`bFireTrigger`（出标触发）｜`uLabelsApplied`（饱和）｜`bMissedLabel`（漏标）｜`fPhaseErrMm`（相位误差 [mm]）｜`fWebSpeedMpm`｜`bLowSpeed`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_LabelSyncState`。
- **边界安全**：① 脉冲差分用 `DINT` 回绕安全写法（`nDelta := nNow − nPrev`，回绕时符号自然正确；禁按绝对值比较，R87 家族）；② `fPulsePerMm ≤ 0` 或 `fLabelPitchMm ≤ 0` → 故障 `030F`（**先判后除**）；③ 线速度低于 `fSpeedMinMpm` → 不出标 + 信息 `01EE` + `bLowSpeed`（低速下相位估算不可靠，硬出标会贴歪）；④ 提前量超一个节距 → 钳位 + 信息 `01ED`；⑤ `bLabelPresent := FALSE` → `bMissedLabel := TRUE` + 计数，不触发；⑥ 失能 → `bFireTrigger := FALSE` + `bValid := FALSE`；⑦ 非有限 → 故障 `0310`。
- **验收向量建议**：① 100 脉冲/mm、节距 50 mm → 每 5000 脉冲出标一次；② 编码器从 `16#7FFF_FFFF` 跨到 `16#8000_0000` → 差分正确、不丢标；③ 线速 2 m/min（< 5）→ `01EE` 不出标；④ `fPulsePerMm = 0` → `030F`。

### 4.14 序号 14 ｜ `FB_DL_CasePackerPattern`（DL_Process，批次 3，复杂度 7）

- **功能**：装箱排列模式生成：按箱型规格（行列层、节距、交错方式）生成「盒号 → 目标位姿 + 旋转标志」的抓取序列；支持行交错与整层 90° 旋转。**只生成序列，不执行动作**。
- **VAR_INPUT**：`nCols`/`nRows`/`nLayers : INT`（1~20）｜`fPitchXMm`/`fPitchYMm`/`fLayerGapMm`（[mm]，> 0）｜`eInterlock : E_DL_PackInterlock`（`eNone` 无交错 / `eRowShift` 行交错 / `eLayerRotate` 层旋转）｜`nBoxCount : INT`（本箱数量 1~容量）｜`bEnable`｜`bReset`。
- **VAR_OUTPUT**：`nSeqIndex : INT`（当前序号，从 1 起）｜`fTargetXMm`/`fTargetYMm`/`fTargetZMm`｜`fTargetRotDeg`（0 / 90 / 180 / 270）｜`bStepDone`（上层置位推进）｜`bLast`｜`nSlotCount : INT`（总槽位）｜`nEmptySlots : INT`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_CasePackState`。
- **边界安全**：① 容量 `nCols × nRows × nLayers` 与 `nBoxCount` 校验：`nBoxCount > 容量` → 故障 `0348`；`nBoxCount < 容量` → 合法（末层留空位）+ 信息 `0404`；② 行列层域外（≤ 0 或 > 20）→ 故障 `0348`；③ 节距 ≤ 0 或非有限 → 故障 `0349`（防除零、防负坐标倒排）；④ 序列越界防护：`nSeqIndex` 超容量即 `bLast` 且不再推进；⑤ 交错/层旋转与单层配置冲突（`nLayers = 1` 且 `eLayerRotate`）→ 钳为 `eNone` + 信息 `0405`；⑥ 失能 → 复位到序号 1 + `bValid := FALSE`。
- **验收向量建议**：① 3×2×4 = 24 槽、`nBoxCount = 24` → 24 步、末步 `bLast`；② 24 槽、`nBoxCount = 20` → 末 4 槽空 + `0404`；③ `eLayerRotate` 下第 2 层 `fTargetRotDeg = 90`；④ `nBoxCount = 30` → `0348`。

### 4.15 序号 15 ｜ `FB_DL_BatteryTestCycler`（DL_Process，批次 3，复杂度 9）

- **功能**：单通道充放电工步机：`eRest → eCcCharge → eCvCharge → eRest → eDiscCharge → eRest → eDone`，容量积分（Ah）统计、CV 终止判据、温度/电压越限保护。**不调度多通道**（多通道归序号 19）。
- **VAR_INPUT**：`fVoltV`/`fCurrentA`/`fTempC`（实测 [V]/[A]/[℃]，电流放电力负）｜`fCcCurrentA`（恒流充电电流 [A]）｜`fCvVoltV`（恒压点 [V]）｜`fCutoffCurrentA`（CV 终止电流 [A]）｜`fDiscCurrentA`（放电电流 [A]）｜`fDiscCutoffV`（放电终止电压 [V]）｜`tRestCharge`/`tRestDisc`（静置时长 [min]）｜`tMaxStep`（单工步超时 [min]）｜`fCapNomAh`（额定容量 [Ah]，> 0）｜`fVoltMaxV`/`fVoltMinV`（安全域 [V]）｜`fTempMaxC`（温度上限 [℃]）｜`bStart`/`bStop`｜`bReset`｜`uDeltaTimeMs`。
- **VAR_OUTPUT**：`eStep : E_DL_BatteryCycleState`｜`fCurrentSetA`（电流设定，故障拍立即 0）｜`fVoltLimitV`｜`fChargedAh`/`fDischargedAh`｜`fCapacityRatioPct`（`= 放电 Ah / 额定 Ah × 100`）｜`bStepDone`｜`tStepElapsed`｜`eErr`/`bError`/`bValid`。
- **边界安全**：① 安全侧优先：温度 > `fTempMaxC` 或电压越 `[fVoltMinV, fVoltMaxV]` → 故障 `034B` + `fCurrentSetA := 0.0` + 转 `eFault`（锂电热失控不可逆，安全路径最高优先）；② 单工步超 `tMaxStep` → 故障 `034C`（工艺卡死，**超时按工步独立计时，禁相内累计**，R40 家族）；③ `fCapNomAh ≤ 0` 或 `fVoltMaxV ≤ fVoltMinV` → 故障 `034C` 之外的组态分支（映射见头注释）；④ 容量积分：`Ah += |I| × Δt/3600`，`Δt` 由 `uDeltaTimeMs` 换算，**LREAL 累加防精度损失**；⑤ CV 终止：`|I| < fCutoffCurrentA` 持续 `nCvHoldSamples := 5` 拍；⑥ `bStop` → 立即 `fCurrentSetA := 0` 并回 `eIdle`；⑦ 失能 → 同上安全侧；⑧ 切相信息 `0406`、容量饱和/提前终止信息 `0407`。
- **验收向量建议**：① CC 1 A 恒流 1 h → `fChargedAh ≈ 1.0`；② CV 段电流降至 cutoff 保持 5 拍 → 切静置；③ 温度 61 ℃ 超 60 → `034B` + 电流 0；④ 工步 130 min 超 120 → `034C`。

### 4.16 序号 16 ｜ `FB_DL_PalletizerLayerSeq`（DL_Process，批次 4，复杂度 8）

- **功能**：码垛层排布顺控：奇偶层旋转（0°/90°）+ 层内位置序列 + 取放指令与反馈握手 + 满层/满垛判定。层内落点用 `FC_DL_Affine2DApply` 施加旋转（**库内复用，不复制低层**）。
- **VAR_INPUT**：`nCasePerLayer : INT`（每层箱数）｜`nLayersPerPallet : INT`（层数 1~20）｜`fPalletLengthMm`/`fPalletWidthMm`｜`fCaseLengthMm`/`fCaseWidthMm`｜`fLayerHeightMm`｜`bOddLayerRotate : BOOL`（奇偶层旋转使能）｜`bCaseReady`（来料在位）｜`bGripDone`（夹手完成反馈）｜`tGripTimeout := T#8S`｜`bStart`/`bStop`｜`bReset`｜`uDeltaTimeMs`。
- **VAR_OUTPUT**：`nLayerIndex`/`nPosIndex`（从 1 起）｜`fTargetXMm`/`fTargetYMm`/`fTargetZMm`｜`fTargetRotDeg`（0/90）｜`bPlaceCmd`｜`bLayerDone`/`bPalletDone`｜`nCaseCount : INT`｜`uPalletCount : UDINT`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_PalletLayerState`。
- **边界安全**：① 层容量自算（`floor(托盘长/箱长) × floor(托盘宽/箱宽)` 与旋转后取大者），`nCasePerLayer > 容量` → 故障 `034E`（**规格不匹配绝不「硬塞」**）；② 取放超时 → 先重试 1 次（信息 `0409`），二次超时 → 故障 `034F` + 中断垛型；③ 层高累计：`Z = (nLayerIndex−1) × fLayerHeightMm`，`LREAL` 承载防溢出；④ 末层不满 → 信息 `0408`；⑤ `bStop` → 完成当前放置后停在层边界（**不在抓取中停**，安全侧）；⑥ 失能 → 撤指令 + `bValid := FALSE`；⑦ 旋转落点必须走 `FC_DL_Affine2DApply`（阵列为常量旋转矩阵，`VAR CONSTANT`）。
- **验收向量建议**：① 托盘 1200×1000、箱 400×300 → 容量 6 层内 6 位；`nCasePerLayer = 6` 通过；② `nCasePerLayer = 8` → `034E`；③ 奇偶层旋转 → 第 2 层 `fTargetRotDeg = 90` 且 X/Y 互换；④ 夹手无反馈超时两次 → `034F`。

> **⚠️ 勘误注记（R25-RESUME 终审核定，2026-11-17 ｜ 追加式，不回改原文）**
> 验收向量①「托盘 1200×1000、箱 400×300 → 容量 6」**算术有误**。总监独立验算：正交取向 `floor(1200/400) × floor(1000/300) = 3 × 3 = 9`；旋转取向 `floor(1200/300) × floor(1000/400) = 4 × 2 = 8`；两取向各自校验，正交层容量 **9**。
> 裁定：**编码者按公式算得 9 并判定派单有误，正确**（`FB_DL_PalletizerLayerSeq` 实现与本裁定一致，v1.0.1）。连带修正：原验收向量②「`nCasePerLayer = 8` → 034E」失效（8 ≤ 9 应通过），**改为 `nCasePerLayer = 10` → 034E**；向量①的通过条件改为 6 ≤ 9 仍通过（用例不改，语义更正）。
> 规则落地：R122（派单数值型验收向量必须附算式自证）。

### 4.17 序号 17 ｜ `FB_DL_SplicerAutoJoint`（DL_Process，批次 4，复杂度 8）

- **功能**：自动接膜零停机顺控：旧卷余量预警 → 新卷预加速 → 速度同步确认 → 裁切压合 → 尾料处理。**未同步绝不裁切**（安全侧铁律）。
- **VAR_INPUT**：`fUnwindDiaMm`/`fCoreDiaMm`/`fFullDiaMm`（旧卷当前/芯径/满卷直径 [mm]）｜`fWebSpeedMpm`/`fNewRollSpeedMpm`（[m/min]）｜`fRemainWarnPct := 15.0`（余量预警 [%]）｜`fSyncTolPct := 2.0`（速度同步容差 [%]）｜`tSyncHold := T#500MS`（同步保持确认）｜`tPreAccelMax := T#20S`｜`tJointMax := T#5S`｜`bNewRollReady`/`bKnifeHome`/`bTapeOk`｜`bStart`/`bStop`/`bReset`｜`uDeltaTimeMs`。
- **VAR_OUTPUT**：`bWarnLowRoll`｜`bPreAccelCmd`｜`bSyncOk`｜`bCutCmd`（裁切指令）｜`bJointDone`｜`fRemainPct`｜`uJointCount : UDINT`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_SplicerState`。
- **边界安全**：① 余量按**面积（卷径平方）比例**计算：`((D² − d_core²) / (D_full² − d_core²)) × 100`——按直径线性折算会把余量算大一倍以上（R12 EnergyMeterAccum 同族量纲教训）；② `fFullDiaMm ≤ fCoreDiaMm` → 故障 `0351` 组态分支（映射见头注释）；③ 预加速超时 → 故障 `0351` + **中止且绝不裁切**（停机保料优于拉断）；④ 同步未达（速度差 > 容差或保持不足 `tSyncHold`）→ 裁切挂起 + 信息 `040B`（**安全侧：宁可等，不裁切**）；⑤ `bTapeOk := FALSE` 或 `bKnifeHome := FALSE` → 禁止接膜 + 故障 `0352`；⑥ `bStop` → 中止并回 `eIdle`（同③）；⑦ 余量预警上升沿 → 信息 `040A`。
- **验收向量建议**：① 满卷 800 / 芯 150 / 当前 450 → 余量 ≈ 30%；② 余量 10% → 预警但未到预加速点；③ 速度差 5%（> 2%）→ `bSyncOk := FALSE` + `040B`，无裁切；④ 预加速 25 s 未达同步 → `0351` + 中止。

### 4.18 序号 18 ｜ `FB_DL_ChillerSeqMgr`（DL_Process，批次 4，复杂度 9）

- **功能**：冷水机组群控：按负荷率加减机（双延迟防抖动）+ 轮值均衡（复用 `FB_DL_DutyStandbyRotation`）+ 防频繁启停 + 故障切备 + 供水低温保护。**不内联机组自身控制**（机组建模归设备层）。
- **VAR_INPUT**：`abChillerReady`/`abChillerRunning`/`abChillerFault : ARRAY[0..5] OF BOOL`（6 台）｜`fSupplyC`/`fReturnC`（[℃]）｜`fLoadPct`（当前负荷率 [%]）｜`fStageUpThrPct := 85.0`｜`fStageDownThrPct := 40.0`｜`tStageUpDelay := T#10M`｜`tStageDownDelay := T#15M`｜`tMinRun := T#15M`／`tMinStop := T#10M`｜`fSupplyLowC := 4.0`（供水低温保护 [℃]）｜`bEnable`/`bReset`｜`uDeltaTimeMs`。
- **VAR_OUTPUT**：`abStartCmd : ARRAY[0..5] OF BOOL`｜`nLeadChiller : INT`（−1 = 无）｜`nRunningCmd : INT`｜`fLoadAvgPct`｜`bStageUpPending`/`bStageDownPending`｜`bNoAvailable`｜`bLowSupplyProtect`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_ChillerGroupState`。
- **边界安全**：① 无可用机组（全故障/全不就绪）→ 故障 `0354` + `bNoAvailable`（工艺停机级，非提示级）；② 负荷率/阈值组态非法（`fStageDownThrPct ≥ fStageUpThrPct`）→ 故障 `0355`；③ 供水温度 < `fSupplyLowC` → 强制减机 + 信息 `040D` + `bLowSupplyProtect`（防冻管，**信息级不锁故障但强制动作**）；④ 加减机双延迟计时中 → 信息 `040C`；⑤ 需求台数域 0~6 钳位；⑥ 非有限 → 故障 `0356` 兜底前独立分支；⑦ 失能 → 全撤指令 + `bValid := FALSE`；⑧ 轮值调用 `FB_DL_DutyStandbyRotation`（组合调用，`tMinRunTime`/`tMinStopTime` 由本件引脚转发，**不重复实现最短时长逻辑**）。
- **验收向量建议**：① 负荷 90% 持续 10 min → 加机 1 台；② 负荷 35% 持续 15 min → 减机；③ 单台故障 → 立即切备（跳过故障台）；④ 供水 3.5 ℃ → 强制减机 + `040D`。

### 4.19 序号 19 ｜ `FB_DL_FormationChannelMgr`（DL_Process，批次 4，复杂度 7）

- **功能**：化成/分容柜多通道调度：空闲通道分配、异常通道隔离锁存、批次完成台账。**不内联充放电工步机**（工步归序号 15，通过布尔快照与指令握手交互）。
- **VAR_INPUT**：`abChBusy`/`abChFault`/`abChDone : ARRAY[0..15] OF BOOL`（通道快照，上限 16）｜`nChannelCount : INT := 16`｜`bAllocReq`（分配请求，上升沿）｜`bBatchStart`/`bBatchAbort`｜`bEnable`/`bReset`。
- **VAR_OUTPUT**：`nAllocatedCh : INT`（−1 = 未分配）｜`bAllocOk`｜`abChBlocked : ARRAY[0..15] OF BOOL`（隔离掩码）｜`abChCmdStart : ARRAY[0..15] OF BOOL`｜`nDoneCount`/`nFaultCount`（INT）｜`bBatchDone`/`bBatchAborted`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_FormationChState`。
- **边界安全**：① 无空闲通道 → `bAllocOk := FALSE` + 信息 `040E`，**挂起等待不置故障**（产线常态）；② 故障通道 → 隔离锁存 `abChBlocked` + 信息 `040F`（锁存至 `bReset`，防止自动复用坏通道）；③ `nChannelCount` 域 1~16，越界 → 故障 `0357`；④ 同一通道重复分配（请求未撤销又发新请求）→ 故障 `0358`（防双工步叠加烧电芯）；⑤ `bBatchAbort` → 撤全通道启动指令 + `bBatchAborted`（中止优先于完成）；⑥ 失能 → 撤指令 + `bValid := FALSE`；⑦ 数组一律按 `nChannelCount` 上界遍历 + 越界防护。
- **验收向量建议**：① 16 通道其中 3 故障、5 忙 → 分配到首个空闲非隔离通道；② 全忙 → `040E` 挂起；③ 同拍两次分配请求 → `0358`；④ 中止 → 全通道启动撤除。

### 4.20 序号 20 ｜ `FB_DL_SolarStringGroundFault`（DL_Process，批次 4，复杂度 7）

- **功能**：光伏组串对地绝缘阻抗检测（不平衡电桥法）：由正/负母线对地电压与母线电压推算正极/负极/并联对地绝缘电阻，分级告警。**仅监视不控**（不触发脱扣）。
- **VAR_INPUT**：`fPosToGroundV`/`fNegToGroundV`（正/负母线对地电压 [V]）｜`fBusV`（组串母线电压 [V]）｜`fBridgeKOhm := 100.0`（测量桥电阻 [kΩ]，> 0）｜`fWarnKOhm := 1000.0`（预警阈值 [kΩ]）｜`fAlarmKOhm := 100.0`（告警阈值 [kΩ]）｜`nConfirmSamples : INT := 3`｜`bEnable`/`bReset`。
- **VAR_OUTPUT**：`fInsPosKOhm`/`fInsNegKOhm`/`fInsTotalKOhm`（[kΩ]）｜`bWarn`/`bAlarm`（确认后锁存至 `bReset`）｜`bUnbalanced`（正负极失衡）｜`bUndecidable`｜`eErr`/`bError`/`bValid`｜`eState : E_DL_StringInsState`。
- **边界安全**：① **量纲推导必须在头注释写明**（R108 量纲组合表）：`Vp/Rp = Vn/Rn`（正负对地分压比）+ `Rp ∥ Rn` 与桥阻构成回路；`fInsTotal = fBridgeKOhm × (fBusV / (Vp + Vn) − 1)`，`Rp = fInsTotal × (Vp + Vn)/Vn`、`Rn = fInsTotal × (Vp + Vn)/Vp`；**编码侧必须先做量纲复核再落码**；② `Vp + Vn ≈ 0`（`|Vp+Vn| < 1.0 V`）或 `fBusV ≤ 0` → 信息 `0410` + `bUndecidable := TRUE` + `bValid := FALSE`（**推算不可判时禁止输出伪阻值**，R42 家族）；③ `fBridgeKOhm ≤ 0` 或阈值倒置（`fAlarmKOhm ≥ fWarnKOhm`）→ 故障 `035A`；④ 非有限 → 故障 `035B`；⑤ 分级：`< fAlarmKOhm` → `bAlarm`；`< fWarnKOhm` → `bWarn`；报警需 `nConfirmSamples` 次确认（防单点误报停机）；⑥ 失衡判据：`max(Rp,Rn) / min(Rp,Rn) > 3.0`（`VAR CONSTANT`）→ `bUnbalanced`；⑦ 失能 → 不判、`bValid := FALSE`（**绝不清除已锁存告警**）。
- **验收向量建议**：① `Bus 600 V, Vp=300, Vn=300, Rb=100 kΩ` → `InsTotal` 巨大（按公式 `100×(600/600−1)=0` → 需在头注释写明「完全平衡时公式退化为 0/→∞，实现取 `Vp+Vn` 与 `fBusV` 之差的下限保护」）——**此退化分支是本件最高风险点，编码侧必须给出显式分支与验收向量④**；② `Vp=400, Vn=200` → `Rp > Rn` 且 `bUnbalanced`；③ 阈值 `Alarm 100 / Warn 1000`，实测 80 → `bAlarm`；④ `Vp+Vn = 0.5 V` → `0410` + `bUndecidable`。

---

> **⚠️ 勘误注记（R25-RESUME 终审核定，2026-11-17 ｜ 追加式，不回改原文）**
> 边界安全①给的乘式 `fInsTotal = fBridgeKOhm × (fBusV / (Vp + Vn) − 1)` **分子分母倒置**：完全平衡（绝缘趋无穷，`Vp+Vn → Vbus`）时该式得 **0 kΩ**，等于把绝缘良好判成对地短路并误告警；单极短路时反而得无穷。两式在代数上互为自洽（均满足 `Rp/Rn = Vp/Vn` 与 `1/(1/Rp+1/Rn) = R_t`），**只有两端极限能判别**。
> 裁定：**编码者改为除式 `fInsTotal = fBridgeKOhm × (Vp + Vn) / (fBusV − Vp − Vn)` 正确**，总监独立复算：`D = Vbus − (Vp+Vn) → 0 ⇒ R_t → ∞`（绝缘良好）、`Vp+Vn → 0 ⇒ R_t → 0`（对地短路），两端极限均与物理方向一致；`Rp = R_t×(Vp+Vn)/Vn`、`Rn = R_t×(Vp+Vn)/Vp` 两式随之成立。
> 退化分支哨兵 **`1.0E9 kΩ` 判定合理**：①高于真实测量可达上限（1e5~1e6 kΩ）3 个数量级，不会与实测混淆；②高于预警阈值 `1000 kΩ` 6~7 个数量级，不会被判告警；③两极同取哨兵使失衡比恒为 1，不误报 `bUnbalanced`；④低于 LREAL 幅值上限，求和与比值不溢出。附带收口：原式下方「需在头注释写明退化……」的编辑性问句由 v1.0.1 组态闸承接（`fWarnKOhm ≥ 哨兵 → 035A`，防阈值配到哨兵之上把「绝缘良好」判成报警）。
> 规则落地：R123（公式类派单必须附量纲链 + 两端极限推演）、R131（实现侧两端极限自检）。

## 5. 派单样板（R50/R59 教训：样板内嵌，逐字照抄替换 `<...>`）

### 5.1 头注释样板

```iecst
//==============================================================================
// <函数/功能块>：<POU 名> ｜ 中文名称：<中文名>
// 所属子库：<DL_Algo/DL_Device/...> ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：<3~8 行：做什么、判据/公式来源、关键设计取舍与不做的事>
// 开源溯源 (Origin)：<§5.3 溯源短语原文二选一，逐字照抄>
// 单位表：<每物理量一行：名[单位] 语义，禁止无单位裸数值>
// 错误码表：<逐行列出本件码位与级别，与 §3 分配表一致；严禁出现 %I / %Q / %M 记号原文>
// 状态机：<ENUM 名 + 成员 + 「CASE 含 ELSE 兜底」声明；纯函数件用 R60 固定文本>
// 边界行为：<①~⑦ 逐条：域外早退 / 限幅 / 跨相时序 / 恢复首拍 / 失能清零 / 安全侧>
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · <来源标签>）
//==============================================================================
```

- 全中文注释；**严禁嵌套 `(* *)`**；严禁「同上」；严禁 `...` 省略号占位（R92/R112）。
- 声明区每行同行双语：`    fApproachK : LREAL;   // 逼近度 [K] / Approach [K]`——格式固定 `// 中文 / English`，物理量必带单位。

### 5.2 错误码声明样板（5 槽码位块）

```iecst
VAR CONSTANT
    DL_<NAME>_CODE_INFO_1 : UDINT := 16#0005_0400;   // 信息级槽 1（语义见错误码表） / info slot 1
    DL_<NAME>_CODE_INFO_2 : UDINT := 16#0005_0401;   // 信息级槽 2 / info slot 2
    DL_<NAME>_CODE_RSV_1  : UDINT := 16#0005_0405;   // 预留禁用（不得挪用） / reserved, do not use
    DL_<NAME>_CODE_FLT_1  : UDINT := 16#0005_0342;   // 故障级槽 1 / fault slot 1
    DL_<NAME>_CODE_FLT_2  : UDINT := 16#0005_0343;   // 故障级槽 2 / fault slot 2
    DL_<NAME>_CODE_FLT_3  : UDINT := 16#0005_0344;   // 故障级槽 3：非法状态兜底 / illegal-state fallback
END_VAR

VAR_OUTPUT
    eErr   : UDINT;   // 错误码，0 = 无错，码位 16#<段>_<起始> 起（信息/故障分带见错误码表） / error code, 0 = none
    bError : BOOL;    // 故障级标志，仅故障级错误置位 / fault-class flag
    bValid : BOOL;    // 输出可用标志，失能闸与故障闸上显式 FALSE / outputs usable flag
END_VAR
```

- 铁律：**信息级不置 `bError`；故障级必置**（R45/R101：`bError := TRUE` 与故障码赋值必须原子成对出现，机检按对匹配）。

### 5.3 溯源短语（二选一，逐字照抄，R93 收敛句式）

- **T1/T2 借鉴件**（序号 1/9/10）：
  `开源溯源 (Origin)：道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）`
  （序号 9/10 写 `仅借 OSCAT ROOM_CONTROL 行为定义/参数域`；序号 1 写 `仅借 LGF 分类事实/参数域/行为定义`）
- **ROADMAP 行业池／自研件**（其余 17 件）：
  `开源溯源 (Origin)：道莅原创实现（参考 <公开工程惯例｜公开规范条款名> 分类与参数域）`
  - 序号 2 括注 `ISO 14644-1:2015 Table 1 公开分级口径`
  - 序号 4 括注 `并网同步条件公开工程惯例（电压/频率/相角/相序四窗）`
  - 序号 20 括注 `不平衡电桥法公开测量原理`
  - 其余按 ROADMAP 原文语义填 `公开工程惯例`
- 来源 URL / 许可证如涉具体仓库，**只记入 `RAW_NOTES_R25.md`**，不进 `.st` 头注释（避免"声称来源"与实际不符）。

### 5.4 编码红线（逐件自检 7 项）

1. 零全局变量、零硬件寻址（`%I/%Q/%M` 连注释都不许出现）；外部数据一律引脚或接口注入。
2. 纯 IEC 61131-3 + `Standard.library`；零厂商专有库；禁 `POINTER TO` / `REFERENCE TO`；显式转换。
3. 防除零（除子前容差判零）、数组边界检查、浮点禁 `=` 判等（`ABS(a−b) < 1E-6` 族）、`WHILE` 防死锁计数器。
4. `ENUM` + `CASE` 含 `ELSE` 兜底（ELSE 置故障码并落安全侧）；纯函数件按 R60 固定文本豁免。
5. `TON`/`TOF`/`R_TRIG` 在待机、故障、各分支**无条件周期刷新**；单拍标志自清；`CASE` 前置无条件状态改写禁用（吞复位沿，R39）。
6. 许可类输出在失能闸/故障闸 RETURN 路径显式 `FALSE`（R72）；**故障路径输出必须是安全值而非上次值**。
7. POU 终结符成对（`END_FUNCTION` / `END_FUNCTION_BLOCK`）；POU 名 = 文件名；码位用满 §3 分配表，**不得越段、不得挪用预留槽**。

### 5.5 组合调用纪律（本轮 8 件涉及）

- 允许**调用低层已注册件**（`FC_DL_WetBulbTempCalc` / `FC_DL_DewPointCalc` / `FC_DL_Affine2DInvert` / `FC_DL_Affine2DApply` / `FB_DL_PidController` / `FB_DL_DutyStandbyRotation`），**禁止复制低层实现**。
- 下游锁存型 `bError` 必须**透传复位且只在故障相处置**（R115）；调用引用的引脚契约以对应 `MANUAL_DL_*.md` 为准，**不得凭记忆猜引脚**。
- 下游件返回信息级码时，本件不得升格为故障（信息安全侧不得放大）。

---

## 6. 批次依赖与实施顺序

| 批次 | 组件 | 依赖（均为已注册件或本批前置件） |
|---|---|---|
| **1** | 1 `Affine2DInvert` / 2 `ParticleCounterStat` / 3 `CoolingTowerApproachCalc` / 4 `InverterGridSync` / 5 `HeatPumpDefrost` | 无外部前置；3 依赖 `FC_DL_WetBulbTempCalc` v1.1.0；1 与 R24 `Affine2DCompose/Apply` 同族但互不依赖 |
| **2** | 6 `VavBoxCtrl` / 7 `WaferMapping` / 8 `DuctStaticReset` / 9 `DewpointReset` / 10 `RoomClimateCtrl` | 6 组合调用 `FB_DL_PidController`；9 调用 `FC_DL_DewPointCalc`；10 组合调用 `FB_DL_PidController` ×2 且复用 9 的露点口径（不重复实现） |
| **3** | 11 `StackingAlignCtrl` / 12 `WeightCheckReject` / 13 `LabelApplySync` / 14 `CasePackerPattern` / 15 `BatteryTestCycler` | 11 依赖批次 1 的 `FC_DL_Affine2DInvert`（**跨批唯一硬依赖**） |
| **4** | 16 `PalletizerLayerSeq` / 17 `SplicerAutoJoint` / 18 `ChillerSeqMgr` / 19 `FormationChannelMgr` / 20 `SolarStringGroundFault` | 16 依赖 `FC_DL_Affine2DApply`（R24）+ 批次 3 的序列语义；18 组合调用 `FB_DL_DutyStandbyRotation`；19 与 15 为「调度 / 工步」分层（15 先落） |

- 批次内按序号编写；序号 11 必须先于 16（逆映射件在批次 1 已完成，16 只做正向应用）。
- 依赖方向核验：`DL_MathData`(1) → `DL_Algo`(2,3,8,9) / `DL_Device`(4,5,6,7) → `DL_Motion`(11,13) → `DL_Process`(10,12,14,15,16,17,18,19,20)（10 在批次 2 但依赖 `DL_Algo` 的 9，属**低层依赖**，合法；**反向依赖 = 红线**）。

---

## 7. 交付与登记要求（收口方）

- 每件入库同步：`INDEX_REGISTRY.json` 增量 + JSONL 语料一条（含 `architecture_thought` 码位复核，R87 五步）+ 子库 `VERSION.md`/`MANUAL_DL_*.md` + 顶层 `CHANGELOG.md`/`README.md`/`LIBRARY_MANUAL.md`（R74 增量四动作，禁整篇重写）。
- **本轮不碰 `INDEX_REGISTRY.json`**（规划阶段只读）；不改任何 `.st`（编码阶段职责）。
- 收口游标：以源码反算实测回写 `SOURCE_HUNTING_MATRIX.md` §4/§5 与本文件 §0 修正注记（R105/R111）。
- 矩阵回写：T1-2 行备注追加「R25 ROOM_CONTROL 子族开族 2 件（DewpointReset / RoomClimateCtrl）」；T2-1 LGF Math 行备注追加「R25 仿射族逆映射补口 1 件（Affine2DInvert）→ 仿射三元闭环齐备」。
- ROADMAP：本轮 18 件来源条目已标注「**R25 认领**」（见 §8），收口时勾选为 `[x]` 并写落地版本号。

---

## 8. ROADMAP 认领标记对照（供收口勾选）

| ROADMAP 位置 | 条目 | 本轮序号 |
|---|---|---|
| §7.1 line 209 | `FB_DL_FormationChannelMgr` | 19 |
| §7.1 line 210 | `FB_DL_StackingAlignCtrl` | 11 |
| §7.1 line 215 | `FB_DL_BatteryTestCycler` | 15 |
| §7.2 line 233 | `FB_DL_InverterGridSync` | 4 |
| §7.3 line 251 | `FB_DL_WaferMapping` | 7 |
| §7.3 line 253 | `FB_DL_ParticleCounterStat` | 2 |
| §7.4 line 271 | `FB_DL_LabelApplySync` | 13 |
| §7.4 line 272 | `FB_DL_WeightCheckReject` | 12 |
| §7.4 line 273 | `FB_DL_CasePackerPattern` | 14 |
| §7.4 line 280 | `FB_DL_SplicerAutoJoint` | 17 |
| §7.5 line 288 | `FB_DL_ChillerSeqMgr` | 18 |
| §7.5 line 289 | `FB_DL_VavBoxCtrl` | 6 |
| §7.5 line 290 | `FB_DL_HeatPumpDefrost` | 5 |
| §7.5 line 291 | `FB_DL_DuctStaticReset` | 8 |
| §7.5 line 293 | `FB_DL_DewpointReset` | 9 |
| R24 增补 line 1020 | `FB_DL_CoolingTowerApproachCalc` | 3 |
| R24 增补 line 1022 | `FB_DL_PalletizerLayerSeq` | 16 |
| R24 增补 line 1023 | `FB_DL_SolarStringGroundFault` | 20 |

> 序号 1（`Affine2DInvert`）与序号 10（`RoomClimateCtrl`）不在 ROADMAP 待办池——前者是源矩阵 T2-1 仿射子族补口，后者是 T1-2 `ROOM_CONTROL` 开族件，按「源矩阵待挖掘组」入口立项，**不入 ROADMAP 待办**（避免池内重复登记，R85 不虚账）。

---

## 9. 风险清单（编码侧必须正面回答的 5 个高风险点）

| 风险 | 涉及件 | 要求 |
|---|---|---|
| **量纲/公式推导** | 20 `SolarStringGroundFault`（电桥法）、3 `CoolingTowerApproachCalc`、17 `SplicerAutoJoint`（卷径平方比） | 头注释必须写量纲链；20 的「完全平衡退化」分支必须有显式写法与验收向量（R108） |
| **默认参数自违反** | 6 `VavBoxCtrl`、9 `DewpointReset`、14 `CasePackerPattern`、18 `ChillerSeqMgr` | 出厂默认组合必须过自身组态闸，不得一上电就报故障（R114） |
| **跨件交互死锁** | 15 `BatteryTestCycler` × 19 `FormationChannelMgr`、10 `RoomClimateCtrl` 双 PID | 下游锁存型 `bError` 复位链必须跑通（R115/R116）；中止路径不得让上层永等 |
| **安全侧方向** | 5 `HeatPumpDefrost`（超时回制热）、12 `WeightCheckReject`（漏剔停线）、17 `SplicerAutoJoint`（未同步不裁切）、6 `VavBoxCtrl`（失能回最小开度） | 安全侧方向必须写进头注释「边界行为」段，且故障拍输出为安全值而非上次值 |
| **数值域** | 2 `ParticleCounterStat`（浓度量级 1E7）、13 `LabelApplySync`（32 位脉冲回绕）、16 `PalletizerLayerSeq`（层高累计） | `LREAL` 承载、回绕差分写法、除零前置；禁止用 `REAL` 存 1E7 以上浓度 |

---

*R25 派单计划 ｜ 2026-11-17 08:29 ｜ 道莅工控代码库产品总监（阶段一盘点 + 阶段二锁定，20 件 / 4 批，零检索 1 次核对）*
