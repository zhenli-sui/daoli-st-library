(* ============================================================
   DL_Motion / FC_DL_ToolLengthCompDeltaCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：刀补切换增量 ΔL = 新长度 − 生效长度，域内回执刀补号供上层写回
   边界：|ΔL| > 200 mm 或 入参非法 → 增量 0、回执 0、bOverLimit=TRUE
         （N4：门控在最后一次赋值处，越限增量绝不下发轴；N1：实值同步写 0）
   依赖：仅 IEC 61131-3（ABS） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_ToolLengthCompDeltaCalc : BOOL
VAR_INPUT
    fLenNewMm : REAL;   // 新刀具长度（刀补表目标值）[mm] / New tool length from the offset table
    fLenOldMm : REAL;   // 当前生效刀补长度 [mm] / Currently active tool length offset
    nToolNo   : DINT;   // 目标刀补号，域 ≥ 0 [-] / Target tool offset number
END_VAR
VAR_OUTPUT
    fDeltaMm   : REAL;   // 长度补偿增量（新−旧）[mm] / Length compensation delta
    nToolNoAck : DINT;   // 刀补号回执，0 = 未应用 [-] / Applied offset number, zero means rejected
    bOverLimit : BOOL;   // 越限或入参非法 [-] / Over limit or illegal argument
END_VAR
VAR
    _fDelta : REAL;  // 未门控的原始增量 [mm] / Raw delta before gating
END_VAR
VAR CONSTANT
    DL_TLC_DMAX : REAL := 200.0;  // 单次换刀允许最大长度差 [mm] / Maximum length change per tool change
END_VAR

(* 段 0：出口预置安全侧（不应用，N3） *)
FC_DL_ToolLengthCompDeltaCalc := FALSE;
fDeltaMm := 0.0;  nToolNoAck := 0;  bOverLimit := TRUE;

(* 段 1：非有限闸 + 刀补号域闸 *)
IF (fLenNewMm <> fLenNewMm) OR (fLenOldMm <> fLenOldMm)
   OR ((fLenNewMm - fLenNewMm) <> (fLenNewMm - fLenNewMm)) THEN
    RETURN;
END_IF
IF nToolNo < 0 THEN RETURN; END_IF

(* 段 2：增量与越限判据（判据基于原始增量，禁先夹量程） *)
_fDelta := fLenNewMm - fLenOldMm;
IF (_fDelta <> _fDelta) OR (ABS(_fDelta) > DL_TLC_DMAX) THEN
    RETURN;                                              // 越限：增量与回执保持 0
END_IF

(* 段 3：单一出口裁决（N4：越限门之后才落最终值） *)
fDeltaMm := _fDelta;  nToolNoAck := nToolNo;  bOverLimit := FALSE;
FC_DL_ToolLengthCompDeltaCalc := TRUE;
END_FUNCTION
