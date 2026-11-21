(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MachineGuardAudit
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 防护门开启审计与批次锁定：门开上升沿 → 若批次活动中
 *                         则按 Holding 语义锁批次并记审计（计数饱和、操作员留痕）→
 *                         Held；恢复需「门已关 + 人工确认」→ RESUMING 核实 →
 *                         NORMAL。开门超 tMaxOpen → VIOLATION 锁存，需操作员标识
 *                         与复位双条件方可解锁。本件只借用 Holding/Held 语义组织
 *                         状态，不属主、不替代整机 PackML 状态机。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_GuardAuditState / TYPE E_DL_GuardErr /
 *                         FUNCTION_BLOCK FB_DL_MachineGuardAudit
 * 依赖 (Depends)        : 无 DL_ 内部依赖；Standard.library TON/R_TRIG 实例
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         计数饱和保护 + 门信号保守处置 ｜ 枚举成员全部显式赋值 ｜
 *                         TON/R_TRIG 每周期无条件调用（仅输入条件化）｜
 *                         CASE 含 ELSE 兜底（ELSE → VIOLATION 锁存 + 锁批次）｜
 *                         禁用系统时间函数（审计时间戳由调用方另行记录）
 * 错误码表 (Codes)      : 16#0005_042B NORMAL
 *                         16#0005_042C HOLDING（批次已锁）
 *                         16#0005_042D HELD（等待恢复确认）
 *                         16#0005_042E VIOLATION（超时锁存，需权限复位）
 *                         16#0005_042F RESUMING（恢复核实）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 4
 * 验收向量 (Acceptance) : 批次活动中门开 → HOLDING(042C) + bLockBatch → HELD(042D)；
 *                         门关 + bManualConfirm → RESUMING(042F) → NORMAL(042B)；
 *                         开门超 tMaxOpen → VIOLATION(042E)，空 sOperId 复位无效
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GuardAuditState（归属 DL_Process，防护门审计状态）
 *----------------------------------------------------------------------------*)
TYPE E_DL_GuardAuditState :
(
    eNormal    := 0,    // 正常：门关、批次可运行 / Normal, door closed
    eHolding   := 10,   // 保持中：批次锁定并记审计 / Holding, batch locked and audited
    eHeld      := 20,   // 已保持：等门关 + 人工确认 / Held, waiting for close plus confirmation
    eResuming  := 30,   // 恢复核实中 / Resuming, residual verification
    eViolation := 40    // 违规：开门超时锁存，需权限复位 / Violation latched, privileged reset required
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GuardErr（归属 DL_Process，与 FB_DL_MachineGuardAudit 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_GuardErr :
(
    eStNormal   := 16#0005_042B,   // NORMAL / Normal
    eStHolding  := 16#0005_042C,   // HOLDING（批次已锁）/ Holding, batch locked
    eStHeld     := 16#0005_042D,   // HELD（等待恢复确认）/ Held, waiting for confirmation
    eStViolation:= 16#0005_042E,   // VIOLATION（超时锁存）/ Violation latched
    eStResuming := 16#0005_042F    // RESUMING（恢复核实）/ Resuming
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_MachineGuardAudit
 * 调用约定: 每个扫描周期无条件调用一次；审计时间戳由上层按任务时基另行记录。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_MachineGuardAudit
VAR_INPUT
    bGuardOpen    : BOOL;                 // 门开信号（TRUE = 门开）/ Guard open signal, TRUE means open
    bBatchActive  : BOOL;                 // 批次运行中 / Batch running
    sOperId       : STRING(32);           // 操作员标识（审计与复位权限）/ Operator identifier for audit and reset
    tMaxOpen      : TIME := T#300S;       // 最长开门时长 [秒]，默认 300 / Maximum open time [s]
    bManualConfirm: BOOL;                 // 人工确认（恢复核实用）/ Manual confirmation for resuming
    bReset        : BOOL;                 // 违规复位请求（上升沿，需操作员标识）/ Violation reset request, edge
END_VAR
VAR_OUTPUT
    eState        : E_DL_GuardAuditState; // 审计状态机当前状态 / Audit state
    bLockBatch    : BOOL;                 // 批次锁定输出 / Batch lock output
    uOpenCnt      : UDINT;                // 开门次数（审计计数，饱和）/ Door-open count, saturating
    sLastOper     : STRING(32);           // 最近一次审计关联操作员 / Last audited operator
    eErr          : E_DL_GuardErr;        // 错误码 / Error code
END_VAR
VAR
    fbGuardTrig   : R_TRIG;               // 门开上升沿实例（无条件调用）/ Guard-open edge instance
    fbResetTrig   : R_TRIG;               // 复位上升沿实例（无条件调用）/ Reset edge instance
    tonOpen       : TON;                  // 开门时长计时器（无条件调用）/ Door-open duration timer
    bOpenPrev     : BOOL;                 // 上拍门信号快照（保守处置参考）/ Previous door signal snapshot
END_VAR
VAR CONSTANT
    DL_GAD_CNT_SAT : UDINT := 16#FFFF_FFFE;   // 开门计数饱和值 [次] / Open count saturation [pcs]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测/TON 每周期无条件调用（仅输入条件化）：超时用状态判定
 *----------------------------------------------------------------------------*)
fbGuardTrig(CLK := bGuardOpen);                        // 门开沿检测无条件刷新 / guard edge refreshed unconditionally
fbResetTrig(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
tonOpen(IN := bGuardOpen AND ((eState = E_DL_GuardAuditState.eHolding)
                           OR (eState = E_DL_GuardAuditState.eHeld)), PT := tMaxOpen);   // 开门时长计时 / open-duration timing
bOpenPrev := bGuardOpen;                               // 门信号快照推进 / snapshot advanced

(*------------------------------------------------------------------------------
 * 段 2｜违规复位：需操作员标识非空（权限侧要求，空标识一律拒绝）
 *----------------------------------------------------------------------------*)
IF fbResetTrig.Q AND (eState = E_DL_GuardAuditState.eViolation) THEN
    IF sOperId <> '' THEN                              // 标识非空才允许复位 / non-empty operator required
        eState := E_DL_GuardAuditState.eNormal;        // 解锁回正常 / back to normal
        bLockBatch := FALSE;                           // 批次解锁 / batch unlocked
    END_IF
    // 空标识：保持 VIOLATION 锁存（权限复位不在本块裁决）/ empty id keeps the violation latched
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜门开上升沿：批次活动中 → HOLDING（锁批次 + 审计）；否则保守置 Held
 *----------------------------------------------------------------------------*)
IF fbGuardTrig.Q THEN
    IF uOpenCnt < DL_GAD_CNT_SAT THEN
        uOpenCnt := uOpenCnt + 1;                      // 开门次数饱和自增 [次] / saturating open count
    END_IF
    sLastOper := sOperId;                              // 审计操作员留痕 / operator audited
    IF bBatchActive THEN
        eState := E_DL_GuardAuditState.eHolding;       // 批次活动：HOLDING / batch active: holding
        bLockBatch := TRUE;                            // 锁批次 / batch locked
    ELSE
        eState := E_DL_GuardAuditState.eHeld;          // 无批次：直接 Held（无需锁）/ no batch: held directly
        bLockBatch := TRUE;                            // 保守侧仍锁批次（防误运行）/ conservatively locked
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜审计状态机：CASE 含 ELSE 兜底（ELSE → VIOLATION 锁存）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_GuardAuditState.eNormal:
        bLockBatch := FALSE;                           // 正常：批次不锁 / batch unlocked
        eErr := E_DL_GuardErr.eStNormal;               // 码 042B / code normal

    E_DL_GuardAuditState.eHolding:
        bLockBatch := TRUE;                            // 保持中：批次锁 / batch locked
        eErr := E_DL_GuardErr.eStHolding;              // 码 042C / code holding
        eState := E_DL_GuardAuditState.eHeld;          // 审计记录完成：进 Held / audit recorded, enter held

    E_DL_GuardAuditState.eHeld:
        bLockBatch := TRUE;                            // 已保持：批次锁 / batch locked
        eErr := E_DL_GuardErr.eStHeld;                 // 码 042D / code held
        IF (NOT bGuardOpen) AND bManualConfirm THEN
            eState := E_DL_GuardAuditState.eResuming;  // 门关 + 人工确认：进核实 / closed plus confirmed: resuming
        ELSIF tonOpen.Q THEN
            eState := E_DL_GuardAuditState.eViolation; // 开门超时：违规锁存 / open timeout: violation latch
            bLockBatch := TRUE;                        // 违规：批次锁保持 / lock held
        END_IF

    E_DL_GuardAuditState.eResuming:
        bLockBatch := TRUE;                            // 核实中：批次锁保持（未核实不放行）/ lock held while verifying
        eErr := E_DL_GuardErr.eStResuming;             // 码 042F / code resuming
        IF (NOT bGuardOpen) AND bManualConfirm THEN
            eState := E_DL_GuardAuditState.eNormal;    // 核实通过（无残留）：回正常 / verified: back to normal
            bLockBatch := FALSE;                       // 批次解锁 / batch unlocked
        ELSIF tonOpen.Q THEN
            eState := E_DL_GuardAuditState.eViolation; // 核实期开门超时：违规锁存 / timeout while verifying: violation
        END_IF

    E_DL_GuardAuditState.eViolation:
        bLockBatch := TRUE;                            // 违规：批次锁保持（需权限复位）/ lock held, privileged reset only
        eErr := E_DL_GuardErr.eStViolation;            // 码 042E / code violation

    ELSE
        eState := E_DL_GuardAuditState.eViolation;     // 非法状态兜底：按违规锁存（保守侧）/ illegal-state fallback to violation
        bLockBatch := TRUE;                            // 批次锁保持 / lock held
        eErr := E_DL_GuardErr.eStViolation;            // 兜底码（违规段，反证句：输出同为锁批次+锁存）/ fallback code

END_CASE
END_FUNCTION_BLOCK
