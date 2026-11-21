(*
  Name        : FB_DL_RecipeSwitchHandover
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 配方切换交接编排：旧配方排空确认 → 参数装载复核（校验和整数直比）→ 新配方放行三相时序，各相独立超时故障码，中止命令相边界停下；/ Recipe switch handover orchestration: drain confirm, load recheck by integer checksum compare, release three-phase sequence with per-phase timeout fault codes and abort at phase boundary
  溯源        : 借 packml/isa88 的配方切换/批次编排组织，clean-room 实现
  Boundary    : ① 三相（排空确认/装载复核/放行）各自 TON 断输入归零 + 相超时独立锁存故障码（R40/R44）；
                ② 装载复核 = 参数集校验和整数直比，不符不放行不半装载（锁存故障至复位沿）；
                ③ 切换中收到中止命令 → 当前相边界停下（不回滚已装载段，eHold 相状态可查，信息级成因）；
                ④ 放行前复核旧配方累计量已清零反馈（幂等放行），未清零不放行（锁存故障）；
                ⑤ 命令优先级：中止 > 放行 > 装载，低优先命令直接丢弃不排队（放行仅放行相生效，装载仅空闲相受理）。
*)
TYPE E_DL_RshState :
(
    eIdle    := 0,                           (* 空闲（可受理装载命令） / Idle *)
    eDrain   := 10,                          (* 旧配方排空确认相 / Drain confirm *)
    eLoadChk := 20,                          (* 参数装载复核相 / Load recheck *)
    eRelease := 30,                          (* 新配方放行相 / Release *)
    eHold    := 40,                          (* 中止驻留相（状态可查） / Abort hold *)
    eFault   := 90                           (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_RshCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：相超时/周期域越界 / Illegal config *)
    eDrainTo   := 2,                        (* 排空相超时（独立码，边界①） / Drain timeout *)
    eLoadTo    := 3,                        (* 装载复核相超时（独立码） / Load recheck timeout *)
    eRelTo     := 4,                        (* 放行相超时（独立码） / Release timeout *)
    eChkMis    := 5,                        (* 校验和不符（不放行不半装载，边界②） / Checksum mismatch *)
    eAccNotClr := 6,                         (* 旧累计量未清零（不放行，边界④） / Accumulator not cleared *)
    eAbort     := 7,                        (* 中止驻留（信息级，边界③） / Abort hold, info level *)
    ePhaseBad  := 8                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_RecipeSwitchHandover
VAR_INPUT
    bCmdLoad : BOOL := FALSE;                (* 装载命令（仅空闲相受理，低优先丢弃）[-] / Load command *)
    bCmdRelease: BOOL := FALSE;              (* 放行命令（仅放行相复核生效）[-] / Release command *)
    bCmdAbort: BOOL := FALSE;                (* 中止命令（最高优先级，相边界停下）[-] / Abort command *)
    bDrainDone: BOOL := FALSE;               (* 排空完成反馈（属主工艺确认）[-] / Drain done feedback *)
    nChkCalc : DINT := 0;                    (* 参数集实算校验和（属主算好输入）[-] / Calculated checksum *)
    nChkExpect: DINT := 0;                   (* 期望校验和（整数直比目标）[-] / Expected checksum *)
    bAccClear: BOOL := FALSE;                (* 旧配方累计量已清零反馈 [-] / Accumulator cleared feedback *)
    tDrain   : TIME := T#30S;                (* 排空相超时，域 > T#0S [ms] / Drain phase timeout *)
    tLoadChk : TIME := T#10S;                (* 装载复核相超时 [ms] / Load phase timeout *)
    tRelease : TIME := T#5S;                 (* 放行相超时 [ms] / Release phase timeout *)
    tScan    : TIME := T#100MS;              (* 扫描周期，域 > T#0S [ms] / Scan period *)
    bEnable  : BOOL := TRUE;                 (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障回空闲 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bReleased: BOOL;                         (* 放行完成脉冲（单拍）[-] / Released pulse *)
    bHold    : BOOL;                         (* 中止驻留指示（状态可查，边界③）[-] / Abort hold indicator *)
    nActPhase: INT;                          (* 当前生效相序号（诊断）[-] / Active phase index *)
    eState   : E_DL_RshState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_RshCause;                (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_RshState := E_DL_RshState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_RshCause := E_DL_RshCause.eNone;  (* 成因锁存量 / Latched cause *)
    rtLoad  : R_TRIG;                        (* 装载命令沿实例，段 0 无条件调用 / Load edge instance *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonDrain: TON;                           (* 排空相超时（IN 串相位闸，边界①） / Drain timeout *)
    tonLoadT: TON;                           (* 装载相超时（IN 串相位闸） / Load timeout *)
    tonRel  : TON;                           (* 放行相超时（IN 串相位闸） / Release timeout *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bRelI  : BOOL;                          (* 放行脉冲内部量（统一出口映射，R187） / Release pulse internal *)
    _bChkOk : BOOL;                          (* 校验和相符当拍量（整数直比）[-] / Checksum match *)
END_VAR
VAR CONSTANT
    DL_RSH_EPS : REAL := 1.0E-6;             (* 判零容差（周期闸配套）[-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；TON 全段 0，边界①） —— *)
_bCfgBad := NOT (tDrain > T#0S) OR NOT (tLoadChk > T#0S) OR NOT (tRelease > T#0S) OR NOT (tScan > T#0S);   (* 相超时/周期域闸（边界①） / Timeout gates *)
rtLoad(CLK := bCmdLoad);                                 (* 装载沿每拍必调 / Load edge every scan *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bChkOk := (nChkCalc = nChkExpect);                      (* 校验和整数直比（边界②） / Checksum integer compare *)
tonDrain(IN := (_eState = E_DL_RshState.eDrain), PT := tDrain);          (* 排空超时：相位闸 + 无条件调用（R40） / Drain timer *)
tonLoadT(IN := (_eState = E_DL_RshState.eLoadChk), PT := tLoadChk);      (* 装载超时：相位闸 + 无条件调用 / Load timer *)
tonRel(IN := (_eState = E_DL_RshState.eRelease), PT := tRelease);        (* 放行超时：相位闸 + 无条件调用 / Release timer *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bRelI := FALSE;                                         (* 放行脉冲内部量预清 / Release preset *)
bReleased := FALSE;                                      (* 放行脉冲出口预清 / Release outlet preset *)
bHold := FALSE;                                          (* 中止指示出口预清（派生拍覆盖） / Hold preset *)
nActPhase := 0;                                          (* 相序号预清（派生拍覆盖） / Phase index preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 回空闲，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_RshCause.eNone;                      (* 清成因 / Clear cause *)
    _eState := E_DL_RshState.eIdle;                      (* 回空闲相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_RshCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_RshState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_RshState.eIdle:                                 (* 空闲：出口确定值，仅装载命令受理（边界⑤） / Idle *)
        IF NOT bEnable THEN
            ;                                            (* 失能保持空闲 / Disabled hold *)
        ELSIF bCmdAbort THEN
            _eCause := E_DL_RshCause.eAbort;             (* 空闲相中止：信息级记因（无相可停） / Abort in idle *)
        ELSIF rtLoad.Q AND NOT _bFault THEN              (* 装载命令沿受理（低优先级在忙相丢弃，边界⑤） / Accept load *)
            _eState := E_DL_RshState.eDrain;             (* 进入排空确认相 / Enter drain *)
        END_IF
    E_DL_RshState.eDrain:                                (* 排空确认相：反馈 or 超时 or 中止（边界①③） / Drain *)
        IF bCmdAbort THEN
            _eCause := E_DL_RshCause.eAbort;             (* 中止：信息级成因（边界③） / Abort cause *)
            _eState := E_DL_RshState.eHold;              (* 当前相边界停下（不回滚） / Hold at boundary *)
        ELSIF tonDrain.Q THEN
            _bFault := TRUE;                             (* 排空相超时独立锁存（边界①） / Drain timeout latch *)
            _eCause := E_DL_RshCause.eDrainTo;           (* 成因：排空超时 / Cause drain timeout *)
            _eState := E_DL_RshState.eFault;             (* 迁故障相 / To fault *)
        ELSIF bDrainDone THEN
            _eState := E_DL_RshState.eLoadChk;           (* 排空确认 → 装载复核相 / To load recheck *)
        END_IF
    E_DL_RshState.eLoadChk:                              (* 装载复核相：校验和直比（边界②） / Load recheck *)
        IF bCmdAbort THEN
            _eCause := E_DL_RshCause.eAbort;             (* 中止：信息级成因（边界③） / Abort cause *)
            _eState := E_DL_RshState.eHold;              (* 相边界停下 / Hold at boundary *)
        ELSIF tonLoadT.Q THEN
            _bFault := TRUE;                             (* 装载相超时独立锁存（边界①） / Load timeout latch *)
            _eCause := E_DL_RshCause.eLoadTo;            (* 成因：装载超时 / Cause load timeout *)
            _eState := E_DL_RshState.eFault;             (* 迁故障相 / To fault *)
        ELSIF NOT _bChkOk THEN
            _bFault := TRUE;                             (* 校验不符锁存：不放行不半装载（边界②） / Mismatch latch *)
            _eCause := E_DL_RshCause.eChkMis;            (* 成因：校验不符 / Cause mismatch *)
            _eState := E_DL_RshState.eFault;             (* 迁故障相（已装载段状态可查） / To fault *)
        ELSE
            _eState := E_DL_RshState.eRelease;           (* 复核通过 → 放行相 / To release *)
        END_IF
    E_DL_RshState.eRelease:                              (* 放行相：累计清零复核 + 放行命令（边界④⑤） / Release *)
        IF bCmdAbort THEN
            _eCause := E_DL_RshCause.eAbort;             (* 中止：信息级成因（边界③） / Abort cause *)
            _eState := E_DL_RshState.eHold;              (* 相边界停下 / Hold at boundary *)
        ELSIF tonRel.Q THEN
            _bFault := TRUE;                             (* 放行相超时独立锁存（边界①） / Release timeout latch *)
            _eCause := E_DL_RshCause.eRelTo;             (* 成因：放行超时 / Cause release timeout *)
            _eState := E_DL_RshState.eFault;             (* 迁故障相 / To fault *)
        ELSIF NOT bAccClear THEN
            _bFault := TRUE;                             (* 旧累计未清零不放行（幂等复核，边界④） / Acc not cleared latch *)
            _eCause := E_DL_RshCause.eAccNotClr;         (* 成因：累计未清 / Cause acc not cleared *)
            _eState := E_DL_RshState.eFault;             (* 迁故障相 / To fault *)
        ELSIF bCmdRelease THEN                           (* 放行命令在放行相生效（低优先在忙相丢弃，边界⑤） / Release command *)
            _bRelI := TRUE;                              (* 放行脉冲内部置位（R187） / Release internal *)
            _eState := E_DL_RshState.eIdle;              (* 回空闲（切换完成） / Back to idle *)
        END_IF
    E_DL_RshState.eHold:                                 (* 中止驻留相：状态可查，新装载沿重启三相（边界③） / Hold *)
        IF NOT bCmdAbort AND rtLoad.Q AND NOT _bFault THEN
            _eState := E_DL_RshState.eDrain;             (* 中止解除 + 新装载沿：从头三相（声明行为） / Restart from drain *)
        END_IF
    E_DL_RshState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_RshState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_RshCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bReleased := _bRelI;                                     (* 放行脉冲单拍出口 / Release pulse outlet *)
bHold := (_eState = E_DL_RshState.eHold);                (* 中止驻留指示镜像 / Hold indicator mirror *)
IF _eState = E_DL_RshState.eDrain THEN
    nActPhase := 1;                                      (* 相序号：排空 / Phase drain *)
ELSIF _eState = E_DL_RshState.eLoadChk THEN
    nActPhase := 2;                                      (* 相序号：装载复核 / Phase load *)
ELSIF _eState = E_DL_RshState.eRelease THEN
    nActPhase := 3;                                      (* 相序号：放行 / Phase release *)
ELSE
    nActPhase := 0;                                      (* 空闲/驻留/故障：0（确定值） / Other phases zero *)
END_IF
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
