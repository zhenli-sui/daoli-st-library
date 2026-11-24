(*
  ==================================================================
  组件名 Component  : FB_DL_ChemDosingGrav
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 化学液定量补给称重（密度补偿外置）。按目标体积与外部注入的
                      密度算出目标质量（目标质量 = 体积 × 密度），以净重反馈判
                      定量是否达标：净重进入目标带判完成，超出上带判超量，注料相
                      超时仍在带外判欠量。密度由外部补偿模块给出，本件只做域闸与
                      质量换算，不自行推算密度。
  溯源   Origin     : 体积乘密度的质量换算与称重定量为公开工程口径；本件为
                      clean-room 实现，仅借鉴来源分类与参数域组织（来源标签
                      roadmap-p2-chemdose），道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / REAL 运算，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做质量换算与定量判据，不驱动泵阀、不算密度（属主边界）；
                      二 密度为外置补偿输入，越域即判故障并禁止定量（防密度错致过量）；
                      三 目标质量在启动沿一次性锁存，注料期内不随引脚漂移；
                      四 净重非有限时不更新判据，出口保持上拍值；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fTargetMassG 在启动沿锁存，周期内不变；
                      bDoseDone 为单拍脉冲（内部位置置位、统一出口映射后撤销）；
                      bDensityOk 为密度域闸实时值，与故障锁存同源否决定量；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 4 · 序号 17）
  ==================================================================
*)

TYPE E_DL_CdgState :
(
    eIdle   := 0,       // 空闲：等启动沿 / idle, waiting for the start edge
    eDose   := 10,      // 注料：净重上升中 / dosing, the net weight is rising
    eDone   := 20,      // 完成：定量判据已锁存 / done, the dosing verdict is latched
    eFault  := 90       // 故障：密度域或组态非法锁存 / fault, density or configuration out of domain
);
END_TYPE

TYPE E_DL_CdgCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：体积、容差或时间越域（故障级，与 bError 配对）/ illegal config, volume, tolerance or time out of domain
    eDensityBad := 2,   // 密度越域或非有限，禁止定量（故障级，与 bError 配对）/ density out of domain or non-finite, dosing inhibited, a fault paired with bError
    eOverMass   := 3,   // 超量：净重越过上带（信息级，由上层决定回抽）/ over mass beyond the upper band, informational and left to the upper layer
    eUnderMass  := 4,   // 欠量：注料超时仍在带外（信息级）/ under mass after the dosing timeout, informational
    eNetBad     := 5    // 净重非有限，判据保持上拍（信息级）/ the net weight is non-finite and the verdicts hold, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChemDosingGrav
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时撤命令回空闲 [-] / enable, disabling withdraws the commands and returns to idle
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存与判据 [-] / reset rising edge clears the fault latch and the verdicts
    bStart       : BOOL := FALSE;            // 周期启动脉冲，上升沿受理 [-] / cycle start pulse, accepted on the rising edge
    fVolTargetMl : REAL := 100.0;            // 目标补给体积 [毫升]，域 大于零 / target dosing volume [millilitre], domain above zero
    fDensityKgL  : REAL := 1.2;              // 外部注入的化学液密度 [千克每升] / externally supplied chemical density [kilogram per litre]
    fDensityMinKgL : REAL := 0.5;            // 密度可接受下限 [千克每升]，域 大于零 / acceptable density floor [kilogram per litre], domain above zero
    fDensityMaxKgL : REAL := 2.5;            // 密度可接受上限 [千克每升]，须大于下限 / acceptable density ceiling [kilogram per litre], above the floor
    fNetG        : REAL := 0.0;              // 净重实测（已去皮）[克] / measured net weight, tare removed [gram]
    fTolPct      : REAL := 1.0;              // 质量容差 [百分比]，域 大于零 / mass tolerance [percent], domain above zero
    tDoseTo      : TIME := T#90S;            // 注料相超时 [毫秒]，域 大于零 / dosing phase timeout [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    fTargetMassG : REAL := 0.0;              // 锁存的目标质量 [克] / latched target mass [gram]
    fDoseErrG    : REAL := 0.0;              // 净重与目标质量偏差 [克] / deviation between the net weight and the target mass [gram]
    fDosePct     : REAL := 0.0;              // 注料完成百分比 [百分比] / dosing completion ratio [percent]
    bInTol       : BOOL := FALSE;            // 净重落在质量带内 [-] / the net weight is inside the mass band
    bDensityOk   : BOOL := FALSE;            // 密度域闸通过 [-] / the density domain gate passed
    bDoseDone    : BOOL := FALSE;            // 定量完成单拍脉冲 [-] / dosing done single-shot pulse
    bOverMass    : BOOL := FALSE;            // 超量判据 [-] / over mass verdict
    bUnderMass   : BOOL := FALSE;            // 欠量判据 [-] / under mass verdict
    eState       : E_DL_CdgState := E_DL_CdgState.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eCause       : E_DL_CdgCause := E_DL_CdgCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStart      : R_TRIG;                   // 启动沿检测，段 0 无条件刷新 / start edge detector, refreshed unconditionally in segment zero
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonDose      : TON;                      // 注料超时，段 0 无条件刷新 / dosing timeout, refreshed unconditionally in segment zero
    _eState      : E_DL_CdgState := E_DL_CdgState.eIdle;  // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause      : E_DL_CdgCause := E_DL_CdgCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause : E_DL_CdgCause := E_DL_CdgCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bDenOk      : BOOL := FALSE;            // 密度域闸工作值 [-] / density gate working value
    _bNetOk      : BOOL := FALSE;            // 净重有限 [-] / the net weight is finite
    _bInTol      : BOOL := FALSE;            // 带内判据内部位 / internal in-target verdict
    _bOverInt    : BOOL := FALSE;            // 超量判据内部位 / internal over mass verdict
    _bUnderInt   : BOOL := FALSE;            // 欠量判据内部位 / internal under mass verdict
    _bDoneInt    : BOOL := FALSE;            // 完成脉冲内部位，统一出口映射 / internal done bit, mapped at the unified outlet
    _fTarget     : REAL := 0.0;              // 目标质量锁存值 [克] / latched target mass [gram]
    _fErr        : REAL := 0.0;              // 偏差工作值 [克] / deviation working value [gram]
    _fPct        : REAL := 0.0;              // 完成百分比工作值 [百分比] / completion ratio working value [percent]
    _fTolG       : REAL := 0.0;              // 容差绝对值 [克] / absolute tolerance [gram]
END_VAR
VAR CONSTANT
    DL_CDG_VOL_MAX   : REAL := 1.0E5;        // 体积量级上限，防量纲错配 [毫升] / volume magnitude ceiling against a mismatch [millilitre]
    DL_CDG_TOL_MAX   : REAL := 100.0;        // 容差上限 [百分比] / tolerance ceiling [percent]
    DL_CDG_MASS_MAX  : REAL := 1.0E8;        // 质量量级上限 [克] / mass magnitude ceiling [gram]
    DL_CDG_PCT_MAX   : REAL := 1000.0;       // 完成百分比上限，防目标过小放大 [百分比] / completion ratio ceiling against a tiny target
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串状态闸与故障闸 / segment 0, unconditional refresh with state and fault gates on IN only
rtStart(CLK := bStart); // 启动沿无条件刷新 / unconditional refresh of the start edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonDose(IN := (_eState = E_DL_CdgState.eDose) AND (NOT _bFault), PT := tDoseTo); // 注料超时，仅在注料相计时 / dosing timeout timing only in the dosing phase

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eState := E_DL_CdgState.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eCause := E_DL_CdgCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_CdgCause.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _fTarget := 0.0; // 目标质量清零 / clear the target mass
    _fErr := 0.0; // 偏差清零 / clear the deviation
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清判据 / 清目标锁存 / segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_CdgCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _eState := E_DL_CdgState.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _bDoneInt := FALSE; // 作用域二：清完成脉冲内部位 / scope two, clear the internal done bit
    _bInTol := FALSE; // 作用域三：清带内判据 / scope three, clear the in-target verdict
    _bOverInt := FALSE; // 作用域三：清超量判据 / scope three, clear the over mass verdict
    _bUnderInt := FALSE; // 作用域三：清欠量判据 / scope three, clear the under mass verdict
    _fTarget := 0.0; // 作用域四：清目标质量锁存 / scope four, clear the latched target
END_IF

// 段 3｜组态域闸（R151 全覆盖）：体积、容差、密度上下限、时间 / segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (fVolTargetMl <= 0.0) OR (fVolTargetMl <> fVolTargetMl) OR (fVolTargetMl > DL_CDG_VOL_MAX) THEN // 体积越域 / the volume is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fTolPct <= 0.0) OR (fTolPct > DL_CDG_TOL_MAX) OR (fTolPct <> fTolPct) THEN // 容差越域 / the tolerance is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fDensityMinKgL <= 0.0) OR (fDensityMaxKgL <= fDensityMinKgL) OR (fDensityMaxKgL <> fDensityMaxKgL) THEN // 密度上下限自相矛盾 / the density bounds contradict each other
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF tDoseTo <= T#0S THEN // 注料超时非正 / the dosing timeout is not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_CdgCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _eState := E_DL_CdgState.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 4｜密度域闸：外置补偿量越域即禁止定量（防密度错致过量）/ segment 4, density domain gate that inhibits dosing when violated
_bDenOk := (fDensityKgL = fDensityKgL) AND ((fDensityKgL - fDensityKgL) = (fDensityKgL - fDensityKgL)) AND (fDensityKgL >= fDensityMinKgL) AND (fDensityKgL <= fDensityMaxKgL); // 密度有限性与区间闸 / density finiteness and band gate
IF (NOT _bDenOk) AND (NOT _bFault) THEN // 密度越域且未锁存 / density out of domain and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_CdgCause.eDensityBad; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _eState := E_DL_CdgState.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 5｜净重闸 / segment 5, net weight gate
_eCause := E_DL_CdgCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
_bNetOk := (fNetG = fNetG) AND ((fNetG - fNetG) = (fNetG - fNetG)) AND (ABS(fNetG) <= DL_CDG_MASS_MAX); // 净重有限性与量级闸 / net weight finiteness and magnitude gate
IF (NOT _bNetOk) AND bEnable THEN // 净重非有限且使能 / the net weight is non-finite while enabled
    _eCause := E_DL_CdgCause.eNetBad; // 信息级成因 / informational cause
END_IF

// 段 6｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 6, phase machine with an ELSE fallback for illegal phases
CASE _eState OF
E_DL_CdgState.eIdle: // 空闲相：等启动沿，启动沿一次性锁存目标质量 / idle, the start edge latches the target mass once
    _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
    _bOverInt := FALSE; // 撤超量判据 / withdraw the over mass verdict
    _bUnderInt := FALSE; // 撤欠量判据 / withdraw the under mass verdict
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND _bDenOk THEN // 启动沿且使能无故障且密度可用 / start edge while enabled, unfaulted and with a usable density
        _fTarget := fVolTargetMl * fDensityKgL; // 目标质量 = 体积 × 密度，单位恰为克 / target mass equals volume times density in grams
        IF (_fTarget <> _fTarget) OR ((_fTarget - _fTarget) <> (_fTarget - _fTarget)) OR (_fTarget > DL_CDG_MASS_MAX) THEN // 目标质量非有限或超量级 / the target is non-finite or out of magnitude
            _fTarget := 0.0; // 归零，防非有限穿透判据 / zeroed so nothing non-finite reaches the verdicts
        END_IF
        _fTolG := _fTarget * fTolPct / 100.0; // 容差绝对值，除子为常量 100.0 / absolute tolerance with the constant divisor one hundred
        _eState := E_DL_CdgState.eDose; // 迁注料相 / migrate to the dosing phase
    END_IF

E_DL_CdgState.eDose: // 注料相：带内即完成，越上带判超量，超时带外判欠量 / dosing phase with three exits
    _fErr := fNetG - _fTarget; // 偏差 / deviation
    _fPct := 0.0; // 完成百分比预置零 / preset the completion ratio to zero
    IF _fTarget > 0.0 THEN // 目标可用 / the target is usable
        _fPct := fNetG / _fTarget * 100.0; // 完成百分比，除子已证大于零 / completion ratio, divisor proven positive
        IF _fPct > DL_CDG_PCT_MAX THEN // 越上限 / above the ceiling
            _fPct := DL_CDG_PCT_MAX; // 上钳 / clamp upward
        END_IF
    END_IF
    IF _bNetOk THEN // 净重可用才判据 / the verdicts need a usable net weight
        IF ABS(_fErr) <= _fTolG THEN // 落带内 / inside the band
            _bInTol := TRUE; // 置带内判据 / raise the in-target verdict
            _bDoneInt := TRUE; // 完成脉冲内部位置位（统一出口映射，R187）/ raise the internal done bit, mapped at the unified outlet
            _eState := E_DL_CdgState.eDone; // 迁完成相 / migrate to the done phase
        ELSIF _fErr > _fTolG THEN // 越过上带 / beyond the upper band
            _bOverInt := TRUE; // 置超量判据 / raise the over mass verdict
            _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
            _eCause := E_DL_CdgCause.eOverMass; // 信息级成因（回抽由上层决定）/ informational cause, the reclaim action belongs to the upper layer
            _eState := E_DL_CdgState.eDone; // 迁完成相（本件判据已定型）/ migrate to the done phase because the verdict is settled
        ELSIF tonDose.Q THEN // 超时仍在带外 / timed out below the band
            _bUnderInt := TRUE; // 置欠量判据 / raise the under mass verdict
            _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
            _eCause := E_DL_CdgCause.eUnderMass; // 信息级成因 / informational cause
            _eState := E_DL_CdgState.eDone; // 迁完成相 / migrate to the done phase
        END_IF
    ELSIF tonDose.Q THEN // 净重不可用且超时 / the net weight is unusable and the phase timed out
        _bUnderInt := TRUE; // 置欠量判据（保守侧）/ raise the under mass verdict on the conservative side
        _eState := E_DL_CdgState.eDone; // 迁完成相 / migrate to the done phase
    END_IF

E_DL_CdgState.eDone: // 完成相：判据驻留，等复位或新启动 / done phase, the verdict holds until reset or a new start
    IF rtStart.Q AND bEnable AND _bDenOk AND (NOT _bFault) THEN // 新启动沿 / a new start edge
        _fTarget := fVolTargetMl * fDensityKgL; // 目标质量重新锁存 / relatch the target mass
        _fTolG := _fTarget * fTolPct / 100.0; // 容差重算 / recompute the tolerance
        _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
        _bOverInt := FALSE; // 撤超量判据 / withdraw the over mass verdict
        _bUnderInt := FALSE; // 撤欠量判据 / withdraw the under mass verdict
        _eState := E_DL_CdgState.eDose; // 直接进注料相 / go straight to the dosing phase
    END_IF

E_DL_CdgState.eFault: // 故障相：判据锁存回放，等复位沿 / fault phase, the verdicts are replayed until the reset edge
    _bInTol := FALSE; // 撤带内判据 / withdraw the in-target verdict
    _bDoneInt := FALSE; // 故障拍不出完成脉冲 / no done pulse while faulted

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_CdgCause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
    _eState := E_DL_CdgState.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 7｜失能语义：回空闲并撤完成脉冲（R191 显式声明）/ segment 7, disabled semantics
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_CdgState.eIdle; // 回空闲相 / return to idle
    _bDoneInt := FALSE; // 撤完成脉冲内部位 / withdraw the internal done bit
END_IF

// 段 8｜统一出口 / segment 8, unified outlet
fTargetMassG := _fTarget; // 目标质量出口（锁存量）/ target mass outlet from the latch
fDoseErrG := _fErr; // 偏差出口 / deviation outlet
fDosePct := _fPct; // 完成百分比出口 / completion ratio outlet
bInTol := _bInTol AND (NOT _bFault); // 带内出口受故障锁存否决 / the in-target outlet is vetoed by the fault latch
bOverMass := _bOverInt; // 超量出口 / over mass outlet
bUnderMass := _bUnderInt; // 欠量出口 / under mass outlet
bDensityOk := _bDenOk AND (NOT _bFault); // 密度闸出口（挂状态量）/ density gate outlet as a state quantity
bDoseDone := _bDoneInt; // 完成脉冲映射本拍值 / map the done pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
eState := _eState; // 相位出口单点映射 / single-point phase outlet mapping
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
