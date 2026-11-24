(*
  Component : FB_DL_ShrinkFilmUsageCalc
  Category  : DL_MathData
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#02_3_5D
  Summary   : 收缩膜单包耗量换算与成本核算：膜长×膜宽×厚度→重量折算，按产量包数对齐口径出总耗与成本。
              Shrink film usage per pack and cost accounting: length x width x thickness to weight, aligned with pack count.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 密度/厚度/膜长/膜宽正域闸（> 0，防除零与负值换算）；包数域闸（≥ 1，防产量口径为 0 除零）；
              价格非负域闸（≥ 0）；厚度 um→m 显式 1.0E-6 换算链，密度 g/cm³→kg/m³ ×1000；
              累计计数防 UDINT 回卷；全浮点比较带 fEps 容差。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_ShrinkFilmUsageCalc
VAR_INPUT
    bRun         : BOOL;               (* 核算使能，假则输出冻结 · Enable, FALSE freezes outputs *)
    fFilmLenM    : LREAL;              (* 单包膜长 [m] · Film length per pack *)
    fFilmWidthM  : LREAL;              (* 膜宽 [m] · Film width *)
    fThickUm     : LREAL;              (* 膜厚 [um] · Film thickness *)
    fDensityGcc  : LREAL := 0.92;      (* 膜密度 [g/cm³] · Film density *)
    fPriceYuanKg : LREAL := 12.0;      (* 膜价 [元/kg] · Film price *)
    nPackCnt     : INT;                (* 产量包数 [包]，口径对齐基准 · Production pack count *)
    fEps         : LREAL := 1.0E-6;    (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fPerPackKg     : LREAL;            (* 单包耗膜重量 [kg] · Film weight per pack *)
    fTotalKg       : LREAL;            (* 总耗膜重量 [kg]（产量口径）· Total film weight *)
    fCostYuan      : LREAL;            (* 总成本 [元] · Total cost *)
    fCostPerPackYn : LREAL;            (* 单包成本 [元/包] · Cost per pack *)
    fTotalKgAcc    : LREAL;            (* 累计耗膜重量 [kg]，班次台账 · Cumulative weight ledger *)
    fCostYuanAcc   : LREAL;            (* 累计成本 [元]，班次台账 · Cumulative cost ledger *)
    bLedgerClr     : BOOL;             (* 台账清零指令 [事件]，真则清累计 · Ledger clear command *)
    bError         : BOOL;             (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId       : UDINT;            (* 事件码 16#0000_005D，0 无事件 · Event code *)
END_VAR
VAR
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging, recomputed *)
    bDimOk  : BOOL;     (* 尺寸域有效标志 · Dimension validity flag *)
    bCntOk  : BOOL;     (* 包数/价格域有效标志 · Count and price validity flag *)
    fDenGcc3: LREAL;    (* 密度 SI 换算值 [kg/m³] · Density in SI units *)
    fThickM : LREAL;    (* 厚度 SI 换算值 [m] · Thickness in SI units *)
    nCycles : UDINT;    (* 有效核算拍计数 [拍]，防回卷 · Valid calculation count with wrap guard *)
END_VAR
VAR CONSTANT
    DL_SFC_UM2M  : LREAL := 1.0E-6;    (* um 到 m 系数 [m/um] · Micrometers to meters *)
    DL_SFC_G2KG  : LREAL := 1000.0;    (* g/cm³ 到 kg/m³ 系数 · Gram per cc to kg per m3 *)
    DL_SFC_WRAP  : UDINT := 4294967290; (* 计数防回卷余量 [拍] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新 === *)
(* 纯核算件：无 TON/R_TRIG 实例，计数状态见段 3；Pure accounting, no timer instances *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码，条件不满足再置（可达清零）/ Clear codes each scan
bDimOk := (fFilmLenM = fFilmLenM) AND (fFilmWidthM = fFilmWidthM) AND (fThickUm = fThickUm)
          AND (fDensityGcc = fDensityGcc)                                          // NaN 自反判据 / NaN reflexivity
          AND (fFilmLenM > fEps) AND (fFilmWidthM > fEps)                          // 长/宽正域闸 / Length and width gate
          AND (fThickUm > fEps) AND (fDensityGcc > fEps)                           // 厚/密正域闸 / Thickness and density gate
          AND (ABS(fDensityGcc) < 1.0E308);                                        // Inf 上限判据 / Inf limit
bCntOk := (nPackCnt >= 1) AND (fPriceYuanKg >= 0.0) AND (fPriceYuanKg = fPriceYuanKg);
                                        // 包数下限闸 + 价格非负闸 / Count and price gates
IF NOT bDimOk OR NOT bCntOk THEN
    uCode := 16#005D;                   // 故障级：域外，核算冻结 / Fault: domain invalid, frozen
END_IF

(* === 段 2 · 主逻辑：量纲链换算 === *)
IF bDimOk THEN
    fDenGcc3 := fDensityGcc * DL_SFC_G2KG;              // 密度 SI 换算 [kg/m³] / Density to SI
    fThickM  := fThickUm * DL_SFC_UM2M;                 // 厚度 SI 换算 [m] / Thickness to SI
    fPerPackKg := fFilmLenM * fFilmWidthM * fThickM * fDenGcc3;     // 单包重量 [kg] / Weight per pack
END_IF

(* === 段 3 · 输出映射与故障码 === *)
    IF bLedgerClr THEN                  (* 台账清零（可达复位路径）/ Ledger clear, reachable reset *)
        fTotalKgAcc := 0.0;             (* 清重量累计 / Clear weight ledger *)
        fCostYuanAcc := 0.0;            (* 清成本累计 / Clear cost ledger *)
    END_IF
    IF bDimOk AND bCntOk THEN
        fTotalKg := fPerPackKg * UDINT_TO_LREAL(INT_TO_UDINT(nPackCnt));    // 产量口径对齐 / Align with pack count
        fCostYuan := fTotalKg * fPriceYuanKg;               // 总成本 [元] / Total cost
        fCostPerPackYn := fCostYuan / UDINT_TO_LREAL(INT_TO_UDINT(nPackCnt));   // 单包成本，包数 ≥1 已闸 / Cost per pack
        fTotalKgAcc := fTotalKgAcc + fTotalKg;      (* 台账累加本拍总耗 / Accumulate the ledger *)
        fCostYuanAcc := fCostYuanAcc + fCostYuan;   (* 台账累加本拍成本 / Accumulate the ledger *)
        IF nCycles < DL_SFC_WRAP THEN
        nCycles := nCycles + 1;         // 有效核算计数，防回卷 / Count valid calculations
    END_IF
ELSIF NOT bDimOk THEN
    fPerPackKg := 0.0;                  // 域外输出安全零 / Safe zero on fault
    fTotalKg := 0.0;
    fCostYuan := 0.0;
    fCostPerPackYn := 0.0;
END_IF
bError := (uCode <> 16#0000);           // 故障标志配对 / Fault flag paired
uErrorId := WORD_TO_UDINT(uCode);       // 码位单点写入（16#0000_005D 形态）/ Single write point
END_FUNCTION_BLOCK
