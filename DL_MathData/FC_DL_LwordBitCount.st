(*
    组件名称 : FC_DL_LwordBitCount
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : LWORD 汉明重量（置位个数 0~64），补齐存量 FC_DL_BitCount 只覆盖 DWORD 的位宽缺口。
              取舍 ①：Brian Kernighan 法 —— 每次 u AND (u − 1) 消掉最低的一个 1，迭代次数恰等于置位数；
              全零输入零次迭代。禁改成 FOR 0..63 的定长 64 次：定长版在「稀疏字」（如只有第 63 位为 1）
              上要多做 63 次无用循环，且与库内 BitCount 的算法选择必须同源，否则两件的行为一致性无从对照。
              取舍 ②：WHILE 必带守卫计数器 —— 理论上 Kernighan 法对 64 位字最多 64 次即归零，
              守卫超限只可能是实现回归或平台整数语义异常，属必须显式落码的防御分支。
              取舍 ③：全零输入是合法工况（未接线的状态字、刚清零的报警位图），返回 0 并发信息码，
              绝不判故障 —— 把「正常空值」当故障会让诊断日志被无效条目淹没。
    开源溯源 : T2-1 LGF 计数与边沿子族（LGF 侧 BitCount 为 DWORD 口径，本件为 64 位域自有实现）；；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。
              算法为公开经典，零查表、零内存、零代码行复制，码位与分级 100% 自有。
    本文件内含 : FUNCTION FC_DL_LwordBitCount（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ WHILE 守卫计数器 + 超限置故障 + 结果域自证（≤ 64）
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 守卫上限与位宽常量化
    错误码   : 16#0001_0442 [信息级] 输入全零（合法工况），返回 0，bValid = TRUE
               16#0001_0443 [信息级] 预留禁用（不得挪用）
               16#0001_0381 [故障级] 守卫超限（理论不可达，纯防御），返回 0，bValid = FALSE
               16#0001_0382 [故障级] 预留禁用（不得挪用）
               16#0001_0383 [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0442 用 / 16#0001_0443 预留 ｜ 16#0001_0381 用 / 16#0001_0382 预留 / 16#0001_0383 预留
    遗留假设 : ① LWORD 在 InoProShop 早期固件上是否原生 64 位未实测；32 位降级会在编译期暴露，不静默错算。
              ② 返回值类型 USINT 的域 0~255 天然覆盖 0~64，无需额外夹域；此为类型推导，未逐平台实测。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 2 入库
*)
FUNCTION FC_DL_LwordBitCount : USINT
VAR_INPUT
    uValue          : LWORD;  // 待计数的字，全 64 位有效 [位图] / word to inspect, all 64 bits are significant [bitmap]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用 / result usable flag
END_VAR
VAR
    uTemp           : LWORD;  // 逐位消去的工作副本 [位图] / working copy with bits cleared one by one [bitmap]
    nCount          : INT;    // 置位计数 0~64 [个] / population count, 0..64 [count]
    nGuard          : DINT;   // 守卫计数器，防 WHILE 失控 [次] / guard counter protecting the WHILE loop [count]
END_VAR
VAR CONSTANT
    DL_GUARD_MAX_BITS : DINT := 64;                      // 守卫上限，等于字宽（Kernighan 法最多 64 次）[次] / guard limit equals the word width [count]
    DL_LWORD_ONE      : LWORD := 16#0000_0000_0000_0001;  // 减一基元，用于 u AND (u − 1) [位图] / the decrement primitive for u AND (u minus one) [bitmap]
    DL_LWORD_ZERO     : LWORD := 0;                      // 零哨兵，终止条件 [位图] / zero sentinel, the termination test [bitmap]
    DL_ERR_NONE       : UDINT := 16#0000_0000;           // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_LwordBitCount := 0;       // 故障缺省返回 0 / fault default returns zero
eErr   := DL_ERR_NONE;          // 预置无错误 / preset no error
bError := FALSE;                // 预置无故障 / preset no fault
bValid := FALSE;                // 预置结果不可用 / preset unusable
nCount := 0;                    // 计数清零 / clear the count
nGuard := 0;                    // 守卫清零 / clear the guard

// 段 2｜全零短路：全零是合法工况，返回 0 并发信息码 / segment 2, an all zero word is legal, not a fault
IF uValue = DL_LWORD_ZERO THEN
    FC_DL_LwordBitCount := 0;   // 置位数 0 / population count is zero
    eErr   := 16#0001_0442;     // 全零输入（信息级，不置 bError）/ all zero input, info level
    bValid := TRUE;             // 结果可用 / the result is usable
    RETURN;                     // 提前出口，不进循环 / early exit, never enter the loop
END_IF

// 段 3｜Kernighan 消位循环：每轮消掉最低的一个 1，WHILE 必带守卫 / segment 3, Kernighan loop with a mandatory guard
uTemp := uValue;                                        // 拷贝入参，不改输入 / copy the input, never modify it
WHILE (uTemp <> DL_LWORD_ZERO) AND (nGuard <= DL_GUARD_MAX_BITS) DO
    uTemp  := uTemp AND (uTemp - DL_LWORD_ONE);         // 消掉最低位的 1 / clear the lowest set bit
    nCount := nCount + 1;                               // 计数递增 / increment the count
    nGuard := nGuard + 1;                               // 守卫递增 / increment the guard
END_WHILE

// 段 4｜守卫复检：未归零说明循环失控，属实现回归，必须显式落码 / segment 4, the guard re-check catches a runaway loop
IF uTemp <> DL_LWORD_ZERO THEN
    FC_DL_LwordBitCount := 0;   // 不给可疑结果 / never emit a suspicious result
    eErr   := 16#0001_0381;     // 守卫超限（故障级，理论不可达）/ guard exceeded, fault level, unreachable in theory
    bError := TRUE;             // 置故障标志 / raise the fault flag
    RETURN;                     // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 5｜出口 / segment 5, exit
FC_DL_LwordBitCount := INT_TO_USINT(nCount);   // 计数恒在 0~64，转换结构性安全 / the count stays within 0..64, so the cast is safe
bValid := TRUE;                                // 结果可用 / the result is usable
END_FUNCTION
