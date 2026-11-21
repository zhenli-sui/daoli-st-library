(*
  ==================================================================
  组件名 Component  : FC_DL_BitScanLword
  分类   Category   : DL_Base
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : LWORD 最低/最高置位索引扫描（uIdx + bFound 双出口）。
  来源   Source     : self-std（IEC 标准位操作语义自研包装）
  平台   Platform   : 纯 IEC 61131-3（FOR / AND / SHR / SHL / 比较），三平台通用
  分工声明 Split     : 与 FC_DL_ReverseBitsLword（位序反转属主）分工——本件只做
                      置位索引定位，不改位序；方向由 bHighFirst 选择，不设两个 POU。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 全零输入：bFound = FALSE 且 uIdx = 0（不泄 -1，不泄哨兵），
                         置信息级码（R90 反证：bFound 只表达「有命中」，无法区分
                         「扫描过且全零」与「未扫」，码位补足该可观测性）；
                      二 扫描循环有界恰好 64 次（禁 WHILE 裸循环，防死锁纪律）；
                      三 方向选择：bHighFirst = FALSE 自低位向高位扫（首命中即
                         最低置位），TRUE 自高位向低位扫（首命中即最高置位）；
                      四 无状态纯函数：局部量段 1 显式预置（R254）。
  错误码   Codes    :
    16#0001_0641【信息级】全零输入零命中（bFound = FALSE，uIdx = 0）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 uSrc=16#0000_0000_0000_0100、bHighFirst=FALSE → uIdx=8、bFound=TRUE
    V2 uSrc=16#0000_0000_0000_0100、bHighFirst=TRUE → uIdx=8（单置位两向同值）
    V3 uSrc=16#0000_0000_0000_0105、bHighFirst=TRUE → uIdx=8
    V4 uSrc=0 → bFound=FALSE、uIdx=0、码 0641
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 1 · 序号 2）
  ==================================================================
*)
FUNCTION FC_DL_BitScanLword : BOOL
VAR_IN_OUT
    uSrc : LWORD; // 待扫描源字 [位图] / the source word to scan
END_VAR
VAR_INPUT
    bHighFirst : BOOL; // 方向开关：TRUE 自高位向低位扫 / the direction switch, true scans from the high end
END_VAR
VAR_OUTPUT
    uIdx   : UDINT; // 首命中置位索引 [位]，零命中时为 0 / the first hit bit index, zero on a miss
    bFound : BOOL;  // 是否存在置位位 [-] / the hit flag
    bValid : BOOL;  // 扫描完成标志（恒真：扫描全域有界）[-] / the scan done flag, always true
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志（信息级不置位，R285 口径）/ the error flag, never raised by the informational grade
END_VAR
VAR
    k : DINT; // 位循环索引 [位] / the bit loop index
END_VAR

// 段 1｜返回值与输出预置（局部量显式预置，R254）/ segment 1, the preset
FC_DL_BitScanLword := FALSE; // 返回值预置假 / preset the return false
uIdx := 0; // 索引预置零（零命中口径，边界一）/ preset the index zero
bFound := FALSE; // 命中标志预置假 / preset the hit flag false
bValid := FALSE; // 完成标志预置假（出口置真）/ preset the done flag false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false

IF uSrc = 16#0000_0000_0000_0000 THEN // 全零输入：零命中早出（边界一）/ the all zero source, a miss with the declared code
    eErr := 16#0001_0641; // 信息级：零命中（信息级不置 bError）/ informational, the miss without the fault bit
    bValid := TRUE; // 扫描完成 / the scan is done
    FC_DL_BitScanLword := TRUE; // 返回成功 / return success
    RETURN; // 早退 / early return
END_IF

// 段 2｜有界扫描：恰好 64 次，首命中即记（边界二）/ segment 2, the bounded scan of exactly sixty four rounds
IF NOT bHighFirst THEN // 自低位向高位 / from the low end
    FOR k := 0 TO 63 DO // 有界循环 / the bounded loop
        IF NOT bFound THEN // 尚未命中才继续判（首命中口径）/ judge only before the first hit
            IF (uSrc AND SHL(16#0000_0000_0000_0001, k)) <> 16#0000_0000_0000_0000 THEN // 第 k 位为置位 / the bit k is set
                uIdx := DINT_TO_UDINT(k); // 记录命中索引 / register the hit index
                bFound := TRUE; // 置命中标志 / raise the hit flag
            END_IF
        END_IF
    END_FOR
ELSE // 自高位向低位 / from the high end
    FOR k := 63 TO 0 BY -1 DO // 有界反序循环 / the bounded reverse loop
        IF NOT bFound THEN // 尚未命中才继续判 / judge only before the first hit
            IF (uSrc AND SHL(16#0000_0000_0000_0001, k)) <> 16#0000_0000_0000_0000 THEN // 第 k 位为置位 / the bit k is set
                uIdx := DINT_TO_UDINT(k); // 记录命中索引 / register the hit index
                bFound := TRUE; // 置命中标志 / raise the hit flag
            END_IF
        END_IF
    END_FOR
END_IF

// 段 3｜出口（源字非零已证，bFound 必为真）/ segment 3, the outlet, the hit is proven since the source is nonzero
bValid := TRUE; // 扫描完成 / the scan is done
FC_DL_BitScanLword := TRUE; // 返回成功 / return success
END_FUNCTION
