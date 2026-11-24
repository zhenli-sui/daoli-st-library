// FC_DL_SwapNibbles v1.0.0
// 开源溯源：来源 brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴点 SWAP_BYTE 半字节交换语义（SHL/SHR + 位移量归一）
(*==============================================================================
 * 功能描述: BYTE 输入高低半字节（nibble）交换。SHL/SHR 各移 4 位后按位或合成，
 *           位移量 4 小于 BYTE 位宽 8（位移量归一红线，无越界移位）。
 * 接口契约: 输入 bIn；返回交换后的 BYTE。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_SwapNibbles : BYTE
VAR_INPUT
    bIn : BYTE := 16#00;   // 输入字节 [位域] / Input byte
END_VAR
VAR
    bHi : BYTE;            // 高半字节移到低 4 位的结果 [位域] / High nibble shifted down
    bLo : BYTE;            // 低半字节移到高 4 位的结果 [位域] / Low nibble shifted up
END_VAR

(* —— 段 0：半字节交换（位移量 4 < 位宽 8，结构性安全） —— *)
bHi := SHR(bIn, 4);                        // 高半字节右移 4 位至低位 / High nibble shifted down by four
bLo := SHL(bIn, 4);                        // 低半字节左移 4 位至高位 / Low nibble shifted up by four
FC_DL_SwapNibbles := bHi OR bLo;           // 按位或合成交换结果 / Bitwise or composes the swap

END_FUNCTION
