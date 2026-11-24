(*==============================================================================
 * 组件名称 (Component)  : FC_DL_OrificeFlowCalc
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 孔板差压流量计算：温压补偿 + 开方 + 量程归一。
 *                         fFlow = fKCoefficient * sqrt( dP * rho(T,P) )，
 *                         密度委托 FC_DL_AirDensity（理想气体同源式，RH=0 干气口径），
 *                         开方委托 FC_DL_NthRoot(2)，本函数只做前置校验 + 钳位 + 错误码，
 *                         不重写任何开方/密度数学内核（T0 红线）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_MathErr / FUNCTION FC_DL_OrificeFlowCalc
 * 依赖 (Depends)        : DL_Algo/FC_DL_AirDensity、DL_MathData/FC_DL_NthRoot
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 量程钳位 + 非有限值防御 ｜ 枚举成员全部显式赋值
 *                         纯函数无状态保持 ｜ 输出在每条早退路径前已赋确定值
 * 错误码表 (Codes)      : 16#0001_0471 故障级 输入无效(NaN/Inf 或系数/量程非法)
 *                         16#0001_0472 故障级 差压为负
 *                         16#0001_0473 信息级 温度越界(已钳制)
 *                         16#0001_0474 信息级 压力越界(已钳制)
 *                         16#0001_0475 成功
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 1
 * 验收向量 (Acceptance) : dP=25000 Pa, P=101325 Pa, T=20 C, K=1.0 → rho≈1.2041,
 *                         flow≈sqrt(25000*1.2041)≈173.38 m3/h，返回 0475
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MathErr（归属 DL_MathData，与 FC_DL_OrificeFlowCalc 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MathErr :
(
    eInvalidInput := 16#0001_0471,   // 故障级：输入无效（非有限值或系数非法）/ Fault: invalid input
    eDiffPressNeg := 16#0001_0472,   // 故障级：差压为负，物理不可实现 / Fault: negative differential pressure
    eTempClamped  := 16#0001_0473,   // 信息级：温度越界已钳制 / Info: temperature clamped
    ePressClamped := 16#0001_0474,   // 信息级：压力越界已钳制 / Info: pressure clamped
    eOk           := 16#0001_0475    // 成功 / Success
);
END_TYPE

(*==============================================================================
 * 函数: FC_DL_OrificeFlowCalc（纯函数，无任何状态保持）
 * 调用约定: 每周期按需调用；返回值 = 计算有效标志。
 *============================================================================*)
FUNCTION FC_DL_OrificeFlowCalc : BOOL
VAR_INPUT
    fDiffPress_Pa  : REAL;              // 差压 [Pa]，有效域 0~50000 / Differential pressure [Pa]
    fAbsPress_Pa   : REAL;              // 绝压 [Pa]，有效域 5.0E4~2.0E6 / Absolute pressure [Pa]
    fTemp_C        : REAL;              // 温度 [摄氏度]，有效域 -40~400 / Temperature [degC]
    fKCoefficient  : REAL;              // 流量系数（含流出系数 C 的合成值），须 > 0 / Flow coefficient including discharge factor, must be > 0
    fFlowRangeMax  : REAL;              // 流量满量程 [立方米每小时]，须 > 0 / Full-scale flow [m3/h], must be > 0
END_VAR
VAR_OUTPUT
    fFlow_m3h      : REAL;              // 体积流量 [立方米每小时] / Volume flow [m3/h]
    eError         : E_DL_MathErr;      // 错误码 / Error code
END_VAR
VAR CONSTANT
    DL_ORIF_DP_MAX    : REAL := 50000.0;   // 差压量程上限 [帕] / Differential pressure span limit [Pa]
    DL_ORIF_T_MIN     : REAL := -40.0;     // 温度域下限 [摄氏度] / Temperature domain lower bound [degC]
    DL_ORIF_T_MAX     : REAL := 400.0;     // 温度域上限 [摄氏度] / Temperature domain upper bound [degC]
    DL_ORIF_P_MIN     : REAL := 5.0E4;     // 绝压域下限 [帕] / Absolute pressure lower bound [Pa]
    DL_ORIF_P_MAX     : REAL := 2.0E6;     // 绝压域上限 [帕] / Absolute pressure upper bound [Pa]
    DL_ORIF_RH_DRY    : REAL := 0.0;       // 干气口径相对湿度（委托密度入口）[%] / Dry-gas humidity fed to the density delegate [%]
    DL_ORIF_INF_MAX   : REAL := 1.0E30;    // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_ORIF_ZERO      : REAL := 0.0;       // 零值常量，避免裸字面量 / Zero constant, avoids a bare literal
    DL_ORIF_RHO_MIN   : LREAL := 1.0E-9;   // 密度可信下限 [千克每立方米] / Density trust lower bound [kg/m3]
END_VAR
VAR
    fDpUse    : REAL;                    // 生效差压（校验后）[帕] / Effective differential pressure [Pa]
    fTempUse  : REAL;                    // 生效温度（钳位后）[摄氏度] / Effective temperature [degC]
    fPressUse : REAL;                    // 生效绝压（钳位后）[帕] / Effective absolute pressure [Pa]
    fRho      : LREAL;                   // 委托密度输出 [千克每立方米] / Density from the delegate [kg/m3]
    fRadicand : LREAL;                   // 开方被开方数 [帕·千克每立方米] / Radicand [Pa*kg/m3]
    fRootVal  : LREAL;                   // 委托开方输出 [无量纲合成] / Square root from the delegate
    bRootOk   : BOOL;                    // 委托开方有效标志 / Delegate root validity flag
    bNonFin   : BOOL;                    // 非有限输入汇总标志 / Non-finite input aggregate flag
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：任何早退路径前输出已确定（哨兵 0 流量 + 输入无效码）
 *----------------------------------------------------------------------------*)
FC_DL_OrificeFlowCalc := FALSE;                       // 返回值默认无效 / return defaults to invalid
fFlow_m3h := DL_ORIF_ZERO;                            // 流量哨兵 0 / flow sentinel zero
eError := E_DL_MathErr.eInvalidInput;                 // 默认输入无效码 / default invalid-input code

(*------------------------------------------------------------------------------
 * 段 2｜非有限值闸：NaN 用自反判（x <> x），溢出用幅值上限判
 *----------------------------------------------------------------------------*)
bNonFin := (fDiffPress_Pa <> fDiffPress_Pa) OR (ABS(fDiffPress_Pa) > DL_ORIF_INF_MAX)
        OR (fAbsPress_Pa  <> fAbsPress_Pa)  OR (ABS(fAbsPress_Pa)  > DL_ORIF_INF_MAX)
        OR (fTemp_C       <> fTemp_C)       OR (ABS(fTemp_C)       > DL_ORIF_INF_MAX)
        OR (fKCoefficient <> fKCoefficient) OR (ABS(fKCoefficient) > DL_ORIF_INF_MAX)
        OR (fFlowRangeMax <> fFlowRangeMax) OR (ABS(fFlowRangeMax) > DL_ORIF_INF_MAX);
IF bNonFin THEN
    RETURN;                                           // 早退：保持默认输出 / early exit with defaults
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜配置与符号闸：系数/量程必须为正，差压不允许为负
 *----------------------------------------------------------------------------*)
IF (fKCoefficient <= DL_ORIF_ZERO) OR (fFlowRangeMax <= DL_ORIF_ZERO) THEN
    RETURN;                                           // 配置非法：保持输入无效码 / invalid configuration
END_IF
IF fDiffPress_Pa < DL_ORIF_ZERO THEN
    eError := E_DL_MathErr.eDiffPressNeg;             // 故障级：差压为负 / fault: negative dp
    RETURN;
END_IF
fDpUse := fDiffPress_Pa;                              // 差压非负直接采用 / non-negative dp adopted

(*------------------------------------------------------------------------------
 * 段 4｜温度/压力钳位（信息级越界码，先到先得但压力优先级低：温度先判）
 *----------------------------------------------------------------------------*)
eError := E_DL_MathErr.eOk;                           // 预置成功 / preset success
fTempUse := fTemp_C;                                  // 温度工作副本 / temperature working copy
IF fTempUse < DL_ORIF_T_MIN THEN
    fTempUse := DL_ORIF_T_MIN;                        // 下限钳位 / floored
    eError := E_DL_MathErr.eTempClamped;              // 信息级：温度越界 / info: temperature clamped
ELSIF fTempUse > DL_ORIF_T_MAX THEN
    fTempUse := DL_ORIF_T_MAX;                        // 上限钳位 / capped
    eError := E_DL_MathErr.eTempClamped;              // 信息级：温度越界 / info: temperature clamped
END_IF
fPressUse := fAbsPress_Pa;                            // 压力工作副本 / pressure working copy
IF fPressUse < DL_ORIF_P_MIN THEN
    fPressUse := DL_ORIF_P_MIN;                       // 下限钳位 / floored
    IF eError = E_DL_MathErr.eOk THEN
        eError := E_DL_MathErr.ePressClamped;         // 信息级：压力越界（不覆盖温度码）/ info: pressure clamped
    END_IF
ELSIF fPressUse > DL_ORIF_P_MAX THEN
    fPressUse := DL_ORIF_P_MAX;                       // 上限钳位 / capped
    IF eError = E_DL_MathErr.eOk THEN
        eError := E_DL_MathErr.ePressClamped;         // 信息级：压力越界（不覆盖温度码）/ info: pressure clamped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜委托密度（理想气体同源式，RH=0 干气口径；委托 FC_DL_AirDensity）
 *----------------------------------------------------------------------------*)
fRho := FC_DL_AirDensity(fTempC := REAL_TO_LREAL(fTempUse), fPressPa := REAL_TO_LREAL(fPressUse), fRh := REAL_TO_LREAL(DL_ORIF_RH_DRY));   // 密度委托 [千克每立方米] / density via delegate
IF (fRho <> fRho) OR (ABS(fRho) > REAL_TO_LREAL(DL_ORIF_INF_MAX)) OR (fRho <= DL_ORIF_RHO_MIN) THEN
    eError := E_DL_MathErr.eInvalidInput;             // 委托输出不可信：按输入无效处置 / unusable delegate output
    fFlow_m3h := DL_ORIF_ZERO;                        // 流量哨兵 / flow sentinel
    FC_DL_OrificeFlowCalc := FALSE;                   // 返回无效 / return invalid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜委托开方（FC_DL_NthRoot(2)）：被开方数 = 差压 x 密度，段 5 已保证非负
 *----------------------------------------------------------------------------*)
fRadicand := REAL_TO_LREAL(fDpUse) * fRho;                     // 被开方数 [帕·千克每立方米] / radicand
fRootVal := FC_DL_NthRoot(fValue := fRadicand, nRoot := 2, bValid => bRootOk);   // 开方委托 / root via delegate
IF (NOT bRootOk) OR (fRootVal <> fRootVal) OR (ABS(fRootVal) > REAL_TO_LREAL(DL_ORIF_INF_MAX)) THEN
    eError := E_DL_MathErr.eInvalidInput;             // 委托失败按输入无效处置 / delegate failure mapped to invalid input
    FC_DL_OrificeFlowCalc := FALSE;                   // 返回无效 / return invalid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜量程换算与上限钳制：flow = K x root，超出满量程钳制并保留成功码
 *----------------------------------------------------------------------------*)
fFlow_m3h := LREAL_TO_REAL(fRootVal) * fKCoefficient;   // 合成流量 [立方米每小时] / composed flow [m3/h]
IF fFlow_m3h > fFlowRangeMax THEN
    fFlow_m3h := fFlowRangeMax;                       // 满量程钳制 / clamped to full scale
END_IF
IF fFlow_m3h < DL_ORIF_ZERO THEN
    fFlow_m3h := DL_ORIF_ZERO;                        // 下限防护（禁止伪负流量）/ floor guard
END_IF
FC_DL_OrificeFlowCalc := TRUE;                        // 计算有效 / computation valid
RETURN;
END_FUNCTION
