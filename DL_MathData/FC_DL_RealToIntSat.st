(*
  ==================================================================
  组件名 Component  : FC_DL_RealToIntSat
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_064E（信息级）｜ 16#0001_064F / 0650（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : LREAL → INT（16 位）饱和转换，统一三平台「部分平台饱和、部分平台
                      回绕」的差异；NaN / ±Inf / 越界全部确定性处置。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.5 类型转换函数（REAL 到整型的截断语义）
  平台   Platform   : 纯 IEC 61131-3（LREAL_TO_INT / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（LREAL_TO_INT 属标准转换函数）
  分工声明 Split     : FC_DL_RealToDintSat（32 位）与 FC_DL_RealToByteSat（8 位）为同位宽
                      兄弟件，本件补 INT（16 位），三件构成位宽三分（R216 双向互引）；
                      工程舍入（四舍五入）归 FC_DL_RoundSat，有效位舍入归 FC_DL_RoundSigFigs，
                      本件只做向零截断。
  归属 Ownership     : 本件无 TYPE 声明，全部引脚为 IEC 标准原生类型。
  编译门槛 Gate      : 交付门槛：主路径委托平台内建 LREAL_TO_INT，其截断（向零）语义须在
                      CODESYS / TwinCAT 3 / InoProShop 三平台各编译并跑一次本文件 V2 向量
                      （R64 内建转换链交付门槛）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 判据严格有序：① NaN → 0 + 故障码 + bValid FALSE + 早退；
                         ② 组态 nLo > nHi → 故障码 + 早退；③ ±Inf → 对应边界；
                         ④ 越界 → 钳边界 + bClamped；⑤ 域内 → 向零截断；
                      二 一律在转换之前做域钳（R151：实数转整数前先钳，防溢出使方向翻转）；
                      三 非有限判据用自反与差值自减，禁用近似阈值（R79）：
                         NaN 用 fIn <> fIn，Inf 用 (fIn − fIn) <> (fIn − fIn)；
                      四 bClamped 与 bNonFinite 语义可分：域钳只置前者，非有限两者都置；
                      五 nLo > nHi 判组态故障返回 FALSE（与 FC_DL_SaturateMul / Div 同口径）；
                      六 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_064E【信息级】输入越 [nLo, nHi] 已钳边界（bClamped = TRUE，bValid = TRUE）
    16#0001_064F【故障级】输入非有限（NaN 返 0；±Inf 钳对应边界；bValid = FALSE）
    16#0001_0650【故障级】组态非法 nLo > nHi（判故障返回 FALSE，nOut = 0）
  码位反证 Note     :
    064E 不可并入 064F：域钳结果可用（bValid = TRUE、无 bError），非有限结果不可用，
    上游 HMI 按 bValid 过滤时两者必须分开，合并会让「钳位可用」被当成「测点坏」停机（R90）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 0.0 → 0、bClamped = FALSE、无码
    V2 -0.5 → 0（向零截断）、bClamped = FALSE（域内，仅截断）
    V3 32767.9 → 32767（越上界半个 LSB，钳上界）
    V4 32768.0 → 32767 + bClamped + 码 064E
    V5 -32768.1 → -32768 + bClamped + 码 064E
    V6 NaN → 0 + bNonFinite = TRUE + bValid = FALSE + 码 064F
    V7 1.0E9 → 32767 + bClamped + 码 064E
    V8 nLo > nHi → 码 0650 + 返回 FALSE
    V9 nLo = nHi = 100 → 恒定输出 100 + bClamped（域退化）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 2 · 序号 5）
  ==================================================================
*)
FUNCTION FC_DL_RealToIntSat : BOOL
VAR_INPUT
    fIn : LREAL;          // 输入量 [工程单位]，必须有限 / the input value, must be finite
    nLo : INT := -32768;  // 目标钳位域下界 [−]，默认 INT 全域下界 / the clamp floor, the INT domain floor by default
    nHi : INT := 32767;   // 目标钳位域上界 [−]，默认 INT 全域上界 / the clamp ceiling, the INT domain ceiling by default
END_VAR
VAR_OUTPUT
    nOut      : INT;   // 饱和转换结果 [−] / the saturated integer result
    bClamped  : BOOL;  // 域钳位发生（含 ±Inf 钳边界）[-] / a domain clamp happened, the infinite boundary clamp included
    bNonFinite: BOOL;  // 输入非有限（NaN 或 ±Inf）[-] / the input was not finite
    bValid    : BOOL;  // 输出可用（非有限与组态故障为 FALSE）[-] / the output is usable
    eErr      : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError    : BOOL;  // 故障标志，故障级码同拍置位（R45 配对）/ the fault flag, raised with a fault level code
END_VAR
VAR
    fLo : LREAL := 0.0; // 下界的实数形式 [−] / the floor in real form
    fHi : LREAL := 0.0; // 上界的实数形式 [−] / the ceiling in real form
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_R2I_ZERO : LREAL := 0.0;   // 实数零常量 [−] / the real zero constant
    DL_R2I_NONE : INT := 0;       // 整型零常量 [−] / the integer zero constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, preset every outlet to its safe value
FC_DL_RealToIntSat := FALSE; // 返回值预置假 / preset the return false
nOut := DL_R2I_NONE; // 结果预置零 [−] / preset the result zero
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false
bNonFinite := FALSE; // 非有限标志预置假 / preset the non finite flag false
bValid := FALSE; // 可用标志预置假，过闸后置位 / preset the validity false, raised after the gates
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
fLo := DL_R2I_ZERO; // 下界实数形式清零 / clear the floor in real form
fHi := DL_R2I_ZERO; // 上界实数形式清零 / clear the ceiling in real form

// 段 2｜判据①NaN：自反性判定，禁近似阈值（边界三，R79）/ segment 2, the NaN gate by reflexivity
IF fIn <> fIn THEN // NaN：一切比较均为假，只能用自反性 / NaN leaves every comparison false, reflexivity is the only test
    bNonFinite := TRUE; // 置非有限标志 / raise the non finite flag
    bValid := FALSE; // 结果不可用（三件套之一，R258）/ the result is not usable
    nOut := DL_R2I_NONE; // 确定缺省值零 [−] / the deterministic default of zero
    eErr := 16#0001_064F; // 故障级：输入非有限 / fault grade, the input is not finite
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退 / early return
END_IF

// 段 3｜判据②组态域闸：nLo > nHi 判故障早退（边界五）/ segment 3, the configuration gate, a reversed domain is a fault
IF nLo > nHi THEN // 钳位域反序 / the clamp domain is reversed
    eErr := 16#0001_0650; // 故障级：组态非法 nLo > nHi / fault grade, the reversed clamp domain
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 输出不可用 / the output is not usable
    nOut := DL_R2I_NONE; // 确定缺省值零 [−] / the deterministic default of zero
    RETURN; // 早退 / early return
END_IF

// 段 4｜判据③±Inf：差值自减判无穷（边界三），钳到对应边界并判故障 / segment 4, the infinite gate by the self difference
IF (fIn - fIn) <> (fIn - fIn) THEN // 无穷处 fIn − fIn 产 NaN，有限值恒为零 / an infinite input yields NaN from the self difference while a finite one yields zero
    bNonFinite := TRUE; // 置非有限标志 / raise the non finite flag
    bClamped := TRUE; // 钳边界已生效 / the boundary clamp took effect
    bValid := FALSE; // 结果不可用（三件套之一，R258）/ the result is not usable
    IF fIn > DL_R2I_ZERO THEN // 正无穷 / the positive infinity
        nOut := nHi; // 钳上界 [−] / clamp to the ceiling
    ELSE // 负无穷 / the negative infinity
        nOut := nLo; // 钳下界 [−] / clamp to the floor
    END_IF
    eErr := 16#0001_064F; // 故障级：输入非有限 / fault grade, the input is not finite
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退 / early return
END_IF

// 段 5｜判据④⑤先钳后转：转换前必须落域内（边界二，R151）/ segment 5, clamp before the conversion
fLo := INT_TO_LREAL(nLo); // 下界实数形式 [−] / the floor in real form
fHi := INT_TO_LREAL(nHi); // 上界实数形式 [−] / the ceiling in real form
IF fIn < fLo THEN // 越下界 / below the floor
    nOut := nLo; // 钳下界 [−] / clamp to the floor
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
    eErr := 16#0001_064E; // 信息级：越下界已钳位 / informational, below the floor and clamped
ELSIF fIn > fHi THEN // 越上界 / above the ceiling
    nOut := nHi; // 钳上界 [−] / clamp to the ceiling
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
    eErr := 16#0001_064E; // 信息级：越上界已钳位 / informational, above the ceiling and clamped
ELSE // 域内：向零截断（四舍五入口径归 FC_DL_RoundSat）/ inside the domain, truncate toward zero
    nOut := LREAL_TO_INT(fIn); // 向零截断（-0.5 → 0，非 -1）[−] / truncated toward zero, minus a half gives zero
END_IF

// 段 6｜统一出口（信息级钳位不置 bError，R285）/ segment 6, the unified outlet without a fault flag
bValid := TRUE; // 域内或钳位输出均可用 / an in-domain or clamped output is usable
FC_DL_RealToIntSat := TRUE; // 返回成功 / return success
END_FUNCTION
