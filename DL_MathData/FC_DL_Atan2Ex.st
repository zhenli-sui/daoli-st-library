(*
    FC_DL_Atan2Ex —— 四象限反正切防御包装（y,x 双入参 + 双零定义 + NaN/Inf 复检）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Trig
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R15）
    ------------------------------------------------------------------
    功能说明  : 求四象限反正切 ATAN2(y,x)，返回 (-pi, pi]。处理次序写死：
                ① NaN 拦截归零早退；② 双零判据（|x|<1.0E-12 且 |y|<1.0E-12）
                返回 0.0 置 16#0001_017E 信息码（bError=TRUE、bValid=FALSE，需上层
                注意）；③ 近零 x 轴判向返回 ±pi/2；④ x>0 委托 ATAN(y/x)；
                ⑤ x<0 按 y 符号加/减 pi；⑥ IF 链尾无条件 ELSE 兜底返回
                0.0 置 16#0001_024B；⑦ 结果 NaN 复检兜底（拦截 Inf/Inf 组合毒值）。
                除法分支均在 |x|>=1.0E-12 保证下执行，无除零风险。
    错误码    : 0000 正常 / 16#0001_017C 入参越界 / 16#0001_017E 双零输入无定义（信息级） / 16#0001_024B 结果不可表示（兜底）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_Atan2Ex : LREAL
VAR_INPUT
    lrY : LREAL; // 纵分量 [无量纲]，任意有限值或 NaN/无穷 / y component [dimensionless], any finite value or NaN/inf
    lrX : LREAL; // 横分量 [无量纲]，任意有限值或 NaN/无穷 / x component [dimensionless], any finite value or NaN/inf
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，4=双零输入，5=结果不可表示 / error id, 0=ok, 4=double zero input, 5=result not representable
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，降级/兜底时为 FALSE / output valid, FALSE for degraded or fallback results
END_VAR
VAR
    lrOut : LREAL; // 计算结果中间量 [rad] / intermediate result [rad]
END_VAR
VAR CONSTANT
    DL_A2_EPS     : LREAL := 1.0E-12; // 双零/近零判据 [无量纲] / double-zero and near-zero threshold [dimensionless]
    DL_A2_PI      : LREAL := 3.1415926535897932; // 圆周率 [rad] / pi [rad]
    DL_A2_PI2     : LREAL := 1.5707963267948966; // 圆周率一半 [rad] / half pi [rad]
    DL_A2_MAXREAL : LREAL := 1.7976931348623157E308; // 双精度有限极值 [无量纲] / double precision finite max [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
lrOut      := 0.0; // 结果中间量预置安全值 / preset intermediate result to safe value
eErr   := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError     := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid     := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜NaN 拦截：任一分量为 NaN 一律归零早退 / segment 2, NaN interception, either component NaN zeroed early exit
IF (lrY <> lrY) OR (lrX <> lrX) THEN
    eErr := 16#0001_017C; // 信息级：输入 NaN，已归零 / informational, NaN input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    FC_DL_Atan2Ex := lrOut;
    RETURN;
END_IF

// 段 3｜四象限 IF/ELSIF 判定链，链尾含无条件 ELSE 兜底 / segment 3, quadrant if-elsif chain with unconditional else fallback
IF (ABS(lrX) < DL_A2_EPS) AND (ABS(lrY) < DL_A2_EPS) THEN
    lrOut    := 0.0; // 双零输入按约定返回 0.0 / double-zero input returns 0.0 by convention
    eErr := 16#0001_017E; // 信息级：双零输入无定义 / informational, double-zero input undefined
    bError   := TRUE; // 置错误标志以示上层注意 / raise error flag for upper layer attention
    bValid   := FALSE; // 约定值非真实角度 / conventional value is not a true angle
ELSIF ABS(lrX) < DL_A2_EPS THEN
    IF lrY > 0.0 THEN
        lrOut := DL_A2_PI2; // 正 y 轴 +pi/2 / positive y axis plus half pi
    ELSIF lrY < 0.0 THEN
        lrOut := -DL_A2_PI2; // 负 y 轴 -pi/2 / negative y axis minus half pi
    ELSE
        lrOut    := 0.0; // 理论不可达兜底 / theoretically unreachable fallback
        eErr := 16#0001_024B; // 结果不可表示 / result not representable
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    END_IF
ELSIF lrX > 0.0 THEN
    lrOut := ATAN(lrY / lrX); // 右半平面一/四象限 / right half plane quadrants 1 and 4, division guarded by the epsilon branch
ELSIF lrX < 0.0 THEN
    IF lrY >= 0.0 THEN
        lrOut := ATAN(lrY / lrX) + DL_A2_PI; // 左上半平面二象限 / upper-left half plane quadrant 2
    ELSE
        lrOut := ATAN(lrY / lrX) - DL_A2_PI; // 左下半平面三象限 / lower-left half plane quadrant 3
    END_IF
ELSE
    lrOut    := 0.0; // 无条件兜底分支，理论不可达 / unconditional fallback branch, theoretically unreachable
    eErr := 16#0001_024B; // 结果不可表示 / result not representable
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
END_IF

// 段 4｜结果 NaN 复检兜底：拦截 Inf/Inf 等组合产生的毒值 / segment 4, result NaN recheck, intercepts poisoned values from combinations like Inf over Inf
IF lrOut <> lrOut THEN
    lrOut := 0.0; // 兜底安全值 / bottom-line safe value
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_024B; // 结果不可表示 / result not representable
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    END_IF
END_IF

// 段 5｜有限性钳位复检与输出 / segment 5, finiteness clamp recheck and output
IF lrOut > DL_A2_MAXREAL THEN
    lrOut := DL_A2_MAXREAL; // 超极值钳位（防御纵深） / clamp beyond-extreme value, defense in depth
ELSIF lrOut < -DL_A2_MAXREAL THEN
    lrOut := -DL_A2_MAXREAL; // 超负极值钳位（防御纵深） / clamp beyond-negative-extreme value, defense in depth
END_IF
FC_DL_Atan2Ex := lrOut; // 输出四象限角 [rad] / output the quadrant angle
END_FUNCTION
