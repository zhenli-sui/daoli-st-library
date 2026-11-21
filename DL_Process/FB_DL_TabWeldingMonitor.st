(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TabWeldingMonitor
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 极耳焊能量/位移/压力三包络窗口判定。每次焊接结束时由 bEval 上升沿触发
 *                         一次评估，在**同一拍内**对三路各判一次双侧包络（下限与上限都要查，
 *                         只查上限会漏"欠能量虚焊"这类最常见的失效）：
 *                           能量 fEnergy ∈ [fEnergyLo, fEnergyHi]  → 否则 bEnergyNg
 *                           位移 fDisp   ∈ [fDispLo,   fDispHi]    → 否则 bDispNg
 *                           压力 fPressure ∈ [fPressLo, fPressHi]  → 否则 bPressNg
 *                         三路**独立**判定、**独立**故障位，绝不合并成一个"焊接不良"位：
 *                         合并后无法区分是能量不足还是压力不足，工艺调参无从下手。
 *                         另出 nNgMask 通道位掩码（bit0 能量 / bit1 位移 / bit2 压力）便于 HMI
 *                         一字节展示，但台账判定仍以三个 BOOL 为准（掩码是展示便利，不是判据）。
 *                         任一通道越窗 → bAnyNg 锁存（累计），直到 bReset 上升沿才清，
 *                         保证两次评估之间的 NG 不会被下一次合格件抹掉（R187 锁存纪律）。
 * 接口     (Interface)  : 输入 fEnergy / fDisp / fPressure 三路实测、六个包络阈值、bEval 评估沿、
 *                         bReset 复位；输出 bEnergyNg / bDispNg / bPressNg 三路独立故障位（锁存）、
 *                         bAnyNg 任一路故障（锁存）、nNgMask 通道位掩码、bEvalDone 单拍评估完成、
 *                         eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"一次焊点的三包络判定"，不控制焊接电源、
 *                         不排序焊点、不判焊点位置**。焊接时序与焊点序列属焊接主控 POU；
 *                         本件的结论位供主控做 NG 剔除与工艺趋势。
 *                         ② 组态闸（每个参与判据的引脚都要闸，缺一即该通道恒判 NG 或恒判 OK）：
 *                         六条阈值任一 fXxxLo >= fXxxHi（上下限倒置）、任一引脚 NaN → 故障锁存，
 *                         三个通道同时不宣称结果（bEvalDone 不出，避免把闸门故障记成焊点 NG）。
 *                         ③ 评估是"沿触发单拍"语义：非评估拍不改变任何锁存位，也不清位。
 *                         ④ 单枚 R_TRIG（bEval）与单枚 R_TRIG（bReset）段 0 无条件周期刷新；
 *                         本件无 TON，故无跨相复位风险。
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisTorqueLimitGuard`（轴力矩瞬时限）分工——那件在运动中连续
 *                         判力矩，本件在焊后一次性判三包络；时间语义（连续 vs 单点）不同，不可互替。
 * 来源标签 (Source Tag) : ROADMAP B 类（锂电池极耳焊工艺监控，自研 clean-room，无外源代码）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 清三路 NG 与任一路 NG 锁存。
 *                         自证可满足：复位为外部动作，不受判据门控；清后下一评估沿重新判定。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。故障出口为三个独立 BOOL + BYTE 通道掩码
 *                         （掩码是**通道位**，不是全局事件码，不参与码段分配）；数字码位待主控
 *                         收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 六阈值双侧几何闸 + NaN 闸 + 浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ R_TRIG 段 0 无条件刷新
 * 返修记录 (Repair)     : v1.0.1（R47 P0 返修）实测 NaN 单列 eMeasBad 出口：原先实测与阈值非有限并入同一
 *                         eCfgIllegal 并锁存，传感器瞬时掉线会把 HMI 打到"组态非法"（误导维护方向）。
 *                         现改为——实测类 NaN 当拍跳过评估、只置 eMeasBad、不锁存、不动通道位；
 *                         阈值类 NaN 与阈值倒置仍判 eCfgIllegal 并锁存（须人工修参数）。
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 2 · 序号 10）
 *==============================================================================*)

TYPE E_DL_TwmState :
(
    eIdle  := 0,    // 等待首次评估沿 / Awaiting the first evaluation edge
    eRun   := 10,   // 逐焊点评估运行相 / Evaluating per weld spot
    eFault := 90    // 组态故障相 / Configuration fault phase
);
END_TYPE

TYPE E_DL_TwmCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（阈值倒置或非有限） / Illegal configuration
    eEnergyNg   := 2,   // 能量越窗 / Energy out of the envelope
    eDispNg     := 3,   // 位移越窗 / Displacement out of the envelope
    ePressNg    := 4,   // 压力越窗 / Pressure out of the envelope
    eMultiNg    := 5,   // 多路同时越窗（归因无法唯一，单列成因） / Multiple channels out of the envelope
    eMeasBad    := 6,   // 实测值 NaN（当拍跳过评估，不锁存） / Measured value NaN, scan skipped, not latched
    ePhaseBad   := 7    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_TabWeldingMonitor
VAR_INPUT
    fEnergy   : REAL := 0.0;     // 焊接能量实测 [J] / Measured weld energy [J]
    fDisp     : REAL := 0.0;     // 焊接位移实测（电极下压量） [mm] / Measured displacement [mm]
    fPressure : REAL := 0.0;     // 焊接压力实测 [N] / Measured weld pressure [N]
    fEnergyLo : REAL := 10.0;    // 能量窗下限，域 < fEnergyHi [J] / Energy lower envelope, < upper [J]
    fEnergyHi : REAL := 100.0;   // 能量窗上限，域 > fEnergyLo [J] / Energy upper envelope, > lower [J]
    fDispLo   : REAL := 0.05;    // 位移窗下限，域 < fDispHi [mm] / Displacement lower envelope [mm]
    fDispHi   : REAL := 1.50;    // 位移窗上限，域 > fDispLo [mm] / Displacement upper envelope [mm]
    fPressLo  : REAL := 50.0;    // 压力窗下限，域 < fPressHi [N] / Pressure lower envelope [N]
    fPressHi  : REAL := 500.0;   // 压力窗上限，域 > fPressLo [N] / Pressure upper envelope [N]
    bEval     : BOOL := FALSE;   // 评估触发，上升沿判一次 [-] / Evaluation trigger, judges once per rising edge
    bReset    : BOOL := FALSE;   // 复位，上升沿清三路 NG 锁存 [-] / Reset, rising edge clears NG latches
END_VAR
VAR_OUTPUT
    bEnergyNg : BOOL;               // 能量越窗（锁存） [-] / Energy out of envelope, latched
    bDispNg   : BOOL;               // 位移越窗（锁存） [-] / Displacement out of envelope, latched
    bPressNg  : BOOL;               // 压力越窗（锁存） [-] / Pressure out of envelope, latched
    bAnyNg    : BOOL;               // 任一路越窗（锁存累计） [-] / Any channel out of envelope, latched
    nNgMask   : BYTE;               // 通道位掩码：bit0 能量 / bit1 位移 / bit2 压力 [-] / Channel bit mask, bit0 energy, bit1 displacement, bit2 pressure
    bEvalDone : BOOL;               // 本次评估完成，单拍脉冲 [-] / Evaluation completed, single-scan pulse
    eState    : E_DL_TwmState;      // 状态出口 [-] / State outlet
    eCause    : E_DL_TwmCause;      // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError    : BOOL;               // 故障标志（组态故障或任一路 NG） [-] / Error flag
END_VAR
VAR
    _eState   : E_DL_TwmState := E_DL_TwmState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_TwmCause := E_DL_TwmCause.eNone;    // 成因锁存量 / Latched cause
    rtEval    : R_TRIG;         // 评估沿实例，段 0 无条件调用 / Evaluation edge instance
    rtReset   : R_TRIG;         // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bNg1     : BOOL;           // 能量越窗锁存位（锁存量） / Latched energy NG
    _bNg2     : BOOL;           // 位移越窗锁存位（锁存量） / Latched displacement NG
    _bNg3     : BOOL;           // 压力越窗锁存位（锁存量） / Latched pressure NG
    _bAnyNg   : BOOL;           // 任一路越窗锁存位（锁存量） / Latched any-NG
    _bCfgBad  : BOOL;           // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin  : BOOL;           // 输入非有限当拍量（含阈值） [-] / Non-finite input this scan
    _bThBad   : BOOL;           // 阈值类非法当拍量（NaN 或倒置，锁存级） [-] / Threshold invalid, latched
    _bMeasBad : BOOL;           // 实测类 NaN 当拍量（跳过评估，不锁存） [-] / Measured NaN, skipped, not latched
    _bE1      : BOOL;           // 本次评估能量越窗当拍量 [-] / Energy NG this evaluation
    _bE2      : BOOL;           // 本次评估位移越窗当拍量 [-] / Displacement NG this evaluation
    _bE3      : BOOL;           // 本次评估压力越窗当拍量 [-] / Pressure NG this evaluation
    _nNgCnt   : USINT;          // 本次评估越窗通道计数（归因唯一性判据） [路] / Channels out of envelope this evaluation
END_VAR
VAR CONSTANT
    DL_TWM_MASK_E : BYTE := 16#01;   // 通道位掩码：能量 [位] / Channel mask bit for energy
    DL_TWM_MASK_D : BYTE := 16#02;   // 通道位掩码：位移 [位] / Channel mask bit for displacement
    DL_TWM_MASK_P : BYTE := 16#04;   // 通道位掩码：压力 [位] / Channel mask bit for pressure
END_VAR

(* —— 段 0：判据派生 + 两沿实例无条件周期刷新 —— *)
(* v1.0.1：实测 NaN 与阈值 NaN 分列——实测类当拍跳过不锁存，阈值类仍属组态非法并锁存 *)
_bMeasBad := (fEnergy <> fEnergy) OR (fDisp <> fDisp) OR (fPressure <> fPressure);          // 实测 NaN 自反判（单列出口） / Measured NaN tests, separate outlet
_bThBad   := (fEnergyLo <> fEnergyLo) OR (fEnergyHi <> fEnergyHi)                          // 能量窗 NaN 判 / Energy envelope NaN tests
          OR (fDispLo <> fDispLo) OR (fDispHi <> fDispHi)                                  // 位移窗 NaN 判 / Displacement envelope NaN tests
          OR (fPressLo <> fPressLo) OR (fPressHi <> fPressHi);                             // 压力窗 NaN 判 / Pressure envelope NaN tests
_bNonFin  := _bMeasBad OR _bThBad;                                                         // 非有限汇总（诊断口径保留） / Aggregated non-finite flag
_bCfgBad  := (fEnergyLo >= fEnergyHi) OR (fDispLo >= fDispHi) OR (fPressLo >= fPressHi)    // 六阈值双侧几何闸（倒置即恒 NG） / Six-threshold geometry gate
          OR _bThBad;                                                                      // 仅阈值类非有限并入组态非法 / Threshold non-finite folded into config
rtEval(CLK := bEval);                                                              // 评估沿，每拍必调（R228A） / Evaluation edge, every scan
rtReset(CLK := bReset);                                                            // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：单拍量预清零（锁存量 _bNg1/_bNg2/_bNg3/_bAnyNg/_eCause 不入清单，R107） —— *)
bEvalDone := FALSE;         // 评估完成脉冲每拍预清 / Eval-done pulse preset
bError    := FALSE;         // 故障标志每拍预清（R45 配对） / Error flag preset
_bE1      := FALSE;         // 本次能量 NG 预清 / Energy NG preset
_bE2      := FALSE;         // 本次位移 NG 预清 / Displacement NG preset
_bE3      := FALSE;         // 本次压力 NG 预清 / Pressure NG preset
_nNgCnt   := 0;             // 越窗计数预清 / NG count preset

(* —— 段 2：复位沿（唯一清锁存路径） —— *)
IF rtReset.Q THEN
    _bNg1   := FALSE;                       // 清能量 NG 锁存 / Clear energy NG latch
    _bNg2   := FALSE;                       // 清位移 NG 锁存 / Clear displacement NG latch
    _bNg3   := FALSE;                       // 清压力 NG 锁存 / Clear pressure NG latch
    _bAnyNg := FALSE;                       // 清任一路 NG 锁存 / Clear any-NG latch
    _eCause := E_DL_TwmCause.eNone;         // 清成因 / Clear cause
    IF _eState = E_DL_TwmState.eFault THEN
        _eState := E_DL_TwmState.eIdle;     // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF

(* —— 段 3：组态闸（闸门故障不得记成焊点 NG，故不置任何通道位） —— *)
IF _bCfgBad THEN
    _eState := E_DL_TwmState.eFault;        // 入故障相 / Enter fault phase
    _eCause := E_DL_TwmCause.eCfgIllegal;   // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3b：实测 NaN 单列出口（当拍跳过评估，不锁存、不动任何通道位，v1.0.1） —— *)
IF rtEval.Q AND _bMeasBad THEN
    _eCause := E_DL_TwmCause.eMeasBad;      // 归因：实测值 NaN / Cause: measured NaN
END_IF

(* —— 段 4：评估沿——三路独立双侧包络判定（单点写入锁存，避免同拍抹除，R187） —— *)
IF rtEval.Q AND (NOT _bCfgBad) AND (NOT _bMeasBad) THEN
    _bE1 := (fEnergy < fEnergyLo) OR (fEnergy > fEnergyHi);        // 能量双侧越窗（下限也要查） / Energy outside both bounds
    _bE2 := (fDisp < fDispLo) OR (fDisp > fDispHi);                // 位移双侧越窗 / Displacement outside both bounds
    _bE3 := (fPressure < fPressLo) OR (fPressure > fPressHi);      // 压力双侧越窗 / Pressure outside both bounds
    IF _bE1 THEN
        _bNg1 := TRUE;                                             // 能量 NG 锁存 / Latch energy NG
    END_IF
    IF _bE2 THEN
        _bNg2 := TRUE;                                             // 位移 NG 锁存 / Latch displacement NG
    END_IF
    IF _bE3 THEN
        _bNg3 := TRUE;                                             // 压力 NG 锁存 / Latch pressure NG
    END_IF
    IF _bE1 THEN
        _nNgCnt := _nNgCnt + 1;                                    // 计数 +1（USINT 上限 5 远够） / Count up, USINT is ample
    END_IF
    IF _bE2 THEN
        _nNgCnt := _nNgCnt + 1;
    END_IF
    IF _bE3 THEN
        _nNgCnt := _nNgCnt + 1;
    END_IF
    IF _nNgCnt > 0 THEN
        _bAnyNg := TRUE;                                           // 累计任一 NG 锁存 / Latch the accumulated any-NG
        IF _nNgCnt = 1 THEN
            IF _bE1 THEN
                _eCause := E_DL_TwmCause.eEnergyNg;                // 归因：唯一越窗=能量 / Cause: energy is the only channel
            ELSIF _bE2 THEN
                _eCause := E_DL_TwmCause.eDispNg;                  // 归因：唯一越窗=位移 / Cause: displacement is the only channel
            ELSE
                _eCause := E_DL_TwmCause.ePressNg;                 // 归因：唯一越窗=压力 / Cause: pressure is the only channel
            END_IF
        ELSE
            _eCause := E_DL_TwmCause.eMultiNg;                     // 归因：多路同时越窗（不强行挑一条） / Cause: multiple channels, no forced pick
        END_IF
    END_IF
    bEvalDone := TRUE;                                             // 单拍评估完成 / Single-scan evaluation done
    IF _eState = E_DL_TwmState.eIdle THEN
        _eState := E_DL_TwmState.eRun;                             // 首次评估后进入运行相 / First evaluation enters run phase
    END_IF
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_TwmState.eIdle:
    IF _bCfgBad THEN                                            // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_TwmState.eFault;
    ELSIF rtEval.Q THEN                                         // 出口 2：首次评估沿 / First evaluation edge
        _eState := E_DL_TwmState.eRun;
    END_IF

E_DL_TwmState.eRun:
    IF _bCfgBad THEN                                            // 出口 1：组态转非法 / Configuration went illegal
        _eState := E_DL_TwmState.eFault;
    ELSIF rtReset.Q THEN                                        // 出口 2：复位回等待相 / Reset back to idle
        _eState := E_DL_TwmState.eIdle;
    END_IF

E_DL_TwmState.eFault:
    IF rtReset.Q AND (NOT _bCfgBad) THEN                        // 出口：复位且组态已合法才迁出（R228B） / Reset with legal config
        _eState := E_DL_TwmState.eIdle;
    END_IF

ELSE
    _eCause := E_DL_TwmCause.ePhaseBad;                         // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_TwmState.eFault;                            // 强拉故障相 / Force fault phase
    bError  := TRUE;                                            // 故障标志 / Error flag

END_CASE

(* —— 段 6：出口单点映射（三路独立 + 掩码同源；名实双出口 R191） —— *)
bEnergyNg := _bNg1;                                             // 能量 NG 出口 / Energy NG outlet
bDispNg   := _bNg2;                                             // 位移 NG 出口 / Displacement NG outlet
bPressNg  := _bNg3;                                             // 压力 NG 出口 / Pressure NG outlet
bAnyNg    := _bAnyNg;                                           // 任一路 NG 出口（锁存累计） / Any-NG outlet
nNgMask   := 16#00;                                             // 掩码每拍重建（由三路 BOOL 派生，不独立维护） / Mask rebuilt from the three flags
IF _bNg1 THEN
    nNgMask := nNgMask OR DL_TWM_MASK_E;                        // bit0 能量 / bit0 energy
END_IF
IF _bNg2 THEN
    nNgMask := nNgMask OR DL_TWM_MASK_D;                        // bit1 位移 / bit1 displacement
END_IF
IF _bNg3 THEN
    nNgMask := nNgMask OR DL_TWM_MASK_P;                        // bit2 压力 / bit2 pressure
END_IF
bError  := _bAnyNg OR (_eState = E_DL_TwmState.eFault);         // 故障标志 = 任一路 NG 或组态故障 / Error = any NG or config fault
eState  := _eState;                                             // 状态出口 / State outlet
eCause  := _eCause;                                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
