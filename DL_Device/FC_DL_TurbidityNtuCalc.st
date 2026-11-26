(* ============================================================
   DL_Device / FC_DL_TurbidityNtuCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：浊度比值法 ratio = (S − D) / (T − D)，NTU = K · ratio + Zero，
         末尾做负值保护与量程上限栅。
   边界：净透射 ≤ 1E-6（遮光/断线）或量程上限 ≤ 0 → 码 1、NTU 写 0（N1）；
         任一入参非有限 → 码 2、NTU 写 0；换算值为负 → 钳 0 报码 3；
         超量程上限 → 钳顶报码 4（饱和上报，值仍可读）。
         量纲清单（N5）：S/T/D 同一光路电压 [mV]，ratio 无量纲；K 单位 NTU/ratio；
         Zero 与上限同为 NTU；1 NTU = 1 FNU。
   依赖：仅 IEC 61131-3（无外部依赖，纯算术） ｜ 溯源：DLF-D-WATERANA
   验收：S=800/T=400/D=0/K=2.0/Zero=0.2/Max=1000 → ratio=2.0、NTU=4.2、码 0；
         T=0 → 码 1、NTU=0；结果超上限 → 钳顶、码 4。
   ============================================================ *)
FUNCTION FC_DL_TurbidityNtuCalc : BOOL
VAR_INPUT
    fScatterV  : REAL;  // 散射光路电压 [mV] / Scattered light channel voltage
    fTransmitV : REAL;  // 透射光路电压 [mV] / Transmitted light channel voltage
    fDarkV     : REAL;  // 暗电流（遮光）基准电压 [mV] / Dark current baseline voltage
    fKScale    : REAL;  // 标定系数，有效域 > 0 [NTU/ratio] / Calibration factor in NTU per ratio unit
    fZeroNtu   : REAL;  // 零点浊度偏置 [NTU] / Zero point turbidity offset
    fNtuMax    : REAL;  // 量程上限，有效域 > 0 [NTU] / Upper range limit of the measurement
END_VAR
VAR_OUTPUT
    fNtu   : REAL;   // 浊度换算值 [NTU] / Turbidity in nephelometric turbidity units
    uErrId : UDINT;  // 码 0 正常 / 1 遮光或组态非法 / 2 非有限 / 3 负值钳零 / 4 超量程钳顶 [-] / Outlet code
END_VAR
VAR
    _fS     : REAL;  // 净散射电压 [mV] / Net scattered light voltage
    _fT     : REAL;  // 净透射电压 [mV] / Net transmitted light voltage
    _fNtu   : REAL;  // 换算中间值 [NTU] / Intermediate turbidity value
END_VAR
VAR CONSTANT
    DL_TBN_EPS : REAL := 1.0E-6;  // 净透射判零下限 [mV] / Zero floor of the net transmitted voltage
END_VAR

(* 段 0：出口预置安全侧（0 NTU、码取最严，N1/N3） *)
FC_DL_TurbidityNtuCalc := FALSE;
fNtu := 0.0;  uErrId := 2;

(* 段 1：非有限闸（六个入参全量枚举；NaN 自反 + Inf 差值自减双判，R79/R272） *)
IF (fScatterV <> fScatterV) OR (fTransmitV <> fTransmitV) OR (fDarkV <> fDarkV)
   OR (fKScale <> fKScale) OR (fZeroNtu <> fZeroNtu) OR (fNtuMax <> fNtuMax) THEN RETURN; END_IF
(* Inf 双判须覆盖 fScatterV / fTransmitV / fDarkV：透射 +Inf 时净透射为 ±Inf，
   判零闸放行、比值算成 0，输出「NTU = Zero、码 0」的伪读数 *)
IF ((fScatterV - fScatterV) <> (fScatterV - fScatterV))
   OR ((fTransmitV - fTransmitV) <> (fTransmitV - fTransmitV))
   OR ((fDarkV - fDarkV) <> (fDarkV - fDarkV))
   OR ((fKScale - fKScale) <> (fKScale - fKScale))
   OR ((fZeroNtu - fZeroNtu) <> (fZeroNtu - fZeroNtu))
   OR ((fNtuMax - fNtuMax) <> (fNtuMax - fNtuMax)) THEN RETURN; END_IF

(* 段 2：域闸（净透射判零 + 系数与量程上限必须为正） *)
_fS := fScatterV - fDarkV;
_fT := fTransmitV - fDarkV;
IF (ABS(_fT) <= DL_TBN_EPS) OR (fKScale <= 0.0) OR (fNtuMax <= 0.0) THEN
    uErrId := 1;                        // 遮光/断线或组态非法：浊度不可解
    RETURN;
END_IF

(* 段 3：比值换算（除子已证 |T_net| > 1E-6） *)
_fNtu := fKScale * (_fS / _fT) + fZeroNtu;

(* 段 4：结果复检（非有限保持段 0 安全侧） *)
IF (_fNtu <> _fNtu) OR ((_fNtu - _fNtu) <> (_fNtu - _fNtu)) THEN RETURN; END_IF

(* 段 5：单一出口裁决（先钳后赋，判据与出口同源于 _fNtu，N4/R23） *)
IF _fNtu < 0.0 THEN
    fNtu := 0.0;  uErrId := 3;          // 负值保护：钳零后上报
ELSIF _fNtu > fNtuMax THEN
    fNtu := fNtuMax;  uErrId := 4;      // 饱和上报：钳顶后值仍可读
ELSE
    fNtu := _fNtu;  uErrId := 0;  FC_DL_TurbidityNtuCalc := TRUE;
END_IF
END_FUNCTION
