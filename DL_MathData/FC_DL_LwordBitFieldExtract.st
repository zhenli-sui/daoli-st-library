(*
    组件名称 : FC_DL_LwordBitFieldExtract
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : LWORD 单字位段读取（起始位 0~63，字段宽 1~64），补齐库内位操作族只覆盖 BYTE/WORD/DWORD 的缺口。
              取舍 ①：掩码构造分两条路径 —— 宽 64 直接取全一常量。因为 SHL(LWORD#1, 64) 的移位量等于容器位宽，
              在 IEC 61131-3 里属未定义行为（部分平台得 1、部分得 0、部分触发异常），绝不能靠「反正会被截断」蒙过去。
              取舍 ②：截取时先 AND 再移 —— 顺序反了（先右移再 AND）会把右侧相邻字段的位一起右移到低位，
              得到「看着像、其实串位」的脏结果；这是位域读最常见的实现错误。
              取舍 ③：读操作越界按可用宽度截断 + bTruncated —— 读无副作用，能读多少读多少并让调用方看得见；
              与写件（FC_DL_LwordBitFieldInsert）的「越界一律拒写」成对，是本轮登记的 R89 纪律。
              取舍 ④：宽域本身非法（≤0 或 >64）判故障而不截断 —— 那是参数错误而非边界擦边，
              静默截断会让「字段宽填成 100」这类配置错长期潜伏。
    开源溯源 : T2-1 LGF Bit Logic 子族（闭源文档只借「合并/拆分位域存在」这一分类事实与 Bit/Width 参数域）。；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。
              算法、掩码策略、截断/拒写纪律、码位与分级 100% 自有，零代码行与注释复制。
    本文件内含 : FUNCTION FC_DL_LwordBitFieldExtract（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 起始位闸 + 宽域闸 + 移位量恒 < 64（禁 SHL(x,64)）+ 截断可观测
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 位宽与全一掩码常量化
    错误码   : 16#0001_043E [信息级] 起始位 + 宽超 64，已按可用位截断，bTruncated = TRUE，bValid = TRUE
               16#0001_043F [信息级] 预留禁用（不得挪用）
               16#0001_037B [故障级] 起始位越界（< 0 或 > 63），返回 0，bValid = FALSE
               16#0001_037C [故障级] 字段宽非法（≤ 0 或 > 64），返回 0，bValid = FALSE
               16#0001_037D [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_043E 用 / 16#0001_043F 预留 ｜ 16#0001_037B 用 / 16#0001_037C 用 / 16#0001_037D 预留
    遗留假设 : ① LWORD 在 InoProShop 早期固件上是否原生 64 位未实测；若平台把 LWORD 降级为 32 位，
              本件的宽 64 路径与掩码常量会被编译期拒收（属编译期可见，不会静默错算）。
              ② SHL/SHR 对 LWORD 的移位量按 IEC 语义限于 [0, 63]，本件已结构性保证，未逐平台实测边界。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 2 入库
*)
FUNCTION FC_DL_LwordBitFieldExtract : LWORD
VAR_INPUT
    uWord           : LWORD;  // 源字，全 64 位可读 [位图] / source word, all 64 bits readable [bitmap]
    nStartBit       : INT;    // 位段起始位，0~63，越界即拒算 [位] / field start bit, 0..63, rejected when out of range [bit]
    nWidth          : INT;    // 字段宽，1~64；超可用位时截断 [位] / field width, 1..64, truncated when it exceeds the available bits [bit]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用 / result usable flag
    bTruncated      : BOOL;   // 宽超可用位已截断，结果只含低位可用部分 / TRUE when the width was truncated to the available bits
END_VAR
VAR
    nEffWidth       : INT;    // 实际取用宽度，= MIN(nWidth, 64 − nStartBit) [位] / effective width, the smaller of the request and the remaining bits [bit]
    uMask           : LWORD;  // 未移位的字段掩码，低 nEffWidth 位为 1 [位图] / unshifted field mask with the low effective bits set [bitmap]
    uFieldShift     : LWORD;  // 已移到目标位置的掩码 [位图] / mask shifted into the target position [bitmap]
    uRet            : LWORD;  // 取出的字段值 [位图] / extracted field value [bitmap]
END_VAR
VAR CONSTANT
    DL_MASK64_ALL   : LWORD := 16#FFFF_FFFF_FFFF_FFFF;   // 全 64 位掩码，宽 64 时直取，规避 SHL(x, 64) [位图] / all ones mask used when the width is 64, avoiding SHL by 64 [bitmap]
    DL_MASK64_LSB   : LWORD := 16#0000_0000_0000_0001;   // 最低位常量，掩码构造的基元 [位图] / lowest bit, the primitive of the mask construction [bitmap]
    DL_LWORD_BITS   : INT := 64;                         // LWORD 位宽 [位] / width of a LWORD [bit]
    DL_BIT_MIN      : INT := 0;                          // 起始位下界 [位] / lower bound of the start bit [bit]
    DL_BIT_MAX      : INT := 63;                         // 起始位上界 [位] / upper bound of the start bit [bit]
    DL_WIDTH_MIN    : INT := 1;                          // 字段宽下界 [位] / lower bound of the field width [bit]
    DL_LWORD_ZERO   : LWORD := 0;                        // 零哨兵 [位图] / zero sentinel [bitmap]
    DL_ERR_NONE     : UDINT := 16#0000_0000;             // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_LwordBitFieldExtract := DL_LWORD_ZERO;   // 故障缺省返回 0 / fault default returns zero
eErr       := DL_ERR_NONE;                     // 预置无错误 / preset no error
bError     := FALSE;                           // 预置无故障 / preset no fault
bValid     := FALSE;                           // 预置结果不可用 / preset unusable
bTruncated := FALSE;                           // 预置未截断 / preset not truncated

// 段 2｜起始位闸 / segment 2, start bit gate
IF (nStartBit < DL_BIT_MIN) OR (nStartBit > DL_BIT_MAX) THEN
    eErr   := 16#0001_037B;                    // 起始位越界（故障级）/ start bit out of range, fault level
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    RETURN;                                    // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 3｜宽域闸：宽 ≤ 0 与宽 > 64 都属参数错误，不做截断 / segment 3, width gate, a wrong width is a parameter error and is never truncated
IF (nWidth < DL_WIDTH_MIN) OR (nWidth > DL_LWORD_BITS) THEN
    eErr   := 16#0001_037C;                    // 字段宽非法（故障级）/ illegal field width, fault level
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    RETURN;                                    // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 4｜有效宽计算：越界按可用位截断（读操作可截断，见 R89）/ segment 4, effective width with truncation allowed for reads
nEffWidth := nWidth;                           // 先按请求宽度 / start from the requested width
IF (nStartBit + nWidth) > DL_LWORD_BITS THEN
    nEffWidth  := DL_LWORD_BITS - nStartBit;   // 只取起始位右侧剩余位 / keep only the bits right of the start bit
    bTruncated := TRUE;                        // 标记已截断 / mark the truncation
    eErr       := 16#0001_043E;                // 宽超可用位已截断（信息级，不置 bError）/ width truncated, info level
END_IF

// 段 5｜掩码构造：宽 64 走常量，其余移位量恒 < 64 / segment 5, mask construction, the shift is always below the container width
IF nEffWidth = DL_LWORD_BITS THEN
    uMask := DL_MASK64_ALL;                    // 宽 64 直取全一，禁 SHL(x, 64) / width 64 takes the all ones constant, never SHL by 64
ELSE
    uMask := SHL(DL_MASK64_LSB, nEffWidth) - DL_MASK64_LSB;   // 2^n − 1，得低 n 位全一 / two to the n minus one gives n low ones
END_IF

// 段 6｜先 AND 再右移：顺序反了会串入右侧邻位的脏数据 / segment 6, mask before shifting, the reverse order pulls in neighbouring bits
uFieldShift := SHL(uMask, nStartBit);          // 掩码移到目标位置 / move the mask to the target position
uRet        := SHR(uWord AND uFieldShift, nStartBit);   // 取段后右移归位 / extract and shift back into the low bits

// 段 7｜出口 / segment 7, exit
FC_DL_LwordBitFieldExtract := uRet;            // 输出字段值 / publish the field value
bValid := TRUE;                                // 结果可用（含截断后的结果）/ the result is usable, truncation included
END_FUNCTION
