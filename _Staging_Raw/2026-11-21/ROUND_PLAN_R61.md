# ROUND_PLAN R61（2026-11-21 · 零检索族内深化轮）

> 规划依据：INDEX_REGISTRY v2.52.0（1085 件）｜ SOURCE_HUNTING_MATRIX 台账 ｜ ROADMAP 未勾 33 条 ｜ REVIEW_R60 挂账 D1~D13。
> 硬约束执行：WebSearch 0/0（R59 概念饱和判定延续）｜ 新件 16（R60 抽检挂账 ≥3 → R249/R193 下调 20→16）｜ 撞名三查全跑（registry 精确 + 同义词根 4 轮 + DL_* 文件树；Reject 拒单 24 件留痕见第五节）。

## 一、盘点

| 项 | 实测值 | 口径 |
|---|---|---|
| 总库进度 | **1085 / 10,000（10.9%）** → 本轮后 1101 | INDEX_REGISTRY v2.52.0 直读 |
| 500 冲刺 | **1101 / 500，超额 +601** | 已封账，只跟踪 10,000 主线 |
| 今日产量 | **88 / 200 → 本轮后预计 104** | 主控口径，本轮今日第 5 轮 |
| 源矩阵覆盖 | **✔8 / ◐26 / ☐11** | 全部新件回指既有 ◐ 行 + self，零新开组；R60 记账差 2 条仍挂收口 |
| ROADMAP 待办 | 33 条未勾 | 本轮不新增本体行；返修段全部来自 REVIEW_R60 挂账 |
| 族避让（R267） | Algo 1 / Process 1（均压上限线） | 拒单重灾区主动避让，重心 Base 4 + MathData 5 + Device 3 + Motion 2 |

## 二、目标清单（16 件，H×3）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_ReverseBitsLword | DL_Base | FC | LWORD 64 位序整体反转（ReverseBitsWord 的 64 位域升版变体，R277 变体类） | t2-1-lgf-bitlogic | L | 1 |
| 2 | FC_DL_BitScanLword | DL_Base | FC | LWORD 最低/最高置位索引扫描（uIdx+bFound，零命中码三件套） | self-std | L | 1 |
| 3 | FC_DL_Hypot3D | DL_MathData | FC | 三维矢量模长 √(x²+y²+z²)（中途缩放防溢出，非有限入闸） | self-std | L | 1 |
| 4 | FC_DL_TrapezoidArea | DL_MathData | FC | 离散序列梯形法累计面积（采样周期入参，与 FB_DL_Integrator 分工：纯函数 vs 连续积分器） | self-std | L | 1 |
| 5 | FC_DL_SortIndexLReal | DL_MathData | FC | 稳定排序仅输出索引排列（不改调用方数组，PercentileLReal 只读纪律） | self-std | M | 2 |
| 6 | FC_DL_WeightedPercentile | DL_MathData | FC | 加权百分位数插值（PercentileLReal 升版邻位：权向量 wᵢ ≥ 0 归一闸） | t2-1-lgf-math | M | 2 |
| 7 | FC_DL_MeanAbsDevCalc | DL_MathData | FC | 均值绝对偏差 MAD-mean（MedianAbsDev 邻位变体：均值域 vs 中位数域） | self-std | L | 2 |
| 8 | FB_DL_LongPressButton | DL_Base | FB | 单按钮短按/长按/超长按三档时序分档（TON 三窗，与 ToggleButtonBank 分工：时序分档 vs 模式解算） | self-std | M | 2 |
| 9 | FB_DL_RailPowerSequence | DL_Base | FB | 多路供电轨按序上电/断电（延时可配、断电逆序、步进超时锁存；与 LaserWeldPowerSeq 分工：通用时序原子 vs 工艺专用） | self-std | M | 3 |
| 10 | FB_DL_AxisLimitSwitchBank | DL_Motion | FB | 硬限位开关组分侧判 + 越限锁存 + 越限计数（与 SoftLimitGuard 分工：硬件开关组 vs 软件限幅预测） | t1-6-plcopen | M | 3 |
| 11 | FB_DL_PidParamGuard | DL_Algo | FB | PID 参数组在线运行期守卫（Kp/Ti/Td 有限性+域闸+退化降级；与 PidParamDriftAudit 分工：在线闸 vs 离线漂移审计） | self-std | M | 3 |
| 12 | FB_DL_PhaseLossGuard | DL_Device | FB | 三相缺相/逆相序检测（幅差判据 + 逆相序独立码；与 PhaseNeutralImbalance 分工：缺相保护 vs 相零不平衡统计） | self-std | M | 3 |
| 13 | FB_DL_SensorPairPlausibility | DL_Device | FB | 双冗余传感器交叉合理性（偏差窗 + 漂移趋势 + 择优输出 + 故障锁定状态机） | t2-6-rockwell-aoi | H | 4 |
| 14 | FB_DL_AirDryerDiag | DL_Device | FB | 压缩空气干燥机诊断（露点越限 + 再生阀时序状态机 + 切换周期劣化档） | t2-2-lbp | M | 4 |
| 15 | FB_DL_TurretToolSelect | DL_Motion | FB | 刀塔就近方向换刀选择（刀位环计数 + 最短路径 + 当前刀位校验状态机） | t1-6-plcopen | H | 4 |
| 16 | FB_DL_LineClearanceVerify | DL_Process | FB | 换型清线验证（清料确认 + 残留计数 + 阶段确认窗状态机 + 超窗升级码） | self-std | H | 4 |

> 分类核账：Base 4 / MathData 5 / Device 3 / Motion 2 / Algo 1 / Process 1 = 16 ✔；Algo ≤1、Process ≤1（R267）✔；H = 3（#13/#15/#16）✔；H 集中批 4 按依赖排序。

## 三、每件边界安全条件（一句话）

1. ReverseBitsLword：uSrc=0 → uRev=0 + bValid=TRUE 恒成立；LWORD↔双 DWORD 拆半区零移位纪律。
2. BitScanLword：全零输入 bFound=FALSE 且 uIdx=0（不泄 -1）；扫描禁移位循环超 64 拍（WHILE 计数器防死锁）。
3. Hypot3D：先 |x| 缩放防 x² 溢出；三入参全枚举进非有限闸（R272 逐个点名）。
4. TrapezoidArea：nCount<2 置码不积；采样周期 tDt≤0 独立码；NaN 点跳过段计 not-a-number 计数上报。
5. SortIndexLReal：nCount=0/1 退化直返恒等索引；相等元素稳定性判据写头注释（下标序）。
6. WeightedPercentile：Σw=0 或权负 → 独立码；分位 p 钳位 [0,1] 整数进位点自证（p=0/p=1 两向量）。
7. MeanAbsDevCalc：nCount=0 置码；均值非有限传播闸；与 MedianAbsDev 互引分工（R216）。
8. LongPressButton：三档窗重叠组态错（tShort≤tLong≤tXLong 组态闸 R239）；R_TRIG 段 0 无条件刷新；单拍输出统一出口预置 FALSE（R256）。
9. RailPowerSequence：断电逆序强制；步进超时锁存独立码 + 解除式可达自证（R28 终审式 1）；uRailCount=0 组态错。
10. AxisLimitSwitchBank：限位触发即锁存且方向侧独立；复位引脚解除式自证；开关极性组态（常闭安全侧默认）。
11. PidParamGuard：参数越界降级为上次合法值快照（不静默清零）；非有限 → 故障锁存 + 复位可达（R187）。
12. PhaseLossGuard：幅差判据阈值常量提级带单位 [%]；逆相序独立码；仅全相有压时才判序（防欠压误报）。
13. SensorPairPlausibility：择优切换须迟滞（防抖动拍拍翻转）；偏差窗漂移趋势滚动窗长度提为输入；故障锁存解除式逐条自证。
14. AirDryerDiag：再生切换周期劣化分档阈值全提为输入；露点非有限闸；状态机 CASE 必带 ELSE 兜底码（R25 批次缺陷教训）。
15. TurretToolSelect：就近方向判据环上整数进位点自证（恰对径 n/2 两向量）；刀位号域闸 [1,n] 钳位；换刀指令单拍脉冲。
16. LineClearanceVerify：残留计数清零判据用整数精确比较；阶段确认窗先消化确认沿再判超窗（R275 同拍竞态模板）；快照出口纳入复位清单（R243）。

## 四、R60 挂账返修清单（交 PLC 编码专家，同批顺手，共 6 项 + 轻项）

| 优先级 | 件 | 文件与行号（REVIEW_R60 实测） | 修法 |
|---|---|---|---|
| P0 D1 | FB_DL_AxisCmdArbiter（DL_Motion） | 段 4 L146-151 + 段 6 L160 | 非有限降级同步置 `_eWinner := eNone`，双通道一致 |
| P0 D2 | FB_DL_AxisCmdArbiter（DL_Motion） | 声明 L80 vs 段 6 L164-166 | 增 `_bFault` 锁存位 + 复位引脚，bError 口径改「故障锁存」 |
| P1 D4+D6 | FC_DL_InterpolateTable3D（DL_MathData）/ FC_DL_Affine2DChain（DL_MathData） | Table3D 段 2 L120-121、L140-141；Affine 段 2 L101-106、段 5 L190-193 | 删信息级码置 bError 共 4 处（口径统一，R285） |
| P1 D5 | FC_DL_Affine2DChain（DL_MathData） | 段 4 L133-141 | nUsed=1 以单位阵为左乘调一次委托，补单级奇异判 |
| P2 D3 | FC_DL_InterpolateTable3D（DL_MathData） | 段 3 L145-159 | 三轴向量逐元素非有限点名 → 独立码（R272 全量必命中） |
| P2 D7 | FB_DL_ShiftHandoverCheck（DL_Process） | 段 2 L124-130 vs 注释 L84 | 增 `_nPendingLock`，仅 eIdle 迁入沿赋值 |
| 轻项 D8~D13 | InterpolateTable3D / ShiftHandover / AxisCmdArbiter / InputShaperZv | Table3D 段 6 L232-253、段 8 L276；ShiftHandover L66-67、L73-74；AxisCmdArbiter 头注释 L21-33；InputShaperZv 段 0 L101 vs 段 3 L134；D13 两件头注释补 Ownership 行 | 同批顺手，含 TwoStepConfirm 段 4 判据补 `AND _bArmed` 双保险 |

## 五、撞名三查留痕（R214 前置化）

**候选 40 / 收录 16 / 拒单 24**（词根 4 轮批扫 + 精确名 + 文件树；富余度 2.5:1 达标）。拒单要点：

| # | 拒单 | 命中理由 | # | 拒单 | 命中理由 |
|---|---|---|---|---|---|
| 1 | AxisBacklashComp | BacklashCompensator/StepComp/Ident 三件在册，族饱和 | 13 | UdintToBcdEx | Bcd 族 6 件在册 |
| 2 | FlyingShearMarkSync | FlyingCutSync 精确近邻 | 14 | QuantizeStepEx | QuantizeStep 同义 |
| 3 | AxisJogSequencer | AxisJogController 同义 | 15 | HexStringParseLword | HexStringToLword 精确命中 |
| 4 | AxisHomingOffsetStore | AxisHomingSeq/PassiveHomingMonitor | 16 | SoftLimitBank | SoftLimitGuard/CfgAudit 双件 |
| 5 | EStopChainDiag | EStopDualChannel/EStopMonitor 双件 | 17 | ValveExerciser | ValvePartialStrokeTest 同概念 |
| 6 | EndianSwapLword | SwapBytes64 覆盖 | 18 | PumpDryRunWatch | PumpDryRunGuard/Protect 双件 |
| 7 | BitMaskGenerate | MaskCompare 近邻差异化不足 | 19 | GreaseLubeSeq | GreaseLubeTimer 近邻 |
| 8 | AngleWrapRad | WrapAngleDeg 精确同义 | 20 | SensorDriftTrend | SensorDriftBaseline 近邻 |
| 9 | GainSchedulerTab | GainScheduler/GainSchedPid/PidGainScheduler 三件 | 21 | SetpointRampGen | RampGenerator |
| 10 | HydraulicPowerUnitDiag | HydraulicPowerUnit 精确命中 | 22 | StdDevCalc | StdDevOnline |
| 11 | WatchdogHeartbeat | HeartbeatGen/WatchdogMonitor/PulseMon 三件 | 23 | CartesianToPolar2D | PolarTransform2D/PolarDecomp2D |
| 12 | GrayCodeLword | BinaryToGray/GrayToBinary 双向 | 24 | EdgeSeqGuard | EdgeOrderCheck 精确近邻（第 4 轮救回） |

另核验：ToggleButtonBank 无长按时序分档（#8 成立）；PumpDryRun 双胞胎（Guard/Protect）已提示收口侧同义件去重挂账。

## 六、批次切分与派单要点

- **批次 1（L0 位域/标量纯函数，L×4）**：#1~#4。共性：64 位操作零移位拆半区纪律、FC 局部计数/标志段 1 显式预置（R254）、回钳量禁再判越界（R241）、码位沿 DL_Base 既有段连续号段（R192）。
- **批次 2（L0 统计深化 + 时序分档原子，L~M×4）**：#5~#8。共性：只读入参数组纪律（PercentileLReal）、MedianAbsDev/PercentileLReal/ToggleButtonBank 三向分工互引（R216）、三档时间窗组态闸重叠判（R239/R253）。
- **批次 3（L1 设备守卫/参数闸，M×4）**：#9~#12。共性：故障锁存 + 解除式可达逐件自证（R28 两式）、降级路径双通道一致（D1 教训前置）、阈值/方向常量提级带单位（R 红线 7）、NE107/枚举只引用既有属主（R264）。
- **批次 4（H 状态机四件，M~H×4）**：#13~#16。共性：CASE 必带 ELSE 安全兜底、TON/R_TRIG 段 0 无条件刷新、同拍竞态「先消化输入沿再判超时」（R275 模板）、快照/最近值出口纳入复位清单（R243）、R272 浮点入参闸逐个点名。
- 批次依赖：批 1/2 纯 L0 无依赖可并行；批 3 仅依赖 L0 既有件；批 4 状态机件沿用批 3 已立参数闸范式，编码侧可交叉复用组态闸模板。
