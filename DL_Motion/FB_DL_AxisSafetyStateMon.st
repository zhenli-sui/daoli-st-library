(*
  ==================================================================
  组件名 Component  : FB_DL_AxisSafetyStateMon
  分类   Category   : DL_Motion
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 轴安全功能状态字监视。从驱动器安全状态字反馈（STO /
                      SLS / SOS 位）解码激活态，与 PLC 侧安全请求逐位比对：
                      请求-反馈不一致经消抖确认窗后锁存不一致位图并置故障
                      （仅监视不发令，无任何命令输出）；全零反馈字持续判
                      通信失效。与 AxisSs1StopSeq 执行件分工互引。
  来源   Source     : t1-6-plcopen（轴侧安全层同层扩展）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；STO / SLS / SOS
                      为 IEC 61800-5-2 公开安全功能语义，clean-room 自研实现，
                      未复制 PLCopen 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_AxisSs1StopSeq 分工——后者为 SS1 停车执行顺控
                      （发令侧），本件为安全功能状态字监视（收令侧仅监视，
                      零命令输出）；本件不做安全功能替代，安全回路本体仍由
                      硬件安全层承担。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 状态字位定义（固定掩码常量，禁变量移位 R48）：
                         位 0 = STO 激活，位 1 = SLS 激活，位 2 = SOS 激活；
                         位 3..15 保留（不参与判定，声明覆盖范围）；
                      二 不一致判据 = 请求位 XOR 反馈位逐位比对，任一位不
                         一致持续 tMismatchDebounce 后锁存位图并置故障；解除
                         路径 = bReset 上升沿（唯一路径，R188）；
                      三 通信失效判据 = 反馈字连续两拍全零且持续 tCommWatch
                         判失效（故障级独立成因，R190）；
                      四 仅监视：本件零命令输出（功能定义即不发令）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 4 · 序号 13）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_AxisSafetyStateMon
VAR_INPUT
    bEnable            : BOOL := TRUE;     // 使能，失能冻结监视输出末值 [-] / enable, disabling freezes the monitor outputs
    bReset             : BOOL := FALSE;    // 复位上升沿清故障锁存 [-] / reset rising edge clears the fault latch
    bStoReq            : BOOL := FALSE;    // STO 请求（PLC 侧发出）[-] / the STO request from the PLC side
    bSlsReq            : BOOL := FALSE;    // SLS 请求 [-] / the SLS request
    bSosReq            : BOOL := FALSE;    // SOS 请求 [-] / the SOS request
    uSafFbWord         : WORD := 16#FFFF;  // 驱动器安全状态字反馈 [位图] / the drive safety status word feedback [bitmap]
    tMismatchDebounce  : TIME := T#100MS;  // 不一致消抖确认窗 [毫秒] / the mismatch debounce window [millisecond]
    tCommWatch         : TIME := T#500MS;  // 全零通信失效窗 [毫秒] / the all zero comm loss window [millisecond]
END_VAR
VAR_OUTPUT
    bStoActive : BOOL := FALSE; // STO 激活解码出口（位 0）[-] / the STO active decode outlet, bit zero
    bSlsActive : BOOL := FALSE; // SLS 激活解码出口（位 1）[-] / the SLS active decode outlet, bit one
    bSosActive : BOOL := FALSE; // SOS 激活解码出口（位 2）[-] / the SOS active decode outlet, bit two
    uMismatch  : WORD := 16#0000; // 不一致位图出口（请求 XOR 反馈，锁存回放）[位图] / the mismatch bitmap outlet, latched replay [bitmap]
    bCommBad   : BOOL := FALSE; // 通信失效指示（故障级）[-] / the comm loss indicator, fault grade
    bError     : BOOL := FALSE; // 故障锁存标志（不一致或通信失效）[-] / the fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    tonMis   : TON;    // 不一致消抖窗，段 0 无条件刷新 / the mismatch debounce window
    tonComm  : TON;    // 通信失效窗，段 0 无条件刷新 / the comm loss window
    _bStoFb  : BOOL := FALSE; // STO 反馈解码工作量（位 0）/ the STO feedback decode work bit
    _bSlsFb  : BOOL := FALSE; // SLS 反馈解码工作量（位 1）/ the SLS feedback decode work bit
    _bSosFb  : BOOL := FALSE; // SOS 反馈解码工作量（位 2）/ the SOS feedback decode work bit
    _uMisNow : WORD := 16#0000; // 当拍不一致位图工作量 [位图] / the current mismatch bitmap work value
    _bMisNow : BOOL := FALSE; // 当拍存在不一致工作量 [-] / the current mismatch work flag
    _bMisL   : BOOL := FALSE; // 不一致锁存位 [-] / the mismatch latch bit
    _uMisL   : WORD := 16#0000; // 不一致位图锁存 [位图] / the mismatch bitmap latch
    _bCommL  : BOOL := FALSE; // 通信失效锁存位 [-] / the comm loss latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
END_VAR
VAR CONSTANT
    DL_ASM_BIT_STO : WORD := 16#0001; // STO 位掩码（位 0，固定常量禁移位）/ the STO bit mask, bit zero
    DL_ASM_BIT_SLS : WORD := 16#0002; // SLS 位掩码（位 1）/ the SLS bit mask, bit one
    DL_ASM_BIT_SOS : WORD := 16#0004; // SOS 位掩码（位 2）/ the SOS bit mask, bit two
    DL_ASM_WORD_ZERO : WORD := 16#0000; // 全零字常量（通信失效判据）/ the all zero word constant
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，FB50-1）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
_bStoFb := (uSafFbWord AND DL_ASM_BIT_STO) <> DL_ASM_WORD_ZERO; // 位 0 解码（固定掩码，无移位）/ the bit zero decode by a fixed mask
_bSlsFb := (uSafFbWord AND DL_ASM_BIT_SLS) <> DL_ASM_WORD_ZERO; // 位 1 解码 / the bit one decode
_bSosFb := (uSafFbWord AND DL_ASM_BIT_SOS) <> DL_ASM_WORD_ZERO; // 位 2 解码 / the bit two decode
_uMisNow := 16#0000; // 当拍位图预清零 / preset the current bitmap zero
IF bStoReq <> _bStoFb THEN // STO 请求反馈不一致 / an STO request feedback mismatch
    _uMisNow := _uMisNow OR DL_ASM_BIT_STO; // 位图记位 / mark the bitmap
END_IF
IF bSlsReq <> _bSlsFb THEN // SLS 不一致 / an SLS mismatch
    _uMisNow := _uMisNow OR DL_ASM_BIT_SLS; // 位图记位 / mark the bitmap
END_IF
IF bSosReq <> _bSosFb THEN // SOS 不一致 / an SOS mismatch
    _uMisNow := _uMisNow OR DL_ASM_BIT_SOS; // 位图记位 / mark the bitmap
END_IF
_bMisNow := _uMisNow <> DL_ASM_WORD_ZERO; // 当拍存在不一致 / a mismatch exists this scan
tonMis(IN := bEnable AND (NOT _bMisL) AND (NOT _bCommL) AND _bMisNow, PT := tMismatchDebounce); // 消抖窗，IN 串锁存反闸（防复位同拍重锁，FB50-1）/ the debounce window gated against the latches
tonComm(IN := bEnable AND (NOT _bCommL) AND (uSafFbWord = DL_ASM_WORD_ZERO), PT := tCommWatch); // 通信失效窗，IN 串全零条件 / the comm window on the all zero condition

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清不一致锁存与位图 / 清通信锁存 / 清出口（三项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bMisL := FALSE; // 作用域一：清不一致锁存（解除路径 = bReset 沿，R188）/ scope one, clear the mismatch latch
    _uMisL := 16#0000; // 作用域一：清位图锁存 / scope one, clear the bitmap latch
    _bCommL := FALSE; // 作用域二：清通信锁存 / scope two, clear the comm latch
    uMismatch := 16#0000; // 作用域三：清位图出口 / scope three, clear the bitmap outlet
    bCommBad := FALSE; // 作用域三：清通信出口 / scope three, clear the comm outlet
    bError := FALSE; // 作用域三：清故障出口 / scope three, clear the fault outlet
END_IF

// 段 3｜故障锁存判定（消抖确认后锁存，R190 独立成因）/ segment 3, the fault latch verdicts
IF bEnable THEN // 使能才锁存 / latch only when enabled
    IF tonMis.Q AND (NOT _bMisL) THEN // 消抖确认且未锁存 / a debounced confirmation while unlatched
        _bMisL := TRUE; // 置不一致锁存 / raise the mismatch latch
        _uMisL := _uMisNow; // 锁存首因位图（回放不重推断 R152）/ latch the first cause bitmap
    END_IF
    IF tonComm.Q AND (NOT _bCommL) THEN // 通信失效确认且未锁存 / a comm confirmation while unlatched
        _bCommL := TRUE; // 置通信锁存 / raise the comm latch
    END_IF
END_IF

// 段 4｜统一出口（边界四：仅监视，零命令输出）/ segment 4, the unified outlet
IF bEnable THEN // 使能实时刷新解码 / refresh the decode when enabled
    bStoActive := _bStoFb; // STO 出口 / the STO outlet
    bSlsActive := _bSlsFb; // SLS 出口 / the SLS outlet
    bSosActive := _bSosFb; // SOS 出口 / the SOS outlet
END_IF // 失能时解码出口冻结保持末值（R191 冻结保持声明）/ disabled freezes the decode outlets
IF _bMisL THEN // 不一致锁存回放 / the mismatch latch replay
    uMismatch := _uMisL; // 位图回放 / replay the bitmap
ELSE // 无锁存随当拍位图（信息级实时可观测）/ no latch, the live bitmap
    uMismatch := _uMisNow; // 实时位图 / the live bitmap
END_IF
bCommBad := _bCommL; // 通信出口与锁存同源 / the comm outlet shares the latch
bError := _bMisL OR _bCommL; // 故障标志聚合（R191 名实双出口）/ the flag aggregation
END_FUNCTION_BLOCK
