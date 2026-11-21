# R31 轮派单计划（2026-11-18）｜阶段一盘点 + 阶段二源矩阵狩猎

**读完即落盘**：批 1 = offset 1/limit 5，批 2 = offset 6/limit 5，批 3 = offset 11/limit 5，批 4 = offset 16/limit 5。

## §0 盘点表

| 项 | 实测值 |
|---|---|
| registry | v2.19.0 / 539 件：Base 75 / MathData 162 / Algo 58 / Device 102 / Motion 55 / Process 87 |
| ROADMAP 未勾选 270 条 | python 全量比对 registry：43 条台账滞后（已注册未回勾），214 条真实空位 |
| T0 快车道 | **补位 0 件**：三条 P0 条码线 grep 证实已注册（台账滞后）；CartonScannerSort 与已注册 trace 族同义，按「不得再造同义变体」不派 |
| 矩阵 ◐ 待挖 | 取 8 件：NE107 仲裁件 / LGF Math 三角·极分解 / T1-2 ROOM_CONTROL 2 件 / T1-6 外部编码器族 2 件 / 半导体 ESC 电流监视 / T1-7 PROFINET 诊断 |
| 分类分布 | Device 5 / Process 11 / Motion 2 / MathData 1 / Algo 1（MathData 仅矩阵待挖方向 1 件；Process 为真实空位主体非变体） |

## §1 组件表（20 件）

| # | 组件名 | 分类 | POU | 功能 | 来源 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_HealthArbiter | Device | FB | NE107 多源健康聚合仲裁件 | T2-8 | 中 | 1 |
| 2 | FC_DL_PolarTransform2D | MathData | FC | 直角↔极坐标双向变换 | T2-1 LGF·Math | 低 | 1 |
| 3 | FB_DL_EnthalpyChangeover | Process | FB | 新风/回风焓值优先模式切换 | T1-2 | 中 | 1 |
| 4 | FB_DL_NightPurgeCtrl | Process | FB | 夜间吹扫顺控（降温除湿侧） | T1-2 | 中 | 1 |
| 5 | I_DL_ExternalEncoder | Motion | I | 外部编码器契约接口（开族） | T1-6 | 低 | 1 |
| 6 | FB_DL_ExternalEncoderLatch | Motion | FB | 外部编码器快照采样锁存 | T1-6 | 中 | 1 |
| 7 | FB_DL_EscChuckCurrentMon | Device | FB | ESC 静电卡盘吸附电流监视 | 半导体 ESC 自研 | 中 | 1 |
| 8 | FB_DL_PnAlarmDiagParse | Device | FB | PROFINET 告警语义解析 | T1-7 | 中 | 1 |
| 9 | FB_DL_WaferHandoffSeq | Device | FB | 双机械手交接防碰撞握手 | 行业池 | 高 | 2 |
| 10 | FB_DL_SlurryStirrerCtrl | Device | FB | 浆料搅拌双电机同步+扭矩监视 | 行业池 | 中 | 2 |
| 11 | FB_DL_ChamberLeakRate | Process | FB | 腔体升压率检漏 | 行业池 | 中 | 2 |
| 12 | FB_DL_VacuumChamberSeq | Process | FB | 粗抽→精抽→检漏→放气顺控 | 行业池 | 高 | 2 |
| 13 | FB_DL_CleanRoomPressure | Process | FB | 多房间正压梯级控制防倒流 | 行业池 | 中 | 3 |
| 14 | FB_DL_ReactorStepCtrl | Process | FB | 反应釜四工步顺控 | 行业池 | 高 | 3 |
| 15 | FB_DL_FlowTotalizer | Process | FB | 流量累积与批控零点 | 行业池 | 低 | 3 |
| 16 | FB_DL_TankLevelCtrl | Process | FB | 储罐液位双泵轮值+联锁 | 行业池 | 中 | 3 |
| 17 | FB_DL_UtilitiesLoadMgr | Process | FB | 多机按需投切负荷分配 | 行业池 | 中 | 4 |
| 18 | FB_DL_FilmTensionDancer | Process | FB | 张力摆辊控制双工位切换 | 行业池 | 高 | 4 |
| 19 | FB_DL_HydrostaticLevelComp | Process | FB | 静压液位介质密度温补 | 行业池 | 低 | 4 |
| 20 | FB_DL_EtchEndpointTrend | Algo | FB | 刻蚀终点趋势双判据检测 | 行业池 | 中 | 4 |

## §2 每件规格

### 1. FB_DL_HealthArbiter（Device）
- 签名：IN `aiHealth:ARRAY[1..DL_HA_SRC_MAX] OF I_DL_DeviceHealth`、`uSrcCount:UINT`、`bRst:BOOL`；OUT `eWorst:E_DL_Ne107Status`、`uWorstSrc:UINT`、`uFaultCnt/uMaintCnt:UINT`、`bChanged:BOOL`、`uErrorId:UINT`。
- 算法：按 NE107 编号即优先级线性扫描各源 eStatus 取最差仲裁；同拍同级取下标最小；bChanged 用与上次锁存结果比较出沿；空引用按 eUnknown 参与仲裁并计数。
- 边界：0 源或全空引用 → eUnknown+信息码不锁故障；下标先判界再取引用；每拍无条件重算无定时器。
- 错误码：05x0 信息级（0 源/空引用/计数钳位），不置 bError。
- 注意：`E_DL_Ne107Status` 唯一属主已存在只引用；头注释写「采用公开 NE107 健康语言」不写「符合认证」。

### 2. FC_DL_PolarTransform2D（MathData，纯函数）
- 签名：IN `fX,fY:LREAL`、`eMode:E_DL_PolarMode`(eToPolar/eToCart)；OUT `fA,fB:LREAL`（极：半径/角度deg；直角：x/y）、`bValid:BOOL`、`uErrorId:UINT`。
- 算法：正变换 r=SQRT(x²+y²) 先取 max 分量归一防平方溢出（CalcDistance3D 范式）、ATAN2 归一到 [0,360)；逆变换 x=r·COS、y=r·SIN，角度先归一防大角度精度损失。
- 边界：非有限早退 bValid=FALSE；原点正变换合法 r=0 θ=0 写死头注释；r<0 按非法拒绝（负半径语义歧义不替调用方定）。
- 错误码：01x0 信息级（非有限/负半径/超域角度钳位）。
- 注意：矩阵裁定矩阵 SVD/特征值方向不立，不得顺手扩展；角度单位 deg 必入注释。

### 3. FB_DL_EnthalpyChangeover（Process）
- 签名：IN `fEnthOA,fEnthRA:kJ/kg`（调用方用 FC_DL_HumidAirEnthalpy 预算注入）、`fDiffMin:kJ/kg`、`eMode:E_DL_ChangeoverMode`(eAuto/eManualOA/eManualRA)、`bEn:BOOL`；OUT `eSelect:E_DL_AirSource`(eOA/eRA)、`bSwitching:BOOL`、`uErrorId:UINT`。
- 算法：自动态「新风焓<回风焓−fDiffMin」判新风优先，带回差不对称双向判定防振荡；手动态直通锁存；切换经 tMinDwell 最小驻留抑制频切。
- 边界：任一焓值非有限保持上次选择+信息码；fDiffMin<0 钳 0 记参数码；首拍初始化为回风（保守侧）。
- 错误码：05x0 信息级（非有限/参数钳位/驻留期请求被拒）。
- 注意：T1-2 R25 已开 ROOM_CONTROL 族，只借行为定义零代码复制；与已收口 EnthalpyCompareCtrl（单回路执行块）职责边界表必写——本件是模式仲裁层。

### 4. FB_DL_NightPurgeCtrl（Process）
- 签名：IN `bEn:BOOL`、`dtNow:DTL`、`fTOut,fTIn:°C`、`fRhOut,fRhIn:%`、`tPurgeWin:TIME`、`bOcc:BOOL`；OUT `bPurgeReq:BOOL`、`eState:E_DL_PurgeState`、`uErrorId:UINT`。
- 算法：无占用+室外比室内凉（带死区）+室外绝对湿度≤室内（Magnus-Tetens 常数唯一属主 FC_DL_VaporPressureSat 只调用）三判据同时成立进入；窗时到或判据失效退出；tCooldown 重启抑制防频启。
- 边界：dtNow/湿度非有限钳位或保持现状+信息码；TON/TOF 主周期无条件刷新；CASE 有 ELSE 锁安全侧（不吹扫）。
- 错误码：05x0 信息级（非有限/时间域外/冷却期请求）。
- 注意：ROOM_CONTROL 待挖子项即本件；吹扫=降温除湿侧方向写死，不得出「加热吹扫」变体。

### 5. I_DL_ExternalEncoder（Motion，接口）
- 契约：PROPERTY_GET `fPos:LREAL`(mm)、`fVel:LREAL`(mm/s)、`bValid:BOOL`；METHOD `Sample(OUT stSnap:ST_DL_EncSnapshot):BOOL`；METHOD `Reset()`。
- 算法：定义「外部编码器=只读位置源」最小契约，Sample 单拍一致快照（位置+速度+时戳同拍锁定）；核心语义：外部编码器不可被驱动，无任何命令方向。
- 边界：接口无实现；文档段写明「实现块不得在本接口后挂写方法」。
- 错误码：无（契约件），bValid=FALSE 由实现块解释。
- 注意：主源记 T1-6、T2-4 不重复记账；接口契约描述必写头注释。

### 6. FB_DL_ExternalEncoderLatch（Motion）
- 签名：IN `iEnc:I_DL_ExternalEncoder`、`bTrig:BOOL`、`bEn:BOOL`、`tStale:TIME`；OUT `stLatch:ST_DL_EncSnapshot`、`bLatchValid:BOOL`、`bStale:BOOL`、`uErrorId:UINT`。
- 算法：bTrig 上升沿（R_TRIG 主周期无条件刷新）调 iEnc.Sample 写入一致快照；每拍比对当前 fPos 与锁存差超容差且 tStale 到 → bStale 提示；清锁存仅由 bEn 下降或 Reset 显式。
- 边界：iEnc 空引用 → bLatchValid=FALSE+信息码且 bError 置位源能在 uErrorId 找到码（R45）；采样 FALSE 本拍保持旧值；非有限快照拒绝入库。
- 错误码：04x0（空引用/采样失败/快照非有限/过期提示）。
- 注意：不自造不消费轴状态枚举（R31 家族高危区）；与 FB_DL_MarkPositionLatch 职责边界表必写（Mark=轴内探针锁存，本件=外部源锁存）。

### 7. FB_DL_EscChuckCurrentMon（Device）
- 签名：IN `fIAds, fISet, fWinLo, fWinHi:A`、`bWafer:BOOL`、`bEn:BOOL`、`tConf:TIME`；OUT `eHealth:E_DL_Ne107Status`、`fIDev:A`、`bError:BOOL`、`uErrorId:UINT`。
- 算法：电流带外（低于 fWinLo=吸附不足/高于 fWinHi=放电异常）持续 tConf 判级：吸附不足→eOutOfSpec、放电异常→eFailure；bWafer 与电流交叉：无片时电流低为合法豁免。
- 边界：非有限电流→eUnknown+信息码不猜；fWinLo≥fWinHi 参数非法不投判级只出组态码；TON 输入每拍无条件刷新；恢复需回带内持续 tConf 对称确认。
- 错误码：03x0（信息级：非有限/参数非法/无片豁免；故障级：吸附不足/放电异常）。
- 注意：矩阵 ESC 行待挖子项，clean-room 自研无外部源；等级→健康映射写死头注释，NE107 主源记 T2-8 不重复记账。

### 8. FB_DL_PnAlarmDiagParse（Device）
- 签名：IN `uAlmType:BYTE`、`uSlot,uPort:USINT`、`uDiagCode:WORD`、`bNew:BOOL`；OUT `eSev:E_DL_DiagSev`、`sText:STRING`、`bRetryable:BOOL`、`uErrorId:UINT`。
- 算法：借「告警码→语义三出口（严重度/中文描述/可重试性）」公开 PN 告警分级语义 clean-room；查表驱动（段表参考 StatusWordSegDecoder 范式），未收录码兜底「未知-告警-不可重试」。
- 边界：槽/端口 0 或超上限非法早退信息级；表驱动循环带 DL_GUARD_MAX；字符串按 R37 定宽样板 bTruncated 显式置位。
- 错误码：03x0 信息级（入参非法/码未收录），仅监视件不置 bError。
- 注意：T1-7 待挖子项即本件；四元组一律引脚注入不绑厂商系统变量名、零厂商专有库依赖。

### 9. FB_DL_WaferHandoffSeq（Device）
- 签名：IN `bReqA,bReqB,bPosA,bPosB,bGripA,bGripB:BOOL`、`bEn:BOOL`、`tStep:TIME`；OUT `eStep:E_DL_HandoffStep`、`bMoveA,bMoveB:BOOL`、`bDone,bError:BOOL`、`uErrorId:UINT`。
- 算法：七步握手（A/B 就位→A 释放→B 吸持→A 撤离→B 撤离→完成）；互斥核心：任一方未撤离另一方不得进交接区（bMove 与对方撤离位互锁）；步超时锁故障。
- 边界：双请求同拍按固定优先 A 先（写死头注释）；到位信号非预期跳变即中止锁故障；CASE 有 ELSE；TON 按步断输入（R40）。
- 错误码：03x0（步超时/互锁违例/反馈矛盾，故障级）。
- 注意：不套通用 InterlockMatrix（判定段与执行段不共享状态机教训）；防碰撞为安全侧语义。

### 10. FB_DL_SlurryStirrerCtrl（Device）
- 签名：IN `bRun:BOOL`、`fTrq1,fTrq2, fTrqMax:Nm`、`fSyncTol:%`、`tConf:TIME`；OUT `bStart1,bStart2:BOOL`、`bSyncOk:BOOL`、`eHealth:E_DL_Ne107Status`、`bError:BOOL`、`uErrorId:UINT`。
- 算法：双电机同启（主从启差≤tSync 防涌流）；同步监视=|fTrq1−fTrq2|/max(均值,1E-6) 超 fSyncTol 持续 tConf → 摘从机降级 eMaintenanceReq；单机超 fTrqMax 停该机锁故障。
- 边界：扭矩非有限按传感器失效摘除不猜值；均值防除零 max(·,1E-6)；启停 TON/TOF 无条件刷新；CASE 有 ELSE。
- 错误码：03x0（信息级：传感器失效/参数钳位；故障级：扭矩超限/同步失稳）。
- 注意：ROADMAP 注明粘度趋势判据依赖 FB_DL_Differentiator——引脚注入消费不内联，头注释列依赖表；单位 Nm 必标。

### 11. FB_DL_ChamberLeakRate（Process）
- 签名：IN `bStart:BOOL`、`fP1,fP2:Pa`（测量窗起止压强外部注入）、`fV:m³`、`tWin:s`、`fLeakLim:Pa·m³/s`；OUT `fLeakRate:Pa·m³/s`、`bPass:BOOL`、`eState:E_DL_LeakTestState`、`bError:BOOL`、`uErrorId:UINT`。
- 算法：压升法 Q=(P2−P1)·V/tWin；三态（稳压→测量→判定）；bPass=Q≤fLeakLim 带 1E-6 相对浮点余量不做严格<。
- 边界：tWin≤0 或 V≤0 参数非法早退；P2<P1（反向/温降）判 PASS 记信息码（保守侧不误杀）；非有限全拦；tWin 整除/除零两点向量进验收（终审两式之整数进位点）。
- 错误码：05x0（信息级：参数非法/反向压差；故障级：测量窗中断）。
- 注意：与 EscHeLeakCheck 职责边界表必写（He 背冷三段 vs 本件通用压升法，不合并）。

### 12. FB_DL_VacuumChamberSeq（Process）
- 签名：IN `bStart,bAbort:BOOL`、`fPNow,fPTgt,fPRough:Pa`、`bLeakOk:BOOL`、`tStepMax:TIME`；OUT `ePhase:E_DL_VacPhase`(eIdle/eRough/eFine/eLeakTest/eVent/eFault)、`bPumpRough,bPumpFine,bVent:BOOL`、`bDone,bError:BOOL`、`uErrorId:UINT`。
- 算法：五相顺控：粗抽至 fPRough→精抽至 fPTgt（迟滞防边界抖动）→检漏（消费 bLeakOk）→放气（速率经斜坡限幅防冲击）；相转换本拍复验数据源（R42）；步超时锁故障。
- 边界：压强非有限冻结当前相+信息码；bAbort 安全退出先停泵再放气次序写死；CASE 有 ELSE 锁安全侧；TON 按相断输入。
- 错误码：05x0（信息级：非有限/迟滞等待；故障级：相超时/联锁违例）。
- 注意：不含工艺加热纯真空顺控原子；头注释写与 SlitValveInterlock 的组合建议。

### 13. FB_DL_CleanRoomPressure（Process）
- 签名：IN `afDp:ARRAY[1..DL_CR_ROOM_MAX] OF LREAL`(Pa)、`uRoomCnt:UINT`、`afSet:ARRAY[...](梯度设定)`、`fBand:Pa`、`bEn:BOOL`；OUT `abBoost:ARRAY[...](加大风量请求)`、`bInvert:BOOL`、`uErrorId:UINT`。
- 算法：梯度校验先于控制——逐室核对 afSet[i]>afSet[i+1]（洁净度递减方向），倒置即 bInvert 锁存并冻结投切（防倒流最高优先）；控制层各室独立带回差双限。
- 边界：uRoomCnt 钳上限、越界逐位清零；非有限压差该室退出仲裁计掩码；首拍全 FALSE。
- 错误码：05x0（信息级：非有限/计数钳位；故障级：梯度倒置）。
- 注意：梯度倒置锁存必须有可达解除式且复位通道不得被 NOT bEn 屏蔽（终审两式之一）。

### 14. FB_DL_ReactorStepCtrl（Process）
- 签名：IN `bStart,bHold,bAbort:BOOL`、`fTNow:°C`、`fPNow:kPa`、`stRecipe:ST_DL_ReactorRecipe`（升温斜率/保温温带/滴加量/冷却目标）、`bFeedAck:BOOL`；OUT `eStep:E_DL_ReactorStep`、`fTSet:°C`、`bFeedReq:BOOL`、`bDone,bError:BOOL`、`uErrorId:UINT`。
- 算法：四工步 CASE 顺控（升温→保温→滴加→冷却）；fTSet 经库内 FB_DL_RampGenerator 斜坡不内联；超温超压独立监视层与顺控层分离；滴加相以 bFeedAck 为终点带步超时。
- 边界：配方域校验先于启动（斜率≤0/温带倒置拒启动）；bHold 在步骤边界生效、恢复不重头（ISA-88 相语义主源记 T2-8）；CASE 有 ELSE 锁安全侧（fTSet 回 0）。
- 错误码：05x0（信息级：配方钳位/暂停挂起；故障级：超温/超压/步超时/反馈缺失）。
- 注意：复用清单头注释列全；不内联 PID（上层闭环外置）。

### 15. FB_DL_FlowTotalizer（Process）
- 签名：IN `fFlow:L/min`、`bRstBatch:BOOL`、`bEn:BOOL`、`tSample:TIME`；OUT `fTotalBatch, fTotalLife:L`、`bBatchFull:BOOL`、`uErrorId:UINT`。
- 算法：ΔV=fFlow·Δt，Δt 取实际运行时间差非定时器假设值防扫描抖动误差；清零沿先保存结算快照再清批次；寿命累计饱和 DL_TOTAL_MAX 防溢出。
- 边界：fFlow 非有限本拍按 0 积分记信息码不中断；Δt≤0 或超扫描周期 10 倍按上次有效值钳位；清零沿与积分同拍冲突先积分后清零（不丢该拍）。
- 错误码：05x0 信息级（非有限/Δt 钳位/批满提示）。
- 注意：与 EnergyMeterAccum 边界写明（kWh vs L 不合并）；批满后停/续由调用方定。

### 16. FB_DL_TankLevelCtrl（Process）
- 签名：IN `fLevel:%`、`bHiHi,bLoLo:BOOL`（独立硬联锁）、`bP1Fb,bP2Fb:BOOL`、`bAuto:BOOL`、`tMinRun,tMinOff:TIME`；OUT `bP1Req,bP2Req:BOOL`、`bLead:UINT`、`bError:BOOL`、`uErrorId:UINT`。
- 算法：双泵交替轮值（运行时长达标或手动切换沿交棒，停止侧安全执行）；Lo 启 Hi 停回差带；最短运行/停机防频启；HiHi/LoLo 硬联锁直接切输出不进状态机（独立窗）。
- 边界：液位非有限冻结投切+信息码；双泵反馈双失效锁故障；交棒时新主泵启确认后才停旧泵（不断流时序写死）。
- 错误码：05x0（信息级：非有限/交棒等待；故障级：双泵失效/硬联锁触发）。
- 注意：轮值参考 DutyStandbyRotation 范式但本件带液位回差是工艺件，职责边界写头注释。

### 17. FB_DL_UtilitiesLoadMgr（Process）
- 签名：IN `afLoad:ARRAY[1..DL_ULD_MAX] OF %`、`uMachCnt:UINT`、`fStartTh,fStopTh:%`、`uMinRun,uMaxRun:UINT`、`bAuto:BOOL`；OUT `abRun:ARRAY[...] OF BOOL`、`uRunCnt:UINT`、`bError:BOOL`、`uErrorId:UINT`。
- 算法：加权平均负载对照回差双阈值（fStartTh>fStopTh 防振荡）定增/减台数；投切按累计运行时长均衡轮值（DutyStandbyRotation 思想库内复用）；台数变更经 tDwell 驻留。
- 边界：uMachCnt=0 或阈值倒置组态码不投切；非有限负载该机权重归零后均值重算防除零；越界逐位清零。
- 错误码：05x0 信息级为主（组态非法/非有限/台数钳位），仅指令与反馈持续矛盾置故障级。
- 注意：空压机/冷冻机通用，不得出「冷机专用变体」；负载率 % 必标。

### 18. FB_DL_FilmTensionDancer（Process）
- 签名：IN `fDancerPos:%`、`fTensionSet:N`、`fRollD:mm`（FC_DL_CoilDiameterCalc 外部注入）、`eSide:E_DL_WindSide`(eUnwind/eRewind)、`bWeb:BOOL`、`bEn:BOOL`；OUT `fSpdTrim:%`、`fTrqSet:%`、`eState:E_DL_DancerState`、`bError:BOOL`、`uErrorId:UINT`。
- 算法：摆辊中位带偏差→PI 修正 fSpdTrim（放/收卷作用方向由 eSide 归一集中一处防符号错）；fTrqSet=锥度张力给定=fTensionSet·(fRollD/fRoll0)；bWeb 失效沿冻结输出回中。
- 边界：fRollD≤0 或非有限锥度输出冻结+信息码；PI 带 anti-windup（限幅处反算）；摆辊超行程持续确认锁故障。
- 错误码：05x0（信息级：非有限/断料冻结；故障级：超行程）。
- 注意：与 WindingTensionCtrl 职责边界表必写（摆辊位移反馈 vs 张力传感器闭环）；复用其分层思想不复制实现。

### 19. FB_DL_HydrostaticLevelComp（Process）
- 签名：IN `fPMeas:kPa`、`fTCurve:ARRAY[1..DL_HLC_PT_MAX] OF ST_DL_Pt2`（温度-密度标定表）、`fTNow:°C`、`fDpOffset:kPa`、`bEn:BOOL`；OUT `fLevel:m`、`fDensity:kg/m³`、`bValid:BOOL`、`uErrorId:UINT`。
- 算法：fDensity 由温-密表分段线性插值（FC_DL_MultiPointLinear 语义库内复用）；fLevel=(fPMeas−fDpOffset)/(fDensity·g)，g=9.80665 m/s² 常量写死头注释；表外温度最近端点钳位记信息码。
- 边界：fDensity≤1E-6 拒算早退防除零；非有限全拦；标定表须单调递增否则组态码锁存；表点数 0/1 组态非法。
- 错误码：05x0（信息级：温度钳位；故障级：密度退化/表非单调/表空）。
- 注意：密度 kg/m³、液位 m 必标；不得与其他液位件合并。

### 20. FB_DL_EtchEndpointTrend（Algo）
- 签名：IN `fSignal:LREAL`、`bRun:BOOL`、`fSlopeTh:单位/分钟`、`fNoiseWin:LREAL`、`tConf:TIME`、`fBaseline:LREAL`；OUT `bEndpoint:BOOL`、`fSlope:单位/分钟`、`eState:E_DL_EndpointState`(eLearning/eMonitor/eTriggered)、`bError:BOOL`、`uErrorId:UINT`。
- 算法：学习相采基线（均值/噪声窗），监视相用库内 FB_DL_Differentiator 求变化率（引脚注入不内联）；|fSlope| 超 fSlopeTh 且突破 fNoiseWin 持续 tConf → 终点触发锁存，保持至 bRun 下降显式复位。
- 边界：信号非有限冻结评估+信息码（学习相非有限则学习重启）；样本不足不出判定；斜率时间差≤0 防除零；TON 无条件刷新。
- 错误码：02x0（信息级：非有限/学习重启/样本不足；故障级：确认窗中断判据矛盾）。
- 注意：主源记行业池，Measurement 行统计族语义邻接不重复记账；头注释列 Differentiator 依赖表；斜率量纲占位说明必写。

## §3 码位分配（实测游标：python 遍历 registry 539 件 code_segment 逐类取最大槽尾）

| 分类 | 前缀 | 实测游标 | 本轮分配 |
|---|---|---|---|
| DL_Device | 16#03_0_ | ~F1（RackDiagSummary） | HealthArbiter F2~F6、EscChuckCurrentMon F7~FB、PnAlarmDiagParse FC~100、WaferHandoffSeq 101~105、SlurryStirrerCtrl 106~10A（均 5 槽，首槽信息级，次槽起故障级） |
| DL_Process | 16#05_0_ | ~8E（CoatingGapMeasure） | EnthalpyChangeover 8F~93、NightPurgeCtrl 94~98、ChamberLeakRate 99~9D、VacuumChamberSeq 9E~A2、CleanRoomPressure A3~A7、ReactorStepCtrl A8~AC、FlowTotalizer AD~B1、TankLevelCtrl B2~B6、UtilitiesLoadMgr B7~BB、FilmTensionDancer BC~C0、HydrostaticLevelComp C1~C5（均 5 槽） |
| DL_Motion | 16#04_0_ | ~62（ElectrodeRollDiameter） | I_DL_ExternalEncoder 63~66（接口 4 槽）、ExternalEncoderLatch 67~6B（5 槽） |
| DL_MathData | 16#01_0_ | ~91（BitArraySegCopy，与 DL_Base 共池） | PolarTransform2D 92~95（FC 纯函数 4 槽） |
| DL_Algo | 16#02_3_ | ~32（ChwDifferentialPressure） | EtchEndpointTrend 33~37（5 槽） |

## §4 查重声明（python 全量 name 提取 → `grep -qx` 精确匹配，539 条基线）

| 组件名 | 结果 |
|---|---|
| FB_DL_HealthArbiter / FC_DL_PolarTransform2D / FB_DL_EnthalpyChangeover / FB_DL_NightPurgeCtrl / I_DL_ExternalEncoder / FB_DL_ExternalEncoderLatch / FB_DL_EscChuckCurrentMon / FB_DL_PnAlarmDiagParse | 8 件均未存在 ✔ |
| FB_DL_WaferHandoffSeq / FB_DL_SlurryStirrerCtrl / FB_DL_ChamberLeakRate / FB_DL_VacuumChamberSeq / FB_DL_CleanRoomPressure / FB_DL_ReactorStepCtrl / FB_DL_FlowTotalizer / FB_DL_TankLevelCtrl / FB_DL_UtilitiesLoadMgr / FB_DL_FilmTensionDancer / FB_DL_HydrostaticLevelComp / FB_DL_EtchEndpointTrend | 12 件均未存在 ✔ |
| 淘汰记录 | MfcFlowCtrl / TrackBarcodeTrace / CartonErectorStation / PalletizerStation / StringBarcodeTrace **已存在**（台账滞后）淘汰；CartonScannerSort 未存在但与已注册 trace 族同义，按「不得再造同义变体」不派 |

**配额自查**：T0 补位 0/4 ✔（P0 三条码线已注册，不造变体）｜T2 组件族 ≥1 ✔（NE107 + LGF Math + T1-2 两件）｜T1 组 ✔（T1-6 外部编码器族开族 2 件）｜MathData 仅 1 件 ✔。

---

## §5 派单勘误（主控 R31 实测改派，优先级高于 §1/§2 对应条目）

**改派原因**：主控对 registry 539 名做全量 grep 后发现两处同义撞车（R148 红线口径：跨子库/同义变体同算撞名）：
- 序 1 `FB_DL_HealthArbiter` ≡ 已注册 `FB_DL_DeviceHealthArbiter`（R19 入库，同为 NE107 多源健康聚合仲裁）→ **作废**
- 序 7 `FB_DL_EscChuckCurrentMon` ≡ 已注册 `FB_DL_EscChuckCurrentMonitor`（R19 入库，同为 ESC 吸附电流监视）→ **作废**

**替代件如下，编码按本节规格执行；码位段沿用原分配（不改码位台账）。**

### 5.1 序 1 替代件 `FB_DL_LamDoorInterlock`（DL_Device，FB，码位 `16#03_0_ F2~F6`）
光伏层压机炉门三联锁：开门放行须同时满足「门已关闭 + 门锁已锁止 + 腔体真空达标 + 腔温 ≤ 安全上限」。
- 输入：`bEnable` BOOL、`bDoorClosed` BOOL、`bDoorLocked` BOOL、`bChamberVacOk` BOOL、`fChamberTemp` REAL、`fSafeTempMax` REAL := 60.0、`bOpenRequest` BOOL、`tReleaseDelay` TIME := T#1S、`bReset` BOOL
- 输出：`bAllowOpen` BOOL、`bUnlockCmd` BOOL、`bError` BOOL、`eState` E_DL_LamDoorState（eIdle/eArmed/eReleasing/eFault）、`uErrorId` UDINT、`sStatus` STRING[80]
- 算法：每拍算四条件 AND → 满足且 `bOpenRequest` 上升沿进 eReleasing；`tReleaseDelay` 计时到则 `bUnlockCmd := TRUE` 并进 eArmed；条件任失立即退出放行（`bAllowOpen := FALSE`、`bUnlockCmd := FALSE`）
- 边界安全：① 温度 `fChamberTemp` 非有限或 `fSafeTempMax <= 0.0` → 判不达标走安全侧（禁放行）并置故障码；② `TON` 实例每拍**无条件**刷新（红线 7，禁放 IF 内）；③ `bEnable = FALSE` 时强制清 `bUnlockCmd` 但**不得**屏蔽 `bReset`（R38）；④ 开门请求用 `R_TRIG` 且实例每拍无条件刷新
- 码位：F2 信息级（条件回落清码）/ F3 腔温非法 / F4 真空未达 / F5 解锁确认超时 / F6 状态非法（ELSE 兜底 eFault）

### 5.2 序 7 替代件 `FB_DL_DosingPumpCalib`（DL_Device，FB，码位 `16#03_0_ F7~FB`）
计量泵标定与脉冲当量校验：由标定容积与实测容积反算实测当量 mL/pulse，与组态当量比偏差，超差报警并给出修正当量。
- 输入：`bStart` BOOL、`bAbort` BOOL、`fCalVolumeMl` REAL、`fMeasuredMl` REAL、`uPulseCount` UDINT、`fNominalMlPerPulse` REAL、`fTolPct` REAL := 2.0、`uMinPulses` UDINT := 100
- 输出：`bBusy` BOOL、`bDone` BOOL、`bError` BOOL、`fMeasuredMlPerPulse` REAL、`fDeviationPct` REAL、`fCorrectedMlPerPulse` REAL、`uErrorId` UDINT
- 算法：`fMeasuredMlPerPulse := fMeasuredMl / UINT_TO_REAL(uPulseCount)`（先判分母>0）；`fDeviationPct := (实测−组态)/组态 × 100.0`；`fCorrectedMlPerPulse` 按偏差反向修正后**夹在 0.5×组态 ~ 2.0×组态**
- 边界安全：① `uPulseCount < uMinPulses` 判样本不足，拒绝出结果；② `fNominalMlPerPulse <= 0.0` 或非有限 → 故障并冻结输出（保持末次有效值，禁用 0 覆盖）；③ 分母为零防护；④ `bAbort` 立即清 busy、不产出半结果、不置 done；⑤ `bDone` 为新沿后的**单拍脉冲**（R27 输出保持语义：跨拍须清零）；⑥ 偏差超差仅告警（eWarn 级），不阻断产线
- 码位：F7 信息级 / F8 样本不足 / F9 容积非法 / FA 当量非法 / FB 偏差超限
