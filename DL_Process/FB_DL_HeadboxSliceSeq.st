(*
  DL Factory R84 | FB_DL_HeadboxSliceSeq
  功能：流浆箱唇口开度调节时序，含开度限位、粗调/精调分级与调节死区
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
TYPE E_DL_HbSliceState :
(
    eIdle := 0, // 空闲待命 [-] / idle [-]
    ePrePos := 1, // 粗定位相 [-] / coarse positioning phase [-]
    eFineAdj := 2, // 精调相 [-] / fine adjustment phase [-]
    eStableCheck := 3, // 稳定确认相 [-] / stability confirmation phase [-]
    eReady := 4, // 就绪相 [-] / ready phase [-]
    eFault := 5 // 故障锁存相 [-] / fault latched phase [-]
) := eIdle;
END_TYPE

FUNCTION_BLOCK FB_DL_HeadboxSliceSeq
VAR_INPUT
    xStart : BOOL; // 唇口调节启动命令 [-] / slice adjustment start command [-]
    xReset : BOOL; // 复位命令，上升沿清故障码 [-] / reset command [-]
    rSliceAct : REAL; // 唇口开度实测值 [mm] / measured slice opening [mm]
    rSliceTarget : REAL := 12.0; // 唇口目标开度 [mm] / target slice opening [mm]
    fPosMinMm : REAL := 5.0; // 开度机械下限 [mm] / mechanical lower limit [mm]
    fPosMaxMm : REAL := 25.0; // 开度机械上限 [mm] / mechanical upper limit [mm]
    fCoarseBandMm : REAL := 0.5; // 粗调转入精调的带宽 [mm] / coarse to fine handover band [mm]
    fDeadbandMm : REAL := 0.05; // 精调调节死区 [mm] / fine adjustment deadband [mm]
    fCoarseStepMm : REAL := 0.20; // 粗调每拍步长 [mm] / coarse step per scan [mm]
    fFineStepMm : REAL := 0.02; // 精调每拍步长 [mm] / fine step per scan [mm]
    tPreLimit : TIME := T#60S; // 粗定位超时 [s] / coarse positioning timeout [s]
    tFineLimit : TIME := T#30S; // 精调超时 [s] / fine adjustment timeout [s]
    tStableLimit : TIME := T#5S; // 稳定确认时长 [s] / stability confirmation duration [s]
END_VAR
VAR_OUTPUT
    eState : E_DL_HbSliceState; // 当前时序状态 [-] / current sequence state [-]
    rSlicePos : REAL; // 唇口开度指令（限位后） [mm] / slice opening command after limiting [mm]
    iErrCode : INT; // 故障码 0=正常，801~805 [-] / error code, 801 to 805 [code]
    xReady : BOOL; // 开度就绪 [-] / opening ready [-]
END_VAR
VAR
    rtStart : R_TRIG; // 启动上升沿实例 [-] / start rising edge instance [-]
    rtReset : R_TRIG; // 复位上升沿实例 [-] / reset edge instance [-]
    tonPre : TON; // 粗定位超时定时器 [-] / coarse positioning timer [-]
    tonFine : TON; // 精调超时定时器 [-] / fine adjustment timer [-]
    tonStable : TON; // 稳定确认定时器 [-] / stability timer [-]
    _eState : E_DL_HbSliceState := E_DL_HbSliceState.eIdle; // 内部相位（CASE 唯一写目标） [-] / internal phase [-]
    _iErr : INT; // 故障码内部锁存 [-] / latched error code [-]
    rPos : REAL; // 开度指令内部量 [mm] / internal opening command [mm]
    rErrMm : REAL; // 开度偏差（目标 − 实测） [mm] / opening error [mm]
    xCfgBad : BOOL; // 组态非法当拍标志 [-] / illegal configuration flag [-]
END_VAR

// 段 0｜边沿与定时器实例无条件周期刷新（R7）
rtStart(CLK := xStart); // 启动沿每拍必调 [-] / start edge every scan [-]
rtReset(CLK := xReset); // 复位沿每拍必调 [-] / reset edge every scan [-]
tonPre(IN := _eState = E_DL_HbSliceState.ePrePos, PT := tPreLimit); // 粗定位相闸 [-] / coarse phase gate [-]
tonFine(IN := _eState = E_DL_HbSliceState.eFineAdj, PT := tFineLimit); // 精调相闸 [-] / fine phase gate [-]
tonStable(IN := _eState = E_DL_HbSliceState.eStableCheck, PT := tStableLimit); // 稳定相闸 [-] / stability phase gate [-]

// 段 1｜组态闸与当拍偏差派生（限位区间/死区/步长必须有效）
xCfgBad := NOT (fPosMinMm < fPosMaxMm) OR NOT (fDeadbandMm > 1.0E-9) OR NOT (fCoarseStepMm > 1.0E-9) OR NOT (fFineStepMm > 1.0E-9); // 限位/死区/步长正域闸（防除零） [mm] / limit, deadband and step gate [mm]
xCfgBad := xCfgBad OR NOT (rSliceAct > -1.0E30 AND rSliceAct < 1.0E30) OR NOT (rSliceTarget > -1.0E30 AND rSliceTarget < 1.0E30); // 开度非有限闸 [-] / non finite opening gate [-]
xCfgBad := xCfgBad OR (rSliceTarget < fPosMinMm) OR (rSliceTarget > fPosMaxMm); // 目标越限闸：不得超出机械限位 [mm] / target outside the mechanical limits [mm]
IF xCfgBad THEN
    _iErr := 801; // 组态非法码 [-] / illegal configuration code [-]
    _eState := E_DL_HbSliceState.eFault; // 锁存迁故障相 [-] / latch into the fault phase [-]
END_IF
rErrMm := rSliceTarget - rSliceAct; // mm − mm = mm / [mm] minus [mm] = [mm]

// 段 2｜复位沿：清故障码与相位（R189）
IF rtReset.Q THEN
    _iErr := 0; // 清故障码 [-] / clear error code [-]
    _eState := E_DL_HbSliceState.eIdle; // 回空闲相 [-] / back to idle [-]
END_IF

// 段 3｜主状态机（合法事件优先于超时迁移，R275）
CASE _eState OF
    E_DL_HbSliceState.eIdle: // 空闲相：指令跟随实测，无扰起步 [-] / idle [-]
        rPos := rSliceAct; // mm 直取 [mm] / take the measurement [mm]
        IF rtStart.Q THEN
            _eState := E_DL_HbSliceState.ePrePos; // 启动沿进粗定位相 [-] / start edge enters coarse positioning [-]
        END_IF
    E_DL_HbSliceState.ePrePos: // 粗定位相：大步长逼近 [-] / coarse positioning [-]
        IF ABS(rErrMm) <= fCoarseBandMm THEN
            _eState := E_DL_HbSliceState.eFineAdj; // 进入粗调带转精调相 [-] / inside the band leads to fine adjustment [-]
        ELSIF tonPre.Q THEN
            _iErr := 802; _eState := E_DL_HbSliceState.eFault; // 粗定位超时（执行机构卡涩） [-] / coarse positioning timeout [-]
        ELSE
            IF rErrMm > 0.0 THEN
                rPos := rPos + fCoarseStepMm; // mm + mm = mm（正向步进） / [mm] + [mm] = [mm]
            ELSE
                rPos := rPos - fCoarseStepMm; // mm − mm = mm（反向步进） / [mm] - [mm] = [mm]
            END_IF
        END_IF
    E_DL_HbSliceState.eFineAdj: // 精调相：小步长收敛至死区 [-] / fine adjustment [-]
        IF ABS(rErrMm) <= fDeadbandMm THEN
            _eState := E_DL_HbSliceState.eStableCheck; // 进死区转稳定确认 [-] / inside the deadband leads to stability check [-]
        ELSIF tonFine.Q THEN
            _iErr := 803; _eState := E_DL_HbSliceState.eFault; // 精调超时（无法收敛） [-] / fine adjustment timeout [-]
        ELSE
            IF rErrMm > 0.0 THEN
                rPos := rPos + fFineStepMm; // mm + mm = mm / [mm] + [mm] = [mm]
            ELSE
                rPos := rPos - fFineStepMm; // mm − mm = mm / [mm] - [mm] = [mm]
            END_IF
        END_IF
    E_DL_HbSliceState.eStableCheck: // 稳定确认相：死区内持续保持 [-] / stability confirmation [-]
        IF ABS(rErrMm) > (2.0 * fDeadbandMm) THEN
            _iErr := 804; _eState := E_DL_HbSliceState.eFault; // 稳定期漂出死区两倍（执行机构打滑） [-] / drifted out of twice the deadband [-]
        ELSIF tonStable.Q THEN
            _eState := E_DL_HbSliceState.eReady; // 稳定时长满转就绪相 [-] / stability elapsed leads to ready [-]
        END_IF
    E_DL_HbSliceState.eReady: // 就绪相 [-] / ready [-]
        IF NOT xStart THEN
            _eState := E_DL_HbSliceState.eIdle; // 命令撤销回空闲 [-] / command released returns to idle [-]
        END_IF
    E_DL_HbSliceState.eFault: // 故障相：码值锁存回放，仅复位沿出 [-] / fault, exit only on reset [-]
        ; // 锁存回放（R28） [-] / replay the latch only [-]
ELSE
    _iErr := 805; _eState := E_DL_HbSliceState.eFault; // 非法相位兜底 [-] / illegal phase fallback [-]
END_CASE

// 段 4｜限位钳位与出口映射（名实双出口，同源赋值）
IF rPos > fPosMaxMm THEN
    rPos := fPosMaxMm; // 上限位钳位 [mm] / clamp at the upper mechanical limit [mm]
END_IF
IF rPos < fPosMinMm THEN
    rPos := fPosMinMm; // 下限位钳位 [mm] / clamp at the lower mechanical limit [mm]
END_IF
eState := _eState; // 状态出口 [-] / state outlet [-]
rSlicePos := rPos; // 开度指令出口（已限位） [mm] / opening command outlet after limiting [mm]
iErrCode := _iErr; // 故障码出口（锁存值） [-] / error code outlet [-]
xReady := _eState = E_DL_HbSliceState.eReady; // 就绪位 = 就绪相镜像 [-] / ready mirrors the ready phase [-]
END_FUNCTION_BLOCK
