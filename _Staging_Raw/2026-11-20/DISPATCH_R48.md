# R48 派单书（一次性派发 PLC 编码专家 · 4 批 × 5 件 + 返修 1 件）

> 全局红线（每件必过，不逐节重复）：① 命名前缀 FB_DL_/FC_DL_/I_DL_ 与变量前缀 b/n/u/f/s/t/a/st/e/fb/i；② 零 GVL / VAR_EXTERNAL / %I %Q %M，外部数据全走引脚；③ 纯 IEC 61131-3 + Standard.library；④ ENUM+CASE 含 ELSE 兜底，TON/TOF/R_TRIG 段 0 无条件刷新；⑤ 防除零 / 数组边界 / 浮点禁 `=` 判等（ABS 差 < 1E-6）/ 非有限值拒算 / WHILE 计数防死锁；⑥ 100% 中文注释 + 头部七要素 + 全部物理量带单位；⑦ 无魔法数，阈值提为带单位输入或 VAR CONSTANT。
> 零码位范式（R46 延续）：出口 BOOL+ENUM，头注释写「码位待收口统一派号」，编码禁 16# 事件码（位掩码类常量除外且须声明非事件码）。
> 属主边界先行：每件头注释写死「只管 X / 不接管 Y」。

---

## 批 1（底层 / 纯函数前置）

### 1. FC_DL_SaturateSub ｜ DL_Base ｜ FC
- **类型/前缀**：FC，前缀 FC_DL_。
- **功能规格**：`FC_DL_SaturateSub(nMinuend : DINT; nSubtrahend : DINT; bOverflow : REFERENCE TO BOOL) : DINT`。`nResult := nMinuend - nSubtrahend`；若下溢（结果 < DINT#-2147483648）钳位返回 MIN 并 `bOverflow := TRUE`；上溢同理钳 MAX。正常域 `bOverflow := FALSE`。
- **边界安全**：溢出判定不得先算后判（中间值回绕不可观测）——用「被减数 < MIN + 减数」式跨域比较预判（DINT 域内安全式）；MIN_INT - (-1) 与 MAX_INT - 负数两边界向量必进验收。
- **依赖**：无（与既有 `FC_DL_SaturateAdd` 成对，**不复制其实现**，只对齐注释风格与引脚组织）。
- **来源标签**：`自研线（成对补口）`。
- **专属工程价值**：累加方向已有饱和保护、扣减方向（余料核销、步进回退计数）仍是裸减法回绕裸奔，成对补齐减法侧防回绕。

### 2. FC_DL_SimpsonQuad ｜ DL_MathData ｜ FC
- **类型/前缀**：FC。
- **功能规格**：`FC_DL_SimpsonQuad(aY : ARRAY[*] OF LREAL; fDx : LREAL; bValid : REFERENCE TO BOOL) : LREAL`。n+1 个等距节点（n 必须偶数）的复合辛普森 1/3 积分：`fI = fDx/3 · (aY[0] + 4·Σ奇 + 2·Σ偶 + aY[n])`。
- **边界安全**：节点数 <3 或 n 为奇数 → 拒算返回 0 并 `bValid := FALSE`（奇偶判据用 MOD 2，禁浮点）；`fDx <= 0` 拒算；逐点非有限值（`x <> x` 自不等口径，R245）前置剔除并整体拒算（部分积分结果不可信）；`fDx` 由调用方保证等距（IN 语义注释声明）。
- **依赖**：无。
- **来源标签**：`T2-1 LGF · Math 数学子族`（公开数学定义 clean-room）。
- **专属工程价值**：全库有求值/滤波/回归、无一次数值积分原语；功率-时间曲线求能、流量累计复核等场景缺此叶子件。

### 3. FC_DL_LagrangeInterp ｜ DL_MathData ｜ FC
- **类型/前缀**：FC。
- **功能规格**：`FC_DL_LagrangeInterp(aX : ARRAY[*] OF LREAL; aY : ARRAY[*] OF LREAL; fXq : LREAL; bValid : REFERENCE TO BOOL) : LREAL`。n 点（2≤n≤8，常量上限）拉格朗日基函数求 `fYq = Σ aY[i]·Π_{j≠i}(fXq-aX[j])/(aX[i]-aX[j])`。
- **边界安全**：两数组长度不一致拒算；查重节点（`ABS(aX[i]-aX[j]) < fNodeTol`，fNodeTol 提为 VAR CONSTANT）→ 分母趋零 → 拒算 `bValid := FALSE`（R28 浮点禁 `=`）；非有限输入拒算；n 超上限钳到上限并注释声明截断语义。
- **依赖**：无（与 `FC_DL_CubicSplineInterp` 分工声明：无样条连续性要求的小样本域，不复制样条实现）。
- **来源标签**：`T2-1 LGF · Math 数学子族`（公开数学定义 clean-room）。
- **专属工程价值**：传感器少量标定点（2~8 点）的非线性插值是现场高频刚需，样条件过重、分段线性件过粗，此粒度空缺。

### 4. FB_DL_ModeArbiter ｜ DL_Base ｜ FB
- **类型/前缀**：FB。
- **功能规格**：三源模式请求仲裁。输入 `bReqManual / bReqAuto / bReqRemote`（请求电平）+ `bActManual` 激活沿；输出 `eMode : E_DL_MarMode`（eNone/eManual/eAuto/eRemote）、`bChanged` 单拍、`bPreempted` 被抢占单拍。优先级 手动 > 自动 > 远程：高优先级请求出现即抢占（`bPreempted` 记录低级被顶）；高优先级撤销后**不自动回退**到低级（回退必须由低级请求重新沿触发 `bActManual` 类激活语义），防模式振荡。
- **状态机**：CASE eMode 四态 + ELSE 兜底拉回 eNone；请求沿 R_TRIG 段 0 无条件刷新。
- **边界安全**：多请求同拍 → 优先级裁决（电平取最高级，同拍置 bChanged）；全部撤销 → eNone（不记忆最后模式，HMI 语义由上层做）；与 `FB_DL_MutexOwnerAudit` 分工声明：运行模式 ≠ 互斥锁属主。
- **依赖**：无。
- **来源标签**：`自研线`。
- **专属工程价值**：每台设备手/自/远切换都在主程序里裸写 IF 链，抢占与回退语义各机各写、事故高发；本件固化「抢占不自动回退」一条铁律。

### 5. FB_DL_HoldRepeatButton ｜ DL_Base ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `bPress`（按钮）、`tDelayInitial : TIME`（首连发延迟）、`tRepeat : TIME`（重复周期）；输出 `bRepeatPulse`（重复脉冲单拍）、`bHolding`（长按中）、`nRepeats : UDINT`（累计连发次数，按住期间累加）。语义：按下即先出一次有效（复用输入本身或单拍，规格定为：按下沿 `bRepeatPulse` 单拍一次）；持续按住超过 tDelayInitial 后按 tRepeat 周期连发；松开立即停且计数冻结（不清零，清零由 `bReset` 引脚显式做）。
- **边界安全**：TON 两枚（tonDelay/tonRepeat）段 0 无条件刷新；`tRepeat` 下限闸（≤ T#0S 组态锁存 bError，防零周期连发打爆下游）；`nRepeats` 饱和不回绕。
- **依赖**：无（与 `FB_DL_MultiClickDetect` 分工声明：连发 ≠ 连击识别）。
- **来源标签**：`自研线`。
- **专属工程价值**：HMI 点动微调（步距设定、微调速度）连发逻辑每个画面裸写一遍，本件给出带防抖闸的统一原语。

---

## 批 2（中粒度 Algo / Device）

### 6. FB_DL_SensorFusion2 ｜ DL_Algo ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fMeasA / fMeasB : LREAL`（双传感器同物理量）、`bFreshA / bFreshB`（数据新鲜度）、`fTauVar : LREAL`（方差递推平滑系数，域 0~1，无量纲）；输出 `fFused : LREAL`、`fWeightA : LREAL`（0~1）、`bAgree : BOOL`（一致性）、`bValid : BOOL`。算法：各源在线递推噪声方差 `_fVarA/_fVarB := (1-fTauVar)·_fVar + fTauVar·(fMeas - _fMean)²`；权重 `fWeightA = (1/_fVarA) / ((1/_fVarA)+(1/_fVarB))`；`fFused = fWeightA·fMeasA + (1-fWeightA)·fMeasB`；一致性 `ABS(fMeasA-fMeasB) <= fDevMax`（fDevMax 输入引脚）。
- **边界安全**：单源失效（bFresh=FALSE）→ 全权重交给健康源（降级不拒算）；双源失效 → 冻结上次 fFused 且 bValid=FALSE；方差下限钳 `fVarMin`（VAR CONSTANT）防除零；非有限值当拍剔除（R245）；权重输出钳 [0,1]。
- **依赖**：无（与 `FB_DL_KalmanFilter1D` / `FB_DL_RedundantSwitch` 分工声明写入头注释）。
- **来源标签**：`自研线（公开加权融合公式）`。
- **专属工程价值**：双冗余传感器现场只有「二选一」件（RedundantSwitch），没有「都信、按噪声配权」件；温漂互补型双测（如 RTD+红外）可直接受益。

### 7. FB_DL_BiasAdaptiveTrim ｜ DL_Algo ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fErr : LREAL`（闭环残差）、`bInService`（投用）、`fKiTrim : LREAL`（修调积分增益，1/s）、`fBand : LREAL`（误差死区，工程单位）、`fLeak : LREAL`（带内泄漏系数，1/s）、`fTrimMin/fTrimMax : LREAL`（修调限幅）；输出 `fTrim : LREAL`、`bSatLim : BOOL`。算法：`ABS(fErr) > fBand` 时 `fTrim += fKiTrim·fErr·fCycle`（fCycle 用 `FB_DL_CycleTimeMeasure` 语义或输入周期引脚）；带内泄漏 `fTrim -= fLeak·fTrim·fCycle`；输出钳位并置 bSatLim。
- **边界安全**：bInService=FALSE 冻结不遗忘（退出即保持，防止重投扰动）；非有限 fErr 当拍跳过；fCycle ≤ 0 拒算用缺省周期；钳位后积分方向不改（防 windup 累积，AntiWindupLink 同族语义）。
- **依赖**：无（与 `FB_DL_Integrator` 分工：纯积分器无死区/泄漏/限幅闭环语义）。
- **来源标签**：`自研线`。
- **专属工程价值**：缓慢漂移型稳态偏差（换热器结垢、阀门磨损）用重调 PID 过重，本件给「外挂修调」轻量解，不动主回路整定。

### 8. FB_DL_FuzzyTrim2In ｜ DL_Algo ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fErr / fErrRate : LREAL`（已标幺 -1~1）、`fGainOut : LREAL`（修调输出增益）；输出 `fTrim : LREAL`（-fGainOut~+fGainOut）、`nRuleHit : UDINT`（命中规则数，诊断）。算法：两输入各 5 级隶属（NB/NS/Z/PS/PB，三角隶属度，中心点与半宽 VAR CONSTANT 可组态）；5×5=25 条规则表（ST_DL_ 常量数组），重心法解模糊：`fTrim = fGainOut·Σ(w_i·c_i)/Σw_i`（c_i 为单点输出集中心）。
- **边界安全**：输入先钳 [-1,1]；Σw_i 下限闸（< 1E-6 输出 0 并置 `bNoRule := TRUE`）；非有限输入 → 冻结输出；规则表越界访问钳位（数组边界红线）。
- **依赖**：无（建议表结构以 `ST_DL_` 类型落地，禁止内联 25 行 IF）。
- **来源标签**：`自研线（Mamdani 结构只借、T2-5 参数域只借）`。
- **专属工程价值**：非线性滞回对象（注塑保压、炉温搭接段）PID 补不动，模糊修调是业内成熟外挂；全库零模糊件，属真空白族开族。

### 9. FB_DL_Decouple2x2 ｜ DL_Algo ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fU1 / fU2 : LREAL`（两主控输出 0~100%）、`bEnable`；输出 `fU1Eff / fU2Eff : LREAL`（解耦后等效输出）、`bEnabled : BOOL`。算法：静态解耦网 `fU1Eff = fU1 + fD21·fU2`、`fU2Eff = fU2 + fD12·fU1`（fD12/fD21 = 组态解耦系数 = Δu_i 对 j 回路的静态影响比，无量纲）；T21/T22 相对增益只作组态参考写入注释（`fD12 ≈ -K12/K11` 公式给现场整定者）。
- **边界安全**：`bEnable=FALSE` 直通（fU1Eff:=fU1）；输出钳 [0,100%]；非有限直通拒改；解耦系数域闸（|fD|>1 锁存 `bCfgBad`，反向主导说明组态颠倒）。
- **依赖**：无（与 `FB_DL_CascadePid` 分工：解耦网 ≠ 串级）。
- **来源标签**：`自研线（公开 Bristol RGA 公式）`。
- **专属工程价值**：双回路强耦合（炉温-气氛、液位-压力）现场最怕「两个 PID 互相打架」，全库无解耦网件，此件补 Algo 控制结构族最后一块常见结构。

### 10. FB_DL_SolenoidCoilHealth ｜ DL_Device ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fCurrentA : LREAL`（线圈电流 A）、`bEnergized`、`tWindow : TIME`（判据窗）、`fPickMaxA/fPickMinA : LREAL`（吸合峰值窗）、`fHoldPct : LREAL`（保持电流容差 %）；输出 `eCoil : E_DL_SchHealth`（eOk/eUnderCurrent/eOverCurrent/eStuckPeak/eNoData）、`fPickPeakA : LREAL`、`bError : BOOL`。算法：吸合沿（bEnergized 上升沿）后 tWindow 内捕获峰值电流，判吸合窗；随后进入保持段，保持电流对基线偏差超 fHoldPct 判欠流（断匝趋势）/超流（短路匝趋势）。
- **边界安全**：电流 ≤0 且 bEnergized=TRUE 持续 tWindow → eNoData（传感器断线，不与欠流混码，R190 成因分码）；非有限剔除；峰值窗 TON 段 0 无条件刷新；基线学习需 n≥3 次合格吸合才生效（不足拒判）。
- **依赖**：无（与 `FB_DL_ContactorWeldDetect` / `FB_DL_SingleSolenoidCyl` 分工声明：电气健康 ≠ 触点熔焊 ≠ 通断驱动）。
- **来源标签**：`T2-6 Rockwell AOI · 设备诊断粒度（只借分类）`。
- **专属工程价值**：阀岛电磁阀「吸不动/吸不牢」占现场故障大头，诊断粒度（吸合窗/保持段分域）只有 Rockwell AOI 有先例，本件补 Device 电气诊断族。

---

## 批 3（重型 Algo / Device / Motion）

### 11. FB_DL_HeaterBreakDetect ｜ DL_Device ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `bHeaterOn`、`fCurrentA : LREAL`、`fTempC : LREAL`（被加热体温度 ℃）、`fCurRefA : LREAL`（额定电流基线 A）、`fTempRiseMin : LREAL`（判据二最小温升 ℃/min）、`tWatch : TIME`；输出 `eHeat : E_DL_HbdState`（eOk/eCurLow/eNoTempRise/eBreakConfirm/eOff）、`bError`。算法：判据一（通电 tWatch 内电流对基线偏差 < -fCurDevPct%）判 eCurLow；判据二（通电且电流正常但温升速率 < fTempRiseMin 持续 tTempWatch）判 eNoTempRise；两判据同时成立 → eBreakConfirm 锁存。
- **边界安全**：非通电相全判据冻结回 eOff；温升速率分母时间闸；非有限剔除；判据二仅在判据一存疑（电流略低未达阈值）时介入，降低散热误报；SCR 调功类供电（电流与功率非线性）须由组态输入 `bPhaseAngle` 声明，该模式下判据一自动降级只信判据二。
- **依赖**：无（与 `FB_DL_SsrHeaterDrive`/`FB_DL_HeaterSsrBank` 分工：诊断 ≠ 驱动）。
- **来源标签**：`T2-6 Rockwell AOI · 设备诊断粒度（只借分类）`。
- **专属工程价值**：断棒检测双判据（电+温）是行业标准做法，但判据间的介入次序决定误报率；本件把「温升只在电流存疑时介入」的次序纪律固化成件。

### 12. FB_DL_VibZoneClassify ｜ DL_Device ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fVibMmS : LREAL`（10~1000Hz RMS 振动速度 mm/s）、`eClass : E_DL_VibClass`（机组等级：Ⅰ小型/Ⅱ中型/Ⅲ大型刚性/Ⅳ大型挠性）、`fHystPct : LREAL`（区间迟滞 %）；输出 `eZone : E_DL_VibZone`（eA良好/eB可接受/eC不合格/eD危险）、`bZoneChanged` 单拍、`bError`。算法：按 ISO 10816-3 四等级 × 四区限值表（ST_DL_ 常量二维数组，mm/s）分区；区间跃迁带 fHystPct 迟滞防临界抖动。
- **边界安全**：限值表内嵌为常量并逐行注释单位（mm/s）与出处行（ISO 10816-3 表），禁散落魔法数；fVib ≤0 或非有限 → 冻结上次 eZone 置 bError；等级枚举越界（ELSE）回 eB 安全侧并报组态错。
- **依赖**：无。
- **来源标签**：`T2-8 ISO 10816-3 公开分区（只借分区事实，无文本复制）`。
- **专属工程价值**：泵/风机/电机状态巡检分区判据目前散在各工艺件里各写一套，本件一次固化、多机复用，且与 RobotArmVibrationWatch（机械臂专项）分域不冲突。

### 13. FB_DL_GapForceSwitchover ｜ DL_Algo ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fPosMm / fVelMmS : LREAL`（轴位姿）、`fForceN : LREAL`（力/压力传感器 N）、`fContactN : LREAL`（接触判据 N）、`fGapTargetMm : LREAL`（目标间隙 mm）、`fForceTargetN : LREAL`（压力段目标 N）、`tContactTmo : TIME`；输出 `eMode : E_DL_GfsMode`（eIdle/eApproach/eContact/eForceCtl/eFault）、`fCmdTrim : LREAL`（对位置环的速度/位置修调输出）、`fForceTrimPct : LREAL`（对压力环输出 %）、`bError`。算法：eApproach 用位置控趋近 fGapTargetMm；`fForceN >= fContactN` 判接触 → eContact 冻结当时速度/输出作为衔接保持值；随后切 eForceCtl 力控（力偏差 → fForceTrimPct）；tContactTmo 内未判接触 → eFault（eCause=eNoContact）。
- **状态机**：五态 CASE + ELSE 兜底 eFault；切换判据浮点容差（ABS 差）；eContact 为单过渡态（保持一个保持窗 tHoldXf 后必迁出，禁驻留 R285）。
- **边界安全**：力传感器非有限/超量程 → eFault（成因分码 eForceBad）；切换点速度不得突跳（衔接保持值显式写出）；复位沿清状态与保持值（R311 预防）；判接触用迟滞（fContactN ± 迟滞带）防临界振荡。
- **依赖**：组合调用（不复制）：`FB_DL_RateLimiter` 可由上层用于修调限速，本件不内嵌。
- **来源标签**：`T2-2 LBP · 压机工艺分类（只借分类）`。
- **专属工程价值**：压装/贴合/研抛类工步「位置控进、压力控做」切换无扰性是良率核心，全库只有测量件与趋势件、无切换闭环件，本件开此结构族。

### 14. FB_DL_LoadShareDroop ｜ DL_Motion ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fVrefMmS : LREAL`（速度基准）、`aLoadPct : ARRAY[1..nAxMax] OF LREAL`（各轴负载 %，nAxMax=4 常量）、`bAxActive : ARRAY[1..nAxMax] OF BOOL`、`fDroopPct : LREAL`（调差率 %/(100%负载)）、`fShareBandPct : LREAL`（均衡目标带 %）；输出 `aVoutMmS : ARRAY[1..nAxMax] OF LREAL`、`bBalanced : BOOL`。算法：`aVout[i] = fVref·(1 - fDroopPct·(aLoad[i]-fLoadAvg)/100)`（负载高于均值者减速让载）；均衡带内不修正（死区防振荡）。
- **边界安全**：数组边界逐轴钳位；非负载轴（bAxActive=FALSE）输出直通不修正；均值只对有效轴计算（全轴失效 → 直通并置 `bNoLoad := TRUE`）；输出钳 ±fVrefMax。
- **依赖**：无（与 `FB_DL_GantrySyncAxis` 分工声明：负载均衡 ≠ 几何同步；与 `FB_DL_GantrySkewMonitor` 分工：修调 ≠ 监视）。
- **来源标签**：`T1-6 PLCopen MC 语义（只借语义）`。
- **专属工程价值**：双机头/多辊同步驱动「一根轴吃载发热、另一根空载」是传动现场顽疾，droop 调差是成熟解但全库零件。

### 15. FB_DL_ZoneSpeedTrim ｜ DL_Motion ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fPosMm : LREAL`（轴实际位置 mm）、`aZone : ARRAY[1..nZoneMax] OF ST_DL_ZoneSpeed`（区段表：fStartMm/fEndMm/fVmaxMmS）、`fVDefaultMmS : LREAL`（表外默认限速）、`fVoutMmS : LREAL`（当前指令速度 mm/s）；输出 `fVCmdMmS : LREAL`（限幅后指令）、`eCurZone : UDINT`（当前命中区段号，0=表外）、`bCapped : BOOL`。算法：位置命中区段 → `fVCmd = MIN(fVout, fVmaxZone)`；未命中 → MIN(fVout, fVDefault)。
- **边界安全**：区段表重叠/倒序逐条校验锁存 `bCfgBad`（表非法比静默错限速危险）；fStart≤fEnd 判据禁浮点 `=`；表满 nZoneMax 钳位；非有限位置 → 冻结上次输出并 bError。
- **依赖**：无（与 `FB_DL_SoftLimitGuard` 分工：动态限速 ≠ 静态软限位报警）。
- **来源标签**：`T1-6 PLCopen MC 语义（只借语义）`。
- **专属工程价值**：机械臂/桁架按区段差异化限速（近人区、近件区、换向区）安全规范高频要求，目前只能在主程序裸写 IF 链，本件给区段表化原语。

---

## 批 4（组合型 / 工艺顺控）

### 16. FB_DL_ContourCrossCouple ｜ DL_Motion ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `fErrX / fErrY : LREAL`（两轴跟随误差 mm）、`fKc : LREAL`（交叉耦合增益，无量纲，0~1）、`bEnable`；输出 `fTrimX / fTrimY : LREAL`（修调注入 mm，注入到从轴位置指令）。算法：轮廓误差 `fEc = (fErrX·fDirX + fErrY·fDirY)/SQRT(fDirX²+fDirY²)`（fDirX/fDirY 轨迹方向单位向量，组态输入或由相邻段自动取）；修调 `fTrimY = fKc·fEc·fDirX`、`fTrimX = -fKc·fEc·fDirY`（把轮廓误差垂直分量还给弱轴）。
- **边界安全**：方向向量模 < 1E-6 → 直通零修调并 `bNoDir := TRUE`（R28 防零）；修调输出限幅 fTrimMaxMm；非有限误差冻结；bEnable 退出时修调斜坡归零（禁突跳）。
- **依赖**：无（与 `FB_DL_GantrySkewMonitor` 分工声明：闭环修调 ≠ 偏差监视）。
- **来源标签**：`T1-6 PLCopen MC 语义（只借语义）`。
- **专属工程价值**：轮廓度是双轴联动机（激光切割、涂胶）核心指标，交叉耦合控制是该指标的标准解法，全库只有监视无闭环，本件补齐闭环侧。

### 17. FB_DL_LookaheadVelPlanner ｜ DL_Motion ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `aSeg : ARRAY[1..nSegMax] OF ST_DL_SegGeom`（段几何：fLenMm、fCornerRad、fVmaxMmS、fAccelMmS2）、`nSegCount : UDINT`、`nLookahead : UDINT`（前瞻深度）、`fVtrajMmS : LREAL`（轨迹目标速度）；输出 `aVelCapMmS : ARRAY[1..nSegMax] OF LREAL`（各段允许速度上限）、`bPlanned : BOOL`、`bCfgBad : BOOL`。算法：① 拐角限速 `fVcorner = SQRT(fAccel·fCornerRad)`（向心加速度 ≤ fAccel 推导式）；② 自深至浅回溯：`aVelCap[i]² = MIN(aVelCap[i]², aVelCap[i+1]² + 2·fAccel·fLen[i+1])`（减速可达性反推）；③ 前向传播可达上限。输出即段速度上限表，供段执行器逐段限速。
- **边界安全**：`nSegCount=0` 或超 nSegMax 钳位报组态；fLen/fAccel ≤0 段拒算锁存 bCfgBad（零长度段除零隐患前置）；SQRT 前判负（累加式可能为负需钳 0 后再开方）；WHILE 回溯带步数计数防死锁。
- **依赖**：无（与 `FB_DL_SCurveGenerator` 分工：段间衔接规划 ≠ 单段成形；与 `FB_DL_MotionCmdQueue` 分工：几何规划 ≠ 指令排队）。
- **来源标签**：`T1-6 PLCopen MC 语义（只借语义）`。
- **专属工程价值**：多段路径「每段都从零加速到满速」是自制非标机节拍差的主因，前瞻规划是唯一解但实现门槛高；本件把回溯-前传两遍法固化为可复用件。

### 18. FB_DL_AutoclaveSterilSeq ｜ DL_Process ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `bStart / bStop / bReset`、`fPrKpa / fTempC : LREAL`（釜压 kPa / 腔温 ℃）、`fPrSetKpa / fTempSetC : LREAL`（灭菌设定）、`tSteril : TIME`（保压灭菌时长）、`nPulseCnt : UDINT`（脉动置换次数）、`fF0Min : LREAL`（F0 灭菌值目标 min）、`fF0Rate : LREAL`（F0 累计速率系数，min/min，组态）；输出 `ePhase : E_DL_AcsPhase`（eIdle/ePulse/eHeatUp/eSteril/eExhaustDry/eDone/eFault）、`fF0AccMin : LREAL`（F0 累计输出）、相指示 BOOL 组、`eCause`、`bError`。算法：ePulse 重复「抽真空-进蒸汽」nPulseCnt 次（置换）；eHeatUp 升温到 fTempSetC；eSteril 保压保温且 `fF0Acc += fF0Rate·fCycle/60`，`fF0Acc >= fF0Min ∧ tonSteril.Q ∧ 温压在带内` 才过相；eExhaustDry 排气干燥回 eDone。
- **状态机**：七态 CASE + ELSE 兜底 eFault；段间 TON 各自专用（R228A 命名豁免式）；eCause 分码：eNoPr（升不起压）/eNoTemp/eSterilBand（带外跌出）/eCfgIllegal。
- **边界安全**：F0 累计带内才累加、带外冻结不倒扣（保守侧）；nPulseCnt=0 组态闸锁存；温压非有限 → eFault（eCause=eNoTemp 分码）；bStop 任一相回 eIdle 不记故障；复位沿清全部锁存（R311）；过相判据禁浮点 `=`。
- **依赖**：组合调用（不复制）：温度带判定语义同 `FB_DL_ToleranceWindow` 思想，但本件自带实现不引用（Level 2 依赖 Level 0 类型可引用，规格定为**不内嵌引用**，独立验收）。
- **来源标签**：`T2-2 LBP 工艺分层（只借分类）`。
- **专属工程价值**：灭菌釜 F0 值累计闸是 GMP 合规刚需（光时间不足），全库消毒类零件，本件开制药/食品工艺族首件。

### 19. FB_DL_TunnelPasteurizerSeq ｜ DL_Process ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `bStart/bStop/bReset`、`fTempPau/fTempCoo : LREAL`（杀菌区/冷却区实测 ℃）、`fTempPauSetC : LREAL`（杀菌设定 ℃）、`fBandC : LREAL`（杀菌温度带半宽 ℃）、`tPauMin : TIME`（杀菌段最短驻留）、`fVconvMmS : LREAL`（网链速度 mm/s）、`bBottleIn / bBottleOut`（进出口光电）；输出 `ePhase : E_DL_TpsPhase`（eIdle/ePreheat/ePau/eCool/eDone/eFault）、`bPauInBand : BOOL`、`eCause`、`bError`。算法：ePau 段要求 `ABS(fTempPau - fTempPauSetC) <= fBandC` 且 tPauMin 驻留到时才放行 eCool；eCool 段出口温降联锁（fTempCoo > fCoolMaxC 时禁 bDone，防烫瓶）；进瓶无料（bBottleIn 长假）挂起不故障。
- **边界安全**：TON 段 0 无条件刷新；fBandC ≤0 组态闸；温度非有限 → eFault 分码 eNoData；带外跌出 → 不退出 ePau 而冻结驻留计时（保守侧，TON IN 表达式派生）+ 记 `eCause=eBandOut`；复位沿全清。
- **依赖**：无。
- **来源标签**：`T2-2 LBP 工艺分层（只借分类）`。
- **专属工程价值**：饮料/食品隧道巴杀「温度带驻留 + 出口温降」双联锁是产品保质期合规点，目前此类多温区段序只有干燥/烧成先例、无巴杀族。

### 20. FB_DL_PumpPrimingSeq ｜ DL_Process ｜ FB
- **类型/前缀**：FB。
- **功能规格**：输入 `bStart/bStop/bReset`、`fPrOutKpa : LREAL`（泵出口压力 kPa）、`fPrPrimeKpa : LREAL`（引水成功判据 kPa）、`bFillValveFb / bVentValveFb : BOOL`（灌液/排气阀反馈）、`tFill : TIME`、`tVent : TIME`、`nRetryMax : UDINT`；输出 `ePhase : E_DL_PpsPhase`（eIdle/eFill/eVent/eConfirm/eRunning/eDone/eFault）、`nRetries : UDINT`、`eCause`、`bError`。算法：eFill 开灌液阀 tFill 到时判反馈；eVent 开排气阀 tVent 到时关；eConfirm 判 `fPrOutKpa >= fPrPrimeKpa` → eRunning（转主运，本件只出态不接管泵启停）；eConfirm 失败 → nRetries+1 回 eFill，nRetries > nRetryMax → eFault（eCause=eNoPrime）。
- **边界安全**：阀反馈超时各自 TON 段 0 刷新、分码 eFbFill/eFbVent（R190）；fPrPrimeKpa ≤0 组态闸；压力非有限 → eFault eNoData；nRetryMax=0 允许（一次不过即故障，合法组态）；bStop/eFault 复位沿全清 nRetries；属主边界写死：只管引水时序，不接管泵本体启停与保护（保护归 PumpDryRunGuard 族）。
- **依赖**：无。
- **来源标签**：`T2-2 LBP 工艺分层（只借分类）`。
- **专属工程价值**：离心泵无自吸需引水，引水失败重试上限与阀反馈分码是现场必须但各写各的，本件固化为通用启动序原语；与 PumpChangeoverSeq（主备切换）/PumpDryRunGuard（干转保护）三分域各管一段。

---

## 附：返修派单（第 21 项，先做）

### 21. FB_DL_ModulePottingVac ｜ DL_Process ｜ FB ｜ v1.0.0 → v1.0.1（引脚契约零变更）
- **缺陷**（R47 终审 5 抽轻项）：`bVacReached`/`bBreakDone` 为短脉冲时先于超时 TON 到 Q 前消失，过相判据 `tonEvacTo.Q AND bVacReached` 恒假 → 到位发生过仍误报超时，且脉冲不重现必复锁。
- **修法四要点**：① 段 0 增 `rtVacIn`/`rtBreakIn` R_TRIG（无条件刷新）+ `_bVacSeen`/`_bBreakSeen` 锁存，进相清、捕获沿置位；② 过相判据改 `tonEvacTo.Q AND _bVacSeen`，超时判据改 `tonEvacTo.Q AND (NOT _bVacSeen)`，破空相同理；持续到位信号行为不变（契约兼容）；③ 迁出链（rtReset.Q / bStop）同时清两锁存量（R310/R311 预防）；④ 头注释补边界⑥「到位沿锁存语义」+ 修订历史 v1.0.1；**零引脚增删改**。验收向量：V1 脉冲到位+超时到 → 过相不误报；V2 中止/复位重启无残留锁存；V3 持续到位仍等满超时窗。
