(*==============================================================================
 * 组件名称 (Component)  : FC_DL_AirDensityFanPower
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 风机轴功率空气密度修正：P_corr = P_rated x rho/rho0，
 *                         rho 委托 FC_DL_AirDensity（湿空气理想气体内核）
 *                         本函数只做前置校验 + 钳位 + 错误码，不重写密度内核。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_FanErr / FUNCTION FC_DL_AirDensityFanPower
 * 依赖 (Depends)        : DL_Algo/FC_DL_AirDensity
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 量程钳位 + 非有限值防御 ｜ 枚举成员全部显式赋值
 *                         纯函数无状态保持 ｜ 输出在每条早退路径前已赋确定值
 * 错误码表 (Codes)      : 16#0002_370B 成功
 *                         16#0002_370C 信息级 温度越界(已钳制)
 *                         16#0002_370D 信息级 湿度越界(已钳制)
 *                         16#0002_370E 信息级 压力越界(已钳制)
 *                         16#0002_370F 故障级 额定功率非法（<= 0 或非有限）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 1
 * 验收向量 (Acceptance) : T=20 C, RH=50%, P=101325 Pa → rho≈1.2041，
 *                         ratio≈0.9829, P_rated=10 kW → P_corr≈9.829 kW，返回 370B
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FanErr（归属 DL_Algo，与 FC_DL_AirDensityFanPower 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FanErr :
(
    eOk          := 16#0002_370B,    // 成功 / Success
    eTempClamped := 16#0002_370C,    // 信息级：温度越界已钳制 / Info: temperature clamped
    eHumClamped  := 16#0002_370D,    // 信息级：湿度越界已钳制 / Info: humidity clamped
    ePressClamp  := 16#0002_370E,    // 信息级：压力越界已钳制 / Info: pressure clamped
    ePowerBad    := 16#0002_370F     // 故障级：额定功率非法 / Fault: illegal rated power
);
END_TYPE

(*==============================================================================
 * 函数: FC_DL_AirDensityFanPower（纯函数，无任何状态保持）
 * 调用约定: 每周期按需调用；返回值 = 计算有效标志。
 *============================================================================*)
FUNCTION FC_DL_AirDensityFanPower : BOOL
VAR_INPUT
    fTemp_C     : REAL;                // 气温 [摄氏度]，有效域 -40~60 / Air temperature [degC]
    fRelHumPct  : REAL;                // 相对湿度 [百分数]，有效域 0~100 / Relative humidity [percent]
    fPress_Pa   : REAL;                // 大气压 [帕]，有效域 6.0E4~1.1E5 / Atmospheric pressure [Pa]
    fPowerRated : REAL;                // 额定轴功率 [千瓦]，有效域 0.1~5000 / Rated shaft power [kW]
END_VAR
VAR_OUTPUT
    fPowerCorr  : REAL;                // 密度修正后轴功率 [千瓦] / Density-corrected shaft power [kW]
    eError      : E_DL_FanErr;         // 错误码 / Error code
END_VAR
VAR CONSTANT
    DL_FAN_T_MIN     : REAL := -40.0;   // 温度域下限 [摄氏度] / Temperature lower bound [degC]
    DL_FAN_T_MAX     : REAL := 60.0;    // 温度域上限 [摄氏度] / Temperature upper bound [degC]
    DL_FAN_HUM_MIN   : REAL := 0.0;     // 湿度域下限 [百分数] / Humidity lower bound [percent]
    DL_FAN_HUM_MAX   : REAL := 100.0;   // 湿度域上限 [百分数] / Humidity upper bound [percent]
    DL_FAN_P_MIN     : REAL := 6.0E4;   // 大气压域下限 [帕] / Pressure lower bound [Pa]
    DL_FAN_P_MAX     : REAL := 1.1E5;   // 大气压域上限 [帕] / Pressure upper bound [Pa]
    DL_FAN_RHO0      : REAL := 1.225;   // 标准工况空气密度 [千克每立方米] / Reference air density [kg/m3]
    DL_FAN_RATIO_MIN : REAL := 0.5;     // 密度比强制下限 [无量纲] / Forced ratio lower bound
    DL_FAN_RATIO_MAX : REAL := 1.5;     // 密度比强制上限 [无量纲] / Forced ratio upper bound
    DL_FAN_INF_MAX   : REAL := 1.0E30;  // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_FAN_ZERO      : REAL := 0.0;     // 零值常量，避免裸字面量 / Zero constant
END_VAR
VAR
    fTempUse  : REAL;                  // 生效温度（钳位后）[摄氏度] / Effective temperature [degC]
    fHumUse   : REAL;                  // 生效湿度（钳位后）[百分数] / Effective humidity [percent]
    fPressUse : REAL;                  // 生效大气压（钳位后）[帕] / Effective pressure [Pa]
    fRho      : LREAL;                 // 委托密度输出 [千克每立方米] / Density from the delegate [kg/m3]
    fRatio    : REAL;                  // 密度比 rho/rho0 [无量纲] / Density ratio [dimensionless]
    bNonFin   : BOOL;                  // 非有限输入汇总标志 / Non-finite input aggregate flag
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：任何早退路径前输出已确定（哨兵 0 功率 + 功率非法码）
 *----------------------------------------------------------------------------*)
FC_DL_AirDensityFanPower := FALSE;                   // 返回值默认无效 / return defaults to invalid
fPowerCorr := DL_FAN_ZERO;                           // 功率哨兵 0 / power sentinel zero
eError := E_DL_FanErr.ePowerBad;                     // 默认功率非法码 / default illegal-power code

(*------------------------------------------------------------------------------
 * 段 2｜非有限值闸：NaN 用自反判，溢出用幅值上限判
 *----------------------------------------------------------------------------*)
bNonFin := (fTemp_C     <> fTemp_C)     OR (ABS(fTemp_C)     > DL_FAN_INF_MAX)
        OR (fRelHumPct  <> fRelHumPct)  OR (ABS(fRelHumPct)  > DL_FAN_INF_MAX)
        OR (fPress_Pa   <> fPress_Pa)   OR (ABS(fPress_Pa)   > DL_FAN_INF_MAX)
        OR (fPowerRated <> fPowerRated) OR (ABS(fPowerRated) > DL_FAN_INF_MAX);
IF bNonFin THEN
    eError := E_DL_FanErr.ePowerBad;                 // 非有限输入并入功率非法段（同为全拒，反证句见头注）/ non-finite mapped to power band
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜额定功率闸：必须为正且落在可信域
 *----------------------------------------------------------------------------*)
IF (fPowerRated < 0.1) OR (fPowerRated > 5000.0) THEN
    eError := E_DL_FanErr.ePowerBad;                 // 故障级：额定功率非法 / fault: illegal rated power
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜三输入钳位（信息级越界码，温度→湿度→压力优先级顺序判定）
 *----------------------------------------------------------------------------*)
eError := E_DL_FanErr.eOk;                           // 预置成功 / preset success
fTempUse := fTemp_C;                                 // 温度工作副本 / temperature working copy
IF fTempUse < DL_FAN_T_MIN THEN
    fTempUse := DL_FAN_T_MIN;                        // 下限钳位 / floored
    eError := E_DL_FanErr.eTempClamped;              // 信息级：温度越界 / info: temperature clamped
ELSIF fTempUse > DL_FAN_T_MAX THEN
    fTempUse := DL_FAN_T_MAX;                        // 上限钳位 / capped
    eError := E_DL_FanErr.eTempClamped;              // 信息级：温度越界 / info: temperature clamped
END_IF
fHumUse := fRelHumPct;                               // 湿度工作副本 / humidity working copy
IF fHumUse < DL_FAN_HUM_MIN THEN
    fHumUse := DL_FAN_HUM_MIN;                       // 下限钳位 / floored
    IF eError = E_DL_FanErr.eOk THEN
        eError := E_DL_FanErr.eHumClamped;           // 信息级：湿度越界（不覆盖前序码）/ info: humidity clamped
    END_IF
ELSIF fHumUse > DL_FAN_HUM_MAX THEN
    fHumUse := DL_FAN_HUM_MAX;                       // 上限钳位 / capped
    IF eError = E_DL_FanErr.eOk THEN
        eError := E_DL_FanErr.eHumClamped;           // 信息级：湿度越界（不覆盖前序码）/ info: humidity clamped
    END_IF
END_IF
fPressUse := fPress_Pa;                              // 压力工作副本 / pressure working copy
IF fPressUse < DL_FAN_P_MIN THEN
    fPressUse := DL_FAN_P_MIN;                       // 下限钳位 / floored
    IF eError = E_DL_FanErr.eOk THEN
        eError := E_DL_FanErr.ePressClamp;           // 信息级：压力越界（不覆盖前序码）/ info: pressure clamped
    END_IF
ELSIF fPressUse > DL_FAN_P_MAX THEN
    fPressUse := DL_FAN_P_MAX;                       // 上限钳位 / capped
    IF eError = E_DL_FanErr.eOk THEN
        eError := E_DL_FanErr.ePressClamp;           // 信息级：压力越界（不覆盖前序码）/ info: pressure clamped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜委托密度（FC_DL_AirDensity 湿空气内核）
 *----------------------------------------------------------------------------*)
fRho := FC_DL_AirDensity(fTempC := REAL_TO_LREAL(fTempUse), fPressPa := REAL_TO_LREAL(fPressUse), fRh := REAL_TO_LREAL(fHumUse));   // 密度委托 [千克每立方米] / density via delegate
IF (fRho <> fRho) OR (ABS(fRho) > REAL_TO_LREAL(DL_FAN_INF_MAX)) OR (fRho <= LREAL#1.0E-9) THEN
    eError := E_DL_FanErr.ePowerBad;                 // 委托输出不可信：按功率非法全拒处置（反证句：输出同为哨兵+无效）/ unusable delegate output
    fPowerCorr := DL_FAN_ZERO;                       // 功率哨兵 / power sentinel
    FC_DL_AirDensityFanPower := FALSE;               // 返回无效 / return invalid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜密度比计算与强制钳位 [0.5, 1.5]：除子 rho0 为常量非零
 *----------------------------------------------------------------------------*)
fRatio := LREAL_TO_REAL(fRho) / DL_FAN_RHO0;         // 密度比 [无量纲] / density ratio [dimensionless]
IF fRatio < DL_FAN_RATIO_MIN THEN
    fRatio := DL_FAN_RATIO_MIN;                      // 比率强制下限（防过修）/ forced ratio floor
ELSIF fRatio > DL_FAN_RATIO_MAX THEN
    fRatio := DL_FAN_RATIO_MAX;                      // 比率强制上限（防过修）/ forced ratio ceiling
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜功率修正与出口（P = P_rated x ratio）
 *----------------------------------------------------------------------------*)
fPowerCorr := fPowerRated * fRatio;                  // 修正功率 [千瓦] / corrected power [kW]
IF fPowerCorr > DL_FAN_INF_MAX THEN
    fPowerCorr := DL_FAN_INF_MAX;                    // 溢出钳位防护 / overflow clamp guard
END_IF
IF fPowerCorr < DL_FAN_ZERO THEN
    fPowerCorr := DL_FAN_ZERO;                       // 下限防护 / floor guard
END_IF
FC_DL_AirDensityFanPower := TRUE;                    // 计算有效 / computation valid
RETURN;
END_FUNCTION
