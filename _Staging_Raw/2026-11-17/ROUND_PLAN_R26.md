# ROUND_PLAN_R26 —— R26 轮次作战计划（仅规划，不落 .st）

- **轮次**：R26 ｜ **日期**：2026-11-17 ｜ **目标数**：20 ｜ **硬预算**：12 分钟规划时限内完成
- **库现状看板**：总库 444 件 / 10,000 ｜ registry v2.14.0 ｜ 今日已入库 60/200 ｜ 距 500 冲刺差 56 件
- **源矩阵覆盖率**：T1-3 OSCAT Network ✔（已收口，本轮不碰）；其余主组 ◐；本轮全部取自「已登记 ◐ 组深化 + T0 零检索变体线」，**无新开 ☐ 组，零 WebSearch**
- **配额自查**：T2 组件族 ≥1 ✔（T2-1 LGF Measurement ×2、T2-2 LBP ×4、T2-7 PackML ×3、T2-8 ISA-18.2 ×1）；T1 组件族 ≥1 ✔（T1-2 OSCAT Building ×4、T1-6 PLCopen ×2）；T0 零检索 ×3
- **防凑数自查**：20 件均含独立工程语义（诊断/保护/计量/编排），无仅改数据类型的重载、无语义重复薄包装；与 444 件 registry + R25 计划清单逐一比对零重名

## 一、主表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_MinPulseWidthFilter | DL_Base | FB | 最小脉宽滤波：窄于 tMinOn/tMinOff 的毛刺抑制，长脉冲 1:1 透传 | `t0-2-定时器变体线`（零检索） | 3 | 1 |
| 2 | FC_DL_StringPad | DL_MathData | FC | 字符串左/右/居中填充至目标长度，越界显式截断并置标志 | `t0-6-字符串`（零检索） | 3 | 1 |
| 3 | FB_DL_EventRateCalc | DL_MathData | FB | 滑窗事件速率计算（事件/分钟），环形桶计数，窗口可 1~3600 s | `t0-2/3-变体线`（零检索） | 4 | 1 |
| 4 | FB_DL_HistogramAccum | DL_MathData | FB | 数值直方图累积：分箱计数 + 下溢/上溢桶 + NaN/Inf 拦截 | `t2-1-lgf-measurement`（统计族待挖，R18 备注） | 4 | 1 |
| 5 | FC_DL_WeightedMovingAvg | DL_MathData | FC | 权重表滑动平均（与既有 IIR 滤波族正交：窗口权重显式可配） | `t2-1-lgf-measurement`（统计族待挖） | 4 | 1 |
| 6 | FB_DL_PidGainScheduler | DL_Algo | FB | 增益调度：按调度变量查表线性插值输出 Kp/Ti/Td，仅输出参数不控回路 | `t2-1-lgf-technology ◐深化` + 本轮规划新增线 | 5 | 2 |
| 7 | FB_DL_ControlValveDiag | DL_Device | FB | 调节阀行程偏差 + 迟滞估计诊断，NE107 健康分级，仅监视不驱动 | `t2-2-lbp ◐深化`（补 AnalogValve/ThreePointValve 诊断缺口） | 5 | 2 |
| 8 | FB_DL_MotorPtcThermistProtect | DL_Device | FB | PTC 热敏电阻绕组保护（DIN 44081 判据：断线/短路/ triplet 阻值域） | `t2-2-lbp ◐深化` + `t1-9-国产手册需求线` | 4 | 2 |
| 9 | FB_DL_ElectrolyteTankLevel | DL_Device | FB | 电解液储罐液位双限 + 氮封微正压监视联锁，加注许可仲裁 | `roadmap §L350 已登记未注册` + `t1-2-oscat-building` | 5 | 2 |
| 10 | FB_DL_PumpDryRunProtect | DL_Device | FB | 泵干转保护：运行态功率/流量双判据 + 确认延时 + 重启闭锁 | `t1-2-oscat-building ◐深化`（泵风机族） | 4 | 2 |
| 11 | FB_DL_AxisLoadTorqueMonitor | DL_Motion | FB | 轴负载扭矩 RMS 滑窗监视 + 堵转/过载预警分级，不触轴状态 | `t1-6-plcopen ◐深化`（安全层第 2 波） | 4 | 3 |
| 12 | FC_DL_CamTableInterp | DL_Motion | FC | 凸轮表按主轴位置线性插值取从轴位置（与 Validate/PhaseTrim 正交） | `t1-6-plcopen ◐深化` | 4 | 3 |
| 13 | FB_DL_AlarmShelving | DL_Process | FB | ISA-18.2 报警搁置/屏蔽管理：限时搁置、超时强制恢复、搁置台账计数 | `t2-8-isa18.2 ◐深化`（与 AlarmManager 正交） | 5 | 3 |
| 14 | FB_DL_ChillerTempStab | DL_Process | FB | 冷冻水供水温度稳定性监视：滑窗均值/标准差 + CV 判稳 | `roadmap §L259 已登记未注册` | 5 | 3 |
| 15 | FB_DL_LineChangeoverChecklist | DL_Process | FB | 换型检查清单顺控：步确认/前向跳步/未完成禁止启动 | `t2-7-packml ◐深化` | 5 | 3 |
| 16 | FB_DL_TankFarmInventory | DL_Process | FB | 罐区库存计量：液位→体积（罐表插值）→ 温度补偿质量，多罐合计 | `t1-2-oscat-building` + 本轮规划新增线 | 6 | 4 |
| 17 | FB_DL_EnergyKpiAggregator | DL_Process | FB | 单位产量能耗 KPI：电能累计 ÷ 产量计数，零产量保持并置掩码 | `t2-7-packml ◐深化`（消费 I_DL_PowerMeter 语义） | 5 | 4 |
| 18 | FB_DL_FanBeltSlipDiag | DL_Device | FB | 风机皮带打滑诊断：电机/叶轮转速比监视 + 确认延时 | `t1-2-oscat-building ◐深化`（泵风机族） | 4 | 4 |
| 19 | FB_DL_VfdThermalDerate | DL_Device | FB | 变频器热/海拔双因素降容：两段线性降容系数 + 迟滞恢复 | `t2-2-lbp ◐深化`（驱动参数化族） | 4 | 4 |
| 20 | FB_DL_DustFreehoodPress | DL_Device | FB | 洁净风帽多房间压差梯度排序监视 + 级联倒序告警 | `roadmap §L363 已登记未注册` | 5 | 4 |

## 二、四批主题

- **批 1（序 1~5）**：Level 0 信号整形/字符串/统计原语，纯 T0 + LGF Measurement，零外部依赖
- **批 2（序 6~10）**：控制参数调度 + 设备诊断/保护族（阀/电机/泵/罐），依赖 DL_Base
- **批 3（序 11~15）**：运动监视 + 过程状态机/报警治理（ISA-18.2、PackML、判稳）
- **批 4（序 16~20）**：计量与 KPI 聚合 + 剩余设备诊断，复用批 1~3 已确立原语语义

## 三、派单样板区（编码时逐字采用）

### 3.1 注释行样板（同行双语，禁止 `(* *)` 内再套 `(* *)`）

```iecst
bTrip        : BOOL; // 干转跳闸锁存，仅 bReset 可清 / Dry-run trip latch, cleared only by bReset
fTorqueRms   : LREAL; // 扭矩滑窗均方根，单位 %（相对额定扭矩）/ Torque RMS over window, unit % of rated
```

### 3.2 错误码声明样板（库内 UDINT 码族，禁 UINT 小整数）

```iecst
eErr : E_DL_ErrorCode; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
// 码值取「四、码位分配表」实测段，形如 16#0003_0375
```

### 3.3 文件头溯源短语（原文照抄）

- T0 件（序 1~3）：`IEC 61131-3 标准语义的道莅防御性实现`
- T1/T2 件（序 4~20）：`道莅 clean-room 防御性实现`

### 3.4 头注释禁写记号（机检全文命中=0，用语义替代）

禁止在头注释出现「全局变量表 / 外部变量声明 / 物理输入映像 / 物理输出映像」等被禁记号的字面写法；数据注入一律描述为「经输入/输出/输入输出引脚注入」。违例自伤说明：若头注释字面命中禁词，机检按全文命中计数会误伤本文件。

## 四、码位分配表（grep 实测 2026-11-17 全量 .st，正则 `16#000N_[0-9A-F]{3,4}`）

实测基线：0001 族（Base+MathData）故障 3xx 最大 0x3BE、信息 4xx 最大 0x470；0002 见 0x36xx（CC 制）；0003 故障 3xx 最大 0x374、信息 2xx 最大 0x2F9；0004 故障 3xx 最大 0x311；0005 故障 3xx 最大 0x35C、信息 4xx 最大 0x411。R25 游标仅作参照，本表以实测为准。每件 3 码位（1 信息 + 2 故障，或纯故障 3 连段）。

| 序号 | 组件 | 码位（UDINT） | 分配依据 |
|---|---|---|---|
| 1 | MinPulseWidthFilter | 0001_0471（信息）；0001_03BF~03C0（故障） | Base/MathData 共段：4xx 实测最大 0x470 → 信息起 0471；3xx 实测最大 0x3BE → 故障起 03BF |
| 2 | StringPad | 0001_0472；0001_03C1~03C2 | 同上连续递推 |
| 3 | EventRateCalc | 0001_0473；0001_03C3~03C4 | 同上连续递推 |
| 4 | HistogramAccum | 0001_0474；0001_03C5~03C6 | 同上连续递推 |
| 5 | WeightedMovingAvg | 0001_0475；0001_03C7~03C8 | 同上连续递推 |
| 6 | PidGainScheduler | 0002_3701/3702/3705 | 0002 为 CC 制，实测最高 0x36xx → 新 CC=0x37，槽位沿用 xx01/xx02/xx05 惯例 |
| 7 | ControlValveDiag | 0003_0375~0377 | Device 3xx 实测最大 0x374 → 起 0375，纯故障 3 连段（信息带 2xx 已近满，避开 03xx 混带） |
| 8 | MotorPtcThermistProtect | 0003_0378~037A | 连续递推 |
| 9 | ElectrolyteTankLevel | 0003_037B~037D | 连续递推 |
| 10 | PumpDryRunProtect | 0003_037E~0380 | 连续递推 |
| 11 | AxisLoadTorqueMonitor | 0004_0312~0314 | Motion 3xx 实测最大 0x311 → 起 0312，纯故障段 |
| 12 | CamTableInterp | 0004_0315~0317 | 连续递推 |
| 13 | AlarmShelving | 0005_0412（信息）；0005_035D~035E（故障） | Process 4xx 实测最大 0x411 → 信息起 0412；3xx 实测最大 0x35C → 故障起 035D |
| 14 | ChillerTempStab | 0005_0413；0005_035F~0360 | 连续递推 |
| 15 | LineChangeoverChecklist | 0005_0414；0005_0361~0362 | 连续递推 |
| 16 | TankFarmInventory | 0005_0415；0005_0363~0364 | 连续递推 |
| 17 | EnergyKpiAggregator | 0005_0416；0005_0365~0366 | 连续递推 |
| 18 | FanBeltSlipDiag | 0003_0381~0383 | Device 故障段续递推（批 4 回补 Device） |
| 19 | VfdThermalDerate | 0003_0384~0386 | 连续递推 |
| 20 | DustFreehoodPress | 0003_0387~0389 | 连续递推 |

> 编码时若与落盘现状冲突（例如 R26 前半程 60 件已占 0375），以落码当天再实测为准顺延，禁止回填已占用码。

## 五、引脚级规格（每件一节）

### 5.1 FB_DL_MinPulseWidthFilter（DL_Base）
- VAR_INPUT：`bIn : BOOL`（待滤波信号）；`tMinOn : TIME`（最小接通脉宽，ms）；`tMinOff : TIME`（最小断开脉宽，ms）
- VAR_OUTPUT：`bOut : BOOL`；`bSuppressed : BOOL`（本周期有脉冲被抑制标志）
- 内部状态：两相 TON（主周期无条件刷新）；ENUM 状态机 Idx→WaitOn/WaitOff，CASE 带 ELSE 归安全态
- 功能：短于最小脉宽的毛刺不透传；达标脉冲原样跟随
- 边界与安全：tMinOn=0 且 tMinOff=0 → 直通模式；上电首扫禁假触发（输出初始化 FALSE）
- 故障码：0001_03BF=两相超时参数非法（负值钳 0 并置码）；0001_03C0=保留
- 验收向量：①5 ms 毛刺（tMinOn=20 ms）→ bOut 不动；②50 ms 脉冲 → 1:1 透传；③tMinOn=0 → 边沿即透传

### 5.2 FC_DL_StringPad（DL_MathData）
- VAR_INPUT：`sIn : STRING`; `sPadChar : STRING`（取首字符，空则默认空格）；`nTargetLen : UINT`（目标长度，0~255）；`eSide : E_DL_PadSide`（LEFT/RIGHT/CENTER）
- VAR_OUTPUT：`sOut : STRING`；`bTruncated : BOOL`
- 边界与安全：nTargetLen>255 → 钳 255 并置 bTruncated；sIn 超长按 nTargetLen 截断
- 故障码：0001_03C1=填充字符为空（已按空格降级）；0001_03C2=保留
- 验收向量：①`'AB',8,RIGHT`→`'AB______'`；②`'ABCDEFG',3`→`'ABC'`+bTruncated=TRUE；③CENTER 奇偶差一填左侧

### 5.3 FB_DL_EventRateCalc（DL_MathData）
- VAR_INPUT：`bEvent : BOOL`（事件脉冲，R_TRIG 内取沿）；`tWindow : TIME`（1 s~3600 s，超出钳位）；`bReset : BOOL`
- VAR_OUTPUT：`fRate : LREAL`（事件/分钟）；`uTotal : ULINT`（累计事件）
- 内部状态：固定桶数常量环形计数数组 `aBuckets`，周期滚桶
- 边界与安全：tWindow<1 s 钳 1 s；>1 h 钳 1 h 并置错误码；单周期多事件按计数累加
- 故障码：0001_03C3=窗口钳位发生；0001_03C4=保留
- 验收向量：①每周期 1 事件、窗口 60 s → fRate≈60；②bReset 后 fRate=0；③窗口钳位时错误码非零且继续工作

### 5.4 FB_DL_HistogramAccum（DL_MathData）
- VAR_IN_OUT：`aEdges : ARRAY[0..n] OF LREAL`（单调递增分箱边界）
- VAR_INPUT：`fValue : LREAL`；`fWeight : LREAL`（默认 1.0）；`bReset : BOOL`
- VAR_OUTPUT：`aCounts : ARRAY OF ULINT`；`uUnderflow/uOverflow : ULINT`；`bEdgeErr : BOOL`
- 边界与安全：NaN/Inf 拒收并置码；fWeight≤0 拒收；边界未排序 → bEdgeErr 且不累计
- 故障码：0001_03C5=NaN/Inf 拒收；0001_03C6=边界表非法
- 验收向量：①值恰等于边界 → 归右箱（右闭约定）；②低于最小边界 → uUnderflow+1；③NaN → 计数不变+故障码

### 5.5 FC_DL_WeightedMovingAvg（DL_MathData）
- VAR_IN_OUT：`fb 本体持环`（FC 以内部静态语义由 FB 化封装时降级为 FB，若编译器不支持 FC 静态则改 `FB_DL_WeightedMovingAvg`，规划允许此改名）
- VAR_INPUT：`fNew : LREAL`；`aWeights : ARRAY OF LREAL`；`bReset : BOOL`
- VAR_OUTPUT：`fAvg : LREAL`；`bValid : BOOL`（窗口未满=FALSE）；`uWindow : UINT`
- 边界与安全：权重和≤0 → 拒新样本并置码；NaN 样本跳过不滚动
- 故障码：0001_03C7=权重和非法；0001_03C8=保留
- 验收向量：①恒值 10.0 输入 → fAvg→10.0；②窗口未满 bValid=FALSE；③权重 {1,0} → 等价 1 阶延迟

### 5.6 FB_DL_PidGainScheduler（DL_Algo）
- VAR_IN_OUT：`aGainTable : ARRAY OF ST_DL_GainPoint`（fVar, fKp, fTi, fTd；需按 fVar 升序）
- VAR_INPUT：`fSchedVar : LREAL`；`bEnable : BOOL`；`bHoldLast : BOOL`（表非法时保持）
- VAR_OUTPUT：`fKp/fTi/fTd : LREAL`；`eErr : E_DL_ErrorCode`
- 边界与安全：变量低于首点/高于末点 → 端点钳位；表未排序 → 错误码 + bHoldLast 生效；NaN → 保持
- 故障码：0002_3701=表未排序；0002_3702=调度变量 NaN；0002_3705=端点钳位发生
- 验收向量：①两点表线性插值中点值正确；②超界取端点+3705；③乱序表 → 保持上次输出

### 5.7 FB_DL_ControlValveDiag（DL_Device）
- VAR_INPUT：`fCmdPos : LREAL`（%）；`fFbPos : LREAL`（%）；`fDevLimit : LREAL`（%）；`tDevDelay : TIME`（确认延时 ms）；`fHystBand : LREAL`（%）；`bEnable : BOOL`
- VAR_OUTPUT：`eHealth : E_DL_Ne107Status`；`bDeviationAlarm : BOOL`；`fDeviation : LREAL`；`uTravelAccum : UREAL`（累计行程 %，寿命估计）
- 边界与安全：fFbPos<-5 或 >105 → 传感器故障态优先于偏差态；bEnable=FALSE 全部输出复位
- 故障码：0003_0375=反馈超量程；0003_0376=偏差确认超时；0003_0377=迟滞超带
- 验收向量：①|cmd-fb|=8%、限 5%、延时到 → 0376；②fb=120% → 0375 优先；③小幅往复迟滞>带 → 0377

### 5.8 FB_DL_MotorPtcThermistProtect（DL_Device）
- VAR_INPUT：`fThermRes : LREAL`（Ω）；`bSensorOk : BOOL`；`fTripRes : LREAL`（默认 3300 Ω，DIN 44081）；`fOpenRes : LREAL`（默认 8000 Ω）；`fShortRes : LREAL`（默认 50 Ω）；`tConfirmDelay : TIME`；`bReset : BOOL`
- VAR_OUTPUT：`bTrip/bWarn/bSensorFault : BOOL`；`fResFiltered : LREAL`
- 边界与安全：断线判定优先于跳闸；bReset 仅在阻值回落正常带后有效（防复位振荡）
- 故障码：0003_0378=断线；0003_0379=短路；0003_037A=跳闸确认
- 验收向量：①4000 Ω 稳定 → 跳闸；②9000 Ω → 断线优先；③跳闸后 100 Ω 短路态下 bReset 无效

### 5.9 FB_DL_ElectrolyteTankLevel（DL_Device）
- VAR_INPUT：`fLevel : LREAL`（%）；`fN2Press : LREAL`（kPa，氮封微正压）；`fHiHi/fLoLo : LREAL`；`fPressLo/fPressHi : LREAL`；`bSensorOk : BOOL`
- VAR_OUTPUT：`bFillPermit : BOOL`；`bN2ValveOpen : BOOL`；`bHiHi/bLoLo/bPressFault : BOOL`
- 边界与安全：bSensorOk=FALSE → 保持上次有效状态 + bPressFault + 禁加注（安全侧）
- 故障码：0003_037B=液位传感器失效；0003_037C=氮封压力越限；0003_037D=双限设定值非法（LoLo≥HiHi）
- 验收向量：①液位低于 LoLo → 禁加注 + LoLo 告警；②氮封低于下限 → 开氮阀；③传感器失效 → 保持+禁加注

### 5.10 FB_DL_PumpDryRunProtect（DL_Device）
- VAR_INPUT：`bPumpRunFb : BOOL`；`fMotorPower : LREAL`（kW）；`fFlow : LREAL`（m³/h，可选，<0 表示未接）；`fNoLoadPower : LREAL`；`tDryDelay : TIME`；`bReset : BOOL`
- VAR_OUTPUT：`bDryRun/bTrip/bRestartInhibit : BOOL`
- 边界与安全：运行反馈存在且功率<空载阈值持续 tDryDelay → 干转确认；跳闸后重启闭锁，需 bReset 且液位/流量恢复（经引脚注入条件）
- 故障码：0003_037E=干转确认；0003_037F=参数非法（空载阈值≤0）；0003_0380=重启闭锁激活
- 验收向量：①运行+功率 0.2 kW（阈值 1 kW）延时到 → 跳闸；②未运行 → 无判定；③跳闸后未复位时重启指令被拒

### 5.11 FB_DL_AxisLoadTorqueMonitor（DL_Motion）
- VAR_INPUT：`fTorqueFb : LREAL`（% 额定）；`fWarnLimit/fTripLimit : LREAL`（%）；`tWindow : TIME`；`bEnable : BOOL`
- VAR_OUTPUT：`fTorqueRms/fTorquePeak : LREAL`；`bWarn/bTrip : BOOL`
- 边界与安全：|fTorqueFb|>200% → 采样拒收+故障码；bEnable 下降沿清统计
- 故障码：0004_0312=警告级超限确认；0004_0313=跳闸级超限确认；0004_0314=采样值非法
- 验收向量：①恒 80%（限 60/90）→ bWarn；②瞬时 150% → 0314；③窗口内 RMS 对方波符合解析值 ±5%

### 5.12 FC_DL_CamTableInterp（DL_Motion）
- VAR_IN_OUT：`aCam : ARRAY OF ST_DL_CamPoint`（fMaster/fSlave，升序）
- VAR_INPUT：`fMasterPos : LREAL`；`bPeriodic : BOOL`；`fPeriod : LREAL`（周期模式主轴周期，mm）
- VAR_OUTPUT：`fSlavePos : LREAL`；`bInRange : BOOL`；`eErr : E_DL_ErrorCode`
- 边界与安全：非周期模式界外钳端点 + bInRange=FALSE；表 <2 点或未升序 → 错误码；周期模式先取模再插值
- 故障码：0004_0315=表非法；0004_0316=主轴位置 NaN；0004_0317=保留
- 验收向量：①两点线性中点插值正确；②界外钳位+标志；③周期取模后插值与手算一致

### 5.13 FB_DL_AlarmShelving（DL_Process）
- VAR_INPUT：`bAlarmActive : BOOL`；`bShelveCmd : BOOL`（上升沿生效）；`tMaxShelve : TIME`；`bRestoreCmd : BOOL`
- VAR_OUTPUT：`bOut : BOOL`（对下游呈现的告警态）；`bShelved : BOOL`；`bTimeout : BOOL`（超时强制恢复）
- 内部状态：TON 搁置计时（主周期无条件刷新）；搁置台账计数 uShelveCount
- 边界与安全：无告警时搁置指令拒绝（计数不增）；超时强制恢复优先于新搁置指令
- 故障码：0005_035D=无效搁置指令（无告警）；0005_035E=搁置超时强制恢复
- 验收向量：①告警中搁置 → bOut=FALSE；②tMaxShelve 到 → 强制恢复+035E；③无告警搁置 → 拒绝+035D

### 5.14 FB_DL_ChillerTempStab（DL_Process）
- VAR_INPUT：`fSupplyTemp : LREAL`（℃）；`fCvLimit : LREAL`（%）；`tConfirm : TIME`；`bReset/bEnable : BOOL`
- VAR_OUTPUT：`fMean/fStdDev/fCv : LREAL`；`bStable : BOOL`；`bUnstableConfirm : BOOL`
- 边界与安全：温度 NaN/超出 -40~120 ℃ 拒收；样本数<最小值 → bStable=FALSE 且不判稳
- 故障码：0005_035F=样本非法拒收；0005_0360=判稳确认超时未达成
- 验收向量：①恒定 7.0 ℃ → CV≈0 判稳；②±3 ℃ 振荡 → 不稳定确认；③拒收样本不计入均值

### 5.15 FB_DL_LineChangeoverChecklist（DL_Process）
- VAR_IN_OUT：`abStepsDone : ARRAY[..] OF BOOL`（检查项完成位）
- VAR_INPUT：`abSkipReq : ARRAY[..] OF BOOL`（跳步申请）；`bStartConfirm : BOOL`；`bReset : BOOL`
- VAR_OUTPUT：`eState : E_DL_ChgoverState`；`uCurStep : UINT`；`bAllDone : BOOL`；`bSkipUsed : BOOL`
- 边界与安全：跳步仅允许前向且不可跳最后一项；未全部完成（含跳步）时 bStartConfirm 拒绝
- 故障码：0005_0361=非法回退跳步申请；0005_0362=未完成启动尝试
- 验收向量：①全确认 → bAllDone；②跳步 3 项中 1 项 → 记录+放行；③缺项启动 → 拒绝+0362

### 5.16 FB_DL_TankFarmInventory（DL_Process）
- VAR_IN_OUT：`aTanks : ARRAY OF ST_DL_TankPoint`（fLevel, fDensity, fTemp, aStrapping[]）
- VAR_OUTPUT：`aVolume/aMass : ARRAY OF LREAL`；`fTotalMass : LREAL`；`abTankErr : ARRAY OF BOOL`
- 边界与安全：罐表未排序 → 该罐错误标志并跳过；密度 <0.5 g/cm³ → 拒收该样本；液位界外钳端
- 故障码：0005_0363=罐表非法；0005_0364=密度拒收
- 验收向量：①单罐线性罐表中点体积正确；②密度 0.4 → 拒收+0364；③合计=各罐质量之和

### 5.17 FB_DL_EnergyKpiAggregator（DL_Process）
- VAR_INPUT：`fEnergyDelta : LREAL`（kWh，周期增量）；`uProdDelta : ULINT`（件）；`tKpiWindow : TIME`；`bReset : BOOL`
- VAR_OUTPUT：`fKpi : LREAL`（kWh/千件）；`bKpiValid : BOOL`；`bZeroProdMask : BOOL`
- 边界与安全：产量为 0 → 保持上次 KPI + bZeroProdMask（不做除零）；能量增量 <0 → 视为表翻转拒收
- 故障码：0005_0365=能量增量非法；0005_0366=零产量掩码激活
- 验收向量：①10 kWh/1000 件 → KPI=10.0；②产量 0 → 掩码+保持；③负增量拒收

### 5.18 FB_DL_FanBeltSlipDiag（DL_Device）
- VAR_INPUT：`fMotorRpm : LREAL`；`fFanRpm : LREAL`；`fRatioTol : LREAL`（%）；`tConfirm : TIME`；`bMotorRun : BOOL`
- VAR_OUTPUT：`bSlip : BOOL`；`bSlipConfirm : BOOL`；`fRatio : LREAL`
- 边界与安全：fMotorRpm≈0（<1 rpm）不判定（防除零）；bMotorRun=FALSE 清确认
- 故障码：0003_0381=转速比超差确认；0003_0382=叶轮停转而电机运行；0003_0383=输入非法
- 验收向量：①比值 1.5、容差 10% → 0381；②电机 1450 rpm、叶轮 0 → 0382；③电机 0 rpm → 不判定

### 5.19 FB_DL_VfdThermalDerate（DL_Device）
- VAR_INPUT：`fHeatsinkTemp : LREAL`（℃）；`fAltitude : LREAL`（m）；`fTempDerateStart : LREAL`（默认 60 ℃）；`fTempDerateFull : LREAL`（默认 80 ℃）；`fAltDerateStart : LREAL`（默认 1000 m）；`fAltDerateFull : LREAL`（默认 4000 m）
- VAR_OUTPUT：`fDerateFactor : LREAL`（0~1）；`bDerateActive : BOOL`
- 边界与安全：双因素取小者；恢复带迟滞 2 ℃（防抖）；NaN 输入保持上次系数
- 故障码：0003_0384=温度输入非法；0003_0385=海拔输入非法；0003_0386=降容系数钳界
- 验收向量：①70 ℃/2000 m → 双因素各算取小；②55 ℃/500 m → 1.0；③温度回差 2 ℃ 内不翻转

### 5.20 FB_DL_DustFreehoodPress（DL_Device）
- VAR_INPUT：`afPress : ARRAY OF LREAL`（Pa，各房间压差）；`fMinCascade : LREAL`（Pa，相邻级最小梯度）；`bSensorOk : BOOL`
- VAR_OUTPUT：`bCascadeOk : BOOL`；`uWorstPair : UINT`（倒序最差相邻对索引）；`bRankAlarm : BOOL`
- 边界与安全：任一传感器失效 → 全列保持+告警；afPress 元素数 <2 → 错误码不判定
- 故障码：0003_0387=传感器失效；0003_0388=级联梯度不足；0003_0389=配置非法
- 验收向量：①梯度 10/10 Pa（需 15）→ 0388+最差对索引；②全达标 → bCascadeOk；③传感器失效 → 保持+0387

## 六、ROADMAP 认领标注（本轮只标注，不增写）

- 序 14 `FB_DL_ChillerTempStab` → ROADMAP.md 第 259 行未勾选项
- 序 9 `FB_DL_ElectrolyteTankLevel` → ROADMAP.md 第 350 行未勾选项
- 序 20 `FB_DL_DustFreehoodPress` → ROADMAP.md 第 363 行未勾选项
- 其余 17 件为已登记 ◐ 源组深化或本轮规划新增缺口线（ROADMAP 现有 337 条 ≥30，按规则不补写）
