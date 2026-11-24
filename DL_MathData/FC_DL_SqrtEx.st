(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SqrtEx
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 SQRT 内建函数，
 *                         不重实现开方内核，无厂商数学方言依赖
 * 功能一句话 (Summary)  : 平方根防御包装：负数与非有限输入域闸门先行，
 *                         域内委托内建 SQRT，绝不向下游输出 NaN。
 * 功能描述 (Function)   : 对被开方数 fX 求平方根。定义域闸门先行写死：
 *                         fX 非有限（NaN 用 x <> x 判据、无穷用 ABS(x) 超
 *                         有限性上界判据，均为库内既有写法）或 fX < 0 时
 *                         不调内建、返回 0.0 并置码；域内（fX >= 0 且有限）
 *                         委托内建 SQRT，结果再做一次非有限复检兜底。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 故障级 16#0001_0227（本件独占）：
 *                           fX < 0 域外，负数开方在 IEEE 754 下产生 NaN——
 *                           本库统一为「0.0 + 故障码」策略，NaN 绝不穿透到
 *                           下游联锁（与 IEEE 默认行为的差异点，见防御声明①）；
 *                         信息级 16#0001_015A（本件独占）：
 *                           输入或输出非有限（NaN / 无穷）拦截。
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 eErr 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例
 *                         一致，沿 R14 批 3 同一裁定）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: SQRT / ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 域闸门先行 + 结果非有限复检
 *                         R5 ✓ 全变量中英双语同行注释
 *                         R6 N/A（纯函数，无 CASE/ENUM 状态机，按批 4 口径标 N/A）
 *                         R7 N/A（FC 为纯函数，无实例调用，头注释显式说明）
 * 防御行为声明 (Defense): ① 负数开方返回 0.0 + 故障码 16#0001_0227，不产生
 *                           NaN——IEEE 754 下 SQRT(-x) = NaN，NaN 会沿调用链
 *                           静默污染下游滤波与比较，本库以显式码替代毒值；
 *                         ② 非有限复检先行：NaN 判据 fX <> fX（NaN 与任何值
 *                           包括自身比较均为不等，库内既有写法）、无穷判据
 *                           ABS(fX) > 1.0E308，命中即不调内建、早退返回 0.0；
 *                         ③ 域内委托内建 SQRT 内核，结果非有限复检兜底
 *                           （防御纵深，正常域内不可能触发）；
 *                         ④ fX = 0 为合法输入，SQRT(0) = 0 直通不置码；
 *                         ⑤ 1.0E308 有限性上界提为只读常量，禁魔法数；
 *                         ⑥ 浮点全程不用等号直比判数值相等，仅用 < > 与
 *                           NaN 自不等判据，符合浮点容差红线口径。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 4 · T0 快车道）
 *============================================================================*)
FUNCTION FC_DL_SqrtEx : LREAL
VAR_INPUT
    fX : LREAL; // 被开方数 [无量纲]，须 >= 0 且有限 / Radicand [dimensionless], must be >= 0 and finite
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，16#0001_0227=负数域外，16#0001_015A=非有限拦截，0=无事件 / Error code, 16#0001_0227=negative domain, 16#0001_015A=non-finite interception, 0=no event
END_VAR
VAR CONSTANT
    DL_SQ_FINITE : LREAL := 1.0E308; // 有限性上界 [无量纲]，超界判无穷（库内既有写法）/ Finiteness bound, values beyond treated as infinity (library idiom)
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与错误码预置：先归零，任何早退路径都不会留下脏码
 *      Preset return value and error code so no early-exit path leaves a stale code
 *-----------------------------------------------------------------------------*)
FC_DL_SqrtEx := 0.0;   // 返回值预置 0.0（安全值，绝不输出 NaN）/ Preset return to 0.0 (safe value, never NaN)
eErr         := 16#0000_0000;   // 错误码预置无事件 / Preset error code to no event

(*------------------------------------------------------------------------------
 * 段 2｜非有限复检先行（防御声明②）：NaN 与无穷一律不进内建内核
 *      Non-finite recheck first (defense note 2): NaN and infinity never reach
 *      the built-in kernel
 *-----------------------------------------------------------------------------*)
IF (fX <> fX) OR (ABS(fX) > DL_SQ_FINITE) THEN
    eErr := 16#0001_015A;   // 信息码：输入非有限（NaN / 无穷），拦截早退 / Informational: non-finite input (NaN or infinity), intercepted
    RETURN;                 // 返回预置安全值 0.0 / Return preset safe value 0.0
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜定义域闸门（防御声明①）：fX < 0 域外，返回 0.0 + 故障码，
 *      杜绝 IEEE 默认的 NaN 穿透（联锁回路毒值）
 *      Domain gate (defense note 1): negative input returns 0.0 with fault code,
 *      IEEE NaN propagation to downstream interlocks is eliminated
 *-----------------------------------------------------------------------------*)
IF fX < 0.0 THEN
    eErr := 16#0001_0227;   // 故障码：负数开方域外，返回安全值 0.0 / Fault: negative radicand out of domain, safe value 0.0 returned
    RETURN;                 // 返回预置安全值 0.0，不产生 NaN / Return preset safe value 0.0, no NaN produced
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜域内委托内建内核（防御声明③④⑤）：fX >= 0 且有限，
 *      SQRT(0) = 0 合法直通；结果非有限复检兜底（防御纵深）
 *      In-domain delegation to the built-in kernel (defense notes 3 to 5):
 *      SQRT(0) = 0 passes legally; result recheck is defense in depth
 *-----------------------------------------------------------------------------*)
FC_DL_SqrtEx := SQRT(fX);   // 委托内建 SQRT 内核，不自实现开方 / Delegate to the built-in SQRT kernel, no re-implementation

(*------------------------------------------------------------------------------
 * 段 5｜结果非有限复检（防御声明③）：域内正常不可能触发，兜底拦截
 *      Result finiteness recheck (defense note 3): unreachable in the normal
 *      domain, kept as a bottom-line interception
 *-----------------------------------------------------------------------------*)
IF (FC_DL_SqrtEx <> FC_DL_SqrtEx) OR (ABS(FC_DL_SqrtEx) > DL_SQ_FINITE) THEN
    FC_DL_SqrtEx := 0.0;    // 兜底安全值 0.0 / Bottom-line safe value 0.0
    eErr := 16#0001_015A;   // 信息码：结果非有限拦截 / Informational: non-finite result intercepted
END_IF
END_FUNCTION
