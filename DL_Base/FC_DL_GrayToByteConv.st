// FC_DL_GrayToByteConv v1.0.0
// 开源溯源：来源 brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴点 BYTE_TO_GRAY 反演语义（移位异或链逐位还原）
(*==============================================================================
 * 功能描述: 格雷码 → 二进制转换（8 位）。采用移位异或链三步反演：
 *           b ^= b>>1; b ^= b>>2; b ^= b>>4，等价于逐位累异或 FOR 循环 8 位的
 *           数学结果，位移量 1/2/4 均小于位宽 8（位移量归一，无越界移位）。
 * 接口契约: 输入 bGray（格雷码字节）；返回二进制字节。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_GrayToByteConv : BYTE
VAR_INPUT
    bGray : BYTE := 16#00;   // 格雷码输入字节 [位域] / Gray-coded input byte
END_VAR
VAR
    bAcc : BYTE;             // 累异或工作字节 [位域] / Accumulating work byte
END_VAR

(* —— 段 0：移位异或链反演（三步覆盖 8 位全部位贡献） —— *)
bAcc := bGray;                              // 工作字节装载格雷码 / Work byte loaded with gray code
bAcc := bAcc XOR SHR(bAcc, 1);              // 第一级：右移 1 位异或（覆盖相邻位） / First stage, shift one
bAcc := bAcc XOR SHR(bAcc, 2);              // 第二级：右移 2 位异或（覆盖隔位） / Second stage, shift two
bAcc := bAcc XOR SHR(bAcc, 4);              // 第三级：右移 4 位异或（覆盖高位） / Third stage, shift four
FC_DL_GrayToByteConv := bAcc;               // 返回二进制结果 / Return binary result

END_FUNCTION
