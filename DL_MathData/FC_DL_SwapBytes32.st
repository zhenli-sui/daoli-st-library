(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SwapBytes32
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 SHL / SHR / AND / OR，零厂商方言
 * 功能描述 (Function)   : 32 位量四排布（ABCD / DCBA / BADC / CDAB）归一化转换。
 *                         调用方声明通信侧原始拼接值实际所属的排布，
 *                         函数统一输出 ABCD（大端大字）归一化值。
 *                         语义锁定为单向归一化，不做双向目标排布选择；
 *                         需要反向时以对称排布重新声明即可（四排布两两互逆）。
 *                         用于 Modbus 多寄存器浮点/长整型量"读回 1e38 天文数字"的定位与校正。
 * 开源溯源 (Origin)     : 原创实现。四种排布命名与业界别名（字交换 / 寄存器内字节互换 /
 *                         全反序）参照 modbus.org 公开协议说明与多家转换器技术资料的
 *                         事实约定；本文件为独立重构，未复制任何源码。
 * 本文件内含       : TYPE  E_DL_ByteOrder（配套枚举，归属 DL_MathData）
 *                    FC    FC_DL_SwapBytes32
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: SHL / SHR
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 移位掩码提取 + 显式类型转换，无切片/指针/字节方言
 *                         R4 N/A（无除法/数组/循环/浮点）｜ R5 ✓ 全变量中英双语同行注释
 *                         R6 ✓ 四排布 CASE 分派 + ELSE 兜底 ｜ R7 N/A（无定时器/边沿实例）
 *                         R8 ✓ 移位量与掩码全常量化
 *
 * 【实现选择 / Implementation choice（边界 B6）】
 *   四条转换路径全部用"移位提取 + 显式 BYTE 转换 + 移位重装"实现，
 *   不调用 16 位互换构件，保证本文件自洽、可单独编译与单独单测。
 *
 * 【浮点使用口径 / Float usage（边界 B7）】
 *   本函数只输出归一化 DWORD，不做 DWORD 到 REAL 的二进制重解释。
 *   浮点拼接规则各平台存在差异，由调用方按其平台口径完成，避免在本层引入行为分支。
 *
 * 【验收向量 / Acceptance vectors（边界 B5，已复算）】
 *   以 16#12345678 为基准：ABCD → 16#12345678；DCBA → 16#78563412；
 *   BADC → 16#34127856；CDAB → 16#56781234。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 C）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ByteOrder（归属 DL_MathData，与 FC_DL_SwapBytes32 同文件）
 * 含义: 通信侧 32 位量的字节排布。A 为最高字节（位 31..24），D 为最低字节。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ByteOrder :
(
    eAbcd := 0,    // ABCD：大端大字（Modicon 事实标准），原始值无需转换 / Big-endian big-word, pass-through
    eDcba := 1,    // DCBA：四字节全反序，常见于小端 CPU 直出的协议栈 / Full byte reverse
    eBadc := 2,    // BADC：两个寄存器内部各自字节互换 / Byte swap within each register
    eCdab := 3     // CDAB：高低字交换（寄存器字序反），常见于电能表 / Word swap
);
END_TYPE

FUNCTION FC_DL_SwapBytes32 : DWORD
VAR_INPUT
    uRaw      : DWORD;                        // 通信侧原始 32 位拼接值 / Raw 32-bit value assembled from comms
    eRawOrder : E_DL_ByteOrder := eAbcd;      // 声明原始值所属排布 / Declared byte order of raw value
END_VAR
VAR_OUTPUT
    bValid    : BOOL;                         // 排布枚举合法标志 / Order enum valid flag
    uErrorId  : UDINT;                        // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uA : BYTE;   // 字节 A（uRaw 位 31..24） / Byte A, bits 31..24
    uB : BYTE;   // 字节 B（uRaw 位 23..16） / Byte B, bits 23..16
    uC : BYTE;   // 字节 C（uRaw 位 15..8）  / Byte C, bits 15..8
    uD : BYTE;   // 字节 D（uRaw 位 7..0）   / Byte D, bits 7..0
END_VAR
VAR CONSTANT
    DL_SWAP_SHIFT8  : UDINT := 8;               // 字节移位量 [bit] / Byte shift width [bit]
    DL_SWAP_SHIFT16 : UDINT := 16;              // 字移位量 [bit] / Word shift width [bit]
    DL_SWAP_SHIFT24 : UDINT := 24;              // 最高字节移位量 [bit] / Top byte shift width [bit]
    DL_MASK_BYTE    : DWORD := 16#0000_00FF;    // 单字节掩码 / Single-byte mask
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（边界 B1 / P-01）：先返回原值，任何异常路径都不会返回 0
 *      Safe preset: return the raw value first, no exceptional path returns zero
 *      0 对浮点量是合法灾难值，原值直通是最安全的确定值
 *      Zero is a legal but catastrophic float value, pass-through is the safest result
 *-----------------------------------------------------------------------------*)
FC_DL_SwapBytes32 := uRaw;
bValid   := TRUE;
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜字节提取（边界 B2）：仅移位 + 掩码 + 显式 BYTE 转换，禁止切片与指针
 *      Byte extraction: shift + mask + explicit BYTE conversion only
 *-----------------------------------------------------------------------------*)
uA := DWORD_TO_BYTE(SHR(uRaw, DL_SWAP_SHIFT24) AND DL_MASK_BYTE);
uB := DWORD_TO_BYTE(SHR(uRaw, DL_SWAP_SHIFT16) AND DL_MASK_BYTE);
uC := DWORD_TO_BYTE(SHR(uRaw, DL_SWAP_SHIFT8)  AND DL_MASK_BYTE);
uD := DWORD_TO_BYTE(uRaw AND DL_MASK_BYTE);

(*------------------------------------------------------------------------------
 * 段 3｜四排布分派（边界 B3/B4）：CASE 分派禁止 IF 链，ELSE 兜底拒收非法枚举
 *      Four-order dispatch: CASE only, ELSE intercepts an out-of-domain enum
 *-----------------------------------------------------------------------------*)
CASE eRawOrder OF

    eAbcd:
        (* 大端大字已是归一化目标，原值直通 *)
        (* Big-endian big-word is already the normalised target, pass through *)
        FC_DL_SwapBytes32 := uRaw;

    eDcba:
        (* 全反序：D C B A *)
        (* Full byte reverse: D C B A *)
        FC_DL_SwapBytes32 := (SHL(BYTE_TO_DWORD(uD), DL_SWAP_SHIFT24)
                          OR  SHL(BYTE_TO_DWORD(uC), DL_SWAP_SHIFT16)
                          OR  SHL(BYTE_TO_DWORD(uB), DL_SWAP_SHIFT8)
                          OR  BYTE_TO_DWORD(uA));

    eBadc:
        (* 寄存器内字节互换：B A D C *)
        (* Byte swap within each register: B A D C *)
        FC_DL_SwapBytes32 := (SHL(BYTE_TO_DWORD(uB), DL_SWAP_SHIFT24)
                          OR  SHL(BYTE_TO_DWORD(uA), DL_SWAP_SHIFT16)
                          OR  SHL(BYTE_TO_DWORD(uD), DL_SWAP_SHIFT8)
                          OR  BYTE_TO_DWORD(uC));

    eCdab:
        (* 高低字交换：C D A B *)
        (* Word swap: C D A B *)
        FC_DL_SwapBytes32 := (SHL(BYTE_TO_DWORD(uC), DL_SWAP_SHIFT24)
                          OR  SHL(BYTE_TO_DWORD(uD), DL_SWAP_SHIFT16)
                          OR  SHL(BYTE_TO_DWORD(uA), DL_SWAP_SHIFT8)
                          OR  BYTE_TO_DWORD(uB));

    ELSE
        (* 非法枚举拦截：枚举被强制写入定义域外的值时返回原值并报错 *)
        (* Illegal enum interception: keep the raw value and raise the error *)
        FC_DL_SwapBytes32 := uRaw;
        bValid            := FALSE;
        uErrorId          := 16#0001_000E;

END_CASE;
END_FUNCTION
