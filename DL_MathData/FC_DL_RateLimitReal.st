(*==============================================================================
 * 组件名称 (Component)  : FC_DL_RateLimitReal
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符与 ABS，零厂商私有库
 * 功能描述 (Function)   : 单拍斜率限幅（FC 形态）：本拍原始输入 fX 与上一拍受限输出
 *                         fXPrev 之差超过 fRateMax × fDt 时，按最大步进逼近，否则直通。
 *                         **契约补充声明**：斜率限幅在数学上必须持有「上一拍输出」，
 *                         故本件使用 VAR_IN_OUT 引脚 fXPrev（调用方声明为静态变量），
 *                         首拍或 fXPrev 被污染时以本拍 fX 重建（置信息码 ePrevRebuilt）。
 *                         严格无内部状态，可重入、可多处例化。
 * 接口     (Interface)  : 输入 fX 原始输入 [工程单位]、fRateMax 限幅速率 [单位/秒]、
 *                         fDt 采样周期 [s]；VAR_IN_OUT fXPrev 上一拍受限输出（本件写回）；
 *                         输出 fY 限幅输出 [工程单位]、eErrCode（E_DL_RateLimitErr）；
 *                         返回值 = 数值可信标志（TRUE = fY 可信）。
 * 边界     (Boundary)   : ① fRateMax ≤ 0 或 fDt ≤ 0 → 旁路，fY = fX（信息级 eBypass，
 *                             返回值 TRUE——旁路输出仍是原值的忠实搬运，非故障）。
 *                         ② 任一浮点入参非有限（NaN / ±Inf）→ 故障级 eNonFinite，
 *                            fY = 0 哨兵，返回 FALSE（R79 双判，禁近似阈值）。
 *                         ③ 步进 fRateMax × fDt 溢出为非有限 → 同按旁路处理（不再逼近）。
 *                         ④ 限幅后结果复检，非有限则回退到 fXPrev 并报故障。
 *                         ⑤ 浮点同值比较一律用容差 DL_RLIM_EPS（1E-6），禁 `=`（R4）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL +
 *                         REAL + 本文件内 enum E_DL_RateLimitErr（全库唯一属主）。
 *                         信息级码 eLimited / eBypass / ePrevRebuilt 永不置错；
 *                         故障级码 eNonFinite 伴随返回值 FALSE。
 * 分工声明 (Scope)      : 有状态斜坡发生（跨周期积分 + 到达标志）归 FB_DL_RampGenerator；
 *                         本件为纯函数形态单拍限幅，供扫描内计算链使用。
 * 归属     (Ownership)  : E_DL_RateLimitErr 归属本文件（全库唯一属主，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         除零结构不可达（无除法）+ 容差比较 ｜ R5 ✓ 逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fX=10.0, fPrev=0.0, fRateMax=2.0, fDt=1.0 → 步进 2.0 → fY=2.0, eLimited；
 *   A2 续 A1：fX=10.0, fPrev=2.0, fRateMax=2.0, fDt=1.0 → fY=4.0, eLimited；
 *   A3 fX=3.0, fPrev=2.0, fRateMax=2.0, fDt=1.0 → 增量 1.0 ≤ 2.0 → fY=3.0, eOk；
 *   A4 fX=5.0, fPrev=2.0, fRateMax=0.0, fDt=1.0 → 旁路 → fY=5.0, eBypass, 返回 TRUE；
 *   A5 fX=NaN, fPrev=2.0 → fY=0.0, eNonFinite, 返回 FALSE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RateLimitErr（斜率限幅出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RateLimitErr :
(
    eOk          := 0,   // 信息级：未超速，直通 / Info: within rate, pass-through
    eLimited     := 1,   // 信息级：本拍已按最大步进逼近 / Info: closed in by the max step this scan
    eBypass      := 2,   // 信息级：速率或周期越域，旁路输出原值 / Info: rate or period out of domain, bypassed
    ePrevRebuilt := 3,   // 信息级：fXPrev 未初始化或被污染，已用本拍 fX 重建 / Info: previous output rebuilt from fX
    eNonFinite   := 10   // 故障级：入参或结果非有限 / Fault: non-finite input or result
);
END_TYPE

FUNCTION FC_DL_RateLimitReal : BOOL
VAR_INPUT
    fX       : REAL;   // 本拍原始输入 [工程单位] / Raw input this scan in engineering unit
    fRateMax : REAL;   // 允许最大变化速率，有效域 > 0 [单位/秒] / Max allowed rate, valid domain > 0 in unit per second
    fDt      : REAL;   // 采样周期，有效域 > 0 [s] / Sampling period, valid domain > 0 in seconds
END_VAR
VAR_IN_OUT
    fXPrev : REAL;     // 上一拍受限输出，本件写回新值 [工程单位] / Previous limited output, written back by this function
END_VAR
VAR_OUTPUT
    fY       : REAL;              // 限幅输出 [工程单位] / Rate-limited output in engineering unit
    eErrCode : E_DL_RateLimitErr;  // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadX     : BOOL;   // fX 非有限标志 [-] / Non-finite flag of fX
    _bBadRate  : BOOL;   // fRateMax 非有限标志 [-] / Non-finite flag of fRateMax
    _bBadDt    : BOOL;   // fDt 非有限标志 [-] / Non-finite flag of fDt
    _bBadPrev  : BOOL;   // fXPrev 非有限标志 [-] / Non-finite flag of fXPrev
    _fMaxStep  : REAL;   // 本拍允许最大步进 = fRateMax × fDt [工程单位] / Max step this scan
    _fDelta    : REAL;   // 原始增量 = fX − fXPrev [工程单位] / Raw delta between input and previous output
    _fAbsDelta : REAL;   // 增量绝对值 [工程单位] / Absolute delta
END_VAR
VAR CONSTANT
    DL_RLIM_ZERO : REAL := 0.0;     // 零基准与符号分界 [-] / Zero base and sign boundary
    DL_RLIM_EPS  : REAL := 1.0E-6;  // 浮点同值判定容差 [-] / Float equality tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_RateLimitReal := FALSE;                        // 返回值预置不可信 / Return preset not trustworthy
fY      := DL_RLIM_ZERO;                             // 输出哨兵 0 / Output sentinel
eErrCode := E_DL_RateLimitErr.eNonFinite;            // 预置最严码 / Preset strictest code

(* —— 段 1：入参非有限闸（R272 全量枚举 fX / fRateMax / fDt） —— *)
_bBadX    := (fX <> fX) OR ((fX - fX) <> DL_RLIM_ZERO);                    // fX 非有限 / fX non-finite
_bBadRate := (fRateMax <> fRateMax) OR ((fRateMax - fRateMax) <> DL_RLIM_ZERO);  // 速率非有限 / Rate non-finite
_bBadDt   := (fDt <> fDt) OR ((fDt - fDt) <> DL_RLIM_ZERO);                // 周期非有限 / Period non-finite
IF _bBadX OR _bBadRate OR _bBadDt THEN
    RETURN;                                          // 故障出口：fY 保持 0 哨兵 / Fault exit, sentinel kept
END_IF

(* —— 段 2：上一拍输出有效性闸（未初始化或已被污染 → 用本拍输入重建，防 NaN 搬运） —— *)
_bBadPrev := (fXPrev <> fXPrev) OR ((fXPrev - fXPrev) <> DL_RLIM_ZERO);     // 前值非有限 / Previous value non-finite
IF _bBadPrev THEN
    fXPrev   := fX;                                  // 以本拍输入重建起点 / Rebuild the starting point
    eErrCode := E_DL_RateLimitErr.ePrevRebuilt;      // 信息级：前值已重建 / Info: previous value rebuilt
END_IF

(* —— 段 3：速率 / 周期域闸（fRateMax ≤ 0 或 fDt ≤ 0 → 旁路，输出原 x） —— *)
IF (fRateMax <= DL_RLIM_ZERO) OR (fDt <= DL_RLIM_ZERO) THEN
    fY      := fX;                                   // 旁路：输出保持原 x / Bypass: output keeps the raw input
    fXPrev  := fX;                                   // 前值同步 / Previous value follows
    eErrCode := E_DL_RateLimitErr.eBypass;           // 信息级：旁路 / Info: bypassed
    FC_DL_RateLimitReal := TRUE;                     // 旁路输出可信 / Bypass output is trustworthy
    RETURN;
END_IF

(* —— 段 4：本拍最大步进（乘后复检，溢出为非有限则旁路） —— *)
_fMaxStep := fRateMax * fDt;                         // 步进 = 速率 × 周期 / Step equals rate times period
IF (_fMaxStep <> _fMaxStep) OR ((_fMaxStep - _fMaxStep) <> DL_RLIM_ZERO) THEN
    fY      := fX;                                   // 步进不可表：放弃逼近 / Unrepresentable step: no approach
    fXPrev  := fX;                                   // 前值同步 / Previous value follows
    eErrCode := E_DL_RateLimitErr.eBypass;           // 信息级：旁路 / Info: bypassed
    FC_DL_RateLimitReal := TRUE;                     // 原值可信 / Raw value is trustworthy
    RETURN;
END_IF

(* —— 段 5：增量比较与逼近（超速按符号方向各逼近一步，方向分列 R146） —— *)
_fDelta    := fX - fXPrev;                           // 原始增量 / Raw delta
_fAbsDelta := ABS(_fDelta);                          // 增量绝对值 / Absolute delta
IF _fAbsDelta <= (_fMaxStep + DL_RLIM_EPS) THEN
    fY      := fX;                                   // 未超速：直通 / Within rate: pass-through
    eErrCode := E_DL_RateLimitErr.eOk;               // 信息级：正常 / Info: normal
ELSE
    IF _fDelta > DL_RLIM_ZERO THEN
        fY := fXPrev + _fMaxStep;                    // 上行逼近 / Approach upward
    ELSE
        fY := fXPrev - _fMaxStep;                    // 下行逼近 / Approach downward
    END_IF
    eErrCode := E_DL_RateLimitErr.eLimited;          // 信息级：本拍受限 / Info: limited this scan
END_IF

(* —— 段 6：结果复检（逼近后仍非有限 → 回退前值并报故障） —— *)
IF (fY <> fY) OR ((fY - fY) <> DL_RLIM_ZERO) THEN
    fY      := fXPrev;                               // 回退上一有效值 / Fall back to the last valid value
    eErrCode := E_DL_RateLimitErr.eNonFinite;        // 故障级码 / Fault-level code
    FC_DL_RateLimitReal := FALSE;                    // 故障出口不可信 / Fault exit not trustworthy
    RETURN;
END_IF

fXPrev := fY;                                        // 前值写回（唯一写入点）/ Single write-back point
FC_DL_RateLimitReal := TRUE;                         // 输出可信 / Output trustworthy
END_FUNCTION
