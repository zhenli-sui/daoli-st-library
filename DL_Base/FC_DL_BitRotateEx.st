//==============================================================================
// 函数：FC_DL_BitRotateEx ｜ 中文名称：位串循环移位（跨位回卷）
// 所属子库：DL_Base ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯标准库 SHL/SHR 组合）
// 功能描述：位串循环移位原子：左/右方向 × 8/16/32 位宽度域内回卷。
//           实现口径：SHL(x,n) OR SHR(x,w−n) 组合回卷，n 先归一到
//           [0, w−1]（负移位量取模回卷，禁 SHL(x,位宽) 未定义行为——
//           移位量归一后为 0 时直通返回原值，落位组合分支的移位量恒在
//           1..w−1 安全域）。与 ShlEx/ShrEx 邻件分工：那两件做饱和/截断
//           单向移位，本件只做回卷循环移位，互不替代。
// 开源溯源 (Origin)：原创实现（t0-std-wrapper 包装族补口，零外部源码行，
//           clean-room 独立编写；与 ShlEx/ShrEx 邻件分工已在头注释声明）
// 公开接口清单：输入 dwVal / nShift / eDir / eWidth；输出 dwRotated / bValid
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0.0），本件不占用 16#0001 段码位（邻件免让位）
// 状态机：E_DL_RotDir / E_DL_RotWidth（本文件唯一定义，全库唯一属主）：
//           方向 eLeft = 0 / eRight = 1；宽度 eW8 = 8 / eW16 = 16 / eW32 = 32
// 边界行为：① 移位量任意整数（含负值）先 MOD 归一到 [0, w−1]；
//           ② 归一后为 0 直通返回原值（组合分支移位量恒 1..w−1，禁
//             SHL(x,位宽) 未定义行为）；
//           ③ 宽度域外（非 8/16/32）→ 哨兵 0.0 返回；
//           ④ 回卷结果按宽度掩码截取（高位残留清零）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 12）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_RotDir / E_DL_RotWidth（归属本函数，同文件发布，全库唯一属主）
 * 含义: 移位方向与位串宽度域，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_RotDir :
(
    eLeft  := 0,   // 左循环移位 / Rotate left
    eRight := 1    // 右循环移位 / Rotate right
);
END_TYPE

TYPE E_DL_RotWidth :
(
    eW8  := 8,     // 8 位宽度域 / 8-bit width domain
    eW16 := 16,    // 16 位宽度域 / 16-bit width domain
    eW32 := 32     // 32 位宽度域 / 32-bit width domain
);
END_TYPE

(*------------------------------------------------------------------------------
 * 调用示例：dwR := FC_DL_BitRotateEx(dwVal := 16#0000_00A1,
 *             nShift := 3, eDir := E_DL_RotDir.eLeft,
 *             eWidth := E_DL_RotWidth.eW8, bValid => bOk);
 * 注意：移位量先归一回卷，任意整数（含负）均合法；宽度域外拒绝。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_BitRotateEx : DWORD
VAR_INPUT
    dwVal   : DWORD;                   // 输入位串 [—] / Input bit pattern
    nShift  : DINT;                    // 移位量 [位]，任意整数（含负，取模回卷）/ Shift amount [bits], any integer, wrapped by modulo
    eDir    : E_DL_RotDir;             // 移位方向枚举 [—] / Rotation direction enum
    eWidth  : E_DL_RotWidth;           // 位串宽度域枚举 [位] / Width domain enum [bits]
END_VAR
VAR_OUTPUT
    bValid  : BOOL;                    // 结果有效标志，FALSE 时返回哨兵 0.0 / Result validity flag
END_VAR
VAR
    nW      : DINT;                    // 生效宽度 [位] / Effective width [bits]
    nEff    : DINT;                    // 归一后移位量 [位]，域 0..w−1 / Normalized shift [bits], range 0..w-1
    dwMask  : DWORD;                   // 宽度掩码 / Width mask
    dwLo    : DWORD;                   // 回卷低位段 / Wrapped low segment
    dwHi    : DWORD;                   // 回卷高位段 / Wrapped high segment
END_VAR
VAR CONSTANT
    DW_ROT_SENTINEL : DWORD := 16#0000_0000; // 无效哨兵返回值 / Sentinel return for invalid
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
bValid := FALSE;                      // 缺省无效 / Invalid by default

// ---- 段 2｜宽度域解析（CASE 带 ELSE；非法宽度拒绝）----
CASE eWidth OF
    E_DL_RotWidth.eW8:                 // 8 位域：掩码低 8 位 / 8-bit domain
        nW     := 8;                   // 生效宽度 [位] / Effective width
        dwMask := 16#0000_00FF;        // 宽度掩码 / Width mask
    E_DL_RotWidth.eW16:                // 16 位域：掩码低 16 位 / 16-bit domain
        nW     := 16;                  // 生效宽度 [位] / Effective width
        dwMask := 16#0000_FFFF;        // 宽度掩码 / Width mask
    E_DL_RotWidth.eW32:                // 32 位域：全掩码 / 32-bit domain
        nW     := 32;                  // 生效宽度 [位] / Effective width
        dwMask := 16#FFFF_FFFF;        // 宽度掩码 / Width mask
    ELSE                               // 枚举非法值兜底（R21：CASE 必带 ELSE）
        FC_DL_BitRotateEx := DW_ROT_SENTINEL; // 非法宽度：哨兵零返回 / Illegal width, sentinel zero return
        RETURN;                        // 结构早退 / early exit
END_CASE

// ---- 段 3｜移位量归一：MOD 取模 + 双侧回卷（负移位量合法）----
nEff := nShift MOD nW;                // 先取模（可能为负，DINT MOD 语义随被除数）/ Modulo first, may be negative
IF nEff < 0 THEN
    nEff := nEff + nW;                // 负移位量回卷到 [0, w−1] / Negative shift wrapped up
END_IF

// ---- 段 4｜回卷主体：移位量 0 直通；组合分支移位量恒 1..w−1 安全域 ----
IF nEff = 0 THEN
    FC_DL_BitRotateEx := dwVal AND dwMask; // 零移位直通（掩码截取）/ Zero shift pass-through, masked
ELSE
    IF eDir = E_DL_RotDir.eLeft THEN  // 左循环：高段出环回低位
        dwHi := SHL(dwVal AND dwMask, DINT_TO_UINT(nEff));        // 左移高位段（标准显式转换 R10）/ Left-shifted high segment, standard explicit cast
        dwLo := SHR(dwVal AND dwMask, DINT_TO_UINT(nW - nEff));   // 出环段回卷到低位 / Wrapped-out segment to low bits
        FC_DL_BitRotateEx := (dwHi OR dwLo) AND dwMask; // 回卷合成 + 掩码截取 / Rotated blend, masked
    ELSE                              // 右循环（含枚举非法值并入右旋，方向枚举仅两员）
        dwLo := SHR(dwVal AND dwMask, DINT_TO_UINT(nEff));        // 右移低位段 / Right-shifted low segment
        dwHi := SHL(dwVal AND dwMask, DINT_TO_UINT(nW - nEff));   // 出环段回卷到高位 / Wrapped-out segment to high bits
        FC_DL_BitRotateEx := (dwHi OR dwLo) AND dwMask; // 回卷合成 + 掩码截取 / Rotated blend, masked
    END_IF
END_IF
bValid := TRUE;                       // 全部防御通过：结果有效 / Result valid
END_FUNCTION
