(*
    FC_DL_SwapBytes64 —— LWORD 全字节逆序
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（LWORD 8 字节全逆序）；
                拆合本件自有的移位与掩码，字节逆序委托库内既有件 FC_DL_SwapBytes32
                （同库资产复用，R12 PortDiagBoard 先例），不重实现字节序内核；
                掩码常量、拆合顺序与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : EtherCAT / CANopen 伺服与智能仪表的 64 位累计量（绝对编码器位置、
                累计流量、电表总电量）按小端直出时，进 PLC 后必须做全字节逆序才与
                上位机的显示口径一致。字节序族已有 16 位与 32 位件，64 位一直是缺口。
                核心防御：① 移位量恒为 32，结构性小于 LWORD 位宽 64，
                   禁出现 SHL/SHR(x, 位宽) 这类跨平台未定义写法（R48 纪律）；
                ② 拆高低 32 位后各自委托 FC_DL_SwapBytes32 做四字节全反序，
                   再把低位的反序结果放到高位、高位反序结果放低位——
                   全字节逆序在 64 位域上等价于「两个 32 位各自逆序再交换半区」；
                ③ 掩码 16#0000_0000_FFFF_FFFF 全常量化，禁裸值；
                ④ 本件是全域双射：任何 LWORD 输入都有唯一确定的输出，不存在非法输入，
                   故信息槽与故障槽按规格全预留禁用，也不为「不存在的错误」虚构码位；
                ⑤ 多次调用幂等：逆序两次即还原，验收向量见下。
                验收向量：输入 16#0102_0304_0506_0708 输出 16#0807_0605_0403_0201。
                职责边界：16 位逆序归 FC_DL_SwapBytes16，32 位四排布归一归 FC_DL_SwapBytes32；
                本件只管 64 位全字节逆序。
    编译门槛  : 主路径依赖平台内建 SHL / SHR（ANY_BIT 语义）、LWORD_TO_DWORD、DWORD_TO_LWORD，
                以及 Standard.library 的位串函数，三平台标准库均提供。
                依赖库内 FC_DL_SwapBytes32 与其配套枚举 E_DL_ByteOrder（同子库，编译顺序无要求）。
    错误码    : 16#0001_0424 预留禁用（信息级，不得挪用——全双射无信息出口）
                16#0001_0425 预留禁用（信息级，不得挪用）
                16#0001_0354 预留禁用（故障级，不得挪用——全域双射不存在非法输入）
                16#0001_0355 预留禁用（故障级，不得挪用）
                16#0001_0356 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0424 预留 / 16#0001_0425 预留 ｜ 16#0001_0354 预留 / 16#0001_0355 预留 / 16#0001_0356 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_SwapBytes64 : LWORD
VAR_INPUT
    liIn             : LWORD;                 // 输入值 [位图]，全域 0~2^64−1 / input value [bitmap], full LWORD domain
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常（本件恒 0，五槽全预留）/ error id, always 0 here as all five slots are reserved
    bError           : BOOL;                  // 故障标志，本件恒 FALSE / error flag, always FALSE here
    bValid           : BOOL;                  // 返回值是否可用，本件恒 TRUE / return usable, always TRUE here
END_VAR
VAR CONSTANT
    DL_SHIFT_DWORD   : UINT := 32;            // 半区移位量 [bit]，结构性小于位宽 64 / half word shift [bit], structurally below the width of 64
    DL_MASK_LO32     : LWORD := 16#0000_0000_FFFF_FFFF; // 低 32 位掩码 [位图] / mask of the low 32 bits [bitmap]
    DL_LWORD_ZERO    : LWORD := 16#0000_0000_0000_0000;  // 长字零常量，避免裸字面量 [位图] / long word zero constant [bitmap]
END_VAR
VAR
    uDwHi            : DWORD;                 // 高 32 位半区 [位图] / the high 32-bit half [bitmap]
    uDwLo            : DWORD;                 // 低 32 位半区 [位图] / the low 32-bit half [bitmap]
    uDwHiRev         : DWORD;                 // 高半区四字节逆序结果 [位图] / byte reversed high half [bitmap]
    uDwLoRev         : DWORD;                 // 低半区四字节逆序结果 [位图] / byte reversed low half [bitmap]
    liOut            : LWORD;                 // 合成结果中间量 [位图] / composed result intermediate [bitmap]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_SwapBytes64 := DL_LWORD_ZERO;           // 缺省返回全零 [位图] / default returns all zero [bitmap]
eErr := 0;                                    // 五槽全预留，恒无错误 / all five slots are reserved, no error is ever raised
bError := FALSE;                              // 本件无故障出口 / no fault exit exists
bValid := FALSE;                              // 预置不可用，段 5 置位 / preset invalid, set TRUE in stage 5
liOut := DL_LWORD_ZERO;                       // 合成中间量清零 / clear the composition intermediate

// 段 2｜拆半区：移位量 32 恒小于位宽 64，掩码全常量化 / segment 2, split the halves safely
uDwHi := LWORD_TO_DWORD(SHR(liIn, DL_SHIFT_DWORD));      // 右移半区宽取高 32 位 [位图] / shift by the half width to take the high 32 bits [bitmap]
uDwLo := LWORD_TO_DWORD(liIn AND DL_MASK_LO32);          // 掩码取低 32 位 [位图] / mask the low 32 bits [bitmap]

// 段 3｜半区各自委托库内既有件做四字节全反序（不重实现字节序内核）/ segment 3, delegate each half to the existing library component
uDwHiRev := FC_DL_SwapBytes32(uRaw := uDwHi, eRawOrder := eDcba); // 高半区全反序 [位图] / byte reverse of the high half [bitmap]
uDwLoRev := FC_DL_SwapBytes32(uRaw := uDwLo, eRawOrder := eDcba); // 低半区全反序 [位图] / byte reverse of the low half [bitmap]

// 段 4｜合成：低半区反序结果进高 32 位，高半区反序结果进低 32 位 / segment 4, compose the reversed halves
liOut := SHL(DWORD_TO_LWORD(uDwLoRev), DL_SHIFT_DWORD) OR DWORD_TO_LWORD(uDwHiRev); // 全字节逆序结果 [位图] / the full byte reversed result [bitmap]

// 段 5｜发布结果 / segment 5, publish the result
FC_DL_SwapBytes64 := liOut;                   // 输出全字节逆序值 [位图] / publish the byte reversed value [bitmap]
bValid := TRUE;                               // 全域双射恒可用 / a total bijection is always usable
bError := FALSE;                              // 无故障出口（双保险）/ no fault exit exists, second line of defence
END_FUNCTION
