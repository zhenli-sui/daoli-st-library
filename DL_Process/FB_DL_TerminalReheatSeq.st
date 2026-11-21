(*
  FB_DL_TerminalReheatSeq  —  末端再热级联联锁 / Terminal reheat cascade interlock
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B2
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，VAV 再热级联公开控制语义借鉴，未复制任何源码行（RESUME 承接 R36 §4 #17 规格）
                  （级间延时语义对齐 FB_DL_SignalDebounce；变化率限幅对齐 FB_DL_RateLimiter，均不实例化）
  功能 Function : 1) 区域温度低于设定值产生再热需求，再热输出按级步进（级间延时 tStageDelay，防级联抖动）；
                  2) 风量低于 fMinAirflowPct 时再热按级降档（每 tStageDelay 降一级）并置 bMinAirflowLimit；
                  3) bReheatInhibit（制冷季互锁输入）时再热全关，出口镜像 bReheatInhibitActive；
                  4) 信号质量坏 → 保持当前级并置码（不跳变，规格强制）。
  边界 Boundary : ① fMinAirflowPct >= 100 判组态错（将使再热永久抑制）；fReheatStageStepPct <= 0 防除零判组态错；
                  ② 级数计算 nStage = TRUNC(fReheatCmdPct / fReheatStageStepPct) 后按级数上限钳制
                     （R28-2 两点向量：整除点 TRUNC 精确取整不越级；上限 +1 级钳到 fReheatMaxPct 对应级数不越上界）；
                  ③ 温度/风量信号非有限（NaN 用 x<>x 自反）→ 保持当前级并置码（不跳变）；
                  ④ 再热输出钳 [0, fReheatMaxPct]，禁越上限；
                  ⑤ 本件无状态机 ENUM/CASE（级联调节件），判据均为每拍重算或保持量承载，无锁存码。
  依赖 Depends  : 仅 Standard.library（TON/ABS/TRUNC/MIN/MAX）；语义对齐 FB_DL_RateLimiter / FB_DL_SignalDebounce（已注册）
  码表 Error codes（本件格 06_0_B2，子码步进 +0x100）:
    16#0006_01B2 信息级：信号质量坏（温度/风量非有限或越域），保持当前级
    16#0006_02B2 故障级：组态非法（最小风量 >= 100 / 级步 <= 0 / 上限越域）
    16#0006_03B2 信息级：最小风量约束生效（按级降档）
    16#0006_04B2 信息级：再热互锁生效，输出全关

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

FUNCTION_BLOCK FB_DL_TerminalReheatSeq
VAR_INPUT
    fZoneTempC        : REAL := 22.0;     // 区域温度 [°C] / Zone temperature
    fZoneSetC         : REAL := 21.0;     // 区域设定值 [°C] / Zone setpoint
    fAirflowPct       : REAL := 80.0;     // 风量 [%] / Airflow percentage
    fMinAirflowPct    : REAL := 30.0;     // 最小风量 [%]，域 < 100 / Minimum airflow
    fReheatMaxPct     : REAL := 100.0;    // 再热上限 [%]，域 0..100 / Reheat ceiling
    fReheatStageStepPct: REAL := 20.0;    // 再热级步 [%]，域 > 0 / Reheat stage step
    tStageDelay       : TIME := T#10S;    // 级间延时 [ms]，域 > 0 / Stage change delay
    bReheatInhibit    : BOOL := FALSE;    // 再热互锁输入（制冷季）/ Reheat inhibit interlock input
END_VAR
VAR_OUTPUT
    fReheatCmdPct      : REAL;            // 再热输出指令 [%] / Reheat command
    bMinAirflowLimit   : BOOL;            // 最小风量约束生效 / Minimum airflow limit flag
    bReheatInhibitActive: BOOL;           // 互锁生效镜像出口（输入 bReheatInhibit 承载规格名）/ Inhibit active mirror
    nActiveStage       : INT;             // 当前再热级数 [级] / Active stage count
    nErrId             : UDINT;           // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonStageDly : TON;                   // 级间延时计时（变化节流），自复位承载 / Stage change delay timer
    tonFaultWch : TON;                   // 故障观察窗，自复位 / Fault watch window, self-resetting
    _nStage     : INT;                   // 当前级数内部量 [级] / Internal stage count
    _nStageDes  : INT;                   // 期望级数（按需求算得）[级] / Desired stage count
    _nStageMax  : INT;                   // 级数上限 [级] / Stage ceiling
    _rErr       : REAL;                  // 温度偏差暂存 [K] / Temperature deviation scratch
    _bSigBad    : BOOL;                  // 信号质量坏聚合 / Signal quality bad aggregate
    _bStageBrk  : BOOL;                  // 级间延时窗断输入请求（自复位范式）/ Stage delay break request
    _bLimitHold : BOOL;                  // 最小风量约束保持量 / Airflow limit held quantity
    _uInfo      : UDINT;                 // 信息码，每拍重算 / Info code
    _bCfgBad    : BOOL;                  // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_WATCH_PT : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WATCH_PT);       // 观察窗自复位（表达式入参）
tonStageDly(IN := (NOT tonStageDly.Q) AND (NOT _bStageBrk), PT := tStageDelay);   // 级间延时自复位窗（表达式入参）
_bStageBrk := FALSE;                 // 断输入拍在调用后自清（R188 范式）

(* —— 段 1：单拍量预清零（保持量 _nStage/_bLimitHold 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;              // 信息码每拍重算
bMinAirflowLimit := FALSE;           // 约束出口缺省 FALSE（段 6 单点置位）
_bCfgBad := FALSE;                   // 组态非法预清零
_bSigBad := FALSE;                   // 信号质量坏预清零
nErrId := 16#0000_0000;              // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF fMinAirflowPct >= 100.0 THEN
    _bCfgBad := TRUE;                // 最小风量 >= 100：再热将永久抑制（规格强制）
END_IF
IF (fReheatStageStepPct <= 0.0) OR (fReheatStageStepPct <> fReheatStageStepPct) THEN
    _bCfgBad := TRUE;                // 级步非法（防除零）
END_IF
IF (fReheatMaxPct <= 0.0) OR (fReheatMaxPct > 100.0) OR (TIME_TO_DINT(tStageDelay) <= 0) THEN
    _bCfgBad := TRUE;                // 上限/级间延时非法
END_IF

(* —— 段 3：信号质量闸（温度/风量非有限或越域 → 保持当前级，不跳变） —— *)
IF (fZoneTempC <> fZoneTempC) OR (fZoneSetC <> fZoneSetC)
   OR (ABS(fZoneTempC) > 80.0) OR (ABS(fZoneSetC) > 80.0) THEN
    _bSigBad := TRUE;                // 温度信号质量坏
    _uInfo := 16#0006_01B2;          // 信息级：保持当前级
END_IF
IF (fAirflowPct <> fAirflowPct) OR (fAirflowPct < 0.0) OR (fAirflowPct > 150.0) THEN
    _bSigBad := TRUE;                // 风量信号质量坏
    _uInfo := 16#0006_01B2;          // 信息级：保持当前级
END_IF

(* —— 段 4：级数上限换算（级步换算，R28-2 两点向量） —— *)
IF NOT _bCfgBad THEN
    _nStageMax := TRUNC(fReheatMaxPct / fReheatStageStepPct);   // 级数上限（整除点精确取整，不越级）
    IF DINT_TO_REAL(DINT(_nStageMax)) * fReheatStageStepPct < fReheatMaxPct THEN
        _nStageMax := _nStageMax + 1;   // 余量进位到覆盖上限（上限 +1 向量：取整后余量补一级）
    END_IF
END_IF

(* —— 段 5：期望级数解算（温度需求 + 风量降档 + 互锁全关） —— *)
IF (NOT _bCfgBad) AND (NOT _bSigBad) THEN
    _rErr := fZoneSetC - fZoneTempC;                 // 温度偏差（> 0 需加热）
    IF bReheatInhibit THEN
        _nStageDes := 0;                             // 互锁：再热全关（规格强制）
        _uInfo := 16#0006_04B2;                      // 信息级：互锁生效
    ELSIF fAirflowPct < fMinAirflowPct THEN
        _nStageDes := 0;                             // 风量不足：按级降档目标（逐级走）
        _bLimitHold := TRUE;                         // 约束保持量
    ELSE
        IF _rErr > 0.5 THEN
            _nStageDes := _nStageMax;                // 明显需热：目标满级（级间延时节流逐级逼近）
        ELSIF _rErr < -0.5 THEN
            _nStageDes := 0;                         // 过热：目标 0 级
        ELSE
            _nStageDes := _nStage;                   // 死区内：维持当前级
        END_IF
    END_IF
END_IF

(* —— 段 6：级间延时节流推进（每 tStageDelay 向期望级走一级，防级联抖动） —— *)
IF (NOT _bCfgBad) AND (NOT _bSigBad) AND (_nStageDes <> _nStage) THEN
    IF tonStageDly.Q THEN
        _bStageBrk := TRUE;                          // 断输入请求：窗重开（自复位范式）
        IF _nStageDes > _nStage THEN
            _nStage := MIN(_nStage + 1, _nStageMax); // 升一级（上限钳制）
        ELSE
            _nStage := MAX(_nStage - 1, 0);          // 降一级（下界钳制）
        END_IF
    END_IF
END_IF

(* —— 段 7：出口单点映射（名实同源；每拍重算，无锁存码回放需求） —— *)
nActiveStage := _nStage;                             // 级数出口
fReheatCmdPct := DINT_TO_REAL(DINT(_nStage)) * fReheatStageStepPct;   // 再热输出 = 级数 × 级步
fReheatCmdPct := MIN(MAX(fReheatCmdPct, 0.0), fReheatMaxPct);         // 钳 [0, 上限]（禁越上界）
bMinAirflowLimit := _bLimitHold AND (fAirflowPct < fMinAirflowPct);   // 约束出口（每拍重算，解除式）
bReheatInhibitActive := bReheatInhibit AND (NOT _bCfgBad);            // 互锁镜像出口
IF _bCfgBad THEN
    nErrId := 16#0006_02B2;              // 故障级：组态非法（每拍重申）
    fReheatCmdPct := 0.0;                // 组态错输出全关（安全侧）
    nActiveStage := 0;
ELSIF bReheatInhibit THEN
    nErrId := 16#0006_04B2;              // 信息级：互锁全关
ELSIF _bSigBad THEN
    nErrId := 16#0006_01B2;              // 信息级：信号坏保持当前级
ELSIF bMinAirflowLimit THEN
    nErrId := 16#0006_03B2;              // 信息级：最小风量约束
END_IF

END_FUNCTION_BLOCK
