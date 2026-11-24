(*
    FC_DL_TriangleSolveSSS —— SSS 三边解三角形（余弦定理三角度，机构几何 / 三点定位纯函数）
    ------------------------------------------------------------------
    组件名称  : FC_DL_TriangleSolveSSS
    分类      : DL_MathData / Geometry
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 「几何原子归 Math 组」的分类事实（T2-1 Math 行，
                R64 订正遗留的三角方向待挖首件）；余弦定理为公开数学。
                本件无任何 LGF 数据结构 / 命名 / 代码行接触（闭源，只借分类
                事实，最严口径）。
                clean-room 声明 —— 零代码行复制；数学仅用标准运算符与
                ACOS / ABS，域钳位与复验逻辑 100% 自有。
                许可证 —— 本件 MIT。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R71 构建轮 · 批 2 · 序号 7）
    ------------------------------------------------------------------
    命名说明  : 泛名 FC_DL_TriangleSolve 在 R71 计划 §2.2 撞名三查中被拒 ——
                与信号发生器 FB_DL_TriangleGenerator（R39 在册）共享
                「Triangle」词根，同根异义高风险命名；故收窄为
                FC_DL_TriangleSolveSSS 并在此声明。本件为 **SSS 专属**
                （三边定三角）：SAS / ASA 等其余解法**不立**（拆件即凑数，
                R62 口径），如有需要由后续轮按独立判据链另行立项。
    功能说明  : 已知三边长（fA / fB / fC，对边对应角 A / B / C），余弦定理
                逐角求解：
                cosA = (b² + c² − a²) / (2·b·c)，A = ACOS(cosA)，B / C 轮换；
                三角和复验 |A + B + C − π| < 1E-6 [rad] 才置返回值 TRUE。
                判据链顺序：三边非有限 / 非正闸 → 三角不等式闸（任意两边
                之和 > 第三边，严格不等；恰等号 = 共线退化 → 拒并出信息码）
                → 余弦定理逐角求解 → 反余弦入参域钳位 [-1, 1]（浮点舍入可致
                比值微越 ±1，直接进 ACOS 得 NaN，R45 口径防域外）→ 三角和
                复验。
                除零面在余弦定理分母 2·b·c：三边非正闸已前置拦截（三边恒正
                则分母恒正），无裸除法暴露；仍做防御性声明（先判后除纪律）。
                浮点判等禁用 =（红线 5）：不等式用严格 > 与容差双口径 ——
                ETOL = 1E-9 [mm] 为绝对容差，仅拦浮点舍入级共线退化
                （工程长度尺度下 1E-9 mm 远小于任何机械可分辨差），域外
                真退化（a + b = c 的实数等号）由严格不等式拒收。
    错误码    : 16#0002_37B0 入参非有限（NaN / Inf / 超幅值）或非正边，角度
                            输出清零 —— 故障级
                16#0002_37B1 三角不等式不成立（含共线退化），拒绝求解，角度
                            输出清零 —— 信息级（几何输入问题，非本件故障）
                16#0002_37B2 三角和复验失败（|Σ−π| >= 1E-6 rad，舍入超差），
                            角度不可信，输出清零 —— 信息级
    码位总账  : 16#0002_37B0 用 ｜ 16#0002_37B1 用 ｜ 16#0002_37B2 用
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无边沿实例 / 无数组下标，周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 域闸逐项点名（R272）：fA / fB / fC 三入参全部纳入非有限闸
                   （NaN 自反判 + Inf 差值自反判 + 幅值 1E30 上界筛查）与
                   非正闸（<= 0 拒，边长无零边 / 负边语义）；
                四 ACOS 入参钳位 [-1, 1] 必做（浮点舍入可致 > 1），钳位为
                   防御动作不算域外故障，无独立码位（钳后结果仍过三角和
                   复验把守，不静默放行）；
                五 复验失败不置 bError（信息级，R45），返回值 FALSE 即可
                   表达不可信，角度输出一律清零（绝不送未复验值给下游）；
                六 返回值即 bValid 语义（出参契约：三角和复验通过才 TRUE）。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R71 构建轮 · 批 2 · 序号 7）
*)
FUNCTION FC_DL_TriangleSolveSSS : BOOL
VAR_INPUT
    fA : LREAL;                            (* 边长 a（角 A 的对边），[mm]，须 > 0 / the side a, opposite to angle A, must be positive *)
    fB : LREAL;                            (* 边长 b（角 B 的对边），[mm]，须 > 0 / the side b, opposite to angle B, must be positive *)
    fC : LREAL;                            (* 边长 c（角 C 的对边），[mm]，须 > 0 / the side c, opposite to angle C, must be positive *)
END_VAR
VAR_OUTPUT
    fAngA    : LREAL;                      (* 角 A，[rad] / the angle A in radians *)
    fAngB    : LREAL;                      (* 角 B，[rad] / the angle B in radians *)
    fAngC    : LREAL;                      (* 角 C，[rad] / the angle C in radians *)
    nInfoCode: UDINT;                      (* 信息 / 错误码，0 = 正常 / the info or error id, 0 = ok *)
    bError   : BOOL;                       (* 故障标志，仅故障级码置位（R45 配对）/ the fault flag, raised only on fault-level codes *)
END_VAR
VAR CONSTANT
    DL_TSS_FMAX : LREAL := 1.0E30;         (* 非有限筛查幅值上限，[mm] / the finiteness screening cap *)
    DL_TSS_ETOL : LREAL := 1.0E-9;         (* 三角不等式退化容差（绝对口径），[mm] / the degeneracy tolerance of the triangle inequality *)
    DL_TSS_PI   : LREAL := 3.14159265358979; // 圆周率，[rad] / the circle constant pi
    DL_TSS_STOL : LREAL := 1.0E-6;         (* 三角和复验容差，[rad] / the angle sum recheck tolerance *)
END_VAR
VAR
    _fCosA : LREAL;                        (* 角 A 余弦中间量，[无量纲] / the cosine of angle A *)
    _fCosB : LREAL;                        (* 角 B 余弦中间量，[无量纲] / the cosine of angle B *)
    _fCosC : LREAL;                        (* 角 C 余弦中间量，[无量纲] / the cosine of angle C *)
    _fSum  : LREAL;                        (* 三角和中间量，[rad] / the angle sum temporary *)
END_VAR

// 段 1｜返回值与角度预置（统一出口预置，R256）/ segment 1, preset the return and the angles
FC_DL_TriangleSolveSSS := FALSE;           // 故障缺省返回不可信 / the fault default is not trustworthy
fAngA     := 0.0;                          // 角 A 预置零 / preset the angle A to zero
fAngB     := 0.0;                          // 角 B 预置零 / preset the angle B to zero
fAngC     := 0.0;                          // 角 C 预置零 / preset the angle C to zero
nInfoCode := 0;                            // 预置无错 / preset no error
bError    := FALSE;                        // 预置无故障 / preset no fault

// 段 2｜三边非有限闸（NaN 自反判 + Inf 差值自反判 + 幅值上界，R272 逐项点名）/ segment 2, the finiteness gate
IF (fA <> fA) OR ((fA - fA) <> 0.0) OR (ABS(fA) > DL_TSS_FMAX) THEN
    nInfoCode := 16#0002_37B0;             // 故障级：边 a 非有限 / fault level: the side a non finite
    bError := TRUE;                        // R45 配对置故障标志 / paired with the flag
    RETURN;                                // 结构早退（角度保持清零预置）/ structural exit, the angles stay zeroed
END_IF
IF (fB <> fB) OR ((fB - fB) <> 0.0) OR (ABS(fB) > DL_TSS_FMAX) THEN
    nInfoCode := 16#0002_37B0;             // 故障级：边 b 非有限 / fault level: the side b non finite
    bError := TRUE;                        // R45 配对 / paired with the flag
    RETURN;                                // 结构早退 / exit
END_IF
IF (fC <> fC) OR ((fC - fC) <> 0.0) OR (ABS(fC) > DL_TSS_FMAX) THEN
    nInfoCode := 16#0002_37B0;             // 故障级：边 c 非有限 / fault level: the side c non finite
    bError := TRUE;                        // R45 配对 / paired with the flag
    RETURN;                                // 结构早退 / exit
END_IF

// 段 3｜三边非正闸（边长无零边 / 负边语义，兼前置拦余弦定理分母 2·b·c 除零面）/ segment 3, the non positive sides gate
IF (fA <= 0.0) OR (fB <= 0.0) OR (fC <= 0.0) THEN
    nInfoCode := 16#0002_37B0;             // 故障级：非正边 / fault level: a non positive side
    bError := TRUE;                        // R45 配对 / paired with the flag
    RETURN;                                // 结构早退 / exit
END_IF

// 段 4｜三角不等式闸（严格不等 + 容差双口径，恰等号 = 共线退化拒收）/ segment 4, the triangle inequality gate
IF ((fB + fC - fA) <= DL_TSS_ETOL) OR ((fA + fC - fB) <= DL_TSS_ETOL) OR ((fA + fB - fC) <= DL_TSS_ETOL) THEN
    nInfoCode := 16#0002_37B1;             // 信息级：不等式不成立 / info level: the inequality violated
    bError := FALSE;                       // 信息级不置故障（R45）/ info level never raises the flag
    RETURN;                                // 结构早退（角度保持清零）/ exit, the angles stay zeroed
END_IF

// 段 5｜余弦定理逐角求解（分母 2·b·c 已由段 3 前置保证恒正，先判后除纪律已履行）/ segment 5, the cosine theorem per angle
_fCosA := (fB * fB + fC * fC - fA * fA) / (2.0 * fB * fC); // 角 A 余弦 / the cosine of angle A
_fCosB := (fA * fA + fC * fC - fB * fB) / (2.0 * fA * fC); // 角 B 余弦 / the cosine of angle B
_fCosC := (fA * fA + fB * fB - fC * fC) / (2.0 * fA * fB); // 角 C 余弦 / the cosine of angle C

// 段 6｜反余弦入参域钳位 [-1, 1]（浮点舍入防 ACOS 域外 NaN，R45 口径）/ segment 6, the ACOS domain clamp
IF _fCosA > 1.0 THEN                       // 角 A 余弦微越上界 / the cosine slightly over one
    _fCosA := 1.0;                         // 钳到上界 / clamp to one
ELSIF _fCosA < -1.0 THEN                   // 角 A 余弦微越下界 / slightly under minus one
    _fCosA := -1.0;                        // 钳到下界 / clamp to minus one
END_IF
IF _fCosB > 1.0 THEN                       // 角 B 余弦微越上界 / the cosine slightly over one
    _fCosB := 1.0;                         // 钳到上界 / clamp to one
ELSIF _fCosB < -1.0 THEN                   // 角 B 余弦微越下界 / slightly under minus one
    _fCosB := -1.0;                        // 钳到下界 / clamp to minus one
END_IF
IF _fCosC > 1.0 THEN                       // 角 C 余弦微越上界 / the cosine slightly over one
    _fCosC := 1.0;                         // 钳到上界 / clamp to one
ELSIF _fCosC < -1.0 THEN                   // 角 C 余弦微越下界 / slightly under minus one
    _fCosC := -1.0;                        // 钳到下界 / clamp to minus one
END_IF

// 段 7｜反余弦求解（域已钳位，无 NaN 面）/ segment 7, the arccosine solve
fAngA := ACOS(_fCosA);                     // 角 A，[rad] / the angle A
fAngB := ACOS(_fCosB);                     // 角 B，[rad] / the angle B
fAngC := ACOS(_fCosC);                     // 角 C，[rad] / the angle C

// 段 8｜三角和复验（|Σ−π| < 1E-6 rad 才置返回值 TRUE）/ segment 8, the angle sum recheck
_fSum := fAngA + fAngB + fAngC;            // 三角和，[rad] / the angle sum
IF ABS(_fSum - DL_TSS_PI) >= DL_TSS_STOL THEN // 复验失败（舍入超差）/ the recheck failed
    fAngA     := 0.0;                      // 角度不可信，输出清零（绝不送未复验值）/ the angles not trustworthy, zeroed
    fAngB     := 0.0;                      // 清零 / zeroed
    fAngC     := 0.0;                      // 清零 / zeroed
    nInfoCode := 16#0002_37B2;             // 信息级：三角和复验失败 / info level: the recheck failed
    bError    := FALSE;                    // 信息级不置故障（R45）/ info level never raises the flag
    RETURN;                                // 出口（返回值保持 FALSE）/ exit, the return stays FALSE
END_IF

// 段 9｜域内正常出口 / segment 9, the in-domain outlet
FC_DL_TriangleSolveSSS := TRUE;            // 复验通过，角度可信 / the recheck passed, the angles trustworthy
END_FUNCTION
