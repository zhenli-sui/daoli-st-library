(*
  FB_DL_HjtPvdSeq  —  HJT 光伏 PVD 镀膜腔体顺控 / HJT PVD coating chamber sequence
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B6
  段位说明      : R38 W7 预留 B6~BF 本轮正式启用，本件启用 B6 格
  版本 Version  : 1.0.0
  来源 Source   : 自研线（半导体/光伏工艺）— HJT PVD 镀膜公开工艺段序
  溯源 Origin   : clean-room 实现，未复制任何源码行
                  （段序语义对齐 FB_DL_StepSequencer，不实例化；接口契约按 I_DL_* 真实成员名调用）
  功能 Function : 1) 四段顺控 BaseVac→Preheat→Coat→Unload，段尾经 Done 回 Idle；
                  2) 本底真空段：抽气至 fBaseVacKpa（深度判据）；
                  3) 预热段：温区 SetSetpoint 到位 + 配方时长驻留；
                  4) 工艺镀膜段：真空深度与温度双到位联锁内置（联锁不满足只等待不故障），
                  配方时长到点收段；
                  5) 取片段：放气常压确认 AND bUnloadPermit 联锁双确认才进 Done；
                  6) 段超时升级：四段各配独立超时 TON，超时锁故障。
  边界 Boundary : ① 真空接口契约：iVac.fPressure 为负压值，深度 = −fPressure（取正深度比较）；
                  ② 组态域闸覆盖全部参与换算引脚（R151）；配方/超时全 0 判组态错；
                  ③ R228-A 达标声明：八只 TON 均单相独占（IN 为单相等式），跨相迁移拍 IN 必断；
                  ④ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此；
                  ⑤ 解除式自证：段超时故障解除 = bReset 上升沿 AND eState = Idle（迁出边唯一可达）；
                  ⑥ CASE 全态覆盖 + ELSE 兜底置 Fault。
  依赖 Depends  : I_DL_VacuumGenerator / I_DL_TemperatureZone（注入，不实例化）；
                  段序语义对齐 FB_DL_StepSequencer（已注册，不实例化）
  码表 Error codes（本件格 06_0_B6，子码步进 +0x100）:
    16#0006_01B6 信息级：周期完成（Done 相）
    16#0006_02B6 故障级：组态非法（真空目标/温度目标/容差/常压阈/配方/超时域非法），锁存至复位
    16#0006_03B6 故障级：段超时升级（四段独立计时），锁存至复位
    16#0006_04B6 故障级：注入件故障（真空/温区 bFault），锁存至复位
    16#0006_05B6 信息级：镀膜双到位联锁等待（不置故障）
    16#0006_06B6 信息级：取片联锁等待（bUnloadPermit 未给，不置故障）
    16#0006_07B6 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 3 · 序号 14）
*)

TYPE E_DL_PvdState :
(
    eIdle     := 0,    // 空闲：等启动指令 / Idle, waiting for start
    eBaseVac  := 10,   // 本底真空段：抽气至目标深度 / Base vacuum, pump down to target
    ePreheat  := 20,   // 预热段：基片升温 + 配方驻留 / Preheat, substrate heating dwell
    eCoat     := 30,   // 工艺镀膜段：双到位联锁 + 配方驻留 / Coating, dual interlock and dwell
    eUnload   := 40,   // 取片段：放气常压 + 取片许可 / Unload, venting and transfer permit
    eDone     := 50,   // 完成：周期落定 / Done
    eFault    := 90    // 故障：组态/超时/注入件锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_HjtPvdSeq
VAR_INPUT
    bStart        : BOOL := FALSE;      // 启动指令（上升沿）/ Start command
    fBaseVacKpa   : REAL := 5.0E-3;     // 本底真空目标深度 [kPa]，域 > 0 / Base vacuum target depth
    fPreheatTempC : REAL := 150.0;      // 预热目标温度 [°C]，域 > 0 / Preheat target temperature
    fCoatTempC    : REAL := 180.0;      // 镀膜目标温度 [°C]，域 > 0 / Coating target temperature
    fTempTolC     : REAL := 2.0;        // 温度到位容差 [°C]，域 > 0 / Temperature tolerance
    fAtmVacKpa    : REAL := 2.0;        // 常压确认阈值 [kPa]，域 >= 0 / Atmospheric confirmation threshold
    tPreheatDur   : TIME := T#600S;     // 预热段配方时长 [ms] / Preheat recipe duration
    tCoatDur      : TIME := T#900S;     // 镀膜段配方时长 [ms] / Coating recipe duration
    tSegTimeout   : TIME := T#1800S;    // 单段超时 [ms]，域 > 0 / Per-segment timeout
    bUnloadPermit : BOOL := FALSE;      // 取片联锁许可（传输机构就位）[-] / Unload permit interlock
    bReset        : BOOL := FALSE;      // 复位（eFault 迁出唯一沿）/ Reset, sole fault exit edge
END_VAR
VAR_OUTPUT
    bCycleDone    : BOOL;               // 周期完成 / Cycle done
    nSegment      : INT;                // 当前段号 [0..3]（0=本底真空 1=预热 2=镀膜 3=取片）/ Segment index
    fVacKpa       : REAL;               // 真空深度出口 [kPa]（取正深度）/ Vacuum depth outlet
    bCoatReady    : BOOL;               // 镀膜双到位联锁满足 [-] / Coating dual interlock satisfied
    nErrId        : UDINT;              // 事件码，0 = 无事件 / Event code
    eState        : E_DL_PvdState;      // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iVac      : I_DL_VacuumGenerator;   // 真空系统引用（注入，不实例化）/ Vacuum system reference
    iTempZone : I_DL_TemperatureZone;   // 温区引用（注入，不实例化）/ Temperature zone reference
END_VAR
VAR
    tonVacTo   : TON;                  // 本底真空段超时（单相独占）/ Base-vac timeout, single phase
    tonPreDur  : TON;                  // 预热段配方计时（单相独占，PT=配方时长）/ Preheat recipe timer, single phase
    tonPreTo   : TON;                  // 预热段超时（单相独占）/ Preheat timeout, single phase
    tonCoatDur : TON;                  // 镀膜段配方计时（单相独占，PT=配方时长）/ Coating recipe timer, single phase
    tonCoatTo  : TON;                  // 镀膜段超时（单相独占）/ Coating timeout, single phase
    tonUnlTo   : TON;                  // 取片段超时（单相独占）/ Unload timeout, single phase
    tonWch     : TON;                  // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtStart    : R_TRIG;               // 启动上升沿 / Start rising edge
    rtReset    : R_TRIG;               // 复位上升沿 / Reset rising edge
    _eState    : E_DL_PvdState := E_DL_PvdState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rVacDepth : REAL;                 // 真空深度暂存 [kPa] / Vacuum depth scratch
    _rTempAct  : REAL;                 // 温区实测温度 [°C] / Zone actual temperature
    _rTempTgt  : REAL;                 // 当前相目标温度 [°C] / Current-phase temperature target
    _bVacOk    : BOOL;                 // 真空到位标志 / Vacuum reached flag
    _bTempOk   : BOOL;                 // 温度到位标志 / Temperature reached flag
    _uFault    : UDINT;                // 故障码锁存 / Latched fault code
    _uInfo     : UDINT;                // 信息码，每拍重算 / Info code
    _bFault    : BOOL;                 // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                 // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_PVD_WATCH_PT : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
    DL_PVD_INF_CAP  : REAL := 1.0E15; // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bStart);                                                // 启动沿刷新，每拍必调
rtReset(CLK := bReset);                                                // 复位沿刷新，每拍必调
tonWch(IN := (NOT tonWch.Q), PT := DL_PVD_WATCH_PT);                   // 观察窗自复位（表达式入参）
tonVacTo(IN := (_eState = E_DL_PvdState.eBaseVac), PT := tSegTimeout);     // 本底真空超时（单相独占）
tonPreDur(IN := (_eState = E_DL_PvdState.ePreheat), PT := tPreheatDur);    // 预热配方计时（单相独占，PT=配方时长）
tonPreTo(IN := (_eState = E_DL_PvdState.ePreheat), PT := tSegTimeout);     // 预热超时（单相独占）
tonCoatDur(IN := (_eState = E_DL_PvdState.eCoat), PT := tCoatDur);         // 镀膜配方计时（单相独占，PT=配方时长）
tonCoatTo(IN := (_eState = E_DL_PvdState.eCoat), PT := tSegTimeout);       // 镀膜超时（单相独占）
tonUnlTo(IN := (_eState = E_DL_PvdState.eUnload), PT := tSegTimeout);      // 取片超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bCycleDone := FALSE;                // 完成出口缺省 FALSE（Done 相单点置位）
bCoatReady := FALSE;                // 联锁满足出口缺省 FALSE（段 6 单点重写）
_bCfgBad := FALSE;                  // 组态非法预清零
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fBaseVacKpa <> fBaseVacKpa) OR (fBaseVacKpa <= 0.0) OR (ABS(fBaseVacKpa) > DL_PVD_INF_CAP)
   OR (fAtmVacKpa < 0.0) OR (TIME_TO_DINT(tSegTimeout) <= 0) THEN
    _bCfgBad := TRUE;               // 真空目标/常压阈/超时非法
END_IF
IF (fPreheatTempC <> fPreheatTempC) OR (fPreheatTempC <= 0.0)
   OR (fCoatTempC <> fCoatTempC) OR (fCoatTempC <= 0.0) OR (fTempTolC <= 0.0) THEN
    _bCfgBad := TRUE;               // 温度目标/容差非法
END_IF
IF (TIME_TO_DINT(tPreheatDur) <= 0) OR (TIME_TO_DINT(tCoatDur) <= 0) THEN
    _bCfgBad := TRUE;               // 配方时长非法
END_IF

(* —— 段 3：eFault 迁出沿（R228-B：rtReset.Q 为输入引脚，恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;
    IF _eState = E_DL_PvdState.eFault THEN
        _eState := E_DL_PvdState.eIdle;     // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 4：过程量只读采集与判据 —— *)
_rVacDepth := -iVac.fPressure;                  // 真空深度 = 负压反馈取反 [kPa]（接口契约：负值=真空）
_rTempAct := iTempZone.fTempActual;             // 温区实测 [°C]
fVacKpa := _rVacDepth;                          // 深度出口（正深度）
_bVacOk := _rVacDepth >= fBaseVacKpa;           // 真空到位判据（每拍重算）
_rTempTgt := fPreheatTempC;                     // 当前相目标温度缺省（镀膜相段内改写）
IF _eState = E_DL_PvdState.eCoat THEN
    _rTempTgt := fCoatTempC;                    // 镀膜相目标温度
END_IF
_bTempOk := ABS(_rTempAct - _rTempTgt) <= MAX(fTempTolC, 1.0E-6);   // 温度到位（容差下限防零容差死判）

(* —— 段 5：相位机（只做迁移与单发命令；出口在段 7） —— *)
CASE _eState OF

E_DL_PvdState.eIdle:
    IF rtStart.Q AND _bCfgBad THEN
        _uFault := 16#0006_02B6;            // 故障级：组态非法
        _bFault := TRUE;
        _eState := E_DL_PvdState.eFault;
    ELSIF rtStart.Q AND (NOT _bCfgBad) THEN
        iVac.CmdEvacuate();                 // 单发抽气指令
        iTempZone.CmdEnable(bOn := TRUE);   // 温区投运
        _eState := E_DL_PvdState.eBaseVac;  // 进本底真空段
    END_IF

E_DL_PvdState.eBaseVac:
    IF (iVac.bFault OR iTempZone.bFault) THEN
        _uFault := 16#0006_04B6;            // 故障级：注入件故障
        _bFault := TRUE;
        iVac.CmdStop();                     // 安全侧全停
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_PvdState.eFault;
    ELSIF tonVacTo.Q THEN
        _uFault := 16#0006_03B6;            // 故障级：本底真空段超时
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_PvdState.eFault;
    ELSIF _bVacOk AND tonWch.Q THEN
        iTempZone.SetSetpoint(fTemp := fPreheatTempC);  // 单发预热设定点
        _eState := E_DL_PvdState.ePreheat;  // 进预热段
    END_IF

E_DL_PvdState.ePreheat:
    IF (iVac.bFault OR iTempZone.bFault) THEN
        _uFault := 16#0006_04B6;
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_PvdState.eFault;
    ELSIF tonPreTo.Q THEN
        _uFault := 16#0006_03B6;            // 故障级：预热段超时
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_PvdState.eFault;
    ELSIF _bTempOk AND tonPreDur.Q THEN
        iTempZone.SetSetpoint(fTemp := fCoatTempC);     // 单发镀膜设定点
        _eState := E_DL_PvdState.eCoat;     // 进镀膜段
    END_IF

E_DL_PvdState.eCoat:
    bCoatReady := _bVacOk AND _bTempOk;     // 双到位联锁派生出口（每拍重算）
    IF (iVac.bFault OR iTempZone.bFault) THEN
        _uFault := 16#0006_04B6;
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_PvdState.eFault;
    ELSIF tonCoatTo.Q THEN
        _uFault := 16#0006_03B6;            // 故障级：镀膜段超时
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_PvdState.eFault;
    ELSIF NOT bCoatReady THEN
        _uInfo := 16#0006_05B6;             // 信息级：双到位联锁等待（不置故障）
    ELSIF tonCoatDur.Q THEN
        iVac.CmdBlowOff();                  // 单发放气（镀膜到点收段）
        _eState := E_DL_PvdState.eUnload;   // 进取片段
    END_IF

E_DL_PvdState.eUnload:
    IF (iVac.bFault OR iTempZone.bFault) THEN
        _uFault := 16#0006_04B6;
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_PvdState.eFault;
    ELSIF tonUnlTo.Q THEN
        _uFault := 16#0006_03B6;            // 故障级：取片段超时
        _bFault := TRUE;
        _eState := E_DL_PvdState.eFault;
    ELSIF (NOT bUnloadPermit) AND (_rVacDepth > fAtmVacKpa) THEN
        _uInfo := 16#0006_06B6;             // 信息级：取片联锁等待（不置故障）
    ELSIF (_rVacDepth <= fAtmVacKpa) AND bUnloadPermit THEN
        iTempZone.CmdEnable(bOn := FALSE);  // 温区退出
        _eState := E_DL_PvdState.eDone;     // 常压 + 许可双确认：进完成相
    END_IF

E_DL_PvdState.eDone:
    bCycleDone := TRUE;                     // 完成出口（Done 相每拍重申）
    _uInfo := 16#0006_01B6;                 // 信息级：周期完成
    IF NOT bStart THEN
        _eState := E_DL_PvdState.eIdle;     // 指令撤销：回空闲
    END_IF

E_DL_PvdState.eFault:
    ;                                       // 故障相：等复位沿（段 3 承载迁出）

ELSE
    _uFault := 16#0006_07B6;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_PvdState.eFault;        // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _eState = E_DL_PvdState.eBaseVac THEN
    nSegment := 0;                          // 段号 0：本底真空
ELSIF _eState = E_DL_PvdState.ePreheat THEN
    nSegment := 1;                          // 段号 1：预热
ELSIF _eState = E_DL_PvdState.eCoat THEN
    nSegment := 2;                          // 段号 2：镀膜
ELSIF _eState = E_DL_PvdState.eUnload THEN
    nSegment := 3;                          // 段号 3：取片
ELSE
    nSegment := -1;                         // Idle/Done/Fault：无有效段号
END_IF
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推）
    bCycleDone := FALSE;                    // 故障相完成出口强制 FALSE（安全侧）
    bCoatReady := FALSE;                    // 故障相联锁出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF
eState := _eState;                          // 状态出口单点映射

END_FUNCTION_BLOCK
