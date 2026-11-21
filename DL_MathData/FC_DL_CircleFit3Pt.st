(*==============================================================================
 * 组件名称 (Component)  : FC_DL_CircleFit3Pt
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（SQRT / ABS），零厂商私有库
 * 功能描述 (Function)   : 三点定圆（外接圆解析解，代数行列式法）：
 *                           D  = 2×[x1(y2−y3) + x2(y3−y1) + x3(y1−y2)]
 *                           Ux = [(x1²+y1²)(y2−y3) + (x2²+y2²)(y3−y1)
 *                                 + (x3²+y3²)(y1−y2)] ÷ D
 *                           Uy = [(x1²+y1²)(x3−x2) + (x2²+y2²)(x1−x3)
 *                                 + (x3²+y3²)(x2−x1)] ÷ D
 *                           R  = SQRT((x1−Ux)² + (y1−Uy)²)
 *                         |D| < 共线容差判三点共线（叉积绝对值判据），拒绝并置
 *                         故障码 eCollinear（防除零前置闸，规格指定）；非有限
 *                         输入 → 故障码 eNonFinite，输出哨兵 0。
 * 接口     (Interface)  : 输入 fX1/fY1/fX2/fY2/fX3/fY3 三点坐标 [mm]；
 *                         输出 fCx 圆心横坐标 [mm]、fCy 圆心纵坐标 [mm]、
 *                         fR 半径 [mm]、eErrCode 错误码（E_DL_CircFitErr）、
 *                         返回值 = 拟合有效标志（BOOL）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做三点定圆解析解，不做
 *                         多点最小二乘拟合、不做圆度评价**；多点拟合归
 *                         统计类件。
 *                         ② 共线闸：|D| = |2×叉积| < DL_CFT_COLMIN → 拒算
 *                         （D 作除数前置判，结构性无除零）；容差量纲随坐标
 *                         单位（mm 口径下 1E-9 对应亚纳米叉积面积），头注释
 *                         声明为「近共线拒算域」，非严格共线唯一判据。
 *                         ③ 非有限判据（R79 双判）：六坐标逐一 NaN 自反
 *                         x <> x 与 Inf 差自减 (x−x) <> (x−x)。
 *                         ④ R 非负结构性保证：平方和开方，无负数开方路径。
 *                         ⑤ 输出预置哨兵 0 早退（四段式：预置→域闸→内核→
 *                         结果复检），任何早退路径前输出已确定。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_CalcDistance3D` 分工：距离原语归那件、
 *                         三点定圆归本件；本件 SQRT 只用于半径合成（属主
 *                         内核例外申报：本件为圆拟合内核属主）。
 * 来源标签 (Source Tag) : 自研线（外接圆行列式公式为公开解析几何定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 返回 +
 *                         LREAL 三值 + ENUM 错误码；数字码位待主控收口阶段
 *                         统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 共线前置闸防除零 + 非有限双判 + 哨兵早退 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 1 · 序号 5）
 * 验收向量 (Acceptance) : ① 点 (0,0),(1,0),(0,1) → D=2.0，Ux=(0+1+0)/2=0.5，
 *                         Uy=(0+0+1)/2=0.5，R=SQRT(0.5)≈0.707106781186548，
 *                         返回 TRUE，eOk；② 点 (0,0),(1,1),(2,2) → D=2×
 *                         [0(1−2)+1(2−0)+2(0−1)]=0 → 共线拒绝，返回 FALSE，
 *                         eCollinear，三输出哨兵 0；③ x2=NaN → 返回 FALSE，
 *                         eNonFinite。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CircFitErr（错误码；故障级恒伴返回 FALSE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CircFitErr :
(
    eOk        := 0,   // 拟合成功 / Fit success
    eCollinear := 1,   // 故障级：三点共线（叉积绝对值低于容差） / Fault: three points collinear
    eNonFinite := 2    // 故障级：坐标非有限（NaN/Inf） / Fault: non-finite coordinate
);
END_TYPE

FUNCTION FC_DL_CircleFit3Pt : BOOL
VAR_INPUT
    fX1 : LREAL;                      // 点 1 横坐标 [mm] / Point 1 X coordinate [mm]
    fY1 : LREAL;                      // 点 1 纵坐标 [mm] / Point 1 Y coordinate [mm]
    fX2 : LREAL;                      // 点 2 横坐标 [mm] / Point 2 X coordinate [mm]
    fY2 : LREAL;                      // 点 2 纵坐标 [mm] / Point 2 Y coordinate [mm]
    fX3 : LREAL;                      // 点 3 横坐标 [mm] / Point 3 X coordinate [mm]
    fY3 : LREAL;                      // 点 3 纵坐标 [mm] / Point 3 Y coordinate [mm]
END_VAR
VAR_OUTPUT
    fCx      : LREAL;                 // 圆心横坐标（哨兵 0 于早退路径） [mm] / Centre X, sentinel zero on early exit [mm]
    fCy      : LREAL;                 // 圆心纵坐标 [mm] / Centre Y coordinate [mm]
    fR       : LREAL;                 // 外接圆半径 [mm] / Circumcircle radius [mm]
    eErrCode : E_DL_CircFitErr;       // 错误码出口 / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;                  // 六坐标非有限汇总 [-] / Non-finite aggregate flag
    _fD      : LREAL;                 // 行列式（2×叉积，除数） [mm²] / Determinant, 2 times cross product
    _fS1     : LREAL;                 // 点 1 平方和 x1²+y1² [mm²] / Point 1 squared norm
    _fS2     : LREAL;                 // 点 2 平方和 [mm²] / Point 2 squared norm
    _fS3     : LREAL;                 // 点 3 平方和 [mm²] / Point 3 squared norm
    _fUx     : LREAL;                 // 圆心横坐标中间量 [mm] / Centre X intermediate
    _fUy     : LREAL;                 // 圆心纵坐标中间量 [mm] / Centre Y intermediate
    _fDx     : LREAL;                 // 点 1 对圆心横差 [mm] / Point 1 to centre X difference
    _fDy     : LREAL;                 // 点 1 对圆心纵差 [mm] / Point 1 to centre Y difference
END_VAR
VAR CONSTANT
    DL_CFT_COLMIN : LREAL := 1.0E-9;  // 共线容差（|2×叉积| 低于此拒算，mm² 口径） [mm²] / Collinearity tolerance
    DL_CFT_ZERO   : LREAL := 0.0;     // 哨兵与非有限判零基准 [mm] / Sentinel and non-finite zero base
    DL_CFT_TWO    : LREAL := 2.0;     // 行列式系数 2 [-] / Determinant factor two
END_VAR

(* —— 段 0：出口预置安全值（四段式第一段：预置） —— *)
FC_DL_CircleFit3Pt := FALSE;          // 返回值预置无效 / Return preset invalid
fCx := DL_CFT_ZERO;                   // 圆心 X 哨兵 0 / Centre X sentinel
fCy := DL_CFT_ZERO;                   // 圆心 Y 哨兵 0 / Centre Y sentinel
fR := DL_CFT_ZERO;                    // 半径哨兵 0 / Radius sentinel
eErrCode := E_DL_CircFitErr.eNonFinite;   // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判：NaN 自反 + Inf 差自减，六坐标逐一） —— *)
_bNonFin := (fX1 <> fX1) OR ((fX1 - fX1) <> DL_CFT_ZERO)
         OR (fY1 <> fY1) OR ((fY1 - fY1) <> DL_CFT_ZERO)
         OR (fX2 <> fX2) OR ((fX2 - fX2) <> DL_CFT_ZERO)
         OR (fY2 <> fY2) OR ((fY2 - fY2) <> DL_CFT_ZERO)
         OR (fX3 <> fX3) OR ((fX3 - fX3) <> DL_CFT_ZERO)
         OR (fY3 <> fY3) OR ((fY3 - fY3) <> DL_CFT_ZERO);   // 非有限汇总 / Non-finite aggregate
IF _bNonFin THEN
    RETURN;                           // 早退保持哨兵与最严码 / Early exit with sentinel
END_IF

(* —— 段 2：行列式与共线闸（D 作除数前置判，结构性无除零） —— *)
_fD := DL_CFT_TWO * (fX1 * (fY2 - fY3) + fX2 * (fY3 - fY1) + fX3 * (fY1 - fY2));   // D = 2×叉积 / Determinant
IF ABS(_fD) < DL_CFT_COLMIN THEN
    eErrCode := E_DL_CircFitErr.eCollinear;       // 共线拒绝（故障级，伴返回 FALSE） / Collinear reject
    RETURN;                                       // 早退保持哨兵 / Early exit with sentinel
END_IF

(* —— 段 3：代数内核（分母 D 已过闸） —— *)
_fS1 := fX1 * fX1 + fY1 * fY1;        // 点 1 平方和 / Point 1 squared norm
_fS2 := fX2 * fX2 + fY2 * fY2;        // 点 2 平方和 / Point 2 squared norm
_fS3 := fX3 * fX3 + fY3 * fY3;        // 点 3 平方和 / Point 3 squared norm
_fUx := (_fS1 * (fY2 - fY3) + _fS2 * (fY3 - fY1) + _fS3 * (fY1 - fY2)) / _fD;   // 圆心 X 解析解 / Centre X closed form
_fUy := (_fS1 * (fX3 - fX2) + _fS2 * (fX1 - fX3) + _fS3 * (fX2 - fX1)) / _fD;   // 圆心 Y 解析解 / Centre Y closed form
_fDx := fX1 - _fUx;                   // 点 1 对圆心横差 / X difference to centre
_fDy := fY1 - _fUy;                   // 点 1 对圆心纵差 / Y difference to centre

(* —— 段 4：半径合成与结果复检（平方和非负，无负开方；复检非有限兜底） —— *)
fR := SQRT(_fDx * _fDx + _fDy * _fDy);   // 半径 = 点 1 到圆心距离 / Radius via squared sum
IF (fR <> fR) OR ((fR - fR) <> DL_CFT_ZERO) THEN
    fCx := DL_CFT_ZERO;               // 复检异常回哨兵（四段式第四段） / Recheck failed: sentinel
    fCy := DL_CFT_ZERO;               // 回哨兵 / Sentinel
    fR := DL_CFT_ZERO;                // 回哨兵 / Sentinel
    RETURN;                           // 保持最严码早退 / Early exit strictest code
END_IF
fCx := _fUx;                          // 圆心 X 出口 / Centre X outlet
fCy := _fUy;                          // 圆心 Y 出口 / Centre Y outlet
eErrCode := E_DL_CircFitErr.eOk;      // 成功码 / Success code
FC_DL_CircleFit3Pt := TRUE;           // 拟合有效 / Fit valid

END_FUNCTION
