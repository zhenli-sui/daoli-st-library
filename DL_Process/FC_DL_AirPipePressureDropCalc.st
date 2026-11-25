(*
  Name: FC_DL_AirPipePressureDropCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 按 Darcy-Weisbach 简化式算管段压降：ΔP = f · (L/D) · (ρ · v² / 2)，
           其中 f 为固定经验摩擦系数（湍流粗糙区，取 VAR CONSTANT 组态值），
           L 为管长、D 为管内径、ρ 为工况密度、v 为管内平均流速。
        2) 管内流速由容积流量与截面积反算：v = Q / A，A = π · D² / 4。
           先统一单位（m3/min → m3/s、mm → m），再算流速，最后把 Pa 折算为 bar。
           算得的压降与允许压降 DL_MAX_DROP_BAR 比较给出超限标志 xOverLimit，
           用于校核管径选型或判既有管路是否已成为瓶颈。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fDropBar 强制 0.0、xOverLimit 强制 FALSE）
           并置无效（R19），无效数据不得触发管径超限告警。
        2) 分母零闸：管内径按 DL_D_MIN_MM(1.0 mm) 做下限钳制后再参与除法，
           流速分母（截面积）与压降分母（D）由此同时得到保护；密度按 DL_RHO_MIN 做下限钳制，
           避免密度为 0 使压降恒为 0 而掩盖超限。
        3) 负值闸：流量、管长、内径任一为负判无效（不取绝对值掩盖）；管长为 0 属合法
           （忽略沿程段），压降为 0，不判无效。
        4) 饱和钳制：流速钳 0 ~ DL_V_MAX_MPS(200 m/s)、压降钳 0 ~ DL_DROP_MAX_BAR(50 bar)，
           防微小管径把压降放大到溢出。
        5) 报警门控：xOverLimit 只在 xValid 为 TRUE 时才可能为 TRUE。
  量纲自证：v = (m3/s) / (m2) = m/s；
           ΔP = [-] · (m/m) · (kg/m3 · m2/s2) = kg/(m·s2) = Pa，量纲闭合（1 Pa = 1 kg/(m·s²)）；
           折算 fDropBar = Pa / 1.0E5 (Pa/bar) = bar；比较两侧同为 bar。
*)

FUNCTION FC_DL_AirPipePressureDropCalc : BOOL
VAR_INPUT
    fFlowM3min      : REAL;   // 管内自由空气体积流量 [m3/min] / Free air volumetric flow [m3/min]
    fPipeIDmm       : REAL;   // 管道内径 [mm] / Pipe internal diameter [mm]
    fLengthM        : REAL;   // 管段长度 [m] / Pipe section length [m]
    fDensityKgM3    : REAL;   // 工况空气密度 [kg/m3] / Air density at operating condition [kg/m3]
END_VAR
VAR_OUTPUT
    fDropBar        : REAL;   // 管段压降 [bar] / Pipe section pressure drop [bar]
    fVelMps         : REAL;   // 管内平均流速 [m/s] / Mean pipe velocity [m/s]
    xOverLimit      : BOOL;   // 压降超允许值 [bool] / Pressure drop over allowable limit [bool]
    xValid          : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDClampMm      : REAL;   // 钳制后的管内径 [mm] / Clamped internal diameter [mm]
    _fDM           : REAL;   // 管内径 [m] / Internal diameter [m]
    _fAreaM2        : REAL;   // 管道截面积 [m2] / Pipe cross-section area [m2]
    _fFlowM3s       : REAL;   // 体积流量 [m3/s] / Volumetric flow [m3/s]
    _fVelRawMps     : REAL;   // 未饱和的流速 [m/s] / Raw velocity [m/s]
    _fRhoClamp      : REAL;   // 钳制后的密度 [kg/m3] / Clamped density [kg/m3]
    _fDropPa        : REAL;   // 压降中间量 [Pa] / Pressure drop intermediate [Pa]
    _fDropRawBar    : REAL;   // 未饱和的压降 [bar] / Raw pressure drop [bar]
END_VAR
VAR CONSTANT
    DL_EPS          : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG          : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PI           : REAL := 3.14159265;   // 圆周率 [-] / Pi [-]
    DL_MM_PER_M     : REAL := 1000.0;    // m → mm 换算因子 [mm/m] / Metre to millimetre factor [mm/m]
    DL_S_PER_MIN    : REAL := 60.0;      // min → s 换算因子 [s/min] / Minute to second factor [s/min]
    DL_FRICTION     : REAL := 0.020;     // 湍流粗糙区摩擦系数 f [-] / Turbulent friction factor f [-]
    DL_D_MIN_MM     : REAL := 1.0;       // 内径下限钳制值 [mm] / Internal diameter lower clamp [mm]
    DL_RHO_MIN      : REAL := 0.1;       // 密度下限钳制值 [kg/m3] / Density lower clamp [kg/m3]
    DL_PA_PER_BAR   : REAL := 1.0E5;     // Pa → bar 换算因子 [Pa/bar] / Pascal to bar factor [Pa/bar]
    DL_V_MAX_MPS    : REAL := 200.0;     // 流速饱和上限 [m/s] / Velocity saturation ceiling [m/s]
    DL_DROP_MAX_BAR : REAL := 50.0;      // 压降饱和上限 [bar] / Pressure drop saturation ceiling [bar]
    DL_MAX_DROP_BAR : REAL := 0.35;      // 管段允许压降（设计准则）[bar] / Allowable drop per section [bar]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fFlowM3min > -DL_BIG AND fFlowM3min < DL_BIG)
   OR NOT (fPipeIDmm > -DL_BIG AND fPipeIDmm < DL_BIG)
   OR NOT (fLengthM > -DL_BIG AND fLengthM < DL_BIG)
   OR NOT (fDensityKgM3 > -DL_BIG AND fDensityKgM3 < DL_BIG) THEN
    fDropBar := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fVelMps := 0.0;                         // 流速强制 0.0 / Velocity forced to zero
    xOverLimit := FALSE;                    // 超限标志强制 FALSE / Over-limit forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirPipePressureDropCalc := FALSE; // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：负值闸（流量/管长/内径任一为负或内径为 0 均属故障或组态错） —— *)
IF (fFlowM3min < 0.0) OR (fLengthM < 0.0) OR (fPipeIDmm <= DL_EPS) OR (fDensityKgM3 <= DL_EPS) THEN
    fDropBar := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fVelMps := 0.0;                         // 流速强制 0.0 / Velocity forced to zero
    xOverLimit := FALSE;                    // 超限标志强制 FALSE / Over-limit forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirPipePressureDropCalc := FALSE; // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：单位统一与截面积（mm → m，min → s，均为分母保护后再除） —— *)
_fDClampMm := MAX(DL_D_MIN_MM, fPipeIDmm);                        // 内径下限钳 [mm]
_fDM := _fDClampMm / DL_MM_PER_M;                                 // 内径 [m]
_fAreaM2 := DL_PI * _fDM * _fDM / 4.0;                            // 截面积 A = πD²/4 [m2]
_fFlowM3s := fFlowM3min / DL_S_PER_MIN;                           // 体积流量 [m3/s]
_fRhoClamp := MAX(DL_RHO_MIN, fDensityKgM3);                      // 密度下限钳 [kg/m3]

(* —— 段 4：流速（R22 方向自核：体积流量除以截面积，不是乘） —— *)
_fVelRawMps := _fFlowM3s / _fAreaM2;                              // 流速 [m/s]

(* —— 段 5：Darcy-Weisbach 简化式（Pa 量纲：ρv²/2 为动压） —— *)
_fDropPa := DL_FRICTION * (fLengthM / _fDM) * (_fRhoClamp * _fVelRawMps * _fVelRawMps / 2.0);
_fDropRawBar := _fDropPa / DL_PA_PER_BAR;                          // Pa → bar

(* —— 段 6：输出单点写盘（先饱和钳制，再据同一值判超限，保证判据与出口同源） —— *)
fVelMps := LIMIT(0.0, _fVelRawMps, DL_V_MAX_MPS);                 // 流速 [m/s]
fDropBar := LIMIT(0.0, _fDropRawBar, DL_DROP_MAX_BAR);            // 压降 [bar]
xValid := (fFlowM3min >= 0.0) AND (fLengthM >= 0.0)
          AND (fPipeIDmm > DL_EPS) AND (fDensityKgM3 > DL_EPS);   // 有效位单点聚合
xOverLimit := xValid AND (fDropBar > DL_MAX_DROP_BAR);            // 超允许压降报警
FC_DL_AirPipePressureDropCalc := xValid;                          // 返回码：TRUE = 计算可信

END_FUNCTION
