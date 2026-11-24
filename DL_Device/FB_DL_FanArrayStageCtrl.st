(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FanArrayStageCtrl
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : N+1 风机阵列分级启停：按需求级数对称加/减机，
 *                         每 tick 至多切换 1 台（加机选运行小时最少者、减机选
 *                         运行小时最多者，轮值均衡）；tMinRun/tMinStop 闸门
 *                         防频繁启停；需求级数钳位 [0, 台数-1] 预留 1 台备机。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_FanArrErr / FUNCTION_BLOCK FB_DL_FanArrayStageCtrl
 * 依赖 (Depends)        : 无 DL_ 内部依赖；Standard.library TON 实例
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         数组下界常量提取 + 防越界 ｜ 枚举成员全部显式赋值
 *                         TON 实例每周期无条件调用（仅 IN 条件化）｜ CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0003_038E 就绪
 *                         16#0003_038F 信息级 台数越界(已钳制 8)
 *                         16#0003_0390 信息级 需求级数越界(已钳制)
 *                         16#0003_0391 信息级 最短时序未满足(等待中)
 *                         16#0003_0392 信息级 运行小时数据全零(轮值退化按顺序)
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 2
 * 验收向量 (Acceptance) : total=4, req=3, 全部停机 → 逐拍加机至 3 台；
 *                         req=4 → 钳 3（预留备机）0390；切换后 tMinRun 内再要求切换 → 0391
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FanArrErr（归属 DL_Device，与 FB_DL_FanArrayStageCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FanArrErr :
(
    eReady       := 16#0003_038E,   // 就绪 / Ready
    eTotalClamp  := 16#0003_038F,   // 信息级：台数越界已钳制 / Info: total clamped
    eStageClamp  := 16#0003_0390,   // 信息级：需求级数越界已钳制 / Info: stage request clamped
    eGateWait    := 16#0003_0391,   // 信息级：最短时序未满足（等待）/ Info: min-run gate waiting
    eHrsAllZero  := 16#0003_0392    // 信息级：运行小时全零，轮值退化按顺序 / Info: all run-hours zero, round-robin degenerated
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FanArrayStageCtrl
 * 调用约定: 每个扫描周期无条件调用一次；aNRunHrs 由调用方按索引注入。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_FanArrayStageCtrl
VAR_INPUT
    aNRunHrs     : ARRAY[1..8] OF UDINT;   // 各风机累计运行小时 [小时] / Run hours per fan [h]
    uStageReq    : UINT;                   // 需求级数 [台]，有效域 0~8 / Requested stage count [fans]
    uFanTotal    : UINT;                   // 装机台数 [台]，有效域 1~8 / Installed fan count [fans]
    tMinRun      : TIME := T#60S;          // 最短运行时长 [秒] / Minimum run time [s]
    tMinStop     : TIME := T#60S;          // 最短停机时长 [秒] / Minimum stop time [s]
END_VAR
VAR_OUTPUT
    auFanCmd     : ARRAY[1..8] OF BOOL;    // 各风机启停指令 / Fan start/stop commands
    uStageAct    : UINT;                   // 实际运行级数 [台] / Actual running stage count [fans]
    eErr         : E_DL_FanArrErr;         // 错误码 / Error code
END_VAR
VAR
    tonGateRun   : TON;                    // 最短运行闸门定时器（无条件调用）/ Min-run gate timer
    tonGateStop  : TON;                    // 最短停机闸门定时器（无条件调用）/ Min-stop gate timer
    bGateArmed   : BOOL;                   // 闸门武装标志（切换后置位）/ Gate armed flag, set on any switch
    bSwitchCycle : BOOL;                   // 本拍为切换拍（定时器 IN 强制断开以复位）/ TRUE on the switch scan, forces timer reset
    uTotalUse    : UINT;                   // 生效台数（钳位后）[台] / Effective installed count [fans]
    uStageUse    : UINT;                   // 生效需求级数（钳位后）[台] / Effective requested stage [fans]
    uIdxBest     : UINT;                   // 候选切换风机索引 [台序] / Candidate fan index for switching
    uHoursZero   : INT;                    // 运行小时为零的风机计数 [台] / Count of fans with zero hours
    i            : INT;                    // 数组循环索引 / Array loop index
    nPickHrs     : UDINT;                  // 候选比较基准小时 [小时] / Candidate comparison hours baseline [h]
    bInit        : BOOL;                   // 首扫初始化标志 / First-scan init flag
END_VAR
VAR CONSTANT
    DL_FAN_IDX_MAX   : INT  := 8;          // 阵列容量上限（数组下界常量提取）/ Array capacity upper bound
    DL_FAN_TOTAL_MAX : UINT := 8;          // 装机台数上限 [台] / Installed count upper bound [fans]
    DL_FAN_RESERVE   : UINT := 1;          // N+1 预留备机数 [台] / Reserved standby count [fans]
    DL_FAN_CNT_SAT   : UINT := 65535;      // 级数输出饱和值 [台] / Stage output saturation [fans]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜TON 实例每周期无条件调用（仅 IN 条件化）：切换拍强制断流以复位计时
 *----------------------------------------------------------------------------*)
tonGateRun(IN := bGateArmed AND NOT bSwitchCycle, PT := tMinRun);    // 运行闸计时 / min-run gate timing
tonGateStop(IN := bGateArmed AND NOT bSwitchCycle, PT := tMinStop);  // 停机闸计时 / min-stop gate timing

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：按当前台数同步指令数组（默认全停）
 *----------------------------------------------------------------------------*)
IF NOT bInit THEN
    FOR i := 1 TO DL_FAN_IDX_MAX DO
        auFanCmd[i] := FALSE;                        // 默认全停 / default all stopped
    END_FOR
    bInit := TRUE;                                   // 首扫完成 / first scan done
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜台数钳位（信息级）：装机台数钳 [1, 8]
 *----------------------------------------------------------------------------*)
eErr := E_DL_FanArrErr.eReady;                       // 预置就绪 / preset ready
uTotalUse := uFanTotal;                              // 台数工作副本 / total working copy
IF uTotalUse > DL_FAN_TOTAL_MAX THEN
    uTotalUse := DL_FAN_TOTAL_MAX;                   // 台数上限钳位 / total capped
    eErr := E_DL_FanArrErr.eTotalClamp;              // 信息级：台数越界 / info: total clamped
ELSIF uTotalUse < 1 THEN
    uTotalUse := 1;                                  // 台数下限钳位 / total floored
    eErr := E_DL_FanArrErr.eTotalClamp;              // 信息级：台数越界 / info: total clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜需求级数钳位 [0, 台数-1]（预留 1 台备机，N+1 纪律）
 *----------------------------------------------------------------------------*)
uStageUse := uStageReq;                              // 需求工作副本 / request working copy
IF uStageUse > (uTotalUse - DL_FAN_RESERVE) THEN
    uStageUse := uTotalUse - DL_FAN_RESERVE;         // 级数上限钳位（预留备机）/ stage capped, standby reserved
    IF eErr = E_DL_FanArrErr.eReady THEN
        eErr := E_DL_FanArrErr.eStageClamp;          // 信息级：需求级数越界 / info: stage clamped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜轮值数据体检：运行小时全零计数（全零则轮值退化按索引顺序）
 *----------------------------------------------------------------------------*)
uHoursZero := 0;                                     // 全零计数清零 / zero-hours count reset
FOR i := 1 TO UINT_TO_INT(uTotalUse) DO
    IF aNRunHrs[i] = 0 THEN
        uHoursZero := uHoursZero + 1;                // 全零风机计数 [台] / count zero-hour fans
    END_IF
END_FOR
IF uHoursZero = UINT_TO_INT(uTotalUse) THEN
    IF eErr = E_DL_FanArrErr.eReady THEN
        eErr := E_DL_FanArrErr.eHrsAllZero;          // 信息级：轮值退化按顺序 / info: round-robin degenerated
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜每 tick 至多切换 1 台：加机选运行小时最少者，减机选运行小时最多者
 *----------------------------------------------------------------------------*)
uIdxBest := 0;                                       // 候选索引清零（0 = 无候选）/ candidate reset, 0 means none
nPickHrs := 0;                                       // 候选基准清零 / baseline reset
IF uStageAct > uStageUse THEN
    // 减机：在运行台中选运行小时最多者（轮值均衡）/ shed: pick running fan with most hours
    IF bGateArmed AND NOT tonGateRun.Q THEN
        IF eErr = E_DL_FanArrErr.eReady THEN
            eErr := E_DL_FanArrErr.eGateWait;        // 信息级：最短时序未满足 / info: gate waiting
        END_IF
    ELSE
        nPickHrs := 0;                               // 最多小时基准从 0 起比 / start from zero for max search
        FOR i := 1 TO UINT_TO_INT(uTotalUse) DO
            IF auFanCmd[i] THEN
                IF (uIdxBest = 0) OR (aNRunHrs[i] >= nPickHrs) THEN
                    uIdxBest := INT_TO_UINT(i);      // 候选更新（运行最久者）/ candidate updated, most-run fan
                    nPickHrs := aNRunHrs[i];         // 基准更新 / baseline updated
                END_IF
            END_IF
        END_FOR
    END_IF
ELSIF uStageAct < uStageUse THEN
    // 加机：在停机台中选运行小时最少者（轮值均衡）/ add: pick stopped fan with least hours
    IF bGateArmed AND NOT tonGateStop.Q THEN
        IF eErr = E_DL_FanArrErr.eReady THEN
            eErr := E_DL_FanArrErr.eGateWait;        // 信息级：最短时序未满足 / info: gate waiting
        END_IF
    ELSE
        nPickHrs := 16#FFFF_FFFF;                    // 最少小时基准从满值起比 / start from max for min search
        FOR i := 1 TO UINT_TO_INT(uTotalUse) DO
            IF NOT auFanCmd[i] THEN
                IF aNRunHrs[i] <= nPickHrs THEN
                    uIdxBest := INT_TO_UINT(i);      // 候选更新（停机最久者近似为小时最少）/ candidate updated, least-run fan
                    nPickHrs := aNRunHrs[i];         // 基准更新 / baseline updated
                END_IF
            END_IF
        END_FOR
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜执行切换：切换拍置武装标志并强制定时器断流复位
 *----------------------------------------------------------------------------*)
bSwitchCycle := FALSE;                               // 切换拍标志默认 FALSE / switch-scan flag defaults FALSE
IF uIdxBest > 0 THEN
    auFanCmd[UINT_TO_INT(uIdxBest)] := NOT auFanCmd[UINT_TO_INT(uIdxBest)];   // 执行切换 / execute the switch
    bGateArmed := TRUE;                              // 闸门武装 / gate armed
    bSwitchCycle := TRUE;                            // 切换拍标志（下拍定时器重新计时）/ switch scan flag
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜实际级数统计与数组上界外指令清扫（防越界残留）
 *----------------------------------------------------------------------------*)
uStageAct := 0;                                      // 实际级数清零 / actual stage reset
FOR i := 1 TO DL_FAN_IDX_MAX DO
    IF i > UINT_TO_INT(uTotalUse) THEN
        auFanCmd[i] := FALSE;                        // 容量外指令强制撤销（防越界残留）/ force FALSE beyond capacity
    ELSIF auFanCmd[i] THEN
        uStageAct := uStageAct + 1;                  // 运行台数累加 [台] / count running fans
    END_IF
END_FOR
IF uStageAct > DL_FAN_CNT_SAT THEN
    uStageAct := DL_FAN_CNT_SAT;                     // 级数饱和防护 / stage saturation guard
END_IF
END_FUNCTION_BLOCK
