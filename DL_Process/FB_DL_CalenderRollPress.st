(*
  FB_DL_CalenderRollPress  —  辊压机辊隙/线压力顺控（双侧压下 + 厚度反馈） / Calender roll-gap and line-force sequencer with dual-side ram and thickness feedback
  分类 Category : DL_Process
  版本 Version  : 1.0.1
  来源 Source   : roadmap-li-p1 — 锂电极片辊压工站真缺口
  溯源 Origin   : 道莅 clean-room 实现；双侧压下同步 + 线压力建立 + 厚度窗监督为公开辊压工艺逻辑，未复制任何源码行
  功能 Function : 1) 四段顺控：eGapSet 双侧压下（左右辊隙均进目标容差带且同步偏差达标）→
                  eBarPress 线压力建立（fLinePressKn 进目标容差带）→ eRun 走带监视
                  （厚度窗 fThicknessUm 越窗即故障）→ eRelease 抬辊返回 → eDone；
                  2) 辊隙建立超时、线压力建立超时各自保护；3) 故障级单码 039F，
                  归因由 eCause 独立成员承载（R190）；4) 信息级 04C7 = 辊压循环完成沿；
                  5) 解除式全当拍量（R240）。
  接口 Interface: 输入双侧辊隙/线压力/厚度与两个时间量；输出状态/双侧镜像/厚度窗镜像/码。
                  抬辊计时 tonRun 复用 tGapTmo 常量（引脚预算取舍，非缺陷；若现场需独立抬辊超时，
                  下一版再增设 tReleaseTmo 引脚，引脚契约变更须走 MINOR 版本而非 PATCH）
  边界 Boundary : ① 组态闸：fGapTolMm <= 0.0、fLinePressTolKn <= 0.0、fGapSyncMaxMm <= 0.0、
                  fThicknessHiUm <= fThicknessLoUm、tGapTmo <= T#0S、tPressTmo <= T#0S
                  任一成立 → 039F 锁存；五个组态实数同时做 NaN 自反判（见 ②），
                  否则 NaN 参与 `<= 0.0` 判据时恒假 → 组态闸静默失效；
                  ② 浮点判据全部容差式（ABS 差 <= 容差），禁 = / <> 判等；
                  〔例外〕NaN 自反判 [x <> x] 与 Inf 差值自减判 [(x-x) <> (x-x)] 是浮点判等禁令的
                  唯一合法例外（R79），只许用于「非有限检测」，不得用于任何工程量比较；
                  机检 G6 已对自反式加白名单；
                  ③ 双侧同步偏差 |左-右| > fGapSyncMaxMm，仅在 eGapSet / eBarPress / eRun 且
                  bStart 为真时判定（相位窗 _bSyncWin）；eIdle / eRelease / eDone 辊缝机械张开，
                  偏差属正常工况不判 —— R281 返修：消除 eIdle 上电即报与 eRelease 收尾误锁；
                  ④ 三个 TON + 一个 R_TRIG 段 0 无条件每周期调用，IN 由相位派生；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；
                  ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无直接物理地址访问）。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 039F / 信息窗口 04C7）:
    16#0005_039F 故障级：辊压故障总码（组态非法 / 辊隙超时 / 双侧失同步 / 线压力超时 / 厚度越窗），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04C7 信息级：辊压循环完成沿（抬辊完成进 eDone 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 1 · 序号 3）
    2026-11-19  v1.0.1  R45 返修（R281）：同步判据加相位窗 _bSyncWin，消除 eIdle/eRelease 误锁 039F；
                        组态闸补 NaN 自反判（组态 NaN 曾使闸静默失效）；头注释边界③改写、接口段补
                        tonRun 复用 tGapTmo 说明；引脚契约零变更（PATCH）
*)

TYPE E_DL_CrpState :
(
    eIdle     := 0,    // 未使能待启动 / Idle, waiting start
    eGapSet   := 10,   // 双侧压下建立辊隙 / Dual-side gap setting
    eBarPress := 20,   // 线压力建立 / Line force build-up
    eRun      := 30,   // 走带运行（厚度窗监督） / Running under thickness window
    eRelease  := 40,   // 抬辊返回 / Roll release
    eDone     := 50,   // 循环完成 / Done
    eFault    := 90    // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_CrpCause :
(
    eNone       := 0,  // 无故障成因 / No cause
    eCfgIllegal := 1,  // 组态非法 / Illegal configuration
    eGapTmo     := 2,  // 辊隙建立超时 / Gap setting timeout
    eGapSync    := 3,  // 双侧失同步（偏差超限） / Dual-side out of sync
    ePressTmo   := 4,  // 线压力建立超时 / Line force timeout
    eThkDev     := 5   // 厚度越窗 / Thickness out of window
);
END_TYPE

FUNCTION_BLOCK FB_DL_CalenderRollPress
VAR_INPUT
    fGapLeftMm      : REAL := 0.0;      // 操作侧辊隙 [mm] / Operator-side roll gap
    fGapRightMm     : REAL := 0.0;      // 传动侧辊隙 [mm] / Drive-side roll gap
    fGapTargetMm    : REAL := 0.120;    // 目标辊隙 [mm]，域 > 0 / Target roll gap
    fGapTolMm       : REAL := 0.005;    // 辊隙容差带 [mm]，域 > 0 / Roll gap tolerance
    fGapSyncMaxMm   : REAL := 0.010;    // 双侧允许同步偏差 [mm]，域 > 0 / Dual-side sync limit
    fLinePressKn    : REAL := 0.0;      // 实测线压力 [kN/cm] / Measured line force
    fLinePressTgtKn : REAL := 12.0;     // 目标线压力 [kN/cm]，域 > 0 / Target line force
    fLinePressTolKn : REAL := 0.5;      // 线压力容差带 [kN/cm]，域 > 0 / Line force tolerance
    fThicknessUm    : REAL := 0.0;      // 实测极片厚度 [µm] / Measured electrode thickness
    fThicknessLoUm  : REAL := 100.0;    // 厚度窗下限 [µm] / Thickness low limit
    fThicknessHiUm  : REAL := 140.0;    // 厚度窗上限 [µm] / Thickness high limit
    tGapTmo         : TIME := T#10S;    // 辊隙建立超时 [ms]，域 > 0 / Gap timeout
    tPressTmo       : TIME := T#10S;    // 线压力建立超时 [ms]，域 > 0 / Force timeout
    bStart          : BOOL := FALSE;    // 启动命令（电平）[-] / Start command
    bReset          : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState          : E_DL_CrpState;    // 状态出口，段 6 单点映射 / State outlet
    eCause          : E_DL_CrpCause;    // 故障成因出口（R190） / Fault cause outlet
    fGapMeanMm      : REAL;             // 双侧辊隙均值 [mm] / Mean roll gap
    bGapOk          : BOOL;             // 辊隙达窗镜像 [-] / Gap in-window mirror
    bThkOk          : BOOL;             // 厚度在窗镜像 [-] / Thickness in-window mirror
    bCycleDone      : BOOL;             // 循环完成标志 [-] / Cycle done flag
    bError          : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId          : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState         : E_DL_CrpState := E_DL_CrpState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause         : E_DL_CrpCause := E_DL_CrpCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonGap          : TON;              // 辊隙建立计时，每周期无条件调用 / Gap timer
    tonPress        : TON;              // 线压力建立计时，每周期无条件调用 / Force timer
    tonRun          : TON;              // 抬辊计时，每周期无条件调用 / Release timer
    rtReset         : R_TRIG;           // 复位沿实例，每周期无条件调用 / Reset edge
    _fGapDev        : REAL;             // 双侧辊隙偏差 [mm]（当拍量） / Dual-side gap deviation
    _fGapErr        : REAL;             // 单侧辊隙对目标偏差 [mm]（当拍量） / Single-side gap error
    _bSyncWin       : BOOL;             // 双侧同步判据窗当拍量 [-]（单拍量，不入锁存清单） / Sync criterion window (per-scan)
    _bGapOk         : BOOL;             // 辊隙达窗当拍量 [-] / Gap verdict
    _bThkOk         : BOOL;             // 厚度在窗当拍量 [-] / Thickness verdict
    _bCfgBad        : BOOL;             // 组态非法当拍量 [-] / Config illegal
    _bFault         : BOOL;             // 故障锁存位（锁存量） / Latched fault bit
    _uFault         : UDINT;            // 故障码锁存（锁存量） / Latched fault code
    _uInfo          : UDINT;            // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 —— *)
_fGapDev := fGapLeftMm - fGapRightMm;                                          // 双侧辊隙偏差 / Dual-side deviation
_bSyncWin := bStart AND ((_eState = E_DL_CrpState.eGapSet)
                      OR (_eState = E_DL_CrpState.eBarPress)
                      OR (_eState = E_DL_CrpState.eRun));                      // 同步判据窗：仅在压下/建压/走带且启动电平在效时判同步 [-] / Sync window
_fGapErr := fGapLeftMm - fGapTargetMm;                                         // 操作侧对目标偏差 / Operator-side error
_bGapOk := (ABS(_fGapErr) <= fGapTolMm) AND (ABS(fGapRightMm - fGapTargetMm) <= fGapTolMm);   // 双侧均在容差带 / Both sides within tolerance
_bThkOk := (fThicknessUm >= fThicknessLoUm - 1.0E-6) AND (fThicknessUm <= fThicknessHiUm + 1.0E-6);  // 厚度容差窗 / Thickness window
_bCfgBad := (fGapTolMm <> fGapTolMm) OR (fLinePressTolKn <> fLinePressTolKn) OR (fGapSyncMaxMm <> fGapSyncMaxMm)
            OR (fThicknessLoUm <> fThicknessLoUm) OR (fThicknessHiUm <> fThicknessHiUm)   // NaN 自反判（禁令唯一例外 R79）/ NaN self-test
            OR (fGapTolMm <= 0.0) OR (fLinePressTolKn <= 0.0) OR (fGapSyncMaxMm <= 0.0)
            OR (fThicknessHiUm <= fThicknessLoUm) OR (tGapTmo <= T#0S) OR (tPressTmo <= T#0S);  // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                        // 复位沿，每拍必调 / Reset edge
tonGap(IN := (_eState = E_DL_CrpState.eGapSet), PT := tGapTmo);                // 辊隙建立计时 / Gap timer
tonPress(IN := (_eState = E_DL_CrpState.eBarPress), PT := tPressTmo);          // 线压力建立计时 / Force timer
tonRun(IN := (_eState = E_DL_CrpState.eRelease), PT := tGapTmo);               // 抬辊计时（复用辊隙超时常量） / Release timer

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
fGapMeanMm := 0.0;                 // 辊隙均值缺省 0 / Mean gap default
bGapOk := FALSE;                   // 辊隙镜像缺省 FALSE / Gap flag default
bThkOk := FALSE;                   // 厚度镜像缺省 FALSE / Thickness flag default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿（操作员复位语义：无条件清故障三件）+ 组态域闸 ——
   与段 4 分工：段 2 = 复位沿即刻清（不等解除式判据），段 4 = 解除式兜底判定；
   两段清同一三件，幂等无冲突（段 4 条件不成立时说明已被段 2 清毕，无需再动）。 *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CrpCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_CrpState.eFault THEN
        _eState := E_DL_CrpState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0005_039F;                   // 故障级：辊压故障总码 / Process fault code
    _bFault := TRUE;                           // 锁存置位 / Latch set
    bError := TRUE;                            // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_CrpCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
END_IF

(* —— 段 3：超时 / 失同步 / 厚度越窗（判据当拍量） —— *)
IF (NOT _bFault) AND tonGap.Q THEN             // 辊隙建立超时 / Gap timeout
    _uFault := 16#0005_039F;                   // 故障级：辊压故障总码 / Process fault code
    _bFault := TRUE;                           // 锁存置位 / Latch set
    bError := TRUE;                            // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_CrpCause.eGapTmo;          // 归因：辊隙超时 / Cause: gap timeout
END_IF
IF (NOT _bFault) AND _bSyncWin AND (ABS(_fGapDev) > fGapSyncMaxMm) THEN   // 仅同步窗内判（R281） / Only inside sync window
    _uFault := 16#0005_039F;                   // 故障级：辊压故障总码 / Process fault code
    _bFault := TRUE;                           // 锁存置位 / Latch set
    bError := TRUE;                            // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_CrpCause.eGapSync;         // 归因：失同步 / Cause: sync
END_IF
IF (NOT _bFault) AND tonPress.Q THEN           // 线压力建立超时 / Force timeout
    _uFault := 16#0005_039F;                   // 故障级：辊压故障总码 / Process fault code
    _bFault := TRUE;                           // 锁存置位 / Latch set
    bError := TRUE;                            // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_CrpCause.ePressTmo;        // 归因：线压力超时 / Cause: force timeout
END_IF
IF (NOT _bFault) AND (_eState = E_DL_CrpState.eRun) AND (NOT _bThkOk) THEN   // 走带期厚度越窗 / Thickness deviation
    _uFault := 16#0005_039F;                   // 故障级：辊压故障总码 / Process fault code
    _bFault := TRUE;                           // 锁存置位 / Latch set
    bError := TRUE;                            // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_CrpCause.eThkDev;          // 归因：厚度越窗 / Cause: thickness
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT tonGap.Q / NOT tonPress.Q ——
   解除式自证可满足（终审两式 1）：故障相内 _eState = eFault → tonGap.IN 与 tonPress.IN 恒假
   → 两 Q 恒假；操作员按复位时只需组态合法（NOT _bCfgBad），四因子即可同时为真 → 达式可满足、
   非 R152 恒假组合。刻意不追加 NOT _bSyncWin：故障相内 _bSyncWin 已恒假，追加即恒真冗余项；
   且复位后 _eState 回 eIdle → _bSyncWin 恒假 → 同步判据不复锁，解除可达性不依赖该因子。 *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT tonGap.Q) AND (NOT tonPress.Q) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CrpCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_CrpState.eFault) THEN
    _eState := E_DL_CrpState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_CrpState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动条件 / Start gate
        _eState := E_DL_CrpState.eGapSet;      // 进辊隙建立相 / Enter gap setting
    END_IF

E_DL_CrpState.eGapSet:
    IF _bGapOk THEN                            // 出口 1：双侧辊隙达窗 / Gap reached
        _eState := E_DL_CrpState.eBarPress;    // 进线压力相 / Enter force build-up
    ELSIF NOT bStart THEN                      // 出口 2：撤启动（R98 双出口） / Start released
        _eState := E_DL_CrpState.eRelease;     // 直接抬辊返回 / Go release
    END_IF

E_DL_CrpState.eBarPress:
    IF ABS(fLinePressKn - fLinePressTgtKn) <= fLinePressTolKn THEN   // 线压力达容差带 / Force reached band
        _eState := E_DL_CrpState.eRun;         // 进走带相 / Enter running
    ELSIF NOT bStart THEN                      // 撤启动：抬辊返回 / Start released
        _eState := E_DL_CrpState.eRelease;
    END_IF

E_DL_CrpState.eRun:
    IF NOT bStart THEN                         // 撤启动：进抬辊相 / Start released enters release
        _eState := E_DL_CrpState.eRelease;
    END_IF

E_DL_CrpState.eRelease:
    IF tonRun.Q THEN                           // 抬辊计时到 / Release elapsed
        _uInfo := 16#0005_04C7;                // 信息级：循环完成沿 / Info: cycle complete edge
        _eState := E_DL_CrpState.eDone;        // 进完成相 / Enter done
    END_IF

E_DL_CrpState.eDone:
    IF bStart THEN                             // 新循环上升请求 / New cycle request
        _eState := E_DL_CrpState.eGapSet;      // 直接进辊隙相 / Enter gap phase
    END_IF

E_DL_CrpState.eFault:
    ;                                          // 故障相：仅段 4 复位沿可迁出 / Only reset exits

ELSE
    _uFault := 16#0005_039F;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _bFault := TRUE;                           // 锁存置位 / Latch set
    bError := TRUE;                            // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_CrpCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _eState := E_DL_CrpState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fGapMeanMm := (fGapLeftMm + fGapRightMm) * 0.5;   // 双侧辊隙均值 / Mean roll gap
bGapOk := _bGapOk AND (NOT _bFault);              // 辊隙镜像 / Gap mirror
bThkOk := _bThkOk AND (NOT _bFault);              // 厚度镜像 / Thickness mirror
bCycleDone := (_eState = E_DL_CrpState.eDone);    // 完成标志 / Done flag
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
