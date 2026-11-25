//==============================================================================
// 功能块：FB_DL_HandAutoModeGateBank ｜ 中文名称：手/自动模式权限门组（双钥匙）
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3，零方言）
// 功能描述：2 回路手/自动模式权限门 Bank：模式切换须"双钥匙同时确认"
//           （bKeyA AND bKeyB）+ 模式请求沿，双钥匙缺一拒绝切换（信息级
//           留痕）。模式切换沿经审计计数器（UDINT 饱和不回绕）留痕，供
//           ISA-88/PackML 相语义审计。两回路逻辑同构独立驻留。
// 开源溯源 (Origin)：候选队列 MANUAL（oscatBasic，MIT 许可，
//           https://github.com/tkucic/brOscatLib/blob/main/oscatBasic/MANUAL.st）
//           与 CONTROL_MODE（AixOCAT，MIT 许可，
//           https://github.com/RWTH-EBC/AixOCAT/blob/develop/OSCAT/OSCAT/OSCAT/oscat_basic/Data%20types/CONTROL_MODE.TcDUT）
//           ——手/自动模式选择与模式枚举行为定义参考；原名 MANUAL /
//           CONTROL_MODE → 道莅 FB_DL_HandAutoModeGateBank，clean-room
//           独立重写（双钥匙确认 + 沿审计为道莅增量，零源码行复制）
// 公开接口清单：输入 {bAutoReq1/2, bManReq1/2, bKeyA1/2, bKeyB1/2}；
//               输出 {eMode1/2, bSwitchPulse1/2, uAuditCnt1/2} / uErrCode / bValid
// 错误码表：16#0005_3060 信息级（回路 1 单钥匙拒绝切换，不置 bError）/
//           16#0005_3061 信息级（回路 2 单钥匙拒绝切换，不置 bError）/
//           16#0005_3062 信息级（审计计数饱和不回绕，不置 bError）/
//           16#0005_3063 预留禁用（不得挪用）
// 状态机：E_DL_HaMode（本文件唯一定义，全库唯一属主）：
//           eAuto = 0 / eManual = 1；非法模式值走 CASE ELSE 兜底归 eManual
//           （人工介入侧为安全侧）
// 边界行为：① 双钥匙缺一切换请求沿 → 拒绝 + 信息码（不切换）；
//           ② 切换成功拍发单拍脉冲 bSwitchPulse（两段式出口映射）；
//           ③ 审计计数饱和于 4294967295 不回绕（信息级留痕）；
//           ④ R_TRIG ×8 每拍无条件刷新（不入分支，红线 R7）；
//           ⑤ CASE 带 ELSE 非法模式兜底归 eManual。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 2 · 序 19）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_HaMode（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 手/自动模式，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_HaMode :
(
    eAuto   := 0,   // 自动模式：上层顺控驱动 / Auto mode, driven by the upper sequence
    eManual := 1    // 手动模式：操作员直接驱动 / Manual mode, operator direct drive
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_HandAutoModeGateBank
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_HandAutoModeGateBank
VAR_INPUT
    bAutoReq1 : BOOL := FALSE;         // 回路 1 自动请求（沿触发）/ Loop 1 auto request, edge triggered
    bManReq1  : BOOL := FALSE;         // 回路 1 手动请求（沿触发）/ Loop 1 manual request, edge triggered
    bKeyA1    : BOOL := FALSE;         // 回路 1 钥匙 A（切换期须保持）/ Loop 1 key A, held during switching
    bKeyB1    : BOOL := FALSE;         // 回路 1 钥匙 B（切换期须保持）/ Loop 1 key B, held during switching
    bAutoReq2 : BOOL := FALSE;         // 回路 2 自动请求（沿触发）/ Loop 2 auto request, edge triggered
    bManReq2  : BOOL := FALSE;         // 回路 2 手动请求（沿触发）/ Loop 2 manual request, edge triggered
    bKeyA2    : BOOL := FALSE;         // 回路 2 钥匙 A（切换期须保持）/ Loop 2 key A, held during switching
    bKeyB2    : BOOL := FALSE;         // 回路 2 钥匙 B（切换期须保持）/ Loop 2 key B, held during switching
END_VAR
VAR_OUTPUT
    eMode1    : E_DL_HaMode;           // 回路 1 当前模式 / Loop 1 current mode
    eMode2    : E_DL_HaMode;           // 回路 2 当前模式 / Loop 2 current mode
    bSwitchPulse1 : BOOL;              // 回路 1 单拍切换脉冲 / Loop 1 single-scan switch pulse
    bSwitchPulse2 : BOOL;              // 回路 2 单拍切换脉冲 / Loop 2 single-scan switch pulse
    uAuditCnt1: UDINT;                 // 回路 1 模式切换审计计数 [次] / Loop 1 switch audit count
    uAuditCnt2: UDINT;                 // 回路 2 模式切换审计计数 [次] / Loop 2 switch audit count
    uErrCode  : UDINT;                 // 信息级码，0 = 无信息 / Info-level code, 0 = none
    bValid    : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    trigAuto1 : R_TRIG;                // 回路 1 自动请求沿，每拍无条件刷新 / Loop 1 auto edge, refreshed every scan
    trigMan1  : R_TRIG;                // 回路 1 手动请求沿，每拍无条件刷新 / Loop 1 manual edge, refreshed every scan
    trigAuto2 : R_TRIG;                // 回路 2 自动请求沿，每拍无条件刷新 / Loop 2 auto edge, refreshed every scan
    trigMan2  : R_TRIG;                // 回路 2 手动请求沿，每拍无条件刷新 / Loop 2 manual edge, refreshed every scan
    _bSw1     : BOOL;                  // 回路 1 切换脉冲内部暂存（统一出口映射） / Loop 1 switch stage
    _bSw2     : BOOL;                  // 回路 2 切换脉冲内部暂存（统一出口映射） / Loop 2 switch stage
END_VAR
VAR CONSTANT
    DL_HA_AUDIT_MAX  : UDINT := 4294967295; // 审计计数上限（饱和不回绕）/ Audit count ceiling, saturating
    DL_HA_CODE_KEY1  : UDINT := 16#0005_3060; // 信息级：回路 1 单钥匙拒绝码 / Info code: loop 1 single key refused
    DL_HA_CODE_KEY2  : UDINT := 16#0005_3061; // 信息级：回路 2 单钥匙拒绝码 / Info code: loop 2 single key refused
    DL_HA_CODE_SAT   : UDINT := 16#0005_3062; // 信息级：审计计数饱和码 / Info code: audit count saturated
END_VAR

// ---- 段 1｜沿实例无条件刷新 + 单拍脉冲出口预清（红线 R7 + 两段式）----
trigAuto1(CLK := bAutoReq1);          // 回路 1 自动沿每拍刷新 / Loop 1 auto edge refreshed
trigMan1(CLK := bManReq1);            // 回路 1 手动沿每拍刷新 / Loop 1 manual edge refreshed
trigAuto2(CLK := bAutoReq2);          // 回路 2 自动沿每拍刷新 / Loop 2 auto edge refreshed
trigMan2(CLK := bManReq2);            // 回路 2 手动沿每拍刷新 / Loop 2 manual edge refreshed
_bSw1 := FALSE;                       // 回路 1 切换暂存先清零 / Loop 1 switch stage cleared
_bSw2 := FALSE;                       // 回路 2 切换暂存先清零 / Loop 2 switch stage cleared
uErrCode := 16#0000_0000;             // 信息码每拍重算（信息级不锁存）/ Info code recomputed, never latched

// ---- 段 2｜回路 1 模式状态机（CASE 带 ELSE；双钥匙闸前置）----
CASE eMode1 OF
    E_DL_HaMode.eAuto:                 // 自动相：可切手动（双钥匙闸）
        IF trigMan1.Q THEN             // 手动请求沿
            IF bKeyA1 AND bKeyB1 THEN  // 双钥匙确认闸 / Dual-key gate
                eMode1 := E_DL_HaMode.eManual; // 切手动 / To manual
                _bSw1 := TRUE;         // 切换脉冲内部置位（出口统一映射）/ Switch stage set
                IF uAuditCnt1 < DL_HA_AUDIT_MAX THEN
                    uAuditCnt1 := uAuditCnt1 + 1; // 审计计数推进 / Audit count advance
                ELSE
                    uErrCode := DL_HA_CODE_SAT;   // 审计计数饱和留痕 / Audit saturation trace
                END_IF
            ELSE
                uErrCode := DL_HA_CODE_KEY1; // 单钥匙拒绝留痕（不切换）/ Single-key refusal, no switch
            END_IF
        END_IF
    E_DL_HaMode.eManual:               // 手动相：可切自动（双钥匙闸）
        IF trigAuto1.Q THEN            // 自动请求沿
            IF bKeyA1 AND bKeyB1 THEN  // 双钥匙确认闸 / Dual-key gate
                eMode1 := E_DL_HaMode.eAuto;   // 切自动 / To auto
                _bSw1 := TRUE;         // 切换脉冲内部置位 / Switch stage set
                IF uAuditCnt1 < DL_HA_AUDIT_MAX THEN
                    uAuditCnt1 := uAuditCnt1 + 1; // 审计计数推进 / Audit count advance
                ELSE
                    uErrCode := DL_HA_CODE_SAT;   // 审计计数饱和留痕 / Audit saturation trace
                END_IF
            ELSE
                uErrCode := DL_HA_CODE_KEY1; // 单钥匙拒绝留痕（不切换）/ Single-key refusal, no switch
            END_IF
        END_IF
    ELSE                               // 非法模式兜底（R21：CASE 必带 ELSE）
        eMode1 := E_DL_HaMode.eManual; // 拦截非法值归手动（人工介入侧安全）/ Catch illegal value to manual, safe side
END_CASE

// ---- 段 3｜回路 2 模式状态机（同段 2 口径）----
CASE eMode2 OF
    E_DL_HaMode.eAuto:                 // 自动相：可切手动（双钥匙闸）
        IF trigMan2.Q THEN             // 手动请求沿
            IF bKeyA2 AND bKeyB2 THEN  // 双钥匙确认闸 / Dual-key gate
                eMode2 := E_DL_HaMode.eManual; // 切手动 / To manual
                _bSw2 := TRUE;         // 切换脉冲内部置位 / Switch stage set
                IF uAuditCnt2 < DL_HA_AUDIT_MAX THEN
                    uAuditCnt2 := uAuditCnt2 + 1; // 审计计数推进 / Audit count advance
                ELSE
                    uErrCode := DL_HA_CODE_SAT;   // 审计计数饱和留痕 / Audit saturation trace
                END_IF
            ELSE
                uErrCode := DL_HA_CODE_KEY2; // 单钥匙拒绝留痕（不切换）/ Single-key refusal, no switch
            END_IF
        END_IF
    E_DL_HaMode.eManual:               // 手动相：可切自动（双钥匙闸）
        IF trigAuto2.Q THEN            // 自动请求沿
            IF bKeyA2 AND bKeyB2 THEN  // 双钥匙确认闸 / Dual-key gate
                eMode2 := E_DL_HaMode.eAuto;   // 切自动 / To auto
                _bSw2 := TRUE;         // 切换脉冲内部置位 / Switch stage set
                IF uAuditCnt2 < DL_HA_AUDIT_MAX THEN
                    uAuditCnt2 := uAuditCnt2 + 1; // 审计计数推进 / Audit count advance
                ELSE
                    uErrCode := DL_HA_CODE_SAT;   // 审计计数饱和留痕 / Audit saturation trace
                END_IF
            ELSE
                uErrCode := DL_HA_CODE_KEY2; // 单钥匙拒绝留痕（不切换）/ Single-key refusal, no switch
            END_IF
        END_IF
    ELSE                               // 非法模式兜底（R21：CASE 必带 ELSE）
        eMode2 := E_DL_HaMode.eManual; // 拦截非法值归手动 / Catch illegal value to manual
END_CASE

// ---- 段 4｜统一出口：切换脉冲单拍映射（两段式）----
bSwitchPulse1 := _bSw1;               // 回路 1 切换脉冲本拍有效 / Loop 1 pulse valid this scan
bSwitchPulse2 := _bSw2;               // 回路 2 切换脉冲本拍有效 / Loop 2 pulse valid this scan
bValid := TRUE;                       // 输出恒可用 / Outputs always usable
END_FUNCTION_BLOCK