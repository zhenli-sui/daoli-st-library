(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LaserTabWeldTrack
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 极耳激光焊跟随误差与虚焊特征窗监视。出光期间统计三类缺陷特征
 *                         ——跟随误差超限、功率相对跌落、位置停滞——各需连续满足确认时长
 *                         才置位；单焊点窗口超时强制给出判决并置超时位，绝不允许无限期停
 *                         在出光态。不做激光功率闭环、不做焊缝跟踪插补、不做焊后强度判定。
 *                         交付门槛：位置停滞判据用 tConfirm 换算秒（时间转换链），须在
 *                         CODESYS / TwinCAT / InoProShop 三平台各编译验证一次。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_WeldTrackState / FUNCTION_BLOCK FB_DL_LaserTabWeldTrack
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS / MAX / TIME_TO_LREAL）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         参考功率与误差上限判零防除零 ｜ 位置非有限只跳过本拍、不清峰值
 *                         四个定时器无条件周期刷新 ｜ 枚举显式赋值 ｜ CASE 含 ELSE 兜底
 * 同拍双窗配比约束      : 窗口超时 tWindowMax 必须显著大于三类判据确认 tConfirm
 *                         （建议 tWindowMax ≥ 5 × tConfirm），否则判据来不及确认即被超时
 *                         抢先判决，缺陷掩码永远只能出 bit3。
 * 错误码表 (Codes)      : 16#0004_0331 就绪（无窗进行或本拍无故障）
 *                         16#0004_0332 信息级 位置读数非有限，本拍跳过（已累计峰值与掩码
 *                                    保持，不清零）
 *                         16#0004_0333 故障级 组态非法（跟随误差上限或参考功率 ≤0）
 *                         16#0004_0334 故障级 非法状态兜底（状态机落 ELSE）
 *                         16#0004_0335 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 2
 *                         2026-11-17  v1.0.1  终审修复：①停滞速度补入组态域闸（负值/NaN 会
 *                                    使停滞距离门限失效而静默关闭 bit2 判据）；②停滞窗起点与
 *                                    焊点位置锁存加位置有限前置（防 NaN 写入出口）· R28 · 阶段四
 * 验收向量 (Acceptance) : 正向 指令 0→50 mm、实际滞后 0.3 mm 超上限 0.2 mm 持续 30 ms →
 *                         bit0 置位、eState=eReject、峰值 0.3 mm
 *                         反向 功率 2000→1500 W（跌 25% 超 10%）持续 30 ms → bit1；
 *                         上限给 0 → 16#0004_0333；窗口拖满 tWindowMax 无判决 → bit3 +
 *                         eReject（不停在出光态）；位置给 NaN → 16#0004_0332 且峰值不清零
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_WeldTrackState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 单焊点监视相位，每个成员在 CASE 中有且仅有一个标签。
 *----------------------------------------------------------------------------*)
TYPE E_DL_WeldTrackState :
(
    eWaiting  := 0,    // 待机：等出光 / Waiting for the weld-on signal
    eWelding  := 10,   // 出光中：累计峰值与三类判据 / Welding, accumulating the peak and the three criteria
    eJudging  := 20,   // 判决中：锁存焊点位置并出结论 / Judging, latching the weld position and issuing the verdict
    ePass     := 30,   // 合格：掩码为 0 / Pass, the defect mask is zero
    eReject   := 40,   // 不合格：至少一个缺陷位或窗口超时 / Reject, at least one defect bit or the window timed out
    eFault    := 99    // 故障：锁存码保持，仅使能沿重启 / Fault, the latch code is held until an enable edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaserTabWeldTrack
VAR_INPUT
    bEnable         : BOOL := FALSE;      // 使能 / Enable
    bWeldOn         : BOOL := FALSE;      // 出光中（仅窗内判据） / Welding on, the criteria are evaluated inside the window only
    fPosCmd_mm      : REAL := 0.0;        // 指令位置 [mm] / Command position in millimetres
    fPosAct_mm      : REAL := 0.0;        // 实际位置 [mm] / Actual position in millimetres
    fPower_W        : REAL := 0.0;        // 实测功率 [W] / Measured power in watt
    fPowerRef_W     : REAL := 2000.0;     // 设定功率 [W]，须 >0 / Reference power in watt, must be positive
    fFollowErrMax_mm : REAL := 0.2;       // 跟随误差上限 [mm]，域 0.01~2.0 / Following error limit in millimetres, domain 0.01 to 2.0
    fPowerDropPct   : REAL := 10.0;       // 功率跌落阈 [%]，域 1~50 / Power drop threshold in percent, domain 1 to 50
    fStallVel_mmS   : REAL := 0.2;        // 停滞判据速度 [mm/s]，域 0~5 / Stall speed criterion in millimetres per second, domain 0 to 5
    tConfirm        : TIME := T#30MS;     // 判据确认时长 [ms]，域 20~500 / Criterion confirmation time, domain 20 to 500 ms
    tWindowMax      : TIME := T#2S;       // 单焊点窗口 [ms]，域 50ms~10s / Single weld spot window, domain 50 ms to 10 s
END_VAR
VAR_OUTPUT
    bTrackOk        : BOOL;               // 轨迹合格（判决合格时置位） / Trajectory accepted
    fFollowErrPeak_mm : REAL;             // 窗内跟随误差峰值 [mm] / Peak following error inside the window
    uDefectMask     : WORD;               // 缺陷掩码 bit0 跟超 bit1 功率跌 bit2 停滞 bit3 超时 [bit] / Defect mask
    fWeldPos_mm     : REAL;               // 锁存焊点位置 [mm] / Latched weld position in millimetres
    eState          : E_DL_WeldTrackState; // 监视相位 [—] / Monitoring phase
    eErr            : UDINT;              // 错误码，段位 16#0004_xxxx / Error code in segment 16#0004_xxxx
END_VAR
VAR
    _eState         : E_DL_WeldTrackState := E_DL_WeldTrackState.eWaiting; // 当前相位 / Current phase
    _bInit          : BOOL := FALSE;      // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCfgOk         : BOOL;               // 组态合法标志 / Configuration valid flag
    _bPosOk         : BOOL;               // 位置读数有限标志 / Position readings finite flag
    _bFaultLatch    : BOOL;               // 故障锁存标志 / Fault latch flag
    _uLatchCode     : UDINT;              // 锁存码载体 / Latch code carrier
    _fFollowErr     : REAL;               // 本拍跟随误差 [mm] / Following error of this scan
    _fPeak          : REAL;               // 窗内峰值内部副本 [mm] / Internal peak copy inside the window
    _fDropPct       : REAL;               // 本拍功率跌落百分比 [%] / Power drop of this scan in percent
    _fPosWinStart   : REAL;               // 停滞窗起点位置 [mm] / Position at the start of the stall window
    _fConfirmSec    : REAL := 0.03;       // 确认时长换算秒 [s] / Confirmation time converted to seconds
    _fStallDist     : REAL;               // 停滞判定距离门限 [mm] / Stall distance threshold in millimetres
    _rtrigEnable    : R_TRIG;             // 使能上升沿 / Rising edge of the enable input
    _tonFollow      : TON;                // 跟超确认计时 / Following error confirmation timer
    _tonPower       : TON;                // 功率跌落确认计时 / Power drop confirmation timer
    _tonStall       : TON;                // 停滞确认计时 / Stall confirmation timer
    _tonWindow      : TON;                // 单焊点窗口计时 / Weld spot window timer
END_VAR
VAR CONSTANT
    DL_WT_READY     : UDINT := 16#0004_0331;  // 就绪码 / Ready code
    DL_WT_POS_BAD   : UDINT := 16#0004_0332;  // 信息级位置非有限码 / Info code for non-finite positions
    DL_WT_CFG_BAD   : UDINT := 16#0004_0333;  // 故障级组态非法码 / Fault code for bad configuration
    DL_WT_ILLEGAL   : UDINT := 16#0004_0334;  // 故障级非法状态码 / Fault code for an illegal state
    DL_WT_BIT_FOLLOW : WORD := 16#0001;       // 缺陷位 bit0 跟超 / Defect bit 0, following error
    DL_WT_BIT_POWER  : WORD := 16#0002;       // 缺陷位 bit1 功率跌 / Defect bit 1, power drop
    DL_WT_BIT_STALL  : WORD := 16#0004;       // 缺陷位 bit2 停滞 / Defect bit 2, stall
    DL_WT_BIT_TIME   : WORD := 16#0008;       // 缺陷位 bit3 超时 / Defect bit 3, window timeout
    DL_WT_EPS        : REAL := 1.0E-6;        // 浮点判零容差 [—] / Float zero tolerance
END_VAR

// 段 1｜输出与单拍标志预置（bTrackOk 逐拍重算，掩码与峰值为窗内累计量，不在此清）
bTrackOk := FALSE;                                  // 合格标志预清 / Accepted flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜沿检测无条件周期刷新
_rtrigEnable(CLK := bEnable);                       // 使能沿 / Enable edge

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eState := E_DL_WeldTrackState.eWaiting;        // 相位待机起步 / Phase starts waiting
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜组态闸（跟随上限与参考功率判零防除零）
_bCfgOk := NOT ((fFollowErrMax_mm <> fFollowErrMax_mm) OR ((fFollowErrMax_mm - fFollowErrMax_mm) <> (fFollowErrMax_mm - fFollowErrMax_mm)))
        AND (fFollowErrMax_mm > DL_WT_EPS)
        AND NOT ((fPowerRef_W <> fPowerRef_W) OR ((fPowerRef_W - fPowerRef_W) <> (fPowerRef_W - fPowerRef_W)))
        AND (fPowerRef_W > DL_WT_EPS)
        AND (fPowerDropPct >= 1.0) AND (fPowerDropPct <= 50.0)
        AND (fStallVel_mmS >= 0.0) AND (fStallVel_mmS <= 5.0)   // 停滞速度域闸：负值/NaN 会使停滞门限失效而静默关闭 bit2 / Stall speed gate, a negative or NaN value silently disables bit 2
        AND (tConfirm >= T#20MS) AND (tConfirm <= T#500MS)
        AND (tWindowMax >= T#50MS) AND (tWindowMax <= T#10S);
_fConfirmSec := TIME_TO_LREAL(tConfirm) / 1000.0;   // 确认时长换算秒 [s] / Confirmation time in seconds
_fStallDist := fStallVel_mmS * _fConfirmSec;        // 停滞判定距离门限 [mm] / Stall distance threshold

// 段 5｜位置有限闸（非有限只跳过本拍，已累计峰值与掩码一律不清零）
_bPosOk := NOT ((fPosCmd_mm <> fPosCmd_mm) OR ((fPosCmd_mm - fPosCmd_mm) <> (fPosCmd_mm - fPosCmd_mm)))
        AND NOT ((fPosAct_mm <> fPosAct_mm) OR ((fPosAct_mm - fPosAct_mm) <> (fPosAct_mm - fPosAct_mm)));
_fFollowErr := ABS(fPosCmd_mm - fPosAct_mm);        // 本拍跟随误差 [mm] / Following error of this scan

// 段 6｜功率跌落百分比（除数已在段 4 判零）
IF (fPower_W <> fPower_W) OR ((fPower_W - fPower_W) <> (fPower_W - fPower_W)) THEN
    _fDropPct := 0.0;                               // 功率非有限：本拍不判跌落 / Non-finite power, no drop judgement this scan
ELSE
    _fDropPct := ((fPowerRef_W - fPower_W) / fPowerRef_W) * 100.0;   // 跌落百分比 [%] / Power drop in percent
END_IF

// 段 7｜四个定时器无条件周期刷新（严禁置于分支内）
_tonFollow(IN := (_eState = E_DL_WeldTrackState.eWelding) AND _bPosOk AND (_fFollowErr > fFollowErrMax_mm), PT := tConfirm);
_tonPower(IN := (_eState = E_DL_WeldTrackState.eWelding) AND (_fDropPct > fPowerDropPct), PT := tConfirm);
_tonStall(IN := (_eState = E_DL_WeldTrackState.eWelding) AND _bPosOk AND (ABS(fPosAct_mm - _fPosWinStart) < _fStallDist), PT := tConfirm);
_tonWindow(IN := (_eState = E_DL_WeldTrackState.eWelding), PT := tWindowMax);

// 段 8｜使能上升沿：锁存解除路径
IF _rtrigEnable.Q THEN
    _bFaultLatch := FALSE;                          // 锁存解除 / Latch released
    _uLatchCode := 0;                               // 锁存码清 / Latch code cleared
    _eState := E_DL_WeldTrackState.eWaiting;        // 相位回待机 / Phase back to waiting
    uDefectMask := 16#0000;                         // 掩码清 / Defect mask cleared
    _fPeak := 0.0;                                  // 峰值清 [mm] / Peak cleared
    fFollowErrPeak_mm := 0.0;                       // 峰值出口清 [mm] / Peak output cleared
END_IF

// 段 9｜失能闸
IF NOT bEnable THEN
    _eState := E_DL_WeldTrackState.eWaiting;        // 相位回待机 / Phase back to waiting
    eErr := DL_WT_READY;                            // 失能为正常停机 / Disable is a normal stop
END_IF

// 段 10｜监视状态机（ENUM + CASE + ELSE 兜底）
IF bEnable THEN
    CASE _eState OF

        E_DL_WeldTrackState.eWaiting:               // 待机：组态错即锁存，出光沿开窗
            IF NOT _bCfgOk THEN
                eErr := DL_WT_CFG_BAD;              // 故障级：组态非法 / Fault, bad configuration
                _uLatchCode := DL_WT_CFG_BAD;
                _bFaultLatch := TRUE;
                _eState := E_DL_WeldTrackState.eFault;
            ELSIF bWeldOn THEN
                uDefectMask := 16#0000;             // 新焊点掩码清 / New spot, the mask is cleared
                _fPeak := 0.0;                      // 新焊点峰值清 [mm] / New spot, the peak is cleared
                fFollowErrPeak_mm := 0.0;
                IF _bPosOk THEN                     // 位置有限才取窗起点与焊点初值（防 NaN 入出口） / Latch only with finite positions
                    _fPosWinStart := fPosAct_mm;    // 停滞窗起点位置 [mm] / Stall window start position
                    fWeldPos_mm := fPosAct_mm;      // 焊点位置初值 [mm] / Weld position initial value
                END_IF
                _eState := E_DL_WeldTrackState.eWelding;   // 开窗出光 / The window opens
            ELSE
                eErr := DL_WT_READY;                // 就绪码 / Ready code
            END_IF

        E_DL_WeldTrackState.eWelding:               // 出光中：累计峰值 + 三类判据确认
            IF NOT _bPosOk THEN
                eErr := DL_WT_POS_BAD;              // 信息级：位置非有限，本拍跳过 / Info, positions not finite, this scan is skipped
            ELSE
                IF _fFollowErr > _fPeak THEN
                    _fPeak := _fFollowErr;          // 峰值刷新 [mm] / Peak refreshed
                END_IF
            END_IF
            fFollowErrPeak_mm := _fPeak;            // 峰值出口 [mm] / Peak output
            IF _fFollowErr > fFollowErrMax_mm THEN
                IF _tonFollow.Q THEN
                    uDefectMask := uDefectMask OR DL_WT_BIT_FOLLOW;   // bit0 跟超确认 / Following error confirmed
                END_IF
            END_IF
            IF _fDropPct > fPowerDropPct THEN
                IF _tonPower.Q THEN
                    uDefectMask := uDefectMask OR DL_WT_BIT_POWER;    // bit1 功率跌落确认 / Power drop confirmed
                END_IF
            END_IF
            IF ABS(fPosAct_mm - _fPosWinStart) < _fStallDist THEN
                IF _tonStall.Q THEN
                    uDefectMask := uDefectMask OR DL_WT_BIT_STALL;    // bit2 停滞确认 / Stall confirmed
                END_IF
            ELSE
                _fPosWinStart := fPosAct_mm;    // 已移动：重置停滞窗起点 [mm] / Moved, restart the stall window
            END_IF
            IF _tonWindow.Q THEN
                uDefectMask := uDefectMask OR DL_WT_BIT_TIME;         // bit3 窗口超时 / Window timed out
                _eState := E_DL_WeldTrackState.eJudging;              // 强制判决，绝不停在出光态 / Forced verdict, never stuck in welding
            ELSIF NOT bWeldOn THEN
                _eState := E_DL_WeldTrackState.eJudging;              // 出光结束：判决 / Weld finished, judge now
            END_IF

        E_DL_WeldTrackState.eJudging:               // 判决中：锁存焊点位置并出结论
            IF _bPosOk THEN                         // 位置有限才刷新焊点位置，保持上次有效值 / Refresh the latch only with finite positions
                fWeldPos_mm := fPosAct_mm;          // 锁存焊点位置 [mm] / Latch the weld position
            END_IF
            IF uDefectMask = 16#0000 THEN
                bTrackOk := TRUE;                   // 掩码为 0：合格 / A zero mask means pass
                _eState := E_DL_WeldTrackState.ePass;
            ELSE
                _eState := E_DL_WeldTrackState.eReject;   // 有缺陷位：不合格 / At least one defect bit, reject
            END_IF
            eErr := DL_WT_READY;                    // 判决本身无故障码 / The verdict produces no fault code

        E_DL_WeldTrackState.ePass:                  // 合格：保持结论，等出光消失后回待机
            bTrackOk := TRUE;
            IF NOT bWeldOn THEN
                _eState := E_DL_WeldTrackState.eWaiting;
            END_IF

        E_DL_WeldTrackState.eReject:                // 不合格：保持结论，等出光消失后回待机
            bTrackOk := FALSE;
            IF NOT bWeldOn THEN
                _eState := E_DL_WeldTrackState.eWaiting;
            END_IF

        E_DL_WeldTrackState.eFault:                 // 故障：锁存码保持
            eErr := _uLatchCode;                    // 锁存码回放 / Replay the latch code
            IF NOT _bFaultLatch THEN
                _eState := E_DL_WeldTrackState.eWaiting;   // 锁存已由使能沿解除 / The latch was released by the enable edge
            END_IF

        ELSE
            // 非法状态兜底（故障级）
            eErr := DL_WT_ILLEGAL;                  // 故障级：非法相位 / Fault, illegal phase
            _uLatchCode := DL_WT_ILLEGAL;
            _bFaultLatch := TRUE;
            _eState := E_DL_WeldTrackState.eFault;

    END_CASE
END_IF

eState := _eState;                                  // 相位出口镜像 / Phase mirrored to the output pin
END_FUNCTION_BLOCK
