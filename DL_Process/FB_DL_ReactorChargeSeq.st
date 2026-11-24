(*
  DL Factory R84 | FB_DL_ReactorChargeSeq
  功能：反应釜多组分投料顺序时序，逐相流量累积达标判据与搅拌运行互锁
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
TYPE E_DL_RctChgState :
(
    eIdle := 0, // 空闲待启动 [-] / idle [-]
    eStirCheck := 1, // 搅拌运行确认相 [-] / stirrer check phase [-]
    eChargeA := 2, // A 组分投料相 [-] / component A charging phase [-]
    eChargeB := 3, // B 组分投料相 [-] / component B charging phase [-]
    eChargeC := 4, // C 组分投料相 [-] / component C charging phase [-]
    eHold := 5, // 投料后保持相 [-] / post charge hold phase [-]
    eDone := 6, // 完成相 [-] / done phase [-]
    eFault := 7 // 故障锁存相 [-] / fault latched phase [-]
) := eIdle;
END_TYPE

FUNCTION_BLOCK FB_DL_ReactorChargeSeq
VAR_INPUT
    xStart : BOOL; // 投料启动按钮 [-] / charge start pushbutton [-]
    xReset : BOOL; // 复位按钮，上升沿清故障码与累积量 [-] / reset pushbutton [-]
    xStirRunning : BOOL; // 搅拌运行反馈（投料互锁条件） [-] / stirrer running interlock feedback [-]
    fFlowKgh : REAL; // 当前投料瞬时流量 [kg/h] / instantaneous charge flow [kg/h]
    tScan : TIME := T#50MS; // 扫描周期（累积用） [s] / scan period for accumulation [s]
    aTargetKg : ARRAY[0..2] OF REAL; // A/B/C 三组分目标投料量 [kg] / target mass per component [kg]
    tStirLimit : TIME := T#10S; // 搅拌确认超时 [s] / stirrer check timeout [s]
    tPhaseLimit : TIME := T#600S; // 单组分投料相超时 [s] / per component charge timeout [s]
    tHoldLimit : TIME := T#120S; // 投料后保持时长 [s] / post charge hold duration [s]
END_VAR
VAR_OUTPUT
    eState : E_DL_RctChgState; // 当前时序状态 [-] / current sequence state [-]
    iErrCode : INT; // 故障码 0=正常，501~506 [-] / error code, 501 to 506 [code]
    fChargedKg : REAL; // 本批已投料累计质量 [kg] / total charged mass of this batch [kg]
    xDone : BOOL; // 完成单拍脉冲 [-] / done one-shot pulse [-]
END_VAR
VAR
    rtStart : R_TRIG; // 启动上升沿实例 [-] / start rising edge instance [-]
    rtReset : R_TRIG; // 复位上升沿实例 [-] / reset edge instance [-]
    tonStir : TON; // 搅拌确认超时定时器 [-] / stirrer check timer [-]
    tonPhaseA : TON; // A 组分投料超时定时器（各相独立，R571） [-] / component A charge timer, one per phase [-]
    tonPhaseB : TON; // B 组分投料超时定时器（各相独立，R571） [-] / component B charge timer, one per phase [-]
    tonPhaseC : TON; // C 组分投料超时定时器（各相独立，R571） [-] / component C charge timer, one per phase [-]
    tonHold : TON; // 保持相定时器 [-] / hold phase timer [-]
    _eState : E_DL_RctChgState := E_DL_RctChgState.eIdle; // 内部相位（CASE 唯一写目标） [-] / internal phase [-]
    _iErr : INT; // 故障码内部锁存 [-] / latched error code [-]
    fCharged : REAL; // 累计投料量内部量 [kg] / internal charged mass [kg]
    fPhaseKg : REAL; // 当前组分已投量 [kg] / mass charged in the current phase [kg]
    fDtSec : REAL; // 扫描周期秒值 [s] / scan period in seconds [s]
    fStepKg : REAL; // 本拍投料增量 [kg] / charge increment of this scan [kg]
    xDoneInt : BOOL; // 完成内部锁存位 [-] / internal done latch [-]
    xDonePrev : BOOL; // 完成前拍快照 [-] / done previous scan snapshot [-]
END_VAR

// 段 0｜边沿与定时器实例无条件周期刷新（R7）
rtStart(CLK := xStart); // 启动沿每拍必调 [-] / start edge every scan [-]
rtReset(CLK := xReset); // 复位沿每拍必调 [-] / reset edge every scan [-]
tonStir(IN := _eState = E_DL_RctChgState.eStirCheck, PT := tStirLimit); // 搅拌确认相闸 [-] / stirrer check phase gate [-]
tonPhaseA(IN := _eState = E_DL_RctChgState.eChargeA, PT := tPhaseLimit); // A 相独立计时，离相即复位 [-] / component A timer, reset when the phase leaves [-]
tonPhaseB(IN := _eState = E_DL_RctChgState.eChargeB, PT := tPhaseLimit); // B 相独立计时，离相即复位 [-] / component B timer, reset when the phase leaves [-]
tonPhaseC(IN := _eState = E_DL_RctChgState.eChargeC, PT := tPhaseLimit); // C 相独立计时，离相即复位 [-] / component C timer, reset when the phase leaves [-]
tonHold(IN := _eState = E_DL_RctChgState.eHold, PT := tHoldLimit); // 保持相闸 [-] / hold phase gate [-]

// 段 1｜本拍增量派生（kg/h × s ÷ 3600 = kg）
fDtSec := LREAL_TO_REAL(TIME_TO_LREAL(tScan) / 1000.0); // ms ÷ 1000 = s / [ms] / 1000 = [s]
fStepKg := 0.0; // 增量初值零 [kg] / increment starts at zero [kg]
IF (fFlowKgh > -1.0E30 AND fFlowKgh < 1.0E30) AND fFlowKgh > 0.0 THEN
    fStepKg := (fFlowKgh * fDtSec) / 3600.0; // kg/h × s ÷ 3600 s/h = kg / [kg/h] × [s] / 3600 = [kg]
END_IF

// 段 2｜复位沿：清故障码、累积量与相位（R189）
IF rtReset.Q THEN
    _iErr := 0; // 清故障码 [-] / clear error code [-]
    fCharged := 0.0; // 清本批累计投料 [kg] / clear the batch charge [kg]
    fPhaseKg := 0.0; // 清当前组分累计 [kg] / clear the phase charge [kg]
    xDoneInt := FALSE; // 清完成锁存 [-] / clear done latch [-]
    _eState := E_DL_RctChgState.eIdle; // 回空闲相 [-] / back to idle [-]
END_IF

// 段 3｜主状态机（合法事件优先于超时迁移，R275）
CASE _eState OF
    E_DL_RctChgState.eIdle: // 空闲相 [-] / idle [-]
        xDoneInt := FALSE; // 空闲清完成锁存 [-] / clear done latch in idle [-]
        fCharged := 0.0; // 空闲期累计归零 [kg] / hold the accumulator at zero [kg]
        fPhaseKg := 0.0; // 空闲期组分累计归零 [kg] / hold the phase accumulator at zero [kg]
        IF rtStart.Q THEN
            _eState := E_DL_RctChgState.eStirCheck; // 启动沿先确认搅拌 [-] / start edge checks the stirrer [-]
        END_IF
    E_DL_RctChgState.eStirCheck: // 搅拌确认相（互锁：未运行禁投料） [-] / stirrer check [-]
        IF xStirRunning AND NOT tonStir.Q THEN
            _eState := E_DL_RctChgState.eChargeA; // 搅拌运行转 A 组分 [-] / stirrer running leads to component A [-]
        ELSIF tonStir.Q THEN
            _iErr := 501; _eState := E_DL_RctChgState.eFault; // 搅拌未运行超时（禁投料） [-] / stirrer timeout, charging blocked [-]
        END_IF
    E_DL_RctChgState.eChargeA: // A 组分投料相 [-] / component A [-]
        IF NOT xStirRunning THEN
            _iErr := 502; _eState := E_DL_RctChgState.eFault; // 投料中搅拌停转（互锁断开） [-] / stirrer lost during charging [-]
        ELSIF fPhaseKg >= aTargetKg[0] THEN
            fPhaseKg := 0.0; // 本组分累计清零 [kg] / clear the phase accumulator [kg]
            _eState := E_DL_RctChgState.eChargeB; // A 达标转 B [-] / A reached leads to B [-]
        ELSIF tonPhaseA.Q THEN
            _iErr := 503; _eState := E_DL_RctChgState.eFault; // A 组分投料超时 [-] / component A timeout [-]
        ELSE
            fCharged := fCharged + fStepKg; // kg + kg = kg / [kg] + [kg] = [kg]
            fPhaseKg := fPhaseKg + fStepKg; // kg + kg = kg / [kg] + [kg] = [kg]
        END_IF
    E_DL_RctChgState.eChargeB: // B 组分投料相 [-] / component B [-]
        IF NOT xStirRunning THEN
            _iErr := 502; _eState := E_DL_RctChgState.eFault; // 投料中搅拌停转 [-] / stirrer lost during charging [-]
        ELSIF fPhaseKg >= aTargetKg[1] THEN
            fPhaseKg := 0.0; // 本组分累计清零 [kg] / clear the phase accumulator [kg]
            _eState := E_DL_RctChgState.eChargeC; // B 达标转 C [-] / B reached leads to C [-]
        ELSIF tonPhaseB.Q THEN
            _iErr := 504; _eState := E_DL_RctChgState.eFault; // B 组分投料超时 [-] / component B timeout [-]
        ELSE
            fCharged := fCharged + fStepKg; // kg + kg = kg / [kg] + [kg] = [kg]
            fPhaseKg := fPhaseKg + fStepKg; // kg + kg = kg / [kg] + [kg] = [kg]
        END_IF
    E_DL_RctChgState.eChargeC: // C 组分投料相 [-] / component C [-]
        IF NOT xStirRunning THEN
            _iErr := 502; _eState := E_DL_RctChgState.eFault; // 投料中搅拌停转 [-] / stirrer lost during charging [-]
        ELSIF fPhaseKg >= aTargetKg[2] THEN
            fPhaseKg := 0.0; // 本组分累计清零 [kg] / clear the phase accumulator [kg]
            _eState := E_DL_RctChgState.eHold; // C 达标转保持相 [-] / C reached leads to hold [-]
        ELSIF tonPhaseC.Q THEN
            _iErr := 505; _eState := E_DL_RctChgState.eFault; // C 组分投料超时 [-] / component C timeout [-]
        ELSE
            fCharged := fCharged + fStepKg; // kg + kg = kg / [kg] + [kg] = [kg]
            fPhaseKg := fPhaseKg + fStepKg; // kg + kg = kg / [kg] + [kg] = [kg]
        END_IF
    E_DL_RctChgState.eHold: // 保持相：搅拌必须仍在运行 [-] / hold phase [-]
        IF NOT xStirRunning THEN
            _iErr := 502; _eState := E_DL_RctChgState.eFault; // 保持期搅拌停转 [-] / stirrer lost during hold [-]
        ELSIF tonHold.Q THEN
            _eState := E_DL_RctChgState.eDone; // 保持时长到转完成相 [-] / hold done leads to done [-]
        END_IF
    E_DL_RctChgState.eDone: // 完成相 [-] / done [-]
        xDoneInt := TRUE; // 置完成锁存（出口统一映射单拍） [-] / raise done latch [-]
        IF NOT xStart THEN
            _eState := E_DL_RctChgState.eIdle; // 松开启动即回空闲 [-] / start released returns to idle [-]
        END_IF
    E_DL_RctChgState.eFault: // 故障相：码值锁存回放，仅复位沿出 [-] / fault, exit only on reset [-]
        ; // 锁存回放（R28） [-] / replay the latch only [-]
ELSE
    _iErr := 506; _eState := E_DL_RctChgState.eFault; // 非法相位兜底 [-] / illegal phase fallback [-]
END_CASE

// 段 4｜出口映射（名实双出口，同源赋值）
eState := _eState; // 状态出口 [-] / state outlet [-]
iErrCode := _iErr; // 故障码出口（锁存值） [-] / error code outlet [-]
fChargedKg := fCharged; // 累计投料出口 [kg] / charged mass outlet [kg]
xDone := xDoneInt AND NOT xDonePrev; // 完成单拍（内部锁存 → 出口映射） [-] / done one-shot [-]
xDonePrev := xDoneInt; // 本拍快照供下拍比较 [-] / snapshot for the next scan [-]
END_FUNCTION_BLOCK
