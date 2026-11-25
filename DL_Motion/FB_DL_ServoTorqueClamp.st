(* ===========================================================================
   组件名   : FB_DL_ServoTorqueClamp
   分类     : DL_Motion / 伺服转矩限幅
   一句话   : 按工艺段查表得正负转矩上限，再按电机温度线性降额，输出限幅生效标志
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : eSeg 工艺段；afPosLim/afNegLim 五段正负转矩上限表 [%]（按段号 1..5）
              fTempMotor 电机温度 [°C]；fTempDerateStart 降额起始温度 [°C]
              fTempDerateEnd 降额终止温度 [°C]；fDerateFloor 最低降额系数
   输出契约 : fTorqueLimPos 正向转矩上限 [%]；fTorqueLimNeg 反向转矩上限（负值）[%]
              fDerateFactor 温度降额系数 0..1；xClampActive 限幅生效（降额<1）
              xValid 输入有效；iErrorCode 0=正常 1=非有限 2=参数非法 9=非法段号
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_TorqueSeg :
(
    eSegIdle := 0,   // 空闲段 | idle segment
    eSegAccel := 1,  // 加速段 | acceleration segment
    eSegRun := 2,    // 匀速段 | constant speed segment
    eSegDecel := 3,  // 减速段 | deceleration segment
    eSegHold := 4    // 保持段 | holding segment
);
END_TYPE

FUNCTION_BLOCK FB_DL_ServoTorqueClamp
VAR_INPUT
    eSeg : E_DL_TorqueSeg := eSegIdle;      // 当前工艺段 | current process segment
    afPosLim : ARRAY[1..5] OF REAL;         // 五段正向转矩上限 [%] | positive limits [%]
    afNegLim : ARRAY[1..5] OF REAL;         // 五段反向转矩上限 [%] | negative limits [%]
    fTempMotor : REAL := 25.0;              // 电机温度 [°C] | motor temperature [°C]
    fTempDerateStart : REAL := 60.0;        // 降额起始温度 [°C] | derate start temp [°C]
    fTempDerateEnd : REAL := 90.0;          // 降额终止温度 [°C] | derate end temp [°C]
    fDerateFloor : REAL := 0.2;             // 最低降额系数 | minimum derate factor
END_VAR
VAR_OUTPUT
    fTorqueLimPos : REAL;                   // 正向转矩上限 [%] | positive torque limit [%]
    fTorqueLimNeg : REAL;                   // 反向转矩上限（负值）[%] | negative torque limit [%]
    fDerateFactor : REAL;                   // 温度降额系数 0..1 | temperature derate factor
    xClampActive : BOOL;                    // 限幅生效标志 | clamp active flag
    xValid : BOOL;                          // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                       // 故障码 0=无故障 | error code
END_VAR
VAR
    _iSeg : INT := 1;                       // 段号数组下标 1..5 | segment index 1..5
    _i : INT := 1;                          // 循环下标 | loop index
    _fPosBase : REAL;                       // 表内正向基值 [%] | table positive base [%]
    _fNegBase : REAL;                       // 表内反向基值 [%] | table negative base [%]
    _fSpan : REAL;                          // 温度降额区间宽度 [°C] | derate span [°C]
    _xBad : BOOL;                           // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                        // 参数非法标志 | invalid parameter flag
END_VAR

// ---- 非有限检测 ----
_xBad := (fTempMotor <> fTempMotor) OR ((fTempMotor - fTempMotor) <> (fTempMotor - fTempMotor))
      OR (fTempDerateStart <> fTempDerateStart) OR ((fTempDerateStart - fTempDerateStart) <> (fTempDerateStart - fTempDerateStart))
      OR (fTempDerateEnd <> fTempDerateEnd) OR ((fTempDerateEnd - fTempDerateEnd) <> (fTempDerateEnd - fTempDerateEnd));
_i := 1;
WHILE _i <= 5 DO
    IF (afPosLim[_i] <> afPosLim[_i]) OR (afNegLim[_i] <> afNegLim[_i]) THEN
        _xBad := TRUE;                      // 表内任一项非有限即判无效
    END_IF
    _i := _i + 1;
END_WHILE

// ---- 参数合法性：降额区间必须正向有序，系数落在 0..1 ----
_fSpan := fTempDerateEnd - fTempDerateStart;
_xBadPar := (_fSpan <= 0.000000001) OR (fDerateFloor <= 0.0) OR (fDerateFloor > 1.0);

// ---- 输出预置 ----
fTorqueLimPos := 0.0;
fTorqueLimNeg := 0.0;
fDerateFactor := 1.0;
xClampActive := FALSE;
xValid := NOT (_xBad OR _xBadPar);
iErrorCode := 0;
IF _xBad THEN
    iErrorCode := 1;
ELSIF _xBadPar THEN
    iErrorCode := 2;
END_IF

// ---- 段号到数组下标映射：用 CASE 显式映射，禁止枚举直接转型 ----
CASE eSeg OF
    eSegIdle: _iSeg := 1;
    eSegAccel: _iSeg := 2;
    eSegRun: _iSeg := 3;
    eSegDecel: _iSeg := 4;
    eSegHold: _iSeg := 5;
ELSE
    _iSeg := 1;                             // 非法段号兜底回空闲段
    iErrorCode := 9;
END_CASE
IF _iSeg < 1 THEN
    _iSeg := 1;                             // 下标钳位，防越界
ELSIF _iSeg > 5 THEN
    _iSeg := 5;
END_IF

IF xValid THEN
    // ---- 温度降额：起始温度以下不降，终止温度以上压到地板值 ----
    IF fTempMotor <= fTempDerateStart THEN
        fDerateFactor := 1.0;
    ELSIF fTempMotor >= fTempDerateEnd THEN
        fDerateFactor := fDerateFloor;
    ELSE
        fDerateFactor := 1.0 - (1.0 - fDerateFloor) * (fTempMotor - fTempDerateStart) / _fSpan;
        IF fDerateFactor < fDerateFloor THEN
            fDerateFactor := fDerateFloor;
        ELSIF fDerateFactor > 1.0 THEN
            fDerateFactor := 1.0;
        END_IF
    END_IF

    // ---- 表值取绝对值作为幅值，正负号由输出方向分别表达 ----
    _fPosBase := ABS(afPosLim[_iSeg]);
    _fNegBase := ABS(afNegLim[_iSeg]);
    fTorqueLimPos := _fPosBase * fDerateFactor;
    fTorqueLimNeg := -_fNegBase * fDerateFactor;    // 反向限幅输出负值

    // ---- 限幅生效：降额系数明显小于 1 即为生效 ----
    xClampActive := (fDerateFactor < 0.999999999);
END_IF
// 非法输入分支不覆盖上限：预置的 0 转矩上限即为安全侧输出（禁止自赋值死语句）
END_FUNCTION_BLOCK
