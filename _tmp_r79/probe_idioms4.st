FUNCTION FC_DL_ProbeG : DINT
VAR_INPUT
    nA : DINT;                       // 输入 / input
END_VAR
VAR
    nB : DINT;                       // 中间量 / intermediate
    nC : DINT;                       // 中间量二 / second intermediate
END_VAR
nB := 1; nC := 2;
IF nA > 0 THEN
    nB := 3; nC := 4;
ELSE
    nB := 5; nC := 6;
END_IF
FC_DL_ProbeG := nB + nC;
END_FUNCTION
