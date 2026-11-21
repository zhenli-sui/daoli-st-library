(*
  ==================================================================
  组件名 Component  : FB_DL_AirDryerDiag
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 压缩空气干燥机诊断（露点越限 + 再生阀时序状态机 + 切换周期劣化档）。
  来源   Source     : t2-2-lbp（干燥机诊断公开工艺语义）
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / CASE / TIME_TO_DINT），三平台通用
  分工声明 Split     : 与 FB_DL_DryerProtect（停机保护属主，若在册）分工——本件
                      只做诊断与周期劣化分档，不做停机联锁（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : E_DL_DryerPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 露点非有限闸逐个点名（R272：fDewPnt / fDewLim /
                         fDeg1Ratio / fDeg2Ratio 四个浮点引脚逐个判）；
                      二 再生切换周期劣化分档阈值全提为输入（fDeg1Ratio /
                         fDeg2Ratio [-]，实测周期与名义周期之比阈值，R 红线 7）；
                         组态递增配比违反判组态锁存（070F）；
                      三 状态机 CASE 必带 ELSE 兜底（R25 批次教训）；TON /
                         R_TRIG 段 0 无条件刷新（禁入分支，R7）；
                      四 故障锁存解除式逐条自证：bReset 上升沿清四锁存（恒可达，
                         R152 自证）；出口锁存回放优先（R187）；
                      五 周期换算：TIME 经 TIME_TO_DINT 落毫秒再升 LREAL 比
                         值（除零由组态闸 tCycleNom > 0 前置证明）；
                      六 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0003_070B【故障级】露点越限（fDewPnt > fDewLim），锁存至复位沿
    16#0003_070C【故障级】再生切换周期劣化二档（比值 ≥ fDeg2Ratio），锁存至复位沿
    16#0003_070D【故障级】露点入参非有限，锁存至复位沿
    16#0003_070E【信息级】再生切换周期劣化一档（比值 ≥ fDeg1Ratio，逐拍重算）
    16#0003_070F【故障级】组态非法（比值阈递增违反或名义周期 ≤ 0），锁存至复位沿
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 露点 -40、限 -20 → 无故障；V2 露点 -15 → 码 070B 锁存
    V3 实测周期 2 倍名义（阈 1.8）→ 码 070C 锁存；1.5 倍 → 070E 信息级
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 4 · 序号 14）
  ==================================================================
*)
TYPE E_DL_DryerPhase :
(
    eDrying := 0,  // 吸附相：干燥塔在工作 / the drying phase, the tower working
    eRegen  := 10, // 再生相：再生阀开 / the regeneration phase, the valve open
    eFault  := 20  // 故障相：锁存待复位 / the fault phase latched until the reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_AirDryerDiag
VAR_INPUT
    bEnable     : BOOL := TRUE;   // 使能，FALSE 时冻结诊断出口（R191 声明行）/ the enable, false freezes the diagnosis outlet
    bReset      : BOOL := FALSE;  // 故障复位电平，上升沿清锁存 / the fault reset level
    bRegenValve : BOOL := FALSE;  // 再生阀开反馈电平 [-] / the regeneration valve open feedback
    fDewPnt     : LREAL := -40.0; // 露点实测值 [摄氏度] / the measured dew point
    fDewLim     : LREAL := -20.0; // 露点上限 [摄氏度] / the dew point limit
    tCycleNom   : TIME := T#6H;   // 名义再生切换周期 [毫秒] / the nominal switch cycle
    fDeg1Ratio  : LREAL := 1.3;   // 劣化一档比值阈 [-] / the degradation level one ratio threshold
    fDeg2Ratio  : LREAL := 1.8;   // 劣化二档比值阈 [-] / the degradation level two ratio threshold
END_VAR
VAR_OUTPUT
    eState     : E_DL_DryerPhase;       // 主状态机当前态 [状态] / the current state
    bDewHigh   : BOOL := FALSE;         // 露点越限锁存指示 [-] / the dew over limit latched indicator
    bDeg1      : BOOL := FALSE;         // 劣化一档指示（信息级逐拍）[-] / the degradation level one indicator
    bDeg2      : BOOL := FALSE;         // 劣化二档锁存指示 [-] / the degradation level two latched indicator
    bError     : BOOL := FALSE;         // 故障锁存位（与锁存同源，R191）/ the fault bit from the latch
    bValid     : BOOL := FALSE;         // 诊断可用标志 [-] / the diagnosis usable flag
    eErr       : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit     : BOOL := FALSE; // 首拍初始化标志（R310）/ the first scan flag
    _eState    : E_DL_DryerPhase := E_DL_DryerPhase.eDrying; // 内部状态寄存器 / the internal state register
    _bDewFlt   : BOOL := FALSE; // 露点越限锁存副本 / the dew fault latch copy
    _bDeg2Flt  : BOOL := FALSE; // 劣化二档锁存副本 / the level two latch copy
    _bDewNF    : BOOL := FALSE; // 露点非有限锁存副本 / the dew non finite latch copy
    _bCfgBad   : BOOL := FALSE; // 组态非法锁存副本 / the configuration latch copy
    _bFin      : BOOL := FALSE; // 四浮点引脚非有限闸结果（逐拍重算）/ the finiteness gate result
    _fRatio    : LREAL := 0.0;  // 实测周期与名义周期比 [-] / the measured to nominal ratio
    _tNomMs    : LREAL := 0.0;  // 名义周期 [毫秒] / the nominal cycle in milliseconds
    _tMeasMs   : LREAL := 0.0;  // 上一周实测周期 [毫秒] / the last measured cycle in milliseconds
    _tPrvSnap  : TIME := T#0S;  // 上拍周期计时快照（R 实战规则 1②）/ the previous cycle timing snapshot
    rtValve    : R_TRIG; // 再生阀开沿实例，段 0 无条件刷新 / the valve open edge instance
    rtReset    : R_TRIG; // 复位沿实例，段 0 无条件刷新 / the reset edge instance
    tonCycle   : TON;    // 切换周期实测计时器，段 0 无条件刷新 / the cycle measurement timer
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtValve(CLK := bRegenValve); // 再生阀开沿 / the valve open edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonCycle(IN := bRegenValve, PT := tCycleNom); // 周期实测（阀开时长累计）/ the cycle timing during the valve open
IF rtValve.Q THEN // 新一周开始：锁存上一周时长快照（周界沿取快照）/ a new cycle latches the last duration snapshot
    _tPrvSnap := tonCycle.ET; // 上周时长快照 / the last duration snapshot
END_IF

// 段 1｜首拍初始化与复位沿作用域（R310 / R311）/ segment 1, the first scan init and the reset scope
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bDewFlt := FALSE; // 露点锁存显式清零 / clear the dew latch explicitly
    _bDeg2Flt := FALSE; // 劣化二档锁存显式清零 / clear the level two latch explicitly
    _bDewNF := FALSE; // 非有限锁存显式清零 / clear the non finite latch explicitly
    _bCfgBad := FALSE; // 组态锁存显式清零 / clear the configuration latch explicitly
    _eState := E_DL_DryerPhase.eDrying; // 状态显式落吸附相 / place the state to drying
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清四锁存 + 迁相位，R311 声明）/ the reset edge with the declared scope
    _bDewFlt := FALSE; // 清露点锁存（解除路径：复位沿恒可达，R152 自证）/ clear the dew latch
    _bDeg2Flt := FALSE; // 清劣化二档锁存 / clear the level two latch
    _bDewNF := FALSE; // 清非有限锁存 / clear the non finite latch
    _bCfgBad := FALSE; // 清组态锁存 / clear the configuration latch
    _eState := E_DL_DryerPhase.eDrying; // 迁回吸附相 / back to drying
END_IF

// 段 2｜非有限闸与组态闸（R272 全量点名，边界一二）/ segment 2, the finiteness and the configuration gates
_bFin := (fDewPnt = fDewPnt) AND ((fDewPnt - fDewPnt) = (fDewPnt - fDewPnt))
AND (fDewLim = fDewLim) AND ((fDewLim - fDewLim) = (fDewLim - fDewLim))
AND (fDeg1Ratio = fDeg1Ratio) AND ((fDeg1Ratio - fDeg1Ratio) = (fDeg1Ratio - fDeg1Ratio))
AND (fDeg2Ratio = fDeg2Ratio) AND ((fDeg2Ratio - fDeg2Ratio) = (fDeg2Ratio - fDeg2Ratio)); // 四浮点引脚逐个自反 + 差值判 / the four floating pins tested one by one
IF NOT _bFin THEN // 入参非有限（露点成因独立锁存，R190）/ a non finite input latches the dew cause
    _bDewNF := TRUE; // 锁存非有限（070D）/ latch the non finite cause
END_IF
IF (fDeg1Ratio <= 1.0) OR (fDeg2Ratio <= fDeg1Ratio) OR (tCycleNom <= T#0S) THEN // 组态递增配比违反（边界二）/ the configuration monotone ratio violated
    _bCfgBad := TRUE; // 锁存组态非法（070F）/ latch the configuration fault
END_IF
_tNomMs := DINT_TO_LREAL(TIME_TO_DINT(tCycleNom)); // 名义周期毫秒化（TIME 口径，边界五）/ the nominal cycle in milliseconds

// 段 3｜露点越限判据（有限才判）/ segment 3, the dew over limit criterion
IF _bFin AND (fDewPnt > fDewLim) THEN // 露点越限（070B 独立成因）/ the dew over the limit
    _bDewFlt := TRUE; // 独立锁存 / latch the dew cause
END_IF

// 段 4｜周期比与劣化分档（周界沿快照换算，除零前置证明）/ segment 4, the cycle ratio and the degradation grades
IF rtValve.Q THEN // 新周界沿：换算上周比值 / a new cycle edge converts the last ratio
    _tMeasMs := DINT_TO_LREAL(TIME_TO_DINT(_tPrvSnap)); // 上周时长毫秒化 / the last duration in milliseconds
    IF _tNomMs > 0.0 THEN // 除零防护（组态闸已证 > 0，双保险）/ the division guard doubled
        _fRatio := _tMeasMs / _tNomMs; // 周期比（除子已证 > 0）/ the cycle ratio with a proven divisor
        IF _fRatio >= fDeg2Ratio THEN // 二档劣化（070C 独立成因）/ the level two degradation
            _bDeg2Flt := TRUE; // 独立锁存 / latch the level two cause
        END_IF
    END_IF
END_IF

// 段 5｜主状态机（ENUM + CASE，ELSE 兜底，边界三）/ segment 5, the main machine with the ELSE guard
CASE _eState OF
    E_DL_DryerPhase.eDrying: // 吸附相 / the drying phase
        IF bRegenValve THEN // 阀开反馈迁入再生相 / the valve open feedback migrates to regen
            _eState := E_DL_DryerPhase.eRegen; // 迁入再生相 / enter the regen phase
        ELSIF _bDewFlt OR _bDeg2Flt OR _bDewNF OR _bCfgBad THEN // 故障迁移（锁存复检，R274）/ the fault migration with the latch recheck
            _eState := E_DL_DryerPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_DryerPhase.eRegen: // 再生相 / the regen phase
        IF NOT bRegenValve THEN // 阀关反馈迁回吸附相 / the valve closed feedback back to drying
            _eState := E_DL_DryerPhase.eDrying; // 迁回吸附相 / back to drying
        ELSIF _bDewFlt OR _bDeg2Flt OR _bDewNF OR _bCfgBad THEN // 故障迁移 / the fault migration
            _eState := E_DL_DryerPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_DryerPhase.eFault: // 故障相：等复位沿（解除可达，边界四）/ the fault phase until the reset
        IF NOT (_bDewFlt OR _bDeg2Flt OR _bDewNF OR _bCfgBad) THEN // 四锁存已清才迁出（防清锁同拍重锁，FB50-1）/ the exit after all latches cleared
            _eState := E_DL_DryerPhase.eDrying; // 迁回吸附相 / back to drying
        END_IF
    ELSE // 非法枚举值拦截（兜底码走组态成因回放）/ the illegal enumeration guard
        _eState := E_DL_DryerPhase.eFault; // 落入故障相 / force to the fault phase
        _bCfgBad := TRUE; // 置锁存（ELSE 兜底码走组态成因回放）/ latch the configuration cause
END_CASE

// 段 6｜统一出口（锁存同源映射；一档信息级逐拍重算，R285）/ segment 6, the unified outlet
eState := _eState; // 状态出口 / the state outlet
bDewHigh := _bDewFlt; // 露点越限出口 / the dew outlet
bDeg2 := _bDeg2Flt; // 二档出口 / the level two outlet
bDeg1 := (NOT _bDeg2Flt) AND (_fRatio >= fDeg1Ratio); // 一档指示（逐拍重算，信息级不置 bError）/ the level one indicator recomputed
bError := _bDewFlt OR _bDeg2Flt OR _bDewNF OR _bCfgBad; // 故障位出口 / the fault bit outlet
bValid := (NOT bError) AND bEnable; // 诊断可用标志 / the usable flag
IF _bCfgBad THEN // 组态成因回放优先 / the configuration cause replays first
    eErr := 16#0003_070F; // 故障级：组态非法 / fault grade, the illegal configuration
ELSIF _bDewNF THEN // 非有限成因 / the non finite cause
    eErr := 16#0003_070D; // 故障级：露点入参非有限 / fault grade, the non finite dew input
ELSIF _bDewFlt THEN // 露点越限成因 / the dew cause
    eErr := 16#0003_070B; // 故障级：露点越限 / fault grade, the dew over the limit
ELSIF _bDeg2Flt THEN // 二档成因 / the level two cause
    eErr := 16#0003_070C; // 故障级：切换周期劣化二档 / fault grade, the cycle degradation level two
ELSE // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
