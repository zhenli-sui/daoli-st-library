(*
  ==================================================================
  组件名 Component  : FC_DL_RtdLinearization
  分类   Category   : DL_MathData
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : Pt100 / Pt1000 阻值到温度的 Callendar-Van Dusen（CVD）反解。
                      T >= 0 段用二次方程求根公式；T < 0 段（含 C(T-100)T³ 项）
                      用定点迭代收敛反解。三线制引线电阻补偿先行扣除；R 越出
                      [R(-200C), R(850C)] 置 bOutOfRange（出口取安全侧零），非有限
                      或 R_eff <= 0 置 bInvalid。
  来源   Source     : ROADMAP R56 池 / T2 自研（IEC 60751 公开系数）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；CVD 方程与 A / B / C
                      系数为 IEC 60751 公开标准值，clean-room 自研实现，未复制任何
                      闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL / SQRT，无私有库、无幂运算符）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做 RTD 阻值反解温度，不做单位换算、不做查表（属主边界）；
                      二 CVD 系数取 IEC 60751 标准值：R0(Pt100)=100 / R0(Pt1000)=1000，
                         A=3.9083E-3，B=-5.775E-7，C=-4.183E-12；
                      三 测温域 [-200, 850] 摄氏度，对应 Pt100 阻值域 [18.52, 390.48] 欧，
                         Pt1000 为其十倍；
                      四 负温段定点迭代收缩因子上界约 0.07（B·2T/A 在 T=-200 处），
                         60 次迭代含 1.0E-9 收敛阈足够；不收敛置 bInvalid；
                      五 无全局变量、无外部变量声明、无物理地址寻址、无定时器（纯函数）。
  输出契约 Output contract:
                      fTempC 仅在 bInvalid = FALSE 且 bOutOfRange = FALSE 时有效；
                      标志优先级 bInvalid > bOutOfRange；本件为纯函数，无跨扫描周期状态驻留。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 1 · 序号 4）
  ==================================================================
*)

TYPE E_DL_RtdType :
(
    ePt100  := 0, // Pt100 铂电阻，R0 = 100 欧 / Pt100 RTD with R0 of one hundred ohm
    ePt1000 := 1  // Pt1000 铂电阻，R0 = 1000 欧 / Pt1000 RTD with R0 of one thousand ohm
);
END_TYPE

FUNCTION FC_DL_RtdLinearization : BOOL
VAR_INPUT
    fROhm    : LREAL;        // RTD 实测阻值（含引线电阻）[欧] / measured RTD resistance including the leads [ohm]
    eType    : E_DL_RtdType; // RTD 类型选择 [枚举] / RTD type selector [enum]
    fLeadOhm : LREAL;        // 三线制引线电阻补偿量（从实测中扣除）[欧] / three wire lead resistance to be subtracted [ohm]
END_VAR
VAR_OUTPUT
    fTempC     : LREAL;      // 反解温度 [摄氏度] / solved temperature [degree celsius]
    bOutOfRange: BOOL;       // 阻值越出测温域 [-] / the resistance is outside the measuring domain
    bInvalid   : BOOL;       // 输入非有限或阻值无效 [-] / input non finite or the resistance void
END_VAR
VAR
    _bFin   : BOOL := FALSE;    // 两个实数输入全部有限 [-] / both real inputs are finite
    _fR0    : LREAL := 100.0;   // 标称零度阻值 [欧] / nominal resistance at zero degree [ohm]
    _fA     : LREAL := 3.9083E-3;   // CVD 一次系数 [每摄氏度] / CVD coefficient A [per degree celsius]
    _fB     : LREAL := -5.775E-7;   // CVD 二次系数 [每平方摄氏度] / CVD coefficient B [per square degree celsius]
    _fC     : LREAL := -4.183E-12;  // CVD 负温系数 [每四次摄氏度] / CVD coefficient C for the negative range [per fourth degree celsius]
    _fRMin  : LREAL := 18.52;   // 测温域下限阻值（-200 摄氏度）[欧] / domain floor resistance at minus two hundred [ohm]
    _fRMax  : LREAL := 390.48;  // 测温域上限阻值（850 摄氏度）[欧] / domain ceiling resistance at eight fifty [ohm]
    _fRUse  : LREAL := 0.0;     // 扣除引线后的有效阻值 [欧] / effective resistance after the lead subtraction [ohm]
    _fRel   : LREAL := 0.0;     // 相对阻值 R/R0 [无量纲] / relative resistance over R0
    _fDisc  : LREAL := 0.0;     // 二次方程判别式 [无量纲] / quadratic discriminant
    _fTPos  : LREAL := 0.0;     // 正温段求根结果 [摄氏度] / the positive branch root [degree celsius]
    _fTIt   : LREAL := 0.0;     // 负温段迭代值 [摄氏度] / the negative branch iterate [degree celsius]
    _fTNext : LREAL := 0.0;     // 负温段下个迭代值 [摄氏度] / the next negative branch iterate [degree celsius]
    _fDlt   : LREAL := 0.0;     // 迭代步差 [摄氏度] / the iterate step difference [degree celsius]
    _nI     : INT := 0;         // 迭代守护游标 [次] / iteration guard cursor [count]
    _bConv  : BOOL := FALSE;    // 迭代收敛标志 [-] / iteration convergence flag
END_VAR

// 段 1｜非有限闸（R151）与类型分派 / segment 1, finiteness gate and the type dispatch
_bFin := (fROhm = fROhm) AND ((fROhm - fROhm) = (fROhm - fROhm)) AND (fLeadOhm = fLeadOhm) AND ((fLeadOhm - fLeadOhm) = (fLeadOhm - fLeadOhm)); // 两实数输入有限性 / finiteness of both real inputs
bInvalid := NOT _bFin; // 非有限即无效 / non finite means invalid
bOutOfRange := FALSE; // 越域标志预置假 / preset the out of range flag to false
fTempC := 0.0; // 出口预置安全侧零（R127）/ preset the outlet to the safe side zero
CASE eType OF // 类型分派，常量在 CASE 内按型落定 / the type dispatch, the constants settle per type
E_DL_RtdType.ePt100: // Pt100 / the Pt100 type
    _fR0 := 100.0;   // 零度阻值 [欧] / the zero degree resistance [ohm]
    _fRMin := 18.52; // -200 摄氏度阻值下限 [欧] / the floor at minus two hundred [ohm]
    _fRMax := 390.48; // 850 摄氏度阻值上限 [欧] / the ceiling at eight fifty [ohm]
E_DL_RtdType.ePt1000: // Pt1000 / the Pt1000 type
    _fR0 := 1000.0;   // 零度阻值 [欧] / the zero degree resistance [ohm]
    _fRMin := 185.2;  // -200 摄氏度阻值下限 [欧] / the floor at minus two hundred [ohm]
    _fRMax := 3904.8; // 850 摄氏度阻值上限 [欧] / the ceiling at eight fifty [ohm]
ELSE // 非法类型枚举兜底（R128）/ the illegal type fallback
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
END_CASE
IF bInvalid THEN // 非有限或非法类型 / non finite or an illegal type
    FC_DL_RtdLinearization := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF

// 段 2｜引线补偿与阻值域闸 / segment 2, lead compensation and the resistance domain gate
_fRUse := fROhm - fLeadOhm; // 扣除引线电阻 / subtract the lead resistance
IF (_fRUse < _fRMin) OR (_fRUse > _fRMax) THEN // 阻值越出测温域 / the resistance is outside the domain
    bOutOfRange := TRUE; // 置越域标志 / raise the out of range flag
    fTempC := 0.0; // 出口取安全侧零（R127）/ the outlet takes the safe side zero
    FC_DL_RtdLinearization := TRUE; // 函数返回成功（越域但可观测）/ the function returns success
    RETURN; // 早退 / early return
END_IF
IF _fRUse <= 0.0 THEN // 有效阻值非正（被引线补偿过度扣除，防御性保留）/ the effective resistance is void, kept as a defence
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    FC_DL_RtdLinearization := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF
_fRel := _fRUse / _fR0; // 相对阻值，除子为标称阻值常量已证非零 / the relative resistance, the divisor is the proven constant

// 段 3｜正温段二次方程求根 / segment 3, the positive branch quadratic root
_fDisc := _fA * _fA - 4.0 * _fB * (1.0 - _fRel); // 判别式 A^2 - 4B(1-r) / the discriminant
IF _fDisc < 0.0 THEN // 判别式为负，方程无实根 / a negative discriminant has no real root
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    FC_DL_RtdLinearization := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF
_fTPos := (-_fA + SQRT(_fDisc)) / (2.0 * _fB); // 求根公式取正根支，除子 2B 为负常量已证非零 / the root, the divisor is the proven negative constant
IF _fTPos >= 0.0 THEN // 正温段命中 / the positive branch hit
    fTempC := _fTPos; // 出口取正温根 / the outlet takes the positive root
    FC_DL_RtdLinearization := TRUE; // 函数返回成功 / the function returns success
    RETURN; // 早退 / early return
END_IF

// 段 4｜负温段定点迭代：T = (r - 1 - B·T^2 - C·(T-100)·T^3) / A（幂次显式乘法展开）/ segment 4, the negative branch fixed point iteration with explicit multiplications
_fTIt := -100.0; // 迭代初值取域中点 / the iterate starts at the domain mid point
_bConv := FALSE; // 收敛标志预置假 / preset the convergence flag to false
_nI := 0; // 守护游标清零 / clear the guard cursor
WHILE (_nI < 60) AND (NOT _bConv) DO // 双重守护：次数上限与收敛判据 / the dual guard on the count and the convergence
    _nI := _nI + 1; // 守护游标递增 / increment the guard
    _fTNext := (_fRel - 1.0 - _fB * _fTIt * _fTIt - _fC * (_fTIt - 100.0) * _fTIt * _fTIt * _fTIt) / _fA; // 定点迭代式，除子 A 为正常量已证非零 / the iteration step, the divisor is the proven positive constant
    _fDlt := ABS(_fTNext - _fTIt); // 步差 / the step difference
    _fTIt := _fTNext; // 推进迭代值 / advance the iterate
    IF _fDlt < 1.0E-9 THEN // 收敛达标 / the convergence is reached
        _bConv := TRUE; // 置收敛标志 / raise the convergence flag
    END_IF
END_WHILE
IF (NOT _bConv) OR (_fTIt < -200.0) OR (_fTIt >= 0.0) THEN // 不收敛或迭代跑出负温域 / no convergence or the iterate left the negative domain
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    FC_DL_RtdLinearization := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF
fTempC := _fTIt; // 出口取负温收敛值 / the outlet takes the converged negative value
FC_DL_RtdLinearization := TRUE; // 函数返回成功 / the function returns success
END_FUNCTION
