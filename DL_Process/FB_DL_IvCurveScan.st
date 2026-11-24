(*
  FB_DL_IvCurveScan  —  IV 曲线扫描与特征点提取（Voc / Isc / FF + 扫描窗） / IV curve scan with Voc, Isc and fill-factor extraction inside a scan window
  分类 Category : DL_Process
  版本 Version  : 1.0.1
  来源 Source   : roadmap-pv-p1 — 光伏组件 IV 扫描测试工站真缺口
  溯源 Origin   : 道莅 clean-room 实现；Voc/Isc/Pmax/FF 为公开光伏特性参数定义式，未复制任何源码行
  功能 Function : 1) 扫描窗 eScan 内逐周期摄取 (fVmeasV, fImeasA) 采样：Voc = 电压最大值、
                  Isc = 电流最大值、Pmax = max(V×I) 功率最大值、nSample 采样计数；
                  2) 段 0 每拍单次求解 FF = Pmax/(Voc×Isc)，内核为纯计算子函数
                  FC_DL_IvFillFactorCalc（分母 <= 1.0E-9 返回 -1.0 哨兵，不饱和、不置 0），
                  判据与出口共用同一当拍量 _fFfPu，全件不存在同一子函数同参二次调用；
                  3) FF 低于 fFfMinPu 判组件异常（归因 eFfLow）；
                  4) 故障级单码 03A2，归因由 eCause 独立成员承载（R190）；
                  5) 信息级 04CA = 扫描完成沿；6) 解除式全当拍量（R240）。
  接口 Interface: 输入逐样电压/电流/扫描窗/最小采样数/FF 下限/电压量程；输出 Voc/Isc/Pmax/FF/采样数/码
  边界 Boundary : ① 组态闸：tScan <= T#0S、nSampleMin = 0、fFfMinPu <= 0.0、fVmaxV <= 0.0
                  任一成立 → 03A2 锁存；fFfMinPu / fVmaxV 同时做 NaN 自反判，否则 NaN 参与
                  `<= 0.0` 判据恒假 → 组态闸与「FF 越下限」判据双双静默失效；
                  ② 非有限输入（NaN 自反 + Inf 差值自减双判）→ 03A2 锁存且该样点不参与极值更新；
                  ③ 除零防护在子函数内前置判（分母非法返回 -1.0 哨兵，不饱和、不置 0）；
                  ④ 采样极值仅扫峰不回落（扫描窗内单调保持），窗口结束由 TON 单点置位；
                  ⑤ 扫描 TON / R_TRIG 段 0 无条件周期调用，IN 由相位派生；
                  ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无直接物理地址访问）；
                  ⑦ 复位沿作用域（R283 返修）：eFault 相内 = 清故障三件 + 净重装窗内量并回 eIdle；
                  非故障相 = 仅清故障锁存三件，窗内量与相位一律不动；窗内量唯一重置点 =
                  eIdle→eScan 迁移（段 5），保证「复位不清窗」与「tonScan 不重装」自洽；
                  ⑧ 〔例外〕NaN 自反判 [x <> x] 与 Inf 差值自减判 [(x-x) <> (x-x)] 是浮点判等
                  禁令的唯一合法例外（R79），只许用于「非有限检测」；机检 G6 已对自反式加白名单。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 03A2 / 信息窗口 04CA）:
    16#0005_03A2 故障级：IV 扫描故障总码（组态非法 / 输入非有限 / 采样数不足 / FF 越下限），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04CA 信息级：扫描完成沿（进入 eDone 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 2 · 序号 6）
    2026-11-19  v1.0.1  R45 返修（R283）：复位沿按相分域，非故障相不再清窗内极值与采样计数
                        （曾致 eScan 中复位后半窗从零累积、与 tonScan 不重装自相矛盾）；
                        FF 计算上移段 0 单次求解 _fFfPu，段 3 判据与 eEval 相改读当拍量，
                        删除同一 FC 同参双调用；出口 fFfPu 恒等 _fFfPu，消除 eDone 相 FF 恒 0；
                        组态闸补 NaN 自反判；边界新增⑦⑧；引脚契约零变更（PATCH）
*)

TYPE E_DL_IvsState :
(
    eIdle  := 0,      // 未使能待启动 / Idle, waiting start
    eScan  := 10,     // 扫描窗内逐样摄取 / Sampling inside scan window
    eEval  := 20,     // 特征点求解与判据 / Feature evaluation
    eDone  := 50,     // 扫描完成 / Done
    eFault := 90      // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_IvsCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2, // 输入非有限 / Non-finite input
    eSampleFew  := 3, // 采样数不足 / Too few samples
    eFfLow      := 4  // FF 越下限（含分母不可计算时 FF 不可达下限） / Fill factor below limit
);
END_TYPE

FUNCTION FC_DL_IvFillFactorCalc : REAL
VAR_INPUT
    fPmaxW : REAL;    // 最大功率 [W] / Maximum power
    fVocV  : REAL;    // 开路电压 [V] / Open-circuit voltage
    fIscA  : REAL;    // 短路电流 [A] / Short-circuit current
END_VAR
(* 纯计算子函数：FF = Pmax / (Voc × Isc)；分母 <= 1.0E-9 返回 -1.0 哨兵（不饱和、不置 0） *)
IF (fVocV <= 1.0E-9) OR (fIscA <= 1.0E-9) THEN      // 除零前置判（分母正域检查） / Divide-by-zero guard
    FC_DL_IvFillFactorCalc := -1.0;                 // 哨兵：分母非法 / Sentinel for invalid denominator
ELSE
    FC_DL_IvFillFactorCalc := fPmaxW / (fVocV * fIscA);   // 填充因子（无量纲） / Fill factor
END_IF
END_FUNCTION

FUNCTION_BLOCK FB_DL_IvCurveScan
VAR_INPUT
    fVmeasV      : REAL := 0.0;       // 逐样电压 [V] / Per-sample voltage
    fImeasA      : REAL := 0.0;       // 逐样电流 [A] / Per-sample current
    tScan        : TIME := T#2S;      // 扫描窗时长 [ms]，域 > 0 / Scan window duration
    nSampleMin   : UDINT := 20;       // 最小采样点数 [点]，域 > 0 / Minimum sample count
    fFfMinPu     : REAL := 0.60;      // FF 下限 [p.u.]，域 > 0 / Fill factor lower limit
    fVmaxV       : REAL := 60.0;      // 电压量程上限 [V]，域 > 0 / Voltage range limit
    bStart       : BOOL := FALSE;     // 启动命令（电平）[-] / Start command
    bReset       : BOOL := FALSE;     // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_IvsState;     // 状态出口，段 6 单点映射 / State outlet
    eCause       : E_DL_IvsCause;     // 故障成因出口（R190） / Fault cause outlet
    fVocV        : REAL;              // 开路电压 [V] / Open-circuit voltage
    fIscA        : REAL;              // 短路电流 [A] / Short-circuit current
    fPmaxW       : REAL;              // 最大功率 [W] / Maximum power
    fFfPu        : REAL;              // 填充因子 [p.u.] / Fill factor
    nSampleCount : UDINT;             // 本次扫描采样点数 [点] / Sample count
    bCycleDone   : BOOL;              // 扫描完成标志 [-] / Scan done flag
    bError       : BOOL;              // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState      : E_DL_IvsState := E_DL_IvsState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_IvsCause := E_DL_IvsCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonScan      : TON;               // 扫描窗计时，每周期无条件调用 / Scan window timer
    rtReset      : R_TRIG;            // 复位沿实例，每周期无条件调用 / Reset edge
    _fVocV       : REAL;              // 扫描期电压极值（窗内保持） / Voltage peak held in window
    _fIscA       : REAL;              // 扫描期电流极值（窗内保持） / Current peak held in window
    _fPmaxW      : REAL;              // 扫描期功率极值（窗内保持） / Power peak held in window
    _nSample     : UDINT;             // 采样计数（窗内累计） / Sample counter
    _fPowW       : REAL;              // 当拍功率 [W] / Instantaneous power
    _fFfPu       : REAL;              // FF 当拍量 [p.u.]（段 0 单次求解，供判据与出口） / FF per-scan value
    _bNonFin     : BOOL;              // 输入非有限当拍量 [-] / Non-finite input flag
    _bCfgBad     : BOOL;              // 组态非法当拍量 [-] / Config illegal
    _bFault      : BOOL;              // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 + 非有限判定 + FF 单次求解 —— *)
_bNonFin := (fVmeasV <> fVmeasV) OR (fImeasA <> fImeasA)
         OR ((fVmeasV - fVmeasV) <> (fVmeasV - fVmeasV))
         OR ((fImeasA - fImeasA) <> (fImeasA - fImeasA));       // NaN 自反 + Inf 差值自减双判（禁令唯一例外 R79） / NaN and Inf detection
_bCfgBad := (fFfMinPu <> fFfMinPu) OR (fVmaxV <> fVmaxV)         // 组态实数 NaN 自反判（禁令唯一例外 R79） / NaN self-test on config reals
         OR (tScan <= T#0S) OR (nSampleMin = 0) OR (fFfMinPu <= 0.0) OR (fVmaxV <= 0.0);   // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                         // 复位沿，每拍必调 / Reset edge
tonScan(IN := (_eState = E_DL_IvsState.eScan), PT := tScan);    // 扫描窗计时（IN 由相位派生，跨相自动复位 R228A/B） / Scan window timer
_fFfPu := FC_DL_IvFillFactorCalc(fPmaxW := _fPmaxW, fVocV := _fVocV, fIscA := _fIscA);   // FF 当拍量：段 0 单次求解，判据与出口共用 / FF solved once per scan

(* —— 段 1：单拍量预清零（锁存量与窗内极值保持量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
fVocV := 0.0;                      // Voc 出口缺省 0 / Voc default
fIscA := 0.0;                      // Isc 出口缺省 0 / Isc default
fPmaxW := 0.0;                     // Pmax 出口缺省 0 / Pmax default
fFfPu := 0.0;                      // FF 出口缺省 0 / FF default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿（按相分域，R283） + 组态域闸 —— *)
IF rtReset.Q THEN                                  // 复位沿（当拍量） / Reset edge
    _bFault := FALSE;                              // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                       // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_IvsCause.eNone;                // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_IvsState.eFault THEN         // 仅故障相做净重装 / Clean re-arm only from fault
        _fVocV := 0.0;                             // 清窗内电压极值 / Clear voltage peak
        _fIscA := 0.0;                             // 清窗内电流极值 / Clear current peak
        _fPmaxW := 0.0;                            // 清窗内功率极值 / Clear power peak
        _nSample := 0;                             // 清采样计数 / Clear sample counter
        _eState := E_DL_IvsState.eIdle;            // 故障相迁出唯一路径 / Sole exit from fault
    END_IF
END_IF
IF _bCfgBad THEN                                   // 组态域闸 / Config gate
    _uFault := 16#0005_03A2;                       // 故障级：IV 扫描故障总码 / Process fault code
    _bFault := TRUE;                               // 锁存置位 / Latch set
    bError := TRUE;                                // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_IvsCause.eCfgIllegal;          // 归因：组态非法 / Cause: illegal config
END_IF
IF (NOT _bFault) AND _bNonFin THEN                 // 输入非有限（当拍量） / Non-finite input
    _uFault := 16#0005_03A2;                       // 故障级：IV 扫描故障总码 / Process fault code
    _bFault := TRUE;                               // 锁存置位 / Latch set
    bError := TRUE;                                // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_IvsCause.eNonFinite;           // 归因：非有限 / Cause: non-finite
END_IF

(* —— 段 3：采样数不足与 FF 越下限（判据当拍量 _fFfPu；仅在 eEval 相判） —— *)
IF (NOT _bFault) AND (_eState = E_DL_IvsState.eEval) AND (_nSample < nSampleMin) THEN
    _uFault := 16#0005_03A2;                       // 故障级：IV 扫描故障总码 / Process fault code
    _bFault := TRUE;                               // 锁存置位 / Latch set
    bError := TRUE;                                // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_IvsCause.eSampleFew;           // 归因：采样不足 / Cause: too few samples
END_IF
IF (NOT _bFault) AND (_eState = E_DL_IvsState.eEval) AND (_fFfPu < fFfMinPu) THEN
    (* 含哨兵 -1.0：分母不可计算（Voc 或 Isc 过小）时 FF 不可达下限，按安全侧判组件异常，
       故此处不设 `>= 0.0` 前置闸——该前置闸会造成 eEval 无迁出（R228B 同类缺陷） / Sentinel included: unreachable FF fails safe *)
    _uFault := 16#0005_03A2;                       // 故障级：IV 扫描故障总码 / Process fault code
    _bFault := TRUE;                               // 锁存置位 / Latch set
    bError := TRUE;                                // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_IvsCause.eEfLow;               // 归因：FF 越下限 / Cause: fill factor low
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin / NOT tonScan.Q ——
   解除式自证可满足（终审两式 1）：故障相内 _eState = eFault → tonScan.IN 恒假 → tonScan.Q 恒假；
   _bCfgBad 与 _bNonFin 由操作员/接线侧消除（组态改正、非有限输入消失），故四因子可同时为真，
   达式可满足、非 R152 恒假组合。 *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND (NOT tonScan.Q) THEN
    _bFault := FALSE;                              // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                       // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_IvsCause.eNone;                // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_IvsState.eFault) THEN
    _eState := E_DL_IvsState.eFault;               // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_IvsState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动条件 / Start gate
        _fVocV := 0.0;                         // 窗内量唯一重置点（起扫） / Sole reset point of window peaks
        _fIscA := 0.0;                         // 清电流极值 / Reset current peak
        _fPmaxW := 0.0;                        // 清功率极值 / Reset power peak
        _nSample := 0;                         // 清采样计数 / Reset sample counter
        _eState := E_DL_IvsState.eScan;        // 进扫描相 / Enter scan
    END_IF

E_DL_IvsState.eScan:
    IF NOT _bNonFin THEN                                   // 仅有效样点参与极值（安全侧） / Valid samples only
        _nSample := _nSample + 1;                          // 采样计数递增 / Sample counter
        IF (fVmeasV > _fVocV) AND (fVmeasV <= fVmaxV) THEN
            _fVocV := fVmeasV;                             // 电压极值更新（量程钳制） / Voltage peak
        END_IF
        IF fImeasA > _fIscA THEN
            _fIscA := fImeasA;                             // 电流极值更新 / Current peak
        END_IF
        _fPowW := fVmeasV * fImeasA;                       // 当拍功率 / Instantaneous power
        IF _fPowW > _fPmaxW THEN
            _fPmaxW := _fPowW;                             // 功率极值更新 / Power peak
        END_IF
    END_IF
    IF tonScan.Q THEN                                      // 扫描窗到时（事件量） / Scan window elapsed
        _eState := E_DL_IvsState.eEval;                    // 进判据相 / Enter evaluation
    ELSIF NOT bStart THEN                                  // 撤启动（前置消失，R98 双出口） / Start released
        _eState := E_DL_IvsState.eIdle;                    // 回空闲（回 eIdle 时经 eIdle→eScan 才净重装） / Back to idle
    END_IF

E_DL_IvsState.eEval:
    IF _bFault THEN                                        // 段 3 已锁故障（含哨兵归因 eFfLow） / Fault already latched
        _eState := E_DL_IvsState.eFault;                   // 入故障相 / Enter fault phase
    ELSE                                                   // 分母合法且 FF 达下限 / Valid FF verdict
        _uInfo := 16#0005_04CA;                            // 信息级：扫描完成沿 / Info: scan complete edge
        _eState := E_DL_IvsState.eDone;                    // 进完成相 / Enter done
    END_IF

E_DL_IvsState.eDone:
    IF NOT bStart THEN                                     // 撤启动回空闲 / Start released returns idle
        _eState := E_DL_IvsState.eIdle;
    END_IF

E_DL_IvsState.eFault:
    ;                                                      // 故障相：仅段 4 复位沿可迁出 / Only reset exits

ELSE
    _uFault := 16#0005_03A2;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _bFault := TRUE;                           // 锁存置位 / Latch set
    bError := TRUE;                            // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_IvsCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _eState := E_DL_IvsState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fVocV := _fVocV;                               // Voc 出口 / Voc outlet
fIscA := _fIscA;                               // Isc 出口 / Isc outlet
fPmaxW := _fPmaxW;                             // Pmax 出口 / Pmax outlet
fFfPu := _fFfPu;                               // FF 出口 = 当拍量（eDone 相保持有效值） / FF from per-scan value
nSampleCount := _nSample;                      // 采样计数出口 / Sample count outlet
bCycleDone := (_eState = E_DL_IvsState.eDone); // 完成标志 / Done flag
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    fFfPu := 0.0;                              // 故障相 FF 出口强制 0（安全侧，不输出哨兵） / FF forced zero in fault
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
