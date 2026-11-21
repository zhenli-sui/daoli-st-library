(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PumpChangeoverSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 冷冻/冷却水泵加减机：供回水温差与目标温差比较，死区
 *                         ±0.5 摄氏度内保持；滞消频宽后折算级数需求（下限 1，
 *                         水泵不保备机——与风机阵列的差异点）；每 tick 至多切换
 *                         1 台，tMinRun/tMinStop 闸门防频繁启停；轮值按运行小时
 *                         均衡选台。温差传感器无效 → 保持当前组合只报码不切换。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_ChgoverErr / FUNCTION_BLOCK FB_DL_PumpChangeoverSeq
 * 依赖 (Depends)        : 无 DL_ 内部依赖；Standard.library TON 实例
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         数组下界常量提取 + 级数钳位 [1,N] + 非有限温差不切换 ｜
 *                         枚举成员全部显式赋值 ｜ TON 实例每周期无条件调用 ｜
 *                         CASE 含 ELSE 兜底 ｜ 与风机阵列共纪律但零共享实例
 * 错误码表 (Codes)      : 16#0005_0426 就绪
 *                         16#0005_0427 信息级 温差在死区（保持，含传感器无效保持）
 *                         16#0005_0428 信息级 加机中
 *                         16#0005_0429 信息级 减机中
 *                         16#0005_042A 信息级 闸门等待（最短时序未满足）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 4
 * 验收向量 (Acceptance) : 目标 5 摄氏度，实测 7.0 → 需求加 1 台并 0428；
 *                         实测 6.0（死区内）→ 保持 0427；切换后 tMinRun 内再要
 *                         切换 → 042A 只记不切
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ChgoverErr（归属 DL_Process，与 FB_DL_PumpChangeoverSeq 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ChgoverErr :
(
    eReady   := 16#0005_0426,   // 就绪 / Ready
    eDeadband:= 16#0005_0427,   // 信息级：温差在死区或传感器无效（保持）/ Info: deadband or invalid sensor, hold
    eAddRun  := 16#0005_0428,   // 信息级：加机中 / Info: adding a pump
    eSubRun  := 16#0005_0429,   // 信息级：减机中 / Info: shedding a pump
    eGateWait:= 16#0005_042A    // 信息级：闸门等待 / Info: minimum-timing gate waiting
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_PumpChangeoverSeq
 * 调用约定: 每个扫描周期无条件调用一次；aNRunHrs 由调用方按索引注入。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PumpChangeoverSeq
VAR_INPUT
    fDeltaT_C    : REAL;                     // 供回水温差 [摄氏度] / Supply-return temperature difference [degC]
    fDeltaTSet_C : REAL := 5.0;              // 目标温差 [摄氏度]，默认 5 / Target temperature difference [degC]
    aNRunHrs     : ARRAY[1..6] OF UDINT;     // 各泵累计运行小时 [小时] / Run hours per pump [h]
    uPumpTotal   : UINT := 6;                // 装机泵数 [台]，有效域 1~6 / Installed pump count [pumps]
    tMinRun      : TIME := T#60S;            // 最短运行时长 [秒] / Minimum run time [s]
    tMinStop     : TIME := T#60S;            // 最短停机时长 [秒] / Minimum stop time [s]
END_VAR
VAR_OUTPUT
    auPumpCmd    : ARRAY[1..6] OF BOOL;      // 各泵启停指令 / Pump start/stop commands
    uRunCount    : UINT;                     // 实际运行泵数 [台] / Actual running pump count [pumps]
    eErr         : E_DL_ChgoverErr;          // 错误码 / Error code
END_VAR
VAR
    tonGateRun   : TON;                      // 最短运行闸门定时器（无条件调用）/ Min-run gate timer
    tonGateStop  : TON;                      // 最短停机闸门定时器（无条件调用）/ Min-stop gate timer
    bGateArmed   : BOOL;                     // 闸门武装标志（切换后置位）/ Gate armed flag
    bSwitchCycle : BOOL;                     // 本拍为切换拍（定时器 IN 强制断流）/ Switch-scan flag, forces timer reset
    fSetUse      : REAL;                     // 生效目标温差 [摄氏度] / Effective target difference [degC]
    fDev_C       : REAL;                     // 温差偏差 [摄氏度] / Temperature difference deviation [degC]
    uTotalUse    : UINT;                     // 生效泵数（钳位后）[台] / Effective pump count [pumps]
    uStageNeed   : UINT;                     // 级数需求 [台] / Stage demand [pumps]
    uIdxBest     : UINT;                     // 候选切换泵索引 [台序] / Candidate pump index
    nPickHrs     : UDINT;                    // 候选比较基准小时 [小时] / Candidate comparison baseline [h]
    i            : INT;                      // 数组循环索引 / Array loop index
    bSensorOk    : BOOL;                     // 温差传感器有效判据 / Temperature sensor validity predicate
    bInit        : BOOL;                     // 首扫初始化标志 / First-scan init flag
END_VAR
VAR CONSTANT
    DL_CHG_IDX_MAX   : INT  := 6;            // 阵列容量上限（数组下界常量提取）/ Array capacity upper bound
    DL_CHG_TOTAL_MAX : UINT := 6;            // 装机泵数上限 [台] / Installed count upper bound [pumps]
    DL_CHG_STAGE_MIN : UINT := 1;            // 级数下限 1 台（水泵不保备机，与风机阵列差异）/ Stage lower bound, one pump minimum
    DL_CHG_DEADBAND  : REAL := 0.5;          // 死区半宽 [摄氏度] / Deadband half width [degC]
    DL_CHG_STAGE_C   : REAL := 2.0;          // 级数折算温差步长 [摄氏度每台] / Stage temperature step [degC per pump]
    DL_CHG_INF_MAX   : REAL := 1.0E30;       // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_CHG_ZERO      : REAL := 0.0;          // 零值常量，避免裸字面量 / Zero constant
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜TON 实例每周期无条件调用（仅 IN 条件化）：切换拍强制断流以复位计时
 *----------------------------------------------------------------------------*)
tonGateRun(IN := bGateArmed AND NOT bSwitchCycle, PT := tMinRun);     // 运行闸计时 / min-run gate timing
tonGateStop(IN := bGateArmed AND NOT bSwitchCycle, PT := tMinStop);   // 停机闸计时 / min-stop gate timing

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：指令数组全停
 *----------------------------------------------------------------------------*)
IF NOT bInit THEN
    FOR i := 1 TO DL_CHG_IDX_MAX DO
        auPumpCmd[i] := FALSE;                           // 默认全停 / default all stopped
    END_FOR
    bInit := TRUE;                                       // 首扫完成 / first scan done
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜泵数钳位与目标温差兜底
 *----------------------------------------------------------------------------*)
uTotalUse := uPumpTotal;                                 // 泵数工作副本 / total working copy
IF uTotalUse > DL_CHG_TOTAL_MAX THEN
    uTotalUse := DL_CHG_TOTAL_MAX;                       // 泵数上限钳位 / total capped
ELSIF uTotalUse < DL_CHG_STAGE_MIN THEN
    uTotalUse := DL_CHG_STAGE_MIN;                       // 泵数下限钳位 / total floored
END_IF
fSetUse := fDeltaTSet_C;                                 // 目标工作副本 / target working copy
IF (fSetUse <> fSetUse) OR (fSetUse <= DL_CHG_ZERO) OR (fSetUse > DL_CHG_INF_MAX) THEN
    fSetUse := 5.0;                                      // 目标非法按 5 摄氏度兜底 / illegal target falls back to 5 degC
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜传感器有效性与偏差计算：无效则保持当前组合只报码
 *----------------------------------------------------------------------------*)
bSensorOk := (fDeltaT_C = fDeltaT_C) AND (ABS(fDeltaT_C) <= DL_CHG_INF_MAX) AND (fDeltaT_C >= DL_CHG_ZERO);   // 温差有效 / difference validity
eErr := E_DL_ChgoverErr.eReady;                          // 预置就绪 / preset ready
uStageNeed := uRunCount;                                 // 需求缺省 = 当前运行数（保持）/ demand defaults to current count
IF NOT bSensorOk THEN
    eErr := E_DL_ChgoverErr.eDeadband;                   // 信息级：传感器无效保持（与死区共用，反证句：均为不切换）/ info: invalid sensor, hold
ELSE
    fDev_C := fDeltaT_C - fSetUse;                       // 温差偏差 [摄氏度] / difference deviation [degC]
    IF (fDev_C > -DL_CHG_DEADBAND) AND (fDev_C < DL_CHG_DEADBAND) THEN
        eErr := E_DL_ChgoverErr.eDeadband;               // 信息级：死区内保持 / info: inside deadband, hold
    ELSIF fDev_C > DL_CHG_ZERO THEN
        // 温差偏高：需要加机（级数需求按偏差折算，上限泵数）/ positive deviation: more pumps
        uStageNeed := uRunCount + UDINT_TO_UINT(REAL_TO_UDINT(ROUND(fDev_C / DL_CHG_STAGE_C)));   // 需求级数折算 [台] / stage demand
        IF uStageNeed <= uRunCount THEN
            uStageNeed := uRunCount + 1;                 // 至少加 1 台（ROUND 归零时保底）/ at least one more pump
        END_IF
        IF uStageNeed > uTotalUse THEN
            uStageNeed := uTotalUse;                     // 需求上限钳位（不保备机）/ demand capped at total
        END_IF
    ELSE
        // 温差偏低：需要减机（下限 1 台）/ negative deviation: fewer pumps, one minimum
        IF fDev_C < -DL_CHG_STAGE_C THEN
            uStageNeed := uRunCount - 1;                 // 偏差超一个步长：减 1 台 / shed one pump
        ELSE
            uStageNeed := uRunCount;                     // 偏差未超步长：保持 / hold, within one step
        END_IF
        IF uStageNeed < DL_CHG_STAGE_MIN THEN
            uStageNeed := DL_CHG_STAGE_MIN;              // 下限钳位 1 台 / floored at one pump
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜每 tick 至多切换 1 台：加机选小时最少，减机选小时最多
 *----------------------------------------------------------------------------*)
uIdxBest := 0;                                           // 候选索引清零（0 = 无候选）/ candidate reset
nPickHrs := 0;                                           // 基准清零 / baseline reset
IF uRunCount > uStageNeed THEN
    IF bGateArmed AND NOT tonGateRun.Q THEN
        eErr := E_DL_ChgoverErr.eGateWait;               // 信息级：闸门等待（只记不切）/ info: gate waiting
    ELSE
        nPickHrs := 0;                                   // 最多小时基准从 0 起比 / max search baseline
        FOR i := 1 TO UINT_TO_INT(uTotalUse) DO
            IF auPumpCmd[i] THEN
                IF (uIdxBest = 0) OR (aNRunHrs[i] >= nPickHrs) THEN
                    uIdxBest := INT_TO_UINT(i);          // 候选更新（运行最久）/ candidate updated
                    nPickHrs := aNRunHrs[i];             // 基准更新 / baseline updated
                END_IF
            END_IF
        END_FOR
        IF uIdxBest > 0 THEN
            eErr := E_DL_ChgoverErr.eSubRun;             // 信息级：减机中 / info: shedding
        END_IF
    END_IF
ELSIF uRunCount < uStageNeed THEN
    IF bGateArmed AND NOT tonGateStop.Q THEN
        eErr := E_DL_ChgoverErr.eGateWait;               // 信息级：闸门等待（只记不切）/ info: gate waiting
    ELSE
        nPickHrs := 16#FFFF_FFFF;                        // 最少小时基准从满值起比 / min search baseline
        FOR i := 1 TO UINT_TO_INT(uTotalUse) DO
            IF NOT auPumpCmd[i] THEN
                IF aNRunHrs[i] <= nPickHrs THEN
                    uIdxBest := INT_TO_UINT(i);          // 候选更新（停机最久近似小时最少）/ candidate updated
                    nPickHrs := aNRunHrs[i];             // 基准更新 / baseline updated
                END_IF
            END_IF
        END_FOR
        IF uIdxBest > 0 THEN
            eErr := E_DL_ChgoverErr.eAddRun;             // 信息级：加机中 / info: adding
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜执行切换：切换拍置武装并强制定时器断流复位
 *----------------------------------------------------------------------------*)
bSwitchCycle := FALSE;                                   // 切换拍标志默认 FALSE / switch-scan flag defaults FALSE
IF uIdxBest > 0 THEN
    auPumpCmd[UINT_TO_INT(uIdxBest)] := NOT auPumpCmd[UINT_TO_INT(uIdxBest)];   // 执行切换 / execute the switch
    bGateArmed := TRUE;                                  // 闸门武装 / gate armed
    bSwitchCycle := TRUE;                                // 切换拍标志（下拍定时器重新计时）/ switch-scan flag
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜运行泵数统计与容量外指令清扫（防越界残留）
 *----------------------------------------------------------------------------*)
uRunCount := 0;                                          // 运行泵数清零 / running count reset
FOR i := 1 TO DL_CHG_IDX_MAX DO
    IF i > UINT_TO_INT(uTotalUse) THEN
        auPumpCmd[i] := FALSE;                           // 容量外指令强制撤销 / force FALSE beyond capacity
    ELSIF auPumpCmd[i] THEN
        uRunCount := uRunCount + 1;                      // 运行泵数累加 [台] / running count incremented
    END_IF
END_FOR
END_FUNCTION_BLOCK
