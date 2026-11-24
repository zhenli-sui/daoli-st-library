(*
    FC_DL_RorLwordEx —— LWORD 循环右移（MOD 64 归一）
    ------------------------------------------------------------------
    分类      : DL_Base / BitString
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 ROR，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : LWORD 位串循环右移防御包装：移位量 nN 大于等于 64（位宽）时按 MOD 64 归一，
                并置信息级 16#0001_020C（与循环左移件同口径，与左移/右移件的「超宽置零」刻意相反）；
                归一后移位量为 0 时直接输出原值，不调用内建 ROR；
                域内委托平台内建 ROR，不重实现移位内核；
                MOD 除子为常量 64（编译期恒非零），结构性满足除法前判除子非零红线；
                钳位方向：移位量按位宽取模归一（0~63），结果位宽严格保持 64 位。
    错误码    : 16#0001_020C 移位量 ≥ 64（位宽），已按 MOD 64 归一——信息级，正常防御
                16#0001_020D 预留禁用（信息级，不得挪用）
                16#0001_0300 预留禁用（故障级，不得挪用）
                16#0001_0301 预留禁用（故障级，不得挪用）
                16#0001_0302 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_RorLwordEx : LWORD
VAR_INPUT
    uIn : LWORD; // 被循环移位位串 [位] / bit string to be rotated [bit]
    nN  : USINT; // 循环移位量 [bit]，USINT 天然非负，范围 0~255 / rotate amount [bit], USINT is non-negative by type, range 0..255
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_WIDTH : USINT := 64; // LWORD 位宽常量，兼作 MOD 除子（编译期恒非零） [bit] / LWORD width constant, also the MOD divisor, never zero [bit]
END_VAR
VAR
    nShift : USINT; // 归一后的实际移位量 0~63 [bit] / normalized shift amount 0..63 [bit]
END_VAR

// 段 1｜输出与错误状态预置 / segment 1, preset output and error status
FC_DL_RorLwordEx := uIn; // 输出预置为原值（零移位等价语义），任何路径不留脏值 [位串] / preset output to the input, the zero-shift identity, no stale value on any path [bit string]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过归一后置位 / preset invalid, set TRUE after normalization

// 段 2｜移位量归一（MOD 位宽） / segment 2, shift amount normalization (modulo width)
nShift := nN; // 默认按原移位量直通 [bit] / pass the original shift amount through by default [bit]
IF nN >= DL_LW_WIDTH THEN // 循环移位对位宽取模仍等价，故归一而非置零 [bit] / rotate modulo the width stays equivalent, so normalize instead of zeroing [bit]
    nShift := nN MOD DL_LW_WIDTH; // 除子为编译期常量 64，恒非零 [bit] / divisor is the compile-time constant 64, never zero [bit]
    eErr := 16#0001_020C;         // 信息级：移位量已归一，正常防御 / info level: shift amount normalized, normal defence
ELSE
    eErr := 0;                    // 未超宽，无记录 / not oversized, nothing recorded
END_IF

// 段 3｜零移位量与域内委托循环移位（末段） / segment 3, zero-shift pass-through and in-domain delegated rotate (final)
IF nShift = 0 THEN
    FC_DL_RorLwordEx := uIn; // 零移位量直接输出原值，规避内建 ROR 的平台差异 [位串] / zero shift passes the input through, avoiding platform differences of built-in ROR [bit string]
ELSE
    FC_DL_RorLwordEx := ROR(uIn, nShift); // 域内委托平台内建 ROR，不重实现移位内核 [位串] / in-domain delegate to built-in ROR, shift kernel not re-implemented [bit string]
END_IF
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 归一后输出有效可用 / output is valid after normalization
END_FUNCTION
