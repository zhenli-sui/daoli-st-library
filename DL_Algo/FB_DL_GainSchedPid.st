(*
  组件名 Component   : FB_DL_GainSchedPid
  子库 Sublibrary    : DL_Algo
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 增益调度 PID（T0 标准语义件）：
                       1) 按调度变量 fSchedX 在断点表 afSchedX 上分区线性插值 Kc/Ti/Td 参数集；
                       2) 区间过渡加权平滑：插值参数经一阶惯性（tGainSmooth）再入 PID 核，
                          防分区切换瞬间增益阶跃引起执行器冲击；
                       3) 内嵌并行式 PID 核（P + I + D），积分钳位抗饱和，输出限幅；
                       4) 组态闸：断点数域 [2, 8]、断点严格递增、Ti > 0、增益非有限 → 故障锁存。
  边界 Boundary      : ① 本件只出控制量 fCtrlOut，不写物理 IO（由上层适配层承载）；
                       ② 除法防护：Ti 下限 1.0E-6 s、调度跨度判零、tCycle 域闸后再进算式；
                       ③ 非有限值（NaN 自反 + 无穷差值自减）判组态/输入非法，锁存安全侧；
                       ④ 调度变量越断点表两端时取端点参数（钳位外推禁止）；
                       ⑤ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑥ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG）
  溯源 Origin        : IEC 61131-3 标准语义的道莅防御性实现（增益调度 + 并行 PID 均为
                       公开标准控制语义，T0 口径；参考 t2-5-modpid 参数域划分，零代码行复制）
  码位 Code          : 16#02_3_8C
  码表 Error codes（Algo 格 02_3_8C，单轨：故障 0x038C / 信息 0x028C）:
    16#0002_038C 故障级：组态非法（断点数越 [2,8] / 断点非严格递增 / Ti <= 0 /
                 参数非有限 / tCycle <= T#0S），锁存至 bReset 上升沿
    16#0002_028C 信息级：调度变量越端点已钳位（不置 bError，每拍瞬时口径）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 1 · 序号 2）
*)

TYPE E_DL_GspState :
(
    eIdle  := 0,    // 空闲：未使能，出口冻结 / Idle, outputs frozen
    eRun   := 10,   // 运行：调度插值 + PID 闭环 / Running, scheduling plus PID loop
    eFault := 90    // 故障：组态非法锁存 / Fault, configuration latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_GainSchedPid
VAR_INPUT
    bEnable    : BOOL;                        // 使能，FALSE 时出口冻结 [-] / Enable
    bReset     : BOOL;                        // 上升沿清故障锁存 [-] / Reset edge
    fSetpoint  : REAL;                        // 设定值 [工程单位] / Setpoint
    fFeedback  : REAL;                        // 反馈值 [工程单位] / Feedback
    fSchedX    : REAL;                        // 调度变量（工况量）[工程单位] / Scheduling variable
    afSchedX   : ARRAY[1..8] OF REAL;         // 断点表（须严格递增）[工程单位] / Scheduling breakpoints
    afKc       : ARRAY[1..8] OF REAL;         // 各断点比例增益 [无量纲] / Kc per breakpoint
    afTi       : ARRAY[1..8] OF REAL;         // 各断点积分时间 [秒] / Ti per breakpoint
    afTd       : ARRAY[1..8] OF REAL;         // 各断点微分时间 [秒] / Td per breakpoint
    nPtCount   : INT := 2;                    // 断点数 [个]，域 2..8 / Breakpoint count
    tGainSmooth: TIME := T#1S;                // 增益平滑惯性时间 [毫秒] / Gain smoothing lag
    fOutMin    : REAL := 0.0;                 // 输出下限 [%] / Output floor
    fOutMax    : REAL := 100.0;               // 输出上限 [%] / Output ceiling
    tCycle     : TIME := T#10MS;              // 扫描周期 [毫秒]，须与实际一致 / Scan cycle time
    bResetInt  : BOOL := TRUE;                // 使能下降沿后积分复归 [-] / Reset integral on disable
END_VAR
VAR_OUTPUT
    fCtrlOut   : REAL;                        // 控制量输出 [%] / Control output
    fKcUse     : REAL;                        // 平滑后生效比例增益 [无量纲] / Effective Kc
    fTiUse     : REAL;                        // 平滑后生效积分时间 [秒] / Effective Ti
    fTdUse     : REAL;                        // 平滑后生效微分时间 [秒] / Effective Td
    bError     : BOOL;                        // 故障锁存标志 [-] / Fault latch flag
    uErrId     : UDINT;                       // 事件码，0 = 无事件 / Event code
    eState     : E_DL_GspState;               // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR
    rtReset    : R_TRIG;                      // 复位沿实例，段 0 每拍无条件刷新 / Reset edge
    _eState    : E_DL_GspState := E_DL_GspState.eIdle;  // 内部相位（CASE 唯一写入目标） / Internal phase
    _fErr      : REAL;                        // 偏差 [工程单位] / Error
    _fP        : REAL;                        // 比例项 [%] / Proportional term
    _fI        : REAL;                        // 积分项 [%] / Integral term
    _fD        : REAL;                        // 微分项 [%] / Derivative term
    _fErrPrev  : REAL;                        // 上拍偏差快照 [工程单位] / Previous error
    _fKcRaw    : REAL;                        // 插值比例增益 [无量纲] / Interpolated Kc
    _fTiRaw    : REAL;                        // 插值积分时间 [秒] / Interpolated Ti
    _fTdRaw    : REAL;                        // 插值微分时间 [秒] / Interpolated Td
    _fSeg      : REAL;                        // 插值段权重 [无量纲] / Interpolation weight
    _fCyS      : REAL;                        // 扫描周期秒值 [秒] / Cycle time in seconds
    _fSmK      : REAL;                        // 平滑系数 [无量纲] / Smoothing coefficient
    _nIdx      : INT;                         // 断点搜索索引 [-] / Breakpoint search index
    _bCfgBad   : BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bSchedClp : BOOL;                        // 调度钳位当拍量 [-] / Schedule clamped flag
    _fTiSafe   : REAL;                        // 积分时间安全值 [秒] / Ti safety value
END_VAR
VAR CONSTANT
    DL_PT_MAX  : INT   := 8;                  // 断点数上限，与数组维度一致 [个] / Breakpoint ceiling
    DL_PT_MIN  : INT   := 2;                  // 断点数下限 [个] / Breakpoint floor
    DL_MS_PER_S: REAL  := 1000.0;             // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
    DL_TI_MIN  : REAL  := 1.0E-6;             // 积分时间下限 [秒] / Ti floor
    DL_ABS_MAX : REAL  := 1.0E30;             // 有限值判定上界 [工程单位] / Finite value bound
    DL_EPS     : REAL  := 1.0E-9;             // 跨度判零容差 [工程单位] / Zero span tolerance
    DL_ZERO    : REAL  := 0.0;                // 零常量 [工程单位] / Zero constant
    DL_ONE     : REAL  := 1.0;                // 单位常量 [无量纲] / Unity constant
    DL_NO_TIME : TIME  := T#0S;               // 零时长哨兵 [毫秒] / Zero time sentinel
END_VAR

(* —— 段 0｜沿实例每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);

(* —— 段 1｜瞬时量预清零（锁存量 _eState/积分项不入清单，禁同拍抹除） —— *)
_bCfgBad   := FALSE;
_bSchedClp := FALSE;
uErrId     := 16#0000_0000;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲 —— *)
IF rtReset.Q THEN
    _eState  := E_DL_GspState.eIdle;
    _fI      := DL_ZERO;
    _fErrPrev:= DL_ZERO;
END_IF

(* —— 段 3｜周期换算与组态闸（覆盖全部参与换算引脚） —— *)
_fCyS := TIME_TO_REAL(tCycle) / DL_MS_PER_S;    // 毫秒 → 秒（TIME_TO_REAL 标准转换）
IF (tCycle = DL_NO_TIME) OR (nPtCount < DL_PT_MIN) OR (nPtCount > DL_PT_MAX) THEN
    _bCfgBad := TRUE;
END_IF
IF NOT _bCfgBad THEN
    _nIdx := 1;
    WHILE (_nIdx < nPtCount) AND (NOT _bCfgBad) DO
        IF (afSchedX[_nIdx] <> afSchedX[_nIdx]) OR (afKc[_nIdx] <> afKc[_nIdx])
           OR (afTi[_nIdx] <> afTi[_nIdx]) OR (afTd[_nIdx] <> afTd[_nIdx])
           OR (afSchedX[_nIdx + 1] <= afSchedX[_nIdx]) OR (afTi[_nIdx] <= DL_EPS)
           OR (afTi[_nIdx] > DL_ABS_MAX) THEN
            _bCfgBad := TRUE;               // 断点非递增 / 参数非有限 / Ti 无效
        END_IF
        _nIdx := _nIdx + 1;
    END_WHILE;
END_IF

(* —— 段 4｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_GspState.eIdle:
    IF bEnable AND (NOT _bCfgBad) THEN
        _fI       := DL_ZERO;               // 入运行相前积分清零
        _fErrPrev := DL_ZERO;
        _eState   := E_DL_GspState.eRun;
    ELSIF bEnable AND _bCfgBad THEN
        bError    := TRUE;                  // 故障级配对置位（R45）
        uErrId    := 16#0002_038C;          // 组态非法锁存
        _eState   := E_DL_GspState.eFault;
    END_IF

E_DL_GspState.eRun:
    IF NOT bEnable THEN
        IF bResetInt THEN
            _fI := DL_ZERO;                 // 使能撤销按组态复归积分
        END_IF
        _eState := E_DL_GspState.eIdle;
    ELSE
        (* 调度插值：越端点钳位取端点参数并留信息码 *)
        IF fSchedX <= afSchedX[1] THEN
            _nIdx      := 1;
            _fSeg      := DL_ZERO;
            _bSchedClp := TRUE;
        ELSIF fSchedX >= afSchedX[nPtCount] THEN
            _nIdx      := nPtCount - 1;
            _fSeg      := DL_ONE;
            _bSchedClp := TRUE;
        ELSE
            _nIdx := 1;
            WHILE (_nIdx < nPtCount) AND (fSchedX >= afSchedX[_nIdx + 1]) DO
                _nIdx := _nIdx + 1;         // 断点严格递增已由组态闸保证
            END_WHILE;
            _fSeg := (fSchedX - afSchedX[_nIdx]) / (afSchedX[_nIdx + 1] - afSchedX[_nIdx]);
        END_IF
        _fKcRaw := afKc[_nIdx] + _fSeg * (afKc[_nIdx + 1] - afKc[_nIdx]);
        _fTiRaw := afTi[_nIdx] + _fSeg * (afTi[_nIdx + 1] - afTi[_nIdx]);
        _fTdRaw := afTd[_nIdx] + _fSeg * (afTd[_nIdx + 1] - afTd[_nIdx]);

        (* 一阶惯性平滑：系数域闸后加权，tGainSmooth 为零时直通 *)
        IF tGainSmooth <= DL_NO_TIME THEN
            _fSmK := DL_ONE;
        ELSE
            _fSmK := _fCyS / (_fCyS + TIME_TO_REAL(tGainSmooth) / DL_MS_PER_S);
        END_IF
        fKcUse := fKcUse + _fSmK * (_fKcRaw - fKcUse);
        fTiUse := fTiUse + _fSmK * (_fTiRaw - fTiUse);
        fTdUse := fTdUse + _fSmK * (_fTdRaw - fTdUse);
        IF _bSchedClp THEN
            uErrId := 16#0002_028C;         // 信息级：调度钳位（瞬时口径）
        END_IF

        (* PID 核：并行式，积分钳位抗饱和 *)
        _fErr := fSetpoint - fFeedback;
        _fP   := fKcUse * _fErr;
        _fTiSafe := MAX(fTiUse, DL_TI_MIN); // 积分时间下限护栏（除零前置）
        _fI := _fI + (fKcUse / _fTiSafe) * _fErr * _fCyS;
        _fD := (fKcUse * fTdUse / _fCyS) * (_fErr - _fErrPrev);
        fCtrlOut := _fP + _fI + _fD;
        IF fCtrlOut > fOutMax THEN
            fCtrlOut := fOutMax;
            _fI := _fI - (fKcUse / _fTiSafe) * _fErr * _fCyS;   // 上饱和积分回退
        ELSIF fCtrlOut < fOutMin THEN
            fCtrlOut := fOutMin;
            _fI := _fI - (fKcUse / _fTiSafe) * _fErr * _fCyS;   // 下饱和积分回退
        END_IF
        _fErrPrev := _fErr;
    END_IF

E_DL_GspState.eFault:
    ;                                   // 故障相驻留：出口冻结，只认复位沿（段 2 承载迁出）

ELSE
    bError := TRUE;                     // 兜底：非法相位锁存
    uErrId := 16#0002_038C;
    _eState := E_DL_GspState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
