(*==============================================================================
 * 组件名称 (Component)  : FC_DL_RoundSat
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 ROUND / ABS 内建函数，
 *                         不重实现取整内核，无厂商数学方言依赖
 * 功能一句话 (Summary)  : 四舍五入取整饱和包装：非有限拦截 + DINT 越界
 *                         钳到端点不回绕，半值取向写死为「四舍五入远离零」。
 * 功能描述 (Function)   : 对输入实数 fX 四舍五入取整为 DINT。闸门次序写死：
 *                         ① 非有限复检先行（NaN 用 x <> x 判据、无穷用
 *                         ABS(x) 超有限性上界判据），命中返回 0 + 故障码；
 *                         ② DINT 越界饱和闸——fX >= 2147483647.5 时 ROUND
 *                         必溢出，钳到 DINT 上端点 2147483647 并置信息码；
 *                         fX <= -2147483648.5 时钳到下端点 -2147483648
 *                         并置信息码，绝不回绕；③ 域内委托内建 ROUND。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 半值取向 (Half Policy): 「.5 半值取向」写死为本库取「四舍五入远离零」
 *                         （round half away from zero，多数平台 ROUND 语义）；
 *                         需要银行家舍入（round half to even）的调用方用
 *                         FLOOR / CEIL / TRUNC 组合自行复现，本件不提供。
 * 码位     (Diag Codes) : 故障级 16#0001_022B（本件独占）：
 *                           输入非有限（NaN / 无穷），返回 0；
 *                         信息级 16#0001_015B（本件独占）：
 *                           DINT 越界已钳位到端点（上端点或下端点，
 *                           饱和是正常防御行为，不回绕）。
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 eErr 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例
 *                         一致，沿 R14 批 3 同一裁定）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ROUND / ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限拦截 + 越界饱和不回绕
 *                         R5 ✓ 全变量中英双语同行注释
 *                         R6 N/A（纯函数，无 CASE/ENUM 状态机，按批 4 口径标 N/A）
 *                         R7 N/A（FC 为纯函数，无实例调用，头注释显式说明）
 * 防御行为声明 (Defense): ① 非有限复检先行：NaN 判据 fX <> fX（NaN 与任何值
 *                           包括自身比较均为不等，库内既有写法）、无穷判据
 *                           ABS(fX) > 1.0E308，命中即不调内建、早退返回 0；
 *                         ② 饱和阈值取 2147483647.5 / -2147483648.5（而非
 *                           DINT 端点本身）：|x| <= 2^53 内 LREAL 可精确表示
 *                           该阈值，ROUND 在阈值内侧（不含）结果必落在
 *                           [DINT_MIN, DINT_MAX]，阈值及外侧一律钳端点置码，
 *                           绝不回绕（与平台整数回绕行为的差异点）；
 *                         ③ 域内委托内建 ROUND 内核（四舍五入远离零），
 *                           本件不重实现取整；
 *                         ④ 饱和是显式信息码 16#0001_015B，不是静默钳位，
 *                           现场可凭码定位「量纲/增益配错导致的巨数」；
 *                         ⑤ 阈值与端点、1.0E308 有限性上界均提为只读常量，
 *                           禁魔法数；
 *                         ⑥ 浮点全程不用等号直比判数值相等，仅用 < > 与
 *                           NaN 自不等判据，符合浮点容差红线口径。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 4 · T0 快车道）
 *============================================================================*)
FUNCTION FC_DL_RoundSat : DINT
VAR_INPUT
    fX : LREAL; // 输入实数 [无量纲] / Input real value [dimensionless]
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，16#0001_022B=非有限输入，16#0001_015B=越界钳位到 DINT 端点，0=无事件 / Error code, 16#0001_022B=non-finite input, 16#0001_015B=clamped to a DINT endpoint, 0=no event
END_VAR
VAR CONSTANT
    DL_RND_FINITE : LREAL := 1.0E308;       // 有限性上界 [无量纲]，超界判无穷（库内既有写法）/ Finiteness bound, values beyond treated as infinity (library idiom)
    DL_RND_HI     : LREAL := 2147483647.5;  // 饱和上阈 [无量纲]，fX >= 此值 ROUND 必溢出上端点 / Saturation upper threshold, ROUND overflows above it
    DL_RND_LO     : LREAL := -2147483648.5; // 饱和下阈 [无量纲]，fX <= 此值 ROUND 必溢出下端点 / Saturation lower threshold, ROUND overflows below it
    DL_RND_DMAX   : DINT  := 2147483647;    // DINT 上端点 [个]，钳位目标 / DINT upper endpoint, clamping target
    DL_RND_DMIN   : DINT  := -2147483648;   // DINT 下端点 [个]，钳位目标 / DINT lower endpoint, clamping target
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与错误码预置：先归零，任何早退路径都不会留下脏码
 *      Preset return value and error code so no early-exit path leaves a stale code
 *-----------------------------------------------------------------------------*)
FC_DL_RoundSat := 0;           // 返回值预置 0 [个] / Preset return value to zero
eErr           := 16#0000_0000;   // 错误码预置无事件 / Preset error code to no event

(*------------------------------------------------------------------------------
 * 段 2｜非有限复检先行（防御声明①）：NaN / 无穷一律不进内建内核
 *      Non-finite recheck first (defense note 1): NaN and infinity never reach
 *      the built-in kernel
 *-----------------------------------------------------------------------------*)
IF (fX <> fX) OR (ABS(fX) > DL_RND_FINITE) THEN
    eErr := 16#0001_022B;   // 故障码：输入非有限（NaN / 无穷），返回 0 / Fault: non-finite input (NaN or infinity), zero returned
    RETURN;                 // 返回预置值 0 [个] / Return preset value zero
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜DINT 越界饱和闸（防御声明②④）：越界钳到端点并置信息码，
 *      绝不回绕；上/下端点对称处理
 *      DINT out-of-range saturation gate (defense notes 2 and 4): clamp to the
 *      endpoint with an informational code, never wrap; symmetric up and down
 *-----------------------------------------------------------------------------*)
IF fX >= DL_RND_HI THEN
    FC_DL_RoundSat := DL_RND_DMAX;   // 钳到 DINT 上端点 2147483647 [个] / Clamp to the DINT upper endpoint
    eErr := 16#0001_015B;            // 信息码：越界已钳位到上端点（不回绕）/ Informational: clamped to the upper endpoint, no wrap
    RETURN;                          // 饱和早退，不进内建 / Saturating early exit, built-in not called
END_IF

IF fX <= DL_RND_LO THEN
    FC_DL_RoundSat := DL_RND_DMIN;   // 钳到 DINT 下端点 -2147483648 [个] / Clamp to the DINT lower endpoint
    eErr := 16#0001_015B;            // 信息码：越界已钳位到下端点（不回绕）/ Informational: clamped to the lower endpoint, no wrap
    RETURN;                          // 饱和早退，不进内建 / Saturating early exit, built-in not called
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜域内委托内建内核（防御声明③）：阈值内侧必落在 DINT 域，
 *      委托内建 ROUND（四舍五入远离零，半值取向见头注释）
 *      In-domain delegation to the built-in kernel (defense note 3): inside
 *      the thresholds the result always fits DINT, delegate to the built-in
 *      ROUND (round half away from zero, see the half policy in the header)
 *-----------------------------------------------------------------------------*)
FC_DL_RoundSat := ROUND(fX);   // 委托内建 ROUND 内核，不自实现取整 / Delegate to the built-in ROUND kernel, no re-implementation
END_FUNCTION
