(*
  Component : FB_DL_SlurryViscosityComp
  Category  : DL_MathData
  Type      : FB
  Version   : 1.0.2
  CodeSeg   : 16#02_3_5C
  Summary   : 浆料粘度温度补偿换算：温-粘标定曲线查表线性插值，输出归一到参考温度的补偿后粘度。
              Slurry viscosity temperature compensation: lookup curve linear interpolation, output normalized to reference temperature.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 温度物理域闸（> -273.15 degC，非有限 NaN/Inf 拦截）；粘度正域闸（> 0，防负值换算）；
              曲线点数域闸（2..8，防数组越界访问）；插值端点钳制（域外温度取边界因子并置 xClamped）；
              插值分母（节点温差）先判容差再除，防除零；全浮点比较带 fEps 容差。
  复用      : 无
  修订历史  : v1.0.2（R34 返修）改动点：① bRun=FALSE 分支改为「冻结保持末次有效粘度 + 置 bDegraded := TRUE」，
              禁输出 0 或未定义值；② xClamped 与钳制判据同源赋值（每拍先清零，仅端点钳制时置 TRUE），
              名实相符且不再在无效态残留旧值。接口仅新增 bDegraded 一个输出引脚，其余引脚与顺序一字不动。
              v1.0.0 首版入库。
  降级语义  : bDegraded = TRUE 表示输出为末次有效值的冻结副本（非本拍换算结果），HMI 需标注数据陈旧。
*)

FUNCTION_BLOCK FB_DL_SlurryViscosityComp
VAR_INPUT
    bRun          : BOOL;              (* 换算使能，假则输出冻结 · Enable, FALSE freezes outputs *)
    fTempC        : LREAL;             (* 浆料实测温度 [degC] · Measured slurry temperature *)
    fViscMeasMpas : LREAL;             (* 实测粘度 [mPa·s] · Measured viscosity *)
    fTRefC        : LREAL := 25.0;     (* 参考温度 [degC]，补偿归一基准 · Reference temperature *)
    aCurveTc      : ARRAY[1..8] OF LREAL := [5.0, 15.0, 25.0, 35.0, 45.0, 55.0, 65.0, 75.0];
                                       (* 曲线温度节点 [degC]，升序标定 · Curve temperature nodes, ascending *)
    aCurveK       : ARRAY[1..8] OF LREAL := [1.60, 1.30, 1.00, 0.80, 0.65, 0.54, 0.46, 0.40];
                                       (* 各节点补偿因子 [比值] · Compensation factor per node *)
    nPts          : INT := 8;          (* 有效点数 [点]，域 2 到 8 · Valid point count *)
    fEps          : LREAL := 1.0E-6;   (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fViscCompMpas : LREAL;             (* 补偿后粘度 [mPa·s]，归一到参考温度 · Compensated viscosity at reference *)
    fFactorNow    : LREAL;             (* 当前温度补偿因子 [比值] · Factor at current temperature *)
    fFactorRef    : LREAL;             (* 参考温度补偿因子 [比值] · Factor at reference temperature *)
    xClamped      : BOOL;              (* 端点钳制标志 [开关] · Endpoint clamp flag *)
    bError        : BOOL;              (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId      : UDINT;             (* 事件码 16#0000_005C，0 无事件 · Event code *)
    bDegraded     : BOOL;              (* v1.0.2 新增：降级标志，TRUE = 输出为末次有效值冻结副本 · Degraded flag, TRUE = frozen last-good output *)
END_VAR
VAR
    uCode   : WORD;    (* 码位暂存，每拍重算 [码] · Code staging, recomputed per scan *)
    bSigOk  : BOOL;    (* 输入有效标志 · Input validity flag *)
    bTblOk  : BOOL;    (* 曲线点数域标志 · Table point-count validity *)
    bRefOk  : BOOL;    (* 参考温度插值有效标志 · Reference interpolation validity *)
    nSeg    : INT;     (* 命中段下标 [索引] · Hit segment index *)
    nI      : INT;     (* 查表循环下标 [索引] · Table loop index *)
    fDen    : LREAL;   (* 插值分母（节点温差）[degC] · Interpolation denominator *)
    nCycles : UDINT;   (* 有效换算拍计数 [拍]，防回卷 · Valid conversion count with wrap guard *)
END_VAR
VAR CONSTANT
    DL_SVC_ABS0 : LREAL := 273.15;     (* 绝对零度 [degC] · Absolute zero in celsius *)
    DL_SVC_WRAP : UDINT := 4294967290; (* 计数防回卷余量 [拍] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新 === *)
(* 纯换算件：无 TON/R_TRIG 实例，计数状态见段 3；Pure conversion, no timer instances *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码，条件不满足再置（可达清零）/ Clear codes each scan
bSigOk := (fTempC = fTempC) AND (fViscMeasMpas = fViscMeasMpas) AND (fTRefC = fTRefC)
          AND (ABS(fTempC) < 1.0E308) AND (ABS(fViscMeasMpas) < 1.0E308)     // NaN 自反 + Inf 上限
          AND (fTempC > (-DL_SVC_ABS0 + fEps))                               // 温度物理域闸 / Physical domain
          AND (fViscMeasMpas > fEps)                                         // 粘度正域闸 / Positive viscosity
          AND (fTRefC > (-DL_SVC_ABS0 + fEps));                              // 参考温度域闸 / Reference domain
bTblOk := (nPts >= 2) AND (nPts <= 8);  // 点数域闸，防数组越界 / Point-count gate
IF NOT bSigOk OR NOT bTblOk THEN
    uCode := 16#005C;                   // 故障级：域外或表无效，换算冻结 / Fault: domain or table invalid
END_IF

(* === 段 2 · 主逻辑：查表线性插值（禁止 IF-ELSE 阶梯硬编码）=== *)
xClamped := FALSE;                      // v1.0.2：每拍先清钳制标志，与钳制判据同源（防无效态残留旧 TRUE）
IF bSigOk AND bTblOk THEN
    IF fTempC <= aCurveTc[1] THEN
        fFactorNow := aCurveK[1];       // 低温端点钳制 / Clamp at the low end
        xClamped := TRUE;
    ELSIF fTempC >= aCurveTc[nPts] THEN
        fFactorNow := aCurveK[nPts];    // 高温端点钳制 / Clamp at the high end
        xClamped := TRUE;
    ELSE
        nSeg := nPts - 1;               // 段下标兜底最后一段 / Default to the last segment
        FOR nI := 1 TO (nPts - 1) DO
            IF fTempC <= aCurveTc[nI + 1] THEN
                nSeg := nI;             // 命中段锁定 / Lock the hit segment
                EXIT;
            END_IF
        END_FOR
        fDen := aCurveTc[nSeg + 1] - aCurveTc[nSeg];    // 分母导出 / Denominator
        IF fDen > fEps THEN             // 防除零闸 / Divide-by-zero gate
            fFactorNow := aCurveK[nSeg] + (aCurveK[nSeg + 1] - aCurveK[nSeg])
                          * (fTempC - aCurveTc[nSeg]) / fDen;   // 线性插值 / Linear interpolation
        ELSE
            fFactorNow := aCurveK[nSeg];    // 退化取左节点因子 / Degenerate to left node
        END_IF
    END_IF
    (* 参考温度因子：同一段插值，参考温度域闸已在段 1 保证 / Same interpolation at the reference *)
    IF fTRefC <= aCurveTc[1] THEN
        fFactorRef := aCurveK[1];       // 参考端点钳制 / Reference clamp low
        bRefOk := TRUE;
    ELSIF fTRefC >= aCurveTc[nPts] THEN
        fFactorRef := aCurveK[nPts];    // 参考端点钳制 / Reference clamp high
        bRefOk := TRUE;
    ELSE
        nSeg := nPts - 1;
        FOR nI := 1 TO (nPts - 1) DO
            IF fTRefC <= aCurveTc[nI + 1] THEN
                nSeg := nI;
                EXIT;
            END_IF
        END_FOR
        fDen := aCurveTc[nSeg + 1] - aCurveTc[nSeg];
        IF fDen > fEps THEN
            fFactorRef := aCurveK[nSeg] + (aCurveK[nSeg + 1] - aCurveK[nSeg])
                          * (fTRefC - aCurveTc[nSeg]) / fDen;
        ELSE
            fFactorRef := aCurveK[nSeg];
        END_IF
        bRefOk := TRUE;                 // 参考插值完成 / Reference interpolation done
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
bDegraded := FALSE;                     // v1.0.2：降级标志每拍重算，条件满足再置
IF bRun THEN
    IF bSigOk AND bTblOk THEN
        IF fFactorRef > fEps THEN           // 归一分母防除零 / Normalize denominator gate
            fViscCompMpas := fViscMeasMpas * fFactorNow / fFactorRef;   // 归一补偿粘度 / Compensated viscosity
        END_IF
        IF nCycles < DL_SVC_WRAP THEN
            nCycles := nCycles + 1;         // 有效换算计数，防回卷 / Count valid conversions
        END_IF
    ELSE
        bDegraded := TRUE;                  // 输入域外：输出冻结为末次有效值并标降级
        xClamped := FALSE;                  // 无效态不主张钳制（与钳制判据同源）
    END_IF
ELSE
    bDegraded := TRUE;                      // v1.0.2：bRun=FALSE 冻结保持末次有效粘度，禁输出 0
    xClamped := FALSE;                      // v1.0.2：停算态钳制标志清零，名实相符
END_IF
bError := (uCode <> 16#0000);           // 故障标志配对 / Fault flag paired
uErrorId := WORD_TO_UDINT(uCode);       // 码位单点写入（16#0000_005C 形态）/ Single write point
END_FUNCTION_BLOCK
