(*==============================================================================
 * 组件名称 (Component)  : FC_DL_WaterEnthalpy
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商方言
 * 功能描述 (Function)   : 0~150 摄氏度液态水的比焓，以 0 摄氏度饱和液水为焓基准，
 *                         同时给出「0 摄氏度到当前温度的平均比热」。
 *                         现场用途：冷热量表按质量流量乘比焓差结算、板换换热量核算、
 *                         锅炉给水与回水焓差、蓄冷水罐冷量统计。
 *                         用固定 4.186 千焦每千克开尔文替代真实比焓，在 70~90 摄氏度
 *                         工况会产生 0.5~1 个百分点的系统偏差，按月结算即为真金白银的差额。
 * 出口契约 (Exit)       : 函数返回值 = 比焓（与出口 fEnthalpy 同值，千焦每千克）；
 *                         温度域外一律返回 0.0 且 bValid = FALSE，绝不把域外温度夹到边界
 *                         再照算（把 200 摄氏度的蒸汽按 150 摄氏度的液水结算属静默错误）。
 * 精度声明 (Accuracy)   : 0~100 摄氏度与 IAPWS-IF97 饱和液焓偏差优于 0.3 个百分点；
 *                         100~150 摄氏度偏差优于 0.8 个百分点。
 *                         仅适用于液态水：不得用于蒸汽、过冷水与冰水混合物。
 *                         中间量采用单精度浮点（与既有湿空气焓件保持同一精度口径），
 *                         150 摄氏度时三次项约 3.4E6，单精度七位有效数字仍有余量。
 * 开源溯源 (Origin)     : 来源标签 oscat-building。许可证：OSCAT 为开源发布，本件未读取、
 *                         未复制其函数体、常量名与注释。借鉴点仅为该族的功能定义
 *                         （输入温度、输出比焓、0 摄氏度基准）与「物性函数单独成件、
 *                         不写成一个带模式开关的巨块」的切分方式。
 *                         多项式系数由 0 / 50 / 100 摄氏度三点公开饱和液比热拟合而来自行推导，
 *                         clean-room 独立实现。
 * 码位说明 (Codes)      : 信息级 16#0002_2101（温度域外已拒绝）/ 16#0002_2102（零度点
 *                         平均比热退化为一次项系数）。共 2 码，落在 R12 计划第 1.2 节本件码段内。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS
 * 红线自检 (Redline)    : 1 ✓ 零全局变量表依赖、零外部变量声明、零物理地址
 *                         2 ✓ 纯 IEC 61131-3，无指针、无厂商库
 *                         3 ✓ 域外与 NaN 前置拦截、平均比热除法前置防零、无循环无数组
 *                         4 ✓ 全变量中英双语同行注释
 *                         5 N/A 纯函数无状态机 ｜ 6 N/A 无定时器与边沿实例
 *                         7 ✓ END_FUNCTION 位于文件最后有效行
 * 规格偏离留档 (Deviation):
 *   计划 3.10 节把 2102 描述为「bUseMeanCp 为 TRUE 且温度为 0」时置码，但同节验收向量 V3
 *   未要求 bUseMeanCp 为 TRUE。本实现取「温度落在零度点即置 2102」的口径：平均比热在该点
 *   无论调用方是否需要，都已经退化为常数，这是事实而非开关派生，且与 V3 一致。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R12 · DL_Algo 物性函数族）
 *============================================================================*)
FUNCTION FC_DL_WaterEnthalpy : REAL
VAR_INPUT
    fTempC     : REAL := 0.0;            // 水温 [摄氏度]，域 0~150 / Water temperature in degrees Celsius, 0..150
    bUseMeanCp : BOOL := FALSE;          // TRUE 时同时使用平均比热出口 / Also use the mean specific heat output
END_VAR
VAR_OUTPUT
    fEnthalpy  : REAL;                   // 比焓 [kJ/kg]，0 摄氏度基准 / Specific enthalpy in kilojoules per kilogram
    fCpMean    : REAL;                   // 0 摄氏度到当前温度的平均比热 [kJ/(kg*K)] / Mean specific heat from zero
    uErrorId   : UDINT;                  // 事件码，0 = 无事件 / Event code, zero means none
    bValid     : BOOL;                   // 温度在域内 TRUE / Temperature inside the domain
END_VAR
VAR
    fT         : REAL;                   // 温度快照 [摄氏度] / Temperature snapshot
    fT2        : REAL;                   // 温度平方 [摄氏度平方] / Temperature squared
    fT3        : REAL;                   // 温度立方 [摄氏度立方] / Temperature cubed
    fH         : REAL;                   // 比焓中间量 [kJ/kg] / Enthalpy intermediate
END_VAR
VAR CONSTANT
    DL_H_C1    : REAL := 4.2176;         // 一次项系数，零度附近比热 [kJ/(kg*K)] / Linear coefficient
    DL_H_C2    : REAL := 0.000718;       // 二次项系数 [kJ/(kg*K*K)] / Quadratic coefficient
    DL_H_C3    : REAL := 0.0000047333;   // 三次项系数 [kJ/(kg*K*K*K)] / Cubic coefficient
    DL_T_MIN   : REAL := 0.0;            // 温度域下限 [摄氏度] / Lower temperature bound
    DL_T_MAX   : REAL := 150.0;          // 温度域上限 [摄氏度] / Upper temperature bound
    DL_T_DEN   : REAL := 1.0;            // 平均比热除法的温度分母保护下限 [摄氏度] / Denominator guard for mean cp
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜结果预置：异常路径的输出必须确定，不允许留未初始化量给上层
 *      Safe preset: abnormal paths still publish defined values
 *-----------------------------------------------------------------------------*)
FC_DL_WaterEnthalpy := 0.0;
fEnthalpy := 0.0;
fCpMean   := DL_H_C1;
uErrorId  := 16#0000_0000;
bValid    := FALSE;
fT        := 0.0;
fT2       := 0.0;
fT3       := 0.0;
fH        := 0.0;

(*------------------------------------------------------------------------------
 * 段 2｜域闸门：写成「正向区间取反」，NaN 参与比较恒为假，取反后必被拒
 *      Domain gate written as an inverted positive range, which rejects NaN too
 *      域外不做夹取：夹取会把蒸汽按 150 摄氏度液水结算，属静默错误
 *      No clamping outside the domain: clamping steam to 150 C is a silent error
 *-----------------------------------------------------------------------------*)
IF NOT ((fTempC >= DL_T_MIN) AND (fTempC <= DL_T_MAX)) THEN
    uErrorId := 16#0002_2101;
    bValid   := FALSE;
    FC_DL_WaterEnthalpy := 0.0;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜比焓多项式：由比热 cp 对温度积分得到的一元三次式，常数项为零即 0 摄氏度基准
 *      Enthalpy polynomial: the integral of cp with a zero constant term
 *      cp 拟合式取自 0 / 50 / 100 摄氏度三点公开饱和液比热 4.2176 / 4.1813 / 4.2180
 *      The cp fit follows three public saturation points at 0, 50 and 100 Celsius
 *-----------------------------------------------------------------------------*)
fT  := fTempC;
fT2 := fT * fT;
fT3 := fT2 * fT;
fH  := DL_H_C1 * fT - DL_H_C2 * fT2 + DL_H_C3 * fT3;

(*------------------------------------------------------------------------------
 * 段 4｜平均比热：h 除以温度，零度点除法前置防零，退化为一次项系数
 *      Mean specific heat with a divide by zero guard at the zero degree point
 *-----------------------------------------------------------------------------*)
IF ABS(fT) > DL_T_DEN THEN
    fCpMean := fH / fT;
ELSE
    fCpMean  := DL_H_C1;
    uErrorId := 16#0002_2102;
END_IF

(* 调用方以平均比热参与简化温差算式时，再做一次符号复核 *)
(* When the caller feeds the mean cp into a simplified formula, re-check its sign *)
IF bUseMeanCp AND (fCpMean <= 0.0) THEN
    fCpMean := DL_H_C1;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜出口收口：比焓与平均比热同时落地，bUseMeanCp 仅作调用方语义标记
 *      Output closure: enthalpy and mean cp land together
 *-----------------------------------------------------------------------------*)
fEnthalpy := fH;
bValid    := TRUE;
FC_DL_WaterEnthalpy := fH;
END_FUNCTION
