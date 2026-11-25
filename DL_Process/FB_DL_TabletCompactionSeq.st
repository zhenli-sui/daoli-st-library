(*
  DL Factory R84 | FB_DL_TabletCompactionSeq
  功能：压片七相时序状态机，含预压/主压到位超时、剔废计数与完成脉冲
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
TYPE E_DL_TabCompState :
(
    eIdle := 0, // 空闲待启动 [-] / idle [-]
    eFill := 1, // 充填相 [-] / die filling phase [-]
    ePreComp := 2, // 预压相 [-] / pre compaction phase [-]
    eMainComp := 3, // 主压相 [-] / main compaction phase [-]
    eEject := 4, // 出片相 [-] / ejection phase [-]
    eRejectCheck := 5, // 剔废判定相 [-] / reject check phase [-]
    eDone := 6, // 完成相 [-] / done phase [-]
    eFault := 7 // 故障锁存相 [-] / fault latched phase [-]
) := eIdle;
END_TYPE

FUNCTION_BLOCK FB_DL_TabletCompactionSeq
VAR_INPUT
    xStart : BOOL; // 压片启动按钮 [-] / start pushbutton [-]
    xReset : BOOL; // 复位按钮，上升沿清故障码 [-] / reset pushbutton [-]
    xFillDone : BOOL; // 充填到位反馈 [-] / fill complete feedback [-]
    xPrePressOk : BOOL; // 预压压力到位反馈 [-] / pre compaction pressure reached [-]
    xMainPressOk : BOOL; // 主压压力到位反馈 [-] / main compaction pressure reached [-]
    xEjectDone : BOOL; // 出片到位反馈 [-] / ejection complete feedback [-]
    xPartOk : BOOL; // 剔废检测判定（TRUE=合格） [-] / tablet quality verdict [-]
    tFillLimit : TIME := T#5S; // 充填相超时 [s] / fill phase timeout [s]
    tEjectLimit : TIME := T#5S; // 出片相超时（独立整定，R572） [s] / eject phase timeout, tuned separately [s]
    tPreLimit : TIME := T#3S; // 预压到位超时 [s] / pre compaction timeout [s]
    tMainLimit : TIME := T#5S; // 主压到位超时 [s] / main compaction timeout [s]
END_VAR
VAR_OUTPUT
    eState : E_DL_TabCompState; // 当前时序状态 [-] / current sequence state [-]
    iErrCode : INT; // 故障码 0=正常，401~405 [-] / error code, 401 to 405 [code]
    iRejectCnt : INT; // 剔废累计片数 [片] / rejected tablet counter [tablets]
    xDone : BOOL; // 完成单拍脉冲 [-] / done one-shot pulse [-]
END_VAR
VAR
    rtStart : R_TRIG; // 启动上升沿实例 [-] / start rising edge instance [-]
    rtReset : R_TRIG; // 复位上升沿实例 [-] / reset rising edge instance [-]
    tonFill : TON; // 充填相超时定时器（独立，R572） [-] / fill phase timer, dedicated [-]
    tonEject : TON; // 出片相超时定时器（独立，R572） [-] / eject phase timer, dedicated [-]
    tonPre : TON; // 预压到位超时定时器 [-] / pre compaction timer [-]
    tonMain : TON; // 主压到位超时定时器 [-] / main compaction timer [-]
    _eState : E_DL_TabCompState := E_DL_TabCompState.eIdle; // 内部相位（CASE 唯一写目标） [-] / internal phase [-]
    _iErr : INT; // 故障码内部锁存 [-] / latched error code [-]
    _iRej : INT; // 剔废计数内部量 [片] / internal reject counter [tablets]
    xDoneInt : BOOL; // 完成内部锁存位 [-] / internal done latch [-]
    xDonePrev : BOOL; // 完成前拍快照 [-] / done previous scan snapshot [-]
END_VAR

// 段 0｜边沿与定时器实例无条件周期刷新（R7；相闸串在 IN 上）
rtStart(CLK := xStart); // 启动沿每拍必调 [-] / start edge every scan [-]
rtReset(CLK := xReset); // 复位沿每拍必调 [-] / reset edge every scan [-]
tonFill(IN := _eState = E_DL_TabCompState.eFill, PT := tFillLimit); // 充填相独立闸，离相复位 [-] / fill phase gate, reset when the phase leaves [-]
tonEject(IN := _eState = E_DL_TabCompState.eEject, PT := tEjectLimit); // 出片相独立闸，离相复位 [-] / eject phase gate, reset when the phase leaves [-]
tonPre(IN := _eState = E_DL_TabCompState.ePreComp, PT := tPreLimit); // 预压相闸 [-] / pre compaction phase gate [-]
tonMain(IN := _eState = E_DL_TabCompState.eMainComp, PT := tMainLimit); // 主压相闸 [-] / main compaction phase gate [-]

// 段 1｜复位沿：清故障码与相位（剔废计数属工艺累计量，不随复位清零，R189）
IF rtReset.Q THEN
    _iErr := 0; // 清故障码 [-] / clear error code [-]
    xDoneInt := FALSE; // 清完成锁存 [-] / clear done latch [-]
    _eState := E_DL_TabCompState.eIdle; // 回空闲相 [-] / back to idle [-]
END_IF

// 段 2｜主状态机（合法事件优先于超时迁移，R275）
CASE _eState OF
    E_DL_TabCompState.eIdle: // 空闲相 [-] / idle [-]
        xDoneInt := FALSE; // 空闲清完成锁存 [-] / clear done latch in idle [-]
        IF rtStart.Q THEN
            _eState := E_DL_TabCompState.eFill; // 启动沿进充填相 [-] / start edge enters filling [-]
        END_IF
    E_DL_TabCompState.eFill: // 充填相 [-] / filling [-]
        IF xFillDone AND NOT tonFill.Q THEN
            _eState := E_DL_TabCompState.ePreComp; // 充填到位转预压 [-] / fill done leads to pre compaction [-]
        ELSIF tonFill.Q THEN
            _iErr := 401; _eState := E_DL_TabCompState.eFault; // 充填超时（料斗缺料/下料不畅） [-] / fill timeout [-]
        END_IF
    E_DL_TabCompState.ePreComp: // 预压相 [-] / pre compaction [-]
        IF xPrePressOk AND NOT tonPre.Q THEN
            _eState := E_DL_TabCompState.eMainComp; // 预压到位转主压 [-] / pre pressure reached leads to main compaction [-]
        ELSIF tonPre.Q THEN
            _iErr := 402; _eState := E_DL_TabCompState.eFault; // 预压到位超时 [-] / pre compaction timeout [-]
        END_IF
    E_DL_TabCompState.eMainComp: // 主压相 [-] / main compaction [-]
        IF xMainPressOk AND NOT tonMain.Q THEN
            _eState := E_DL_TabCompState.eEject; // 主压到位转出片 [-] / main pressure reached leads to ejection [-]
        ELSIF tonMain.Q THEN
            _iErr := 403; _eState := E_DL_TabCompState.eFault; // 主压到位超时（液压/过载） [-] / main compaction timeout [-]
        END_IF
    E_DL_TabCompState.eEject: // 出片相 [-] / ejection [-]
        IF xEjectDone AND NOT tonEject.Q THEN
            _eState := E_DL_TabCompState.eRejectCheck; // 出片到位转剔废判定 [-] / ejection leads to reject check [-]
        ELSIF tonEject.Q THEN
            _iErr := 404; _eState := E_DL_TabCompState.eFault; // 出片到位超时 [-] / ejection timeout [-]
        END_IF
    E_DL_TabCompState.eRejectCheck: // 剔废判定相 [-] / reject check [-]
        IF xPartOk THEN
            _eState := E_DL_TabCompState.eDone; // 判定合格转完成相 [-] / qualified leads to done [-]
        ELSE
            _iRej := _iRej + 1; // 片数累加（+1 片） / count one rejected tablet
            _eState := E_DL_TabCompState.eDone; // 判废踢出后同样回完成相 [-] / rejected tablet still ends the cycle [-]
        END_IF
    E_DL_TabCompState.eDone: // 完成相 [-] / done [-]
        xDoneInt := TRUE; // 置完成锁存（出口统一映射单拍） [-] / raise done latch [-]
        IF NOT xStart THEN
            _eState := E_DL_TabCompState.eIdle; // 松开启动即回空闲 [-] / start released returns to idle [-]
        END_IF
    E_DL_TabCompState.eFault: // 故障相：码值锁存回放，仅复位沿出 [-] / fault, exit only on reset [-]
        ; // 锁存回放（R28） [-] / replay the latch only [-]
ELSE
    _iErr := 405; _eState := E_DL_TabCompState.eFault; // 非法相位兜底 [-] / illegal phase fallback [-]
END_CASE

// 段 3｜出口映射（名实双出口，同源赋值）
eState := _eState; // 状态出口 [-] / state outlet [-]
iErrCode := _iErr; // 故障码出口（锁存值） [-] / error code outlet [-]
iRejectCnt := _iRej; // 剔废计数出口 [片] / reject counter outlet [tablets]
xDone := xDoneInt AND NOT xDonePrev; // 完成单拍（内部锁存 → 出口映射） [-] / done one-shot [-]
xDonePrev := xDoneInt; // 本拍快照供下拍比较 [-] / snapshot for the next scan [-]
END_FUNCTION_BLOCK
