(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ByteArrayXor
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 位运算内建，零厂商私有库
 * 功能描述 (Function)   : 字节数组异或校验和（BCC / Block Check Character），用于串口协议帧尾校验。
 *                         逐字节按序异或，结果 BYTE 单字节出口。
 *                         与 CRC16-Modbus / LRC 件的差别（属主边界）：BCC 是无进位单字节异或，
 *                         无初值/无反射/无多项式，不可互替；三者各占一件，判据互不共用。
 *                         验收向量（算法级自证，脚本可复算）：
 *                           ① 空数组 uLen=0            → 拒算返回 16#00 + bInvalid
 *                           ② {16#55}                  → 16#55
 *                           ③ {16#01, 16#02, 16#03}    → 16#00（1^2=3，3^3=0，异或自反性）
 *                           ④ {16#FF, 16#F0}           → 16#0F
 * 接口     (Interface)  : 入 aBytes 待校验字节缓冲（IN_OUT，调用者持有）、uLen 有效长度；
 *                         出 返回值 = BCC 字节、bInvalid 拒算标志、bClamped 长度越上限钳位标志。
 * 边界     (Boundary)   : ① **空数组拒算**：uLen = 0 → 返回 16#00 + bInvalid（空帧的异或和为 0
 *                         会与"单字节 0"不可区分，是伪校验，故拒算而非返回真值）；
 *                         ② **长度上限防扫爆**：uLen > 256 时钳到 256 并置 bClamped，
 *                         不允许调用者声明的长度把循环拖进长扫描（R104 运行时二次闸）；
 *                         ③ 数组上界以**字面量 255** 声明（接口上界须编译期常量，R104），
 *                         同值常量 DL_BCC_MAX_LEN=256 作运行时二次闸，两处同源、改动须同步；
 *                         ④ 调用者须保证 uLen ≤ 实际数组长度（IN_OUT 语义，本件只做上限侧防御）；
 *                         ⑤ 纯函数无记忆量；零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"单字节异或和"。不接管：CRC/LRC 多项式校验、帧头帧长解析、
 *                         校验失败后的重发编排（属协议层件）。
 * 来源标签 (Source Tag) : T0 防御包装 —— IEC 61131-3 标准语义的道莅防御性实现
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 空数组闸 + 长度上限钳 + 双端循环上界 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 无状态机（纯组合函数，判别用 IF 链含两分支） ｜ R7 ✓ 无定时器/沿实例
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 1 · 序号 2）
 *==============================================================================*)

FUNCTION FC_DL_ByteArrayXor : BYTE
VAR_IN_OUT
    aBytes : ARRAY[0..255] OF BYTE;         // 待校验字节缓冲（上界字面量，R104） [-] / Source byte buffer, literal bound
END_VAR
VAR_INPUT
    uLen : UINT := 0;                       // 有效字节数，域 0..256（0 拒算） [-] / Valid byte count, 0 rejected
END_VAR
VAR_OUTPUT
    bInvalid : BOOL := FALSE;               // 拒算标志（uLen=0，当拍有效） [-] / Rejection flag (uLen=0, this scan)
    bClamped : BOOL := FALSE;               // 长度越上限钳位标志 [-] / Length clamp flag (upper bound hit)
END_VAR
VAR
    uXor    : BYTE := 16#00;                // 异或累加器（初值 0 为异或单位元） [-] / XOR accumulator
    uLenUse : UINT := 0;                    // 归一后的实际扫描长度 [-] / Normalised scan length
    i       : UINT := 0;                    // 字节下标 / Byte index
END_VAR
VAR CONSTANT
    DL_BCC_MAX_LEN : UINT := 256;           // 扫描长度上限（与接口字面量上界 255 同源） [-] / Max scan length
END_VAR

(* —— 段 1：返回值与两标志预置（R45 四段式第①段） —— *)
FC_DL_ByteArrayXor := 16#00;                // 返回值预置异或单位元 / Return value preset to XOR identity
bInvalid := FALSE;                          // 拒算标志预置 / Rejection flag preset
bClamped := FALSE;                          // 钳位标志预置 / Clamp flag preset
uXor    := 16#00;                           // 累加器预置 / Accumulator preset
uLenUse := 0;                               // 长度工作量预置 / Length working value preset

(* —— 段 2：域闸门早退（空数组不扫、不宣称校验和） —— *)
IF uLen = 0 THEN
    bInvalid := TRUE;                       // 空数组拒算 / Empty array rejected
    FC_DL_ByteArrayXor := 16#00;            // 拒算返回值 / Return value on rejection
    RETURN;                                 // 早退，不进入扫描 / Early return, no scan
END_IF

(* —— 段 3：长度上限钳位（运行时二次闸，防调用者传巨值扫爆） —— *)
uLenUse := uLen;                            // 取调用者长度 / Take the caller length
IF uLenUse > DL_BCC_MAX_LEN THEN
    uLenUse := DL_BCC_MAX_LEN;              // 钳到上限 / Clamp to the upper bound
    bClamped := TRUE;                       // 置钳位标志 / Raise the clamp flag
END_IF

(* —— 段 4：逐字节异或（双端上界：uLenUse ≤ 256，下标恒在数组域内） —— *)
i := 0;                                     // 下标归零 / Index reset
WHILE (i < uLenUse) AND (i < DL_BCC_MAX_LEN) DO
    uXor := uXor XOR aBytes[i];             // 累加异或 / Accumulate XOR
    i := i + 1;                             // 计数器推进（循环必然收敛） / Counter advance, loop terminates
END_WHILE

(* —— 段 5：统一出口（BYTE 域天然闭合，无需再钳） —— *)
FC_DL_ByteArrayXor := uXor;                 // 输出 BCC 单字节 / Output the BCC byte

END_FUNCTION
