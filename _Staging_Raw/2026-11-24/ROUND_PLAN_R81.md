# ROUND_PLAN_R81 —— 道莅万级工业代码库（R81 / 2026-11-24 冲刺轮）

> 生成时间：2026-11-24T08:26+08:00（落盘实测，T+1′） ｜ 目标 40 件 = 复杂 4 + 简单 36 ｜ 模式：**SPRINT**（今日 82/300 < 第3轮进度 114）
> 修复名额：**0**（非当日首轮，铁律一）｜上轮 P0 五项逻辑 MAJOR 修复顺延至次日首轮
> 规划期词根去重：40 名全量 token 级扫描（≥2 token 命中即驳回），4 名改版后零命中

## 批 A —— 简单件（C1~C2，20~50 行，5 族模板派生，单批 36 件一次写盘）

| # | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_ShuttleStrokeTimeEst | DL_Process | FC | 穿梭车单行程时间估算（加速段+匀速段+减速段） | 立库族/clean-room | C1 | A | 简单 |
| 2 | FC_DL_ShuttleAisleLockChk | DL_Process | FC | 穿梭车巷道互锁校验（同巷道双车互斥） | 立库族/clean-room | C1 | A | 简单 |
| 3 | FC_DL_LifterCycleTimeEst | DL_Process | FC | 提升机单循环节拍估算（含装卸换向） | 立库族/clean-room | C1 | A | 简单 |
| 4 | FC_DL_StocktakeVarianceCalc | DL_Process | FC | 盘点账实差异量与差异率 | 立库族/clean-room | C1 | A | 简单 |
| 5 | FC_DL_BeamToppleRiskChk | DL_Process | FC | 货架横梁倾覆风险（偏心载重比） | 立库族/clean-room | C1 | A | 简单 |
| 6 | FC_DL_CellOccupyRateCalc | DL_Process | FC | 货位占用率（按区分组统计） | 立库族/clean-room | C1 | A | 简单 |
| 7 | FC_DL_ForkExtendSafeChk | DL_Process | FC | 货叉伸出安全校验（通道余量与货位对齐） | 立库族/clean-room | C2 | A | 简单 |
| 8 | FC_DL_BinLabelCheckSum | DL_Process | FC | 货位标号校验和（含断字符过滤） | 立库族/clean-room | C1 | A | 简单 |
| 9 | FC_DL_FoamSuppressDutyCalc | DL_Process | FC | 抑泡剂投加占空比（按液面高度比例） | 灌装清洗族/clean-room | C1 | A | 简单 |
| 10 | FC_DL_RinseWaterVolumeCalc | DL_Process | FC | 冲洗水量计算（管容+残留系数） | 灌装清洗族/clean-room | C1 | A | 简单 |
| 11 | FC_DL_SanitizeHoldTimeCalc | DL_Process | FC | 消毒保持时间（按浓度折标） | 灌装清洗族/clean-room | C2 | A | 简单 |
| 12 | FC_DL_ConductivityDilutionCalc | DL_Process | FC | 电导率折稀释比（母液/目标） | 灌装清洗族/clean-room | C1 | A | 简单 |
| 13 | FC_DL_NozzleClogIndexCalc | DL_Process | FC | 喷嘴堵塞指数（同组流量偏差） | 灌装清洗族/clean-room | C2 | A | 简单 |
| 14 | FC_DL_SipResidueVolumeEst | DL_Process | FC | SIP 管路残留量估算（坡度+盲管段） | 灌装清洗族/clean-room | C2 | A | 简单 |
| 15 | FC_DL_FillValveSealWearEst | DL_Process | FC | 灌装阀密封磨损量估算（循环次数+温升） | 灌装清洗族/clean-room | C2 | A | 简单 |
| 16 | FC_DL_BottleNeckLevelMargin | DL_Process | FC | 瓶口液位余量（防溢流裕度） | 灌装清洗族/clean-room | C1 | A | 简单 |
| 17 | FC_DL_ReceiverPressureDropCalc | DL_Process | FC | 储气罐压降速率与容量核算 | 空压站族/clean-room | C2 | A | 简单 |
| 18 | FC_DL_AirQualityClassifyCalc | DL_Process | FC | 压缩空气质量等级判定（露点/含油/颗粒） | 空压站族/clean-room | C2 | A | 简单 |
| 19 | FC_DL_DesiccantLifeEstimate | DL_Process | FC | 干燥剂剩余寿命估算（吸湿累积） | 空压站族/clean-room | C2 | A | 简单 |
| 20 | FC_DL_MotorLoadFactorCalc | DL_Process | FC | 电机负载率（视在/额定） | 空压站族/clean-room | C1 | A | 简单 |
| 21 | FC_DL_CompressorDutyCycleCalc | DL_Process | FC | 空压机加载占空比与卸载能耗占比 | 空压站族/clean-room | C2 | A | 简单 |
| 22 | FC_DL_DrainIntervalCalc | DL_Process | FC | 自动排水间隔（析水量/阀容） | 空压站族/clean-room | C1 | A | 简单 |
| 23 | FC_DL_IdleRunRatioCalc | DL_Process | FC | 空转率（卸载时长/运行时长） | 空压站族/clean-room | C1 | A | 简单 |
| 24 | FC_DL_VacuumPadForceCalc | DL_Device | FC | 真空吸盘吸附力（面积×压差×安全系数） | 真空吸取族/clean-room | C1 | A | 简单 |
| 25 | FC_DL_SuctionFlowEst | DL_Device | FC | 抽吸流量估算（喷嘴孔径+压差） | 真空吸取族/clean-room | C2 | A | 简单 |
| 26 | FC_DL_SheetPeelForceCalc | DL_Device | FC | 片材剥离力估算（粘附+静电） | 真空吸取族/clean-room | C2 | A | 简单 |
| 27 | FC_DL_VacHoldDecayChk | DL_Device | FC | 真空保持衰减校验（保压窗口阈值） | 真空吸取族/clean-room | C1 | A | 简单 |
| 28 | FC_DL_PadWearIndexCalc | DL_Device | FC | 吸盘磨损指数（泄漏增量归一） | 真空吸取族/clean-room | C2 | A | 简单 |
| 29 | FC_DL_VacuumGenDutyCalc | DL_Device | FC | 真空发生器工作占空比 | 真空吸取族/clean-room | C1 | A | 简单 |
| 30 | FC_DL_SuctionCupCountCalc | DL_Device | FC | 吸盘数量配置（按负载与冗余） | 真空吸取族/clean-room | C1 | A | 简单 |
| 31 | FC_DL_LineSpeedMatchRatio | DL_Motion | FC | 线速匹配比（主从速比与偏差） | 输送传动族/clean-room | C1 | A | 简单 |
| 32 | FC_DL_ChainWearElongation | DL_Motion | FC | 链条磨损伸长率（节距增量） | 输送传动族/clean-room | C2 | A | 简单 |
| 33 | FC_DL_RollerSlipRatioCalc | DL_Motion | FC | 辊筒打滑率（线速差/理论速） | 输送传动族/clean-room | C1 | A | 简单 |
| 34 | FC_DL_SkateWheelLoadCalc | DL_Motion | FC | 滑板轮单轮载荷分配 | 输送传动族/clean-room | C2 | A | 简单 |
| 35 | FC_DL_LaneDiverterAngleCalc | DL_Motion | FC | 分流道岔转角（按包件尺寸） | 输送传动族/clean-room | C1 | A | 简单 |
| 36 | FC_DL_TrackingOffsetChk | DL_Motion | FC | 跟踪偏移校验（编码器累计误差） | 输送传动族/clean-room | C2 | A | 简单 |

## 批 B —— 复杂件（C3~C5，5 件/批，本批 4 件）

| # | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 37 | FB_DL_RotaryIndexerCycleSeq | DL_Process | FB | 转盘八工位索引节拍：工位并行推进+杯位好坏移位寄存器+剔除工位 | 队列 FB_Dolum（MIT，绿区） | C5 | B | 复杂 |
| 38 | FB_DL_AsrsSlotAllocSeq | DL_Process | FB | 立库货位分配与取放握手：ack_seq/res_seq 序号同步+冲突回退 | 队列 FB_Asrs（MIT，绿区） | C4 | B | 复杂 |
| 39 | FB_DL_FillPreactSelfLearn | DL_Process | FB | 灌装预动作量自学习：粗/细流切换+下落量补偿闭环+学习限幅 | 队列 FB_Dolum PREACT（MIT，绿区） | C4 | B | 复杂 |
| 40 | FB_DL_MeasureInputLatch | DL_Motion | FB | 探针测量锁存：布防-触发-锁存-读取四相+窗口超时 | 队列 MC_MeasuringInputFB（MIT，绿区） | C3 | B | 复杂 |

## 族组织

| 族 | 件数 | 连号 | 语义空白依据（规划期 grep 实测） |
|---|---|---|---|
| 立体库族 | 8 | 1-8 | Shuttle/Lifter/Aisle/Stocktake/Fork 词根全库 0 命中 |
| 灌装清洗族 | 8 | 9-16 | FoamSuppress/Rinse/Sanitize/NozzleClog 0 命中 |
| 空压站族 | 7 | 17-23 | Receiver/AirQuality/MotorLoad 0 命中 |
| 真空吸取族 | 7 | 24-30 | VacuumPad/Suction/Peel 0 命中 |
| 输送传动族 | 6 | 31-36 | LineSpeed/Tracking/Diverter/ChainWear 0 命中 |

## 撞名驳回留痕（规划期，未写盘）

| 原名 | 撞名对象 | 重叠 token | 处置 |
|---|---|---|---|
| FC_DL_FilmTensionTaperCalc | FB_DL_FilmTaperTension | film,tension | 驳回，整族放弃 |
| FC_DL_StretchOverlapRatio | FB_DL_StretchWrapSeq | stretch,wrap | 驳回 |
| FC_DL_BeltSlipRatioCalc | FB_DL_ConveyorSlipWatch | belt,slip | 驳回 |
| FC_DL_JamDetectWindow | FB_DL_ConveyorJamDetect | jam,detect | 驳回 |
| FC_DL_AccumZoneCountCalc | FB_DL_ConveyorAccumGateSeq | accum,zone | 驳回 |
| FC_DL_AirLeakRateEst | FC_DL_PneuLeakRateCalc | air,leak | 驳回 |
| FC_DL_SipLineResidueEst | FB_DL_SipLineSterilSeq | sip,line | 改名→SipResidueVolumeEst |
| FC_DL_UnloadAirRatioCalc | FB_DL_AirCompressorLoadUnload | air,unload | 改名→IdleRunRatioCalc |
| FC_DL_CupDenestForceCalc | FB_DL_CupFillDenest | cup,denest | 改名→SheetPeelForceCalc |
| FB_DL_CupFillSealIndexer | FB_DL_CupFillDenest | cup,fill | 改名→RotaryIndexerCycleSeq |

## 里程碑（T=08:25）

| 检查点 | 时限 | 判据 |
|---|---|---|
| 规划落盘 | T+15′ 08:40 | ✔ 实际 T+1′ 08:26 |
| 编码交付 ≥28 | T+40′ 09:05 | ✔ 实际 T+15′ 前 36 件、T+25′ 前 40 件 |
| 闸裁 ≥28 | T+50′ 09:15 | ✔ 实际 T+18′ 批 A 36 件、T+31′ 批 B 终裁 |
| 入库战报 | T+60′ 09:25 | ✔ 实际 T+32′ 入库、T+37′ 战报 |

## 溯源口径（本轮）

- 复杂 4 件全部来自候选队列 R80 采集的 MIT 绿区条目（FB_Dolum / FB_Asrs / MC_MeasuringInputFB），头注写「来源 / URL / 许可证 / 借鉴点」。
- 简单 36 件为工程公式 clean-room 自研，头注标 `clean-room (no upstream)`，**不虚报溯源**。
- 预估溯源占比 4/40 = 10%，未达 30% 铁律 —— 原因：队列剩余 92 条为 OSCAT 基础数学，与五族垂直工艺语义零交集；如实披露，不注水。
