(*
  组件名 Component   : FB_DL_DesiccantRegenSeq
  子库 Sublibrary    : DL_Process
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 干燥剂吸附塔再生顺控（ISA-88 相语义最小子集）：
                       1) 四相顺控：吸附（eAdsorb）→ 再生（eRegen）→ 吹冷（eCool）→
                       切换驻留（eSwitchDwell）→ 回吸附，吸附时长由 tAdsorbDur 承载；
                       2) 塔间轮换：A/B 双塔，eSwitchDwell 相完成阀组切换并翻转
                       bTowerAActive/bTowerBActive（切换指令单点出口）；
                       3) 再生温度曲线监视：再生相内再生温度须在
                       [fRegenTempLoC, fRegenTempHiC] 曲线带内，越带持续 tTempDevTo
                       → 故障锁存；
                       4) 各相计时独立 TON 实例（禁跨相复用，R228A）。
  边界 Boundary      : ① 本件只出阀组/加热指令与塔选通，不写物理 IO；
                       ② 吹冷相退出双条件：吹冷计时到 或 出口温度低于 fCoolEndC
                       （事件达成 + 前置消失双路径）；再生许可不满足时吸附相驻留等待；
                       ③ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ④ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-8-isa88 相语义分类与参数域，
                       零代码行复制）
  码位 Code          : 16#06_0_BE（Process 段 0006，B 子带 BE 格）
  码表 Error codes（本件格 06_0_BE，单轨子道：故障 0x02BE / 信息 0x01BE）:
    16#0006_02BE 故障级：再生顺控故障总码（再生温度越带 / 切换超时 / 组态非法 /
                 输入非有限），锁存至复位
    16#0006_01BE 信息级：塔切换完成沿（eSwitchDwell → eAdsorb 迁移拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 3 · 序号 15）
*)

TYPE E_DL_DrsPhase :
(
    eIdle        := 0,   // 空闲：未使能 / Idle, not enabled
    eAdsorb      := 10,  // 吸附：当前塔吸附运行 / Adsorbing on active tower
    eRegen       := 20,  // 再生：离线塔再生加热 / Regenerating offline tower
    eCool        := 30,  // 吹冷：再生塔吹冷 / Cooling regenerated tower
    eSwitchDwell := 40,  // 切换：塔间阀组切换驻留 / Switching towers dwell
    eFault       := 90   // 故障：总码锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_DesiccantRegenSeq
VAR_INPUT
    bEnable      : BOOL;                   // 使能（电平）[-] / Enable
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    bRegenPermissive: BOOL;                // 再生许可（电平）[-] / Regen permissive
    fRegenTempC  : REAL;                   // 再生温度 [摄氏度] / Regen temperature
    fCoolOutTempC: REAL;                   // 吹冷出口温度 [摄氏度] / Cooling outlet temperature
    tAdsorbDur   : TIME := T#8H;           // 吸附时长 [毫秒] / Adsorption duration
    tRegenDur    : TIME := T#4H;           // 再生时长 [毫秒] / Regen duration
    tCoolMaxDur  : TIME := T#2H;           // 吹冷最大时长 [毫秒] / Cooling max duration
    tSwitchDur   : TIME := T#60S;          // 切换驻留 [毫秒] / Switch dwell
    fRegenTempLoC: REAL := 120.0;          // 再生温度带下限 [摄氏度] / Regen band floor
    fRegenTempHiC: REAL := 200.0;          // 再生温度带上限 [摄氏度] / Regen band ceiling
    fCoolEndC    : REAL := 45.0;           // 吹冷结束温度 [摄氏度] / Cooling end temperature
    tTempDevTo   : TIME := T#30S;          // 温度越带确认窗 [毫秒] / Temperature deviation timeout
END_VAR
VAR_OUTPUT
    bTowerAActive: BOOL;                   // A 塔吸附选通 [-] / Tower A active
    bTowerBActive: BOOL;                   // B 塔吸附选通 [-] / Tower B active
    bRegenHeatCmd: BOOL;                   // 再生加热指令 [-] / Regen heat command
    bRegenCoolCmd: BOOL;                   // 吹冷指令 [-] / Regen cool command
    bSwitchCmd   : BOOL;                   // 塔切换指令（驻留相电平）[-] / Tower switch command
    ePhase       : E_DL_DrsPhase;          // 相位出口，段尾单点映射 / Phase outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset   : R_TRIG;                    // 复位沿实例，段 0 无条件刷新 / Reset edge
    tonAdsorb : TON;                       // 吸附计时（独立实例） / Adsorption timer
    tonRegen  : TON;                       // 再生计时（独立实例） / Regen timer
    tonCoolMax: TON;                       // 吹冷最大计时（独立实例） / Cooling max timer
    tonSwitch : TON;                       // 切换驻留计时（独立实例） / Switch dwell timer
    tonTempDevTo: TON;                     // 温度越带确认（专用超时件命名） / Temp deviation timeout
    _ePhase   : E_DL_DrsPhase := E_DL_DrsPhase.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bTowerA  : BOOL := TRUE;              // 内部塔选（TRUE = A 塔吸附）/ Internal tower select
    _bFault   : BOOL;                      // 故障锁存位（锁存量） / Latched fault bit
    _uFault   : UDINT;                     // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad  : BOOL;                      // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin  : BOOL;                      // 输入非有限当拍量 [-] / Non-finite input flag
    _bTempDev : BOOL;                      // 温度越带当拍量 [-] / Temperature deviation flag
END_VAR
VAR CONSTANT
    DL_ABS_MAX : REAL := 1.0E30;           // 有限值判定上界 [摄氏度] / Finite bound
    DL_ZERO    : REAL := 0.0;              // 零常量 [摄氏度] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内；各相独立实例禁复用） —— *)
rtReset(CLK := bReset);
tonAdsorb (IN := (_ePhase = E_DL_DrsPhase.eAdsorb) AND (NOT _bFault), PT := tAdsorbDur);
tonRegen  (IN := (_ePhase = E_DL_DrsPhase.eRegen) AND (NOT _bFault), PT := tRegenDur);
tonCoolMax(IN := (_ePhase = E_DL_DrsPhase.eCool) AND (NOT _bFault), PT := tCoolMaxDur);
tonSwitch (IN := (_ePhase = E_DL_DrsPhase.eSwitchDwell) AND (NOT _bFault), PT := tSwitchDur);
_bTempDev := (_ePhase = E_DL_DrsPhase.eRegen)
             AND ((fRegenTempC < fRegenTempLoC) OR (fRegenTempC > fRegenTempHiC));
tonTempDevTo(IN := _bTempDev AND (NOT _bFault), PT := tTempDevTo);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/_bTowerA 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _ePhase := E_DL_DrsPhase.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与判据换算引脚） —— *)
IF (fRegenTempLoC >= fRegenTempHiC) OR (tAdsorbDur = T#0S) OR (tRegenDur = T#0S)
   OR (tCoolMaxDur = T#0S) OR (tSwitchDur = T#0S) OR (tTempDevTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fRegenTempC <> fRegenTempC) OR ((fRegenTempC - fRegenTempC) <> DL_ZERO)
   OR (fCoolOutTempC <> fCoolOutTempC) OR ((fCoolOutTempC - fCoolOutTempC) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：六态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF

E_DL_DrsPhase.eIdle:
    bTowerAActive := FALSE;
    bTowerBActive := FALSE;
    bRegenHeatCmd := FALSE;
    bRegenCoolCmd := FALSE;
    bSwitchCmd    := FALSE;
    IF bEnable AND (NOT _bCfgBad) THEN
        _bTowerA := TRUE;                // 入运行相：A 塔先吸附（固定初序）
        _ePhase  := E_DL_DrsPhase.eAdsorb;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BE;
        bError  := TRUE;
        _ePhase := E_DL_DrsPhase.eFault;
    END_IF

E_DL_DrsPhase.eAdsorb:
    bTowerAActive := _bTowerA;
    bTowerBActive := NOT _bTowerA;
    bRegenHeatCmd := FALSE;
    bRegenCoolCmd := FALSE;
    bSwitchCmd    := FALSE;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BE;
        bError  := TRUE;
        _ePhase := E_DL_DrsPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_DrsPhase.eIdle;  // 使能撤销回空闲
    ELSIF tonAdsorb.Q AND bRegenPermissive THEN
        _ePhase := E_DL_DrsPhase.eRegen; // 吸附时长到且再生许可满足：进再生
    ELSIF tonAdsorb.Q THEN
        ;                                // 吸附时长到但许可未满足：吸附相驻留等待（退出前置消失路径）
    END_IF

E_DL_DrsPhase.eRegen:
    bTowerAActive := _bTowerA;
    bTowerBActive := NOT _bTowerA;
    bRegenHeatCmd := TRUE;
    bRegenCoolCmd := FALSE;
    bSwitchCmd    := FALSE;
    IF _bNonFin OR tonTempDevTo.Q THEN
        _bFault := TRUE;                 // 温度越带或输入非法：锁存
        _uFault := 16#0006_02BE;
        bError  := TRUE;
        _ePhase := E_DL_DrsPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_DrsPhase.eIdle;  // 使能撤销回空闲
    ELSIF tonRegen.Q THEN
        _ePhase := E_DL_DrsPhase.eCool;  // 迁出条件 1：再生时长到
    END_IF

E_DL_DrsPhase.eCool:
    bTowerAActive := _bTowerA;
    bTowerBActive := NOT _bTowerA;
    bRegenHeatCmd := FALSE;
    bRegenCoolCmd := TRUE;
    bSwitchCmd    := FALSE;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BE;
        bError  := TRUE;
        _ePhase := E_DL_DrsPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_DrsPhase.eIdle;  // 使能撤销回空闲
    ELSIF (fCoolOutTempC <= fCoolEndC) OR tonCoolMax.Q THEN
        _ePhase := E_DL_DrsPhase.eSwitchDwell;   // 迁出双条件：温度达成 或 吹冷计时到
    END_IF

E_DL_DrsPhase.eSwitchDwell:
    bTowerAActive := FALSE;
    bTowerBActive := FALSE;
    bRegenHeatCmd := FALSE;
    bRegenCoolCmd := FALSE;
    bSwitchCmd    := TRUE;               // 切换指令（驻留相电平）
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BE;
        bError  := TRUE;
        _ePhase := E_DL_DrsPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_DrsPhase.eIdle;  // 使能撤销回空闲
    ELSIF tonSwitch.Q THEN
        _bTowerA := NOT _bTowerA;        // 塔间轮换翻转
        uErrId := 16#0006_01BE;          // 信息级：塔切换完成沿
        _ePhase := E_DL_DrsPhase.eAdsorb;    // 回吸附相（待机可返回路径）
    END_IF

E_DL_DrsPhase.eFault:
    bTowerAActive := FALSE;
    bTowerBActive := FALSE;
    bRegenHeatCmd := FALSE;              // 故障相：加热指令安全侧撤销
    bRegenCoolCmd := FALSE;
    bSwitchCmd    := FALSE;
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0006_02BE;
    bError  := TRUE;
    _ePhase := E_DL_DrsPhase.eFault;
END_CASE

(* —— 段 5｜相位出口单点映射 —— *)
ePhase := _ePhase;
END_FUNCTION_BLOCK
