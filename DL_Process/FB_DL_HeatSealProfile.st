(*
  FB_DL_HeatSealProfile  —  热封温度-压力-时间三参数配方曲线管理 / Heat-seal temperature-pressure-time profile
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B0
  版本 Version  : 1.0.0
  来源 Source   : t2-7-packml — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，PackML 热封段序公开语义借鉴，未复制任何源码行
                  （RESUME 承接 R36 §4 #15 规格；段推进语义对齐 FB_DL_StepSequencer，配方驻留对齐 FB_DL_RampSoakProfile，均不实例化）
  功能 Function : 1) 升温(Heat)→加压(Press)→冷却(Cool) 三段按配方时长推进（时长 0 的段跳过并记信息码）；
                  2) 各段实测温度/压力必须落在配方 ± 容差带内，越带记段不合格（_abSegBad 末段汇总 bProfileOk）；
                  3) 单段超 tSealMax 升级为 Fault；bAbort 在任意段立即进 Fault 并置 bReject。
  边界 Boundary : ① 配方时长为 0 的段跳过但记信息码；配方三段全为 0 判组态错不启动；
                  ② 容差/超时非法同判组态错；温度配方须为正值域（开尔文域防御）；
                  ③ bAbort 任意段立即进 Fault 并置 bReject（安全侧先撤输出）；
                  ④ CASE 全态覆盖 + ELSE 兜底（未知状态回 Idle 并置码，规格强制）；
                  ⑤ 解除式自证：bReject 解除 = bStart 上升沿 AND bReset（两引脚均可满足，R28-1）；
                  ⑥ 段判据 _abSegBad 为周期内锁存量，Done 相汇总后随新周期 bStart 上升沿清零。
  依赖 Depends  : 仅 Standard.library（TON/R_TRIG）；段序语义对齐 FB_DL_StepSequencer / FB_DL_RampSoakProfile（已注册，不实例化）
  码表 Error codes（本件格 06_0_B0，子码步进 +0x100）:
    16#0006_01B0 信息级：段时长为 0，该段跳过
    16#0006_02B0 故障级：组态非法（配方全 0 / 容差 <= 0 / tSealMax <= 0），锁存至复位
    16#0006_03B0 故障级：单段超时 tSealMax 升级
    16#0006_04B0 信息级：段参数越容差带（记段不合格）
    16#0006_05B0 信息级：中止判废（bAbort 触发）
    16#0006_06B0 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_SealPhase :
(
    eIdle   := 0,    // 空闲：等启动指令 / Idle, waiting for start
    eHeat   := 10,   // 升温段 / Heating segment
    ePress  := 20,   // 加压段 / Pressing segment
    eCool   := 30,   // 冷却段 / Cooling segment
    eDone   := 40,   // 完成：曲线合格汇总落定 / Done, profile verdict settled
    eReject := 50,   // 判废：曲线不合格落定（非故障）/ Rejected, profile unfit
    eFault  := 90    // 故障：组态/超时/中止锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeatSealProfile
VAR_INPUT
    bStart         : BOOL := FALSE;              // 启动指令（上升沿）/ Start command
    bAbort         : BOOL := FALSE;              // 中止指令（任意段生效）/ Abort command
    bReset         : BOOL := FALSE;              // 复位（Fault/bReject 解除路径之一）/ Reset
    afSealTempC    : ARRAY[0..2] OF REAL;        // 配方温度三段 [°C] / Recipe temperatures
    afSealPressBar : ARRAY[0..2] OF REAL;        // 配方压力三段 [bar] / Recipe pressures
    atSealTimeMs   : ARRAY[0..2] OF TIME;        // 配方时长三段 [ms] / Recipe durations
    fTempActualC   : REAL := 0.0;                // 实测封口温度 [°C] / Actual seal temperature
    fPressActualBar: REAL := 0.0;                // 实测封口压力 [bar] / Actual seal pressure
    fTempTolC      : REAL := 5.0;                // 温度容差 [°C]，域 > 0 / Temperature tolerance
    fPressTolBar   : REAL := 0.5;                // 压力容差 [bar]，域 > 0 / Pressure tolerance
    tSealMax       : TIME := T#30S;              // 单段超时上限 [ms]，域 > 0 / Segment timeout ceiling
END_VAR
VAR_OUTPUT
    bSealing   : BOOL;                       // 封口进行中（Heat/Press/Cool 任一段）/ Sealing in progress
    bProfileOk : BOOL;                       // 曲线合格（末段汇总）/ Profile verdict
    bReject    : BOOL;                       // 判废锁存（解除式：bStart 沿 AND bReset）/ Reject latch
    nSegment   : INT;                        // 当前段号 [0..2] / Current segment index
    fElapsedMs : REAL;                       // 当前段已走时长 [ms] / Segment elapsed time
    nErrId     : UDINT;                      // 事件码，0 = 无事件 / Event code
    eState     : E_DL_SealPhase;             // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR
    tonSeg     : TON;                        // 当前段配方时长计时，段 0 无条件刷新 / Segment recipe timer
    tonSegMax  : TON;                        // 单段超时计时，段 0 无条件刷新 / Segment timeout timer
    tonFaultWch: TON;                        // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtStart    : R_TRIG;                     // 启动上升沿 / Start rising edge
    rtReset    : R_TRIG;                     // 复位上升沿 / Reset rising edge
    _eState    : E_DL_SealPhase := E_DL_SealPhase.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nSeg      : INT;                        // 当前段号内部量 [0..2] / Internal segment index
    _abSegBad  : ARRAY[0..2] OF BOOL;        // 段不合格锁存（越带记段）/ Per-segment unfit latch
    _bAnyBad   : BOOL;                       // 任一段不合格聚合 / Any segment unfit aggregate
    _bSkip     : BOOL;                       // 段时长为 0 跳过标志（本拍重算）/ Zero-duration skip flag
    _uFault    : UDINT;                      // 故障码锁存 / Latched fault code
    _uInfo     : UDINT;                      // 信息码，每拍重算 / Info code
    _bFault    : BOOL;                       // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                       // 组态非法聚合 / Configuration invalid aggregate
    _bRejectL  : BOOL;                       // 判废锁存保持量 / Reject latch held quantity
    _nK        : INT;                        // 循环计数器 / Loop counter
END_VAR
VAR CONSTANT
    DL_WatchPt : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bStart);                                          // 启动上升沿，每拍必调
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WatchPt);        // 观察窗自复位（表达式入参）
tonSeg(IN := (_eState = E_DL_SealPhase.eHeat) OR (_eState = E_DL_SealPhase.ePress)
            OR (_eState = E_DL_SealPhase.eCool), PT := atSealTimeMs[_nSeg]);   // 段配方时长（表达式入参）
tonSegMax(IN := (_eState = E_DL_SealPhase.eHeat) OR (_eState = E_DL_SealPhase.ePress)
              OR (_eState = E_DL_SealPhase.eCool), PT := tSealMax);   // 单段超时（表达式入参）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bRejectL/_abSegBad/_bAnyBad 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
bSealing := FALSE;              // 封口出口缺省 FALSE（段 8 单点置位）
_bCfgBad := FALSE;              // 组态非法预清零
_bSkip := FALSE;                // 跳过标志预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fTempTolC <= 0.0) OR (fPressTolBar <= 0.0) OR (TIME_TO_DINT(tSealMax) <= 0) THEN
    _bCfgBad := TRUE;           // 容差/超时非法
END_IF
FOR _nK := 0 TO 2 DO
    IF (afSealTempC[_nK] <> afSealTempC[_nK]) OR (afSealTempC[_nK] <= 0.0)
       OR (afSealTempC[_nK] > 400.0) THEN
        _bCfgBad := TRUE;       // 温度配方非法（正值域，开尔文域防御）
    END_IF
    IF (afSealPressBar[_nK] <> afSealPressBar[_nK]) OR (afSealPressBar[_nK] <= 0.0)
       OR (afSealPressBar[_nK] > 10.0) THEN
        _bCfgBad := TRUE;       // 压力配方非法（正值域上限防御）
    END_IF
END_FOR
IF (TIME_TO_DINT(atSealTimeMs[0]) <= 0) AND (TIME_TO_DINT(atSealTimeMs[1]) <= 0)
   AND (TIME_TO_DINT(atSealTimeMs[2]) <= 0) THEN
    _bCfgBad := TRUE;           // 配方三段全 0：不启动（规格强制）
END_IF

(* —— 段 3：复位沿（bReject 解除式：bStart 上升沿 AND bReset；Fault 解除 = bReset） —— *)
IF rtReset.Q THEN
    IF rtStart.Q THEN
        _bRejectL := FALSE;     // 判废锁存清零（解除式自证路径）
    END_IF
    _bFault := FALSE;           // 清故障锁存位
    _uFault := 16#0000_0000;
    IF _eState = E_DL_SealPhase.eFault THEN
        _eState := E_DL_SealPhase.eIdle;    // 故障相回空闲
    END_IF
END_IF

(* —— 段 4：中止拦截（任意段立即升级，安全侧先撤输出——出口由 Fault 相缺省保证） —— *)
IF bAbort AND (_eState <> E_DL_SealPhase.eIdle) AND (_eState <> E_DL_SealPhase.eFault)
   AND (_eState <> E_DL_SealPhase.eDone) AND (_eState <> E_DL_SealPhase.eReject) THEN
    _uFault := 16#0006_03B0;    // 中止按故障级升级（撤输出）
    _bFault := TRUE;            // 锁存
    _bRejectL := TRUE;          // 判废锁存（bAbort 置 bReject，规格强制）
    _uInfo := 16#0006_05B0;     // 信息级：中止判废
    _eState := E_DL_SealPhase.eFault;
END_IF

(* —— 段 5：相位机（只做迁移与判据记账；出口在段 8） —— *)
CASE _eState OF

E_DL_SealPhase.eIdle:
    IF _bCfgBad THEN
        _uFault := 16#0006_02B0;            // 故障级：组态非法
        _bFault := TRUE;                    // 锁存（复位沿可清）
        _eState := E_DL_SealPhase.eFault;
    ELSIF rtStart.Q THEN
        _nSeg := 0;                         // 段号归零
        FOR _nK := 0 TO 2 DO
            _abSegBad[_nK] := FALSE;        // 段判据清零（新周期）
        END_FOR
        _bAnyBad := FALSE;                  // 聚合清零
        bProfileOk := FALSE;                // 曲线结论复位（Done 相重判）
        _eState := E_DL_SealPhase.eHeat;    // 进升温段
    END_IF

E_DL_SealPhase.eHeat:
    IF TIME_TO_DINT(atSealTimeMs[_nSeg]) <= 0 THEN
        _bSkip := TRUE;                     // 段时长为 0：跳过
        _uInfo := 16#0006_01B0;             // 信息级：段跳过
        _nSeg := _nSeg + 1;                 // 段号递增（上限守卫在 CASE 前判）
        IF _nSeg > 2 THEN
            _eState := E_DL_SealPhase.eDone;    // 三段走完：进完成相
        ELSE
            _eState := E_DL_SealPhase.ePress;   // 进加压段
        END_IF
    ELSIF tonSeg.Q THEN
        IF ABS(fTempActualC - afSealTempC[_nSeg]) > fTempTolC THEN
            _abSegBad[_nSeg] := TRUE;       // 越温带：记段不合格
            _uInfo := 16#0006_04B0;         // 信息级：段越带
        END_IF
        _nSeg := _nSeg + 1;
        IF _nSeg > 2 THEN
            _eState := E_DL_SealPhase.eDone;
        ELSE
            _eState := E_DL_SealPhase.ePress;
        END_IF
    ELSIF tonSegMax.Q THEN
        _uFault := 16#0006_03B0;            // 故障级：单段超时升级
        _bFault := TRUE;
        _eState := E_DL_SealPhase.eFault;
    END_IF

E_DL_SealPhase.ePress:
    IF TIME_TO_DINT(atSealTimeMs[_nSeg]) <= 0 THEN
        _bSkip := TRUE;
        _uInfo := 16#0006_01B0;
        _nSeg := _nSeg + 1;
        IF _nSeg > 2 THEN
            _eState := E_DL_SealPhase.eDone;
        ELSE
            _eState := E_DL_SealPhase.eCool;
        END_IF
    ELSIF tonSeg.Q THEN
        IF ABS(fTempActualC - afSealTempC[_nSeg]) > fTempTolC THEN
            _abSegBad[_nSeg] := TRUE;
            _uInfo := 16#0006_04B0;
        END_IF
        IF ABS(fPressActualBar - afSealPressBar[_nSeg]) > fPressTolBar THEN
            _abSegBad[_nSeg] := TRUE;       // 越压带：记段不合格
            _uInfo := 16#0006_04B0;
        END_IF
        _nSeg := _nSeg + 1;
        IF _nSeg > 2 THEN
            _eState := E_DL_SealPhase.eDone;
        ELSE
            _eState := E_DL_SealPhase.eCool;
        END_IF
    ELSIF tonSegMax.Q THEN
        _uFault := 16#0006_03B0;
        _bFault := TRUE;
        _eState := E_DL_SealPhase.eFault;
    END_IF

E_DL_SealPhase.eCool:
    IF TIME_TO_DINT(atSealTimeMs[_nSeg]) <= 0 THEN
        _bSkip := TRUE;
        _uInfo := 16#0006_01B0;
        _nSeg := _nSeg + 1;
        _eState := E_DL_SealPhase.eDone;    // 冷却为末段：进完成相
    ELSIF tonSeg.Q THEN
        IF ABS(fTempActualC - afSealTempC[_nSeg]) > fTempTolC THEN
            _abSegBad[_nSeg] := TRUE;
            _uInfo := 16#0006_04B0;
        END_IF
        _nSeg := _nSeg + 1;
        _eState := E_DL_SealPhase.eDone;
    ELSIF tonSegMax.Q THEN
        _uFault := 16#0006_03B0;
        _bFault := TRUE;
        _eState := E_DL_SealPhase.eFault;
    END_IF

E_DL_SealPhase.eDone:
    _bAnyBad := _abSegBad[0] OR _abSegBad[1] OR _abSegBad[2];   // 末段汇总
    bProfileOk := NOT _bAnyBad;             // 曲线合格结论
    IF _bAnyBad THEN
        _bRejectL := TRUE;                  // 不合格判废
    END_IF
    IF NOT bStart THEN
        _eState := E_DL_SealPhase.eIdle;    // 指令撤销：回空闲（结论保持）
    END_IF

E_DL_SealPhase.eReject:
    ;                                       // 预留相（判废经 Done 落定，本相不进入——保留枚举全态覆盖）

E_DL_SealPhase.eFault:
    ;                                       // 故障相：等复位沿（段 3 承载解除）

ELSE
    _uFault := 16#0006_06B0;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_SealPhase.eIdle;        // 未知状态回 Idle（规格强制）

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bSealing := (_eState = E_DL_SealPhase.eHeat) OR (_eState = E_DL_SealPhase.ePress)
            OR (_eState = E_DL_SealPhase.eCool);            // 封口出口：三段任一
nSegment := _nSeg;                          // 段号出口
fElapsedMs := TIME_TO_REAL(tonSegMax.ET);   // 已走时长出口（超时窗实时值 [ms]）
bReject := _bRejectL;                       // 判废出口 = 锁存量（置位同拍不被抹）
IF _bFault THEN
    nErrId := _uFault;          // 故障锁存码回放
    bSealing := FALSE;          // 故障相封口出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;           // 信息码
END_IF
eState := _eState;              // 状态出口单点映射

END_FUNCTION_BLOCK
