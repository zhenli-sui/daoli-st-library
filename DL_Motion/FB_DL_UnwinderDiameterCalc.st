(*==============================================================================
 * 组件名称 (Component)  : FB_DL_UnwinderDiameterCalc
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 放卷卷径实时估算：fDia = sqrt(fDiaInit^2 - 4 x thick x
 *                         SigmaLen / pi)，开方委托 FC_DL_NthRoot(2)；按外部累计
 *                         放膜长度增量递推；低于最小卷径 → bSpoolEnd 预警。
 *                         被开方数 < 0（数据矛盾）→ 冻结并报错，不塞伪值。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_UnwdErr / FUNCTION_BLOCK FB_DL_UnwinderDiameterCalc
 * 依赖 (Depends)        : DL_MathData/FC_DL_NthRoot
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 量程钳位 + 非有限值防御 ｜ 枚举成员全部显式赋值
 *                         开方委托不重实现 ｜ 浮点容差比较 ｜ 输出冻结语义显式
 * 错误码表 (Codes)      : 16#0004_0318 就绪
 *                         16#0004_0319 信息级 膜厚非法(已钳制下限)
 *                         16#0004_031A 故障级 长度增量非法(拒绝递推)
 *                         16#0004_031B 故障级 数据矛盾(根号内负值或非有限，冻结输出)
 *                         16#0004_031C 信息级 接近空卷预警
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 3
 * 验收向量 (Acceptance) : 初始卷径 500 mm，膜厚 50 um，累计放膜 1000 m
 *                         → 卷径 = sqrt(500^2 - 4*0.05*1000/3.14159...) ≈ 499.94 mm
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_UnwdErr（归属 DL_Motion，与 FB_DL_UnwinderDiameterCalc 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_UnwdErr :
(
    eReady      := 16#0004_0318,   // 就绪 / Ready
    eThickClamp := 16#0004_0319,   // 信息级：膜厚非法已钳制下限 / Info: film thickness clamped
    eLenIncrBad := 16#0004_031A,   // 故障级：长度增量非法（放卷长度不允许回退）/ Fault: illegal length increment
    eDataContrad:= 16#0004_031B,   // 故障级：数据矛盾（根号内负值或非有限，冻结）/ Fault: data contradiction, output frozen
    eSpoolEnd   := 16#0004_031C    // 信息级：接近空卷预警 / Info: spool-end warning
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_UnwinderDiameterCalc
 * 调用约定: 每个扫描周期无条件调用一次；fWebLen_m 必须为单调不减的累计放膜长度。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_UnwinderDiameterCalc
VAR_INPUT
    fFilmThick_um : REAL;              // 膜厚 [微米]，有效域 5~500 / Film thickness [um]
    fDiaInit_mm   : REAL;              // 初始卷径 [毫米]，有效域 50~1200 / Initial roll diameter [mm]
    fWebLen_m     : REAL;              // 累计放膜长度 [米]（外部积分输入，单调不减）/ Accumulated web length [m]
    fDiaMin_mm    : REAL;              // 最小卷径 [毫米]（空卷预警门限）/ Minimum roll diameter [mm]
    bReset        : BOOL;              // 换卷复位（重新以初始卷径起算）/ Roll-change reset
END_VAR
VAR_OUTPUT
    fDiaNow_mm    : REAL;              // 当前卷径 [毫米] / Current roll diameter [mm]
    bSpoolEnd     : BOOL;              // 接近空卷预警 / Spool-end warning
    eErr          : E_DL_UnwdErr;      // 错误码 / Error code
END_VAR
VAR
    fLenPrev      : REAL;              // 上拍累计长度快照 [米]（增量基准）/ Previous length snapshot [m]
    fLenUse       : REAL;              // 生效累计长度（增量非法时冻结）[米] / Effective accumulated length [m]
    fThickUse_mm  : REAL;              // 生效膜厚（换算毫米，钳位后）[毫米] / Effective thickness in mm [mm]
    fDiaInitUse   : REAL;              // 生效初始卷径（NaN 兜底）[毫米] / Effective initial diameter [mm]
    fLenIncr      : REAL;              // 本拍长度增量 [米] / Length increment this scan [m]
    fRadicand     : LREAL;             // 被开方数 [平方毫米] / Radicand [mm2]
    fRootVal      : LREAL;             // 委托开方输出 [毫米] / Delegate root output [mm]
    bRootOk       : BOOL;              // 委托开方有效标志 / Delegate root validity flag
    bFrozen       : BOOL;              // 输出冻结标志（数据矛盾置位）/ Output frozen flag
    bInit         : BOOL;              // 首扫初始化标志 / First-scan init flag
END_VAR
VAR CONSTANT
    DL_UNWD_THICK_MIN : REAL := 5.0;      // 膜厚下限 [微米] / Thickness lower bound [um]
    DL_UNWD_THICK_MAX : REAL := 500.0;    // 膜厚上限 [微米] / Thickness upper bound [um]
    DL_UNWD_DIA_MIN   : REAL := 50.0;     // 初始卷径下限 [毫米] / Initial diameter lower bound [mm]
    DL_UNWD_DIA_MAX   : REAL := 1200.0;   // 初始卷径上限 [毫米] / Initial diameter upper bound [mm]
    DL_UNWD_UM2MM     : REAL := 0.001;    // 微米换毫米系数 [毫米每微米] / um-to-mm factor [mm per um]
    DL_UNWD_M2MM      : REAL := 1000.0;   // 米换毫米系数 [毫米每米] / m-to-mm factor [mm per m]
    DL_UNWD_FOUR      : REAL := 4.0;      // 面积递推系数 4（4 x thick x len / pi）/ Area recursion factor
    DL_UNWD_PI        : REAL := 3.14159265358979;   // 圆周率 [无量纲] / Pi [dimensionless]
    DL_UNWD_TOL       : REAL := 1.0E-6;   // 浮点比较容差 / Float comparison tolerance
    DL_UNWD_INF_MAX   : REAL := 1.0E30;   // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_UNWD_ZERO      : REAL := 0.0;      // 零值常量，避免裸字面量 / Zero constant
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜换卷复位：清快照与冻结标志，卷径回初始值
 *----------------------------------------------------------------------------*)
IF bReset THEN
    fLenPrev := fWebLen_m;                         // 快照重置为当前累计长度 / snapshot reset
    fLenUse := fWebLen_m;                          // 累计长度重置 / length reset
    fDiaNow_mm := fDiaInit_mm;                     // 卷径回初始值 / diameter back to initial
    bFrozen := FALSE;                              // 冻结解除 / freeze released
    bSpoolEnd := FALSE;                            // 预警解除 / warning released
    bInit := TRUE;                                 // 视为首扫完成（跳过旧快照）/ treated as initialized
    eErr := E_DL_UnwdErr.eReady;                   // 回就绪码 / back to ready
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：建立长度快照基准
 *----------------------------------------------------------------------------*)
IF NOT bInit THEN
    fLenPrev := fWebLen_m;                         // 首扫快照 / first-scan snapshot
    fLenUse := fWebLen_m;                          // 累计长度基准 / length baseline
    bInit := TRUE;                                 // 首扫完成 / first scan done
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限值闸：任一输入 NaN/溢出 → 冻结输出并报数据矛盾（不塞伪值）
 *----------------------------------------------------------------------------*)
IF (fFilmThick_um <> fFilmThick_um) OR (ABS(fFilmThick_um) > DL_UNWD_INF_MAX)
   OR (fDiaInit_mm <> fDiaInit_mm) OR (ABS(fDiaInit_mm) > DL_UNWD_INF_MAX)
   OR (fWebLen_m <> fWebLen_m) OR (ABS(fWebLen_m) > DL_UNWD_INF_MAX)
   OR (fDiaMin_mm <> fDiaMin_mm) OR (ABS(fDiaMin_mm) > DL_UNWD_INF_MAX) THEN
    bFrozen := TRUE;                               // 输出冻结 / output frozen
    eErr := E_DL_UnwdErr.eDataContrad;             // 故障级：数据矛盾（非有限并入）/ fault: data contradiction
    bSpoolEnd := TRUE;                             // 数据矛盾按安全侧预警 / safe-side warning
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜膜厚钳位（信息级）与初始卷径兜底
 *----------------------------------------------------------------------------*)
eErr := E_DL_UnwdErr.eReady;                       // 预置就绪 / preset ready
fThickUse_mm := fFilmThick_um * DL_UNWD_UM2MM;     // 膜厚换算毫米 [毫米] / thickness to mm
IF fFilmThick_um < DL_UNWD_THICK_MIN THEN
    fThickUse_mm := DL_UNWD_THICK_MIN * DL_UNWD_UM2MM;   // 膜厚下限钳制 / thickness floored
    eErr := E_DL_UnwdErr.eThickClamp;              // 信息级：膜厚非法已钳制 / info: thickness clamped
ELSIF fFilmThick_um > DL_UNWD_THICK_MAX THEN
    fThickUse_mm := DL_UNWD_THICK_MAX * DL_UNWD_UM2MM;   // 膜厚上限钳制 / thickness capped
    eErr := E_DL_UnwdErr.eThickClamp;              // 信息级：膜厚非法已钳制 / info: thickness clamped
END_IF
fDiaInitUse := fDiaInit_mm;                        // 初始卷径工作副本 / initial diameter working copy
IF (fDiaInitUse < DL_UNWD_DIA_MIN) OR (fDiaInitUse > DL_UNWD_DIA_MAX) THEN
    fDiaInitUse := DL_UNWD_DIA_MIN;                // 初始卷径出域按下限兜底（配置防御）/ initial diameter falls back
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜长度增量合法性闸：放卷长度单调不减（容差内视为零增量）
 *----------------------------------------------------------------------------*)
fLenIncr := fWebLen_m - fLenPrev;                  // 本拍增量 [米] / increment this scan [m]
IF fLenIncr < -DL_UNWD_TOL THEN
    bFrozen := TRUE;                               // 增量为负：拒绝递推，冻结输出 / negative increment: reject, freeze
    eErr := E_DL_UnwdErr.eLenIncrBad;              // 故障级：长度增量非法 / fault: illegal increment
    fLenUse := fLenPrev;                           // 冻结到上拍快照 / frozen at previous snapshot
    RETURN;
END_IF
IF fLenIncr < DL_UNWD_ZERO THEN
    fLenIncr := DL_UNWD_ZERO;                      // 容差内微负增量钳零 / tiny negative clamped to zero
END_IF
fLenUse := fLenPrev + fLenIncr;                    // 生效累计长度 [米] / effective length [m]
fLenPrev := fWebLen_m;                             // 快照推进 / snapshot advanced

(*------------------------------------------------------------------------------
 * 段 6｜卷径递推：被开方数 = 初始卷径^2 - 4 x 膜厚 x 累计长度 / pi
 *       被开方数 < 0（数据矛盾：放膜量超过卷料面积）→ 冻结并报故障级
 *----------------------------------------------------------------------------*)
fRadicand := REAL_TO_LREAL(fDiaInitUse * fDiaInitUse)
           - REAL_TO_LREAL(DL_UNWD_FOUR * fThickUse_mm * fLenUse * DL_UNWD_M2MM) / REAL_TO_LREAL(DL_UNWD_PI);   // 被开方数 [平方毫米]（米换毫米链）/ radicand [mm2]
IF (fRadicand <> fRadicand) OR (ABS(fRadicand) > REAL_TO_LREAL(DL_UNWD_INF_MAX)) THEN
    bFrozen := TRUE;                               // 非有限中间量：冻结 / non-finite intermediate: freeze
    eErr := E_DL_UnwdErr.eDataContrad;             // 故障级：数据矛盾 / fault: data contradiction
    bSpoolEnd := TRUE;                             // 安全侧预警 / safe-side warning
    RETURN;
END_IF
IF fRadicand < LREAL#0.0 THEN
    bFrozen := TRUE;                               // 根号内负值：数据矛盾冻结 / negative radicand: freeze
    eErr := E_DL_UnwdErr.eDataContrad;             // 故障级：根号内负值 / fault: negative radicand
    bSpoolEnd := TRUE;                             // 安全侧预警 / safe-side warning
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜委托开方（FC_DL_NthRoot(2)）与空卷预警
 *----------------------------------------------------------------------------*)
fRootVal := FC_DL_NthRoot(fValue := fRadicand, nRoot := 2, bValid => bRootOk);   // 开方委托 [毫米] / root via delegate [mm]
IF (NOT bRootOk) OR (fRootVal <> fRootVal) OR (ABS(fRootVal) > REAL_TO_LREAL(DL_UNWD_INF_MAX)) THEN
    bFrozen := TRUE;                               // 委托失败：冻结 / delegate failure: freeze
    eErr := E_DL_UnwdErr.eDataContrad;             // 故障级：数据矛盾（委托失败并入，输出同为冻结）/ fault: contradiction
    RETURN;
END_IF
fDiaNow_mm := LREAL_TO_REAL(fRootVal);             // 当前卷径输出 [毫米] / current diameter output [mm]
IF fDiaNow_mm < DL_UNWD_ZERO THEN
    fDiaNow_mm := DL_UNWD_ZERO;                    // 下限防护 / floor guard
END_IF
bSpoolEnd := fDiaNow_mm <= fDiaMin_mm + DL_UNWD_TOL;   // 空卷预警判据（容差比较）/ spool-end predicate
IF bSpoolEnd THEN
    eErr := E_DL_UnwdErr.eSpoolEnd;                // 信息级：接近空卷 / info: spool-end warning
END_IF
END_FUNCTION_BLOCK
