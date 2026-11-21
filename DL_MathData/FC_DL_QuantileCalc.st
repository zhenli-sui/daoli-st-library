(*
  FC_DL_QuantileCalc  —  排序数组分位数（线性插值法） / Quantile of a sorted array by linear interpolation
  分类 Category : DL_MathData
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-math — 统计底座族零检索深化（P50/P95 工艺窗）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 对前 nCnt 个已升序元素计算分位数 fQ，落位索引 pos := (nCnt-1) × fQ；
                  2) 正好整除点（pos 与 TRUNC(pos) 差 < 1.0E-9）直接取位，置信息级 04A6；
                  3) 非整除点在相邻两元素间线性插值；
                  4) fQ 越界按 [0, 1] 钳位并置信息级 04A5（钳位后照常输出）。
  边界 Boundary : ① 判界先行：nCnt <= 0 或 > 32 → 故障级 03E2，直接出口；
                  ② 样本非有限（NaN 自反判 / Inf 差值自减判）→ 故障级 03E3，拒绝输出；
                  ③ 整除点判定禁浮点 = 判等，用容差 1.0E-9；
                  ④ 无 GVL 依赖：纯函数，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（TRUNC / ABS / LREAL 算术）
  码表 Error codes（段 0001，窗口 03E2~03E3 / 04A5~04A6）:
    16#0001_03E2 故障级：入参非法（nCnt <= 0 或 > 32），返回 0，bValid = FALSE，bError = TRUE
    16#0001_03E3 故障级：参与样本含非有限元素，返回 0，bValid = FALSE，bError = TRUE
    16#0001_04A5 信息级：fQ 越界已钳位至 [0, 1]（结果照常输出）
    16#0001_04A6 信息级：整除点直接取位（未插值）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 1 · 序号 5）
*)

FUNCTION FC_DL_QuantileCalc : LREAL
VAR_INPUT
    aSorted     : ARRAY[1..32] OF LREAL;   // 已升序样本数组 [EU]，前 nCnt 个参与 / Sorted samples, first nCnt used
    nCnt        : INT;               // 参与元素数 [个]，域 1..32 / Element count, 1..32
    fQ          : REAL;              // 分位数 [无量纲]，域 [0,1]，越界钳位 / Quantile, clamped to 0..1
END_VAR
VAR_OUTPUT
    eErr        : UDINT;             // 事件码，0 = 正常 / Event code
    bError      : BOOL;              // 故障级标志 / Fault-level flag
    bValid      : BOOL;              // 返回值是否可用 / Result usable flag
END_VAR
VAR
    fQc         : LREAL;             // 钳位后的分位数（LREAL 口径）/ Clamped quantile
    fPos        : LREAL;             // 落位索引 [索引] / Floating position index
    fLo         : LREAL;             // 落位整数部分 [索引] / Integer part of the position
    nLo         : INT;               // 下位索引（1 基）/ Lower index, one based
    nHi         : INT;               // 上位索引（1 基）/ Upper index, one based
    fFrac       : LREAL;             // 落位小数部分 [无量纲] / Fractional part
    i           : INT;               // 非有限扫描游标 [索引] / Scan cursor
    bClamped    : BOOL;              // 钳位发生标志 / Clamped flag
END_VAR
VAR CONSTANT
    DL_QTC_N_MAX      : INT := 32;               // 数组容量上限 [个] / Array capacity bound
    DL_QTC_TOL_IDX    : LREAL := 1.0E-9;         // 整除点判定容差 [索引] / Integer-point tolerance
    DL_QTC_ERR_IN     : UDINT := 16#0001_03E2;   // 故障级：nCnt 界外 / Fault: count out of range
    DL_QTC_ERR_NAN    : UDINT := 16#0001_03E3;   // 故障级：样本非有限 / Fault: non-finite sample
    DL_QTC_INFO_CLAMP : UDINT := 16#0001_04A5;   // 信息级：fQ 已钳位 / Info: quantile clamped
    DL_QTC_INFO_EXACT : UDINT := 16#0001_04A6;   // 信息级：整除点取位 / Info: exact index hit
END_VAR

(* —— 段 1｜返回值与错误状态预置 —— *)
FC_DL_QuantileCalc := 0.0;          // 缺省返回 0 / default return zero
eErr := 16#0000_0000;               // 预置无事件 / preset no event
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 预置不可用 / preset unusable
bClamped := FALSE;                  // 钳位标志清零 / clear clamp flag

(* —— 段 2｜判界先行：nCnt 域闸 —— *)
IF (nCnt <= 0) OR (nCnt > DL_QTC_N_MAX) THEN
    eErr := DL_QTC_ERR_IN;          // 故障级：nCnt 界外
    bError := TRUE;                 // 故障码配对置位（R101）
    bValid := FALSE;                // 结果不可用
    RETURN;                         // 直接出口 / early exit
END_IF

(* —— 段 3｜样本非有限闸：NaN 自反判 + Inf 差值自减判，逐元素扫描 —— *)
FOR i := 1 TO nCnt DO
    IF (aSorted[i] <> aSorted[i]) OR ((aSorted[i] - aSorted[i]) <> (aSorted[i] - aSorted[i])) THEN
        eErr := DL_QTC_ERR_NAN;     // 故障级：样本非有限
        bError := TRUE;             // 故障码配对置位（R101）
        bValid := FALSE;            // 结果不可用
        RETURN;                     // 直接出口 / early exit
    END_IF
END_FOR

(* —— 段 4｜fQ 钳位（越界不拒，钳位后照常输出 + 信息级） —— *)
fQc := LREAL(fQ);                   // REAL 升位到 LREAL 口径 / widen to LREAL
IF fQc < 0.0 THEN
    fQc := 0.0;                     // 下界钳位 / clamp low
    bClamped := TRUE;               // 钳位标志
ELSIF fQc > 1.0 THEN
    fQc := 1.0;                     // 上界钳位 / clamp high
    bClamped := TRUE;               // 钳位标志
END_IF

(* —— 段 5｜落位与插值：pos := (nCnt-1) × fQ，整除点直接取位（进位点） —— *)
fPos := INT_TO_LREAL(nCnt - 1) * fQc;   // 浮点落位 / floating position
fLo := TRUNC(fPos);                     // 整数部分 / integer part
nLo := LREAL_TO_INT(fLo) + 1;           // 1 基下位索引 / one-based lower index
fFrac := fPos - fLo;                    // 小数部分 / fractional part
IF fFrac < DL_QTC_TOL_IDX THEN
    FC_DL_QuantileCalc := aSorted[nLo]; // 整除点：直接取位（禁浮点 = 判等）/ exact hit
    eErr := DL_QTC_INFO_EXACT;          // 信息级：整除点取位 / info level
ELSIF nLo >= nCnt THEN
    FC_DL_QuantileCalc := aSorted[nCnt];    // 上边界防御：小数溢出取末位 / upper boundary defense
ELSE
    nHi := nLo + 1;                     // 上位索引 / upper index
    FC_DL_QuantileCalc := aSorted[nLo] + (aSorted[nHi] - aSorted[nLo]) * fFrac;
                                        // 线性插值 / linear interpolation
END_IF

(* —— 段 6｜出口 —— *)
IF bClamped THEN
    eErr := DL_QTC_INFO_CLAMP;      // 信息级：钳位提示（覆盖整除点信息级，钳位优先报告）/ info level
END_IF
bValid := TRUE;                     // 结果可用 / result usable
END_FUNCTION
