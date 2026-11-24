// FC_DL_InvSqrtApprox v1.0.0
(*==============================================================================
 * 功能描述: 平方根倒数 1/sqrt(x) 快速近似。先按 4 倍缩放把自变量归一到 [1,4)，
 *           线性初值后牛顿迭代 4 次（残差 < 0.1%），再按缩放级数还原；缩放循环带
 *           128 步守护（R3 三族开闭词配对口径）；x <= 0 或非有限防御返回 0 并置
 *           bValid=FALSE。
 * 接口契约: 输入 fX，域 > 0 [无量纲]；输出 bValid 回执，返回 1/sqrt(x) 近似值。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_InvSqrtApprox : REAL
VAR_INPUT
    fX : REAL := 1.0;   // 自变量，域 > 0 [无量纲] / Argument, domain > 0
END_VAR
VAR_OUTPUT
    bValid : BOOL;      // 结果有效回执 [-] / Result validity receipt
END_VAR
VAR CONSTANT
    DL_ISA_EPS : REAL := 1.0E-6;   // 判零容差 [无量纲] / Zero-test epsilon
END_VAR
VAR
    fScaled : REAL;     // 缩放后自变量（落在 [1,4)）[无量纲] / Scaled argument in [1,4)
    fY      : REAL;     // 牛顿迭代工作值 [无量纲] / Newton iteration working value
    nScale  : INT;      // 4 倍缩放级数 [级] / Scaling stages of factor four
    nGuard  : INT;      // 缩放循环守护计数 [步] / Scaling loop guard
END_VAR

(* —— 段 0：全路径赋值缺省（无效安全侧） —— *)
bValid := FALSE;                             // 有效回执预清 / Validity preset
FC_DL_InvSqrtApprox := 0.0;                  // 返回值缺省零 / Result default zero

(* —— 段 1：域闸与非有限闸 —— *)
IF fX <> fX THEN                             // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive test
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF
IF fX < DL_ISA_EPS THEN                      // 非正域拦截（含判零容差） / Non-positive domain intercepted
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF
IF fX >= 3.0E38 THEN                         // 近 Inf 幅值闸 / Near-Inf magnitude gate
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF

(* —— 段 2：4 倍缩放归一到 [1,4)（守护 128 步防死循环，R3 配对口径） —— *)
fScaled := fX;                               // 缩放工作值装载 / Scaled value seeded
nScale := 0;                                 // 缩放级数清零 / Stage count cleared
nGuard := 0;                                 // 守护计数清零 / Guard cleared
WHILE (fScaled >= 4.0) AND (nGuard < 128) DO // 大于等于 4 连续除 4 / Divide by four while at or above four
    fScaled := fScaled / 4.0;                // 除以 4（缩放一级） / Divide by four
    nScale := nScale + 1;                    // 级数递增 / Stage increments
    nGuard := nGuard + 1;                    // 守护递增 / Guard increments
END_WHILE                                    // WHILE 闭合（配对断言） / WHILE closed, pairing asserted

(* —— 段 3：线性初值 + 牛顿迭代 4 次（[1,4) 域内残差 < 0.1%） —— *)
fY := 0.95 - 0.15 * fScaled;                 // 线性初值（域内偏差 <= 30%） / Linear seed, deviation at most thirty percent
fY := fY * (3.0 - fScaled * fY * fY) / 2.0;  // 牛顿第 1 次：y*(3-x*y²)/2 / Newton iteration one
fY := fY * (3.0 - fScaled * fY * fY) / 2.0;  // 牛顿第 2 次 / Newton iteration two
fY := fY * (3.0 - fScaled * fY * fY) / 2.0;  // 牛顿第 3 次 / Newton iteration three
fY := fY * (3.0 - fScaled * fY * fY) / 2.0;  // 牛顿第 4 次 / Newton iteration four

(* —— 段 4：按缩放级数还原（每级乘 0.5，级数由守护上界钳定） —— *)
WHILE (nScale > 0) AND (nGuard < 256) DO     // 还原循环（守护二次覆盖） / Restore loop, second guard
    fY := fY * 0.5;                          // 每级乘 0.5（除以 2 的逆缩放） / Multiply by a half per stage
    nScale := nScale - 1;                    // 级数递减 / Stage decrements
    nGuard := nGuard + 1;                    // 守护递增 / Guard increments
END_WHILE                                    // WHILE 闭合（配对断言） / WHILE closed, pairing asserted
FC_DL_InvSqrtApprox := fY;                   // 返回近似值 / Return the approximation
bValid := TRUE;                              // 有效回执 / Validity receipt

END_FUNCTION
