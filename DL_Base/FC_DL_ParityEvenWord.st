(*==============================================================================
 * 组件名称 : FC_DL_ParityEvenWord ｜ 子库 : DL_Base ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 计算 16 位字的偶校验位：字中 1 的个数为偶数返回 TRUE。
 *            移位 + 异或折叠 WHILE 循环实现（错位 8→4→2→1），不使用
 *            任何校验库函数。字节族同算法扩位版。
 * 契约     : 返回 TRUE = 1 计数为偶（含全 0 字）；输入 wVal 任意字；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 循环有界（错位每轮减半必归 0）
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 奇偶校验族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_ParityEvenWord : BOOL
VAR_INPUT
    wVal : WORD;        // 待校验 16 位字 / 16-bit word to be parity-checked
END_VAR
VAR
    uX : WORD;          // 异或折叠工作副本 / XOR-fold working copy
    nShift : INT;       // 当前错位量（8→4→2→1） / Current fold shift (8→4→2→1)
END_VAR
uX := wVal;                         // 取工作副本 / Take working copy
nShift := 8;                        // 初错位 = 半字宽 / Initial shift = half width
WHILE nShift >= 1 DO                // 折叠循环，错位每轮减半必归 0 / Fold loop, shift halves each round
    uX := uX XOR SHR(uX, nShift);   // 错位异或，奇偶性保持 / XOR fold preserves ones-parity
    nShift := nShift / 2;           // 错位减半（整除截断）/ Halve the shift
END_WHILE
FC_DL_ParityEvenWord := (uX AND 16#0001) = 16#0000;     // 位 0 = 全字 1 计数奇偶 / Bit0 = parity of ones count
END_FUNCTION
