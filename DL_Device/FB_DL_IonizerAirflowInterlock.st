(*
  ==================================================================
  组件名 Component  : FB_DL_IonizerAirflowInterlock
  分类   Category   : DL_Device
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 离子风机风速联锁。风速低于下限持续 tConfirm 确认窗才锁存
                      （单拍毛刺不动作）；放行门控出口（bPermitOk）与消电离
                      有效性出口（bIonValid）分离；失能即解锁回空闲且输出
                      安全侧断开放行。
  来源   Source     : self-esc（ROADMAP R56 评估项转正；借鉴 ISA-TR84 风量联锁
                      确认窗纪律，clean-room 自研实现，未复制任何文档代码行）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；离子风机风速下限
                      联锁为公开防静电工艺语义。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_EsdGroundMonitor（接地判级）分工——本件只做
                      风速联锁与放行门控，不做接地电阻判级。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态闸：fAirMin > 0 且非有限拦截（R151）；
                      二 确认窗纪律：tConfirm 内持续低于下限才锁存，
                         单拍毛刺由 TON.IN 断开自然吸收；
                      三 失能即解锁：回 Idle 相、锁存清除、bPermitOk 安全侧
                         断开放行（R191 显式声明）；
                      四 锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 4 · 序号 17）
  ==================================================================
*)

TYPE E_DL_IaiPhase :
(
    eIdle    := 0,  // 未使能：联锁停摆，放行断开 / disabled, the interlock idle, the permit open
    eRun     := 10, // 运行：风速监视 / running, the airflow watched
    eLatched := 20, // 锁存：风速欠限已确认 / latched, the underrun confirmed
    eFault   := 90  // 故障：传感失效或组态非法 / fault, a sensor failure or an illegal config
);
END_TYPE

TYPE E_DL_IaiFault :
(
    eNone       := 0, // 无成因 / no cause
    eCfgIllegal := 1, // 组态非法：下限越域（故障级，与 bError 配对）/ an illegal config
    eSensorBad  := 2, // 风速非有限（故障级，与 bError 配对）/ a non finite airflow
    eAirLow     := 3, // 风速低于下限已确认锁存（故障级，与 bError 配对）/ the underrun latched
    ePhaseBad   := 4  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_IonizerAirflowInterlock
VAR_INPUT
    bEnable  : BOOL := TRUE;   // 使能，失能即解锁回空闲 [-] / enable, disabling unlocks to idle
    bReset   : BOOL := FALSE;  // 复位上升沿清锁存 [-] / reset rising edge clears the latch
    fAirflow : LREAL := 5.0;   // 风速实测 [米每秒] / the measured airflow [metre per second]
    fAirMin  : LREAL := 1.0;   // 风速下限 [米每秒]，域 大于零 / the airflow floor [metre per second], above zero
    tConfirm : TIME := T#3S;   // 欠限确认窗 [毫秒]，单拍毛刺不动作 / the confirm window [millisecond], a single glitch inert
END_VAR
VAR_OUTPUT
    bPermitOk   : BOOL := FALSE; // 放行门控出口（安全侧断开）[-] / the permit gate outlet, open on the safe side
    bIonValid   : BOOL := FALSE; // 消电离有效性出口（风速在限内）[-] / the ionization validity outlet
    bLatched    : BOOL := FALSE; // 欠限锁存电平 [-] / the underrun latch level
    tConfirmEt  : TIME := T#0S;  // 确认窗已流逝 [毫秒] / the confirm elapsed [millisecond]
    ePhase      : E_DL_IaiPhase := E_DL_IaiPhase.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    eFault      : E_DL_IaiFault := E_DL_IaiFault.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError      : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    tonConfirm : TON; // 欠限确认窗，段 0 无条件刷新 / the confirm window, refreshed unconditionally
    _ePhase : E_DL_IaiPhase := E_DL_IaiPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC : E_DL_IaiFault := E_DL_IaiFault.eNone; // 故障级成因，锁存至复位沿 / the fault cause, latched
    _bFault : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _bInOk  : BOOL := FALSE; // 风速有限 [-] / the airflow finite
    _bCfgOk : BOOL := FALSE; // 组态域内 [-] / the config inside the domain
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonConfirm(IN := (_ePhase = E_DL_IaiPhase.eRun) AND (NOT _bFault) AND _bInOk AND (fAirflow < fAirMin), PT := tConfirm); // 确认窗，IN 串运行相 / 有限 / 欠限三重闸 / the window gated by the phase, the finiteness and the underrun

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit  := TRUE; // 置首扫标志 / raise the flag
    _ePhase := E_DL_IaiPhase.eRun; // 相位从运行起步（使能默认真）/ the phase starts in run
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁运行相（两项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_IaiFault.eNone; // 作用域一：清成因 / scope one, clear the cause
    _ePhase := E_DL_IaiPhase.eRun; // 作用域二：迁回运行相 / scope two, back to run
END_IF

// 段 3｜组态与输入域闸（边界一）/ segment 3, the configuration and input gates
_bInOk := (fAirflow = fAirflow) AND ((fAirflow - fAirflow) = (fAirflow - fAirflow)); // 风速有限双判据 / the airflow finiteness
_bCfgOk := (fAirMin > 0.0) AND (fAirMin = fAirMin) AND ((fAirMin - fAirMin) = (fAirMin - fAirMin)) AND (tConfirm > T#0S); // 下限与确认窗域判定 / the floor and window verdict
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 输入缺陷或组态非法 / a defect or an illegal config
    IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        IF NOT _bInOk THEN // 传感失效优先归因（R190）/ the sensor failure first
            _eFaulC := E_DL_IaiFault.eSensorBad; // 传感成因 / the sensor cause
        ELSE // 组态非法 / the illegal config
            _eFaulC := E_DL_IaiFault.eCfgIllegal; // 组态成因 / the config cause
        END_IF
        _ePhase := E_DL_IaiPhase.eFault; // 迁故障相 / migrate to fault
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_IaiPhase.eIdle: // 未使能相 / the idle phase
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_IaiPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_IaiPhase.eRun: // 运行相：风速监视 / the run phase
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_IaiPhase.eIdle; // 迁未使能相（解锁，边界三）/ migrate to idle
    ELSIF tonConfirm.Q THEN // 欠限持续确认到期（边界二）/ the underrun confirmed
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_IaiFault.eAirLow; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_IaiPhase.eLatched; // 迁锁存相 / migrate to latched
    END_IF

E_DL_IaiPhase.eLatched: // 锁存相：放行断开，等复位沿或失能 / the latched phase, the permit open until the reset edge
    IF NOT bEnable THEN // 失能即解锁（边界三）/ disabling unlocks
        _bFault := FALSE; // 清故障锁存 / clear the fault latch
        _eFaulC := E_DL_IaiFault.eNone; // 清成因 / clear the cause
        _ePhase := E_DL_IaiPhase.eIdle; // 回空闲相 / back to idle
    END_IF

E_DL_IaiPhase.eFault: // 故障相：成因锁存，等复位沿或失能 / the fault phase, latched until reset or disable
    IF NOT bEnable THEN // 失能 / disabled
        _bFault := FALSE; // 清故障锁存 / clear the fault latch
        _eFaulC := E_DL_IaiFault.eNone; // 清成因 / clear the cause
        _ePhase := E_DL_IaiPhase.eIdle; // 回空闲相 / back to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_IaiFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause
    _ePhase := E_DL_IaiPhase.eFault; // 迁故障相 / migrate to fault
END_CASE

// 段 5｜统一出口：放行与有效性分离单点映射 / segment 5, the unified outlet
IF (_ePhase = E_DL_IaiPhase.eRun) AND (NOT _bFault) AND _bInOk AND _bCfgOk AND (fAirflow >= fAirMin) THEN // 风速在限内 / the airflow inside the band
    bPermitOk := TRUE; // 放行接通 / the permit closed
    bIonValid := TRUE; // 消电离有效 / the ionization valid
ELSE // 任何异常相放行安全侧断开（边界三）/ any abnormal phase opens the permit on the safe side
    bPermitOk := FALSE; // 放行断开 / the permit open
    bIonValid := (_ePhase = E_DL_IaiPhase.eRun) AND (NOT _bFault); // 有效性随运行相 / the validity follows the run phase
END_IF
bLatched := (_ePhase = E_DL_IaiPhase.eLatched); // 锁存电平派生 / the latch level derived
tConfirmEt := tonConfirm.ET; // 确认窗流逝出口 / the confirm elapsed outlet
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eFault := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
ELSE // 无锁存 / no latch
    eFault := E_DL_IaiFault.eNone; // 无成因 / no cause
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the flag shares the latch
END_FUNCTION_BLOCK
