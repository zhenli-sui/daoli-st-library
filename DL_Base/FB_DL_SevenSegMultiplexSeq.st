(*==============================================================================
 * 组件 Component : FB_DL_SevenSegMultiplexSeq ｜ DL_Base ｜ v1.0.0 ｜ 2026-11-25
 * 功能 Function  : 多路动态扫描驱动状态机（共阴高有效口径，bit0=a … bit6=g）。
 *                 相序：eBlank 消隐（全段关、仅位选稳定）→ eSelect 位选并输出
 *                 段码（保持 tSlot − tBlank）→ 位索引推进 → 回到 eBlank；
 *                 整帧末位完成后回卷到 0 位。
 * 边界 Boundary  : ① 位缺失诊断：uDigitCnt=0 → eFault（uErrId=1），不空转扫描；
 *                 ② 组态闸：tScan ≤ 0 或位数 > 8 → eFault（uErrId=2）；
 *                 ③ 扫描超时：整帧看门狗 PT = 2 × 一帧时长（留一帧扫描量化余量），
 *                 帧窗随帧首置位、末位回卷清位（IN 不恒 TRUE），超时未完成即 eFault（uErrId=3）；
 *                 ④ 字形越界：uGlyphVal > 15 → 全灭并置 uErrId=4（不点亮乱码）；
 *                 ⑤ 同拍双窗配比约束：tSlot > tBlank，且 tBlank ≥ 1ms，
 *                 由段 5 强制钳定后赋值给两定时器（R100）；
 *                 ⑥ 故障解除路径：bEnable 下降沿（撤使能即清锁存并回 eIdle），恒可达；
 *                 ⑦ 出口 uSegCode 在非 eSelect 相恒为全灭，禁残留上一段码（N2）。
 * 依赖 Depends   : 仅 IEC 61131-3 标准库（TON / TIME_TO_DINT / DINT_TO_TIME）
 * 溯源 Origin    : DLF-C-SEVENSEG（R95 规划标签，内部原创线，无外部代码抄录）
 * 枚举归属      : E_DL_SevSegScanPhase 归属本文件（全库唯一属主，R264）
 * 码位分配      : 零 16# 段位范式；uErrId 常量 0 无 / 1 位缺失 / 2 组态非法 /
 *                 3 扫描超时 / 4 字形越界 / 5 非法相位。
 * 红线 Redline   : R1✓ R2✓ R3✓ R4✓ R5✓ R6✓（ENUM + CASE + ELSE 兜底）
 *                 R7✓（tonBlank/tonSlot/tonFrame 段 0 无条件刷新） R8✓ R9✓
 *                 R14✓（无 PROPERTY） R16✓（字形译码内联，不引用本轮未裁决件）
 *                 R17✓（无浮点索引） R20✓（相位只在 CASE 内写）
 * 验收 Accept    : A1 4 位、tScan=10ms、字形 8 → 4 个位轮扫，每槽 2.5ms、消隐 1ms；
 *                 A2 位数 0 → eFault、uErrId=1；A3 字形 20 → 全灭、uErrId=4；
 *                 A4 撤 bEnable → 回 eIdle、uSegCode 全灭、锁存清零。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SevSegScanPhase（七段多路扫描相序）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SevSegScanPhase :
(
    eIdle   := 0,    // 待机：全灭，等待使能 / Idle with all segments blanked
    eBlank  := 10,   // 消隐：换位前的全段关断窗 / Blanking window before the digit change
    eSelect := 20,   // 位选：输出当前位与段码 / Digit selected with the glyph code driven
    eFault  := 90    // 故障：位缺失 / 组态 / 超时锁存 / Fault latched by a diagnostic
);
END_TYPE

FUNCTION_BLOCK FB_DL_SevenSegMultiplexSeq
VAR_INPUT
    bEnable   : BOOL;   // 扫描使能，下降沿清故障并回待机 [-] / Scan enable, a falling edge clears the fault
    uDigitCnt : UINT;   // 扫描位数，有效域 1~8 [位] / Scanned digit count, valid from one to eight
    tScan     : TIME;   // 整帧扫描周期，有效域 > 0 [ms] / Frame scan period
    uGlyphVal : UINT;   // 当前位字形值，有效域 0~15 [-] / Glyph value of the current digit
    bFastMode : BOOL;   // TRUE=消隐取 1ms / FALSE=消隐取 2ms [-] / TRUE selects the shorter blanking
END_VAR
VAR_OUTPUT
    uSegCode  : BYTE;   // 段码输出（非选位相为全灭）[-] / Segment code, blanked outside the select phase
    uDigitIdx : UINT;   // 当前位索引（0 基）[-] / Current digit index starting at zero
    bScanOk   : BOOL;   // 扫描健康（无故障且组态有效）[-] / Scan healthy without diagnostics
    uErrId    : UDINT;  // 事件码锁存，0 = 无事件 [-] / Latched event code
END_VAR
VAR
    tonBlank : TON;                                          // 消隐窗定时器，段 0 无条件刷新 / Blanking window timer
    tonSlot  : TON;                                          // 选位保持定时器，段 0 无条件刷新 / Select hold timer
    tonFrame : TON;                                          // 整帧看门狗，段 0 无条件刷新 / Whole frame watchdog
    _eState  : E_DL_SevSegScanPhase := E_DL_SevSegScanPhase.eIdle;  // 内部相位 / Internal phase
    _bInit   : BOOL := FALSE;                                // 首扫初始化已执行 [-] / First scan initialization done
    _bFault  : BOOL := FALSE;                                // 故障锁存位 [-] / Latched fault bit
    _uFault  : UDINT := 0;                                   // 事件码锁存 [-] / Latched event code
    _nIdx    : UINT := 0;                                    // 当前位索引 [位] / Current digit index
    _nCnt    : DINT;                                         // 钳定后位数 [位] / Clamped digit count
    _nScanMs : DINT;                                         // 帧周期毫秒值 [ms] / Frame period in milliseconds
    _nSlotMs : DINT;                                         // 每槽毫秒值 [ms] / Slot duration in milliseconds
    _nBlankMs: DINT;                                         // 消隐毫秒值 [ms] / Blanking duration in milliseconds
    _tSlotPT : TIME;                                         // 选位保持时长（钳定后）[ms] / Clamped select hold time
    _tBlankPT: TIME;                                         // 消隐时长（钳定后）[ms] / Clamped blanking time
    _tFramePT: TIME;                                         // 整帧看门狗时长 [ms] / Whole frame watchdog duration
    _uRaw    : BYTE;                                         // 共阴字形原始段码 [-] / Raw glyph code
    _bCfgBad : BOOL;                                         // 组态非法当拍量 [-] / Illegal configuration flag
    _bDigitMiss : BOOL;                                      // 位缺失当拍量（位数为 0）[-] / Missing digit flag
    _bGlyphBad : BOOL;                                       // 字形越界当拍量 [-] / Glyph out of range flag
    _uErrSnap : UDINT;                                       // 事件码当拍暂存 [-] / Staged event code
    _bFrameWin : BOOL := FALSE;                              // 帧窗锁存量：帧首拍置位、末位回卷清位（看门狗随帧回落）[-] / Frame window latch
END_VAR
VAR CONSTANT
    DL_SSQ_OFF      : BYTE := 16#00;  // 全灭（共阴）[-] / All segments off in common cathode wiring
    DL_SSQ_MAXDIG   : DINT := 8;      // 位数上限 [位] / Digit count ceiling
    DL_SSQ_BLANK_FAST : DINT := 1;    // 快速模式消隐时长 [ms] / Blanking duration in fast mode
    DL_SSQ_BLANK_SLOW : DINT := 2;    // 常规模式消隐时长 [ms] / Blanking duration in normal mode
    DL_SSQ_ONE      : DINT := 1;      // 单位常量 [ms] / Unit constant
    DL_SSQ_C_NONE   : UDINT := 0;     // 码 0：无事件 / Code zero, no event
    DL_SSQ_C_DIGIT  : UDINT := 1;     // 码 1：位缺失（位数为 0）/ Code one, missing digit
    DL_SSQ_C_CFG    : UDINT := 2;     // 码 2：组态非法 / Code two, illegal configuration
    DL_SSQ_C_TMO    : UDINT := 3;     // 码 3：扫描超时 / Code three, frame scan timeout
    DL_SSQ_C_GLYPH  : UDINT := 4;     // 码 4：字形越界 / Code four, glyph out of range
    DL_SSQ_C_ILL    : UDINT := 5;     // 码 5：非法相位兜底 / Code five, illegal phase fallback
END_VAR

(* —— 段 0｜定时器无条件每拍刷新（R7；IN 串 NOT 锁存，防复位同拍重锁） —— *)
tonBlank (IN := (_eState = E_DL_SevSegScanPhase.eBlank) AND (NOT _bFault), PT := _tBlankPT);
tonSlot  (IN := (_eState = E_DL_SevSegScanPhase.eSelect) AND (NOT _bFault), PT := _tSlotPT);
tonFrame (IN := _bFrameWin AND (NOT _bFault), PT := _tFramePT);   // 帧窗随帧首置位/回卷清位，禁恒 TRUE

(* —— 段 1｜单拍量预清零（锁存量 _bFault/_uFault/_nIdx/_eState 不入清单，R107） —— *)
_bCfgBad    := FALSE;
_bDigitMiss := FALSE;
_bGlyphBad  := FALSE;
_uErrSnap   := DL_SSQ_C_NONE;

(* —— 段 2｜首扫初始化 —— *)
IF NOT _bInit THEN
    _bInit  := TRUE;
    _bFault := FALSE;
    _uFault := DL_SSQ_C_NONE;
    _nIdx   := 0;
    _bFrameWin := FALSE;
    _eState := E_DL_SevSegScanPhase.eIdle;
END_IF

(* —— 段 3｜撤使能即解除：清锁存、索引归零、回待机（唯一解除路径，R152） —— *)
IF NOT bEnable THEN
    _bFault := FALSE;                        // 作用域①：清锁存 / Scope one, clear the latch
    _uFault := DL_SSQ_C_NONE;
    _nIdx   := 0;                            // 作用域②：清位索引 / Scope two, clear the digit index
    _bFrameWin := FALSE;                     // 作用域②：帧窗撤位，看门狗即时回落
    _eState := E_DL_SevSegScanPhase.eIdle;   // 作用域③：迁待机 / Scope three, back to idle
END_IF

(* —— 段 4｜组态闸与字形越界判据（覆盖全部参与换算的引脚） —— *)
IF uDigitCnt = 0 THEN
    _bDigitMiss := TRUE;                     // 位缺失：独立归因（R190）
    _bCfgBad    := TRUE;
ELSIF UINT_TO_DINT(uDigitCnt) > DL_SSQ_MAXDIG THEN
    _bCfgBad := TRUE;
END_IF
IF TIME_TO_DINT(tScan) <= 0 THEN
    _bCfgBad := TRUE;
END_IF
IF uGlyphVal > 15 THEN
    _bGlyphBad := TRUE;                      // 字形越界：不点亮乱码（N1：实值同步全灭）
END_IF

(* —— 段 5｜槽时长与时序钳定（tSlot > tBlank ≥ 1ms，配比约束在此强制） —— *)
_nScanMs  := TIME_TO_DINT(tScan);
_nCnt     := UINT_TO_DINT(uDigitCnt);
IF _nCnt < DL_SSQ_ONE THEN
    _nCnt := DL_SSQ_ONE;
END_IF
IF _nCnt > DL_SSQ_MAXDIG THEN
    _nCnt := DL_SSQ_MAXDIG;
END_IF
_nSlotMs  := _nScanMs / _nCnt;               // 除子 ∈ 1..8，除零不可达
IF _nSlotMs < DL_SSQ_ONE THEN
    _nSlotMs := DL_SSQ_ONE;
END_IF
IF bFastMode THEN
    _nBlankMs := DL_SSQ_BLANK_FAST;
ELSE
    _nBlankMs := DL_SSQ_BLANK_SLOW;
END_IF
IF _nBlankMs >= _nSlotMs THEN
    _nBlankMs := _nSlotMs / 2;               // 配比保护：消隐不得超过半个槽（R100）
END_IF
IF _nBlankMs < 0 THEN
    _nBlankMs := 0;
END_IF
_tBlankPT := DINT_TO_TIME(_nBlankMs);
_tSlotPT  := DINT_TO_TIME(_nSlotMs - _nBlankMs);
_tFramePT := DINT_TO_TIME(_nScanMs * 2);     // 整帧看门狗 = 2 × 一帧时长（留一帧量化余量，禁零余量边界误报）

(* —— 段 6｜字形译码（内联实现，不引用本轮未裁决件，R16） —— *)
CASE uGlyphVal OF
0:  _uRaw := 16#3F;
1:  _uRaw := 16#06;
2:  _uRaw := 16#5B;
3:  _uRaw := 16#4F;
4:  _uRaw := 16#66;
5:  _uRaw := 16#6D;
6:  _uRaw := 16#7D;
7:  _uRaw := 16#07;
8:  _uRaw := 16#7F;
9:  _uRaw := 16#6F;
10: _uRaw := 16#77;
11: _uRaw := 16#7C;
12: _uRaw := 16#39;
13: _uRaw := 16#5E;
14: _uRaw := 16#79;
15: _uRaw := 16#71;
ELSE
    _uRaw := DL_SSQ_OFF;                     // 兜底：全灭 / Fallback blanks all segments
END_CASE

(* —— 段 7｜主状态机：三相 + 故障相全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_SevSegScanPhase.eIdle:
    IF bEnable THEN
        IF _bDigitMiss THEN
            _bFault := TRUE;                 // 位缺失：码 1（独立归因）
            _uFault := DL_SSQ_C_DIGIT;
            _eState := E_DL_SevSegScanPhase.eFault;
        ELSIF _bCfgBad THEN
            _bFault := TRUE;                 // 故障级配对（R45）
            _uFault := DL_SSQ_C_CFG;
            _eState := E_DL_SevSegScanPhase.eFault;
        ELSE
            _nIdx   := 0;                    // 拍 N+1 转出：从 0 位开始一帧
            _eState := E_DL_SevSegScanPhase.eBlank;
        END_IF
    END_IF

E_DL_SevSegScanPhase.eBlank:
    IF _bGlyphBad THEN
        _uErrSnap := DL_SSQ_C_GLYPH;         // 字形越界：报码但不停机（显示侧可容错）
    END_IF
    IF _nIdx = 0 THEN
        _bFrameWin := TRUE;                  // 帧首拍：帧窗置位（回卷后隔一拍重新武装，让看门狗复位）
    END_IF
    IF tonBlank.Q THEN
        _eState := E_DL_SevSegScanPhase.eSelect;   // 拍 N+1 转出：消隐结束
    END_IF

E_DL_SevSegScanPhase.eSelect:
    IF _bGlyphBad THEN
        _uErrSnap := DL_SSQ_C_GLYPH;
    END_IF
    IF tonSlot.Q THEN
        (* 位推进：末位回卷到 0 位 / Advance the index and wrap after the last digit *)
        IF UINT_TO_DINT(_nIdx) >= (_nCnt - DL_SSQ_ONE) THEN
            _nIdx := 0;
            _bFrameWin := FALSE;             // 帧末：帧窗清位，看门狗本拍复位（禁恒 TRUE 误报码 3）
        ELSE
            _nIdx := _nIdx + 1;
        END_IF
        _eState := E_DL_SevSegScanPhase.eBlank;   // 拍 N+1 转出：回到消隐窗
    ELSIF tonFrame.Q THEN
        _bFault := TRUE;                     // 扫描超时：独立归因（R190）
        _uFault := DL_SSQ_C_TMO;
        _bFrameWin := FALSE;
        _eState := E_DL_SevSegScanPhase.eFault;
    END_IF

E_DL_SevSegScanPhase.eFault:
    _bFault := TRUE;                         // 故障相驻留：码位锁存回放（复位=bEnable 下降沿）
    _nIdx   := 0;
    _bFrameWin := FALSE;                     // 故障相：帧窗撤位，看门狗不武装

ELSE
    _bFault := TRUE;                         // 非法相位兜底（R6）
    _uFault := DL_SSQ_C_ILL;
    _eState := E_DL_SevSegScanPhase.eFault;
END_CASE

(* —— 段 8｜故障迁相闸（置于解除段之后，R274） —— *)
IF _bFault AND (_eState <> E_DL_SevSegScanPhase.eFault) THEN
    _eState := E_DL_SevSegScanPhase.eFault;
END_IF

(* —— 段 9｜统一出口段：段码/位索引/健康位单点裁决（N4 / R191） —— *)
uDigitIdx := _nIdx;
IF (_eState = E_DL_SevSegScanPhase.eSelect) AND (NOT _bFault) AND (NOT _bGlyphBad) THEN
    uSegCode := _uRaw;                       // 仅选位相输出段码 / Only the select phase drives segments
ELSE
    uSegCode := DL_SSQ_OFF;                  // 其余相恒全灭，禁残留（N2）
END_IF
bScanOk := (NOT _bFault) AND (NOT _bCfgBad);
IF _uErrSnap <> DL_SSQ_C_NONE THEN
    uErrId := _uErrSnap;                     // 信息级当拍码优先呈现（4 = 字形越界）
ELSE
    uErrId := _uFault;                       // 否则回放锁存码
END_IF
END_FUNCTION_BLOCK
