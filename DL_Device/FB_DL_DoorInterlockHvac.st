(*
  FB_DL_DoorInterlockHvac  —  机房门禁-风机联锁（开门降频 → 关门延时恢复）/ Door interlock with fan speed ramp-down
  分类 Category : DL_Device
  码位 Code     : 16#03_2_18
  段位说明      : 03_2 段低半字节已满，1x 段续号，17 格由 BcdFieldPanelIO 启用，本件启用 18 格（R192）
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 门禁-风机「降频-恢复」策略组态待挖项
  溯源 Origin   : clean-room 实现，未复制任何源码行
                  （与 FB_DL_GuardLockDoor 分工：那件管门本体握手；与炉门互锁族分工：那族管全停互锁，
                   本件管「降频-恢复」而非全停——风机保持运行仅限速，保障机房排风）
  功能 Function : 1) 四相联锁 Normal→Reduced→RestoreWait→Normal：开门（消抖/模拟量迟滞双口径）
                  降频至 fDoorOpenSpdPct，关门后经 tRestoreDelay 延时恢复需求转速；
                  2) 降频目标经 FB_DL_RateLimiter 斜坡（fRateUpPctS/fRateDownPctS 分向速率），
                  风机不失电不喘振；
                  3) 模拟量门磁口径（bUseAnaDoor = TRUE）：门缝宽度经 FC_DL_Hysteresis 迟滞判门态；
                  数字量口径：经 FB_DL_SignalDebounce 消抖判门态；
                  4) 故障相（组态非法）风机指令强制归零（安全侧：机房排风联锁失效宁可停风机报警）。
  边界 Boundary : ① 本件只出转速指令 fFanSpdCmdPct，不写风机本体 IO（由上层 PRG_IoMapping 承载）；
                  ② 门开降频与关门恢复的策略参数（速率/延时/降频值）全部引脚化组态；
                  ③ R228-A 达标声明：tonRestore 单相独占（IN 为单相等式），跨相迁移拍 IN 必断；
                  ④ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此；
                  ⑤ 迟滞判门态时 fDoorHystMm 越组态域按上限钳位（防御误填，不中断扫描）。
  依赖 Depends  : FB_DL_RateLimiter / FB_DL_SignalDebounce（实例化，引脚按 registry 实名）；
                  FC_DL_Hysteresis（函数调用，bState 由本件成员持有回传）
  码表 Error codes（本件格 03_2_18，子码步进 +0x100）:
    16#0003_0118 信息级：降频目标已到达（Reduced 相稳定）
    16#0003_0218 故障级：组态非法（需求/降频值越 0..100 / 速率非法 / 迟滞域非法），锁存至复位
    16#0003_0318 信息级：关门恢复延时进行中（RestoreWait 相，不置故障）
    16#0003_0418 故障级：状态机落 ELSE 兜底（非法相位 ID），锁存至复位

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 2 · 序号 10）
*)

TYPE E_DL_DoorIntState :
(
    eNormal      := 0,    // 正常：需求转速直通 / Normal, demand speed passes through
    eReduced     := 10,   // 降频：门开，指令钳到降频值 / Reduced, door open, speed clamped
    eRestoreWait := 20,   // 恢复等待：门关，延时恢复 / Restore wait, door closed, delayed restore
    eFault       := 90    // 故障：组态锁定，指令归零 / Fault, latched, command forced to zero
);
END_TYPE

FUNCTION_BLOCK FB_DL_DoorInterlockHvac
VAR_INPUT
    bEnable         : BOOL := TRUE;       // 总使能，FALSE 时指令归零并回 Normal 判定冻结 [-] / Master enable
    bDoorOpenRaw    : BOOL := FALSE;      // 数字量门磁原始信号（bUseAnaDoor = FALSE 时生效）/ Digital door switch raw input
    fDoorGapMm      : REAL := 0.0;        // 模拟量门缝宽度 [mm]（bUseAnaDoor = TRUE 时生效）/ Analog door gap width
    bUseAnaDoor     : BOOL := FALSE;      // 门态判据口径选择：TRUE = 模拟量迟滞 / FALSE = 数字消抖 / Door sensing mode select
    fDoorThrMm      : REAL := 30.0;       // 门缝开门判据阈 [mm]，域 > 0 / Analog door-open threshold
    fDoorHystMm     : REAL := 5.0;        // 门缝迟滞带 [mm]，域 > 0 / Analog door hysteresis band
    fFanSpdReqPct   : REAL := 80.0;       // 正常需求转速 [%]，域 [0, 100] / Normal demand speed
    fDoorOpenSpdPct : REAL := 30.0;       // 门开降频转速 [%]，域 [0, 100] / Door-open reduced speed
    fRateUpPctS     : REAL := 20.0;       // 恢复上升速率 [%/s]，域 > 0 / Restore ramp-up rate
    fRateDownPctS   : REAL := 40.0;       // 降频下降速率 [%/s]，域 > 0 / Reduced ramp-down rate
    tRestoreDelay   : TIME := T#5S;       // 关门恢复延时 [ms]，域 > 0 / Restore delay after door closed
    tSampleTime     : TIME := T#100MS;    // 限速器采样周期 [ms] / Rate limiter sample period
    bReset          : BOOL := FALSE;      // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    fFanSpdCmdPct : REAL;                 // 风机转速指令 [%]（上层风机消费）/ Fan speed command output
    bDoorDeb      : BOOL;                 // 门态判定出口（消抖/迟滞后）/ Judged door state output
    bReduced      : BOOL;                 // 降频生效中（Reduced 相）[-] / Reduced mode active
    bRestorePend  : BOOL;                 // 恢复延时进行中（RestoreWait 相）[-] / Restore delay in progress
    eState        : E_DL_DoorIntState;    // 状态出口，段尾单点映射 / State outlet
    bError        : BOOL;                 // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch
    uErrorId      : UDINT;                // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR
    fbDeb       : FB_DL_SignalDebounce;   // 数字量门磁消抖实例（主体首部无条件刷新）/ Digital door debounce instance
    fbLim       : FB_DL_RateLimiter;      // 转速斜坡限速实例（主体首部无条件刷新）/ Speed ramp limiter instance
    tonRestore  : TON;                    // 恢复延时计时（单相独占，R228-A）/ Restore delay timer, single phase
    rtReset     : R_TRIG;                 // 复位上升沿 / Reset rising edge
    _eState     : E_DL_DoorIntState := E_DL_DoorIntState.eNormal;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bDoorSt    : BOOL;                   // 迟滞判门态回传保持变量（FC_DL_Hysteresis 有状态纪律）/ Hysteresis door-state hold member
    _rTarget    : REAL;                   // 本拍目标转速 [%] / Target speed this cycle
    _rDoorSpdEff: REAL := 30.0;           // 钳位后降频转速 [%] / Clamped reduced speed
    _rReqEff    : REAL := 80.0;           // 钳位后需求转速 [%] / Clamped demand speed
    _bFault     : BOOL;                   // 故障锁存位 / Latched fault bit
    _uFault     : UDINT;                  // 故障码锁存寄存 / Latched fault code register
    _uInfo      : UDINT;                  // 信息码，每拍重算 / Info code
    _bCfgBad    : BOOL;                   // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_DIH_INF_CAP : REAL := 1.0E15;    // 非有限值筛查幅值上限 / Non-finite screening cap
    DL_DIH_DT_MIN  : TIME := T#10MS;    // 限速器采样周期下限 [ms] / Rate limiter sample lower clamp
END_VAR

(* —— 段 0：定时器与边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                                 // 复位沿刷新，每拍必调
fbDeb(bRawInput := bDoorOpenRaw,                                        // 数字门磁消抖
      tRiseDelay := T#100MS,                                            // 上升确认延时（门磁标准口径）
      tFallDelay := T#100MS,                                            // 下降确认延时
      bEnable := NOT bUseAnaDoor);                                      // 数字口径使能（模拟口径旁路）
fbLim(bEnable := TRUE,                                                  // 限速器恒使能（跨相平滑）
      fIn := _rTarget,                                                  // 限速输入 = 本拍目标
      fRateUp := MAX(fRateUpPctS, 1.0E-6),                              // 上升速率（下限防零速率卡死）
      fRateDown := MAX(fRateDownPctS, 1.0E-6),                          // 下降速率（下限防零速率卡死）
      bTrack := FALSE,                                                  // 不跟踪（转速指令连续性优先）
      fTrackValue := 0.0,                                               // 跟踪值（未用，占位保持接口完整）
      tSampleTime := MAX(tSampleTime, DL_DIH_DT_MIN));                  // 采样周期（下限钳位）
tonRestore(IN := (_eState = E_DL_DoorIntState.eRestoreWait) AND (NOT bDoorSt), PT := tRestoreDelay);   // 恢复延时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bDoorSt 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
_rTarget := 0.0;                    // 目标转速预清零（段 4 单点重写）

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fFanSpdReqPct < 0.0) OR (fFanSpdReqPct > 100.0)
   OR (fDoorOpenSpdPct < 0.0) OR (fDoorOpenSpdPct > 100.0)
   OR (fRateUpPctS <= 0.0) OR (fRateDownPctS <= 0.0)
   OR (TIME_TO_DINT(tRestoreDelay) <= 0) THEN
    _bCfgBad := TRUE;               // 需求/降频值越域或速率/延时非法
END_IF
IF (fDoorGapMm <> fDoorGapMm) OR (ABS(fDoorGapMm) > DL_DIH_INF_CAP) OR ((fDoorGapMm - fDoorGapMm) <> 0.0) THEN
    _bCfgBad := TRUE;               // 门缝输入非有限
END_IF
IF bUseAnaDoor AND ((fDoorThrMm <= 0.0) OR (fDoorHystMm <= 0.0) OR (fDoorHystMm > fDoorThrMm * 0.5)) THEN
    _bCfgBad := TRUE;               // 模拟口径阈值/迟滞非法（迟滞不越过阈值一半）
END_IF

(* —— 段 3：故障锁存与 eFault 迁出沿（R228-B：迁出条件 rtReset.Q 恒可达） —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0003_0218;        // 故障级：组态非法（仅首次进入时写入）
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT _bCfgBad) THEN
    _bFault := FALSE;               // 清故障锁存位（组态恢复合法为前提）
    _uFault := 16#0000_0000;
    IF _eState = E_DL_DoorIntState.eFault THEN
        _eState := E_DL_DoorIntState.eNormal;   // 故障相迁出：回正常相
    END_IF
END_IF

(* —— 段 4：门态判定与目标转速计算（故障相强制归零，安全侧） —— *)
_rReqEff := fFanSpdReqPct;          // 需求转速生效值（域已由段 2 闸门保证 0..100）
_rDoorSpdEff := fDoorOpenSpdPct;    // 降频转速生效值（域已由段 2 闸门保证 0..100）
IF bUseAnaDoor THEN
    bDoorDeb := FC_DL_Hysteresis(fIn := fDoorGapMm,             // 模拟口径：门缝迟滞判门态
                                 fThreshold := fDoorThrMm,      // 开门阈
                                 fHysteresis := fDoorHystMm,    // 迟滞带
                                 bState := _bDoorSt);           // 回传保持变量（同一成员，有状态纪律）
ELSE
    bDoorDeb := fbDeb.bStable;      // 数字口径：消抖稳定值
END_IF
IF _bFault OR (NOT bEnable) THEN
    _rTarget := 0.0;                // 故障/失能：指令目标归零（安全侧）
ELSIF bDoorDeb THEN
    _rTarget := MIN(_rReqEff, _rDoorSpdEff);    // 门开：需求与降频值取小（降频不高于需求）
ELSE
    _rTarget := _rReqEff;           // 门关：需求直通
END_IF

(* —— 段 5：相位机（只做相迁移与信息码；出口在段 7） —— *)
CASE _eState OF

E_DL_DoorIntState.eNormal:
    IF bDoorDeb THEN
        _eState := E_DL_DoorIntState.eReduced;      // 门开：进降频相
    END_IF

E_DL_DoorIntState.eReduced:
    IF bDoorDeb AND (_rTarget <= _rDoorSpdEff) THEN
        _uInfo := 16#0003_0118;     // 信息级：降频目标已到达（斜坡收敛）
    END_IF
    IF NOT bDoorDeb THEN
        _eState := E_DL_DoorIntState.eRestoreWait;  // 门关：进恢复等待相
    END_IF

E_DL_DoorIntState.eRestoreWait:
    bRestorePend := TRUE;           // 恢复延时进行中（相内重申）
    IF bDoorDeb THEN
        _eState := E_DL_DoorIntState.eReduced;      // 门复开：回降频相（延时计时随相断，R228-A）
    ELSIF tonRestore.Q THEN
        _eState := E_DL_DoorIntState.eNormal;       // 延时到点：回正常相
    END_IF

E_DL_DoorIntState.eFault:
    ;                               // 故障相：等复位沿（段 3 承载迁出）

ELSE
    _uFault := 16#0003_0418;        // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_DoorIntState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
fFanSpdCmdPct := fbLim.fOut;        // 转速指令 = 限速器输出（斜坡平滑口径）
bReduced := (_eState = E_DL_DoorIntState.eReduced);         // 降频生效中
bRestorePend := (_eState = E_DL_DoorIntState.eRestoreWait); // 恢复延时进行中（相外重写覆盖相内置位，口径统一）
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放
    bError := TRUE;
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
