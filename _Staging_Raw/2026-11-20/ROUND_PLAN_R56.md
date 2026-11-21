# R56 构建轮 · 目标锁定与选题台账（2026-11-20 23:18 启动）

规划角色：道莅代码库产品总监｜本轮只做规划与留痕，零 .st 代码产出（规划环节 ≤8 分钟纪律）。

## 一、统计段

| 指标 | 数值 |
|---|---|
| 总库组件数 | 997 / 10,000（v2.47.0，INDEX_REGISTRY 2026-11-20T21:05） |
| 距 1,000 里程碑 | 差 3（本轮 20 件若全落地 → 1,017，跨过 1,000） |
| 子库 counts（registry 与文件树实盘双核一致） | Base 111 / MathData 218 / Algo 118 / Device 181 / Motion 109 / Process 260 |
| ROADMAP 未勾待办 | 14 条（低于 30 条阈值 → 本轮追加 ≤10 条新待办，见 `## R56 增补`） |
| 源矩阵 | ☐ 待挖组 = 0；T0 八组 8/8 ✔ 余量 0 → 本轮 T0 = 0 件，禁硬凑（R228） |
| 本轮构成 | 全部为 ROADMAP 未注册真缺口（14 条存量待办均为治理/手册/编译债类，无组件类可勾）+ T2/T1 既有 ◐ 组深化 |
| 检索预算 | 零 WebSearch（复用 RAW_NOTES R39~R55 与矩阵源行，同源不重复检索） |
| 今日（11-20）已入库 | 132 / 200（本轮 20 件落地后 → 152 / 200） |

## 二、三查执行记录（R214 撞名三查：registry 全名表 + ROADMAP 全文 + 六库文件树 glob）

- 候选 20 件 × 三查，机械脚本逐件留痕（`grep -cx` registry 全名 997 行 / `grep -c` ROADMAP 全文 / `ls DL_*/*.st` 文件树实盘 111+218+118+181+109+260=997）：
- **结果：20/20 三处零命中**（registry=0 / roadmap=0 / file=0，实测记录 2026-11-20 23:2x）。无同名撞车、无脏项、无变体语义命中，零换名。
- 文件树实盘与 registry counts 完全一致（997 = 997），本轮无三向差额挂账。

## 三、选题台账（20 件 = 4 批 × 5 件，批次即依赖顺序）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次(1-4) |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_HermiteInterp | DL_MathData | FC_DL_ | 三次 Hermite 插值（端点值+端点导数四条件定曲线，非等距单区间） | t2-1-lgf-math | 3 | 1 |
| 2 | FC_DL_QuatSlerp | DL_MathData | FC_DL_ | 单位四元数球面插值 SLERP（最短路径+角度超域钳制） | t2-1-lgf-math | 3 | 1 |
| 3 | FC_DL_RoundSigFigs | DL_MathData | FC_DL_ | 按有效数字位数舍入（相对量级 10^n 幂定位+舍入误差半位闸） | t2-1-lgf-math | 3 | 1 |
| 4 | FC_DL_RtdLinearization | DL_MathData | FC_DL_ | RTD 阻值→温度 CVD 多项式线性化（Pt100/Pt1000，IEC 60751 公开系数） | t2-1-lgf-converter | 4 | 1 |
| 5 | FB_DL_EStopDualChannel | DL_Base | FB_DL_ | 急停双回路监视（双路不一致/单路失效/复位链自检三判据+锁存） | 自研线（IEC 60204-1 公开条款） | 4 | 1 |
| 6 | FC_DL_Kalman2DSmoother | DL_MathData | FC_DL_ | 2D 常速模型标量序贯卡尔曼（位置/速度双状态+单次测量更新纯函数形态） | t2-1-lgf-measurement | 5 | 2 |
| 7 | FB_DL_SignalSeqGuard | DL_Base | FB_DL_ | 多信号顺序到位校验（序号数组配置+乱序/超时双诊断出口） | 自研线（次借 t2-2-lbp 三段分层） | 3 | 2 |
| 8 | FB_DL_TwoDofPid | DL_Algo | FB_DL_ | 二自由度 PID（设定值加权 β/γ 双自由度，抑超调与抗扰分调） | t2-5-modpid | 4 | 2 |
| 9 | FB_DL_AxisAccelFeedforward | DL_Motion | FB_DL_ | 轴加速度前馈注入（规划加速度×折算惯量比→转矩前馈偏置） | t1-6-plcopen | 3 | 2 |
| 10 | FB_DL_HydraulicAccumPreChg | DL_Device | FB_DL_ | 蓄能器氮气预充压力校验（气体定律温度补偿+预充欠/过压双态） | t2-2-lbp | 3 | 2 |
| 11 | FB_DL_VacIonizerBalance | DL_Device | FB_DL_ | 离子风机平衡监视（平衡电压偏移+衰减时间双判据分级诊断） | 半导体 ESC 自研线 | 3 | 3 |
| 12 | FB_DL_FanVfdBypassSwap | DL_Device | FB_DL_ | 风机变频→工频旁路切换时序（停机互锁+接触器间隔窗+切换诊断） | t2-2-lbp | 4 | 3 |
| 13 | FB_DL_AxisCantileverComp | DL_Motion | FB_DL_ | 悬臂轴挠曲位置补偿（负载×伸长量→变形量前馈修正，材料力学公开式） | t2-4-s7-motion 次源 | 4 | 3 |
| 14 | FB_DL_HotRunnerZoneBalance | DL_Process | FB_DL_ | 热流道多区温度均衡分级（区间偏差分级+孤立区诊断） | t2-2-lbp | 3 | 3 |
| 15 | FB_DL_SlurrySieveClogWatch | DL_Process | FB_DL_ | 料浆筛网堵塞判据（进出口压差比+筛下流量衰减双判据+确认窗） | t2-6-rockwell-aoi | 4 | 3 |
| 16 | FB_DL_LossInWeightFeeder | DL_Algo | FB_DL_ | 失重秤连续给料控制（罐重变化率→喂料速度闭环+重灌装切换相） | t2-2-lbp | 5 | 4 |
| 17 | FB_DL_UvDoseCtrl | DL_Algo | FB_DL_ | UV 剂量累计控制（强度×时间积分+灯老化补偿+剂量达标判定） | 自研线（公开物理定义） | 5 | 4 |
| 18 | FB_DL_UltrasonicWeldCtrl | DL_Device | FB_DL_ | 超声焊接控制（能量/振幅/时间三模终点+过载保护+焊接窗口审计） | t2-2-lbp | 5 | 4 |
| 19 | FB_DL_AxisProbeMeasCycle | DL_Motion | FB_DL_ | 探针测量循环（趋近-触发锁存-回退-尺寸计算-N 点评价全序列） | t1-6-plcopen | 5 | 4 |
| 20 | FB_DL_AirShowerInterlockSeq | DL_Process | FB_DL_ | 风淋室联锁序列（外门-吹淋定时-内门三段联锁+吹淋不完整禁行） | t2-2-lbp | 4 | 4 |

批次依赖说明：
- **批 1**：Level 0 纯函数 4 件（MathData）+ Base 双回路监视 1 件，零内部依赖，全部只引用既有件，先行落库。
- **批 2**：MathData 统计件 + Base 序列校验 + Algo/Motion/Device 各 1 件，只依赖 Level 0 既有件，零互依。
- **批 3**：Device 诊断/切换 2 + Motion 补偿 1 + Process 分级/判据 2，依赖批 1~2 既有件（Kalman/RtdLinear 等对照口径），零互依。
- **批 4**：重组合件（失重闭环 / 剂量积分 / 超声三模 / 探针全序列 / 风淋序列），依赖面最宽（DosingControl 对照 / 接口 / 门联锁既有件），压轴。

## 四、分类与配额自评

- 分类分布：Base 2 / MathData 5 / Algo 3 / Device 4 / Motion 3 / Process 3 —— **六库全覆盖且均 ≥1**；单库峰值 MathData 5、Process 3（≤3 建议达标），全部 ≤6。
- 复杂度分布：cx3 = 8（#1/2/3/7/9/10/11/14）｜cx4 = 7（#4/5/8/12/13/15/20）｜cx5 = 5（#6/16/17/18/19）——cx3~cx4 各 ≤8 ✓，cx5~cx6 合计 5 ≤6 ✓，cx3+cx4 = 15 为主 ✓。
- T2/T1 深化配额：**T2 族深化 = t2-1-lgf-math（4 件）+ t2-1-lgf-converter（1 件）+ t2-1-lgf-measurement（1 件）+ t2-5-modpid（1 件）+ t2-2-lbp（6 件）+ t2-6-rockwell-aoi（1 件）**；**T1 组深化 = t1-6-plcopen（2 件）**——满足「本轮须至少 1 个 T2 族或 T1 组深化」，无 ☐→◐ 新开组，未触碰任何已收口组。
- T0 类 = 0（八组余量 0，禁凑，R228）。
- 源优先级：20 件全部为 ROADMAP 未注册真缺口（存量 14 条待办均为治理类，无组件池可消化），高于矩阵 ◐ 组重复挖掘，符合源优先级排序。

## 五、拒单留痕（候选名 + 命中位置）

| 拒绝候选名 | 三查结果 | 拒绝原因 | 处置 |
|---|---|---|---|
| FC_DL_ManhattanDistance | registry=0 / roadmap=0 / file=0 | 非同名命中，判**同义邻件语义命中**：与存量 `FC_DL_CalcDistance3D`（R11，距离族属主，明文「2D 判退化拒绝拆变体」）同树同义，曼哈顿/切比雪夫距离在 PLC 侧无独立用例 | 不立项，本表留痕 |
| FC_DL_ChebyshevDistance | registry=0 / roadmap=0 / file=0 | 同上，距离度量变体凑数 | 不立项，本表留痕 |
| FC_DL_EwmaCalc | registry=0 / roadmap=0 / file=0 | 与存量 `FB_DL_R2rEwmaTuner`（EWMA 域）+ `FB_DL_MovingAverage`/`FC_DL_WeightedMovingAvg`（均值族）同树同义，指数加权均值无独立验收粒度 | 不立项，本表留痕 |
| FB_DL_AxisSs2StopSeq | registry=0 / roadmap=0 / file=0 | 与存量 `FB_DL_AxisSs1StopSeq`（R45 SS1 停车族）同族同义，SS2 仅保持语义差异，属参数级变体 | 不立项，本表留痕 |
| FB_DL_AxisBacklashDirBias | registry=0 / roadmap=0 / file=0 | 背隙族**饱和**（`AxisBacklashCompensator`/`AxisBacklashComp`/`AxisBacklashIdent`/`AxisBacklashStepComp` 四件在册），方向偏置属同义变体 | 不立项，本表留痕 |
| FB_DL_FailsafeGate | registry=0 / roadmap=0 / file=0 | 规划中途自裁：安全侧直通语义已被 `FB_DL_EStopDualChannel`（#5）的失效判据覆盖大半，独立成件验收粒度不足 | 收敛进 #5，不单独立项 |

- 拒单合计 6 项：同名命中 0 / 语义同义命中 6 / 自裁收敛 1（计入上表第 6 行）。主因：距离度量与背隙家族的变体凑数倾向，按 R61/R228「宁少勿滥」拒绝。

## 六、反证句（逐件 20 行，不得合并）

1. FC_DL_HermiteInterp：该件不与 `FC_DL_CubicSplineInterp` / `FC_DL_LagrangeInterp` / `FC_DL_InterpolateTable2D` 同树同义，差异点 = Hermite 由「端点值 + 端点导数」四条件定曲线，支持非等距单区间、不建全局网格表；样条需全局连续性、拉格朗日需等距节点、查表件只做折线。
2. FC_DL_QuatSlerp：该件不与 `FC_DL_QuatRotateVec` / `FC_DL_WrapAngleDeg` / `FC_DL_Affine2DCompose` 同树同义，差异点 = 输出是两姿态间的**中间四元数**（球面插值），不是旋转向量作用、不是角度归一、不是 2D 仿射链。
3. FC_DL_RoundSigFigs：该件不与 `FC_DL_RoundSat` / `FC_DL_RoundBankEx` / `FC_DL_TruncEx` 同树同义，差异点 = 按**有效数字位数**（相对量级幂定位）舍入，而非小数位饱和 / 银行家舍入 / 向零截断。
4. FC_DL_RtdLinearization：该件不与 `FC_DL_TempUnitConvert` / `FC_DL_MultiPointLinear` / `FB_DL_NtcTempScan` 同树同义，差异点 = 输入是 RTD 阻值、用 CVD 物理多项式（IEC 60751 公开系数）反解温度；单位换算不做线性化、查表不做物理解析、NTC 是 B 值指数族。
5. FB_DL_EStopDualChannel：该件不与 `FB_DL_TwoHandSafety` / `FB_DL_SafetyRelayFeedback` / `FB_DL_InterlockMatrix` 同树同义，差异点 = 急停**双回路本体**的连续不一致监视 + 单路失效判别 + 复位链自检；双手件是同步性校验、继电器件是反馈镜像、联锁件是多条件仲裁。
6. FC_DL_Kalman2DSmoother：该件不与 `FB_DL_KalmanFilter1D` / `FB_DL_LuenbergerObserver` / `FB_DL_SignalStatistics` 同树同义，差异点 = 2D 常速模型（位置/速度双状态）单测量序贯更新纯函数形态；1D 件只有标量状态、观测器是一般状态重构、统计件无模型。
7. FB_DL_SignalSeqGuard：该件不与 `FB_DL_EdgeOrderCheck` / `FB_DL_MultiClickDetect` / `FB_DL_StepTimeRecorder` 同树同义，差异点 = N 路信号必须按预配置**序号数组**逐位到位校验（乱序+超时双出口）；边沿件只判两信号先后、连击件判重复按压、计时件只记录不分序。
8. FB_DL_TwoDofPid：该件不与 `FB_DL_PidController` / `FB_DL_CascadePid` / `FB_DL_BumplessTransfer` 同树同义，差异点 = 设定值加权 β/γ 的**二自由度结构**（抑超调与抗扰分调两个自由度）；单自由度件共享同一误差、串级件是双回路、无扰切换是手自动过渡。
9. FB_DL_LossInWeightFeeder：该件不与 `FB_DL_BatchDosingControl` / `FB_DL_FillWeightCtrl` / `FB_DL_PowderDosingLoss` 同树同义，差异点 = 失重秤**连续失重速率闭环**（罐重一阶差分→喂料速度调节 + 重灌装暂停相）；批次件是定量结算、灌装件是终检、损耗件是统计。
10. FB_DL_UvDoseCtrl：该件不与 `FB_DL_EnergyMeterAccum` / `FB_DL_RampSoakProfile` / `FB_DL_BatchEndPointTrend` 同树同义，差异点 = 剂量 = 强度×时间的**受控积分达标判定**（带灯老化补偿系数），不是电量累计、不是程序曲线、不是趋势终点推断。
11. FB_DL_HydraulicAccumPreChg：该件不与 `FB_DL_PressureReliefMonitor` / `FB_DL_PumpCavitationGuard` / `FB_DL_PressureSwitchChatter` 同树同义，差异点 = 蓄能器**氮气预充压力**经气体定律温度折算后的欠/过压双态校验；泄放件是超压监视、汽蚀件是泵判据、抖振件是开关触点行为。
12. FB_DL_VacIonizerBalance：该件不与 `FB_DL_EscHeLeakCheck` / `FB_DL_HealthAggregator` / `FB_DL_CleanRoomPressure` 同树同义，差异点 = 离子风机**平衡电压偏移 + 衰减时间**双判据的 ESD 器件分级诊断；氦检是泄漏率、聚合件是多源仲裁、压差件是房间环境。
13. FB_DL_FanVfdBypassSwap：该件不与 `FB_DL_FanArraySeq` / `FB_DL_RedundantSwitch` / `FB_DL_InverterGridSync` 同树同义，差异点 = 单台风机**变频→工频旁路**的接触器互锁切换时序（停机互锁 + 间隔窗）；阵列件是多台轮值、冗余件是传感器切换、并网件是电压同步。
14. FB_DL_UltrasonicWeldCtrl：该件不与 `FB_DL_LaserWeldPowerSeq` / `FB_DL_HeatSealProfile` / `FB_DL_PressFitStation` 同树同义，差异点 = 超声焊接**能量/振幅/时间三模终点** + 振幅过载保护；激光件是功率序、热封件是温度曲线、压装件是力-位移。
15. FB_DL_AxisAccelFeedforward：该件不与 `FB_DL_AxisFrictionFf` / `FB_DL_TorqueLimitControl` / `FB_DL_LeadLagCompensator` 同树同义，差异点 = 由**规划加速度 × 折算惯量比**生成加速度前馈偏置；摩擦件补偿速度相关项、限幅件是保护、超前滞后是频域结构。
16. FB_DL_AxisProbeMeasCycle：该件不与 `FB_DL_MarkPositionLatch` / `FB_DL_AxisInPosMonitor` / `FB_DL_CoatingGapMeasure` 同树同义，差异点 = 完整**探针测量循环**（趋近速度级联→触发锁存→回退→N 点尺寸评价）；锁存件是单点原子、在位件是监视、间隙件是涂层工艺量。
17. FB_DL_AxisCantileverComp：该件不与 `FB_DL_AxisBacklashCompensator` / `FB_DL_AxisTeachOffset` / `FB_DL_GantrySkewMonitor` 同树同义，差异点 = 悬臂**挠曲变形量**随负载/伸长量的材料力学前馈修正；背隙件是反向间隙、示教件是固定偏置、龙门件是双驱偏差。
18. FB_DL_HotRunnerZoneBalance：该件不与 `FB_DL_HeatCoolZone` / `FB_DL_LamHeaterZoneSync` / `FB_DL_TempCompClassify` 同树同义，差异点 = 热流道**多区间均衡偏差分级 + 孤立区诊断**（模具域）；单区件是冷热执行、同步件是跟随指令、分类件是补偿分类。
19. FB_DL_SlurrySieveClogWatch：该件不与 `FB_DL_FilterDpMonitor` / `FB_DL_AhuFilterDpBank` / `FB_DL_ConveyorSlipWatch` 同树同义，差异点 = 料浆筛网**压差比 + 筛下流量衰减双判据**堵塞诊断；滤压差件是单判据通用滤波、滤芯组是暖通批量、打滑件是速差。
20. FB_DL_AirShowerInterlockSeq：该件不与 `FB_DL_GuardLockDoor` / `FB_DL_FoupDoorSeq` / `FB_DL_EfEmDoorInterlockPlus` 同树同义，差异点 = 风淋室**双侧门 + 吹淋定时三段联锁序列**（吹淋不完整禁行）；门锁件是单门互锁、FOUP 件是传送对接、EFEM 件是泛设备联锁。

## 七、P0 返修规格（承 R55 五抽，整理自 `REVIEW_R55.md` 行级修法，交付编码专家施工）

> 版本口径：五件返修统一 **v1.0.1**；行为变更处（FopdtStepIdent 切线法、PackMlUnitMode 校验、StringElImageMap 复位作用域）在 VERSION.md / CHANGELOG 变更行标 **MINOR 说明**；返修后必须重注入 JSONL 对应行并 sha256 复验（R102 全量口径）。

### 7.1 FB_DL_BacdHvacPoll（DL_Process）—— 严重（编译阻断）
- [ ] 补声明：VAR 区新增 `_nCurRetry : INT := 0;  // 当前设备已重试次数工作值 [次] / retry working value`——段 2（L143）、段 4 响应支路（L199）、超时支路（L228/229/235）、eFault 相（L281）、出口映射（L324）共 7 处引用/赋值依赖此声明。
- [ ] 死分支裁决：段 7 成因分派 `ELSIF _nUseCount < 1` 恒假（`_nUseCount` 段 3 已回钳 ≥1）——建议改按原始引脚 `nDevCount < 1` 判定使 `eNoDevice` 成因可达；若裁定删除，须在头注释留痕并说明 `eNoDevice` 由参数非法闸承载。
- [ ] 返修后执行全库 `grep` 专项扫描「先引用后声明」模式（`\b_n[A-Z]` 工作值变量），失败清单挂 R56 增补 P0 条目。

### 7.2 FB_DL_FopdtStepIdent（DL_Algo）—— 中
- [ ] L396 切线法改带符号斜率求截距：引入 `_fSlopeSig := _fSlopeMax * SIGN(_fDeltaPv);` 后以 `_fDeadTan := _fTSlopeMax - (_fPvSlopeMax - _fPvBase) / _fSlopeSig;` 求截距；分母量级守卫仍由既有 `_fSlopeMax > DL_FOPDT_EPS` 证明（SIGN 结果绝对值 = 1，不改变量级论证）。验收向量：负向阶跃（fMvStep < 0）时 bUseTangent=TRUE 出口死区时间与两点法口径同量级，不再系统性高估。
- [ ] eDone 相重启分支（L461~470）补清 `_fPvSlopeMax := 0.0;` / `_fTSlopeMax := 0.0;` 两行（与 eIdle 分支对齐），防二次辨识残留首辨识斜率峰值。

### 7.3 FB_DL_CoinCellAssembler（DL_Process）—— 轻
- [ ] 删除死变量 `_eCause`（全文件仅首扫清零与出口映射出现、无任何赋值路径写入非 eNone 值），并简化段 7 出口映射；若为后续信息级成因预留，则补注释声明其恒空契约。

### 7.4 FB_DL_StringElImageMap（DL_Process）—— 轻
- [ ] 段 2 复位作用域补 4 行清零：`fLastXmm := 0.0;` / `fLastYmm := 0.0;` / `fLastSizeMm2 := 0.0;` / `nLastType := 0;`（复位后旧缺陷坐标不得残留出口）。
- [ ] 段 2 补 `_stCur.uBatchId := uBatchId;` 重同步，防复位后首条新批报告被误判入旧批窗口。

### 7.5 FB_DL_PackMlUnitMode（DL_Process）—— 轻
- [ ] 段 4 受理 `_eMode := eModeReq` 前补枚举合法性校验（仿段 3 五选一判式），非法请求改记 `_eReject := E_DL_PmlReject.eModeBlocked;` 不采纳，消除一拍非法模式窗口且拒绝有留痕。
- [ ] 注释段号回正：段 9 / 段 10 头注释错标 "segment 10 / segment 11"（L374、L380）改为正确段号。

### 7.6 返修批记账（R193/R194 三维）
- 返修件数 5 × 处数 15（BacdHvacPoll 7 + Fopdt 3 + SEI 1 族 + CCA 1 + PML 3）× R55 批次；返修批优先于批 1 新件施工（下轮排程首位 = BacdHvacPoll 补声明）。
- R55 五抽挂账 5/5 触发扩检条款：本轮批 4 新件终审须含「声明区完整性」同族复查项。

---

*R56 规划线 ｜ 2026-11-20 ｜ 道莅工控代码库产品总监 ｜ 阶段一+阶段二：零 WebSearch、零 .st 产出*
