(*
    组件名称 : FC_DL_ChecksumSum8
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 8 位累加和校验，覆盖 DL/T 645、水表/电表自定义帧这类「不用 CRC、只用累加和」的协议形态。
              取舍 ①：用 DINT 累加而不是 BYTE 累加 —— 255 × 256 在 BYTE 域必然回绕，回绕本身虽等价于 MOD 256，
              但一旦有人在中间插入一步「判和是否超限」的诊断，回绕后的和就已经撒谎；升位累加、末了一次取模，
              中间量始终可观测。
              取舍 ②：补码模式的结果 0 必须显式判 —— 累加和 0 的补码在数学上仍是 0（不是 256），
              若写成 256 − 0 会溢出成 256 再被截成 0，看着对但依赖隐式回绕；而且「校验字节为 0」在部分协议里
              表示「本帧无校验」，这条歧义必须发信息码让上位机知情。
              取舍 ③：帧长超上限拒绝而不截断 —— 同 CRC 件口径，截断后的累加和格式合法但必然校验失败。
              取舍 ④：本件不做 LWORD 累加变体 —— 64 位累加和没有任何公开协议用例，属过度设计，
              8 位才是实际协议形态；该判断已在本轮规格留档。
    开源溯源 : T2-1 LGF Data Handling 子族（「校验族尚余累加和待挖」）；算法为公开经典，零查表、；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。
              零代码行复制，码位与分级 100% 自有。
    本文件内含 : FUNCTION FC_DL_ChecksumSum8（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 帧长闸 + 空帧短路 + 补码零特例 + 累加升位防回绕 + 取模前操作数非负
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 取模基数与缓冲上限常量化
    错误码   : 16#0001_0446 [信息级] 补码模式下结果为 0 的特例（部分协议以 0 表示无校验），bValid = TRUE
               16#0001_0447 [信息级] 空帧，返回 0，bValid = TRUE
               16#0001_0387 [故障级] 帧长超 DL_SUM_BUF_MAX，拒绝计算，返回 0，bValid = FALSE
               16#0001_0388 [故障级] 预留禁用（不得挪用）
               16#0001_0389 [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0446 用 / 16#0001_0447 用 ｜ 16#0001_0387 用 / 16#0001_0388 预留 / 16#0001_0389 预留
    遗留假设 : ① 累加上界推导：最大 255 × 255 + 255 级余量远小于 DINT 上界，中间量不会溢出；
              该推导依赖「nLen ≤ 255 由闸门保证」，若上限常量被改大须重新核算（已在头注释留痕）。
              ② 无内建转换链依赖，编译门槛未见风险。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 2 入库
*)
FUNCTION FC_DL_ChecksumSum8 : BYTE
VAR_INPUT
    nLen            : UINT;   // 待累加字节数，0~DL_SUM_BUF_MAX，0 = 空帧 [字节] / number of bytes, zero means an empty frame [byte]
    bTwosComplement : BOOL := FALSE;   // TRUE 输出累加和的二进制补码（DL/T 645 口径）/ TRUE returns the two's complement, the DL/T 645 convention
END_VAR
VAR_IN_OUT
    afData          : ARRAY[0..DL_SUM_BUF_MAX] OF BYTE;   // 待累加字节数组，仅前 nLen 个有效 [字节] / data buffer, only the first nLen bytes are used [byte]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用 / result usable flag
END_VAR
VAR
    nSum            : DINT;   // 升位累加器，恒非负 [无量纲] / widened accumulator, always non-negative [dimensionless]
    nModRes         : DINT;   // 累加和对 256 取模后的低 8 位值 [无量纲] / low byte value after the modulo [dimensionless]
    uIdx            : UINT;   // 字节游标 [字节] / byte cursor [byte]
    uRet            : BYTE;   // 校验字节结果 [字节] / checksum byte result [byte]
END_VAR
VAR CONSTANT
    DL_SUM_BUF_MAX  : UINT := 255;     // 单帧字节数上限 [字节] / frame length upper bound [byte]
    DL_BYTE_MOD     : DINT := 256;     // 8 位容器的取模基数 [无量纲] / modulus of the byte container [dimensionless]
    DL_DINT_ZERO    : DINT := 0;       // 零哨兵 [无量纲] / zero sentinel [dimensionless]
    DL_SUM_LEN_NONE : UINT := 0;       // 空帧长度哨兵，减法前必判 [字节] / empty frame sentinel [byte]
    DL_BYTE_ZERO    : BYTE := 16#00;   // 字节零哨兵 [字节] / byte zero sentinel [byte]
    DL_ERR_NONE     : UDINT := 16#0000_0000;   // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_ChecksumSum8 := DL_BYTE_ZERO;   // 故障缺省返回 0 / fault default returns zero
eErr   := DL_ERR_NONE;                // 预置无错误 / preset no error
bError := FALSE;                      // 预置无故障 / preset no fault
bValid := FALSE;                      // 预置结果不可用 / preset unusable
nSum   := DL_DINT_ZERO;               // 累加器清零 / clear the accumulator

// 段 2｜帧长闸：超上限拒绝，绝不截断 / segment 2, length gate, refuse instead of truncating
IF nLen > DL_SUM_BUF_MAX THEN
    eErr   := 16#0001_0387;           // 帧长超上限（故障级）/ frame too long, fault level
    bError := TRUE;                   // 置故障标志 / raise the fault flag
    RETURN;                           // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 3｜空帧短路：长度 0 时 nLen − 1 会回绕成 65535，必须先判零 / segment 3, empty frame short circuit before any subtraction
IF nLen = DL_SUM_LEN_NONE THEN
    FC_DL_ChecksumSum8 := DL_BYTE_ZERO;   // 空帧累加和为 0 / an empty frame sums to zero
    eErr   := 16#0001_0447;               // 空帧（信息级，不置 bError）/ empty frame, info level
    bValid := TRUE;                       // 空帧是协议合法输入 / an empty frame is a legal protocol input
    RETURN;                               // 提前出口，绝不进循环 / early exit, never enter the loop
END_IF

// 段 4｜升位累加：nLen 已保证 ≥ 1 / segment 4, widened accumulation, nLen is at least one
FOR uIdx := 0 TO nLen - 1 DO
    nSum := nSum + BYTE_TO_DINT(afData[uIdx]);   // 升到 DINT 累加，中间量始终可观测 / widen to DINT so the intermediate stays observable
END_FOR

// 段 5｜取模与补码：nSum 恒非负，MOD 安全 / segment 5, modulo and two's complement, the operand is never negative
nModRes := nSum MOD DL_BYTE_MOD;      // 低 8 位值，0~255 / the low byte, 0..255
IF bTwosComplement THEN
    IF nModRes = DL_DINT_ZERO THEN
        uRet := DL_BYTE_ZERO;         // 零的补码仍是零，显式判，不依赖 256 − 0 的回绕 / zero complements to zero, tested explicitly
        eErr := 16#0001_0446;         // 补码结果为零的特例（信息级）/ two's complement result is zero, info level
    ELSE
        uRet := DINT_TO_BYTE(DL_BYTE_MOD - nModRes);   // 256 − 和，落 1~255 / two hundred and fifty six minus the sum, 1..255
    END_IF
ELSE
    uRet := DINT_TO_BYTE(nModRes);    // 直接取低 8 位 / take the low byte directly
END_IF

// 段 6｜出口 / segment 6, exit
FC_DL_ChecksumSum8 := uRet;           // 输出校验字节 / publish the checksum byte
bValid := TRUE;                       // 结果可用 / the result is usable
END_FUNCTION
