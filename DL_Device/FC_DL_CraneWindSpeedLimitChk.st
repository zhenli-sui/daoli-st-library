(*
 * FC_DL_CraneWindSpeedLimitChk | C1 | DL_Device
 * 功能：风速分级作业限幅判定（正常 / 降速 / 停工 / 锚定）       单位：风速 [m/s]，分级与许可为枚举码与布尔
 * 工况边界：阈值取 GB/T 3811 工作状态风 13.8 / 20.0 / 25.0 m/s；判据以 MAX(3 s 均值, 阵风) 为最不利值；风速 NaN/Inf 或超 40 m/s 量程一律按锚定侧安全值输出；本件不含滞环，滞环由序列 FB 承担
 * 代数值回代：MAX(均值,阵风)=22.0 → nLevel=2（20~25 停工）；26.0 → nLevel=3（锚定）；8.0 → nLevel=0（正常）（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CraneWindSpeedLimitChk : BOOL
VAR_INPUT
    rWindMs : REAL;                  // 风速 3 s 均值 | wind speed, 3 s mean [m/s]
    rGustMs : REAL;                  // 风速阵风值（3 s 均值窗内的最大瞬时）| gust value within the 3 s window [m/s]
END_VAR
VAR_OUTPUT
    nLevel         : INT;            // 0=正常 / 1=降速 / 2=停工 / 3=锚定 | 0 normal, 1 derate, 2 stop, 3 anchor
    xPermitWork    : BOOL;           // 允许作业 | work permitted
    xPermitTravel  : BOOL;           // 允许行车 | travelling permitted
    xRequireAnchor : BOOL;           // 要求锚定 | anchoring required
    xPermitFullSpeed : BOOL;         // 允许全速（仅 0 级）| full speed permitted, level 0 only
    xValid         : BOOL;           // 输出有效（风速可信）| outputs valid, the wind reading is trustworthy
END_VAR
VAR
    xFinMean : BOOL;                 // 均值有限性 | mean value is finite
    xFinGust : BOOL;                 // 阵风有限性 | gust value is finite
    rWindChk : REAL;                 // 判定用风速（取均值与阵风的较大者）| wind used for grading, the worse of the two
END_VAR
VAR CONSTANT
    DL_CWS_DERATE : REAL := 13.8;    // 降速阈 | derating threshold [m/s]
    DL_CWS_STOP   : REAL := 20.0;    // 停工阈 | stop threshold [m/s]
    DL_CWS_ANCHOR : REAL := 25.0;    // 锚定阈 | anchoring threshold [m/s]
    DL_CWS_MAX    : REAL := 40.0;    // 风速量程上限 | upper wind range limit [m/s]
END_VAR

// 段1｜非有限闸（R19：不可信即按锚定侧安全值输出，不让非有限值参与比较）
xFinMean := (rWindMs = rWindMs) AND ((rWindMs - rWindMs) = 0.0);
xFinGust := (rGustMs = rGustMs) AND ((rGustMs - rGustMs) = 0.0);
IF (NOT xFinMean) OR (NOT xFinGust) THEN
    nLevel := 3;                     // 安全值：最高级（锚定）| safe value, the highest level
    xPermitWork := FALSE;
    xPermitTravel := FALSE;
    xRequireAnchor := TRUE;
    xPermitFullSpeed := FALSE;
    xValid := FALSE;
    FC_DL_CraneWindSpeedLimitChk := FALSE;
    RETURN;
END_IF

// 段2｜域闸：负风速或超量程同样按不可信处理（判据与出口同源，R24）
IF (rWindMs < 0.0) OR (rGustMs < 0.0) OR (rWindMs > DL_CWS_MAX) OR (rGustMs > DL_CWS_MAX) THEN
    nLevel := 3;
    xPermitWork := FALSE;
    xPermitTravel := FALSE;
    xRequireAnchor := TRUE;
    xPermitFullSpeed := FALSE;
    xValid := FALSE;
    FC_DL_CraneWindSpeedLimitChk := FALSE;
    RETURN;
END_IF

// 段3｜算法：以最不利值（均值与阵风的较大者）分级
rWindChk := MAX(rWindMs, rGustMs);
nLevel := 0;
xPermitWork := TRUE;
xPermitTravel := TRUE;
xRequireAnchor := FALSE;
xPermitFullSpeed := TRUE;
IF rWindChk > DL_CWS_ANCHOR THEN
    nLevel := 3;                     // >25：锚定 | above 25, anchor
    xPermitWork := FALSE;
    xPermitTravel := FALSE;
    xRequireAnchor := TRUE;
    xPermitFullSpeed := FALSE;
ELSIF rWindChk > DL_CWS_STOP THEN
    nLevel := 2;                     // 20~25：停工 | 20 to 25, stop
    xPermitWork := FALSE;
    xPermitTravel := FALSE;
    xRequireAnchor := FALSE;
    xPermitFullSpeed := FALSE;
ELSIF rWindChk >= DL_CWS_DERATE THEN
    nLevel := 1;                     // 13.8~20：降速作业 | 13.8 to 20, derated working
    xPermitWork := TRUE;
    xPermitTravel := TRUE;
    xRequireAnchor := FALSE;
    xPermitFullSpeed := FALSE;
END_IF

// 段4｜出口
xValid := TRUE;
FC_DL_CraneWindSpeedLimitChk := TRUE;
END_FUNCTION
