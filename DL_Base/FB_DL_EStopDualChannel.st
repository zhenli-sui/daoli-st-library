(*
  ==================================================================
  组件名 Component  : FB_DL_EStopDualChannel
  分类   Category   : DL_Base
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 双通道急停监视。两路常闭信号（TRUE = 触点闭合 = 安全侧）做
                      一致性监视：两路均闭合出安全态；仅一路闭合进入差异窗
                      （tDiscMax），超窗判单通道失效并锁存坏通道位；两路均断开
                      判「已拍下」（信息级，安全侧输出为假）；复位上升沿必须在
                      两通道均恢复后到达才可清锁存，未恢复即按复位判 eStuckReset。
  来源   Source     : t2-1-lgf-converter（安全逻辑组织）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；双回路不一致监视组织
                      借鉴 IEC 60204-1 公开条款语义，clean-room 自研，未复制任何
                      闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做双回路监视与安全侧出口，不驱动任何执行器（属主边界）；
                      二 bSafeState 只在两通道均确认安全（均闭合）且无故障锁存时为真，
                         任何不确定一律走 FALSE（安全侧优先，失效即断开语义）；
                      三 eBothOpen 为信息级成因（正常拍下状态），不置 bError；
                         其余成因均为故障级，与 bError 配对（R45）；
                      四 故障锁存解除路径 = bReset 上升沿且两通道均闭合（唯一路径，
                         头注释声明，R188）；未恢复即复位判 eStuckReset 并锁存；
                      五 差异自愈：差异窗内两通道恢复一致即回运行相，不锁存（瞬时抖动
                         不判失效，tDiscMax 内自愈为设计意图）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      bChannel1Bad / bChannel2Bad 为锁存位，仅在 eDiscTimeout 判定时
                      置位（坏通道 = 处于断开位的那一路），复位沿恢复后清零；
                      eFault 为锁存回放（不在故障相按当下输入重推断，R152）；
                      ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 1 · 序号 5）
  ==================================================================
*)

TYPE E_DL_EsdPhase :
(
    eIdle    := 0,  // 未使能：监视停摆，安全侧输出为假 / disabled, the watch is idle and the safe outlet is false
    eRun     := 10, // 运行：两通道一致（均闭合或均断开）/ running, the channels agree
    eDiscord := 20, // 差异：仅一路闭合，差异窗计时中 / discrepancy, one channel closed and the window is timing
    eFault   := 90  // 故障：成因锁存，安全侧输出为假 / fault, the cause is latched and the safe outlet is false
);
END_TYPE

TYPE E_DL_EsdFault :
(
    eNone            := 0, // 无成因 / no cause
    eChannelMismatch := 1, // 通道不一致（差异窗内，信息级）/ the channels disagree inside the window, informational
    eDiscTimeout     := 2, // 差异超窗判单通道失效（故障级，与 bError 配对）/ the discrepancy outlasted the window, a single channel failed, fault grade paired with bError
    eBothOpen        := 3, // 两路均断开 = 急停已拍下（信息级，安全侧为假）/ both channels open, the stop is pressed, informational
    eStuckReset      := 4, // 复位到达但通道未恢复（故障级，与 bError 配对）/ a reset arrived without both channels restored, fault grade paired with bError
    ePhaseBad        := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_EStopDualChannel
VAR_INPUT
    bEnable  : BOOL := TRUE;      // 使能，失能时安全侧输出为假 [-] / enable, the safe outlet is false when disabled
    bReset   : BOOL := FALSE;     // 复位，上升沿在两通道均闭合时清锁存 [-] / reset, the rising edge clears the latch only with both channels closed
    bCh1Ok   : BOOL := TRUE;      // 通道 1 常闭反馈，TRUE = 闭合 = 安全 [-] / channel one normally closed feedback, true is closed and safe
    bCh2Ok   : BOOL := TRUE;      // 通道 2 常闭反馈，TRUE = 闭合 = 安全 [-] / channel two normally closed feedback, true is closed and safe
    tDiscMax : TIME := T#500MS;   // 差异窗（单通道失效判定时长）[毫秒]，域 大于零 / discrepancy window [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    bSafeState    : BOOL := FALSE; // 安全侧输出：仅在两通道均闭合且无故障锁存时为真 [-] / the safe side outlet, true only with both channels closed and no fault latch
    bChannel1Bad  : BOOL := FALSE; // 通道 1 失效锁存位 [-] / channel one failed latch bit
    bChannel2Bad  : BOOL := FALSE; // 通道 2 失效锁存位 [-] / channel two failed latch bit
    ePhase        : E_DL_EsdPhase := E_DL_EsdPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault        : E_DL_EsdFault := E_DL_EsdFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError        : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonDisc  : TON;    // 差异窗计时，段 0 无条件刷新 / discrepancy window timer, refreshed unconditionally in segment zero
    _ePhase  : E_DL_EsdPhase := E_DL_EsdPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause  : E_DL_EsdFault := E_DL_EsdFault.eNone; // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaulC  : E_DL_EsdFault := E_DL_EsdFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bDisc   : BOOL := FALSE; // 本拍通道不一致 [-] / the channels disagree this scan
    _bBothOk : BOOL := FALSE; // 本拍两通道均闭合 [-] / both channels are closed this scan
    _bNoneOk : BOOL := FALSE; // 本拍两通道均断开 [-] / both channels are open this scan
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸 / segment 0, unconditional refresh with the phase and fault gates on IN only
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonDisc(IN := (_ePhase = E_DL_EsdPhase.eDiscord) AND (NOT _bFault), PT := tDiscMax); // 差异窗，IN 串差异相闸与故障闸 / the discrepancy window with the phase and fault gates on IN

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_EsdPhase.eRun; // 相位从运行起步（使能默认真）/ the phase starts in run
    _eCause := E_DL_EsdFault.eNone; // 信息级成因清零 / clear the informational cause
    _eFaulC := E_DL_EsdFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
END_IF

// 段 2｜本拍一致性判定（组合量，无锁存）/ segment 2, the per scan consistency verdict
_bBothOk := bCh1Ok AND bCh2Ok; // 两路均闭合 / both channels are closed
_bNoneOk := (NOT bCh1Ok) AND (NOT bCh2Ok); // 两路均断开 / both channels are open
_bDisc := (bCh1Ok <> bCh2Ok); // 两路不一致（XOR 语义）/ the channels disagree

// 段 3｜复位沿作用域：仅在两通道均恢复时清锁存，未恢复判卡死复位 / segment 3, reset edge scope, the latch clears only with both channels restored
IF rtReset.Q THEN // 复位沿 / the reset edge
    IF _bBothOk THEN // 两通道均恢复 / both channels are restored
        _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
        _eFaulC := E_DL_EsdFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
        bChannel1Bad := FALSE; // 作用域一：清通道 1 失效位 / scope one, clear the channel one failed bit
        bChannel2Bad := FALSE; // 作用域一：清通道 2 失效位 / scope one, clear the channel two failed bit
        _ePhase := E_DL_EsdPhase.eRun; // 作用域二：迁回运行相 / scope two, migrate back to run
    ELSE // 未恢复即复位 / a reset without restoration
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_EsdFault.eStuckReset; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_EsdPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_EsdPhase.eIdle: // 未使能相：安全侧输出为假 / the disabled phase, the safe outlet is false
    IF bEnable THEN // 使能恢复 / enabled again
        _ePhase := E_DL_EsdPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_EsdPhase.eRun: // 运行相：两通道一致 / the run phase, the channels agree
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_EsdPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF _bDisc THEN // 通道不一致 / the channels disagree
        _eCause := E_DL_EsdFault.eChannelMismatch; // 信息级成因：差异窗内 / the informational cause inside the window
        _ePhase := E_DL_EsdPhase.eDiscord; // 迁差异相 / migrate to the discrepancy phase
    ELSIF _bNoneOk THEN // 两路均断开 = 已拍下 / both open, the stop is pressed
        _eCause := E_DL_EsdFault.eBothOpen; // 信息级成因，不置故障（设计语义）/ the informational cause, no fault by design
    ELSE // 两路均闭合，无成因 / both closed, no cause
        _eCause := E_DL_EsdFault.eNone; // 成因清零 / clear the cause
    END_IF

E_DL_EsdPhase.eDiscord: // 差异相：差异窗计时 / the discrepancy phase, the window is timing
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_EsdPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF _bBothOk THEN // 差异自愈：窗内恢复一致（R152 自愈路径）/ the transient self heals inside the window
        _eCause := E_DL_EsdFault.eNone; // 成因清零 / clear the cause
        _ePhase := E_DL_EsdPhase.eRun; // 迁回运行相 / migrate back to run
    ELSIF _bNoneOk THEN // 两路均断开，回到一致（已拍下）/ both open, consistent again
        _eCause := E_DL_EsdFault.eBothOpen; // 信息级成因 / the informational cause
        _ePhase := E_DL_EsdPhase.eRun; // 迁回运行相 / migrate back to run
    ELSIF tonDisc.Q THEN // 差异超窗：判单通道失效 / the window expired, a single channel failed
        bChannel1Bad := NOT bCh1Ok; // 坏通道 1 = 处于断开位的一路 / channel one is bad when it sits open
        bChannel2Bad := NOT bCh2Ok; // 坏通道 2 同口径 / channel two the same way
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_EsdFault.eDiscTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_EsdPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSE // 差异仍在窗内 / the discrepancy persists inside the window
        _eCause := E_DL_EsdFault.eChannelMismatch; // 信息级成因每拍重算 / the informational cause is recomputed every scan
    END_IF

E_DL_EsdPhase.eFault: // 故障相：成因锁存回放，安全侧输出为假 / the fault phase, the cause is latched and the safe outlet is false
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_EsdPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_EsdFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_EsdPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口：安全侧出口与成因锁存回放 / segment 5, the unified outlet with the safe side and the latched cause
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（不按当下输入重推断，R152）/ the fault cause replayed from the latch
ELSE
    eFault := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bSafeState := bCh1Ok AND bCh2Ok AND (NOT _bFault) AND bEnable; // 安全侧出口：双确认 + 无锁存 + 使能（任何不确定走假）/ the safe outlet, double confirmation without a latch, any doubt is false
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
