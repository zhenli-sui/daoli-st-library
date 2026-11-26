(*
  DL Factory R84 | FB_DL_ToolMagazinePosSeq
  功能：刀库就近寻刀定位时序，含双向索引差取小择向与旋转/锁紧双超时
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
TYPE E_DL_TmagState :
(
    eIdle := 0, // 空闲待命 [-] / idle [-]
    eSearch := 1, // 就近择向计算相 [-] / nearest slot evaluation phase [-]
    eRotate := 2, // 刀盘旋转相 [-] / magazine rotation phase [-]
    eLockCheck := 3, // 锁紧确认相 [-] / lock confirmation phase [-]
    eReady := 4, // 定位完成相 [-] / positioned phase [-]
    eFault := 5 // 故障锁存相 [-] / fault latched phase [-]
) := eIdle;
END_TYPE

FUNCTION_BLOCK FB_DL_ToolMagazinePosSeq
VAR_INPUT
    xStart : BOOL; // 寻刀启动命令 [-] / seek start command [-]
    xReset : BOOL; // 复位命令（上升沿清故障码） [-] / reset command [-]
    iReqSlot : INT; // 请求刀位序号（0 基） [个] / requested slot index, zero based [count]
    iCurSlot : INT; // 当前刀位序号（0 基） [个] / current slot index, zero based [count]
    iSlotCnt : INT; // 刀库总刀位数（1~200） [个] / total slot count [count]
    xRotInPos : BOOL; // 旋转到位反馈 [-] / rotation in position feedback [-]
    xLocked : BOOL; // 刀盘锁紧确认 [-] / magazine locked confirmation [-]
    tRotLimit : TIME := T#20S; // 旋转到位超时门限 [s] / rotation timeout [s]
    tLockLimit : TIME := T#3S; // 锁紧确认超时门限 [s] / lock timeout [s]
END_VAR
VAR_OUTPUT
    eState : E_DL_TmagState; // 当前时序状态 [-] / current sequence state [-]
    iTargetSlot : INT; // 择定的目标刀位序号（0 基） [个] / resolved target slot [count]
    iErrCode : INT; // 故障码 0=正常，301~304 [-] / error code, 301 to 304 [code]
    xReady : BOOL; // 定位完成（可换刀） [-] / positioned and ready [-]
    iDirCtrl : INT; // 择向指令出口 1=正转 −1=反转 0=未定 [-] / direction command outlet, 1 forward -1 reverse 0 undecided (R583)
END_VAR
VAR
    rtStart : R_TRIG; // 启动上升沿实例 [-] / start rising edge instance [-]
    rtReset : R_TRIG; // 复位上升沿实例 [-] / reset rising edge instance [-]
    tonRot : TON; // 旋转到位超时定时器 [-] / rotation timeout timer [-]
    tonLock : TON; // 锁紧确认超时定时器 [-] / lock timeout timer [-]
    _eState : E_DL_TmagState := E_DL_TmagState.eIdle; // 内部相位（CASE 唯一写目标） [-] / internal phase [-]
    _iErr : INT; // 故障码内部锁存 [-] / latched error code [-]
    iDiff : INT; // 正向索引差（已取绝对值） [个] / forward absolute index difference [count]
    iAlt : INT; // 反向索引差 [个] / reverse index difference [count]
    iDir : INT; // 择向结果 1=正转 −1=反转 [-] / chosen direction [-]
END_VAR

// 段 0｜边沿与定时器实例无条件周期刷新（R7）
rtStart(CLK := xStart); // 启动沿每拍必调 [-] / start edge called every scan [-]
rtReset(CLK := xReset); // 复位沿每拍必调 [-] / reset edge called every scan [-]
tonRot(IN := _eState = E_DL_TmagState.eRotate, PT := tRotLimit); // 旋转相闸 + 无条件调用 [-] / rotation timer, unconditional [-]
tonLock(IN := _eState = E_DL_TmagState.eLockCheck, PT := tLockLimit); // 锁紧相闸 + 无条件调用 [-] / lock timer, unconditional [-]

// 段 0｜出口预置（R256）：择向指令每拍先归未定，由 eSearch 单点重赋
iDir := 0; // 未择向 [-] / undecided direction [-]

// 段 1｜复位沿：清故障码与相位（保持量不含 Prev/Acc/Latch，R189）
IF rtReset.Q THEN
    _iErr := 0; // 清故障码 [-] / clear error code [-]
    _eState := E_DL_TmagState.eIdle; // 回空闲相 [-] / back to idle [-]
END_IF

// 段 2｜主状态机（合法事件优先于超时迁移，R275）
CASE _eState OF
    E_DL_TmagState.eIdle: // 空闲相 [-] / idle [-]
        IF rtStart.Q THEN
            _eState := E_DL_TmagState.eSearch; // 启动沿进择向相 [-] / start edge enters evaluation [-]
        END_IF
    E_DL_TmagState.eSearch: // 就近择向：两方向索引差取小（有符号差显式取模，R271 禁单侧 ABS） [-] / nearest direction [-]
        IF (iSlotCnt < 1) OR (iSlotCnt > 200) OR (iReqSlot < 0) OR (iReqSlot >= iSlotCnt) OR (iCurSlot < 0) OR (iCurSlot >= iSlotCnt) THEN
            _iErr := 301; _eState := E_DL_TmagState.eFault; // 刀位组态越界 [-] / slot index out of range [-]
        ELSE
            iDiff := iReqSlot - iCurSlot; // 有符号差先求再取模 [个] / signed difference [count]
            IF iDiff < 0 THEN
                iDiff := -iDiff; // 双侧直比：负数显式取反 [个] / take the magnitude explicitly [count]
            END_IF
            iAlt := iSlotCnt - iDiff; // 反向圈数 = 总数 − 正向步数 [个] / reverse count [count]
            IF iDiff <= iAlt THEN
                iDir := 1; // 正向不多于反向，取正转 [-] / forward is not longer [-]
            ELSE
                iDir := -1; // 反向更短，取反转 [-] / reverse is shorter [-]
            END_IF
            iTargetSlot := iReqSlot; // 输出择定目标刀位 [个] / export the resolved slot [count]
            _eState := E_DL_TmagState.eRotate; // 择向完成立即转旋转相 [-] / evaluation leads to rotation [-]
        END_IF
    E_DL_TmagState.eRotate: // 旋转相（iDir 供执行层决定正/反转） [-] / rotation [-]
        IF xRotInPos AND NOT tonRot.Q THEN
            _eState := E_DL_TmagState.eLockCheck; // 到位转锁紧确认 [-] / in position leads to lock check [-]
        ELSIF tonRot.Q THEN
            _iErr := 302; _eState := E_DL_TmagState.eFault; // 旋转到位超时 [-] / rotation timeout [-]
        END_IF
    E_DL_TmagState.eLockCheck: // 锁紧确认相（上锁类安全相，入相复检无故障） [-] / lock check [-]
        IF xLocked AND NOT tonLock.Q THEN
            _eState := E_DL_TmagState.eReady; // 锁紧确认转完成相 [-] / locked leads to ready [-]
        ELSIF tonLock.Q THEN
            _iErr := 303; _eState := E_DL_TmagState.eFault; // 锁紧确认超时 [-] / lock timeout [-]
        END_IF
    E_DL_TmagState.eReady: // 定位完成相：保持刀位，命令撤销即回空闲 [-] / ready [-]
        IF NOT xStart THEN
            _eState := E_DL_TmagState.eIdle; // 命令撤销回空闲 [-] / command released returns to idle [-]
        END_IF
    E_DL_TmagState.eFault: // 故障相：码值锁存回放，仅复位沿出 [-] / fault, exit only on reset [-]
        ; // 锁存回放（读己不改值，R28） [-] / replay the latch only, no re-inference [-]
ELSE
    _iErr := 304; _eState := E_DL_TmagState.eFault; // 非法相位兜底 [-] / illegal phase fallback [-]
END_CASE

// 段 3｜出口映射（名实双出口，同源赋值）
eState := _eState; // 状态出口 [-] / state outlet [-]
iErrCode := _iErr; // 故障码出口（锁存值） [-] / error code outlet [-]
iDirCtrl := iDir; // 择向结果出口（原先仅内部量，R583 补出口） [-] / direction outlet, previously internal only [-]
xReady := _eState = E_DL_TmagState.eReady; // 完成位 = 完成相镜像 [-] / ready mirrors the ready phase [-]
END_FUNCTION_BLOCK
