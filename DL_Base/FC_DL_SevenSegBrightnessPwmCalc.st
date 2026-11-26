(* ============================================================
   DL_Base / FC_DL_SevenSegBrightnessPwmCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：亮度 → PWM 占空换算：uDuty = uLevel×255/uFullScale（整数式），
         再按下限保护抬到 uMinDuty 并置 bAtMin（防人眼可辨的熄灭/闪烁）
   边界：uFullScale = 0 → 除零闸，占空 0、bAtMin=TRUE、返回 FALSE（N1）；
         uLevel > uFullScale → 按满占空钳定；中间乘积用 UDINT 承载
         （255×255 = 65025 > USINT），防窄型溢出
   依赖：仅 IEC 61131-3（USINT_TO_UDINT / UDINT_TO_USINT） ｜ 溯源：DLF-C-SEVENSEG
   ============================================================ *)
FUNCTION FC_DL_SevenSegBrightnessPwmCalc : BOOL
VAR_INPUT
    uLevel     : USINT;  // 亮度等级，域 0~uFullScale [级] / Brightness level
    uFullScale : USINT;  // 亮度满量程，域 > 0 [级] / Full scale of the brightness
    uMinDuty   : USINT;  // 占空下限保护 [1/255] / Lower duty clamp
END_VAR
VAR_OUTPUT
    uDuty  : USINT;  // 占空值（255 = 100%）[1/255] / Duty value where 255 is one hundred percent
    bAtMin : BOOL;   // 占空被下限抬升 [-] / Duty raised by the lower clamp
END_VAR
VAR
    _uLevelUse : USINT;  // 钳定后亮度等级 [级] / Clamped brightness level
    _udDuty    : UDINT;  // 占空中间值 [1/255] / Intermediate duty value
END_VAR

(* 段 0：出口预置安全侧（占空 0、标志置位，N1/N3） *)
FC_DL_SevenSegBrightnessPwmCalc := FALSE;
uDuty := 0;  bAtMin := TRUE;

(* 段 1：除零闸（满量程为 0 无定义） *)
IF uFullScale = 0 THEN RETURN; END_IF

(* 段 2：等级钳定（超满量程按满占空，禁窄型溢出） *)
IF uLevel > uFullScale THEN _uLevelUse := uFullScale; ELSE _uLevelUse := uLevel; END_IF

(* 段 3：占空换算（UDINT 承载，除子已证 > 0） *)
_udDuty := USINT_TO_UDINT(_uLevelUse) * 255 / USINT_TO_UDINT(uFullScale);
IF _udDuty > 255 THEN _udDuty := 255; END_IF       // 结构性兜底：比例上界 255

(* 段 4：下限保护（判据在原始占空上，出口单点裁决，N4） *)
IF UDINT_TO_USINT(_udDuty) < uMinDuty THEN
    uDuty := uMinDuty;  bAtMin := TRUE;
ELSE
    uDuty := UDINT_TO_USINT(_udDuty);  bAtMin := FALSE;
END_IF
FC_DL_SevenSegBrightnessPwmCalc := TRUE;
END_FUNCTION
