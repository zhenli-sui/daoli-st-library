(*
    FC_DL_DintToRealChk —— DINT 到 REAL 精度告警转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 DINT_TO_REAL，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 DINT 防御性转换为 REAL 并作为返回值输出，转换委托平台内建 DINT_TO_REAL；
                |nIn| 超过 2^24（16777216，REAL 尾数 24 位可精确表示的整数上界）时，
                值照常转换输出，仅置信息级 16#0001_01FC 提示低位精度损失（bError=FALSE、bValid=TRUE）；
                极值对称性防御：采用双侧比较 nIn > 上界 OR nIn < -上界，
                禁用 ABS(nIn) 单侧比较（对 DINT 最小值无回绕，但保持与 R16 LintToLrealChk 同范式，避免后续升位改造引入回绕）；
                钳位方向：无钳位（信息级仅记录，转换结果为最接近的可表值）。
    错误码    : 16#0001_01FC |nIn| 超 2^24 精度极限，转换值低位可能失真——信息级，正常防御
                16#0001_01FD 预留禁用（信息级，不得挪用）
                16#0001_02E8 预留禁用（故障级，不得挪用）
                16#0001_02E9 预留禁用（故障级，不得挪用）
                16#0001_02EA 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_DintToRealChk : REAL
VAR_INPUT
    nIn : DINT; // 待转换整数值，建议域 ±2147483647 [无量纲] / integer value to convert, suggested domain +/-2147483647 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_F24_MAX : DINT := 16777216; // REAL 尾数 24 位可精确表示的整数上界 2^24 [无量纲] / 2^24 exact-integer bound of REAL's 24-bit significand [dimensionless]
    DL_REAL_ZERO : REAL := 0.0;    // 返回值预置零（本件无故障路径，仅作预置约定） [无量纲] / preset zero, no fault path in this component [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DintToRealChk := DL_REAL_ZERO; // 预置 0.0（本件无故障级路径，仅作预置约定） [无量纲] / preset 0.0, no fault-level path in this component [dimensionless]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过精度判定后置位 / preset invalid, set TRUE after the precision check

// 段 2｜24 位尾数精度极限判定与主体转换（末段） / segment 2, 24-bit significand precision check and main conversion (final)
FC_DL_DintToRealChk := DINT_TO_REAL(nIn); // 值照常转换（委托平台内建转换语义），本件只告警不钳位 [无量纲] / convert as-is via the built-in conversion, this component warns but never clamps [dimensionless]
IF (nIn > DL_F24_MAX) OR (nIn < -DL_F24_MAX) THEN // 双侧比较，禁用 ABS 单侧式 [无量纲] / two-sided comparison, single-sided ABS form forbidden [dimensionless]
    eErr := 16#0001_01FC; // 信息级：超 2^24 精度极限，低位可能失真，仅记录不钳位 / info level: beyond the 2^24 precision limit, low bits may lose accuracy, recorded only
ELSE
    eErr := 0;            // 精度域内无告警 / within the precision domain, no notice
END_IF
bError := FALSE; // 信息级精度告警不置故障 / info-level precision notice never raises fault
bValid := TRUE;  // 域内或精度告警输出均有效可用 / in-domain or precision-noticed output is valid
END_FUNCTION
