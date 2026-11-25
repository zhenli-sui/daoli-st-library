// FC_DL_KegFillingCounterPressureCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 桶装背压：饱和压 = 亨利常数·CO2 体积倍数·(1 + 0.02·(T − 10))（温度线性修正为工程近似，
        非严格亨利温度指数式）；静压 = ρ·g·h/1e5 [bar]；背压 = 饱和压 + 静压 + 0.2 bar 裕量。
  邻件/码位: 用酒温与 CO2 目标定背压，与 FC_DL_BeerCoolingLoadCalc 的降温工序衔接；
             16#0002_9237 = 非有限、CO2 倍数/亨利常数/密度非正、高度为负或背压超 6 bar。
*)
FUNCTION FC_DL_KegFillingCounterPressureCalc : REAL
VAR_INPUT
    fBeerTemp : REAL := 4.0;        // 酒温 [°C] / Beer temperature [degC]
    fCO2Vol   : REAL := 2.5;        // 目标 CO2 体积倍数 [-]，域 > 0 / CO2 volumes
    fHenryK   : REAL := 0.65;       // 亨利常数 [bar]，域 > 0 / Henry constant [bar]
    fHeight   : REAL := 3.0;        // 液柱高度 [m]，域 >= 0 / Liquid column height [m]
    fDensity  : REAL := 1010.0;     // 啤酒密度 [kg/m³]，域 > 0 / Beer density [kg/m^3]
END_VAR
VAR_OUTPUT
    fCounterPressure : REAL;        // 背压设定 [bar]，工艺界 6.0 / Counter pressure [bar]
    bValid           : BOOL;        // 结果有效回执 [-] / Result validity receipt
    uErrorId         : UDINT;       // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fSatPress : REAL := 0.0;        // 饱和压 [bar] / Saturation pressure [bar]
    fStatic   : REAL := 0.0;        // 液柱静压 [bar] / Hydrostatic pressure [bar]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fCounterPressure := 0.0;            // 背压缺省零 / Counter pressure default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_KegFillingCounterPressureCalc := 0.0;     // 返回值缺省零（镜像背压）/ Return default zero
// 段 1：非有限闸（五入参全枚举）/ Non-finite gate over all inputs
IF (fBeerTemp <> fBeerTemp) OR (fCO2Vol <> fCO2Vol) OR (fHenryK <> fHenryK)
   OR (fHeight <> fHeight) OR (fDensity <> fDensity)
   OR (ABS(fBeerTemp) >= 3.0E38) OR (ABS(fCO2Vol) >= 3.0E38) OR (ABS(fHenryK) >= 3.0E38)
   OR (ABS(fHeight) >= 3.0E38) OR (ABS(fDensity) >= 3.0E38) THEN
    uErrorId := 16#0002_9237;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（CO2 倍数与亨利常数非正拒收 + 密度正 + 高度非负，R4）/ Domain gate
IF (fCO2Vol <= 1.0E-6) OR (fHenryK <= 1.0E-6) THEN
    uErrorId := 16#0002_9237;   // CO2 倍数或亨利常数非正 / Non-positive CO2 or Henry constant
    RETURN;
END_IF
IF fDensity <= 1.0E-6 THEN
    uErrorId := 16#0002_9237;   // 密度非正，静压不可解 / Non-positive density
    RETURN;
END_IF
IF fHeight < 0.0 THEN
    uErrorId := 16#0002_9237;   // 液柱高度为负 / Negative liquid height
    RETURN;
END_IF
// 段 3：主计算（饱和压 + 静压 + 裕量）/ Main computation
fSatPress := fHenryK * fCO2Vol * (1.0 + 0.02 * (fBeerTemp - 10.0));     // 饱和压 [bar] / Saturation
fStatic := fDensity * 9.81 * fHeight / 1.0E5;                           // 静压 [bar] / Hydrostatic
fCounterPressure := fSatPress + fStatic + 0.2;                          // 背压 [bar] / Counter pressure
// 段 4：出口闸（非有限复核 + 6 bar 工艺界判定）/ Outlet gate
IF (fCounterPressure <> fCounterPressure) OR (ABS(fCounterPressure) >= 3.0E38)
   OR (fCounterPressure <= 0.0) THEN
    fCounterPressure := 0.0;    // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9237;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
IF fCounterPressure > 6.0 THEN
    uErrorId := 16#0002_9237;   // 信息级：背压超 6 bar（桶耐压风险）/ Info: pressure above bound
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_KegFillingCounterPressureCalc := fCounterPressure;    // 返回值镜像背压 / Return mirrors pressure
END_FUNCTION
