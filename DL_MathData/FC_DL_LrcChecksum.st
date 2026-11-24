(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LrcChecksum
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / 显式类型转换），无厂商方言
 * 功能描述 (Function)   : Modbus ASCII 模式的 LRC（纵向冗余校验）计算。
 *                         把地址、功能码、数据字节按无符号 8 位累加，
 *                         取二进制补码（256 - 累加和 的低 8 位）作为校验值。
 *                         用于电表、称重仪表、老式温控器等仍走 ASCII 模式
 *                         设备的收帧校验。
 *
 * 【帧边界声明 / Frame-boundary declaration（边界 B1）】
 *   **冒号 16#3A 与回车换行 16#0D/16#0A 不参与计算。**
 *   误把帧头帧尾算进累加和，是现场 LRC 对不上的第一原因。
 *   输入必须传"解码后"的字节：先用 FC_DL_HexStringToBytes 把 ASCII 字符
 *   解码为字节数组，再把该数组传入本函数——两步调用顺序不可颠倒。
 *   若误传 ASCII 字符码（'0' = 16#30 而非 16#00），结果必然错。
 *
 * 【与 CRC 的关系 / Relation to CRC（边界 B5）】
 *   LRC 与 CRC-16 不可互算、不可互验。ASCII 模式用 LRC，RTU 模式用 CRC，
 *   同一设备切换模式时校验字段同时变。配套函数见 FC_DL_Crc16Modbus。
 *
 * 【大小写与字节序 / Case and byte order（边界 B6）】
 *   返回值是数值字节。转 ASCII 十六进制字符（"FB" 还是 "fb"）由组帧方
 *   决定，本函数不输出字符串、不规定大小写。
 *
 * 【使用前提与配套组件 / Prerequisites and companion（边界 B2）】
 *   本函数是无状态纯函数：不保存上一次的报文、不持有任何跨周期数据，
 *   可在任意任务周期安全调用，也支持同一扫描周期内对多路设备依次调用。
 *   上游配套为十六进制解码函数（先解码、后校验，见上方两步调用顺序）；
 *   下游如需 RTU 模式校验请改用 CRC-16 族函数，二者不可互验。
 *   收帧链路中冒号与回车换行必须在解码阶段被剥离，若上游解码函数
 *   配置为不剥帧，本函数的累加和将整体偏移，校验恒失败——
 *   该故障模式下 uSumLow 每次都对不上同一个值，可作为判据。
 *
 * 【验收向量 / Acceptance vectors（已实算复核，含逐字节和值分解）】
 *   V1  01 03 00 00 00 01（标准读保持寄存器请求）
 *       和值分解：01+03+00+00+00+01 = 16#05 → LRC = 16#FB
 *   V2  01 03 02 12 34（标准响应，寄存器值 1234）
 *       和值分解：01+03+02+12+34 = 16#4C → LRC = 16#B4
 *   V3  空报文（nLength = 0）→ 和 16#00 → 256-0 取模 → LRC = 16#00
 *       （正确值，非错误）
 *   V4  FF FF → 和 16#1FE，低 8 位 16#FE → 256-FE = 02 → LRC = 16#02
 *   V5  单字节 00 → 和 16#00 → LRC = 16#00
 *
 * 【两步调用顺序 / Two-step call sequence（边界 B2）】
 *   现场收帧的固定次序，不可颠倒：
 *     第一步：收到 ASCII 报文（含冒号与回车换行）后，先用配套的十六进制
 *             解码函数把报文体解码为字节数组（帧字符被剥离，不进数组）
 *     第二步：把解码后的字节数组与本函数要求的长度传入本函数，
 *             返回值即 LRC，与报文尾随的校验字符比对
 *   误传原始 ASCII 字符（如 '0' 的字符码 16#30 而非数值 16#00）时，
 *   累加和整体偏移，校验必然失败——这是现场第二常见错误。
 * 开源溯源 (Origin)     : 依 Modbus 应用协议规范（Modbus over Serial Line，
 *                         ASCII 传输模式定义）独立实现。OSCAT Network 校验
 *                         函数族仅提供"按协议分族、独立成函数"的组织方式参考
 *                         （EPL-2.0），未复制任何源码。
 * 依赖     (Depends)    : 无 DL_ 内部依赖（配套解码见 FC_DL_HexStringToBytes）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（显式 BYTE_TO_UDINT / UDINT_TO_BYTE）
 *                         R4 ✓ 长度钳位 + 下标双检 + 空报文兜底 + 宽类型防溢出
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 *
 * 【与 CRC 族函数的分工表 / Division of labour with the CRC family】
 *   传输模式      | 校验算法 | 本库配套函数           | 典型设备
 *   ASCII 串口    | LRC      | FC_DL_LrcChecksum      | 老式电表、称重仪表
 *   RTU 串口      | CRC-16   | FC_DL_Crc16Modbus      | 变频器、温控器
 *   以太网帧      | CRC-32   | FC_DL_Crc32Ethernet    | 固件下发、文件校验
 *   三者校验字段互不可算、互不可验；同一设备切换模式时校验字段同时变。
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
FUNCTION FC_DL_LrcChecksum : BYTE
VAR_IN_OUT
    aabyData  : ARRAY[0..255] OF BYTE;    // 参与校验的解码后字节（不含帧头帧尾） / Decoded payload bytes, framing excluded
END_VAR
VAR_INPUT
    nLength   : INT;                      // 字节数，合法域 0..256，越界自动钳位 / Byte count, range 0..256, clamped
END_VAR
VAR_OUTPUT
    uSumLow   : BYTE;                     // 累加和低 8 位（诊断用，LRC = 其补码） / Low byte of the sum for diagnostics
    uErrorId  : UDINT;                    // 故障码，0 = 无故障，16#0001_0001 = 长度越界已钳位 / Error code, 0 = no error, 0001_0001 = length clamped
END_VAR
VAR
    uSum      : UDINT;                    // 累加器，宽类型防中间溢出（禁止字节自加回绕） / Wide accumulator to avoid byte wrap-around
    nLenWork  : INT;                      // 钳位后的本地长度副本，不回写输入引脚 / Local clamped copy of the length
    nI        : INT;                      // 字节循环索引，值域 0..255 / Byte loop index, range 0..255
    nSumLowInt: INT;                      // 累加和低 8 位的整数形式，供补码运算 / Integer form of the low byte for two's complement math
END_VAR
VAR CONSTANT
    DL_LRC_MOD     : INT   := 256;        // 模 256，补码运算的模 / Modulus for two's complement math
    DL_LRC_BUF_MAX : INT   := 256;        // 缓冲上限，必须与数组维度一致 / Buffer limit, must match the array dimension
    DL_LRC_MASK    : UDINT := 16#0000_00FF; // 取低 8 位掩码 / Low-byte mask
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值与累加器归零，故障码清零
 *      Safe preset: return value and accumulator cleared, error code reset
 *      空报文（长度 0）是合法输入：和为 0，补码后 LRC = 16#00，
 *      这是正确值而非错误，不得报故障（边界 B3）。
 *      返回值先落 16#00 再进入计算：异常路径下不会返回未定义值，
 *      且 16#00 在补码口径下本就是合法的校验值（对应和值回绕到 0），
 *      与 CRC 族"返回值不得用 0 判错"的约定不同，此差异为算法本质。
 *-----------------------------------------------------------------------------*)
FC_DL_LrcChecksum := 16#00;
uSum              := 16#0000_0000;
uSumLow           := 16#00;
uErrorId          := 16#0000_0000;
nLenWork          := nLength;

(*------------------------------------------------------------------------------
 * 段 2｜长度防御（边界 B4）：钳位而非拒绝，让诊断链拿到可比对的值
 *      Length defence: clamp instead of reject, transient code on clamp
 *      负值 → 0；大于 256 → 256；均置 16#0001_0001（瞬时码）。
 *      选择钳位而非直接退回：现场排错时长度参数偶发抖动（比如上游
 *      把帧字符计入又纠正），直接退回会让诊断链断在第一步，
 *      钳位至少能给出一个"截断口径"的校验值供比对。
 *-----------------------------------------------------------------------------*)
IF nLenWork < 0 THEN
    nLenWork := 0;
    uErrorId := 16#0001_0001;
ELSIF nLenWork > DL_LRC_BUF_MAX THEN
    nLenWork := DL_LRC_BUF_MAX;
    uErrorId := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜累加（边界 B4）：用 UDINT 宽类型累加，禁止依赖 BYTE 自加回绕——
 *      Accumulation in a wide UDINT accumulator
 *      部分平台对 BYTE 溢出回绕行为未定义，跨平台不可依赖。
 *      量级核算：256 字节全 0xFF 时累加和达 65280（16#FF00），
 *      UDINT 容量余量超过六万倍，本函数不存在累加溢出的可能，
 *      无需对累加器做饱和保护。
 *-----------------------------------------------------------------------------*)
IF nLenWork > 0 THEN

    FOR nI := 0 TO (nLenWork - 1) DO

        (* 数组下标上下界双检（红线 R4）：nLenWork ≤ 256 已保证 nI ≤ 255 *)
        (* Array index double check: nLenWork ≤ 256 guarantees nI ≤ 255 *)
        IF nI < DL_LRC_BUF_MAX THEN
            uSum := uSum + BYTE_TO_UDINT(aabyData[nI]);
        END_IF

    END_FOR;

END_IF

(*------------------------------------------------------------------------------
 * 段 4｜补码与回写：LRC = (256 - 累加和低 8 位) MOD 256
 *      Two's complement and write-back: LRC = (256 - low byte) MOD 256
 *      累加和低 8 位同步输出供诊断（对帧时可直接比对和值）。
 *      补码口径说明：本式等价于"按位取反加一后截取低 8 位"，
 *      但避免了取负运算，只依赖取模，跨平台行为完全一致。
 *      和值低 8 位为 0 时（含空报文与整字节回绕两种情况），
 *      LRC 均为 16#00，与 V3/V5 向量一致。
 *-----------------------------------------------------------------------------*)
uSumLow    := UDINT_TO_BYTE(uSum AND DL_LRC_MASK);
nSumLowInt := BYTE_TO_INT(uSumLow);

(* 显式 INT_TO_BYTE，MOD 已保证结果落在 0..255，无越界 *)
(* Explicit INT_TO_BYTE, MOD already bounds the result to 0..255 *)
FC_DL_LrcChecksum := INT_TO_BYTE((DL_LRC_MOD - nSumLowInt) MOD DL_LRC_MOD);

(*------------------------------------------------------------------------------
 * 段 5｜现场对拍指引（诊断用，无逻辑）
 *      On-site cross-check guidance for diagnostics, no logic here
 *      ① 收帧失败时先比对 uSumLow：与上位机侧算出的和值低 8 位一致，
 *        说明报文体一致、分歧在校验算法；不一致说明收到的字节本身有错，
 *        先查串口链路再查校验。
 *      ② 和值对、校验值不对：检查双方补码口径（本块为 256 减和取模，
 *        不是按位取反加一以外的变体）。
 *      ③ 和值偶尔对偶尔不对：多为帧字符混入或长度参数抖动，
 *        回查上游解码步骤的长度来源是否把帧字符计入了。
 *
 * 段 6｜自检向量断言说明（供单元测试与现场对拍，向量已实算复核）
 *      Self-check vector assertion notes, recomputed and verified
 *      V1  01 03 00 00 00 01 → 和 16#05 → uSumLow = 16#05、LRC = 16#FB
 *      V2  01 03 02 12 34   → 和 16#4C → uSumLow = 16#4C、LRC = 16#B4
 *      V3  空报文（长度 0）  → 和 16#00 → uSumLow = 16#00、LRC = 16#00
 *      V4  FF FF            → 和 16#1FE → uSumLow = 16#FE、LRC = 16#02
 *      V5  单字节 00         → 和 16#00 → uSumLow = 16#00、LRC = 16#00
 *-----------------------------------------------------------------------------*)
END_FUNCTION
