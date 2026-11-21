(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LnEx
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 LN 内建函数，
 *                         不重实现对数内核，无厂商数学方言依赖
 * 功能一句话 (Summary)  : 自然对数防御包装：fX <= 0 域闸门与非有限复检前置，
 *                         委托内建 LN，禁止 NaN / -Inf 穿透到下游联锁。
 * 功能描述 (Function)   : 对真数 fX 求自然对数。域闸门先行写死：
 *                         fX 非有限（NaN 用 x <> x 判据、无穷用 ABS(x) 超
 *                         有限性上界判据，均为库内既有写法）或 fX <= 0 时
 *                         不调内建、返回 0.0 并置码；fX = 0 在数学上趋于
 *                         -Inf，统一按域外拦截，不返回 -Inf；域内（fX > 0
 *                         且有限）委托内建 LN，结果再做一次非有限复检兜底。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 故障级 16#0001_0228（本件独占）：
 *                           fX <= 0 域外——LN(0) 数学上趋于 -Inf、LN(-x) 在
 *                           IEEE 754 下产生 NaN，本库统一拦截为「0.0 + 故障码」；
 *                         故障级 16#0001_0229（本件独占）：
 *                           输入或输出非有限（NaN / 无穷）拦截。
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 eErr 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例
 *                         一致，沿 R14 批 3 同一裁定）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LN / ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 域闸门先行 + 结果非有限复检
 *                         R5 ✓ 全变量中英双语同行注释
 *                         R6 N/A（纯函数，无 CASE/ENUM 状态机，按批 4 口径标 N/A）
 *                         R7 N/A（FC 为纯函数，无实例调用，头注释显式说明）
 * 防御行为声明 (Defense): ① fX <= 0 一律域外：LN(0) 极限为 -Inf，若放行会让
 *                           下游比较器拿到负无穷毒值，本库统一返回 0.0 +
 *                           故障码 16#0001_0228，与 IEEE/平台默认行为差异在此；
 *                         ② 非有限复检先行：NaN 判据 fX <> fX（NaN 与任何值
 *                           包括自身比较均为不等，库内既有写法）、无穷判据
 *                           ABS(fX) > 1.0E308，命中即不调内建、早退返回 0.0；
 *                         ③ 域内委托内建 LN 内核，结果非有限复检兜底
 *                           （防御纵深，正常域内不可能触发）；
 *                         ④ 两级闸门按「先非有限、后定义域」次序写死，
 *                           不可调换（NaN 参与任何大小比较均为 FALSE，
 *                           先判域会把 NaN 静默放行）；
 *                         ⑤ 1.0E308 有限性上界提为只读常量，禁魔法数；
 *                         ⑥ 浮点全程不用等号直比判数值相等，仅用 < > 与
 *                           NaN 自不等判据，符合浮点容差红线口径。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 4 · T0 快车道）
 *============================================================================*)
FUNCTION FC_DL_LnEx : LREAL
VAR_INPUT
    fX : LREAL; // 真数 [无量纲]，须 > 0 且有限 / Antilogarithm argument [dimensionless], must be > 0 and finite
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，16#0001_0228=fX<=0 域外，16#0001_0229=非有限拦截，0=无事件 / Error code, 16#0001_0228=argument <= 0, 16#0001_0229=non-finite interception, 0=no event
END_VAR
VAR CONSTANT
    DL_LN_FINITE : LREAL := 1.0E308; // 有限性上界 [无量纲]，超界判无穷（库内既有写法）/ Finiteness bound, values beyond treated as infinity (library idiom)
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与错误码预置：先归零，任何早退路径都不会留下脏码
 *      Preset return value and error code so no early-exit path leaves a stale code
 *-----------------------------------------------------------------------------*)
FC_DL_LnEx := 0.0;   // 返回值预置 0.0（安全值，绝不输出 NaN / -Inf）/ Preset return to 0.0 (safe value, never NaN or -Inf)
eErr       := 16#0000_0000;   // 错误码预置无事件 / Preset error code to no event

(*------------------------------------------------------------------------------
 * 段 2｜非有限复检先行（防御声明②④）：次序写死——NaN 先于定义域，
 *      否则 NaN 会在大小比较中被静默放行
 *      Non-finite recheck first (defense notes 2 and 4): fixed order, NaN gate
 *      precedes the domain gate or NaN would silently pass the comparisons
 *-----------------------------------------------------------------------------*)
IF (fX <> fX) OR (ABS(fX) > DL_LN_FINITE) THEN
    eErr := 16#0001_0229;   // 故障码：输入非有限（NaN / 无穷），拦截早退 / Fault: non-finite input (NaN or infinity), intercepted
    RETURN;                 // 返回预置安全值 0.0 / Return preset safe value 0.0
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜定义域闸门（防御声明①）：fX <= 0 域外（含 fX = 0 的 -Inf 趋近），
 *      返回 0.0 + 故障码，NaN / -Inf 绝不穿透到下游联锁
 *      Domain gate (defense note 1): fX <= 0 out of domain (including the -Inf
 *      limit at zero), returns 0.0 with fault code, no NaN or -Inf propagation
 *-----------------------------------------------------------------------------*)
IF fX <= 0.0 THEN
    eErr := 16#0001_0228;   // 故障码：真数 <= 0 域外，返回安全值 0.0 / Fault: argument <= 0 out of domain, safe value 0.0 returned
    RETURN;                 // 返回预置安全值 0.0，不产生 NaN / -Inf / Return preset safe value 0.0, no NaN or -Inf produced
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜域内委托内建内核（防御声明③）：fX > 0 且有限，委托内建 LN
 *      In-domain delegation to the built-in kernel (defense note 3):
 *      fX > 0 and finite, delegate to the built-in LN
 *-----------------------------------------------------------------------------*)
FC_DL_LnEx := LN(fX);   // 委托内建 LN 内核，不自实现对数 / Delegate to the built-in LN kernel, no re-implementation

(*------------------------------------------------------------------------------
 * 段 5｜结果非有限复检（防御声明③）：域内正常不可能触发，兜底拦截
 *      Result finiteness recheck (defense note 3): unreachable in the normal
 *      domain, kept as a bottom-line interception
 *-----------------------------------------------------------------------------*)
IF (FC_DL_LnEx <> FC_DL_LnEx) OR (ABS(FC_DL_LnEx) > DL_LN_FINITE) THEN
    FC_DL_LnEx := 0.0;    // 兜底安全值 0.0 / Bottom-line safe value 0.0
    eErr := 16#0001_0229;   // 故障码：结果非有限拦截 / Fault: non-finite result intercepted
END_IF
END_FUNCTION
