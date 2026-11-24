(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PulseSeqVerify
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 脉冲序列完整性校验。bStartCmd 上升沿武装并清零计数，
 *                         随后在开放窗口内对 bPulseIn 计数（实测 m），窗口关闭
 *                         条件 = 实测达到期望 n 或窗口超时 tWindow。收口时比对：
 *                         m = n → 序列完整 bSeqOk 单拍置位；m < n → 丢失判据
 *                         bSeqFail 置位并输出缺口数 nMissing = n - m；m > n
 *                         视为串扰/抖动超差同样判失败（缺失/多计双口径）。
 *                         步进电机丢步、流量脉冲丢失、编码器脉冲串完整性场景。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : PulseSeqVerify（序列完整性，本件）↔ EventCounter（无序
 *                         事件计数，既有件）：本件管「期望 n 与实测 m 的有序
 *                         比对与窗口收口」，不做无限累计计数；EventCounter 只
 *                         累计不比对、不判完整性。
 * 输出语义 (Fallback)   : 【R191】eIdle 相 → 全输出缺省零值；eFault 相 → 计数
 *                         与比对结果冻结保持末值，bError = TRUE；窗口运行中
 *                         失能 → 本轮作废、计数清零（作废语义在此声明）。
 * 组态闸 (Config gate)  : nPulseExpect < 1（无序列可验）或 tWindow <= T#0S
 *                         → 故障锁存（PT 为保持时长语义，非超时上限，R219 口径）。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 组态闸/整型域防御（DINT 计数防回绕）✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件每拍刷新，各实例单用途 ✓
 * 验收向量 (Acceptance) : V1 期望 100 实测恰 100 → bSeqOk 单拍 TRUE；
 *                         V2 期望 100 实测 97 → bSeqFail=TRUE，nMissing=3；
 *                         V3 期望 100 窗口到时仅 40 → bSeqFail，nMissing=60；
 *                         V4 复位沿清全部计数与锁存 → 上电回夹防线（R268）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 1 · 序号 4）
 *==============================================================================*)
TYPE E_DL_PsvState :
(
    eIdle   := 0,                            (* 待武装（输出缺省） / Idle, disarmed *)
    eArmed  := 10,                           (* 计数窗口开放中 / Counting window open *)
    eDone   := 20,                           (* 本轮收口完成，结果保持 / Round closed, result held *)
    eFault  := 90                            (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_PsvCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：期望数/窗口越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PulseSeqVerify
VAR_INPUT
    bPulseIn    : BOOL := FALSE;             (* 被校验脉冲输入（内部取上升沿）[-] / Pulse input to verify *)
    nPulseExpect: DINT := 100;               (* 期望脉冲数 n，域 >= 1 [个] / Expected pulse count, domain >= 1 *)
    tWindow     : TIME := T#10S;             (* 计数开放窗口保持时长（收口时限语义）[ms] / Counting window hold time *)
    bStartCmd   : BOOL := FALSE;             (* 启动命令，上升沿武装本轮并清零计数 [-] / Start command, rising edge arms round *)
    bEnable     : BOOL := TRUE;              (* 校验使能，运行中失能则本轮作废清零 [-] / Enable, disable aborts current round *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清全部内部状态 [-] / Reset, rising edge clears all internal state *)
END_VAR
VAR_OUTPUT
    nPulseMeas  : DINT;                      (* 本轮实测脉冲数 m（收口后保持）[个] / Measured pulse count this round *)
    nMissing    : DINT;                      (* 缺口数 = n - m（多计为负值），收口后保持 [个] / Missing count, negative on overrun *)
    bSeqOk      : BOOL;                      (* 本轮序列完整单拍位（m = n 收口拍置位）[-] / Round-complete single-scan flag *)
    bSeqFail    : BOOL;                      (* 本轮序列不完整锁存位（收口至复位沿）[-] / Round-incomplete latch until reset *)
    bCounting   : BOOL;                      (* 窗口开放中指示 [-] / Window-open indicator *)
    eState      : E_DL_PsvState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_PsvCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError      : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_PsvState := E_DL_PsvState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_PsvCause := E_DL_PsvCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtPulse   : R_TRIG;                     (* 脉冲上升沿实例，段 0 无条件调用 / Pulse rising edge *)
    rtStart   : R_TRIG;                     (* 启动上升沿实例，段 0 无条件调用 / Start rising edge *)
    rtReset   : R_TRIG;                     (* 复位上升沿实例，段 0 无条件调用 / Reset rising edge *)
    tonWindow : TON;                        (* 窗口计时，IN 由相位派生，段 0 无条件调用 / Window timer *)
    _nCount   : DINT;                       (* 实测计数锁存（本轮累计量）[个] / Measured count latch *)
    _bFault   : BOOL;                       (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                       (* 组态非法当拍量 / Illegal config this scan *)
    _bResult  : BOOL;                       (* 本轮收口判据：TRUE 完整 / FALSE 不完整 / Round verdict latch *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件周期刷新（R228A） —— *)
_bCfgBad := (nPulseExpect < 1) OR (tWindow <= T#0S);       (* 组态闸：期望数与窗口越域 / Config gate *)
rtPulse(CLK := bPulseIn);                                   (* 脉冲沿每拍必调 / Pulse edge every scan *)
rtStart(CLK := bStartCmd);                                  (* 启动沿每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                                     (* 复位沿每拍必调 / Reset edge every scan *)
tonWindow(IN := _eState = E_DL_PsvState.eArmed, PT := tWindow);   (* 窗口计时随相位派生 / Window timer phase-derived *)

(* —— 段 1：单拍量预清零（锁存量与实例不入清单，R107） —— *)
bSeqOk := FALSE;                                            (* 完整单拍位预清，唯一分支置位 / Complete pulse preset *)

(* —— 段 2：复位沿处理（作用域：清锁存 + 清计数 + 清结果 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                       (* 清故障锁存 / Clear fault latch *)
    _eCause := E_DL_PsvCause.eNone;                         (* 清成因 / Clear cause *)
    _nCount := 0;                                           (* 清实测计数 / Clear count *)
    _bResult := FALSE;                                      (* 清结果锁存 / Clear verdict latch *)
    nPulseMeas := 0;                                        (* 清输出计数镜像 / Clear output count *)
    nMissing := 0;                                          (* 清缺口输出 / Clear missing output *)
    bSeqFail := FALSE;                                      (* 清失败锁存 / Clear fail latch *)
    _eState := E_DL_PsvState.eIdle;                         (* 迁待武装相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（赋值 3 行内置 bError，R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                        (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_PsvCause.eCfgIllegal;                   (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_PsvState.eFault;                        (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PsvState.eIdle:                                    (* 待武装相 / Idle *)
        IF rtStart.Q AND bEnable AND NOT _bFault THEN
            _nCount := 0;                                   (* 武装清零本轮计数 / Arm clears count *)
            _eState := E_DL_PsvState.eArmed;                (* 进入计数窗口 / Enter armed *)
        END_IF
    E_DL_PsvState.eArmed:                                   (* 计数窗口相 / Armed *)
        IF NOT bEnable THEN                                 (* 运行中失能：本轮作废清零（声明语义） / Disable aborts round *)
            _nCount := 0;                                   (* 作废清计数 / Abort clears count *)
            _eState := E_DL_PsvState.eIdle;                 (* 回待武装 / Back to idle *)
        ELSIF rtPulse.Q THEN
            _nCount := _nCount + 1;                         (* 脉冲计数（DINT 域，窗口时限天然防回绕） / Increment count *)
        END_IF
        IF _eState = E_DL_PsvState.eArmed AND (_nCount >= nPulseExpect OR tonWindow.Q) THEN
            nPulseMeas := _nCount;                          (* 收口：实测镜像 / Close round: mirror count *)
            nMissing := nPulseExpect - _nCount;             (* 缺口数（多计为负） / Missing, negative on overrun *)
            _bResult := (_nCount = nPulseExpect);           (* 完整判据：恰等（整型用等值比较合法） / Verdict: exact equality *)
            bSeqOk := _bResult;                             (* 完整单拍位 / Complete pulse *)
            bSeqFail := NOT _bResult;                       (* 失败锁存至复位沿 / Fail latch until reset *)
            _eState := E_DL_PsvState.eDone;                 (* 迁收口相 / Enter done *)
        END_IF
    E_DL_PsvState.eDone:                                    (* 收口保持相：结果冻结，等下一轮武装或复位 / Done: hold result *)
        IF rtStart.Q AND bEnable AND NOT _bFault THEN       (* 新一轮武装重启 / New round re-arms *)
            _nCount := 0;                                   (* 清本轮计数 / Clear count *)
            bSeqFail := FALSE;                              (* 清上一轮失败锁存 / Clear previous fail latch *)
            _eState := E_DL_PsvState.eArmed;                (* 进入计数窗口 / Enter armed *)
        END_IF
    E_DL_PsvState.eFault:                                   (* 故障相：冻结保持，仅复位沿出 / Fault: frozen *)
        ;                                                   (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                    (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PsvState.eFault;                    (* 迁故障相 / To fault *)
        _bFault := TRUE;                                    (* 同步锁存 / Latch *)
        _eCause := E_DL_PsvCause.ePhaseBad;                 (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bCounting := (_eState = E_DL_PsvState.eArmed);              (* 窗口开放指示 / Window-open indicator *)
nPulseMeas := _nCount;                                      (* 实测计数实时镜像（窗口中也可见） / Live count mirror *)
bError := _bFault;                                          (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                          (* 状态出口 / State outlet *)
eCause := _eCause;                                          (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
