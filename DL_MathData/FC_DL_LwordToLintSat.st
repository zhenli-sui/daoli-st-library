(*
    FC_DL_LwordToLintSat —— LWORD 到 LINT 的上饱和
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（LWORD 64 位无符号 → LINT 64 位有符号）；
                域内委托平台内建 LWORD_TO_LINT，本件不重实现数学内核；
                上饱和出口、无损模式复核、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 与 R19 的 FC_DL_LintToUdintSat 构成 64 位交叉域对偶：那件把有符号落无符号，
                本件把无符号大计数落有符号域。
                核心防御：① 全件比较一律在 LWORD / LINT 字面量常量之间进行，
                   禁隐式跨符号域比较——64 位跨符号域的隐式提升在部分平台走无符号路径，
                   会让 9223372036854775807 与 9223372036854775808 判等（R56 纪律）；
                ② 超域值绝不进内建：LWORD_TO_LINT 在域外是回绕行为，平台间不一致，
                   这是本件与「直接强转」的本质区别；
                ③ 上饱和置 bSatHigh 供 HMI 显示封顶；无损模式下饱和升故障级；
                ④ 域内路径零钳位、零额外比较开销。
                职责边界：有符号落无符号归 FC_DL_LintToUdintSat，64 位无符号升有符号验真归
                FC_DL_UdintToLintChk（32 位端口）；本件只管 64 位上饱和。
    编译门槛  : 主路径依赖平台内建 LWORD_TO_LINT，IEC 61131-3 标准转换函数，
                三平台标准库均提供。LWORD 字面量采用 16# 十六进制形式，
                避免十进制超长字面量在部分编译器的解析差异。
    错误码    : 16#0001_041A 超 LINT 域已饱和至 9223372036854775807——信息级，值可用
                16#0001_041B 预留禁用（信息级，不得挪用）
                16#0001_0345 调用方要求无损（bRequireLossless = TRUE）却发生饱和——故障级，bValid = FALSE
                16#0001_0346 预留（故障级，不得挪用）
                16#0001_0347 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_041A 用 / 16#0001_041B 预留 ｜ 16#0001_0345 用 / 16#0001_0346 预留 / 16#0001_0347 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_LwordToLintSat : LINT
VAR_INPUT
    uIn              : LWORD;                 // 输入值 [无量纲]，全域 0~2^64−1 / input value [dimensionless], full LWORD domain
    bRequireLossless : BOOL := FALSE;         // TRUE = 发生饱和即判故障（计量/累计场景）/ TRUE turns any saturation into a fault
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（要求无损却饱和时为 FALSE）/ return usable, FALSE when saturated in lossless mode
    bSatHigh         : BOOL;                  // 上饱和发生（输入 > 9223372036854775807）/ high saturation occurred
END_VAR
VAR CONSTANT
    DL_LINT_MAX_AS_LWORD : LWORD := 16#7FFF_FFFF_FFFF_FFFF; // LINT 上限的 LWORD 形态，即 2^63−1 [无量纲] / the LINT maximum as LWORD, 2 to the 63 minus one [dimensionless]
    DL_LINT_MAX      : LINT := 9223372036854775807; // LINT 上限值 [无量纲] / the LINT maximum value [dimensionless]
    DL_LINT_ZERO     : LINT := 0;             // 有符号零常量，避免裸字面量 [无量纲] / signed zero constant [dimensionless]
END_VAR
VAR
    liOut            : LINT;                  // 结果中间量 [无量纲] / result intermediate [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LwordToLintSat := DL_LINT_ZERO;         // 故障缺省返回 0 [无量纲] / fault default returns zero [dimensionless]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bSatHigh := FALSE;                            // 预置未饱和 / preset no saturation
liOut := DL_LINT_ZERO;                        // 结果中间量清零 / clear the result intermediate

// 段 2｜上域闸：LWORD 与 LWORD 常量比较，绝不让比较隐式跨符号域 / segment 2, upper gate with LWORD constants only
IF uIn > DL_LINT_MAX_AS_LWORD THEN
    liOut := DL_LINT_MAX;                     // 上饱和至 LINT 上限 / saturate to the LINT maximum
    bSatHigh := TRUE;                         // 标记上饱和 / flag the high saturation
    eErr := 16#0001_041A;                     // 信息级：超 LINT 域已饱和 / info level, saturated beyond the LINT domain
ELSE
    // 段 3｜域内才委托内建（域外调用是回绕不一致的根源）/ segment 3, delegate only inside the domain
    liOut := LWORD_TO_LINT(uIn);              // 域内无损降位 [无量纲] / lossless narrowing inside the domain [dimensionless]
END_IF

// 段 4｜无损模式复核（要求无损却发生饱和即故障级）/ segment 4, lossless recheck
IF bRequireLossless AND bSatHigh THEN
    eErr := 16#0001_0345;                     // 故障级：要求无损却发生饱和 / fault level, saturation under the lossless requirement
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可进结算 / the value must not enter settlements
    FC_DL_LwordToLintSat := liOut;            // 仍发布钳位值供 HMI 观察 / still publish the clamped value for observation
    RETURN;                                   // 出口 / exit
END_IF

// 段 5｜发布结果 / segment 5, publish the result
FC_DL_LwordToLintSat := liOut;                // 输出 64 位有符号结果 [无量纲] / publish the signed 64-bit result [dimensionless]
bValid := TRUE;                               // 直通或钳位均可用 / usable either way
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION
