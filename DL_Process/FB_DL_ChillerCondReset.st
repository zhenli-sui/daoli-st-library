(*
  FB_DL_ChillerCondReset  —  冷水机组冷凝压力重置（室外湿球联动限幅） / Chiller condensing-pressure setpoint reset driven by outdoor wet-bulb with clamping
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇冷站冷凝压力重置族深化
  溯源 Origin   : 道莅 clean-room 实现；湿球联动线性重置 + 死区 + 步长限幅为公开 HVAC 节能控制律，未复制任何源码行
  功能 Function : 1) 目标设定 fCondSpKpa = fWetBulbC × fSlopeKpaPerK + fOffsetKpa；
                  2) 硬限幅钳制到 [fSpMinKpa, fSpMaxKpa]（先限幅后限速，顺序固定）；
                  3) 步长限速：单次调用变化量不超过 fStepMaxKpa（向上与向下同限）；
                  4) 死区保持：|候选 - 当前输出| < fDeadbandKpa 时输出保持不变（避免阀位抖动）；
                  5) 故障级单码 03A3，归因由 eCause 独立成员承载（R190）；
                  6) 信息级 04CB = 重置激活沿（进 eRun 单拍）；7) 解除式全当拍量（R240）。
  接口 Interface: 输入湿球/斜率/偏置/上下限/死区/步长；输出设定值与限幅/限速镜像
  边界 Boundary : ① 组态闸：fSlopeKpaPerK <= 0.0、fSpMaxKpa <= fSpMinKpa、fStepMaxKpa <= 0.0、
                  fDeadbandKpa < 0.0、fWetBulbMaxC <= fWetBulbMinC 任一成立 → 03A3 锁存；
                  ② 湿球非有限（NaN 自反 + Inf 差值自减）或越量程 → 03A3 锁存，输出保持上一有效值
                  （冻结保持，非降级）；③ 浮点判据全容差式，禁 = / <> 判等；
                  ④ 无 TON 跨相复用（仅一个激活沿 R_TRIG + 一个 R_TRIG 复位沿），段 0 无条件调用；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 03A3 / 信息窗口 04CB）:
    16#0005_03A3 故障级：冷凝压力重置故障总码（组态非法 / 湿球非有限 / 湿球越量程），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04CB 信息级：重置激活沿（bEnable 上升进入 eRun 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 2 · 序号 7）
*)

TYPE E_DL_CcrState :
(
    eIdle  := 0,      // 未使能：输出冻结上一值 / Idle, output frozen
    eRun   := 10,     // 重置运行中 / Reset active
    eFault := 90      // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_CcrCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eWbNonFin   := 2, // 湿球输入非有限 / Wet-bulb non-finite
    eWbRange    := 3  // 湿球越量程 / Wet-bulb out of range
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChillerCondReset
VAR_INPUT
    fWetBulbC      : REAL := 10.0;     // 室外湿球温度 [°C] / Outdoor wet-bulb temperature
    fWetBulbMinC   : REAL := -20.0;    // 湿球量程下限 [°C] / Wet-bulb range low
    fWetBulbMaxC   : REAL := 45.0;     // 湿球量程上限 [°C] / Wet-bulb range high
    fSlopeKpaPerK  : REAL := 2.0;      // 联动斜率 [kPa/K]，域 > 0 / Reset slope
    fOffsetKpa     : REAL := 400.0;    // 联动偏置 [kPa] / Reset offset
    fSpMinKpa      : REAL := 500.0;    // 设定下限 [kPa] / Setpoint low limit
    fSpMaxKpa      : REAL := 900.0;    // 设定上限 [kPa] / Setpoint high limit
    fDeadbandKpa   : REAL := 5.0;      // 死区 [kPa]，域 >= 0 / Deadband
    fStepMaxKpa    : REAL := 10.0;     // 单次限速步长 [kPa]，域 > 0 / Rate limit step
    bEnable        : BOOL := FALSE;    // 重置使能（电平）[-] / Reset enable
    bReset         : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState         : E_DL_CcrState;    // 状态出口，段 6 单点映射 / State outlet
    eCause         : E_DL_CcrCause;    // 故障成因出口（R190） / Fault cause outlet
    fCondSpKpa     : REAL;             // 冷凝压力设定 [kPa] / Condensing pressure setpoint
    bLimited       : BOOL;             // 限幅生效镜像 [-] / Clamp active mirror
    bDbHold        : BOOL;             // 死区保持镜像 [-] / Deadband hold mirror
    bError         : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId         : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState        : E_DL_CcrState := E_DL_CcrState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause        : E_DL_CcrCause := E_DL_CcrCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtEnable       : R_TRIG;           // 使能沿实例，每周期无条件调用 / Enable edge
    rtReset        : R_TRIG;           // 复位沿实例，每周期无条件调用 / Reset edge
    _fSp           : REAL;             // 设定输出保持槽（持久） / Setpoint holding slot
    _fRawKpa       : REAL;             // 未限幅原始设定 [kPa]（当拍量） / Raw setpoint
    _fClampKpa     : REAL;             // 限幅后候选 [kPa]（当拍量） / Clamped candidate
    _bClampOn      : BOOL;             // 限幅生效当拍量 [-] / Clamp active
    _bNonFin       : BOOL;             // 湿球非有限当拍量 [-] / Wet-bulb non-finite
    _bRangeBad     : BOOL;             // 湿球越量程当拍量 [-] / Wet-bulb out of range
    _bCfgBad       : BOOL;             // 组态非法当拍量 [-] / Config illegal
    _bFault        : BOOL;             // 故障锁存位（锁存量） / Latched fault bit
    _uFault        : UDINT;            // 故障码锁存（锁存量） / Latched fault code
    _uInfo         : UDINT;            // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 当拍量判据 —— *)
_fRawKpa := fWetBulbC * fSlopeKpaPerK + fOffsetKpa;                       // 联动原始设定 [kPa] / Raw linked setpoint
_bNonFin := (fWetBulbC <> fWetBulbC) OR ((fWetBulbC - fWetBulbC) <> (fWetBulbC - fWetBulbC));   // NaN/Inf 双判 / NaN and Inf
_bRangeBad := (fWetBulbC < fWetBulbMinC) OR (fWetBulbC > fWetBulbMaxC);    // 量程判据（双侧直比） / Range verdict
_bCfgBad := (fSlopeKpaPerK <= 0.0) OR (fSpMaxKpa <= fSpMinKpa) OR (fStepMaxKpa <= 0.0)
            OR (fDeadbandKpa < 0.0) OR (fWetBulbMaxC <= fWetBulbMinC);     // 组态非法当拍量 / Config illegal
rtEnable(CLK := bEnable);                                                 // 使能沿，每拍必调 / Enable edge
rtReset(CLK := bReset);                                                   // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量与设定保持槽不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
bLimited := FALSE;                 // 限幅镜像缺省 FALSE / Clamp mirror default
bDbHold := FALSE;                  // 死区镜像缺省 FALSE / Deadband mirror default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CcrCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_CcrState.eFault THEN
        _eState := E_DL_CcrState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0005_03A3;                   // 故障级：重置故障总码 / Process fault code
    _eCause := E_DL_CcrCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF

(* —— 段 3：湿球非有限 / 越量程（判据当拍量） —— *)
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0005_03A3;
    _eCause := E_DL_CcrCause.eWbNonFin;        // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (NOT _bNonFin) AND _bRangeBad THEN   // 越量程锁存 / Range latch
    _uFault := 16#0005_03A3;
    _eCause := E_DL_CcrCause.eWbRange;         // 归因：越量程 / Cause: out of range
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin / NOT _bRangeBad —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND (NOT _bRangeBad) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CcrCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（输出冻结上一有效值，非降级） —— *)
IF _bFault AND (_eState <> E_DL_CcrState.eFault) THEN
    _eState := E_DL_CcrState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_CcrState.eIdle:
    IF rtEnable.Q AND (NOT _bFault) THEN       // 使能上升沿启动 / Enable rising starts
        _uInfo := 16#0005_04CB;                // 信息级：重置激活沿 / Info: reset active edge
        _eState := E_DL_CcrState.eRun;         // 进运行相 / Enter run
    END_IF

E_DL_CcrState.eRun:
    IF NOT bEnable THEN                        // 撤使能：回未使能（输出冻结） / Disable returns idle
        _eState := E_DL_CcrState.eIdle;
    ELSE
        _fClampKpa := _fRawKpa;                            // 候选 = 原始设定 / Candidate from raw
        IF _fClampKpa < fSpMinKpa THEN                     // 下限钳制 / Low clamp
            _fClampKpa := fSpMinKpa;
            _bClampOn := TRUE;
        ELSIF _fClampKpa > fSpMaxKpa THEN                  // 上限钳制 / High clamp
            _fClampKpa := fSpMaxKpa;
            _bClampOn := TRUE;
        ELSE
            _bClampOn := FALSE;                            // 未限幅 / No clamp
        END_IF
        IF ABS(_fClampKpa - _fSp) < fDeadbandKpa THEN      // 死区内保持（容差式比较） / Deadband hold
            bDbHold := TRUE;
        ELSIF (_fClampKpa - _fSp) > fStepMaxKpa THEN       // 向上限速 / Upward rate limit
            _fSp := _fSp + fStepMaxKpa;
        ELSIF (_fSp - _fClampKpa) > fStepMaxKpa THEN       // 向下限速 / Downward rate limit
            _fSp := _fSp - fStepMaxKpa;
        ELSE
            _fSp := _fClampKpa;                            // 直接跟随 / Direct follow
        END_IF
        IF (_fSp < fSpMinKpa) THEN                         // 限速后二次下限复核 / Post-limit low check
            _fSp := fSpMinKpa;
        ELSIF (_fSp > fSpMaxKpa) THEN                      // 限速后二次上限复核 / Post-limit high check
            _fSp := fSpMaxKpa;
        END_IF
    END_IF

E_DL_CcrState.eFault:
    ;                                          // 故障相：输出冻结，仅段 4 复位沿可迁出 / Frozen, reset only

ELSE
    _uFault := 16#0005_03A3;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_CcrCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_CcrState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fCondSpKpa := _fSp;                            // 设定值出口 / Setpoint outlet
bLimited := _bClampOn AND (NOT _bFault);       // 限幅镜像 / Clamp mirror
bDbHold := bDbHold AND (NOT _bFault);          // 死区保持镜像 / Deadband mirror
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
