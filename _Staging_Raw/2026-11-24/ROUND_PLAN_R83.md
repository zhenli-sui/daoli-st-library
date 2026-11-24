# ROUND_PLAN_R83 —— 2026-11-24 下午轮（冲刺模式）

> 计划 40 件 = 简单 36（族A~E 批量派生）+ 复杂 4。修复名额 **0**（非当日首轮，铁律一）。

> 撞名终审：词根交集扫描（≥2 非通用词根命中同一存量件即驳回）+ registry 全名精确比对。


## 复杂件（4 件，C3~C4）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_PrintRegisterAutoTrimSeq` | DL_Process | FB | 印刷套准自动调整状态机 | 自研/clean-room | C4 | B1 | 复杂 |
| 2 | `FB_DL_DyeBatchRecipeSeq` | DL_Process | FB | 染批配方分段升温加料时序 | 自研/clean-room | C4 | B1 | 复杂 |
| 3 | `FB_DL_PlatingLineTransferSeq` | DL_Process | FB | 电镀线行车转序与槽位占用时序 | 自研/clean-room | C4 | B1 | 复杂 |
| 4 | `FB_DL_SortDiverterSeq` | DL_Algo | FB | 分拣分流器握手与故障恢复状态机 | 自研/clean-room | C3 | B1 | 复杂 |

## 简单件（36 件，C1~C2，20~50 行，族模板派生）


### 族A 印刷包装（8 件）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 5 | `FC_DL_InkViscosityTempComp` | DL_Process | FC | 油墨黏度温度补偿系数计算 | 自研/clean-room | C1 | S1 | 简单 |
| 6 | `FC_DL_RegisterErrorCalc` | DL_Process | FC | 套准横纵误差合成偏差计算 | 自研/clean-room | C2 | S1 | 简单 |
| 7 | `FC_DL_AniloxInkTransferCalc` | DL_Process | FC | 网纹辊单位面积传墨量计算 | 自研/clean-room | C2 | S1 | 简单 |
| 8 | `FC_DL_SpliceOverlapWidthCalc` | DL_Process | FC | 接卷搭接宽度与胶带用量计算 | 自研/clean-room | C2 | S1 | 简单 |
| 9 | `FC_DL_CutLengthDeviationCalc` | DL_Process | FC | 定长裁切偏差与补偿量计算 | 自研/clean-room | C1 | S1 | 简单 |
| 10 | `FC_DL_DryerSolventLoadCalc` | DL_Process | FC | 干燥箱单位时间溶剂负荷估算 | 自研/clean-room | C2 | S1 | 简单 |
| 11 | `FB_DL_SpliceCountdownCtrl` | DL_Process | FB | 接卷剩余米数倒计时与报警 | 自研/clean-room | C2 | S1 | 简单 |
| 12 | `FC_DL_ImpulseSealDwellCalc` | DL_Process | FC | 脉冲热封通电与保压时间计算 | 自研/clean-room | C2 | S1 | 简单 |

### 族B 纺织染整（8 件）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 13 | `FC_DL_DyeLiquorRatioCalc` | DL_Process | FC | 染浴浴比与总液量计算 | 自研/clean-room | C1 | S1 | 简单 |
| 14 | `FC_DL_FabricWeightAreaCalc` | DL_Process | FC | 织物单位面积克重计算 | 自研/clean-room | C1 | S1 | 简单 |
| 15 | `FC_DL_PaddingPickupCalc` | DL_Process | FC | 轧车轧余率与带液量计算 | 自研/clean-room | C2 | S1 | 简单 |
| 16 | `FC_DL_StenterHeatSetCalc` | DL_Process | FC | 定型机热定形时间与超喂计算 | 自研/clean-room | C2 | S1 | 简单 |
| 17 | `FC_DL_YarnCountConvert` | DL_MathData | FC | 纱线支数制式换算 | 自研/clean-room | C1 | S1 | 简单 |
| 18 | `FC_DL_BeamWarpLengthCalc` | DL_Process | FC | 经轴可卷绕经纱长度计算 | 自研/clean-room | C2 | S1 | 简单 |
| 19 | `FB_DL_DyeBathReplenishCtrl` | DL_Process | FB | 染浴液位与助剂补加联动控制 | 自研/clean-room | C2 | S1 | 简单 |
| 20 | `FC_DL_ShadeDriftIndexCalc` | DL_Process | FC | 色光漂移指数与回修判定 | 自研/clean-room | C2 | S1 | 简单 |

### 族C 表面处理电镀（7 件）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 21 | `FC_DL_PlatingThicknessChargeCalc` | DL_Process | FC | 法拉第定律镀层厚度与电量折算 | 自研/clean-room | C2 | S1 | 简单 |
| 22 | `FC_DL_FaradayEfficiencyCalc` | DL_Process | FC | 镀液电流效率由实测增重反算 | 自研/clean-room | C1 | S1 | 简单 |
| 23 | `FC_DL_AnodeCurrentDensityCalc` | DL_Process | FC | 阳极面积基准电流密度计算 | 自研/clean-room | C2 | S1 | 简单 |
| 24 | `FC_DL_RinseDragOutCalc` | DL_Process | FC | 漂洗槽带出量与补水率估算 | 自研/clean-room | C2 | S1 | 简单 |
| 25 | `FC_DL_BarrelRotationRpmCalc` | DL_Device | FC | 滚镀滚筒转速与临界转速比 | 自研/clean-room | C2 | S1 | 简单 |
| 26 | `FB_DL_ElectrolessBathReplenishCtrl` | DL_Process | FB | 化学镀浴按负荷补加控制 | 自研/clean-room | C2 | S1 | 简单 |
| 27 | `FC_DL_HexChromeTriRatioCalc` | DL_Process | FC | 六价三价铬浓度比与老化判定 | 自研/clean-room | C1 | S1 | 简单 |

### 族D 输送分拣（7 件）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 28 | `FC_DL_SortChuteTimingCalc` | DL_Algo | FC | 滑槽分拣释放延时计算 | 自研/clean-room | C2 | S1 | 简单 |
| 29 | `FC_DL_BeltThroughputCalc` | DL_Algo | FC | 皮带单位时间通过量计算 | 自研/clean-room | C1 | S1 | 简单 |
| 30 | `FC_DL_DiverterLeadTimeCalc` | DL_Algo | FC | 分流器动作提前量计算 | 自研/clean-room | C2 | S1 | 简单 |
| 31 | `FC_DL_ScannerReadRateCalc` | DL_Algo | FC | 读码首读率与重读次数统计 | 自研/clean-room | C1 | S1 | 简单 |
| 32 | `FC_DL_ChuteFullPredict` | DL_Algo | FC | 滑槽满料到达时间预测 | 自研/clean-room | C2 | S1 | 简单 |
| 33 | `FB_DL_ToteGapReleaseCtrl` | DL_Algo | FB | 料箱最小间隔放行控制 | 自研/clean-room | C2 | S1 | 简单 |
| 34 | `FC_DL_AccumulationZoneFillCalc` | DL_Algo | FC | 积放区占位率计算 | 自研/clean-room | C1 | S1 | 简单 |

### 族E 仓储立库周边（6 件）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 35 | `FC_DL_SlotHeightFitCalc` | DL_Device | FC | 货位净高与货高匹配校验 | 自研/clean-room | C1 | S1 | 简单 |
| 36 | `FC_DL_PalletOverhangCalc` | DL_Device | FC | 托盘悬垂量与允许上限校验 | 自研/clean-room | C1 | S1 | 简单 |
| 37 | `FC_DL_ForkEntryClearanceCalc` | DL_Device | FC | 货叉入叉左右余量计算 | 自研/clean-room | C2 | S1 | 简单 |
| 38 | `FC_DL_AsrsCycleTimeCalc` | DL_Device | FC | 堆垛机单循环作业时间估算 | 自研/clean-room | C2 | S1 | 简单 |
| 39 | `FC_DL_StackerMastSwayCalc` | DL_Motion | FC | 堆垛机立柱加减速摆幅估算 | 自研/clean-room | C2 | S1 | 简单 |
| 40 | `FC_DL_InventoryAgeIndexCalc` | DL_Device | FC | 出库优先级库龄指数计算 | 自研/clean-room | C1 | S1 | 简单 |

## 统计

- 通过 40 件（复杂 4 / 简单 36）
- 驳回 0 件：无
- 与存量 1,570 件全名精确比对：0 同名