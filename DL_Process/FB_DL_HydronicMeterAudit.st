(*
  FB_DL_HydronicMeterAudit  —  冷冻水/冷却水能量审计（流量累计 × 侧焓差） / Hydronic energy audit: flow accumulation times loop enthalpy difference
  分类 Category : DL_Process
  版本 Version  : 1.0.1
  来源 Source   : t1-2-oscat-building — 楼宇能量审计族零检索深化
  溯源 Origin   : clean-room 实现，Q = 流量×密度×比热×温差 换算链为公开热工公式，未复制任何源码行
  功能 Function : 1) 逐周期功率换算：fPowerKw = fFlowLpm × fRhoKgL × fCpKj ×
                  (fTinC - fToutC) / 60.0（L/min×kg/L×kJ/(kg·K)×K = kJ/min，
                  除以 60 得 kW，除数 60.0 为常量无除零）；
                  2) 能量累计：fEnergyKwh += fPowerKw × tCycle/T#1H（TIME 比
                  经 DINT 除法，除数 T#1H 为非零常量）；累计仅使能相且温差判据
                  有效（|ΔT| >= fDtMinK）承载；
                  3) 温差判据无效（|ΔT| < fDtMinK）→ ePause 相暂停累计（ePause
                  双出口：判据恢复 / 撤使能，R98）；累计饱和（fEnergyKwh 越上限
                  1.0E12，可表性反算：远低于 LREAL 上限 1.8E308）→ 0387 锁存；
                  4) 故障级：0385 组态非法 / 0386 输入非有限锁存 / 0387 饱和锁存；
                  5) 信息级三码：审计激活沿 / 温差判据恢复沿 / 累计复位完成沿；
                  6) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：tCycle <= 0、fCpKj <= 0、fRhoKgL <= 0、fDtMinK < 0
                  → 0385 锁存，ELSE 兜底归并 0385（码表声明），累计停发；
                  ② 非有限判据用自反比较与差值自减双判（禁近似阈值，R79）；
                  ③ ΔT 上下双向均参与功率（冷/热侧同式），不按方向拆分归因
                  （本件为能量计量非保护判据，R146 方向拆分不适用）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0385~0387 / 04AD~04AF）:
    16#0005_0385 故障级：组态非法（周期/比热/密度/温差阈域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_0386 故障级：流量或温度输入非有限锁存（累计暂停，安全侧），锁存至 bReset
    16#0005_0387 故障级：能量累计饱和锁存（越 1.0E12 kWh 上限，停止累计），锁存至 bReset
    16#0005_04AD 信息级：审计激活沿（进 eRun）
    16#0005_04AE 信息级：温差判据恢复沿（ePause 判据恢复出口）
    16#0005_04AF 信息级：能量累计复位完成沿
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 2 · 序号 3）
    2026-11-19  v1.0.1  R42 终审返修：① 补声明内部相位变量 _eState（首版漏声明，
                        段 4/CASE 引用未声明变量属编译阻断缺陷，机检盲区）；
                        ② 新增段 4A 故障锁存相位迁移闸——0385/0386/0387 锁存后
                        _eState 强制迁 eFault，冻结 eRun 相内累计递增（否则饱和
                        锁存后 fEnergyKwh 持续越限增长、0385 期间累计不冻结）；
                        对外引脚契约不变。
*)

TYPE E_DL_HmaState :
(
    eIdle   := 0,    // 未使能：不累计 / Idle, not accumulating
    eRun    := 10,   // 审计中：逐周期累计 / Run, per-cycle accumulating
    ePause  := 20,   // 暂停：温差判据无效 / Pause, delta-T verdict invalid
    eFault  := 90    // 故障：非有限或饱和锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_HydronicMeterAudit
VAR_INPUT
    fFlowLpm     : REAL := 0.0;       // 侧流量 [L/min]，调用方注入 / Loop flow rate
    fTinC        : REAL := 12.0;      // 供水温度 [°C] / Supply water temperature
    fToutC       : REAL := 7.0;       // 回水温度 [°C] / Return water temperature
    fCpKj        : REAL := 4.186;     // 水比热 [kJ/(kg·K)]，域 > 0 / Specific heat capacity
    fRhoKgL      : REAL := 1.0;       // 水密度 [kg/L]，域 > 0 / Water density
    fDtMinK      : REAL := 0.5;       // 温差判据下限 [K]，域 >= 0 / Minimum delta-T verdict threshold
    fEnergyCap   : REAL := 1.0E12;    // 能量累计上限 [kWh]，可表性反算见头注释 / Energy accumulation cap
    tCycle       : TIME := T#1S;      // 审计累加周期 [ms]，域 > 0 / Audit accumulation cycle
    bAuditEn     : BOOL := FALSE;     // 审计使能（电平）[-] / Audit enable, level
    bEnergyRst   : BOOL := FALSE;     // 能量复位指令，上升沿清累计 [-] / Energy reset command edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_HmaState;     // 状态出口，段尾单点映射 / State outlet
    fPowerKw     : REAL;              // 逐周期功率 [kW] / Per-cycle power
    fEnergyKwh   : REAL;              // 能量累计 [kWh] / Accumulated energy
    bDtInvalid   : BOOL;              // 温差判据无效镜像 [-] / Delta-T invalid mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState      : E_DL_HmaState := E_DL_HmaState.eIdle;  // 内部相位（CASE 唯一写入目标；R42 终审补声明）/ Internal phase
    rtEnergyRst  : R_TRIG;            // 能量复位沿实例，无条件刷新 / Energy reset edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _fDt         : REAL;              // 侧温差 [K]（当拍量）/ Loop delta temperature
    _bDtOk       : BOOL;              // 温差判据有效当拍量 [-] / Delta-T verdict valid flag
    _bNonFin     : BOOL;              // 输入非有限当拍量 [-] / Non-finite input flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_fDt := fTinC - fToutC;                              // 侧温差（当拍量）
_bDtOk := ABS(_fDt) >= fDtMinK;                      // 温差判据有效（当拍量，容差式阈值）
_bNonFin := (fFlowLpm <> fFlowLpm) OR (fTinC <> fTinC) OR (fToutC <> fToutC)
         OR ((fFlowLpm - fFlowLpm) <> (fFlowLpm - fFlowLpm))
         OR ((fTinC - fTinC) <> (fTinC - fTinC))
         OR ((fToutC - fToutC) <> (fToutC - fToutC));        // 非有限防御（NaN 自反 + 差值自减）
rtEnergyRst(CLK := bEnergyRst);                      // 能量复位沿（每拍必调）
rtReset(CLK := bReset);                              // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
fPowerKw := 0.0;                    // 功率出口缺省 0
bDtInvalid := FALSE;                // 判据无效镜像缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tCycle) <= 0) OR (fCpKj <= 0.0) OR (fRhoKgL <= 0.0) OR (fDtMinK < 0.0) THEN
    _uFault := 16#0005_0385;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF
IF rtEnergyRst.Q THEN               // 能量复位沿（当拍量）
    fEnergyKwh := 0.0;              // 累计清零
    _uInfo := 16#0005_04AF;         // 信息级：累计复位完成沿
END_IF

(* —— 段 3：非有限与饱和锁存（判据当拍量；安全侧赋值右值仅常量，FB32-4） —— *)
IF _bNonFin THEN
    fPowerKw := 0.0;                // 安全侧功率清零（常量右值）
    _uFault := 16#0005_0386;        // 故障级：输入非有限锁存
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (fEnergyKwh >= fEnergyCap) THEN
    _uFault := 16#0005_0387;        // 故障级：累计饱和锁存
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT _bNonFin = 当拍量；NOT bAuditEn = 当拍量；
     fEnergyKwh < fEnergyCap 为保持槽值（非当拍量），饱和解除路径为能量复位沿 + 复位沿组合：
     rtEnergyRst.Q 先清 fEnergyKwh，下一拍保持槽值已降，复位沿当拍量配合解除。 —— *)
IF rtReset.Q AND (NOT _bNonFin) AND (NOT bAuditEn) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_HmaState.eFault THEN
        _eState := E_DL_HmaState.eIdle;     // 故障相迁出：回未使能
    END_IF
END_IF

(* —— 段 4A：故障锁存相位迁移闸（R42 终审返修，v1.0.1）：
     0385 组态 / 0386 非有限 / 0387 饱和锁存置位而相位未迁出时强制入故障相，
     冻结 eRun 相内累计递增（否则饱和锁存后 fEnergyKwh 每周期持续越限增长，
     0385 组态非法期间累计亦不冻结）；置于段 4 之后，解除沿当拍清锁不触发
     迁移，无同拍抢迁。 —— *)
IF _bFault AND (_eState <> E_DL_HmaState.eFault) THEN
    _eState := E_DL_HmaState.eFault;        // 锁存即入故障相（累计冻结，仅解除沿可离相）
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底；累计仅在段内承载） —— *)
CASE _eState OF

E_DL_HmaState.eIdle:
    IF bAuditEn AND (NOT _bFault) THEN
        _uInfo := 16#0005_04AD;         // 信息级：审计激活沿
        _eState := E_DL_HmaState.eRun;  // 进审计相
    END_IF

E_DL_HmaState.eRun:
    IF (NOT _bNonFin) AND _bDtOk THEN   // 判据有效：逐周期累计（除数 60.0/T#1H 均非零常量）
        fPowerKw := (LREAL_TO_REAL(LREAL(fFlowLpm) * LREAL(fRhoKgL) * LREAL(fCpKj)
                    * LREAL(_fDt) / 60.0));         // 功率换算（LREAL 精度承载）
        fEnergyKwh := fEnergyKwh + fPowerKw * LREAL_TO_REAL(TIME_TO_LREAL(tCycle) / TIME_TO_LREAL(T#1H));
                                        // 能量累计（周期占比加权）
    ELSE
        _eState := E_DL_HmaState.ePause;    // 判据无效：进暂停相
    END_IF
    IF NOT bAuditEn THEN
        _eState := E_DL_HmaState.eIdle;     // 撤使能：回未使能相
    END_IF

E_DL_HmaState.ePause:
    bDtInvalid := TRUE;                 // 判据无效镜像（相电平）
    IF _bDtOk AND (NOT _bNonFin) THEN   // 出口 1：判据恢复（事件量）
        _uInfo := 16#0005_04AE;         // 信息级：温差判据恢复沿
        _eState := E_DL_HmaState.eRun;  // 回审计相
    ELSIF NOT bAuditEn THEN             // 出口 2：撤使能（前置条件消失，R98 双出口）
        _eState := E_DL_HmaState.eIdle; // 回未使能相
    END_IF

E_DL_HmaState.eFault:
    ;                                   // 故障相：累计冻结，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_0385;            // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_HmaState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    fPowerKw := 0.0;                // 故障相功率出口强制 0（安全侧）
    bDtInvalid := FALSE;            // 故障相判据镜像强制 FALSE
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
