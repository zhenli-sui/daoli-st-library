(*
  ==================================================================
  组件名 Component  : FC_DL_HammingDist
  分类   Category   : DL_Base
  版本   Version    : 1.0.0
  功能   Purpose    : 汉明距离：两 LWORD 位串逐位异或后统计 1 的个数（等价
                      popcount），输出 0~64。实现取「逐字节分治」口径：先整字
                      XOR 消除公共位，再按 8 字节循环、每字节 8 位内层计数，
                      双层 FOR 均以常量封顶（8/8），结构性无越界、无死循环；
                      移位量 8*i 最大 56 < 64，满足「移位量先归一」纪律。
  来源   Source     : t2-1-lgf-bitlogic（位逻辑族：借 popcount 分治计数口径，
                      实现零源码复制，全自研）
  互引   Cross-ref  : FC_DL_ReverseBitsLword（同族位序变换原子，上游可先做
                      位序归一再进本件；本件不调用它，仅声明同族关系）
  平台   Platform   : 纯 IEC 61131-3（XOR/SHR/AND/FOR），三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库定时器
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 无除法无浮点（整数域无除零面）/R5 全变量双语同行注释
                      R6 纯函数无状态机（CASE 不适用）/R7 无定时器与沿检测
                      R8 循环界与常量全局部化
  验收   Acceptance : V1 uA=uB → 0 ｜ V2 uA=0,uB=全 1 → 64 ｜
                      V3 uA=16#F0F0..,uB=16#0F0F.. → 64 ｜ V4 单 bit 差 → 1
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 1 序 1）
  ==================================================================
*)
FUNCTION FC_DL_HammingDist : UDINT
VAR_INPUT
    uA    : LWORD;  // 位串 A [位串] / bit string A [bits]
    uB    : LWORD;  // 位串 B [位串] / bit string B [bits]
END_VAR
VAR_OUTPUT
    uDist : UDINT;  // 汉明距离，0~64 [位] / Hamming distance, 0 to 64 [bit]
END_VAR
VAR
    uXor  : LWORD;  // 异或工作寄存器 [位串] / xor working register [bits]
    uWork : LWORD;  // 移位后的字节级工作量 [位串] / shifted word for byte extraction [bits]
    uByte : BYTE;   // 当前字节切片 [字节] / current byte slice [byte]
    i     : DINT;   // 外层字节循环变量，0~7 [索引] / outer byte loop index, 0 to 7 [index]
    j     : DINT;   // 内层位循环变量，0~7 [索引] / inner bit loop index, 0 to 7 [index]
END_VAR
VAR CONSTANT
    DHD_BYTE_NUM  : DINT := 8;      // LWORD 字节数，外层循环封顶 [字节] / bytes per LWORD, outer loop bound [byte]
    DHD_BIT_NUM   : DINT := 8;      // 每字节数，内层循环封顶 [位] / bits per byte, inner loop bound [bit]
    DHD_BIT_STEP  : DINT := 8;      // 每字节移位步距，8*i ≤ 56 < 64 [位] / shift step per byte [bit]
    DHD_ZERO      : UDINT := UDINT#0;  // 距离零哨兵 [位] / zero sentinel [bit]
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
uDist := DHD_ZERO;              // 距离预置 0 / preset distance to zero
FC_DL_HammingDist := DHD_ZERO;  // 返回值与输出同源（R191 名实双出口）/ the return mirrors the output

// 段 2｜整字异或：公共位归零，仅剩差异位 / segment 2, whole word xor keeps only the differing bits
uXor := uA XOR uB;              // 差异位图 [位串] / the difference bitmap [bits]

// 段 3｜逐字节 popcount：双层常量封顶 FOR / segment 3, per byte popcount with constant bounded loops
FOR i := 0 TO DHD_BYTE_NUM - 1 DO       // 8 字节全覆盖 / all 8 bytes covered
    uWork := SHR(uXor, i * DHD_BIT_STEP);  // 移位量 0/8/../56，恒小于 64，合规归一 / shift amounts stay below 64
    uByte := LWORD_TO_BYTE(uWork);         // 取低 8 位为字节切片 / take the low 8 bits as a byte slice
    FOR j := 0 TO DHD_BIT_NUM - 1 DO       // 字节内 8 位逐位判 / test the 8 bits inside the byte
        IF (uByte AND SHL(BYTE#1, j)) <> BYTE#0 THEN  // 掩码 1 左移 j 位，j ≤ 7 恒在字节域内 / mask one shifted by j stays inside the byte domain
            uDist := uDist + UDINT#1;      // 距离累加，上限 64 由位宽结构性保证 / accumulate, capped at 64 by width
        END_IF
    END_FOR
END_FOR

// 段 4｜返回值落位（与 uDist 同值）/ segment 4, publish the return equal to uDist
FC_DL_HammingDist := uDist;     // 名实双出口 / the named and the returned agree
END_FUNCTION
