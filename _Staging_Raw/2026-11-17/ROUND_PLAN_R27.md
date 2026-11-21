# ROUND_PLAN_R27（阶段一+二：规划与锁定 20 个目标）

## 0 盘点（2026-11-17）
总库 464/10,000；今日 80/200；距 500 差 36；registry v2.15.0（Base 74/MathData 156/Algo 49/Device 83/Motion 40/Process 62）。本轮 20 件 × 5 码槽，WebSearch 0 次（复用 SOURCE_HUNTING_MATRIX 既有条目 + 公开标准语义）。

## 1 目标总表（20 行）
| 序号 | 组件名 | 分类 | 前缀 | POU类型 | 一句话功能 | 来源标签 | 复杂度 | 码位(5槽) | 批次 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_OrificeFlowCalc | DL_MathData | FC | 函数 | 孔板差压流量计算（温压补偿+开方+量程换算一体） | roadmap-L845 / T0 | 3 | 16#0001_0471~0475 | 1 |
| 2 | FC_DL_WaferCountYield | DL_MathData | FC | 函数 | 晶圆投入/产出/返工三计数→良率与损失分档 | roadmap-L712 / T0 | 2 | 16#0001_0476~047A | 1 |
| 3 | FC_DL_GasFlowSqrt | DL_Algo | FC | 函数 | 特气差压流量开方换算（委托 NthRoot+FlowCompensate+钳位） | roadmap-L645 / T0 | 2 | 16#0002_3706~370A | 1 |
| 4 | FC_DL_AirDensityFanPower | DL_Algo | FC | 函数 | 风机功率空气密度修正（委托 AirDensity+LinearScale） | roadmap-L660 / T0 | 2 | 16#0002_370B~370F | 1 |
| 5 | FB_DL_LoopWaveInject | DL_Algo | FB | 功能块 | 回路调试波形注入（正弦/方波可选，斜率保护） | roadmap-L672 / T0 | 3 | 16#0002_3710~3714 | 1 |
| 6 | FB_DL_FanArrayStageCtrl | DL_Device | FB | 功能块 | 风机阵列 N+1 分级启停与轮值均衡 | roadmap-L302 / T1-5 | 4 | 16#0003_038E~0392 | 2 |
| 7 | FB_DL_FrostProtectFreeze | DL_Device | FB | 功能块 | 防冻保护（低温断路器联动新风阀/盘管阀） | roadmap-L298 / T1-2 | 3 | 16#0003_0393~0397 | 2 |
| 8 | FB_DL_MfcFlowCtrl | DL_Device | FB | 功能块 | MFC 设定-回读校验（斜率/超调/稳定判据） | roadmap-L249 / T1-5 | 4 | 16#0003_0398~039C | 2 |
| 9 | FB_DL_DateCoderSync | DL_Device | FB | 功能块 | 喷码打码同步（编码器分频+字符间距偏移补偿） | roadmap-L281 / T1-5 | 3 | 16#0003_039D~03A1 | 2 |
| 10 | FB_DL_SealIntegrityMonitor | DL_Device | FB | 功能块 | 封口完整性监视（温度/压力/时间三参数趋势窗） | roadmap-L277 / T2-8 | 3 | 16#0003_03A2~03A6 | 2 |
| 11 | FB_DL_UnwinderDiameterCalc | DL_Motion | FB | 功能块 | 放卷卷径实时估算（膜厚层数积分递推） | roadmap-L279 / 自研 | 3 | 16#0004_0318~031C | 3 |
| 12 | FB_DL_StringCutAlign | DL_Motion | FB | 功能块 | 串焊裁切对位（相机偏差→切割轴微调） | roadmap-L242 / T1-6 | 4 | 16#0004_031D~0321 | 3 |
| 13 | FB_DL_StepperZLiftMicron | DL_Motion | FB | 功能块 | Z 轴微米级步进升降（细分当量组态+软限位拦截） | roadmap-L563 / T1-8 | 3 | 16#0004_0322~0326 | 3 |
| 14 | FB_DL_FillWeightCtrl | DL_Process | FB | 功能块 | 灌装净重闭环（快/细灌两段+落差提前量自学习） | roadmap-L274 / 自研 | 4 | 16#0005_0412~0416 | 3 |
| 15 | FB_DL_VffsBagLength | DL_Process | FB | 功能块 | 立式制袋袋长控制（色标同步+切刀相位对齐） | roadmap-L275 / T2-7 | 4 | 16#0005_0417~041B | 3 |
| 16 | FB_DL_CartonErectSeq | DL_Process | FB | 功能块 | 开箱机顺控（吸箱→成型→折底→输送，含卡箱检测） | roadmap-L270 / 自研 | 3 | 16#0005_041C~0420 | 4 |
| 17 | FB_DL_LoadPortSeq | DL_Process | FB | 功能块 | LoadPort 载具对接与 Wafer Map 校验顺控 | roadmap-L261 / T2-8 | 5 | 16#0005_0421~0425 | 4 |
| 18 | FB_DL_PumpChangeoverSeq | DL_Process | FB | 功能块 | 冷冻/冷却水泵加减机与温差优化 | roadmap-L296 / T1-2 | 4 | 16#0005_0426~042A | 4 |
| 19 | FB_DL_MachineGuardAudit | DL_Process | FB | 功能块 | 防护门开启审计与批次锁定（PackML Holding/Held 联动） | roadmap-L282 / T2-7 | 3 | 16#0005_042B~042F | 4 |
| 20 | FB_DL_SplicerAutoJoint(v1.1.0) | DL_Process | FB | 功能块 | 欠账收口：eSyncWait 增 tSyncMax 超时（ROADMAP §24.1 P0） | roadmap-§24.1 | 2 | 16#0005_0430~0434 | 4 |

T2 族配额：序 19 借 T2-7 PackML Holding/Held 语义（clean-room）；序 10 借 T2-8 ISA-88 参数窗语义。配额满足。

## 2 组件规格（每件 ≤12 行）

### 1 FC_DL_OrificeFlowCalc (DL_MathData)
功能：孔板差压→体积/质量流量，内置温压补偿与量程归一，纯函数无状态。
引脚：fDiffPress_Pa:REAL //差压 Pa 0~50000｜fAbsPress_Pa:REAL //绝压 Pa 5e4~2e6｜fTemp_C:REAL //温度 ℃ -40~400｜fKCoefficient:REAL //流量系数 由节流装置计算书｜fFlowRangeMax:REAL //满量程 m3/h 1e-3~1e5 → fFlow_m3h:REAL //流量 m3/h｜eError:E_DL_MathErr //错误码
算法：fFlow = K·C·√(ΔP·ρ(T,P))，ρ 用 FC_DL_AirDensity 同源理想气体式，√ 委托 FC_DL_NthRoot(2)。
边界：ΔP<0 按无效；绝压/温度越界钳制至量程并置 eWarning；√ 输入非负保证；NaN/Inf 入参拒绝。
错误码：0471 输入无效｜0472 差压为负｜0473 温度越界(钳制)｜0474 压力越界(钳制)｜0475 成功。
防错：浮点禁=判等；无魔法数（常数提为常量并带单位）；纯函数禁 VAR_OUTPUT 遗漏 RETURN 语义。

### 2 FC_DL_WaferCountYield (DL_MathData)
功能：投入/产出/返工三计数→良率%与损失分档（A级≥99/B级≥95/C级≥90/D级<90），纯函数。
引脚：uInputCnt:UDINT //投入片数 0~1e9｜uOutputGood:UDINT //良品片数｜uReworkCnt:UDINT //返工片数 → fYieldPct:REAL //良率 %｜eGrade:E_DL_YieldGrade //A~D 档｜bValid:BOOL //输入合法
算法：fYield = good/input×100；损失=input-good-rework 分档区间比较。
边界：input=0 时 bValid=FALSE 且 fYield 保持 0（防除零）；good>input 视为计数错误拒绝；uRework+good>input 同拒。
错误码：0476 成功｜0477 投入为0｜0478 良品>投入｜0479 计数溢出矛盾｜047A 成功但D档。
防错：UDINT 减法先验下界防下溢；枚举全部 `:=` 赋初值。

### 3 FC_DL_GasFlowSqrt (DL_Algo)
功能：特气差压流量开方换算，委托 FC_DL_NthRoot + FC_DL_FlowCompensate，统一钳位与错误码，不重实现数学内核。
引脚：fDiffPress:REAL //差压 kPa 0~100｜fGasDensity:REAL //工况密度 kg/m3 0.01~20｜fCompFactor:REAL //温压补偿系数 0.5~2.0｜fScaleMax:REAL //满量程 slm → fFlowSlm:REAL //流量 slm｜eError:E_DL_FlowErr
算法：校验→补偿系数钳位→委托开方→量程换算→上限钳制。
边界：密度≤0 拒绝；补偿系数出域钳制；开方输入非负由前置校验保证；结果 NaN 探测。
错误码：3706 成功｜3707 密度非法｜3708 差压为负｜3709 补偿系数越界(钳制)｜370A 结果溢出。
防错：严禁自写开方内核（T0 红线）；引脚注释带单位与量程。

### 4 FC_DL_AirDensityFanPower (DL_Algo)
功能：按实际空气密度修正风机轴功率（P∝ρ/ρ0），委托 FC_DL_AirDensity + FC_DL_LinearScale。
引脚：fTemp_C:REAL //气温 ℃ -40~60｜fRelHumPct:REAL //相对湿度 % 0~100｜fPress_Pa:REAL //大气压 Pa 6e4~1.1e5｜fPowerRated:REAL //额定功率 kW 0.1~5000 → fPowerCorr:REAL //修正功率 kW｜eError:E_DL_FanErr
算法：ρ_actual=委托 AirDensity(T,RH,P)；比率钳位 [0.5,1.5]；P=PowerRated·ρ/ρ0（ρ0=1.225 kg/m3 常量带单位）。
边界：三输入越界钳制并置警告；比率强制钳位防过修；额定功率≤0 拒绝。
错误码：370B 成功｜370C 温度越界(钳制)｜370D 湿度越界(钳制)｜370E 压力越界(钳制)｜370F 额定功率非法。
防错：ρ0 必须提为常量不得裸写 1.225；浮点比较用容差。

### 5 FB_DL_LoopWaveInject (DL_Algo)
功能：PID 回路调试激励源：正弦/方波/阶跃三型可选，叠加到给定值，带斜率与幅值保护。
引脚：bEnable:BOOL //注入使能｜eWaveType:E_DL_WaveType //SIN/SQR/STEP｜fAmplitude:REAL //幅值 % 0~100｜fPeriod_s:REAL //周期 s 0.1~600｜fSlewLimit:REAL //斜率限制 %/s 0.01~100 → fInjectOut:REAL //注入量 %｜bActive:BOOL //注入有效
算法：相位累加器（dt=周期测量）→ 按 eWaveType 计算瞬时值 → 委托 FB_DL_RateLimiter 斜率保护 → 输出。
边界：周期/幅值越界钳制；bEnable 下降沿输出平滑归零（经 RateLimiter 自然回零）；禁用期间输出冻结 0。
错误码：3710 就绪｜3711 幅值越界(钳制)｜3712 周期非法(钳制)｜3713 斜率限制非法｜3714 注入激活中。
防错：TON/相位累加须每周期无条件刷新；ENUM 成员 `:=`；CASE 必带 ELSE（默认输出0）。

### 6 FB_DL_FanArrayStageCtrl (DL_Device)
功能：N+1 风机阵列分级启停：按需求级数对称加/减机，运行小时轮值均衡。
引脚：aNRunHrs:ARRAY[1..8] OF UDINT //各风机累计小时 h｜uStageReq:UINT //需求级数 0~8｜uFanTotal:UINT //装机台数 1~8｜tMinRun:TIME //最短运行 60s｜tMinStop:TIME //最短停机 60s → auFanCmd:ARRAY[1..8] OF BOOL //启停指令｜uStageAct:UINT //实际级数
算法：需求级数钳位[0,total-1]（保 1 台备机）→ 与当前级数差 → 每 tick 至多切换 1 台（选运行最久/停机最久者）→ tMinRun/tMinStop 闸门（TON 无条件刷新）。
边界：uFanTotal>8 钳制 8；级数上限=total-1 预留备机；切换间隔闸门防频繁启停；数组下界检查。
错误码：038E 就绪｜038F 台数越界(钳制)｜0390 需求级数越界(钳制)｜0391 最短时序未满足(等待)｜0392 运行小时数据全零(轮值退化为顺序)。
防错：TON 实例无条件周期刷新；禁止在条件分支内才调 FB。

### 7 FB_DL_FrostProtectFreeze (DL_Device)
功能：防冻保护：低温断路器判据联动新风阀关闭/盘管阀开+风机联锁。
引脚：fFrostTemp_C:REAL //防冻温度设定 ℃ 默认4｜fOutdoor_C:REAL //室外温度 ℃ -50~60｜bHysteresisC:REAL //回差 ℃ 默认1.0｜bFrostAlarm:BOOL //盘管防冻开关输入 → bDamperCloseCmd:BOOL //关新风阀指令｜bCoilOpenCmd:BOOL //开盘管阀指令｜bFanStopCmd:BOOL //风机停指令｜eState:E_DL_FrostState //NORMAL/WARN/TRIP/RESET
算法：委托 FB_DL_Hysteresis 双阈判定（设定±回差）→ NORMAL→WARN（接近）→TRIP（触发：三输出同拍）→ 条件恢复+人工复位→RESET→NORMAL。
边界：室外温越界钳制；TRIP 后必须 bManualReset 才退出（安全侧保持）；回差≥0.1 钳制。
错误码：0393 NORMAL｜0394 WARN｜0395 TRIP(冻结输出保持)｜0396 复位挂起(条件未满足)｜0397 传感器无效(保持上次安全态)。
防错：ENUM 全成员 `:=` 初始化；CASE 带 ELSE→安全态输出。

### 8 FB_DL_MfcFlowCtrl (DL_Device)
功能：MFC 设定-回读校验：斜坡后检验回读进入容差窗、超调判据、稳定时间记录。
引脚：fSetpointSlm:REAL //设定流量 slm 0~量程｜fReadbackSlm:REAL //回读流量 slm｜fTolPct:REAL //容差 %FS 默认2｜fOvershootPct:REAL //超调判据 %FS 默认5｜tStable:TIME //稳定窗 默认5s｜bNewSp:BOOL //新设定触发 → bInTol:BOOL //入容差｜bOvershoot:BOOL //超调检出｜tSettleMs:UDINT //实测稳定时间 ms｜eError:E_DL_MfcErr
算法：bNewSp 上升沿→启动跟踪窗→窗内峰值 vs 设定+超调阈→持续 tStable 在容差窗→bInTol；窗超时（tStable×5）未入窗→超时故障。
边界：容差/超调下限 0.5%FS 钳制；回读 NaN/越量程判无效冻结；设定 0 视为关断不校验。
错误码：0398 就绪｜0399 校验通过｜039A 超调检出｜039B 稳定超时｜039C 回读无效。
防错：跟踪窗状态机 ENUM+CASE+ELSE；峰值检测用比较不用浮点=；TON 无条件刷新。

### 9 FB_DL_DateCoderSync (DL_Device)
功能：喷码/打码同步：编码器脉冲分频出喷墨触发，字符间距偏移补偿（产品间隙不均时修正触发相位）。
引脚：bEncoderPulse:BOOL //编码器脉冲输入｜uDivRatio:UINT //分频比 1~10000｜nOffsetCounts:DINT //偏移补偿 计数 -1000~1000｜bProductDetect:BOOL //产品到位 → bPrintTrig:BOOL //喷印触发｜uPulseCount:UDINT //累计计数(诊断)
算法：R_TRIG 采编码脉冲→计数器带偏移→计满 uDivRatio 修正值→触发一拍（TP 成形脉宽）；偏移限幅后取模。
边界：分频比 0 拒绝（钳 1）；偏移越界钳制；产品检测丢失超时→跳过并计数。
错误码：039D 就绪｜039E 分频比非法(钳1)｜039F 偏移越界(钳制)｜03A0 产品信号超时(跳过)｜03A1 正常喷印中。
防错：R_TRIG/TP 实例无条件刷新；DINT 负计数取模用委托逻辑防负余数。

### 10 FB_DL_SealIntegrityMonitor (DL_Device)
功能：封口完整性在线监视：温度/压力/时间三参数与配方窗比对，趋势超差预警（判定不执行封口，仅监视）。
引脚：fSealTemp_C:REAL //封口温度 ℃｜fSealPress_N:REAL //封口压力 N｜tSealTime:TIME //封口时间 ms｜fTempWin_L/H:REAL //温度窗下/上限 ℃｜fPressWin_L/H:REAL //压力窗下/上限 N｜tTimeWin_L/H:TIME //时间窗 → bInSpec:BOOL //三参全在窗｜nViolCnt:UINT //连续超差次数｜eError:E_DL_SealErr
算法：每封口节拍（bSealDone 上升沿采样三值）→三窗独立判定→全过→bInSpec；连续超差计数≥阈值→预警锁存（需复位）。
边界：窗下限<上限合法性自检（非法则拒判并报错）；NaN 判超差；计数饱和 65535。
错误码：03A2 在规格内｜03A3 温度超差｜03A4 压力超差｜03A5 时间超差｜03A6 窗参数非法(拒绝判定)。
防错：采样用 R_TRIG 无条件刷新；禁止浮点=；超差码可组合但主码取首个违参。

### 11 FB_DL_UnwinderDiameterCalc (DL_Motion)
功能：放卷卷径实时估算：膜厚×圈数积分递推，初始卷径+编码器行程递推，张力前馈数据源。
引脚：fFilmThick_um:REAL //膜厚 μm 5~500｜fDiaInit_mm:REAL //初始卷径 mm 50~1200｜fWebLen_m:REAL //累计放膜长度 m（外部积分输入）｜fDiaMin_mm:REAL //最小卷径 mm → fDiaNow_mm:REAL //当前卷径 mm｜bSpoolEnd:BOOL //接近空卷
算法：fDia = √(fDiaInit² − 4·thick·Σlen/π)，√ 委托 FC_DL_NthRoot(2)；每周期按 fWebLen 增量递推；低于 fDiaMin→bSpoolEnd。
边界：被开方数<0（数据矛盾）→冻结并报错；膜厚下限钳制；增量<0 拒绝（放卷只减卷径）。
错误码：0318 就绪｜0319 膜厚非法(钳制)｜0320 长度增量非法(拒绝)｜0321 根号内负值(冻结)｜0322 接近空卷预警。
防错：开方委托不重实现；浮点容差比较；输出冻结语义显式（不塞伪值）。

### 12 FB_DL_StringCutAlign (DL_Motion)
功能：串焊裁切对位：相机测得的电池串偏差→切割轴微调指令（比例修正+行程钳位+在位确认）。
引脚：fCamOffset_mm:REAL //相机偏差 mm -50~50｜fGainPct:REAL //比例增益 % 默认80｜fMaxCorr_mm:REAL //最大修正 mm 默认10｜bCutCycle:BOOL //切割节拍触发｜bAxisInPos:BOOL //轴在位反馈 → fCorrCmd_mm:REAL //修正指令 mm｜bCorrDone:BOOL //修正完成｜eError:E_DL_AlignErr
算法：bCutCycle 上升沿锁存偏差→滤波(委托 FB_DL_LowPassFilter)→比例计算→钳位→发指令→等 bAxisInPos→bCorrDone；超时→报错。
边界：偏差越界钳制并标记；增益 0~100 钳制；在位等待超时（提为 tInPosMax:TIME:=T#2S）→中止。
错误码：031D 就绪｜031E 偏差越界(钳制)｜031F 修正指令下发｜0320 在位超时(中止)｜0321 对位完成。
防错：锁存用上升沿触发 FB 无条件刷新；超时引脚带单位默认值（Splicer 教训迁移）。

### 13 FB_DL_StepperZLiftMicron (DL_Motion)
功能：Z 轴微米级步进升降：细分当量组态 + 相对/绝对微动 + 软限位行程拦截。
引脚：fUmPerStep:REAL //μm/步 当量 0.01~100（细分组态）｜fTargetUm:REAL //目标位置 μm｜fUpLimit_um / fLoLimit_um:REAL //软限位 μm｜fSpeedPps:UDINT //速度 步/s 1~100000 → fPosNow_um:REAL //当前 μm｜bMoving:BOOL｜bLimitHit:BOOL //限位拦截
算法：目标→步数换算(ROUND 防浮点累积)→软限位预检→按速度发步脉冲节拍（TP 计步）→位置累加。
边界：当量≤0 拒绝；步数溢出检测（>1e7 拒绝）；软限位预检先行，动中越限立即停；速度越界钳制。
错误码：0322 就绪｜0323 当量非法(拒绝)｜0324 目标超软限位(拒绝)｜0325 运动中限位拦截(急停)｜0326 到位。
防错：TP/计步无条件刷新；位置累加用 LREAL 防微米级累积误差；禁绝对地址。

### 14 FB_DL_FillWeightCtrl (DL_Process)
功能：灌装净重闭环：快灌/细灌两段阀切换 + 落差提前量自动学习（上罐误差修正本罐粗细切换点）。
引脚：fGrossWeight_g:REAL //毛重 g｜fTargetNet_g:REAL //目标净重 g 1~50000｜fCoarsePct:REAL //快灌切换点 % 默认85｜tFineMax:TIME //细灌超时 默认10s → bCoarseValve:BOOL｜bFineValve:BOOL｜bFillDone:BOOL｜fAdvance_g:REAL //当前提前量 g（学习值）
算法：去皮→快灌（毛重<目标−提前量×粗灌比）→细灌→毛重≥目标−提前量→双阀关→稳定窗称终值→误差→提前量指数学习（λ=0.3 常量带注释）。
边界：目标≤0 拒绝；细灌超时→中止并双阀关（安全侧）；学习值限幅[0, 目标×0.2]；重量信号无效冻结。
错误码：0412 就绪｜0413 粗灌中｜0414 细灌中｜0415 细灌超时(中止)｜0416 完成(提前量已更新)。
防错：学习更新仅在完成相执行（防运行中改写）；浮点禁=；两阀互斥校验。

### 15 FB_DL_VffsBagLength (DL_Process)
功能：立式制袋袋长控制：色标同步修正袋长 + 切刀相位对齐（色标丢失时退化为定长）。
引脚：bMarkDetect:BOOL //色标传感器｜fBagLenSet_mm:REAL //设定袋长 mm 50~2000｜uEncPpr:UINT //编码器每袋脉冲 数/袋｜fCorrLimit_mm:REAL //修正限幅 mm 默认5 → fBagLenAct_mm:REAL //实际袋长 mm｜bMarkLost:BOOL //色标丢失｜bCutPhaseOk:BOOL //切刀相位就绪
算法：编码器计长→色标上升沿比对基准差→偏差限幅修正下袋长→连续 N 袋(默认3,常量)无标→bMarkLost 退化定长；切刀相位=计长模袋长对齐窗。
边界：EncPpr=0 拒绝；修正限幅双向钳制；色标抖动去抖（TON 5ms 无条件刷新）；模运算防负。
错误码：0417 同步运行｜0418 色标丢失(定长退化)｜0419 修正饱和(连续贴限)｜041A 编码器非法(拒绝)｜041B 相位对齐完成。
防错：TON/R_TRIG 无条件刷新；退化态显式输出不清零显示。

### 16 FB_DL_CartonErectSeq (DL_Process)
功能：开箱机顺控：吸箱→成型→折底→输送四相，含卡箱检测与单相超时。
引脚：bVacuumOk:BOOL //真空建立反馈｜bBoxFormed:BOOL //成型到位｜bFlapClosed:BOOL //折底到位｜tStepMax:TIME //单相超时 默认5s → ePhase:E_DL_ErectPhase //IDLE/PICK/FORM/FLAP/EJECT/DONE/ERR｜bDone:BOOL｜bJam:BOOL //卡箱
算法：ENUM+CASE 步序；每相 TON 超时监视（无条件刷新）；反馈缺失→ERR+卡箱锁存；复位退 IDLE。
边界：每相反馈超时→ERR（不跳相）；真空反馈在 PICK 超时→释放真空再报错；CASE 带 ELSE→安全态（全输出 FALSE）。
错误码：041C IDLE｜041D PICK(吸箱)｜041E FORM(成型)｜041F FLAP(折底)｜0420 ERR(含相超时定位输出)。
防错：TON 无条件刷新；ENUM 全成员 `:=`；无占位词；超时引脚带单位。

### 17 FB_DL_LoadPortSeq (DL_Process)
功能：LoadPort 载具对接顺控：FOUP 开合→门阀握手→Wafer Map 片位映射比对→放行/拒收。
引脚：bFoupPresent:BOOL //FOUP 在位｜bDoorOpenOk:BOOL //开门到位｜aMapExpect:ARRAY[1..25] OF BOOL //期望片位图｜aMapRead:ARRAY[1..25] OF BOOL //读回片位图 → ePhase:E_DL_LoadPortPhase｜bMapMatch:BOOL //映射一致｜bReleaseOk:BOOL //放行
算法：七相顺控（IDLE/DOCK/OPEN/HANDSHAKE/MAPCMP/RELEASE/DONE/ERR）；MAPCMP 逐位比对，差异计数；握手超时→ERR。
边界：数组 25 元素固定下界检查；开门/握手各自超时；任意相异常→ERR 并安全收拢（关门指令）。
错误码：0421 IDLE｜0422 对接/开合进行中｜0423 映射不符(差异计数输出)｜0424 握手超时｜0425 放行完成。
防错：CASE+ELSE 安全态；TON 无条件刷新；数组边界常量提取。

### 18 FB_DL_PumpChangeoverSeq (DL_Process)
功能：冷冻/冷却水泵加减机：按温差需求对称加减机，复用轮值与最短时序纪律，一次泵变流量。
引脚：fDeltaT_C:REAL //供回水温差 ℃｜fDeltaTSet_C:REAL //目标温差 ℃ 默认5｜aNRunHrs:ARRAY[1..6] OF UDINT //运行小时 h｜tMinRun/tMinStop:TIME //最短时序 → auPumpCmd:ARRAY[1..6] OF BOOL｜uRunCount:UINT｜eError:E_DL_ChgoverErr
算法：温差偏差带（±0.5℃ 死区，常量）→滞消频宽→级数需求→每 tick 至多 1 台切换→tMinRun/tMinStop 闸门（TON 无条件刷新）→轮值选台。
边界：温差传感器无效→保持当前组合；级数钳位[1,N]（水泵不保备机，与风机阵列差异点）；切换闸门期间需求数>实际只记不切。
错误码：0426 就绪｜0427 温差在死区(保持)｜0428 加机中｜0429 减机中｜042A 闸门等待。
防错：与 FanArrayStageCtrl 共纪律但不共享实例；TON 无条件刷新；数组下界检查。

### 19 FB_DL_MachineGuardAudit (DL_Process)
功能：防护门开启审计与批次锁定：门开→按 PackML Holding 语义锁定批次、记录审计事件，恢复后 Held→核实→回到原相。
引脚：bGuardOpen:BOOL //门开信号｜bBatchActive:BOOL //批次运行中｜sOperId:STRING(32) //操作员标识（审计用）｜tMaxOpen:TIME //最长开门 默认300s → eState:E_DL_GuardAuditState //NORMAL/HOLDING/HELD/RESUMING/VIOLATION｜bLockBatch:BOOL //批次锁定输出｜uOpenCnt:UDINT //开启次数(审计)
算法：门开上升沿→若批次活动→HOLDING(锁批次+审计时间戳)→HELD；门关+bManualConfirm→RESUMING(核实无残留)→NORMAL；超 tMaxOpen→VIOLATION(锁存需权限复位)。
边界：门信号无效(与安全反馈矛盾)→按开处理（保守侧）；VIOLATION 需 sOperId 非空才可复位；审计计数饱和保护。
错误码：042B NORMAL｜042C HOLDING(批次已锁)｜042D HELD(等待恢复确认)｜042E VIOLATION(超时锁存)｜042F RESUMING(恢复核实)。
防错：借 PackML Holding/Held 语义组织（clean-room，17 态属主仍为 PackMlStateMachine）；R_TRIG 无条件刷新。

### 20 FB_DL_SplicerAutoJoint v1.0.x→v1.1.0（欠账收口，DL_Process）
功能：仅在既有 `FB_DL_SplicerAutoJoint` 上增补：eSyncWait 相新增 `tSyncMax : TIME := T#30S` 自有计时器，超时置新故障码并中止且绝不裁切。不改既有引脚契约（MINOR 升级）。
新增引脚：tSyncMax:TIME //同步等待超时 默认 T#30S（s）；新增输出：bSyncTimeout:BOOL //同步超时事件。
算法：eSyncWait 相内 TON（每周期无条件刷新）计时；速度差持续超容差至 tSyncMax→超时分支：置 0430 故障码→转中止相→bCutCmd 全程保持 FALSE。
边界：验收向量（必须写入 VERSION 修订记录）：速度差恒定 5%、容差 2% → tSyncMax 后 0430 且 bCutCmd 全程 FALSE。
错误码：0430~0434 为本件新占段：0430 同步超时故障；0431~0434 预留内部诊断（本件 MINOR 只启用 0430）。
防错：TON 只在 eSyncWait 相也须保持每周期调用（条件内 FB 调用陷阱——用 IF 包裹但 FB 实例调用本身无条件、仅输入条件化）；禁破坏既有码位。

## 3 批次分配表（4×5，批内编写顺序 1→5）
| 批次 | 组件序号 | 组件 | 顺序 |
|---|---|---|---|
| 1 | 1-5 | OrificeFlowCalc → WaferCountYield → GasFlowSqrt → AirDensityFanPower → LoopWaveInject | 1→5（纯函数先行热身） |
| 2 | 6-10 | FanArrayStageCtrl → FrostProtectFreeze → MfcFlowCtrl → DateCoderSync → SealIntegrityMonitor | 1→5（Device 件） |
| 3 | 11-15 | UnwinderDiameterCalc → StringCutAlign → StepperZLiftMicron → FillWeightCtrl → VffsBagLength | 1→5（Motion→Process 混编） |
| 4 | 16-20 | CartonErectSeq → LoadPortSeq → PumpChangeoverSeq → MachineGuardAudit → SplicerAutoJoint收口 | 1→5（最难/欠账殿后） |

## 4 缺口说明
无缺口，20 件足额；全部有真实工程语义与 roadmap/矩阵溯源，无凑数变体。查重说明：GasFlowSqrt 与存量 FlowSqrtExtract 语义区分（特气+温压补偿一体，roadmap L645 明确保留）；UnwinderDiameterCalc（实时递推 FB）与 FC_DL_CoilDiameterCalc（静态计算 FC）不重叠；CartonErectSeq 与 CartonErectorStation（整机工站）层级不同。
