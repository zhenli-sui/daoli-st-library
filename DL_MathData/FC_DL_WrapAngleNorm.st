// FC_DL_WrapAngleNorm v1.0.0
(*==============================================================================
 * 功能描述: 角度归一化到 [-180, 180) 区间。fmod 风格两段修正：先以 TRUNC 取整
 *           折返 (-360,360)，再单侧修正进 [-180,180)；非有限输入返回 0 并置
 *           bValid=FALSE。同名避让：库内已有 FC_DL_WrapAngleDeg。
 * 接口契约: 输入 fAngleDeg [°]；输出 bValid 回执，返回归一后角度 [°]。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_WrapAngleNorm : REAL
VAR_INPUT
    fAngleDeg : REAL := 0.0;   // 输入角度（任意域）[°] / Input angle, any range [deg]
END_VAR
VAR_OUTPUT
    bValid : BOOL;             // 结果有效回执 [-] / Result validity receipt
END_VAR
VAR
    fW : REAL;                 // 折返工作角 [°] / Folded working angle
END_VAR

(* —— 段 0：全路径赋值缺省（无效安全侧） —— *)
bValid := FALSE;                             // 有效回执预清 / Validity preset
FC_DL_WrapAngleNorm := 0.0;                  // 返回角缺省零 / Result default zero

(* —— 段 1：非有限与幅值闸（NaN 自反判 + 近 Inf 兜底） —— *)
IF fAngleDeg <> fAngleDeg THEN               // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive test
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF
IF ABS(fAngleDeg) >= 1.0E15 THEN             // 近 Inf 幅值闸（TRUNC 精度域兜底） / Near-Inf magnitude gate
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF

(* —— 段 2：两段归一化（TRUNC 折返 → 单侧修正进 [-180,180)） —— *)
fW := fAngleDeg - 360.0 * TRUNC(fAngleDeg / 360.0);   // 第一段：折返到 (-360,360) / First fold into (-360,360)
IF fW >= 180.0 THEN                          // 第二段：上界修正进 [-180,180) / Upper correction into range
    fW := fW - 360.0;
ELSIF fW < -180.0 THEN                       // 第二段：下界修正进 [-180,180) / Lower correction into range
    fW := fW + 360.0;
END_IF
FC_DL_WrapAngleNorm := fW;                   // 返回归一后角度 / Return wrapped angle
bValid := TRUE;                              // 有效回执 / Validity receipt

END_FUNCTION
