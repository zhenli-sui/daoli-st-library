(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StepperFeederBelt
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 步进供料带间歇送料 + 色标偏差补偿。送料请求上升沿受理一次，
 *                         步距 = 标称间距 + 色标补偿增量（偏差 × 增益），补偿量按上限
 *                         累计约束；送料后等停稳确认时长再给单拍完成脉冲。运行期请求
 *                         一律丢弃不排队。不做色标检测本身（偏差由引脚注入）、不做
 *                         速度前馈、不做多段送料。
 *                         说明：接口契约 MoveRelative 只接受距离与速度，fAccel_mmS2 仅参与
 *                         参数门禁校验，不向下转发（规格口径在本行登记）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_FeederState / FUNCTION_BLOCK FB_DL_StepperFeederBelt
 * 依赖 (Depends)        : DL_Device/I_DL_StepperOpenLoop（只调用契约方法与属性）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         间距判零防除零 ｜ 步距双向钳制（防倒料） ｜ 非有限用自反比较
 *                         枚举显式赋值 ｜ 停稳定时器与沿检测无条件周期刷新 ｜ CASE 含 ELSE
 * 错误码表 (Codes)      : 16#0004_032C 就绪/单次送料完成
 *                         16#0004_032D 故障级 步进轴拒绝送料指令。反证句：轴拒绝在输出侧
 *                                    与「组态非法」同为「本拍无位移」，但组态非法可由 032E
 *                                    在启动前观测，故轴拒绝须独立成码
 *                         16#0004_032E 故障级 组态非法（间距判零、增益/上限/速度/加速度出域）
 *                         16#0004_032F 信息级 补偿后步距越 0.5~1.5 倍间距已钳制（防倒料，
 *                                    不置故障级标志，送料照常进行）
 *                         16#0004_0330 故障级 累计补偿越上限，停送（继续补偿会把误差藏进
 *                                    机构行程）。本件 5 槽全用、无预留槽，已登记待裁定
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 1
 * 验收向量 (Acceptance) : 正向 间距 100 mm、偏差 +2 mm、增益 0.5 → 步距 101 mm、累计
 *                         +1 mm、16#0004_032C、计数 +1
 *                         反向 连续 60 拍偏差 +1 mm（增益 0.5）→ 累计 30 mm 超上限 20 mm
 *                         → 16#0004_0330 停送；间距给 0 → 16#0004_032E；步距被钳到
 *                         1.5 倍间距 → 16#0004_032F 且照常送料
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FeederState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 供料带送料相位，每个成员在 CASE 中有且仅有一个标签。
 *----------------------------------------------------------------------------*)
TYPE E_DL_FeederState :
(
    eIdle     := 0,    // 空闲：等送料请求沿 / Idle, waiting for the index request edge
    eIndexing := 10,   // 送料中：已派单，等轴就绪 / Indexing, dispatched and waiting for the axis to be ready
    eSettling := 20,   // 停稳确认：等 tSettle 计时满 / Settling, waiting for the settle time
    eFault    := 99    // 故障：锁存码保持，仅使能沿重启 / Fault, the latch code is held until an enable edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_StepperFeederBelt
VAR_INPUT
    bEnable         : BOOL := FALSE;      // 使能，上升沿清补偿累计（班次重启语义） / Enable, the rising edge clears the trim accumulation
    bIndexReq       : BOOL := FALSE;      // 送料请求，上升沿受理，运行期丢弃 / Index request, accepted on the rising edge and dropped while busy
    fPitch_mm       : REAL := 100.0;      // 标称间距 [mm]，域 1~2000 / Nominal pitch in millimetres, domain 1 to 2000
    fMarkOffset_mm  : REAL := 0.0;        // 色标偏差 [mm]，域 ±20，正=超前 / Mark offset in millimetres, domain plus minus 20, positive means ahead
    fTrimGain       : REAL := 0.5;        // 补偿增益 [—]，域 0~1（>1 振荡） / Trim gain, domain 0 to 1, above 1 oscillates
    fTrimAccumMax_mm : REAL := 20.0;      // 累计补偿上限 [mm]，域 0.5~50 / Trim accumulation limit in millimetres, domain 0.5 to 50
    fSpeed_mmS      : REAL := 100.0;      // 运行速度 [mm/s]，域 1~500 / Run speed in millimetres per second, domain 1 to 500
    fAccel_mmS2     : REAL := 1000.0;     // 加速度 [mm/s²]，域 10~5000（仅门禁校验） / Acceleration, domain 10 to 5000, gate check only
    tSettle         : TIME := T#200MS;    // 停稳确认时长 [ms]，域 10~500 / Settle confirmation time, domain 10 to 500 ms
END_VAR
VAR_IN_OUT
    iAxis           : I_DL_StepperOpenLoop; // 供料带开环步进契约引用 [—] / Feeder belt open-loop stepper contract reference
END_VAR
VAR_OUTPUT
    fStepCmd_mm     : REAL;               // 本次实际步距（含补偿）[mm] / Effective step distance including trim
    fTrimAccum_mm   : REAL;               // 累计补偿量 [mm] / Accumulated trim in millimetres
    bDone           : BOOL;               // 送料完成脉冲，单拍有效 / Index completion pulse, valid for one scan
    bBusy           : BOOL;               // 送料进行中 / Index in progress
    bError          : BOOL;               // 故障级标志，仅故障级码置位 / Fault-class flag, set on fault codes only
    uIndexCnt       : UDINT;              // 累计送料次数 [次] / Total index count
    eErr            : UDINT;              // 错误码，段位 16#0004_xxxx / Error code in segment 16#0004_xxxx
END_VAR
VAR
    _eState         : E_DL_FeederState := E_DL_FeederState.eIdle; // 当前相位 / Current phase
    _bInit          : BOOL := FALSE;      // 首扫标志，取非判定 / First-scan flag, tested negated
    _bRefOk         : BOOL;               // 契约引用有效标志 / Contract reference valid flag
    _bParamOk       : BOOL;               // 参数门禁通过标志 / Parameter gate pass flag
    _bIssueScan     : BOOL;               // 派单当拍标志（本拍不判就绪） / Dispatch scan flag, readiness is not judged in this scan
    _bFaultLatch    : BOOL;               // 故障锁存标志 / Fault latch flag
    _fStepRaw       : REAL;               // 补偿后原始步距 [mm] / Raw step distance after trim
    _fStepEff       : REAL;               // 钳制后生效步距 [mm] / Effective step distance after clamping
    _fAccumNew      : REAL;               // 拟施加的累计补偿 [mm] / Trim accumulation to be applied
    _fSpeedEff      : REAL := 100.0;      // 生效速度（下限兜底）[mm/s] / Effective speed with a lower bound guard
    _uLatchCode     : UDINT;              // 锁存码载体 / Latch code carrier
    _rtrigIndex     : R_TRIG;             // 送料请求上升沿 / Rising edge of the index request
    _rtrigEnable    : R_TRIG;             // 使能上升沿 / Rising edge of the enable input
    _tonSettle      : TON;                // 停稳确认计时 / Settle confirmation timer
END_VAR
VAR CONSTANT
    DL_FDR_READY      : UDINT := 16#0004_032C;  // 就绪/完成码 / Ready or completion code
    DL_FDR_AXIS_REJ   : UDINT := 16#0004_032D;  // 故障级轴拒绝码 / Fault code for a rejected axis command
    DL_FDR_CFG_BAD    : UDINT := 16#0004_032E;  // 故障级组态非法码 / Fault code for bad configuration
    DL_FDR_CLAMP      : UDINT := 16#0004_032F;  // 信息级步距钳制码 / Info code for a clamped step distance
    DL_FDR_ACCUM_MAX  : UDINT := 16#0004_0330;  // 故障级累计补偿越限码 / Fault code for trim accumulation overflow
    DL_FDR_PITCH_LO   : REAL := 1.0;            // 间距下限 [mm] / Pitch lower bound
    DL_FDR_PITCH_HI   : REAL := 2000.0;         // 间距上限 [mm] / Pitch upper bound
    DL_FDR_OFF_HI     : REAL := 20.0;           // 色标偏差绝对值上限 [mm] / Absolute mark offset bound
    DL_FDR_GAIN_HI    : REAL := 1.0;            // 补偿增益上限 [—] / Trim gain upper bound
    DL_FDR_ACCUM_LO   : REAL := 0.5;            // 累计上限下限 [mm] / Lower bound of the accumulation limit
    DL_FDR_ACCUM_HI   : REAL := 50.0;           // 累计上限上限 [mm] / Upper bound of the accumulation limit
    DL_FDR_SPD_LO     : REAL := 1.0;            // 速度下限 [mm/s] / Speed lower bound
    DL_FDR_SPD_HI     : REAL := 500.0;          // 速度上限 [mm/s] / Speed upper bound
    DL_FDR_STEP_LO_K  : REAL := 0.5;            // 步距下限系数 [倍间距] / Step distance lower factor
    DL_FDR_STEP_HI_K  : REAL := 1.5;            // 步距上限系数 [倍间距] / Step distance upper factor
    DL_FDR_EPS        : REAL := 1.0E-6;         // 浮点判零容差 [—] / Float zero tolerance
END_VAR

// 段 1｜输出与单拍标志预置
bDone := FALSE;                                     // 完成脉冲预清 / Completion pulse pre-cleared
bBusy := FALSE;                                     // 运行标志预清 / Busy flag pre-cleared
bError := FALSE;                                    // 故障标志预清 / Fault flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
_bIssueScan := FALSE;                               // 派单当拍标志预清 / Dispatch scan flag pre-cleared

// 段 2｜沿检测无条件周期刷新（严禁置于分支内）
_rtrigIndex(CLK := bIndexReq);                      // 送料请求沿 / Index request edge
_rtrigEnable(CLK := bEnable);                       // 使能沿 / Enable edge

// 段 2.5｜停稳定时器无条件周期刷新（仅在停稳相计时）
_tonSettle(IN := (_eState = E_DL_FeederState.eSettling), PT := tSettle);

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eState := E_DL_FeederState.eIdle;              // 相位待机起步 / Phase starts idle
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜使能上升沿：清补偿累计与锁存（班次重启语义）
IF _rtrigEnable.Q THEN
    _bFaultLatch := FALSE;                          // 使能沿为锁存解除路径 / The enable edge releases the latch
    _uLatchCode := 0;                               // 锁存码清 / Latch code cleared
    _fAccumNew := 0.0;                              // 累计补偿清零（班次重启）[mm] / Trim accumulation cleared at shift restart
    _eState := E_DL_FeederState.eIdle;              // 相位复位 / Phase reset
END_IF

// 段 5｜契约引用有效性 + 参数门禁逐拍重算（非有限用自反比较）
_bRefOk := (iAxis <> 0);                            // 引用注入判据 / Reference injected flag
_bParamOk := _bRefOk
         AND NOT ((fPitch_mm <> fPitch_mm) OR ((fPitch_mm - fPitch_mm) <> (fPitch_mm - fPitch_mm)))
         AND NOT ((fMarkOffset_mm <> fMarkOffset_mm) OR ((fMarkOffset_mm - fMarkOffset_mm) <> (fMarkOffset_mm - fMarkOffset_mm)))
         AND NOT ((fTrimGain <> fTrimGain) OR ((fTrimGain - fTrimGain) <> (fTrimGain - fTrimGain)))
         AND NOT ((fTrimAccumMax_mm <> fTrimAccumMax_mm) OR ((fTrimAccumMax_mm - fTrimAccumMax_mm) <> (fTrimAccumMax_mm - fTrimAccumMax_mm)))
         AND (fPitch_mm >= DL_FDR_PITCH_LO) AND (fPitch_mm <= DL_FDR_PITCH_HI)
         AND (ABS(fMarkOffset_mm) <= DL_FDR_OFF_HI)
         AND (fTrimGain >= 0.0) AND (fTrimGain <= DL_FDR_GAIN_HI)
         AND (fTrimAccumMax_mm >= DL_FDR_ACCUM_LO) AND (fTrimAccumMax_mm <= DL_FDR_ACCUM_HI)
         AND (fSpeed_mmS >= DL_FDR_SPD_LO) AND (fSpeed_mmS <= DL_FDR_SPD_HI)
         AND (fAccel_mmS2 >= 10.0) AND (fAccel_mmS2 <= 5000.0)
         AND (tSettle >= T#10MS) AND (tSettle <= T#500MS);
_fSpeedEff := LIMIT(DL_FDR_SPD_LO, fSpeed_mmS, DL_FDR_SPD_HI);  // 生效速度钳制 [mm/s] / Effective speed after clamping

// 段 6｜失能闸：立即停止受理，相位回空闲（不锁存故障）
IF NOT bEnable THEN
    _eState := E_DL_FeederState.eIdle;              // 相位回空闲 / Phase back to idle
    eErr := DL_FDR_READY;                           // 失能为正常停机，只回就绪码 / Disable is a normal stop, ready code only
ELSE

    // 段 7｜送料状态机（ENUM + CASE + ELSE 兜底）
    CASE _eState OF

        E_DL_FeederState.eIdle:                     // 空闲：受理请求沿 + 参数与上限校验
            IF _rtrigIndex.Q THEN
                IF NOT _bParamOk THEN
                    eErr := DL_FDR_CFG_BAD;         // 故障级：组态非法 / Fault, bad configuration
                    _uLatchCode := DL_FDR_CFG_BAD;
                    _bFaultLatch := TRUE;
                    bError := TRUE;
                    _eState := E_DL_FeederState.eFault;
                ELSE
                    _fAccumNew := fTrimAccum_mm + (fMarkOffset_mm * fTrimGain);   // 拟施加累计补偿 [mm] / Trim accumulation to be applied
                    IF (ABS(_fAccumNew) > fTrimAccumMax_mm) THEN
                        eErr := DL_FDR_ACCUM_MAX;   // 故障级：累计补偿越上限，停送 / Fault, trim accumulation beyond the limit, feeding stopped
                        _uLatchCode := DL_FDR_ACCUM_MAX;
                        _bFaultLatch := TRUE;
                        bError := TRUE;
                        _eState := E_DL_FeederState.eFault;
                    ELSE
                        _fStepRaw := fPitch_mm + (fMarkOffset_mm * fTrimGain);         // 补偿后步距 [mm] / Step distance after trim
                        _fStepEff := _fStepRaw;                                       // 生效步距初值 [mm] / Effective step initial value
                        IF _fStepRaw < (fPitch_mm * DL_FDR_STEP_LO_K) THEN
                            _fStepEff := fPitch_mm * DL_FDR_STEP_LO_K;                // 下限钳制（防倒料）[mm] / Lower clamp, prevents reverse feeding
                            eErr := DL_FDR_CLAMP;                                     // 信息级：步距已钳制 / Info, step distance clamped
                        END_IF
                        IF _fStepRaw > (fPitch_mm * DL_FDR_STEP_HI_K) THEN
                            _fStepEff := fPitch_mm * DL_FDR_STEP_HI_K;                // 上限钳制（防冲料）[mm] / Upper clamp, prevents overshoot feeding
                            eErr := DL_FDR_CLAMP;                                     // 信息级：步距已钳制 / Info, step distance clamped
                        END_IF
                        IF ABS(_fStepEff - _fStepRaw) < DL_FDR_EPS THEN
                            eErr := DL_FDR_READY;                                     // 未钳制：就绪码 / No clamping, ready code
                        END_IF
                        fStepCmd_mm := _fStepEff;                                     // 本次步距出口 [mm] / Step distance output
                        IF iAxis.MoveRelative(_fStepEff, _fSpeedEff) THEN
                            _bIssueScan := TRUE;                                      // 派单当拍不判就绪 / Readiness is not judged in the dispatch scan
                            bBusy := TRUE;
                            _eState := E_DL_FeederState.eIndexing;                    // 进入送料相 / Enter the indexing phase
                        ELSE
                            eErr := DL_FDR_AXIS_REJ;                                  // 故障级：轴拒绝指令 / Fault, the axis rejected the command
                            _uLatchCode := DL_FDR_AXIS_REJ;
                            _bFaultLatch := TRUE;
                            bError := TRUE;
                            _eState := E_DL_FeederState.eFault;
                        END_IF
                    END_IF
                END_IF
            END_IF

        E_DL_FeederState.eIndexing:                 // 送料中：请求一律丢弃（不排队），等轴就绪
            bBusy := TRUE;
            IF _bIssueScan THEN
                _bIssueScan := FALSE;                   // 派单拍已过，下一拍开始判就绪 / The dispatch scan has passed, readiness is judged from the next scan
            ELSIF iAxis.bReady THEN
                _eState := E_DL_FeederState.eSettling;  // 轴就绪：进入停稳确认 / Axis ready, enter the settle phase
            END_IF

        E_DL_FeederState.eSettling:                 // 停稳确认：计时满即完成
            bBusy := TRUE;
            IF _tonSettle.Q THEN
                uIndexCnt := uIndexCnt + 1;             // 累计送料次数 +1 [次] / Index count incremented
                bDone := TRUE;                          // 单拍完成脉冲（下一拍段 1 预清即自清） / One-scan completion pulse, self-cleared in the next scan
                eErr := DL_FDR_READY;                   // 就绪/完成码 / Ready or completion code
                bBusy := FALSE;
                _eState := E_DL_FeederState.eIdle;      // 回空闲 / Back to idle
            END_IF

        E_DL_FeederState.eFault:                    // 故障：锁存码保持，仅使能沿重启
            bBusy := FALSE;
            eErr := _uLatchCode;                        // 锁存码回放 / Replay the latch code
            bError := TRUE;                             // 故障级标志保持 / Fault flag held

        ELSE
            // 非法状态兜底（故障级，组态非法码承载）
            eErr := DL_FDR_CFG_BAD;                     // 故障级：非法相位 / Fault, illegal phase
            _uLatchCode := DL_FDR_CFG_BAD;
            _bFaultLatch := TRUE;
            bError := TRUE;
            bBusy := FALSE;
            _eState := E_DL_FeederState.eFault;

    END_CASE
END_IF

// 段 8｜累计补偿出口单点写入（全件唯一写点，禁两处赋值）
fTrimAccum_mm := _fAccumNew;                        // 累计补偿出口 [mm] / Trim accumulation output in millimetres
END_FUNCTION_BLOCK
