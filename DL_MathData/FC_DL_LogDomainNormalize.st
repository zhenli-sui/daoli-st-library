(*
  Name        : FC_DL_LogDomainNormalize
  Category    : DL_MathData
  Version     : 1.0.0
  Purpose     : 对数域归一化：pH/浓度/浊度等跨量级测量按 log 域映射到 0~1 线性度输出，含定义域与底数守卫；/ Normalize a wide-dynamic-range measurement into 0..1 via a log-domain mapping, with domain and base guards
  溯源        : 借 t1-1-oscat·math 的分类/参数域组织，clean-room 实现
  Boundary    : ① 定义域闸：fVal/fMin <= 0、fMax <= fMin、fBase <= 0 → 返回 0.0 哨兵（非故障级）；
                ② 底数闸：|LN(fBase)| < eps（即 fBase = 1）→ 对数退化除零 → 返回哨兵；
                ③ 跨度闸：|LN 域跨度| < eps → 返回哨兵（不产生 Inf）；
                ④ 非有限输入（NaN/Inf）拒收返回哨兵；⑤ xClamp 决定越界饱和或线性外推。
*)
FUNCTION FC_DL_LogDomainNormalize : LREAL
VAR_INPUT
    fVal     : LREAL := 1.0;                 (* 原始测量值（pH/浓度/浊度），域 > 0 [工程单位] / Raw measurement, must be > 0 *)
    fMin     : LREAL := 0.001;               (* 归一化下界（映射到 0.0），域 > 0 [工程单位] / Lower bound mapped to 0.0 *)
    fMax     : LREAL := 100.0;               (* 归一化上界（映射到 1.0），域 > fMin [工程单位] / Upper bound mapped to 1.0 *)
    fBase    : LREAL := 10.0;                (* 对数底，域 > 0 且 <> 1（典型 10 或 2.718）[-] / Log base, > 0 and not 1 *)
    xClamp   : BOOL := TRUE;                 (* TRUE = 输出饱和到 0..1；FALSE = 允许越界外推 [-] / Clamp output to 0..1 *)
END_VAR
VAR
    fLnBase : LREAL;                         (* LN(底数) 缓存 [-] / Cached LN of base *)
    fLnMin  : LREAL;                         (* 下界的底数域对数值 [-] / Log-domain value of lower bound *)
    fLnMax  : LREAL;                         (* 上界的底数域对数值 [-] / Log-domain value of upper bound *)
    fSpan   : LREAL;                         (* 对数域跨度 = fLnMax - fLnMin [-] / Log-domain span *)
    fNorm   : LREAL;                         (* 未钳位归一值 [-] / Unclamped normalized value *)
END_VAR
VAR CONSTANT
    DL_LDN_EPS : LREAL := 1.0E-6;            (* 定义域/底数/跨度判零容差（REAL 量级）[-] / Domain epsilon *)
    DL_LDN_ONE : LREAL := 1.0;               (* 归一上限常量 [-] / Normalized upper bound *)
    DL_LDN_ZERO : LREAL := 0.0;              (* 归一/哨兵零点常量 [-] / Zero constant *)
END_VAR

(* —— 段 1：全路径预置哨兵（未命中合法分支即输出 0.0，无旧值残留） —— *)
FC_DL_LogDomainNormalize := DL_LDN_ZERO;      (* 哨兵 0.0：还原方向不饱和，交由调用侧组态闸判有效性 / Sentinel 0.0, validity judged by caller *)

(* —— 段 2：非有限输入拒收（NaN 自反、Inf 差判，禁用近似阈值） —— *)
IF (fVal <> fVal) OR (fMin <> fMin) OR (fMax <> fMax) OR (fBase <> fBase) THEN
    RETURN;                                   (* NaN 拒收 / NaN rejected *)
END_IF
IF ((fVal - fVal) <> (fVal - fVal)) OR ((fMin - fMin) <> (fMin - fMin))
   OR ((fMax - fMax) <> (fMax - fMax)) OR ((fBase - fBase) <> (fBase - fBase)) THEN
    RETURN;                                   (* Inf 拒收（x-x 非零即非有限） / Inf rejected *)
END_IF

(* —— 段 3：定义域闸（每个参与换算的引脚单独覆盖，R151） —— *)
IF (fVal <= DL_LDN_ZERO) OR (fMin <= DL_LDN_ZERO) OR (fBase <= DL_LDN_ZERO) THEN
    RETURN;                                   (* 对数域要求正数输入 / Log domain requires positive inputs *)
END_IF
IF (fMax - fMin) <= DL_LDN_EPS THEN
    RETURN;                                   (* 上界须严格大于下界（差比较用容差，禁 = ） / Upper must exceed lower, tolerance compare *)
END_IF

(* —— 段 4：底数与跨度闸（除零唯一出入口） —— *)
fLnBase := LN(fBase);                         (* 自然对数缓存，仅算一次 / Natural log cached once *)
IF ABS(fLnBase) < DL_LDN_EPS THEN
    RETURN;                                   (* 底数 = 1：LOG 退化为除零 / Base 1 degenerates to division by zero *)
END_IF
fLnMin := LN(fMin) / fLnBase;                 (* 下界折算到底数域（除子已过闸） / Lower bound in base domain *)
fLnMax := LN(fMax) / fLnBase;                 (* 上界折算到底数域 / Upper bound in base domain *)
fSpan := fLnMax - fLnMin;                     (* 对数域跨度 / Log-domain span *)
IF ABS(fSpan) < DL_LDN_EPS THEN
    RETURN;                                   (* 跨度退化：不产生 Inf / Degenerate span, no Inf *)
END_IF

(* —— 段 5：归一换算 + 可选饱和（饱和前先算实值，非先钳后算） —— *)
fNorm := (LN(fVal) / fLnBase - fLnMin) / fSpan;   (* 线性内插：0 → fMin，1 → fMax / Linear interpolation in log domain *)
IF xClamp THEN
    IF fNorm < DL_LDN_ZERO THEN
        fNorm := DL_LDN_ZERO;                 (* 下限饱和 0.0 / Lower saturation *)
    ELSIF fNorm > DL_LDN_ONE THEN
        fNorm := DL_LDN_ONE;                  (* 上限饱和 1.0 / Upper saturation *)
    END_IF
END_IF
FC_DL_LogDomainNormalize := fNorm;            (* 返回归一值 / Return normalized value *)
END_FUNCTION
