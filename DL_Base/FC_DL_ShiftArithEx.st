(*
  ==================================================================
  组件名 Component  : FC_DL_ShiftArithEx
  分类   Category   : DL_Base
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_064B（信息级）｜ 16#0001_064C（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : DINT 算术右移（符号位扩展右移）：IEC 标准只有逻辑 SHR，本件补
                      算术语义，移位量越域按语义钳位并以 bSat 提示。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.3 位串移位函数 SHR 的语义与实参域
  平台   Platform   : 纯 IEC 61131-3（SHR / OR / 类型转换），CODESYS / TwinCAT 3 / InoProShop 通用
  依赖   Depends    : 仅 Standard.library（SHR 属标准位串函数）
  分工声明 Split     : FC_DL_ShrEx（DWORD 逻辑右移）与 FC_DL_ShrLwordEx（LWORD 逻辑
                      右移）为逻辑右移属主，本件不重复其职责；IEC 标准无算术右移原语，
                      故本件仅补符号扩展语义（R216 双向互引）。
  归属 Ownership     : 本件无 TYPE 声明；常量表 DL_SAR_MASK 为本文件私有常量。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 移位量归一（R48）：nShift ≥ 32 时不调用 SHR，直接走「全符号位
                         填充」常量路径，杜绝 SHL/SHR(x, 32) 的未定义行为；
                      二 高位掩码用 32 项预计算常量表，禁运行时 SHL(x, 32)；
                         掩码仅在符号位为 1 时参与 OR，否则会把非负结果污染成负数；
                      三 nShift ≤ 0 原值返回（0 移位不改值）；nShift < 0 反向移位非法，
                         钳 0 并置 bSat + 信息码，禁静默反向移位；
                      四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_064B【信息级】移位量为负已钳 0（反向移位非法，结果等于原值）
    16#0001_064C【信息级】移位量 ≥ 32 已按符号位全填充饱和（负数得 -1，非负得 0）
  码位反证 Note     :
    064B 与 064C 不可合并：两者 bSat 同为 TRUE，但「原值返回」与「全符号填充」是
    两个相反的语义分支，合并后现场无法由 diOut 与 bSat 唯一还原是哪种越域（R90）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 -8 >> 1 → -4；V2 -1 >> 5 → -1（全 1 保持）；V3 8 >> 31 → 0
    V4 8 >> 32 → 0 且 bSat = TRUE、码 064C
    V5 -8 >> 32 → -1 且 bSat = TRUE（符号填充）
    V6 x >> 0 → x 精确、bSat = FALSE、无码
    V7 x >> -1 → x 且 bSat = TRUE、码 064B（越域钳 0）
    V8 MIN >> 1 → -1073741824（符号保持）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 1 · 序号 3）
  ==================================================================
*)
FUNCTION FC_DL_ShiftArithEx : BOOL
VAR_INPUT
    diIn   : DINT; // 待移位值 [−]，完整 DINT 域 / the value to shift over the full DINT domain
    nShift : DINT; // 移位位数 [位]，合法域 1..31，0 原值、负值钳 0、≥32 饱和 / the shift amount in bits, valid one to thirty one
END_VAR
VAR_OUTPUT
    diOut  : DINT;  // 算术右移结果 [−] / the arithmetic shift result
    bSat   : BOOL;  // 移位量越域已被钳（含负值与 ≥32）[-] / the shift amount was out of domain and clamped
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（本件只有信息级码，恒 FALSE，保留引脚供族内统一）/ the fault flag, always false here since only informational codes exist
END_VAR
VAR
    udwWork : DWORD := 16#0000_0000; // 逻辑右移工作寄存器 [位] / the logical shift working register in bits
    nUse    : DINT := 0;             // 归一后的移位量 [位] / the normalized shift amount in bits
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_SAR_ZERO : DINT := 0;         // 零常量 [位] / the zero constant
    DL_SAR_BITS : DINT := 32;        // DINT 容器位宽 [位] / the DINT container width in bits
    DL_SAR_NEG1 : DINT := -1;        // 全 1 常量（负数饱和填充值）[−] / the all ones constant used as the negative saturation fill
    DL_SAR_MASK : ARRAY[0..31] OF DWORD := // 高位掩码表（第 k 项 = 高 k 位置 1，k = 0 为零），预计算禁运行时 SHL(x,32) [位] / the precomputed high side mask table, k bits set from the top
    [
        16#0000_0000, // k = 0：不移位，无高位 / k equals zero, no high bits at all
        16#8000_0000, // k = 1：最高 1 位 / the top single bit
        16#C000_0000, // k = 2 / two top bits
        16#E000_0000, // k = 3 / three top bits
        16#F000_0000, // k = 4 / four top bits
        16#F800_0000, // k = 5 / five top bits
        16#FC00_0000, // k = 6 / six top bits
        16#FE00_0000, // k = 7 / seven top bits
        16#FF00_0000, // k = 8 / eight top bits
        16#FF80_0000, // k = 9 / nine top bits
        16#FFC0_0000, // k = 10 / ten top bits
        16#FFE0_0000, // k = 11 / eleven top bits
        16#FFF0_0000, // k = 12 / twelve top bits
        16#FFF8_0000, // k = 13 / thirteen top bits
        16#FFFC_0000, // k = 14 / fourteen top bits
        16#FFFE_0000, // k = 15 / fifteen top bits
        16#FFFF_0000, // k = 16：高半字 / the whole high half word
        16#FFFF_8000, // k = 17 / seventeen top bits
        16#FFFF_C000, // k = 18 / eighteen top bits
        16#FFFF_E000, // k = 19 / nineteen top bits
        16#FFFF_F000, // k = 20 / twenty top bits
        16#FFFF_F800, // k = 21 / twenty one top bits
        16#FFFF_FC00, // k = 22 / twenty two top bits
        16#FFFF_FE00, // k = 23 / twenty three top bits
        16#FFFF_FF00, // k = 24 / twenty four top bits
        16#FFFF_FF80, // k = 25 / twenty five top bits
        16#FFFF_FFC0, // k = 26 / twenty six top bits
        16#FFFF_FFE0, // k = 27 / twenty seven top bits
        16#FFFF_FFF0, // k = 28 / twenty eight top bits
        16#FFFF_FFF8, // k = 29 / twenty nine top bits
        16#FFFF_FFFC, // k = 30 / thirty top bits
        16#FFFF_FFFE  // k = 31 / thirty one top bits
    ];
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, preset every outlet to its safe value
FC_DL_ShiftArithEx := FALSE; // 返回值预置假 / preset the return false
diOut := DL_SAR_ZERO; // 结果预置零 [−] / preset the result zero
bSat := FALSE; // 越域标志预置假 / preset the saturation flag false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假（本件无故障级码）/ preset the fault flag false, no fault level code exists here
udwWork := 16#0000_0000; // 工作寄存器清零 [位] / clear the working register
nUse := DL_SAR_ZERO; // 归一移位量清零 [位] / clear the normalized shift amount

// 段 2｜nShift ≤ 0：0 移位原值返回；负值反向移位非法，钳 0 并提示（边界三）/ segment 2, the non positive shift amount branch
IF nShift < DL_SAR_ZERO THEN // 反向移位非法 / a reverse shift is illegal
    bSat := TRUE; // 置越域标志 / raise the out of domain flag
    eErr := 16#0001_064B; // 信息级：移位量为负已钳 0 / informational, a negative amount is clamped to zero
    diOut := diIn; // 钳 0 后等于原值 [−] / with zero shift the result is the original value
    FC_DL_ShiftArithEx := TRUE; // 信息级不阻断，返回成功 / an informational code does not block, return success
    RETURN; // 早退 / early return
END_IF
IF nShift = DL_SAR_ZERO THEN // 零移位：不改值且无任何提示 / a zero shift changes nothing and raises nothing
    diOut := diIn; // 原值直出 [−] / pass the original value through
    FC_DL_ShiftArithEx := TRUE; // 返回成功 / return success
    RETURN; // 早退 / early return
END_IF

// 段 3｜nShift ≥ 32：不调用 SHR，直接按符号位全填充（边界一，禁 SHL/SHR(x,32)）/ segment 3, the at or above container width branch
IF nShift >= DL_SAR_BITS THEN // 移位量达到或超过容器位宽 / the amount reached or exceeded the container width
    bSat := TRUE; // 置越域标志 / raise the out of domain flag
    eErr := 16#0001_064C; // 信息级：移位量 ≥ 32 已按符号位全填充 / informational, the amount at or above thirty two fills with the sign bit
    IF diIn < DL_SAR_ZERO THEN // 负数：全 1 填充 / a negative value fills with all ones
        diOut := DL_SAR_NEG1; // 结果为 -1 [−] / the result is minus one
    ELSE // 非负数：全 0 填充 / a non negative value fills with zeros
        diOut := DL_SAR_ZERO; // 结果为 0 [−] / the result is zero
    END_IF
    FC_DL_ShiftArithEx := TRUE; // 返回成功 / return success
    RETURN; // 早退 / early return
END_IF

// 段 4｜1 ≤ nShift ≤ 31：逻辑右移 + 符号位为 1 时 OR 高位掩码（边界二）/ segment 4, the normal arithmetic shift by mask
nUse := nShift; // 域内移位量接管（已证 1..31）[位] / take the in-domain amount, proven one to thirty one
udwWork := SHR(DINT_TO_DWORD(diIn), nUse); // 逻辑右移（高位补 0）[位] / the logical shift with zeros shifted in
IF diIn < DL_SAR_ZERO THEN // 符号位为 1 才需补 1（非负数 OR 掩码会污染成负数）/ fill only for a set sign bit, otherwise the mask would turn the result negative
    udwWork := udwWork OR DL_SAR_MASK[nUse]; // 补入高 nUse 个 1 [位] / fill the top amount of ones
END_IF
diOut := DWORD_TO_DINT(udwWork); // 位型还原为有符号结果 [−] / reinterpret the bit pattern as a signed result

// 段 5｜统一出口（信息级未触发，码保持 0）/ segment 5, the unified outlet without any event
bSat := FALSE; // 正常路径明确落假（越域分支已早退）/ the normal path explicitly falls to false, the out of domain branches returned earlier
FC_DL_ShiftArithEx := TRUE; // 返回成功 / return success
END_FUNCTION
