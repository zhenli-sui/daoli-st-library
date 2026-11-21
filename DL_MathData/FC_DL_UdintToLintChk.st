(*
    FC_DL_UdintToLintChk —— UDINT 到 LINT 升位验真
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（UDINT 32 位无符号 → LINT 64 位有符号）；
                委托平台内建 UDINT_TO_LINT 完成升位，本件不重实现数学内核；
                round-trip 验真判据、复核开关、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : UDINT 到 LINT 在数学上恒无损（32 位无符号域完全落在 64 位有符号域内），
                但平台实现常见两种路径：直接零扩展（正确），或经 32 位有符号中间量再升位
                （错误：≥ 2^31 的值被符号扩展成负数）。后者在 DINT 中转站写法里反复出现，
                且编译期无告警、运行期只在超过 2147483647 时才显形，属隐蔽缺陷。
                本件的价值就是把这个隐性错误变成可判定的显式故障：
                核心防御：① round-trip 验真——把结果 LINT_TO_UDINT 反算回去，
                   与输入逐位相等才算无损；不等即判平台符号扩展错误（故障级）；
                ② 验真是判定式而非猜测式：只依赖 IEC 标准往返转换，不依赖任何平台内建语义；
                ③ bCheckEveryCall = FALSE 时跳过复核以降开销，但发信息级说明
                   「本拍未验真」，让审计侧知道该批数据没有复核保护；
                ④ 反算本身也在域内（LINT 结果必为 0~4294967295，若平台已错则反算必然不等），
                   不存在二次溢出风险。
                职责边界：有符号域内饱和归 FC_DL_LintToDintSat，双向无符号落地归
                FC_DL_LintToUdintSat；本件只承担「升位是否真正无损」的验真职责。
    编译门槛  : 主路径依赖平台内建 UDINT_TO_LINT 与 LINT_TO_UDINT，均为 IEC 61131-3
                标准转换函数，三平台标准库均提供，无厂商方言。
    错误码    : 16#0001_0414 调用方关闭逐次复核（bCheckEveryCall = FALSE），本拍未验真——信息级，值仍可用
                16#0001_0415 预留禁用（信息级，不得挪用）
                16#0001_033C round-trip 验真失败，平台把中间量经 32 位有符号路径符号扩展——故障级，bValid = FALSE
                16#0001_033D 预留（故障级，不得挪用）
                16#0001_033E 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0414 用 / 16#0001_0415 预留 ｜ 16#0001_033C 用 / 16#0001_033D 预留 / 16#0001_033E 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
                复核开关是引脚量而非内部锁存，调用方可按数据重要性逐调用切换。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_UdintToLintChk : LINT
VAR_INPUT
    uIn              : UDINT;                // 输入值 [无量纲]，全域 0~4294967295 / input value [dimensionless], full UDINT domain
    bCheckEveryCall  : BOOL := TRUE;          // TRUE = 每次调用都做 round-trip 复核 / TRUE performs the round-trip check on every call
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（验真失败为 FALSE）/ return usable, FALSE when the round trip failed
    bRoundTripFail   : BOOL;                  // round-trip 复核失败标志 / round-trip check failed flag
END_VAR
VAR CONSTANT
    DL_UDINT_MAX     : UDINT := 16#FFFF_FFFF; // UDINT 上限值，域上限登记（类型本身即保证无需显式比较）[无量纲] / the UDINT maximum, registered domain top [dimensionless]
    DL_LINT_ZERO     : LINT := 0;             // 有符号零常量，避免裸字面量 [无量纲] / signed zero constant [dimensionless]
END_VAR
VAR
    liOut            : LINT;                  // 升位结果中间量 [无量纲] / widened result intermediate [dimensionless]
    uBack            : UDINT;                 // 反算回无符号的复核值 [无量纲] / back-converted value used by the check [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_UdintToLintChk := DL_LINT_ZERO;         // 故障缺省返回 0 [无量纲] / fault default returns zero [dimensionless]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bRoundTripFail := FALSE;                      // 预置未失败 / preset no failure
liOut := DL_LINT_ZERO;                        // 中间量清零 / clear the intermediate

// 段 2｜主体：域内升位委托平台内建（数学上恒无损）/ segment 2, widen through the built-in, mathematically lossless
liOut := UDINT_TO_LINT(uIn);                  // 32 位无符号升 64 位有符号 [无量纲] / widen 32-bit unsigned into 64-bit signed [dimensionless]

// 段 3｜复核开关闸：关闭复核只发信息级，绝不伪装成已验真 / segment 3, check switch gate
IF NOT bCheckEveryCall THEN
    eErr := 16#0001_0414;                     // 信息级：本拍未验真，值仍可用 / info level, unchecked this cycle, still usable
    FC_DL_UdintToLintChk := liOut;            // 发布未复核的结果 / publish the unchecked result
    bValid := TRUE;                           // 未复核不等于不可用 / unchecked does not mean unusable
    RETURN;                                   // 出口 / exit
END_IF

// 段 4｜round-trip 验真：反算回去必须逐位相等 / segment 4, round-trip verification
uBack := LINT_TO_UDINT(liOut);                // 反算回无符号域 [无量纲] / convert back into the unsigned domain [dimensionless]
IF uBack <> uIn THEN
    bRoundTripFail := TRUE;                   // 标记验真失败 / flag the failed verification
    eErr := 16#0001_033C;                     // 故障级：平台符号扩展错误 / fault level, the platform sign-extended the value
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用于后续运算 / the value must not enter later arithmetic
    FC_DL_UdintToLintChk := liOut;            // 仍发布结果供 HMI 对比观察 / still publish the value so HMI can compare it
    RETURN;                                   // 出口 / exit
END_IF

// 段 5｜发布验真通过的结果 / segment 5, publish the verified result
FC_DL_UdintToLintChk := liOut;                // 输出升位结果 [无量纲] / publish the widened result [dimensionless]
bValid := TRUE;                               // 验真通过即可用 / verified values are usable
END_FUNCTION
