(*
  DL Factory R88 | FC_DL_CvdFilmStressCalc
  功能：Stoney 式算薄膜应力 σ=E_s·t_s²/(6(1-ν)·t_f·R)，曲率半径取绝对值、符号由曲率方向给定，超 300 MPa 提示
  开源溯源：无（clean-room 自研，依据公开工艺公式 Stoney 薄膜应力式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_CvdFilmStressCalc : REAL
VAR_INPUT
    fSubstModulusGPa : REAL := 200.0; // 基片双轴模量 E_s（Si(100) 约 180 GPa） [GPa] / substrate biaxial modulus [GPa]
    fSubstThkUm : REAL := 725.0; // 基片厚度 t_s [µm] / substrate thickness [um]
    fPoissonNu : REAL := 0.28; // 基片泊松比 ν（Si 约 0.28） [-] / Poisson ratio [-]
    fFilmThkUm : REAL := 1.0; // 薄膜厚度 t_f（须远小于 t_s） [µm] / film thickness [um]
    fCurvRadiusM : REAL := 10.0; // 曲率半径 R（带符号：正=上凸/张应力，负=下凹/压应力） [m] / signed radius [m]
    fLimitMPa : REAL := 300.0; // 应力绝对值报警上限 [MPa] / absolute stress alarm limit [MPa]
END_VAR
VAR_OUTPUT
    fStressMPa : REAL; // 薄膜应力 σ（正=张应力，负=压应力） [MPa] / film stress, positive is tensile [MPa]
    xOverLimit : BOOL; // TRUE=应力绝对值超过上限 [-] / TRUE when the absolute value is above the limit [-]
END_VAR
VAR
    fTsM : REAL; // 基片厚度换算为 m [m] / substrate thickness in metres [m]
    fTfM : REAL; // 薄膜厚度换算为 m（除零判据） [m] / film thickness in metres, the divisor [m]
    fDenom : REAL; // 分母 6(1-ν)·t_f·R_abs（除零判据） [m²] / denominator, the divisor [m^2]
    fMagMPa : REAL; // 应力幅值（未加符号） [MPa] / stress magnitude [MPa]
END_VAR

// 段 1｜出口预置
FC_DL_CvdFilmStressCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fStressMPa := 0.0; // 应力预置零 [MPa] / stress preset zero [MPa]
xOverLimit := FALSE; // 超限位预置 FALSE（未判定前不报警） [-] / over-limit flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fSubstModulusGPa > -1.0E30 AND fSubstModulusGPa < 1.0E30) OR NOT (fSubstThkUm > -1.0E30 AND fSubstThkUm < 1.0E30) OR NOT (fPoissonNu > -1.0E30 AND fPoissonNu < 1.0E30) THEN
    RETURN; // 模量/基片厚/泊松比任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fFilmThkUm > -1.0E30 AND fFilmThkUm < 1.0E30) OR NOT (fCurvRadiusM > -1.0E30 AND fCurvRadiusM < 1.0E30) OR NOT (fLimitMPa > -1.0E30 AND fLimitMPa < 1.0E30) THEN
    RETURN; // 膜厚/曲率半径/上限任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fSubstModulusGPa <= 0.0 OR fSubstThkUm < 1.0E-9 OR fFilmThkUm < 1.0E-9 THEN
    RETURN; // 模量正域闸 + 厚度正域闸（分母因子不得为零） [GPa, µm] / positive modulus and thicknesses
END_IF
IF fPoissonNu <= -1.0 OR fPoissonNu >= 0.5 OR ABS(fCurvRadiusM) < 1.0E-9 OR fLimitMPa <= 0.0 THEN
    RETURN; // 泊松比开区间闸 (-1,0.5) + 曲率绝对值闸 + 上限正域闸 [-] / Poisson, radius and limit gates
END_IF

// 段 3｜计算（Stoney 式，长度统一换算到 m、模量换算到 Pa，末步转 MPa）
fTsM := fSubstThkUm * 1.0E-6; // µm × 1e-6 m/µm = m，基片厚换算 [m] / [um] x [m/um] = [m]
fTfM := fFilmThkUm * 1.0E-6; // µm × 1e-6 m/µm = m，膜厚换算 [m] / [um] x [m/um] = [m]
fDenom := 6.0 * (1.0 - fPoissonNu) * fTfM * ABS(fCurvRadiusM); // 无量纲 × 无量纲 × m × m = m²，分母 [m²] / [m^2]
IF fDenom < 1.0E-9 THEN
    RETURN; // 除法前分母闸：6(1-ν)t_f·R 必须大于 1E-9 才可作除数 [m²] / denominator gate [m^2]
END_IF
fMagMPa := fSubstModulusGPa * 1.0E9 * fTsM * fTsM / fDenom * 1.0E-6; // Pa × m² ÷ m² = Pa，再 ×1e-6 转 MPa [MPa] / [MPa]
IF fCurvRadiusM < 0.0 THEN
    fStressMPa := -fMagMPa; // 负曲率对应压应力（符号约定），幅值来自上式的绝对半径 [MPa] / compressive [MPa]
ELSE
    fStressMPa := fMagMPa; // 正曲率对应张应力（符号约定），幅值来自上式的绝对半径 [MPa] / tensile [MPa]
END_IF

// 段 4｜判定与饱和
IF NOT (fStressMPa > -1.0E30 AND fStressMPa < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次（防溢出成 Inf） [MPa] / re-check the result for finiteness [MPa]
END_IF
xOverLimit := ABS(fStressMPa) > fLimitMPa; // 按绝对值与上限直比（张压同判） [MPa] / compare the magnitude [MPa]

// 段 5｜出口自检
IF fTfM >= fTsM THEN RETURN; END_IF // 出口自检：Stoney 式前提是薄膜远薄于基片，t_f>=t_s 时结果不可信 [m] / premiss violated
FC_DL_CvdFilmStressCalc := fStressMPa; // 返回薄膜应力（正=张，负=压） [MPa] / return the film stress [MPa]
END_FUNCTION
