(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitCount
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 AND / 减法 / WHILE，无任何厂商内建函数
 * 功能描述 (Function)   : 统计 32 位字中置 1 的位数（Hamming Weight / Population Count），
 *                         返回 0..32。用于多传感器投票表决、工位占用统计、报警字
 *                         严重度分级。采用 Brian Kernighan 法 uTemp AND (uTemp - 1)，
 *                         迭代次数等于置位数：全 0 输入零次、全 1 输入恰好 32 次，
 *                         避免逐位 FOR 的固定 32 次开销与差一错误。
 * 开源溯源 (Origin)     : 原创实现。Brian W. Kernighan 位计数法（公开经典算法，
 *                         见《The C Programming Language》习题 2-9），本处为 ST 重写。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ WHILE 防死锁计数器 + 无符号回绕前提注释
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_BitCount : USINT
VAR_INPUT
    uValue   : DWORD;    // 待统计的 32 位字 / 32-bit word to be counted
END_VAR
VAR_OUTPUT
    bValid   : BOOL;     // 计算完整标志，FALSE 表示触发循环保护 / Calculation complete flag, FALSE means loop guard tripped
    uErrorId : UDINT;    // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uTemp    : DWORD;    // 工作副本，循环中被逐位清零 / Working copy, bits cleared one by one inside the loop
    nCount   : USINT;    // 置位计数，值域 0..32 / Population count, range 0..32
    nGuard   : DINT;     // 循环防死锁计数器 / Loop deadlock guard counter
END_VAR
VAR CONSTANT
    DL_POPCOUNT_MAX_LOOP : DINT := 32;  // 迭代上限，等于 Brian Kernighan 法的理论上界 / Iteration limit equal to the theoretical bound
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与工作变量初始化：任何路径下返回值确定
 *      Initialize return value and working variables for deterministic results
 *-----------------------------------------------------------------------------*)
FC_DL_BitCount := 16#00;
bValid         := TRUE;
uErrorId       := 16#0000_0000;
uTemp          := uValue;
nCount         := 16#00;
nGuard         := 0;

(*------------------------------------------------------------------------------
 * 段 2｜Brian Kernighan 位计数（边界 B1/B2/B3）
 *      Brian Kernighan population count (boundaries B1/B2/B3)
 *      每次 uTemp AND (uTemp - 1) 精确清除最低位的 1，迭代次数 = 置位数
 *      前提：uTemp - 1 的无符号回绕仅在 uTemp 非零时安全，故"非零"写进
 *            WHILE 条件成为循环不变式，而非仅写在注释里的口头约定
 *      Premise: the unsigned wrap of (uTemp - 1) is safe only while uTemp <> 0,
 *               therefore the non-zero test lives in the WHILE condition itself
 *-----------------------------------------------------------------------------*)
WHILE (uTemp <> 16#0000_0000) AND (nGuard < DL_POPCOUNT_MAX_LOOP) DO
    uTemp  := uTemp AND (uTemp - 16#0000_0001);
    nCount := nCount + 16#01;
    nGuard := nGuard + 1;
END_WHILE;

(*------------------------------------------------------------------------------
 * 段 3｜循环完整性判定（边界 B2）
 *      Loop completeness check (boundary B2)
 *      判据取"残值是否归零"而非"计数器是否到顶"：全 1 输入在第 32 次迭代
 *      同时使残值归零与计数器到顶，若只比对计数器会误报循环保护
 *      The residual value is the criterion, not the guard counter: an all-ones
 *      input reaches both limits simultaneously and would be falsely flagged
 *-----------------------------------------------------------------------------*)
IF uTemp <> 16#0000_0000 THEN
    bValid   := FALSE;
    uErrorId := 16#0001_0004;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜结果回写（边界 B4/B5）：USINT 容量 255 远大于 32，无溢出风险
 *      Result write-back: USINT capacity 255 far exceeds 32, overflow impossible
 *-----------------------------------------------------------------------------*)
FC_DL_BitCount := nCount;
END_FUNCTION
