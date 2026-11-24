// FC_DL_QuartileCalc v1.0.0
// 开源溯源：self-cleanroom / 统计族补口
(*
  道莅工业代码库 | DL_MathData | FC_DL_QuartileCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 四分位数 Q1/Q2/Q3 计算（数据升序排序后线性插值口径：
        位置 p = 1 + k·(n-1)/4，k=1,2,3，相邻两元素加权）
  邻件关系: 与 PercentileLReal / PercentileRank（百分位单值/排名）同族 ——
            差异点：本件一次返回三值（Q1/Q2/Q3），口径为四分位专用，
            排序基准一致（升序），码位独立（16#0002_1D01）
  数组契约: aData 为显式上界 100 的定长数组，nCount 为有效元素数（1..100），
            超界元素忽略；内部复制工作副本，不改调用方数组
*)
FUNCTION FC_DL_QuartileCalc : BOOL
VAR_INPUT
    aData  : ARRAY[1..100] OF REAL;              // 输入数据（前 nCount 个有效）[工程单位] / Input data, first nCount valid
    nCount : INT;                                // 有效元素数 [个]，域 1..100 / Valid element count, domain 1..100
END_VAR
VAR_OUTPUT
    fQ1     : REAL;                              // 下四分位 Q1 [工程单位] / First quartile
    fQ2     : REAL;                              // 中位数 Q2 [工程单位] / Median
    fQ3     : REAL;                              // 上四分位 Q3 [工程单位] / Third quartile
    bValid  : BOOL;                              // 结果有效回执 [-] / Result validity receipt
    uErrorId: UDINT;                             // 事件码，0 = 无事件；16#0002_1D01 = 计数非法 / Event code
END_VAR
VAR
    aWork   : ARRAY[1..100] OF REAL;             // 排序工作副本 [工程单位] / Working copy for sorting
    n       : INT;                               // 生效元素数 [个] / Effective count
    i       : INT;                               // 冒泡外层索引 [次] / Bubble outer index
    j       : INT;                               // 冒泡内层索引 [次] / Bubble inner index
    fSwap   : REAL;                              // 交换暂存 [工程单位] / Swap temp
    fPos    : REAL;                              // 四分位实数位置 [1] / Quartile real position
    nLo     : INT;                               // 位置下邻索引 [1] / Position lower index
    nHi     : INT;                               // 位置上邻索引 [1] / Position upper index
    fFrac   : REAL;                              // 插值份额 ∈ [0,1] [1] / Interpolation fraction
END_VAR

// —— 段 0：全路径缺省 —— //
fQ1 := 0.0;                                      // Q1 缺省零 / Q1 default
fQ2 := 0.0;                                      // Q2 缺省零 / Q2 default
fQ3 := 0.0;                                      // Q3 缺省零 / Q3 default
bValid := FALSE;                                 // 有效回执预清 / Validity preset
uErrorId := 16#0000;                             // 事件码预清 / Event code preset
FC_DL_QuartileCalc := FALSE;                     // 返回值缺省 FALSE / Return default FALSE

// —— 段 1：计数域闸（下标判界，R4） —— //
IF (nCount < 1) OR (nCount > 100) THEN           // 计数越出 1..100 / Count out of bounds
    uErrorId := 16#0002_1D01;                    // 信息级：计数非法（不置 bError） / Info level: illegal count
    RETURN;                                      // 不计算返回 / Return without computation
END_IF
n := nCount;                                     // 生效计数 / Effective count

// —— 段 2：复制工作副本（防调用方数组被改序） —— //
FOR i := 1 TO n DO                                // 逐元素复制（下标 i ≤ n ≤ 100 判界安全）/ Copy elements, index safe
    aWork[i] := aData[i];
END_FOR

// —— 段 3：冒泡升序排序（n ≤ 100，O(n²) 可接受） —— //
FOR i := 1 TO (n - 1) DO                          // 外层趟数 / Outer passes
    FOR j := 1 TO (n - i) DO                      // 内层相邻比较 / Inner adjacent compares
        IF aWork[j] > aWork[j + 1] THEN           // 升序交换 / Ascending swap
            fSwap := aWork[j];
            aWork[j] := aWork[j + 1];
            aWork[j + 1] := fSwap;
        END_IF
    END_FOR
END_FOR

// —— 段 4：单元素特判（四分位退化全等于该值，防 nLo 越界） —— //
IF n = 1 THEN                                     // 单元素：Q1=Q2=Q3 / Single element: all quartiles equal
    fQ1 := aWork[1];
    fQ2 := aWork[1];
    fQ3 := aWork[1];
    bValid := TRUE;
    FC_DL_QuartileCalc := TRUE;
    RETURN;
END_IF

// —— 段 5：线性插值四分位（位置法 p = 1 + k(n-1)/4） —— //
FOR i := 1 TO 3 DO                                // k = 1..3 依次算 Q1/Q2/Q3 / k=1..3 for Q1/Q2/Q3
    fPos := 1.0 + DINT_TO_REAL(i) * DINT_TO_REAL(n - 1) / 4.0;   // 实数位置 [1] / Real position
    nLo := REAL_TO_DINT(fPos);                    // 向零截断取下邻 / Truncate to lower index
    IF DINT_TO_REAL(nLo) > fPos THEN              // 截断上偏修正（负值域防御）/ Truncation correction
        nLo := nLo - 1;
    END_IF
    IF nLo < 1 THEN
        nLo := 1;                                 // 下界钳位 / Clamp low
    END_IF
    IF nLo > (n - 1) THEN
        nLo := n - 1;                             // 上邻必存在的上界钳位 / Clamp so upper neighbor exists
    END_IF
    nHi := nLo + 1;                               // 上邻索引 ≤ n 判界安全 / Upper neighbor safe
    fFrac := fPos - DINT_TO_REAL(nLo);            // 插值份额 / Interpolation fraction
    IF fFrac < 0.0 THEN
        fFrac := 0.0;                             // 份额下钳 / Fraction clamp low
    END_IF
    IF fFrac > 1.0 THEN
        fFrac := 1.0;                             // 份额上钳 / Fraction clamp high
    END_IF
    IF i = 1 THEN
        fQ1 := aWork[nLo] + fFrac * (aWork[nHi] - aWork[nLo]);   // Q1 插值 / Q1 interpolation
    ELSIF i = 2 THEN
        fQ2 := aWork[nLo] + fFrac * (aWork[nHi] - aWork[nLo]);   // Q2 插值 / Q2 interpolation
    ELSE
        fQ3 := aWork[nLo] + fFrac * (aWork[nHi] - aWork[nLo]);   // Q3 插值 / Q3 interpolation
    END_IF
END_FOR
bValid := TRUE;                                   // 有效回执 / Validity receipt
FC_DL_QuartileCalc := TRUE;                       // 返回成功 / Return success
END_FUNCTION
