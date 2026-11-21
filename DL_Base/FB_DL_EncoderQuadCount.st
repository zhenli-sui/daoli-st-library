(*
  ==================================================================
  组件名 Component  : FB_DL_EncoderQuadCount
  分类   Category   : DL_Base
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.1
  功能   Purpose    : 正交 A/B 两相四倍频加减计数。按格雷序四态状态机解码相位
                      跳变方向；A/B 同拍跳变（非法 00↔11 或 01↔10）按状态保持
                      并按 2 步口径累计丢步；计数饱和 ±DL_ENC_QUAD_MAX 口径不回
                      绕；方向出口与计数出口分离。
  来源   Source     : iec-std-wrapper（T0）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；正交解码格雷序四态
                      状态机为公开编码器语义，clean-room 自研实现，未复制任何
                      厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（无私有库、无定时器实例、无 MOD 于计数路径）
  分工声明 Split     : 与 FB_DL_HistogramAccum / FB_DL_EventRateCalc 分工——本件
                      只做正交相位解码与四倍频计数，不做速率换算与统计分箱。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 首扫经 _bFirst 豁免一拍步进判定（v1.0.1）：首拍只锁存
                         格雷态，不产生任何计数与方向（消除上电停在非 00 态时
                         用陈旧 _eGrayPv 判转移的首拍假步进）；
                      二 非法跳变（对角跳 00↔11 / 01↔10）状态保持、计数不动、
                         丢步按 2 步口径累计（v1.0.1 A 案：一个对角跳变实际
                         丢失 2 个四分之一周期步，计数单位 [步]）；
                      三 计数饱和 ±DL_ENC_QUAD_MAX，饱和侧锁存指示，不回绕；
                      四 方向出口只随最近一次有效步进更新，非法跳变不改方向；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 1 · 序号 3）
    2026-11-21  v1.0.1  R58 返修两项：①段 1 的 _bInit 预置 _eGrayNow 为死代码
                        （当拍即被段 3 重锁存覆盖），改置 _bFirst 豁免首拍步进
                        判定；②丢步判式口径二选一：全库检索无手册引用，选 A
                        案代码改——对角非法跳变按丢失 2 步累计（四分支 + 兜底
                        分支同口径），计数单位 [步]，头注释边界二同步改写。
  ==================================================================
*)

TYPE E_DL_EncGray :
(
    eQ0 := 0, // 格雷态 0：A=0 / B=0（AB 编码 00）/ gray state zero, A low and B low
    eQ1 := 1, // 格雷态 1：A=0 / B=1（AB 编码 01）/ gray state one, A low and B high
    eQ3 := 3, // 格雷态 3：A=1 / B=1（AB 编码 11）/ gray state three, A high and B high
    eQ2 := 2  // 格雷态 2：A=1 / B=0（AB 编码 10）/ gray state two, A high and B low
);
END_TYPE

FUNCTION_BLOCK FB_DL_EncoderQuadCount
VAR_INPUT
    bPhaseA  : BOOL := FALSE;       // 正交 A 相输入 [-] / the quadrature phase A input
    bPhaseB  : BOOL := FALSE;       // 正交 B 相输入 [-] / the quadrature phase B input
    bEnable  : BOOL := TRUE;        // 使能，失能冻结计数 [-] / enable, disabling freezes the count
    bReset   : BOOL := FALSE;       // 复位上升沿清计数与丢步 [-] / reset rising edge clears the count and missed steps
END_VAR
VAR_OUTPUT
    nQuadCount : DINT := 0;   // 四倍频计数出口（饱和 ±上限，不回绕）[步] / the quadrature count outlet, saturated, no wrap [step]
    bDirPos    : BOOL := FALSE; // 方向出口，TRUE = 最近有效步进为正向 [-] / the direction outlet, true for the latest valid forward step
    bSatHi     : BOOL := FALSE; // 正向饱和锁存指示 [-] / the forward saturation latch indicator
    bSatLo     : BOOL := FALSE; // 反向饱和锁存指示 [-] / the reverse saturation latch indicator
    nMissCnt   : UDINT := 0;    // 非法跳变丢步累计（对角跳变按 2 步计，v1.0.1 A 案）[步] / the illegal transition missed count in steps, a diagonal counts two
    bError     : BOOL := FALSE; // 故障标志（保留位，本件无锁存故障）[-] / the fault flag, reserved, no latched fault
END_VAR
VAR
    rtReset   : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    _eGrayPv  : E_DL_EncGray := E_DL_EncGray.eQ0; // 上拍格雷态 / the previous gray state
    _eGrayNow : E_DL_EncGray := E_DL_EncGray.eQ0; // 当拍格雷态 / the current gray state
    _bInit    : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan flag
    _bFirst   : BOOL := FALSE; // 首拍跳过步进判定标记（v1.0.1 豁免一拍）/ the first scan skip flag, exempts one scan
    _nStep    : DINT := 0;     // 本拍步进量（+1、-1、0 三值）[步] / the step amount this scan [step]
    _nMissAdd : DINT := 0;     // 本拍丢步累加量，对角跳变按 2 [步] / the miss addition this scan, a diagonal counts two [step]
END_VAR
VAR CONSTANT
    DL_ENC_QUAD_MAX : DINT := 2147483600; // 四倍频计数饱和上限 [步]，留 47 步余量防 ±1 回绕 / the saturation bound [step], a margin against a plus or minus one wrap
    DL_ENC_MISS_MAX : UDINT := 4294967293; // 丢步计数钳定界 [步]，留 2 步余量防累加回绕 / the missed count clamp [step], a two step margin against a wrap
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首扫初始化（R310）：置 _bFirst 豁免一拍，零计数零方向（v1.0.1）/ segment 1, the first scan raises the exemption flag
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit  := TRUE; // 置首扫标志 / raise the first scan flag
    _bFirst := TRUE; // 首拍豁免步进判定（上电停在非 00 态不用陈旧 _eGrayPv 判转移）/ exempt the first scan from the step verdict
END_IF

// 段 2｜复位沿作用域：清计数 / 清方向 / 清饱和与丢步（四项逐项声明）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    nQuadCount := 0; // 作用域一：清计数 / scope one, clear the count
    bDirPos := FALSE; // 作用域二：清方向 / scope two, clear the direction
    bSatHi := FALSE; // 作用域三：清正向饱和 / scope three, clear the forward saturation
    bSatLo := FALSE; // 作用域三：清反向饱和 / scope three, clear the reverse saturation
    nMissCnt := 0; // 作用域四：清丢步计数 / scope four, clear the missed counter
END_IF

// 段 3｜当拍格雷态解码（A 低位 B 高位，纯布尔组合，无 MOD 无移位）/ segment 3, the gray decode, pure boolean composition
_eGrayNow := E_DL_EncGray.eQ0; // 默认态 00 / the default state
IF bPhaseA AND (NOT bPhaseB) THEN _eGrayNow := E_DL_EncGray.eQ2; END_IF // 编码 10 / the encoding ten
IF (NOT bPhaseA) AND bPhaseB THEN _eGrayNow := E_DL_EncGray.eQ1; END_IF // 编码 01 / the encoding one
IF bPhaseA AND bPhaseB THEN _eGrayNow := E_DL_EncGray.eQ3; END_IF // 编码 11 / the encoding eleven

// 段 4｜步进与丢步判定：格雷序状态机 CASE，非法跳变保持丢步（边界二）/ segment 4, the step and miss verdict
_nStep    := 0; // 步进量预置零 / preset the step to zero
_nMissAdd := 0; // 丢步累加量预置零 / preset the miss addition to zero
IF bEnable AND (NOT _bFirst) AND (_eGrayNow <> _eGrayPv) THEN // 使能且非首拍且格雷态变化（v1.0.1 豁免闸）/ enabled, not the first scan, and the gray state changed
    CASE _eGrayPv OF // 以上拍态为基准查转移表 / the transition table keyed by the previous state

    E_DL_EncGray.eQ0: // 上拍 00 / the previous state zero
        IF _eGrayNow = E_DL_EncGray.eQ1 THEN // 00→01 正向四分之一周期 / a forward quarter cycle
            _nStep := 1; // 正向步进 / a forward step
        ELSIF _eGrayNow = E_DL_EncGray.eQ2 THEN // 00→10 反向四分之一周期 / a reverse quarter cycle
            _nStep := -1; // 反向步进 / a reverse step
        ELSE // 00→11 对角非法跳变 / the diagonal illegal transition
            _nMissAdd := 2; // 对角跳变按丢失 2 步计（v1.0.1 A 案）/ a diagonal transition counts as two lost steps
        END_IF

    E_DL_EncGray.eQ1: // 上拍 01 / the previous state one
        IF _eGrayNow = E_DL_EncGray.eQ3 THEN // 01→11 正向 / a forward transition
            _nStep := 1; // 正向步进 / a forward step
        ELSIF _eGrayNow = E_DL_EncGray.eQ0 THEN // 01→00 反向 / a reverse transition
            _nStep := -1; // 反向步进 / a reverse step
        ELSE // 01→10 对角非法 / the diagonal illegal transition
            _nMissAdd := 2; // 对角跳变按丢失 2 步计（v1.0.1 A 案）/ a diagonal transition counts as two lost steps
        END_IF

    E_DL_EncGray.eQ3: // 上拍 11 / the previous state three
        IF _eGrayNow = E_DL_EncGray.eQ2 THEN // 11→10 正向 / a forward transition
            _nStep := 1; // 正向步进 / a forward step
        ELSIF _eGrayNow = E_DL_EncGray.eQ1 THEN // 11→01 反向 / a reverse transition
            _nStep := -1; // 反向步进 / a reverse step
        ELSE // 11→00 对角非法 / the diagonal illegal transition
            _nMissAdd := 2; // 对角跳变按丢失 2 步计（v1.0.1 A 案）/ a diagonal transition counts as two lost steps
        END_IF

    E_DL_EncGray.eQ2: // 上拍 10 / the previous state two
        IF _eGrayNow = E_DL_EncGray.eQ0 THEN // 10→00 正向 / a forward transition
            _nStep := 1; // 正向步进 / a forward step
        ELSIF _eGrayNow = E_DL_EncGray.eQ3 THEN // 10→11 反向 / a reverse transition
            _nStep := -1; // 反向步进 / a reverse step
        ELSE // 10→01 对角非法 / the diagonal illegal transition
            _nMissAdd := 2; // 对角跳变按丢失 2 步计（v1.0.1 A 案）/ a diagonal transition counts as two lost steps
        END_IF

    ELSE // 非法格雷态兜底（R128，实际不可达：_eGrayPv 只取自段 3 四态解码）/ the illegal gray fallback, unreachable since the snapshot only takes the four decoded states
        _nMissAdd := 2; // 兜底与对角跳变同口径按 2 步计（v1.0.1）/ the fallback aligns with the diagonal two step convention
    END_CASE
END_IF
_bFirst := FALSE; // 首拍标记仅豁免一拍（v1.0.1，段 4 之后段 5 之前清除）/ the first scan flag exempts only one scan, cleared after segment four

// 段 5｜饱和计数写入点唯一（净额单点施加，R47）/ segment 5, the single count write point with saturation
IF _nStep > 0 THEN // 正向步进 / a forward step
    IF nQuadCount >= DL_ENC_QUAD_MAX THEN // 已在正向饱和界 / already at the forward bound
        bSatHi := TRUE; // 锁存饱和指示 / latch the saturation indicator
    ELSE // 未饱和 / not saturated
        nQuadCount := nQuadCount + 1; // 计数 +1 / count up
        bDirPos := TRUE; // 方向出口置正 / the direction outlet positive
    END_IF
ELSIF _nStep < 0 THEN // 反向步进 / a reverse step
    IF nQuadCount <= -DL_ENC_QUAD_MAX THEN // 已在反向饱和界 / already at the reverse bound
        bSatLo := TRUE; // 锁存饱和指示 / latch the saturation indicator
    ELSE // 未饱和 / not saturated
        nQuadCount := nQuadCount - 1; // 计数 -1 / count down
        bDirPos := FALSE; // 方向出口置负 / the direction outlet negative
    END_IF
END_IF
IF _nMissAdd > 0 THEN // 非法跳变丢步（状态保持、计数不动、方向不改，边界二四）/ an illegal transition, the state held, the count untouched, the direction unchanged
    nMissCnt := nMissCnt + DINT_TO_UDINT(_nMissAdd); // 丢步累计按步口径推进（v1.0.1 A 案）/ advance the missed count in steps
    IF nMissCnt > DL_ENC_MISS_MAX THEN // UDINT 上界防回绕（钳定界留 2 步累加余量）/ the wrap guard clamped with a two step margin
        nMissCnt := DL_ENC_MISS_MAX; // 钳在安全界 / clamp below the ceiling
    END_IF
END_IF

// 段 6｜格雷态快照推进（无条件，失能拍也推进防恢复假跳变）/ segment 6, the gray snapshot advances unconditionally
_eGrayPv := _eGrayNow; // 快照推进 / advance the snapshot
END_FUNCTION_BLOCK
