(*
  ==================================================================
  组件名 Component  : FC_DL_SignExtendEx
  分类   Category   : DL_Base
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_064D（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 取 DINT 的低 nWidth 位，按 bSigned 选择符号扩展或零扩展，结果落 DINT。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.3 位串 AND / OR / XOR / NOT 语义与位宽约定
  平台   Platform   : 纯 IEC 61131-3（AND / OR / XOR / NOT / 类型转换），三平台通用
  依赖   Depends    : 仅 Standard.library（无库调用）
  分工声明 Split     : FC_DL_BitFieldExtract 为无符号位段提取属主；FC_DL_WordToIntSat
                      为整字宽（16 位整字）饱和属主；本件为任意窄位宽的有符号/零扩展，
                      三者边界：多位段拼接用前者，整字溢出饱和用中者，窄位宽符号还原用本件。
  归属 Ownership     : 本件无 TYPE 声明；常量表 DL_SEXT_LO 为本文件私有常量。
  典型用途 Use      : Modbus 双字有符号量拼装（先拼 32 位再按 16 位符号还原）、
                      12 / 16 位 ADC 原始码还原、位域字段解包。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 nWidth 越域（< 1 或 > 32）判故障并早退返回 FALSE，禁静默钳位：
                         位宽错意味着调用方拼装逻辑已错，钳位后继续会掩盖协议错位；
                      二 全部掩码由单一预计算常量表 DL_SEXT_LO 派生：
                         低位掩码 = LO[n]；高位掩码 = LO[n] XOR 全 1；符号位 = LO[n] AND NOT LO[n-1]；
                         由此消灭运行时 SHL(x, nWidth)，nWidth = 32 时不触发未定义行为；
                      三 符号扩展只在符号位为 1 时 OR 高位掩码，否则零扩展路径不受污染；
                      四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_064D【故障级】位宽越域（nWidth < 1 或 > 32），diOut = 0，返回 FALSE
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 nWidth=1、bSigned=TRUE、diIn=1 → -1；diIn=0 → 0
    V2 nWidth=8、bSigned=TRUE：16#0000_00FF → -1；16#0000_007F → 127
    V3 nWidth=16、bSigned=TRUE：16#0000_8000 → -32768
    V4 nWidth=32：任意值原样返回（两种 bSigned 一致）
    V5 nWidth=0 → 0 + 码 064D + 返回 FALSE；V6 nWidth=33 → 同一处置
    V7 nWidth=4、bSigned=FALSE、diIn=16#F → 15（掩码后不扩符号）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 2 · 序号 4）
  ==================================================================
*)
FUNCTION FC_DL_SignExtendEx : BOOL
VAR_INPUT
    diIn    : DINT; // 待扩展值 [−]，完整 DINT 域 / the value to extend over the full DINT domain
    nWidth  : DINT; // 有效位宽 [位]，合法域 1..32 / the significant width in bits, legal one to thirty two
    bSigned : BOOL; // TRUE = 符号扩展，FALSE = 零扩展 [-] / true selects the sign extension, false the zero extension
END_VAR
VAR_OUTPUT
    diOut   : DINT;  // 扩展结果 [−] / the extended result
    eErr    : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL;  // 故障标志，故障级码同拍置位（R45 配对）/ the fault flag, raised with a fault level code
END_VAR
VAR
    udwIn   : DWORD := 16#0000_0000; // 输入位型 [位] / the input bit pattern in bits
    udwLo   : DWORD := 16#0000_0000; // 低 nWidth 位掩码 [位] / the low width mask in bits
    udwHi   : DWORD := 16#0000_0000; // 高位全 1 掩码 [位] / the high side all ones mask in bits
    udwSign : DWORD := 16#0000_0000; // 符号位单点掩码 [位] / the single bit sign mask in bits
    udwOut  : DWORD := 16#0000_0000; // 扩展后位型 [位] / the extended bit pattern in bits
VAR CONSTANT
    DL_SEXT_MINW : DINT := 1;            // 位宽下界 [位] / the width floor in bits
    DL_SEXT_MAXW : DINT := 32;           // 位宽上界（DINT 容器位宽）[位] / the width ceiling, the DINT container width
    DL_SEXT_ALL  : DWORD := 16#FFFF_FFFF; // 全 1 常量，用于取补 [位] / the all ones constant used for the complement
    DL_SEXT_LO : ARRAY[0..32] OF DWORD := // 低 n 位掩码表（第 n 项 = 低 n 位置 1），预计算禁运行时 SHL [位] / the precomputed low width mask table
    [
        16#0000_0000, // n = 0：无有效位 / n equals zero, no significant bit
        16#0000_0001, // n = 1 / one bit
        16#0000_0003, // n = 2 / two bits
        16#0000_0007, // n = 3 / three bits
        16#0000_000F, // n = 4 / four bits
        16#0000_001F, // n = 5 / five bits
        16#0000_003F, // n = 6 / six bits
        16#0000_007F, // n = 7 / seven bits
        16#0000_00FF, // n = 8：单字节 / one byte
        16#0000_01FF, // n = 9 / nine bits
        16#0000_03FF, // n = 10 / ten bits
        16#0000_07FF, // n = 11 / eleven bits
        16#0000_0FFF, // n = 12：12 位 ADC 原始码常用 / the usual twelve bit ADC raw code width
        16#0000_1FFF, // n = 13 / thirteen bits
        16#0000_3FFF, // n = 14 / fourteen bits
        16#0000_7FFF, // n = 15 / fifteen bits
        16#0000_FFFF, // n = 16：单字 / one word
        16#0001_FFFF, // n = 17 / seventeen bits
        16#0003_FFFF, // n = 18 / eighteen bits
        16#0007_FFFF, // n = 19 / nineteen bits
        16#000F_FFFF, // n = 20 / twenty bits
        16#001F_FFFF, // n = 21 / twenty one bits
        16#003F_FFFF, // n = 22 / twenty two bits
        16#007F_FFFF, // n = 23 / twenty three bits
        16#00FF_FFFF, // n = 24 / twenty four bits
        16#01FF_FFFF, // n = 25 / twenty five bits
        16#03FF_FFFF, // n = 26 / twenty six bits
        16#07FF_FFFF, // n = 27 / twenty seven bits
        16#0FFF_FFFF, // n = 28 / twenty eight bits
        16#1FFF_FFFF, // n = 29 / twenty nine bits
        16#3FFF_FFFF, // n = 30 / thirty bits
        16#7FFF_FFFF, // n = 31 / thirty one bits
        16#FFFF_FFFF  // n = 32：整容器 / the whole container
    ];
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, preset every outlet to its safe value
FC_DL_SignExtendEx := FALSE; // 返回值预置假 / preset the return false
diOut := 0; // 结果预置零 [−] / preset the result zero
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
udwIn := 16#0000_0000; // 输入位型清零 [位] / clear the input bit pattern
udwLo := 16#0000_0000; // 低位掩码清零 [位] / clear the low mask
udwHi := 16#0000_0000; // 高位掩码清零 [位] / clear the high mask
udwSign := 16#0000_0000; // 符号掩码清零 [位] / clear the sign mask
udwOut := 16#0000_0000; // 输出位型清零 [位] / clear the output bit pattern

// 段 2｜位宽域闸：越域判故障早退（边界一，禁静默钳位）/ segment 2, the width domain gate, no silent clamping
IF (nWidth < DL_SEXT_MINW) OR (nWidth > DL_SEXT_MAXW) THEN // 位宽越域 / the width is out of the domain
    eErr := 16#0001_064D; // 故障级：位宽越域 / fault grade, the width is out of the domain
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    diOut := 0; // 确定缺省值零 [−] / the deterministic default of zero
    RETURN; // 早退，禁钳后继续（钳位会掩盖调用方的协议错位）/ early return, clamping would hide a protocol misalignment
END_IF

// 段 3｜三张掩码由单一常量表派生（边界二，无运行时移位）/ segment 3, derive all three masks from the single precomputed table
udwIn := DINT_TO_DWORD(diIn); // 输入位型接管 [位] / take the input bit pattern
udwLo := DL_SEXT_LO[nWidth]; // 低 nWidth 位掩码 [位] / the low width mask
udwHi := udwLo XOR DL_SEXT_ALL; // 高位全 1 掩码 = 低掩码取补 [位] / the high mask is the complement of the low mask
udwSign := udwLo AND (NOT DL_SEXT_LO[nWidth - DL_SEXT_MINW]); // 符号位 = 第 nWidth 位（低 n 掩码与低 n-1 掩码之差）[位] / the sign bit is the n-th bit

// 段 4｜零扩展基线：先取低 nWidth 位（两条路径共用的第一段）/ segment 4, the zero extension baseline shared by both paths
udwOut := udwIn AND udwLo; // 低 nWidth 位保留，其余清零 [位] / keep the low width bits and clear the rest

// 段 5｜符号扩展：符号位为 1 才补高位全 1（边界三）/ segment 5, the sign extension only when the sign bit is set
IF bSigned THEN // 调用方要求符号扩展 / the caller asked for the sign extension
    IF (udwOut AND udwSign) <> 16#0000_0000 THEN // 符号位为 1 / the sign bit is set
        udwOut := udwOut OR udwHi; // 高位补全 1（nWidth = 32 时 udwHi 为零，等价原样返回）/ fill the high side, the width of thirty two yields a zero high mask and passes the value through
    END_IF
END_IF

// 段 6｜统一出口（位型还原为有符号结果）/ segment 6, the unified outlet
diOut := DWORD_TO_DINT(udwOut); // 位型还原 [−] / reinterpret the bit pattern as a signed value
FC_DL_SignExtendEx := TRUE; // 返回成功 / return success
END_FUNCTION
