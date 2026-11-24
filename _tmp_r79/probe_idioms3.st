FUNCTION FC_DL_ProbeF : DINT
VAR_INPUT
    nMonth : DINT;                   // 月 / month
    bLeap : BOOL;                    // 闰年 / leap year
END_VAR
VAR
    nDays : DINT;                    // 天数 / days
    i : DINT;                        // 索引 / index
    nSum : DINT;                     // 和 / sum
    nCnt : DINT;                     // 计数 / count
END_VAR
nDays := 0;
CASE nMonth OF
    1, 3, 5, 7, 8, 10, 12:
        nDays := 31;
    4, 6, 9, 11:
        nDays := 30;
    2:
        IF bLeap THEN
            nDays := 29;
        ELSE
            nDays := 28;
        END_IF
ELSE
    nDays := 0;
END_CASE
nSum := 0;
nCnt := 0;
FOR i := 1 TO 10 DO
    nCnt := nCnt + 1;
    IF nCnt > 5 THEN
        EXIT;
    END_IF
    nSum := nSum + i;
END_FOR
WHILE (nSum > 0) AND (nCnt < 30) DO
    nSum := nSum - 1;
    nCnt := nCnt + 1;
END_WHILE
IF (nDays = 0) THEN
    FC_DL_ProbeF := nSum;
    RETURN;
END_IF
FC_DL_ProbeF := nDays + nCnt;
END_FUNCTION
