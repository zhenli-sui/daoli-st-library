(* ===========================================================================
   组件名   : FB_DL_StrainFatigueCounter
   分类     : DL_Device / 应变疲劳循环计数
   一句话   : 简化雨流（峰值谷值三点配对）统计循环幅值并累积线性 S-N 损伤度
   复杂度   : 3        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fStrain 应变输入 [µε]；fDeadBand 反转识别死区 [µε]
              fSnCoeff S-N 系数，即 N=1 对应的循环幅值 [µε]
              fDamageLimit 损伤度限值（1.0=理论失效） | damage limit
              xReset 计数与损伤复位上升沿
   输出契约 : fDamageAcc 累积损伤度；iCycles 已计数全循环个数；iStackLevel 反转点栈深
              fRangeMax 已统计最大循环幅值 [µε]；xOverDamage 损伤超限锁存
              xValid 输入有效；iErrorCode 0=正常 1=非有限或参数非法 2=栈满降级
   算法说明 : 三点法判据——设栈顶三点 A,B,C，幅值 R1=|A−B|、R2=|B−C|；
              若 R2 ≥ R1 则 A→B 构成一个全循环（幅值 R1），弹出 A、B 两点；
              线性 S-N 近似取 N = fSnCoeff / R1，单循环损伤 = 1/N
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_FatigueDir :
(
    eDirNone := 0,   // 未定向（初始） | undirected initial
    eDirUp := 1,     // 上升段 | rising run
    eDirDown := 2    // 下降段 | falling run
);
END_TYPE

FUNCTION_BLOCK FB_DL_StrainFatigueCounter
VAR_INPUT
    fStrain : REAL;                        // 应变输入 [µε] | strain input [µε]
    fDeadBand : REAL := 5.0;               // 反转识别死区 [µε] | reversal dead band [µε]
    fSnCoeff : REAL := 500.0;              // S-N 系数（N=1 对应幅值） [µε] | sn coefficient [µε]
    fDamageLimit : REAL := 1.0;            // 损伤度限值 | damage limit
    xReset : BOOL;                         // 复位上升沿 | reset rising edge
END_VAR
VAR_OUTPUT
    fDamageAcc : REAL;                     // 累积损伤度 | accumulated damage
    iCycles : INT;                         // 已计数全循环个数 | counted full cycles
    iStackLevel : INT;                     // 反转点栈深 | reversal stack level
    fRangeMax : REAL;                      // 已统计最大循环幅值 [µε] | max counted range [µε]
    xOverDamage : BOOL;                    // 损伤超限锁存 | latched over-damage
    xValid : BOOL;                         // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                      // 故障码 0=无故障 | error code
    eDirOut : E_DL_FatigueDir;             // 当前走向观测 | current direction observation
END_VAR
VAR
    _eDir : E_DL_FatigueDir := eDirNone;   // 内部走向状态 | internal direction state
    _afRev : ARRAY[1..8] OF REAL;          // 反转点栈 [µε] | reversal point stack [µε]
    _iTop : INT;                           // 栈顶下标 0=空 | stack top index
    _k : INT;                              // 前移循环下标 | shift loop index
    _fExtreme : REAL;                      // 当前走向极值 [µε] | extreme in current run [µε]
    _fPushVal : REAL;                      // 待入栈反转点 [µε] | reversal to push [µε]
    _fR1 : REAL;                           // 内层循环幅值 [µε] | inner range [µε]
    _fR2 : REAL;                           // 外层循环幅值 [µε] | outer range [µε]
    _fN : REAL;                            // 该幅值对应寿命（循环数） | life at that range
    _xPush : BOOL;                         // 本拍有待入栈反转点 | pending push flag
    _xPair : BOOL;                         // 三点配对继续标志 | pairing continue flag
    _xInit : BOOL;                         // 首拍初始化完成 | first cycle done
    _xBad : BOOL;                          // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                       // 参数非法标志 | invalid parameter flag
    _rtReset : R_TRIG;                     // 复位上升沿 | reset rising edge
END_VAR

// ---- 无条件每周期调用：复位沿检测 ----
_rtReset(CLK := xReset);

// ---- 非有限检测 ----
_xBad := (fStrain <> fStrain) OR ((fStrain - fStrain) <> (fStrain - fStrain))
      OR (fDeadBand <> fDeadBand) OR ((fDeadBand - fDeadBand) <> (fDeadBand - fDeadBand));

// ---- 参数合法性：死区与 S-N 系数必须为正（两者都充当分母或判据） ----
_xBadPar := (fDeadBand <= 0.0) OR (fSnCoeff <= 0.0) OR (fDamageLimit <= 0.0);

// ---- 输出预置：损伤度为积分量，不做每拍清零 ----
xValid := NOT (_xBad OR _xBadPar);
iErrorCode := 0;
IF _xBad THEN
    iErrorCode := 1;
ELSIF _xBadPar THEN
    iErrorCode := 1;
END_IF

// ---- 首拍只记录极值，不产生任何循环 ----
IF NOT _xInit THEN
    _xInit := TRUE;
    _fExtreme := fStrain;
END_IF

IF xValid THEN
    // ---- 方向状态机：带死区的反转识别 ----
    _xPush := FALSE;
    _fPushVal := 0.0;
    CASE _eDir OF
        eDirNone:
            IF (fStrain - _fExtreme) > fDeadBand THEN
                _eDir := eDirUp;                       // 首次确立上升走向
                _fExtreme := fStrain;
            ELSIF (_fExtreme - fStrain) > fDeadBand THEN
                _eDir := eDirDown;                     // 首次确立下降走向
                _fExtreme := fStrain;
            END_IF

        eDirUp:
            IF fStrain > _fExtreme THEN
                _fExtreme := fStrain;                  // 刷新上升段高点
            ELSIF fStrain < (_fExtreme - fDeadBand) THEN
                _fPushVal := _fExtreme;                // 高点确认反转，待入栈
                _xPush := TRUE;
                _eDir := eDirDown;
                _fExtreme := fStrain;
            END_IF

        eDirDown:
            IF fStrain < _fExtreme THEN
                _fExtreme := fStrain;                  // 刷新下降段低点
            ELSIF fStrain > (_fExtreme + fDeadBand) THEN
                _fPushVal := _fExtreme;                // 低点确认反转，待入栈
                _xPush := TRUE;
                _eDir := eDirUp;
                _fExtreme := fStrain;
            END_IF

    ELSE
        _eDir := eDirNone;                             // 非法走向兜底重新定向
        _fExtreme := fStrain;
    END_CASE

    // ---- 入栈与三点配对 ----
    IF _xPush THEN
        IF _iTop >= 8 THEN
            // 栈满降级：丢弃最旧两点后仍继续入栈，并记录降级码
            FOR _k := 1 TO 6 DO
                _afRev[_k] := _afRev[_k + 2];
            END_FOR
            _iTop := 6;
            iErrorCode := 2;
        END_IF
        _iTop := _iTop + 1;
        _afRev[_iTop] := _fPushVal;

        _xPair := TRUE;
        WHILE _xPair AND (_iTop >= 3) DO
            _fR1 := ABS(_afRev[_iTop - 2] - _afRev[_iTop - 1]);
            _fR2 := ABS(_afRev[_iTop - 1] - _afRev[_iTop]);
            IF _fR2 >= _fR1 THEN
                // ---- 构成一个全循环，幅值 R1 ----
                IF _fR1 > 0.000001 THEN
                    _fN := fSnCoeff / _fR1;            // 分母已守卫
                    IF _fN < 1.0 THEN
                        _fN := 1.0;                    // 寿命下限 1 次，防损伤爆炸
                    END_IF
                    fDamageAcc := fDamageAcc + 1.0 / _fN;   // 分母已守卫
                    iCycles := iCycles + 1;
                    IF _fR1 > fRangeMax THEN
                        fRangeMax := _fR1;
                    END_IF
                END_IF
                // ---- 弹出 A、B 两点：剩余元素整体前移两位 ----
                FOR _k := 1 TO (_iTop - 2) DO
                    _afRev[_k] := _afRev[_k + 2];
                END_FOR
                _iTop := _iTop - 2;
            ELSE
                _xPair := FALSE;                       // 不满足判据，退出配对循环
            END_IF
        END_WHILE
    END_IF

    // ---- 损伤超限锁存与唯一解除路径 ----
    IF fDamageAcc >= fDamageLimit THEN
        xOverDamage := TRUE;
    END_IF
    IF _rtReset.Q AND NOT xOverDamage THEN
        fDamageAcc := 0.0;                             // 无锁存时复位仅清计数器
        iCycles := 0;
        iStackLevel := 0;
    ELSIF _rtReset.Q AND xOverDamage THEN
        xOverDamage := FALSE;                          // 解除路径：复位上升沿
        fDamageAcc := 0.0;
        iCycles := 0;
        fRangeMax := 0.0;
        _iTop := 0;
        _eDir := eDirNone;
        _xInit := FALSE;
    END_IF
END_IF

iStackLevel := _iTop;
eDirOut := _eDir;
END_FUNCTION_BLOCK
