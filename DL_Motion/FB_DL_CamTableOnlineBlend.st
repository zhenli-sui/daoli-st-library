//==============================================================================
// 功能块：FB_DL_CamTableOnlineBlend ｜ 中文名称：凸轮表在线无缝切换（双表交叉渐变）
// 所属子库：DL_Motion ｜ 版本：v1.0.1 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3 第 3 版，零方言）
// 功能描述：两张已运行的凸轮修正源（表 A / 表 B 的位置输出以引脚注入）在线
//           交叉渐变切换：切换令沿触发后，权重 w 以当前稳态值为起点、在
//           tBlend 时长内线性推进到目标值（A→B：0→1；B→A：1→0，双向可逆），
//           输出 fPosOut = (1−w)·fPosA + w·fPosB。相位连续性由权重起点连续
//           天然保证：切换瞬间 w 从稳态值起步，输出无台阶；渐变期两表输出
//           按权重交叉合成，终点严格等于目标表原样输出。
//           职责边界：本件做表级切换；表内逐点修调属 FB_DL_CamDynTrim
//           （属主已判已覆盖，互不替代）。
// 开源溯源 (Origin)：原创实现（t1-6-plcopen 表级切换语义深化，零外部源码行，
//           clean-room 独立编写；与 CamDynTrim 属主分工已在头注释声明）
// 公开接口清单：输入 bEn / bSwCmd / fPosA / fPosB / tBlend；
//               输出 fPosOut / fW / bSwitching / bSwitchDone / eState /
//               uErrCode / bValid
// 单位表：fPosA/fPosB/fPosOut[mm] / fW[1]（无量纲权重）/ tBlend[ms]
// 输入契约：fPosA/fPosB 为两表各自刷新的位置修正输出，须同一主轴位置基准；
//           tBlend 为渐变总时长，只在切换沿采纳（渐变中途改参下沿生效）。
// 输出契约：fPosOut 直接叠加主轴位置给定；fW 供上位机观察切换进度；
//           bSwitchDone 单拍完成脉冲；uErrCode 信息级不锁存；
//           bValid = FALSE 拍输出冻结为上一拍有效合成快照（首拍即非有限、
//           无快照时哨兵 0.0）。
// 错误码表：16#0004_08D0 信息级（切换时长非法拒绝触发、位置源非有限安全侧
//           冻结输出，不置 bError）/ 16#0004_08D1 预留禁用（不得挪用）
// 状态机：E_DL_CamBlendState（本文件唯一定义，全库唯一属主）：
//           eActive = 0 / eBlending = 10
// 边界行为：① tBlend <= 0 或非有限 → 拒绝触发 + 信息码，保持当前表原样；
//           ② 位置源非有限 → 输出冻结上一拍有效快照 _fPosOutLast 直通
//             fPosOut，非法输入不参与任何算术；无快照（首拍即非有限）哨兵
//             0.0 + bValid := FALSE（安全侧，R73 返修）；
//           ③ 权重起点/终点在切换沿单拍锁存，渐变期内不刷新（连续性关键）；
//           ④ w 全程钳 0..1，时长换算用 TIME_TO_LREAL（库内已证可编译口径，R397 弃用 TIME_TO_DWORD 非标准扩展）；
//           ⑤ CASE 带 ELSE 非法态兜底回 eActive；
//           ⑥ TON/R_TRIG 每拍无条件刷新（不入分支，红线 R7）；
//           ⑦ 渐变期内重复切换令被抑制（信息级留痕不打断权重窗，
//             R90 复用码）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 1 · 序 2）
//           v1.0.1 2026-11-23 R73 返修：非有限防御分支改冻结上一拍有效输出
//           快照（新增 _fPosOutLast / _bOutValid，无条件段统一滚存），非法
//           输入不再参与合成算术，NaN/Inf 不直穿输出。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_CamBlendState（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 双表切换相位，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_CamBlendState :
(
    eActive   := 0,    // 稳态：按当前权重直接输出 / Steady state, output by the current weight
    eBlending := 10    // 渐变中：权重向目标值线性推进 / Blending, weight advancing toward the target
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CamTableOnlineBlend
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 * 调用示例: camBlend(bEn := TRUE, bSwCmd := bSwSelB,
 *                    fPosA := camTableA.fCorr, fPosB := camTableB.fCorr,
 *                    tBlend := T#2S);
 *          两表各自独立刷新修正输出后经引脚注入；合成输出
 *          camBlend.fPosOut 直接叠加到主轴位置给定上。
 * 组装说明: ① 两张凸轮表的逐点修调由各自表实例承担（CamDynTrim 属主），
 *             本件只消费两表的输出引脚，不触碰表数据本体；
 *           ② bSwCmd 双向触发：当前权重 < 0.5 判向 B 表渐变，反之判向
 *             A 表，回切无需反向专用引脚；
 *           ③ 切换期间禁止上层同时改 tBlend（时长闸只在触发沿生效，
 *             渐变中途改参将被下一次沿才采纳）；
 *           ④ 位置源非有限时输出冻结上一有效权重合成值并拉低 bValid，
 *             上层应据 bValid 门控下游位置给定的采纳。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_CamTableOnlineBlend
VAR_INPUT
    bEn      : BOOL := FALSE;          // 使能（FALSE 冻结输出并回稳态）/ Enable, FALSE freezes and returns to steady
    bSwCmd   : BOOL := FALSE;          // 切换令沿：双向，触发即向目标表渐变 / Switch command edge, bidirectional, trigger blends toward the target table
    fPosA    : LREAL := 0.0;           // 表 A 位置修正输出 [mm]，引脚注入 / Table A position output [mm], injected via the pin
    fPosB    : LREAL := 0.0;           // 表 B 位置修正输出 [mm]，引脚注入 / Table B position output [mm], injected via the pin
    tBlend   : TIME  := T#1S;          // 渐变时长 [ms]，权窗推进总时长 / Blend duration [ms], total weight window
END_VAR
VAR_OUTPUT
    fPosOut  : LREAL;                  // 交叉合成位置输出 [mm] / Crossfaded position output [mm]
    fW       : LREAL;                  // 当前权重 w [1]，0 = 全 A / 1 = 全 B / Current blend weight [1]
    bSwitching: BOOL;                  // TRUE = 渐变进行中 / TRUE = blending in progress
    bSwitchDone: BOOL;                 // 单拍切换完成脉冲 / Single-scan switch-done pulse
    eState   : E_DL_CamBlendState;     // 切换当前相位 / Current blend phase
    uErrCode : UDINT;                  // 信息级码，0 = 无信息 / Info-level code, 0 = none
    bValid   : BOOL;                   // 输出有效标志 / Outputs usable flag
END_VAR
VAR
    tonBlend : TON;                    // 渐变权窗定时器，每拍无条件刷新 / Blend weight timer, refreshed every scan
    trigSw   : R_TRIG;                 // 切换令沿检测，每拍无条件刷新 / Switch command edge, refreshed every scan
    fWStart  : LREAL;                  // 渐变起点权重 [1]，切换沿锁存 / Start weight [1], latched at the switch edge
    fWEnd    : LREAL;                  // 渐变终点权重 [1]，切换沿锁存 / End weight [1], latched at the switch edge
    _bDone   : BOOL;                   // 完成脉冲内部暂存（统一出口映射） / Done stage internal, mapped at the unified outlet
    _fPosOutLast : LREAL;              // 上一拍有效合成输出快照 [mm]，非有限拍冻结源 / Last valid output snapshot [mm], freeze source on non-finite scans
    _bOutValid   : BOOL;               // 快照有效声明（首个有效拍后置位）/ Snapshot validity flag, set after the first valid scan
END_VAR
VAR CONSTANT
    DL_CB_EPS  : LREAL := 1.0E-9;      // 浮点容差 / Float tolerance
    DL_CB_INF  : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_CB_WMIN : LREAL := 0.0;         // 权重下界 [1]，全 A 表 / Weight floor [1], table A only
    DL_CB_WMAX : LREAL := 1.0;         // 权重上界 [1]，全 B 表 / Weight ceiling [1], table B only
END_VAR

// ---- 段 1｜定时/沿实例无条件刷新 + 单拍脉冲出口预清（红线 R7 + 两段式）----
tonBlend(IN := (eState = E_DL_CamBlendState.eBlending), PT := tBlend); // 权窗计时按态断输入 / Weight timer input per state
trigSw(CLK := bSwCmd);                 // 切换令沿每拍刷新 / Switch edge refreshed unconditionally
_bDone      := FALSE;                  // 完成脉冲暂存先清零 / Done stage preset FALSE
bSwitching  := FALSE;                  // 渐变声明默认 FALSE / Switching flag preset FALSE
bSwitchDone := FALSE;                  // 完成脉冲默认 FALSE（相内重置位）/ Done pulse preset FALSE
uErrCode    := 16#0000_0000;           // 信息码每拍重算（信息级不锁存）/ Info code recomputed, info level never latched
bValid      := TRUE;                   // 可用标志默认 TRUE（防御段可改写）/ Usable flag preset TRUE, defense may overwrite

// ---- 段 2｜输入防御：位置源或时长非有限 → 输出冻结 + 安全侧回稳态 ----
IF (fPosA <> fPosA) OR (ABS(fPosA) > DL_CB_INF)
   OR (fPosB <> fPosB) OR (ABS(fPosB) > DL_CB_INF) THEN
    uErrCode := 16#0004_08D0;          // 信息级：位置源非有限 / Info: non-finite position source
    bValid   := FALSE;                 // 输出不可用 / Outputs unusable
    IF eState <> E_DL_CamBlendState.eActive THEN
        eState := E_DL_CamBlendState.eActive; // 渐变中止回稳态（权重保持当前值）/ Blending aborted, weight held
    END_IF
    IF _bOutValid THEN                 // 已有有效快照 → 冻结直通 / Snapshot available, freeze through
        fPosOut := _fPosOutLast;       // 冻结上一拍有效输出（非法输入不参与算术）/ Freeze the last valid output, invalid input never enters arithmetic
    ELSE
        fPosOut := 0.0;                // 首拍即非有限无快照：哨兵 0.0 / Non-finite on the first scan, sentinel zero
    END_IF
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 3｜状态机（CASE 带 ELSE；权重推进除法先过时长闸）----
CASE eState OF
    E_DL_CamBlendState.eActive:        // 稳态相：按当前权重合成输出
        fPosOut := fW * fPosB + (1.0 - fW) * fPosA; // 交叉合成 [mm] / Crossfade blend [mm]
        IF bEn AND trigSw.Q AND (tBlend > T#0MS) THEN
            IF fW < (0.5 + DL_CB_EPS) THEN // 距 B 更近判目标（中点判决）/ Target table by midpoint decision
                fWStart := fW;             // 起点权重锁存（连续性关键）/ Start weight latched, the continuity key
                fWEnd   := DL_CB_WMAX;     // 目标权重 1（B 表）/ Target weight 1, table B
            ELSE
                fWStart := fW;             // 起点权重锁存 / Start weight latched
                fWEnd   := DL_CB_WMIN;     // 目标权重 0（A 表）/ Target weight 0, table A
            END_IF
            eState := E_DL_CamBlendState.eBlending; // 进入渐变相 / Enter the blending phase
        END_IF

    E_DL_CamBlendState.eBlending:      // 渐变相：权重向目标值线性推进，输出相位连续
        bSwitching := TRUE;            // 渐变进行中声明 / Blending declared
        IF trigSw.Q THEN               // 渐变期内重复切换令抑制（信息级留痕，不打断权重窗）/ Repeated command suppressed, info trace
            uErrCode := 16#0004_08D0;  // 信息级：切换令被抑制（复用码 R90）/ Info: command suppressed, code reused per R90
        END_IF
        IF tBlend > T#0MS THEN         // 时长闸（防除零前置，双保险复检）/ Duration gate, defense in depth
            fW := fWStart + (fWEnd - fWStart)
                  * TIME_TO_LREAL(tonBlend.ET)
                  / TIME_TO_LREAL(tBlend);      // 权重线性推进 [1] / Linear weight advance [1]
        END_IF
        fW := MIN(MAX(fW, DL_CB_WMIN), DL_CB_WMAX); // 权重双侧钳位 / Two-sided weight clamp
        fPosOut := fW * fPosB + (1.0 - fW) * fPosA; // 相位连续合成 [mm] / Phase-continuous blend [mm]
        IF tonBlend.Q THEN
            fW     := fWEnd;           // 权窗到顶强制终点值（防尾差）/ Force the end weight at window end
            eState := E_DL_CamBlendState.eActive; // 渐变完成回稳态 / Blending complete, back to steady
            _bDone := TRUE;            // 完成脉冲内部置位（出口统一映射） / Done stage set for the outlet
        END_IF

    ELSE                               // 非法状态兜底（R21：CASE 必带 ELSE）
        eState  := E_DL_CamBlendState.eActive; // 拦截非法值回稳态 / Catch illegal value back to steady
        fW      := DL_CB_WMIN;         // 权重回 0（A 表侧安全）/ Weight back to 0, table A side
        fPosOut := fPosA;              // 输出回 A 表原样 / Output back to table A as-is
END_CASE

// ---- 段 4｜统一出口：完成脉冲单拍映射 + 撤使能兜底 ----
IF NOT bEn THEN                        // 撤使能兜底（门控挂状态量，非单拍标志）
    IF eState <> E_DL_CamBlendState.eActive THEN
        eState  := E_DL_CamBlendState.eActive; // 回稳态 / Back to steady state
        fW      := DL_CB_WMIN;         // 权重回 0 / Weight back to zero
    END_IF
    fPosOut := fPosA;                  // 撤使能输出回 A 表原样 / Disabled output back to table A
END_IF
bSwitchDone := _bDone;                 // 完成脉冲本拍有效（两段式出口）/ Done pulse valid this scan
_fPosOutLast := fPosOut;               // 快照滚存（到达此处输入必已过有限闸）/ Snapshot rolled forward, the finite gate already passed
_bOutValid   := TRUE;                  // 快照有效声明 / Snapshot declared valid
END_FUNCTION_BLOCK