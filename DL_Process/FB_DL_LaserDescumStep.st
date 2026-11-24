(*
  组件名 Component   : FB_DL_LaserDescumStep
  子库 Sublibrary    : DL_Process
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 激光去渣（descum）工步（自研行业池：半导体）：
                       1) 工步参数集：功率/扫速/圈数以输入引脚承载，工步沿启动；
                       2) 逐圈执行：每圈时长 tPassDur，圈计数达到 nPassCount 后停发；
                       3) 终点判据双路：反射率 >= fReflectEndPct 持续 tReflConfirm
                       确认（仪器路）或 bVisConfirm 操作员目视沿（人判路），任一
                       达成即提前结束（早退路径，不发参数变更）；
                       4) 工步超时：tStepTo 专用超时 TON（专用超时件命名），超时即
                       故障锁存（禁把配方时长接到段超时）。
  边界 Boundary      : ① 本件只出激光使能与参数就绪标志，不写物理 IO；
                       ② 工步沿启动后参数集冻结快照（工步中改参不生效，禁中途
                       变参重推断）；圈数域 [1, 99]；
                       ③ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ④ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（自研行业池：半导体去渣工步共性语义，
                       零外部代码行复制）
  码位 Code          : 16#06_0_C1（Process 段 0006，C 子带 C1 格）
  码表 Error codes（本件格 06_0_C1，单轨子道：故障 0x02C1 / 信息 0x01C1 / 0x03C1）:
    16#0006_02C1 故障级：工步故障总码（工步超时 / 组态非法 / 输入非有限），
                 锁存至复位
    16#0006_01C1 信息级：反射率早退沿（仪器判据达成提前结束拍）
    16#0006_03C1 信息级：目视早退沿（操作员确认提前结束拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 4 · 序号 18）
*)

TYPE E_DL_LdsPhase :
(
    eIdle  := 0,    // 空闲：等工步沿 / Idle, waiting step edge
    eRun   := 10,   // 工步：逐圈执行 + 终点监视 / Running, pass loop and endpoint watch
    eDone  := 20,   // 完成：工步结论驻留 / Done, step verdict held
    eFault := 90    // 故障：工步锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaserDescumStep
VAR_INPUT
    bStartCmd    : BOOL;                   // 工步启动（上升沿承载）[-] / Step start edge
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    bVisConfirm  : BOOL;                   // 目视确认（上升沿承载）[-] / Visual confirm edge
    fPowerPct    : REAL := 80.0;           // 激光功率 [%]，域 0..100 / Laser power
    fScanSpeedMmS: REAL := 100.0;          // 扫描速度 [mm/s] / Scan speed
    nPassCount   : INT := 3;               // 计划圈数 [圈]，域 1..99 / Planned pass count
    fReflectPct  : REAL;                   // 反射率实测 [%] / Measured reflectivity
    fReflectEndPct: REAL := 60.0;          // 反射率终点阈 [%] / Reflectivity endpoint threshold
    tPassDur     : TIME := T#10S;          // 每圈时长 [毫秒] / Pass duration
    tReflConfirm : TIME := T#2S;           // 反射率确认窗 [毫秒] / Reflectivity confirm window
    tStepTo      : TIME := T#600S;         // 工步超时 [毫秒] / Step timeout
END_VAR
VAR_OUTPUT
    bLaserEnable : BOOL;                   // 激光使能输出 [-] / Laser enable output
    bParamReady  : BOOL;                   // 参数集就绪标志（工步沿冻结快照有效）[-] / Parameter ready flag
    nPassDone    : INT;                    // 已完成圈数 [圈] / Completed pass count
    bEarlyExit   : BOOL;                   // 早退标志（终点判据提前达成）[-] / Early exit flag
    ePhase       : E_DL_LdsPhase;          // 相位出口，段尾单点映射 / Phase outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset   : R_TRIG;                    // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtStart   : R_TRIG;                    // 工步沿实例，段 0 无条件刷新 / Start edge
    rtVisConf : R_TRIG;                    // 目视确认沿实例，段 0 无条件刷新 / Visual confirm edge
    tonPassDur: TON;                       // 每圈计时（独立实例） / Pass duration timer
    tonReflConf: TON;                      // 反射率确认窗 / Reflectivity confirm timer
    tonStepTo : TON;                       // 工步超时（专用超时件命名） / Step timeout
    _ePhase   : E_DL_LdsPhase := E_DL_LdsPhase.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nPassPlan: INT;                       // 冻结计划圈数 [圈] / Frozen planned passes
    _bFault   : BOOL;                      // 故障锁存位（锁存量） / Latched fault bit
    _uFault   : UDINT;                     // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad  : BOOL;                      // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin  : BOOL;                      // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_PASS_MAX : INT  := 99;              // 圈数上限 [圈] / Pass count ceiling
    DL_PASS_MIN : INT  := 1;               // 圈数下限 [圈] / Pass count floor
    DL_ONE      : INT  := 1;               // 单位圈数常量 [圈] / One pass
    DL_ABS_MAX  : REAL := 1.0E30;          // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO     : REAL := 0.0;             // 零常量 [工程单位] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset  (CLK := bReset);
rtStart  (CLK := bStartCmd);
rtVisConf(CLK := bVisConfirm);
tonPassDur (IN := (_ePhase = E_DL_LdsPhase.eRun) AND (NOT _bFault), PT := tPassDur);
tonReflConf(IN := (_ePhase = E_DL_LdsPhase.eRun) AND (fReflectPct >= fReflectEndPct)
            AND (NOT _bFault), PT := tReflConfirm);
tonStepTo  (IN := (_ePhase = E_DL_LdsPhase.eRun) AND (NOT _bFault), PT := tStepTo);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/_nPassPlan/bEarlyExit 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，激光使能撤销 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    bLaserEnable := FALSE;
    bParamReady  := FALSE;
    _ePhase := E_DL_LdsPhase.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据 —— *)
IF (fPowerPct <= DL_ZERO) OR (fPowerPct > DL_ABS_MAX) OR (fScanSpeedMmS <= DL_ZERO)
   OR (nPassCount < DL_PASS_MIN) OR (nPassCount > DL_PASS_MAX) OR (tPassDur = T#0S)
   OR (tReflConfirm = T#0S) OR (tStepTo = T#0S) OR (fReflectEndPct <= DL_ZERO) THEN
    _bCfgBad := TRUE;
END_IF
IF (fReflectPct <> fReflectPct) OR ((fReflectPct - fReflectPct) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：四态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF

E_DL_LdsPhase.eIdle:
    bLaserEnable := FALSE;
    IF _bFault THEN
        bError := TRUE;                  // 故障锁存回放（R189）
    END_IF
    IF rtStart.Q AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _nPassPlan := nPassCount;        // 参数集冻结快照（工步中改参不生效）
        nPassDone  := 0;
        bEarlyExit := FALSE;
        bParamReady := TRUE;
        bLaserEnable := TRUE;
        _ePhase := E_DL_LdsPhase.eRun;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                 // 带病启动拒绝
        _uFault := 16#0006_02C1;
        bError  := TRUE;
        _ePhase := E_DL_LdsPhase.eFault;
    END_IF

E_DL_LdsPhase.eRun:
    bLaserEnable := TRUE;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C1;
        bError  := TRUE;
        _ePhase := E_DL_LdsPhase.eFault;
    ELSIF rtVisConf.Q THEN
        bEarlyExit := TRUE;              // 人判路早退：终点判据提前达成
        uErrId := 16#0006_03C1;          // 信息级：目视早退沿
        bLaserEnable := FALSE;
        _ePhase := E_DL_LdsPhase.eDone;
    ELSIF tonReflConf.Q THEN
        bEarlyExit := TRUE;              // 仪器路早退：反射率确认达成
        uErrId := 16#0006_01C1;          // 信息级：反射率早退沿
        bLaserEnable := FALSE;
        _ePhase := E_DL_LdsPhase.eDone;
    ELSIF tonPassDur.Q THEN
        nPassDone := nPassDone + DL_ONE; // 一圈完成：圈计数累加
        IF nPassDone >= _nPassPlan THEN
            bLaserEnable := FALSE;       // 圈数达成：停发（正常收口）
            _ePhase := E_DL_LdsPhase.eDone;
        END_IF
    ELSIF tonStepTo.Q THEN
        _bFault := TRUE;                 // 工步超时（配方时长接段计，超时独立承载）
        _uFault := 16#0006_02C1;
        bError  := TRUE;
        bLaserEnable := FALSE;
        _ePhase := E_DL_LdsPhase.eFault;
    END_IF

E_DL_LdsPhase.eDone:
    bLaserEnable := FALSE;
    IF NOT bStartCmd THEN
        _ePhase := E_DL_LdsPhase.eIdle;  // 工步指令撤销：回空闲（结论锁存保留）
    END_IF

E_DL_LdsPhase.eFault:
    bLaserEnable := FALSE;               // 故障相：激光使能安全侧撤销
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0006_02C1;
    bError  := TRUE;
    _ePhase := E_DL_LdsPhase.eFault;
END_CASE

(* —— 段 5｜相位出口单点映射 —— *)
ePhase := _ePhase;
END_FUNCTION_BLOCK
