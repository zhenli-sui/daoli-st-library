(*
  ==================================================================
  组件名 Component  : FC_DL_DintToBcd
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0658（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : DINT → 8 位 BCD（DWORD 容器），负值显式拒绝 + 越域显式拒绝，
                      逐位 MOD 10 / DIV 10 提取后按权装入半字节。
  开源溯源 Origin    : 公开公式 clean-room，参考 BCD 编码公开工程语义（分类与参数域
                      借鉴，零代码复制），本件实现、闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术与移位运算符（MOD / DIV / SHL / OR）
  平台   Platform   : 纯 IEC 61131-3（FOR / MOD / DIV / SHL / OR），三平台通用
  依赖   Depends    : 仅 Standard.library（无库调用）
  分工声明 Split     : FC_DL_ByteToBcd / FC_DL_WordToBcd / FC_DL_UdintToBcd 为既有
                      BCD 编码族（无符号域入口），本件为 DINT 带符号域入口；负值
                      显式拒绝为本件与 UDINT 版本的**行为差异**（写死，禁取绝对值
                      回绕伪装成功）；MOD/DIV 10 原语经派单规格明写授权，本件为
                      BCD 编解码属主；四件互引（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 判据顺序（写死）：① nIn < 0 → 故障级码 + udBcd = 0 早退
                         （负值不可 BCD 表示，禁取绝对值回绕）；② nIn > 99999999 →
                         越域故障 + bOvF = TRUE 早退；③ 正常才进入提取；
                      二 两场景一码的反证句（R90）：负值与越域的出口仅 bOvF 一位
                         之差（负值 FALSE / 越域 TRUE），一个输出位即可唯一还原
                         场景，三组以内输出可区分，按 R90 不另立码；
                      三 移位量 4·k（k = 0..7）最大 28 < 32（DWORD 位宽），结构性
                         安全（R48）；
                      四 越域上界常量 DL_BCD_MAX = 99999999 与 8 位 BCD 可表域
                         一致，超域属「不可表」而非「截断后仍可用」，禁静默截断；
                      五 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      六 无全局、无外部变量、无物理地址、无指针。
  错误码 Codes      :
    16#0001_0658【故障级】不可 BCD 编码（nIn < 0 负值，bOvF = FALSE；或
                         nIn > 99999999 越域，bOvF = TRUE）
  码位反证 Note     :
    负值与越域共用一码：出口组合仅 bOvF 一位可区分（边界二反证句），按 R90 不另立。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 0 → 16#00000000；V2 99999999 → 16#99999999（恰好整除上界向量）
    V3 -1 → 故障 0658 + bOvF = FALSE + 早退（禁取绝对值）
    V4 100000000 → 故障 0658 + bOvF = TRUE + 早退
    V5 12345678 → 16#12345678
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 1 · 序号 2）
  ==================================================================
*)
FUNCTION FC_DL_DintToBcd : BOOL
VAR_INPUT
    nIn     : DINT := 0; // 待编码整数 [个]，合法域 0..99999999 / the integer to encode, legal from zero to ninety nine million
END_VAR
VAR_OUTPUT
    udBcd   : DWORD := 16#00000000; // 8 位 BCD 输出 [码] / the eight digit BCD output
    bOvF    : BOOL := FALSE;        // 越域标志（仅 nIn > 99999999 置位）[-] / the overflow flag raised only above the BCD domain
    bValid  : BOOL := FALSE;        // 结果可用 [-] / the result usable flag
    eErr    : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL := FALSE;        // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    k       : DINT := 0;  // 码元位置索引 [下标]，0..7 / the digit position index from zero to seven
    nShift  : DINT := 0;  // 移位量 [位]，4·k ≤ 28 结构性安全 / the shift amount of four times the position, proven below the word width
    nWork   : DINT := 0;  // 逐位提取工作副本 [个] / the working copy of the digit extraction
    uDig    : USINT := 0; // 当前位码元 [位] / the current digit extracted
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_BCD_MAX   : DINT := 99999999;   // 8 位 BCD 可表上界 [个] / the representable ceiling of the eight digit BCD
    DL_BCD_N     : DINT := 8;          // 码元总数 [个] / the digit count of eight
    DL_BCD_TEN   : DINT := 10;         // 十进制提取基数 [个] / the decimal extraction base of ten
    DL_BCD_NIB   : DINT := 4;          // 每码元位宽 [位] / the nibble width of four bits
    DL_BCD_ZERO  : DINT := 0;          // 整型零常量 [个] / the integer zero constant
    DL_BCD_ONE   : DINT := 1;          // 整型一常量 [个] / the integer one constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and every outlet
FC_DL_DintToBcd := FALSE; // 返回值预置假 / preset the return false
udBcd := 16#00000000; // BCD 输出预置全零 [码] / preset the BCD output to all zeros
bOvF := FALSE; // 越域标志预置假 / preset the overflow flag false
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the error flag false
nWork := DL_BCD_ZERO; // 工作副本预置零 [个] / preset the working copy zero
k := DL_BCD_ZERO; // 索引预置零 / preset the index zero
nShift := DL_BCD_ZERO; // 移位量预置零 [位] / preset the shift amount zero
uDig := 0; // 码元预置零 [位] / preset the digit zero

// 段 2｜判据一：负值显式拒绝（边界一①，禁取绝对值回绕伪装成功）/ segment 2, the negative value rejection
IF nIn < DL_BCD_ZERO THEN // 负值不可 BCD 表示 / a negative value is not representable in BCD
    udBcd := 16#00000000; // 输出强制全零 [码] / force the output to all zeros
    eErr := 16#0001_0658; // 故障级：不可 BCD 编码（负值，bOvF 保持 FALSE 供区分）/ fault grade, not encodable as BCD, the overflow flag stays false for the discrimination
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 3｜判据二：越域显式拒绝（边界一②，禁静默截断）/ segment 3, the domain overflow rejection
IF nIn > DL_BCD_MAX THEN // 超 8 位 BCD 可表上界 / above the representable ceiling
    udBcd := 16#00000000; // 输出强制全零 [码] / force the output to all zeros
    bOvF := TRUE; // 置越域标志（与负值场景的唯一区分位）/ raise the overflow flag, the only bit distinguishing this scene
    eErr := 16#0001_0658; // 故障级：不可 BCD 编码（越域）/ fault grade, not encodable as BCD, the domain is exceeded
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 4｜逐位提取与按权装入（移位量 4·k ≤ 28 < 32 结构性安全，边界三）/ segment 4, the digit extraction and the weighted packing
nWork := nIn; // 工作副本接管 [个] / take the working copy
FOR k := DL_BCD_ZERO TO DL_BCD_N - DL_BCD_ONE DO // 有界遍历 8 个码元位置 / the bounded traversal over eight digit positions
    uDig := DINT_TO_USINT(nWork MOD DL_BCD_TEN); // 当前位 = nWork MOD 10 [位] / the current digit is the remainder of ten
    nWork := nWork / DL_BCD_TEN; // 副本右移一位（DINT 整除截断，nIn ≥ 0 已证，无负回绕）/ shift the copy one digit right, the truncating division is safe since the input is proven non negative
    nShift := DL_BCD_NIB * k; // 移位量 = 4·k，最大 28 [位] / the shift amount of four times the position
    udBcd := udBcd OR SHL(USINT_TO_DWORD(uDig), nShift); // 码元装入对应半字节（OR 合成）/ pack the digit into its nibble by the or composition
END_FOR

// 段 5｜统一出口 / segment 5, the unified outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_DintToBcd := TRUE; // 返回成功 / return success
END_FUNCTION
