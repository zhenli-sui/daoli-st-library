(*
  ==================================================================
  组件名 Component  : FC_DL_QuadraticSolve
  分类   Category   : DL_MathData
  复杂度 Complexity  : 轻
  版本   Version    : 1.0.0
  功能   Purpose    : 二次方程 a·x² + b·x + c = 0 实根求解。判别式三域分档：
                      D > eps 两实根（x1 ≥ x2）、|D| ≤ eps 重根、D < -eps 无
                      实根（nRoots = 0，非故障）；a ≈ 0 退化线性分支（b ≈ 0
                      再分恒成立/无解）；全程浮点禁等号，用 ABS 阈值。
                      OSCAT Basic 数值域公开语义 clean-room。
  来源   Source     : T1-1-oscat-basic（数值域公开语义）
  溯源   Origin     : 二次方程求根公式为公开数学语义，clean-room 自研实现，
                      未复制 OSCAT 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_SimpsonQuad 分工——后者做数值积分，本件做
                      二次方程解析求根。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限入参闸（自反双判据，三参数全覆盖）：命中置
                         bError 早退，输出安全侧零（四段式 R45）；
                      二 除零闸：线性分支除 b、求根除 2a 前强制 |系数| ≥ eps
                         判据（已由分支条件保证，代码内再显式闸一层）；
                      三 SQRT 域闸：仅 D ≥ 0 才开方（判据前置）；
                      四 nRoots = -1 表示 a = b = 0 且 c = 0 恒成立（全 x 均
                         为解），nRoots = 0 无实根，均为信息级非故障；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 1 · 序号 5）
  ==================================================================
*)

FUNCTION FC_DL_QuadraticSolve : BOOL
VAR_INPUT
    fA : LREAL := 0.0; // 二次项系数 [无量纲] / the quadratic coefficient
    fB : LREAL := 0.0; // 一次项系数 [无量纲] / the linear coefficient
    fC : LREAL := 0.0; // 常数项 [无量纲] / the constant term
END_VAR
VAR_OUTPUT
    fX1    : LREAL := 0.0; // 实根一（两根时较大者）[无量纲] / the real root one, the larger when two roots
    fX2    : LREAL := 0.0; // 实根二 [无量纲] / the real root two
    nRoots : DINT  := 0;   // 实根个数：0 无 / 1 重根或线性 / 2 两根 / -1 恒成立 [个] / the real root count, minus one means identity
    bLinear: BOOL := FALSE; // a ≈ 0 退化线性分支受理 [-] / the degenerate linear branch accepted
    bValid : BOOL := FALSE; // 结果可用标志 [-] / the result usable flag
    bError : BOOL := FALSE; // 故障标志（非有限入参）[-] / the fault flag, a non finite input
END_VAR
VAR CONSTANT
    DL_QUA_EPS : LREAL := 1.0E-12; // 系数与判别式零阈值 [无量纲] / the coefficient and discriminant zero threshold
END_VAR
VAR
    lrD  : LREAL; // 判别式工作量 [无量纲] / the discriminant work value
    lrS  : LREAL; // 判别式平方根工作量 [无量纲] / the discriminant square root work value
    lrT  : LREAL; // 两倍二次项工作量 [无量纲] / the twice a work value
END_VAR

// 段 1｜返回值与输出预置安全值（四段式第一段，R45）/ segment 1, preset the return and the outputs
FC_DL_QuadraticSolve := FALSE; // 受理标志预置假 / preset the accepted flag false
fX1 := 0.0; // 根一预置零 / preset the root one zero
fX2 := 0.0; // 根二预置零 / preset the root two zero
nRoots := 0; // 根数预置零 / preset the count zero
bLinear := FALSE; // 线性标志预置假 / preset the linear flag false
bValid := FALSE; // 有效预置假 / preset the valid false
bError := FALSE; // 故障预置假 / preset the fault false

// 段 2｜非有限入参闸（三参数自反双判据全覆盖，R79）/ segment 2, the non finite gate
IF (fA <> fA) OR ((fA - fA) <> (fA - fA)) THEN // 二次项非有限 / a non finite a
    bError := TRUE; // 置故障 / raise the fault
END_IF
IF (fB <> fB) OR ((fB - fB) <> (fB - fB)) THEN // 一次项非有限 / a non finite b
    bError := TRUE; // 置故障 / raise the fault
END_IF
IF (fC <> fC) OR ((fC - fC) <> (fC - fC)) THEN // 常数项非有限 / a non finite c
    bError := TRUE; // 置故障 / raise the fault
END_IF
IF bError THEN // 非有限命中早退 / a non finite hit, return early
    RETURN; // 早退 / return early
END_IF

// 段 3｜a ≈ 0 退化线性分支（ABS 阈值禁等号，除零前置闸）/ segment 3, the degenerate linear branch
IF ABS(fA) < DL_QUA_EPS THEN // 二次项近似零 / the a near zero
    bLinear := TRUE; // 线性分支受理 / accept the linear branch
    IF ABS(fB) < DL_QUA_EPS THEN // 一次项也近似零 / the b near zero too
        IF ABS(fC) < DL_QUA_EPS THEN // 常数项也近似零：恒成立 / the c near zero too, an identity
            nRoots := -1; // 全 x 均为解（信息级）/ every x is a root, informational
        ELSE // 常数项非零：无解 / a nonzero c, no solution
            nRoots := 0; // 无实根（信息级非故障）/ no real root, informational
        END_IF
    ELSE // 正常线性 bx + c = 0 / the normal linear form
        nRoots := 1; // 单实根 / one real root
        fX1 := -fC / fB; // 求根（|fB| ≥ eps 已由分支保证，除零闸）/ the root, divided by the gated b
    END_IF
    bValid := TRUE; // 结果可用 / the result usable
    FC_DL_QuadraticSolve := TRUE; // 受理 / accept
    RETURN; // 早退（线性分支完结）/ return early
END_IF

// 段 4｜判别式三域分档（D ≥ 0 才开方，除 2a 前显式闸，边界二三）/ segment 4, the discriminant three domains
lrD := (fB * fB) - (4.0 * fA * fC); // 判别式 / the discriminant
IF lrD > DL_QUA_EPS THEN // 两实根域 / the two roots domain
    lrS := SQRT(lrD); // 开方（D > eps 已闸）/ the square root, gated
    lrT := 2.0 * fA; // 两倍二次项 / the twice a
    IF ABS(lrT) < DL_QUA_EPS THEN // 除零兜底闸（与段 3 判据互斥，防御纵深）/ the divide by zero fallback gate
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
    fX1 := (-fB + lrS) / lrT; // 根一（公式分子取加号）/ the root one
    fX2 := (-fB - lrS) / lrT; // 根二 / the root two
    IF fX1 < fX2 THEN // 排序保证 x1 ≥ x2 / sort to keep x1 the larger
        fX1 := fX2; // 大根归 x1 / the larger to x1
        fX2 := (-fB + lrS) / lrT; // 小根归 x2 / the smaller to x2
    END_IF
    nRoots := 2; // 两实根 / two real roots
ELSIF lrD < -DL_QUA_EPS THEN // 无实根域（信息级非故障）/ the no real root domain
    nRoots := 0; // 无实根 / no real root
ELSE // 重根域 |D| ≤ eps / the double root domain
    lrT := 2.0 * fA; // 两倍二次项 / the twice a
    IF ABS(lrT) < DL_QUA_EPS THEN // 除零兜底闸 / the divide by zero fallback gate
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
    fX1 := -fB / lrT; // 重根 x1 = x2 / the double root
    fX2 := fX1; // 重根同值 / the same value
    nRoots := 1; // 单重根 / one double root
END_IF
bValid := TRUE; // 结果可用 / the result usable
FC_DL_QuadraticSolve := TRUE; // 受理 / accept
END_FUNCTION
