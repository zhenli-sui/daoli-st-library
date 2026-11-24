(*
  ==================================================================
  组件名 Component  : FB_DL_HydraulicAccumPreChg
  分类   Category   : DL_Device
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.1
  功能   Purpose    : 液压蓄能器氮气预充压力监视。把实测气囊压力按理想气体等温
                      折算到参考温度 20 摄氏度（pCorr = pGas · T0K / TK），再对额定
                      预充压力求偏差百分比；欠充 / 过充双态判据带迟滞防抖；油口
                      压力显著高于气囊侧判气囊失效疑点（eBladderSuspect）；传感器
                      非有限或压力 / 温度物理域越界判 eSensorBad。
  来源   Source     : t2-2-lbp
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；理想气体等温折算与
                      蓄能器预充校验为公开热力学与液压语义，clean-room 自研实现，
                      未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL 运算，无私有库、无定时器实例）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做预充状态判级，不做充放气控制、不做泄放（属主边界）；
                      二 判据方向性（R146）：欠充与过充为同量纲双向异常，分派独立
                         成因成员（R190 归因唯一），互不合并；
                      三 迟滞口径：进入判据用全带宽，退出判据带宽收窄 fHystBar，
                         防边界抖动反复置清；
                      四 成因锁存解除路径 = bReset 上升沿（唯一路径，头注释声明，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fDevPct 为温度修正后偏差百分比（正 = 高于额定，负 = 低于额定）；
                      eFault 为锁存回放；bError 与故障级成因配对（R45）；
                      ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 2 · 序号 10）
    2026-11-21  v1.0.1  R57 返修：段 3 域闸补温度上界 150.0 摄氏度判 eSensorBad（阈值提为常量并注单位）
  ==================================================================
*)

TYPE E_DL_HapPhase :
(
    eIdle  := 0,  // 未使能：判级停摆 / disabled, the grading is idle
    eRun   := 10, // 运行：逐拍判级 / running, graded every scan
    eFault := 90  // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_HapFault :
(
    eNone          := 0, // 无成因 / no cause
    eUnderCharge   := 1, // 预充不足（故障级，与 bError 配对）/ the precharge is under, fault grade paired with bError
    eOverCharge    := 2, // 预充过量（故障级，与 bError 配对）/ the precharge is over, fault grade paired with bError
    eBladderSuspect:= 3, // 油口压力显著高于气囊侧，气囊失效疑点（故障级，与 bError 配对）/ the oil side clearly exceeds the gas side, a bladder suspect, fault grade paired with bError
    eSensorBad     := 4, // 传感器非有限或物理域越界（故障级，与 bError 配对）/ a sensor is non finite or out of the physical domain, fault grade paired with bError
    ePhaseBad      := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_HydraulicAccumPreChg
VAR_INPUT
    bEnable   : BOOL := TRUE;   // 使能，失能时判级停摆 [-] / enable, the grading stops when disabled
    bReset    : BOOL := FALSE;  // 复位上升沿清全部成因锁存 [-] / reset rising edge clears every cause latch
    pGas      : LREAL := 90.0;  // 气囊压力实测 [巴] / measured gas side pressure [bar]
    pOil      : LREAL := 0.0;   // 油口压力实测 [巴] / measured oil port pressure [bar]
    fTempC    : LREAL := 20.0;  // 气体温度实测 [摄氏度] / measured gas temperature [degree celsius]
    pNom      : LREAL := 90.0;  // 额定预充压力 [巴]，域 大于零 / rated precharge pressure [bar], domain above zero
    fUnderBar : LREAL := 9.0;   // 欠充判据带宽（低于额定的绝对量）[巴] / undercharge band below the rating [bar]
    fOverBar  : LREAL := 9.0;   // 过充判据带宽（高于额定的绝对量）[巴] / overcharge band above the rating [bar]
    fHystBar  : LREAL := 1.0;   // 迟滞带宽 [巴]，域 0..判据带宽 / hysteresis band [bar], inside the criterion band
    fBladMarg : LREAL := 20.0;  // 气囊疑点裕度（油口超出气囊侧百分比）[百分比] / bladder suspect margin over the gas side [percent]
END_VAR
VAR_OUTPUT
    fDevPct : LREAL := 0.0;  // 温度修正后预充偏差百分比 [百分比] / the corrected precharge deviation [percent]
    ePhase  : E_DL_HapPhase := E_DL_HapPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault  : E_DL_HapFault := E_DL_HapFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError  : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    _ePhase  : E_DL_HapPhase := E_DL_HapPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_HapFault := E_DL_HapFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bInOk   : BOOL := FALSE; // 三个实数输入全部有限 [-] / all three real inputs are finite
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _fTK     : LREAL := 0.0;  // 气体绝对温度 [开尔文] / the absolute gas temperature [kelvin]
    _fPCorr  : LREAL := 0.0;  // 折算到参考温度的气囊压力 [巴] / the gas pressure corrected to the reference temperature [bar]
    _fDev    : LREAL := 0.0;  // 偏差绝对量 [巴] / the deviation magnitude [bar]
    _bUnder  : BOOL := FALSE; // 欠充迟滞锁存 [-] / the undercharge hysteresis latch
    _bOver   : BOOL := FALSE; // 过充迟滞锁存 [-] / the overcharge hysteresis latch
    _bBlad   : BOOL := FALSE; // 气囊疑点迟滞锁存 [-] / the bladder suspect hysteresis latch
    _bBad    : BOOL := FALSE; // 传感器无效锁存 [-] / the sensor bad latch
END_VAR
VAR CONSTANT
    DL_HAP_TEMP_HI : LREAL := 150.0; // 温度上界 [摄氏度]，超界判传感器无效（v1.0.1 返修）/ the temperature ceiling [degree celsius], beyond it the sensor is judged bad (v1.0.1 fix)
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detector
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_HapPhase.eRun; // 相位从运行起步（使能默认真）/ the phase starts in run
    _eFaulC := E_DL_HapFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
END_IF

// 段 2｜复位沿作用域：清全部迟滞与锁存 / 迁相位（两项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_HapFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _bUnder := FALSE; // 作用域一：清欠充迟滞 / scope one, clear the undercharge latch
    _bOver := FALSE; // 作用域一：清过充迟滞 / scope one, clear the overcharge latch
    _bBlad := FALSE; // 作用域一：清气囊疑点迟滞 / scope one, clear the bladder latch
    _bBad := FALSE; // 作用域一：清传感器无效锁存 / scope one, clear the sensor bad latch
    _ePhase := E_DL_HapPhase.eRun; // 作用域二：迁回运行相 / scope two, migrate back to run
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖）/ segment 3, the configuration and input domain gates
_bInOk := (pGas = pGas) AND ((pGas - pGas) = (pGas - pGas)) AND (pOil = pOil) AND ((pOil - pOil) = (pOil - pOil)) AND (fTempC = fTempC) AND ((fTempC - fTempC) = (fTempC - fTempC)); // 三输入有限性 / finiteness of the three inputs
_bCfgOk := (pNom > 0.0) AND (pNom = pNom) AND (fUnderBar >= 0.0) AND (fUnderBar = fUnderBar) AND (fOverBar >= 0.0) AND (fOverBar = fOverBar) AND (fHystBar >= 0.0) AND (fHystBar <= fUnderBar) AND (fHystBar <= fOverBar) AND (fBladMarg > 0.0) AND (fBladMarg = fBladMarg); // 组态参数域判定 / the configuration domain verdict
IF (NOT _bInOk) OR (pGas < 0.0) OR (pOil < 0.0) OR (fTempC < -270.0) OR (fTempC > DL_HAP_TEMP_HI) OR (NOT _bCfgOk) THEN // 输入非有限、物理域越界（含 v1.0.1 温度上界）或组态非法 / a non finite input, a physical domain violation (with the v1.0.1 temperature ceiling) or an illegal configuration
    IF NOT _bBad THEN // 未锁存才置（防同拍抹除）/ set only while unlatched
        _bBad := TRUE; // 置传感器无效锁存 / raise the sensor bad latch
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_HapPhase.eIdle: // 未使能相 / the disabled phase
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_HapPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_HapPhase.eRun: // 运行相：逐拍判级 / the run phase, graded every scan
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_HapPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF _bBad THEN // 传感器无效锁存优先 / the sensor bad latch takes priority
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_HapFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_HapPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSE // 正常判级 / the normal grading
        _fTK := fTempC + 273.15; // 摄氏度转开尔文 / celsius to kelvin
        IF _fTK < 1.0 THEN // 绝对温度趋零防御（等温折算除子域闸）/ the absolute temperature guard for the divisor
            _fTK := 1.0; // 钳到下限 / clamp to the floor
        END_IF
        _fPCorr := pGas * (293.15 / _fTK); // 等温折算到 20 摄氏度参考（除子为绝对温度已证超阈）/ the isothermal correction to the twenty degree reference
        IF pNom > 0.0 THEN // 额定压力已证大于零（组态闸）/ the rating is proven positive by the gate
            fDevPct := (_fPCorr - pNom) / pNom * 100.0; // 偏差百分比 / the deviation percentage
        ELSE // 组态非法兜底（防御性保留）/ the illegal configuration fallback
            fDevPct := 0.0; // 偏差记零 / the deviation is zeroed
        END_IF
        _fDev := _fPCorr - pNom; // 偏差绝对量（带符号）/ the signed deviation
        IF _fDev < -fUnderBar THEN // 欠充进入判据 / the undercharge entry criterion
            _bUnder := TRUE; // 置欠充迟滞锁存 / raise the undercharge latch
        ELSIF _fDev > -fUnderBar + fHystBar THEN // 欠充退出判据（迟滞收窄）/ the undercharge exit criterion with the narrowed band
            _bUnder := FALSE; // 清欠充迟滞 / clear the undercharge latch
        END_IF
        IF _fDev > fOverBar THEN // 过充进入判据 / the overcharge entry criterion
            _bOver := TRUE; // 置过充迟滞锁存 / raise the overcharge latch
        ELSIF _fDev < fOverBar - fHystBar THEN // 过充退出判据（迟滞收窄）/ the overcharge exit criterion with the narrowed band
            _bOver := FALSE; // 清过充迟滞 / clear the overcharge latch
        END_IF
        IF pOil > _fPCorr * (1.0 + fBladMarg / 100.0) THEN // 油口显著高于气囊侧 / the oil side clearly exceeds the gas side
            _bBlad := TRUE; // 置气囊疑点迟滞锁存 / raise the bladder latch
        ELSIF pOil < _fPCorr * (1.0 + fBladMarg / 200.0) THEN // 气囊疑点退出判据（半带迟滞）/ the bladder exit criterion with a half band
            _bBlad := FALSE; // 清气囊疑点迟滞 / clear the bladder latch
        END_IF
        IF _bBlad THEN // 气囊疑点优先级最高（结构性失效）/ the bladder suspect has the highest priority, a structural failure
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_HapFault.eBladderSuspect; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_HapPhase.eFault; // 迁故障相 / migrate to the fault phase
        ELSIF _bOver THEN // 过充次优先 / the overcharge takes the next priority
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_HapFault.eOverCharge; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_HapPhase.eFault; // 迁故障相 / migrate to the fault phase
        ELSIF _bUnder THEN // 欠充再次优先 / the undercharge follows
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_HapFault.eUnderCharge; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_HapPhase.eFault; // 迁故障相 / migrate to the fault phase
        END_IF
    END_IF

E_DL_HapPhase.eFault: // 故障相：成因锁存，等待复位沿；偏差出口冻结保持末值（R191 显式声明）/ the fault phase, the cause is latched, the deviation outlet holds frozen

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_HapFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_HapPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口 / segment 5, the unified outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（不按当下输入重推断，R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_HapFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
