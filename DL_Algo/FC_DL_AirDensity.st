(*==============================================================================
 * 组件名称 (Component)  : FC_DL_AirDensity
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 湿空气物性（密度）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅用标准 EXP / ABS / LIMIT
 * 功能描述 (Function)   : 按干空气与水蒸气分压叠加法计算湿空气密度
 *                         密度 = 干空气分压 除以 (干空气气体常数 乘以 绝对温度)
 *                                + 水蒸气分压 除以 (水蒸气气体常数 乘以 绝对温度)
 *                         单位为千克每立方米。饱和蒸汽压用 Magnus-Tetens 式计算。
 *                         用于风量质量流量换算（风机功率核算、风管风速换算）、
 *                         洁净室换气次数、烘干与涂布风量配比、空压站产气量折算。
 * 与既有件边界 (Boundary): FC_DL_HumidAirEnthalpy 出比焓（焦耳每克）；
 *                         FC_DL_DewPointCalc 出露点（摄氏度）；本件出密度
 *                         （千克每立方米）。三件共享同一 Magnus 常量口径，
 *                         但各自内联实现，禁止互相调用（泳道内零依赖），
 *                         保证任一件单独移植时不需要再带两个依赖件。
 * 精度声明 (Accuracy)   : 在零下 10 度到 50 度域内，相对误差小于 0.5 个百分点
 *                         （公开文献口径）；超出该域仅供趋势参考。这是本库对
 *                         OSCAT 同类函数行为定义的收窄，按 R11 留档。
 * 设计要点 (Key notes)  : ① 干空气分压必须防负：高湿低压的极端组态会出现
 *                           水蒸气分压大于总压，物理上不可能，但组态可给出；
 *                           出现即钳到 0 并置码，绝不输出负密度；
 *                         ② Magnus 式分母（243.12 加温度）在零下 40 度时为
 *                           203.12，恒大于 0，温度下限已保证无除零；
 *                         ③ 绝对温度由温度下限保证不小于 233.15 开，恒正；
 *                         ④ 域校验采用「钳位后继续算」策略：现场宁可要一个
 *                           标注为近似的密度值，也不要因为传感器越量程就断链。
 * 开源溯源 (Origin)     : oscat-building。参考 OSCAT 公开函数库 Building 分类
 *                         中空气密度函数的功能分类与参数域（温度 / 压力 /
 *                         湿度 三段输入，密度单值输出），只借分类、参数域与
 *                         Magnus 常量口径，实现 100% 自有 clean-room，
 *                         未复制任何源码行，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 EXP 与 LIMIT
 * 故障码表 (Error codes):
 *   16#0002_1E01【信息级】温度越界被钳位
 *   16#0002_1E02【信息级】压力越界被钳位
 *   16#0002_1E03【信息级】相对湿度越界被钳位
 *   16#0002_1E04【信息级】干空气分压为负，已钳到 0（高湿低压极端组态）
 *   16#0002_1E10【信息级】入参非有限，返回 0
 * 验收向量 (Acceptance) :
 *   V1 15 度 / 101325 帕 / 湿度 0 → 约 1.2250 千克每立方米（容差 2E-3）
 *   V2 20 度 / 101325 帕 / 湿度 0 → 约 1.2041 千克每立方米（容差 2E-3）
 *   V3 20 度 / 101325 帕 / 湿度 100 → 必须小于 V2 值（水蒸气比干空气轻）
 *   V4 湿度 150 → 钳到 100，码 1E03，bValid = FALSE
 *   V5 120 度 / 50000 帕 / 湿度 100 → 触发 1E04，密度不为负
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 分母恒正（温度下限保证）、
 *                         分压防负、浮点判等用容差、非有限值筛查
 *                         R5 全变量中英双语同行注释 ｜ R6 N/A（纯函数）
 *                         R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · 工艺物理量链）
 *============================================================================*)

FUNCTION FC_DL_AirDensity : LREAL
VAR_INPUT
    fTempC   : LREAL := 20.0;     // 干球温度，域零下 40 到 120 [摄氏度] / Dry-bulb temperature, -40 to 120 degrees Celsius
    fPressPa : LREAL := 101325.0; // 绝对大气压，域 50000 到 120000 [帕] / Absolute pressure, 50000 to 120000 Pa
    fRh      : LREAL := 50.0;     // 相对湿度，域 0 到 100 [百分比] / Relative humidity, 0 to 100 percent
END_VAR
VAR_OUTPUT
    fDensity    : LREAL;   // 湿空气密度 [千克每立方米] / Moist air density in kilograms per cubic metre
    fSatPressPa : LREAL;   // 饱和蒸汽压，诊断与复用出口 [帕] / Saturation vapour pressure in Pa
    fVapPressPa : LREAL;   // 水蒸气分压 [帕] / Water vapour partial pressure in Pa
    bValid      : BOOL;    // 入参域全部合法且无修正事件为 TRUE [-] / TRUE when the domain is legal and no correction fired
    uErrorId    : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    fTempUse  : LREAL;     // 生效温度（已钳位）[摄氏度] / Effective temperature
    fPressUse : LREAL;     // 生效绝对压力（已钳位）[帕] / Effective pressure
    fRhUse    : LREAL;     // 生效相对湿度（已钳位）[百分比] / Effective relative humidity
    fKelvin   : LREAL;     // 绝对温度 [开尔文] / Absolute temperature in Kelvin
    fPDry     : LREAL;     // 干空气分压 [帕] / Dry air partial pressure
    fDensDry  : LREAL;     // 干空气项密度贡献 [千克每立方米] / Dry air density contribution
    fDensVap  : LREAL;     // 水蒸气项密度贡献 [千克每立方米] / Vapour density contribution
    bDirty    : BOOL;      // 是否发生过钳位或修正事件 [-] / TRUE when any clamp or correction fired
END_VAR
VAR CONSTANT
    DL_R_DRY     : LREAL := 287.058;             // 干空气比气体常数 [焦耳每千克开] / Specific gas constant of dry air
    DL_R_VAP     : LREAL := 461.495;             // 水蒸气比气体常数 [焦耳每千克开] / Specific gas constant of water vapour
    DL_KELVIN    : LREAL := 273.15;              // 摄氏转开尔文偏移 [开] / Celsius to Kelvin offset
    DL_MAGNUS_A  : LREAL := 17.62;               // Magnus 系数 A [-] / Magnus coefficient A
    DL_MAGNUS_B  : LREAL := 243.12;              // Magnus 系数 B [摄氏度] / Magnus coefficient B
    DL_MAGNUS_C  : LREAL := 611.2;               // Magnus 基准饱和压（零度时）[帕] / Magnus reference pressure at zero Celsius
    DL_T_MIN     : LREAL := -40.0;               // 温度下限 [摄氏度] / Temperature lower bound
    DL_T_MAX     : LREAL := 120.0;               // 温度上限 [摄氏度] / Temperature upper bound
    DL_P_MIN     : LREAL := 50000.0;             // 压力下限 [帕] / Pressure lower bound
    DL_P_MAX     : LREAL := 120000.0;            // 压力上限 [帕] / Pressure upper bound
    DL_RH_MIN    : LREAL := 0.0;                 // 湿度下限 [百分比] / Humidity lower bound
    DL_RH_MAX    : LREAL := 100.0;               // 湿度上限 [百分比] / Humidity upper bound
    DL_PCT_FULL  : LREAL := 100.0;               // 百分比满量程 [-] / Full scale of the percent unit
    DL_DENS_MIN  : LREAL := 0.0;                 // 密度下限，负密度一律钳到 0 [千克每立方米] / Density lower bound
    DL_DENS_MAX  : LREAL := 20.0;                // 密度上限，覆盖高压低温极端工况 [千克每立方米] / Density upper bound
    DL_FLOAT_EPS : LREAL := 1.0E-9;              // 浮点容差 [-] / Float tolerance
    DL_BIG       : LREAL := 1.0E300;             // 非有限值兜底门限 [-] / Magnitude guard
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置
 *      Pre-set outputs
 *-----------------------------------------------------------------------------*)
FC_DL_AirDensity := 0.0;
fDensity    := 0.0;
fSatPressPa := 0.0;
fVapPressPa := 0.0;
bValid      := FALSE;
uErrorId    := 16#0000_0000;
bDirty      := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜入参有限性筛查（边界 B1）：任一非有限即返回 0 并给码
 *      Input finiteness check: any non-finite value yields zero and a code
 *-----------------------------------------------------------------------------*)
IF (fTempC <> fTempC) OR (fPressPa <> fPressPa) OR (fRh <> fRh) THEN
    uErrorId := 16#0002_1E10;
    RETURN;
END_IF

IF (ABS(fTempC) > DL_BIG) OR (ABS(fPressPa) > DL_BIG) OR (ABS(fRh) > DL_BIG) THEN
    uErrorId := 16#0002_1E10;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜域校验与钳位（信息级）：钳位后继续计算，结果标注为近似
 *      Domain clamping with informational codes, computation continues
 *-----------------------------------------------------------------------------*)
fTempUse := fTempC;
IF fTempUse < DL_T_MIN THEN
    fTempUse := DL_T_MIN;
    uErrorId := 16#0002_1E01;
    bDirty   := TRUE;
ELSIF fTempUse > DL_T_MAX THEN
    fTempUse := DL_T_MAX;
    uErrorId := 16#0002_1E01;
    bDirty   := TRUE;
END_IF

fPressUse := fPressPa;
IF fPressUse < DL_P_MIN THEN
    fPressUse := DL_P_MIN;
    uErrorId  := 16#0002_1E02;
    bDirty    := TRUE;
ELSIF fPressUse > DL_P_MAX THEN
    fPressUse := DL_P_MAX;
    uErrorId  := 16#0002_1E02;
    bDirty    := TRUE;
END_IF

fRhUse := fRh;
IF fRhUse < DL_RH_MIN THEN
    fRhUse  := DL_RH_MIN;
    uErrorId := 16#0002_1E03;
    bDirty  := TRUE;
ELSIF fRhUse > DL_RH_MAX THEN
    fRhUse  := DL_RH_MAX;
    uErrorId := 16#0002_1E03;
    bDirty  := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜饱和蒸汽压（Magnus-Tetens，单位帕）
 *      Saturation vapour pressure by the Magnus-Tetens relation in Pa
 *      分母 243.12 加温度：温度下限零下 40 度时为 203.12，恒大于 0，无除零面
 *-----------------------------------------------------------------------------*)
fSatPressPa := DL_MAGNUS_C * EXP((DL_MAGNUS_A * fTempUse) / (DL_MAGNUS_B + fTempUse));

(*------------------------------------------------------------------------------
 * 段 5｜水蒸气分压与干空气分压（防负是硬要求）
 *      Vapour partial pressure and dry air partial pressure with a negative guard
 *-----------------------------------------------------------------------------*)
fVapPressPa := fSatPressPa * (fRhUse / DL_PCT_FULL);

fPDry := fPressUse - fVapPressPa;
IF fPDry <= 0.0 THEN
    fPDry   := 0.0;              // 干空气分压不可能为负：高湿低压极端组态下的修正
    uErrorId := 16#0002_1E04;
    bDirty  := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜绝对温度与密度叠加
 *      Absolute temperature and the density superposition
 *      fKelvin 最小为 233.15 开（由温度下限保证），恒正，无除零面
 *-----------------------------------------------------------------------------*)
fKelvin := fTempUse + DL_KELVIN;

fDensDry := fPDry / (DL_R_DRY * fKelvin);
fDensVap := fVapPressPa / (DL_R_VAP * fKelvin);
fDensity := fDensDry + fDensVap;

(*------------------------------------------------------------------------------
 * 段 7｜输出防御与有效性收口
 *      Output defence and validity close-out
 *-----------------------------------------------------------------------------*)
IF (fDensity <> fDensity) OR (ABS(fDensity) > DL_BIG) THEN
    fDensity := 0.0;             // 非有限兜底
    uErrorId := 16#0002_1E10;
    bValid   := FALSE;
    FC_DL_AirDensity := fDensity;
    RETURN;
END_IF

fDensity := LIMIT(DL_DENS_MIN, fDensity, DL_DENS_MAX);

IF bDirty THEN
    bValid := FALSE;             // 发生过钳位或修正，标注为近似
ELSE
    bValid := TRUE;
END_IF

IF ABS(fDensity) < DL_FLOAT_EPS THEN
    bValid := FALSE;             // 密度为零在物理上不可达，视为数据不可用
END_IF

FC_DL_AirDensity := fDensity;
END_FUNCTION
