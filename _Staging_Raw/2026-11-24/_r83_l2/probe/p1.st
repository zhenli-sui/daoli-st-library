FUNCTION_BLOCK FB_Probe
VAR_INPUT
    afA : ARRAY[0..3] OF LREAL := [1.0,2.0,3.0,4.0]; // 数组 / array
END_VAR
VAR_OUTPUT
    nLo : DINT; // 下界 / lower bound
    nHi : DINT; // 上界 / upper bound
END_VAR
    nLo := LOWER_BOUND(afA, 1); // 固定长数组取下界 / lower bound of a fixed array
    nHi := UPPER_BOUND(afA, 1); // 固定长数组取上界 / upper bound of a fixed array
END_FUNCTION_BLOCK
