(*
  组件名 Component   : FB_DL_ChillerStagingSeq
  子库 Sublibrary    : DL_Process
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 冷机加卸载顺控（与 ChillerTempStab/ChillerCondReset 分工：稳定
                       判稳 vs 顺控编组）：
                       1) 按需量 nDemand 分级加/卸载：在编台数 < 需量 → 启动累计运行
                       时间最短的停机台；> 需量 → 停止累计运行时间最长的运行台（轮值
                       均衡按运行小时数自然轮换）；
                       2) 最短启停驻留：每台独立启停驻留扫描计数，未满驻留不得启停，
                       驻留阻塞期置 bDwellLock（信息级）；
                       3) 需量越域钳位 [0, 台数上限] 并留信息码（瞬时口径）；
                       4) 到期轮值检查窗自复触周期计时（R188 范式）。
  边界 Boundary      : ① 本件只出各台启停指令，不写物理 IO，不接管冷冻水回路；
                       ② 运行时间累计由本件按扫描期内部折算（tCycle 换算分钟），
                       上位机无需另喂运行时数；
                       ③ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ④ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-7-packml 最小子集与 t1-2-oscat
                       暖通语义分类与参数域，零代码行复制）
  码位 Code          : 16#06_0_BD（Process 段 0006，B 子带 BD 格）
  码表 Error codes（本件格 06_0_BD，单轨子道：故障 0x02BD / 信息 0x01BD）:
    16#0006_02BD 故障级：组态非法（台数越域 / 驻留或周期为 0），锁存至复位
    16#0006_01BD 信息级：需量越域已钳位（瞬时口径，不置 bError）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 3 · 序号 14）
*)

TYPE E_DL_CssState :
(
    eIdle  := 0,    // 空闲：未使能，全台停机 / Idle, all stages off
    eRun   := 10,   // 编组运行：加卸载顺控 / Running, staging sequence
    eFault := 90    // 故障：组态锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChillerStagingSeq
VAR_INPUT
    bEnable  : BOOL;                       // 使能（电平）[-] / Enable
    bReset   : BOOL;                       // 上升沿清故障锁存 [-] / Reset edge
    nDemand  : INT;                        // 需量台数 [台]，域 0..4 / Required stage count
    tMinOn   : TIME := T#300S;             // 最短运行驻留 [毫秒] / Minimum on dwell
    tMinOff  : TIME := T#600S;             // 最短停机驻留 [毫秒] / Minimum off dwell
    tRotateWin: TIME := T#60S;             // 轮值均衡检查窗 [毫秒] / Rotation check window
    tCycle   : TIME := T#1S;               // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    abStageRun : ARRAY[1..4] OF BOOL;      // 各台运行指令输出 [-] / Stage run commands
    nStaged    : INT;                      // 在编台数 [台] / Staged count
    bDwellLock : BOOL;                     // 驻留阻塞电平 [-] / Dwell blocking level
    eState     : E_DL_CssState;            // 状态出口，段尾单点映射 / State outlet
    bError     : BOOL;                     // 故障锁存标志 [-] / Fault latch flag
    uErrId     : UDINT;                    // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset : R_TRIG;                      // 复位沿实例，段 0 无条件刷新 / Reset edge
    tonRotateWin: TON;                     // 轮值检查窗（自复触，R188） / Rotation window
    _eState : E_DL_CssState := E_DL_CssState.eIdle;    // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nDemandUse: INT;                      // 钳位后需量 [台] / Clamped demand
    _auRunMin  : ARRAY[1..4] OF UDINT;     // 各台累计运行时间 [分] / Runtime per stage
    _auDwellScan: ARRAY[1..4] OF UDINT;    // 各台启停驻留扫描计 [拍] / Dwell scans per stage
    _abLastRun : ARRAY[1..4] OF BOOL;      // 各台上拍运行态镜像 [-] / Previous run state
    _nIdx    : INT;                        // 台索引 [-] / Stage index
    _nPick   : INT;                        // 候选台号 [-] / Candidate stage
    _bFound  : BOOL;                       // 候选已找到标志 [-] / Candidate found flag
    _bFault  : BOOL;                       // 故障锁存位（锁存量） / Latched fault bit
    _uFault  : UDINT;                      // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad : BOOL;                       // 组态非法当拍量 [-] / Config illegal flag
    _bDemClp : BOOL;                       // 需量钳位当拍量 [-] / Demand clamped flag
    _bDwellLockCalc: BOOL;                 // 驻留阻塞内部量 [-] / Dwell blocking internal
    _uDwellOnScan: UDINT;                  // 运行驻留折算扫描数 [拍] / On dwell in scans
    _uDwellOffScan: UDINT;                 // 停机驻留折算扫描数 [拍] / Off dwell in scans
END_VAR
VAR CONSTANT
    DL_STAGE_MAX : INT := 4;               // 台数上限，与数组维度一致 [台] / Stage ceiling
    DL_ZERO_INT  : INT := 0;               // 零台常量 [台] / Zero stages
    DL_ZERO_UD   : UDINT := UDINT#0;       // 零计数常量 [拍] / Zero scans
    DL_MS_PER_MIN: REAL := 60000.0;        // 毫秒 → 分换算系数 [毫秒/分] / Milliseconds per minute
    DL_ONE_UD    : UDINT := UDINT#1;       // 单位计数常量 [拍] / One scan
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);
tonRotateWin(IN := (_eState = E_DL_CssState.eRun) AND (NOT _bFault) AND (NOT tonRotateWin.Q),
             PT := tRotateWin);          // 自复触周期窗：Q 拍断开一拍（R188）

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/abStageRun/auRunMin 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bDemClp := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，全台停机 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    FOR _nIdx := 1 TO DL_STAGE_MAX DO
        abStageRun[_nIdx] := FALSE;
        _abLastRun[_nIdx] := FALSE;
        _auDwellScan[_nIdx] := DL_ZERO_UD;
    END_FOR
    nStaged := DL_ZERO_INT;
    _eState := E_DL_CssState.eIdle;
END_IF

(* —— 段 3｜组态闸与需量钳位 —— *)
IF (tMinOn = T#0S) OR (tMinOff = T#0S) OR (tRotateWin = T#0S) OR (tCycle = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
_nDemandUse := nDemand;
IF _nDemandUse < DL_ZERO_INT THEN
    _nDemandUse := DL_ZERO_INT;
    _bDemClp := TRUE;
ELSIF _nDemandUse > DL_STAGE_MAX THEN
    _nDemandUse := DL_STAGE_MAX;
    _bDemClp := TRUE;
END_IF
IF _bDemClp THEN
    uErrId := 16#0006_01BD;              // 信息级：需量钳位（瞬时口径）
END_IF

(* —— 段 4｜驻留折算：驻留时长 ÷ 扫描周期 = 驻留扫描数（除法前周期域闸已过） —— *)
_uDwellOnScan  := REAL_TO_UDINT(TIME_TO_REAL(tMinOn) / MAX(TIME_TO_REAL(tCycle), 1.0));
_uDwellOffScan := REAL_TO_UDINT(TIME_TO_REAL(tMinOff) / MAX(TIME_TO_REAL(tCycle), 1.0));

(* —— 段 5｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_CssState.eIdle:
    FOR _nIdx := 1 TO DL_STAGE_MAX DO
        abStageRun[_nIdx] := FALSE;      // 空闲相全台停机（安全侧）
    END_FOR
    nStaged := DL_ZERO_INT;
    IF bEnable AND (NOT _bCfgBad) THEN
        FOR _nIdx := 1 TO DL_STAGE_MAX DO
            _auRunMin[_nIdx] := DL_ZERO_UD;      // 入运行相：运行时数基线清零
            _auDwellScan[_nIdx] := DL_ZERO_UD;
            _abLastRun[_nIdx] := FALSE;
        END_FOR
        _eState := E_DL_CssState.eRun;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BD;
        bError  := TRUE;
        _eState := E_DL_CssState.eFault;
    END_IF

E_DL_CssState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_CssState.eIdle;  // 使能撤销回空闲
    ELSE
        (* 运行时数与驻留计数：按上拍运行态刷新（驻留只在台数未变方向上累计） *)
        _bDwellLockCalc := FALSE;
        FOR _nIdx := 1 TO DL_STAGE_MAX DO
            IF abStageRun[_nIdx] THEN
                _auRunMin[_nIdx] := _auRunMin[_nIdx]
                    + REAL_TO_UDINT(TIME_TO_REAL(tCycle) / DL_MS_PER_MIN);
            END_IF
            IF abStageRun[_nIdx] = _abLastRun[_nIdx] THEN
                _auDwellScan[_nIdx] := _auDwellScan[_nIdx] + DL_ONE_UD;  // 方向未变：驻留累计
            ELSE
                _auDwellScan[_nIdx] := DL_ZERO_UD;   // 方向翻转：驻留清零
                _abLastRun[_nIdx] := abStageRun[_nIdx];
            END_IF
        END_FOR
        nStaged := DL_ZERO_INT;
        FOR _nIdx := 1 TO DL_STAGE_MAX DO
            IF abStageRun[_nIdx] THEN
                nStaged := nStaged + 1;
            END_IF
        END_FOR
        (* 加载：在编 < 需量，选运行时数最短的停机台（驻留满方可启） *)
        IF nStaged < _nDemandUse THEN
            _bFound := FALSE;
            _nPick  := 0;
            FOR _nIdx := 1 TO DL_STAGE_MAX DO
                IF (NOT abStageRun[_nIdx]) AND (_auDwellScan[_nIdx] >= _uDwellOffScan) THEN
                    IF (NOT _bFound) OR (_auRunMin[_nIdx] < _auRunMin[_nPick]) THEN
                        _bFound := TRUE;
                        _nPick  := _nIdx;
                    END_IF
                END_IF
            END_FOR
            IF _bFound THEN
                abStageRun[_nPick] := TRUE;  // 启动轮值均衡最优台
                _abLastRun[_nPick] := TRUE;
                _auDwellScan[_nPick] := DL_ZERO_UD;
            ELSE
                _bDwellLockCalc := TRUE;     // 无驻留满足台：阻塞
            END_IF
        ELSIF nStaged > _nDemandUse THEN
            (* 卸载：在编 > 需量，选运行时数最长的运行台（驻留满方可停） *)
            _bFound := FALSE;
            _nPick  := 0;
            FOR _nIdx := 1 TO DL_STAGE_MAX DO
                IF abStageRun[_nIdx] AND (_auDwellScan[_nIdx] >= _uDwellOnScan) THEN
                    IF (NOT _bFound) OR (_auRunMin[_nIdx] > _auRunMin[_nPick]) THEN
                        _bFound := TRUE;
                        _nPick  := _nIdx;
                    END_IF
                END_IF
            END_FOR
            IF _bFound THEN
                abStageRun[_nPick] := FALSE; // 停止轮值均衡最劣台
                _abLastRun[_nPick] := FALSE;
                _auDwellScan[_nPick] := DL_ZERO_UD;
            ELSE
                _bDwellLockCalc := TRUE;     // 无驻留满足台：阻塞
            END_IF
        END_IF
        bDwellLock := _bDwellLockCalc;       // 驻留阻塞电平同源赋值（R191）
    END_IF

E_DL_CssState.eFault:
    FOR _nIdx := 1 TO DL_STAGE_MAX DO
        abStageRun[_nIdx] := FALSE;      // 故障相全台停机（安全侧）
    END_FOR
    nStaged := DL_ZERO_INT;
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0006_02BD;
    bError  := TRUE;
    _eState := E_DL_CssState.eFault;
END_CASE

(* —— 段 6｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
