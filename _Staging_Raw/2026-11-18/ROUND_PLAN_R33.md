# R33 轮计划（阶段一锁定稿）

- 日期：2026-11-18 ｜ 候选池：193 条（主控已去重）｜ 本轮目标：20 件（常态回归）
- 本轮排除项：上轮欠账 3 件（FB_DL_BlindPositionCtrl / FB_DL_CompressorFleetStaging / FB_DL_WaferThermalBudgetAccum，主控另行处理）；池内第 163 行 FB_DL_ChwDifferentialPressureReset 已被 R30 并案，不选。
- 配额统计：DL_Process 10 / DL_Device 5 / DL_Algo 2 / DL_MathData 2 / DL_Motion 1，覆盖 5 个子库（池内无 DL_Base 与 FC 前缀候选，按"宁少勿滥"下调，不硬凑）。
- T2 借鉴族 4 件 ≥ 1 ✓：t2-lgf ×1、t2-isa88 ×1、t2-isa182 ×1、t2-ne107 ×1。
- FC 件数：0（池内无 FC 候选；单位换算价值由 2 件 MathData FB 承载）。

## 20 件清单

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次(1-4) |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_SlurryViscosityComp | DL_MathData | FB | 浆料粘度温度补偿换算（温-粘标定曲线，输出补偿后粘度） | 原生 | 2 | 1 |
| 2 | FB_DL_ShrinkFilmUsageCalc | DL_MathData | FB | 收缩膜单包耗量换算与成本核算（膜长→重量折算 + 产量口径对齐） | 原生 | 3 | 1 |
| 3 | FB_DL_TrackerSolarAngle | DL_Algo | FB | 跟踪支架太阳角计算（时角/赤纬/高度角，含逆跟踪防阴影角度限幅） | 原生 | 3 | 1 |
| 4 | FB_DL_FanBeltSlipDetect | DL_Device | FB | 风机皮带打滑判据（转速-频率偏差速率 + 维护提醒） | 原生 | 4 | 1 |
| 5 | FB_DL_UnlockHoldTimeout | DL_Device | FB | 安全门 eUnlocked 保持超时监视（解锁有效但门未开 → 电磁铁/机械卡滞提示，终审立项） | 终审立项 | 4 | 1 |
| 6 | FB_DL_VacuumPumpBasePress | DL_Device | FB | 真空泵本底压强与恢复时间台账（压强平滑 + 恢复超时计数） | 原生 | 4 | 2 |
| 7 | FB_DL_InverterDeratingCtrl | DL_Device | FB | 逆变器温度/电压分段降额与功率限值（降额状态机 + 原因上报） | t2-ne107 | 5 | 2 |
| 8 | FB_DL_PrecursorCanisterWeight | DL_Device | FB | 前驱体源瓶称重余量预测（消耗速率积分 + 换瓶参数核对） | 原生 | 5 | 2 |
| 9 | FB_DL_ChillerLiftOptimize | DL_Process | FB | 冷机 Lift（冷凝-蒸发温差）优化限值（温差基线 + 设定值限速） | 原生 | 5 | 2 |
| 10 | FB_DL_CoolingTowerOpt | DL_Algo | FB | 冷却塔群控逼近度优化（湿球逼近度控制律 + 塔群投切决策） | 原生 | 6 | 2 |
| 11 | FB_DL_FreezeStatGuard | DL_Process | FB | 表冷器防冻保护与低温联锁（低温门限 + 预热阀调节 + 冻结告警） | 原生 | 5 | 3 |
| 12 | FB_DL_StackPressureProfile | DL_Process | FB | 叠片压力曲线与保压判定（压力段轮廓 + 保压窗 + 越窗分级） | 原生 | 5 | 3 |
| 13 | FB_DL_PilePressLimitClass | DL_Process | FB | 堆叠压力四档分级与 NG 分道（压力归类 + 分道放行） | 原生 | 5 | 3 |
| 14 | FB_DL_PressFitCurveArchive | DL_Process | FB | 压装曲线特征点归档与批次追溯（四特征点 + 曲线缓存按批次号索引） | 原生 | 6 | 3 |
| 15 | FB_DL_FilmTaperTension | DL_Motion | FB | 薄膜锥度张力给定曲线（卷径计算 + 锥度给定 + 收卷闭环） | 原生 | 6 | 3 |
| 16 | FB_DL_CartonScannerSort | DL_Process | FB | 纸箱扫码分道（读码 + 分道放行调度，P0） | 原生 | 6 | 4 |
| 17 | FB_DL_PigLauncherSeq | DL_Process | FB | 清管器收发球筒顺控（发球-跟踪-接收联锁状态机） | t2-lgf | 6 | 4 |
| 18 | FB_DL_FormationTempRiseRate | DL_Process | FB | 化成温升速率监视与异常电芯截断（速率微分 + 工艺窗 + 分级报警） | 原生 | 6 | 4 |
| 19 | FB_DL_RollChangeoverSeq | DL_Process | FB | 换卷换规格一键切换顺控（张力回零 + 参数配方合法性校验） | t2-isa88 | 7 | 4 |
| 20 | FB_DL_AndonLinePack | DL_Process | FB | 包装线安灯分级呼叫与响应报表（仲裁锁存 + 分段计时 + 台账） | t2-isa182 | 7 | 4 |

## 码位分配

- DL_MathData / DL_Algo 窗口 `16#02_3_5C` 起顺延；DL_Device `16#03_1_01` 起；DL_Motion `16#04_0_6C` 起；DL_Process `16#06_0_37` 起顺延（窗口余量充足，无需转 `16#05_0_C6`）。

| 名称 | 码位 |
|---|---|
| FB_DL_SlurryViscosityComp | 16#02_3_5C |
| FB_DL_ShrinkFilmUsageCalc | 16#02_3_5D |
| FB_DL_TrackerSolarAngle | 16#02_3_5E |
| FB_DL_FanBeltSlipDetect | 16#03_1_01 |
| FB_DL_UnlockHoldTimeout | 16#03_1_02 |
| FB_DL_VacuumPumpBasePress | 16#03_1_03 |
| FB_DL_InverterDeratingCtrl | 16#03_1_04 |
| FB_DL_PrecursorCanisterWeight | 16#03_1_05 |
| FB_DL_ChillerLiftOptimize | 16#06_0_37 |
| FB_DL_CoolingTowerOpt | 16#02_3_5F |
| FB_DL_FreezeStatGuard | 16#06_0_38 |
| FB_DL_StackPressureProfile | 16#06_0_39 |
| FB_DL_PilePressLimitClass | 16#06_0_3A |
| FB_DL_PressFitCurveArchive | 16#06_0_3B |
| FB_DL_FilmTaperTension | 16#04_0_6C |
| FB_DL_CartonScannerSort | 16#06_0_3C |
| FB_DL_PigLauncherSeq | 16#06_0_3D |
| FB_DL_FormationTempRiseRate | 16#06_0_3E |
| FB_DL_RollChangeoverSeq | 16#06_0_3F |
| FB_DL_AndonLinePack | 16#06_0_40 |

## 批次派单要点

### 批 1（独立计算与轻量诊断件）
- 温-粘/膜长换算曲线必须走查表插值，禁止 IF-ELSE 阶梯硬编码；插值端点钳制并标注单位（mPa·s / m / g）。
- 太阳角计算的赤纬/时角公式输入为弧度，接口注释必须声明角度单位约定；逆跟踪角度限幅防除零与 ±90° 越界。
- 诊断件（打滑/解锁超时）的 TON 实例必须每拍无条件刷新且 `IN := NOT ton.Q` 自复位；超时时间提为带 ms 单位的输入引脚，禁魔法数。
- UnlockHoldTimeout 不得侵入 `FB_DL_GuardLockDoor` 内部状态，只消费其对外输出引脚；故障提示允许自清（非锁存），锁存解除式必须可达。

### 批 2（单设备策略与优化件）
- 本底压强台账件：MovingAverage 采样窗与恢复计时窗分离；恢复超时计数用事件沿触发，禁止电平重复累加。
- InverterDeratingCtrl 是本轮唯一 NE107 四态族件：降额状态机用 ENUM + CASE 且必带 ELSE 回 Normal 降级路径；降额原因枚举与 `_eState` 分离，不得复用同一枚举。
- 源瓶余量预测的消耗速率积分必须防除零（时间为 0 时速率取上次有效值）；换瓶 tare 时清积分器但要留痕。
- ChillerLiftOptimize / CoolingTowerOpt 的设定值输出必须过 RateLimiter 限速；逼近度/温差基线统计窗未满时输出冻结在当前值并置 bBaselineReady=FALSE。

### 批 3（压力/温度工艺窗口件）
- 压力曲线件统一复用 `FB_DL_RampSoakProfile` 段轮廓骨架；保压窗判定用 `FB_DL_ToleranceWindow`，越窗报警经 `FB_DL_AlarmManager` 分级，禁止裸比较直出报警。
- 压力单位统一 kN / bar 并在注释标注；位移单位 mm；四档分级用 `FC_DL_LimitClassify`，档位边界常量提为带单位常量组。
- PressFitCurveArchive 的曲线缓存用环形缓冲按批次号索引，批次号越界必须防御；归档触发用 R_TRIG 沿。
- FilmTaperTension：卷径最小值防御（防除零），锥度系数为 0 时退化为恒张力；与 `FB_DL_WindingTensionCtrl` 的握手用 VAR_IN_OUT。

### 批 4（多件复合顺控与报表件）
- 顺控件（扫码分道/收发球筒/换卷）统一复用 `FB_DL_StepSequencer` + `FB_DL_InterlockMatrix`；每步超时提为引脚，步进 CASE 必带 ELSE 安全步。
- CartonScannerSort 分道放行必须与 `FB_DL_ConveyorZone` 段间握手，防止追尾；读码失败走旁路 NG 道而非堵线。
- RollChangeoverSeq 的配方合法性校验失败必须拒绝启动并给出首个失败项索引；张力回零完成判据带超时，不得无限等待。
- AndonLinePack 分段计时（呼叫→应答→解除）各自独立 TON，禁止共用实例；仲裁锁存沿用 `FB_DL_AndonCallSystem` 语义，报表分档用 `FB_DL_RuntimeMeter` + 班次窗口。
- 温升速率件（FormationTempRiseRate）的 Differentiator 前置平滑必须够，防单拍毛刺误截断；截断动作与报警分离，截断允许手动复位。

## 三个最高风险件（总监预判）

1. **FB_DL_AndonLinePack**：多源并发呼叫仲裁 + 三段计时 + 报表口径三重耦合，竞态与口径漂移风险最高，终审重点查锁存解除式。
2. **FB_DL_RollChangeoverSeq**：跨系统配方切换，参数校验失败路径多，张力回零与安全联锁的时序交错易出死锁。
3. **FB_DL_CoolingTowerOpt**：群控投切控制律（非简单 PID），塔群最小开机数/防震荡死区若缺失会频繁投切损坏设备。
