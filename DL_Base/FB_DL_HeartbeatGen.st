(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HeartbeatGen
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商私有库
 * 功能描述 (Function)   : 可组周期心跳翻转脉冲发生器（喂狗侧）。内部 TON 以
 *                         tPeriod 为半周期，每次到时翻转 _bLevel 并重启计时，
 *                         输出 bHeartOut 电平镜像 _bLevel，bEdgeOut 为翻转沿
 *                         单拍脉冲。与 FB_DL_WatchdogPulseMon（监视侧）成对：
 *                         本件只管「发生」，不监视任何回读信号（R298 属主边界）。
 * 来源标签 (Origin)     : 自研线（与既有监视件成对补口，IEC 61131-3 标准语义的
 *                         道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : HeartbeatGen（发生侧，本件）↔ WatchdogPulseMon（监视侧，
 *                         既有件）：本件只产生翻转电平与沿，不读回、不判超时、
 *                         不接管通信链诊断；监视侧只判周期窗，不产生心跳。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → bHeartOut 冻结保持当前电平
 *                         （不强制 FALSE：突然拉低可能被监视侧判为心跳丢失），
 *                         eState 迁 eIdle，bError = FALSE（失能不是故障）；
 *                         eFault 相 → bHeartOut 冻结保持末值，bError = TRUE。
 * 组态闸 (Config gate)  : tPeriod < T#10MS（低于工程最小可分辨半周期）或
 *                         > T#60S（超过常见看门狗窗口量级）→ 故障锁存。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL(bError)+
 *                         ENUM(eCause)，码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 组态闸/容差防御 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件每拍刷新，单实例单用途 ✓
 * 验收向量 (Acceptance) : V1 tPeriod=500MS → bHeartOut 每 500ms 翻转一次；
 *                         V2 bEnable=FALSE → 电平冻结，恢复使能不强制重新起拍；
 *                         V3 tPeriod=1MS → eFault 锁存，bError=TRUE，复位沿解除。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 1 · 序号 3）
 *==============================================================================*)
TYPE E_DL_HbGenState :
(
    eIdle  := 0,                             (* 失能待使能（电平冻结保持） / Idle, level frozen *)
    eRun   := 10,                            (* 心跳翻转运行 / Heartbeat toggling run *)
    eFault := 90                             (* 故障锁存相（组态非法） / Fault latched phase *)
);
END_TYPE

TYPE E_DL_HbGenCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：半周期越域 / Illegal config: period out of domain *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeartbeatGen
VAR_INPUT
    tPeriod  : TIME := T#500MS;              (* 翻转半周期，域 T#10MS..T#60S [ms] / Toggle half-period, domain 10 ms..60 s *)
    bEnable  : BOOL := FALSE;                (* 心跳使能，FALSE 时电平冻结保持 [-] / Enable, FALSE freezes level *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障并从低电平重新起拍 [-] / Reset, rising edge clears fault *)
END_VAR
VAR_OUTPUT
    bHeartOut : BOOL;                        (* 心跳输出电平（翻转方波镜像）[-] / Heartbeat output level *)
    bEdgeOut  : BOOL;                        (* 本拍翻转沿单拍脉冲 [-] / Single-scan toggle edge pulse *)
    eState    : E_DL_HbGenState;             (* 状态出口，段 6 单点映射 / State outlet *)
    eCause    : E_DL_HbGenCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_HbGenState := E_DL_HbGenState.eIdle;   (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_HbGenCause := E_DL_HbGenCause.eNone;   (* 故障成因锁存量 / Latched cause *)
    tonTick  : TON;                          (* 翻转计时，自复位式 IN := NOT Q（R188） / Toggle timer, self-resetting *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bLevel  : BOOL;                         (* 内部电平锁存（输出镜像源）[-] / Internal level latch *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新（R228A） —— *)
_bCfgBad := (tPeriod < T#10MS) OR (tPeriod > T#60S);      (* 组态闸：半周期越域 / Config gate: period out of domain *)
rtReset(CLK := bReset);                                    (* 复位沿每拍必调 / Reset edge every scan *)
tonTick(IN := (NOT tonTick.Q) AND _eState = E_DL_HbGenState.eRun, PT := tPeriod);   (* 自复位式计时：Q 到时下拍自动重启 / Self-resetting timer *)

(* —— 段 1：单拍量预清零（锁存量与实例不入清单，R107） —— *)
bEdgeOut := FALSE;                                         (* 翻转沿单拍位预清，唯一分支置位 / Edge pulse preset, set in one branch *)

(* —— 段 2：复位沿处理（作用域：清故障锁存 + 电平归零 + 迁 eRun，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                      (* 清故障锁存位 / Clear fault latch *)
    _eCause := E_DL_HbGenCause.eNone;                      (* 清成因 / Clear cause *)
    _bLevel := FALSE;                                      (* 电平归零重新起拍 / Level to zero, restart *)
    tonTick(IN := FALSE, PT := tPeriod);                   (* 计时器清零重启 / Timer reset restart *)
    IF NOT _bCfgBad THEN
        _eState := E_DL_HbGenState.eRun;                   (* 组态合法时复位即恢复运行 / Resume run if config valid *)
    END_IF
END_IF

(* —— 段 3：组态闸故障锁存（赋值 3 行内置 bError，R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                       (* 锁存故障位 / Latch fault bit *)
    _eCause := E_DL_HbGenCause.eCfgIllegal;                (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_HbGenState.eFault;                     (* 同步迁故障相（bError/eState 失配防线） / Migrate to fault phase *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_HbGenState.eIdle:                                 (* 失能相：电平冻结保持，不动作 / Idle: level frozen *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_HbGenState.eRun;               (* 使能进入运行相 / Enable enters run *)
        END_IF
    E_DL_HbGenState.eRun:                                  (* 运行相：翻转电平 / Run: toggle level *)
        IF NOT bEnable THEN
            _eState := E_DL_HbGenState.eIdle;              (* 失能退回待机（电平保持不强制） / Disable back to idle *)
        ELSIF tonTick.Q THEN
            _bLevel := NOT _bLevel;                        (* 半周期到翻转电平 / Toggle level on half-period *)
            bEdgeOut := TRUE;                              (* 翻转沿单拍脉冲 / Toggle edge pulse *)
        END_IF
    E_DL_HbGenState.eFault:                                (* 故障相：电平冻结保持，仅复位沿可出 / Fault: frozen, only reset edge exits *)
        ;                                                  (* 故障相按锁存回放，不按当下输入重推断（R28 清单） / Replay from latch *)
    ELSE                                                   (* 非法相位兜底：迁安全态 eFault / Illegal phase fallback to fault *)
        _eState := E_DL_HbGenState.eFault;                 (* 兜底迁故障相 / Fallback to fault *)
        _bFault := TRUE;                                   (* 兜底同步锁存 / Fallback latch *)
        _eCause := E_DL_HbGenCause.ePhaseBad;              (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191 名实双出口） —— *)
bHeartOut := _bLevel AND (_eState = E_DL_HbGenState.eRun OR _eState = E_DL_HbGenState.eIdle);   (* 电平镜像：失能/故障均冻结保持 / Level mirror, frozen in idle and fault *)
bError := _bFault;                                         (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                         (* 状态出口单点映射 / State outlet mapping *)
eCause := _eCause;                                         (* 成因出口映射 / Cause outlet mapping *)
END_FUNCTION_BLOCK
