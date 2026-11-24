(*
  Name        : FC_DL_PriorityEncodeWord
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 位串优先编码：返回最高或最低置 1 位的位序号（1..32），无置位返回 0 号哨兵；/ Priority encoding: return the bit number (1..32) of the highest or lowest set bit, sentinel 0 when none
  溯源        : 借 t2-1-lgf·bitlogic 的分类/参数域组织，clean-room 实现
  Boundary    : ① 位序号口径为 1 基（1..32），哨兵 0 表示「无置位」，二者不重叠；
                ② 移位量恒 0..31 < 32，禁 SHL(x, 位宽)；
                ③ 结果上限 32 钳位（防下游数组下标越界，R308）；
                ④ 纯位运算无除零；整型入参无 NaN 路径。
*)
FUNCTION FC_DL_PriorityEncodeWord : INT
VAR_INPUT
    dwBits   : DWORD := 0;                   (* 待编码位串（32 位解释）[-] / Bit string to encode, 32-bit *)
    xHighest : BOOL := TRUE;                 (* TRUE = 最高置位优先；FALSE = 最低置位优先 [-] / Highest-set or lowest-set priority *)
END_VAR
VAR
    nIdx   : INT;                            (* 位序号游标 0..31（FOR 自复位，R227）[-] / Bit index cursor 0..31 *)
    nFound : INT;                            (* 命中位号 1..32；0 = 无置位哨兵 [-] / Hit bit number 1..32, 0 = none *)
    dwMask : DWORD;                          (* 单热掩码，初值 1 后逐位左移 [-] / Walking-one mask *)
END_VAR
VAR CONSTANT
    DL_PEW_WIDTH : INT   := 32;              (* DWORD 位宽（移位量上界基准）[位] / DWORD bit width *)
    DL_PEW_NONE  : INT   := 0;               (* 无置位哨兵位号（与 1..32 不重叠）[-] / No-bit sentinel *)
    DL_PEW_ONE   : DWORD := 1;               (* 单热掩码初值 [-] / Initial mask *)
    DL_PEW_ZERO  : DWORD := 0;               (* 位串零常量 [-] / Zero constant *)
END_VAR

(* —— 段 1：单拍量预清零（每拍全路径派生，R107） —— *)
nFound := DL_PEW_NONE;                       (* 哨兵预置：仅命中分支改写 / Sentinel preset *)
dwMask := DL_PEW_ONE;                        (* 掩码从最低位起扫 / Mask starts at LSB *)

(* —— 段 2：逐位扫描（单循环 + 优先级策略，两口径同一遍历） —— *)
FOR nIdx := 0 TO DL_PEW_WIDTH - 1 DO
    IF (dwBits AND dwMask) <> DL_PEW_ZERO THEN
        IF xHighest THEN
            nFound := nIdx + 1;              (* 最高优先：持续覆盖，末次命中即最高位 / Highest: last hit wins *)
        ELSIF nFound = DL_PEW_NONE THEN
            nFound := nIdx + 1;              (* 最低优先：首个命中即锁定，后续不覆盖 / Lowest: first hit locks *)
        END_IF
    END_IF
    dwMask := SHL(dwMask, 1);                (* 掩码左移（1..31 < 32，无越界） / Shift mask, amount < width *)
END_FOR

(* —— 段 3：输出上限钳位（1..32 或哨兵 0，二者互斥且均在合法域） —— *)
IF nFound > DL_PEW_WIDTH THEN
    nFound := DL_PEW_WIDTH;                  (* 上限饱和 32：理论不可达，防御性 / Upper saturation, defensive *)
ELSIF nFound < DL_PEW_NONE THEN
    nFound := DL_PEW_NONE;                   (* 下限兜底到哨兵 / Lower fallback to sentinel *)
END_IF
FC_DL_PriorityEncodeWord := nFound;          (* 返回位号或哨兵 0 / Return bit number or sentinel 0 *)
END_FUNCTION
