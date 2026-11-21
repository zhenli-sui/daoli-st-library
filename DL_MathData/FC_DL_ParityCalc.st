(*
    FC_DL_ParityCalc —— 奇/偶校验位计算（位宽显式参数 + 无效位宽拒算）
    ------------------------------------------------------------------
    分类      : DL_MathData / Data-Integrity
    前缀      : FC_DL_
    版本      : 1.0.0
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （纯位运算循环，无内建校验内核依赖；未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_LwordBitCount（位计数）、FC_DL_Crc16Generic（CRC 族）
                分工——BitCount 返回置位总数，本件只做奇/偶校验位单出口；
                CRC 为多项式校验，与本件奇偶口径互不替代。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 对 LWORD 数据低 nWidth 位计算奇/偶校验位。位宽域 [1, 64]，
                越域拒算置错误（等效钳位语义：非法值不执行任何位运算）；
                偶校验 = 置位总数模 2；奇校验 = 偶校验取反。移位量恒为 1，
                结构性安全（R48）。
    错误码    : 0000 正常 / 16#0003_0005 位宽越域拒算
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 3 · 序号 13）
*)
TYPE E_DL_ParityMode :
(
    eEven := 0, // 偶校验：置位总数为偶时校验位 0 / even parity, a zero bit when the set count is even
    eOdd  := 1  // 奇校验：置位总数为奇时校验位 0 / odd parity, a zero bit when the set count is odd
);
END_TYPE

FUNCTION FC_DL_ParityCalc : BOOL
VAR_INPUT
    uData  : LWORD; // 被校验数据（仅低 nWidth 位参与）[-] / the checked data, only the low nWidth bits participate
    nWidth : INT;   // 参与校验的位宽 [位]，域 1..64 / the participating width [bit], one through sixty four
    eMode  : E_DL_ParityMode := E_DL_ParityMode.eEven; // 校验模式 [枚举] / the parity mode [enum]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid : BOOL;  // 结果是否可用，拒算时为假 / the result usable, false when rejected
END_VAR
VAR
    uMask  : LWORD; // 位测试掩码 [-] / the bit test mask
    nI     : INT;   // 循环计数 [位] / the loop counter
    nOnes  : INT;   // 置位总数 [个] / the set bit count
    bBit   : BOOL;  // 当前位为 1 [-] / the current bit set
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_ParityCalc := FALSE; // 校验位预置 0 / preset the parity bit to zero
eErr   := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
bValid := TRUE; // 有效标志预置真 / preset the valid flag true

// 段 2｜位宽域闸：越域拒算（边界十三）/ segment 2, the width gate, out of domain rejects
IF (nWidth < 1) OR (nWidth > 64) THEN // 位宽非法 / an illegal width
    eErr   := 16#0003_0005; // 错误级：位宽越域拒算 / error grade, an out of domain width rejected
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 FALSE / return the preset safe false
END_IF

// 段 3｜逐位测试计数：移位量恒 1，结构性安全（R48）/ segment 3, the bit by bit tally, the shift amount always one
uMask := LWORD#1; // 掩码从最低位起步 / the mask starts at the lowest bit
nOnes := 0; // 置位计数清零 / clear the tally
FOR nI := 1 TO nWidth DO // 有界循环（nWidth 已证 1..64）/ the bounded loop
    bBit := (uData AND uMask) <> LWORD#0; // 当前位测试 / the current bit test
    IF bBit THEN // 置位 / a set bit
        nOnes := nOnes + 1; // 计数推进 / advance the tally
    END_IF
    IF nI < nWidth THEN // 末位后不再移位（防 64 位移出丢失语义位）/ no shift after the last bit
        uMask := SHL(uMask, 1); // 掩码左移 1 位（移位量常量）/ shift the mask left by one
    END_IF
END_FOR

// 段 4｜奇偶模式判定（nOnes 非负，MOD 合法）/ segment 4, the parity verdict, the modulus on a nonnegative tally
IF eMode = E_DL_ParityMode.eEven THEN // 偶校验 / the even mode
    FC_DL_ParityCalc := (nOnes MOD 2) = 1; // 置位总数为奇时校验位 1 / the parity bit one on an odd tally
ELSIF eMode = E_DL_ParityMode.eOdd THEN // 奇校验 / the odd mode
    FC_DL_ParityCalc := (nOnes MOD 2) = 0; // 置位总数为偶时校验位 1 / the parity bit one on an even tally
ELSE // 非法模式兜底 / the illegal mode fallback
    eErr   := 16#0003_0005; // 错误级：模式非法拒算 / error grade, an illegal mode rejected
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    FC_DL_ParityCalc := FALSE; // 返回安全值 / return the safe value
END_IF
END_FUNCTION
