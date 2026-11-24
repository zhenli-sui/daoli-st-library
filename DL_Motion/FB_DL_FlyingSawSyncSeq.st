//==============================================================================
// 功能块：FB_DL_FlyingSawSyncSeq ｜ 中文名称：飞锯同步切入-切割-返回全序列
// 所属子库：DL_Motion ｜ 版本：v1.0.1 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3 第 3 版，零方言）
// 功能描述：飞锯电子凸轮全序列编排。以同步轴（主轴）位置为时间基准：在切割
//           锚点前方 fSyncLen 区间内把主从速比从 0 线性爬升到 1（同步切入），
//           保持速比 1 走完 fCutLen 切割窗口（本窗内 bCutReq 置位），再对称
//           降回 0（同步返回）。速比全部按主轴位置增量生成，即相对同步轴
//           补偿：主轴中途变速不破坏同步关系，刀轴速度 = 主轴速度 × fRatio。
// 开源溯源 (Origin)：原创实现（t1-6-plcopen 运动序列语义深化 + S-9 工程惯例，
//           零外部源码行，clean-room 独立编写）
// 公开接口清单：输入 bEn / bStart / fMasterPos / fSyncLen / fCutLen；
//               输出 bKnifeRun / fRatio / bCutReq / bCycleDone / eState /
//               uErrCode / bValid
// 单位表：fMasterPos[mm] / fSyncLen[mm] / fCutLen[mm] / fRatio[1]（无量纲比）
// 输入契约：fMasterPos 为主轴编码器工程位置，须单调正向为切割方向；fSyncLen
//           /fCutLen 为工艺给定窗长，启动闸拒绝非正值；bStart 沿触发单周期。
// 输出契约：fRatio 注入刀轴速度合成（刀速 = 主速 × fRatio）；bCutReq 为
//           请求级信号（非执行器驱动级）；bCycleDone 单拍计件脉冲；
//           uErrCode 信息级不锁存；bValid = FALSE 拍全部输出视为不可信。
// 错误码表：16#0004_08C0 信息级（参数非法拒绝启动、输入非有限安全侧回怠速、
//           序列中途参数退化中止，不置 bError）/
//           16#0004_08C1 预留禁用（不得挪用）
// 状态机：E_DL_FlyingSawState（本文件唯一定义，全库唯一属主）：
//           eIdle = 0 / eWait = 10 / eSyncIn = 20 / eCutting = 30 / eSyncOut = 40
// 边界行为：① fSyncLen / fCutLen <= 0 或非有限 → 拒绝启动（怠速态）+ 信息码；
//           ② 主轴位置非有限 → 速比冻结 0、序列中止回 eIdle（安全侧）；
//           ③ 速比全程钳 0..1，除法分母 fSyncLen 先过正域闸；
//           ④ 切入相内主轴位置跳变已越锚点 → 相位判据顺带直入切割相不丢拍
//             （未来窗锚点下，启动沿不可能已越窗）；
//           ⑤ CASE 带 ELSE 非法状态兜底回 eIdle；
//           ⑥ R_TRIG 每拍无条件刷新（不入分支，红线 R7）；
//           ⑦ bCycleDone 两段式单拍脉冲（内部置位 → 统一出口映射）；
//           ⑧ 活动相内主轴位置倒退超容差（方向反转）→ 序列中止回怠速，
//             信息级 08C0 复用留痕（R90），速比归零安全侧。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 1 · 序 1）
//           v1.0.1 2026-11-23 R73 返修：锚点改未来窗语义——启动沿锁存
//           fAnchor := fMasterPos + fSyncLen（预留一个同步窗长的提前量），
//           切入窗 [fAnchor−fSyncLen, fAnchor] 整体落在主轴前方，速比
//           0→1 爬坡真实发生；bCutReq 仍仅在速比 1 切割相内置位（头注释
//           与实现保持一致，R372 语料保真）。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_FlyingSawState（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 飞锯序列相位，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_FlyingSawState :
(
    eIdle    := 0,    // 怠速：速比 0，等待启动沿 / Idle, ratio 0, waiting for start edge
    eWait    := 10,   // 待同步：锚点已记，等主轴进入同步窗 / Waiting, anchor set, master not yet in sync window
    eSyncIn  := 20,   // 同步切入：速比 0→1 线性爬升 / Sync-in, ratio ramping 0 to 1
    eCutting := 30,   // 切割窗口：速比恒 1，bCutReq 置位 / Cutting window, ratio held 1, cut request active
    eSyncOut := 40    // 同步返回：速比 1→0 对称降回 / Sync-out, ratio ramping 1 back to 0
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FlyingSawSyncSeq
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 * 调用示例: sawSeq(bEn := bLineRun, bStart := bBatchGo,
 *                  fMasterPos := fEncPos, fSyncLen := 120.0, fCutLen := 25.0);
 *          刀轴速度指令 = fEncVel × sawSeq.fRatio；bCutReq 触发剪切执行器，
 *          bCycleDone 作为计件脉冲送上层台账。
 * 组装说明: ① 本件为纯位置闭环序列件，主轴位置经 PRG_IoMapping 读入后
 *             引脚注入，本件零 %I/%Q 物理地址（红线 R2）；
 *           ② bCutReq 属请求级信号，剪切电磁阀驱动须在上层输出映射层
 *             复加安全联锁（与急停链 FB_DL_EmergencyStopChainDiag 合取）；
 *           ③ 多刀位并行时每刀独立实例，主轴位置引脚共享即可。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_FlyingSawSyncSeq
VAR_INPUT
    bEn        : BOOL := FALSE;        // 使能（FALSE 冻结回怠速）/ Enable, FALSE freezes to idle
    bStart     : BOOL := FALSE;        // 单周期启动沿输入 / One-cycle start trigger input
    fMasterPos : LREAL := 0.0;         // 同步轴位置 [mm]，序列时钟 / Master axis position [mm], the sequence clock
    fSyncLen   : LREAL := 100.0;       // 同步窗长度（切入=返回对称）[mm] / Sync window length, ramp-in equals ramp-out [mm]
    fCutLen    : LREAL := 20.0;        // 切割窗口长度（速比 1 区间）[mm] / Cutting window length at ratio 1 [mm]
END_VAR
VAR_OUTPUT
    bKnifeRun  : BOOL;                 // 刀轴运行使能输出 / Knife axis run enable output
    fRatio     : LREAL;                // 主从速比 [1]，刀速 = 主速 × 本值 / Master-to-knife velocity ratio [1]
    bCutReq    : BOOL;                 // 切割请求（速比 1 窗口内）[—] / Cut request inside the ratio-1 window
    bCycleDone : BOOL;                 // 单拍完成脉冲（本拍有效）[—] / Single-scan cycle-done pulse
    eState     : E_DL_FlyingSawState;  // 序列当前相位 / Current sequence phase
    uErrCode   : UDINT;                // 信息级码，0 = 无信息 / Info-level code, 0 = none
    bValid     : BOOL;                 // 输出有效标志（非有限拍为 FALSE）/ Outputs usable flag
END_VAR
VAR
    trigStart  : R_TRIG;               // 启动沿检测，每拍无条件刷新 / Start edge detector, refreshed every scan
    fAnchor    : LREAL;                // 切割锚点 [mm]，启动沿锁存为前方未来点（当前位置 + fSyncLen）/ Cut anchor [mm], latched ahead of the master (current position + fSyncLen)
    fLastPos   : LREAL;                // 主轴位置上拍快照 [mm]，防倒退闸用 / Master position last-scan snapshot [mm], reversal guard
    bEnEff     : BOOL;                 // 防御闸后的有效使能 / Effective enable after the defense gate
    _bDone     : BOOL;                 // 完成脉冲内部暂存（统一出口映射） / Done pulse internal stage, mapped at the unified outlet
END_VAR
VAR CONSTANT
    DL_FS_EPS  : LREAL := 1.0E-9;      // 浮点容差（窗长下限闸）[mm] / Float tolerance, window length floor [mm]
    DL_FS_INF  : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR

// ---- 段 1｜沿实例无条件刷新 + 单拍脉冲出口（两段式：置位在 CASE，映射在此）----
trigStart(CLK := bStart);              // 启动沿每拍刷新 / Start edge refreshed unconditionally
_bDone := FALSE;                       // 完成脉冲暂存先清零 / Done stage preset FALSE
bCutReq := FALSE;                      // 切割请求默认 FALSE（切割相内重置位）/ Cut request preset FALSE, re-raised in the cutting phase

// ---- 段 2｜输入防御与参数闸：非有限或参数退化 → 安全侧拒绝（信息级）----
IF (fMasterPos <> fMasterPos) OR (ABS(fMasterPos) > DL_FS_INF)
   OR (fSyncLen <> fSyncLen) OR (ABS(fSyncLen) > DL_FS_INF)
   OR (fCutLen <> fCutLen) OR (ABS(fCutLen) > DL_FS_INF) THEN
    bEnEff   := FALSE;                 // 非有限输入冻结使能 / Non-finite input freezes the enable
    eState   := eIdle;                 // 序列强制回怠速（安全侧）/ Sequence forced back to idle, safe side
    fAnchor  := 0.0;                   // 锚点清零防残留 / Anchor cleared against stale value
    uErrCode := 16#0004_08C0;          // 信息级：输入非有限 / Info: non-finite input
    bValid   := FALSE;                 // 输出不可用 / Outputs unusable
    RETURN;                            // 结构早退（输出保持确定值）/ early exit with deterministic outputs
END_IF
IF (fSyncLen <= DL_FS_EPS) OR (fCutLen <= DL_FS_EPS) THEN
    bEnEff   := FALSE;                 // 参数退化冻结使能 / Degenerated parameters freeze the enable
    eState   := eIdle;                 // 回怠速并留痕 / Back to idle with the code set
    uErrCode := 16#0004_08C0;          // 信息级：窗长参数非法 / Info: illegal window length
    bValid   := FALSE;                 // 输出不可用 / Outputs unusable
    RETURN;                            // 结构早退 / early exit
END_IF
bEnEff   := bEn;                       // 闸后有效使能 / Effective enable after the gate
uErrCode := 16#0000_0000;              // 信息码先清零 / Info code cleared first
bValid   := TRUE;                      // 防御通过输出可用 / Outputs usable after the gate

// ---- 段 3｜序列状态机（CASE 带 ELSE 非法态兜底；速比统一出口赋值）----
CASE eState OF
    E_DL_FlyingSawState.eIdle:         // 怠速相：等待启动沿
        fRatio := 0.0;                 // 速比零（安全侧）/ Ratio zero, safe side
        IF bEnEff AND trigStart.Q THEN
            fAnchor := fMasterPos + fSyncLen; // 锚点 = 当前位置 + 同步窗长（未来窗，切入区间落在主轴前方，R73）/ Anchor = current position + sync length, future window ahead of the master
            eState  := E_DL_FlyingSawState.eWait; // 进入待同步相 / Enter the waiting phase
        END_IF

    E_DL_FlyingSawState.eWait:         // 待同步相：等主轴进入同步窗
        fRatio := 0.0;                 // 未同步区间速比保持零 / Ratio held zero before the sync window
        IF NOT bEnEff THEN
            eState := E_DL_FlyingSawState.eIdle; // 撤使能中止 / Abort on disable
        ELSIF fMasterPos >= (fAnchor - fSyncLen) THEN
            eState := E_DL_FlyingSawState.eSyncIn; // 进入切入相 / Enter the ramp-in phase
        END_IF

    E_DL_FlyingSawState.eSyncIn:       // 切入相：速比 = 位置进度线性爬升
        fRatio := (fMasterPos - (fAnchor - fSyncLen)) / fSyncLen; // 进度比 [1]，分母已闸 / Progress ratio, denominator gated
        fRatio := MIN(MAX(fRatio, 0.0), 1.0);  // 速比双侧钳位 / Two-sided ratio clamp
        IF NOT bEnEff THEN
            eState := E_DL_FlyingSawState.eIdle;   // 撤使能中止 / Abort on disable
        ELSIF fMasterPos >= fAnchor THEN
            eState := E_DL_FlyingSawState.eCutting; // 到锚点进入切割相 / Reach the anchor, enter cutting
        END_IF

    E_DL_FlyingSawState.eCutting:      // 切割相：速比恒 1，切割请求置位
        fRatio  := 1.0;                // 完全同步 / Fully synchronized
        bCutReq := TRUE;               // 切割窗口声明 / Cut request declared
        IF NOT bEnEff THEN
            eState := E_DL_FlyingSawState.eIdle;   // 撤使能中止 / Abort on disable
        ELSIF fMasterPos >= (fAnchor + fCutLen) THEN
            eState := E_DL_FlyingSawState.eSyncOut; // 出切割窗进入返回相 / Leave the window, enter ramp-out
        END_IF

    E_DL_FlyingSawState.eSyncOut:      // 返回相：速比对称降回 0
        fRatio := 1.0 - (fMasterPos - (fAnchor + fCutLen)) / fSyncLen; // 对称进度比 [1] / Mirrored progress ratio
        fRatio := MIN(MAX(fRatio, 0.0), 1.0);  // 速比双侧钳位 / Two-sided ratio clamp
        IF NOT bEnEff THEN
            eState := E_DL_FlyingSawState.eIdle;   // 撤使能中止 / Abort on disable
        ELSIF fMasterPos >= (fAnchor + fCutLen + fSyncLen) THEN
            eState := E_DL_FlyingSawState.eIdle;   // 序列完成回怠速 / Sequence complete, back to idle
            _bDone := TRUE;                        // 完成脉冲内部置位（出口统一映射） / Done stage set, mapped at the outlet
        END_IF

    ELSE                               // 非法状态兜底（R21：CASE 必带 ELSE）
        eState  := E_DL_FlyingSawState.eIdle;      // 拦截非法值回怠速 / Catch illegal value back to idle
        fRatio  := 0.0;                // 速比归零（安全侧）/ Ratio zeroed, safe side
END_CASE

// ---- 段 4｜防倒退闸：活动相内主轴位置倒退 → 序列中止回怠速（安全侧）----
IF (eState = E_DL_FlyingSawState.eSyncIn)
   OR (eState = E_DL_FlyingSawState.eCutting)
   OR (eState = E_DL_FlyingSawState.eSyncOut) THEN
    IF fMasterPos < (fLastPos - DL_FS_EPS) THEN // 位置倒退超容差判方向反转 / Position regression beyond tolerance, reversal
        eState   := E_DL_FlyingSawState.eIdle;  // 序列中止回怠速 / Sequence aborted to idle
        fRatio   := 0.0;               // 速比归零（安全侧）/ Ratio zeroed, safe side
        uErrCode := 16#0004_08C0;      // 信息级：主轴方向反转中止（复用码 R90）/ Info: reversal abort, code reused
        bValid   := FALSE;             // 本拍输出不可信 / Outputs unusable this scan
    END_IF
END_IF
fLastPos := fMasterPos;                // 位置快照滚存（闸后统一写）/ Snapshot rolled forward after the gate

// ---- 段 5｜统一出口：完成脉冲单拍映射 + 速比安全兜底 ----
bCycleDone := _bDone;                  // 完成脉冲本拍有效 / Done pulse valid this scan
bKnifeRun  := bEn AND (eState <> E_DL_FlyingSawState.eIdle); // 运行使能随相位 / Run enable follows the phase
END_FUNCTION_BLOCK