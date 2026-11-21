(*
  FC_DL_CubicSplineInterp  —  自然三次样条插值与斜率输出 / Natural cubic spline interpolation with slope output
  分类 Category : DL_MathData
  码位 Code     : 16#05_0_01
  版本 Version  : 1.0.0
  来源标签 Tag  : t2-1-lgf-math
  溯源 Source   : LGF Math 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码行
  功能 Function : 1) 自然三次样条（二阶导三对角求解，Thomas 追赶法，WHILE 带死锁计数器上限 = 节点数 + 1）；
                  2) 同时输出插值值与一阶导数（斜率），供曲线跟踪/前馈使用；
                  3) 越界不外推：钳到端点并置 bInRange := FALSE。
  边界 Boundary : ① nPointCount < 2 判无效；
                  ② 节点 X 非严格递增（含相等）拒绝求值并置码，不做静默排序；
                  ③ fQueryX 越界 → 钳到端点、bInRange := FALSE、不外推；
                  ④ 三对角主元近零（|主元| < 1E-12）判节点病态置码；
                  ⑤ 节点数超 nMaxNode 组态上限拒绝（防静态数组越界）；
                  ⑥ 节点坐标非有限（NaN/Inf）拒绝求值（FB32-7 保持槽非有限闸）。
  依赖 Depends  : 无（纯 IEC 61131-3 标准运算，零库内内核可委托；SQRT/MOD 原语未使用）

  码表 Error codes（本件格 05_0_01，子码步进 +0x10）:
    16#0005_0501 故障级：组态非法（节点数 < 2 / 节点数超 nMaxNode / 节点 X 非严格递增 / 主元近零病态 / 节点非有限）
    16#0005_0511 信息级：查询点越界已钳到端点且不外推（不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R36 首版入库（W1 窗次件）
*)

FUNCTION FC_DL_CubicSplineInterp : BOOL
VAR_INPUT
    afX        : ARRAY[0..63] OF LREAL;   // 节点横坐标表，要求严格递增 [任意工程单位] / Knot abscissa table, strictly increasing
    afY        : ARRAY[0..63] OF LREAL;   // 节点纵坐标表 [任意工程单位] / Knot ordinate table
    nPointCount : UINT := 0;              // 有效节点数 [个]，域 2 ~ nMaxNode / Effective knot count, domain 2..nMaxNode
    nMaxNode   : UINT := 64;              // 组态节点上限 [个]，域 2 ~ 64（静态数组上界保护）/ Configured max knot count
    fQueryX    : LREAL := 0.0;            // 查询横坐标 [任意工程单位] / Query abscissa
END_VAR
VAR_OUTPUT
    fOutY      : LREAL;                   // 插值结果 [任意工程单位]，无效时为 0 / Interpolated ordinate, 0 when invalid
    fOutSlope  : LREAL;                   // 一阶导数（斜率）[单位/单位]，无效时为 0 / First derivative, 0 when invalid
    bInRange   : BOOL;                    // 查询点是否落在节点区间内（FALSE 表示已钳到端点）/ Query inside knot span
    bValid     : BOOL;                    // 结果有效标志 / Result valid flag
    bError     : BOOL;                    // 故障标志，与故障级码配对 / Fault flag paired with fault code
    nErrId     : UDINT;                   // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    nCount     : INT;                                  // 生效节点数整型副本 [个] / Integer copy of knot count
    nLast      : INT;                                  // 末节点索引（nCount - 1）[1] / Last knot index
    i          : INT;                                  // 三对角求解行索引 [1] / Tridiagonal row index
    nGuard     : INT;                                  // 追赶快照死锁计数器 [1] / Back-substitution deadlock counter
    fHiPrev    : LREAL;                                // 左邻区间宽度 x[i]-x[i-1] [单位] / Left span width
    fHiNext    : LREAL;                                // 右邻区间宽度 x[i+1]-x[i] [单位] / Right span width
    fAlpha     : LREAL;                                // 追赶法右端项 [单位] / Thomas right-hand term
    fPivot     : LREAL;                                // 主元（对角元）[单位] / Pivot of tridiagonal system
    fQuery     : LREAL;                                // 生效查询横坐标（钳定后）[单位] / Effective (clamped) query abscissa
    fH         : LREAL;                                // 命中区间宽度 [单位] / Hit span width
    fA         : LREAL;                                // 左权 (x[i+1]-q)/h [1] / Left blend weight
    fB         : LREAL;                                // 右权 (q-x[i])/h [1] / Right blend weight
    nSeg       : INT;                                   // 命中区间左端索引 [1] / Hit span left index
    bFound     : BOOL;                                  // 区间查找命中标志 / Span found flag
    bMono      : BOOL;                                  // 节点严格递增检查标志 / Strict monotonic check flag
    bBad       : BOOL;                                  // 节点非有限标志 / Non-finite knot flag
    afM        : ARRAY[0..63] OF LREAL;                // 二阶导解向量 m[i] [单位] / Second derivative solution vector
    afL        : ARRAY[0..63] OF LREAL;                // 追赶法下对角 l[i] [单位] / Thomas lower diagonal
    afMu       : ARRAY[0..63] OF LREAL;                // 追赶法消元系数 mu[i] [1] / Thomas elimination coefficient
    afZ        : ARRAY[0..63] OF LREAL;                // 追赶法变换后右端 z[i] [单位] / Thomas transformed right-hand side
END_VAR
VAR CONSTANT
    DL_NODE_MIN : UINT  := 2;               // 节点数下限 [个]，单点无法定义斜率 / Minimum knot count
    DL_NODE_MAX : UINT  := 64;              // 节点数硬上限 [个]，等于数组上界 + 1 / Hard upper bound of knots
    DL_PIVOT_EPS : LREAL := 1.0E-12;       // 主元判零容差 [1]，低于此值判病态 / Pivot zero tolerance
    DL_EPS      : LREAL := 1.0E-12;        // 通用判零容差 [1] / Generic zero tolerance
END_VAR

(* —— 段 0：返回值与输出预置安全值 —— *)
FC_DL_CubicSplineInterp := FALSE;   // 返回布尔：FALSE = 本拍无有效结果
fOutY     := 0.0;                   // 插值结果预置 0
fOutSlope := 0.0;                   // 斜率预置 0
bInRange  := FALSE;                 // 区间内标志预置 FALSE
bValid    := FALSE;                 // 有效标志预置 FALSE
bError    := FALSE;                 // 故障标志预置 FALSE
nErrId    := 0;                     // 事件码预置 0
bFound    := FALSE;                 // 区间查找标志预置 FALSE
bMono     := TRUE;                  // 单调性假定成立
bBad      := FALSE;                 // 非有限假定不成立
nCount    := UINT_TO_INT(nPointCount);  // 节点数整型副本 [个]

(* —— 段 1：组态域闸（节点数与上限，先于任何数组访问） —— *)
IF (nCount < INT_TO_INT(DL_NODE_MIN)) OR (nCount > INT_TO_INT(DL_NODE_MAX)) THEN
    nErrId := 16#0005_0501;         // 故障级：节点数越 [2, 64] 域
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 域闸命中不求值
END_IF
IF (nMaxNode < DL_NODE_MIN) OR (nMaxNode > DL_NODE_MAX) THEN
    nErrId := 16#0005_0501;         // 故障级：组态上限越域
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 域闸命中不求值
END_IF
IF nPointCount > nMaxNode THEN
    nErrId := 16#0005_0501;         // 故障级：实际节点数超组态上限（防越界，不静默截断）
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 域闸命中不求值
END_IF
IF (fQueryX <> fQueryX) OR ((fQueryX - fQueryX) <> (fQueryX - fQueryX)) THEN
    nErrId := 16#0005_0501;         // 故障级：查询横坐标非有限
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 域闸命中不求值
END_IF
nLast := nCount - 1;                // 末节点索引 [1]

(* —— 段 2：节点表体检（严格递增 + 非有限），任一不满足拒绝求值 —— *)
FOR i := 0 TO nLast DO
    IF (afX[i] <> afX[i]) OR ((afX[i] - afX[i]) <> (afX[i] - afX[i])) THEN
        bBad := TRUE;               // 节点横坐标非有限
    END_IF
    IF (afY[i] <> afY[i]) OR ((afY[i] - afY[i]) <> (afY[i] - afY[i])) THEN
        bBad := TRUE;               // 节点纵坐标非有限
    END_IF
END_FOR
IF bBad THEN
    nErrId := 16#0005_0501;         // 故障级：节点表含非有限值
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 不求值
END_IF
FOR i := 1 TO nLast DO
    IF afX[i] - afX[i - 1] <= 0.0 THEN
        bMono := FALSE;             // 非严格递增（含相等与倒序）
    END_IF
END_FOR
IF NOT bMono THEN
    nErrId := 16#0005_0501;         // 故障级：节点 X 非严格递增，拒绝求值（不做静默排序）
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 不求值
END_IF

(* —— 段 3：自然样条二阶导求解（Thomas 追赶法，主元近零判病态） —— *)
afM[0] := 0.0;                      // 自然边界：首端二阶导为 0
afM[nLast] := 0.0;                  // 自然边界：末端二阶导为 0
afL[0] := 1.0;                      // 追赶法初值
afMu[0] := 0.0;                     // 追赶法初值
afZ[0] := 0.0;                      // 追赶法初值
FOR i := 1 TO (nLast - 1) DO
    fHiPrev := afX[i] - afX[i - 1];                                  // 左邻区间宽度 [单位]
    fHiNext := afX[i + 1] - afX[i];                                  // 右邻区间宽度 [单位]，递增性已证明 > 0
    fAlpha := 3.0 / fHiNext * (afY[i + 1] - afY[i]) - 3.0 / fHiPrev * (afY[i] - afY[i - 1]);  // 右端项
    fPivot := 2.0 * (afX[i + 1] - afX[i - 1]) - fHiPrev * afMu[i - 1];                        // 主元
    IF ABS(fPivot) < DL_PIVOT_EPS THEN
        nErrId := 16#0005_0501;     // 故障级：三对角主元近零，节点病态
        bError := TRUE;             // 故障标志置位（R45 配对）
        RETURN;                     // 不出结论
    END_IF
    afL[i] := fPivot;                                               // 保存消元主元
    afMu[i] := fHiNext / afL[i];                                    // 消元系数（主元已证明非零）
    afZ[i] := (fAlpha - fHiPrev * afZ[i - 1]) / afL[i];             // 变换后右端
END_FOR
afM[nLast] := 0.0;                  // 自然边界复核（末端）
nGuard := 0;                        // 死锁计数器清零
i := nLast - 1;                     // 回代起点
WHILE (i >= 1) AND (nGuard <= (nCount + 1)) DO
    afM[i] := afZ[i] - afMu[i] * afM[i + 1];                        // 回代求二阶导
    i := i - 1;                                                     // 索引递减
    nGuard := nGuard + 1;                                           // 死锁计数器自增
END_WHILE
IF nGuard > (nCount + 1) THEN
    nErrId := 16#0005_0501;         // 故障级：回代未在节点数 + 1 步内收敛（结构性防御）
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 不出结论
END_IF

(* —— 段 4：定位命中区间（线性查找，不外推：越界钳到端点） —— *)
fQuery := fQueryX;                  // 生效查询横坐标初值
IF fQueryX < afX[0] THEN
    fQuery := afX[0];               // 左越界钳到首端，不外推
    bInRange := FALSE;              // 标记越界
ELSIF fQueryX > afX[nLast] THEN
    fQuery := afX[nLast];           // 右越界钳到末端，不外推
    bInRange := FALSE;              // 标记越界
ELSE
    bInRange := TRUE;               // 落在节点区间内
END_IF
nSeg := 0;                          // 区间左端索引初值
FOR i := 0 TO (nLast - 1) DO
    IF (fQuery >= afX[i]) AND (fQuery <= afX[i + 1]) THEN
        nSeg := i;                  // 命中区间 [x[i], x[i+1]]
        bFound := TRUE;             // 查找命中
        EXIT;                       // 唯一区间（严格递增保证）
    END_IF
END_FOR
IF NOT bFound THEN
    nSeg := nLast - 1;              // 端点等值数值落空的兜底：取末区间
END_IF

(* —— 段 5：区间内求值与斜率（h 已证明 > 0，无除零风险） —— *)
fH := afX[nSeg + 1] - afX[nSeg];                                        // 命中区间宽度 [单位]
IF fH <= 0.0 THEN
    nErrId := 16#0005_0501;         // 故障级：命中区间宽度非正（数值退化）
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 不出结论
END_IF
fA := (afX[nSeg + 1] - fQuery) / fH;                                    // 左权 [1]
fB := (fQuery - afX[nSeg]) / fH;                                        // 右权 [1]
fOutY := fA * afY[nSeg] + fB * afY[nSeg + 1]
       + ((fA * fA * fA - fA) * afM[nSeg] + (fB * fB * fB - fB) * afM[nSeg + 1]) * fH * fH / 6.0;  // 插值结果
fOutSlope := (afY[nSeg + 1] - afY[nSeg]) / fH
           - (3.0 * fA * fA - 1.0) / 6.0 * fH * afM[nSeg]
           + (3.0 * fB * fB - 1.0) / 6.0 * fH * afM[nSeg + 1];           // 一阶导数

(* —— 段 6：结果非有限复检 + 越界信息码 + 有效标志 —— *)
IF (fOutY <> fOutY) OR ((fOutY - fOutY) <> (fOutY - fOutY)) THEN
    fOutY := 0.0;                   // 非有限复检兜底
    fOutSlope := 0.0;               // 斜率同步兜底
    nErrId := 16#0005_0501;         // 故障级：插值结果非有限
    bError := TRUE;                 // 故障标志置位（R45 配对）
    RETURN;                         // 不出结论
END_IF
IF NOT bInRange THEN
    nErrId := 16#0005_0511;         // 信息级：查询点越界已钳到端点（信息级不置 bError）
END_IF
bValid := TRUE;                     // 结果有效（越界钳定亦有效，但 bInRange 已置 FALSE 提示）
FC_DL_CubicSplineInterp := TRUE;    // 返回布尔：TRUE = 本拍有可交付结果
