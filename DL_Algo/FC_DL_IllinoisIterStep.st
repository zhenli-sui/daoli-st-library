(* ============================================================
   DL_Algo / FC_DL_IllinoisIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：Illinois 改进试位单步的端点修正环节。由上次插值点 fXPrev 落在括号哪一半
         定出本次替换侧（1=a / 2=b）；若与 uLastSide 相同（同端连续被保留），
         则把停滞端函数值折半，防单侧卡死（收敛阶高于经典试位法）
   边界：端点函数值判零（容差）→ 已是根，不折半原样回传；非有限 → 两值写 0
         且 uSideOut=0（上层据侧码 0 拒收本步，N1：判据位与实值同源）
   依赖：仅 IEC 61131-3（ABS / MIN / MAX） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_IllinoisIterStep : BOOL
VAR_INPUT
    fA        : LREAL;  // 括号下界 [-] / Lower bracket bound
    fB        : LREAL;  // 括号上界 [-] / Upper bracket bound
    fFa       : LREAL;  // 下界函数值 [-] / Function value at the lower bound
    fFb       : LREAL;  // 上界函数值 [-] / Function value at the upper bound
    fXPrev    : LREAL;  // 上次弦线插值点 [-] / Previous interpolated point
    uLastSide : UDINT;  // 上次被替换侧 0 无历史 / 1 a / 2 b [-] / Side replaced last time
END_VAR
VAR_OUTPUT
    fFaOut       : LREAL;  // a 端函数值（可能折半）[-] / Outgoing value at the lower bound
    fFbOut       : LREAL;  // b 端函数值（可能折半）[-] / Outgoing value at the upper bound
    uSideOut     : UDINT;  // 本次替换侧 0 非法 / 1 a / 2 b [-] / Side replaced this time
    bHalfApplied : BOOL;   // 本次执行了停滞端折半 [-] / Stagnating endpoint halving applied
END_VAR
VAR
    _fMid  : LREAL;  // 括号中点 [-] / Bracket midpoint
    _uSide : UDINT;  // 本次替换侧暂存 [-] / Staged side code
END_VAR
VAR CONSTANT
    DL_ILL_EPS : LREAL := 1.0E-12;  // 判零容差 [-] / Zero tolerance
END_VAR

(* 段 0：出口预置（侧码 0、未折半，值域先落 0） *)
FC_DL_IllinoisIterStep := FALSE;
fFaOut := 0.0;  fFbOut := 0.0;  uSideOut := 0;  bHalfApplied := FALSE;

(* 段 1：非有限闸（NaN 自反 + Inf 差值自减，五入参全量枚举，R79/R272） *)
IF (fA <> fA) OR (fB <> fB) OR (fFa <> fFa) OR (fFb <> fFb) OR (fXPrev <> fXPrev) THEN
    RETURN;
END_IF
(* Inf 双判须覆盖 fA/fB/fFa/fFb：只判 fXPrev 时 fFa=+Inf 会原样进 fFaOut 出口并
   以 uSideOut≠0、返回 TRUE 上报（伪有效端点值） *)
IF ((fA - fA) <> (fA - fA)) OR ((fB - fB) <> (fB - fB))
   OR ((fFa - fFa) <> (fFa - fFa)) OR ((fFb - fFb) <> (fFb - fFb))
   OR ((fXPrev - fXPrev) <> (fXPrev - fXPrev)) THEN RETURN; END_IF
fFaOut := fFa;  fFbOut := fFb;                // 闸后先原样回传

(* 段 2：端点已是根（容差判零）则不做任何修正 *)
IF (ABS(fFa) <= DL_ILL_EPS) OR (ABS(fFb) <= DL_ILL_EPS) THEN
    uSideOut := 1;  FC_DL_IllinoisIterStep := TRUE;  RETURN;
END_IF

(* 段 3：本次替换侧判定（上次插值点落在哪一半） *)
_fMid := MIN(fA, fB) + (ABS(fB - fA)) / 2.0;
IF fXPrev <= _fMid THEN
    _uSide := 1;                              // 偏下：a 端被替换
ELSE
    _uSide := 2;                              // 偏上：b 端被替换
END_IF

(* 段 4：Illinois 折半规则（同一端连续被保留 → 停滞端折半） *)
IF uLastSide = _uSide THEN
    IF _uSide = 1 THEN
        fFbOut := fFb / 2.0;                  // a 被替换：停滞端为 b
    ELSE
        fFaOut := fFa / 2.0;                  // b 被替换：停滞端为 a
    END_IF
    bHalfApplied := TRUE;
END_IF

(* 段 5：单一出口裁决（N4） *)
uSideOut := _uSide;  FC_DL_IllinoisIterStep := TRUE;
END_FUNCTION
