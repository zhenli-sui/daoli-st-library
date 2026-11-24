(*
  FC_DL_HeatExchangerLmtd  —  换热器对数平均温差 + ε-NTU 效能 / Heat exchanger LMTD and effectiveness
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_84
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-technology — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，LMTD/ε-NTU 公开传热语义，未复制任何源码行
  功能 Function : 1) 按流向布置（逆流/并流/1-2 程）取端差 ΔT1/ΔT2，LMTD = (ΔT1−ΔT2)/LN(ΔT1/ΔT2)；
                  2) 1-2 程乘 F 修正系数（Kern 公式，R≈1 走极限分支）；
                  3) 效能 ε：NTU = U·A/(m·cp)，Cr 由端差能量平衡反推（Cr = MIN(r, 1/r)，r = ΔTh/ΔTc）；
                  4) 热侧换热量 fQkw = m·cp·(T_h,in − T_h,out) / 1000。
  边界 Boundary : ① ΔT1 与 ΔT2 符号相反 → bTempCross := TRUE 置故障码（温度交叉，物理不可能）；
                  ② 任一 ΔT <= 0 判无效置码；|ΔT1−ΔT2| < 1E-3 K 走退化分支改算术平均（禁 LN(1) 除零）；
                  ③ fMassFlowHotKgS <= 0 / fCpHotJkgK <= 0 / fAreaM2 <= 0 防除零判组态错；
                  ④ fUwPerM2K <= 0 时仅输出 fLmtdK，fEpsilon := 0 并置「UA 未组态」信息码（Q 亦不输出）；
                  ⑤ F 修正分支：P >= 1 或 P·R >= 1 判退化（端点温度重合），1-2 程不输出效能；
                  ⑥ 解除式自证：bTempCross/bDegenerate 每调用重算，条件消失即自动解除（无锁存）。
  依赖 Depends  : 仅 Standard.library（LN/EXP/SQRT/ABS/MIN/MAX）；枚举 E_DL_FlowArrangement 随本件发布
  码表 Error codes（本件格 02_3_84，子码步进 +0x100）:
    16#0002_0184 信息级：UA 未组态（U <= 0），仅输出 LMTD，效能/热量不输出
    16#0002_0284 故障级：温度交叉（ΔT1 与 ΔT2 符号相反）或任一端差 <= 0
    16#0002_0384 故障级：组态非法（m <= 0 / cp <= 0 / A <= 0）
    16#0002_0484 信息级：端差退化分支（|ΔT1−ΔT2| < 1E-3 K，改算术平均）
    16#0002_0584 故障级：1-2 程 F 修正域退化（P >= 1 或 P·R >= 1，端点重合）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_FlowArrangement :
(
    eCounter         := 0,   // 逆流 / Counter flow
    eParallel        := 1,   // 并流 / Parallel flow
    eOneShellTwoTube := 2    // 1-2 程（壳侧 1 程，管侧 2 程）/ One shell pass, two tube passes
);
END_TYPE

FUNCTION FC_DL_HeatExchangerLmtd : BOOL
VAR_INPUT
    fHotInC        : REAL;                        // 热侧进口温度 [°C] / Hot inlet temperature
    fHotOutC       : REAL;                        // 热侧出口温度 [°C] / Hot outlet temperature
    fColdInC       : REAL;                        // 冷侧进口温度 [°C] / Cold inlet temperature
    fColdOutC      : REAL;                        // 冷侧出口温度 [°C] / Cold outlet temperature
    eFlowType      : E_DL_FlowArrangement;        // 流向布置 / Flow arrangement
    fAreaM2        : REAL;                        // 换热面积 [m²]，域 > 0 / Heat transfer area
    fUwPerM2K      : REAL;                        // 总传热系数 U [W/(m²·K)]，<= 0 = 未组态 / Overall U coefficient
    fMassFlowHotKgS: REAL;                        // 热侧质量流量 [kg/s]，域 > 0 / Hot side mass flow
    fCpHotJkgK     : REAL;                        // 热侧比热 [J/(kg·K)]，域 > 0 / Hot side specific heat
END_VAR
VAR_OUTPUT
    fLmtdK         : REAL;                        // 对数平均温差 [K] / Log mean temperature difference
    fEpsilon       : REAL;                        // 效能 [无量纲 0..1] / Effectiveness
    fQkw           : REAL;                        // 热侧换热量 [kW] / Heat duty
    bTempCross     : BOOL;                        // 温度交叉标志 / Temperature cross flag
    bDegenerate    : BOOL;                        // 端差退化标志（改算术平均）/ Degenerate-end-difference flag
    nErrId         : UDINT;                       // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    rDt1, rDt2     : LREAL;                       // 两端差 [K] / Terminal differences
    rLmtd, rNum    : LREAL;                       // LMTD 与分子暂存 / LMTD and numerator scratch
    rCph, rRatio   : LREAL;                       // 热侧热容流率/端差比 / Hot capacity rate, delta ratio
    rNtu, rCr      : LREAL;                       // NTU 与热容比 / NTU and capacity ratio
    rR, rP, rX, rF : LREAL;                       // 1-2 程修正中间量 / One-shell-two-tube F correction scratch
    rLnArg         : LREAL;                       // 对数自变量暂存 / Logarithm argument scratch
END_VAR
VAR CONSTANT
    rDtEps   : LREAL := 1.0E-3;   // 端差退化阈值 [K] / End-difference degeneracy threshold
    rEpsMin  : LREAL := 1.0E-6;   // R≈1 判据阈值 / R near-unity threshold
    rZeroMin : LREAL := 1.0E-12; // 近零判据通用阈值 / Generic near-zero threshold
END_VAR

(* —— 段 1：输出缺省与组态闸（纯函数，每调用重算） —— *)
fLmtdK := 0.0;  fEpsilon := 0.0;  fQkw := 0.0;    // 输出缺省 0
bTempCross := FALSE;  bDegenerate := FALSE;       // 判据标志缺省
nErrId := 16#0000_0000;                           // 事件码缺省无事件
FC_DL_HeatExchangerLmtd := FALSE;                 // 返回值缺省失败

IF (LREAL(fMassFlowHotKgS) <= rZeroMin) OR (LREAL(fCpHotJkgK) <= rZeroMin)
   OR (LREAL(fAreaM2) <= rZeroMin) THEN
    nErrId := 16#0002_0384;                       // 故障级：组态非法（防除零）
    RETURN;
END_IF

(* —— 段 2：按布置取端差（ΔT 均取「热侧 − 冷侧」，符号即物理方向） —— *)
CASE eFlowType OF

E_DL_FlowArrangement.eCounter:
    rDt1 := LREAL(fHotInC)  - LREAL(fColdOutC);   // 逆流：进口端差 = 热 进 − 冷 出
    rDt2 := LREAL(fHotOutC) - LREAL(fColdInC);    // 逆流：出口端差 = 热 出 − 冷 进

E_DL_FlowArrangement.eParallel:
    rDt1 := LREAL(fHotInC)  - LREAL(fColdInC);    // 并流：进口端差 = 热 进 − 冷 进
    rDt2 := LREAL(fHotOutC) - LREAL(fColdOutC);   // 并流：出口端差 = 热 出 − 冷 出

E_DL_FlowArrangement.eOneShellTwoTube:
    rDt1 := LREAL(fHotInC)  - LREAL(fColdOutC);   // 1-2 程：按逆流端点取端差（F 修正承载差异）
    rDt2 := LREAL(fHotOutC) - LREAL(fColdInC);

ELSE
    nErrId := 16#0002_0384;                       // 未知布置并入组态错兜底
    RETURN;

END_CASE

(* —— 段 3：温度交叉与端差有效性判据 —— *)
IF (rDt1 > 0.0) <> (rDt2 > 0.0) THEN
    bTempCross := TRUE;                           // 端差符号相反：温度交叉（物理不可能）
END_IF
IF (rDt1 <= 0.0) OR (rDt2 <= 0.0) OR bTempCross THEN
    nErrId := 16#0002_0284;                       // 故障级：温度交叉或端差 <= 0
    RETURN;                                       // 不输出 LMTD
END_IF

(* —— 段 4：LMTD（退化分支改算术平均，禁 LN(1) 除零） —— *)
IF ABS(rDt1 - rDt2) < rDtEps THEN
    rLmtd := (rDt1 + rDt2) / 2.0;                 // 退化分支：算术平均（规格强制）
    bDegenerate := TRUE;                          // 退化标志
    nErrId := 16#0002_0484;                       // 信息级：端差退化分支
ELSE
    rNum := rDt1 - rDt2;                          // 分子（已闸 |·| >= 1E-3）
    rLmtd := rNum / LN(rDt1 / rDt2);              // 对数平均（分母 LN(ΔT1/ΔT2) 与分子同号，非零）
END_IF
fLmtdK := REAL(rLmtd);

(* —— 段 5：UA 未组态短路（仅输出 LMTD） —— *)
IF LREAL(fUwPerM2K) <= rZeroMin THEN
    nErrId := 16#0002_0184;                       // 信息级：UA 未组态
    FC_DL_HeatExchangerLmtd := TRUE;              // LMTD 已有效输出
    RETURN;                                       // fEpsilon/fQkw 维持 0
END_IF

(* —— 段 6：ε-NTU 效能（Cr 由端差能量平衡反推） —— *)
rCph := LREAL(fMassFlowHotKgS) * LREAL(fCpHotJkgK);               // 热侧热容流率 [W/K]
rNtu := LREAL(fUwPerM2K) * LREAL(fAreaM2) / rCph;                 // NTU = U·A/(m·cp)，分母已闸
rRatio := rDt1 / MAX(rDt2, rDtEps);                               // r = ΔTh/ΔTc（冷端差用作 ΔTc 已闸 > 0）
rCr := MIN(rRatio, 1.0 / rRatio);                                 // Cr = Cmin/Cmax ∈ [0,1]，防除零（rRatio > 0）
IF ABS(rCr - 1.0) < rEpsMin THEN
    fEpsilon := REAL(rNtu / (1.0 + rNtu));                        // Cr = 1 极限：ε = NTU/(1+NTU)
ELSIF eFlowType = E_DL_FlowArrangement.eParallel THEN
    fEpsilon := REAL((1.0 - EXP(-rNtu * (1.0 + rCr))) / (1.0 + rCr));  // 并流效能式
ELSE
    fEpsilon := REAL((1.0 - EXP(-rNtu * (1.0 - rCr)))
              / (1.0 - rCr * EXP(-rNtu * (1.0 - rCr))));          // 逆流/1-2 程效能式
END_IF

IF eFlowType = E_DL_FlowArrangement.eOneShellTwoTube THEN
    rR := rRatio;                                                 // R = ΔTh/ΔTc
    rP := 1.0 - rDt2 / MAX(LREAL(fHotInC) - LREAL(fColdInC), rDtEps);  // P = (Tco−Tci)/(Thi−Tci)
    IF (rP <= 0.0) OR (rP >= 1.0) OR (rP * rR >= 1.0) THEN
        nErrId := 16#0002_0584;                                   // 故障级：F 修正域退化（端点重合）
        RETURN;
    END_IF
    rX := SQRT(rR * rR + 1.0);                                    // X = sqrt(R²+1)
    IF ABS(rR - 1.0) < rEpsMin THEN
        rLnArg := (2.0 - rP * (2.0 - rX)) / (2.0 - rP * (2.0 + rX));  // R = 1 极限分支的对数自变量
        rF := (rX * rP / (1.0 - rP)) / LN(rLnArg);                // R = 1 极限：F = X·P/((1−P)·ln(·))
    ELSE
        rLnArg := (1.0 - rP) / (1.0 - rP * rR);                   // 通用分支第一对数自变量（已闸 > 0）
        rF := (rX / (rR - 1.0)) * LN(rLnArg)
            / LN((2.0 - rP * (rR + 1.0 - rX)) / (2.0 - rP * (rR + 1.0 + rX)));  // Kern 通用式
    END_IF
    fEpsilon := REAL(MIN(MAX(LREAL(fEpsilon) * rF, 0.0), 1.0));   // 效能乘 F 修正并钳 0..1
END_IF

(* —— 段 7：热侧换热量与出口 —— *)
fQkw := REAL(rCph * (LREAL(fHotInC) - LREAL(fHotOutC)) / 1000.0); // Q = m·cp·ΔTh [kW]
fEpsilon := REAL(MIN(MAX(LREAL(fEpsilon), 0.0), 1.0));            // 效能钳 0..1
FC_DL_HeatExchangerLmtd := TRUE;                                  // 计算有效

END_FUNCTION
