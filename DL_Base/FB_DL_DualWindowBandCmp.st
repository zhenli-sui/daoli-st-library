// FB_DL_DualWindowBandCmp v1.0.0
// 开源溯源：brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴 WINDOW2 双窗三态语义，clean-room 重写
(*
  道莅工业代码库 | DL_Base | FB_DL_DualWindowBandCmp
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 双独立窗口三态比较器（下窗/带内/上窗），窗口 A/B 各自独立判定，
        并输出双窗一致性（同带）判据
  邻件关系: 与 FC_DL_ToleranceWindow（单容差窗布尔判定）相邻 —— 差异点：
            容差窗为单窗带内/带外两态布尔，本件为双窗各三态枚举 + 同带
            一致性输出，语义扩展非同义替换
*)
TYPE E_DL_WindowBand3 :
(
    eBelow  := 0,    // 低于窗下限 / Below window low limit
    eInBand := 10,   // 带内 / Within band
    eAbove  := 20    // 高于窗上限 / Above window high limit
);
END_TYPE

FUNCTION_BLOCK FB_DL_DualWindowBandCmp
VAR_INPUT
    fValA    : REAL := 0.0;                      // 窗 A 判定值 [工程单位] / Window A value
    fLowA    : REAL := 0.0;                      // 窗 A 下限 [工程单位] / Window A low limit
    fHighA   : REAL := 100.0;                    // 窗 A 上限 [工程单位] / Window A high limit
    fValB    : REAL := 0.0;                      // 窗 B 判定值 [工程单位] / Window B value
    fLowB    : REAL := 0.0;                      // 窗 B 下限 [工程单位] / Window B low limit
    fHighB   : REAL := 100.0;                    // 窗 B 上限 [工程单位] / Window B high limit
    fEps     : REAL := 1.0E-6;                   // 浮点判等容差 [工程单位] / Float equality tolerance
END_VAR
VAR_OUTPUT
    eBandA     : E_DL_WindowBand3;               // 窗 A 三态判定 / Window A three-state band
    eBandB     : E_DL_WindowBand3;               // 窗 B 三态判定 / Window B three-state band
    bBothIn    : BOOL;                           // 双窗同时带内 [-] / Both windows in band
    bSameBand  : BOOL;                           // 双窗同带（枚举相等）[-] / Same band on both windows
    bValid     : BOOL;                           // 组态有效回执 [-] / Configuration validity receipt
    bError     : BOOL;                           // 故障标志（组态非法）/ Fault flag (invalid configuration)
    uErrorId   : UDINT;                          // 事件码，0 = 无事件；16#0002_1C01 = 窗限组态非法 / Event code
END_VAR

// —— 段 0：全路径缺省 —— //
eBandA := E_DL_WindowBand3.eInBand;              // 三态缺省带内（安全中性值）/ Default neutral in-band
eBandB := E_DL_WindowBand3.eInBand;              // 窗 B 缺省 / Window B default
bBothIn := FALSE;                                // 一致性预清 / Agreement preset
bSameBand := FALSE;                              // 同带预清 / Same-band preset
bValid := FALSE;                                 // 有效回执预清 / Validity preset
bError := FALSE;                                 // 故障预清（组态非法路径置位）/ Fault preset
uErrorId := 16#0000;                             // 事件码预清 / Event code preset

// —— 段 1：组态闸（窗限单调 + 非有限 + 容差非负） —— //
IF (fLowA > fHighA + fEps) OR (fLowB > fHighB + fEps) THEN   // 窗限倒置（容差判等）/ Window limits inverted
    bError := TRUE;                              // 故障级：组态非法 / Fault level: invalid config
    uErrorId := 16#0002_1C01;                    // 故障码（1Cxx 步进）/ Fault code
    RETURN;                                      // 非法组态不判定 / No judgment on invalid config
END_IF
IF (fValA <> fValA) OR (fValB <> fValB) OR (fLowA <> fLowA) OR (fHighA <> fHighA)
   OR (fLowB <> fLowB) OR (fHighB <> fHighB) THEN
    bError := TRUE;                              // 任一输入 NaN / Any input NaN
    uErrorId := 16#0002_1C01;                    // 同组态故障码 / Same fault code family
    RETURN;
END_IF
bValid := TRUE;                                  // 组态与输入均有效 / Config and inputs valid

// —— 段 2：窗 A 三态判定（带界按闭区间，容差判等） —— //
IF fValA < fLowA - fEps THEN                     // 低于下限（容差外）/ Below low with tolerance
    eBandA := E_DL_WindowBand3.eBelow;
ELSIF fValA > fHighA + fEps THEN                 // 高于上限（容差外）/ Above high with tolerance
    eBandA := E_DL_WindowBand3.eAbove;
ELSE                                             // 带内（含边界容差带）/ Within band incl. boundary
    eBandA := E_DL_WindowBand3.eInBand;
END_IF

// —— 段 3：窗 B 三态判定（同口径） —— //
IF fValB < fLowB - fEps THEN                     // 窗 B 低于下限 / Window B below low
    eBandB := E_DL_WindowBand3.eBelow;
ELSIF fValB > fHighB + fEps THEN                 // 窗 B 高于上限 / Window B above high
    eBandB := E_DL_WindowBand3.eAbove;
ELSE                                             // 窗 B 带内 / Window B in band
    eBandB := E_DL_WindowBand3.eInBand;
END_IF

// —— 段 4：一致性输出（双窗同带 + 双带内） —— //
bBothIn := (eBandA = E_DL_WindowBand3.eInBand) AND (eBandB = E_DL_WindowBand3.eInBand);   // 双带内 / Both in band
bSameBand := (eBandA = eBandB);                  // 枚举相等判同带（浮点禁等令不适用于枚举）/ Same band by enum equality
END_FUNCTION_BLOCK
