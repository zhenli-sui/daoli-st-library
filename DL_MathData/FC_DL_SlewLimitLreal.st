(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SlewLimitLreal
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符、ABS 与标准转换函数，零厂商私有库
 * 功能描述 (Function)   : LREAL 精度斜率限幅（FC 形态）：与 FC_DL_RateLimitReal 同族，
 *                         但全链以 LREAL 计算，避免高精度位置 / 流量累加链在 REAL
 *                         单精度（约 7 位有效数字）上的步进量化误差。
 *                         **窄化出口**：fYReal 由 LREAL_TO_REAL 显式转换（R10），并在
 *                         超出 REAL 可表范围时饱和到 ±3.4028235E38 并置信息级
 *                         eNarrowClamp；窄化方向属于监护出口，饱和不放行是安全侧。
 *                         **契约声明**：fXPrev（VAR_IN_OUT）持有上一拍受限输出。
 * 接口     (Interface)  : 输入 fX 原始输入 [工程单位]、fRateMax 限幅速率 [单位/秒]、
 *                         fDt 采样周期 [s]；VAR_IN_OUT fXPrev 上一拍受限输出（本件写回，LREAL）；
 *                         输出 fY 限幅输出 [LREAL 工程单位]、fYReal 窄化出口 [REAL]、
 *                         eErrCode（E_DL_SlewLimitErr）；返回值 = 数值可信标志。
 * 边界     (Boundary)   : ① fRateMax ≤ 0 或 fDt ≤ 0 → 旁路，fY = fX（信息级 eBypass）。
 *                         ② 任一浮点入参非有限 → 故障级 eNonFinite，fY = 0 哨兵，返回 FALSE。
 *                         ③ 步进溢出为非有限 → 按旁路处理（信息级 eBypass）。
 *                         ④ 限幅后复检非有限 → 回退 fXPrev 并报故障。
 *                         ⑤ 窄化超 REAL 可表范围 → 饱和 + 信息级 eNarrowClamp（不改 LREAL 主出口）。
 *                         ⑥ 容差 DL_SLEW_EPS（1E-12，LREAL 口径；REAL 的 1E-6 在此过粗）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + LREAL +
 *                         本文件内 enum E_DL_SlewLimitErr（全库唯一属主）。
 * 分工声明 (Scope)      : REAL 精度同族件为 FC_DL_RateLimitReal；本件只做精度升级，
 *                         判据结构一致，便于同一工程内按量纲精度选型。
 * 归属     (Ownership)  : E_DL_SlewLimitErr 归属本文件（全库唯一属主，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         容差比较 + 无除法 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 N/A（纯函数）
 *                         R7 N/A（无实例调用） ｜ R10 ✓ LREAL_TO_REAL 显式窄化
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fX=1.0, fPrev=0.0, fRateMax=0.1, fDt=1.0 → fY=0.1, fYReal=0.1, eLimited；
 *   A2 fX=1.0E-9, fPrev=0.0, fRateMax=1.0, fDt=1.0 → 增量在步进内 → fY=1.0E-9, eOk
 *      （REAL 精度件在同一向量上会因 1E-6 容差直通，本件用 1E-12 容差仍判直通但步进量可分辨）；
 *   A3 fX=5.0, fPrev=4.0, fRateMax=0.0, fDt=1.0 → 旁路 fY=5.0, eBypass, 返回 TRUE；
 *   A4 fX=NaN → fY=0.0, eNonFinite, 返回 FALSE；
 *   A5 fX=1.0E39（超 REAL 范围）, fPrev=0.0, fRateMax=1.0E40, fDt=1.0 → fY=1.0E39,
 *      fYReal=3.4028235E38（饱和）, eNarrowClamp。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SlewLimitErr（LREAL 斜率限幅出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SlewLimitErr :
(
    eOk          := 0,   // 信息级：未超速，直通 / Info: within rate, pass-through
    eLimited     := 1,   // 信息级：本拍已按最大步进逼近 / Info: closed in by the max step this scan
    eBypass      := 2,   // 信息级：速率或周期越域，旁路输出原值 / Info: rate or period out of domain, bypassed
    ePrevRebuilt := 3,   // 信息级：fXPrev 未初始化或被污染，已重建 / Info: previous output rebuilt from fX
    eNarrowClamp := 4,   // 信息级：窄化出口超 REAL 可表范围，已饱和 / Info: narrowing saturated at REAL range
    eNonFinite   := 10   // 故障级：入参或结果非有限 / Fault: non-finite input or result
);
END_TYPE

FUNCTION FC_DL_SlewLimitLreal : BOOL
VAR_INPUT
    fX       : LREAL;   // 本拍原始输入 [工程单位，LREAL 精度] / Raw input this scan in engineering unit, LREAL precision
    fRateMax : LREAL;   // 允许最大变化速率，有效域 > 0 [单位/秒] / Max allowed rate, valid domain > 0 in unit per second
    fDt      : LREAL;   // 采样周期，有效域 > 0 [s] / Sampling period, valid domain > 0 in seconds
END_VAR
VAR_IN_OUT
    fXPrev : LREAL;     // 上一拍受限输出，本件写回新值 [工程单位] / Previous limited output, written back by this function
END_VAR
VAR_OUTPUT
    fY       : LREAL;              // 限幅输出（主出口，全精度）[工程单位] / Limited output, primary full-precision outlet
    fYReal   : REAL;               // 窄化出口（LREAL_TO_REAL 显式转换）[工程单位] / Narrowed outlet via explicit LREAL_TO_REAL
    eErrCode : E_DL_SlewLimitErr;   // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadX     : BOOL;    // fX 非有限标志 [-] / Non-finite flag of fX
    _bBadRate  : BOOL;    // fRateMax 非有限标志 [-] / Non-finite flag of fRateMax
    _bBadDt    : BOOL;    // fDt 非有限标志 [-] / Non-finite flag of fDt
    _bBadPrev  : BOOL;    // fXPrev 非有限标志 [-] / Non-finite flag of fXPrev
    _fMaxStep  : LREAL;   // 本拍允许最大步进 = fRateMax × fDt [工程单位] / Max step this scan
    _fDelta    : LREAL;   // 原始增量 = fX − fXPrev [工程单位] / Raw delta
    _fAbsDelta : LREAL;   // 增量绝对值 [工程单位] / Absolute delta
END_VAR
VAR CONSTANT
    DL_SLEW_ZERO  : LREAL := 0.0;              // 零基准与符号分界 [-] / Zero base and sign boundary
    DL_SLEW_EPS   : LREAL := 1.0E-12;          // LREAL 口径浮点同值判定容差 [-] / Float equality tolerance in LREAL terms
    DL_SLEW_RMAX  : LREAL := 3.4028235E38;     // REAL 正向可表上限（窄化饱和用） / Positive REAL maximum for narrowing saturation
    DL_SLEW_RNEG  : LREAL := -3.4028235E38;    // REAL 负向可表下限（窄化饱和用） / Negative REAL minimum for narrowing saturation
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_SlewLimitLreal := FALSE;                       // 返回值预置不可信 / Return preset not trustworthy
fY      := DL_SLEW_ZERO;                             // LREAL 主出口哨兵 / Primary outlet sentinel
fYReal  := LREAL_TO_REAL(DL_SLEW_ZERO);              // 窄化出口哨兵（显式转换）/ Narrowed outlet sentinel via explicit conversion
eErrCode := E_DL_SlewLimitErr.eNonFinite;            // 预置最严码 / Preset strictest code

(* —— 段 1：入参非有限闸（R272 全量枚举 fX / fRateMax / fDt） —— *)
_bBadX    := (fX <> fX) OR ((fX - fX) <> DL_SLEW_ZERO);                          // fX 非有限 / fX non-finite
_bBadRate := (fRateMax <> fRateMax) OR ((fRateMax - fRateMax) <> DL_SLEW_ZERO);  // 速率非有限 / Rate non-finite
_bBadDt   := (fDt <> fDt) OR ((fDt - fDt) <> DL_SLEW_ZERO);                      // 周期非有限 / Period non-finite
IF _bBadX OR _bBadRate OR _bBadDt THEN
    RETURN;                                          // 故障出口：哨兵保持 / Fault exit, sentinels kept
END_IF

(* —— 段 2：上一拍输出有效性闸（未初始化或污染 → 以本拍输入重建） —— *)
_bBadPrev := (fXPrev <> fXPrev) OR ((fXPrev - fXPrev) <> DL_SLEW_ZERO);          // 前值非有限 / Previous value non-finite
IF _bBadPrev THEN
    fXPrev   := fX;                                  // 重建起点 / Rebuild the starting point
    eErrCode := E_DL_SlewLimitErr.ePrevRebuilt;      // 信息级：前值已重建 / Info: previous value rebuilt
END_IF

(* —— 段 3：速率 / 周期域闸（≤ 0 → 旁路，输出原 x） —— *)
IF (fRateMax <= DL_SLEW_ZERO) OR (fDt <= DL_SLEW_ZERO) THEN
    fY       := fX;                                  // 旁路输出原值 / Bypass keeps the raw input
    fXPrev   := fX;                                  // 前值同步 / Previous value follows
    eErrCode := E_DL_SlewLimitErr.eBypass;           // 信息级：旁路 / Info: bypassed
    fYReal   := LREAL_TO_REAL(fY);                   // 窄化出口同步（显式）/ Narrowed outlet follows
    FC_DL_SlewLimitLreal := TRUE;                    // 旁路输出可信 / Bypass output trustworthy
    RETURN;
END_IF

(* —— 段 4：本拍最大步进（乘后复检，溢出为旁路） —— *)
_fMaxStep := fRateMax * fDt;                         // 步进 = 速率 × 周期 / Step equals rate times period
IF (_fMaxStep <> _fMaxStep) OR ((_fMaxStep - _fMaxStep) <> DL_SLEW_ZERO) THEN
    fY       := fX;                                  // 步进不可表：放弃逼近 / Unrepresentable step: no approach
    fXPrev   := fX;                                  // 前值同步 / Previous value follows
    eErrCode := E_DL_SlewLimitErr.eBypass;           // 信息级：旁路 / Info: bypassed
    fYReal   := LREAL_TO_REAL(fY);                   // 窄化出口同步（显式）/ Narrowed outlet follows
    FC_DL_SlewLimitLreal := TRUE;                    // 原值可信 / Raw value trustworthy
    RETURN;
END_IF

(* —— 段 5：增量比较与逼近（上下行分列，R146） —— *)
_fDelta    := fX - fXPrev;                           // 原始增量 / Raw delta
_fAbsDelta := ABS(_fDelta);                          // 增量绝对值 / Absolute delta
IF _fAbsDelta <= (_fMaxStep + DL_SLEW_EPS) THEN
    fY       := fX;                                  // 未超速：直通 / Within rate: pass-through
    eErrCode := E_DL_SlewLimitErr.eOk;               // 信息级：正常 / Info: normal
ELSE
    IF _fDelta > DL_SLEW_ZERO THEN
        fY := fXPrev + _fMaxStep;                    // 上行逼近 / Approach upward
    ELSE
        fY := fXPrev - _fMaxStep;                    // 下行逼近 / Approach downward
    END_IF
    eErrCode := E_DL_SlewLimitErr.eLimited;          // 信息级：本拍受限 / Info: limited this scan
END_IF

(* —— 段 6：结果复检（非有限 → 回退前值并报故障） —— *)
IF (fY <> fY) OR ((fY - fY) <> DL_SLEW_ZERO) THEN
    fY       := fXPrev;                              // 回退上一有效值 / Fall back to the last valid value
    fYReal   := LREAL_TO_REAL(fY);                   // 窄化出口同步（显式）/ Narrowed outlet follows
    eErrCode := E_DL_SlewLimitErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;                                          // 返回 FALSE / Fault exit
END_IF

(* —— 段 7：窄化出口（R10 显式转换 + 可表范围饱和 + 信息级声明） —— *)
IF fY > DL_SLEW_RMAX THEN
    fYReal := LREAL_TO_REAL(DL_SLEW_RMAX);           // 正向饱和 / Saturate positive
    eErrCode := E_DL_SlewLimitErr.eNarrowClamp;      // 信息级：窄化饱和 / Info: narrowing saturated
ELSIF fY < DL_SLEW_RNEG THEN
    fYReal := LREAL_TO_REAL(DL_SLEW_RNEG);           // 负向饱和 / Saturate negative
    eErrCode := E_DL_SlewLimitErr.eNarrowClamp;      // 信息级：窄化饱和 / Info: narrowing saturated
ELSE
    fYReal := LREAL_TO_REAL(fY);                     // 域内窄化（显式）/ In-range narrowing via explicit conversion
END_IF

fXPrev := fY;                                        // 前值写回（唯一写入点）/ Single write-back point
FC_DL_SlewLimitLreal := TRUE;                        // 输出可信 / Output trustworthy
END_FUNCTION
