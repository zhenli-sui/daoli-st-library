(*==============================================================================
 * 组件名称 : FC_DL_ParityEvenLword ｜ 子库 : DL_Base ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 计算双字（32 位 DWORD 口径）的偶校验位：1 的个数为偶数返回
 *            TRUE。移位 + 异或折叠 WHILE 循环实现（错位 16→8→4→2→1），
 *            不使用任何校验库函数。字节/字族同算法扩位版。
 * 契约     : 返回 TRUE = 1 计数为偶（含全 0 双字）；输入 dwVal 任意双字；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 循环有界（错位每轮减半必归 0）
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 奇偶校验族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_ParityEvenLword : BOOL
VAR_INPUT
    dwVal : DWORD;      // 待校验双字（32 位 DWORD） / 32-bit double word to be parity-checked
END_VAR
VAR
    uX : DWORD;         // 异或折叠工作副本 / XOR-fold working copy
    nShift : INT;       // 当前错位量（16→8→4→2→1） / Current fold shift (16→8→4→2→1)
END_VAR
uX := dwVal;                        // 取工作副本 / Take working copy
nShift := 16;                       // 初错位 = 半字宽 / Initial shift = half width
WHILE nShift >= 1 DO                // 折叠循环，错位每轮减半必归 0 / Fold loop, shift halves each round
    uX := uX XOR SHR(uX, nShift);   // 错位异或，奇偶性保持 / XOR fold preserves ones-parity
    nShift := nShift / 2;           // 错位减半（整除截断）/ Halve the shift
END_WHILE
FC_DL_ParityEvenLword := (uX AND 16#0000_0001) = 16#0000_0000;      // 位 0 = 全双字 1 计数奇偶 / Bit0 = parity of ones count
END_FUNCTION
