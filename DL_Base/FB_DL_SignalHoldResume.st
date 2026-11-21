(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SignalHoldResume
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / F_TRIG），零厂商私有库
 * 功能描述 (Function)   : 8 路信号快照锁存/恢复：bHold 上升沿将 8 路实时输入
 *                         abSignal[0..7] 拍照锁存到锁存副本 abSnap；bHold=TRUE
 *                         期间输出 abOut 保持锁存副本（实时变化不穿透）；bHold
 *                         下降沿（恢复沿）输出无扰切回实时值，并逐通道做
 *                         「锁存副本 vs 实时值」一致性校验：不一致通道记入
 *                         uChgMask 位图与信息码 eResumeDiff（信息级，不置 bError）。
 * 接口     (Interface)  : 输入 abSignal 8 路实时信号数组、bHold 保持/恢复命令；
 *                         输出 abOut 8 路输出（保持期=锁存副本，恢复期=实时值）、
 *                         abSnap 锁存副本透读（诊断用）、uChgMask 恢复沿不一致
 *                         位图（bit i 对应通道 i，恢复沿单拍更新）、bHolding
 *                         保持中指示、eErrCode 信息码、bError 故障标志
 *                         （本件无故障级条件，恒 FALSE，出口保留契约位）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做快照锁存与恢复校验，
 *                         不判定信号真伪、不接管联锁**；信号质量诊断归
 *                         `FB_DL_SignalQualify`。
 *                         ② 锁存判定只读锁存副本（abSnap），禁止读实时数组替代
 *                         （锁存副本与实时镜像不得混用，派单红线）。
 *                         ③ 恢复沿校验用锁存副本与当拍实时值比较；uChgMask 在
 *                         非恢复沿拍保持上拍值（诊断锁存语义，非单拍抹除）。
 *                         ④ 两沿实例（R_TRIG/F_TRIG）段 0 无条件周期调用（R6）。
 *                         ⑤ 通道数定长 8（常量），无数组越界路径。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_SignalFrozenDetect` 分工：信号冻结检测归那件、
 *                         快照锁存/恢复归本件；与 `FB_DL_BitShiftRegister` 分工：
 *                         移位 ≠ 快照。
 * 来源标签 (Source Tag) : 自研线（快照锁存语义为道莅防御性实现）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 数组 + WORD
 *                         位图 + ENUM 信息码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 锁存副本/实时镜像分用 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 一 F_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 1 · 序号 2）
 * 验收向量 (Acceptance) : ① 实时 [F,T,F,F,F,F,F,F] 时 bHold 上升沿 → abSnap=
 *                         [F,T,...]，随后 abSignal[1] 变 F：保持期 abOut 仍
 *                         [F,T,...]（变化不穿透），bHolding=TRUE；
 *                         ② bHold 下降沿：abOut 切回实时 [F,F,...]，通道 1
 *                         锁存副本 T ≠ 实时 F → uChgMask.bit1=1，
 *                         eErrCode=eResumeDiff（信息级）；
 *                         ③ 锁存副本与实时全一致时恢复 → uChgMask=0，
 *                         eErrCode=eOk。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ShrErr（信息码；本件无故障级条件，信息级不置 bError）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ShrErr :
(
    eOk         := 0,   // 恢复沿锁存副本与实时一致 / Snapshot matches live at resume
    eResumeDiff := 1    // 信息级：恢复沿存在不一致通道（见 uChgMask） / Info: mismatch channels at resume, see uChgMask
);
END_TYPE

FUNCTION_BLOCK FB_DL_SignalHoldResume
VAR_INPUT
    abSignal : ARRAY[0..7] OF BOOL;   // 8 路实时输入信号 [-] / Eight live input signals
    bHold    : BOOL := FALSE;         // 保持/恢复命令（上升沿拍照，下降沿恢复） [-] / Hold command, rising edge snapshots
END_VAR
VAR_OUTPUT
    abOut    : ARRAY[0..7] OF BOOL;   // 8 路输出（保持期=锁存副本，恢复期=实时） [-] / Eight outputs
    abSnap   : ARRAY[0..7] OF BOOL;   // 锁存副本透读（诊断用） [-] / Latched snapshot for diagnostics
    uChgMask : WORD;                  // 恢复沿不一致位图（bit i=通道 i） [-] / Mismatch bitmap at resume edge
    bHolding : BOOL;                  // 保持中指示（bHold 电平镜像） [-] / Holding indicator
    eErrCode : E_DL_ShrErr;           // 信息码出口 / Info code outlet
    bError   : BOOL;                  // 故障标志（本件无故障级条件，恒 FALSE，契约位） [-] / Error flag, contract pin, always FALSE
END_VAR
VAR
    _abSnap  : ARRAY[0..7] OF BOOL;   // 锁存副本（唯一快照源，判定只读此副本） [-] / Latched snapshot, sole judgment source
    _uChg    : WORD;                  // 不一致位图内部锁存量（非恢复沿保持） [-] / Mismatch bitmap latch
    _bDiff   : BOOL;                  // 恢复沿存在不一致当拍量 [-] / Mismatch exists at resume
    i        : DINT;                  // 通道循环索引 / Channel loop index
    rtHold   : R_TRIG;                // 保持上升沿实例，段 0 无条件调用 / Hold rising-edge instance
    ftHold   : F_TRIG;                // 保持下降沿实例，段 0 无条件调用 / Hold falling-edge instance
END_VAR
VAR CONSTANT
    DL_SHR_NCHAN : DINT := 8;         // 通道定长 [路] / Fixed channel count
    DL_SHR_BIT0  : WORD := 1;         // bit0 基准掩码 [-] / Bit zero base mask
END_VAR

(* —— 段 0：沿实例无条件周期刷新（R6/R7） —— *)
rtHold(CLK := bHold);                 // 保持上升沿，每拍必调 / Hold rising edge, every scan
ftHold(CLK := bHold);                 // 保持下降沿，每拍必调 / Hold falling edge, every scan

(* —— 段 1：单拍量预清（_abSnap/_uChg 为锁存量不入清单，R107） —— *)
_bDiff := FALSE;                      // 不一致当拍量预清 / Mismatch preset

(* —— 段 2：保持上升沿 → 8 路拍照锁存 —— *)
IF rtHold.Q THEN
    FOR i := 0 TO (DL_SHR_NCHAN - 1) DO
        _abSnap[i] := abSignal[i];    // 逐通道快照锁存 / Per-channel snapshot latch
    END_FOR
END_IF

(* —— 段 3：恢复沿 → 锁存副本 vs 实时值逐通道一致性校验 —— *)
IF ftHold.Q THEN
    _uChg := 0;                       // 恢复沿重建位图（锁存量唯一写入点） / Rebuild bitmap at resume edge
    FOR i := 0 TO (DL_SHR_NCHAN - 1) DO
        IF _abSnap[i] <> abSignal[i] THEN
            _uChg := _uChg OR SHL(DL_SHR_BIT0, i);   // 不一致通道记位（i∈[0,7] 位宽内，结构性不越界） / Mark mismatch bit
            _bDiff := TRUE;           // 存在不一致 / Mismatch exists
        END_IF
    END_FOR
END_IF

(* —— 段 4：输出组合（保持期穿透闸：输出只取锁存副本） —— *)
FOR i := 0 TO (DL_SHR_NCHAN - 1) DO
    IF bHold THEN
        abOut[i] := _abSnap[i];       // 保持期：输出锁存副本（实时变化不穿透） / Held: output snapshot
    ELSE
        abOut[i] := abSignal[i];      // 恢复期：输出实时值 / Resumed: output live value
    END_IF
    abSnap[i] := _abSnap[i];          // 副本透读出口 / Snapshot readout outlet
END_FOR

(* —— 段 5：出口单点映射（名实双出口同源，R191） —— *)
bHolding := bHold;                    // 保持中指示（电平镜像） / Holding indicator
uChgMask := _uChg;                    // 位图出口（恢复沿外保持） / Bitmap outlet
IF _bDiff THEN
    eErrCode := E_DL_ShrErr.eResumeDiff;   // 信息级码（不置 bError） / Info code
ELSE
    eErrCode := E_DL_ShrErr.eOk;           // 一致或缺省 / Consistent or default
END_IF
bError := FALSE;                      // 本件无故障级条件（头注释声明，契约位恒 FALSE） / No fault-level condition

END_FUNCTION_BLOCK
