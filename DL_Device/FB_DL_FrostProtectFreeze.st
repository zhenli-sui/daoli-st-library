(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FrostProtectFreeze
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 防冻保护：委托 FC_DL_Hysteresis 双阈判定（设定 ± 回差）
 *                         联动新风阀关闭 / 盘管阀开 + 风机停机；NORMAL → WARN →
 *                         TRIP（三输出同拍安全态）→ 人工复位 → RESET（条件核实）→
 *                         NORMAL。TRIP 后必须 bManualReset 才退出（安全侧保持）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_FrostState / TYPE E_DL_FrostErr /
 *                         FUNCTION_BLOCK FB_DL_FrostProtectFreeze
 * 依赖 (Depends)        : DL_MathData/FC_DL_Hysteresis
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         非有限值防御 + 量程钳位 + 回差下限钳制 ｜ 枚举成员全部显式赋值
 *                         状态机 CASE 含 ELSE 兜底（ELSE → 安全态输出）｜ 无定时器实例
 * 错误码表 (Codes)      : 16#0003_0393 NORMAL
 *                         16#0003_0394 WARN（接近防冻设定）
 *                         16#0003_0395 TRIP(冻结输出保持)
 *                         16#0003_0396 复位挂起(恢复条件未满足)
 *                         16#0003_0397 传感器无效(保持上次安全态)
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 2
 * 验收向量 (Acceptance) : 设定 4 C 回差 1 C：室外 3.0 → TRIP；室外 5.5+复位 → RESET→NORMAL；
 *                         bFrostAlarm=TRUE → 直进 TRIP；温度 NaN → 0397 保持安全态
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FrostState（归属 DL_Device，防冻状态机状态）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FrostState :
(
    eNormal := 0,    // 正常：防冻判据未触发 / Normal, no frost trip
    eWarn   := 10,   // 预警：温度接近防冻设定（迟滞带内）/ Warning, temperature near the setpoint
    eTrip   := 20,   // 跳闸：防冻触发，三输出安全态保持 / Tripped, safe outputs held
    eReset  := 30,   // 复位挂起：人工已复位但恢复条件未核实 / Reset pending, conditions unverified
    eFault  := 99    // 传感器无效兜底态 / Sensor-invalid fallback
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FrostErr（归属 DL_Device，与 FB_DL_FrostProtectFreeze 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FrostErr :
(
    eNormal    := 16#0003_0393,   // NORMAL / Normal
    eWarn      := 16#0003_0394,   // WARN（接近防冻设定）/ Warning near setpoint
    eTrip      := 16#0003_0395,   // TRIP（冻结输出保持）/ Tripped, outputs held
    eResetHold := 16#0003_0396,   // 复位挂起（条件未满足）/ Reset pending
    eSensorBad := 16#0003_0397    // 传感器无效（保持上次安全态）/ Sensor invalid
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FrostProtectFreeze
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_FrostProtectFreeze
VAR_INPUT
    fFrostTemp_C  : REAL;              // 防冻温度设定 [摄氏度]，默认 4 / Frost protection setpoint [degC]
    fOutdoor_C    : REAL;              // 室外温度 [摄氏度]，有效域 -50~60 / Outdoor temperature [degC]
    bHysteresisC  : REAL;              // 回差 [摄氏度]，默认 1.0，下限钳 0.1 / Hysteresis width [degC]
    bFrostAlarm   : BOOL;              // 盘管防冻开关输入（硬件低温断路器）/ Coil frost switch input
    bManualReset  : BOOL;              // 人工复位（TRIP 退出门票）/ Manual reset, trip exit ticket
END_VAR
VAR_OUTPUT
    bDamperCloseCmd : BOOL;            // 关新风阀指令 / Damper close command
    bCoilOpenCmd    : BOOL;            // 开盘管阀指令 / Coil valve open command
    bFanStopCmd     : BOOL;            // 风机停机指令 / Fan stop command
    eState          : E_DL_FrostState; // 防冻状态机当前状态 / Frost state machine state
    eErr            : E_DL_FrostErr;   // 错误码 / Error code
END_VAR
VAR
    bHystState   : BOOL;               // 迟滞状态（调用方持有并回传）/ Hysteresis state held by caller
    fTempUse     : REAL;               // 生效室外温度（钳位后）[摄氏度] / Effective outdoor temperature [degC]
    fSetUse      : REAL;               // 生效设定（NaN 兜底）[摄氏度] / Effective setpoint [degC]
    fHystUse     : REAL;               // 生效回差（钳位后）[摄氏度] / Effective hysteresis [degC]
    bFrostTrip   : BOOL;               // 防冻跳闸判据（迟滞+开关合成）/ Frost trip predicate
    bNonFin      : BOOL;               // 非有限输入汇总标志 / Non-finite input aggregate flag
    uHystErr     : UDINT;              // 委托迟滞错误码（0 = 无错）/ Delegate hysteresis error id
    fUpTrip      : REAL;               // 委托输出：实际上阈值 [摄氏度] / Delegate upper trip [degC]
    fLoTrip      : REAL;               // 委托输出：实际下阈值 [摄氏度] / Delegate lower trip [degC]
END_VAR
VAR CONSTANT
    DL_FRS_T_MIN    : REAL := -50.0;   // 室外温度域下限 [摄氏度] / Outdoor temperature lower bound [degC]
    DL_FRS_T_MAX    : REAL := 60.0;    // 室外温度域上限 [摄氏度] / Outdoor temperature upper bound [degC]
    DL_FRS_HYST_MIN : REAL := 0.1;     // 回差下限 [摄氏度] / Hysteresis lower bound [degC]
    DL_FRS_SET_DFLT : REAL := 4.0;     // 设定兜底值 [摄氏度] / Setpoint fallback [degC]
    DL_FRS_INF_MAX  : REAL := 1.0E30;  // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_FRS_ZERO     : REAL := 0.0;     // 零值常量，避免裸字面量 / Zero constant
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜非有限值闸：设定/温度 NaN 或溢出 → 0397 保持安全态输出
 *----------------------------------------------------------------------------*)
bNonFin := (fFrostTemp_C <> fFrostTemp_C) OR (ABS(fFrostTemp_C) > DL_FRS_INF_MAX)
        OR (fOutdoor_C    <> fOutdoor_C)    OR (ABS(fOutdoor_C)    > DL_FRS_INF_MAX)
        OR (bHysteresisC  <> bHysteresisC)  OR (ABS(bHysteresisC)  > DL_FRS_INF_MAX);
IF bNonFin THEN
    eState := E_DL_FrostState.eFault;                // 进传感器无效兜底态 / enter sensor-invalid fallback
    eErr := E_DL_FrostErr.eSensorBad;                // 信息级：传感器无效 / sensor invalid
    bDamperCloseCmd := TRUE;                         // 安全态：关新风阀 / safe: close damper
    bCoilOpenCmd := TRUE;                            // 安全态：开盘管阀 / safe: open coil valve
    bFanStopCmd := TRUE;                             // 安全态：风机停机 / safe: stop fan
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜参数钳位：室外温 [-50,60]、回差下限 0.1、设定兜底
 *----------------------------------------------------------------------------*)
fTempUse := fOutdoor_C;                              // 温度工作副本 / temperature working copy
IF fTempUse < DL_FRS_T_MIN THEN
    fTempUse := DL_FRS_T_MIN;                        // 下限钳位 / floored
ELSIF fTempUse > DL_FRS_T_MAX THEN
    fTempUse := DL_FRS_T_MAX;                        // 上限钳位 / capped
END_IF
fSetUse := fFrostTemp_C;                             // 设定工作副本 / setpoint working copy
IF (fSetUse <= DL_FRS_T_MIN) OR (fSetUse >= DL_FRS_T_MAX) THEN
    fSetUse := DL_FRS_SET_DFLT;                      // 设定出域按兜底值（配置防御）/ setpoint out of domain falls back
END_IF
fHystUse := bHysteresisC;                            // 回差工作副本 / hysteresis working copy
IF fHystUse < DL_FRS_HYST_MIN THEN
    fHystUse := DL_FRS_HYST_MIN;                     // 回差下限钳位 / hysteresis floored
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜委托迟滞双阈判定（FC_DL_Hysteresis，状态由本块持有回传）
 *----------------------------------------------------------------------------*)
FC_DL_Hysteresis(fIn := fTempUse, fThreshold := fSetUse, fHysteresis := fHystUse,
                 bState := bHystState, fUpperTrip => fUpTrip, fLowerTrip => fLoTrip,
                 uErrorId => uHystErr);              // 迟滞委托：bHystState 为 TRUE 表示温度低于下阈 / delegate: TRUE means below lower trip
bFrostTrip := bHystState OR bFrostAlarm;             // 跳闸判据 = 迟滞触发或硬件开关 / trip predicate

(*------------------------------------------------------------------------------
 * 段 4｜状态机：CASE 含 ELSE 兜底（ELSE → 安全态输出）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_FrostState.eNormal:
        bDamperCloseCmd := FALSE;                    // 正常态不关阀 / no damper close in normal
        bCoilOpenCmd := FALSE;                       // 正常态不开盘管阀 / no coil valve in normal
        bFanStopCmd := FALSE;                        // 正常态不停风机 / no fan stop in normal
        IF fTempUse < (fSetUse - fHystUse) THEN
            eState := E_DL_FrostState.eWarn;         // 接近设定：预警 / near setpoint: warning
        END_IF
        IF bFrostTrip THEN
            eState := E_DL_FrostState.eTrip;         // 跳闸判据成立：直进 TRIP / trip predicate: enter trip
        END_IF

    E_DL_FrostState.eWarn:
        bDamperCloseCmd := FALSE;                    // 预警不动作（仅提示）/ warning only, no action
        bCoilOpenCmd := FALSE;                       // 预警不动作 / no action on warning
        bFanStopCmd := FALSE;                        // 预警不动作 / no action on warning
        IF bFrostTrip THEN
            eState := E_DL_FrostState.eTrip;         // 跳闸判据成立：TRIP / trip predicate: enter trip
        ELSIF fTempUse > fSetUse THEN
            eState := E_DL_FrostState.eNormal;       // 温度回升过设定：回正常 / recovered above setpoint
        END_IF

    E_DL_FrostState.eTrip:
        bDamperCloseCmd := TRUE;                     // TRIP 安全态：关新风阀 / trip safe: close damper
        bCoilOpenCmd := TRUE;                        // TRIP 安全态：开盘管阀 / trip safe: open coil valve
        bFanStopCmd := TRUE;                         // TRIP 安全态：风机停机 / trip safe: stop fan
        IF bManualReset THEN
            eState := E_DL_FrostState.eReset;        // 人工复位进核实相 / manual reset enters reset-pending
        END_IF

    E_DL_FrostState.eReset:
        bDamperCloseCmd := TRUE;                     // 核实相保持安全态（条件未满足不撤）/ safe outputs held while unverified
        bCoilOpenCmd := TRUE;                        // 核实相保持安全态 / safe outputs held
        bFanStopCmd := TRUE;                         // 核实相保持安全态 / safe outputs held
        IF bFrostTrip THEN
            eState := E_DL_FrostState.eTrip;         // 跳闸判据仍在：退回 TRIP / predicate persists: back to trip
        ELSIF (NOT bFrostTrip) AND (fTempUse > fSetUse) THEN
            eState := E_DL_FrostState.eNormal;       // 恢复条件满足（温度过设定且开关释放）/ recovery conditions met
        ELSE
            eState := E_DL_FrostState.eReset;        // 条件未满足：复位挂起 / conditions unmet, reset pending
        END_IF

    E_DL_FrostState.eFault:
        bDamperCloseCmd := TRUE;                     // 兜底态保持安全输出 / fallback holds safe outputs
        bCoilOpenCmd := TRUE;                        // 兜底态保持安全输出 / fallback holds safe outputs
        bFanStopCmd := TRUE;                         // 兜底态保持安全输出 / fallback holds safe outputs
        IF (NOT bNonFin) THEN
            eState := E_DL_FrostState.eNormal;       // 输入恢复有限后自动回正常（传感器无效不锁存）/ auto-recover when input finite again
        END_IF

    ELSE
        eState := E_DL_FrostState.eFault;            // 非法状态兜底 / illegal-state fallback
        eErr := E_DL_FrostErr.eSensorBad;            // 兜底码（传感器无效段，反证句：输出同为三安全态）/ fallback code
        bDamperCloseCmd := TRUE;                     // 安全态输出 / safe outputs
        bCoilOpenCmd := TRUE;                        // 安全态输出 / safe outputs
        bFanStopCmd := TRUE;                         // 安全态输出 / safe outputs

END_CASE

(*------------------------------------------------------------------------------
 * 段 5｜状态码映射（信息级状态码随状态输出）
 *----------------------------------------------------------------------------*)
CASE eState OF
    E_DL_FrostState.eNormal:
        eErr := E_DL_FrostErr.eNormal;               // 码 0393 / code normal
    E_DL_FrostState.eWarn:
        eErr := E_DL_FrostErr.eWarn;                 // 码 0394 / code warn
    E_DL_FrostState.eTrip:
        eErr := E_DL_FrostErr.eTrip;                 // 码 0395 / code trip
    E_DL_FrostState.eReset:
        eErr := E_DL_FrostErr.eResetHold;            // 码 0396 / code reset pending
    E_DL_FrostState.eFault:
        eErr := E_DL_FrostErr.eSensorBad;            // 码 0397 / code sensor invalid
    ELSE
        eErr := E_DL_FrostErr.eSensorBad;            // 非法状态兜底码 / illegal-state fallback code
END_CASE
END_FUNCTION_BLOCK
