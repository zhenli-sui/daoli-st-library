(*
    FC_DL_ShrLwordEx —— LWORD 逻辑右移（超宽置零）
    ------------------------------------------------------------------
    分类      : DL_Base / BitString
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 SHR，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : LWORD 位串逻辑右移防御包装：移位量 nN 大于等于 64（位宽）时走常量路径直接输出全零，
                并置信息级 16#0001_0232，严禁把 nN ≥ 64 送进内建 SHR；
                nN < 64 时委托平台内建 SHR，不重实现移位内核；
                LWORD 为无符号位串，逻辑右移与算术右移等价，本件不做符号位扩展
                （若调用方需要符号语义，请先用显式类型转换，不得在本件内隐式判断）；
                nN 为 USINT 类型天然非负，负移位量结构性不可能；
                钳位方向：移位量超宽按「结果置 0」处理。
    错误码    : 16#0001_0232 移位量 ≥ 64（位宽），结果已置全零——信息级，正常防御
                16#0001_0209 预留禁用（信息级，不得挪用）
                16#0001_02FA 预留禁用（故障级，不得挪用）
                16#0001_02FB 预留禁用（故障级，不得挪用）
                16#0001_02FC 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_ShrLwordEx : LWORD
VAR_INPUT
    uIn : LWORD; // 被移位位串（无符号位串，无符号位扩展语义） [位] / bit string to be shifted, unsigned, no sign extension [bit]
    nN  : USINT; // 移位量 [bit]，USINT 天然非负，范围 0~255 / shift amount [bit], USINT is non-negative by type, range 0..255
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_WIDTH : USINT := 64;                        // LWORD 位宽常量 [bit] / LWORD width constant [bit]
    DL_LW_ZERO  : LWORD := 16#0000_0000_0000_0000;     // 超宽移位结果零值 [位串] / zero result of an oversized shift [bit string]
END_VAR

// 段 1｜输出与错误状态预置 / segment 1, preset output and error status
FC_DL_ShrLwordEx := DL_LW_ZERO; // 输出预置全零，任何路径不留脏值 [位串] / preset output to all zeros, no stale value on any path [bit string]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过移位量闸门后置位 / preset invalid, set TRUE after the shift-amount gate

// 段 2｜移位量闸门（超宽走常量路径，不调内建） / segment 2, shift amount gate (oversized takes the constant path, built-in not called)
IF nN >= DL_LW_WIDTH THEN // 移位量不小于位宽一律走常量路径，绝不送入内建 SHR [bit] / shift amounts not below the width always take the constant path and never reach built-in SHR [bit]
    FC_DL_ShrLwordEx := DL_LW_ZERO; // 结果置全零（无符号位串逻辑右移后高位全补 0） [位串] / result set to all zeros, logical right shift of an unsigned string fills zeros [bit string]
    eErr := 16#0001_0232;           // 信息级：超宽移位已置零，正常防御 / info level: oversized shift zeroed, normal defence
    bError := FALSE;                // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                 // 零结果本身有效可用 / the zero result itself is valid
    RETURN;                         // 常量路径即出口，内建 SHR 不被调用 / the constant path is the exit, built-in SHR is not called
END_IF

// 段 3｜域内委托移位（末段） / segment 3, in-domain delegated shift (final)
FC_DL_ShrLwordEx := SHR(uIn, nN); // 域内委托平台内建 SHR，不重实现移位内核 [位串] / in-domain delegate to built-in SHR, shift kernel not re-implemented [bit string]
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
