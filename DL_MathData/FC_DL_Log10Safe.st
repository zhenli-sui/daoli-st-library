// FC_DL_Log10Safe v1.0.0
// 开源溯源：来源 brOscatLib（EXP10 镜像件反演族） / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴点 对数换算非正域饱和返回语义
(*==============================================================================
 * 功能描述: 安全 log10。输入 fX > 0 时返回 LN(fX)/LN(10)；fX <= 0 或非有限时
 *           返回 -3.402823e38 饱和值并置 bValid=FALSE（物理无效域安全侧）。
 * 接口契约: 输入 fX；输出 bValid 回执，返回值为 log10 结果。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_Log10Safe : REAL
VAR_INPUT
    fX : REAL := 1.0;   // 对数自变量，域 > 0 [无量纲] / Logarithm argument, domain > 0
END_VAR
VAR_OUTPUT
    bValid : BOOL;      // 结果有效回执 [-] / Result validity receipt
END_VAR
VAR CONSTANT
    DL_L10_SAT : REAL := -3.402823E38;   // REAL 负向饱和哨兵值 [无量纲] / Negative saturation sentinel
    DL_L10_EPS : REAL := 1.0E-6;         // 判零容差 [无量纲] / Zero-test epsilon
END_VAR

(* —— 段 0：全路径赋值缺省（无效域安全侧） —— *)
bValid := FALSE;                            // 有效回执预清 / Validity preset
FC_DL_Log10Safe := DL_L10_SAT;              // 返回值缺省负饱和 / Result default negative saturation

(* —— 段 1：域闸与非有限闸（NaN 自反判 + 非正域拦截） —— *)
IF (fX <> fX) THEN                          // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive test
    RETURN;                                 // 无效返回饱和 / Invalid, return saturation
END_IF
IF fX <= DL_L10_EPS THEN                    // 非正域（含判零容差）拦截 / Non-positive domain intercepted
    RETURN;                                 // 无效返回饱和 / Invalid, return saturation
END_IF
IF fX >= 3.0E38 THEN                        // 近 Inf 幅值闸 / Near-Inf gate
    RETURN;                                 // 无效返回饱和 / Invalid, return saturation
END_IF

(* —— 段 2：正常换算（LN(fX)/LN(10)，LN(10) 为常量无除零） —— *)
FC_DL_Log10Safe := LN(fX) / 2.302585093;    // log10 = LN(fX)/LN(10) / Logarithm base ten via natural log
bValid := TRUE;                             // 有效回执 / Validity receipt

END_FUNCTION
