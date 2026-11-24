(*==============================================================================
 * 组件名称 (Component)  : FC_DL_Matrix3Inverse
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 三阶方阵求逆
 *                         lgf-math / matrix / affine-transform
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 ABS / MIN /
 *                         MAX / LIMIT，无矩阵库依赖，无循环嵌套
 * 功能一句话 (Summary)  : 3 乘 3 实数矩阵按伴随矩阵法解析求逆，含相对奇异判据与
 *                         出口夹域，失败时逆矩阵整体置 0 且绝不输出非数。
 * 功能描述 (Function)   : 九个元素行主序传入，先用余子式展开算行列式，再用伴随矩阵
 *                         除以行列式得到逆。全过程为定长表达式，无主元选取、无嵌套
 *                         循环、无分支跳步，因此同一输入在同一平台上的每一步中间量
 *                         都可复算。典型现场用途：视觉与机器人手眼标定的反解、仿射
 *                         变换的逆映射（像素坐标反算机械坐标）、三传感器三角定位的
 *                         线性方程组求解、标定矩阵在校验工位上的逐拍复核。
 * 为什么不用高斯消元    : 三阶的解析逆是固定九个表达式，无分支、无主元交换、无循环，
 *                         天然满足「纯函数、确定性、可逐拍复算」三条验收要求；高斯
 *                         消元需要三层嵌套循环加主元选择分支，在三阶规模上没有任何
 *                         数值或性能收益，却引入了「主元为 0 时要换行」的分支面。
 * 数值判据（本件关键）  : 不用绝对阈值判奇异。矩阵元素量纲相差一千倍时（毫米级标定
 *                         矩阵与微米级标定矩阵），绝对阈值必然失效：同一个 1.0E-9 的
 *                         绝对门槛对前者过严、对后者过松。本件改用相对判据
 *                         「行列式绝对值 小于等于 相对容差 乘 最大元素绝对值的立方」，
 *                         于是同一个相对容差在两种量纲下都成立。fDetEps 是相对量，
 *                         默认 1.0E-9，不是绝对量，切勿按绝对行列式理解。
 * 与既有件边界 (Boundary): FC_DL_LineIntersection 解两直线交点、FC_DL_CalcDistance3D 算
 *                         点距、FC_DL_PolygonArea 算多边形面积。三者都是定式几何量；
 *                         本件提供通用可逆性判定与逆矩阵，供标定与坐标变换链复用。
 *                         矩阵子族从此件开族，后续四阶与伪逆另立。
 * 设计要点 (Key notes)  : ① 入口先做非有限元素体检：任一元为无穷或非数则整件拒绝，
 *                           而不是让脏值流进行列式把九个输出全污染；
 *                         ② 相对奇异判据只用「行列式、最大元素绝对值、相对容差」
 *                           三个量，判据、守卫、封顶三者同向（见下方三元一致表）；
 *                         ③ 除法前显式确认行列式非零，即使奇异判据已保证；
 *                         ④ 出口夹域：每个逆元素先判有限再夹进上下界，失败路径整体
 *                           置 0 而不置非数，上层拿到的是「明确不可信」而不是毒值；
 *                         ⑤ 纯函数：无内部状态、无跨周期残留，同入参同结果。
 *
 * 【三元一致表 / Guard and criterion consistency (R35)】
 *   守卫：最大元素绝对值 fMaxAbs 仅用于构造立方尺度，不做封顶
 *   封顶：奇异性阈值等于 相对容差 乘 fMaxAbs 的立方，阈值随量纲自动缩放
 *   判据：行列式绝对值 小于等于 该阈值 即判奇异，与守卫同向，无「守卫通过但判据更宽」的缝
 *
 * 【验收向量 / Acceptance vectors】
 *   V1  单位阵 → 逆等于自身、行列式 1.0、返回真
 *   V2  对角阵「2 4 5」→ 逆为对角「0.5 0.25 0.2」、行列式 40.0、返回真
 *   V3  V-A 奇异专测：第一行「1 2 3」、第二行「2 4 6」（第二行是第一行两倍）、
 *       第三行「7 8 9」→ 行列式 0、返回假、码 0225、逆矩阵全 0
 *   V4  V-B 相对判据专测：V3 整体乘 1.0E-6 → 行列式量级 1.0E-18，绝对阈值必然
 *       误判为可逆；本件按相对判据仍返回假、码 0225（此向量是本判据存在的唯一理由）
 *   V5  V-D 出口夹域：任一元素传入非数 → 码 014B、返回假、逆矩阵全 0（不输出非数）
 *   V6  V-D 相对容差非法：相对容差传 0 → 码 014C、按默认 1.0E-9 继续，返回真
 *   V7  病态提示：对角阵「1 1 1.0E-6」且相对容差取 1.0E-12 → 条件数粗估
 *       fCondEst = |det| 除 maxAbs 立方 = 1.0E-6 除 1 = 1.0E-6（v1.0.1 勘误，
 *       旧版误记 1.0E-18），落在「超 10 倍容差、低于 1.0E-3」区间内，
 *       逆已给出、码 014A（提示精度不保）
 *
 * 开源溯源 (Origin)     : 来源标签 lgf-math。LGF（Libre Graphical Framework）为免费
 *                         闭源发布的公开函数库手册，本件仅借鉴其数学组存在「矩阵」
 *                         子族（含求逆、转置、乘加等按阶数分件的粒度事实），作为
 *                         子族开族的立项依据；许可证按其发布方条款仅作分类参考。
 *                         伴随矩阵法与余子式展开属公开线性代数经典内容，本件零代码行、
 *                         零注释、零数据结构引用，clean-room 独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 信息 16#0001_014A 病态但已给逆 ｜ 16#0001_014B 含非有限元素
 *                         16#0001_014C 相对容差非正已用默认
 *                         故障 16#0001_0225 矩阵奇异。取号见本轮规格 §3.2，
 *                         与定长串子族 0143 到 0149 不重叠。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 ABS / LIMIT。
 * 镜像量清单 (R38)      : 无锁存副本。九个元素入口一次拷入局部数组，其后全部表达式
 *                         只用局部数组与入口标量，不再读形参数组，故调用方在本件返回前
 *                         改写入参数组也不会撕裂中间量。
 * 偏离留档 (Deviation)  : 形参数组维度用字面量 9（行主序九个元素），逻辑区用常量
 *                         DL_M3_CNT 表达同一上界，二者字面一致，不构成双源。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址直写
 *                         纯 IEC 61131-3 ｜ 每处除法前判行列式非零 ｜ 浮点不用等值比较
 *                         全变量双语同行注释 ｜ 状态机 N/A（纯函数）｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 B 矩阵子族开族）
 *                         2026-11-16  v1.0.1  终审勘误：验收向量 V7 的条件数粗估值由
 *                         误记的 1.0E-18 更正为实算值 1.0E-6（fCondEst = |det| 除
 *                         maxAbs 立方），仅更正头注释记载，判定逻辑与码位不变
 *============================================================================*)

(*==============================================================================
 * 行主序排布与余子式对应 (Row-major layout)：
 *   元素 1 到 3 是第一行，4 到 6 是第二行，7 到 9 是第三行
 *   行列式按第一行展开，三个余子式分别用第二三两行的元素组合
 *   伴随矩阵是余子式矩阵的转置，故逆矩阵第 2 个元素用的是「第 1 行第 2 列」的
 *   代数余子式，而不是第 2 行第 1 列的，写反会让逆矩阵整体转置
 *   对角阵是最容易验证排布是否写反的例子：转置后仍然是对角阵，看不出错，
 *   所以验收向量必须包含非对角元素非零的矩阵（V3 的三行两两不成比例）
 *============================================================================*)

FUNCTION FC_DL_Matrix3Inverse : BOOL
VAR_INPUT
    afM     : ARRAY[1..9] OF LREAL;   // 行主序 3 乘 3 矩阵 [无量纲或工程单位] / Row-major three by three matrix
    fDetEps : LREAL := 1.0E-9;        // 相对奇异判据 [无量纲]，非正时按默认处理 / Relative singularity epsilon, defaulted when not positive
END_VAR
VAR_OUTPUT
    afInv   : ARRAY[1..9] OF LREAL;   // 逆矩阵，行主序，失败时全 0 [无量纲或工程单位] / Inverse in row-major order, zeroed on failure
    fDet    : LREAL;                  // 行列式值 [无量纲或工程单位立方] / Determinant value
    fCondEst: LREAL;                  // 条件数粗估，越小越病态 [无量纲] / Coarse condition estimate, smaller means worse
    uErrorId: UDINT;                  // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    aV      : ARRAY[1..9] OF LREAL;   // 入参局部副本，非有限元素已按 0 落盘 [无量纲] / Local copy with non-finite elements zeroed
    aW      : ARRAY[1..9] OF LREAL;   // 伴随矩阵九个分子，尚未除以行列式 [无量纲] / Nine adjugate numerators before the division
    fMaxAbs : LREAL;                  // 九个元素绝对值的最大值 [同元素单位] / Largest absolute element
    fScale  : LREAL;                  // 最大元素绝对值的立方，作相对尺度的分母 [同元素单位立方] / Cube of the largest absolute element
    fDetR   : LREAL;                  // 行列式计算值 [同元素单位立方] / Computed determinant
    fCofA   : LREAL;                  // 第一行第一列余子式 [同元素单位平方] / First cofactor
    fCofB   : LREAL;                  // 第一行第二列余子式 [同元素单位平方] / Second cofactor
    fCofC   : LREAL;                  // 第一行第三列余子式 [同元素单位平方] / Third cofactor
    fEps    : LREAL;                  // 本次生效的相对容差 [无量纲] / Effective relative epsilon
    fThresh : LREAL;                  // 奇异性阈值，等于容差乘尺度 [同元素单位立方] / Singularity threshold
    fTmp    : LREAL;                  // 逆元素中间量 [无量纲] / Inverse element intermediate
    nI      : INT;                    // 元素循环下标 [索引]，1 到 9 / Element loop index, 1 to 9
    bNonFin : BOOL;                   // 含非有限元素标记 / Non-finite element flag
    uCode   : UDINT;                  // 码位暂存，出口单点写入 [码] / Code staging, written once at the exit
END_VAR
VAR CONSTANT
    DL_M3_CNT      : INT := 9;              // 元素个数 [个]，与形参维度一致 / Element count, matches the dimension
    DL_M3_FINITE   : LREAL := 1.0E308;      // 有限性上界 [无量纲]，用于拦无穷与非数 / Finiteness bound
    DL_M3_CONDWARN : LREAL := 1.0E-3;       // 病态提示门限 [无量纲]，小于此值提示精度不保 / Ill-conditioned warning threshold
    DL_M3_CONDK    : LREAL := 10.0;         // 病态提示的相对倍数 [无量纲] / Multiplier for the ill-conditioned test
    DL_M3_EPSDEF   : LREAL := 1.0E-9;       // 默认相对容差 [无量纲] / Default relative epsilon
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置（边界 B1，R43）：失败路径的逆矩阵必须是全 0，不是全非数
 *      Pre-set: the failure path publishes all zeros, never not-a-number values
 *      逐元素预置而不是整块赋值，保证每一路出口都在声明域内
 *      Element by element, so every exit path stays inside the declared domain
 *-----------------------------------------------------------------------------*)
FC_DL_Matrix3Inverse := FALSE;
FOR nI := 1 TO DL_M3_CNT DO
    afInv[nI] := 0.0;
    aV[nI]    := 0.0;
    aW[nI]    := 0.0;
END_FOR;
fDet      := 0.0;
fCondEst  := 0.0;
uErrorId  := 16#0000_0000;
uCode     := 16#0000_0000;
fMaxAbs   := 0.0;
fScale    := 0.0;
fDetR     := 0.0;
fThresh   := 0.0;
bNonFin   := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜相对容差闸门（边界 B2）：非正容差退回默认，不阻断计算
 *      Epsilon gate: a non-positive epsilon falls back to the default
 *      容差为 0 会让所有矩阵都判奇异，为负更无意义；退回默认并报信息级码
 *      A zero epsilon would mark every matrix singular, so the default is used
 *-----------------------------------------------------------------------------*)
IF fDetEps > 0.0 THEN
    fEps := fDetEps;
ELSE
    fEps    := DL_M3_EPSDEF;
    uCode   := 16#0001_014C;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限元素体检（边界 B3）：任一元为无穷或非数则整件拒绝
 *      Non-finite check: a single bad element rejects the whole call
 *      体检式：两个比较同时成立才算有限，非数会让两个比较都为假，故此式一并拦截
 *      Both comparisons must hold, a not-a-number fails both and is caught
 *      脏值按 0 落进副本仅用于让码位与诊断可读，本路径不会继续求逆
 *      The dirty value is stored as zero only so the diagnostics stay readable
 *-----------------------------------------------------------------------------*)
FOR nI := 1 TO DL_M3_CNT DO
    IF (afM[nI] <= DL_M3_FINITE) AND (afM[nI] >= -DL_M3_FINITE) THEN
        aV[nI] := afM[nI];
    ELSE
        aV[nI]    := 0.0;
        bNonFin   := TRUE;
    END_IF
END_FOR;

IF bNonFin THEN
    uErrorId := 16#0001_014B;   // 信息级：含非有限元素，逆矩阵保持全 0
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜相对尺度（边界 B4）：九个元素绝对值的最大值，其立方即量纲尺度
 *      Relative scale: the largest absolute element, its cube is the scale
 *      尺度为零意味着整张矩阵全零，后续阈值也为零，行列式零必然被判奇异
 *      A zero scale means an all zero matrix, the threshold collapses to zero as well
 *-----------------------------------------------------------------------------*)
FOR nI := 1 TO DL_M3_CNT DO
    IF ABS(aV[nI]) > fMaxAbs THEN
        fMaxAbs := ABS(aV[nI]);
    END_IF
END_FOR;

fScale := fMaxAbs * fMaxAbs * fMaxAbs;

(*------------------------------------------------------------------------------
 * 段 5｜行列式与条件数粗估（边界 B5）：按第一行展开，三个余子式先行
 *      Determinant and condition estimate: expand along the first row
 *      除法前的显式判零放在段 7，此处只算不除
 *      No division here, the guarded division lives in stage seven
 *-----------------------------------------------------------------------------*)
fCofA := aV[5] * aV[9] - aV[6] * aV[8];   // 第一行第一列余子式 / Cofactor of row one column one
fCofB := aV[4] * aV[9] - aV[6] * aV[7];   // 第一行第二列余子式 / Cofactor of row one column two
fCofC := aV[4] * aV[8] - aV[5] * aV[7];   // 第一行第三列余子式 / Cofactor of row one column three

fDetR := aV[1] * fCofA - aV[2] * fCofB + aV[3] * fCofC;

IF (fDetR <= DL_M3_FINITE) AND (fDetR >= -DL_M3_FINITE) THEN
    fDet := fDetR;                          // 有限才发布，否则保持 0 / Published only when finite
ELSE
    fDet := 0.0;
END_IF

fCondEst := 0.0;
IF fScale > 0.0 THEN
    fTmp := ABS(fDetR) / fScale;            // 除数是正数，无除零面
    IF (fTmp <= DL_M3_FINITE) AND (fTmp >= -DL_M3_FINITE) THEN
        fCondEst := fTmp;
    ELSE
        fCondEst := 0.0;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜相对奇异判定（边界 B6）：阈值随量纲缩放，判据与守卫同向
 *      Relative singularity test: the threshold scales with the magnitude
 *      阈值等于容差乘尺度；全零矩阵时尺度与阈值同为 0，判据「0 小于等于 0」成立
 *      With an all zero matrix both sides collapse to zero and the test still holds
 *-----------------------------------------------------------------------------*)
fThresh := fEps * fScale;

IF ABS(fDetR) <= fThresh THEN
    uErrorId := 16#0001_0225;   // 故障级：奇异，逆不可得，逆矩阵保持全 0
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜伴随矩阵与除法（边界 B7）：先显式确认行列式非零，再逐元素相除
 *      Adjugate and division: confirm a non-zero determinant before dividing
 *      奇异判据已保证行列式非零，此处仍显式判一次，属于除零面的第二道锁
 *      The singularity test already guarantees it, this is the second lock
 *-----------------------------------------------------------------------------*)
IF (fDetR > 0.0) OR (fDetR < 0.0) THEN

    aW[1] := aV[5] * aV[9] - aV[6] * aV[8];
    aW[2] := aV[3] * aV[8] - aV[2] * aV[9];
    aW[3] := aV[2] * aV[6] - aV[3] * aV[5];
    aW[4] := aV[6] * aV[7] - aV[4] * aV[9];
    aW[5] := aV[1] * aV[9] - aV[3] * aV[7];
    aW[6] := aV[3] * aV[4] - aV[1] * aV[6];
    aW[7] := aV[4] * aV[8] - aV[5] * aV[7];
    aW[8] := aV[2] * aV[7] - aV[1] * aV[8];
    aW[9] := aV[1] * aV[5] - aV[2] * aV[4];

    FOR nI := 1 TO DL_M3_CNT DO
        fTmp := aW[nI] / fDetR;
        (* 出口夹域：非有限先归零，再夹进上下界，出口值必在声明域内 *)
        (* Exit clamp: non-finite collapses to zero, then everything is bounded *)
        IF (fTmp <= DL_M3_FINITE) AND (fTmp >= -DL_M3_FINITE) THEN
            afInv[nI] := LIMIT(-DL_M3_FINITE, fTmp, DL_M3_FINITE);
        ELSE
            afInv[nI] := 0.0;
        END_IF
    END_FOR;

ELSE

    uErrorId := 16#0001_0225;   // 兜底：行列式恰为零，与奇异判据同码
    RETURN;

END_IF

(*------------------------------------------------------------------------------
 * 段 8｜病态提示与成功收口（边界 B8）
 *      Ill-conditioning notice and the success close out
 *      条件数粗估小于千分之一但明显高于容差，说明逆虽给出、精度不保
 *      Below one thousandth yet well above the epsilon, the inverse is shown but shaky
 *-----------------------------------------------------------------------------*)
IF (fCondEst < DL_M3_CONDWARN) AND (fCondEst > (DL_M3_CONDK * fEps)) THEN
    uCode := 16#0001_014A;      // 信息级：病态，逆已给出
END_IF

uErrorId := uCode;              // 码位单点写入，全拍只写一次
FC_DL_Matrix3Inverse := TRUE;
END_FUNCTION
