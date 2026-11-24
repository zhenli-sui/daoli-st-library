(*
  DL Factory R84 | FB_DL_KilnPreheatStageSeq
  功能：预热器旋风级联投料时序，含各级压差确认、堵料判据与喂料升速
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
TYPE E_DL_KilnPreState :
(
    eIdle := 0, // 空闲待启动 [-] / idle [-]
    eStageCheck := 1, // 各级压差确认相 [-] / stage pressure check phase [-]
    eFeedOn := 2, // 喂料投入相 [-] / feed on phase [-]
    eStableCheck := 3, // 稳定确认相 [-] / stability confirmation phase [-]
    eFeedUp := 4, // 喂料升速相 [-] / feed ramp up phase [-]
    eDone := 5, // 完成相 [-] / done phase [-]
    eFault := 6 // 故障锁存相 [-] / fault latched phase [-]
) := eIdle;
END_TYPE

FUNCTION_BLOCK FB_DL_KilnPreheatStageSeq
VAR_INPUT
    xStart : BOOL; // 级联投料启动命令 [-] / cascade feed start command [-]
    xReset : BOOL; // 复位命令，上升沿清故障码与堵料位 [-] / reset command [-]
    aStageDpKpa : ARRAY[0..3] OF REAL; // 四级旋风筒压差（C1..C4） [kPa] / stage pressure drops C1 to C4 [kPa]
    fDpMinKpa : REAL := 0.3; // 单级最小压差（低于即判断料不畅） [kPa] / minimum stage pressure drop [kPa]
    fDpBlockKpa : REAL := 2.5; // 单级堵料压差阈值 [kPa] / blockage pressure threshold [kPa]
    xFeedReady : BOOL; // 喂料设备就绪反馈 [-] / feed equipment ready feedback [-]
    fFeedTph : REAL; // 当前喂料量 [t/h] / current feed rate [t/h]
    fFeedTargetTph : REAL := 180.0; // 目标喂料量 [t/h] / target feed rate [t/h]
    fFeedOnTph : REAL := 5.0; // 喂料已投入判据下限 [t/h] / feed on detection floor [t/h]
    tCheckLimit : TIME := T#30S; // 压差确认超时 [s] / pressure check timeout [s]
    tStableLimit : TIME := T#120S; // 稳定确认时长 [s] / stability confirmation duration [s]
    tRampLimit : TIME := T#600S; // 升速相超时 [s] / ramp up timeout [s]
    tScan : TIME := T#100MS; // 扫描周期 [s] / scan period [s]
END_VAR
VAR_OUTPUT
    eState : E_DL_KilnPreState; // 当前时序状态 [-] / current sequence state [-]
    iErrCode : INT; // 故障码 0=正常，701~706 [-] / error code, 701 to 706 [code]
    xBlocked : BOOL; // 堵料标志（锁存至复位沿） [-] / blockage flag latched [-]
    xDone : BOOL; // 完成单拍脉冲 [-] / done one-shot pulse [-]
END_VAR
VAR
    rtStart : R_TRIG; // 启动上升沿实例 [-] / start rising edge instance [-]
    rtReset : R_TRIG; // 复位上升沿实例 [-] / reset edge instance [-]
    tonCheck : TON; // 压差确认超时定时器 [-] / pressure check timer [-]
    tonFeed : TON; // 喂料投入超时定时器（独立实例，避免与确认相共计时） [-] / feed on timer, a dedicated instance [-]
    tonStable : TON; // 稳定确认定时器 [-] / stability timer [-]
    tonRamp : TON; // 升速相超时定时器 [-] / ramp timeout timer [-]
    _eState : E_DL_KilnPreState := E_DL_KilnPreState.eIdle; // 内部相位（CASE 唯一写目标） [-] / internal phase [-]
    _iErr : INT; // 故障码内部锁存 [-] / latched error code [-]
    _bBlocked : BOOL; // 堵料内部锁存 [-] / internal blockage latch [-]
    xDoneInt : BOOL; // 完成内部锁存位 [-] / internal done latch [-]
    xDonePrev : BOOL; // 完成前拍快照 [-] / done previous scan snapshot [-]
    i : INT; // 级索引游标（0→3 正向） [-] / stage cursor, forward only [-]
    xDpBad : BOOL; // 压差非有限或越界当拍标志 [-] / pressure bad flag [-]
    xBlockNow : BOOL; // 本拍堵料判据 [-] / blockage verdict of this scan [-]
    fStepTph : REAL; // 本拍升速增量 [t/h] / ramp increment of this scan [t/h]
    fDtSec : REAL; // 扫描周期秒值 [s] / scan period in seconds [s]
END_VAR

// 段 0｜边沿与定时器实例无条件周期刷新（R7）
rtStart(CLK := xStart); // 启动沿每拍必调 [-] / start edge every scan [-]
rtReset(CLK := xReset); // 复位沿每拍必调 [-] / reset edge every scan [-]
tonCheck(IN := _eState = E_DL_KilnPreState.eStageCheck, PT := tCheckLimit); // 确认相独立计时 [-] / check phase timer [-]
tonFeed(IN := _eState = E_DL_KilnPreState.eFeedOn, PT := tCheckLimit); // 喂料相独立计时 [-] / feed on phase timer [-]
tonStable(IN := _eState = E_DL_KilnPreState.eStableCheck, PT := tStableLimit); // 稳定相闸 [-] / stability gate [-]
tonRamp(IN := _eState = E_DL_KilnPreState.eFeedUp, PT := tRampLimit); // 升速相闸 [-] / ramp gate [-]

// 段 1｜四级压差异常与堵料判据（定长数组，正向游标 0→3）
fDtSec := LREAL_TO_REAL(TIME_TO_LREAL(tScan) / 1000.0); // ms ÷ 1000 = s / [ms] / 1000 = [s]
xDpBad := FALSE; // 初值置假 [-] / start false [-]
xBlockNow := FALSE; // 初值置假 [-] / start false [-]
FOR i := 0 TO 3 DO
    IF NOT (aStageDpKpa[i] > -1.0E30 AND aStageDpKpa[i] < 1.0E30) THEN
        xDpBad := TRUE; // 压差非有限（变送器失效） [-] / non finite pressure drop [-]
    ELSIF aStageDpKpa[i] > fDpBlockKpa THEN
        xBlockNow := TRUE; // 单级压差超堵料阈值 [-] / stage pressure above the blockage threshold [-]
    END_IF
END_FOR
IF xBlockNow THEN
    _bBlocked := TRUE; // 堵料锁存（复位沿清） [-] / latch the blockage, cleared on reset [-]
END_IF

// 段 2｜复位沿：清故障码、堵料位与相位（R189）
IF rtReset.Q THEN
    _iErr := 0; // 清故障码 [-] / clear error code [-]
    _bBlocked := FALSE; // 清堵料锁存 [-] / clear the blockage latch [-]
    xDoneInt := FALSE; // 清完成锁存 [-] / clear done latch [-]
    _eState := E_DL_KilnPreState.eIdle; // 回空闲相 [-] / back to idle [-]
END_IF

// 段 3｜主状态机（合法事件优先于超时迁移，R275）
CASE _eState OF
    E_DL_KilnPreState.eIdle: // 空闲相 [-] / idle [-]
        xDoneInt := FALSE; // 空闲清完成锁存 [-] / clear done latch in idle [-]
        IF rtStart.Q THEN
            _eState := E_DL_KilnPreState.eStageCheck; // 启动沿进压差确认相 [-] / start edge enters the check [-]
        END_IF
    E_DL_KilnPreState.eStageCheck: // 各级压差确认相 [-] / stage pressure check [-]
        IF xBlockNow THEN
            _iErr := 701; _eState := E_DL_KilnPreState.eFault; // 投料前已堵料 [-] / blockage before feeding [-]
        ELSIF xDpBad THEN
            _iErr := 702; _eState := E_DL_KilnPreState.eFault; // 压差信号失效 [-] / pressure signal invalid [-]
        ELSIF tonCheck.Q THEN
            _iErr := 703; _eState := E_DL_KilnPreState.eFault; // 压差建立超时（通风不足） [-] / pressure build up timeout [-]
        ELSIF (aStageDpKpa[0] >= fDpMinKpa) AND (aStageDpKpa[1] >= fDpMinKpa) AND (aStageDpKpa[2] >= fDpMinKpa) AND (aStageDpKpa[3] >= fDpMinKpa) THEN
            _eState := E_DL_KilnPreState.eFeedOn; // 各级压差均达标转喂料相 [-] / all stages above the floor leads to feed on [-]
        END_IF
    E_DL_KilnPreState.eFeedOn: // 喂料投入相 [-] / feed on [-]
        IF NOT xFeedReady THEN
            _iErr := 704; _eState := E_DL_KilnPreState.eFault; // 喂料设备未就绪 [-] / feed equipment not ready [-]
        ELSIF xDpBad THEN
            _iErr := 702; _eState := E_DL_KilnPreState.eFault; // 喂料中压差信号失效（R583 补：原仅两相有闸） [-] / pressure signal lost while feeding [-]
        ELSIF xBlockNow THEN
            _iErr := 701; _eState := E_DL_KilnPreState.eFault; // 投料中堵料 [-] / blockage while feeding [-]
        ELSIF fFeedTph >= fFeedOnTph THEN
            _eState := E_DL_KilnPreState.eStableCheck; // 喂料已建立转稳定确认 [-] / feed established leads to stability check [-]
        ELSIF tonFeed.Q THEN
            _iErr := 705; _eState := E_DL_KilnPreState.eFault; // 喂料未建立超时 [-] / feed on timeout [-]
        END_IF
    E_DL_KilnPreState.eStableCheck: // 稳定确认相 [-] / stability check [-]
        IF xBlockNow THEN
            _iErr := 701; _eState := E_DL_KilnPreState.eFault; // 稳定期堵料 [-] / blockage during the stability window [-]
        ELSIF xDpBad THEN
            _iErr := 702; _eState := E_DL_KilnPreState.eFault; // 压差信号失效 [-] / pressure signal invalid [-]
        ELSIF tonStable.Q THEN
            _eState := E_DL_KilnPreState.eFeedUp; // 稳定时长满转升速相 [-] / stable window elapsed leads to ramp up [-]
        END_IF
    E_DL_KilnPreState.eFeedUp: // 喂料升速相 [-] / feed ramp up [-]
        fStepTph := 0.5 * fDtSec; // (t/h)/s × s = t/h（固定 0.5 t/h 每秒升幅） / [t/h] per [s] × [s] = [t/h]
        IF xDpBad THEN
            _iErr := 702; _eState := E_DL_KilnPreState.eFault; // 升速中压差信号失效（R583 补） [-] / pressure signal lost during ramp up [-]
        ELSIF xBlockNow THEN
            _iErr := 701; _eState := E_DL_KilnPreState.eFault; // 升速中堵料（立即停止喂料） [-] / blockage during ramp up [-]
        ELSIF (fFeedTargetTph - fFeedTph) <= fStepTph THEN
            _eState := E_DL_KilnPreState.eDone; // 达目标喂料量转完成相 [-] / target reached leads to done [-]
        ELSIF tonRamp.Q THEN
            _iErr := 705; _eState := E_DL_KilnPreState.eFault; // 升速超时（未达目标） [-] / ramp up timeout [-]
        END_IF
    E_DL_KilnPreState.eDone: // 完成相 [-] / done [-]
        xDoneInt := TRUE; // 置完成锁存（出口统一映射单拍） [-] / raise done latch [-]
        IF NOT xStart THEN
            _eState := E_DL_KilnPreState.eIdle; // 命令撤销回空闲 [-] / command released returns to idle [-]
        END_IF
    E_DL_KilnPreState.eFault: // 故障相：码值锁存回放，仅复位沿出 [-] / fault, exit only on reset [-]
        ; // 锁存回放（R28） [-] / replay the latch only [-]
ELSE
    _iErr := 706; _eState := E_DL_KilnPreState.eFault; // 非法相位兜底 [-] / illegal phase fallback [-]
END_CASE

// 段 4｜出口映射（名实双出口，同源赋值）
eState := _eState; // 状态出口 [-] / state outlet [-]
iErrCode := _iErr; // 故障码出口（锁存值） [-] / error code outlet [-]
xBlocked := _bBlocked; // 堵料位出口（锁存值） [-] / blockage outlet [-]
xDone := xDoneInt AND NOT xDonePrev; // 完成单拍（内部锁存 → 出口映射） [-] / done one-shot [-]
xDonePrev := xDoneInt; // 本拍快照供下拍比较 [-] / snapshot for the next scan [-]
END_FUNCTION_BLOCK
