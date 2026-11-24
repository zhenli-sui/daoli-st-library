(*
  ==================================================================
  组件名 Component  : FC_DL_ReverseBitsLword
  分类   Category   : DL_Base
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : LWORD 64 位序整体反转（ReverseBitsWord 的 64 位域升版变体）。
  来源   Source     : t2-1-lgf-bitlogic（位逻辑族 64 位变体）
  平台   Platform   : 纯 IEC 61131-3（FOR / SHL / SHR / AND / OR），三平台通用
  分工声明 Split     : 与 FC_DL_ReverseBitsWord（32 位域属主）分工——本件只做
                      LWORD 域，不重声明低位宽件；移位量恒为 1（R48 归一纪律：
                      全程无 ≥ 位宽的移位量，无拆半区）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 uSrc = 0 → uRev = 0 且 bValid = TRUE 恒成立（全零可逆）；
                      二 反转是全域双射：任何输入都有唯一合法输出，本件无钳位、
                         无故障路径，故按 R90 反证不加任何错误码（bError 恒假、
                         eErr 恒零，属声明性常量，沿 TwoStepConfirm bError 先例）；
                      三 无状态纯函数：局部量段 1 显式预置（R254）。
  错误码   Codes    : 无（R90 反证：反转全域可逆，无任何可故障场景，不加码）。
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 uSrc=16#0000_0000_0000_0001 → uRev=16#8000_0000_0000_0000
    V2 uSrc=16#8000_0000_0000_0000 → uRev=16#0000_0000_0000_0001
    V3 uSrc=0 → uRev=0、bValid=TRUE
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 1 · 序号 1）
  ==================================================================
*)
FUNCTION FC_DL_ReverseBitsLword : BOOL
VAR_IN_OUT
    uSrc : LWORD; // 待反转源字 [位图] / the source word to reverse
END_VAR
VAR_OUTPUT
    uRev   : LWORD;       // 反转结果字 [位图] / the reversed word
    bValid : BOOL;        // 结果可用标志（恒真：全域可逆）[-] / the validity flag, always true
    eErr   : UDINT;       // 错误码，0 = 正常（恒零：无故障路径）/ the error code, constant zero
    bError : BOOL;        // 错误标志（恒假：无故障路径，边界二）/ the error flag, constant false
END_VAR
VAR
    uWork : LWORD; // 移位工作副本（每拍右移一位耗尽）/ the shifting work copy
    k     : DINT;  // 位循环索引 [位] / the bit loop index
END_VAR

// 段 1｜返回值与输出预置（局部量显式预置，R254）/ segment 1, the preset of the return and the outputs
FC_DL_ReverseBitsLword := FALSE; // 返回值预置假 / preset the return false
uRev := 16#0000_0000_0000_0000; // 结果字预置零 / preset the result zero
bValid := FALSE; // 有效标志预置假（出口置真）/ preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假（全域可逆，无故障路径）/ preset the error flag false
uWork := uSrc; // 工作副本装入源字 / load the work copy from the source

// 段 2｜64 位逐位反转（移位量恒 1，结构性安全于 R48）/ segment 2, the bit by bit reversal with a constant shift of one
FOR k := 0 TO 63 DO // 有界循环恰好 64 次 / the bounded loop of exactly sixty four rounds
    uRev := SHL(uRev, 1) OR (uWork AND 16#0000_0000_0000_0001); // 结果左移一位并装入源字最低位 / shift the result left and append the lowest source bit
    uWork := SHR(uWork, 1); // 源字右移一位 / shift the source right
END_FOR

// 段 3｜出口（反转全域可逆，恒成功）/ segment 3, the outlet, always successful
bValid := TRUE; // 有效标志置真 / raise the validity
FC_DL_ReverseBitsLword := TRUE; // 返回成功 / return success
END_FUNCTION
