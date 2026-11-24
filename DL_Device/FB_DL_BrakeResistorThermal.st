(*
  Name        : FB_DL_BrakeResistorThermal
  Category    : DL_Device
  Version     : 1.0.1
  Purpose     : 变频器制动电阻热累积估算：按 I²·R 瞬时功率逐拍积分成能量，叠加一阶冷却（时间常数 tau）折算温升与能量百分比，给出过载/预警与降额建议；/ Estimate braking-resistor thermal accumulation by integrating I2R power with first-order cooling, yielding temperature rise, energy percentage, overload warnings and a derating hint
  溯源        : 借 t2-6-rockwell-aoi 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：额定电流/电阻/时间常数/周期/温升额度任一非正 → 锁存故障；
                ② 除零前置：热容/时间常数、能量上限、温升额度的除子均在组态闸保证非按零后使用；
                ③ 非有限电流/温度输入该拍不积分（保留上拍累积值，防污染积分器）；
                ④ 能量百分比饱和 0..100 且过载判据用 >= 阈值直比（阈值来自组态，非浮点等值比较）；
                ⑤ 本件为估算模型，不替代硬件热保护（安全回路须由变频器/热继电器实现）。
  修订记录    : 2026-11-20 v1.0.1：温升改热阻功率比口径（fRiseRated × P/P_rated，R52-09）；组态闸追加能量额度一致性校验（fEnergyMax > I²R·τ 派生上界即故障）并把默认 fEnergyMax 收口为 6000 kJ 派生值；_fPct 饱和处回夹 _fAccJ/_fAccKj 能量上界（R52-10）；eIdle 补 fEnergyPct/fDeratePct 出口镜像并按 dT/dt = -T/tauCool 冷却衰减。
*)
TYPE E_DL_BrtState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eEst   := 10,                            (* 热累积估算 / Thermal estimation *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_BrtCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：电气参数/时间常数越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BrakeResistorThermal
VAR_INPUT
    fBrakeCurrent : REAL := 0.0;             (* 制动电流实测（RMS），域 >= 0 [A] / Measured braking current RMS *)
    fRatedCurrent : REAL := 20.0;            (* 电阻额定电流，域 > 0 [A] / Rated current, > 0 *)
    fResistance   : REAL := 50.0;            (* 电阻阻值（冷态），域 > 0 [Ohm] / Resistance, > 0 *)
    tCycle        : TIME := T#10MS;          (* 估算周期，域 > T#0S [ms] / Estimation period, > 0 *)
    fTauCool      : REAL := 300.0;           (* 冷却时间常数 tau，域 > 0 [s] / Cooling time constant, > 0 *)
    fEnergyMax    : REAL := 6000.0;          (* 允许累计能量上限（= 可吸收能量，默认为 I²R·τ 派生量 20²·50·300/1000，须 <= 派生上界）[kJ] / Allowed energy budget, <= I2R*tau derived cap *)
    fTempAmb      : REAL := 40.0;            (* 环境温度 [°C] / Ambient temperature *)
    fRiseRated    : REAL := 250.0;           (* 满载（额定）稳态温升，域 > 0 [K] / Steady rise at rated load, > 0 *)
    bEnable       : BOOL := TRUE;            (* 估算使能 [-] / Enable *)
    bReset        : BOOL := FALSE;           (* 复位命令，上升沿清累积能量与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fEnergyKj    : REAL;                     (* 当前累积能量（净额，含冷却扣除）[kJ] / Accumulated net energy *)
    fEnergyPct   : REAL;                     (* 能量占额度百分比 0..100（饱和）[%] / Energy percentage, saturated *)
    fTempRise    : REAL;                     (* 估算温升（相对环境）[K] / Estimated temperature rise *)
    fTempEst     : REAL;                     (* 估算电阻温度 = 环境 + 温升 [°C] / Estimated resistor temperature *)
    fDeratePct   : REAL;                     (* 降额建议（100 = 不降额，50 = 半载），0..100 [%] / Derating hint, 0..100 *)
    bWarn        : BOOL;                     (* 预警：能量百分比 >= 80% [-] / Warning at 80 percent *)
    bOverload    : BOOL;                     (* 过载：能量百分比 >= 100% [-] / Overload at 100 percent *)
    eState       : E_DL_BrtState;            (* 状态出口 / State outlet *)
    eCause       : E_DL_BrtCause;            (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError       : BOOL;                     (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_BrtState := E_DL_BrtState.eIdle;    (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_BrtCause := E_DL_BrtCause.eNone;    (* 故障成因锁存量 / Latched cause *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite  : BOOL;                        (* 输入有限性当拍量 / Input finiteness *)
    _fDtSec   : REAL;                        (* 周期折算秒值，域 > eps [s] / Period in seconds *)
    _fPowerW  : REAL;                        (* 本拍制动功率 P = I²·R [W] / Braking power this scan *)
    _fEinJ    : REAL;                        (* 本拍注入能量 [J] / Injected energy this scan *)
    _fEoutJ   : REAL;                        (* 本拍冷却带走能量（一阶）[J] / Energy removed by cooling *)
    _fAccJ    : REAL;                        (* 累积能量内部量（焦耳口径）[J] / Accumulated energy in joules *)
    _fAccKj   : REAL;                        (* 累积能量换算 kJ 中间量 [kJ] / Accumulated energy in kJ *)
    _fPct     : REAL;                        (* 未饱和百分比 [%] / Unclamped percentage *)
    _fRiseEst : REAL;                        (* 温升估算中间量 [K] / Rise estimate intermediate *)
    _fDerate  : REAL;                        (* 降额中间量 [%] / Derate intermediate *)
    _fBudgetKj: REAL;                        (* 能量额度物理上界 I²R·τ 派生量（kJ 口径）[kJ] / Physics energy cap I2R*tau *)
    _fEfullJ  : REAL;                        (* 能量额度满值焦耳换算中间量（回夹用）[J] / Budget in joules for clamping *)
END_VAR
VAR CONSTANT
    DL_BRT_EPS   : REAL := 1.0E-6;           (* 判零容差（REAL 量级）[-] / Epsilon *)
    DL_BRT_J2KJ  : REAL := 1000.0;           (* 焦耳→千焦换算因子（常量除子）[-] / Joules to kJ factor *)
    DL_BRT_PCTMAX: REAL := 100.0;            (* 百分比满量程 [%] / Percentage full scale *)
    DL_BRT_WARN  : REAL := 80.0;             (* 预警门槛 [%] / Warning threshold *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tCycle) / 1000.0;                                     (* 周期秒化（除子常量 1000） / Period to seconds *)
_fBudgetKj := fRatedCurrent * fRatedCurrent * fResistance * fTauCool / DL_BRT_J2KJ;   (* 能量额度物理上界 = I²R·τ（稳态能量平衡，除子为常量）[kJ] / Physics cap I2R*tau *)
_fEfullJ := fEnergyMax * DL_BRT_J2KJ;                                          (* 能量额度满值焦耳换算（回夹上界）[J] / Budget in joules *)
_bCfgBad := NOT (tCycle > T#0S)                                                (* 周期正域闸 / Period gate *)
            OR (fRatedCurrent <= DL_BRT_EPS) OR (fResistance <= DL_BRT_EPS)    (* 电气参数正域闸 / Electrical gates *)
            OR (fTauCool <= DL_BRT_EPS) OR (fEnergyMax <= DL_BRT_EPS)          (* 冷却常数/能量额度正域闸（除零前置） / Cooling and budget gates *)
            OR (fRiseRated <= DL_BRT_EPS)                                      (* 温升额度正域闸 / Rise gate *)
            OR ((fTauCool > DL_BRT_EPS) AND (fEnergyMax > _fBudgetKj));        (* 能量额度一致性校验：应 ≈ I²R·τ 派生量（除子先过正域闸，v1.0.1）/ Budget consistency gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fBrakeCurrent = fBrakeCurrent) AND (fTempAmb = fTempAmb)          (* NaN 自反闸 / NaN reflex gates *)
            AND ((fBrakeCurrent - fBrakeCurrent) = (fBrakeCurrent - fBrakeCurrent));   (* Inf 差判闸 / Inf gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
bWarn := FALSE;                                                                (* 预警位预清 / Warn preset *)
bOverload := FALSE;                                                            (* 过载位预清 / Overload preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清累积能量 + 清出口 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_BrtCause.eNone;                                            (* 清成因 / Clear cause *)
    _fAccJ := 0.0;                                                             (* 清累积能量（焦耳） / Clear accumulated joules *)
    fEnergyKj := 0.0;                                                          (* 清能量出口 / Clear energy outlet *)
    fEnergyPct := 0.0;                                                         (* 清百分比出口 / Clear percentage *)
    fTempRise := 0.0;                                                          (* 清温升出口 / Clear rise outlet *)
    fTempEst := fTempAmb;                                                      (* 温度回环境值 / Temperature back to ambient *)
    fDeratePct := DL_BRT_PCTMAX;                                               (* 降额建议回 100%（不降额） / Derate back to 100 *)
    _eState := E_DL_BrtState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_BrtCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_BrtState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_BrtState.eIdle:                                                       (* 未使能：停机冷却 + 出口镜像 / Disabled: cooling and mirrors *)
        _fAccJ := _fAccJ - (_fAccJ / fTauCool) * _fDtSec;                      (* 停机即按 dT/dt = -T/tauCool 一阶冷却衰减（除子 tau 已过组态闸，v1.0.1） / First-order cooling while idle *)
        IF _fAccJ < 0.0 THEN
            _fAccJ := 0.0;                                                     (* 冷却下限 0：不允许负累积 / Energy floor zero *)
        END_IF
        _fAccKj := _fAccJ / DL_BRT_J2KJ;                                       (* 焦耳→千焦（除子为常量）[kJ] / Joules to kJ *)
        fEnergyKj := _fAccKj;                                                  (* 能量出口镜像 / Energy outlet mirror *)
        _fPct := _fAccKj / fEnergyMax * DL_BRT_PCTMAX;                         (* 占额度百分比：除子额度已过闸 [%] / Percentage of budget *)
        IF _fPct > DL_BRT_PCTMAX THEN
            _fPct := DL_BRT_PCTMAX;                                            (* 上限饱和 100 [%] / Upper saturation *)
        ELSIF _fPct < 0.0 THEN
            _fPct := 0.0;                                                      (* 下限饱和 0 [%] / Lower saturation *)
        END_IF
        fEnergyPct := _fPct;                                                   (* 百分比出口镜像（v1.0.1 补） / Percentage outlet mirror *)
        _fDerate := DL_BRT_PCTMAX - _fPct;                                     (* 降额镜像：能量越满降额越深 [%] / Derate mirror *)
        IF _fDerate < 0.0 THEN
            _fDerate := 0.0;                                                   (* 降额下限 0 / Derate floor *)
        END_IF
        fDeratePct := _fDerate;                                                (* 降额出口镜像（v1.0.1 补） / Derate outlet mirror *)
        fTempRise := 0.0;                                                      (* 无估算语义：温升 0 / No estimation: rise 0 *)
        fTempEst := fTempAmb;                                                  (* 温度 = 环境 / Temperature = ambient *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_BrtState.eEst;                                     (* 使能进入估算 / Enter estimation *)
        END_IF
    E_DL_BrtState.eEst:                                                        (* 估算相：I²R 积分 + 一阶冷却 / Estimation *)
        IF NOT bEnable THEN
            _eState := E_DL_BrtState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF _bFinite AND (_fDtSec > DL_BRT_EPS) THEN
            _fPowerW := fBrakeCurrent * fBrakeCurrent * fResistance;            (* 瞬时制动功率 I²·R [W]（乘性，无除零） / Instantaneous I2R power *)
            _fEinJ := _fPowerW * _fDtSec;                                      (* 本拍注入能量 [J] / Injected energy *)
            _fEoutJ := (_fAccJ / fTauCool) * _fDtSec;                          (* 一阶冷却带走能量（除子 tau 已过闸）[J] / First-order cooling *)
            _fAccJ := _fAccJ + _fEinJ - _fEoutJ;                               (* 净额积分（单点写入，无双向双计） / Net integration, single write *)
            IF _fAccJ < 0.0 THEN
                _fAccJ := 0.0;                                                 (* 能量下限 0：不允许负累积 / Energy floor zero *)
            END_IF
            _fAccKj := _fAccJ / DL_BRT_J2KJ;                                   (* 焦耳→千焦 [kJ] / Joules to kJ *)
            fEnergyKj := _fAccKj;                                              (* 能量出口 / Energy outlet *)
            _fPct := _fAccKj / fEnergyMax * DL_BRT_PCTMAX;                     (* 占额度百分比：除子额度已过闸 [%] / Percentage of budget *)
            IF _fPct > DL_BRT_PCTMAX THEN
                _fPct := DL_BRT_PCTMAX;                                        (* 上限饱和 100 [%] / Upper saturation *)
                _fAccJ := _fEfullJ;                                            (* 能量上界回夹 = 额度满值（饱和处同步，v1.0.1，R52-10） / Clamp energy to budget *)
                _fAccKj := fEnergyMax;                                         (* kJ 镜像同步回夹 / Mirror clamp in kJ *)
                fEnergyKj := _fAccKj;                                          (* 能量出口同步回夹 / Energy outlet sync *)
            ELSIF _fPct < 0.0 THEN
                _fPct := 0.0;                                                  (* 下限饱和 0 [%] / Lower saturation *)
            END_IF
            fEnergyPct := _fPct;                                               (* 百分比出口 / Percentage outlet *)
            _fRiseEst := fRiseRated * (_fPowerW / (fRatedCurrent * fRatedCurrent * fResistance));   (* 温升 = 满载稳态温升 × 瞬时功率/额定功率比（热阻口径，除子由组态闸保证 > 0，v1.0.1） / Rise = rated rise times power ratio *)
            IF _fRiseEst < 0.0 THEN
                _fRiseEst := 0.0;                                              (* 温升下限 0 [K] / Rise floor *)
            END_IF
            fTempRise := _fRiseEst;                                            (* 温升出口 [K] / Rise outlet *)
            fTempEst := fTempAmb + _fRiseEst;                                  (* 电阻温度 = 环境 + 温升 [°C] / Estimated temperature *)
            _fDerate := DL_BRT_PCTMAX - _fPct;                                 (* 降额建议：能量越满降额越深 [%] / Derate hint *)
            IF _fDerate < 0.0 THEN
                _fDerate := 0.0;                                               (* 降额下限 0（已过载即全禁） / Derate floor *)
            END_IF
            fDeratePct := _fDerate;                                            (* 降额出口 / Derate outlet *)
            IF _fPct >= DL_BRT_PCTMAX THEN
                bOverload := TRUE;                                             (* 过载：能量额度耗尽 / Overload: budget exhausted *)
            ELSIF _fPct >= DL_BRT_WARN THEN
                bWarn := TRUE;                                                 (* 预警：能量额度达 80% / Warning at 80 percent *)
            END_IF
        END_IF                                                                 (* 非有限输入：不积分，保持上拍累积（边界③） / Non-finite: hold *)
    E_DL_BrtState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_BrtState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_BrtCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
