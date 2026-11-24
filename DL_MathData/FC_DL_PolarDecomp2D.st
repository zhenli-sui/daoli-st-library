(*==============================================================================
 * 组件名称 (Component)  : FC_DL_PolarDecomp2D
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（SQRT / ATAN / ABS），零厂商私有库
 * 功能描述 (Function)   : 2D 矩阵极分解（纯函数 FC）。对 2×2 矩阵 M 求
 *                         M = R·S：S = (MᵀM)^(1/2) 对称正定部分，R 旋转部分；
 *                         输出主方向角 θ（S 的最大特征向量角）与两个奇异值
 *                         σ1 >= σ2（谱半径语义）。算法：MᵀM 的对称表示
 *                         [a b; b c]，特征值 λ = (T ± √(D²+4b²))/2（T=a+c,
 *                         D=a-c），θ = 0.5·atan2(2b, a-c)。与 Matrix3Inverse
 *                         （求逆）/Affine2D*（仿射组合）分工：谱语义首次入库。
 * 来源标签 (Origin)     : 源矩阵 T2-1 LGF Math ◐ 待挖子项（R25 备注既有），自研 clean-room
 * 边界语义 (Boundary)   : ① 输入 NaN/Inf → 返回 FALSE，输出哨兵 0（还原方向
 *                         不饱和、哨兵 + 有效性位，R81）；
 *                         ② 零矩阵（λ1 <= eps）→ 返回 FALSE（主方向无定义）；
 *                         ③ atan2 本地实现（纯 ATAN 四象限组装），贴轴归属
 *                         写死：y = 0 且 x < 0 归 y >= 0 支，值域 (-π, π]（R52）；
 *                         ④ 除法仅出现在 atan2 域内（x ≠ 0 分支），无除零。
 * 输出语义 (Fallback)   : 返回 FALSE → fTheta/fSigma1/fSigma2 哨兵 0（调用方
 *                         以返回值判有效性，非故障级）。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码（纯函数无错误码）。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（atan2 分支闸）/NaN 哨兵 ✓｜R5 双语同行注释 ✓
 *                         R6 纯函数无顺序逻辑（CASE 无涉）✓｜R7 无定时器实例 ✓
 * 验收向量 (Acceptance) : V1 M=diag(2,1) → σ1=2.0、σ2=1.0、θ=0.0（对角阵
 *                         主方向沿 x 轴）；
 *                         V2 纯旋转 45°（MᵀM=I）→ σ1=σ2=1.0、θ=0.0（各向
 *                         同性退化，θ 无定义取 0 并在头注释声明）；
 *                         V3 剪切 [[1,1],[0,1]] → σ1=1.618034（黄金比）、
 *                         σ2=0.618034、θ≈1.0172 rad（公开数值可复算）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 3 · 序号 15）
 *==============================================================================*)
FUNCTION FC_DL_PolarDecomp2D : BOOL     // 返回 TRUE = 分解有效（θ/σ 可信）/ TRUE = decomposition valid
VAR_INPUT
    fM11 : LREAL;                        (* 矩阵 M 第 1 行第 1 列 [-] / Matrix element m11 *)
    fM12 : LREAL;                        (* 矩阵 M 第 1 行第 2 列 [-] / Matrix element m12 *)
    fM21 : LREAL;                        (* 矩阵 M 第 2 行第 1 列 [-] / Matrix element m21 *)
    fM22 : LREAL;                        (* 矩阵 M 第 2 行第 2 列 [-] / Matrix element m22 *)
END_VAR
VAR_OUTPUT
    fTheta  : LREAL;                     (* 主方向角（S 最大特征向量角）[rad] / Principal direction angle *)
    fSigma1 : LREAL;                     (* 奇异值 1（σ1 >= σ2）[-] / Largest singular value *)
    fSigma2 : LREAL;                     (* 奇异值 2 [-] / Smaller singular value *)
END_VAR
VAR
    fA    : LREAL;                       (* MᵀM 对称元素 a = m11²+m21² [-] / Symmetric element a *)
    fB    : LREAL;                       (* MᵀM 对称元素 b = m11·m12+m21·m22 [-] / Symmetric element b *)
    fC    : LREAL;                       (* MᵀM 对称元素 c = m12²+m22² [-] / Symmetric element c *)
    fT    : LREAL;                       (* 迹 T = a + c [-] / Trace *)
    fD    : LREAL;                       (* 对角差 D = a - c [-] / Diagonal difference *)
    fDisc : LREAL;                       (* 判别式 D² + 4b² [-] / Discriminant *)
    fL1   : LREAL;                       (* 特征值 λ1 = (T+√disc)/2 [-] / Eigenvalue 1 *)
    fL2   : LREAL;                       (* 特征值 λ2 = (T-√disc)/2 [-] / Eigenvalue 2 *)
    fAx   : LREAL;                       (* atan2 实参 x = a - c [-] / atan2 argument x *)
    fAy   : LREAL;                       (* atan2 实参 y = 2b [-] / atan2 argument y *)
    fAng  : LREAL;                       (* atan2 结果工作量 [rad] / atan2 result work *)
END_VAR
VAR CONSTANT
    DL_PDC_EPS : LREAL := 1.0E-12;       (* 特征值判零容差 [-] / Eigenvalue epsilon *)
    DL_PDC_PI  : LREAL := 3.14159265358979324;   (* π（LREAL 精度字面量，R51①）[rad] / Pi *)
    DL_PDC_PI2 : LREAL := 1.57079632679489662;   (* π/2 [rad] / Half pi *)
END_VAR

(* —— 段 0：输出哨兵预置（还原方向不饱和，R81） —— *)
fTheta := 0.0;                           (* θ 哨兵 0 / Theta sentinel *)
fSigma1 := 0.0;                          (* σ1 哨兵 0 / Sigma1 sentinel *)
fSigma2 := 0.0;                          (* σ2 哨兵 0 / Sigma2 sentinel *)
FC_DL_PolarDecomp2D := FALSE;            (* 返回值预置无效 / Return preset invalid *)

(* —— 段 1：输入非有限闸（NaN 自反 + Inf 差判，R79） —— *)
IF (fM11 <> fM11) OR ((fM11 - fM11) <> (fM11 - fM11))
   OR (fM12 <> fM12) OR ((fM12 - fM12) <> (fM12 - fM12))
   OR (fM21 <> fM21) OR ((fM21 - fM21) <> (fM21 - fM21))
   OR (fM22 <> fM22) OR ((fM22 - fM22) <> (fM22 - fM22)) THEN
    RETURN;                              (* 非有限输入：哨兵 + FALSE 早退（变换集合 = 哨兵全零，无后处理须补，R94） / Non-finite: early return with sentinels *)
END_IF

(* —— 段 2：MᵀM 对称表示与特征分解 —— *)
fA := fM11 * fM11 + fM21 * fM21;         (* a = m11² + m21² / Element a *)
fB := fM11 * fM12 + fM21 * fM22;         (* b = m11·m12 + m21·m22 / Element b *)
fC := fM12 * fM12 + fM22 * fM22;         (* c = m12² + m22² / Element c *)
fT := fA + fC;                           (* 迹 / Trace *)
fD := fA - fC;                           (* 对角差 / Diagonal diff *)
fDisc := fD * fD + 4.0 * fB * fB;        (* 判别式（≥ 0 结构性成立，MᵀM 半正定） / Discriminant *)
fL1 := 0.5 * (fT + SQRT(fDisc));         (* λ1（SQRT 实参 ≥ 0 无域违例） / Eigenvalue 1 *)
fL2 := 0.5 * (fT - SQRT(fDisc));         (* λ2 / Eigenvalue 2 *)
IF fL1 <= DL_PDC_EPS THEN
    RETURN;                              (* 零矩阵：主方向无定义，哨兵 + FALSE（边界②） / Zero matrix: return FALSE *)
END_IF

(* —— 段 3：本地 atan2 四象限组装（贴轴归属写死：y=0 且 x<0 归 y>=0 支，值域 (-π, π]，R52） —— *)
fAx := fA - fC;                          (* 实参 x / Argument x *)
fAy := 2.0 * fB;                         (* 实参 y / Argument y *)
IF fAx > 0.0 THEN
    fAng := ATAN(fAy / fAx);             (* 右半平面：除子 x > 0 无除零 / Right half: divide gated *)
ELSIF fAx < 0.0 THEN
    IF fAy >= 0.0 THEN
        fAng := ATAN(fAy / fAx) + DL_PDC_PI;   (* 上左半平面（含贴轴 y=0,x<0 → π） / Upper-left incl. axis rule *)
    ELSE
        fAng := ATAN(fAy / fAx) - DL_PDC_PI;   (* 下左半平面 / Lower-left *)
    END_IF
ELSE                                     (* x = 0 贴轴支 / Axis branch *)
    IF fAy > 0.0 THEN
        fAng := DL_PDC_PI2;              (* +π/2 / +pi/2 *)
    ELSIF fAy < 0.0 THEN
        fAng := -DL_PDC_PI2;             (* -π/2 / -pi/2 *)
    ELSE
        fAng := 0.0;                     (* x=y=0：退化方向取 0（各向同性，与 V2 声明一致） / Degenerate: zero *)
    END_IF
END_IF

(* —— 段 4：输出映射（σ 由 λ 开方，λ >= 0 结构性保证无域违例） —— *)
fTheta := 0.5 * fAng;                    (* 主方向角 = 半角（特征向量角公式） / Principal angle *)
fSigma1 := SQRT(fL1);                    (* σ1 = √λ1（λ1 > eps 已闸） / Sigma1 *)
fSigma2 := SQRT(fL2);                    (* σ2 = √λ2（λ2 >= 0 半正定） / Sigma2 *)
FC_DL_PolarDecomp2D := TRUE;             (* 分解有效 / Valid *)
END_FUNCTION
