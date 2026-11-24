// FB_DL_SmokeDetZoneMon v1.0.0
// 开源溯源：self-cleanroom / 消防域
(*
  道莅工业代码库 | DL_Base | FB_DL_SmokeDetZoneMon
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 消防烟雾探测分区监视：4 分区各自报警/故障/屏蔽三态判定 + 报警
        确认延时去抖 + 报警/故障双锁存（复位沿解除）
  邻件关系: 与 EStopMonitor（急停监视）相邻 —— 差异点：急停件为单点
            安全回路监视，本件为多分区探测三态聚合（报警/故障/屏蔽），
            分区级独立锁存
  锁存声明: 报警锁存 bAnyAlarmLatch 至 bReset 上升沿解除；故障锁存
            bAnyFaultLatch 至该区故障消失且 bReset 上升沿解除（双条件可达）
*)
TYPE E_DL_SmokeZoneState :
(
    eNormal := 0,    // 正常（无报警无故障）/ Normal, no alarm no fault
    eAlarm  := 10,   // 报警（确认延时满）/ Alarm confirmed after delay
    eFault  := 20,   // 探测器故障 / Detector fault
    eMasked := 30     // 分区屏蔽（维护旁路）/ Zone masked for maintenance
);
END_TYPE

FUNCTION_BLOCK FB_DL_SmokeDetZoneMon
VAR_INPUT
    bEnable      : BOOL := FALSE;             // 监视总使能（FALSE 全区置屏蔽态）/ Master enable
    bZoneSmoke1  : BOOL := FALSE;             // 区 1 烟感信号 [-] / Zone 1 smoke signal
    bZoneSmoke2  : BOOL := FALSE;             // 区 2 烟感信号 [-] / Zone 2 smoke signal
    bZoneSmoke3  : BOOL := FALSE;             // 区 3 烟感信号 [-] / Zone 3 smoke signal
    bZoneSmoke4  : BOOL := FALSE;             // 区 4 烟感信号 [-] / Zone 4 smoke signal
    bZoneFault1  : BOOL := FALSE;             // 区 1 探测器故障 [-] / Zone 1 detector fault
    bZoneFault2  : BOOL := FALSE;             // 区 2 探测器故障 [-] / Zone 2 detector fault
    bZoneFault3  : BOOL := FALSE;             // 区 3 探测器故障 [-] / Zone 3 detector fault
    bZoneFault4  : BOOL := FALSE;             // 区 4 探测器故障 [-] / Zone 4 detector fault
    bMask1       : BOOL := FALSE;             // 区 1 屏蔽请求 [-] / Zone 1 mask request
    bMask2       : BOOL := FALSE;             // 区 2 屏蔽请求 [-] / Zone 2 mask request
    bMask3       : BOOL := FALSE;             // 区 3 屏蔽请求 [-] / Zone 3 mask request
    bMask4       : BOOL := FALSE;             // 区 4 屏蔽请求 [-] / Zone 4 mask request
    tAlarmDelay  : TIME := T#5S;              // 报警确认延时 [ms]，去抖 / Alarm confirm delay
    bReset       : BOOL := FALSE;             // 复位（上升沿解锁存）/ Reset, rising edge clears latches
END_VAR
VAR_OUTPUT
    eState1          : E_DL_SmokeZoneState;   // 区 1 三态 / Zone 1 state
    eState2          : E_DL_SmokeZoneState;   // 区 2 三态 / Zone 2 state
    eState3          : E_DL_SmokeZoneState;   // 区 3 三态 / Zone 3 state
    eState4          : E_DL_SmokeZoneState;   // 区 4 三态 / Zone 4 state
    bAnyAlarmLatch   : BOOL;                  // 任一区报警锁存（复位沿解除）/ Any alarm latched
    bAnyFaultLatch   : BOOL;                  // 任一区故障锁存 / Any fault latched
    uAlarmZoneCnt    : UDINT;                 // 当前报警区数 [区] / Current alarm zone count
    uFaultZoneCnt    : UDINT;                 // 当前故障区数 [区] / Current fault zone count
    bValid           : BOOL;                  // 组态有效回执 [-] / Config validity receipt
    bError           : BOOL;                  // 故障标志（延时组态非法）/ Fault flag (delay config illegal)
    uErrorId         : UDINT;                 // 事件码，0 = 无事件；16#0002_2401 = 延时组态非法 / Event code
END_VAR
VAR
    rtrReset     : R_TRIG;                    // 复位沿（每拍无条件刷新）/ Reset edge, refreshed every cycle
    tonZone1     : TON;                       // 区 1 确认延时（自复位）/ Zone 1 confirm delay, self-resetting
    tonZone2     : TON;                       // 区 2 确认延时 / Zone 2 confirm delay
    tonZone3     : TON;                       // 区 3 确认延时 / Zone 3 confirm delay
    tonZone4     : TON;                       // 区 4 确认延时 / Zone 4 confirm delay
    bLatch1      : BOOL;                      // 区 1 报警锁存 [-] / Zone 1 alarm latch
    bLatch2      : BOOL;                      // 区 2 报警锁存 [-] / Zone 2 alarm latch
    bLatch3      : BOOL;                      // 区 3 报警锁存 [-] / Zone 3 alarm latch
    bLatch4      : BOOL;                      // 区 4 报警锁存 [-] / Zone 4 alarm latch
    bFltLatch1   : BOOL;                      // 区 1 故障锁存 [-] / Zone 1 fault latch
    bFltLatch2   : BOOL;                      // 区 2 故障锁存 [-] / Zone 2 fault latch
    bFltLatch3   : BOOL;                      // 区 3 故障锁存 [-] / Zone 3 fault latch
    bFltLatch4   : BOOL;                      // 区 4 故障锁存 [-] / Zone 4 fault latch
END_VAR

// —— 段 0：实例无条件刷新（R7：沿与定时器每周期调用） —— //
rtrReset(CLK := bReset);                          // 复位沿每拍刷新 / Reset edge refreshed
tonZone1(IN := bEnable AND bZoneSmoke1 AND (NOT bMask1), PT := tAlarmDelay);   // 区 1 延时 / Zone 1 delay
tonZone2(IN := bEnable AND bZoneSmoke2 AND (NOT bMask2), PT := tAlarmDelay);   // 区 2 延时 / Zone 2 delay
tonZone3(IN := bEnable AND bZoneSmoke3 AND (NOT bMask3), PT := tAlarmDelay);   // 区 3 延时 / Zone 3 delay
tonZone4(IN := bEnable AND bZoneSmoke4 AND (NOT bMask4), PT := tAlarmDelay);   // 区 4 延时 / Zone 4 delay

// —— 段 1：组态闸 —— //
bValid := (tAlarmDelay > T#0MS);                  // 延时必须非零（去抖有效）/ Delay must be nonzero
IF NOT bValid THEN
    bError   := TRUE;                             // 故障级：延时组态非法 / Fault level: delay config illegal
    uErrorId := 16#0002_2401;                     // 故障码（24xx 步进）/ Fault code
    RETURN;                                       // 非法组态不判定 / No judgment on illegal config
END_IF
bError   := FALSE;                                // 组态恢复：故障清零（解除路径）/ Fault cleared on valid config
uErrorId := 16#0000;                              // 事件码清零 / Event code cleared

// —— 段 2：复位沿解锁存（双条件可达：锁存源消失 + 复位沿） —— //
IF rtrReset.Q THEN
    IF NOT bZoneSmoke1 THEN
        bLatch1 := FALSE;                         // 区 1 报警锁存解除 / Zone 1 alarm latch clear
    END_IF
    IF NOT bZoneSmoke2 THEN
        bLatch2 := FALSE;                         // 区 2 报警锁存解除 / Zone 2 clear
    END_IF
    IF NOT bZoneSmoke3 THEN
        bLatch3 := FALSE;                         // 区 3 报警锁存解除 / Zone 3 clear
    END_IF
    IF NOT bZoneSmoke4 THEN
        bLatch4 := FALSE;                         // 区 4 报警锁存解除 / Zone 4 clear
    END_IF
    IF NOT bZoneFault1 THEN
        bFltLatch1 := FALSE;                      // 区 1 故障锁存解除 / Zone 1 fault clear
    END_IF
    IF NOT bZoneFault2 THEN
        bFltLatch2 := FALSE;                      // 区 2 故障锁存解除 / Zone 2 clear
    END_IF
    IF NOT bZoneFault3 THEN
        bFltLatch3 := FALSE;                      // 区 3 故障锁存解除 / Zone 3 clear
    END_IF
    IF NOT bZoneFault4 THEN
        bFltLatch4 := FALSE;                      // 区 4 故障锁存解除 / Zone 4 clear
    END_IF
END_IF

// —— 段 3：报警/故障锁存置位（源出现即置位，状态型锁存） —— //
IF bEnable AND (NOT bMask1) THEN
    IF tonZone1.Q THEN
        bLatch1 := TRUE;                          // 确认延时满：区 1 报警锁存 / Delay full: zone 1 alarm latch
    END_IF
END_IF
IF bEnable AND (NOT bMask2) THEN
    IF tonZone2.Q THEN
        bLatch2 := TRUE;                          // 区 2 报警锁存 / Zone 2 alarm latch
    END_IF
END_IF
IF bEnable AND (NOT bMask3) THEN
    IF tonZone3.Q THEN
        bLatch3 := TRUE;                          // 区 3 报警锁存 / Zone 3 alarm latch
    END_IF
END_IF
IF bEnable AND (NOT bMask4) THEN
    IF tonZone4.Q THEN
        bLatch4 := TRUE;                          // 区 4 报警锁存 / Zone 4 alarm latch
    END_IF
END_IF
IF bEnable AND bZoneFault1 AND (NOT bMask1) THEN
    bFltLatch1 := TRUE;                           // 区 1 故障锁存 / Zone 1 fault latch
END_IF
IF bEnable AND bZoneFault2 AND (NOT bMask2) THEN
    bFltLatch2 := TRUE;                           // 区 2 故障锁存 / Zone 2 fault latch
END_IF
IF bEnable AND bZoneFault3 AND (NOT bMask3) THEN
    bFltLatch3 := TRUE;                           // 区 3 故障锁存 / Zone 3 fault latch
END_IF
IF bEnable AND bZoneFault4 AND (NOT bMask4) THEN
    bFltLatch4 := TRUE;                           // 区 4 故障锁存 / Zone 4 fault latch
END_IF

// —— 段 4：逐区三态判定（故障 > 报警 > 屏蔽 > 正常优先序） —— //
IF (NOT bEnable) OR bMask1 THEN
    eState1 := E_DL_SmokeZoneState.eMasked;       // 区 1 屏蔽（失能按屏蔽安全语义）/ Zone 1 masked
ELSIF bFltLatch1 THEN
    eState1 := E_DL_SmokeZoneState.eFault;        // 区 1 故障 / Zone 1 fault
ELSIF bLatch1 THEN
    eState1 := E_DL_SmokeZoneState.eAlarm;        // 区 1 报警 / Zone 1 alarm
ELSE
    eState1 := E_DL_SmokeZoneState.eNormal;       // 区 1 正常 / Zone 1 normal
END_IF
IF (NOT bEnable) OR bMask2 THEN
    eState2 := E_DL_SmokeZoneState.eMasked;       // 区 2 屏蔽 / Zone 2 masked
ELSIF bFltLatch2 THEN
    eState2 := E_DL_SmokeZoneState.eFault;        // 区 2 故障 / Zone 2 fault
ELSIF bLatch2 THEN
    eState2 := E_DL_SmokeZoneState.eAlarm;        // 区 2 报警 / Zone 2 alarm
ELSE
    eState2 := E_DL_SmokeZoneState.eNormal;       // 区 2 正常 / Zone 2 normal
END_IF
IF (NOT bEnable) OR bMask3 THEN
    eState3 := E_DL_SmokeZoneState.eMasked;       // 区 3 屏蔽 / Zone 3 masked
ELSIF bFltLatch3 THEN
    eState3 := E_DL_SmokeZoneState.eFault;        // 区 3 故障 / Zone 3 fault
ELSIF bLatch3 THEN
    eState3 := E_DL_SmokeZoneState.eAlarm;        // 区 3 报警 / Zone 3 alarm
ELSE
    eState3 := E_DL_SmokeZoneState.eNormal;       // 区 3 正常 / Zone 3 normal
END_IF
IF (NOT bEnable) OR bMask4 THEN
    eState4 := E_DL_SmokeZoneState.eMasked;       // 区 4 屏蔽 / Zone 4 masked
ELSIF bFltLatch4 THEN
    eState4 := E_DL_SmokeZoneState.eFault;        // 区 4 故障 / Zone 4 fault
ELSIF bLatch4 THEN
    eState4 := E_DL_SmokeZoneState.eAlarm;        // 区 4 报警 / Zone 4 alarm
ELSE
    eState4 := E_DL_SmokeZoneState.eNormal;       // 区 4 正常 / Zone 4 normal
END_IF

// —— 段 5：聚合输出（计数用枚举统计，锁存聚合） —— //
uAlarmZoneCnt := 0;                               // 报警区计数预清 / Alarm zone count preset
IF eState1 = E_DL_SmokeZoneState.eAlarm THEN
    uAlarmZoneCnt := uAlarmZoneCnt + 1;           // 区 1 计入 / Zone 1 counted
END_IF
IF eState2 = E_DL_SmokeZoneState.eAlarm THEN
    uAlarmZoneCnt := uAlarmZoneCnt + 1;           // 区 2 计入 / Zone 2 counted
END_IF
IF eState3 = E_DL_SmokeZoneState.eAlarm THEN
    uAlarmZoneCnt := uAlarmZoneCnt + 1;           // 区 3 计入 / Zone 3 counted
END_IF
IF eState4 = E_DL_SmokeZoneState.eAlarm THEN
    uAlarmZoneCnt := uAlarmZoneCnt + 1;           // 区 4 计入 / Zone 4 counted
END_IF
uFaultZoneCnt := 0;                               // 故障区计数预清 / Fault zone count preset
IF eState1 = E_DL_SmokeZoneState.eFault THEN
    uFaultZoneCnt := uFaultZoneCnt + 1;           // 区 1 计入 / Zone 1 counted
END_IF
IF eState2 = E_DL_SmokeZoneState.eFault THEN
    uFaultZoneCnt := uFaultZoneCnt + 1;           // 区 2 计入 / Zone 2 counted
END_IF
IF eState3 = E_DL_SmokeZoneState.eFault THEN
    uFaultZoneCnt := uFaultZoneCnt + 1;           // 区 3 计入 / Zone 3 counted
END_IF
IF eState4 = E_DL_SmokeZoneState.eFault THEN
    uFaultZoneCnt := uFaultZoneCnt + 1;           // 区 4 计入 / Zone 4 counted
END_IF
bAnyAlarmLatch := (uAlarmZoneCnt > 0);            // 任一报警聚合（当前态镜像）/ Any alarm aggregate
bAnyFaultLatch := (uFaultZoneCnt > 0);            // 任一故障聚合 / Any fault aggregate
END_FUNCTION_BLOCK
