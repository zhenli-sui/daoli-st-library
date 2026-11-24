FUNCTION FC_DL_ProbeA : LREAL
VAR_INPUT
    aPtsX : ARRAY[1..10] OF LREAL;   // 探针 X 数组 / probe X array
    aPtsY : ARRAY[1..10] OF LREAL;   // 探针 Y 数组 / probe Y array
    nCnt : INT;                      // 点数 / point count
END_VAR
VAR_OUTPUT
    eErr : UDINT;                    // 错误码 / error id
    bError : BOOL;                   // 故障标志 / fault flag
    bValid : BOOL;                   // 有效标志 / valid flag
END_VAR
VAR
    fSum : LREAL;                    // 累计 / accumulator
    fDx : LREAL;                     // 差值 / delta
    i : INT;                         // 索引 / index
    nB : UDINT;                      // 探针无符号 / probe unsigned
    nC : UDINT;                      // 探针无符号二 / probe unsigned two
    nD : UDINT;                      // 探针无符号三 / probe unsigned three
END_VAR
VAR CONSTANT
    DL_EPS : LREAL := 1.0E-9;        // 容差 / epsilon
    DL_MAX : UDINT := 16#FFFF_FFFF;  // 上限 / upper bound
END_VAR
fSum := 0.0;
eErr := 0;
bError := FALSE;
bValid := TRUE;
FOR i := 1 TO 10 DO
    fDx := aPtsX[i] - aPtsY[i];
    fSum := fSum + SQRT(fDx * fDx + DL_EPS);
END_FOR
nB := 123456;
nC := nB / 10;
nD := nB MOD 10;
IF nD > DL_MAX THEN
    bError := TRUE;
END_IF
IF EXPT(2.0, 3.0) > 7.0 THEN
    fSum := fSum + ATAN(1.0);
END_IF
FC_DL_ProbeA := fSum + LREAL_TO_REAL(fSum);
END_FUNCTION

FUNCTION FC_DL_ProbeB : UDINT
VAR_INPUT
    nVal : UDINT;                    // 探针输入 / probe input
END_VAR
VAR_OUTPUT
    eErr : UDINT;                    // 错误码 / error id
    bError : BOOL;                   // 故障标志 / fault flag
    bOverflow : BOOL;                // 溢出标志 / overflow flag
END_VAR
VAR
    nRoot : UDINT;                   // 试根 / trial root
    nIter : UDINT;                   // 迭代计数 / iteration counter
    fTmp : LREAL;                    // 探针实数 / probe real
END_VAR
nRoot := nVal;
nIter := 0;
WHILE (nIter < 64) AND (nRoot > 1) DO
    nRoot := nRoot / 2;
    nIter := nIter + 1;
END_WHILE
fTmp := TRUNC(LREAL_TO_REAL(1.5));
FC_DL_ProbeB := nRoot + LREAL_TO_UDINT(fTmp);
END_FUNCTION

FUNCTION_BLOCK FB_DL_ProbeC
VAR_INPUT
    bEnable : BOOL;                  // 使能 / enable
    bReset : BOOL;                   // 复位上升沿 / reset rising edge
    fSample : LREAL;                 // 样本 / sample
END_VAR
VAR_OUTPUT
    fMean : LREAL;                   // 均值 / mean
    nCount : UDINT;                  // 计数 / count
END_VAR
VAR
    rtReset : R_TRIG;                // 复位沿 / reset edge
    nStep : INT;                     // 内部状态 / internal state
    fSum : LREAL;                    // 累计 / accumulator
END_VAR
VAR CONSTANT
    DL_NAN_GUARD : LREAL := 1.0E308; // 有限上限 / finite ceiling
END_VAR
rtReset(CLK := bReset);
IF rtReset.Q THEN
    fSum := 0.0;
    nCount := 0;
    nStep := 0;
END_IF
CASE nStep OF
    0:
        IF bEnable THEN
            nStep := 10;
        END_IF
    10:
        IF NOT ((fSample <> fSample) OR (ABS(fSample) > DL_NAN_GUARD)) THEN
            fSum := fSum + fSample;
            nCount := nCount + 1;
            IF nCount > 0 THEN
                fMean := fSum / UDINT_TO_LREAL(nCount);
            END_IF
        END_IF
ELSE
    nStep := 0;
END_CASE
END_FUNCTION_BLOCK
