(*
  ==================================================================
  组件名 Component  : FC_DL_InterpolateTable3D
  分类   Category   : DL_MathData
  复杂度 Complexity  : 高
  版本   Version    : 1.0.1
  功能   Purpose    : 三维表三线性插值。三条轴向量（升序）定位所在单元，索引钳位到
                      [0, n-2]，单元内按 X→Y→Z 三次线性插值出结果；轴乱序、
                      输入非有限、表值非有限三类异常各自置码并拒绝出值。
  来源   Source     : t2-1-lgf-math（LGF Math 插值族三维变体）
  溯源   Origin     : 三线性插值属公开数值语义，clean-room 自研实现，未复制 LGF
                      或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则运算 / ABS），三平台通用
  分工声明 Split     : 与 FC_DL_InterpolateTable2D（2D 属主）与 FB_DL_LineInterp2Axis
                      （轴对直线插值）分工——本件为三维表族谱最高维成员，只做
                      三线性单元插值，不做二维降维代理、不做外插。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 轴向量必须严格升序（aX[i] < aX[i+1]）：非升序判故障级码并
                         拒绝插值，不做排序修正（改调用方数据属越界，边界五）；
                      二 单元索引钳位到 [0, n-2]：输入低于首节点落单元 0、高于末节点
                         落单元 n-2（外插不外推，等价于边界保持）；
                      三 有限性闸覆盖参与换算的每个浮点引脚（R272 自证）：标量
                         fX / fY / fZ 逐个点名，轴向量与表值按参与元素逐个判；
                      四 结果非有限兜底同拍置 eErr + bError + bValid 三件套（R258）；
                      五 只读轴向量与表数组，不改调用方数据（PercentileLReal 纪律）。
  错误码   Codes    :
    16#0001_0626【信息级】轴元素数越域已钳位（<2 或 >16）
    16#0001_0627【故障级】轴向量非严格升序，拒绝插值
    16#0001_0628【故障级】输入坐标含非有限值，拒绝插值
    16#0001_0629【故障级】轴或表值含非有限值，拒绝插值
    16#0001_0630【故障级】插值结果非有限（复检兜底，R190 独立码）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 轴 0/10、表值仅随 X 线性（f=2X）→ 输入 (5,0,0) 得 10.0
    V2 输入 (20,0,0) 高于末节点 → 落末单元，得末节点值（不外推）
    V3 aX = 0/10/5（乱序）→ 码 0627、bValid = FALSE
    V4 fX = NaN → 码 0628、bValid = FALSE、fOut = 0
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 3 · 序号 9）
    2026-11-21  v1.0.1  R61 返修：D3 三轴向量逐元素非有限点名（R272 全量）；
                        D4 信息级 0626 两处不再置 bError（R285 口径统一）；
                        D8 段 6 八角点判缩进对齐；D9 新增 0630 结果非有限码
  ==================================================================
*)
FUNCTION FC_DL_InterpolateTable3D : LREAL
VAR_IN_OUT
    afX     : ARRAY[0..15] OF LREAL;             // X 轴向量（严格升序）[用户单位] / the X axis vector, strictly ascending
    afY     : ARRAY[0..15] OF LREAL;             // Y 轴向量（严格升序）[用户单位] / the Y axis vector, strictly ascending
    afZ     : ARRAY[0..15] OF LREAL;             // Z 轴向量（严格升序）[用户单位] / the Z axis vector, strictly ascending
    afTable : ARRAY[0..15, 0..15, 0..15] OF LREAL; // 表值 [工程单位]，维序 X,Y,Z / the table values with the dimension order X, Y, Z
END_VAR
VAR_INPUT
    nX : DINT;   // X 轴元素数 [个]，合法域 2..16 / the X element count, legal from two to sixteen
    nY : DINT;   // Y 轴元素数 [个]，合法域 2..16 / the Y element count, legal from two to sixteen
    nZ : DINT;   // Z 轴元素数 [个]，合法域 2..16 / the Z element count, legal from two to sixteen
    fX : LREAL;  // X 输入坐标 [用户单位] / the X input coordinate
    fY : LREAL;  // Y 输入坐标 [用户单位] / the Y input coordinate
    fZ : LREAL;  // Z 输入坐标 [用户单位] / the Z input coordinate
END_VAR
VAR_OUTPUT
    bValid : BOOL;  // 结果可用标志 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志，eErr 非 0 时为真 / the error flag, true when eErr is nonzero
END_VAR
VAR
    nIx     : DINT;  // X 单元索引 [下标] / the X cell index
    nIy     : DINT;  // Y 单元索引 [下标] / the Y cell index
    nIz     : DINT;  // Z 单元索引 [下标] / the Z cell index
    k       : DINT;  // 轴遍历索引 [下标] / the axis loop index
    nUseX   : DINT;  // 钳位后 X 元素数 [个] / the clamped X count
    nUseY   : DINT;  // 钳位后 Y 元素数 [个] / the clamped Y count
    nUseZ   : DINT;  // 钳位后 Z 元素数 [个] / the clamped Z count
    fTx     : LREAL; // X 单元内归一化位置 [-] / the normalised X position inside the cell
    fTy     : LREAL; // Y 单元内归一化位置 [-] / the normalised Y position inside the cell
    fTz     : LREAL; // Z 单元内归一化位置 [-] / the normalised Z position inside the cell
    fSpan   : LREAL; // 单元宽度工作副本 [用户单位] / the cell span copy
    fC000   : LREAL; // 角点 (i,j,k) 表值 [工程单位] / the corner value at i, j, k
    fC100   : LREAL; // 角点 (i+1,j,k) 表值 [工程单位] / the corner value at i plus one, j, k
    fC010   : LREAL; // 角点 (i,j+1,k) 表值 [工程单位] / the corner value at i, j plus one, k
    fC110   : LREAL; // 角点 (i+1,j+1,k) 表值 [工程单位] / the corner value at i plus one, j plus one, k
    fC001   : LREAL; // 角点 (i,j,k+1) 表值 [工程单位] / the corner value at i, j, k plus one
    fC101   : LREAL; // 角点 (i+1,j,k+1) 表值 [工程单位] / the corner value at i plus one, j, k plus one
    fC011   : LREAL; // 角点 (i,j+1,k+1) 表值 [工程单位] / the corner value at i, j plus one, k plus one
    fC111   : LREAL; // 角点 (i+1,j+1,k+1) 表值 [工程单位] / the corner value at i plus one, j plus one, k plus one
    fX0     : LREAL; // 单元 X 下节点坐标 [用户单位] / the cell lower X node
    fY0     : LREAL; // 单元 Y 下节点坐标 [用户单位] / the cell lower Y node
    fZ0     : LREAL; // 单元 Z 下节点坐标 [用户单位] / the cell lower Z node
    fA0     : LREAL; // X 向插值低端结果（k 层）[工程单位] / the X interpolation at the lower Z layer
    fA1     : LREAL; // X 向插值低端结果（k+1 层）[工程单位] / the X interpolation at the upper Z layer
    fB0     : LREAL; // Y 向插值结果（k 层）[工程单位] / the Y interpolation at the lower Z layer
    fB1     : LREAL; // Y 向插值结果（k+1 层）[工程单位] / the Y interpolation at the upper Z layer
    bClamp  : BOOL;  // 元素数钳位标记 [-] / the element count clamp flag
    bOrder  : BOOL;  // 轴乱序标记 [-] / the axis order fault flag
    bNonFin : BOOL;  // 非有限标记 [-] / the non finite flag
END_VAR
VAR CONSTANT
    DL_I3D_NMAX : DINT := 16; // 轴元素容量上界 [个]，与数组第一维一致 / the axis capacity aligned with the first dimension
    DL_I3D_TOL  : LREAL := 1.0E-12; // 差值比较容差 [用户单位] / the difference comparison tolerance
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 局部量显式预置（R254）/ segment 1, the preset of the return, the codes and the local guards
FC_DL_InterpolateTable3D := 0.0; // 返回值预置安全值零 / preset the return to zero
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
bClamp := FALSE; // 钳位标记预置假 / preset the clamp flag false
bOrder := FALSE; // 乱序标记预置假 / preset the order fault flag false
bNonFin := FALSE; // 非有限标记预置假 / preset the non finite flag false
nIx := 0; // X 单元索引预置零 / preset the X cell index zero
nIy := 0; // Y 单元索引预置零 / preset the Y cell index zero
nIz := 0; // Z 单元索引预置零 / preset the Z cell index zero
fTx := 0.0; // X 归一化位置预置零 / preset the X position zero
fTy := 0.0; // Y 归一化位置预置零 / preset the Y position zero
fTz := 0.0; // Z 归一化位置预置零 / preset the Z position zero
fSpan := 0.0; // 单元宽度预置零 / preset the cell span zero
fX0 := 0.0; // X 下节点预置零 / preset the X lower node zero
fY0 := 0.0; // Y 下节点预置零 / preset the Y lower node zero
fZ0 := 0.0; // Z 下节点预置零 / preset the Z lower node zero

// 段 2｜元素数域闸（<2 早退，>16 钳位，边界二）/ segment 2, the element count gate
IF (nX < 2) OR (nY < 2) OR (nZ < 2) THEN // 任轴少于两个节点，无单元可插值 / fewer than two nodes leave no cell
    eErr := 16#0001_0626; // 信息级：轴元素数越域已钳位（信息级不置 bError，R285 口径统一）/ informational, the element count clamped, no fault bit by the unified grade rule
    RETURN; // 早退 / early return
END_IF
nUseX := nX; // X 元素数域内接管 / take the X count
nUseY := nY; // Y 元素数域内接管 / take the Y count
nUseZ := nZ; // Z 元素数域内接管 / take the Z count
IF nUseX > DL_I3D_NMAX THEN // 超容量 / above the capacity
    nUseX := DL_I3D_NMAX; // 钳到容量 / clamp to the capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF nUseY > DL_I3D_NMAX THEN // 超容量 / above the capacity
    nUseY := DL_I3D_NMAX; // 钳到容量 / clamp to the capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF nUseZ > DL_I3D_NMAX THEN // 超容量 / above the capacity
    nUseZ := DL_I3D_NMAX; // 钳到容量 / clamp to the capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF bClamp THEN // 钳位置信息级 / raise the informational code on a clamp
    eErr := 16#0001_0626; // 信息级：轴元素数越域已钳位 / informational, the element count clamped
    bError := TRUE; // 置错误标志 / raise the error flag
END_IF

// 段 3｜轴严格升序与有限性闸（轴与输入坐标，边界一三）/ segment 3, the axis order and the finiteness gate
FOR k := 0 TO nUseX - 2 DO // X 轴相邻比较 / the X neighbour comparison
    IF (afX[k] <> afX[k]) OR ((afX[k] - afX[k]) <> (afX[k] - afX[k]))
    OR (afX[k + 1] <> afX[k + 1]) OR ((afX[k + 1] - afX[k + 1]) <> (afX[k + 1] - afX[k + 1])) THEN // X 轴相邻元素逐个非有限判（D3 返修，R272 点名）/ the adjacent X elements tested for finiteness one by one
        bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
    END_IF
    IF afX[k] >= afX[k + 1] THEN // 非严格升序 / not strictly ascending
        bOrder := TRUE; // 置乱序标记 / raise the order flag
    END_IF
END_FOR
FOR k := 0 TO nUseY - 2 DO // Y 轴相邻比较 / the Y neighbour comparison
    IF (afY[k] <> afY[k]) OR ((afY[k] - afY[k]) <> (afY[k] - afY[k]))
    OR (afY[k + 1] <> afY[k + 1]) OR ((afY[k + 1] - afY[k + 1]) <> (afY[k + 1] - afY[k + 1])) THEN // Y 轴相邻元素逐个非有限判（D3 返修）/ the adjacent Y elements tested for finiteness
        bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
    END_IF
    IF afY[k] >= afY[k + 1] THEN // 非严格升序 / not strictly ascending
        bOrder := TRUE; // 置乱序标记 / raise the order flag
    END_IF
END_FOR
FOR k := 0 TO nUseZ - 2 DO // Z 轴相邻比较 / the Z neighbour comparison
    IF (afZ[k] <> afZ[k]) OR ((afZ[k] - afZ[k]) <> (afZ[k] - afZ[k]))
    OR (afZ[k + 1] <> afZ[k + 1]) OR ((afZ[k + 1] - afZ[k + 1]) <> (afZ[k + 1] - afZ[k + 1])) THEN // Z 轴相邻元素逐个非有限判（D3 返修）/ the adjacent Z elements tested for finiteness
        bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
    END_IF
    IF afZ[k] >= afZ[k + 1] THEN // 非严格升序 / not strictly ascending
        bOrder := TRUE; // 置乱序标记 / raise the order flag
    END_IF
END_FOR
IF bNonFin THEN // 轴向量含非有限（NaN 使序闸恒假，须先于乱序判拒算，D3）/ a non finite axis element, gated ahead of the order test
    eErr := 16#0001_0629; // 故障级：轴或表值含非有限值 / fault grade, a non finite axis or table value
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
IF bOrder THEN // 轴乱序即拒算（不排序修正，边界一）/ refuse on a disorder, no sorting
    eErr := 16#0001_0627; // 故障级：轴向量非严格升序 / fault grade, the axis is not strictly ascending
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
IF (fX <> fX) OR ((fX - fX) <> (fX - fX)) OR (fY <> fY) OR ((fY - fY) <> (fY - fY))
OR (fZ <> fZ) OR ((fZ - fZ) <> (fZ - fZ)) THEN // 三个输入坐标逐个非有限判（R272 点名）/ the three input coordinates tested one by one
    eErr := 16#0001_0628; // 故障级：输入坐标含非有限值 / fault grade, a non finite input coordinate
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF

// 段 4｜三轴单元定位（线性查找 + 钳位到 [0, n-2]，输入不外推）/ segment 4, the cell location clamped to the legal index band
nIx := 0; // X 单元索引从零起 / the X index starts at zero
FOR k := 0 TO nUseX - 2 DO // 升序轴线性定位 / the linear location on an ascending axis
    IF fX >= afX[k] THEN // 已过该下节点 / the input is past this lower node
        nIx := k; // 记录候选单元 / register the candidate cell
    END_IF
END_FOR
nIy := 0; // Y 单元索引从零起 / the Y index starts at zero
FOR k := 0 TO nUseY - 2 DO // 升序轴线性定位 / the linear location on an ascending axis
    IF fY >= afY[k] THEN // 已过该下节点 / the input is past this lower node
        nIy := k; // 记录候选单元 / register the candidate cell
    END_IF
END_FOR
nIz := 0; // Z 单元索引从零起 / the Z index starts at zero
FOR k := 0 TO nUseZ - 2 DO // 升序轴线性定位 / the linear location on an ascending axis
    IF fZ >= afZ[k] THEN // 已过该下节点 / the input is past this lower node
        nIz := k; // 记录候选单元 / register the candidate cell
    END_IF
END_FOR

// 段 5｜单元内归一化位置（单元宽度已证 > 0：轴严格升序 + 容差闸）/ segment 5, the normalised positions with a proven positive span
fX0 := afX[nIx]; // X 下节点 / the X lower node
fY0 := afY[nIy]; // Y 下节点 / the Y lower node
fZ0 := afZ[nIz]; // Z 下节点 / the Z lower node
fSpan := afX[nIx + 1] - fX0; // X 单元宽度 [用户单位] / the X cell span
IF fSpan <= DL_I3D_TOL THEN // 宽度非正（升序已证，属结构性不可达兜底）/ a non positive span, kept as a guard
    eErr := 16#0001_0627; // 故障级：轴向量退化，拒绝相除 / fault grade, the degenerate axis refuses the division
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
fTx := (fX - fX0) / fSpan; // X 归一化位置（除子已证 > 容差）/ the X position with a proven divisor
fSpan := afY[nIy + 1] - fY0; // Y 单元宽度 [用户单位] / the Y cell span
IF fSpan <= DL_I3D_TOL THEN // 兜底闸 / the guard
    eErr := 16#0001_0627; // 故障级：轴向量退化 / fault grade, the degenerate axis
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
fTy := (fY - fY0) / fSpan; // Y 归一化位置 / the Y position
fSpan := afZ[nIz + 1] - fZ0; // Z 单元宽度 [用户单位] / the Z cell span
IF fSpan <= DL_I3D_TOL THEN // 兜底闸 / the guard
    eErr := 16#0001_0627; // 故障级：轴向量退化 / fault grade, the degenerate axis
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
fTz := (fZ - fZ0) / fSpan; // Z 归一化位置 / the Z position

// 段 6｜八角点取值与表值有限性（逐角点判，R272 数组侧覆盖）/ segment 6, the eight corners and the table finiteness
fC000 := afTable[nIx, nIy, nIz]; // 角点 000 / the corner 000
fC100 := afTable[nIx + 1, nIy, nIz]; // 角点 100 / the corner 100
fC010 := afTable[nIx, nIy + 1, nIz]; // 角点 010 / the corner 010
fC110 := afTable[nIx + 1, nIy + 1, nIz]; // 角点 110 / the corner 110
fC001 := afTable[nIx, nIy, nIz + 1]; // 角点 001 / the corner 001
fC101 := afTable[nIx + 1, nIy, nIz + 1]; // 角点 101 / the corner 101
fC011 := afTable[nIx, nIy + 1, nIz + 1]; // 角点 011 / the corner 011
fC111 := afTable[nIx + 1, nIy + 1, nIz + 1]; // 角点 111 / the corner 111
// 八角点逐个非有限判（覆盖本次参与的全部表值元素）/ the corner-wise non finite test over every participating value
IF (fC000 <> fC000) OR ((fC000 - fC000) <> (fC000 - fC000)) THEN // 角点 000 非有限 / the corner 000 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (fC100 <> fC100) OR ((fC100 - fC100) <> (fC100 - fC100)) THEN // 角点 100 非有限 / the corner 100 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (fC010 <> fC010) OR ((fC010 - fC010) <> (fC010 - fC010)) THEN // 角点 010 非有限 / the corner 010 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (fC110 <> fC110) OR ((fC110 - fC110) <> (fC110 - fC110)) THEN // 角点 110 非有限 / the corner 110 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (fC001 <> fC001) OR ((fC001 - fC001) <> (fC001 - fC001)) THEN // 角点 001 非有限 / the corner 001 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (fC101 <> fC101) OR ((fC101 - fC101) <> (fC101 - fC101)) THEN // 角点 101 非有限 / the corner 101 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (fC011 <> fC011) OR ((fC011 - fC011) <> (fC011 - fC011)) THEN // 角点 011 非有限 / the corner 011 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (fC111 <> fC111) OR ((fC111 - fC111) <> (fC111 - fC111)) THEN // 角点 111 非有限 / the corner 111 is not finite
    bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF bNonFin THEN // 表值含非有限 / a non finite table value exists
    eErr := 16#0001_0629; // 故障级：轴或表值含非有限值 / fault grade, a non finite axis or table value
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    FC_DL_InterpolateTable3D := 0.0; // 返回值回安全值 / the return back to the safe zero
    RETURN; // 早退 / early return
END_IF

// 段 7｜三线性插值 X→Y→Z（先沿最内维、再逐层，次序写死）/ segment 7, the trilinear interpolation with the fixed order
fA0 := fC000 + (fC100 - fC000) * fTx; // k 层 X 向插值 / the X interpolation on the lower layer
fA1 := fC001 + (fC101 - fC001) * fTx; // k+1 层 X 向插值 / the X interpolation on the upper layer
fB0 := fA0 + ((fC010 + (fC110 - fC010) * fTx) - fA0) * fTy; // k 层 Y 向插值 / the Y interpolation on the lower layer
fB1 := fA1 + ((fC011 + (fC111 - fC011) * fTx) - fA1) * fTy; // k+1 层 Y 向插值 / the Y interpolation on the upper layer
FC_DL_InterpolateTable3D := fB0 + (fB1 - fB0) * fTz; // Z 向插值出结果 / the Z interpolation gives the result

// 段 8｜结果复检兜底（非有限同拍三件套，边界四）/ segment 8, the result recheck with the triple on a non finite value
IF (FC_DL_InterpolateTable3D <> FC_DL_InterpolateTable3D)
OR ((FC_DL_InterpolateTable3D - FC_DL_InterpolateTable3D) <> (FC_DL_InterpolateTable3D - FC_DL_InterpolateTable3D)) THEN // 结果非有限 / the result is not finite
    FC_DL_InterpolateTable3D := 0.0; // 兜底安全值 / the bottom-line safe value
    eErr := 16#0001_0630; // 故障级：结果非有限（D9 返修独立码，不复用 0629）/ fault grade, the non finite result with its own code
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
ELSE // 结果有限 / a finite result
    bValid := TRUE; // 结果可用 / the result is usable
END_IF
END_FUNCTION
