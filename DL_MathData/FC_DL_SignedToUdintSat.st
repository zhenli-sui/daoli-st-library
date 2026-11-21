(*
  ==================================================================
  组件名 Component  : FC_DL_SignedToUdintSat
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0651（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : DINT → UDINT 确定性转换：负值钳 0 并发信息级提示（多数平台此类
                      隐式转换行为不一，负值可能回绕成巨大正数，是 Modbus 寄存器打包的
                      经典故障源）。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.5 类型转换函数与 §6.5 有符号/无符号整数域定义
  平台   Platform   : 纯 IEC 61131-3（DINT_TO_UDINT / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（DINT_TO_UDINT 属标准转换函数）
  分工声明 Split     : FC_DL_UdintToDintChk 为反方向（UDINT → DINT，超上界钳 MAX 并置
                      故障级码），本件为 DINT → UDINT（负值钳零并置信息级码），两件成对，
                      边界互引（R216）。16 位入口（INT → UINT 同语义）按「禁新增同义邻件」
                      纪律并入本件重载，不另立文件。
  归属 Ownership     : 本件无 TYPE 声明，全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 负值钳零是确定性合法行为而非故障：置信息级码、bValid 保持 TRUE、
                         bError 保持 FALSE（若按故障处理，Modbus 打包遇到合法的负温度
                         就会停机，分级明显错位）；
                      二 正域精确无溢出，域包含证明：DINT 非负域 [0, 2^31 − 1] 是全序
                         子集于 UDINT 全域 [0, 2^32 − 1]，即 [0, 2147483647] ⊂ [0, 4294967295]，
                         故 diIn ≥ 0 时 DINT_TO_UDINT 恒为精确映射，无须溢出分支；
                      三 反方向（UDINT → DINT）的越上界场景在本件域内不可能出现：
                         入参已是 UDINT 域内的值经 DINT 往返，属反方向件职责，本件不设分支；
                      四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_0651【信息级】负值已钳零（不锁存、不置 bError、bValid 保持 TRUE）
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 0 → 0、bNegClamped = FALSE、无码
    V2 -1 → 0 + bNegClamped + 码 0651（bError = FALSE）
    V3 MIN（-2147483648）→ 0 + bNegClamped + 码 0651
    V4 MAX（2147483647）→ 2147483647 精确、无码
    V5 反方向向量（2^32−1 入 DINT）域上不可能，注释已给域包含关系，无须代码分支
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 2 · 序号 6）
  ==================================================================
*)
FUNCTION FC_DL_SignedToUdintSat : BOOL
VAR_INPUT
    diIn : DINT; // 有符号输入 [−]，完整 DINT 域 / the signed input over the full DINT domain
END_VAR
VAR_OUTPUT
    udiOut      : UDINT; // 无符号结果 [−] / the unsigned result
    bNegClamped : BOOL;  // 负值已钳零 [-] / a negative value was clamped to zero
    bValid      : BOOL;  // 结果可用（本件恒 TRUE，保留引脚供族内统一）[-] / the result is usable, always true here
    eErr        : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError      : BOOL;  // 故障标志（本件只有信息级码，恒 FALSE）/ the fault flag, always false here since only an informational code exists
END_VAR
VAR CONSTANT
    DL_S2U_ZERO : DINT := 0;                  // 有符号零常量 [−] / the signed zero constant
    DL_S2U_UMIN : UDINT := 0;                 // 无符号零常量 [−] / the unsigned zero constant
    DL_S2U_DMAX : DINT := 2147483647;         // DINT 可表达上界 [−]，即 2^31−1 / the expressible DINT ceiling, two to the thirty first minus one
    DL_S2U_UMAX : UDINT := 4294967295;        // UDINT 可表达上界 [−]，即 2^32−1 / the expressible UDINT ceiling, two to the thirty second minus one
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, preset every outlet to its safe value
FC_DL_SignedToUdintSat := FALSE; // 返回值预置假 / preset the return false
udiOut := DL_S2U_UMIN; // 结果预置零 [−] / preset the result zero
bNegClamped := FALSE; // 负值钳零标志预置假 / preset the negative clamp flag false
bValid := FALSE; // 可用标志预置假，过闸后置位 / preset the validity false, raised after the gates
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假（本件无故障级码）/ preset the fault flag false, no fault level code exists here

// 段 2｜负值钳零（边界一：确定性行为，非故障）/ segment 2, the negative clamp is a deterministic behaviour, not a fault
IF diIn < DL_S2U_ZERO THEN // 负值域 / the negative domain
    udiOut := DL_S2U_UMIN; // 钳零 [−] / clamp to zero
    bNegClamped := TRUE; // 置钳零标志 / raise the negative clamp flag
    eErr := 16#0001_0651; // 信息级：负值已钳零 / informational, a negative value was clamped to zero
    bError := FALSE; // 明确不置故障标志（信息级，R285 分级纪律）/ keep the fault flag false, this is informational
ELSE // 非负域：精确映射（边界二域包含证明）/ the non negative domain maps exactly
    udiOut := DINT_TO_UDINT(diIn); // 标准显式转换（DINT 非负域 ⊆ UDINT 全域）[−] / the standard explicit conversion, the signed non negative domain is a subset of the unsigned domain
END_IF

// 段 3｜统一出口（信息级钳零仍可用）/ segment 3, the unified outlet where a clamped zero stays usable
bValid := TRUE; // 负值钳零与正域精确均可用 / both the clamped zero and the exact positive domain are usable
FC_DL_SignedToUdintSat := TRUE; // 返回成功 / return success
END_FUNCTION
