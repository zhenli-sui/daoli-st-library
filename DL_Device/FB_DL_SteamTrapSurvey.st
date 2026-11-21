(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SteamTrapSurvey
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / ABS），零厂商私有库
 * 功能描述 (Function)   : 疏水阀温度周期特征普查与失效分级。对单阀（多实例
 *                         部署即跨管网普查）滚动窗（tCycleWin 自复位 TON）内
 *                         累计阀温-环境温差样本，窗到时按平均温差分级：
 *                         >= fDTOpen 判直通泄漏（eLeak）、<= fDTClosed 判
 *                         堵塞冷阀（eBlock）、介于其间健康（eOk）。与
 *                         SteamTrapMonitor/DiagTrend（单阀监测与温差趋势）
 *                         分工：本件是周期窗普查 + 失效分级的语义。
 * 来源标签 (Origin)     : ROADMAP §21.5 R13 池（L920），自研 clean-room
 * 边界语义 (Boundary)   : ① 温度 NaN/Inf 拍拒收（不入累计不推进计数）；
 *                         ② 滚动窗 TON 自复位（IN 带 NOT tonWin.Q，FB33-2），
 *                         窗到时单拍清累计（真滚动窗口径）；
 *                         ③ 分级门限配比约束 fDTOpen > fDTClosed（组态闸）；
 *                         ④ 窗未满最小样本数（nMinSamp）不判级（防短窗误报）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 分级保持末值 + 测量出口
 *                         FALSE（普查监视失能必须收敛）；eFault 相 → 冻结
 *                         + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（计数 eps 闸）/NaN 拒收/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 窗内温差均值 45（fDTOpen=30）→ eHealth=eLeak；
 *                         V2 均值 5（fDTClosed=10）→ eHealth=eBlock；
 *                         V3 均值 20 → eHealth=eOk；V4 窗内样本 < 8 →
 *                         eHealth=eUnknown 不判级。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 3 · 序号 14）
 *==============================================================================*)
TYPE E_DL_StsHealth :
(
    eOk      := 0,                           (* 健康（温差居中带） / Healthy *)
    eLeak    := 1,                           (* 直通泄漏（温差持续高） / Steam leaking *)
    eBlock   := 2,                           (* 堵塞冷阀（温差持续低） / Blocked cold trap *)
    eUnknown := 3                            (* 样本不足未判级 / Insufficient samples *)
);
END_TYPE

TYPE E_DL_StsState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eSurvey:= 10,                            (* 普查运行 / Survey run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_StsCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：窗时/门限/秒值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SteamTrapSurvey
VAR_INPUT
    fTempC     : LREAL := 0.0;               (* 阀体温度 [°C] / Trap body temperature *)
    fAmbC      : LREAL := 25.0;              (* 环境参考温度 [°C] / Ambient reference *)
    tCycleWin  : TIME := T#60S;              (* 普查滚动窗时长，域 > T#0S [ms] / Survey window time *)
    fDTOpen    : LREAL := 30.0;              (* 直通泄漏门限（均值 >= 判泄），域 > fDTClosed [K] / Leak threshold *)
    fDTClosed  : LREAL := 10.0;              (* 堵塞冷阀门限（均值 <= 判堵），域 < fDTOpen [K] / Block threshold *)
    nMinSamp   : INT := 8;                   (* 判级最小样本数，域 1..999 [点] / Min samples for verdict *)
    fScanS     : LREAL := 1.0;               (* 扫描周期秒值，域 > 1E-6 [s] / Scan period seconds *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fDtAvg     : LREAL;                      (* 最近窗平均温差 [K] / Window mean delta-T *)
    eHealth    : E_DL_StsHealth;             (* 失效分级出口（信息级逐窗重算，R189） / Health grade outlet *)
    nSampCnt   : INT;                        (* 最近窗样本数 [点] / Window sample count *)
    bWinTick   : BOOL;                       (* 窗到时单拍脉冲 [-] / Window expiry pulse *)
    eState     : E_DL_StsState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_StsCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_StsState := E_DL_StsState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_StsCause := E_DL_StsCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonWin   : TON;                          (* 普查滚动窗自复位计时，段 0 无条件调用 / Self-resetting survey window *)
    _fDtSum  : LREAL;                        (* 窗内温差累计 [K] / Delta-T window sum *)
    _fDt     : LREAL;                        (* 本拍温差派生量 [K] / Delta-T this scan *)
    _nSamp   : INT;                          (* 窗样本计数 [点] / Window sample count *)
    _nSampMax: INT;                          (* 窗样本计数上限锁存（防 INT 溢出）[点] / Sample cap latch *)
    _fAvg    : LREAL;                        (* 窗均值工作量 [K] / Window mean work *)
    _bTick   : BOOL;                         (* 窗到时单拍量 [-] / Window tick work *)
    _bTempBad: BOOL;                        (* 温度非有限当拍量 [-] / Non-finite temperature *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_STS_EPS  : LREAL := 1.0E-6;           (* 秒值/计数判零容差 [-] / Epsilon *)
    DL_STS_NCAP : INT   := 999;              (* 窗样本计数上限（防 INT 溢出）[点] / Sample cap *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (tCycleWin <= T#0S) OR (fDTOpen <= fDTClosed) OR (nMinSamp < 1) OR (nMinSamp > DL_STS_NCAP)
            OR (fScanS <= DL_STS_EPS);   (* 组态闸（R151 全引脚 + 门限序 R146） / Config gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bTempBad := (fTempC <> fTempC) OR ((fTempC - fTempC) <> (fTempC - fTempC))
            OR (fAmbC <> fAmbC) OR ((fAmbC - fAmbC) <> (fAmbC - fAmbC));   (* 双温度 NaN 自反 + Inf 差判 / Non-finite temperature gates *)
tonWin(IN := (_eState = E_DL_StsState.eSurvey) AND NOT tonWin.Q, PT := tCycleWin);   (* 滚动窗自复位计时（FB33-2） / Self-resetting window *)
_bTick := tonWin.Q;                          (* 窗到时单拍量 / Window tick work *)

(* —— 段 1：单拍量预清零（R107） —— *)
_fDt := 0.0;                                 (* 温差预清（每拍全路径派生，R285） / Delta-T preset *)
_fAvg := 0.0;                                (* 均值预清 / Mean preset *)
bWinTick := FALSE;                           (* 窗到时脉冲预清，唯一分支置位 / Tick preset *)
_nSampMax := DL_STS_NCAP;                    (* 计数上限预置 / Cap preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清窗累计 + 清样本计数 + 清分级出口 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_StsCause.eNone;          (* 清成因 / Clear cause *)
    _fDtSum := 0.0;                          (* 清窗累计 / Clear sum *)
    _nSamp := 0;                             (* 清样本计数 / Clear count *)
    fDtAvg := 0.0;                           (* 清均值出口 / Clear mean outlet *)
    eHealth := E_DL_StsHealth.eUnknown;      (* 分级回未知 / Grade unknown *)
    nSampCnt := 0;                           (* 清样本出口 / Clear count outlet *)
    _eState := E_DL_StsState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_StsCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_StsState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_StsState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault AND NOT _bTempBad THEN
            _eState := E_DL_StsState.eSurvey;   (* 进入普查 / Enter survey *)
        END_IF
    E_DL_StsState.eSurvey:                   (* 普查相：滚动窗累计 + 到时分级 / Survey *)
        IF NOT bEnable THEN
            _eState := E_DL_StsState.eIdle;  (* 失能回待机（分级保持末值，R191 声明） / Back to idle *)
        ELSE
            IF NOT _bTempBad THEN
                _fDt := fTempC - fAmbC;      (* 温差派生（减法无除零） / Delta-T derive *)
                _fDtSum := _fDtSum + _fDt;   (* 窗累计 / Sum into window *)
                IF _nSamp < _nSampMax THEN
                    _nSamp := _nSamp + 1;    (* 样本计数（上限内防 INT 溢出） / Count sample *)
                END_IF
            END_IF                           (* 温度坏值拍：拒收不入累计（边界①） / Bad scan: reject *)
            IF _bTick THEN                   (* 窗到时单拍：分级 + 清窗（滚动窗口径，边界②） / On window tick *)
                bWinTick := TRUE;            (* 窗到时脉冲 / Tick pulse *)
                nSampCnt := _nSamp;          (* 窗样本数出口快照 / Count snapshot *)
                IF _nSamp >= nMinSamp THEN   (* 最小样本闸（边界④） / Min-sample gate *)
                    _fAvg := _fDtSum / INT_TO_LREAL(_nSamp);   (* 窗均值（除子 >= nMinSamp >= 1，无除零） / Window mean *)
                    fDtAvg := _fAvg;         (* 均值出口刷新 / Mean outlet *)
                    IF _fAvg >= fDTOpen THEN
                        eHealth := E_DL_StsHealth.eLeak;   (* 直通泄漏（独立分级，R190） / Leak grade *)
                    ELSIF _fAvg <= fDTClosed THEN
                        eHealth := E_DL_StsHealth.eBlock;  (* 堵塞冷阀（独立分级） / Block grade *)
                    ELSE
                        eHealth := E_DL_StsHealth.eOk;     (* 健康居中带（IF 链 ELSE 兜底，R285） / Healthy *)
                    END_IF
                ELSE
                    eHealth := E_DL_StsHealth.eUnknown;   (* 样本不足未判级 / Unknown *)
                    fDtAvg := 0.0;           (* 未判级均值出口回哨兵 / Mean sentinel *)
                END_IF
                _fDtSum := 0.0;              (* 清窗累计（下一窗起算） / Clear sum *)
                _nSamp := 0;                 (* 清样本计数 / Clear count *)
            END_IF
        END_IF
    E_DL_StsState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_StsState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_StsCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bWinTick := _bTick;                          (* 窗到时脉冲出口 / Tick outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
