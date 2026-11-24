(*
  ==================================================================
  组件名 Component  : FB_DL_EvaDosingTare
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : EVA 膜裁剪称重定量（自动去皮）。周期开始自动去皮（等称重稳定后
                      把当前毛重锁为皮重），随后进入注料 / 供料相，净重 = 毛重 − 皮重；
                      净重进入目标带且稳定保持即判定定量完成。超上限判超量、稳定后
                      仍低于下限判欠量，二者各自独立成因（R190 归因唯一）。
  溯源   Origin     : 自动去皮与带内定量为通用称重定量语义；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-eva），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / REAL 运算，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  同拍双窗配比约束（R100）：tStableTime 必须同时小于 tTareTo 与 tDoseTo —— 稳定确认窗
                      短于两个相超时窗，两窗职责分离：稳定窗判「可以锁皮重 / 可以判完成」，
                      超时窗判「相失败」，任一窗不得兼作另一窗用途。
  边界 Boundary     :
                      一 本件只出定量完成 / 超量 / 欠量判据与去皮值，不驱动螺杆或阀（属主边界）；
                      二 去皮值一经锁存即锁至本周期结束（周期内不重算，防净重跳变）；
                      三 稳定判据用「毛重变化小于稳定带并持续 tStableTime」双条件；
                      四 毛重非有限时本拍不更新净重、不判完成，出口保持上拍值；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fNetG 仅在有效称重拍更新，非有限拍保持上拍值；
                      bInTol 在净重进入目标带且稳定时为真（挂状态量）；
                      bDoseDone 为单拍脉冲（内部位置置位、统一出口映射后撤销）；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 4 · 序号 16）
  ==================================================================
*)

TYPE E_DL_Edt2State :
(
    eIdle     := 0,     // 空闲：等启动沿 / idle, waiting for the start edge
    eTareWait := 10,    // 去皮等稳定：等称重稳定后锁皮重 / waiting for stability before latching the tare
    eDose     := 20,    // 注料：净重上升中 / dosing, the net weight is rising
    eSettle   := 30,    // 稳定判定：净重带内且稳定 / settling, the net weight is inside the band and stable
    eDone     := 40,    // 完成：定量判据已锁存 / done, the dosing verdict is latched
    eFault    := 90     // 故障：组态非法锁存 / fault, illegal configuration latched
);
END_TYPE

TYPE E_DL_Edt2Cause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：目标量、容差、稳定带或时间越域（故障级，与 bError 配对）/ illegal config, target, tolerance, band or time out of domain
    eOverWeight := 2,   // 超量：净重超上容差（故障级，与 bError 配对）/ over weight beyond the upper tolerance, a fault paired with bError
    eUnderWeight:= 3,   // 欠量：稳定后净重低于下容差（故障级，与 bError 配对）/ under weight below the lower tolerance after settling, a fault paired with bError
    eNoStable   := 4,   // 等待稳定超时（信息级，仅去皮相记为警示）/ waiting for stability timed out, informational and only in the tare phase
    eTareLost   := 5    // 皮重非有限已复位（信息级）/ the tare was non-finite and has been reset, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_EvaDosingTare
VAR_INPUT
    bEnable     : BOOL := TRUE;              // 使能，失能时撤命令回空闲 [-] / enable, disabling withdraws the commands and returns to idle
    bReset      : BOOL := FALSE;            // 复位上升沿清故障锁存与判据 [-] / reset rising edge clears the fault latch and the verdicts
    bStart      : BOOL := FALSE;            // 周期启动脉冲，上升沿受理 [-] / cycle start pulse, accepted on the rising edge
    fGrossG     : REAL := 0.0;               // 毛重实测 [克] / measured gross weight [gram]
    fTargetG    : REAL := 50.0;              // 目标净重 [克]，域 大于零 / target net weight [gram], domain above zero
    fTolG       : REAL := 0.5;               // 净重容差（正负对称）[克]，域 大于零 / net weight tolerance, symmetric [gram], domain above zero
    fStableBandG: REAL := 0.05;              // 稳定带（连续两拍毛重变化上限）[克]，域 大于零 / stability band on the gross change between adjacent scans [gram], domain above zero
    tStableTime : TIME := T#2S;              // 稳定确认时长 [毫秒]，域 大于零 / stability confirmation duration [millisecond], domain above zero
    tTareTo     : TIME := T#30S;             // 去皮等稳定超时 [毫秒]，域 大于零 / tare stability timeout [millisecond], domain above zero
    tDoseTo     : TIME := T#120S;            // 注料相超时 [毫秒]，域 大于零 / dosing phase timeout [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    fTareG      : REAL := 0.0;               // 锁存皮重 [克] / latched tare weight [gram]
    fNetG       : REAL := 0.0;               // 净重 [克] / net weight [gram]
    fErrG       : REAL := 0.0;               // 净重与目标偏差 [克] / net weight deviation from the target [gram]
    bInTol      : BOOL := FALSE;             // 净重落在目标带内 [-] / the net weight is inside the target band
    bOver       : BOOL := FALSE;             // 超量判据 [-] / over weight verdict
    bUnder      : BOOL := FALSE;             // 欠量判据 [-] / under weight verdict
    bStable     : BOOL := FALSE;             // 称重稳定 [-] / the weight is stable
    bDoseDone   : BOOL := FALSE;             // 定量完成单拍脉冲 [-] / dosing done single-shot pulse
    bCycleDone  : BOOL := FALSE;             // 周期结束指示（完成或超欠量判据成立）[-] / cycle finished indicator
    eState      : E_DL_Edt2State := E_DL_Edt2State.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eCause      : E_DL_Edt2Cause := E_DL_Edt2Cause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError      : BOOL := FALSE;             // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStart     : R_TRIG;                    // 启动沿检测，段 0 无条件刷新 / start edge detector, refreshed unconditionally in segment zero
    rtReset     : R_TRIG;                    // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonStable   : TON;                       // 稳定确认计时，段 0 无条件刷新 / stability timer, refreshed unconditionally in segment zero
    tonTare     : TON;                       // 去皮超时，段 0 无条件刷新 / tare timeout, refreshed unconditionally in segment zero
    tonDose     : TON;                       // 注料超时，段 0 无条件刷新 / dosing timeout, refreshed unconditionally in segment zero
    _eState     : E_DL_Edt2State := E_DL_Edt2State.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause     : E_DL_Edt2Cause := E_DL_Edt2Cause.eNone; // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause: E_DL_Edt2Cause := E_DL_Edt2Cause.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault     : BOOL := FALSE;             // 故障锁存位 [-] / fault latch bit
    _bInit      : BOOL := FALSE;             // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad    : BOOL := FALSE;             // 组态非法判定 [-] / illegal configuration verdict
    _bGrossOk   : BOOL := FALSE;             // 毛重有限 [-] / the gross weight is finite
    _bStable    : BOOL := FALSE;             // 稳定判据工作值 [-] / stability verdict working value
    _bDoneInt   : BOOL := FALSE;             // 完成脉冲内部位，统一出口映射 / internal done bit, mapped at the unified outlet
    _bOver      : BOOL := FALSE;             // 超量判据内部位 / internal over weight verdict
    _bUnder     : BOOL := FALSE;             // 欠量判据内部位 / internal under weight verdict
    _bInTol     : BOOL := FALSE;             // 带内判据内部位 / internal in-target verdict
    _fTare      : REAL := 0.0;               // 皮重工作值 [克] / tare working value [gram]
    _fGrossPrev : REAL := 0.0;               // 上一拍毛重快照 [克] / previous scan gross weight [gram]
    _fNet       : REAL := 0.0;               // 净重工作值 [克] / net weight working value [gram]
    _fErr       : REAL := 0.0;               // 偏差工作值 [克] / deviation working value [gram]
    _fNetHold   : REAL := 0.0;               // 净重保持块 [克] / net weight holder [gram]
END_VAR
VAR CONSTANT
    DL_EDB_GROSS_MAX : REAL := 1.0E6;        // 毛重量级上限，防量纲错配 [克] / gross weight magnitude ceiling against a mismatch [gram]
    DL_EDB_BAND_MAX  : REAL := 100.0;        // 稳定带上限 [克] / stability band ceiling [gram]
    DL_EDB_TOL_MAX   : REAL := 1.0E5;        // 容差上限 [克] / tolerance ceiling [gram]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串状态闸与业务闸 / segment 0, unconditional refresh with state and process gates on IN only
rtStart(CLK := bStart); // 启动沿无条件刷新 / unconditional refresh of the start edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonStable(IN := (_eState = E_DL_Edt2State.eTareWait) OR (_eState = E_DL_Edt2State.eSettle), PT := tStableTime); // 稳定确认，仅在去皮与稳定判定两相计时 / stability timing only in the tare and settle phases
tonTare(IN := (_eState = E_DL_Edt2State.eTareWait) AND (NOT _bFault), PT := tTareTo); // 去皮超时 / tare timeout
tonDose(IN := ((_eState = E_DL_Edt2State.eDose) OR (_eState = E_DL_Edt2State.eSettle)) AND (NOT _bFault), PT := tDoseTo); // 注料超时 / dosing timeout

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eState := E_DL_Edt2State.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eCause := E_DL_Edt2Cause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_Edt2Cause.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fTare := 0.0; // 皮重清零 / clear the tare
    _fNetHold := 0.0; // 净重保持块清零 / clear the net holder
    _fGrossPrev := 0.0; // 毛重快照清零 / clear the gross snapshot
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清判据（皮重保留到下一周期去皮，避免误用零皮重）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_Edt2Cause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _eState := E_DL_Edt2State.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _bDoneInt := FALSE; // 作用域二：清完成脉冲内部位 / scope two, clear the internal done bit
    _bOver := FALSE; // 作用域三：清超量判据 / scope three, clear the over verdict
    _bUnder := FALSE; // 作用域三：清欠量判据 / scope three, clear the under verdict
    _bInTol := FALSE; // 作用域三：清带内判据 / scope three, clear the in-target verdict
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (fTargetG <= 0.0) OR (fTargetG <> fTargetG) OR (fTargetG > DL_EDB_GROSS_MAX) THEN // 目标量越域 / the target is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fTolG <= 0.0) OR (fTolG > DL_EDB_TOL_MAX) OR (fTolG <> fTolG) OR (fTolG >= fTargetG) THEN // 容差越域或大于目标量 / the tolerance is out of domain or above the target
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fStableBandG <= 0.0) OR (fStableBandG > DL_EDB_BAND_MAX) OR (fStableBandG <> fStableBandG) THEN // 稳定带越域 / the stability band is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (tStableTime <= T#0S) OR (tTareTo <= T#0S) OR (tDoseTo <= T#0S) THEN // 时间引脚非正 / a time pin is not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (tStableTime >= tTareTo) OR (tStableTime >= tDoseTo) THEN // 稳定窗不短于相超时窗，违反双窗配比（R100）/ the settle window is not shorter than a phase timeout
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_Edt2Cause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _eState := E_DL_Edt2State.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 4｜毛重闸与稳定判据 / segment 4, gross gate and stability verdict
_eCause := E_DL_Edt2Cause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
_bGrossOk := (fGrossG = fGrossG) AND ((fGrossG - fGrossG) = (fGrossG - fGrossG)) AND (ABS(fGrossG) <= DL_EDB_GROSS_MAX); // 毛重有限性与量级闸 / gross finiteness and magnitude gate
_bStable := _bGrossOk AND (ABS(fGrossG - _fGrossPrev) <= fStableBandG); // 稳定判据：相邻两拍变化在稳定带内 / stability verdict on the adjacent scan change
IF _bGrossOk THEN // 毛重可用 / the gross weight is usable
    _fGrossPrev := fGrossG; // 快照推进 / advance the snapshot
END_IF

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, phase machine with an ELSE fallback for illegal phases
CASE _eState OF
E_DL_Edt2State.eIdle: // 空闲相：等启动沿 / idle, waiting for the start edge
    _bInTol := FALSE; // 带内判据撤除 / the in-target verdict is withdrawn
    _bOver := FALSE; // 超量判据撤除 / the over verdict is withdrawn
    _bUnder := FALSE; // 欠量判据撤除 / the under verdict is withdrawn
    IF rtStart.Q AND bEnable AND (NOT _bFault) THEN // 启动沿且使能无故障 / start edge while enabled and unfaulted
        _fTare := 0.0; // 本周起皮重清零点 / the tare starts from zero for this cycle
        _eState := E_DL_Edt2State.eTareWait; // 迁去皮等稳定相 / migrate to the tare wait phase
    END_IF

E_DL_Edt2State.eTareWait: // 去皮等稳定相：稳定保持到时即锁皮重 / tare wait, the tare latches once stability holds long enough
    IF (NOT _bFault) AND _bStable AND tonStable.Q THEN // 稳定到时且无故障 / stable long enough and unfaulted
        _fTare := fGrossG; // 锁存皮重（本周期内不再重算）/ latch the tare for this cycle
        IF (_fTare <> _fTare) OR ((_fTare - _fTare) <> (_fTare - _fTare)) THEN // 皮重非有限 / the tare is non-finite
            _fTare := 0.0; // 归零，防非有限穿透净重 / zeroed so nothing non-finite reaches the net weight
            _eCause := E_DL_Edt2Cause.eTareLost; // 信息级成因 / informational cause
        END_IF
        _eState := E_DL_Edt2State.eDose; // 迁注料相 / migrate to the dosing phase
    ELSIF tonTare.Q THEN // 去皮超时 / the tare timed out
        _eCause := E_DL_Edt2Cause.eNoStable; // 信息级成因，不锁故障（操作可继续等稳定）/ informational cause without a fault
    END_IF

E_DL_Edt2State.eDose: // 注料相：净重上升，进入目标带即转稳定判定 / dosing phase, entering the band moves to the settle phase
    IF _bGrossOk THEN // 毛重可用才更新净重 / the net weight updates only with a usable gross
        _fNet := fGrossG - _fTare; // 净重 / net weight
        _fErr := _fNet - fTargetG; // 偏差 / deviation
        _fNetHold := _fNet; // 保持块更新 / refresh the holder
    END_IF
    IF _fNetHold > (fTargetG + fTolG) THEN // 越过上容差 / beyond the upper tolerance
        _bOver := TRUE; // 置超量判据 / raise the over verdict
        _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
        _eState := E_DL_Edt2State.eFault; // 迁故障相 / migrate to the fault phase
        IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaultCause := E_DL_Edt2Cause.eOverWeight; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
        END_IF
    ELSIF ABS(_fNetHold - fTargetG) <= fTolG THEN // 进入目标带 / inside the target band
        _bInTol := TRUE; // 置带内判据 / raise the in-target verdict
        _eState := E_DL_Edt2State.eSettle; // 迁稳定判定相 / migrate to the settle phase
    ELSIF tonDose.Q THEN // 注料超时（未进带也未超量）/ dosing timed out below the band
        _bUnder := TRUE; // 置欠量判据 / raise the under verdict
        _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
        _eState := E_DL_Edt2State.eFault; // 迁故障相 / migrate to the fault phase
        IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaultCause := E_DL_Edt2Cause.eUnderWeight; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
        END_IF
    END_IF

E_DL_Edt2State.eSettle: // 稳定判定相：带内且稳定到时即完成 / settle phase, in band plus stability completes the cycle
    IF _bGrossOk THEN // 毛重可用才更新净重 / the net weight updates only with a usable gross
        _fNet := fGrossG - _fTare; // 净重 / net weight
        _fErr := _fNet - fTargetG; // 偏差 / deviation
        _fNetHold := _fNet; // 保持块更新 / refresh the holder
    END_IF
    IF _fNetHold > (fTargetG + fTolG) THEN // 稳定过程中又超上容差 / the weight passes the upper tolerance while settling
        _bOver := TRUE; // 置超量判据 / raise the over verdict
        _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
        _eState := E_DL_Edt2State.eFault; // 迁故障相 / migrate to the fault phase
        IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaultCause := E_DL_Edt2Cause.eOverWeight; // 故障级成因 / fault grade cause
        END_IF
    ELSIF (ABS(_fNetHold - fTargetG) <= fTolG) AND _bStable AND tonStable.Q THEN // 带内且稳定到时 / in band and stable long enough
        _bInTol := TRUE; // 置带内判据 / raise the in-target verdict
        _bDoneInt := TRUE; // 完成脉冲内部位置位（统一出口映射，R187）/ raise the internal done bit, mapped at the unified outlet
        _eState := E_DL_Edt2State.eDone; // 迁完成相 / migrate to the done phase
    ELSIF (ABS(_fNetHold - fTargetG) > fTolG) AND tonDose.Q THEN // 稳定判定相超时仍未进带 / the settle phase timed out outside the band
        _bUnder := TRUE; // 置欠量判据 / raise the under verdict
        _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
        _eState := E_DL_Edt2State.eFault; // 迁故障相 / migrate to the fault phase
        IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaultCause := E_DL_Edt2Cause.eUnderWeight; // 故障级成因 / fault grade cause
        END_IF
    END_IF

E_DL_Edt2State.eDone: // 完成相：判据驻留，等复位或新启动 / done phase, the verdict holds until reset or a new start
    IF rtStart.Q AND bEnable THEN // 新启动沿 / a new start edge
        _fTare := 0.0; // 皮重清零点 / the tare restarts from zero
        _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
        _bOver := FALSE; // 撤超量判据 / withdraw the over verdict
        _bUnder := FALSE; // 撤欠量判据 / withdraw the under verdict
        _eState := E_DL_Edt2State.eTareWait; // 重新去皮 / restart from the tare phase
    END_IF

E_DL_Edt2State.eFault: // 故障相：判据锁存回放，等复位沿 / fault phase, the verdicts are replayed until the reset edge
    _bInTol := FALSE; // 带内判据撤除 / the in-target verdict is withdrawn

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_Edt2Cause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
    _eState := E_DL_Edt2State.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜失能语义：撤命令回空闲（R191 显式声明）/ segment 6, disabled semantics
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_Edt2State.eIdle; // 回空闲相 / return to idle
    _bDoneInt := FALSE; // 撤完成脉冲内部位 / withdraw the internal done bit
END_IF

// 段 7｜统一出口 / segment 7, unified outlet
fTareG := _fTare; // 皮重出口 / tare outlet
fNetG := _fNetHold; // 净重出口取保持块 / net weight outlet from the holder
fErrG := _fErr; // 偏差出口 / deviation outlet
bInTol := _bInTol AND (NOT _bFault); // 带内出口受故障锁存否决 / the in-target outlet is vetoed by the fault latch
bOver := _bOver; // 超量出口 / over verdict outlet
bUnder := _bUnder; // 欠量出口 / under verdict outlet
bStable := _bStable; // 稳定出口 / stability outlet
bDoseDone := _bDoneInt; // 完成脉冲映射本拍值 / map the done pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
bCycleDone := (_eState = E_DL_Edt2State.eDone) OR _bOver OR _bUnder; // 周期结束指示（完成或超欠量判据）/ cycle finished on completion or on an over or under verdict
eState := _eState; // 相位出口单点映射 / single-point phase outlet mapping
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
