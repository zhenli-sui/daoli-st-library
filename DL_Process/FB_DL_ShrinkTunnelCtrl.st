(*
  FB_DL_ShrinkTunnelCtrl  —  热收缩炉温区-网速联动三段工艺窗 / Shrink tunnel zone-temperature to belt-speed linkage in three process windows
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat — 工艺联动族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 三段配方顺控：ePre（预缩）→ eMain（主缩）→ eSettle（定型）→ eDone，
                  段推进 TON（tonAdvPre/tonAdvMain/tonAdvSet）与总超时 TON（tonPhaseTo）
                  成对分实例（R233 纪律）；
                  2) 温区-网速联动：温区均温（来源 = 上游 FB_DL_HeatCoolZone 各区温度镜像，
                  经 aZoneTemp 引脚注入，本件不实例化 HeatCoolZone——每区需四重接口注入，
                  组合方式见边界①）落当前段窗 [fXxxLo, fXxxHi] → 网速设定 = fVelMax；
                  越窗 → 降速至 fVelMin（保窗优先），越窗沿/回窗沿置信息级；
                  3) 段推进沿 048F；越窗降速激活沿 0490；回窗恢复沿 0491；
                  4) 段超时或非法相位兜底 → 0369 锁存；温度非有限 → 0368 锁存。
  边界 Boundary : ① 温度源组合方式：上游每温区一个 FB_DL_HeatCoolZone 实例，其加热/冷却
                  执行后的区温（或经 I_DL_AnalogSensor 读数）由调用方逐区镜像入 aZoneTemp；
                  本件只消费温度数值做工艺窗判定，不承载温区 PID（分工：HeatCoolZone 管区
                  内恒温，本件管跨区工艺窗与网速联动）；
                  ② 组态闸：uZoneCnt < 1 或 > 8、fVelMin <= 0 或 >= fVelMax、任一窗上下限
                  颠倒 → 0367 锁存；
                  ③ 网速下限 > 0 组态闸（防零速死锁）；配方推进与超时 TON 分实例；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 与 FB_DL_HeatCoolZone 温度镜像组合（不实例化）；Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0367~0369 / 048F~0491）:
    16#0005_0367 故障级：组态非法（站数/网速域/工艺窗颠倒），锁存至 bReset
    16#0005_0368 故障级：温区温度非有限（NaN 自反判），锁存至 bReset
    16#0005_0369 故障级：段超时或相位落 ELSE 兜底，锁存至 bReset
    16#0005_048F 信息级：段推进沿（Pre→Main→Settle）
    16#0005_0490 信息级：越窗降速激活沿
    16#0005_0491 信息级：回窗恢复沿（降速解除）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 4 · 序号 3）
*)

TYPE E_DL_ShrinkPhase :
(
    eIdle   := 0,    // 空闲：等启动沿 / Idle, waiting start edge
    ePre    := 10,   // 预缩段 / Pre-shrink phase
    eMain   := 20,   // 主缩段 / Main-shrink phase
    eSettle := 30,   // 定型段 / Settle phase
    eDone   := 40,   // 完成 / Done
    eFault  := 90    // 故障 / Fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_ShrinkTunnelCtrl
VAR_INPUT
    aZoneTemp    : ARRAY[1..8] OF LREAL;  // 各温区实际温度 [°C]（HeatCoolZone 镜像）/ Zone temperatures mirrored
    uZoneCnt     : UINT := 1;         // 温区数 [区]，域 1..8 / Zone count
    fVelMin      : LREAL := 5.0;      // 网速下限（降速保窗档）[m/min]，域 > 0 / Belt speed lower bound
    fVelMax      : LREAL := 30.0;     // 网速正常档 [m/min]，域 > fVelMin / Belt speed normal bound
    fPreLo       : LREAL := 120.0;    // 预缩窗下限 [°C] / Pre-shrink window low
    fPreHi       : LREAL := 160.0;    // 预缩窗上限 [°C] / Pre-shrink window high
    fMainLo      : LREAL := 180.0;    // 主缩窗下限 [°C] / Main-shrink window low
    fMainHi      : LREAL := 220.0;    // 主缩窗上限 [°C] / Main-shrink window high
    fSetLo       : LREAL := 90.0;     // 定型窗下限 [°C] / Settle window low
    fSetHi       : LREAL := 130.0;    // 定型窗上限 [°C] / Settle window high
    tPreDur      : TIME := T#30S;     // 预缩段时长 [ms]，域 > 0 / Pre-phase duration
    tMainDur     : TIME := T#60S;     // 主缩段时长 [ms]，域 > 0 / Main-phase duration
    tSetDur      : TIME := T#45S;     // 定型段时长 [ms]，域 > 0 / Settle-phase duration
    tTotalTo     : TIME := T#300S;    // 配方总超时 [ms]，域 > 0 / Total recipe timeout
    bStart       : BOOL := FALSE;     // 启动沿 [-] / Start edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    ePhase       : E_DL_ShrinkPhase;  // 段出口，段尾单点映射 / Phase outlet
    fVelSet      : LREAL;             // 网速设定出口 [m/min] / Belt speed setpoint outlet
    bTempOk      : BOOL;              // 温度落当前段窗标志 [-] / Temperature in-window flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonAdvPre    : TON;               // 预缩段推进 TON，无条件刷新 / Pre-phase advance timer
    tonAdvMain   : TON;               // 主缩段推进 TON，无条件刷新 / Main-phase advance timer
    tonAdvSet    : TON;               // 定型段推进 TON，无条件刷新 / Settle-phase advance timer
    tonPhaseTo   : TON;               // 配方总超时 TON（专用超时命名），无条件刷新 / Total timeout timer
    rtStart      : R_TRIG;            // 启动沿实例，无条件刷新 / Start edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_ShrinkPhase := E_DL_ShrinkPhase.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fZoneAvg    : LREAL;             // 温区均温 [°C] / Zone average temperature
    _nCap        : INT;               // 生效温区数 [区] / Effective zone count
    _bInWin      : BOOL;              // 温度落窗当拍量 [-] / In-window current-scan flag
    _bSlowPrev   : BOOL;              // 上拍降速镜像（回窗沿判据）/ Previous slow mirror
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    i            : INT;               // 均温循环游标 [索引] / Average loop cursor
    _nGuard      : INT;               // 均温守卫计数 [次] / Average guard counter
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtStart(CLK := bStart);                                   // 启动沿（每拍必调）
rtReset(CLK := bReset);                                   // 复位沿（每拍必调）
tonAdvPre(IN := (_eState = E_DL_ShrinkPhase.ePre), PT := tPreDur);      // 预缩推进（单相独占）
tonAdvMain(IN := (_eState = E_DL_ShrinkPhase.eMain), PT := tMainDur);   // 主缩推进（单相独占）
tonAdvSet(IN := (_eState = E_DL_ShrinkPhase.eSettle), PT := tSetDur);   // 定型推进（单相独占）
tonPhaseTo(IN := (_eState = E_DL_ShrinkPhase.ePre)
           OR (_eState = E_DL_ShrinkPhase.eMain)
           OR (_eState = E_DL_ShrinkPhase.eSettle), PT := tTotalTo);    // 总超时（配方相集合）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据；网速下限 > 0 组态闸） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    _eState := E_DL_ShrinkPhase.eIdle;  // 相位回空闲
END_IF
_nCap := UINT_TO_INT(uZoneCnt);     // 温区数快照
IF (_nCap < 1) OR (_nCap > 8) OR (fVelMin <= 0.0) OR (fVelMin >= fVelMax)
   OR (fPreLo >= fPreHi) OR (fMainLo >= fMainHi) OR (fSetLo >= fSetHi)
   OR (TIME_TO_DINT(tTotalTo) <= 0) THEN
    _uFault := 16#0005_0367;        // 故障级：组态非法
    _bFault := TRUE;
END_IF

(* —— 段 3：温区均温计算（LREAL 口径；守卫循环；防除零由 uZoneCnt 组态闸承载） —— *)
_fZoneAvg := 0.0;                   // 均温累加器清零
_nGuard := 0;                       // 守卫清零
IF (NOT _bFault) AND (_nCap >= 1) AND (_nCap <= 8) THEN
    FOR i := 1 TO _nCap DO
        _nGuard := _nGuard + 1;     // 守卫递增
        IF _nGuard > 8 THEN
            EXIT;                   // 守卫兜底退出（理论不可达）
        END_IF
        IF (aZoneTemp[i] <> aZoneTemp[i]) OR ((aZoneTemp[i] - aZoneTemp[i]) <> (aZoneTemp[i] - aZoneTemp[i])) THEN
            _uFault := 16#0005_0368;    // 故障级：温区温度非有限
            _bFault := TRUE;
        END_IF
        _fZoneAvg := _fZoneAvg + aZoneTemp[i];  // 累加
    END_FOR
    IF NOT _bFault THEN
        _fZoneAvg := _fZoneAvg / INT_TO_LREAL(_nCap);   // 均温（分母 >= 1 已过闸，防除零）
    END_IF
END_IF

(* —— 段 4：工艺窗判定与网速联动（当拍量判据） —— *)
CASE _eState OF
E_DL_ShrinkPhase.ePre:
    _bInWin := (_fZoneAvg >= fPreLo) AND (_fZoneAvg <= fPreHi);     // 预缩窗判定
E_DL_ShrinkPhase.eMain:
    _bInWin := (_fZoneAvg >= fMainLo) AND (_fZoneAvg <= fMainHi);   // 主缩窗判定
E_DL_ShrinkPhase.eSettle:
    _bInWin := (_fZoneAvg >= fSetLo) AND (_fZoneAvg <= fSetHi);     // 定型窗判定
ELSE
    _bInWin := FALSE;               // 非工艺相无窗判定
END_CASE
bTempOk := _bInWin AND (NOT _bFault);   // 落窗出口
IF (NOT _bFault) AND bStart THEN
    IF _bInWin THEN
        fVelSet := fVelMax;         // 落窗：正常档网速
        IF _bSlowPrev THEN
            _uInfo := 16#0005_0491; // 信息级：回窗恢复沿
        END_IF
    ELSE
        fVelSet := fVelMin;         // 越窗：降速保窗
        IF NOT _bSlowPrev THEN
            _uInfo := 16#0005_0490; // 信息级：越窗降速激活沿
        END_IF
    END_IF
ELSE
    fVelSet := 0.0;                 // 非运行相网速归零（安全侧）
END_IF

(* —— 段 5：配方相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_ShrinkPhase.eIdle:
    IF rtStart.Q AND (NOT _bFault) THEN
        _eState := E_DL_ShrinkPhase.ePre;   // 进预缩段
    END_IF

E_DL_ShrinkPhase.ePre:
    IF _bFault THEN
        _eState := E_DL_ShrinkPhase.eFault; // 故障相
    ELSIF tonPhaseTo.Q THEN
        _uFault := 16#0005_0369;            // 故障级：配方总超时
        _bFault := TRUE;
        _eState := E_DL_ShrinkPhase.eFault;
    ELSIF tonAdvPre.Q THEN
        _uInfo := 16#0005_048F;             // 信息级：段推进沿
        _eState := E_DL_ShrinkPhase.eMain;  // 进主缩段
    END_IF

E_DL_ShrinkPhase.eMain:
    IF _bFault THEN
        _eState := E_DL_ShrinkPhase.eFault; // 故障相
    ELSIF tonPhaseTo.Q THEN
        _uFault := 16#0005_0369;            // 故障级：配方总超时
        _bFault := TRUE;
        _eState := E_DL_ShrinkPhase.eFault;
    ELSIF tonAdvMain.Q THEN
        _uInfo := 16#0005_048F;             // 信息级：段推进沿
        _eState := E_DL_ShrinkPhase.eSettle;    // 进定型段
    END_IF

E_DL_ShrinkPhase.eSettle:
    IF _bFault THEN
        _eState := E_DL_ShrinkPhase.eFault; // 故障相
    ELSIF tonPhaseTo.Q THEN
        _uFault := 16#0005_0369;            // 故障级：配方总超时
        _bFault := TRUE;
        _eState := E_DL_ShrinkPhase.eFault;
    ELSIF tonAdvSet.Q THEN
        _uInfo := 16#0005_048F;             // 信息级：段推进沿
        _eState := E_DL_ShrinkPhase.eDone;  // 进完成相
    END_IF

E_DL_ShrinkPhase.eDone:
    IF NOT bStart THEN
        _eState := E_DL_ShrinkPhase.eIdle;  // 指令撤销回空闲
    END_IF

E_DL_ShrinkPhase.eFault:
    ;                                   // 故障相：等复位沿（段 2 承载迁出）

ELSE
    _uFault := 16#0005_0369;            // 故障级：非法相位兜底（归并超时码，头注释码表声明）
    _bFault := TRUE;
    _eState := E_DL_ShrinkPhase.eFault; // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    fVelSet := 0.0;                 // 故障期网速归零（安全侧）
    bTempOk := FALSE;               // 故障期落窗出口 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
ePhase := _eState;                  // 状态出口单点映射
_bSlowPrev := (NOT _bInWin) AND (NOT _bFault);   // 降速镜像快照

END_FUNCTION_BLOCK
