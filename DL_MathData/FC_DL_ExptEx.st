(*
    FC_DL_ExptEx —— 幂运算防御包装（0 的负次幂 / 负底非整数次幂 / 溢出三类防护）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Exp
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R15）
    ------------------------------------------------------------------
    功能说明  : 求幂 lrBase 的 lrExp 次方。① NaN 拦截归零置 16#0001_0186；② 零底
                闸：|base|<1.0E-9 且 exp<0 返回 0.0 置 16#0001_0255（不可表示），
                exp=0 按惯例返回 1.0，exp>0 返回 0.0；③ 负底非整数指数
                闸：小数部分 |lrFrac|>1.0E-9 判为无实数解，返回 0.0 置
                16#0001_0187（|exp|>=2.0E9 时 ulp 大于 1 视为整数直通）；④ 溢出
                预判 exp*LN(|base|) 超阈值钳位极值置 16#0001_0254（保留符号：
                负底奇整数次幂钳到负极值）；⑤ 域内委托内建 EXPT，结果
                NaN/Inf 复检兜底。
    错误码    : 0000 正常 / 16#0001_0186 入参越界（NaN） / 16#0001_0254 上溢下溢（已钳位） / 16#0001_0187 负底非整数次幂无实数解 / 16#0001_0255 结果不可表示（0 的负次幂）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_ExptEx : LREAL
VAR_INPUT
    lrBase : LREAL; // 底数 [无量纲]，任意有限值或 NaN/无穷 / base value [dimensionless], any finite value or NaN/inf
    lrExp  : LREAL; // 指数 [无量纲]，任意有限值或 NaN/无穷 / exponent value [dimensionless], any finite value or NaN/inf
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界，2=上溢下溢，3=非法字符（负底非整数次幂），5=结果不可表示 / error id, 0=ok, 1=input out of domain, 2=overflow or underflow, 3=negative base with non-integer exponent, 5=result not representable
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，降级/钳位可用时 TRUE，不可表示时 FALSE / output valid, TRUE for usable degraded results, FALSE for non-representable cases
END_VAR
VAR
    lrFrac : LREAL; // 指数小数部分 [无量纲]，整数判定用 / fractional part of the exponent [dimensionless], for integer detection
    lrMag  : LREAL; // 结果幅值对数中间量 [无量纲]，exp 乘 LN 底绝对值 / log-magnitude intermediate [dimensionless], exponent times LN of base absolute value
    lrOut  : LREAL; // 计算结果中间量 [无量纲] / intermediate result [dimensionless]
    nPar   : DINT; // 指数整数部分 [无量纲]，奇偶判定用 / integer part of the exponent [dimensionless], for parity check
END_VAR
VAR CONSTANT
    DL_EP_EPS     : LREAL := 1.0E-9; // 浮点容差/零底判据 [无量纲] / tolerance and near-zero base threshold [dimensionless]
    DL_EP_OV      : LREAL := 709.782712893384; // 上溢预判阈值 [无量纲] / overflow pre-check threshold [dimensionless]
    DL_EP_UN      : LREAL := -745.1332191019411; // 下溢预判阈值 [无量纲] / underflow pre-check threshold [dimensionless]
    DL_EP_INTMAX  : LREAL := 2.0E9; // 指数 DINT 安全域 [无量纲]，超界视作整数 / exponent DINT safe bound [dimensionless], beyond treated as integer
    DL_EP_MAXREAL : LREAL := 1.7976931348623157E308; // 双精度有限极值 [无量纲] / double precision finite max [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
lrOut    := 0.0; // 结果中间量预置安全值 / preset intermediate result to safe value
eErr := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError   := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid   := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜NaN 拦截：任一入参为 NaN 一律归零早退 / segment 2, NaN interception, either input NaN zeroed early exit
IF (lrBase <> lrBase) OR (lrExp <> lrExp) THEN
    eErr := 16#0001_0186; // 信息级：输入 NaN，已归零 / informational, NaN input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    FC_DL_ExptEx := lrOut;
    RETURN;
END_IF

// 段 3｜零底闸：0 的负次幂不可表示置 16#0001_0255，0 的 0 次幂按惯例取 1.0 / segment 3, zero-base gate, zero to a negative power not representable with code 5, zero to zero as 1.0 by convention
IF ABS(lrBase) < DL_EP_EPS THEN
    IF lrExp < 0.0 THEN
        lrOut    := 0.0; // 0 的负次幂返回安全值 0.0 / zero to negative power returns safe value 0.0
        eErr := 16#0001_0255; // 结果不可表示 / result not representable
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    ELSIF lrExp = 0.0 THEN
        lrOut := 1.0; // 0 的 0 次幂按 IEEE 幂惯例取 1.0，精确零比较 / zero to zero as 1.0 per power convention, exact zero compare
    ELSE
        lrOut := 0.0; // 0 的正次幂恒为 0.0 / zero to a positive power is always 0.0
    END_IF
    FC_DL_ExptEx := lrOut;
    RETURN;
END_IF

// 段 4｜负底非整数指数闸：无实数解置 16#0001_0187；指数超 DINT 安全域时 ulp 大于 1 视作整数直通 / segment 4, negative base with non-integer exponent gate, no real solution with code 3, exponent beyond DINT safe bound treated as integer
IF lrBase < 0.0 THEN
    IF ABS(lrExp) < DL_EP_INTMAX THEN
        lrFrac := lrExp - DINT_TO_LREAL(TRUNC(lrExp)); // 指数小数部分 / fractional part of the exponent
        IF ABS(lrFrac) > DL_EP_EPS THEN
            lrOut    := 0.0; // 无实数解返回安全值 0.0 / no real solution, safe value 0.0
            eErr := 16#0001_0187; // 非法格式码：负底非整数次幂 / illegal format code, negative base with non-integer exponent
            bError   := TRUE; // 置错误标志 / raise error flag
            bValid   := FALSE; // 输出不可用 / output invalid
            FC_DL_ExptEx := lrOut;
            RETURN;
        END_IF
    END_IF
END_IF

// 段 5｜溢出/下溢预判闸：幅值对数先判后算，负底奇整数次幂钳位保留负号 / segment 5, overflow and underflow pre-check gates, negative base with odd integer exponent clamps to the negative extreme
lrMag := lrExp * LN(ABS(lrBase)); // 结果幅值的对数 [无量纲]，底非零保证 LN 安全 / log of result magnitude, base nonzero keeps LN safe
IF lrMag > DL_EP_OV THEN
    lrOut    := DL_EP_MAXREAL; // 上溢钳位到正极值 / overflow clamped to the positive extreme
    IF lrBase < 0.0 THEN
        nPar := TRUNC(lrExp); // 取指数整数部分 / take integer part of the exponent
        IF ABS(nPar MOD 2) = 1 THEN
            lrOut := -DL_EP_MAXREAL; // 奇数次幂钳到负极值保号 / odd power clamped to the negative extreme keeping the sign
        END_IF
    END_IF
    eErr := 16#0001_0254; // 上溢码：已钳位到类型极值 / overflow code, clamped to type extreme
    bError   := TRUE; // 置错误标志 / raise error flag
    // bValid 保持 TRUE：饱和值降级可用 / valid stays TRUE, saturated value usable
    FC_DL_ExptEx := lrOut;
    RETURN;
ELSIF lrMag < DL_EP_UN THEN
    lrOut    := 0.0; // 下溢钳位到 0.0 / underflow clamped to 0.0
    eErr := 16#0001_0254; // 下溢码 / underflow code
    bError   := TRUE; // 置错误标志 / raise error flag
    // bValid 保持 TRUE：下溢结果 0.0 降级可用 / valid stays TRUE, underflow 0.0 usable
    FC_DL_ExptEx := lrOut;
    RETURN;
END_IF

// 段 6｜域内委托内建 EXPT / segment 6, in-domain delegation to built-in EXPT
lrOut := EXPT(lrBase, lrExp); // 委托内建 EXPT 内核，不自实现幂内核 / delegate to built-in EXPT kernel

// 段 7｜结果复检兜底：NaN 归零置 16#0001_0255，超极值钳位置 16#0001_0254 / segment 7, result recheck, NaN zeroed with code 5, beyond-extreme clamped with code 2
IF lrOut <> lrOut THEN
    lrOut    := 0.0; // 兜底安全值 / bottom-line safe value
    eErr := 16#0001_0255; // 结果不可表示 / result not representable
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
ELSIF lrOut > DL_EP_MAXREAL THEN
    lrOut    := DL_EP_MAXREAL; // 防御纵深钳位 / defense in depth clamp
    eErr := 16#0001_0254; // 上溢码 / overflow code
    bError   := TRUE; // 置错误标志 / raise error flag
ELSIF lrOut < -DL_EP_MAXREAL THEN
    lrOut    := -DL_EP_MAXREAL; // 防御纵深钳位 / defense in depth clamp
    eErr := 16#0001_0254; // 上溢码 / overflow code
    bError   := TRUE; // 置错误标志 / raise error flag
END_IF
FC_DL_ExptEx := lrOut; // 输出幂结果 [无量纲] / output the power result
END_FUNCTION
