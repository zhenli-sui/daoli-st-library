(*
    FC_DL_BcdToByte —— 2 位半字节 BCD 解码（BYTE 容器）
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（BYTE 容器 2 位 BCD → USINT 数值）；
                域内委托平台内建 BCD_TO_BYTE，本件不重实现数学内核；
                半字节合法性校验、满量程提示、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 拨码开关组态位、老式仪表组态字最常见的 2 位 BCD 编码（一个 BYTE 装 0~99），
                解码成 0~99 的数值参与比对。
                核心防御：① 先判后算——两个半字节都必须 ≤ 9 才允许进内建。
                   非法 BCD（如 16#1F、16#AA）在内建层的行为平台各不相同（有的翻转、
                   有的返回原值、有的置 0），是本件最不能容忍的不确定点；
                ② 校验只看半字节数值，不看容器大小，故 16#99 合法、16#FF 非法；
                ③ 满量程 99 发信息级提示：拨码全拨到 9 常是调试残留，
                   值本身合法，不该升故障级；
                ④ 合成路径（若平台缺内建）在容器校验之后做半字节乘加，
                   属校验后合成，不是重实现数学内核。
                职责边界：反向编码归 FC_DL_ByteToBcd；4 位 Word 容器归 FC_DL_BcdToWord，
                8 位 Udint 容器归 FC_DL_BcdToUdint；本件只管 2 位拨码容器。
    编译门槛  : 主路径依赖平台内建 BCD_TO_BYTE，三平台标准库均提供。
                若目标平台缺该内建，按合成路径落地：uOut = uHi * 10 + uLo，
                两半字节已由段 2 保证 ≤ 9，乘加结果必然 ≤ 99，无溢出可能。
    错误码    : 16#0001_041C BCD 值恰为满量程 99（多拨码开关调试残留）——信息级，值可用
                16#0001_041D 预留禁用（信息级，不得挪用）
                16#0001_0348 非法 BCD（某半字节 > 9）——故障级，返回 0
                16#0001_0349 预留（故障级，不得挪用）
                16#0001_034A 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_041C 用 / 16#0001_041D 预留 ｜ 16#0001_0348 用 / 16#0001_0349 预留 / 16#0001_034A 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_BcdToByte : USINT
VAR_INPUT
    uBcd             : BYTE;                  // BCD 编码值 [无量纲]，每半字节 0~9，合计 0~99 / BCD value [dimensionless], each nibble 0 to 9, total 0 to 99
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（非法 BCD 为 FALSE）/ return usable, FALSE on an illegal BCD
END_VAR
VAR CONSTANT
    DL_BCD_NIB_MAX   : BYTE := 9;             // 单个半字节的合法上限 [无量纲] / legal upper bound of one nibble [dimensionless]
    DL_BCD_MASK_LO   : BYTE := 16#0F;         // 低半字节掩码 [位图] / low nibble mask [bitmap]
    DL_BCD_SHIFT_HI  : USINT := 4;            // 高半字节移位量 [bit]，结构性小于 8 / the high nibble shift [bit], structurally below 8
    DL_BCD_FULL      : USINT := 99;           // 满量程值，用于提示 [无量纲] / full scale value used by the hint [dimensionless]
    DL_USINT_ZERO    : USINT := 0;            // 无符号零常量，避免裸字面量 [无量纲] / unsigned zero constant [dimensionless]
END_VAR
VAR
    uLo              : BYTE;                  // 低半字节 [无量纲] / the low nibble [dimensionless]
    uHi              : BYTE;                  // 高半字节 [无量纲] / the high nibble [dimensionless]
    uOut             : USINT;                 // 结果中间量 [无量纲] / result intermediate [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_BcdToByte := DL_USINT_ZERO;             // 故障缺省返回 0 [无量纲] / fault default returns zero [dimensionless]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
uOut := DL_USINT_ZERO;                        // 结果中间量清零 / clear the result intermediate

// 段 2｜半字节分解与合法性校验（先判后算，域外绝不进内建）/ segment 2, nibble split and legality gate
uLo := uBcd AND DL_BCD_MASK_LO;               // 低半字节 [无量纲] / extract the low nibble [dimensionless]
uHi := SHR(uBcd, DL_BCD_SHIFT_HI);            // 高半字节，移位量 4 结构性小于 8 [无量纲] / extract the high nibble, the shift stays below 8 [dimensionless]

IF (uLo > DL_BCD_NIB_MAX) OR (uHi > DL_BCD_NIB_MAX) THEN
    eErr := 16#0001_0348;                     // 故障级：非法 BCD，半字节超 9 / fault level, illegal BCD, a nibble exceeds nine
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_BcdToByte := DL_USINT_ZERO;         // 确定缺省值 0 / deterministic default of zero
    RETURN;                                   // 出口，不触碰内建 / exit, the built-in is never touched
END_IF

// 段 3｜主体：容器校验通过后委托平台内建 / segment 3, delegate the built-in after the container check
uOut := BYTE_TO_USINT(BCD_TO_BYTE(uBcd));     // BCD → 数值 [无量纲] / decode BCD into a number [dimensionless]

// 段 4｜发布结果与满量程提示（信息级，不置 bError）/ segment 4, publish and hint the full scale value
FC_DL_BcdToByte := uOut;                      // 输出解码值 0~99 [无量纲] / publish the decoded value 0 to 99 [dimensionless]
bValid := TRUE;                               // 合法 BCD 即可用 / a legal BCD is usable
IF uOut = DL_BCD_FULL THEN
    eErr := 16#0001_041C;                     // 信息级：满量程 99，多为拨码调试残留 / info level, full scale, often left over from commissioning
END_IF
END_FUNCTION
