(*
  FB_DL_HumidifierWaterQual  —  加湿器水质电导率监视与排水联锁 / Humidifier water conductivity monitoring with drain interlock
  分类 Category : DL_Device
  码位 Code     : 16#03_2_04
  版本 Version  : 1.0.0
  溯源 Source   : 道莅自研 clean-room（电导率标定与排水联锁为通用水处理工程语义）
  功能 Function : 1) 电导率经标定换算（斜率/偏置）后按门限分级，超标触发排水周期；
                  2) 排水阀与补水阀互斥，同拍双开即判冲突并双双回安全位（关阀）；
                  3) 电导门限带迟滞防抖，越限解除有可到达路径；标定斜率非法（0/负）即拒算并置码。
  边界 Boundary : ① 标定参数非法（斜率 0 或负）拒算并置码；
                  ② 排水联锁与补水阀互斥（同拍双开判冲突回安全位）；
                  ③ 电导门限带迟滞防抖，越限解除有可到达路径；
                  ④ 输出三行同向：电导值 → 分级 → 排水阀。
  依赖 Depends  : FC_DL_LimitClassify（电导分级，每拍无条件调用）、FB_DL_TimeWindowCheck（排水维护时间窗，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0304 故障级：电导率标定参数非法（斜率 <= 0 或非有限），拒算
    16#0002_0314 故障级：排水阀与补水阀同拍双开（互斥冲突），双双回安全位
    16#0002_0324 信息级：电导率越限已启动排水（不置 bError）
*)

TYPE E_DL_HwqPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eMonitor := 10,  // 电导监视 / Conductivity monitoring
    eDrain   := 20,  // 排水周期进行 / Drain cycle running
    eHold    := 30,  // 拒算保持 / Rejected, held
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_HumidifierWaterQual
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 关阀回空闲 / Master enable
    bReset       : BOOL;                          // 复位，上升沿清故障与冲突锁存 / Reset
    fCondRawUScm : REAL;                          // 电导率原始值 [uS/cm]，域 0~2000 / Raw conductivity [uS/cm]
    fCalSlope    : REAL := 1.0;                   // 电导标定斜率 [uS/cm per 原始计数]，域 > 0 / Calibration slope
    fCalOffset   : REAL := 0.0;                   // 电导标定偏置 [uS/cm] / Calibration offset [uS/cm]
    fCondWarnUScm: REAL := 300.0;                 // 电导警告门限 [uS/cm]，域 > 0 / Conductivity warning limit
    fCondTripUScm: REAL := 600.0;                 // 电导排水门限 [uS/cm]，须 > 警告门限 / Drain trigger limit
    fCondHystUScm: REAL := 20.0;                  // 电导迟滞 [uS/cm]，域 >= 0 / Conductivity hysteresis
    tDrainTime   : TIME := T#30S;                 // 单次排水时长 [ms]，域 > 0 / Drain duration [ms]
    tDrainPeriod : TIME := T#10M;                 // 排水周期 [ms]，域 > 0 / Drain period [ms]
    uHourNow     : USINT := 0;                    // 当前时刻-时 [h]（注入，禁读 CPU 钟）/ Injected hour [h]
    uMinNow      : USINT := 0;                    // 当前时刻-分 [min]（注入）/ Injected minute [min]
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fCondUScm    : REAL;                          // 标定后电导率 [uS/cm] / Calibrated conductivity [uS/cm]
    bDrainValve  : BOOL;                          // 排水阀 [开关] / Drain valve
    bFillValve   : BOOL;                          // 补水阀 [开关] / Make-up fill valve
    bCondWarn    : BOOL;                          // 电导警告（保持型）/ Conductivity warning, held
    bInDrainWin  : BOOL;                          // 处于维护排水时间窗 / Inside maintenance drain window
    bValveConflict : BOOL;                        // 阀门互斥冲突标志 / Valve exclusion conflict flag
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_HwqPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_HwqPhase := E_DL_HwqPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    tonDrain     : TON;                           // 排水时长计时（自复位）/ Drain duration timer
    tonPeriod    : TON;                           // 排水周期节拍（自复位）/ Drain period tick
    fbWindow     : FB_DL_TimeWindowCheck;         // 排水维护时间窗实例（无条件调用）/ Drain time window
    bCalOk       : BOOL;                          // 标定参数合法 / Calibration valid
    bCfgOk       : BOOL;                          // 组态合法 / Configuration valid
    eBand        : E_DL_LimitBand;                // 电导分级结果 / Conductivity band
    aDayEn       : ARRAY[1..7] OF BOOL;           // 星期使能表（周一~周日）/ Weekday enable table
    nDay         : INT;                           // 星期填充下标 / Weekday fill index
    fCondCal     : REAL;                          // 标定后电导率暂存 [uS/cm] / Calibrated conductivity buffer
    bCondHigh    : BOOL;                          // 越排水门限标志 / Above drain threshold
    bDrainCmd    : BOOL;                          // 排水指令暂存 / Drain command buffer
    bFillCmd     : BOOL;                          // 补水指令暂存 / Fill command buffer
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_HWQ_CMAX  : REAL := 2000.0;                // 电导物理域上限 [uS/cm] / Conductivity domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用，自复位节拍）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿
tonDrain(IN := (_eState = E_DL_HwqPhase.eDrain) AND (NOT tonDrain.Q), PT := tDrainTime);   // 自复位
tonPeriod(IN := NOT tonPeriod.Q, PT := tDrainPeriod);                                      // 周期心跳自复位
FOR nDay := 1 TO 7 DO
    aDayEn[nDay] := TRUE;                         // 维护排水窗与星期无关：全周使能
END_FOR
fbWindow(uHourNow := uHourNow,                    // 注入当前时
         uMinNow := uMinNow,                      // 注入当前分
         bEnableDay := TRUE,                      // 日窗使能
         aWeekdayEnable := aDayEn,                // 周一到周日全开（本地数组填充）
         uWeekdayNow := 1,                        // 星期注入（维护窗与星期无关）
         uHourOn := 0,                            // 窗开 00:00
         uMinOn := 0,                             // 窗开 0 分
         uHourOff := 23,                          // 窗关 23:00
         uMinOff := 59,                           // 窗关 59 分
         bReset := rtrReset.Q);                   // 复位沿清信息码
bInDrainWin := fbWindow.bInWindow;                // 时间窗输出

(* === 段 1 · 标定与组态闸 === *)
bCalOk := (fCalSlope > fEps) AND (fCalSlope = fCalSlope) AND (fCalOffset = fCalOffset);   // 斜率正域 + NaN 自反
bCfgOk := (fCondWarnUScm > fEps) AND (fCondTripUScm > fCondWarnUScm)
          AND (fCondHystUScm >= 0.0) AND (tDrainTime > T#0MS) AND (tDrainPeriod > T#0MS)
          AND (fCondWarnUScm = fCondWarnUScm) AND (fCondTripUScm = fCondTripUScm);   // 含 NaN 自反
IF NOT bCalOk THEN
    uFault := 16#0002_0304;                       // 故障级：标定参数非法，拒算
END_IF
IF NOT bCfgOk THEN
    uFault := 16#0002_0304;                       // 故障级：组态非法同码段（防无码可查）
END_IF
IF rtrReset.Q AND bCalOk AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
    bValveConflict := FALSE;                      // 冲突标志同步复位
    bCondWarn := FALSE;                           // 警告标志同步复位
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
IF bCalOk AND (fCondRawUScm = fCondRawUScm) AND (fCondRawUScm >= 0.0)
   AND (fCondRawUScm <= DL_HWQ_CMAX) THEN
    fCondCal := fCondRawUScm * fCalSlope + fCalOffset;   // 标定换算
    IF fCondCal < 0.0 THEN
        fCondCal := 0.0;                          // 负电导截零（物理不可达）
    END_IF
    fCondUScm := fCondCal;                        // 电导值输出
ELSE
    fCondCal := 0.0;                              // 拒算：不出数值
END_IF

(* === 段 2 · 电导分级（函数每拍无条件调用）=== *)
eBand := FC_DL_LimitClassify(fVal := fCondCal,
                             fLowLimit := -1.0,               // 低低限：本件不使用（负值域）
                             fLowWarn := -0.5,                // 低警告限：本件不使用
                             fUpWarn := fCondWarnUScm,        // 高警告限
                             fUpLimit := fCondTripUScm);      // 高排水限
bCondHigh := (eBand = E_DL_LimitBand.eUpTripped);  // 到达排水级
IF eBand = E_DL_LimitBand.eUpWarn THEN
    bCondWarn := TRUE;                             // 警告级：置警告
END_IF

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_HwqPhase.eIdle :
    bDrainCmd := FALSE;                            // 空闲不排水
    bFillCmd := FALSE;                             // 空闲不补水
    IF (uFault <> 16#0000) AND (uFault <> 16#0002_0314) THEN
        _eState := E_DL_HwqPhase.eFault;           // 故障优先
    ELSIF bEnable AND (NOT bCalOk) THEN
        _eState := E_DL_HwqPhase.eHold;            // 标定非法：拒算保持
    ELSIF bEnable THEN
        _eState := E_DL_HwqPhase.eMonitor;         // 进入监视相
    END_IF

E_DL_HwqPhase.eMonitor :
    bFillCmd := NOT bDrainCmd;                     // 补水默认开（与排水互斥）
    IF bCondHigh THEN
        bCondWarn := TRUE;                         // 置位型：电导警告
        uInfo := 16#0002_0324;                     // 信息级：越限启动排水
        _eState := E_DL_HwqPhase.eDrain;           // 转排水相
    ELSIF (eBand = E_DL_LimitBand.eNormal) AND (fCondCal < (fCondWarnUScm - fCondHystUScm)) THEN
        bCondWarn := FALSE;                        // 迟滞带下方：解除警告（可到达的解除路径）
    END_IF
    IF (NOT bEnable) OR (NOT bCalOk) THEN
        _eState := E_DL_HwqPhase.eIdle;            // 失能/标定失效回空闲
    END_IF

E_DL_HwqPhase.eDrain :
    bDrainCmd := TRUE;                             // 排水阀开（驱动方向）
    bFillCmd := FALSE;                             // 补水阀关（互斥）
    IF tonDrain.Q THEN
        bDrainCmd := FALSE;                        // 排水时长到：关阀（本拍行为）
        IF bCondHigh THEN
            IF tonPeriod.Q THEN
                bFillCmd := TRUE;                  // 周期未到且仍超标：等待下一周期再排
            END_IF
            _eState := E_DL_HwqPhase.eMonitor;     // 回监视相，等下一周期
        ELSE
            _eState := E_DL_HwqPhase.eMonitor;     // 达标：回监视相
        END_IF
    END_IF

E_DL_HwqPhase.eHold :
    bDrainCmd := FALSE;                            // 拒算态关排水
    bFillCmd := FALSE;                             // 拒算态关补水
    IF bCalOk THEN
        _eState := E_DL_HwqPhase.eMonitor;         // 标定恢复：解除拒算（可到达的解除路径）
    END_IF

E_DL_HwqPhase.eFault :
    bDrainCmd := FALSE;                            // 故障态排水阀关（安全侧）
    bFillCmd := FALSE;                             // 故障态补水阀关
    IF uFault = 16#0000 THEN
        _eState := E_DL_HwqPhase.eIdle;            // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_HwqPhase.eFault;               // 非法状态拦截
    uFault := 16#0002_0304;                        // 故障级：相 ID 越界
    bDrainCmd := FALSE;                            // 安全侧关阀
    bFillCmd := FALSE;                             // 安全侧关阀
END_CASE

(* === 段 4 · 阀门互斥仲裁（同拍双开判冲突，双双回安全位）=== *)
IF bDrainCmd AND bFillCmd THEN
    bDrainCmd := FALSE;                            // 冲突：排水阀回安全位
    bFillCmd := FALSE;                             // 冲突：补水阀回安全位
    bValveConflict := TRUE;                        // 冲突标志置位
    uFault := 16#0002_0314;                        // 故障级：互斥冲突
ELSE
    bValveConflict := FALSE;                       // 无冲突：标志清零（非置位型）
END_IF
IF rtrReset.Q AND bValveConflict THEN
    uFault := 16#0000;                             // 冲突经复位解除（复位路径可达）
    bValveConflict := FALSE;                       // 标志同步清零
END_IF
IF NOT bEnable THEN
    bDrainCmd := FALSE;                            // 失能最高优先：排水关
    bFillCmd := FALSE;                             // 失能最高优先：补水关
END_IF

(* === 段 5 · 输出映射（三行同向：电导值 → 分级 → 排水阀）=== *)
bDrainValve := bDrainCmd;                          // 排水阀输出
bFillValve := bFillCmd;                            // 补水阀输出
bError := (uFault <> 16#0000);                     // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                            // 故障级优先上报
ELSE
    uErrorId := uInfo;                             // 否则上报信息级码
END_IF
eStateOut := _eState;                              // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
