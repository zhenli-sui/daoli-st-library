(*
  ==================================================================
  组件名 Component  : FB_DL_StringIrrNormalize
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 组串电流辐照归一化。把实测组串电流归一到参考辐照（默认
                      1000 瓦每平方米）与参考电池温度（默认 25 摄氏度）下的等效
                      电流：分母 = (G / Gref) × [1 + k × (T − Tref)]，
                      分子 = 实测电流；归一化电流 = 分子 / 分母。
                      用于不同辐照 / 温度工况下的组串横向比对与遮挡判别。
  溯源   Origin     : 辐照与温度归一为公开光伏工程口径；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-string），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（REAL 运算，无私有库、无方言转换）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做归一化与有效性判定，不判组件故障、不做 MPPT（属主边界）；
                      二 辐照低于有效下限（默认 50 瓦每平方米）时不归一，出口保持上拍值；
                      三 分母（辐照相对量 × 温度因子）低于 1E-6 时不归一，出口保持上拍值；
                      四 温度补偿可按 bTempComp 关闭，关闭时温度因子恒为 1；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fINormA 仅在 bValid 为真的拍更新，其余拍保持上一次有效值
                      （首拍保持引脚初值 0），非有限值永不写入出口；
                      nHoldCnt 为连续无效拍计数（上限饱和），供上层判「长时间不可归一」；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 2 · 序号 10）
  ==================================================================
*)

TYPE E_DL_SinCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：参考辐照、温度系数或参考温度越域（故障级，与 bError 配对）/ illegal config, reference irradiance, temperature coefficient or reference temperature out of domain
    eIrrLow     := 2,   // 辐照低于有效下限，本拍不归一（信息级）/ irradiance below the effective floor, not normalised this scan, informational
    eInputBad   := 3,   // 输入非有限或分母不可用，本拍不归一（信息级）/ non-finite input or unusable denominator, not normalised this scan, informational
    eDenormBad  := 4    // 分母超量程，结果不可信（信息级）/ the denominator is out of range and the result is untrustworthy, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_StringIrrNormalize
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时冻结出口保持末值 [-] / enable, the outlet freezes and holds its last value when disabled
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存与保持计数 [-] / reset rising edge clears the fault latch and the hold counter
    fIrrWm2      : REAL := 0.0;              // 实测辐照 [瓦每平方米] / measured irradiance [watt per square metre]
    fIMeasA      : REAL := 0.0;              // 实测组串电流 [安培] / measured string current [ampere]
    fCellTempC   : REAL := 25.0;             // 实测电池温度 [摄氏度] / measured cell temperature [degree Celsius]
    fIrrRefWm2   : REAL := 1000.0;           // 参考辐照 [瓦每平方米]，域 大于零 / reference irradiance [watt per square metre], domain above zero
    fTempRefC    : REAL := 25.0;             // 参考电池温度 [摄氏度] / reference cell temperature [degree Celsius]
    fTempCoefPct : REAL := 0.35;             // 温度系数 [百分比每开尔文]，域 0..2 / temperature coefficient [percent per Kelvin], domain 0 to 2
    fIrrMinWm2   : REAL := 50.0;             // 有效辐照下限 [瓦每平方米]，域 大于零 / effective irradiance floor [watt per square metre], domain above zero
    bTempComp    : BOOL := TRUE;             // 真 = 做温度补偿，假 = 温度因子恒为 1 [-] / true applies temperature compensation, false keeps the factor at one
    nHoldMax     : INT := 600;               // 连续无效拍计数上限 [拍]，域 1..100000 / hold counter ceiling [scan], domain 1 to 100000
END_VAR
VAR_OUTPUT
    fINormA      : REAL := 0.0;              // 归一化组串电流 [安培] / normalised string current [ampere]
    fDenom       : REAL := 0.0;              // 归一化分母（辐照相对量 × 温度因子）[无量纲] / normalisation denominator, relative irradiance times the temperature factor [dimensionless]
    fIRelPct     : REAL := 0.0;              // 辐照相对量 [百分比] / relative irradiance [percent]
    fTFac        : REAL := 1.0;              // 温度因子 [无量纲] / temperature factor [dimensionless]
    bValid       : BOOL := FALSE;            // 本拍归一结果是否有效 [-] / this scan result valid flag
    nHoldCnt     : INT := 0;                 // 连续无效拍计数（饱和到上限）[拍] / consecutive invalid scan count, saturated at the ceiling
    eCause       : E_DL_SinCause := E_DL_SinCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _eCause      : E_DL_SinCause := E_DL_SinCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause : E_DL_SinCause := E_DL_SinCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bInOk       : BOOL := FALSE;            // 三项输入均有限 [-] / all three inputs finite
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bDivOk      : BOOL := FALSE;            // 分母可用判定 [-] / denominator usable verdict
    _bValid      : BOOL := FALSE;            // 本拍有效内部位 [-] / internal validity bit of this scan
    _nHoldUse    : INT := 1;                 // 钳定后的保持计数上限 [拍] / clamped hold counter ceiling [scan]
    _nHoldCnt    : INT := 0;                 // 连续无效拍计数工作值 [拍] / consecutive invalid scan counter [scan]
    _fIrrRel     : REAL := 0.0;              // 辐照相对量工作值 [无量纲] / relative irradiance working value [dimensionless]
    _fTFac       : REAL := 1.0;              // 温度因子工作值 [无量纲] / temperature factor working value [dimensionless]
    _fDenom      : REAL := 0.0;              // 分母工作值 [无量纲] / denominator working value [dimensionless]
    _fNorm       : REAL := 0.0;              // 归一化结果工作值 [安培] / normalised result working value [ampere]
    _fNormHold   : REAL := 0.0;              // 归一化结果保持块 [安培] / normalised result holder [ampere]
END_VAR
VAR CONSTANT
    DL_SIN_DENOM_MIN : REAL := 1.0E-6;       // 分母下限，防除零 [无量纲] / denominator floor against division by zero [dimensionless]
    DL_SIN_DENOM_MAX : REAL := 1.0E3;        // 分母上限，防量纲错配放大 [无量纲] / denominator ceiling against a magnitude mismatch [dimensionless]
    DL_SIN_NORM_MAX  : REAL := 1.0E6;        // 归一化电流量级上限 [安培] / normalised current magnitude ceiling [ampere]
    DL_SIN_COEF_MIN  : REAL := 0.0;          // 温度系数下限 [百分比每开尔文] / temperature coefficient floor [percent per Kelvin]
    DL_SIN_COEF_MAX  : REAL := 2.0;          // 温度系数上限 [百分比每开尔文] / temperature coefficient ceiling [percent per Kelvin]
    DL_SIN_TREF_MIN  : REAL := -50.0;        // 参考温度下限 [摄氏度] / reference temperature floor [degree Celsius]
    DL_SIN_TREF_MAX  : REAL := 100.0;        // 参考温度上限 [摄氏度] / reference temperature ceiling [degree Celsius]
    DL_SIN_HOLD_MAX  : INT := 100000;        // 保持计数上限的钳定上限 [拍] / clamp ceiling of the hold counter [scan]
    DL_SIN_IRR_MAX   : REAL := 2000.0;       // 辐照量级上限，超此视为不可信 [瓦每平方米] / irradiance magnitude ceiling above which the value is untrustworthy [watt per square metre]
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the reset edge, never inside a branch
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_SinCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_SinCause.eNone; // 故障级成因清零 / clear the fault cause
    _nHoldCnt := 0; // 保持计数清零 / clear the hold counter
    _fNormHold := 0.0; // 保持块清零 / clear the holder
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 清保持计数（出口保持块不清，避免读数跳变）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_SinCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _nHoldCnt := 0; // 作用域二：清连续无效拍计数 / scope two, clear the consecutive invalid count
END_IF

// 段 3｜组态域闸（R151 全覆盖）：参考辐照、参考温度、温度系数、辐照下限、计数上限 / segment 3, configuration domain gate over every tuning pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (fIrrRefWm2 <= 0.0) OR (fIrrRefWm2 <> fIrrRefWm2) OR (fIrrRefWm2 > DL_SIN_IRR_MAX) THEN // 参考辐照越域 / reference irradiance out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fTempRefC < DL_SIN_TREF_MIN) OR (fTempRefC > DL_SIN_TREF_MAX) OR (fTempRefC <> fTempRefC) THEN // 参考温度越域 / reference temperature out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fTempCoefPct < DL_SIN_COEF_MIN) OR (fTempCoefPct > DL_SIN_COEF_MAX) OR (fTempCoefPct <> fTempCoefPct) THEN // 温度系数越域 / temperature coefficient out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fIrrMinWm2 <= 0.0) OR (fIrrMinWm2 <> fIrrMinWm2) OR (fIrrMinWm2 >= fIrrRefWm2) THEN // 辐照下限越域或与参考值矛盾 / irradiance floor out of domain or contradicting the reference
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nHoldMax < 1) OR (nHoldMax > DL_SIN_HOLD_MAX) THEN // 计数上限越域 / counter ceiling out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_SinCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF
_nHoldUse := nHoldMax; // 计数上限直通 / counter ceiling passes through
IF _nHoldUse < 1 THEN // 下越界 / below the lower bound
    _nHoldUse := 1; // 回钳到 1 / clamp to one
ELSIF _nHoldUse > DL_SIN_HOLD_MAX THEN // 上越界 / above the upper bound
    _nHoldUse := DL_SIN_HOLD_MAX; // 回钳到上限 / clamp to the ceiling
END_IF

// 段 4｜输入有限性闸：三项全有限才参与换算，任一非有限即保持上拍出口 / segment 4, input finiteness gate over all three measurements
_bInOk := (fIrrWm2 = fIrrWm2) AND ((fIrrWm2 - fIrrWm2) = (fIrrWm2 - fIrrWm2)) AND (fIMeasA = fIMeasA) AND ((fIMeasA - fIMeasA) = (fIMeasA - fIMeasA)) AND (fCellTempC = fCellTempC) AND ((fCellTempC - fCellTempC) = (fCellTempC - fCellTempC)); // 辐照、电流、温度三项有限性闸 / finiteness gate on irradiance, current and temperature
_eCause := E_DL_SinCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
_bValid := FALSE; // 本拍有效位预置假 / preset the validity bit to false
IF (NOT _bInOk) OR _bFault OR (NOT bEnable) THEN // 输入非有限、故障锁存或失能 / non-finite input, fault latched or disabled
    _eCause := E_DL_SinCause.eInputBad; // 信息级成因：不归一 / informational cause, not normalised
ELSE
    // 段 5｜温度因子：补偿关闭时恒为 1；补偿开启时按系数与温差展开 / segment 5, temperature factor computation
    _fTFac := 1.0; // 温度因子默认 1 / the temperature factor defaults to one
    IF bTempComp THEN // 补偿开启 / compensation enabled
        _fTFac := 1.0 + (fTempCoefPct / 100.0) * (fCellTempC - fTempRefC); // 因子，除子为常量 100.0 / factor with the constant divisor one hundred
        IF _fTFac < 0.05 THEN // 因子过小（极端温差外推）/ the factor is too small for a valid extrapolation
            _fTFac := 0.05; // 钳到下限，防分母趋零 / clamped to the floor against a vanishing denominator
        ELSIF _fTFac > 5.0 THEN // 因子过大 / the factor is too large
            _fTFac := 5.0; // 钳到上限 / clamped to the ceiling
        END_IF
    END_IF
    // 段 6｜辐照相对量与分母：辐照低于有效下限时不归一 / segment 6, relative irradiance and denominator
    _fIrrRel := fIrrWm2 / fIrrRefWm2; // 辐照相对量，除子已由域闸证明大于零 / relative irradiance, divisor proven positive by the domain gate
    _fDenom := _fIrrRel * _fTFac; // 分母 / denominator
    _bDivOk := (_fDenom >= DL_SIN_DENOM_MIN) AND (_fDenom <= DL_SIN_DENOM_MAX); // 分母在可用区间 / the denominator is inside the usable band
    IF (fIrrWm2 < fIrrMinWm2) OR (fIrrWm2 > DL_SIN_IRR_MAX) THEN // 辐照低于下限或超量程上限 / irradiance below the floor or above the magnitude ceiling
        _eCause := E_DL_SinCause.eIrrLow; // 信息级成因：辐照不可用 / informational cause, irradiance unusable
    ELSIF NOT _bDivOk THEN // 分母不可用 / the denominator is unusable
        _eCause := E_DL_SinCause.eDenormBad; // 信息级成因：分母超量程 / informational cause, denominator out of range
    ELSE
        _fNorm := fIMeasA / _fDenom; // 归一化电流，除子已证不小于 1E-6 / normalised current, divisor proven not below one micro unit
        IF (_fNorm <> _fNorm) OR ((_fNorm - _fNorm) <> (_fNorm - _fNorm)) OR (ABS(_fNorm) > DL_SIN_NORM_MAX) THEN // 结果非有限或超量级 / the result is non-finite or out of magnitude
            _eCause := E_DL_SinCause.eDenormBad; // 信息级成因：结果不可信 / informational cause, the result is untrustworthy
        ELSE
            _fNormHold := _fNorm; // 有效拍更新保持块（非有限不穿透出口）/ the holder is updated on a valid scan so nothing non-finite passes the outlet
            _bValid := TRUE; // 置本拍有效 / raise the this-scan validity
            _nHoldCnt := 0; // 有效拍清零连续无效计数 / clear the count on a valid scan
        END_IF
    END_IF
END_IF

// 段 7｜无效拍计数：饱和到钳定上限，防溢出翻转 / segment 7, invalid scan counting saturated at the clamped ceiling
IF (NOT _bValid) AND bEnable AND (NOT _bFault) THEN // 仅在使能且无故障时累计无效拍 / counting runs only while enabled and unfaulted
    IF _nHoldCnt < _nHoldUse THEN // 未达上限 / below the ceiling
        _nHoldCnt := _nHoldCnt + 1; // 计数递增 / increment the count
    END_IF
END_IF

// 段 8｜统一出口 / segment 8, unified outlet
fINormA := _fNormHold; // 归一化电流出口取保持块 / the normalised current outlet takes the holder
fDenom := _fDenom; // 分母出口 / denominator outlet
fIRelPct := _fIrrRel * 100.0; // 辐照相对量出口，乘常量 100.0 / relative irradiance outlet with the constant multiplier one hundred
fTFac := _fTFac; // 温度因子出口 / temperature factor outlet
bValid := _bValid AND (NOT _bFault); // 有效出口受故障锁存否决（挂状态量）/ the valid outlet is vetoed by the fault latch, a state quantity
nHoldCnt := _nHoldCnt; // 连续无效拍计数出口 / hold counter outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
