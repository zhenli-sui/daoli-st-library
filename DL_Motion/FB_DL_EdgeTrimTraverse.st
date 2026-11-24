(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EdgeTrimTraverse
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 修边刀架横动往复定位。启动后在行程两端之间往复，折返点按重叠量
 *                         外延，端点驻留可组态；停止请求只在段终点生效（半途硬切会在膜面
 *                         留刀痕）。行程过窄、速度出域判组态故障；目标越软包络在启动沿前
 *                         预检拒绝，一轴不动。不做刀压控制、不做随线速度联动、不做多段
 *                         变速。说明：既有 FB_DL_SoftLimitGuard 的契约绑定运动轴接口，
 *                         与本件的开环步进契约不同，故按同一语义内联预检，不做跨契约强转。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_TraverseState / FUNCTION_BLOCK FB_DL_EdgeTrimTraverse
 * 依赖 (Depends)        : DL_Device/I_DL_StepperOpenLoop（只调用契约方法与属性）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         行程宽度判零防除零 ｜ 重叠量与驻留出域双向钳制 ｜ 非有限用自反比较
 *                         驻留定时器与沿实例无条件周期刷新 ｜ 枚举显式赋值 ｜ CASE 含 ELSE
 * 错误码表 (Codes)      : 16#0004_033B 就绪（空闲/本拍无事件）
 *                         16#0004_033C 故障级 旋转轴/横动轴拒绝运动指令
 *                         16#0004_033D 故障级 组态非法（行程宽度 < 5 mm 或速度出域）
 *                         16#0004_033E 故障级 目标越软包络，启动沿前预检拒绝（一轴不动）
 *                         16#0004_033F 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 2
 * 验收向量 (Acceptance) : 正向 行程 0~300 mm、100 mm/s、重叠 5 mm、驻留 200 ms → 单程
 *                         约 3 s、端点重叠 5 mm、单程计数 +1
 *                         反向 行程改 0~3 mm（宽 3 mm < 5 mm）→ 16#0004_033D；重叠给
 *                         -50 mm → 钳 0 后照常运行；目标包络外延后越限 → 16#0004_033E
 *                         且一轴不动；轴拒绝指令 → 16#0004_033C
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TraverseState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 横动往复相位，每个成员在 CASE 中有且仅有一个标签。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TraverseState :
(
    eIdle    := 0,    // 空闲：等启动沿与预检 / Idle, waiting for the start edge and the pre-check
    eRunMin  := 10,   // 向负端行进 / Travelling toward the minimum end
    eRunMax  := 20,   // 向正端行进 / Travelling toward the maximum end
    eDwell   := 30,   // 端点驻留计时 / Dwell timing at an end
    eStopped := 40,   // 段终点已停：等停止请求撤除 / Stopped at the segment end, waiting for the stop request to clear
    eFault   := 99    // 故障：锁存码保持，仅启动沿重启 / Fault, the latch code is held until a start edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_EdgeTrimTraverse
VAR_INPUT
    bEnable       : BOOL := FALSE;        // 使能 / Enable
    bStart        : BOOL := FALSE;        // 启动，上升沿启动一次 / Start, the rising edge starts one cycle
    bStop         : BOOL := FALSE;        // 停止，电平请求，段终点生效 / Stop request, level input, effective at the segment end
    fPosMin_mm    : REAL := 0.0;          // 行程负端 [mm]，域 ±1000 / Negative travel end in millimetres, domain plus minus 1000
    fPosMax_mm    : REAL := 300.0;        // 行程正端 [mm]，须 Max − Min ≥ 5 / Positive travel end in millimetres, Max minus Min must reach 5
    fSpeed_mmS    : REAL := 100.0;        // 运行速度 [mm/s]，域 0.5~200 / Run speed in millimetres per second, domain 0.5 to 200
    fOverlap_mm   : REAL := 5.0;          // 端点重叠 [mm]，域 0~20 / End overlap in millimetres, domain 0 to 20
    tDwell        : TIME := T#200MS;      // 端点驻留 [ms]，域 0~5 s / End dwell, domain 0 to 5 s
END_VAR
VAR_IN_OUT
    iAxis         : I_DL_StepperOpenLoop; // 横动轴开环步进契约引用 [—] / Traverse axis open-loop stepper contract reference
END_VAR
VAR_OUTPUT
    fPosOut_mm    : REAL;                 // 当前横动位置 [mm] / Current traverse position in millimetres
    bAtMin        : BOOL;                 // 负端到位 / At the minimum end
    bAtMax        : BOOL;                 // 正端到位 / At the maximum end
    uTraverseCnt  : UDINT;                // 累计单程数 [次] / Accumulated single passes
    eState        : E_DL_TraverseState;   // 横动相位 [—] / Traverse phase
    eErr          : UDINT;                // 错误码，段位 16#0004_xxxx / Error code in segment 16#0004_xxxx
END_VAR
VAR
    _eState       : E_DL_TraverseState := E_DL_TraverseState.eIdle; // 当前相位 / Current phase
    _bInit        : BOOL := FALSE;        // 首扫标志，取非判定 / First-scan flag, tested negated
    _bRefOk       : BOOL;                 // 契约引用有效标志 / Contract reference valid flag
    _bCfgOk       : BOOL;                 // 组态合法标志 / Configuration valid flag
    _bIssueScan   : BOOL;                 // 派单当拍标志（本拍不判就绪） / Dispatch scan flag, readiness is not judged in this scan
    _bStopPending : BOOL;                 // 段终点停止挂起标志 / Stop pending at the segment end
    _bDirMax      : BOOL;                 // 下一段方向：TRUE = 向正端 / Next segment direction, TRUE for the positive end
    _bFaultLatch  : BOOL;                 // 故障锁存标志 / Fault latch flag
    _uLatchCode   : UDINT;                // 锁存码载体 / Latch code carrier
    _fTgtHigh     : REAL;                 // 正端折返目标（含重叠）[mm] / Positive turn target including overlap
    _fTgtLow      : REAL;                 // 负端折返目标（含重叠）[mm] / Negative turn target including overlap
    _fOverlapEff  : REAL := 0.0;          // 生效重叠量（钳制后）[mm] / Effective overlap after clamping
    _fSpeedEff    : REAL := 100.0;        // 生效速度（下限兜底）[mm/s] / Effective speed with a lower bound guard
    _fDist        : REAL;                 // 本段待走距离 [mm] / Pending distance of this segment
    _rtrigStart   : R_TRIG;               // 启动上升沿 / Rising edge of the start command
    _tonDwell     : TON;                  // 端点驻留计时 / End dwell timer
END_VAR
VAR CONSTANT
    DL_TRV_READY   : UDINT := 16#0004_033B;  // 就绪码 / Ready code
    DL_TRV_AXIS_BAD : UDINT := 16#0004_033C; // 故障级轴拒绝码 / Fault code for a rejected axis command
    DL_TRV_CFG_BAD : UDINT := 16#0004_033D;  // 故障级组态非法码 / Fault code for bad configuration
    DL_TRV_LIMIT   : UDINT := 16#0004_033E;  // 故障级预检拒绝码 / Fault code for a pre-check rejection
    DL_TRV_W_MIN   : REAL := 5.0;            // 行程最小宽度 [mm] / Minimum travel width in millimetres
    DL_TRV_POS_HI  : REAL := 1000.0;         // 行程端点绝对值上限 [mm] / Absolute bound of the travel ends
    DL_TRV_OVL_HI  : REAL := 20.0;           // 重叠量上限 [mm] / Overlap upper bound
    DL_TRV_SPD_LO  : REAL := 0.5;            // 速度下限 [mm/s] / Speed lower bound
    DL_TRV_SPD_HI  : REAL := 200.0;          // 速度上限 [mm/s] / Speed upper bound
    DL_TRV_AT_TOL  : REAL := 0.05;           // 端点到位容差 [mm] / End-point arrival tolerance
END_VAR

// 段 1｜输出与单拍标志预置
bAtMin := FALSE;                                    // 负端到位预清 / At-minimum flag pre-cleared
bAtMax := FALSE;                                    // 正端到位预清 / At-maximum flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
_bIssueScan := FALSE;                               // 派单当拍标志预清 / Dispatch scan flag pre-cleared

// 段 2｜沿检测无条件周期刷新
_rtrigStart(CLK := bStart);                         // 启动沿 / Start edge

// 段 3｜驻留定时器无条件周期刷新（仅驻留相计时）
_tonDwell(IN := (_eState = E_DL_TraverseState.eDwell), PT := tDwell);

// 段 4｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eState := E_DL_TraverseState.eIdle;            // 相位待机起步 / Phase starts idle
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 5｜引用与组态闸（行程宽度 < 5 mm 使往复退化为抖动）
_bRefOk := (iAxis <> 0);
_bCfgOk := _bRefOk
        AND NOT ((fPosMin_mm <> fPosMin_mm) OR ((fPosMin_mm - fPosMin_mm) <> (fPosMin_mm - fPosMin_mm)))
        AND NOT ((fPosMax_mm <> fPosMax_mm) OR ((fPosMax_mm - fPosMax_mm) <> (fPosMax_mm - fPosMax_mm)))
        AND ((fPosMax_mm - fPosMin_mm) >= DL_TRV_W_MIN)
        AND (ABS(fPosMin_mm) <= DL_TRV_POS_HI) AND (ABS(fPosMax_mm) <= DL_TRV_POS_HI)
        AND NOT ((fSpeed_mmS <> fSpeed_mmS) OR ((fSpeed_mmS - fSpeed_mmS) <> (fSpeed_mmS - fSpeed_mmS)))
        AND (fSpeed_mmS >= DL_TRV_SPD_LO) AND (fSpeed_mmS <= DL_TRV_SPD_HI)
        AND (tDwell >= T#0MS) AND (tDwell <= T#5S);
_fSpeedEff := LIMIT(DL_TRV_SPD_LO, fSpeed_mmS, DL_TRV_SPD_HI);          // 生效速度钳制 [mm/s] / Effective speed after clamping
_fOverlapEff := LIMIT(0.0, fOverlap_mm, DL_TRV_OVL_HI);                 // 重叠量钳制 [mm] / Overlap after clamping
_fTgtHigh := fPosMax_mm + _fOverlapEff;                                 // 正端折返目标（外延）[mm] / Positive turn target, extended
_fTgtLow := fPosMin_mm - _fOverlapEff;                                  // 负端折返目标（外延）[mm] / Negative turn target, extended

// 段 6｜位置回读与端点判据
IF _bRefOk THEN
    fPosOut_mm := iAxis.fPosition;                  // 当前横动位置 [mm] / Current traverse position
    bAtMax := ABS(fPosOut_mm - fTgtHigh) <= DL_TRV_AT_TOL;   // 正端到位判据 / At the positive end
    bAtMin := ABS(fPosOut_mm - fTgtLow) <= DL_TRV_AT_TOL;    // 负端到位判据 / At the negative end
ELSE
    fPosOut_mm := 0.0;                              // 引用无效：位置输出置 0 / Invalid reference, the position output is zeroed
END_IF

// 段 7｜失能闸
IF NOT bEnable THEN
    IF _bRefOk THEN
        iAxis.Stop();                               // 失能即受控停车 / Controlled stop on disable
    END_IF
    _eState := E_DL_TraverseState.eIdle;            // 相位回空闲 / Phase back to idle
    _bStopPending := FALSE;                         // 停止挂起清 / Stop pending cleared
    eErr := DL_TRV_READY;                           // 失能为正常停机 / Disable is a normal stop
END_IF

// 段 8｜横动往复状态机（ENUM + CASE + ELSE 兜底）
IF bEnable THEN
    CASE _eState OF

        E_DL_TraverseState.eIdle:                   // 空闲：等启动沿，先做组态与包络预检
            IF _rtrigStart.Q THEN
                _bFaultLatch := FALSE;              // 启动沿为锁存解除路径 / The start edge releases the latch
                _uLatchCode := 0;                   // 锁存码清 / Latch code cleared
                _bStopPending := FALSE;             // 停止挂起清 / Stop pending cleared
                IF NOT _bCfgOk THEN
                    eErr := DL_TRV_CFG_BAD;         // 故障级：组态非法 / Fault, bad configuration
                    _uLatchCode := DL_TRV_CFG_BAD;
                    _bFaultLatch := TRUE;
                    _eState := E_DL_TraverseState.eFault;
                ELSIF (ABS(_fTgtHigh) > DL_TRV_POS_HI) OR (ABS(_fTgtLow) > DL_TRV_POS_HI) THEN
                    eErr := DL_TRV_LIMIT;           // 故障级：重叠外延后越软包络，一轴不动 / Fault, the extended target leaves the envelope
                    _uLatchCode := DL_TRV_LIMIT;
                    _bFaultLatch := TRUE;
                    _eState := E_DL_TraverseState.eFault;
                ELSE
                    _bDirMax := TRUE;               // 首段向正端 / The first segment heads to the positive end
                    _eState := E_DL_TraverseState.eRunMax;
                END_IF
            ELSE
                IF NOT _bCfgOk THEN
                    eErr := DL_TRV_CFG_BAD;         // 故障级：组态非法（空闲期即报） / Fault, bad configuration reported while idle
                    _uLatchCode := DL_TRV_CFG_BAD;
                    _bFaultLatch := TRUE;
                    _eState := E_DL_TraverseState.eFault;
                END_IF
            END_IF

        E_DL_TraverseState.eRunMax:                 // 向正端行进：等轴就绪，停止请求挂起
            IF _bIssueScan THEN
                _bIssueScan := FALSE;               // 派单拍已过 / The dispatch scan has passed
            ELSIF (NOT _bStopPending) AND bStop THEN
                _bStopPending := TRUE;              // 停止请求挂起，段终点生效 / Stop pending, effective at the segment end
            ELSIF iAxis.bReady THEN
                uTraverseCnt := uTraverseCnt + 1;   // 单程计数 +1 [次] / Single-pass count incremented
                IF _bStopPending THEN
                    _eState := E_DL_TraverseState.eStopped;   // 段终点停车 / Stop at the segment end
                ELSE
                    _eState := E_DL_TraverseState.eDwell;     // 端点驻留 / Dwell at the end
                END_IF
            END_IF

        E_DL_TraverseState.eRunMin:                 // 向负端行进：等轴就绪，停止请求挂起
            IF _bIssueScan THEN
                _bIssueScan := FALSE;
            ELSIF (NOT _bStopPending) AND bStop THEN
                _bStopPending := TRUE;
            ELSIF iAxis.bReady THEN
                uTraverseCnt := uTraverseCnt + 1;   // 单程计数 +1 [次] / Single-pass count incremented
                IF _bStopPending THEN
                    _eState := E_DL_TraverseState.eStopped;
                ELSE
                    _eState := E_DL_TraverseState.eDwell;
                END_IF
            END_IF

        E_DL_TraverseState.eDwell:                  // 端点驻留：计时满后换向派单
            IF _tonDwell.Q THEN
                IF _bDirMax THEN
                    _bDirMax := FALSE;              // 换向：下一段向负端 / Reverse, the next segment heads to the negative end
                    _fDist := _fTgtLow - iAxis.fPosition;      // 待走距离 [mm] / Pending distance
                ELSE
                    _bDirMax := TRUE;               // 换向：下一段向正端 / Reverse, the next segment heads to the positive end
                    _fDist := _fTgtHigh - iAxis.fPosition;     // 待走距离 [mm] / Pending distance
                END_IF
                IF iAxis.MoveRelative(_fDist, _fSpeedEff) THEN
                    _bIssueScan := TRUE;            // 派单当拍不判就绪 / Readiness is not judged in the dispatch scan
                    IF _bDirMax THEN
                        _eState := E_DL_TraverseState.eRunMax;
                    ELSE
                        _eState := E_DL_TraverseState.eRunMin;
                    END_IF
                    eErr := DL_TRV_READY;           // 就绪码 / Ready code
                ELSE
                    eErr := DL_TRV_AXIS_BAD;        // 故障级：轴拒绝指令 / Fault, the axis rejected the command
                    _uLatchCode := DL_TRV_AXIS_BAD;
                    _bFaultLatch := TRUE;
                    _eState := E_DL_TraverseState.eFault;
                END_IF
            END_IF

        E_DL_TraverseState.eStopped:                // 段终点已停：停止请求撤除后回空闲
            IF NOT bStop THEN
                _bStopPending := FALSE;
                _eState := E_DL_TraverseState.eIdle;
            END_IF
            eErr := DL_TRV_READY;

        E_DL_TraverseState.eFault:                  // 故障：锁存码保持，仅新启动沿重启
            eErr := _uLatchCode;                    // 锁存码回放 / Replay the latch code
            IF _rtrigStart.Q THEN
                _bFaultLatch := FALSE;
                _uLatchCode := 0;
                _bStopPending := FALSE;
                eErr := DL_TRV_READY;
                _eState := E_DL_TraverseState.eIdle; // 回空闲需再给启动沿（下一拍） / A further start edge is required
            END_IF

        ELSE
            // 非法状态兜底（故障级）
            eErr := DL_TRV_CFG_BAD;                 // 故障级：非法相位 / Fault, illegal phase
            _uLatchCode := DL_TRV_CFG_BAD;
            _bFaultLatch := TRUE;
            _eState := E_DL_TraverseState.eFault;

    END_CASE
END_IF

eState := _eState;                                  // 相位出口镜像 / Phase mirrored to the output pin
END_FUNCTION_BLOCK
