(*
  ==================================================================
  组件名 Component  : FC_DL_BcdToDint
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0657（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : 8 位 BCD（DWORD 容器，8 个半字节）→ DINT，逐码元合法性闸，
                      任一半字节 > 9 判故障早退，禁静默按半字节折算。
  开源溯源 Origin    : 公开公式 clean-room，参考 BCD 编码公开工程语义（分类与参数域
                      借鉴，零代码复制），本件实现、闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 移位与位运算符（SHR / AND）
  平台   Platform   : 纯 IEC 61131-3（FOR / SHR / AND / 四则），三平台通用
  依赖   Depends    : 仅 Standard.library（无库调用）
  分工声明 Split     : FC_DL_BcdToByte / FC_DL_BcdToWord / FC_DL_BcdToUdint 为既有
                      BCD 解码族（BYTE / WORD / UDINT 位宽），本件补 DWORD 8 位宽
                      解码口，四件互引（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 域证明（写死）：8 位 BCD 最大 99999999 < 2147483647（DINT
                         上界），累加无溢出可能，故本件无溢出分支；
                      二 逐码元提取：SHR 移位量 4·k（k = 0..7）最大 28 < 32（DWORD
                         位宽），结构性安全（R48 移位量归一：移位量上界由循环界
                         常量证明，禁运行时可变移位量越位宽）；
                      三 任一码元 > 9 → 故障级码 + bBadDigit = TRUE + nOut = 0 +
                         三件套 + RETURN 早退（禁把 A~F 半字节静默折算）；
                      四 首个非法码元即早退（首因保序），bBadDigit 单点置位；
                      五 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      六 无全局、无外部变量、无物理地址、无指针。
  错误码 Codes      :
    16#0001_0657【故障级】非法码元（8 个半字节任一 > 9，首个非法位即早退）
  码位反证 Note     :
    本件仅一个故障场景：8 个码元的合法性出口组合完全同形（nOut = 0、bBadDigit =
    TRUE、bValid = FALSE），无法从输出区分「哪一位非法」，按 R90 只立一码，
    非法位序号不外显（如需位级定位由调用方自行逐半字节复扫）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 16#00000000 → 0；V2 16#99999999 → 99999999（精确无溢出）
    V3 16#0000000A → 故障 0657 + bBadDigit（禁折算）
    V4 16#12345678 → 12345678；V5 16#00000007 → 7（前导零）
    V6 高位半字节 16#A0000000 与低位 16#0000000F → 均故障（A/F 两端抽验）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 1 · 序号 1）
  ==================================================================
*)
FUNCTION FC_DL_BcdToDint : BOOL
VAR_INPUT
    udBcd   : DWORD := 16#00000000; // 8 位 BCD 输入 [码]，8 个半字节 / the eight digit BCD input in a double word container
END_VAR
VAR_OUTPUT
    nOut    : DINT := 0;            // 解码结果 [个]，非法码元时为 0 / the decoded result, zero when a digit is illegal
    bBadDigit : BOOL := FALSE;      // 非法码元标志（任一半字节 > 9）[-] / the illegal digit flag raised when any nibble exceeds nine
    bValid  : BOOL := FALSE;        // 结果可用 [-] / the result usable flag
    eErr    : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL := FALSE;        // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    k       : DINT := 0;  // 半字节遍历索引 [下标]，0..7 / the nibble traversal index from zero to seven
    nShift  : DINT := 0;  // 移位量 [位]，4·k ≤ 28 结构性安全 / the shift amount of four times the index, proven below the word width
    uDig    : USINT := 0; // 当前半字节码元 [位] / the current digit nibble
    nAcc    : DINT := 0;  // 十进制累加器（Horner 展开）[个] / the decimal accumulator of the Horner expansion
VAR CONSTANT
    DL_BCD_MASK  : DWORD := 16#0000000F; // 半字节掩码常量（提级禁魔法数）[-] / the nibble mask constant lifted out of the body
    DL_BCD_DIG9  : USINT := 9;           // 合法码元上界 [位] / the legal digit ceiling of nine
    DL_BCD_NIB   : DINT := 4;            // 每码元位宽 [位] / the nibble width of four bits
    DL_BCD_N     : DINT := 8;            // 码元总数 [个]（DWORD 恰 8 半字节，R57）/ the nibble count of eight aligned with the container
    DL_BCD_ZERO  : DINT := 0;            // 整型零常量 [个] / the integer zero constant
    DL_BCD_ONE   : DINT := 1;            // 整型一常量 [个] / the integer one constant
    DL_BCD_TEN   : DINT := 10;           // 十进制权值基数 [个] / the decimal weight base of ten
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and every outlet
FC_DL_BcdToDint := FALSE; // 返回值预置假 / preset the return false
nOut := DL_BCD_ZERO; // 结果预置零 [个] / preset the result zero
bBadDigit := FALSE; // 非法码元标志预置假 / preset the illegal digit flag false
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the error flag false
nAcc := DL_BCD_ZERO; // 累加器预置零 [个] / preset the accumulator zero
k := DL_BCD_ZERO; // 索引预置零 / preset the index zero
nShift := DL_BCD_ZERO; // 移位量预置零 [位] / preset the shift amount zero
uDig := 0; // 码元预置零 [位] / preset the digit zero

// 段 2｜逐码元提取与合法性闸（移位量 4·k ≤ 28 < 32 结构性安全，边界二）/ segment 2, the digit extraction with the structural shift bound
FOR k := DL_BCD_ZERO TO DL_BCD_N - DL_BCD_ONE DO // 有界遍历 8 个半字节（循环界常量证明，无死循环）/ the bounded traversal over eight nibbles proven by the constant loop bound
    nShift := DL_BCD_NIB * k; // 移位量 = 4·k，最大 28 [位] / the shift amount of four times the index, at most twenty eight
    uDig := DWORD_TO_USINT(SHR(udBcd, nShift) AND DL_BCD_MASK); // 提取当前半字节（SHR 后与掩码，常量提级）/ extract the current nibble by shifting then masking with the lifted constant
    IF uDig > DL_BCD_DIG9 THEN // 码元 > 9：非法（边界三，禁折算）/ a digit above nine is illegal, never folded silently
        bBadDigit := TRUE; // 置非法码元标志 / raise the illegal digit flag
        eErr := 16#0001_0657; // 故障级：非法码元 / fault grade, an illegal digit
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        bValid := FALSE; // 结果不可用 / the result is not usable
        nOut := DL_BCD_ZERO; // 结果强制归零（禁部分折算值外泄）/ force the result to zero so no partial fold leaks
        RETURN; // 早退（首因保序，边界四）/ early return with the first cause kept
    END_IF
    nAcc := (nAcc * DL_BCD_TEN) + USINT_TO_DINT(uDig); // Horner 十进制累加：nAcc = nAcc×10 + 码元 [个] / the Horner decimal accumulation, the domain proof in boundary one covers every step
END_FOR

// 段 3｜统一出口（域证明：nAcc ≤ 99999999 < DINT 上界，无溢出分支，边界一）/ segment 3, the unified outlet with the domain proof
nOut := nAcc; // 结果出口 [个] / the result outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_BcdToDint := TRUE; // 返回成功 / return success
END_FUNCTION
