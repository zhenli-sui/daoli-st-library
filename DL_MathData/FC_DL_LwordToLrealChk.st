(*
    FC_DL_LwordToLrealChk —— LWORD 到 LREAL 精度告警转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 LWORD_TO_LREAL，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 LWORD 防御性转换为 LREAL 并作为返回值输出，转换委托平台内建 LWORD_TO_LREAL；
                nIn 超过 2^53（9007199254740992，双精度浮点尾数 53 位精度极限）时，
                值照常转换输出，仅置信息级 16#0001_020E 提示低位精度损失（bError=FALSE、bValid=TRUE）；
                与 FC_DL_LintToLrealChk 的职责边界：本件源类型为无符号 64 位位串，
                LWORD 无负值分支（类型系统保证），故不需要该件的双侧比较式；
                钳位方向：无钳位（信息级仅记录，转换结果为最接近的可表值）。
    错误码    : 16#0001_020E nIn 超 2^53 精度极限，转换值低位可能失真——信息级，正常防御
                16#0001_020F 预留禁用（信息级，不得挪用）
                16#0001_0303 预留禁用（故障级，不得挪用）
                16#0001_0304 预留禁用（故障级，不得挪用）
                16#0001_0305 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_LwordToLrealChk : LREAL
VAR_INPUT
    nIn : LWORD; // 待转换 64 位无符号位串，建议域 0 ~ 16#FFFF_FFFF_FFFF_FFFF [位] / 64-bit unsigned bit string to convert, suggested domain 0 .. 16#FFFF_FFFF_FFFF_FFFF [bit]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_F53_MAX : LWORD := 9007199254740992; // 双精度浮点尾数 53 位精度极限 2^53 [无量纲] / double-precision 53-bit mantissa precision limit 2^53 [dimensionless]
    DL_LREAL_ZERO : LREAL := 0.0;              // 返回值预置零（本件无故障路径，仅作预置约定） [无量纲] / preset zero, no fault path in this component [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LwordToLrealChk := DL_LREAL_ZERO; // 预置 0.0（本件无故障级路径，仅作预置约定） [无量纲] / preset 0.0, no fault-level path in this component [dimensionless]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过精度判定后置位 / preset invalid, set TRUE after the precision check

// 段 2｜53 位精度极限判定与主体转换（末段） / segment 2, 53-bit precision limit check and main conversion (final)
FC_DL_LwordToLrealChk := LWORD_TO_LREAL(nIn); // 值照常转换（委托平台内建转换语义），本件只告警不钳位 [无量纲] / convert as-is via the built-in conversion, this component warns but never clamps [dimensionless]
IF nIn > DL_LW_F53_MAX THEN // 无符号位串仅需上界单侧比较，负值分支由类型系统结构性排除 [位] / unsigned bit string only needs the upper-bound test, negative branch excluded by the type system [bit]
    eErr := 16#0001_020E; // 信息级：超 2^53 精度极限，低位可能失真，仅记录不钳位 / info level: beyond the 2^53 precision limit, low bits may lose accuracy, recorded only
ELSE
    eErr := 0;            // 精度域内无告警 / within the precision domain, no notice
END_IF
bError := FALSE; // 信息级精度告警不置故障 / info-level precision notice never raises fault
bValid := TRUE;  // 域内或精度告警输出均有效可用 / in-domain or precision-noticed output is valid
END_FUNCTION
