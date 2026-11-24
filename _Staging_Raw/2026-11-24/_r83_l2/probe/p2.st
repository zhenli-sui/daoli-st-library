FUNCTION FC_P2 : DINT
VAR_IN_OUT
    aArr : ARRAY[*] OF LREAL; // 开数组 / open array
END_VAR
    FC_P2 := UPPER_BOUND(aArr, 1) + 1; // 上界+1 / upper bound plus one
END_FUNCTION
