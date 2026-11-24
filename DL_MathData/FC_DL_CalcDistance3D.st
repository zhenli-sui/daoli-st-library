(*==============================================================================
 * 组件名称 (Component)  : FC_DL_CalcDistance3D
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 几何计算函数（Function · Math / Pure function）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（SQRT / ABS / MAX），零厂商方言
 * 功能描述 (Function)   : 计算两点之间的三维欧氏距离，附带非有限值防护、
 *                         大数溢出缩放保护与三个分量差诊断输出。
 *                         平面（二维）距离不另设组件：把两个端点的 Z 坐标
 *                         同时填 0.0 即为其退化情形，规格明确禁止为凑数拆变体。
 *                         全程无内部状态，可任意频次调用。
 *
 * 【引脚契约 / Pin contract】
 *   输入 fX1 / fY1 / fZ1 : REAL — 点 1 的 X / Y / Z 坐标 [mm]，量程 ±1.0E6，
 *                                  平面场景把两个 Z 都填 0.0；
 *   输入 fX2 / fY2 / fZ2 : REAL — 点 2 的 X / Y / Z 坐标 [mm]，量程同上；
 *   输出 bValid          : BOOL — 六个输入全部有限（非 NaN、非无穷）= TRUE；
 *   输出 bSaturated      : BOOL — 本次计算进入大数缩放分支（结果仍然有效，
 *                                  但已落在置信区间，提示调用方复核量纲）；
 *   输出 fDeltaX/Y/Z     : REAL — 三个分量差 [mm]，便于现场诊断「差在哪个轴」；
 *   输出 uErrorId        : UDINT — 事件码，0 = 无。本件全部码为信息级。
 *   返回  值             : REAL — 距离 [mm]，恒非负；输入非法时返回 0.0。
 *
 * 【算法分步 / Algorithm steps（写死，防实现漂移）】
 *   ① 有限性闸门：六个输入任一非有限 → bValid FALSE、返回 0.0、置 0122 后早退。
 *      刻意**不返回 NaN**：NaN 会沿调用链污染下游滤波、比较与统计（历史教训）；
 *   ② 分量差：dX = X2 − X1（同 Y、Z），同时作为诊断输出；
 *   ③ 比例因子：fScale = MAX(|dX|, |dY|, |dZ|)，取最大分量作为量级基准；
 *   ④ 分支一（常规）：fScale 小于缩放阈值 → 直接 SQRT(dX² + dY² + dZ²)；
 *   ⑤ 分支二（缩放）：fScale 超阈值 → SQRT((dX/fScale)² + (dY/fScale)² +
 *      (dZ/fScale)²) × fScale。归一后每一项绝对值不超过 1，平方和不超过 3，
 *      彻底规避「大数先平方再开方」的中间溢出，结果为同一数学量的稳定写法；
 *   ⑥ 退化：三个分量差全为零（同一点）→ 返回 0.0 且不置任何码，因为距离为 0
 *      是合法结果而不是异常；
 *   ⑦ 后置守卫：最终结果非有限时（理论上不可达，防御性兜底）返回 0.0 并置 0122。
 *
 * 【数值安全 / Numeric safety】
 *   N1 非有限值用「区间比较取反」识别：NaN 参与任何有序比较均为假，故
 *      NOT(下限比较 AND 上限比较) 同时覆盖 NaN 与正负无穷，无需浮点判等；
 *   N2 缩放分支的分母恒大于阈值（阈值远大于 0），不存在除零；
 *   N3 平方和最多 3 项、每项不超过 1（缩放分支）或落在量程平方内（常规分支），
 *      不触碰 REAL 上界；
 *   N4 距离恒非负：SQRT 结果非负，早退路径返回 0.0，不存在负距离输出；
 *   N5 浮点判等红线：本件所有比较均为有序比较（小于 / 大于），唯一涉及「等于」
 *      的语义（同一点）由分量差与 0.0 做有序比较（小于容差）实现，不判等。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 输入非有限（任一轴）→ bValid FALSE、返回 0.0、置 0122、不输出分量差；
 *   B2 两点重合 → 返回 0.0、bValid TRUE、bSaturated FALSE、零码（合法值）；
 *   B3 坐标取负 → 差值平方后符号消失，结果与全正坐标一致（V5 验证）；
 *   B4 量级超阈值 → 走缩放分支、bSaturated TRUE、置 0219（信息级，结果可用）；
 *   B5 结果非有限（兜底）→ 返回 0.0、置 0122，绝不把无穷扩散到调用方；
 *   B6 平面场景（Z 同值）→ 第三个分量差为 0，平方项为 0，公式自动退化，
 *      不需要任何分支判断，也不需要单独的二维入口。
 *
 * 【单位与量纲 / Units】
 *   输入输出统一按 [mm] 声明；若调用方用 [m] 或 [deg] 注入，输出随之为同单位，
 *   本件不做任何单位换算（换算属于标定层职责）。坐标差值超过 ±1.0E6 时
 *   结果仍然正确，但 bSaturated 会提示「已进入缩放置信区」，供质量追溯。
 *
 * 【与既有件的职责边界 / Family separation】
 *   FC_DL_PolygonArea       = 多点多边形面积与质心（面量）；
 *   FC_DL_LineIntersection  = 两条直线求交点（线量）；
 *   FB_DL_ElectronicCam /
 *   FB_DL_GantrySyncAxis    = 运动耦合，与几何距离无关；
 *   本件                    = 两点之间距离（点量），本族唯一的点对点度量件。
 *
 * 【调用示例 / Call example（仅行注释，不嵌套块注释）】
 *   // 视觉引导取料：料框中心与吸嘴当前坐标的三维距离，超过 50 mm 拒绝动作
 *   // fDist := FC_DL_CalcDistance3D(fX1 := fNozzleX, fY1 := fNozzleY, fZ1 := fNozzleZ,
 *   //          fX2 := fTargetX, fY2 := fTargetY, fZ2 := fTargetZ,
 *   //          bValid => bGeomOk, bSaturated => bGeomScaled,
 *   //          fDeltaX => fDx, fDeltaY => fDy, fDeltaZ => fDz,
 *   //          uErrorId => uGeomErr);
 *   // IF (NOT bGeomOk) OR (fDist > 50.0) THEN
 *   //     bMoveEnable := FALSE;
 *   // END_IF
 *
 * 【平台移植注意 / Porting notes】
 *   SQRT 为标准函数，输入非负时三平台行为一致；本件通过缩放分支保证 SQRT 的
 *   入参不会因中间溢出变成负值或无穷；阈值与容差全部来自 VAR CONSTANT，
 *   换平台不需要改动逻辑区任何一行。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 视觉引导取料：吸嘴与目标点的三维偏差直接作为定位修正量；
 *   ② 三坐标 / 关节臂测点：两个测点之间的空间距离用于形位公差初筛；
 *   ③ 机器人安全距离：工具中心点与围栏采样点的距离，进入缩放区时提示复核；
 *   ④ 堆垛高度校核：料垛顶面采样点与理论平面的距离用于判定垛型合格。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1 平面退化：(0, 0, 0) 到 (3, 4, 0) → 5.0（勾股 3-4-5）；
 *   V2 三维：(0, 0, 0) 到 (2, 3, 6) → 7.0（4 + 9 + 36 = 49，开方 7）；
 *   V3 同点：(1, 1, 1) 到 (1, 1, 1) → 0.0、bValid TRUE、零码；
 *   V4 非有限：fX1 为 NaN → 0.0、bValid FALSE、uErrorId 0122；
 *   V5 负坐标：(−3, −4, 0) 到 (0, 0, 0) → 5.0（差值绝对值参与平方）；
 *   V6 大数缩放：分量差 2.0E18 → bSaturated TRUE、uErrorId 0219、结果仍有限。
 *
 * 【事件码表 / Event code table（全部信息级，不置报警位）】
 *   16#0001_0122  输入含非有限值，返回 0.0 且 bValid 置假；
 *   16#0001_0219  模长超缩放阈值，已按缩放式求模，结果有效但进入置信区。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 A · LGF Math 组）
 *============================================================================*)
FUNCTION FC_DL_CalcDistance3D : REAL
VAR_INPUT
    fX1 : REAL;                            // 点 1 X 坐标 [mm]，量程 ±1.0E6 / Point 1 X coordinate [mm], range plus or minus 1.0E6
    fY1 : REAL;                            // 点 1 Y 坐标 [mm] / Point 1 Y coordinate [mm]
    fZ1 : REAL;                            // 点 1 Z 坐标 [mm]，平面场景填 0.0 / Point 1 Z coordinate [mm], 0.0 for planar use
    fX2 : REAL;                            // 点 2 X 坐标 [mm] / Point 2 X coordinate [mm]
    fY2 : REAL;                            // 点 2 Y 坐标 [mm] / Point 2 Y coordinate [mm]
    fZ2 : REAL;                            // 点 2 Z 坐标 [mm] / Point 2 Z coordinate [mm]
END_VAR
VAR_OUTPUT
    bValid     : BOOL;                     // 六个输入全为有限值 / All six inputs are finite
    bSaturated : BOOL;                     // 进入大数缩放分支 / The scaling branch was used
    fDeltaX    : REAL;                     // X 分量差 [mm]，诊断用 / X component delta [mm], for diagnostics
    fDeltaY    : REAL;                     // Y 分量差 [mm]，诊断用 / Y component delta [mm], for diagnostics
    fDeltaZ    : REAL;                     // Z 分量差 [mm]，诊断用 / Z component delta [mm], for diagnostics
    uErrorId   : UDINT;                    // 事件码，0 = 无 / Event code, 0 = none
END_VAR
VAR
    _fScale    : REAL;                     // 最大分量绝对值 [mm]，量级基准 / Largest absolute component [mm], magnitude basis
    _fSumSq    : REAL;                     // 归一后平方和 [-] / Normalised sum of squares
    _fResult   : REAL;                     // 距离工作副本 [mm] / Working copy of the distance [mm]
    _bFinite   : BOOL;                     // 有限性闸门标志 / Finiteness gate flag
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS  : REAL  := 1.0E-6;       // 同点判定容差 [mm] / Coincident-point epsilon [mm]
    DL_INF_LIM    : REAL  := 1.0E37;       // 非有限值判据阈值，超此视为无穷 / Non-finite threshold, beyond is infinity
    DL_SCALE_THR  : REAL  := 1.0E18;       // 触发缩放的模长阈值 [mm] / Scaling threshold [mm]
    DL_DIST_ZERO  : REAL  := 0.0;          // 距离下界，恒非负 / Distance lower bound, never negative
    DL_ERR_NONFIN : UDINT := 16#0001_0122; // 输入非有限值的信息级码 / Info code for non-finite inputs
    DL_ERR_SCALED : UDINT := 16#0001_0219; // 已按缩放式求模的信息级码 / Info code for the scaled evaluation
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（函数必须先给出安全返回值）
 *      Preset the return value and the outputs
 *   返回值预置 0.0：任何早退路径都带「无距离」语义，绝不返回 NaN 或未初始化值。
 *-----------------------------------------------------------------------------*)
FC_DL_CalcDistance3D := DL_DIST_ZERO;      // 返回值预置 0（Return preset to zero）
bValid     := TRUE;                        // 有效性预置通过（Validity preset to pass）
bSaturated := FALSE;                       // 缩放标志预置（Scaling flag preset）
fDeltaX    := DL_DIST_ZERO;                // 分量差预置 0（Delta X preset to zero）
fDeltaY    := DL_DIST_ZERO;                // 分量差预置 0（Delta Y preset to zero）
fDeltaZ    := DL_DIST_ZERO;                // 分量差预置 0（Delta Z preset to zero）
uErrorId   := 16#0000_0000;                // 事件码预清零（Event code preset to zero）
_bFinite   := TRUE;                        // 有限性闸门预置通过（Finiteness gate preset to pass）

(*------------------------------------------------------------------------------
 * 段 2｜有限性闸门（边界 B1 / 数值安全 N1）
 *      Finiteness gate over the six coordinates
 *   NaN 与任何有序比较的结果均为假，故「比较区间取反」同时覆盖 NaN 与无穷。
 *-----------------------------------------------------------------------------*)
IF NOT ((fX1 <= DL_INF_LIM) AND (fX1 >= -DL_INF_LIM)) THEN   // X1 非有限（X1 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fY1 <= DL_INF_LIM) AND (fY1 >= -DL_INF_LIM)) THEN   // Y1 非有限（Y1 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fZ1 <= DL_INF_LIM) AND (fZ1 >= -DL_INF_LIM)) THEN   // Z1 非有限（Z1 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fX2 <= DL_INF_LIM) AND (fX2 >= -DL_INF_LIM)) THEN   // X2 非有限（X2 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fY2 <= DL_INF_LIM) AND (fY2 >= -DL_INF_LIM)) THEN   // Y2 非有限（Y2 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fZ2 <= DL_INF_LIM) AND (fZ2 >= -DL_INF_LIM)) THEN   // Z2 非有限（Z2 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF

IF NOT _bFinite THEN                       // 任一坐标不可判（Any coordinate undecidable）
    bValid   := FALSE;                     // 有效性置假（Validity cleared）
    uErrorId := DL_ERR_NONFIN;             // 置非有限值信息码（Raise the non-finite info code）
    RETURN;                                // 早退，返回值保持 0.0（Early exit, return stays zero）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜分量差计算（同时作为诊断输出，便于定位偏差轴）
 *      Component deltas, also exposed for diagnostics
 *-----------------------------------------------------------------------------*)
fDeltaX := fX2 - fX1;                      // X 分量差 [mm]（X delta）
fDeltaY := fY2 - fY1;                      // Y 分量差 [mm]（Y delta）
fDeltaZ := fZ2 - fZ1;                      // Z 分量差 [mm]（Z delta）

(*------------------------------------------------------------------------------
 * 段 4｜量级基准与分支选择（边界 B4 / 数值安全 N2）
 *      Magnitude basis and branch selection
 *   取最大分量绝对值作为量级基准：既用于同点判定，也用作缩放分母。
 *-----------------------------------------------------------------------------*)
_fScale := MAX(ABS(fDeltaX), MAX(ABS(fDeltaY), ABS(fDeltaZ)));  // 最大分量绝对值（Largest absolute component）

IF _fScale < DL_FLOAT_EPS THEN             // 三点差全在容差内，即同一点（Coincident points）
    FC_DL_CalcDistance3D := DL_DIST_ZERO;  // 同点距离为 0，属合法值（Zero distance, a legal result）
ELSIF _fScale <= DL_SCALE_THR THEN         // 常规量级，直接求模（Regular magnitude, direct evaluation）
    FC_DL_CalcDistance3D := SQRT(fDeltaX * fDeltaX
                               + fDeltaY * fDeltaY
                               + fDeltaZ * fDeltaZ);             // 直接平方和开方（Direct sum of squares）
ELSE                                       // 超阈值，走缩放分支（Above the threshold, scaled branch）
    _fResult := SQRT((fDeltaX / _fScale) * (fDeltaX / _fScale)
                   + (fDeltaY / _fScale) * (fDeltaY / _fScale)
                   + (fDeltaZ / _fScale) * (fDeltaZ / _fScale)) * _fScale;  // 归一平方和乘回量级（Normalised sum times the scale）
    FC_DL_CalcDistance3D := _fResult;      // 缩放结果（Scaled result）
    bSaturated := TRUE;                    // 置缩放标志（Raise the scaling flag）
    uErrorId   := DL_ERR_SCALED;           // 置缩放信息码（Raise the scaled info code）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜后置守卫（边界 B5 / 数值安全 N4）
 *      Post guard on the returned distance
 *   理论上不可达：缩放分支已把中间量限制在 3 以内，常规分支受量程约束。
 *   仍保留兜底，杜绝无穷或 NaN 扩散到调用方的滤波与比较链。
 *-----------------------------------------------------------------------------*)
IF NOT ((FC_DL_CalcDistance3D <= DL_INF_LIM) AND (FC_DL_CalcDistance3D >= -DL_INF_LIM)) THEN
    FC_DL_CalcDistance3D := DL_DIST_ZERO;  // 结果非有限，回退 0（Non-finite result, fall back to zero）
    bSaturated := FALSE;                   // 缩放标志复位（Scaling flag cleared）
    uErrorId   := DL_ERR_NONFIN;           // 置非有限值信息码（Raise the non-finite info code）
END_IF

IF FC_DL_CalcDistance3D < DL_DIST_ZERO THEN // 负距离不可能，兜底钳位（A negative distance is impossible）
    FC_DL_CalcDistance3D := DL_DIST_ZERO;  // 钳到 0，维持非负承诺（Clamp to zero, keep the non-negative promise）
END_IF
END_FUNCTION
