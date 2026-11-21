(*
  组件名 Component   : FB_DL_CoolingTowerReset
  子库 Sublibrary    : DL_Process
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 冷塔出水温度重置（DewpointReset 同族、对象不同）：
                       1) 重置计算：出水温度设定 = 湿球温度 + 逼近度目标
                       （fOutSpC := fWetBulbC + fApproachTargetK）；
                       2) 湿球下限保护：湿球低于 fWetBulbMinC → 保护标志置位，
                       设定值按湿球下限折算并冻结重置下调（防过冷结冰）；
                       3) 两级执行：逼近度误差 > 台级上调阈 → 加开一台风机；误差 <
                       台级下调阈 → 停一台风机（台级驻留 uDwellScan 拍内禁再切台）；
                       频率细调 = 误差 / 误差满跨 × 频率区间（除子域闸承载）；
                       4) 信息级：台级切换沿与湿球保护进入沿随行。
  边界 Boundary      : ① 本件只出风机台数与频率指令，不写物理 IO；
                       ② 频率细调除法前置域闸：fErrSpanK <= 0 判组态非法；
                       ③ 台级切换驻留扫描计（单计数器，方向翻转清零）；
                       ④ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑤ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t1-2-oscat-building reset 族分类与
                       参数域，零代码行复制）
  码位 Code          : 16#06_0_C3（Process 段 0006，C 子带 C3 格）
  码表 Error codes（本件格 06_0_C3，单轨子道：故障 0x02C3 / 信息 0x01C3 / 0x03C3）:
    16#0006_02C3 故障级：组态非法或输入非有限，锁存至复位
    16#0006_01C3 信息级：风机台级切换沿（nFanCmd 变更拍）
    16#0006_03C3 信息级：湿球保护进入沿（bWbProtect 由 FALSE 转 TRUE 拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 4 · 序号 20）
*)

TYPE E_DL_CtrState :
(
    eIdle  := 0,    // 空闲：未使能，风机全停 / Idle, fans all off
    eRun   := 10,   // 运行：重置计算 + 两级执行 / Running, reset and two-level actuation
    eFault := 90    // 故障：组态/输入锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoolingTowerReset
VAR_INPUT
    bEnable      : BOOL;                   // 使能（电平）[-] / Enable
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    fWetBulbC    : REAL;                   // 湿球温度 [摄氏度] / Wet-bulb temperature
    fOutTempC    : REAL;                   // 冷塔出水实测温度 [摄氏度] / Tower outlet temperature
    fApproachTargetK: REAL := 3.0;         // 逼近度目标 [开尔文] / Approach target
    fWetBulbMinC : REAL := 5.0;            // 湿球下限 [摄氏度] / Wet-bulb floor
    fErrSpanK    : REAL := 6.0;            // 频率细调误差满跨 [开尔文] / Error span for full speed
    fFanFreqMinHz: REAL := 20.0;           // 风机频率下限 [赫兹] / Fan frequency floor
    fFanFreqMaxHz: REAL := 50.0;           // 风机频率上限 [赫兹] / Fan frequency ceiling
    nFanCountMax : INT := 4;               // 风机总台数 [台] / Fan count
    uDwellScan   : UDINT := 600;           // 台级切换驻留 [拍] / Stage change dwell scans
    tCycle       : TIME := T#1S;           // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    fOutSpC      : REAL;                   // 出水温度设定 [摄氏度] / Outlet temperature setpoint
    nFanCmd      : INT;                    // 风机运行台数指令 [台] / Fan stage command
    fFanFreqHz   : REAL;                   // 风机频率指令 [赫兹] / Fan frequency command
    bWbProtect   : BOOL;                   // 湿球保护标志 [-] / Wet-bulb protection flag
    eState       : E_DL_CtrState;          // 状态出口，段尾单点映射 / State outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset : R_TRIG;                      // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtFanChg: R_TRIG;                      // 台级切换沿实例，段 0 无条件刷新 / Fan change edge
    rtWbProt: R_TRIG;                      // 保护进入沿实例，段 0 无条件刷新 / Protection entry edge
    _eState : E_DL_CtrState := E_DL_CtrState.eIdle;    // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fErrK  : REAL;                        // 逼近度误差 [开尔文] / Approach error
    _fWbUse : REAL;                        // 保护折算后湿球 [摄氏度] / Effective wet-bulb
    _fErrUse: REAL;                        // 保护折算后误差 [开尔文] / Effective error
    _nFanPrev: INT;                        // 上拍台数镜像 [台] / Previous fan count
    _uDwellCnt: UDINT;                     // 台级驻留扫描计 [拍] / Stage dwell scans
    _bFault : BOOL;                        // 故障锁存位（锁存量） / Latched fault bit
    _uFault : UDINT;                       // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                        // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_FREQ_EPS  : REAL := 1.0E-6;         // 频率区间判零容差 [赫兹] / Frequency band tolerance
    DL_DWELL_MIN : UDINT := UDINT#1;       // 驻留扫描下限 [拍] / Dwell scan floor
    DL_ABS_MAX   : REAL := 1.0E30;         // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO      : REAL := 0.0;            // 零常量 [工程单位] / Zero constant
    DL_ZERO_INT  : INT  := 0;              // 零台常量 [台] / Zero fans
    DL_ONE       : INT  := 1;              // 单位台常量 [台] / One fan
END_VAR

(* —— 段 0｜沿实例每拍无条件刷新（禁置于 IF/CASE 内） —— *)
_fErrK := fOutTempC - (fWetBulbC + fApproachTargetK);   // 逼近度误差当拍量
rtReset (CLK := bReset);
rtFanChg(CLK := (nFanCmd <> _nFanPrev));
rtWbProt(CLK := bWbProtect);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/fOutSpC/nFanCmd 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，风机全停 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    bWbProtect := FALSE;
    nFanCmd := DL_ZERO_INT;
    fFanFreqHz := DL_ZERO;
    _eState := E_DL_CtrState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与判据换算引脚，R28 加固） —— *)
IF (fErrSpanK <= DL_ZERO) OR (fFanFreqMinHz <= DL_FREQ_EPS) OR (fFanFreqMaxHz <= fFanFreqMinHz)
   OR (nFanCountMax < DL_ONE) OR (uDwellScan < DL_DWELL_MIN) THEN
    _bCfgBad := TRUE;
END_IF
IF (fWetBulbC <> fWetBulbC) OR ((fWetBulbC - fWetBulbC) <> DL_ZERO)
   OR (fOutTempC <> fOutTempC) OR ((fOutTempC - fOutTempC) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_CtrState.eIdle:
    fOutSpC := DL_ZERO;                  // 空闲相设定归零（不驱动）
    nFanCmd := DL_ZERO_INT;
    fFanFreqHz := DL_ZERO;
    bWbProtect := FALSE;                 // 空闲相保护标志复归
    IF bEnable AND (NOT _bCfgBad) THEN
        nFanCmd := DL_ONE;               // 入运行相：基线一台
        _nFanPrev := nFanCmd;
        _uDwellCnt := UDINT#0;
        _eState := E_DL_CtrState.eRun;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C3;
        bError  := TRUE;
        _eState := E_DL_CtrState.eFault;
    END_IF

E_DL_CtrState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_CtrState.eIdle;  // 使能撤销回空闲
    ELSE
        (* 湿球下限保护：低于下限按湿球下限折算设定并冻结下调 *)
        IF fWetBulbC < fWetBulbMinC THEN
            bWbProtect := TRUE;
            _fWbUse := fWetBulbMinC;
        ELSE
            bWbProtect := FALSE;
            _fWbUse := fWetBulbC;
        END_IF
        fOutSpC := _fWbUse + fApproachTargetK;   // 重置计算：湿球 + 逼近度目标
        IF rtWbProt.Q THEN
            uErrId := 16#0006_03C3;      // 信息级：湿球保护进入沿
        END_IF
        (* 两级执行之一：台级（误差超阈且驻留满才切台） *)
        IF _bNonFin THEN
            _bFault := TRUE;             // 输入非有限：锁存
            _uFault := 16#0006_02C3;
            bError  := TRUE;
            _eState := E_DL_CtrState.eFault;
        ELSE
            _fErrUse := fOutTempC - fOutSpC;     // 折算后误差（安全侧）
            _uDwellCnt := _uDwellCnt + UDINT#1;  // 驻留扫描累计
            IF (_fErrUse > fErrSpanK) AND (nFanCmd < nFanCountMax)
               AND (_uDwellCnt >= uDwellScan) THEN
                nFanCmd := nFanCmd + DL_ONE;     // 加开一台
                _uDwellCnt := UDINT#0;
            ELSIF (_fErrUse < DL_ZERO) AND (nFanCmd > DL_ZERO_INT)
                  AND (_uDwellCnt >= uDwellScan) THEN
                nFanCmd := nFanCmd - DL_ONE;     // 停一台
                _uDwellCnt := UDINT#0;
            END_IF
            (* 两级执行之二：频率细调（误差满跨映射频率区间，除子域闸已过） *)
            fFanFreqHz := fFanFreqMinHz
                          + MAX(MIN(_fErrUse, fErrSpanK), DL_ZERO) / fErrSpanK
                            * (fFanFreqMaxHz - fFanFreqMinHz);
            IF nFanCmd = DL_ZERO_INT THEN
                fFanFreqHz := DL_ZERO;   // 零台时频率归零（名实双出口一致性）
            END_IF
        END_IF
    END_IF

E_DL_CtrState.eFault:
    nFanCmd := DL_ZERO_INT;              // 故障相：风机全停（安全侧）
    fFanFreqHz := DL_ZERO;
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0006_02C3;
    bError  := TRUE;
    _eState := E_DL_CtrState.eFault;
END_CASE

(* —— 段 5｜台级切换沿与镜像刷新（信息级随行） —— *)
IF rtFanChg.Q THEN
    uErrId := 16#0006_01C3;              // 信息级：台级切换沿
END_IF
_nFanPrev := nFanCmd;                    // 上拍台数镜像刷新

(* —— 段 6｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
