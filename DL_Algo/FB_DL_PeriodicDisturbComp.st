(*
  ==================================================================
  组件名 Component  : FB_DL_PeriodicDisturbComp
  分类   Category   : DL_Algo
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.1
  功能   Purpose    : 周期性扰动重复控制补偿器。内模原理：环形延迟线按周期
                      拍数存储上周期同相位误差，泄漏积分（遗忘因子）逐拍正
                      反馈累加，收敛增益钳位后取负作为前馈补偿输出。适用轧
                      辊偏心 / 卷筒周期张力等固定周期扰动。与 DisturbanceObserver
                      非周期观测分工互引。
  来源   Source     : self（控制理论公开：重复控制 / 内模原理）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；重复控制内模为
                      公开控制理论语义，clean-room 自研实现，未复制任何厂商
                      私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FB_DL_DisturbanceObserver 分工——后者做非周期扰动
                      状态观测，本件做固定周期扰动的内模累积补偿；本件只
                      输出补偿量，不做误差观测器极点配置。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态域：nPeriodTicks ∈ [2..4096]（拍），fForget ∈
                         [0..0.999]（无量纲，取 1.0 会无界累积故禁用），
                         fGain ∈ [0..1.0]（无量纲）；越域锁存（解除 = bReset
                         沿，R188），锁存与失能期补偿输出安全侧零；
                      二 每次调用 = 一拍：先读后写（读上周期同相位存量，
                         写本拍泄漏积分），拍推进仅在使能且域内；
                      三 非有限误差拒收（自反双判据）：本拍环不写入、输出
                         冻结保持，拒收计数出口 nSkipCnt 供调用方可观测；
                      四 环容量固定 4096，周期组态改变时写指针按新周期回
                         绕（MOD 式比较回绕，无移位无溢出）；
                      五 无全局变量、无外部变量声明、无物理地址寻址；
                      六 维护纪律（R59 轻①）：环块双清须同步维护——凡清环块
                         _aRing 必须同时清写指针 _uWidx，首扫段与复位段两处
                         双清块增删必须同步对齐，禁止只清其一。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 3 · 序号 10）
    2026-11-21  v1.0.1  R59 返修轻①②：头注释补环块双清同步维护纪律（边界六）；常量 DL_PDC_SKIPMAX 名实不符
                        改名 DL_PDC_CNTMAX（计数防回绕上界，覆盖 _nTick 与 nSkipCnt 两处钳定用法）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_PeriodicDisturbComp
VAR_INPUT
    fErr        : LREAL := 0.0;   // 误差反馈输入 [工程单位] / the error feedback input [engineering unit]
    nPeriodTicks: UINT  := 100;   // 扰动周期拍数 [拍]，域 2..4096 / the disturbance period in ticks, two through four thousand ninety six
    fForget     : LREAL := 0.95;  // 遗忘因子 [无量纲]，域 0..0.999 / the forgetting factor, zero through point nine nine nine
    fGain       : LREAL := 0.5;   // 收敛增益 [无量纲]，域 0..1.0 / the convergence gain, zero through one
    bEnable     : BOOL  := FALSE; // 使能，失能输出安全侧零且环冻结 [-] / enable, disabling zeroes the output and freezes the ring
    bReset      : BOOL  := FALSE; // 复位上升沿清环与锁存 [-] / reset rising edge clears the ring and the latch
END_VAR
VAR_OUTPUT
    fComp   : LREAL := 0.0; // 补偿输出（前馈，取负反馈）[工程单位] / the compensation outlet, the negative feedforward [engineering unit]
    bLearned: BOOL := FALSE; // 环已填满一周期指示 [-] / the ring filled one period indicator
    nSkipCnt: UDINT := 0;   // 非有限拒收拍计数 [拍] / the skipped non finite tick count
    bError  : BOOL := FALSE; // 域闸故障锁存标志 [-] / the domain gate fault latch flag
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    _aRing  : ARRAY[0..4095] OF LREAL; // 环形延迟线 [工程单位] / the ring delay line [engineering unit]
    _uWidx  : UINT := 0;   // 环写指针 [槽] / the ring write index [slot]
    _nTick  : UDINT := 0;  // 使能以来累计拍数 [拍]（填满判定）/ the ticks since enabled [tick]
    _bLatch : BOOL := FALSE; // 域闸锁存位 [-] / the domain gate latch bit
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _nPer   : DINT;        // 周期拍数 DINT 工作副本 [拍] / the period as a DINT work copy [tick]
    _bFin   : BOOL;        // 误差有限工作量 [-] / the error finiteness work flag
    _nI     : DINT;        // 清环遍历索引 [槽] / the ring clear loop index
END_VAR
VAR CONSTANT
    DL_PDC_PERMAX : UINT := 4096;  // 周期拍数上界 [拍]，与环容量一致 / the period bound, aligned with the ring capacity
    DL_PDC_FGTMAX : LREAL := 0.999; // 遗忘因子上界 [无量纲] / the forgetting ceiling
    DL_PDC_CNTMAX : UDINT := 4294967294; // 计数防回绕上界 [拍]（R59 轻②：由 SKIPMAX 改名，名实对齐）/ the counter anti wrap clamp bound
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首扫初始化（R310）：环清零与指针复位（与复位沿同款块）/ segment 1, the first scan init, the same block as the reset edge
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
    FOR _nI := 0 TO 4095 DO // 固定界清环 / the fixed bound ring clear
        _aRing[_nI] := 0.0; // 槽清零 / clear the slot
    END_FOR
    _uWidx := 0; // 指针复位 / reset the index
    _nTick := 0; // 拍计数复位 / reset the tick count
END_IF

// 段 2｜复位沿作用域：清环 / 清指针与计数 / 清锁存（三项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    FOR _nI := 0 TO 4095 DO // 作用域一：固定界清环 / scope one, the fixed bound ring clear
        _aRing[_nI] := 0.0; // 槽清零 / clear the slot
    END_FOR
    _uWidx := 0; // 作用域二：清写指针 / scope two, clear the write index
    _nTick := 0; // 作用域二：清累计拍 / scope two, clear the tick count
    nSkipCnt := 0; // 作用域二：清拒收计数 / scope two, clear the skip count
    _bLatch := FALSE; // 作用域三：清域闸锁存（解除路径 = bReset 沿，R188）/ scope three, clear the latch
END_IF

// 段 3｜组态域闸（边界一）/ segment 3, the config gate
_nPer := UINT_TO_DINT(nPeriodTicks); // 升宽工作副本 / the widened work copy
IF (nPeriodTicks < 2) OR (nPeriodTicks > DL_PDC_PERMAX) // 周期域 / the period domain
OR (fForget < 0.0) OR (fForget > DL_PDC_FGTMAX) // 遗忘因子域（禁 1.0 无界累积）/ the forgetting domain
OR (fGain < 0.0) OR (fGain > 1.0) // 收敛增益域 / the gain domain
OR (fForget <> fForget) OR ((fForget - fForget) <> (fForget - fForget)) // 遗忘因子非有限 / a non finite forgetting
OR (fGain <> fGain) OR ((fGain - fGain) <> (fGain - fGain)) THEN // 增益非有限 / a non finite gain
    IF NOT _bLatch THEN // 未锁存才置位 / latch only while unlatched
        _bLatch := TRUE; // 置域闸锁存 / raise the latch
    END_IF
END_IF
bError := _bLatch; // 故障标志与锁存位同源（R191 名实双出口）/ the flag shares the latch

// 段 4｜内模逐拍正反馈累加（先读后写，边界二）/ segment 4, the internal model per tick, read then write
_bFin := (fErr = fErr) AND ((fErr - fErr) = (fErr - fErr)); // 误差有限双判据（R79）/ the error finiteness dual verdicts
IF bEnable AND (NOT _bLatch) AND _bFin THEN // 使能且域内且样本有限 / enabled, inside the domain, and finite
    fComp := -fGain * _aRing[_uWidx]; // 读上周期同相位存量取负前馈（写指针槽界已证 0..4095）/ the negative feedforward of the stored same phase error
    _aRing[_uWidx] := fErr + fForget * _aRing[_uWidx]; // 写本拍泄漏积分 / write the leaked integration
    _uWidx := _uWidx + 1; // 拍推进 / advance the tick
    IF UINT_TO_DINT(_uWidx) >= _nPer THEN // 按新周期回绕（比较式回绕，无 MOD 无移位）/ wrap by the period comparison
        _uWidx := 0; // 回绕到零 / wrap to zero
    END_IF
    IF _nTick < DL_PDC_CNTMAX THEN // 累计拍防回绕 / the tick wrap guard
        _nTick := _nTick + 1; // 累计推进 / advance the count
    END_IF
    bLearned := (_nTick >= DINT_TO_UDINT(_nPer)); // 环已填满一周期判定（标准转换函数）/ the filled verdict with a standard conversion
ELSIF (NOT _bFin) AND (NOT _bLatch) AND bEnable THEN // 非有限拒收拍（边界三）：环不写输出冻结 / a non finite tick, the ring untouched, the output frozen
    IF nSkipCnt < DL_PDC_CNTMAX THEN // 拒收计数防回绕 / the skip wrap guard
        nSkipCnt := nSkipCnt + 1; // 拒收计数推进 / advance the skip count
    END_IF
ELSE // 失能或域闸锁存：输出安全侧零（边界一）/ disabled or latched, the output safe zero
    fComp := 0.0; // 安全侧零 / the safe zero
    bLearned := FALSE; // 填满指示随失能清除 / the indicator cleared
END_IF
END_FUNCTION_BLOCK
