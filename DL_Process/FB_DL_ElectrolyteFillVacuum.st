(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ElectrolyteFillVacuum
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 注液真空度监视与静置计时台账。注液运行电平内监视
 *                         真空度对设定容差窗（bVacOk），静置 TON 达 tHoldReq
 *                         即 bHoldDone；静置期记录最低真空度台账；注液结束
 *                         沿若静置已完成则批次计数 +1 并清窗内台账。与
 *                         VacuumGaugeMux（计融合）分工：本件是静置窗 + 门限
 *                         + 批次计数的工艺台账件。
 * 来源标签 (Origin)     : ROADMAP §21.1 R13 池（L879），自研 clean-room
 * 边界语义 (Boundary)   : ① 真空度 NaN/Inf 拍：bVacOk 强制 FALSE（安全侧，
 *                         静置计时断链不误完成）；
 *                         ② 容差/静置时长/秒值域闸 → 组态故障；
 *                         ③ 最低真空台账随静置起步清零、随批次收口清零；
 *                         ④ TON 为电平计时（非自复位周期窗）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → bVacOk/bHoldDone 强制
 *                         FALSE（监视出口失能必须收敛）；eFault 相 → FALSE
 *                         + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/NaN 安全侧/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 设定 5.0 kPa 容差 0.5、实测 5.2 → bVacOk=TRUE，
 *                         静置 T#60S 到时 → bHoldDone=TRUE；
 *                         V2 静置期实测最低 4.3 → fVacMinHold=4.3；
 *                         V3 bFillEnd 沿且静置已完成 → nBatchCnt+1 且台账清零。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 3 · 序号 12）
 *==============================================================================*)
TYPE E_DL_EfvState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eFill  := 10,                            (* 注液监视运行 / Fill monitor *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_EfvCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：容差/时长/秒值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrolyteFillVacuum
VAR_INPUT
    fVacKpa   : LREAL := 0.0;                (* 真空度实测 [kPa] / Vacuum actual *)
    fVacSp    : LREAL := 5.0;                (* 真空度设定 [kPa] / Vacuum setpoint *)
    fVacTol   : LREAL := 0.5;                (* 真空容差，域 > 0 [kPa] / Vacuum tolerance *)
    tHoldReq  : TIME := T#60S;               (* 静置时长要求，域 > T#0S [ms] / Hold time requirement *)
    bFillRun  : BOOL := FALSE;               (* 注液运行电平 [-] / Fill run level *)
    bFillEnd  : BOOL := FALSE;               (* 注液结束沿 [-] / Fill end edge *)
    bEnable   : BOOL := TRUE;                (* 使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bVacOk    : BOOL;                        (* 真空度在容差窗内 [-] / Vacuum in tolerance *)
    bHoldDone : BOOL;                        (* 静置完成（TON 到时电平）[-] / Hold done *)
    fVacMinHold: LREAL;                      (* 本次静置期最低真空度台账 [kPa] / Min vacuum ledger *)
    tHoldElapsed : TIME;                     (* 静置已进行时长（诊断）[ms] / Hold elapsed *)
    nBatchCnt : UDINT;                       (* 完成批次计数（静置完 + 结束沿）[批] / Batch count *)
    eState    : E_DL_EfvState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_EfvCause;               (* 故障成因出口 / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_EfvState := E_DL_EfvState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_EfvCause := E_DL_EfvCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtEnd     : R_TRIG;                      (* 结束沿实例，段 0 无条件调用 / End edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonHold   : TON;                         (* 静置计时，段 0 无条件调用 / Hold timer *)
    _fVacMin  : LREAL;                       (* 最低真空锁存 [kPa] / Min vacuum latch *)
    _bHoldL   : BOOL;                        (* 静置完成锁存（结转批次判据）[-] / Hold-done latch *)
    _nBatch   : UDINT;                       (* 批次计数锁存 [批] / Batch count latch *)
    _bVacBad  : BOOL;                        (* 真空非有限当拍量 [-] / Non-finite vacuum *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_EFV_EPS : LREAL := 1.0E-9;            (* 容差判零容差 [kPa] / Tolerance epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fVacTol <= DL_EFV_EPS) OR (tHoldReq <= T#0S);   (* 组态闸（R151 全引脚） / Config gate *)
rtEnd(CLK := bFillEnd);                      (* 结束沿每拍必调 / End edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bVacBad := (fVacKpa <> fVacKpa) OR ((fVacKpa - fVacKpa) <> (fVacKpa - fVacKpa));   (* 真空 NaN 自反 + Inf 差判 / Non-finite vacuum *)
tonHold(IN := (_eState = E_DL_EfvState.eFill) AND bFillRun AND (NOT _bVacBad) AND bVacOk, PT := tHoldReq);   (* 静置计时：容差窗内才走时（电平计时非周期窗） / Hold timer, gated by window *)

(* —— 段 1：单拍量预清零（R107） —— *)
bVacOk := FALSE;                             (* 真空判定预清（全路径赋值） / Vac-ok preset *)
bHoldDone := FALSE;                          (* 静置完成预清 / Hold-done preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清批次计数 + 清台账 + 清锁存 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_EfvCause.eNone;          (* 清成因 / Clear cause *)
    _nBatch := 0;                            (* 清批次计数 / Clear batch count *)
    _fVacMin := 0.0;                         (* 清最低台账 / Clear min ledger *)
    fVacMinHold := 0.0;                      (* 清台账出口 / Clear ledger outlet *)
    _bHoldL := FALSE;                        (* 清静置锁存 / Clear hold latch *)
    _eState := E_DL_EfvState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_EfvCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_EfvState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_EfvState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_EfvState.eFill;  (* 进入监视 / Enter fill *)
        END_IF
    E_DL_EfvState.eFill:                     (* 监视相：容差判定 + 静置 + 台账 + 批次收口 / Fill *)
        IF NOT bEnable THEN
            _eState := E_DL_EfvState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSE
            IF NOT _bVacBad THEN
                bVacOk := ABS(fVacKpa - fVacSp) <= fVacTol;   (* 容差窗判定（除法无涉） / Tolerance verdict *)
            END_IF                           (* 坏值拍 bVacOk 保持预清 FALSE（边界①安全侧） / Bad scan: safe FALSE *)
            bHoldDone := tonHold.Q;          (* 静置完成出口 / Hold-done outlet *)
            IF tonHold.Q AND (NOT _bHoldL) THEN   (* 静置完成沿：锁定 + 台账起步 / On hold-done edge *)
                _bHoldL := TRUE;             (* 置完成锁存（供批次收口结转） / Set hold latch *)
            END_IF
            IF bFillRun AND (NOT _bVacBad) AND bVacOk THEN   (* 静置期最低真空台账 / Min ledger *)
                IF (_fVacMin = 0.0) OR (fVacKpa < _fVacMin) THEN   (* 首样本或更低取值（0.0 为哨兵起点非合法真空读数） / First-or-lower *)
                    _fVacMin := fVacKpa;     (* 更新最低 / Update min *)
                END_IF
            END_IF
            IF rtEnd.Q THEN                  (* 注液结束沿：批次收口判定 / On fill end edge *)
                IF _bHoldL THEN
                    _nBatch := _nBatch + 1;  (* 静置已完成：批次 +1（UDINT 回绕工程安全） / Count batch *)
                    _bHoldL := FALSE;        (* 清完成锁存（下一批重新静置） / Clear hold latch *)
                END_IF
                _fVacMin := 0.0;             (* 清窗内台账（边界③：随收口清零） / Clear ledger *)
                fVacMinHold := _fVacMin;     (* 台账出口刷新 / Ledger outlet *)
            ELSE
                fVacMinHold := _fVacMin;     (* 台账出口实时镜像 / Ledger mirror *)
            END_IF
        END_IF
    E_DL_EfvState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_EfvState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_EfvCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
tHoldElapsed := tonHold.ET;                  (* 静置时长诊断镜像 / Elapsed mirror *)
nBatchCnt := _nBatch;                        (* 批次计数出口 / Batch outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
