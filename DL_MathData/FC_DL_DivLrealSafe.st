(*
    组件名称 : FC_DL_DivLrealSafe
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 浮点防御除法原子，把「除法前置防零」这条红线从散落各件的内联 IF 收成唯一出口。
              取舍 ①：微量分母判故障且不输出伪值 —— 绝不返回 0 冒充有效商，bValid 强制 FALSE，
              逼调用方写分支；返回 0 只会把异常静默带进后面的换算链。
              取舍 ②：溢出判据不用 ABS(商) > LREAL_MAX（商一旦溢出，比较式自身已无意义），
              改用「|分子| / LREAL_MAX > |分母|」等价变形：被除数恒为有限域，除法永不溢出，
              判据结构性安全（R54 预判式内禁乘除溢出的同类纪律）。
              取舍 ③：饱和值与除零分开定性 —— 商超有限域是「可观测的饱和」（bValid TRUE + 信息码），
              分母过小是「无结果」（bValid FALSE + 故障码），两者性质不同，绝不混为一谈。
    开源溯源 : 原创实现，红线手册第六节「除法前置防零」的落地载体；无外部源码参考，码位与分级 100% 自有。；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
    本文件内含 : FUNCTION FC_DL_DivLrealSafe（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 微量分母闸 + 阈值合法性闸 + 非有限闸 + 商饱和复检
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 全部阈值常量化
    错误码   : 16#0001_0436 [信息级] 商超有限域已饱和至 ±LREAL_MAX，bValid = TRUE，bError = FALSE
               16#0001_0437 [信息级] 预留禁用（不得挪用）
               16#0001_036F [故障级] |分母| < fDenEps（微量分母），返回 0，bValid = FALSE
               16#0001_0370 [故障级] 阈值参数 fDenEps ≤ 0，返回 0，bValid = FALSE
               16#0001_0371 [故障级] 输入含 NaN 或 ±INF，返回 0，bValid = FALSE
    码位总账 : 16#0001_0436 用 / 16#0001_0437 预留 ｜ 16#0001_036F 用 / 16#0001_0370 用 / 16#0001_0371 用
    遗留假设 : ① NaN 判据用自比较（x = x 为假），±INF 判据用 |x| > LREAL_MAX；两式均为 IEEE 754 语义推导，
              未在 InoProShop 上实测（该平台浮点异常屏蔽字配置未知，若开启 FPU 异常陷阱需先关）。
              ② 商饱和取 ±LREAL_MAX 而非 INF，饱和值可被下游有限性检查捕获，避免 INF 在后续乘法中扩散。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 1 入库
*)
FUNCTION FC_DL_DivLrealSafe : LREAL
VAR_INPUT
    fNum            : LREAL := 1.0;      // 分子，全域有限实数 [无量纲] / numerator, finite real [dimensionless]
    fDen            : LREAL := 1.0;      // 分母，|fDen| < fDenEps 即判故障 [无量纲] / denominator, a magnitude below fDenEps is a fault [dimensionless]
    fDenEps         : LREAL := 1.0E-12;  // 微量分母阈值，必须 > 0；≤ 0 判故障 [无量纲] / micro denominator threshold, must exceed zero [dimensionless]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;             // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;              // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;              // 商是否可用，FALSE 时调用方必须走故障分支 / quotient usable flag, the caller must branch when FALSE
    fRatio          : LREAL;             // 分母安全裕度 = |分母| / fDenEps，≥1 表示远离微量阈，仅调试观察 [倍] / denominator safety margin, debug only [ratio]
END_VAR
VAR
    bNumFin         : BOOL;              // 分子是否有限 / numerator finiteness
    bDenFin         : BOOL;              // 分母是否有限 / denominator finiteness
    bNegResult      : BOOL;              // 商的符号预判，供饱和时取号 / predicted sign of the quotient, used when saturating
    fQuot           : LREAL;             // 商工作寄存器 [无量纲] / quotient working register [dimensionless]
END_VAR
VAR CONSTANT
    DL_DIV_EPS          : LREAL := 1.0E-12;                     // 缺省微量分母阈值 [无量纲] / default micro denominator threshold [dimensionless]
    DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308;      // LREAL 最大有限值，饱和与有限性判据 [无量纲] / largest finite LREAL, saturation and finiteness bound [dimensionless]
    DL_LREAL_ONE        : LREAL := 1.0;                         // 单位哨兵，裕度除法前判分母幅值 [无量纲] / unity sentinel guarding the margin division [dimensionless]
    DL_LREAL_ZERO       : LREAL := 0.0;                         // 零哨兵，避免裸 0 参与比较 [无量纲] / zero sentinel [dimensionless]
    DL_ERR_NONE         : UDINT := 16#0000_0000;                // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置（四段式第一段）/ segment 1, preset the return value and the error state
FC_DL_DivLrealSafe := DL_LREAL_ZERO;    // 故障缺省返回 0 / fault default returns zero
eErr   := DL_ERR_NONE;                  // 预置无错误 / preset no error
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 预置结果不可用 / preset unusable
fRatio := DL_LREAL_ZERO;                // 预置裕度 0 / preset the margin to zero

// 段 2｜阈值合法性闸：阈值本身非法时任何比较都无意义 / segment 2, threshold legality gate
IF fDenEps <= DL_LREAL_ZERO THEN
    eErr   := 16#0001_0370;             // 阈值参数非法（故障级）/ illegal threshold parameter
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 3｜输入有限性闸：NaN 用自比较，±INF 用幅值越界，两式都必须是显式判据 / segment 3, input finiteness gate
bNumFin := (fNum = fNum) AND (ABS(fNum) <= DL_LREAL_MAX_FINITE);   // 自比较为假即 NaN；幅值越界即 INF / self compare catches NaN, the magnitude bound catches INF
bDenFin := (fDen = fDen) AND (ABS(fDen) <= DL_LREAL_MAX_FINITE);   // 与分子同一判据 / same finite test as for the numerator
IF (NOT bNumFin) OR (NOT bDenFin) THEN
    eErr   := 16#0001_0371;             // 输入非有限（故障级）/ non-finite input, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 4｜微量分母闸：域内分母过小一律判故障，不输出伪值 / segment 4, micro denominator gate, never emit a pseudo value
IF ABS(fDen) < fDenEps THEN
    eErr   := 16#0001_036F;             // 微量分母（故障级）/ micro denominator, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE；调用方必须走故障分支 / return zero, the caller must branch
END_IF

// 段 5｜分母裕度：|分母| ≤ 1 才做除法，避免调试量自身溢出（R54 口径）/ segment 5, margin computed without any overflowing multiply
IF ABS(fDen) > DL_LREAL_ONE THEN
    fRatio := DL_LREAL_MAX_FINITE;      // 分母远大于阈，裕度封顶表达 / the denominator is far above the threshold, cap the margin
ELSE
    fRatio := ABS(fDen) / fDenEps;      // 分母不超过 1，商不会溢出 / the denominator is at most one, the quotient cannot overflow
END_IF

// 段 6｜商溢出预判：|分子| / LREAL_MAX > |分母| 即商必超有限域，此时禁止直接除 / segment 6, overflow prediction before the division
bNegResult := ((fNum < DL_LREAL_ZERO) AND (fDen > DL_LREAL_ZERO)) OR ((fNum > DL_LREAL_ZERO) AND (fDen < DL_LREAL_ZERO)); // 异号即负商 / unlike signs give a negative quotient
IF (ABS(fNum) / DL_LREAL_MAX_FINITE) > ABS(fDen) THEN
    IF bNegResult THEN
        FC_DL_DivLrealSafe := -DL_LREAL_MAX_FINITE;   // 负向饱和 / saturate negative
    ELSE
        FC_DL_DivLrealSafe := DL_LREAL_MAX_FINITE;    // 正向饱和 / saturate positive
    END_IF
    eErr   := 16#0001_0436;             // 商超有限域已饱和（信息级，不置 bError）/ quotient saturated, info level
    bValid := TRUE;                     // 饱和值可观测，与除零性质不同，结果仍可用 / a saturated value is still observable and usable
    RETURN;                             // 带值返回 / return with the saturated value
END_IF

// 段 7｜域内委托：唯一一次真除法 / segment 7, the single genuine division inside the safe domain
fQuot := fNum / fDen;                   // 分母已过微量闸，商不会发散 / the denominator passed the micro gate, the quotient cannot blow up

// 段 8｜结果复检：预判之外的第二道保险，兜住判据边界误差 / segment 8, result re-check as the second line of defence
IF ABS(fQuot) >= DL_LREAL_MAX_FINITE THEN
    IF bNegResult THEN
        fQuot := -DL_LREAL_MAX_FINITE;  // 负向饱和 / saturate negative
    ELSE
        fQuot := DL_LREAL_MAX_FINITE;   // 正向饱和 / saturate positive
    END_IF
    eErr := 16#0001_0436;               // 商超有限域已饱和（信息级）/ quotient saturated, info level
END_IF

// 段 9｜出口 / segment 9, exit
FC_DL_DivLrealSafe := fQuot;            // 输出商 / publish the quotient
bValid := TRUE;                         // 结果可用 / the result is usable
END_FUNCTION
