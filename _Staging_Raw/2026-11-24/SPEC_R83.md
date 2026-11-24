# SPEC_R83 —— 编码规格书（R83 下午轮）

## 一、铁律（违反即返修）

R1 零 GVL/VAR_EXTERNAL；R2 零 %I/%Q 物理地址；R3 纯 IEC 61131-3 跨平台语法；R4 防除零/越界/浮点容差（除法前 `IF ABS(x) > 1.0E-9 THEN`，开方前非负闸）；R5 变量声明同行中英双语注释；R6 状态机用 ENUM+CASE 且必有 ELSE 兜底；R7 TON/R_TRIG 实例每周期无条件刷新（不放在 IF 内）。
R8 METHOD 先声明后实现（所有 VAR 之后、代码体之前）；R9 每 METHOD 必 END_METHOD；R10 禁 `LREAL(x)`/`DWORD(1)`/`UINT(n)` 式转换，一律 `REAL_TO_LREAL`/`INT_TO_DWORD`/`INT_TO_UINT`；R11 所有 VAR 声明以分号结尾（有行尾注释时分号在注释前）；R12 ENUM 成员赋值用 `:=`，ENUM 只在本件定义一次；R13 编码前语义查重；R14 FB 内禁 PROPERTY；R15 禁 VLA 透传；R16 引用他人前确认已 L2 PASS，否则内联。
**R17（本轮新增硬红线，R81/R82 血案）**：`FOR` 循环**严禁** `DOWNTO`（RuSTy 1.0.8 报 E007），倒序遍历一律改写为升序镜像下标 `dst := n-1-i`。
**R18**：`TON` 的 IN 不得跨相 OR 合并；每个定时器只串本相使能，且相迁移必须复位实例。
**R19**：声明了常量必须至少引用一次，零引用常量禁止留盘。
**R20**：凡输出「比率/回收率/效率」的件，必须保证该输出**不是恒等式**（不得由输入同式反算后直接回填）；凡有「标定/学习」语义的件必须写量纲自检与入参因果表。
**R21**：所有分母都必须显式零闸；NaN/Inf 必须被拦截（`IF NOT (x > -1.0E30 AND x < 1.0E30) THEN` 走故障分支，**不能**只写 `ABS(x) > FIN`）。

## 二、文件头（每件必写，clean-room 声明）

```
(*
  DL Factory R83 | <组件名>
  功能：<中文一句话>
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
```

## 三、目标清单（按序写盘，禁止跳号、禁止占位符）

1. `FC_DL_InkViscosityTempComp` | DL_Process | FC | 油墨黏度温度补偿系数计算 | C1 | 族印刷包装
2. `FC_DL_RegisterErrorCalc` | DL_Process | FC | 套准横纵误差合成偏差计算 | C2 | 族印刷包装
3. `FC_DL_AniloxInkTransferCalc` | DL_Process | FC | 网纹辊单位面积传墨量计算 | C2 | 族印刷包装
4. `FC_DL_SpliceOverlapWidthCalc` | DL_Process | FC | 接卷搭接宽度与胶带用量计算 | C2 | 族印刷包装
5. `FC_DL_CutLengthDeviationCalc` | DL_Process | FC | 定长裁切偏差与补偿量计算 | C1 | 族印刷包装
6. `FC_DL_DryerSolventLoadCalc` | DL_Process | FC | 干燥箱单位时间溶剂负荷估算 | C2 | 族印刷包装
7. `FB_DL_SpliceCountdownCtrl` | DL_Process | FB | 接卷剩余米数倒计时与报警 | C2 | 族印刷包装
8. `FC_DL_ImpulseSealDwellCalc` | DL_Process | FC | 脉冲热封通电与保压时间计算 | C2 | 族印刷包装
9. `FC_DL_DyeLiquorRatioCalc` | DL_Process | FC | 染浴浴比与总液量计算 | C1 | 族纺织染整
10. `FC_DL_FabricWeightAreaCalc` | DL_Process | FC | 织物单位面积克重计算 | C1 | 族纺织染整
11. `FC_DL_PaddingPickupCalc` | DL_Process | FC | 轧车轧余率与带液量计算 | C2 | 族纺织染整
12. `FC_DL_StenterHeatSetCalc` | DL_Process | FC | 定型机热定形时间与超喂计算 | C2 | 族纺织染整
13. `FC_DL_YarnCountConvert` | DL_MathData | FC | 纱线支数制式换算 | C1 | 族纺织染整
14. `FC_DL_BeamWarpLengthCalc` | DL_Process | FC | 经轴可卷绕经纱长度计算 | C2 | 族纺织染整
15. `FB_DL_DyeBathReplenishCtrl` | DL_Process | FB | 染浴液位与助剂补加联动控制 | C2 | 族纺织染整
16. `FC_DL_ShadeDriftIndexCalc` | DL_Process | FC | 色光漂移指数与回修判定 | C2 | 族纺织染整
17. `FC_DL_PlatingThicknessChargeCalc` | DL_Process | FC | 法拉第定律镀层厚度与电量折算 | C2 | 族表面处理电镀
18. `FC_DL_FaradayEfficiencyCalc` | DL_Process | FC | 镀液电流效率由实测增重反算 | C1 | 族表面处理电镀
19. `FC_DL_AnodeCurrentDensityCalc` | DL_Process | FC | 阳极面积基准电流密度计算 | C2 | 族表面处理电镀
20. `FC_DL_RinseDragOutCalc` | DL_Process | FC | 漂洗槽带出量与补水率估算 | C2 | 族表面处理电镀
21. `FC_DL_BarrelRotationRpmCalc` | DL_Device | FC | 滚镀滚筒转速与临界转速比 | C2 | 族表面处理电镀
22. `FB_DL_ElectrolessBathReplenishCtrl` | DL_Process | FB | 化学镀浴按负荷补加控制 | C2 | 族表面处理电镀
23. `FC_DL_HexChromeTriRatioCalc` | DL_Process | FC | 六价三价铬浓度比与老化判定 | C1 | 族表面处理电镀
24. `FC_DL_SortChuteTimingCalc` | DL_Algo | FC | 滑槽分拣释放延时计算 | C2 | 族输送分拣
25. `FC_DL_BeltThroughputCalc` | DL_Algo | FC | 皮带单位时间通过量计算 | C1 | 族输送分拣
26. `FC_DL_DiverterLeadTimeCalc` | DL_Algo | FC | 分流器动作提前量计算 | C2 | 族输送分拣
27. `FC_DL_ScannerReadRateCalc` | DL_Algo | FC | 读码首读率与重读次数统计 | C1 | 族输送分拣
28. `FC_DL_ChuteFullPredict` | DL_Algo | FC | 滑槽满料到达时间预测 | C2 | 族输送分拣
29. `FB_DL_ToteGapReleaseCtrl` | DL_Algo | FB | 料箱最小间隔放行控制 | C2 | 族输送分拣
30. `FC_DL_AccumulationZoneFillCalc` | DL_Algo | FC | 积放区占位率计算 | C1 | 族输送分拣
31. `FC_DL_SlotHeightFitCalc` | DL_Device | FC | 货位净高与货高匹配校验 | C1 | 族仓储立库周边
32. `FC_DL_PalletOverhangCalc` | DL_Device | FC | 托盘悬垂量与允许上限校验 | C1 | 族仓储立库周边
33. `FC_DL_ForkEntryClearanceCalc` | DL_Device | FC | 货叉入叉左右余量计算 | C2 | 族仓储立库周边
34. `FC_DL_AsrsCycleTimeCalc` | DL_Device | FC | 堆垛机单循环作业时间估算 | C2 | 族仓储立库周边
35. `FC_DL_StackerMastSwayCalc` | DL_Motion | FC | 堆垛机立柱加减速摆幅估算 | C2 | 族仓储立库周边
36. `FC_DL_InventoryAgeIndexCalc` | DL_Device | FC | 出库优先级库龄指数计算 | C1 | 族仓储立库周边
37. `FB_DL_PrintRegisterAutoTrimSeq` | DL_Process | FB | 印刷套准自动调整状态机 | C4 | 族复杂件
38. `FB_DL_DyeBatchRecipeSeq` | DL_Process | FB | 染批配方分段升温加料时序 | C4 | 族复杂件
39. `FB_DL_PlatingLineTransferSeq` | DL_Process | FB | 电镀线行车转序与槽位占用时序 | C4 | 族复杂件
40. `FB_DL_SortDiverterSeq` | DL_Algo | FB | 分拣分流器握手与故障恢复状态机 | C3 | 族复杂件

## 四、风格约束

- 简单件 20~50 行（含声明），复杂件 120~260 行。
- 每个 FC 至少 4 个输入 + 2 个输出；FB 至少 6 个输入 + 3 个输出 + 1 个 iErrCode。
- 物理量必须有单位注释，量纲必须自洽（例：mm/m 换算系数 0.001）。
- 变量名 PascalCase 局部 `_` 前缀，接口无前缀。