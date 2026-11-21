(*
    组件名称 : FC_DL_LwordBitFieldInsert
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : LWORD 单字位段读改写（清位 → 取值 → 合成），与 FC_DL_LwordBitFieldExtract 构成读写对偶。
              取舍 ①：四步固定序不可交换 —— ① 算复位掩码 ② 清位 ③ 取值 ④ 合成。
              「先清后置」是读改写唯一安全序：若先把新值 OR 进去再清位，会把刚写进去的位一起清掉；
              若直接 OR 而不清位，旧值里为 1 的位永远抹不掉（写入 0 失效）。此纪律与库内 BitArrayInsert 同源。
              取舍 ②：越界一律拒写并返回原字 —— 写有不可逆副作用，「宁可一字不写」也不写半个字。
              这与读件的截断策略成对（R89）：读可截断、写必须拒。
              取舍 ③：字段值高位于宽外的部分只提示不静默 —— 调用方若把 16 位值写进 4 位字段，
              高位必然丢，必须让它看见，否则「写进去了但值不对」是最贵的故障形态。
              取舍 ④：bChanged 只在字值真变时为 TRUE —— 上层用它做配置写回节流，
              避免每次扫描都往 EEPROM 里刷一份没变的参数。
    开源溯源 : T2-1 LGF Bit Logic 子族，只借「合并/拆分位域存在」的分类事实与 Bit/Width 参数域；；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。
              清位-取值-合成顺序、拒写策略、码位与分级 100% 自有，零代码行与注释复制。
    本文件内含 : FUNCTION FC_DL_LwordBitFieldInsert（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 起始位闸 + 宽域闸 + 越界拒写（返回原值）+ 移位量恒 < 64
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 位宽与全一掩码常量化
    错误码   : 16#0001_0440 [信息级] 字段值超宽高位已丢弃，结果照写，bValid = TRUE
               16#0001_0441 [信息级] 预留禁用（不得挪用）
               16#0001_037E [故障级] 起始位越界，返回原字，bValid = FALSE
               16#0001_037F [故障级] 字段宽非法（≤ 0 或 > 64），返回原字，bValid = FALSE
               16#0001_0380 [故障级] 起始位 + 宽 > 64，越界拒写，返回原字，bValid = FALSE
    码位总账 : 16#0001_0440 用 / 16#0001_0441 预留 ｜ 16#0001_037E 用 / 16#0001_037F 用 / 16#0001_0380 用
    遗留假设 : ① LWORD 在 InoProShop 早期固件上是否原生 64 位未实测；若降级为 32 位，宽 64 路径将被编译期拒收
              （编译期可见，不会静默错算）。
              ② 用 DEC 形式不可得，故 bChanged 由「新旧字按位不等」比较得出，比较的是整字而非字段，
              这是有意为之：整字比较能兜住「掩码算错但恰好字段相同」的实现回归。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 2 入库
*)
FUNCTION FC_DL_LwordBitFieldInsert : LWORD
VAR_INPUT
    uBase           : LWORD;  // 原字，除目标字段外全部保持 [位图] / base word, every bit outside the field is preserved [bitmap]
    uField          : LWORD;  // 待写入字段值，只用低 nWidth 位 [位图] / field value to write, only the low bits are used [bitmap]
    nStartBit       : INT;    // 位段起始位，0~63 [位] / field start bit, 0..63 [bit]
    nWidth          : INT;    // 字段宽，1~64；越界即拒写 [位] / field width, 1..64, rejected when out of range [bit]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用，FALSE 时返回的是原字 / result usable flag, FALSE means the base word is returned unchanged
    bChanged        : BOOL;   // 写出后整字与输入不同即为 TRUE，供配置写回节流 / TRUE when the resulting word differs from the input, used to throttle writes
END_VAR
VAR
    uFieldMask      : LWORD;  // 已移位的字段掩码 [位图] / shifted field mask [bitmap]
    uResetMask      : LWORD;  // 字段掩码取反，用于清位 [位图] / inverted field mask used to clear the field [bitmap]
    uTemp           : LWORD;  // 清位后的中间字 [位图] / intermediate word after clearing [bitmap]
    uVal            : LWORD;  // 截到字段宽内的待写值 [位图] / value trimmed to the field width [bitmap]
    uRet            : LWORD;  // 合成结果 [位图] / composed result [bitmap]
    uHighLost       : LWORD;  // 被丢弃的字段高位，仅用于置信息码 [位图] / discarded high bits, used only for the info code [bitmap]
    uMaskRaw        : LWORD;  // 未移位的字段掩码 [位图] / unshifted field mask [bitmap]
END_VAR
VAR CONSTANT
    DL_MASK64_ALL   : LWORD := 16#FFFF_FFFF_FFFF_FFFF;   // 全 64 位掩码，宽 64 时直取，规避 SHL(x, 64) [位图] / all ones mask for width 64 [bitmap]
    DL_MASK64_LSB   : LWORD := 16#0000_0000_0000_0001;   // 最低位常量，掩码构造基元 [位图] / lowest bit, the mask primitive [bitmap]
    DL_LWORD_BITS   : INT := 64;                         // LWORD 位宽 [位] / width of a LWORD [bit]
    DL_BIT_MIN      : INT := 0;                          // 起始位下界 [位] / lower bound of the start bit [bit]
    DL_BIT_MAX      : INT := 63;                         // 起始位上界 [位] / upper bound of the start bit [bit]
    DL_WIDTH_MIN    : INT := 1;                          // 字段宽下界 [位] / lower bound of the field width [bit]
    DL_LWORD_ZERO   : LWORD := 0;                        // 零哨兵 [位图] / zero sentinel [bitmap]
    DL_ERR_NONE     : UDINT := 16#0000_0000;             // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置；故障缺省返回原字（拒写的不变式）/ segment 1, preset, faults return the base word unchanged
FC_DL_LwordBitFieldInsert := uBase;             // 故障缺省返回原字 / fault default returns the base word
eErr     := DL_ERR_NONE;                        // 预置无错误 / preset no error
bError   := FALSE;                              // 预置无故障 / preset no fault
bValid   := FALSE;                              // 预置结果不可用 / preset unusable
bChanged := FALSE;                              // 预置未改动 / preset unchanged

// 段 2｜起始位闸：拒写并返回原字 / segment 2, start bit gate, refuse the write and keep the base word
IF (nStartBit < DL_BIT_MIN) OR (nStartBit > DL_BIT_MAX) THEN
    eErr   := 16#0001_037E;                     // 起始位越界（故障级）/ start bit out of range, fault level
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    RETURN;                                     // 返回原字 / return the base word
END_IF

// 段 3｜宽域闸：宽 ≤ 0 或 > 64 属参数错误 / segment 3, width gate, a wrong width is a parameter error
IF (nWidth < DL_WIDTH_MIN) OR (nWidth > DL_LWORD_BITS) THEN
    eErr   := 16#0001_037F;                     // 字段宽非法（故障级）/ illegal field width, fault level
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    RETURN;                                     // 返回原字 / return the base word
END_IF

// 段 4｜跨字闸：写操作越界必须拒写，「宁可一字不写」/ segment 4, cross boundary gate, a write is refused rather than truncated
IF (nStartBit + nWidth) > DL_LWORD_BITS THEN
    eErr   := 16#0001_0380;                     // 越界拒写（故障级）/ out of range write refused, fault level
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    RETURN;                                     // 返回原字 / return the base word
END_IF

// 段 5｜掩码构造：宽 64 走常量，其余移位量恒 < 64 / segment 5, mask construction without any undefined shift
IF nWidth = DL_LWORD_BITS THEN
    uMaskRaw := DL_MASK64_ALL;                  // 宽 64 直取全一 / width 64 takes the all ones constant
ELSE
    uMaskRaw := SHL(DL_MASK64_LSB, nWidth) - DL_MASK64_LSB;   // 2^n − 1 / two to the n minus one
END_IF
uFieldMask := SHL(uMaskRaw, nStartBit);         // 掩码移到目标位置 / move the mask into place
uResetMask := NOT uFieldMask;                   // 复位掩码 = 字段掩码取反 / the reset mask is the inverted field mask

// 段 6｜字段高位丢弃提示（只提示，不影响写入）/ segment 6, hint about the discarded high bits, writing goes on
uHighLost := uField AND uResetMask;             // 落在字段宽之外的位 / bits that fall outside the field
IF uHighLost <> DL_LWORD_ZERO THEN
    eErr := 16#0001_0440;                       // 字段值高位已丢弃（信息级，不置 bError）/ high bits dropped, info level
END_IF

// 段 7｜四步固定序：清位 → 取值 → 合成 / segment 7, the fixed four step order, clear then set
uTemp := uBase AND uResetMask;                  // ① 清位：字段位置零，其余保持 / clear the field, keep every other bit
uVal  := uField AND uMaskRaw;                   // ② 取值：截到字段宽内 / trim the value to the field width
uRet  := uTemp OR SHL(uVal, nStartBit);         // ③ 合成：移到目标位置后或入 / ④ shift into place and OR it in

// 段 8｜改动判定与出口 / segment 8, change detection and exit
IF uRet <> uBase THEN
    bChanged := TRUE;                           // 整字真变才置位，供写回节流 / set only on a real change, used to throttle writes
END_IF
FC_DL_LwordBitFieldInsert := uRet;              // 输出合成结果 / publish the composed word
bValid := TRUE;                                 // 结果可用 / the result is usable
END_FUNCTION
