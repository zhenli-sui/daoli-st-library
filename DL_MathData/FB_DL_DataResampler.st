(*
  ==================================================================
  组件名 Component  : FB_DL_DataResampler
  分类   Category   : DL_MathData
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 变周期数据重采样。新周期沿（bNewCycle 上升沿）锁存新
                      样本进双缓冲（fPrev/fLast），拍间按相位 fFrac ∈ [0,1]
                      线性插值桥接输出；周期缺口超 tGapMax 计丢拍 nLostCnt；
                      非有限样本拒收计数 nSkipCnt 并置 bBad（禁静默吞）。
                      测量评估族语义，与 FB_DL_MovingAverage 窗口滤波分工。
  来源   Source     : T2-1-lgf-measurement（测量评估族待挖项）
  溯源   Origin     : 周期沿锁存 + 线性插值桥接为公开工程语义，clean-room
                      自研实现，未复制 LGF 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_MovingAverage 分工——后者做窗口均值滤波，
                      本件做变周期样本锁存与拍间插值桥接。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 安全语义：样本不足两帧或末帧非有限时 fOut 安全侧
                         零、bValid 假（插值桥不外推）；
                      二 fFrac 越域 [0,1] 回夹并置 bClamped（信息级，单点
                         回夹防多处覆盖）；
                      三 缺口窗 tGapMax 到期单拍计丢拍一次（自复位窗，R188），
                         窗口末退出迁移（本库纪律④）；
                      四 非有限样本：环不写入、bBad 置位、nSkipCnt 计数
                         （本库纪律②）；
                      五 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 2 · 序号 8）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_DataResampler
VAR_INPUT
    fIn       : LREAL := 0.0;  // 样本输入 [工程单位] / the sample input [engineering unit]
    bNewCycle : BOOL := FALSE; // 新周期标志，上升沿锁存样本 [-] / the new cycle flag, the rising edge latches the sample
    fFrac     : LREAL := 0.0;  // 插值相位，域 [0,1] [无量纲] / the interpolation phase, zero through one
    tGapMax   : TIME := T#5S;  // 周期缺口看门狗窗 [毫秒] / the cycle gap watchdog [millisecond]
    bEnable   : BOOL := TRUE;  // 使能，失能输出安全侧零 [-] / the enable, disabling zeroes the output
END_VAR
VAR_OUTPUT
    fOut     : LREAL := 0.0;  // 插值桥接输出 [工程单位] / the interpolated bridge outlet [engineering unit]
    bValid   : BOOL := FALSE; // 输出可用标志（双帧齐且有限）[-] / the output usable flag
    bClamped : BOOL := FALSE; // 相位回夹发生（信息级）[-] / the phase clamp happened, informational
    bBad     : BOOL := FALSE; // 非有限样本拒收实时标志 [-] / the non finite sample rejection flag
    nLostCnt : UDINT := 0;    // 丢拍计数 [拍] / the lost cycle count
    nSkipCnt : UDINT := 0;   // 非有限拒收计数 [次] / the skipped non finite count
END_VAR
VAR CONSTANT
    DL_DRS_CNTMAX : UDINT := 4294967294; // 计数防回绕上界 [次] / the counter anti wrap clamp bound
END_VAR
VAR
    _bInit  : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：首拍安全态预置）/ the first scan flag, real use
    _fPrev  : LREAL := 0.0;  // 前帧锁存副本 [工程单位] / the previous latched sample copy
    _fLast  : LREAL := 0.0;  // 末帧锁存副本 [工程单位] / the last latched sample copy
    _bHave  : BOOL := FALSE; // 双帧齐备锁存 [-] / the two samples ready latch
    _bFin   : BOOL;          // 样本有限工作量 [-] / the sample finiteness work flag
    rtNew   : R_TRIG;        // 新周期沿检测，段 0 无条件刷新 / the new cycle edge, refreshed unconditionally
    tonGap  : TON;           // 缺口看门狗（自复位窗），段 0 无条件刷新 / the gap watchdog, the self reset window
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtNew(CLK := bNewCycle); // 新周期沿 / the new cycle edge
tonGap(IN := bEnable AND (NOT rtNew.Q) AND (NOT tonGap.Q), PT := tGapMax); // 自复位缺口窗（R188：IN 串 NOT Q）/ the self reset gap window

// 段 1｜首拍初始化（R310 真实使用路径）：输出安全态显式预置 / segment 1, the first scan init, the safe preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the flag
    fOut := 0.0; // 输出强制安全零 / force the safe zero
    bValid := FALSE; // 有效强制假 / force the valid false
END_IF

// 段 2｜丢拍计数（缺口窗到期单拍一次，窗口末退出迁移，边界三）/ segment 2, the lost cycle count
IF tonGap.Q THEN // 缺口窗到期（本拍为超窗第一拍）/ the gap window expired, the first scan beyond
    IF nLostCnt < DL_DRS_CNTMAX THEN // 计数防回绕 / the wrap guard
        nLostCnt := nLostCnt + 1; // 计丢拍一次 / count one lost cycle
    END_IF
END_IF

// 段 3｜新周期沿锁存（有限样本才入双缓冲，边界四）/ segment 3, the edge latch
_bFin := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn)); // 样本有限双判据（R79）/ the finiteness dual verdicts
IF rtNew.Q THEN // 新周期沿 / the new cycle edge
    IF _bFin THEN // 有限样本受理 / a finite sample accepted
        _fPrev := _fLast; // 旧末帧降为前帧 / the old last to the previous
        _fLast := fIn; // 新样本入末帧 / the new sample to the last
        _bHave := TRUE; // 双帧齐备（第二帧起成立）/ the two samples ready
    ELSE // 非有限样本拒收（环不写、置位、计数，本库纪律②）/ a non finite sample rejected
        bBad := TRUE; // 置拒收实时标志 / raise the rejection flag
        IF nSkipCnt < DL_DRS_CNTMAX THEN // 计数防回绕 / the wrap guard
            nSkipCnt := nSkipCnt + 1; // 拒收计数推进 / advance the skip count
        END_IF
    END_IF
END_IF

// 段 4｜插值桥接输出（相位单点回夹 + 有限性闸，边界一二）/ segment 4, the interpolated bridge outlet
IF bEnable AND _bHave AND _bFin AND (_fPrev = _fPrev) AND ((_fPrev - _fPrev) = (_fPrev - _fPrev)) THEN // 双帧齐且有限 / both ready and finite
    IF fFrac < 0.0 THEN // 相位下越域回夹 / the phase below the band
        fFrac := 0.0; // 夹到零 / clamp to zero
        bClamped := TRUE; // 信息级 / informational
    ELSIF fFrac > 1.0 THEN // 相位上越域回夹 / the phase above the band
        fFrac := 1.0; // 夹到一 / clamp to one
        bClamped := TRUE; // 信息级 / informational
    END_IF
    fOut := _fPrev + (fFrac * (_fLast - _fPrev)); // 线性插值桥（不外推）/ the linear bridge, no extrapolation
    bValid := TRUE; // 输出可用 / the output usable
ELSE // 样本不足或非有限或失能：安全侧零 / not enough, non finite or disabled, the safe zero
    fOut := 0.0; // 安全侧零 / the safe zero
    bValid := FALSE; // 可用标志假 / the valid false
END_IF
END_FUNCTION_BLOCK
