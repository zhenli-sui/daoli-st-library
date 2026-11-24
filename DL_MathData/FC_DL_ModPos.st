(*
    组件名称 : FC_DL_ModPos
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 恒正取模原子，返回恒非负余数 r ∈ [0, |m|-1]，消灭「负数取余」在三大平台上的符号歧义。
              取舍 ①：全文只允许一次 MOD —— 先按模数绝对值取余，再用「条件加法」把负余数搬回正域。
              禁二次取模（r := (v MOD m + m) MOD m），那是同一歧义的第二处实现，改一处必漏一处。
              取舍 ②：禁「先 ABS 再 MOD」。ABS(nValue) 在 nValue = DINT_MIN 处回绕成自身，会静默算错；
              本件只对模数取绝对值，并对 DINT_MIN 模数直接报故障。
              取舍 ③：模数为负时取绝对值后照算并发信息级提示 —— (-7) MOD (-3) 与 (-7) MOD 3 归一后同为 2，
              模数符号不影响数学结论，但调用方多半写错了，必须让它看得见而不是静默吞掉。
    开源溯源 : 原创实现。取模归一属 IEC 61131-3 MOD 运算符的防御性封装，无外部源码参考；；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              码位、错误分级、下界哨兵策略与注释 100% 自有。
    本文件内含 : FUNCTION FC_DL_ModPos（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 零模闸 + 下界闸 + 条件加法归一（无二次取模、无 ABS 单侧）
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 全部哨兵与下界常量化
    错误码   : 16#0001_0434 [信息级] 模数为负已取绝对值，结果照算，bError = FALSE，bValid = TRUE
               16#0001_0435 [信息级] 预留禁用（不得挪用）
               16#0001_036C [故障级] 模数为零，返回 0，bValid = FALSE
               16#0001_036D [故障级] 模数为 DINT 下界，取绝对值溢出，返回 0，bValid = FALSE
               16#0001_036E [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0434 用 / 16#0001_0435 预留 ｜ 16#0001_036C 用 / 16#0001_036D 用 / 16#0001_036E 预留
    遗留假设 : ① MOD 余数符号按 IEC 61131-3 取「与被除数同号」，本件的条件加法同时兼容「恒非负」与「同号」
              两种平台实现，故该假设失效也不改变结果 —— 此结论为推导，未在三平台逐一实测。
              ② 本件无内建转换链、无时间日期口径，编译门槛未见风险。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 1 入库
*)
FUNCTION FC_DL_ModPos : DINT
VAR_INPUT
    nValue          : DINT;   // 被除数，全域 -2147483648~2147483647 [无量纲] / dividend, full DINT domain [dimensionless]
    nModulus        : DINT;   // 模数，必须 ≠ 0；为负时取绝对值后照算 [无量纲] / modulus, must not be zero, negative modulus is taken by absolute value [dimensionless]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用，FALSE 时调用方必须走故障分支 / output valid flag, the caller must branch when FALSE
END_VAR
VAR
    nModAbs         : DINT;   // 模数绝对值，进入取模前恒 > 0 [无量纲] / absolute modulus, always positive before the MOD [dimensionless]
    nRem            : DINT;   // 余数工作寄存器，出口前被搬入正域 [无量纲] / remainder working register, moved into the positive domain before exit [dimensionless]
END_VAR
VAR CONSTANT
    DL_DINT_ZERO    : DINT := 0;             // 零哨兵，避免裸 0 参与比较 [无量纲] / zero sentinel, no bare zero in comparisons [dimensionless]
    DL_DINT_MIN     : DINT := -2147483648;   // DINT 下界，取绝对值回绕，必须单独拦截 [无量纲] / DINT lower bound whose absolute value wraps around [dimensionless]
    DL_DINT_MIN_ABS : DINT := -2147483647;   // 可直接取绝对值的下界哨兵（−MAX−1 的邻值）[无量纲] / lowest value that can be negated safely [dimensionless]
    DL_ERR_NONE     : UDINT := 16#0000_0000; // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置（四段式第一段）/ segment 1, preset the return value and the error state
FC_DL_ModPos := DL_DINT_ZERO;   // 故障缺省返回 0 / fault default returns zero
eErr         := DL_ERR_NONE;    // 预置无错误 / preset no error
bError       := FALSE;          // 预置无故障 / preset no fault
bValid       := FALSE;          // 预置结果不可用，通过全部闸门后置 TRUE / preset unusable, set TRUE after every gate
nModAbs      := nModulus;       // 先按原值占位，符号归一后会覆盖 / provisional copy, overwritten by the sign normalisation

// 段 2｜模数零闸：零模一律不进 MOD / segment 2, zero modulus gate, never enter the MOD
IF nModulus = DL_DINT_ZERO THEN
    eErr   := 16#0001_036C;     // 模数为零（故障级）/ zero modulus, fault level
    bError := TRUE;             // 置故障标志 / raise the fault flag
    RETURN;                     // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 3｜模数下界闸：DINT_MIN 取绝对值回绕成自身，必须拒算 / segment 3, lower bound gate, negating DINT_MIN wraps around
IF nModulus = DL_DINT_MIN THEN
    eErr   := 16#0001_036D;     // 模数下界不可表示其绝对值（故障级）/ modulus lower bound has no representable absolute value
    bError := TRUE;             // 置故障标志 / raise the fault flag
    RETURN;                     // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 4｜模数符号归一：负模取绝对值，信息级提示，结果照算 / segment 4, negative modulus is normalised, info level only
IF nModulus < DL_DINT_ZERO THEN
    nModAbs := -nModulus;       // 下界已拦，取负结构性安全 / the lower bound is already rejected, so negation is structurally safe
    eErr    := 16#0001_0434;    // 模数为负已取绝对值（信息级，不置 bError）/ negative modulus normalised, info level, never sets bError
END_IF

// 段 5｜全文唯一一次 MOD，然后条件加法把负余数搬回正域 / segment 5, the single MOD followed by one conditional add
nRem := nValue MOD nModAbs;     // 余数与被除数同号，负域需归一 / the remainder follows the dividend sign and must be normalised
IF nRem < DL_DINT_ZERO THEN
    nRem := nRem + nModAbs;     // 加一次模数即落回 [0, |m|-1]，不做二次取模 / one addition lands in [0, |m|-1], no second MOD
END_IF

// 段 6｜出口：结果是真值，bValid 置 TRUE / segment 6, exit with a genuine value
FC_DL_ModPos := nRem;           // 输出归一后的非负余数 / publish the normalised non-negative remainder
bValid       := TRUE;           // 结果可用（信息级不影响可用性）/ the result is usable, info codes never block it
END_FUNCTION
