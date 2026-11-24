(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EStopMonitor
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / F_TRIG / ABS），
 *                         零厂商私有库
 * 功能描述 (Function)   : 急停双通道监视：通道语义 TRUE=回路闭合（健康）。
 *                         任一通道断开 → bSafe 立即 FALSE（安全侧一级拦截，
 *                         不等确认窗）；两通道电平不一致（bCh1 <> bCh2）持续
 *                         tMismatchWin → bMismatch 锁存 + 首出通道号 eFirstOut
 *                         锁存（先断开的通道，F_TRIG 双实例竞争记录）；复位须
 *                         双通道恢复一致（bCh1 ∧ bCh2）且 bReset 上升沿才清
 *                         bMismatch/首出（规格指定）。
 * 接口     (Interface)  : 输入 bCh1 通道 1（TRUE=闭合健康）、bCh2 通道 2、
 *                         tMismatchWin 失配确认窗（域 > T#0S）、bReset 复位；
 *                         输出 bSafe 可运行判据（双通道健康 ∧ 无失配锁存）、
 *                         bMismatch 失配锁存、eFirstOut 首出通道号（锁存）、
 *                         eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做双通道监视判据，不切断
 *                         执行器、不做安全认证**（安全切断由安全继电器/IO 映射层
 *                         双保险执行，本件为诊断与允许运行判据源）。
 *                         ② 首出归因：双 F_TRIG 竞争窗口内先到沿者赢（同拍
 *                         双断时按 bCh1 优先判定，头注释声明：同拍双断无法区分
 *                         物理先后，eFirstOut 取 eCh1，规格允许的确定性归因）。
 *                         ③ 双通道同拍齐断（一致断开）不判失配：bSafe=FALSE
 *                         照常拦截，eFirstOut 保持 eNone（一致事件无失配语义）。
 *                         ④ 失配确认 TON 的 IN 派生式（bCh1 <> bCh2）∧ 通道
 *                         未齐断，段 0 无条件调用；出窗自复位（不一致消失即
 *                         复位，无外部沿清零依赖）。
 *                         ⑤ 锁存解除路径：bMismatch/eFirstOut 解除边 = 双通道
 *                         健康 ∧ bReset 上升沿（可达，头注释声明，R188/R152）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_RedundantSwitch` 分工：通道二选一归那件、
 *                         急停一致性监视归本件；与 `FB_DL_EdgeOrderCheck` 分工：
 *                         通用顺序校验归那件，本件首出归因为急停专用语义。
 * 来源标签 (Source Tag) : IEC 61131-3 标准语义的道莅防御性实现（双通道一致性
 *                         监视为标准安全监视语义）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 组 +
 *                         ENUM 通道号/错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 一级拦截不等窗 + 锁存解除可达 + 归因唯一 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM 状态机不用（首出枚举 + 锁存态） ｜ R7 ✓ 一 TON 两 F_TRIG 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 2 · 序号 10）
 * 验收向量 (Acceptance) : ① 双通道 TRUE，bCh1 在 t0 断开且 tMismatchWin 内未
 *                         恢复 → bMismatch=TRUE、eFirstOut=eCh1、bSafe=FALSE；
 *                         ② bCh1 断开 20ms 内恢复（tMismatchWin=100MS）→
 *                         tonMis 未到，bMismatch 保持 FALSE；③ 失配锁存后
 *                         bCh1/bCh2 均 TRUE + bReset 上升沿 → bMismatch=
 *                         FALSE、eFirstOut=eNone、bSafe=TRUE；④ 双通道同拍
 *                         齐断 → bSafe=FALSE，bMismatch=FALSE，eFirstOut=eNone。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_EstChannel（首出通道号，锁存回放）
 *----------------------------------------------------------------------------*)
TYPE E_DL_EstChannel :
(
    eNone := 0,   // 无首出（未发生失配或同拍齐断） / No first-out
    eCh1  := 1,   // 首出通道 1 / First-out channel 1
    eCh2  := 2    // 首出通道 2 / First-out channel 2
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_EstErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_EstErr :
(
    eOk      := 0,   // 正常 / Normal
    eCfgBad  := 1,   // 故障级：确认窗组态非法（<= T#0S） / Fault: window config illegal
    eMisLock := 2    // 故障级：失配锁存回放（归因见 eFirstOut） / Fault: mismatch latched replay
);
END_TYPE

FUNCTION_BLOCK FB_DL_EStopMonitor
VAR_INPUT
    bCh1         : BOOL := TRUE;    // 通道 1（TRUE=回路闭合健康） [-] / Channel 1, TRUE means healthy closed
    bCh2         : BOOL := TRUE;    // 通道 2（TRUE=回路闭合健康） [-] / Channel 2, TRUE means healthy closed
    tMismatchWin : TIME := T#100MS; // 失配确认窗，域 > T#0S [ms] / Mismatch confirmation window
    bReset       : BOOL := FALSE;   // 复位（须双通道健康后上升沿才生效） [-] / Reset, effective only with both channels healthy
END_VAR
VAR_OUTPUT
    bSafe     : BOOL;                // 可运行判据（双通道健康 ∧ 无失配锁存） [-] / Safe-to-run verdict
    bMismatch : BOOL;                // 失配锁存（解除 = 双通道健康 ∧ 复位沿） [-] / Mismatch latch
    eFirstOut : E_DL_EstChannel;     // 首出通道号（锁存回放，R189） / First-out channel, latched
    eErrCode  : E_DL_EstErr;         // 错误码出口 / Error code outlet
    bError    : BOOL;                // 故障标志（失配锁存或组态） [-] / Error flag
END_VAR
VAR
    _bMisLatch: BOOL;                // 失配锁存位（解除路径见头注释⑤） / Latched mismatch bit
    _eFirst   : E_DL_EstChannel := E_DL_EstChannel.eNone;   // 首出通道锁存 / Latched first-out channel
    _bCfgBad  : BOOL;                // 组态非法当拍量 [-] / Illegal configuration this scan
    _bCfgLatch: BOOL;                // 组态故障锁存位（解除沿 = 双通道健康 ∧ bReset 上升沿） / Latched config fault
    _bBothOk  : BOOL;                // 双通道健康当拍量 [-] / Both channels healthy
    rtReset   : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge instance
    ftCh1     : F_TRIG;              // 通道 1 下降沿（断开）实例，段 0 无条件调用 / Ch1 falling-edge instance
    ftCh2     : F_TRIG;              // 通道 2 下降沿（断开）实例，段 0 无条件调用 / Ch2 falling-edge instance
    tonMis    : TON;                 // 失配确认窗，段 0 无条件调用 / Mismatch confirmation TON
END_VAR

(* —— 段 0：组态闸 + 全部沿/定时器无条件周期刷新（R6/R7） —— *)
_bCfgBad := (tMismatchWin <= T#0S);            // 确认窗域闸 / Window configuration gate
_bBothOk := bCh1 AND bCh2;                     // 双通道健康判据 / Both channels healthy
rtReset(CLK := bReset);                        // 复位沿，每拍必调 / Reset edge, every scan
ftCh1(CLK := bCh1);                            // 通道 1 断开沿，每拍必调 / Ch1 open edge, every scan
ftCh2(CLK := bCh2);                            // 通道 2 断开沿，每拍必调 / Ch2 open edge, every scan
tonMis(IN := (bCh1 <> bCh2) AND (NOT _bMisLatch) AND (NOT _bCfgLatch),
       PT := tMismatchWin);                    // 失配确认窗（出窗自复位：不一致消失即清，头注释④） / Mismatch window, self-resetting

(* —— 段 1：复位沿（须双通道健康才生效；清失配/首出/组态锁存） —— *)
IF rtReset.Q AND _bBothOk THEN
    _bMisLatch := FALSE;                       // 清失配锁存（可达解除路径，头注释⑤） / Clear mismatch latch
    _eFirst := E_DL_EstChannel.eNone;          // 清首出归因 / Clear first-out
    _bCfgLatch := FALSE;                       // 清组态锁存 / Clear config latch
END_IF
IF _bCfgBad AND (NOT _bCfgLatch) THEN
    _bCfgLatch := TRUE;                        // 组态锁存 / Latch config fault
END_IF

(* —— 段 2：首出归因（失配未锁存期，先断沿者赢；同拍双断 bCh1 优先，头注释②） —— *)
IF (NOT _bMisLatch) AND (bCh1 <> bCh2) THEN
    IF ftCh1.Q THEN
        _eFirst := E_DL_EstChannel.eCh1;       // 通道 1 先断归因 / Ch1 first-out
    ELSIF ftCh2.Q THEN
        _eFirst := E_DL_EstChannel.eCh2;       // 通道 2 先断归因 / Ch2 first-out
    END_IF
END_IF

(* —— 段 3：失配确认锁存（窗到锁存；同拍齐断不判失配，头注释③） —— *)
IF tonMis.Q AND (NOT _bMisLatch) THEN
    _bMisLatch := TRUE;                        // 失配锁存（R189：锁存回放，不在故障相重推断） / Latch mismatch
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
bSafe := _bBothOk AND (NOT _bMisLatch) AND (NOT _bCfgLatch);   // 可运行判据（安全侧一级拦截不等窗） / Safe verdict, immediate intercept
bMismatch := _bMisLatch;                       // 失配出口 / Mismatch outlet
eFirstOut := _eFirst;                          // 首出出口 / First-out outlet
IF _bCfgLatch THEN
    bError := TRUE;                            // 故障标志（组态级，R45 配对） / Error flag
    eErrCode := E_DL_EstErr.eCfgBad;           // 组态故障码 / Config fault code
ELSIF _bMisLatch THEN
    bError := TRUE;                            // 故障标志（失配级） / Error flag
    eErrCode := E_DL_EstErr.eMisLock;          // 失配锁存回放码 / Mismatch replay code
ELSE
    bError := FALSE;                           // 正常 / Normal
    eErrCode := E_DL_EstErr.eOk;               // 正常码 / OK code
END_IF

END_FUNCTION_BLOCK
