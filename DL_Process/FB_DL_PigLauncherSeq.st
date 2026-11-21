(*
  Component : FB_DL_PigLauncherSeq
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_3D
  Summary   : 清管器收发球筒顺控：装球-增压-发球-跟踪-接收联锁状态机，步超时回安全步。
              Pig launcher sequence: load-pressurize-launch-track-receive interlock machine, step timeouts to a safe step.
  溯源声明  : 仅借 t2-lgf 管线清管流程分类与步序域，代码 clean-room（T2 借鉴件）
  边界安全  : 发球联锁：发球阀开且管段空闲（bZoneClear）方可推进；每步超时 tStepMs 提为输入引脚，
              超时锁存故障并回安全步（全阀关、筒卸压指令）；步进 CASE 必带 ELSE 安全步；
              压力正域闸；TON 每拍无条件刷新（段 0）；故障码锁存有复位沿可达解除路径。
  复用      : 复用 FB_DL_StepSequencer + FB_DL_InterlockMatrix 语义（clean-room 自含实现，无实例依赖）
*)

FUNCTION_BLOCK FB_DL_PigLauncherSeq
VAR_INPUT
    bRun        : BOOL;                 (* 顺控使能 · Enable *)
    bStartCmd   : BOOL;                 (* 起动指令 [事件]，沿触发 · Start command, edge *)
    bPigLoaded  : BOOL;                 (* 装球到位反馈 [开关] · Pig loaded feedback *)
    bPressOk    : BOOL;                 (* 增压到位反馈 [开关] · Pressure reached feedback *)
    bZoneClear  : BOOL;                 (* 下游管段空闲联锁 [开关] · Downstream zone clear interlock *)
    bReceived   : BOOL;                 (* 接收筒到位反馈 [开关] · Pig received feedback *)
    tStepMs     : TIME  := T#30000MS;   (* 单步超时 [ms] · Step timeout *)
    bReset      : BOOL;                 (* 故障复位 [事件]，沿触发 · Fault reset, edge *)
    fEps        : LREAL := 1.0E-6;      (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    eStep       : (eStpIdle := 0, eStpLoad := 1, eStpPress := 2, eStpLaunch := 3, eStpReceive := 4);    (* 步枚举输出 / Step output enum *)
    oLoadValve  : BOOL;                 (* 装球筒进气阀输出 [引脚] · Load valve output *)
    oBoostValve : BOOL;                 (* 增压阀输出 [引脚] · Boost valve output *)
    bSeqDone    : BOOL;                 (* 顺控完成脉冲 [脉冲] · Sequence done pulse *)
    bError      : BOOL;                 (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId    : UDINT;                (* 事件码 16#0000_003D，0 无事件 · Event code *)
END_VAR
VAR
    _eState  : (eStIdle := 0, eStLoad := 1, eStPress := 2, eStLaunch := 3, eStReceive := 4);    (* 内部步进状态 / Internal step state *)
    uCode    : WORD;    (* 码位暂存（锁存），条件重置 [码] · Latched code staging *)
    tonStep  : TON;     (* 步超时计时 [ms]，每拍无条件刷新 · Step timeout timer *)
    rTrigStrt: R_TRIG;  (* 起动沿检测 · Start edge *)
    rTrigRst : R_TRIG;  (* 复位沿检测 · Reset edge *)
    nCycles  : UDINT;   (* 完成周期计数 [次]，防回卷 · Completed cycle count *)
END_VAR
VAR CONSTANT
    DLS_PIG_WRAP : UDINT := 4294967290; (* 计数防回卷余量 [次] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonStep(IN := (_eState <> eStIdle), PT := tStepMs);     (* 步超时计时 / Step timeout timing *)
rTrigStrt(CLK := bStartCmd);                            (* 起动沿检测 / Start edge *)
rTrigRst(CLK := bReset);                                (* 复位沿检测 / Reset edge *)

(* === 段 1 · 输入校验与量程闸 === *)
IF tStepMs <= T#0MS THEN
    uCode := 16#003D;                   (* 故障级锁存：步超时整定非正域 / Fault: non-positive step timeout *)
END_IF
IF rTrigRst.Q THEN
    uCode := 16#0000;                   (* 复位沿清锁存码（可达解除路径）/ Reset edge clears the latch *)
END_IF

(* === 段 2 · 主逻辑：五步联锁状态机 === *)
CASE _eState OF
    eStIdle:                            (* 空闲步：全阀关待令 / Idle: valves closed *)
        oLoadValve := FALSE;            (* 阀关安全位 / Safe valve close *)
        oBoostValve := FALSE;
        IF bRun AND (uCode = 16#0000) AND rTrigStrt.Q THEN
            _eState := eStLoad;         (* 拍 N 起动沿进入，拍 N+1 装球步 / To load next scan *)
        END_IF
    eStLoad:                            (* 装球步：开装球阀等到位 / Load: open valve, await feedback *)
        oLoadValve := TRUE;             (* 开装球阀 / Open the load valve *)
        oBoostValve := FALSE;
        IF bPigLoaded THEN
            _eState := eStPress;        (* 到位转增压步 / To pressurize *)
        ELSIF tonStep.Q THEN
            uCode := 16#003D;           (* 步超时锁存故障 / Latch the timeout fault *)
            _eState := eStIdle;         (* 回安全步（全阀关）/ Back to the safe step *)
        END_IF
    eStPress:                           (* 增压步：关装球阀开增压阀 / Pressurize *)
        oLoadValve := FALSE;            (* 关装球阀 / Close the load valve *)
        oBoostValve := TRUE;            (* 开增压阀 / Open the boost valve *)
        IF bPressOk THEN
            _eState := eStLaunch;       (* 增压到位转发球步 / To launch *)
        ELSIF tonStep.Q THEN
            uCode := 16#003D;
            _eState := eStIdle;         (* 超时回安全步 / To the safe step *)
        END_IF
    eStLaunch:                          (* 发球步：联锁闸（管段空闲）才推进 / Launch with the interlock gate *)
        IF bZoneClear THEN
            _eState := eStReceive;      (* 联锁通过转接收步 / To receive *)
        ELSIF tonStep.Q THEN
            uCode := 16#003D;
            _eState := eStIdle;         (* 联锁等待超时回安全步 / Interlock timeout to safe *)
        END_IF
    eStReceive:                         (* 接收步：到位收周期 / Receive and close the cycle *)
        IF bReceived THEN
            IF nCycles < DLS_PIG_WRAP THEN
                nCycles := nCycles + 1; (* 完成周期在迁移点直接计数 / Count at the transition *)
            END_IF
            bSeqDone := TRUE;           (* 完成脉冲置位（段 3 收口）/ Set the done pulse *)
            _eState := eStIdle;         (* 回空闲步 / Back to idle *)
        ELSIF tonStep.Q THEN
            uCode := 16#003D;
            _eState := eStIdle;
        END_IF
ELSE
    _eState := eStIdle;                 (* ELSE 兜底回安全步，全阀关 / ELSE fallback to safe *)
    oLoadValve := FALSE;
    oBoostValve := FALSE;
END_CASE

(* === 段 3 · 输出映射与故障码（CASE 内未触碰输出枚举）=== *)
bSeqDone := FALSE;                      (* 完成脉冲单拍收口（计数已在迁移点完成）/ One-scan done pulse *)
eStep := eStpIdle;                      (* 步映射默认 / Default mapping *)
IF _eState = eStLoad THEN
    eStep := eStpLoad;                  (* 装球步映射 / Map load *)
ELSIF _eState = eStPress THEN
    eStep := eStpPress;                 (* 增压步映射 / Map press *)
ELSIF _eState = eStLaunch THEN
    eStep := eStpLaunch;                (* 发球步映射 / Map launch *)
ELSIF _eState = eStReceive THEN
    eStep := eStpReceive;               (* 接收步映射 / Map receive *)
END_IF
bError := (uCode <> 16#0000);           (* 故障锁存回放 / Latched fault replay *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_003D 形态）/ Single write point *)
END_FUNCTION_BLOCK
