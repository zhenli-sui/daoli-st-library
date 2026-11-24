//==============================================================================
// 功能块：FB_DL_RoomClimateCtrl ｜ 中文名称：房间温湿度双回路耦合控制
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：房间温湿度双回路耦合控制：温度回路单 PID 带符号输出分程
//           （正 = 加热阀、负 = 冷却阀），湿度回路单 PID 带符号输出分
//           程（正 = 加湿阀、负 = 除湿阀），带宽死区内输出保持（PID
//           内置死区）。防结露联锁（安全联锁而非优化，头注释写明物理
//           后果：供水温度低于「露点 + 余量」时冷盘管表面结露滴水，
//           滴水进入洁净室即污染事故）→ 限制冷却/除湿阀上限并置
//           bCondensationRisk + 信息 0401。温湿同拍冲突互斥仲裁（冷侧
//           优先：冷却与加湿同拍 → 撤加湿；除湿与加热同拍 → 撤加热，
//           均置 bConflictArbitrated + 信息 0400）。PID 组合调用
//           FB_DL_PidController（两实例，不内联），露点由
//           FC_DL_DewPointCalc 计算（Magnus-Tetens 常数唯一属主
//           FC_DL_VaporPressureSat，R23 裁定，只调用不复制）。失能四
//           阀回 0%（安全侧：不制冷不加热不加湿不除湿）。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现（仅借 OSCAT ROOM_CONTROL 行为定义/参数域，零代码行与符号名复制）
// 单位表：温度[摄氏度] / 相对湿度[%] / 带宽[K 或百分数] / 阀输出[百分数] / 增益[百分数每K 或 百分数每百分数] / 积分时间[s] / 余量[K] / 扫描间隔[ms]
// 错误码表：16#0005_0400 信息级（温湿回路同拍冲突被互斥仲裁，冷侧优先，
//           不置 bError）/ 16#0005_0401 信息级（防结露联锁限制降温与
//           除湿，安全联锁生效，不置 bError）/ 16#0005_0342 故障级（设
//           定域/带宽/增益/余量组态非法，置 bError）/ 16#0005_0343 故
//           障级（输入非有限，置 bError，四阀回 0% 安全侧）/
//           16#0005_0344 故障级兜底（状态机落 ELSE 或非法状态，置
//           bError 并四阀回 0%）
// 状态机：E_DL_RoomClimateState（eIdle=0 / eAuto=10 / eInterlock=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 0344 并四阀回 0%
//           （安全侧：联锁与仲裁之外任何异常一律全关执行器）
// 边界行为：① 冷/热阀互斥（分程结构天然互斥），跨回路同拍冲突仲裁：
//           冷侧优先（冷却 ∧ 加湿 → 撤加湿；除湿 ∧ 加热 → 撤加热），
//           置 bConflictArbitrated + 信息 0400；② 防结露联锁：
//           fChwSupplyC 低于露点 + fDewMarginK → bCondensationRisk +
//           信息 0401，冷却/除湿阀上限按 (供水 − 露点)/余量 线性压缩
//           （供水贴露点 → 0%，供水达露点 + 余量 → 100%），这是安全
//           联锁而非优化；③ 带宽死区内 PID 输出保持（防阀频繁动作）；
//           ④ 设定域/带宽/增益/余量组态非法（带宽非正、温度设定超
//           0~45、湿度设定超 10~95、增益非正、余量小于 0）→ 故障 0342；
//           ⑤ 非有限（NaN 自反判 + Inf 幅值上限判，R79）→ 故障 0343，
//           四阀回 0% 安全侧；⑥ 失能 → 四阀回 0% + bValid := FALSE
//           （安全侧：不制冷不加热不加湿不除湿）；⑦ 双 PID 与露点件
//           每拍无条件调用恰好一次（实例纪律）；⑧ 贴限 bAtLimit：任
//           一阀达 100%（容差比较）；⑨ 上电首拍 bValid := FALSE。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.10，依赖 §4.1 件语义）
//           v1.0.1 2026-11-17 终审补失能出口收口（段 11，对外引脚契约零变更）：PID 件失能时
//           输出回 rOutMin = −100%，经带符号分程映射为 100% 冷却/除湿，而四阀归零只在下一拍
//           eIdle 相执行，导致「失能 = 四阀回 0%」契约在失能沿那一拍被破坏（安全侧漂移）。
//           收口放在 CASE 之后：失能电平期间出口强制 0%（不依赖相切换时序）。
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_RoomClimateState（归属 DL_Process，与 FB_DL_RoomClimateCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RoomClimateState :
(
    eIdle      := 0,   // 失能/待机：四阀回 0% / Idle: all four valves closed
    eAuto      := 10,  // 双回路自动：分程输出无联锁限制 / Auto: split-range outputs, no interlock
    eInterlock := 20,  // 防结露联锁生效：冷却/除湿被限幅 / Anti-condensation interlock: cooling and dehumidifying capped
    eFault     := 99   // 故障兜底态：组态非法/非有限/非法状态，四阀回 0% / Fault fallback, valves closed
);
END_TYPE
FUNCTION_BLOCK FB_DL_RoomClimateCtrl
VAR_INPUT
    fTempSetC      : LREAL;                    // 温度设定 [摄氏度]，域 0~45 / Temperature setpoint [degC], domain 0..45
    fTempMeasC     : LREAL;                    // 实测温度 [摄氏度] / Measured temperature [degC]
    fRhSetPct      : LREAL;                    // 湿度设定 [百分数]，域 10~95 / Humidity setpoint [percent], domain 10..95
    fRhMeasPct     : LREAL;                    // 实测湿度 [百分数] / Measured humidity [percent]
    fTempBandK     : LREAL := 0.5;             // 温度带宽 [K]，死区内输出保持 / Temperature dead band [K]
    fRhBandPct     : LREAL := 3.0;             // 湿度带宽 [百分数] / Humidity dead band [percent]
    fChwSupplyC    : LREAL;                    // 冷冻水供水温度 [摄氏度]，防结露用 / Chilled-water supply temperature [degC]
    fDewMarginK    : LREAL := 1.5;             // 防结露安全余量 [K] / Anti-condensation margin [K]
    fKpValvePctPerK : LREAL := 12.0;           // 温度回路比例增益 [百分数每K] / Temperature loop proportional gain [percent per K]
    fTiTempS       : LREAL := 180.0;           // 温度回路积分时间 [s]，0 = 纯比例 / Temperature loop integral time [s]
    fKpDehumPctPerPct : LREAL := 5.0;          // 湿度回路比例增益 [百分数每百分数] / Humidity loop proportional gain [percent per percent]
    fTiRhS         : LREAL := 240.0;           // 湿度回路积分时间 [s]，0 = 纯比例 / Humidity loop integral time [s]
    uDeltaTimeMs   : UDINT;                    // 扫描间隔 [ms]，调用方注入，禁用系统时间函数 / Scan interval [ms], caller-injected
    bEnable        : BOOL;                     // 总使能 / Master enable
    bReset         : BOOL;                     // 复位，上升沿清状态与双 PID / Reset, rising edge clears state and both PIDs
END_VAR
VAR_OUTPUT
    fCoolValvePct  : LREAL;                    // 冷却阀指令 [百分数]，与加热阀互斥 / Cooling valve command [percent], exclusive with heating
    fHeatValvePct  : LREAL;                    // 加热阀指令 [百分数]，与冷却阀互斥 / Heating valve command [percent], exclusive with cooling
    fDehumValvePct : LREAL;                    // 除湿阀指令 [百分数]，与加湿阀互斥 / Dehumidifying valve command [percent], exclusive with humidifying
    fHumValvePct   : LREAL;                    // 加湿阀指令 [百分数]，与除湿阀互斥 / Humidifying valve command [percent], exclusive with dehumidifying
    bCondensationRisk : BOOL;                 // 防结露联锁生效标志 / Anti-condensation interlock active flag
    bConflictArbitrated : BOOL;                // 同拍冲突被仲裁标志（冷侧优先）/ Conflict arbitrated this scan, cold side wins
    fDewPointC     : LREAL;                    // 室内露点 [摄氏度]，下游件计算透传 / Room dew point [degC], passed through
    bAtLimit       : BOOL;                     // 任一阀达 100% / Any valve at 100 percent
    eErr           : UDINT;                    // 错误码，0 = 无错，码位 16#0005_0400 起信息级、16#0005_0342 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                     // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                     // 控制输出可用标志，失能/故障闸显式 FALSE / Control usable flag, explicit FALSE on disable/fault gates
    eState         : E_DL_RoomClimateState;    // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset        : R_TRIG;                   // 复位上升沿检测实例 / Reset rising edge detector
    fbPidTemp      : FB_DL_PidController;      // 温度回路 PID 组合实例（DL_Algo，契约见手册）/ Temperature loop PID composed instance
    fbPidRh        : FB_DL_PidController;      // 湿度回路 PID 组合实例（DL_Algo，契约见手册）/ Humidity loop PID composed instance
    fTempReal      : REAL;                     // 温度设定降精度暂存 [摄氏度] / Temperature setpoint staging in REAL precision
    fTempMeasReal  : REAL;                     // 实测温度降精度暂存 [摄氏度] / Measured temperature staging in REAL precision
    fRhSetReal     : REAL;                     // 湿度设定降精度暂存 [百分数] / Humidity setpoint staging in REAL precision
    fRhMeasReal    : REAL;                     // 实测湿度降精度暂存 [百分数] / Measured humidity staging in REAL precision
    fTempOutReal   : REAL;                     // 温度 PID 带符号输出暂存 [百分数] / Signed temperature PID output staging
    fRhOutReal     : REAL;                     // 湿度 PID 带符号输出暂存 [百分数] / Signed humidity PID output staging
    fTempSetClamped : LREAL;                   // 钳位后温度设定 [摄氏度] / Clamped temperature setpoint [degC]
    fRhSetClamped  : LREAL;                    // 钳位后湿度设定 [百分数] / Clamped humidity setpoint [percent]
    fTempRealIn    : REAL;                     // 露点件干球输入暂存 [摄氏度] / Dew-point dry-bulb staging
    fRhRealIn      : REAL;                     // 露点件湿度输入暂存 [百分数] / Dew-point humidity staging
    fDewReal       : REAL;                     // 露点返回值暂存 [摄氏度] / Dew-point return staging
    uDewErr        : UDINT;                    // 露点件错误码暂存 / Dew-point error code staging
    fVaporPa       : REAL;                     // 露点件水汽压暂存 [Pa]（诊断透传）/ Dew-point vapor pressure staging [Pa]
    bDewInRange    : BOOL;                     // 露点件域内标志暂存 / Dew-point in-domain flag staging
    bDewOk         : BOOL;                     // 露点件结果可用判据 / Dew-point usable predicate
    fCapPct        : LREAL;                    // 联锁阀位上限 [百分数] / Interlock valve cap [percent]
    fTiTempMs      : LREAL;                    // 温度回路积分时间换算毫秒 [ms] / Temperature integral time in ms
    fTiRhMs        : LREAL;                    // 湿度回路积分时间换算毫秒 [ms] / Humidity integral time in ms
    tPidSample     : TIME;                     // PID 采样周期 [ms]（扫描间隔下限钳位）/ PID sample period, floored scan interval
    ePidErr        : UDINT;                    // PID 件错误码暂存（共用判据）/ PID error code staging
    bPidErrTemp    : BOOL;                     // 温度 PID 故障标志暂存 / Temperature PID fault flag staging
    bPidErrRh      : BOOL;                     // 湿度 PID 故障标志暂存 / Humidity PID fault flag staging
    bAnyFault      : BOOL;                     // 本拍任一 PID 故障 / Any PID fault this scan
    bFirstScan     : BOOL := TRUE;             // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_RCC_CODE_INFO_1 : UDINT := 16#0005_0400;   // 信息级槽 1（同拍冲突仲裁） / info slot 1
    DL_RCC_CODE_INFO_2 : UDINT := 16#0005_0401;   // 信息级槽 2（防结露联锁生效） / info slot 2
    DL_RCC_CODE_FLT_1  : UDINT := 16#0005_0342;   // 故障级槽 1（设定域/带宽组态非法） / fault slot 1
    DL_RCC_CODE_FLT_2  : UDINT := 16#0005_0343;   // 故障级槽 2（输入非有限） / fault slot 2
    DL_RCC_CODE_FLT_3  : UDINT := 16#0005_0344;   // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_RC_ZERO     : LREAL := 0.0;            // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_RC_TOL      : LREAL := 1.0E-6;         // 浮点比较容差 [—] / Float comparison tolerance
    DL_RC_INF      : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_RC_TEMP_MIN : LREAL := 0.0;            // 温度设定域下限 [摄氏度] / Temperature setpoint domain floor [degC]
    DL_RC_TEMP_MAX : LREAL := 45.0;           // 温度设定域上限 [摄氏度] / Temperature setpoint domain ceiling [degC]
    DL_RC_RH_MIN   : LREAL := 10.0;           // 湿度设定域下限 [百分数] / Humidity setpoint domain floor [percent]
    DL_RC_RH_MAX   : LREAL := 95.0;           // 湿度设定域上限 [百分数] / Humidity setpoint domain ceiling [percent]
    DL_RC_T_MIN    : LREAL := -40.0;          // 露点件干球钳位下限 [摄氏度] / Dew-point dry-bulb clamp floor [degC]
    DL_RC_T_MAX    : LREAL := 60.0;           // 露点件干球钳位上限 [摄氏度] / Dew-point dry-bulb clamp ceiling [degC]
    DL_RC_RH_C_MIN : LREAL := 1.0;            // 露点件湿度钳位下限 [百分数] / Dew-point humidity clamp floor [percent]
    DL_RC_RH_C_MAX : LREAL := 100.0;          // 露点件湿度钳位上限 [百分数] / Dew-point humidity clamp ceiling [percent]
    DL_RC_OUT_MAX  : LREAL := 100.0;          // 阀输出上限 [百分数] / Valve output ceiling [percent]
    DL_RC_TD_OFF   : TIME := T#0S;            // 微分关闭语义值 [s] / Derivative-off semantic value
    DL_RC_MS_PER_S : LREAL := 1000.0;         // 毫秒转秒系数 [s/ms] / Ms-to-s factor
    DL_RC_DT_MIN_MS : UDINT := 10;            // 扫描间隔下限 [ms] / Scan interval floor [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿检测在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_RoomClimateState.eIdle;
    eErr   := 16#0000_0000;                    // 复位清码 / reset clears code
    bError := FALSE;                           // 复位清故障 / reset clears fault
    bCondensationRisk := FALSE;                // 联锁标志清 / interlock flag cleared
    bConflictArbitrated := FALSE;              // 仲裁标志清 / arbitration flag cleared
    bFirstScan := TRUE;                        // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（浮点引脚逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *       命中即四阀回 0% 安全侧
 *----------------------------------------------------------------------------*)
IF (fTempSetC <> fTempSetC) OR (ABS(fTempSetC) >= DL_RC_INF)
   OR (fTempMeasC <> fTempMeasC) OR (ABS(fTempMeasC) >= DL_RC_INF)
   OR (fRhSetPct <> fRhSetPct) OR (ABS(fRhSetPct) >= DL_RC_INF)
   OR (fRhMeasPct <> fRhMeasPct) OR (ABS(fRhMeasPct) >= DL_RC_INF)
   OR (fTempBandK <> fTempBandK) OR (ABS(fTempBandK) >= DL_RC_INF)
   OR (fRhBandPct <> fRhBandPct) OR (ABS(fRhBandPct) >= DL_RC_INF)
   OR (fChwSupplyC <> fChwSupplyC) OR (ABS(fChwSupplyC) >= DL_RC_INF)
   OR (fDewMarginK <> fDewMarginK) OR (ABS(fDewMarginK) >= DL_RC_INF)
   OR (fKpValvePctPerK <> fKpValvePctPerK) OR (ABS(fKpValvePctPerK) >= DL_RC_INF)
   OR (fTiTempS <> fTiTempS) OR (ABS(fTiTempS) >= DL_RC_INF)
   OR (fKpDehumPctPerPct <> fKpDehumPctPerPct) OR (ABS(fKpDehumPctPerPct) >= DL_RC_INF)
   OR (fTiRhS <> fTiRhS) OR (ABS(fTiRhS) >= DL_RC_INF) THEN
    eState := E_DL_RoomClimateState.eFault;
    eErr   := DL_RCC_CODE_FLT_2;               // 故障级：输入非有限 / fault: non-finite input
    bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                           // 输出不可用 / outputs unusable
    fCoolValvePct := DL_RC_ZERO;               // 四阀回 0% 安全侧 / valves to zero, safe side
    fHeatValvePct := DL_RC_ZERO;               // 四阀回 0% 安全侧 / valves to zero, safe side
    fDehumValvePct := DL_RC_ZERO;              // 四阀回 0% 安全侧 / valves to zero, safe side
    fHumValvePct := DL_RC_ZERO;                // 四阀回 0% 安全侧 / valves to zero, safe side
    bCondensationRisk := FALSE;                // 故障态不判联锁 / interlock not judged in fault
    bConflictArbitrated := FALSE;              // 故障态不判仲裁 / arbitration not judged in fault
    bAtLimit := FALSE;                         // 贴限撤 / at-limit withdrawn
    fDewPointC := DL_RC_ZERO;                  // 露点出口清零 / dew-point output zeroed
    fbPidTemp(bEnable := FALSE);               // 双 PID 无条件调用保刷新（使能撤）/ both PIDs called unconditionally, enable off
    fbPidRh(bEnable := FALSE);                 // 双 PID 无条件调用保刷新（使能撤）/ both PIDs called unconditionally, enable off
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸（设定域/带宽/增益/余量）
 *----------------------------------------------------------------------------*)
IF (fTempBandK <= DL_RC_TOL) OR (fRhBandPct <= DL_RC_TOL)
   OR (fTempSetC < DL_RC_TEMP_MIN - DL_RC_TOL) OR (fTempSetC > DL_RC_TEMP_MAX + DL_RC_TOL)
   OR (fRhSetPct < DL_RC_RH_MIN - DL_RC_TOL) OR (fRhSetPct > DL_RC_RH_MAX + DL_RC_TOL)
   OR (fKpValvePctPerK <= DL_RC_TOL) OR (fKpDehumPctPerPct <= DL_RC_TOL)
   OR (fDewMarginK < DL_RC_ZERO) THEN
    eState := E_DL_RoomClimateState.eFault;
    eErr   := DL_RCC_CODE_FLT_1;               // 故障级：设定域/带宽组态非法 / fault: setpoint domain or band config invalid
    bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                           // 输出不可用 / outputs unusable
    fCoolValvePct := DL_RC_ZERO;               // 四阀回 0% 安全侧 / valves to zero, safe side
    fHeatValvePct := DL_RC_ZERO;               // 四阀回 0% 安全侧 / valves to zero, safe side
    fDehumValvePct := DL_RC_ZERO;              // 四阀回 0% 安全侧 / valves to zero, safe side
    fHumValvePct := DL_RC_ZERO;                // 四阀回 0% 安全侧 / valves to zero, safe side
    bCondensationRisk := FALSE;                // 故障态不判联锁 / interlock not judged in fault
    bConflictArbitrated := FALSE;              // 故障态不判仲裁 / arbitration not judged in fault
    bAtLimit := FALSE;                         // 贴限撤 / at-limit withdrawn
    fDewPointC := DL_RC_ZERO;                  // 露点出口清零 / dew-point output zeroed
    fbPidTemp(bEnable := FALSE);               // 双 PID 无条件调用保刷新（使能撤）/ both PIDs called unconditionally, enable off
    fbPidRh(bEnable := FALSE);                 // 双 PID 无条件调用保刷新（使能撤）/ both PIDs called unconditionally, enable off
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜露点组合调用（FC_DL_DewPointCalc，每拍恰好一次，只调用不复制）
 *----------------------------------------------------------------------------*)
fTempRealIn := LREAL_TO_REAL(fTempMeasC);      // 干球降精度显式转换 / dry-bulb explicit narrowing
fRhRealIn := LREAL_TO_REAL(fRhMeasPct);        // 湿度降精度显式转换 / humidity explicit narrowing
fDewReal := FC_DL_DewPointCalc(fTempC := fTempRealIn, fRhPct := fRhRealIn,
                               uErrorId => uDewErr, fVaporPa => fVaporPa,
                               bInRange => bDewInRange);  // 露点组合调用，返回值即露点 [摄氏度] / dew-point call
bDewOk := (uDewErr = 16#0000_0000) AND bDewInRange;    // 下游可用判据 / downstream usable predicate
IF bDewOk THEN
    fDewPointC := fDewReal;                    // 露点出口透传 / dew-point output pass-through
ELSE
    fDewPointC := fTempMeasC;                  // 防御路径：露点取干球保守估计（露点不超过干球，联锁偏紧安全侧）/ defensive: dry-bulb conservative estimate, interlock biased tight
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜双 PID 组合调用：每拍无条件执行恰好一次（实例纪律）。
 *       温度回路：PID 偏差 = 设定 − 实测，正 = 过冷需加热，负 = 过热需
 *       冷却，带符号输出分程；湿度回路同构（正 = 过干加湿，负 = 过湿
 *       除湿）；带宽死区由 PID 内置 fDeadband 承担（死区内输出保持）。
 *----------------------------------------------------------------------------*)
IF uDeltaTimeMs < DL_RC_DT_MIN_MS THEN
    tPidSample := UDINT_TO_TIME(DL_RC_DT_MIN_MS);  // 间隔过小按下限注入 / floored interval injected
ELSE
    tPidSample := UDINT_TO_TIME(uDeltaTimeMs);     // 间隔原值注入 / interval injected as-is
END_IF
fTempSetClamped := fTempSetC;                  // 温度设定工作副本（段 4 已闸域内）/ temperature setpoint working copy
fRhSetClamped := fRhSetPct;                    // 湿度设定工作副本（段 4 已闸域内）/ humidity setpoint working copy
fTempReal := LREAL_TO_REAL(fTempSetClamped);   // 温度设定降精度 / temperature setpoint narrowing
fTempMeasReal := LREAL_TO_REAL(fTempMeasC);    // 实测温度降精度 / measured temperature narrowing
fRhSetReal := LREAL_TO_REAL(fRhSetClamped);    // 湿度设定降精度 / humidity setpoint narrowing
fRhMeasReal := LREAL_TO_REAL(fRhMeasPct);      // 实测湿度降精度 / measured humidity narrowing
fTiTempMs := fTiTempS * DL_RC_MS_PER_S;        // 温度积分时间换算毫秒 [ms] / temperature integral time to ms
fTiRhMs := fTiRhS * DL_RC_MS_PER_S;            // 湿度积分时间换算毫秒 [ms] / humidity integral time to ms
fbPidTemp(bEnable := bEnable,                  // 温度 PID 每拍无条件调用 / temperature PID called unconditionally
          bManual := FALSE,                    // 纯自动 / auto only
          fSetpoint := fTempReal,              // 温度设定 [摄氏度] / temperature setpoint
          fActual := fTempMeasReal,            // 实测温度 [摄氏度] / measured temperature
          fKp := LREAL_TO_REAL(fKpValvePctPerK),           // 比例增益 [百分数每K] / proportional gain
          tTi := DINT_TO_TIME(LREAL_TO_DINT(fTiTempMs)),   // 积分时间 [ms]，0 = 纯比例 / integral time
          tTd := DL_RC_TD_OFF,                 // 微分关闭（常量语义值）/ derivative off
          fDeadband := LREAL_TO_REAL(fTempBandK),          // 温度带宽死区 [K] / temperature dead band
          bIncremental := FALSE,               // 位置式 / positional form
          rOutMin := LREAL_TO_REAL(-DL_RC_OUT_MAX),        // 输出下限（负 = 冷侧）[百分数] / output floor, negative = cooling
          rOutMax := LREAL_TO_REAL(DL_RC_OUT_MAX),         // 输出上限（正 = 热侧）[百分数] / output ceiling, positive = heating
          tSampleTime := tPidSample,           // 采样周期（已钳位）/ sample period
          bTrack := FALSE,                     // 无跟踪需求（失能由 bEnable 承担）/ no tracking need
          fTrackValue := LREAL_TO_REAL(DL_RC_ZERO),        // 跟踪值占位零 / track value zero
          bReset := fbReset.Q,                 // 复位沿透传 / reset edge passed through
          fOut => fTempOutReal,                // 带符号输出暂存 [百分数] / signed output staging
          uErrorId => ePidErr,                 // 错误码暂存 / error code staging
          bError => bPidErrTemp);              // 故障标志暂存 / fault flag staging
fbPidRh(bEnable := bEnable,                    // 湿度 PID 每拍无条件调用 / humidity PID called unconditionally
        bManual := FALSE,                      // 纯自动 / auto only
        fSetpoint := fRhSetReal,               // 湿度设定 [百分数] / humidity setpoint
        fActual := fRhMeasReal,                // 实测湿度 [百分数] / measured humidity
        fKp := LREAL_TO_REAL(fKpDehumPctPerPct),           // 比例增益 [百分数每百分数] / proportional gain
        tTi := DINT_TO_TIME(LREAL_TO_DINT(fTiRhMs)),       // 积分时间 [ms] / integral time
        tTd := DL_RC_TD_OFF,                   // 微分关闭（常量语义值）/ derivative off
        fDeadband := LREAL_TO_REAL(fRhBandPct),            // 湿度带宽死区 [百分数] / humidity dead band
        bIncremental := FALSE,                 // 位置式 / positional form
        rOutMin := LREAL_TO_REAL(-DL_RC_OUT_MAX),          // 输出下限（负 = 除湿侧）[百分数] / output floor, negative = dehumidifying
        rOutMax := LREAL_TO_REAL(DL_RC_OUT_MAX),           // 输出上限（正 = 加湿侧）[百分数] / output ceiling, positive = humidifying
        tSampleTime := tPidSample,             // 采样周期（已钳位）/ sample period
        bTrack := FALSE,                       // 无跟踪需求 / no tracking need
        fTrackValue := LREAL_TO_REAL(DL_RC_ZERO),          // 跟踪值占位零 / track value zero
        bReset := fbReset.Q,                   // 复位沿透传 / reset edge passed through
        fOut => fRhOutReal,                    // 带符号输出暂存 [百分数] / signed output staging
        uErrorId => ePidErr,                   // 错误码暂存（共用暂存，以故障标志分件）/ error code staging, shared staging
        bError => bPidErrRh);                  // 故障标志暂存 / fault flag staging
bAnyFault := bPidErrTemp OR bPidErrRh;         // 任一 PID 故障 / any PID fault

(*------------------------------------------------------------------------------
 * 段 7｜带符号分程：正出热侧、负出冷侧（结构天然互斥，同侧不可能双开）
 *----------------------------------------------------------------------------*)
IF fTempOutReal >= 0.0 THEN
    fHeatValvePct := fTempOutReal;             // 加热阀 = 正输出 [百分数] / heating = positive output
    fCoolValvePct := DL_RC_ZERO;               // 冷却阀关 / cooling closed
ELSE
    fCoolValvePct := -fTempOutReal;            // 冷却阀 = 负输出取反 [百分数] / cooling = negated output
    fHeatValvePct := DL_RC_ZERO;               // 加热阀关 / heating closed
END_IF
IF fRhOutReal >= 0.0 THEN
    fHumValvePct := fRhOutReal;                // 加湿阀 = 正输出 [百分数] / humidifying = positive output
    fDehumValvePct := DL_RC_ZERO;              // 除湿阀关 / dehumidifying closed
ELSE
    fDehumValvePct := -fRhOutReal;             // 除湿阀 = 负输出取反 [百分数] / dehumidifying = negated output
    fHumValvePct := DL_RC_ZERO;                // 加湿阀关 / humidifying closed
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜防结露联锁（安全联锁而非优化）：供水低于露点 + 余量 → 压缩冷侧阀上限
 *----------------------------------------------------------------------------*)
bCondensationRisk := fChwSupplyC < (fDewPointC + fDewMarginK);  // 联锁判据 / interlock predicate
IF bCondensationRisk THEN
    IF (fDewPointC + fDewMarginK - fChwSupplyC) >= fDewMarginK THEN
        fCapPct := DL_RC_ZERO;                 // 供水低于露点整一个余量：冷侧全关 / supply a full margin below dew point: cold side closed
    ELSE
        fCapPct := DL_RC_OUT_MAX * (fChwSupplyC - fDewPointC) / fDewMarginK;  // 线性压缩：贴露点 → 0%，达露点 + 余量 → 100% / linear cap
        IF fCapPct < DL_RC_ZERO THEN
            fCapPct := DL_RC_ZERO;             // 下限防护 / floor guard
        END_IF
        IF fCapPct > DL_RC_OUT_MAX THEN
            fCapPct := DL_RC_OUT_MAX;          // 上限防护 / ceiling guard
        END_IF
    END_IF
    IF fCoolValvePct > fCapPct THEN
        fCoolValvePct := fCapPct;              // 冷却阀被联锁限幅 / cooling capped by interlock
    END_IF
    IF fDehumValvePct > fCapPct THEN
        fDehumValvePct := fCapPct;             // 除湿阀被联锁限幅 / dehumidifying capped by interlock
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜温湿同拍冲突互斥仲裁（冷侧优先）：冷却 ∧ 加湿 → 撤加湿；
 *       除湿 ∧ 加热 → 撤加热。判据用容差比较（禁浮点判等）。
 *----------------------------------------------------------------------------*)
bConflictArbitrated := FALSE;                  // 仲裁标志逐拍重判 / arbitration flag re-judged per scan
IF (fCoolValvePct > DL_RC_TOL) AND (fHumValvePct > DL_RC_TOL) THEN
    fHumValvePct := DL_RC_ZERO;                // 冷侧优先：撤加湿 / cold side wins: humidifying withdrawn
    bConflictArbitrated := TRUE;               // 仲裁发生 / arbitrated
END_IF
IF (fDehumValvePct > DL_RC_TOL) AND (fHeatValvePct > DL_RC_TOL) THEN
    fHeatValvePct := DL_RC_ZERO;               // 冷侧优先：撤加热 / cold side wins: heating withdrawn
    bConflictArbitrated := TRUE;               // 仲裁发生 / arbitrated
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜贴限出口与状态机：CASE 含 ELSE 兜底（非法状态 → 0344 + 四阀回 0%）
 *----------------------------------------------------------------------------*)
bAtLimit := (ABS(fCoolValvePct - DL_RC_OUT_MAX) < DL_RC_TOL)
         OR (ABS(fHeatValvePct - DL_RC_OUT_MAX) < DL_RC_TOL)
         OR (ABS(fDehumValvePct - DL_RC_OUT_MAX) < DL_RC_TOL)
         OR (ABS(fHumValvePct - DL_RC_OUT_MAX) < DL_RC_TOL);   // 任一阀贴满 / any valve saturated

CASE eState OF

    E_DL_RoomClimateState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        fCoolValvePct := DL_RC_ZERO;           // 四阀回 0% 安全侧 / valves to zero, safe side
        fHeatValvePct := DL_RC_ZERO;           // 四阀回 0% 安全侧 / valves to zero, safe side
        fDehumValvePct := DL_RC_ZERO;          // 四阀回 0% 安全侧 / valves to zero, safe side
        fHumValvePct := DL_RC_ZERO;            // 四阀回 0% 安全侧 / valves to zero, safe side
        bCondensationRisk := FALSE;            // 失能不判联锁 / interlock not judged in idle
        bConflictArbitrated := FALSE;          // 失能不判仲裁 / arbitration not judged in idle
        bAtLimit := FALSE;                     // 贴限撤 / at-limit withdrawn
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable AND (NOT bAnyFault) THEN
            eState := E_DL_RoomClimateState.eAuto;     // 使能且无 PID 故障进自动 / enable without PID fault enters auto
            bFirstScan := FALSE;               // 首拍标志清除 / first-scan flag cleared
        ELSIF bEnable AND bAnyFault THEN
            eState := E_DL_RoomClimateState.eFault;    // 使能但 PID 故障：进故障相处置（不滞留待机）/ enable with PID fault: to fault phase
        END_IF

    E_DL_RoomClimateState.eAuto:
        bValid := TRUE;                        // 自动相输出可用 / usable in auto
        eErr := 16#0000_0000;                  // 自动相先清码 / auto clears code first
        bError := FALSE;                       // 自动相先清故障 / auto clears fault first
        IF bConflictArbitrated THEN
            eErr := DL_RCC_CODE_INFO_1;        // 信息级：同拍冲突被仲裁 / info: conflict arbitrated
        END_IF
        IF bCondensationRisk THEN
            eErr := DL_RCC_CODE_INFO_2;        // 信息级：防结露联锁生效（优先于仲裁提示）/ info: interlock active, outranks arbitration
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_RoomClimateState.eIdle;     // 失能回待机 / disable returns to idle
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
        ELSIF bAnyFault THEN
            eState := E_DL_RoomClimateState.eFault;    // PID 件故障透传（R115，故障相处置）/ PID fault passed through in fault phase
            eErr := DL_RCC_CODE_FLT_2;         // 复用非有限故障槽（PID 件故障 = 控制数据不可信，不升格不加码）/ reuses fault slot
            bError := TRUE;                    // 故障级必置 bError / fault-class pairs with bError
        ELSIF bCondensationRisk THEN
            eState := E_DL_RoomClimateState.eInterlock;        // 联锁生效转联锁相 / interlock enters interlock state
        END_IF

    E_DL_RoomClimateState.eInterlock:
        bValid := TRUE;                        // 联锁相输出可用（限幅后值）/ usable in interlock (capped values)
        eErr := DL_RCC_CODE_INFO_2;            // 信息级：防结露联锁生效 / info: interlock active
        bError := FALSE;                       // 信息级不置 bError / info never raises bError
        IF bConflictArbitrated THEN
            eErr := DL_RCC_CODE_INFO_1;        // 仲裁提示并列（联锁更关键，先写仲裁后写联锁）/ arbitration hint merged
            eErr := DL_RCC_CODE_INFO_2;        // 联锁码保留为出口 / interlock code kept as the outlet
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_RoomClimateState.eIdle;     // 失能回待机（第二条退出条件）/ disable returns to idle, second exit
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
            bCondensationRisk := FALSE;        // 联锁标志清 / interlock flag cleared
        ELSIF bAnyFault THEN
            eState := E_DL_RoomClimateState.eFault;    // PID 件故障透传 / PID fault passed through
            eErr := DL_RCC_CODE_FLT_2;
            bError := TRUE;
        ELSIF NOT bCondensationRisk THEN
            eState := E_DL_RoomClimateState.eAuto;     // 风险消失回自动相（第一条退出条件）/ risk gone, first exit to auto
        END_IF

    E_DL_RoomClimateState.eFault:
        bValid := FALSE;                       // 故障闸显式不可用 / explicit FALSE on fault gate
        fCoolValvePct := DL_RC_ZERO;           // 四阀回 0% 安全侧 / valves to zero, safe side
        fHeatValvePct := DL_RC_ZERO;           // 四阀回 0% 安全侧 / valves to zero, safe side
        fDehumValvePct := DL_RC_ZERO;          // 四阀回 0% 安全侧 / valves to zero, safe side
        fHumValvePct := DL_RC_ZERO;            // 四阀回 0% 安全侧 / valves to zero, safe side
        bCondensationRisk := FALSE;            // 故障态不判联锁 / interlock not judged in fault
        bConflictArbitrated := FALSE;          // 故障态不判仲裁 / arbitration not judged in fault
        bAtLimit := FALSE;                     // 贴限撤 / at-limit withdrawn
        eErr := DL_RCC_CODE_FLT_2;             // 故障级保持（PID 透传或非有限，上游闸持续命中时已在早退路径改写）/ fault held
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        IF bEnable AND (NOT bAnyFault) THEN
            eState := E_DL_RoomClimateState.eIdle;     // 故障源消失且使能：回待机重启 / fault source gone: back to idle
        END_IF

    ELSE
        eState := E_DL_RoomClimateState.eFault;        // 非法状态兜底 / illegal-state fallback
        eErr := DL_RCC_CODE_FLT_3;             // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        fCoolValvePct := DL_RC_ZERO;           // 四阀回 0% 安全侧 / valves to zero, safe side
        fHeatValvePct := DL_RC_ZERO;           // 四阀回 0% 安全侧 / valves to zero, safe side
        fDehumValvePct := DL_RC_ZERO;          // 四阀回 0% 安全侧 / valves to zero, safe side
        fHumValvePct := DL_RC_ZERO;            // 四阀回 0% 安全侧 / valves to zero, safe side
END_CASE

(*------------------------------------------------------------------------------
 * 段 11｜失能出口收口（v1.0.1 补）：PID 件的 bEnable 语义是「失能即输出回 rOutMin」，
 *       而本件两条回路的 rOutMin 均为 −100%（负 = 冷侧/除湿侧），经段 7 带符号分程会
 *       映射成 100% 冷却/除湿——失能拍恰好落在相切换那一拍（本拍仍在 eAuto/eInterlock，
 *       四阀归零要等下一拍 eIdle 相），于是「失能 = 四阀回 0%」的契约被破坏一拍。
 *       收口放在 CASE 之后、任何相之外：失能电平期间出口一律强制 0%。
 *----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    fCoolValvePct := DL_RC_ZERO;               // 失能出口收口：冷却阀 0% [百分数] / disable clamp: cooling 0 percent
    fHeatValvePct := DL_RC_ZERO;               // 失能出口收口：加热阀 0% / disable clamp: heating 0 percent
    fDehumValvePct := DL_RC_ZERO;              // 失能出口收口：除湿阀 0% / disable clamp: dehumidifying 0 percent
    fHumValvePct := DL_RC_ZERO;                // 失能出口收口：加湿阀 0% / disable clamp: humidifying 0 percent
    bAtLimit := FALSE;                         // 全关态不可能是贴限 / all-closed can never be at a limit
END_IF
END_FUNCTION_BLOCK
