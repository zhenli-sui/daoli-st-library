(*
  组件名 Component   : FB_DL_CellAgingRestSeq
  子库 Sublibrary    : DL_Process
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 电芯老化静置顺控（自研行业池：锂电）：
                       1) 静置计时：tRestDur 总静置时长承载（独立 TON）；
                       2) 抽测窗口：静置相内周期开抽测窗（周期计 tonSampleInt 自复触，
                       R188），窗长 tSampleWin；窗口结束后锁存最后一次抽测值；
                       3) 时限到期判级出柜：静置时长到 → 按末次抽测电压与内阻判级
                       （合格 ePass / 降级 eMarginal / 不合格 eFail），结果锁存至复位；
                       4) 静置中断判据：抽测窗内电压越域持续 tVoltDevTo → 故障锁存。
  边界 Boundary      : ① 本件只出抽测请求与判级结论，不驱动充放电（老化柜本体自控）；
                       ② 判级只认末次抽测锁存值（禁按当下输入重推断，R152）；
                       ③ 周期窗计时自复触范式（R188），静置/窗口/越带确认独立实例；
                       ④ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑤ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（自研行业池：锂电老化静置共性语义，
                       零外部代码行复制）
  码位 Code          : 16#06_0_C0（Process 段 0006，C 子带 C0 格）
  码表 Error codes（本件格 06_0_C0，单轨子道：故障 0x02C0 / 信息 0x01C0）:
    16#0006_02C0 故障级：静置顺控故障总码（电压越域 / 组态非法 / 输入非有限），
                 锁存至复位
    16#0006_01C0 信息级：判级完成沿（ePass/eMarginal/eFail 写定拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 4 · 序号 17）
*)

TYPE E_DL_CarPhase :
(
    eIdle     := 0,   // 空闲：未使能 / Idle, not enabled
    eRest     := 10,  // 静置：计时 + 周期抽测 / Resting with periodic sampling
    eSample   := 20,  // 抽测：窗口驻留 / Sampling window dwell
    eGrade    := 30,  // 判级：末次抽测定级 / Grading from last sample
    eDone     := 40,  // 完成：结论驻留 / Done, verdict held
    eFault    := 90   // 故障：总码锁存 / Fault, latched
);
END_TYPE

TYPE E_DL_CarGrade :
(
    eNone     := 0,   // 无结论 / No verdict
    ePass     := 10,  // 合格：电压内阻双达标 / Pass
    eMarginal := 20,  // 降级：电压入降级带 / Marginal
    eFail     := 30   // 不合格：越降级带下限或内阻不足 / Fail
);
END_TYPE

FUNCTION_BLOCK FB_DL_CellAgingRestSeq
VAR_INPUT
    bEnable     : BOOL;                  // 使能（电平）[-] / Enable
    bReset      : BOOL;                  // 上升沿清故障锁存 [-] / Reset edge
    fCellVoltV  : REAL;                  // 电芯实测电压 [伏特] / Cell voltage
    fIrMohm     : REAL;                  // 电芯实测内阻 [毫欧] / Internal resistance
    tRestDur    : TIME := T#72H;         // 总静置时长 [毫秒] / Total rest duration
    tSampleInt  : TIME := T#4H;          // 抽测周期 [毫秒] / Sample interval
    tSampleWin  : TIME := T#60S;         // 抽测窗口长 [毫秒] / Sample window duration
    fVoltPassLoV: REAL := 3.60;          // 合格电压下限 [伏特] / Pass voltage floor
    fVoltMargLoV: REAL := 3.50;          // 降级电压下限 [伏特] / Marginal voltage floor
    fIrMinMohm  : REAL := 1.0;           // 合格内阻下限 [毫欧] / IR pass floor
    tVoltDevTo  : TIME := T#10S;         // 电压越域确认窗 [毫秒] / Voltage deviation timeout
END_VAR
VAR_OUTPUT
    bSampleReq  : BOOL;                  // 抽测请求电平（窗口相）[-] / Sample request level
    fVoltLastV  : REAL;                  // 末次抽测电压 [伏特] / Last sampled voltage
    fIrLastMohm : REAL;                  // 末次抽测内阻 [毫欧] / Last sampled IR
    eGrade      : E_DL_CarGrade;         // 判级结论出口 / Grade verdict outlet
    ePhase      : E_DL_CarPhase;         // 相位出口，段尾单点映射 / Phase outlet
    bError      : BOOL;                  // 故障锁存标志 [-] / Fault latch flag
    uErrId      : UDINT;                 // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset    : R_TRIG;                 // 复位沿实例，段 0 无条件刷新 / Reset edge
    tonRestDur : TON;                    // 静置总时长计时（独立实例） / Rest duration timer
    tonSampleInt: TON;                   // 抽测周期计（自复触，R188） / Sample interval timer
    tonSampleWin: TON;                   // 抽测窗口计时（独立实例） / Sample window timer
    tonVoltDevTo: TON;                   // 电压越域确认（专用超时件命名） / Voltage timeout
    _ePhase    : E_DL_CarPhase := E_DL_CarPhase.eIdle;    // 内部相位（CASE 唯一写入目标）/ Internal phase
    _eGrade    : E_DL_CarGrade := E_DL_CarGrade.eNone;    // 内部判级（锁存量）/ Internal grade
    _bFault    : BOOL;                   // 故障锁存位（锁存量） / Latched fault bit
    _uFault    : UDINT;                  // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad   : BOOL;                   // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin   : BOOL;                   // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_ABS_MAX : REAL := 1.0E30;         // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO    : REAL := 0.0;            // 零常量 [工程单位] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内；各实例独立禁复用） —— *)
rtReset(CLK := bReset);
tonRestDur (IN := (_ePhase = E_DL_CarPhase.eRest) AND (NOT _bFault), PT := tRestDur);
tonSampleInt(IN := (_ePhase = E_DL_CarPhase.eRest) AND (NOT _bFault) AND (NOT tonSampleInt.Q),
             PT := tSampleInt);          // 自复触周期窗：Q 拍断开一拍（R188）
tonSampleWin(IN := (_ePhase = E_DL_CarPhase.eSample) AND (NOT _bFault), PT := tSampleWin);
tonVoltDevTo(IN := (_ePhase = E_DL_CarPhase.eSample) AND ((fCellVoltV > fVoltPassLoV)
              OR (fCellVoltV < fVoltMargLoV)) AND (NOT _bFault), PT := tVoltDevTo);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/_eGrade/fVoltLastV/fIrLastMohm 不入清单） —— *)
uErrId   := 16#0000_0000;
bSampleReq := FALSE;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障与判级一次性清干净，相位回空闲 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eGrade := E_DL_CarGrade.eNone;
    _ePhase := E_DL_CarPhase.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与判据换算引脚） —— *)
IF (fVoltMargLoV >= fVoltPassLoV) OR (fIrMinMohm <= DL_ZERO) OR (tRestDur = T#0S)
   OR (tSampleInt = T#0S) OR (tSampleWin = T#0S) OR (tVoltDevTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fCellVoltV <> fCellVoltV) OR ((fCellVoltV - fCellVoltV) <> DL_ZERO)
   OR (fIrMohm <> fIrMohm) OR ((fIrMohm - fIrMohm) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：六态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF

E_DL_CarPhase.eIdle:
    IF bEnable AND (NOT _bCfgBad) THEN
        _ePhase := E_DL_CarPhase.eRest;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C0;
        bError  := TRUE;
        _ePhase := E_DL_CarPhase.eFault;
    END_IF

E_DL_CarPhase.eRest:
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C0;
        bError  := TRUE;
        _ePhase := E_DL_CarPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_CarPhase.eIdle;  // 使能撤销回空闲
    ELSIF tonSampleInt.Q THEN
        _ePhase := E_DL_CarPhase.eSample;    // 抽测周期到：开抽测窗
    ELSIF tonRestDur.Q THEN
        _ePhase := E_DL_CarPhase.eGrade;     // 静置时长到：进判级相
    END_IF

E_DL_CarPhase.eSample:
    bSampleReq := TRUE;                  // 抽测请求电平（窗口相电平）
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C0;
        bError  := TRUE;
        _ePhase := E_DL_CarPhase.eFault;
    ELSIF tonVoltDevTo.Q THEN
        _bFault := TRUE;                 // 窗内电压越域持续：锁存
        _uFault := 16#0006_02C0;
        bError  := TRUE;
        _ePhase := E_DL_CarPhase.eFault;
    ELSIF tonSampleWin.Q THEN
        fVoltLastV := fCellVoltV;        // 窗口结束：末次抽测值锁存（R152）
        fIrLastMohm := fIrMohm;
        bSampleReq := FALSE;
        _ePhase := E_DL_CarPhase.eRest;  // 回静置相（抽测周期重新起算）
    END_IF

E_DL_CarPhase.eGrade:
    (* 判级只认末次抽测锁存值（禁按当下输入重推断） *)
    IF (fVoltLastV >= fVoltPassLoV) AND (fIrLastMohm >= fIrMinMohm) THEN
        _eGrade := E_DL_CarGrade.ePass;  // 合格：双达标
    ELSIF (fVoltLastV >= fVoltMargLoV) AND (fIrLastMohm >= fIrMinMohm) THEN
        _eGrade := E_DL_CarGrade.eMarginal;      // 降级：电压入降级带
    ELSE
        _eGrade := E_DL_CarGrade.eFail;  // 不合格：越降级带或内阻不足
    END_IF
    uErrId := 16#0006_01C0;              // 信息级：判级完成沿
    _ePhase := E_DL_CarPhase.eDone;

E_DL_CarPhase.eDone:
    ;                                    // 结论锁存驻留（eGrade 出口回放），等复位或使能撤销
    IF NOT bEnable THEN
        _ePhase := E_DL_CarPhase.eIdle;  // 使能撤销回空闲（待机可返回路径）
    END_IF

E_DL_CarPhase.eFault:
    bError := TRUE;                      // 故障相驻留：判级与抽测值冻结，只认复位沿（段 2 迁出）
    ;                                    // （冻结语义：fVoltLastV/fIrLastMohm/_eGrade 保持）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0006_02C0;
    bError  := TRUE;
    _ePhase := E_DL_CarPhase.eFault;
END_CASE

(* —— 段 5｜相位与判级出口单点映射（名实同源） —— *)
eGrade := _eGrade;
ePhase := _ePhase;
END_FUNCTION_BLOCK
