(* ============================================================
   DL_Motion / FC_DL_RotFeedInvTimeCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：旋转轴进给率双向换算与限幅。正向 INV_TIME[1/min]×每转角度[deg/rev]
         = deg/min；反向按限幅比例折算等效每转进给 fFeedPerRev[deg/rev]
   边界：INV≤0 / 每转角度≤0 / 上限≤0 → 码 1/2/3；非有限 → 码 4；三者均写 0 出口（N1/N3）
   依赖：仅 IEC 61131-3（MIN） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_RotFeedInvTimeCalc : BOOL
VAR_INPUT
    fInvTimeVal    : LREAL;  // INV_TIME 编程值，域 > 0 [1/min] / Inverse time value per minute
    fDegPerRev     : LREAL;  // 每转对应角度（分度轴 360）[deg/rev] / Degrees per revolution
    fFeedMaxDegMin : LREAL;  // 允许进给上限，域 > 0 [deg/min] / Allowed feed ceiling
END_VAR
VAR_OUTPUT
    fFeedDegMin : LREAL;  // 限幅后进给率 [deg/min] / Limited feed rate
    fFeedPerRev : LREAL;  // 折算后每转进给 [deg/rev] / Effective advance per revolution
    uErrId      : UDINT;  // 出口码 0/1/2/3/4 [-] / Outlet code
    bLimited    : BOOL;   // 本拍被上限钳制 [-] / Feed clamped by the ceiling
END_VAR
VAR
    _fRaw : LREAL;  // 未限幅进给率 = INV × 每转角度 [deg/min] / Unlimited feed rate
END_VAR
VAR CONSTANT
    DL_RFI_EPS : LREAL := 1.0E-9;  // 判零与判等容差 [deg/min] / Zero and equality tolerance
END_VAR

(* 段 0：出口预置安全侧（进给 0 即停转，N3） *)
FC_DL_RotFeedInvTimeCalc := FALSE;
fFeedDegMin := 0.0;  fFeedPerRev := 0.0;  bLimited := TRUE;  uErrId := 4;

(* 段 1：非有限闸 + 三域闸 *)
IF (fInvTimeVal <> fInvTimeVal) OR (fDegPerRev <> fDegPerRev) OR (fFeedMaxDegMin <> fFeedMaxDegMin) THEN
    RETURN;
END_IF
IF fInvTimeVal <= 0.0 THEN uErrId := 1; RETURN; END_IF
IF fDegPerRev <= 0.0 THEN uErrId := 2; RETURN; END_IF
IF fFeedMaxDegMin <= 0.0 THEN uErrId := 3; RETURN; END_IF

(* 段 2：正向换算 INV[1/min] × 每转角度[deg/rev] = [deg/min] *)
_fRaw := fInvTimeVal * fDegPerRev;
IF (_fRaw <> _fRaw) OR ((_fRaw - _fRaw) <> (_fRaw - _fRaw)) THEN RETURN; END_IF

(* 段 3：单侧限幅（进给恒非负），标志与出口同源 *)
IF _fRaw > fFeedMaxDegMin + DL_RFI_EPS THEN
    fFeedDegMin := fFeedMaxDegMin;  bLimited := TRUE;
ELSE
    fFeedDegMin := _fRaw;  bLimited := FALSE;
END_IF

(* 段 4：反向折算（除子 _fRaw 已证 > 0） + 单一出口裁决（N4） *)
fFeedPerRev := fDegPerRev * (fFeedDegMin / _fRaw);
IF (fFeedPerRev <> fFeedPerRev) OR ((fFeedPerRev - fFeedPerRev) <> (fFeedPerRev - fFeedPerRev)) THEN
    fFeedDegMin := 0.0;  fFeedPerRev := 0.0;  bLimited := TRUE;  uErrId := 4;  RETURN;
END_IF
uErrId := 0;  FC_DL_RotFeedInvTimeCalc := TRUE;
END_FUNCTION
