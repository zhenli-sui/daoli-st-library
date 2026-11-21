# ROUND_PLAN_R43（第 43 轮规划 · 2026-11-19 · 20 目标锁定 + 码位硬约束）

> 本轮性质：**纯规划轮**，零编码、零文档正文改动。WebSearch **0 次**，全部复用 `SOURCE_HUNTING_MATRIX.md` 既有 T0/T1/T2 组与 ROADMAP 真缺口实测。
> 口径：R241 反证句 / R242 磁盘优先 / R192 三向一致 / R28 终审两式。

## §1 总库看板

| 项 | 数值 |
|---|---|
| 总库规模 | **745 / 10,000（7.45%）**，registry v2.34.0，last_updated 2026-11-19T20:30 |
| 今日（11-19）产出 | **75 / 200**（R39 20 + R40 15 + R41 20 + R42 20）；R43 交付后 95 / 200 |
| 距 500 差额 | **+245 超额**（已远超阶段目标） |
| 各池 counts | Base 83 / MathData 197 / Algo 74 / Device 145 / Motion 70 / Process 176 |
| ROADMAP 未勾 | 总 135 条；行首锚定正则实测带名 **115 条 → 真缺口 80 / 伪缺口 35**（伪缺口为本轮剔除依据，见 §4） |
| 源矩阵覆盖 | 沿用 R42 实测：状态列 110 行，✔33 / ◐61 / ☐16 → 全收口 30%、含部分 85.5%；T0 七组 7/7 ✔，**无未收口 T0 组** |
| 品类缺口 | MathData 197 已超配（占 26.4%），Algo 74 / Motion 70 偏薄 → **本轮 MathData 0 件**，Algo+Motion 合计 7 件补薄 |

## §2 20 目标总表（已逐名过三段查重，反证句见 §3）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 | 码位（故障 / 信息） |
|---|---|---|---|---|---|---|---|---|
| 1 | FB_DL_StakingPressCtrl | DL_Process | FB | 叠片台压装顺控（对齐-压紧-保压-泄压，压力窗判据） | roadmap-li-p1 | 6 | 1 | 05_3_9D / 05_4_C5 |
| 2 | FB_DL_PouchVacuumSeal | DL_Process | FB | 铝塑膜真空封装（真空度窗 + 封头温度 + 封合延时） | roadmap-li-p1 | 6 | 1 | 05_3_9E / 05_4_C6 |
| 3 | FB_DL_CalenderRollPress | DL_Process | FB | 辊压机辊隙/线压力顺控（双侧压下 + 厚度反馈） | roadmap-li-p1 | 6 | 1 | 05_3_9F / 05_4_C7 |
| 4 | FB_DL_QuarterCellCutSeq | DL_Process | FB | 极片分切顺控（刀轴相位 + 张力窗 + 废边回收） | roadmap-li-p2 | 6 | 1 | 05_3_A0 / 05_4_C8 |
| 5 | FB_DL_CellOcvBinSort | DL_Process | FB | OCV 分选档位落 bin（档位映射 + 满 bin 换道） | roadmap-li-p1 | 6 | 1 | 05_3_A1 / 05_4_C9 |
| 6 | FB_DL_IvCurveScan | DL_Process | FB | IV 曲线扫描与特征点提取（Voc/Isc/FF + 扫描窗） | roadmap-pv-p1 | 7 | 2 | 05_3_A2 / 05_4_CA |
| 7 | FB_DL_ChillerCondReset | DL_Process | FB | 冷水机组冷凝压力重置（室外湿球联动限幅） | t1-2-oscat-building | 5 | 2 | 05_3_A3 / 05_4_CB |
| 8 | FB_DL_SampleLoopPurge | DL_Process | FB | 取样回路吹扫与取样窗（阀序 + 吹扫/静置计时） | t1-2-oscat-building | 5 | 2 | 05_3_A4 / 05_4_CC |
| 9 | FB_DL_BundleShrinkTemp | DL_Process | FB | 收缩包装热风温度窗（超温/欠温双判 + 冷却延时） | roadmap-pkg-p2 | 5 | 2 | 05_3_A5 / 05_4_CD |
| 10 | FB_DL_DuctLeakRateEst | DL_Algo | FB | 风管漏风率估算（流量差法 + 静压修正 + 分级判据） | t1-2-oscat-building | 6 | 2 | 02_3_86 / — |
| 11 | FB_DL_VavPressureReset | DL_Algo | FB | VAV 静压重置（最不利末端阀位寻优 + 步长限幅） | t1-2-oscat-building | 6 | 3 | 02_3_87 / — |
| 12 | FB_DL_ChwDifferentialPressureReset | DL_Algo | FB | 冷冻水压差重置（阀位反馈反算设定 + 死区保持） | t1-2-oscat-building | 6 | 3 | 02_3_88 / — |
| 13 | FB_DL_SelfDischargeScreen | DL_Algo | FB | 自放电筛分（压降速率 K 值分级 + 温度补偿） | roadmap-li-p2 | 6 | 3 | 02_3_89 / — |
| 14 | FB_DL_FanPressureTrim | DL_Algo | FB | 风机静压微调（偏差积分微调 + 抗饱和回退） | t2-7-packml | 5 | 3 | 02_3_8A / — |
| 15 | FB_DL_CleanRoomRhTrim | DL_Device | FB | 洁净室加湿阀脉冲微调（RH 偏差 + 最小开度保护） | t1-2-oscat-building | 5 | 3 | 03_5_2B / 03_4_31 |
| 16 | FB_DL_BoilerFlueCondenseGuard | DL_Device | FB | 锅炉烟气冷凝防护（排烟温度低限联锁 + 回水温度钳制） | t1-2-oscat-building | 5 | 4 | 03_5_2C / 03_4_32 |
| 17 | FB_DL_CellFeederVacuum | DL_Device | FB | 电芯真空上料吸盘（真空窗 + 泄漏率判据 + 掉料重试） | t1-5-tcopen | 5 | 4 | 03_5_2D / 03_4_33 |
| 18 | FB_DL_AxisBrakeDistPredict | DL_Motion | FB | 轴制动距离预判（速度/减速度→停车距离 + 硬限位留量） | t1-6-plcopen | 6 | 4 | 04_0_A6 / — |
| 19 | FB_DL_GearInPhaseAlign | DL_Motion | FB | 电子齿轮啮合相位对齐（相位差窗 + 从轴偏置补偿） | t1-6-plcopen | 6 | 4 | 04_0_A7 / — |
| 20 | FC_DL_TimeToCycleCeil | DL_Base | FC | 时间→扫描周期数**向上取整**（正好整除不 +1，含 0/上限钳制） | iec-std-wrapper | 3 | 4 | 01_0_02 / — |

**分布**：Process 9 / Algo 5 / Device 3 / Motion 2 / Base 1 / MathData 0 = 20。
**配额自证**：T2 族 4 件（t1-2 OSCAT Building 8 件含 T1、t1-5 TcOpen 1、t1-6 PLCopen 2、t2-7 PackML 1）→ 满足「≥1 T1 组 + ≥1 T2 族」；T0 防御包装 1 件（#20，委托内建 TRUNC 判定 + 统一错误码，不重实现数学内核）。ROADMAP 真缺口取 14 件、源矩阵既有组取 6 件。
**批次**：#1~5 批1 / #6~10 批2 / #11~15 批3 / #16~20 批4。

## §3 反证句逐件清单（registry 精确名 + 磁盘 .st + 词干三查）

> 实测口径：registry = `INDEX_REGISTRY.json` 745 名全量；磁盘 = `DL_*/*.st` 745 件（disk-only 0，与 registry 一一对应）。

1. StakingPressCtrl：registry 命中 0；磁盘 .st 0；词干 Staking 命中 0。
2. PouchVacuumSeal：registry 命中 0；磁盘 .st 0；词干 Pouch 命中 PouchSwellingGauge（鼓包厚度测量），本件为真空封装封合顺控——判非同义。
3. CalenderRollPress：registry 命中 0；磁盘 .st 0；词干 Calender 命中 0。
4. QuarterCellCutSeq：registry 命中 0；磁盘 .st 0；词干 Quarter 命中 0。
5. CellOcvBinSort：registry 命中 0；磁盘 .st 0；词干 OcvBin 命中 0；Ocv 命中 OcvGradingBin（分选落料执行）/ OcvProbeDock（探针对接压装），本件为 OCV 数据到档位映射排序——判非同义。
6. IvCurveScan：registry 命中 0；磁盘 .st 0；词干 IvCurve 命中 0（`Iv` 子串命中 12 件均为 MotorDriver/Vfd/Div 类误命中，非词干）。
7. ChillerCondReset：registry 命中 0；磁盘 .st 0；词干 ChillerCond 命中 0（ChillerTempStab 为温度稳定，非同义）。
8. SampleLoopPurge：registry 命中 0；磁盘 .st 0；词干 SampleLoop 命中 0（AnalyzerSampleSeq 为分析仪取样时序，本件为回路吹扫阀序）——判非同义。
9. BundleShrinkTemp：registry 命中 0；磁盘 .st 0；词干 Bundle / BundleShrink 命中 0。
10. DuctLeakRateEst：registry 命中 0；磁盘 .st 0；词干 DuctLeak 命中 0（DuctStaticReset 为静压重置，非漏风率估算）——判非同义。
11. VavPressureReset：registry 命中 0；磁盘 .st 0；词干 VavPressure 命中 0（VavDischargeAirReset 为送风温度重置 / VavBoxCtrl 为箱体控制）——判非同义。
12. ChwDifferentialPressureReset：registry 命中 0；磁盘 .st 0；词干 ChwDiff 命中 ChwDifferentialPressure（压差**测量**件），本件为设定**重置**律——判非同义。
13. SelfDischargeScreen：registry 命中 0；磁盘 .st 0；词干 SelfDischarge 命中 0。
14. FanPressureTrim：registry 命中 0；磁盘 .st 0；词干 FanPressure 命中 0（FanArrayStageCtrl/Seq 为风机群组级联，非同义）。
15. CleanRoomRhTrim：registry 命中 0；磁盘 .st 0；词干 CleanRoomRh 命中 0（CleanRoomPressure 为压差控制）——判非同义。
16. BoilerFlueCondenseGuard：registry 命中 0；磁盘 .st 0；词干 BoilerFlue 命中 0（BoilerThreeElement 为三冲量水位）——判非同义。
17. CellFeederVacuum：registry 命中 0；磁盘 .st 0；词干 CellFeeder 命中 0。
18. AxisBrakeDistPredict：registry 命中 0；磁盘 .st 0；词干 BrakeDist 命中 0（AxisBrakeSeq 为制动**序列执行**，本件为**距离预判**）——判非同义。
19. GearInPhaseAlign：registry 命中 0；磁盘 .st 0；词干 GearIn 命中 0（CamTableValidate/Interp 为凸轮表，非同义）。
20. TimeToCycleCeil：registry 命中 0；磁盘 .st 0；词干 TimeTo 命中 TimeToDintMs / TimeToLrealSec / TimeToHmsString（纯单位换算，均**截断**），本件为**向上取整 + 正好整除边界**专用——判非同义。

## §4 剔除候选留档（防下轮重提）

- `FB_DL_TabWeldingMonitor`：词干 Tab 命中 **LaserTabWeldTrack**（激光叠瓦焊接跟踪），语义重叠 → 剔除，不更名重提。
- `FB_DL_CaseErectFaultSeq`：词干 Case/Erect 命中 CartonErectSeq / CartonErectVacMonitor / CartonErectorStation 三件族，判同义 → 剔除。
- `FB_DL_SteamTrapSurvey`：命中 SteamTrapMonitor / SteamTrapDiagTrend 双件 → 剔除。
- `FB_DL_AhuFanArrayTrim`：命中 FanArrayStageCtrl / FanArraySeq → 剔除。
- `FB_DL_CasePackerPatternVerify`：命中 CasePackerPattern（模式件本体）→ 剔除。
- `FB_DL_FormationChannelQueue`：命中 FormationChannelMgr（队列管理器在册）→ 剔除。
- `FB_DL_RfidTrayRoute` / `FB_DL_FoupRfidCheck`：词干 RfidTray/Foup 命中 FoupDoorSeq / FoupPurgeN2Flow / Rfid 族 → 剔除。
- `FB_DL_AmcMonitorStat`：`Amc` 为 **SteamCondensatePot / LamCtrlDualZone 子串误命中**，本可立项，但与本轮 #13 同属半导体环境统计，**让位下一轮**（非语义否决，标 ◐ 保留）。
- `FB_DL_SafeDiv` / `FB_DL_BitMaskDecode`：分别命中 FC_DL_DivLrealSafe/DivDintSafeChk 与既有位运算族，属薄包装凑数 → 剔除（R241 凑数禁令）。
- R42 剔除清单**继续有效**：ChamberPumpDownSeq / TankBlanketPrCtrl / LaminatorZoneSync / FC_DL_ShlDwordEx / 6 条伪缺口，本轮未重提。
- ROADMAP 伪缺口 35 条（registry 已在册仍挂未勾）：如 MfcFlowCtrl / CartonErectSeq / VffsBagLength / MachineGuardAudit / NailMachineSeq / PumpDryRunGuard / TrackBarcodeTrace / StringBarcodeTrace / LamDoorInterlock / PowderDosingLoss / RotaryIndexModulo / TankDosingMulti / StepperMicroFeedPulseEquiv / InverterPdiPoll / GasFlowSqrt / CartonErectorStation / PalletizerStation / AirDensityFanPower / GasDensityComp / LoopWaveInject / ElectrolyteMoistureGuard / SolderRibbonTension / MfcSetpointRamp / WaferCountYield / CoilFrostWindow / RollCompressForceBalance / WindingAlignEdge / TrackerSnowShedAngle / ConveyorMetalDetect / OrificeFlowCalc / SwapBytes16 / SemaMutex / WordToIntSat / MotionCmdQueue / InertPurgeSeq —— **一律不得再立项**，交 R44 勾选回写专项。

## §5 派单要点（每批必含，编码侧不得改判码位）

1. **七项红线**：命名前缀（POU `FB_DL_`/`FC_DL_`；变量 `b`/`n`/`u`/`f`/`s`/`t`/`a`/`st`/`e`/`fb`/`i`）；零全局耦合（禁 GVL / VAR_EXTERNAL / `%I`/`%Q`/`%M`）；纯 IEC 61131-3 + Standard.library；ENUM+CASE 全覆盖含 `ELSE` 兜底；防御性编程（浮点禁 `=`、防除零、数组边界、WHILE 计数器）；100% 双语注释 + 头部七要素（含 Origin 与修订历史）；无魔法数（阈值/限幅/超时提为带单位常量或输入引脚）。
2. **来源标签**：逐件把 §2 表标签原样写入头注释 `来源 Source`（`roadmap-li-p1` / `roadmap-pv-p1` / `roadmap-li-p2` / `roadmap-pkg-p2` / `t1-2-oscat-building` / `t1-5-tcopen` / `t1-6-plcopen` / `t2-7-packml` / `iec-std-wrapper`）。
3. **行尾 CRLF**；**双语注释**每行「中文 + / English」；**ENUM 单冒号体例** `eState : E_DL_Xxx := eIdle`。
4. **故障码硬约束**：Process 用 `05_3_9D~A5`（信息 `05_4_C5~CD`）；Algo `02_3_86~8A`；Device 故障 `03_5_2B~2D`（05xx 副带续编，头注释须写分段理由：段 0003 故障带已满、避开 0590~0599 判错位段）、信息 `03_4_31~33`；Motion `04_0_A6/A7`；Base `01_0_02`。**逐件唯一，不得两件同码**；改判须回主控。
5. **锁存解除式（R28-1）**：每个故障锁存位先写解除式再写置位，解除式全当拍量，逐 BOOL 标注锁存量/当拍量；恒假即当轮修（`IF NOT bEnable AND NOT _bFaultLatch` 反例禁写）。
6. **TON 纪律（R176/R232）**：跨相复位显式化；禁 `TON(IN:=TRUE)` 恒真；沿直连 TON 须审「门控沿与计时基不得同拍互斥」（R42 P0-1 教训）。
7. **整数进位点（R28-2）**：#20 与 #10~#13 的 ceil/round/钳制在「正好整除」与「上限+1」两点各出一条验收向量；`TRUNC(x)+1` 视为缺陷写法。
8. **本轮特殊注意**：#6 IV 扫描与 #13 自放电筛分涉高复杂度曲线/分级判据，须拆分纯计算子函数避免单块超 400 行；#18/#19 为 Motion 件，**只做 PLCopen MC 接口映射层**，禁内联轨迹规划内核（应复用 DL_Algo 既有件）。

## §6 挂账续转（R244：逐条续转，不得静默清账）

- **P1｜全库码位冲突普查**（含 Device 05xx 副带启用后的全带核对、MutexOwnerAudit 4 处存量冲突 0102/0202/0302/0402）→ **第 4 次挂账**，R43 若仍超时，R44 出专项回写（R192 三向一致口径，不阻塞主线）。
- **P1｜编译验证债**（连欠 ≥3 轮）→ 续挂；R43 失败即启动 R195 硬闸：冻结新增数学/编解码/转换类高复杂度件，首批实编译抽样 3 件。
- **P1｜code_segment 回填**：R42 新增 20 件已带码位头注释，registry `code_segment` 字段仍空 → 待 INDEX 专项轮统一回填。
- **P1｜MANUAL 补录**：MANUAL_DL_Algo.md（9.8KB）与 MANUAL_DL_MathData.md（4.2KB）显著落后于 counts，R44 起按子库补录。
- **P2｜ROADMAP 三向收敛**：伪缺口 35 条勾选回写 + 真缺口 80 条按品类重排（本轮已耗 14 条，余 66 条）。
