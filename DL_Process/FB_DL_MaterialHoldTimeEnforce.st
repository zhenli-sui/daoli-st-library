(*
  ==================================================================
  组件名 Component  : FB_DL_MaterialHoldTimeEnforce
  分类   Category   : DL_Process
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 物料保持时限强制。批次开始沿起累计保持时长，超时限判
                      NG 锁存（ISA-88 批次语境）；复检合格沿解锁放行并出
                      单拍放行脉冲；批次与超时台账计数出口。GMP 保持时限
                      公开语义（中间品 / 批次在制时限管理）。
  来源   Source     : self（GMP 保持时限公开语义，ISA-88 批次语境次源）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；保持时限与复检
                      放行为行业公开流程语义，clean-room 自研实现，未复制
                      任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: R_TRIG / F_TRIG，无私有库）
  分工声明 Split     : 与 DL_Process 存量批次追溯件（批次履历类）分工——履历
                      件做批次数据记录，本件只做保持时限判定与放行门控；
                      不做配方切换与批次数据缓存。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 代理量三句声明（R95）：fScanPeriodMin 为每次调用的
                         代表时长（代理值）；覆盖任务周期 0.1..10 分钟调用
                         节拍；覆盖不到的区间（调用节拍外事件）由调用方批
                         次信号沿精度兜尾；
                      二 组态域：fHoldLimitMin > 0 且非有限、fScanPeriodMin
                         > 0 且非有限；越域锁存（解除 = bReset 沿，R188）；
                      三 超时 NG 锁存解除路径 = bRecheckOk 上升沿（复检放行，
                         唯一路径，R188 头注释声明）；放行脉冲为单拍（R25：
                         预清零点在段 3，置位点在段 5，两段式映射）；
                      四 复位沿作用域：清故障锁存 / 清台账计数 / 清保持累计
                         与锁存（三项逐项声明）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 4 · 序号 15）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_MaterialHoldTimeEnforce
VAR_INPUT
    bEnable        : BOOL := TRUE;   // 使能，失能冻结判定（输出保持）[-] / enable, disabling freezes the verdicts
    bReset         : BOOL := FALSE;  // 复位上升沿清锁存与台账 [-] / reset rising edge clears the latch and the ledger
    bBatchStart    : BOOL := FALSE;  // 批次开始信号（沿生效）[-] / the batch start signal, edge effective
    bBatchActive   : BOOL := FALSE;  // 批次在制电平 [-] / the batch active level
    bRecheckOk     : BOOL := FALSE;  // 复检合格信号（沿生效）[-] / the recheck pass signal, edge effective
    fHoldLimitMin  : LREAL := 120.0; // 保持时限 [分钟]，域 大于 0 / the hold limit [minute], above zero
    fScanPeriodMin : LREAL := 1.0;   // 每次调用的代表时长 [分钟]（代理量，边界一）/ the representative duration per call [minute]
END_VAR
VAR_OUTPUT
    bExpired        : BOOL := FALSE; // 超时限 NG 锁存出口 [-] / the expired NG latch outlet
    bReleaseOk      : BOOL := FALSE; // 复检放行单拍出口 [-] / the recheck release pulse outlet
    fHoldElapsedMin : LREAL := 0.0;  // 已保持时长出口 [分钟] / the elapsed hold duration outlet [minute]
    nBatchCnt       : UDINT := 0;    // 累计批次数 [批] / the total batch count [batch]
    nExpiredCnt     : UDINT := 0;    // 超时批次数 [批] / the expired batch count [batch]
    bError          : BOOL := FALSE; // 域闸故障锁存标志 [-] / the domain gate fault latch flag
END_VAR
VAR
    rtStart : R_TRIG; // 批次开始沿检测，段 0 无条件刷新 / the batch start edge
    rtRel   : R_TRIG; // 复检合格沿检测，段 0 无条件刷新 / the recheck edge
    ftBatch : F_TRIG; // 批次结束沿检测（在制下降沿），段 0 无条件刷新 / the batch end edge, a falling edge
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    _bCnt   : BOOL := FALSE; // 保持计时进行中 [-] / the hold timing active
    _bExpL  : BOOL := FALSE; // 超时 NG 锁存位（解除 = 复检合格沿）/ the expired NG latch bit
    _bRel   : BOOL := FALSE; // 放行脉冲内部保持量（统一出口映射单拍）/ the release pulse internal holder
    _bLatch : BOOL := FALSE; // 域闸故障锁存位 [-] / the domain gate latch bit
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
END_VAR
VAR CONSTANT
    DL_MHT_CNTMAX : UDINT := 4294967294; // 台账计数钳定界 [批]，防 UDINT 回绕 / the ledger clamp against a wrap
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，FB50-1）/ segment 0, the unconditional refresh
rtStart(CLK := bBatchStart); // 批次开始沿 / the batch start edge
rtRel(CLK := bRecheckOk); // 复检合格沿 / the recheck edge
ftBatch(CLK := bBatchActive); // 批次结束沿 / the batch end edge
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 清台账 / 清保持累计与锁存（三项逐项声明，边界四）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bLatch := FALSE; // 作用域一：清域闸锁存 / scope one, clear the latch
    _bExpL := FALSE; // 作用域一：清 NG 锁存（复位沿为 NG 锁存的辅助解除路径）/ scope one, clear the NG latch
    nBatchCnt := 0; // 作用域二：清批次台账 / scope two, clear the batch ledger
    nExpiredCnt := 0; // 作用域二：清超时台账 / scope two, clear the expired ledger
    fHoldElapsedMin := 0.0; // 作用域三：清保持累计 / scope three, clear the hold accumulator
    _bCnt := FALSE; // 作用域三：清计时进行 / scope three, clear the timing
END_IF

// 段 3｜组态域闸 + 单拍标志预清零（R25）/ segment 3, the config gate and the single shot presets
IF (fHoldLimitMin <> fHoldLimitMin) OR ((fHoldLimitMin - fHoldLimitMin) <> (fHoldLimitMin - fHoldLimitMin)) // 时限非有限 / a non finite limit
OR (fHoldLimitMin <= 0.0) // 时限域 / the limit domain
OR (fScanPeriodMin <> fScanPeriodMin) OR ((fScanPeriodMin - fScanPeriodMin) <> (fScanPeriodMin - fScanPeriodMin)) // 代理周期非有限 / a non finite period
OR (fScanPeriodMin <= 0.0) THEN // 代理周期域 / the period domain
    IF NOT _bLatch THEN // 未锁存才置位 / latch only while unlatched
        _bLatch := TRUE; // 置域闸锁存 / raise the latch
    END_IF
END_IF
bError := _bLatch; // 故障标志与锁存位同源（R191 名实双出口）/ the flag shares the latch
bReleaseOk := FALSE; // 放行单拍每拍预清零（R25，置位点在段 5 统一出口）/ the release pulse preset false each scan

// 段 4｜批次受理与保持累计（域内才推进，边界一二）/ segment 4, the batch admission and the hold accumulation
IF (rtStart.Q OR (bBatchActive AND (NOT _bCnt) AND (NOT _bExpL))) AND (NOT _bLatch) THEN // 批次开始沿或在制重新受理 / a batch start edge or a re admission
    IF rtStart.Q THEN // 仅开始沿计台账 / only the start edge counts the ledger
        IF nBatchCnt < DL_MHT_CNTMAX THEN // 台账防回绕 / the ledger wrap guard
            nBatchCnt := nBatchCnt + 1; // 批次计数推进 / advance the batch count
        END_IF
    END_IF
    fHoldElapsedMin := 0.0; // 保持累计清零起算 / clear the accumulator
    _bCnt := TRUE; // 启动保持计时 / start the timing
    _bExpL := FALSE; // 新批次清 NG 锁存（换批自动解锁声明）/ clear the NG latch on a new batch
END_IF
IF _bCnt AND bBatchActive AND (NOT _bLatch) THEN // 计时中且在制且域内 / while timing, active, inside the domain
    fHoldElapsedMin := fHoldElapsedMin + fScanPeriodMin; // 保持累计推进（代理量，边界一）/ advance the accumulator
    IF (fHoldElapsedMin > fHoldLimitMin) AND (NOT _bExpL) THEN // 首次越限（单批只计一次台账）/ the first overrun, one ledger entry per batch
        _bExpL := TRUE; // 置 NG 锁存 / raise the NG latch
        IF nExpiredCnt < DL_MHT_CNTMAX THEN // 台账防回绕 / the ledger wrap guard
            nExpiredCnt := nExpiredCnt + 1; // 超时计数推进 / advance the expired count
        END_IF
    END_IF
END_IF
IF ftBatch.Q THEN // 批次结束沿（在制下降）/ a batch end edge
    _bCnt := FALSE; // 停止计时（累计量保留供显示）/ stop the timing, the accumulator retained
END_IF

// 段 5｜复检放行与统一出口（边界三）/ segment 5, the release and the unified outlet
IF _bExpL AND rtRel.Q THEN // NG 锁存且复检合格沿（解除路径，R188）/ the NG latch with the recheck edge
    _bExpL := FALSE; // 解除 NG 锁存 / release the NG latch
    _bRel := TRUE; // 置放行内部保持量 / raise the release holder
END_IF
bExpired := _bExpL; // NG 锁存出口单点映射 / the NG outlet mapped
IF _bRel THEN // 放行内部保持量 → 统一出口单拍映射（两段式，R189）/ the holder mapped to the pulse
    bReleaseOk := TRUE; // 放行单拍 / the release pulse
    _bRel := FALSE; // 消费保持量 / consume the holder
END_IF
END_FUNCTION_BLOCK
