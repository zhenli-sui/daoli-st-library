(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MedianFilter
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / MIN / MOD），无厂商方言
 * 功能描述 (Function)   : 滑动窗口中值滤波器（窗口 3..15，强制奇数）。
 *                         对孤立脉冲干扰（变频器干扰、接触器拉弧、单次 AD 跳变）
 *                         免疫：窗口内 1 个坏点被整体剔除，而均值滤波会把坏点
 *                         摊到全窗。用于称重、温度、压力、位置反馈的采集前端。
 *                         启动阶段不等装满：输出"已到样本"的中值，保证上电即有
 *                         合理值，避免 PID 把启动期 0 误认为测量值而满输出。
 * 本文件内含       : E_DL_MedianState（枚举，归属本组件）
 *                    FB_DL_MedianFilter（功能块主体）
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 测量评估组的滤波器分类方式
 *                         与 OSCAT Basic 中值函数"排序后取中"的行为定义
 *                         （EPL-2.0）；OSCAT 采用地址指针入参且会原地排序传入
 *                         数组，本块改为内部副本排序、无指针、无副作用，
 *                         clean-room 编写，未复制任何源码）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3，无位访问方言与私有指令
 *                         R4 ✓ 窗口钳位 + 环形取数正数化取模 + 下标双检 + NaN 跳过
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ ENUM + CASE + ELSE 兜底
 *                         R7 N/A（无定时器/边沿实例）
 *
 * 【排序副本披露 / Sorting-copy disclosure（边界 B4）】
 *   排序在副本 afSort 上进行，绝不原地排序环形窗 afWindow——
 *   原地排序会打乱环形时间顺序，后续取"最近 N 个样本"时取到错值。
 *
 * 【环形回退取数 / Ring look-back（边界 B3）】
 *   取最近样本用 (写指针 - 1 - k + 容量×2) 取模：先加两倍容量再取模，
 *   把被减数正数化，规避负数取模的跨平台行为差异。
 *
 * 【偶数窗口 / Even window（边界 B2）】
 *   偶数窗口无唯一中值，强制加 1 变奇数，绝不静默取"中间两个的平均"
 *   ——那会退化成均值，尖峰重新渗入输出。
 *
 * 【选型公式 / Sizing formula（边界 B6）】
 *   中值只剔除孤立尖峰。若干扰持续 ≥ 半个窗口宽度，中值仍会被带偏；
 *   窗口长度应 ≥ 2 × 干扰持续采样数 + 1。
 * 【验收向量 / Acceptance vectors】
 *   V1  窗口 5，序列 10,11,10,100,10 → 装满后 fMedian = 10（100 被剔除；
 *       同序列均值 = 28.2，对比可见中值的抗尖峰价值）
 *   V2  窗口 5，仅采 10,10,10 → nFilled = 3、fMedian = 10、eFilling（上电即有值）
 *   V3  窗口 5，采 1,2,3,4,5 → fMedian = 3
 *   V4  窗口设 4（偶数）→ 生效 5、uErrorId = 16#0001_0001
 *   V5  V3 后窗口改为 3 → 整窗重填（nFilled 归 0 再累）、16#0001_0001
 *   V6  bClear 一拍 → nFilled = 0、bValid = FALSE
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
TYPE E_DL_MedianState :
(
    eEmpty   := 0,    // 未采到任何样本 / No samples yet
    eFilling := 10,   // 窗口未满，输出已到样本的中值 / Filling, median of available samples
    eReady   := 20,   // 窗口已满 / Window full
    eFault   := 99    // 参数非法当拍（已钳位，下拍恢复）/ Parameter event scan, clamped, recovers next scan
);
END_TYPE

FUNCTION_BLOCK FB_DL_MedianFilter
VAR_INPUT
    fIn       : REAL;                      // 采样输入 [EU] / Sample input [EU]
    bSample   : BOOL := TRUE;              // TRUE = 本拍采一个样本（给单周期脉冲即按需采样） / TRUE: take one sample this scan
    nWindow   : INT   := 5;                // 窗口长度，奇数 3..15，偶数自动加 1，越界钳位 / Window length, odd 3..15, even forced odd
    bClear    : BOOL;                      // TRUE：清空窗口重新填充 / TRUE: clear window and refill
END_VAR
VAR_OUTPUT
    fMedian   : REAL;                      // 中值输出 [EU] / Median output [EU]
    nFilled   : INT;                       // 当前有效样本数 [个]，0..窗口长 / Valid sample count, 0..window length
    bValid    : BOOL;                      // 至少有 1 个样本 / At least one sample available
    bWindowFull : BOOL;                    // 窗口已满 / Window full flag
    uErrorId  : UDINT;                     // 故障码，0 = 无故障（本块码均为瞬时，逐拍重算） / Error code, transient, recomputed every scan
    eState    : E_DL_MedianState;          // 当前状态（供诊断） / Current state for diagnostics
END_VAR
VAR
    afWindow  : ARRAY[0..14] OF REAL;      // 环形样本窗 [EU] / Circular sample window [EU]
    afSort    : ARRAY[0..14] OF REAL;      // 排序副本（不破坏原窗时间顺序） / Sorting copy, ring order untouched
    nWrite    : INT;                       // 写指针，值域 0..14 / Write index, range 0..14
    nFilledInt: INT;                       // 有效样本数（内部） / Internal valid sample count
    nWinEff   : INT;                       // 生效窗口（钳位与奇数化后） / Effective odd window after clamping
    nLastWin  : INT;                       // 上拍生效窗口（变更检测，触发整窗重填） / Previous effective window, change forces refill
    nI        : INT;                       // 插入排序外层索引 / Insertion sort outer index
    nJ        : INT;                       // 插入排序内层索引 / Insertion sort inner index
    nK        : INT;                       // 环形取数索引 / Ring fetch index
    nIdx      : INT;                       // 环形取数换算下标 / Resolved ring index
    fTmp      : REAL;                      // 插入排序交换临时量 [EU] / Insertion sort swap temp [EU]
    nGuard    : INT;                       // 排序防死锁计数器 / Sort guard counter
    bParamEvt : BOOL;                      // 本拍发生参数钳位或窗口变更 / Parameter clamp or window change this scan
    bShiftEnd : BOOL;                      // 本轮内层回退结束标志 / Inner shift finished flag
    bGuardTrip: BOOL;                      // 守卫超限标志（本拍） / Guard tripped flag this scan
    eStateInt : E_DL_MedianState;          // 内部状态机当前态 / Internal state machine state
END_VAR
VAR CONSTANT
    DL_MED_WIN_MIN : INT   := 3;          // 最小窗口 / Minimum window
    DL_MED_WIN_MAX : INT   := 15;         // 最大窗口（= 数组维度） / Maximum window, equals the array dimension
    DL_MED_CAP     : INT   := 15;         // 环形容量，必须与数组维度严格一致 / Ring capacity, must match the array
    DL_MED_EPS     : REAL  := 1.0E-6;     // 浮点判零容差 / Float zero tolerance
    DL_MED_INF_LIM : REAL  := 1.0E30;     // 非有限值判据阈值（超此视为 Inf） / Infinity threshold for non-finite detection
    DL_MED_GUARD   : INT   := 225;        // 排序循环防死锁上限（容量平方） / Sort guard limit, capacity squared
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜故障码本周期清零：本块故障码全部为瞬时码，逐拍重算
 *      Error code cleared every scan: all codes are transient
 *-----------------------------------------------------------------------------*)
uErrorId  := 16#0000_0000;
bParamEvt := FALSE;
bGuardTrip:= FALSE;
nGuard    := 0;

(*------------------------------------------------------------------------------
 * 段 2｜窗口规整（边界 B2）：越界钳位、偶数强制奇数，只在本拍置码不刷屏
 *      Window normalization: clamp and force odd, code set only on the event scan
 *-----------------------------------------------------------------------------*)
nWinEff := nWindow;
IF nWinEff < DL_MED_WIN_MIN THEN
    nWinEff  := DL_MED_WIN_MIN;
    bParamEvt := TRUE;
END_IF
IF nWinEff > DL_MED_WIN_MAX THEN
    nWinEff  := DL_MED_WIN_MAX;
    bParamEvt := TRUE;
END_IF
IF (nWinEff MOD 2) = 0 THEN
    nWinEff  := MIN(nWinEff + 1, DL_MED_WIN_MAX);
    bParamEvt := TRUE;
END_IF
IF bParamEvt THEN
    uErrorId := 16#0001_0001;           // 窗口非法已钳位 / Window invalid, clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜窗口变更检测（R14 语义参数变更）：生效窗口与上拍不同 → 整窗作废。
 *      Window change detection: effective window differs, whole window voided
 *      新旧窗口混填的中值无物理意义；重填会有一个窗口长度的空档
 *-----------------------------------------------------------------------------*)
IF nWinEff <> nLastWin THEN
    nFilledInt := 0;
    nWrite     := 0;
    IF nLastWin <> 0 THEN               // 上电首扫不算参数事件 / Power-up first scan is not a parameter event
        uErrorId  := 16#0001_0001;      // 窗口变更触发重填 / Window change forces refill
        bParamEvt := TRUE;
    END_IF
END_IF
nLastWin := nWinEff;

(*------------------------------------------------------------------------------
 * 段 4｜清空：电平触发，先于采样处理
 *      Clear: level-triggered, handled before sampling
 *-----------------------------------------------------------------------------*)
IF bClear THEN
    nFilledInt := 0;
    nWrite     := 0;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜采样（边界：NaN/Inf 跳过不入窗）
 *      Sampling: NaN or Inf samples are skipped, never stored
 *-----------------------------------------------------------------------------*)
IF bSample THEN
    IF (fIn <> fIn) OR (ABS(fIn) > DL_MED_INF_LIM) THEN
        uErrorId := 16#0001_0006;       // 样本非有限值已跳过 / Non-finite sample skipped
    ELSIF (nWrite >= 0) AND (nWrite < DL_MED_CAP) THEN
        (* 写指针双检（红线 R4）：MOD 已保证范围，仍显式兜底防越界写 *)
        (* Write index double check: explicit guard besides MOD *)
        afWindow[nWrite] := fIn;
        nWrite    := (nWrite + 1) MOD DL_MED_CAP;
        nFilledInt := MIN(nFilledInt + 1, nWinEff);
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜取有效样本到排序副本（边界 B3）：只取最近 nFilledInt 个，
 *      Copy the valid samples into the sorting copy
 *      禁止复制整窗——未填区是 0，会把中值拉低
 *-----------------------------------------------------------------------------*)
FOR nK := 0 TO (nFilledInt - 1) DO
    (* 正数化取模：先加两倍容量再取模，规避负数取模的平台差异（边界 B3） *)
    (* Positive modulo: add twice the capacity before MOD, platform-safe *)
    nIdx := (nWrite - 1 - nK + DL_MED_CAP * 2) MOD DL_MED_CAP;
    IF (nIdx >= 0) AND (nIdx < DL_MED_CAP) AND (nK >= 0) AND (nK < DL_MED_CAP) THEN
        afSort[nK] := afWindow[nIdx];
    END_IF
END_FOR;

(*------------------------------------------------------------------------------
 * 段 7｜插入排序（边界 B4）：对副本 afSort[0..nFilledInt-1] 排序，
 *      Insertion sort on the copy afSort[0..nFilledInt-1]
 *      n ≤ 15 最坏 105 次比较；nGuard 防死锁，超限置 16#0001_0004
 *-----------------------------------------------------------------------------*)
FOR nI := 1 TO (nFilledInt - 1) DO
    fTmp      := afSort[nI];
    nJ        := nI - 1;
    bShiftEnd := FALSE;
    WHILE (nJ >= 0) AND (NOT bShiftEnd) DO
        nGuard := nGuard + 1;
        IF nGuard > DL_MED_GUARD THEN
            uErrorId   := 16#0001_0004; // 排序循环保护触发 / Sort loop guard tripped
            bGuardTrip := TRUE;         // 本拍放弃落位，保留已排部分 / Drop this pass, keep the sorted part
            bShiftEnd  := TRUE;
        ELSIF afSort[nJ] > fTmp THEN
            afSort[nJ + 1] := afSort[nJ];
            nJ := nJ - 1;
        ELSE
            bShiftEnd := TRUE;
        END_IF
    END_WHILE
    IF NOT bGuardTrip THEN
        afSort[nJ + 1] := fTmp;         // 正常路径含 nJ = -1 时落位到队首 / Normal path, nJ = -1 lands at the front
    END_IF
END_FOR;

(*------------------------------------------------------------------------------
 * 段 8｜取中值：奇数取正中；偶数为防御分支（正常流程已被 B2 排除）
 *      Median extraction: odd takes the middle; even is defensive only
 *-----------------------------------------------------------------------------*)
IF nFilledInt > 0 THEN
    IF (nFilledInt MOD 2) = 1 THEN
        fMedian := afSort[nFilledInt / 2];              // 整除取正中 / Integer division takes the middle
    ELSE
        fMedian := (afSort[nFilledInt / 2 - 1] + afSort[nFilledInt / 2]) / 2.0;
    END_IF
ELSE
    fMedian := 0.0;                     // 空窗输出 0.0 哨兵 / Empty window outputs the 0.0 sentinel
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜状态派生与主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      State derivation and main state machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
IF bParamEvt THEN
    eStateInt := E_DL_MedianState.eFault;
ELSIF nFilledInt <= 0 THEN
    eStateInt := E_DL_MedianState.eEmpty;
ELSIF nFilledInt < nWinEff THEN
    eStateInt := E_DL_MedianState.eFilling;
ELSE
    eStateInt := E_DL_MedianState.eReady;
END_IF

CASE eStateInt OF

    E_DL_MedianState.eEmpty:
        (* 空窗：无有效输出，bValid 由段 10 置 FALSE / Empty: no valid output *)

    E_DL_MedianState.eFilling:
        (* 填充中：段 8 已按已到样本取中值，保证上电即有值（边界 B1） *)
        (* Filling: median of available samples, a value from power-up on *)

    E_DL_MedianState.eReady:
        (* 就绪：整窗中值 / Ready: full-window median *)

    E_DL_MedianState.eFault:
        (* 参数事件当拍：参数已修正、下拍恢复，不锁存 / Event scan, recovers next scan *)

    ELSE
        (* 非法状态一律回故障态并置码（红线 R6） *)
        (* Illegal state falls back to fault with a code *)
        eStateInt := E_DL_MedianState.eFault;
        uErrorId  := 16#0001_0005;

END_CASE

(*------------------------------------------------------------------------------
 * 段 10｜输出单一出口：有效性与满窗标志由计数派生
 *      Single output exit: validity and full flags derived from the count
 *-----------------------------------------------------------------------------*)
nFilled     := nFilledInt;
bValid      := (nFilledInt > 0);
bWindowFull := (nFilledInt >= nWinEff);
eState      := eStateInt;
END_FUNCTION_BLOCK
