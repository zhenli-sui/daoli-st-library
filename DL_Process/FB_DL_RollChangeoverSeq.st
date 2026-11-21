(*
  Component : FB_DL_RollChangeoverSeq
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.1
  CodeSeg   : 16#06_0_3F
  Summary   : 换卷换规格一键切换顺控：参数配方合法性校验（首失败项索引）+ 张力回零超时守护 + 步进状态机。
              Roll changeover sequence: recipe validation with first-fail index plus tension zeroing timeout and step machine.
  溯源声明  : 仅借 t2-isa88 换卷流程分类与步序域，代码 clean-room（T2 借鉴件）
  边界安全  : 配方参数域闸逐项校验并输出首失败项索引（拒绝启动，按派单要点）；
              张力回零判据带超时（tZeroMs 输入引脚），不得无限等待；步进 CASE 必带 ELSE 安全步；
              张力零位判据带容差（禁等值直比）；故障码锁存有复位沿可达解除路径；TON 每拍无条件刷新。
  复用      : 复用 FB_DL_StepSequencer + FB_DL_InterlockMatrix 语义（clean-room 自含实现，无实例依赖）
*)

FUNCTION_BLOCK FB_DL_RollChangeoverSeq
VAR_INPUT
    bRun        : BOOL;                 (* 顺控使能 · Enable *)
    bStartCmd   : BOOL;                 (* 一键切换指令 [事件]，沿触发 · One-key start command *)
    fTenNowN    : LREAL;                (* 当前张力反馈 [N] · Current tension feedback *)
    fTensionSetN: LREAL := 50.0;        (* 配方：新卷张力给定 [N] · Recipe tension setpoint *)
    fSpdMpm     : LREAL := 120.0;       (* 配方：新规格线速 [m/min] · Recipe line speed *)
    fSpdMaxMpm  : LREAL := 300.0;       (* 线速上限 [m/min] · Speed upper bound *)
    fTenMaxN    : LREAL := 120.0;       (* 张力上限 [N] · Tension upper bound *)
    fZeroEpsN   : LREAL := 1.0;         (* 张力零位判据容差 [N] · Tension zero tolerance *)
    tZeroMs     : TIME  := T#8000MS;    (* 张力回零超时 [ms] · Tension zeroing timeout *)
    bReset      : BOOL;                 (* 故障复位 [事件]，沿触发 · Fault reset, edge *)
    fEps        : LREAL := 1.0E-6;      (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    eStep    : (eStpIdle := 0, eStpValidate := 1, eStpTenZero := 2, eStpSwitch := 3);   (* 步枚举输出 / Step output enum *)
    nFailIdx : INT;                     (* 配方首失败项索引 [索引]，0 为全过 · First failed recipe index *)
    bRejected: BOOL;                    (* 配方拒绝启动标志 · Recipe rejected flag *)
    bSeqDone : BOOL;                    (* 切换完成脉冲 [脉冲] · Changeover done pulse *)
    bError   : BOOL;                    (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId : UDINT;                   (* 事件码 16#0000_003F，0 无事件 · Event code *)
END_VAR
VAR
    _bDone   : BOOL;                   (* 完成脉冲内部标志 [开关] · Internal done flag *)
    _eState  : (eStIdle := 0, eStValidate := 1, eStTenZero := 2, eStSwitch := 3);   (* 内部步进状态 / Internal step state *)
    uCode    : WORD;    (* 码位暂存（锁存），复位沿清 [码] · Latched code staging *)
    tonZero  : TON;     (* 张力回零超时计时 [ms]，每拍无条件刷新 · Zeroing timeout timer *)
    rTrigStrt: R_TRIG;  (* 起动沿检测 · Start edge *)
    rTrigRst : R_TRIG;  (* 复位沿检测 · Reset edge *)
    bSigOk   : BOOL;    (* 输入有效标志 · Input validity flag *)
    nCycles  : UDINT;   (* 完成切换计数 [次]，防回卷 · Changeover count *)
END_VAR
VAR CONSTANT
    DL_RCS_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [次] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonZero(IN := (_eState = eStTenZero), PT := tZeroMs);   (* 回零超时计时 / Zeroing timeout *)
rTrigStrt(CLK := bStartCmd);                            (* 起动沿检测 / Start edge *)
rTrigRst(CLK := bReset);                                (* 复位沿检测 / Reset edge *)

(* === 段 1 · 输入校验与量程闸 === *)
bSigOk := (fTenNowN = fTenNowN) AND (ABS(fTenNowN) < 1.0E308)       // 非有限拦截 / Non-finite guard
          AND (tZeroMs > T#0MS) AND (fZeroEpsN > fEps)               // 超时/容差正域闸 / Timeout and tolerance gates
          AND (fSpdMaxMpm > fEps) AND (fTenMaxN > fEps);             // 上限正域闸 / Upper bound gates
IF rTrigRst.Q THEN
    uCode := 16#0000;                   (* 复位沿清锁存（可达解除路径）/ Reset edge clears the latch *)
END_IF

(* === 段 2 · 主逻辑：配方校验与步进状态机 === *)
CASE _eState OF
    eStIdle:                            (* 空闲步：待令 / Idle *)
        IF bRun AND bSigOk AND rTrigStrt.Q THEN
            nFailIdx := 0;              (* 启动沿才清失败项，拒绝结果保留到下次启动 / Clear only on start edge *)
            bRejected := FALSE;         (* 启动沿清拒绝标志 / Clear reject on start edge *)
            uCode := 16#0000;           (* 启动沿清历史锁存码（可达解除路径 2）/ Clear latched codes on start *)
    _eState := eStValidate;     (* 拍 N 起动沿进入，拍 N+1 校验步 / To validate *)
        END_IF
    eStValidate:                        (* 校验步：逐项域闸，记首失败项 / Validate recipe, record first fail *)
        nFailIdx := 0;                  (* 默认全过 / Default all pass *)
        IF (fTensionSetN <= fEps) OR (fTensionSetN > fTenMaxN) THEN
            nFailIdx := 1;              (* 首失败项 1：张力给定域外 / Fail index 1: tension *)
        ELSIF (fSpdMpm <= fEps) OR (fSpdMpm > fSpdMaxMpm) THEN
            nFailIdx := 2;              (* 首失败项 2：线速域外 / Fail index 2: speed *)
        END_IF
        IF nFailIdx > 0 THEN
            bRejected := TRUE;          (* 拒绝启动并上报首失败项 / Reject with the first fail index *)
            uCode := 16#003F;           (* 故障级：配方域外 / Fault: recipe out of domain *)
            _eState := eStIdle;         (* 回空闲安全步 / Back to idle *)
        ELSE
            _eState := eStTenZero;      (* 校验通过转张力回零步 / To tension zeroing *)
        END_IF
    eStTenZero:                         (* 回零步：张力进入零位容差带 / Zeroing with tolerance band *)
        IF ABS(fTenNowN) < fZeroEpsN THEN
            _eState := eStSwitch;       (* 零位到位转切换步 / To switch *)
        ELSIF tonZero.Q THEN
            uCode := 16#003F;           (* 回零超时锁存故障（不无限等待）/ Latch the zeroing timeout *)
            _eState := eStIdle;         (* 回安全步 / Back to the safe step *)
        END_IF
    eStSwitch:                          (* 切换步：下发新配方参数并收周期 / Switch and close *)
        _bDone := TRUE;                 (* 完成脉冲置内部标志，段 3 输出 / Set internal done flag *)
        IF nCycles < DL_RCS_WRAP THEN
            nCycles := nCycles + 1;     (* 完成切换计数 / Count changeovers *)
        END_IF
        _eState := eStIdle;             (* 回空闲步 / Back to idle *)
ELSE
    _eState := eStIdle;                 (* ELSE 兜底回安全步 / ELSE fallback to safe step *)
END_CASE

(* === 段 3 · 输出映射与故障码（CASE 内未触碰输出枚举）=== *)
bSeqDone := _bDone;                     (* 完成脉冲输出（CASE 置位→此处映射）/ Done pulse mapped from internal flag *)
_bDone := FALSE;                        (* 单拍脉冲收口（置位与收口分离，防同拍抹除）/ One-scan pulse, no same-scan wipe *)
eStep := eStpIdle;                      (* 步映射默认 / Default mapping *)
IF _eState = eStValidate THEN
    eStep := eStpValidate;              (* 校验步映射 / Map validate *)
ELSIF _eState = eStTenZero THEN
    eStep := eStpTenZero;               (* 回零步映射 / Map zeroing *)
ELSIF _eState = eStSwitch THEN
    eStep := eStpSwitch;                (* 切换步映射 / Map switch *)
END_IF
bError := (uCode <> 16#0000);           (* 故障锁存回放 / Latched fault replay *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_003F 形态）/ Single write point *)
END_FUNCTION_BLOCK
