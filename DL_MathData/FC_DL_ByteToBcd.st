(*
    FC_DL_ByteToBcd —— 0~99 到 2 位 BCD 的编码
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（USINT 数值 → BYTE 容器 2 位 BCD）；
                域内委托平台内建 BYTE_TO_BCD，本件不重实现数学内核；
                上域闸门、满量程兜底口径、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 把 0~99 的数值编码成 2 位 BCD 写回拨码开关组态字、仪表设定寄存器，
                与 FC_DL_BcdToByte 构成双向对。
                核心防御：① 上域闸门先判：输入 > 99 时不做截断、不做模 100 折算，
                   直接按满量程 16#99 兜底并升故障级——写回方向宁给满量程也不给
                   「半错位值」，因为 100 编码成 16#00 会让设备读到 0，是危险的静默错；
                ② 域内才委托内建，域外调用内建的行为平台间不一致；
                ③ 边界值（0 与 99）发信息级提示，便于排查上游把哨兵值当设定值下发；
                ④ 合成路径（若平台缺内建）按「商 10 / 余 10 拼半字节」落地，
                   域内输入已保证两半字节 ≤ 9，无越界可能。
                职责边界：反向解码归 FC_DL_BcdToByte；4 位 Word 容器归 FC_DL_WordToBcd，
                8 位 Udint 容器归 FC_DL_UdintToBcd；本件只管 2 位拨码容器。
    编译门槛  : 主路径依赖平台内建 BYTE_TO_BCD，三平台标准库均提供。
                若目标平台缺该内建，按合成路径落地：uHi = uIn / 10、uLo = uIn MOD 10
                （两操作数恒为非负且 < 100，取余口径安全），再 uOut = SHL(uHi, 4) OR uLo。
    错误码    : 16#0001_041E 输入恰为域端点（0 或 99），已如实编码——信息级，值可用
                16#0001_041F 预留禁用（信息级，不得挪用）
                16#0001_034B 输入 > 99，已按满量程 16#99 兜底——故障级，bValid = FALSE
                16#0001_034C 预留（故障级，不得挪用）
                16#0001_034D 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_041E 用 / 16#0001_041F 预留 ｜ 16#0001_034B 用 / 16#0001_034C 预留 / 16#0001_034D 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_ByteToBcd : BYTE
VAR_INPUT
    uIn              : USINT;                 // 输入数值 [无量纲]，有效域 0~99 / input value [dimensionless], valid domain 0 to 99
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（输入越界为 FALSE）/ return usable, FALSE when the input is out of range
END_VAR
VAR CONSTANT
    DL_BCD_IN_MAX    : USINT := 99;           // 2 位 BCD 可表达的数值上限 [无量纲] / the largest value a 2-digit BCD can carry [dimensionless]
    DL_BCD_IN_MIN    : USINT := 0;            // 2 位 BCD 可表达的数值下限 [无量纲] / the smallest value a 2-digit BCD can carry [dimensionless]
    DL_BCD_FULL      : BYTE := 16#99;         // 满量程 BCD 兜底值 [位图] / full scale BCD fallback value [bitmap]
    DL_BYTE_ZERO     : BYTE := 16#00;         // 字节零常量，避免裸字面量 [位图] / byte zero constant [bitmap]
END_VAR
VAR
    uOut             : BYTE;                  // 结果中间量 [位图] / result intermediate [bitmap]
    uWork            : USINT;                 // 入参副本，避免改动调用方数据 [无量纲] / input copy, never modifies caller data [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_ByteToBcd := DL_BYTE_ZERO;              // 故障缺省返回 0 [位图] / fault default returns zero [bitmap]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
uOut := DL_BYTE_ZERO;                         // 结果中间量清零 / clear the result intermediate
uWork := uIn;                                 // 取入参副本参与判定 / copy the input for the comparisons

// 段 2｜上域闸门：越界即满量程兜底并升故障级（绝不静默截断）/ segment 2, upper gate, full scale fallback with a fault
IF uWork > DL_BCD_IN_MAX THEN
    FC_DL_ByteToBcd := DL_BCD_FULL;           // 满量程兜底 16#99 / fall back to the full scale BCD
    eErr := 16#0001_034B;                     // 故障级：输入超 2 位 BCD 域 / fault level, the input exceeds the 2-digit BCD domain
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值标记不可用 / flag the return as unusable
    RETURN;                                   // 出口，不触碰内建 / exit, the built-in is never touched
END_IF

// 段 3｜主体：域内才委托平台内建 / segment 3, delegate the built-in only inside the domain
uOut := BYTE_TO_BCD(USINT_TO_BYTE(uWork));    // 数值 → BCD 编码 [位图] / encode the number into BCD [bitmap]

// 段 4｜发布结果与域端点提示（信息级，不置 bError）/ segment 4, publish and hint the domain endpoints
FC_DL_ByteToBcd := uOut;                      // 输出 BCD 编码 [位图] / publish the BCD code [bitmap]
bValid := TRUE;                               // 域内编码可用 / the in-domain code is usable
IF (uWork = DL_BCD_IN_MIN) OR (uWork = DL_BCD_IN_MAX) THEN
    eErr := 16#0001_041E;                     // 信息级：输入恰为域端点，多为上游哨兵值 / info level, a domain endpoint, often an upstream sentinel
END_IF
END_FUNCTION
