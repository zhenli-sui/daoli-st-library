(*
  ==================================================================
  组件名 Component  : FC_DL_FlowUnitConvert
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0667（故障级）
  版本   Version    : 1.0.1
  复杂度 Complexity  : 低
  功能   Purpose    : 流量单位换算：m³/h ↔ L/min ↔ NL/min ↔ SCFM 四单位互转，
                      经 m³/h 基准单位两级换算；与 FC_DL_TempUnitConvert /
                      FC_DL_PressUnitConvert 同族三件齐（T0-4 单位换算族补口）。
  开源溯源 Origin    : T0-4 单位换算族补口（内部来源，零检索）；换算因子取
                      NIST 公开物理常数口径（1 ft³ = 0.0283168 m³，标准状态
                      60°F / 1 atm）；与 Temp / Press 族同骨架复用（本库自有
                      范式），零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；NIST 公开单位换算
                      常数口径
  平台   Platform   : 纯 IEC 61131-3（CASE / 四则），三平台通用
  依赖   Depends    : 无（零委托、零库件）
  分工声明 Split     : FC_DL_TempUnitConvert / FC_DL_PressUnitConvert 为同族
                      姊妹件（互引，三件齐口径）；本件只换流量，体积流量
                      与质量流量换算（需密度）归 FC_DL_FlowMassConvert
                      职责，本件不做（R216）。
  归属 Ownership     : E_DL_FlowUnit 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限闸：fValue 非有限（NaN / ±Inf）→ 故障级 0667 +
                         fResult = 0 + bValid = FALSE + 早退；
                      二 单位枚举闸：eUnitFrom / eUnitTo 任一越域（强改非法
                         枚举值）由 CASE ... ELSE 拦截 → 同码 0667 同形出口
                         （禁静默换算）；与非有限出口组合完全相同（fResult
                         = 0、bValid = FALSE、bError = TRUE），合并一码
                         （反证句见码表）；
                      三 换算链：fBase = fValue × 源因子（→ m³/h 基准），
                         fResult = fBase ÷ 目标因子；除子为目标因子常量
                         （因子表全部 > 0，编译期常量，除零不可达，R1 口径）；
                      四 负值合法（反向流量信号照实换算），零值合法；
                      五 NL/min 口径声明：标准状态取 0°C / 101.325 kPa，
                         1 NL/min = 0.06 m³/h；SCFM 取 60°F / 1 atm，
                         1 SCFM = 1.699011 m³/h（NIST 口径，常量注释逐条带
                         来源）；不同标准态需求由调用方先归一再入参；
                      六 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      七 无循环、无数组访问；无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0001_0667【故障级】fValue 非有限或单位枚举越域（两场景出口同形，合并一码）
  码位反证 Note     :
    0667 合并「数值非有限」与「单位枚举越域」的理由：两场景出口组合完全相同
    （fResult = 0、bValid = FALSE、bError = TRUE），三组以内输出无法唯一还原
    该场景，按 R90 不另立码；非零正常换算无码。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 60 m³/h → L/min = 1000.0；V2 100 L/min → m³/h = 6.0
    V3 50 NL/min → m³/h = 3.0；V4 100 SCFM → m³/h ≈ 169.9011
    V5 同单位换算（eFrom = eTo）→ 原值返回（恒等链）
    V6 fValue = NaN → 码 0667 + fResult 0 + bValid = FALSE
    V7 eUnitFrom = 99（强改非法）→ 同码同形出口
    V8 负值 -6 m³/h → L/min = -100.0（反向流量照实）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 2 · 序号 6，T0-4 单位换算族补口，三件齐）
    2026-11-21  v1.0.1  R64 终审 R64-S1（严重·安全侧就地修）：DL_FUC_LMIN 因子
                       方向倒置（16.666667 为 [L/min 每 m³/h] 的倒数值，与本表
                       声明的 [（m³/h）/（L/min）] 口径相反）→ L/min 参与的全部
                       换算错 277.78 倍；改为 1 L/min = 0.06 m³/h。V1~V4 验收向量
                       修复后自证成立（V1 600000/0.06=1000.0 等），与 Press / Temp
                       姊妹件「因子 = 基准/源单位」口径统一。
  ==================================================================
*)
TYPE E_DL_FlowUnit :
(
    eM3h   := 0, // 立方米每小时 [m³/h]（基准单位）/ the cubic meter per hour, the canonical unit
    eLmin  := 1, // 升每分钟 [L/min] / the liter per minute
    eNLmin := 2, // 标准升每分钟 [NL/min]，0°C / 101.325 kPa / the normal liter per minute at the normal state
    eScfm  := 3  // 标准立方英尺每分钟 [SCFM]，60°F / 1 atm / the standard cubic foot per minute
);
END_TYPE

FUNCTION FC_DL_FlowUnitConvert : BOOL
VAR_INPUT
    fValue    : LREAL := 0.0;            // 入口流量值 [源单位]，必须有限 / the inlet flow value, must be finite
    eUnitFrom : E_DL_FlowUnit := E_DL_FlowUnit.eM3h;  // 源单位 [枚举] / the source unit
    eUnitTo   : E_DL_FlowUnit := E_DL_FlowUnit.eLmin;  // 目标单位 [枚举] / the target unit
END_VAR
VAR_OUTPUT
    fResult: LREAL; // 换算结果 [目标单位]，失败 = 0 / the converted result, zero on failure
    bValid : BOOL;  // 结果可用 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    fBase : LREAL := 0.0; // 基准量工作副本 [m³/h] / the canonical working copy in the cubic meter per hour
    fFromF: LREAL := 0.0; // 源单位因子 [（m³/h）/ 源单位] / the source unit factor to the canonical
    fToF  : LREAL := 0.0; // 目标单位因子 [（m³/h）/ 目标单位] / the target unit factor to the canonical
VAR CONSTANT
    DL_FUC_ZERO   : LREAL := 0.0;      // 实数零常量 [目标单位] / the real zero constant
    DL_FUC_M3H    : LREAL := 1.0;      // m³/h 基准因子 [（m³/h）/（m³/h）] / the canonical factor of itself
    DL_FUC_LMIN   : LREAL := 0.06;     // L/min 因子：1 L/min = 0.06 m³/h（60/1000）[（m³/h）/（L/min）] / the liter per minute factor
    DL_FUC_NLMIN  : LREAL := 0.06;     // NL/min 因子：1 NL/min = 0.06 m³/h（0°C / 101.325 kPa）[（m³/h）/（NL/min）] / the normal liter factor
    DL_FUC_SCFM   : LREAL := 1.699011; // SCFM 因子：1 SCFM = 0.0283168 × 60 m³/h（60°F / 1 atm，NIST 口径）[（m³/h）/（SCFM）] / the standard cubic foot factor
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_FlowUnitConvert := FALSE; // 返回值预置假 / preset the return false
fResult := DL_FUC_ZERO; // 结果预置零 [目标单位] / preset the result zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
fBase := DL_FUC_ZERO; // 基准量预置零 [m³/h] / preset the canonical copy zero
fFromF := DL_FUC_M3H; // 源因子预置基准因子（ELSE 兜底口径）/ preset the source factor to the canonical
fToF := DL_FUC_M3H; // 目标因子预置基准因子（ELSE 兜底口径）/ preset the target factor to the canonical

// 段 2｜非有限闸（边界一）/ segment 2, the finiteness gate
IF (fValue <> fValue) OR ((fValue - fValue) <> (fValue - fValue)) THEN // 入口值非有限（NaN 或 ±Inf）/ the inlet value is not finite
    eErr := 16#0001_0667; // 故障级：非有限或单位越域（合并一码，R90）/ fault grade under the merged code
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 3｜源单位因子表（边界二：CASE ... ELSE 拦非法枚举）/ segment 3, the source factor table with the illegal guard
CASE eUnitFrom OF
    E_DL_FlowUnit.eM3h:   fFromF := DL_FUC_M3H;   // 基准因子 / the canonical factor
    E_DL_FlowUnit.eLmin:  fFromF := DL_FUC_LMIN;  // L/min 因子 / the liter per minute factor
    E_DL_FlowUnit.eNLmin: fFromF := DL_FUC_NLMIN; // NL/min 因子 / the normal liter factor
    E_DL_FlowUnit.eScfm:  fFromF := DL_FUC_SCFM;  // SCFM 因子 / the standard cubic foot factor
    ELSE // 非法枚举拦截（禁静默换算，边界二）/ the illegal enumeration guard
        eErr := 16#0001_0667; // 故障级：单位越域（与非有限同形出口，R90）/ fault grade, the unit out of the domain
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        bValid := FALSE; // 结果不可用 / the result is not usable
        RETURN; // 早退 / early return
END_CASE

// 段 4｜目标单位因子表（边界二：CASE ... ELSE 拦非法枚举）/ segment 4, the target factor table with the illegal guard
CASE eUnitTo OF
    E_DL_FlowUnit.eM3h:   fToF := DL_FUC_M3H;   // 基准因子 / the canonical factor
    E_DL_FlowUnit.eLmin:  fToF := DL_FUC_LMIN;  // L/min 因子 / the liter per minute factor
    E_DL_FlowUnit.eNLmin: fToF := DL_FUC_NLMIN; // NL/min 因子 / the normal liter factor
    E_DL_FlowUnit.eScfm:  fToF := DL_FUC_SCFM;  // SCFM 因子 / the standard cubic foot factor
    ELSE // 非法枚举拦截（禁静默换算，边界二）/ the illegal enumeration guard
        eErr := 16#0001_0667; // 故障级：单位越域（与非有限同形出口，R90）/ fault grade, the unit out of the domain
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        bValid := FALSE; // 结果不可用 / the result is not usable
        RETURN; // 早退 / early return
END_CASE

// 段 5｜两级换算（边界三：除子 fToF 为常量因子，因子表全部 > 0，除零不可达）/ segment 5, the two stage conversion with the proven constant divisor
fBase := fValue * fFromF; // 源单位 → m³/h 基准 [m³/h] / the source value to the canonical
fResult := fBase / fToF; // 基准 → 目标单位 [目标单位]（除子常量已证 > 0）/ the canonical to the target with the proven divisor
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_FlowUnitConvert := TRUE; // 返回成功 / return success
END_FUNCTION
