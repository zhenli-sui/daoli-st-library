(*==============================================================================
 * 组件名称 (Component)  : FC_DL_TanEx
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 TAN / COS / ABS 内建函数，
 *                         不重实现三角内核，无厂商数学方言依赖
 * 功能一句话 (Summary)  : 正切防御包装：弧度制输入，π/2 + kπ 周期奇点
 *                         双闸拦截（cos 容差闸 + 幅值上限闸），委托内建 TAN。
 * 功能描述 (Function)   : 对弧度制角度 fX 求正切。三道闸门按次序写死：
 *                         ① 非有限复检先行（NaN 用 x <> x 判据、无穷用
 *                         ABS(x) 超有限性上界判据）；② π/2 极点容差闸——
 *                         用内建 COS 求 |cos(fX)|（不自写级数），|cos| <
 *                         1.0E-12 判为极点邻域，返回 0.0 + 故障码；
 *                         ③ 域内委托内建 TAN，结果做非有限与幅值双重复检：
 *                         |tan| 超过 1.0E6 幅值上限判为奇点域（内建 TAN 在
 *                         极点可能返回天文数字而非 Inf，幅值闸必须兜住）。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 故障级 16#0001_022A（本件独占）：
 *                           极点邻域（|cos(fX)| < 1.0E-12）、输入/输出非有限
 *                           或幅值爆炸（|tan| > 1.0E6）——三况同码，均判为
 *                           奇点域，返回安全值 0.0。
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 eErr 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例
 *                         一致，沿 R14 批 3 同一裁定）。
 * 单位声明 (Unit Note)  : 输入 fX 单位为弧度 [rad]，非角度制；角度制调用方
 *                         先乘 π/180 显式转换后再调用，本件不做隐式换算。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TAN / COS / ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 三道闸门次序写死 + 双重复检
 *                         R5 ✓ 全变量中英双语同行注释
 *                         R6 N/A（纯函数，无 CASE/ENUM 状态机，按批 4 口径标 N/A）
 *                         R7 N/A（FC 为纯函数，无实例调用，头注释显式说明）
 * 防御行为声明 (Defense): ① 弧度制输入 [rad]，不做隐式角度换算（单位声明节）；
 *                         ② 非有限复检先行：NaN 判据 fX <> fX（NaN 与任何值
 *                           包括自身比较均为不等，库内既有写法）、无穷判据
 *                           ABS(fX) > 1.0E308，命中即不调内建、早退返回 0.0；
 *                         ③ 极点容差闸前置：|cos(fX)| < 1.0E-12 判为 π/2 + kπ
 *                           周期奇点邻域，cos 由内建求（严禁自写泰勒级数），
 *                           返回 0.0 + 故障码，杜绝幅值爆炸值进入下游；
 *                         ④ 幅值上限闸兜底：内建 TAN 在极点邻域可能返回
 *                           天文数字有限值而非 Inf，|tan| > 1.0E6 判奇点域
 *                           返回 0.0 + 故障码（非有限与幅值双判据同码 022A）；
 *                         ⑤ 1.0E-12 容差与 1.0E6 幅值上限、1.0E308 有限性
 *                           上界均提为只读常量，禁魔法数；
 *                         ⑥ 浮点全程不用等号直比判数值相等，仅用 < > 与
 *                           NaN 自不等判据，符合浮点容差红线口径。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 4 · T0 快车道）
 *============================================================================*)
FUNCTION FC_DL_TanEx : LREAL
VAR_INPUT
    fX : LREAL; // 自变量 [rad]，弧度制，非角度制 / Argument [rad], radians, not degrees
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，16#0001_022A=极点邻域/非有限/幅值爆炸（奇点域），0=无事件 / Error code, 16#0001_022A=pole neighborhood or non-finite or amplitude blow-up (singular domain), 0=no event
END_VAR
VAR CONSTANT
    DL_TAN_FINITE : LREAL := 1.0E308; // 有限性上界 [无量纲]，超界判无穷（库内既有写法）/ Finiteness bound, values beyond treated as infinity (library idiom)
    DL_TAN_EPS    : LREAL := 1.0E-12; // 极点容差 [无量纲]，|cos| 低于此判奇点邻域 / Pole tolerance, |cos| below this means pole neighborhood
    DL_TAN_SAT    : LREAL := 1.0E6;   // 幅值上限 [无量纲]，|tan| 超此判奇点域 / Amplitude ceiling, |tan| above this means singular domain
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与错误码预置：先归零，任何早退路径都不会留下脏码
 *      Preset return value and error code so no early-exit path leaves a stale code
 *-----------------------------------------------------------------------------*)
FC_DL_TanEx := 0.0;   // 返回值预置 0.0（安全值，绝不输出 NaN / 天文数字）/ Preset return to 0.0 (safe value, never NaN or astronomical value)
eErr        := 16#0000_0000;   // 错误码预置无事件 / Preset error code to no event

(*------------------------------------------------------------------------------
 * 段 2｜闸门一：非有限复检先行（防御声明②），NaN / 无穷不进内建内核
 *      Gate 1: non-finite recheck first (defense note 2), NaN and infinity
 *      never reach the built-in kernel
 *-----------------------------------------------------------------------------*)
IF (fX <> fX) OR (ABS(fX) > DL_TAN_FINITE) THEN
    eErr := 16#0001_022A;   // 故障码：输入非有限，判奇点域，拦截早退 / Fault: non-finite input, singular domain, intercepted
    RETURN;                 // 返回预置安全值 0.0 / Return preset safe value 0.0
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜闸门二：π/2 极点容差闸前置（防御声明③）——|cos(fX)| < 1.0E-12
 *      判为周期奇点 π/2 + kπ 邻域，cos 委托内建求，不自写级数
 *      Gate 2: pole tolerance gate ahead (defense note 3) — |cos(fX)| below
 *      1.0E-12 means the periodic singularity neighborhood; cos via the
 *      built-in, never a hand-rolled series
 *-----------------------------------------------------------------------------*)
IF ABS(COS(fX)) < DL_TAN_EPS THEN
    eErr := 16#0001_022A;   // 故障码：极点邻域（π/2 + kπ），返回安全值 0.0 / Fault: pole neighborhood (pi/2 + k*pi), safe value 0.0 returned
    RETURN;                 // 返回预置安全值 0.0 / Return preset safe value 0.0
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜域内委托内建内核（防御声明①④）：极点邻域外委托内建 TAN
 *      In-domain delegation to the built-in kernel (defense notes 1 and 4):
 *      outside the pole neighborhood, delegate to the built-in TAN
 *-----------------------------------------------------------------------------*)
FC_DL_TanEx := TAN(fX);   // 委托内建 TAN 内核，不自实现三角 / Delegate to the built-in TAN kernel, no re-implementation

(*------------------------------------------------------------------------------
 * 段 5｜闸门三：结果双重复检（防御声明④⑤）——非有限或 |tan| 超 1.0E6
 *      幅值上限均判奇点域，兜住「极点返回天文数字而非 Inf」的平台差异
 *      Gate 3: dual result recheck (defense notes 4 and 5) — non-finite or
 *      |tan| above the amplitude ceiling both mean singular domain, catching
 *      platforms that return huge finite values instead of Inf at poles
 *-----------------------------------------------------------------------------*)
IF (FC_DL_TanEx <> FC_DL_TanEx) OR (ABS(FC_DL_TanEx) > DL_TAN_FINITE) OR (ABS(FC_DL_TanEx) > DL_TAN_SAT) THEN
    FC_DL_TanEx := 0.0;    // 兜底安全值 0.0 / Bottom-line safe value 0.0
    eErr := 16#0001_022A;   // 故障码：输出非有限或幅值爆炸，判奇点域 / Fault: non-finite or blown-up output, singular domain
END_IF
END_FUNCTION
