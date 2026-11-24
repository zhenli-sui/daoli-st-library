(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AlarmShelving
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（ISA-18.2 族深化）
 * 所属子库 (Sublibrary) : DL_Process / AlarmGovernance
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON / R_TRIG
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 报警搁置管理（ISA-18.2 搁置态）
 * 功能一句话 (Summary)  : 限时搁置告警，超时强制恢复，搁置台账计数，与报警管理件正交。
 * 边界与安全 (Boundary) : ①无告警时搁置指令拒绝（台账不增，置码 035D）；
 *                         ②超时强制恢复优先于新搁置指令（同拍仲裁）；
 *                         ③搁置 TON 与指令沿检测无条件周期刷新；
 *                         ④bOut=告警态 AND NOT 搁置态（对下游呈现口径）；
 *                         ⑤超时恢复 bTimeout 为单拍脉冲，下一拍自清。
 * 错误码    : 16#0005_035D 无效搁置指令（无告警时搁置被拒）——信息级（单拍）
 *             16#0005_035E 搁置超时强制恢复——信息级（单拍脉冲）
 * 码位总账  : 16#0005_035D 用 / 16#0005_035E 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_AlarmShelving
VAR_INPUT
    bAlarmActive : BOOL; // 原始告警态输入 / Raw alarm active input
    bShelveCmd   : BOOL; // 搁置指令（上升沿生效）/ Shelve command (rising edge)
    tMaxShelve   : TIME; // 最大搁置时长 [ms] / Maximum shelve duration [ms]
    bRestoreCmd  : BOOL; // 恢复指令（上升沿生效）/ Restore command (rising edge)
END_VAR
VAR_OUTPUT
    bOut         : BOOL; // 对下游呈现的告警态（搁置时 FALSE）/ Alarm state presented downstream
    bShelved     : BOOL; // 当前搁置态 / Currently shelved
    bTimeout     : BOOL; // 超时强制恢复单拍脉冲 / Timeout forced-restore one-shot pulse
    uShelveCount : UDINT; // 搁置台账累计计数 / Shelve ledger total count
    eErr         : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    tonShelve : TON;   // 搁置计时（无条件刷新）/ Shelve timer, unconditional refresh
    rShelve   : R_TRIG; // 搁置指令上升沿（无条件刷新）/ Shelve command edge
    rRestore  : R_TRIG; // 恢复指令上升沿（无条件刷新）/ Restore command edge
    bTimeoutPulse: BOOL; // 超时单拍内部（锁存后下拍清）/ Timeout one-shot internal
END_VAR

// ---------- 无条件周期刷新：沿检测与搁置计时 ----------
rShelve (CLK := bShelveCmd);
rRestore(CLK := bRestoreCmd);
tonShelve(IN := bShelved, PT := tMaxShelve);

// ---------- 周期起点：错误码与超时脉冲先清（单拍生命周期） ----------
eErr := 0;
bTimeout := FALSE;

// ---------- 超时强制恢复：优先于新搁置指令（同拍仲裁） ----------
IF tonShelve.Q THEN
    bShelved := FALSE;                        // 强制恢复 / Forced restore
    bTimeoutPulse := TRUE;                    // 超时脉冲锁存 / Timeout pulse latched
    uShelveCount := uShelveCount + UDINT#1;   // 台账记一次超时 / Ledger counts timeout
END_IF

// ---------- 搁置指令仲裁 ----------
IF rShelve.Q THEN
    IF bAlarmActive AND (NOT bShelved) THEN
        bShelved := TRUE;                     // 有效搁置 / Valid shelve
        uShelveCount := uShelveCount + UDINT#1; // 台账计数加一 / Ledger increment
    ELSE
        eErr := 16#0005_035D;                 // 无效搁置（无告警或已搁置）/ Invalid shelve
    END_IF
END_IF

// ---------- 恢复指令仲裁（人工恢复） ----------
IF rRestore.Q AND bShelved THEN
    bShelved := FALSE;                        // 人工恢复 / Manual restore
END_IF

// ---------- 超时单拍脉冲：置位后下一拍清零（先出后清） ----------
IF bTimeoutPulse THEN
    bTimeout := TRUE;                            // 本拍输出超时脉冲 / Timeout pulse this cycle
    bTimeoutPulse := FALSE;                   // 内部单拍自销 / Internal one-shot self-clear
END_IF

// ---------- 对下游呈现口径：原始告警被搁置时呈现为无告警 ----------
bOut := bAlarmActive AND (NOT bShelved);

END_FUNCTION_BLOCK
