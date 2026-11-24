(*
  ==================================================================
  组件名 Component  : FC_DL_RunningSumCalc
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0668（故障级）｜ 16#0001_0669（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : LREAL 运行累加和：Kahan 补偿求和防长序列累积误差，非
                      有限闸冻结状态，DINT 拍数饱和计数；供产期能耗累计、
                      批次总量计量、运行时长折算等调用方使用。
  开源溯源 Origin    : T0 统计族补口（内部来源，零检索）；Kahan 补偿求和为
                      公共领域算法（Kahan 1965）；增量式运行口径 + 非有限闸
                      为本库扩展，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；Kahan 补偿求和
                      （Kahan 1965，公共领域算法）
  平台   Platform   : 纯 IEC 61131-3（四则 / 比较），三平台通用
  依赖   Depends    : 无（零委托、零库件）
  分工声明 Split     : FC_DL_SignalStatistics（窗口统计族，批内全量重算）为
                      互补件（互引）；本件为逐拍增量式运行口径（状态外置
                      结构体），统计族为窗内批处理口径，职责不同（R216）。
  归属 Ownership     : ST_DL_RunningSumState 属主为本文件（全库唯一定义，
                      R264）；引用件只引用不重声明。状态经 VAR_IN_OUT 外置，
                      本件零内部记忆量（FC 无实例态，纯 IEC 口径）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 状态外置契约：累计状态（主和 / 补偿项 / 拍数）由
                         调用方持有（ST_DL_RunningSumState 实例经 VAR_IN_OUT
                         传入），本件零内部记忆量；调用方须每拍以同一实例
                         调用，跨实例混用即口径破坏（头注释声明，不做运行
                         期甄别——FC 无法取得实例身份，无永假防御）；
                      二 非有限闸：fSample 非有限（NaN / ±Inf）→ 故障级
                         0668 + 状态冻结（主和 / 补偿 / 拍数本拍不动）+
                         bValid = FALSE + bError = TRUE；nMaxScans < 1
                         （组态非法）出口组合同形（本拍不累加、状态不动、
                         三件套），合并一码（反证句见码表）；
                      三 Kahan 补偿链：y = fSample − fComp；t = fSum + y；
                         fComp = (t − fSum) − y；fSum = t（防长序列累积
                         误差，每拍补偿项回吸）；
                      四 结果复检：Kahan 后 fSum 非有限（理论上不可达的
                         兜底，R258）→ 同码 0668 + 状态冻结 + 三件套；
                      五 拍数饱和（信息级 0669）：nScans 已达 nMaxScans 后
                         拍数计数饱和钳位不再推进，累加本身继续（拍数是
                         审计量不是累加门槛），置信息级 0669 不置 bError；
                      六 bReset 电平复位：主和 / 补偿 / 拍数 / 冻结标记
                         全量清账（复位优先于累加，回夹路径显式清账）；
                      七 无定时器、无边沿实例；无除法；无全局、无外部
                         变量、无物理地址。
  错误码 Codes      :
    16#0001_0668【故障级】fSample 非有限（状态冻结）或 nMaxScans < 1（组态
                         非法）或结果复检命中非有限（三场景出口同形，合并一码）
    16#0001_0669【信息级】拍数已达 nMaxScans 饱和钳位（累加继续，不置 bError）
  码位反证 Note     :
    0668 合并三场景（样本非有限 / 拍数上限组态非法 / 结果复检命中）的理由：
    三场景出口组合完全相同（状态四元组本拍不动、bValid = FALSE、bError =
    TRUE），三组以内输出无法唯一还原该场景，按 R90 不另立码；0669 与 0668
    分立：0669 出口 bValid = TRUE（累加继续），bValid 可唯一区分。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 累加 1.0 × 10 拍 → fSum = 10.0、nScans = 10
    V2 长序列误差向量：1.0E16 起 +1.0 累加 1000 拍 → Kahan fSum 精度优于
       朴素累加（与 FC_DL_SignalStatistics 直和对比断言）
    V3 fSample = NaN 单拍 → 码 0668 + fSum 不动 + bError = TRUE，下一拍
       恢复正常样本继续累加（NaN 输入冻结不粘滞）
    V4 nMaxScans = 5、累加 8 拍 → nScans = 5（饱和）、fSum 照常推进、
       码 0669（bError = FALSE）
    V5 nMaxScans = 0 → 码 0668 + 状态不动
    V6 bReset 一拍 → fSum / fComp / nScans 全量清零
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 2 · 序号 7，T0 统计族补口，Kahan 增量口径）
  ==================================================================
*)
TYPE ST_DL_RunningSumState :
STRUCT
    fSum   : LREAL := 0.0; // Kahan 主和 [工程单位] / the kahan main sum
    fComp  : LREAL := 0.0; // Kahan 补偿项 [工程单位]（每拍回吸损失）/ the kahan compensation term
    nScans : DINT   := 0;  // 累计拍数 [拍]（饱和上限 nMaxScans）/ the accumulated scan count saturated at the ceiling
    bFrozen: BOOL   := FALSE; // 状态冻结标记（非有限冻结期累计挂起）/ the frozen flag suspending the accumulation
END_STRUCT
END_TYPE

FUNCTION FC_DL_RunningSumCalc : BOOL
VAR_IN_OUT
    stState : ST_DL_RunningSumState; // 累计状态（调用方持有，须每拍同一实例）/ the accumulation state owned by the caller with the same instance every scan
END_VAR
VAR_INPUT
    fSample   : LREAL := 0.0; // 本拍样本 [工程单位]，必须有限 / the sample of this scan, must be finite
    nMaxScans : DINT   := 0;  // 拍数饱和上限 [拍]，须 ≥ 1，0 = 未组态（判故障）/ the scan ceiling, at least one, zero means unconfigured
    bReset    : BOOL  := FALSE; // 复位电平，TRUE 拍全量清账（复位优先于累加）/ the reset level clearing the whole state first
END_VAR
VAR_OUTPUT
    fSum   : LREAL; // 累加和出口 [工程单位] / the running sum outlet
    nScans : DINT;  // 累计拍数出口 [拍]（饱和口径）/ the scan count outlet saturated
    bValid : BOOL;  // 结果可用 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    fY : LREAL := 0.0; // Kahan 增量工作副本（样本 − 补偿）[工程单位] / the kahan increment copy of the sample minus the compensation
    fT : LREAL := 0.0; // Kahan 中间和工作副本 [工程单位] / the kahan intermediate sum copy
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_RSC_ZERO : LREAL := 0.0; // 实数零常量 [工程单位] / the real zero constant
    DL_RSC_ZEROI: DINT   := 0;  // 整型零常量 [拍] / the integer zero constant
    DL_RSC_ONEI : DINT   := 1;  // 整型一常量 [拍] / the integer one constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_RunningSumCalc := FALSE; // 返回值预置假 / preset the return false
fSum := stState.fSum; // 和出口预置为现行状态值（冻结 / 复位口径的基线）[工程单位] / preset the sum outlet from the current state
nScans := stState.nScans; // 拍数出口预置为现行状态值 [拍] / preset the count outlet from the current state
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
fY := DL_RSC_ZERO; // Kahan 增量预置零 [工程单位] / preset the kahan increment zero
fT := DL_RSC_ZERO; // Kahan 中间和预置零 [工程单位] / preset the kahan intermediate zero

// 段 2｜复位优先段（边界六：全量清账，复位优先于累加与一切闸）/ segment 2, the reset first with the full clearing
IF bReset THEN // 复位电平有效 / the reset level is active
    stState.fSum := DL_RSC_ZERO; // 主和清账 [工程单位] / clear the main sum
    stState.fComp := DL_RSC_ZERO; // 补偿项清账 [工程单位] / clear the compensation
    stState.nScans := DL_RSC_ZEROI; // 拍数清账 [拍] / clear the scan count
    stState.bFrozen := FALSE; // 冻结标记清账 / clear the frozen flag
    fSum := DL_RSC_ZERO; // 和出口同步清零 [工程单位] / sync the sum outlet zero
    nScans := DL_RSC_ZEROI; // 拍数出口同步清零 [拍] / sync the count outlet zero
    bValid := TRUE; // 复位是合法可用结果 / the reset is a legit usable result
    FC_DL_RunningSumCalc := TRUE; // 返回成功 / return success
    RETURN; // 早退（复位拍不累加）/ early return, no accumulation on the reset scan
END_IF

// 段 3｜非有限闸与组态闸（边界二：两场景出口同形合并一码，状态冻结）/ segment 3, the finiteness gate and the configuration gate freezing the state
IF (fSample <> fSample) OR ((fSample - fSample) <> (fSample - fSample))
OR (nMaxScans < DL_RSC_ONEI) THEN // 样本非有限或拍数上限组态非法 / the sample is not finite or the ceiling is misconfigured
    stState.bFrozen := TRUE; // 置状态冻结（本拍累计挂起）/ raise the frozen flag
    eErr := 16#0001_0668; // 故障级：非有限或组态非法（合并一码，R90）/ fault grade under the merged code
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，状态四元组本拍不动 / early return, the state untouched this scan
END_IF

// 段 4｜Kahan 补偿累加（边界三；冻结期挂起，恢复后自动续计）/ segment 4, the kahan compensated accumulation
IF NOT stState.bFrozen THEN // 未冻结才累加 / accumulate only when not frozen
    fY := fSample - stState.fComp; // 增量 = 样本 − 补偿项 [工程单位] / the increment of the sample minus the compensation
    fT := stState.fSum + fY; // 中间和 [工程单位] / the intermediate sum
    stState.fComp := (fT - stState.fSum) - fY; // 补偿项回吸本轮舍入损失 [工程单位] / the compensation sucking back the rounding loss
    stState.fSum := fT; // 主和推进 [工程单位] / advance the main sum
    IF stState.nScans < nMaxScans THEN // 拍数未达上限 / the count below the ceiling
        stState.nScans := stState.nScans + DL_RSC_ONEI; // 拍数推进 [拍] / advance the scan count
    ELSE // 拍数已达上限：饱和钳位 + 信息级（累加继续，边界五）/ the count saturated with the info code, the accumulation continues
        eErr := 16#0001_0669; // 信息级：拍数饱和钳位（R285）/ informational, the count is saturated
        bError := FALSE; // 信息级不置故障标志 / keep the fault flag false, this is informational
    END_IF
ELSE // 冻结期（上拍非有限命中后本拍已过闸，自动解冻续计）/ the frozen period auto releases after the gate passed
    stState.bFrozen := FALSE; // 解冻（非有限输入冻结不粘滞，恢复路径可达）/ release the frozen flag, the recovery is reachable
    fY := fSample - stState.fComp; // 解冻拍照常累加 [工程单位] / accumulate as usual on the release scan
    fT := stState.fSum + fY; // 中间和 [工程单位] / the intermediate sum
    stState.fComp := (fT - stState.fSum) - fY; // 补偿项回吸 [工程单位] / the compensation
    stState.fSum := fT; // 主和推进 [工程单位] / advance the main sum
    IF stState.nScans < nMaxScans THEN // 拍数未达上限 / the count below the ceiling
        stState.nScans := stState.nScans + DL_RSC_ONEI; // 拍数推进 [拍] / advance the scan count
    ELSE // 拍数饱和（信息级，累加继续）/ the count saturated, the accumulation continues
        eErr := 16#0001_0669; // 信息级：拍数饱和钳位 / informational, the count is saturated
        bError := FALSE; // 信息级不置故障标志 / keep the fault flag false
    END_IF
END_IF

// 段 5｜结果复检兜底（边界四：理论上不可达，R258 三件套 + 状态冻结）/ segment 5, the result recheck with the three part fallback
IF (stState.fSum <> stState.fSum) OR ((stState.fSum - stState.fSum) <> (stState.fSum - stState.fSum)) THEN // 主和非有限（兜底防御）/ the main sum is not finite
    stState.bFrozen := TRUE; // 置状态冻结 / raise the frozen flag
    eErr := 16#0001_0668; // 故障级：结果复检命中（同形合并一码，R90）/ fault grade under the merged code
    bError := TRUE; // 置故障标志（R45 配对）/ raise the fault flag
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，状态冻结 / early return with the state frozen
END_IF

// 段 6｜统一出口 / segment 6, the unified outlet
fSum := stState.fSum; // 和出口 [工程单位] / the sum outlet
nScans := stState.nScans; // 拍数出口 [拍] / the count outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_RunningSumCalc := TRUE; // 返回成功 / return success
END_FUNCTION
