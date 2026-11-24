(*
  ==================================================================
  组件名 Component  : FC_DL_ConductivityTempComp
  分类   Category   : DL_MathData
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 电导率温度补偿（参考温归一）。κ_ref = κ_T / (1 +
                      α(T − T_ref))，α 为温度系数 [%每摄氏度]，域 [0,5]；
                      测温域 [0,60] 摄氏度，越域钳位并置 bOutOfRange（信息级
                      超域标志）；补偿分母下限闸防除零与负分母。OSCAT
                      Building 水质域公开语义 clean-room。
  来源   Source     : T1-2-oscat-building（水质域公开语义）
  溯源   Origin     : 线性温度补偿公式为公开水质工程语义，clean-room 自研
                      实现，未复制 OSCAT 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_PhCompensation 分工——后者做 pH 温度补偿，
                      本件做电导率参考温归一。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限入参闸（自反双判据，三参数全覆盖）：命中置
                         bError，输出安全侧零（四段式 R45）；
                      二 测温域 [0,60] 与系数域 [0,5] 越域钳位并置
                         bOutOfRange / bClamped（信息级，单点回夹）；
                      三 除零与负分母闸：分母 < 0.1 置 bError（防 1+αΔT
                         趋零或变负，含负绝对温差场景）；
                      四 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 4 · 序号 17）
  ==================================================================
*)

FUNCTION FC_DL_ConductivityTempComp : BOOL
VAR_INPUT
    fCondRaw  : LREAL := 0.0; // 电导率实测值 [微西门子每厘米] / the measured conductivity [microsiemens per centimeter]
    fTempC    : LREAL := 25.0; // 水样温度 [摄氏度]，域 [0,60] / the sample temperature [degree celsius]
    fAlphaPct : LREAL := 2.0;  // 温度系数 [%每摄氏度]，域 [0,5] / the temperature coefficient [percent per degree celsius]
    fRefTempC : LREAL := 25.0; // 参考温度 [摄氏度] / the reference temperature [degree celsius]
END_VAR
VAR_OUTPUT
    fCondRef    : LREAL := 0.0; // 参考温归一电导率 [微西门子每厘米] / the normalized conductivity [microsiemens per centimeter]
    bValid      : BOOL := FALSE; // 结果可用标志 [-] / the result usable flag
    bOutOfRange : BOOL := FALSE; // 测温越域标志（信息级）[-] / the temperature out of range flag, informational
    bClamped    : BOOL := FALSE; // 系数越域钳位（信息级）[-] / the coefficient clamp, informational
    bError      : BOOL := FALSE; // 故障标志（非有限或分母退化）[-] / the fault flag
END_VAR
VAR CONSTANT
    DL_CTC_TMIN  : LREAL := 0.0;  // 测温域下界 [摄氏度] / the temperature floor
    DL_CTC_TMAX  : LREAL := 60.0; // 测温域上界 [摄氏度] / the temperature ceiling
    DL_CTC_AMIN  : LREAL := 0.0;  // 系数域下界 [%每摄氏度] / the coefficient floor
    DL_CTC_AMAX  : LREAL := 5.0;  // 系数域上界 [%每摄氏度] / the coefficient ceiling
    DL_CTC_DENMIN: LREAL := 0.1;  // 补偿分母下限 [无量纲] / the denominator floor
END_VAR
VAR
    lrT    : LREAL; // 测温工作量（钳后）[摄氏度] / the clamped temperature work value
    lrAlp  : LREAL; // 系数工作量（钳后）[%每摄氏度] / the clamped coefficient work value
    lrDen  : LREAL; // 补偿分母工作量 [无量纲] / the denominator work value
    bFin   : BOOL;  // 入参有限工作量 [-] / the input finiteness work flag
END_VAR

// 段 1｜返回值与输出预置（四段式第一段，R45）/ segment 1, preset the return and the outputs
FC_DL_ConductivityTempComp := FALSE; // 受理预置假 / preset the accepted false
fCondRef := 0.0; // 输出预置零 / preset the output zero
bValid := FALSE; // 有效预置假 / preset the valid false
bOutOfRange := FALSE; // 越域预置假 / preset the range flag false
bClamped := FALSE; // 钳位预置假 / preset the clamp false
bError := FALSE; // 故障预置假 / preset the fault false

// 段 2｜非有限入参闸（三参数自反双判据全覆盖，R79）/ segment 2, the non finite gate
bFin := (fCondRaw = fCondRaw) AND ((fCondRaw - fCondRaw) = (fCondRaw - fCondRaw)) // 电导率有限 / the conductivity finite
    AND (fTempC = fTempC) AND ((fTempC - fTempC) = (fTempC - fTempC)) // 测温有限 / the temperature finite
    AND (fAlphaPct = fAlphaPct) AND ((fAlphaPct - fAlphaPct) = (fAlphaPct - fAlphaPct)) // 系数有限 / the coefficient finite
    AND (fRefTempC = fRefTempC) AND ((fRefTempC - fRefTempC) = (fRefTempC - fRefTempC)); // 参考温有限 / the reference finite
IF NOT bFin THEN // 非有限命中 / a non finite hit
    bError := TRUE; // 置故障（纪律②）/ raise the fault
    RETURN; // 早退 / return early
END_IF

// 段 3｜域钳制（测温越域置 bOutOfRange，系数钳位置 bClamped，边界二）/ segment 3, the domain clamps
lrT := fTempC; // 装测温 / load the temperature
IF (lrT < DL_CTC_TMIN) OR (lrT > DL_CTC_TMAX) THEN // 测温越域 / the temperature out of range
    bOutOfRange := TRUE; // 置超域标志（信息级）/ raise the out of range flag
    IF lrT < DL_CTC_TMIN THEN // 下越界 / below the floor
        lrT := DL_CTC_TMIN; // 钳到下界 / clamp to the floor
    ELSE // 上越界 / above the ceiling
        lrT := DL_CTC_TMAX; // 钳到上界 / clamp to the ceiling
    END_IF
END_IF
lrAlp := fAlphaPct; // 装系数 / load the coefficient
IF lrAlp < DL_CTC_AMIN THEN // 系数下钳 / clamp the coefficient down
    lrAlp := DL_CTC_AMIN; // 夹到零 / clamp to the floor
    bClamped := TRUE; // 信息级 / informational
ELSIF lrAlp > DL_CTC_AMAX THEN // 系数上钳 / clamp the coefficient up
    lrAlp := DL_CTC_AMAX; // 夹到上限 / clamp to the ceiling
    bClamped := TRUE; // 信息级 / informational
END_IF

// 段 4｜补偿计算（分母下限闸防除零与负分母，边界三）/ segment 4, the compensation with the denominator gate
lrDen := 1.0 + ((lrAlp / 100.0) * (lrT - fRefTempC)); // 补偿分母 / the denominator
IF lrDen < DL_CTC_DENMIN THEN // 分母退化闸（除零与负分母双防）/ the degenerate denominator gate
    bError := TRUE; // 置故障（纪律②）/ raise the fault
    RETURN; // 早退 / return early
END_IF
fCondRef := fCondRaw / lrDen; // 参考温归一（除子已闸）/ the normalization, divided by the gated denominator
bValid := TRUE; // 结果可用 / the result usable
FC_DL_ConductivityTempComp := TRUE; // 受理 / accept
END_FUNCTION
