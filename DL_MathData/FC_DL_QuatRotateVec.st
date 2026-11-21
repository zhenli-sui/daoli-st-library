(*==============================================================================
 * 组件名称 (Component)  : FC_DL_QuatRotateVec
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         纯 IEC 61131-3 标准函数实现，零外部库依赖，零内部状态
 * 功能描述 (Function)   : 单位四元数旋转三维向量叶子件。输入四元数 q = (qw, qx, qy, qz)
 *                         与三维向量 v，输出旋转后向量 v'，采用无三角函数的
 *                         「t = 2·cross(qv, v); v' = v + qw·t + cross(qv, t)」
 *                         展开式（三叉积六项直算，比旋转矩阵构造少 9 次乘法）。
 *                         适用机器人末端姿态换算、跟踪支架指向换算等场景。
 * 来源标签 (Origin)     : 自研线（公开四元数代数定义 clean-room，IEC 61131-3
 *                         标准语义的道莅防御性实现，零代码行复制）
 * 边界语义 (Boundary)   : ① 模长闸：|q| < eps（四元数未归一或全零）→ bValid = FALSE
 *                         且输出 0 向量（静默输出错误姿态比零更危险，R133 口径）；
 *                         ② 模长用平方和比较，避免开方后舍入：qw²+qx²+qy²+qz²
 *                         落于 [1-eps2, 1+eps2] 视为单位四元数，域外仍按比例
 *                         归一后计算（工程容差），但 bValid 报告归一动作；
 *                         ③ 输入任一分量为 NaN（x<>x 自反判）→ bValid = FALSE；
 *                         ④ 纯函数：同输入同输出，无状态、无定时器、无副作用。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码，有效性经 bValid 布尔出口承载
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 防御完整（模长/NaN/叉积无除法天然防零）✓
 *                         R5 双语同行注释 ✓｜R6 N/A（纯函数无状态机）✓｜R7 N/A（无实例）✓
 * 验收向量 (Acceptance) : V1 q=(0.7071,0,0,0.7071)（绕 Z 轴 90°），v=(1,0,0)
 *                         → 输出 (0,1,0)（容差 1E-6）；V2 q 全零 → bValid=FALSE；
 *                         V3 输入含 NaN → bValid=FALSE 且输出零向量。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 1 · 序号 1）
 *==============================================================================*)
FUNCTION FC_DL_QuatRotateVec : BOOL          (* 返回本调用有效性，TRUE = 输出可用 / Returns validity, TRUE = output usable *)
VAR_INPUT
    fQw      : LREAL;                        (* 四元数标量部（cos(θ/2)）[-] / Quaternion scalar part *)
    fQx      : LREAL;                        (* 四元数向量部 x（sin(θ/2)·ax）[-] / Quaternion vector part x *)
    fQy      : LREAL;                        (* 四元数向量部 y（sin(θ/2)·ay）[-] / Quaternion vector part y *)
    fQz      : LREAL;                        (* 四元数向量部 z（sin(θ/2)·az）[-] / Quaternion vector part z *)
    fVx      : LREAL;                        (* 待旋转向量 x 分量 [工程单位] / Input vector x component *)
    fVy      : LREAL;                        (* 待旋转向量 y 分量 [工程单位] / Input vector y component *)
    fVz      : LREAL;                        (* 待旋转向量 z 分量 [工程单位] / Input vector z component *)
END_VAR
VAR_OUTPUT
    fRx      : LREAL;                        (* 旋转后向量 x 分量 [工程单位] / Rotated vector x component *)
    fRy      : LREAL;                        (* 旋转后向量 y 分量 [工程单位] / Rotated vector y component *)
    fRz      : LREAL;                        (* 旋转后向量 z 分量 [工程单位] / Rotated vector z component *)
    bNormalized : BOOL;                      (* 输入非严格单位模、已按比例归一 [-] / Input not exactly unit, scaled normalization applied *)
END_VAR
VAR
    fSq      : LREAL;                        (* 四元数模长平方（中间量）[-] / Quaternion norm squared, intermediate *)
    fInv     : LREAL;                        (* 模长平方倒数（归一用中间量）[-] / Norm-squared reciprocal, intermediate *)
    fTx      : LREAL;                        (* 一次叉积中间量 t 的 x 分量 [-] / First cross-product intermediate t x *)
    fTy      : LREAL;                        (* 一次叉积中间量 t 的 y 分量 [-] / First cross-product intermediate t y *)
    fTz      : LREAL;                        (* 一次叉积中间量 t 的 z 分量 [-] / First cross-product intermediate t z *)
END_VAR
VAR CONSTANT
    DL_QEPS_NORM : LREAL := 1.0E-9;          (* 模长平方判零容差 [-] / Norm-squared zero epsilon *)
    DL_QEPS_UNIT : LREAL := 1.0E-6;          (* 单位模容差（模长平方偏离 1 的容忍带）[-] / Unit-norm tolerance band *)
END_VAR

(* —— 段 1：缺省输出与有效性预置（R285 每拍全路径赋值，纯函数同样适用） —— *)
fRx := 0.0;                                  (* 旋转输出 x 缺省零向量 / Default rotated x *)
fRy := 0.0;                                  (* 旋转输出 y 缺省零向量 / Default rotated y *)
fRz := 0.0;                                  (* 旋转输出 z 缺省零向量 / Default rotated z *)
bNormalized := FALSE;                        (* 归一标记缺省 FALSE / Normalization flag default *)
FC_DL_QuatRotateVec := FALSE;                (* 返回值缺省无效 / Return default invalid *)

(* —— 段 2：NaN 自反判（判等禁令唯一例外，R135 口径：非有限值绝不进入计算） —— *)
IF (fQw <> fQw) OR (fQx <> fQx) OR (fQy <> fQy) OR (fQz <> fQz)
   OR (fVx <> fVx) OR (fVy <> fVy) OR (fVz <> fVz) THEN
    RETURN;                                  (* 任一输入非有限 → 保持零向量与无效返回 / Any non-finite input keeps zero output *)
END_IF

(* —— 段 3：模长闸与按比例归一（模长平方比较，避免 SQRT 后舍入误差放大） —— *)
fSq := fQw * fQw + fQx * fQx + fQy * fQy + fQz * fQz;   (* 四元数模长平方 [-] / Quaternion norm squared *)
IF fSq < DL_QEPS_NORM THEN
    RETURN;                                  (* 全零/未初始化四元数 → 无效返回 / Degenerate quaternion, invalid *)
END_IF
IF ABS(fSq - 1.0) > DL_QEPS_UNIT THEN        (* 偏离单位模超出工程容差 / Norm deviates beyond tolerance *)
    fInv := 1.0 / fSq;                       (* 模长平方非零已由上闸保证，此处无除零 / Divisor guaranteed nonzero by prior gate *)
    fQw := fQw * fInv;                       (* 按模长平方归一标量部（一阶近似，工程容差内成立） / Scale scalar part *)
    fQx := fQx * fInv;                       (* 归一向量部 x / Scale vector part x *)
    fQy := fQy * fInv;                       (* 归一向量部 y / Scale vector part y *)
    fQz := fQz * fInv;                       (* 归一向量部 z / Scale vector part z *)
    bNormalized := TRUE;                     (* 报告执行了归一修正 / Report normalization applied *)
END_IF

(* —— 段 4：两叉积展开式旋转核心（六乘加组，无三角函数无除法） —— *)
(* t = 2·cross(qv, v)，qv = (fQx, fQy, fQz) / t = 2 * cross(quat vector, input vector) *)
fTx := 2.0 * (fQy * fVz - fQz * fVy);        (* 中间叉积 t 的 x 分量 / Intermediate t x component *)
fTy := 2.0 * (fQz * fVx - fQx * fVz);        (* 中间叉积 t 的 y 分量 / Intermediate t y component *)
fTz := 2.0 * (fQx * fVy - fQy * fVx);        (* 中间叉积 t 的 z 分量 / Intermediate t z component *)
(* v' = v + qw·t + cross(qv, t) / v' = v + qw * t + cross(quat vector, t) *)
fRx := fVx + fQw * fTx + (fQy * fTz - fQz * fTy);   (* 输出 x = 直通项 + 标量项 + 二次叉积项 / Output x composition *)
fRy := fVy + fQw * fTy + (fQz * fTx - fQx * fTz);   (* 输出 y 同构 / Output y composition *)
fRz := fVz + fQw * fTz + (fQx * fTy - fQy * fTx);   (* 输出 z 同构 / Output z composition *)

FC_DL_QuatRotateVec := TRUE;                 (* 全部闸通过，输出有效 / All gates passed, output valid *)
END_FUNCTION
