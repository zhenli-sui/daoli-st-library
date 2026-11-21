(*
  FB_DL_BoilerFlueCondenseGuard  —  锅炉烟气冷凝防护（排烟温度低限联锁 + 回水温度钳制） / Boiler flue-gas condensation guard with low flue-temperature interlock and return-water clamping
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇锅炉防冷凝保护族深化
  溯源 Origin   : 道莅 clean-room 实现；排烟温度低限联锁 + 回水温度低限钳制为公开锅炉防低温腐蚀保护逻辑，未复制任何源码行
  功能 Function : 1) 三级判据：排烟温度 fFlueTempC 低于报警限 fFlueLoC → 冷凝风险信息位；
                  低于联锁限 fFlueLoLoC 且持续 tConfirm → 联锁撤销燃烧器许可；
                  2) 回水温度钳制：fReturnTempC 低于 fReturnMinC 时输出 bReturnClamp 请求（提高回水），
                  仅在燃烧器许可有效时给出；
                  3) 故障级单码 052C / 信息级 0432 = 冷凝风险进入沿（由无风险转风险单拍）。
  接口 Interface: 输入排烟温度/两级限值/回水温度/回水下限/确认延时；输出许可与风险位
  边界 Boundary : ① 组态闸：fFlueLoLoC >= fFlueLoC（联锁限须低于报警限）、fFlueLoC <= 0.0、
                  fReturnMinC < 0.0、tConfirm <= T#0S → 052C 锁存；
                  ② 温度非有限（NaN 自反 + Inf 差值自减）→ 052C 锁存，燃烧器许可撤销（安全侧）；
                  ③ 低限判据为「<=」单侧直比（限值语义明确，无容差歧义），回水钳制同为单侧直比；
                  ④ 一个 TON + 两个 R_TRIG 段 0 无条件调用；⑤ 故障相迁出唯一路径 = bReset 上升沿；
                  ⑥ 零全局耦合：无 GVL / VAR_EXTERNAL / %I %Q %M 直接地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Device 分段见下，故障窗口 052C / 信息窗口 0432）:
    16#0003_052C 故障级：烟气冷凝防护故障总码（组态非法 / 温度非有限），锁存至 bReset 上升沿；
                 归因见 eCause，不新增码位（派单硬约束单码）
    16#0003_0432 信息级：冷凝风险进入沿（无风险 → 风险，单拍）
    分段理由：段 0003 故障带 03A0~03FF 于 R42 用尽，启用 05xx 副带续编，避开 0590~0599 判错位段。
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 4 · 序号 16）
*)

TYPE E_DL_BfgState :
(
    eIdle     := 0,   // 未使能：许可撤销 / Idle, permit withdrawn
    eGuard    := 10,  // 防护监视中（许可有效） / Guarding with permit valid
    eLockout  := 20,  // 联锁动作（许可撤销） / Interlocked, permit withdrawn
    eFault    := 90   // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_BfgCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2  // 温度非有限 / Non-finite temperature
);
END_TYPE

FUNCTION_BLOCK FB_DL_BoilerFlueCondenseGuard
VAR_INPUT
    fFlueTempC   : REAL := 0.0;        // 排烟温度 [°C] / Flue gas temperature
    fFlueLoC     : REAL := 90.0;       // 冷凝风险报警限 [°C]，域 > 0 / Condensation alarm limit
    fFlueLoLoC   : REAL := 70.0;       // 联锁限 [°C]，须低于报警限 / Interlock limit
    fReturnTempC : REAL := 0.0;        // 回水温度 [°C] / Return water temperature
    fReturnMinC  : REAL := 55.0;       // 回水温度下限 [°C]，域 >= 0 / Return water minimum
    tConfirm     : TIME := T#30S;      // 联锁确认延时 [ms]，域 > 0 / Interlock confirmation delay
    bEnable      : BOOL := FALSE;      // 防护使能（电平）[-] / Guard enable
    bReset       : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_BfgState;      // 状态出口，段 6 单点映射 / State outlet
    eCause       : E_DL_BfgCause;      // 故障成因出口（R190） / Fault cause outlet
    bBurnerPermit: BOOL;               // 燃烧器许可 [-] / Burner permit
    bCondenseRisk: BOOL;               // 冷凝风险位 [-] / Condensation risk flag
    bReturnClamp : BOOL;               // 回水温度钳制请求 [-] / Return-water clamping request
    bError       : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState      : E_DL_BfgState := E_DL_BfgState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_BfgCause := E_DL_BfgCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonConfirm   : TON;                // 联锁确认计时，每周期无条件调用 / Confirmation timer
    rtReset      : R_TRIG;             // 复位沿实例，每周期无条件调用 / Reset edge
    rtRisk       : R_TRIG;             // 风险沿实例，每周期无条件调用 / Risk edge
    _bRisk       : BOOL;               // 冷凝风险当拍量 [-] / Risk verdict
    _bLoLo       : BOOL;               // 低于联锁限当拍量 [-] / Below interlock limit
    _bRetLow     : BOOL;               // 回水低于下限当拍量 [-] / Return water below minimum
    _bNonFin     : BOOL;               // 温度非有限当拍量 [-] / Non-finite temperature
    _bCfgBad     : BOOL;               // 组态非法当拍量 [-] / Config illegal
    _bFault      : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;              // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 + 当拍量判据 —— *)
_bRisk := fFlueTempC <= fFlueLoC;                                            // 冷凝风险（单侧直比） / Risk verdict
_bLoLo := fFlueTempC <= fFlueLoLoC;                                          // 低于联锁限 / Below interlock
_bRetLow := fReturnTempC < fReturnMinC;                                      // 回水低于下限 / Return below minimum
_bNonFin := (fFlueTempC <> fFlueTempC) OR (fReturnTempC <> fReturnTempC)
         OR ((fFlueTempC - fFlueTempC) <> (fFlueTempC - fFlueTempC))
         OR ((fReturnTempC - fReturnTempC) <> (fReturnTempC - fReturnTempC));  // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (fFlueLoLoC >= fFlueLoC) OR (fFlueLoC <= 0.0) OR (fReturnMinC < 0.0)
            OR (tConfirm <= T#0S);                                           // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                      // 复位沿，每拍必调 / Reset edge
rtRisk(CLK := _bRisk AND (NOT _bFault));                                     // 风险沿（故障相屏蔽） / Risk edge
tonConfirm(IN := (_eState = E_DL_BfgState.eGuard) AND _bLoLo, PT := tConfirm);   // 联锁确认计时 / Interlock timer

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
bBurnerPermit := FALSE;            // 许可缺省撤销（安全侧缺省） / Permit default withdrawn
bCondenseRisk := FALSE;            // 风险位缺省 FALSE / Risk default
bReturnClamp := FALSE;             // 钳制请求缺省 FALSE / Clamp default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_BfgCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_BfgState.eFault THEN
        _eState := E_DL_BfgState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
    IF _eState = E_DL_BfgState.eLockout THEN
        _eState := E_DL_BfgState.eGuard;       // 联锁相复位迁出：回防护（恢复许可） / Lockout exit to guard
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0003_052C;                   // 故障级：防护故障总码（05xx 副带） / Device fault code
    _eCause := E_DL_BfgCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0003_052C;
    _eCause := E_DL_BfgCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：联锁确认（低于联锁限持续 tConfirm 即进联锁相） —— *)
IF (NOT _bFault) AND (_eState = E_DL_BfgState.eGuard) AND tonConfirm.Q THEN
    _eState := E_DL_BfgState.eLockout;         // 进联锁相（许可撤销） / Enter lockout
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_BfgCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_BfgState.eFault) THEN
    _eState := E_DL_BfgState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_BfgState.eIdle:
    IF bEnable AND (NOT _bFault) THEN          // 使能条件 / Enable gate
        _eState := E_DL_BfgState.eGuard;       // 进防护相 / Enter guard
    END_IF

E_DL_BfgState.eGuard:
    bBurnerPermit := NOT _bLoLo;               // 许可：未低于联锁限即允许 / Permit unless below interlock
    bCondenseRisk := _bRisk;                   // 风险位（相内按当拍量给出） / Risk flag
    bReturnClamp := _bRetLow AND bBurnerPermit; // 回水钳制请求（许可有效时） / Return clamp request
    IF rtRisk.Q THEN                           // 风险进入沿 / Risk entrance edge
        _uInfo := 16#0003_0432;                // 信息级：冷凝风险进入沿 / Info: risk entrance
    END_IF
    IF NOT bEnable THEN                        // 撤使能：许可撤销，回未使能 / Disable withdraws permit
        _eState := E_DL_BfgState.eIdle;
    ELSIF NOT _bRisk THEN                      // 风险消失：保持防护相（不迁移） / Risk cleared, stay
        ;
    END_IF

E_DL_BfgState.eLockout:
    bBurnerPermit := FALSE;                    // 联锁相：许可强制撤销 / Permit forced withdrawn
    bCondenseRisk := TRUE;                     // 联锁相风险位恒真 / Risk latched high
    IF NOT _bLoLo THEN                         // 排烟温度回到联锁限之上（事件） / Flue temperature recovered
        _eState := E_DL_BfgState.eGuard;       // 恢复防护相 / Back to guard
    ELSIF NOT bEnable THEN                     // 撤使能：回未使能 / Disable returns idle
        _eState := E_DL_BfgState.eIdle;
    END_IF

E_DL_BfgState.eFault:
    ;                                          // 故障相：许可撤销，仅段 4 复位沿可迁出 / Permit withdrawn, reset only

ELSE
    _uFault := 16#0003_052C;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_BfgCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_BfgState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；故障相许可强制撤销） —— *)
IF _bFault THEN
    bBurnerPermit := FALSE;                    // 故障相许可强制撤销（安全侧） / Permit forced withdrawn
    bReturnClamp := FALSE;                     // 故障相钳制请求强制 FALSE / Clamp forced false
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
