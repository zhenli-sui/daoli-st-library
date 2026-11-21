(*
  Name        : FC_DL_BitCountOnes
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 位串置 1 计数（popcount）：逐位单热掩码扫描统计 DWORD 中为 1 的位数，输出 0..32；/ Population count of set bits in a DWORD, walking-one mask scan, result 0..32
  溯源        : 借 t2-1-lgf·bitlogic 的分类/参数域组织，clean-room 实现
  Boundary    : ① 位宽固定 32 位（DWORD 为跨平台最宽公共无符号型；LWORD 64 位需平台确认，本族另件）；
                ② 移位量恒 0..31 < 32，绝不出现 SHL(x, 位宽) 的未定义行为（末拍 SHL(16#80000000,1)=0 无害）；
                ③ 输出域钳位 0..32，防越界写入下游；
                ④ 输入 NaN 概念不适用（整型），无除零路径（纯位运算）。
*)
FUNCTION FC_DL_BitCountOnes : INT
VAR_INPUT
    dwBits     : DWORD := 0;                 (* 待计数位串，按 32 位解释 [-] / Bit string to count, 32-bit *)
    xEarlyExit : BOOL := TRUE;               (* 提前退出：剩余未扫描位已全 0 时终止循环（省周期）[-] / Early exit when remaining bits are zero *)
END_VAR
VAR
    dwMask : DWORD;                          (* 逐位单热掩码，初值 1 后每拍左移 1 位 [-] / Walking-one mask *)
    dwRest : DWORD;                          (* 剩余未扫描位串（早退出判据）[-] / Remaining unscanned bits *)
    nIdx   : INT;                            (* 位序号游标 0..31（FOR 自复位，R227）[-] / Bit index cursor 0..31 *)
    nAcc   : INT;                            (* 累加计数 0..32 [-] / Accumulated count 0..32 *)
END_VAR
VAR CONSTANT
    DL_BCO_WIDTH : INT   := 32;              (* DWORD 位宽（移位量上界基准，恒 < 本值）[位] / DWORD bit width *)
    DL_BCO_MAX   : INT   := 32;              (* 计数结果上限（防越界，R308）[位] / Count result ceiling *)
    DL_BCO_ONE   : DWORD := 1;               (* 单热掩码初值（最低位置 1）[-] / Initial walking-one mask *)
    DL_BCO_ZERO  : DWORD := 0;               (* 位串零常量（比较用，避免魔法数）[-] / Zero constant for comparison *)
END_VAR

(* —— 段 1：单拍量预清零（R107：每拍全路径派生，无跨拍残留） —— *)
nAcc := 0;                                   (* 累加器预清 / Accumulator preset *)
dwMask := DL_BCO_ONE;                        (* 掩码回到最低位 / Mask to LSB *)
dwRest := dwBits;                            (* 剩余位串取输入全量 / Remaining bits = input *)

(* —— 段 2：逐位扫描（FOR 上限 < 位宽，移位量归一，R28） —— *)
FOR nIdx := 0 TO DL_BCO_WIDTH - 1 DO
    IF (dwRest = DL_BCO_ZERO) AND xEarlyExit THEN
        EXIT;                                (* 剩余位全 0：提前终止，计数已定 / Early exit, count settled *)
    END_IF
    IF (dwBits AND dwMask) <> DL_BCO_ZERO THEN
        nAcc := nAcc + 1;                     (* 该位为 1：计数递增 / Bit set: increment *)
    END_IF
    dwRest := dwRest AND NOT dwMask;          (* 清除已扫描位（NOT 为按位取反，DWORD 语义） / Clear scanned bit *)
    dwMask := SHL(dwMask, 1);                 (* 掩码左移一位（1..31 < 32，无越界） / Shift mask left, amount < width *)
END_FOR

(* —— 段 3：输出饱和（硬限反算：极限值 32 为 INT 可表，安全） —— *)
IF nAcc < 0 THEN
    nAcc := 0;                                (* 下限兜底（理论不可达，防御性） / Lower bound fallback *)
ELSIF nAcc > DL_BCO_MAX THEN
    nAcc := DL_BCO_MAX;                       (* 上限饱和 32 [位] / Upper saturation to 32 *)
END_IF
FC_DL_BitCountOnes := nAcc;                  (* 函数返回：置 1 位数 / Return: number of set bits *)
END_FUNCTION
