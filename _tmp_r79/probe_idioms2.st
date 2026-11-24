TYPE E_DL_ProbeState :
(
    eIdle := 0,          // 空闲 / idle
    eRun := 1            // 运行 / run
);
END_TYPE

FUNCTION FC_DL_ProbeD : UDINT
VAR_INPUT
    aData : ARRAY[1..16] OF BYTE;    // 字节块 / byte block
    nLen : INT;                      // 长度 / length
END_VAR
VAR_OUTPUT
    eErr : UDINT;                    // 错误码 / error id
    bError : BOOL;                   // 故障标志 / fault flag
END_VAR
VAR
    nSum1 : UDINT;                   // 和 1 / sum one
    nSum2 : UDINT;                   // 和 2 / sum two
    nByte : UDINT;                   // 字节值 / byte value
    nWord : UDINT;                   // 字值 / word value
    nLo : UDINT;                     // 低字节 / low byte
    nHi : UDINT;                     // 高字节 / high byte
    bTmp : BYTE;                     // 字节中间量 / byte intermediate
    i : INT;                         // 索引 / index
    nUse : INT;                      // 有效长度 / effective length
END_VAR
VAR CONSTANT
    DL_MOD : UDINT := 255;           // 模数 / modulus
    DL_SHIFT : UDINT := 8;           // 移位量 / shift amount
END_VAR
eErr := 0;
bError := FALSE;
nSum1 := 0;
nSum2 := 0;
nUse := nLen;
IF nUse < 0 THEN
    nUse := 0;
ELSIF nUse > 16 THEN
    nUse := 16;
END_IF
FOR i := 1 TO nUse DO
    nByte := BYTE_TO_UDINT(aData[i]);
    nSum1 := (nSum1 + nByte) MOD DL_MOD;
    nSum2 := (nSum2 + nSum1) MOD DL_MOD;
END_FOR
nLo := BYTE_TO_UDINT(aData[1]);
nHi := BYTE_TO_UDINT(aData[2]);
nWord := nLo + nHi * 256;
bTmp := UDINT_TO_BYTE(nWord MOD DL_MOD);
FC_DL_ProbeD := (nSum2 * 256 + nSum1) + BYTE_TO_UDINT(bTmp) + nWord * 0;
END_FUNCTION

FUNCTION_BLOCK FB_DL_ProbeE
VAR_INPUT
    bEnable : BOOL;                  // 使能 / enable
END_VAR
VAR_OUTPUT
    eState : E_DL_ProbeState;        // 状态 / state
END_VAR
VAR
    nIdx : UDINT;                    // 计数 / counter
    nA : UDINT;                      // 无符号一 / unsigned one
    nB : UDINT;                      // 无符号二 / unsigned two
    nQ : DINT;                       // 有符号商 / signed quotient
    nR : DINT;                       // 有符号余 / signed remainder
END_VAR
VAR CONSTANT
    DL_DINT_MIN_P : DINT := -2147483648;  // 下界 / lower bound
    DL_DINT_MAX_P : DINT := 2147483647;   // 上界 / upper bound
END_VAR
eState := eIdle;
nA := 16#FFFF_FFFF;
nB := 0;
IF bEnable THEN
    eState := eRun;
    nB := nA / 2;
    nIdx := nA - nB;
    IF (nIdx > 1000) AND (nIdx < 16#FFFF_FFFF) THEN
        nQ := UDINT_TO_DINT(nIdx);
        nR := nQ MOD 7;
    END_IF
END_IF
IF (nQ = DL_DINT_MIN_P) OR (nR = DL_DINT_MAX_P) THEN
    eState := eIdle;
END_IF
IF eState = eRun THEN
    nIdx := nIdx + 1;
END_IF
END_FUNCTION_BLOCK
