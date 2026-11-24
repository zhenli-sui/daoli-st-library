(*
  ==================================================================
  组件名 Component  : FB_DL_EsdGroundMonitor
  分类   Category   : DL_Device
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : ESD 接地连续性监视。对接地电阻做窗口判级（低于下限疑短路 /
                      接线反，高于上限疑断路），双阈值迟滞防边界抖动；传感失效
                      锁存优先于判级；健康语言出口按 NE107 五态口径输出。
  来源   Source     : self-esc（次源 t2-8 NE107，借鉴 NE107 健康状态五态语言，
                      clean-room 自研实现，未复制任何文档代码行）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；ESD 接地电阻窗口
                      判级为公开防静电工艺语义（常见口径 <10 欧姆量级）。
  平台   Platform   : 纯 IEC 61131-3（LREAL 运算，无私有库、无定时器实例）
  分工声明 Split     : 与 DL_Device 存量联锁族（风机关 / 传递窗）分工——本件只
                      做接地电阻判级与健康语言映射，不做风量联锁与顺控。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态闸（R151）：fOhmMin > 0 且 fOhmMax > fOhmMin，
                         迟滞带宽 0 <= fHystOhm < 半窗宽；
                      二 迟滞收窄口径：进入判据用全带宽，退出判据带宽收窄
                         fHystOhm，防边界抖动反复置清；
                      三 传感失效（非有限双判据 / 电阻 < 0）锁存优先于判级；
                      四 成因锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      eHealth 为 NE107 五态健康语言；bGroundOk 为放行派生电平；
                      eFault 为锁存回放；bError 与故障级成因配对（R45）。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 4 · 序号 16）
  ==================================================================
*)

TYPE E_DL_EgmPhase :
(
    eIdle  := 0,  // 未使能：判级停摆 / disabled, the grading idle
    eRun   := 10, // 运行：逐拍判级 / running, graded every scan
    eFault := 90  // 故障：成因锁存 / fault, the cause latched
);
END_TYPE

TYPE E_DL_EgmFault :
(
    eNone       := 0, // 无成因 / no cause
    eCfgIllegal := 1, // 组态非法：电阻窗或迟滞越域（故障级，与 bError 配对）/ an illegal config
    eSensorBad  := 2, // 传感失效：电阻非有限或负值（故障级，与 bError 配对）/ a sensor failure
    eGroundOpen := 3, // 接地断路：电阻超上限（故障级，与 bError 配对）/ a ground open
    eGroundShort:= 4, // 接地短路疑点：电阻低于下限（故障级，与 bError 配对）/ a ground short suspect
    ePhaseBad   := 5  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

TYPE E_DL_EgmHealth :
(
    eInit           := 0, // NE107 初始态 / the NE107 initial state
    eGood           := 1, // NE107 正常 / the NE107 good state
    eCheckFunction  := 2, // NE107 功能受影响（组态非法驻留）/ the NE107 check function state
    eMaintenanceReq := 3, // NE107 维护要求（判级异常驻留）/ the NE107 maintenance required state
    eFailure        := 4  // NE107 故障（传感失效锁存）/ the NE107 failure state
);
END_TYPE

FUNCTION_BLOCK FB_DL_EsdGroundMonitor
VAR_INPUT
    bEnable   : BOOL := TRUE;   // 使能，失能时判级停摆 [-] / enable, the grading stops when disabled
    bReset    : BOOL := FALSE;  // 复位上升沿清全部成因锁存 [-] / reset rising edge clears every cause latch
    fResOhm   : LREAL := 5.0;   // 接地电阻实测 [欧姆] / the measured ground resistance [ohm]
    fOhmMin   : LREAL := 0.5;   // 电阻窗下限 [欧姆]，域 大于零 / the window floor [ohm], above zero
    fOhmMax   : LREAL := 10.0;  // 电阻窗上限 [欧姆]，域 大于下限 / the window ceiling [ohm], above the floor
    fHystOhm  : LREAL := 0.5;   // 迟滞带宽 [欧姆]，域 0..半窗宽 / the hysteresis band [ohm]
END_VAR
VAR_OUTPUT
    eHealth  : E_DL_EgmHealth := E_DL_EgmHealth.eInit; // NE107 健康语言出口 [枚举] / the NE107 health outlet [enum]
    bGroundOk: BOOL := FALSE; // 接地合格放行派生电平 [-] / the ground ok derived level
    ePhase   : E_DL_EgmPhase := E_DL_EgmPhase.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    eFault   : E_DL_EgmFault := E_DL_EgmFault.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed from the latch
    bError   : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    _ePhase : E_DL_EgmPhase := E_DL_EgmPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC : E_DL_EgmFault := E_DL_EgmFault.eNone; // 故障级成因，锁存至复位沿 / the fault cause, latched until the reset edge
    _bFault : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _bInOk  : BOOL := FALSE; // 电阻有限且非负 [-] / the resistance finite and nonnegative
    _bCfgOk : BOOL := FALSE; // 组态域内 [-] / the configuration inside the domain
    _bOpen  : BOOL := FALSE; // 断路迟滞锁存 [-] / the open hysteresis latch
    _bShort : BOOL := FALSE; // 短路疑点迟滞锁存 [-] / the short suspect hysteresis latch
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, the first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit  := TRUE; // 置首扫标志 / raise the flag
    _ePhase := E_DL_EgmPhase.eRun; // 相位从运行起步（使能默认真）/ the phase starts in run
END_IF

// 段 2｜复位沿作用域：清锁存 / 清迟滞 / 迁相位（三项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_EgmFault.eNone; // 作用域一：清成因 / scope one, clear the cause
    _bOpen := FALSE; // 作用域二：清断路迟滞 / scope two, clear the open latch
    _bShort := FALSE; // 作用域二：清短路迟滞 / scope two, clear the short latch
    _ePhase := E_DL_EgmPhase.eRun; // 作用域三：迁回运行相 / scope three, back to run
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖，边界一）/ segment 3, the configuration and input gates
_bInOk := (fResOhm = fResOhm) AND ((fResOhm - fResOhm) = (fResOhm - fResOhm)) AND (fResOhm >= 0.0); // 电阻有限且非负 / the resistance finite and nonnegative
_bCfgOk := (fOhmMin > 0.0) AND (fOhmMin = fOhmMin) AND (fOhmMax > fOhmMin) AND (fOhmMax = fOhmMax) AND (fHystOhm >= 0.0) AND (fHystOhm < (fOhmMax - fOhmMin) / 2.0); // 窗与迟滞域判定（除子为窗宽已证大于零）/ the window and hysteresis verdict
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 输入缺陷或组态非法 / an input defect or an illegal config
    IF NOT _bFault THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        IF NOT _bInOk THEN // 传感失效优先归因（R190 归因唯一）/ the sensor failure attributed first
            _eFaulC := E_DL_EgmFault.eSensorBad; // 传感失效成因 / the sensor cause
        ELSE // 组态非法 / the illegal config
            _eFaulC := E_DL_EgmFault.eCfgIllegal; // 组态成因 / the config cause
        END_IF
        _ePhase := E_DL_EgmPhase.eFault; // 迁故障相 / migrate to fault
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_EgmPhase.eIdle: // 未使能相：健康语言回初始 / the idle phase, the health back to init
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_EgmPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_EgmPhase.eRun: // 运行相：逐拍判级 / the run phase, graded every scan
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_EgmPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSE // 正常判级 / the normal grading
        IF fResOhm > fOhmMax THEN // 断路进入判据（全带宽）/ the open entry criterion, the full band
            _bOpen := TRUE; // 置断路迟滞 / raise the open latch
        ELSIF fResOhm < fOhmMax - fHystOhm THEN // 断路退出判据（迟滞收窄，边界二）/ the open exit criterion, the narrowed band
            _bOpen := FALSE; // 清断路迟滞 / clear the open latch
        END_IF
        IF fResOhm < fOhmMin THEN // 短路疑点进入判据（全带宽）/ the short entry criterion
            _bShort := TRUE; // 置短路迟滞 / raise the short latch
        ELSIF fResOhm > fOhmMin + fHystOhm THEN // 短路退出判据（迟滞收窄）/ the short exit criterion
            _bShort := FALSE; // 清短路迟滞 / clear the short latch
        END_IF
        IF _bShort THEN // 短路疑点优先（接线异常更急）/ the short suspect first
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_EgmFault.eGroundShort; // 故障级成因（R45 配对 bError）/ the fault cause
            _ePhase := E_DL_EgmPhase.eFault; // 迁故障相 / migrate to fault
        ELSIF _bOpen THEN // 断路次优先 / the open next
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_EgmFault.eGroundOpen; // 故障级成因（R45 配对 bError）/ the fault cause
            _ePhase := E_DL_EgmPhase.eFault; // 迁故障相 / migrate to fault
        END_IF
    END_IF

E_DL_EgmPhase.eFault: // 故障相：成因锁存，等待复位沿；健康语言按成因映射 / the fault phase, the cause latched until the reset edge

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_EgmFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause
    _ePhase := E_DL_EgmPhase.eFault; // 迁故障相 / migrate to fault
END_CASE

// 段 5｜统一出口：健康语言与放行派生单点映射 / segment 5, the unified outlet
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eFault := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
    CASE _eFaulC OF // 成因到 NE107 健康语言映射 / the cause to health mapping
    E_DL_EgmFault.eSensorBad: eHealth := E_DL_EgmHealth.eFailure; // 传感失效映射故障态 / the sensor failure to failure
    E_DL_EgmFault.eCfgIllegal: eHealth := E_DL_EgmHealth.eCheckFunction; // 组态非法映射功能受影响 / the config to check function
    ELSE eHealth := E_DL_EgmHealth.eMaintenanceReq; // 判级异常映射维护要求 / the grading anomalies to maintenance
    END_CASE
ELSE // 无锁存 / no latch
    eFault := E_DL_EgmFault.eNone; // 无成因 / no cause
    IF bEnable THEN // 使能中 / enabled
        eHealth := E_DL_EgmHealth.eGood; // 健康态 / the good state
    ELSE // 失能驻留 / disabled
        eHealth := E_DL_EgmHealth.eInit; // 初始态 / the init state
    END_IF
END_IF
bGroundOk := (_ePhase = E_DL_EgmPhase.eRun) AND (NOT _bFault) AND (NOT _bShort) AND (NOT _bOpen); // 放行派生电平 / the ok derived level
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
bError := _bFault; // 故障标志与锁存位同源 / the flag shares the latch
END_FUNCTION_BLOCK
