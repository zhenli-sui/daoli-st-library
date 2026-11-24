(*
  FB_DL_ElectronicCamSwitchBank  —  电子凸轮开关组（MC_CamSwitch 语义）/ Electronic cam switch bank
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A5
  版本 Version  : 1.0.0
  来源 Source   : t1-6-plcopen — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : PLCopen MC_CamSwitch 公开语义借鉴，clean-room 实现，未复制任何源码行
                  （与 FB_DL_MarkPositionLatch 分工相反：本件由位置产生输出；FB_DL_ElectronicCam 管凸轮表插值，本件只做开关窗判）
  功能 Function : 1) 轴位置（模 360）逐路判是否落在 [pos+offset, pos+offset+width]；窗口跨 0° 按两段拆判；
                  2) Cyclic 每圈重复触发；Single 每开关只触发一次（abFired 锁存，重置仅经 bReset 上升沿）；
                  3) nActiveMask 聚合 ≤32 路活动位（SHL 显式位号，禁魔法掩码）。
  边界 Boundary : ① uSwitchCount = 0 或超数组上界（32）判组态错返回（全输出 FALSE 安全侧）；
                  ② uSwitchCount > 32 不生成 nActiveMask（判组态错，禁静默截断）；
                  ③ afSwitchWidthDeg <= 0 或 >= 360 判组态错；
                  ④ 轴位置非有限（NaN 用 x<>x 自反判定）置故障态并全输出 FALSE（安全侧，锁存至复位）；
                  ⑤ 解除式自证：abFired 清零 = bReset 上升沿（引脚可满足）；Fault 退出 = bReset 上升沿 AND 组态合法；
                  ⑥ CASE 全态覆盖 + ELSE 兜底置故障相。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化）；仅 Standard.library（R_TRIG/SHL）
  码表 Error codes（本件格 04_0_A5，子码步进 +0x100）:
    16#0004_01A5 信息级：开关组使能运行中（不置故障）
    16#0004_02A5 故障级：组态非法（通道数越域 / 宽度 <= 0 或 >= 360），锁存至复位
    16#0004_03A5 故障级：轴位置非有限（NaN/Inf），全输出 FALSE，锁存至复位
    16#0004_04A5 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_CamSwMode :
(
    eSingle := 0,   // 单次：每开关每使能期只触发一次 / Single, fires once per enable period
    eCyclic := 1    // 周期：每圈重复触发 / Cyclic, fires every revolution
);
END_TYPE

TYPE E_DL_CamSwState :
(
    eIdle  := 0,    // 空闲：未使能 / Idle, not enabled
    eRun   := 10,   // 运行：使能且位置有效 / Run, enabled with valid position
    eFault := 90    // 故障：组态/位置故障锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectronicCamSwitchBank
VAR_INPUT
    anSwitchPosDeg  : ARRAY[0..31] OF LREAL;   // 开关位置表 [deg] / Switch position table
    afSwitchWidthDeg: ARRAY[0..31] OF REAL;    // 触发宽度 [deg] / Trigger width
    auPhaseOffsetDeg: ARRAY[0..31] OF REAL;    // 相位偏移 [deg] / Phase offset
    uSwitchCount    : INT;                     // 开关数 [路]，域 1..32 / Switch count
    bEnable         : BOOL := FALSE;           // 使能 / Enable
    eTriggerMode    : E_DL_CamSwMode;          // 触发模式（Single/Cyclic）/ Trigger mode
    bReset          : BOOL := FALSE;           // 复位（abFired 清零唯一路径）/ Reset, sole abFired clear path
END_VAR
VAR_OUTPUT
    abSwitchOut     : ARRAY[0..31] OF BOOL;    // 各开关输出 / Per-switch outputs
    bAnyActive      : BOOL;                    // 任一开关活动 / Any switch active
    nActiveMask     : DWORD;                   // 活动位掩码（<= 32 路才生成）/ Active bit mask
    nErrId          : UDINT;                   // 事件码，0 = 无事件 / Event code
    eState          : E_DL_CamSwState;         // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iAxis           : I_DL_MotionAxis;         // 轴接口引用（注入，不实例化）/ Axis reference, injected
END_VAR
VAR
    rtReset  : R_TRIG;                         // 复位上升沿 / Reset rising edge
    _eState  : E_DL_CamSwState := E_DL_CamSwState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _abFired : ARRAY[0..31] OF BOOL;           // Single 模式已触发锁存 / Single-mode fired latch
    _bCfgBad : BOOL;                           // 组态非法锁存 / Configuration fault latch
    _bPosBad : BOOL;                           // 位置非有限标志 / Position non-finite flag
    _rPos    : LREAL;                          // 轴位置 [deg] / Axis position
    _rPosMod : LREAL;                          // 模 360 位置 [deg] / Position modulo 360
    _rStart  : LREAL;                          // 窗口起点（模 360）/ Window start, wrapped
    _rEnd    : LREAL;                          // 窗口终点（模 360 前）/ Window end before wrap
    _bInWin  : BOOL;                           // 本路在窗标志 / In-window flag
    _nK      : INT;                            // 循环计数器 / Loop counter
END_VAR
VAR CONSTANT
    nMaxSw     : INT   := 32;      // 数组上界 = 掩码位宽 [路] / Array bound = mask width
    DL_FULL    : LREAL := 360.0;   // 全圆周期 [deg] / Full circle period
    DL_ZERO_EPS: LREAL := 1.0E-9;  // 近零判据 / Near-zero epsilon
END_VAR

(* —— 段 0：边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                        // 复位上升沿，每拍必调

(* —— 段 1：单拍量预清零（锁存量 _abFired/_bCfgBad 不入清单，R187①） —— *)
bAnyActive := FALSE;                           // 聚合出口缺省 FALSE
nActiveMask := 0;                              // 掩码缺省 0
nErrId := 16#0000_0000;                        // 事件码缺省无事件
FOR _nK := 0 TO (nMaxSw - 1) DO
    abSwitchOut[_nK] := FALSE;                 // 输出缺省 FALSE（安全侧，段 6 单点置位）
END_FOR

(* —— 段 2：复位沿（abFired 清零唯一路径；Fault 解除唯一路径） —— *)
IF rtReset.Q THEN
    FOR _nK := 0 TO (nMaxSw - 1) DO
        _abFired[_nK] := FALSE;                // Single 触发锁存清零（解除式自证：bReset 可满足）
    END_FOR
    _bCfgBad := FALSE;                         // 组态锁存清零
    _bPosBad := FALSE;                         // 位置故障清零
    IF _eState = E_DL_CamSwState.eFault THEN
        _eState := E_DL_CamSwState.eIdle;      // 故障相回空闲（组态合法性由段 3 复判）
    END_IF
END_IF

(* —— 段 3：组态域闸（每拍复判；锁存置位只在 Fault 判定时引用） —— *)
IF (uSwitchCount <= 0) OR (uSwitchCount > nMaxSw) THEN
    _bCfgBad := TRUE;                          // 通道数越域（> 32 不生成掩码，禁静默截断）
END_IF
IF NOT _bCfgBad THEN
    FOR _nK := 0 TO (uSwitchCount - 1) DO
        IF (LREAL(afSwitchWidthDeg[_nK]) <= DL_ZERO_EPS)
           OR (LREAL(afSwitchWidthDeg[_nK]) >= DL_FULL) THEN
            _bCfgBad := TRUE;                  // 宽度 <= 0 或 >= 360
        END_IF
        IF (REAL_TO_LREAL(auPhaseOffsetDeg[_nK]) <> REAL_TO_LREAL(auPhaseOffsetDeg[_nK]))
           OR (ABS(REAL_TO_LREAL(auPhaseOffsetDeg[_nK])) >= DL_FULL) THEN
            _bCfgBad := TRUE;                  // 相位偏移非有限或越一圈
        END_IF
    END_FOR
END_IF

(* —— 段 4：轴位置采集与非有限判定（NaN 用 x<>x 自反，Inf 用幅值上限兜） —— *)
_rPos := iAxis.fPosition;                      // 轴位置 [deg]
IF (_rPos <> _rPos) OR (ABS(_rPos) > 1.0E15) THEN
    _bPosBad := TRUE;                          // 非有限：置故障态全输出 FALSE（安全侧）
END_IF
IF NOT _bPosBad THEN
    _rPosMod := _rPos - DL_FULL * TRUNC(_rPos / DL_FULL);   // 模 360 折返到 [0, 360)
END_IF

(* —— 段 5：相位机（只做迁移；出口在段 6） —— *)
CASE _eState OF

E_DL_CamSwState.eIdle:
    IF _bCfgBad OR _bPosBad THEN
        _eState := E_DL_CamSwState.eFault;     // 组态/位置故障：进故障相
    ELSIF bEnable THEN
        _eState := E_DL_CamSwState.eRun;       // 使能：进运行相
    END_IF

E_DL_CamSwState.eRun:
    IF _bCfgBad OR _bPosBad THEN
        _eState := E_DL_CamSwState.eFault;     // 组态/位置故障：进故障相
    ELSIF NOT bEnable THEN
        _eState := E_DL_CamSwState.eIdle;      // 失能：回空闲（故障与失能分流，归因唯一）
    END_IF

E_DL_CamSwState.eFault:
    ;                                          // 故障相：等复位沿（段 2 承载解除）

ELSE
    _eState := E_DL_CamSwState.eFault;         // 非法相位 ID 兜底

END_CASE

(* —— 段 6：窗口判算与出口（仅运行相执行；故障/空闲全 FALSE 已由段 1 缺省保证） —— *)
IF _eState = E_DL_CamSwState.eRun THEN
    FOR _nK := 0 TO (uSwitchCount - 1) DO
        _rStart := _rPosMod + LREAL(auPhaseOffsetDeg[_nK]);     // 起点 = 位置 + 相位偏移
        _rStart := _rStart - DL_FULL * TRUNC(_rStart / DL_FULL); // 模 360 折返到 [0, 360)
        _rEnd   := _rStart + LREAL(afSwitchWidthDeg[_nK]);      // 终点（可越 360）
        IF _rEnd <= DL_FULL THEN
            _bInWin := (_rPosMod >= _rStart) AND (_rPosMod <= _rEnd);            // 单段判
        ELSE
            _bInWin := (_rPosMod >= _rStart) OR (_rPosMod <= (_rEnd - DL_FULL)); // 跨 0° 两段拆判
        END_IF
        IF _bInWin THEN
            IF eTriggerMode = E_DL_CamSwMode.eSingle THEN
                IF NOT _abFired[_nK] THEN
                    abSwitchOut[_nK] := TRUE;       // Single：首遇触发
                    _abFired[_nK] := TRUE;          // 触发锁存（bReset 沿清零）
                END_IF
            ELSE
                abSwitchOut[_nK] := TRUE;           // Cyclic：每圈重复触发
            END_IF
            nActiveMask := nActiveMask OR SHL(INT_TO_DWORD(1), _nK);   // SHL 显式位号（禁魔法掩码）
        END_IF
    END_FOR
    bAnyActive := nActiveMask <> 0;                 // 任一活动聚合
    nErrId := 16#0004_01A5;                         // 信息级：开关组运行中
END_IF

(* —— 段 7：故障码与状态出口单点映射（锁存码回放，禁同拍抹除） —— *)
IF (_eState = E_DL_CamSwState.eFault) AND _bCfgBad THEN
    nErrId := 16#0004_02A5;                         // 故障级：组态非法
ELSIF (_eState = E_DL_CamSwState.eFault) AND _bPosBad THEN
    nErrId := 16#0004_03A5;                         // 故障级：位置非有限
END_IF
eState := _eState;                                  // 状态出口单点映射

END_FUNCTION_BLOCK
