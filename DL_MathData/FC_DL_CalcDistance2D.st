(*
  ==================================================================
  组件名 Component  : FC_DL_CalcDistance2D
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : 2D 平面两点欧氏距离 √(Δx²+Δy²)：大坐标防溢出采用
                      Hypot 等价缩放思路——取 |Δ| 较大者为尺度因子 m，
                      d = m·√((Δx/m)² + (Δy/m)²)，平方项全部落在 1..2，
                      根号项 ≤ √2，杜绝 (1E154)² 型平方溢出。m=0（两点重
                      合）单分支直返 0，不进除法面。
  来源   Source     : t2-1-lgf-math（Hypot 缩放为公开数值方法口径
                      （C99 hypot 语义），实现零源码复制）
  互引   Cross-ref  : FC_DL_CalcDistance3D（同族三维距离件，本件为其平面
                      特例口径属主，二者共用「尺度缩放防溢出」方法论）
  平台   Platform   : 纯 IEC 61131-3 四则 + ABS/SQRT，三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 非有限闸 + 除零闸（m=0 分支）+ 缩放后非有限复核
                      /R5 全变量双语同行注释/R6 纯函数无状态机（CASE 不
                      适用）/R7 无定时器与沿检测/R8 阈值全常量化
  错误码 Codes      : 01【失效级】任一坐标非有限（NaN 自反判 / Inf 上限
                      兜底判），返回 0
                      02【失效级】缩放后中间量或结果非有限（结构性罕见
                      兜底），返回 0
  码位反证 Note     : 01/02 分立依据（R90）：01 在输入面、02 在数值面可
                      观测；02 若并入 01，则「输入全有限仍失败」这一病态
                      信号将不可观测，故必须分立。
  验收   Acceptance : V1 (0,0)-(3,4) → 5 ｜ V2 重合点 → 0（bValid）｜
                      V3 (1E300,0)-(0,1E300) → ≈1.414E300（不溢出）｜
                      V4 含 NaN → 码 01 ｜ V5 两坐标互换 → 距离不变
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 2 序 1）
  ==================================================================
*)
FUNCTION FC_DL_CalcDistance2D : LREAL
VAR_INPUT
    fX1    : LREAL;  // 点 1 横坐标 [mm]/[物理单位] / the x of point one
    fY1    : LREAL;  // 点 1 纵坐标 [mm]/[物理单位] / the y of point one
    fX2    : LREAL;  // 点 2 横坐标 [mm]/[物理单位] / the x of point two
    fY2    : LREAL;  // 点 2 纵坐标 [mm]/[物理单位] / the y of point two
END_VAR
VAR_OUTPUT
    bValid : BOOL;   // 距离可用标志 [-] / the distance usable flag
    nErrId : UDINT;  // 错误码，0=正常，01/02 见头注 [码] / the error code [code]
END_VAR
VAR
    fDx    : LREAL;  // 横向增量工作寄存器 / the delta x working register
    fDy    : LREAL;  // 纵向增量工作寄存器 / the delta y working register
    fAx    : LREAL;  // |Δx| 工作寄存器 / the abs delta x register
    fAy    : LREAL;  // |Δy| 工作寄存器 / the abs delta y register
    fScale : LREAL;  // 尺度因子 m = max(|Δx|,|Δy|) / the scale factor m
    fTmp   : LREAL;  // 缩放平方和工作寄存器 / the scaled squared sum register
END_VAR
VAR CONSTANT
    C2D_FIN_MAX  : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    C2D_ERR_NONE : UDINT := 16#0000_0000;           // 无错误 [码] / no error [code]
    C2D_ERR_NAN  : UDINT := 16#0000_0001;           // 码 01：输入非有限 / code 01, non finite input
    C2D_ERR_OVF  : UDINT := 16#0000_0002;           // 码 02：中间量/结果非有限 / code 02, non finite intermediate
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
FC_DL_CalcDistance2D := 0.0;  // 失效缺省返回 0 / fault default returns zero
bValid := FALSE;              // 预置不可用 / preset unusable
nErrId := C2D_ERR_NONE;       // 预置无错误 / preset no error

// 段 2｜输入非有限闸（码 01）：NaN 自反判 + Inf 上限兜底判 / segment 2, the input finite gate
IF (fX1 <> fX1) OR (fY1 <> fY1) OR (fX2 <> fX2) OR (fY2 <> fY2)
   OR (ABS(fX1) > C2D_FIN_MAX) OR (ABS(fY1) > C2D_FIN_MAX)
   OR (ABS(fX2) > C2D_FIN_MAX) OR (ABS(fY2) > C2D_FIN_MAX) THEN
    nErrId := C2D_ERR_NAN;
    RETURN;
END_IF

// 段 3｜增量与尺度因子（有限值之差仍可能溢出 Inf，段 4 复核）
//      segment 3, the deltas and the scale factor, the finite minus finite can still overflow
fDx := fX2 - fX1;                       // 横向增量 / the delta x
fDy := fY2 - fY1;                       // 纵向增量 / the delta y
fAx := ABS(fDx);                        // |Δx| / the abs delta x
fAy := ABS(fDy);                        // |Δy| / the abs delta y
IF fAx >= fAy THEN                      // 尺度因子取较大者 / the larger magnitude
    fScale := fAx;
ELSE
    fScale := fAy;
END_IF

// 段 4｜重合点分支（m=0 除零闸，直返 0）+ 增量非有限复核（码 01，Inf 归因输入面）
//      segment 4, the coincident point branch and the delta finiteness recheck
IF fScale = 0.0 THEN                    // 两点重合（Δx=Δy=0，零判安全：精确零源自精确相等）/ the coincident points
    FC_DL_CalcDistance2D := 0.0;        // 距离 0 / the zero distance
    bValid := TRUE;                     // 合法零距离 / the valid zero distance
    RETURN;
END_IF
IF (fDx <> fDx) OR (fDy <> fDy) OR (fScale <> fScale) OR (ABS(fDx) > C2D_FIN_MAX) OR (ABS(fDy) > C2D_FIN_MAX) THEN
    nErrId := C2D_ERR_NAN;              // 增量溢出为非有限 / the delta overflowed to non finite
    RETURN;
END_IF

// 段 5｜Hypot 缩放求距：d = m·√((Δx/m)² + (Δy/m)²)，平方项 ∈ 0..1
//      segment 5, the hypot scaled distance, the squared terms inside zero to one
fTmp := (fDx / fScale) * (fDx / fScale) + (fDy / fScale) * (fDy / fScale);  // 缩放平方和 ≤ 2 / the scaled squared sum
IF (fTmp <> fTmp) OR (fTmp < 0.0) OR (fTmp > 2.0000000001) THEN
    nErrId := C2D_ERR_OVF;              // 缩放后仍非有限（结构性罕见兜底）/ the non finite after scaling
    RETURN;
END_IF
FC_DL_CalcDistance2D := fScale * SQRT(fTmp);  // 距离 [mm]/[物理单位] / the distance
IF (FC_DL_CalcDistance2D <> FC_DL_CalcDistance2D) OR (ABS(FC_DL_CalcDistance2D) > C2D_FIN_MAX) THEN
    nErrId := C2D_ERR_OVF;              // 结果非有限复核 / the result finiteness recheck
    FC_DL_CalcDistance2D := 0.0;        // 失效回缺省 0 / fault default zero
    RETURN;
END_IF
bValid := TRUE;                         // 距离可用 / the distance is usable
END_FUNCTION
