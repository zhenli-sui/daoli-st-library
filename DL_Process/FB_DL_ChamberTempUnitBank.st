(*
  ==================================================================
  组件名 Component  : FB_DL_ChamberTempUnitBank
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 多腔室温标统一换算行。批量把 1..8 个腔室的温度实测值从
                      源温标（摄氏 / 华氏 / 开尔文）换算到目标温标，出口逐通道
                      结果、逐通道有效性掩码与统计计数。内核为「先归一到摄氏、
                      再由摄氏展开到目标温标」两段式，六种换向共用同一对归一 /
                      展开函数体，不存在重复公式分支。
  溯源   Origin     : 温标换算为公开物理定义（0 摄氏度 = 273.15 开尔文 = 32 华氏度，
                      华氏步长为摄氏的 1.8 倍）；本件为 clean-room 实现，仅借鉴来源
                      分类与参数域组织（来源标签 roadmap-p2-chamber），道莅原创设计，
                      未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（REAL / WORD / SHL 常量移位，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做单位换算与有效性标记，不判工艺超温、不做滤波、不做报警；
                      二 非有限输入不穿透出口：该通道保持上拍值并置无效位；
                      三 结果低于目标温标绝对零度时按 bClampAbsZero 钳到绝对零点并置无效位；
                      四 通道游标经回钳 1..8，掩码位移量 0..7 由数组边界与循环上界共同证明；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      afTempOut 逐通道结果；序号大于 nChamberCount 的通道保持上拍值不清零；
                      wInvalidMask 位 i-1 对应通道 i，自证向量：仅通道 1 无效 → 16#0001，
                      仅通道 8 无效 → 16#0080；
                      故障级成因 eUnitBad 与 bError 配对（R45），信息级成因永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 1 · 序号 4）
  ==================================================================
*)

TYPE E_DL_TempUnit :
(
    eCelsius    := 0,   // 摄氏度 [摄氏度] / degree Celsius
    eFahrenheit := 10,  // 华氏度 [华氏度] / degree Fahrenheit
    eKelvin     := 20   // 开尔文 [开尔文] / Kelvin
);
END_TYPE

TYPE E_DL_TubCause :
(
    eNone       := 0,   // 无成因 / no cause
    eUnitBad    := 1,   // 温标枚举非法（故障级，与 bError 配对）/ illegal temperature unit enumeration, a fault paired with bError
    eCountBad   := 2,   // 通道数越域已回钳（信息级）/ channel count out of domain and clamped, informational
    eChanBad    := 3,   // 存在非有限通道，已保持上拍值（信息级）/ non-finite channels present and held at the last value, informational
    eAbsZero    := 4    // 结果低于绝对零度已钳位（信息级）/ result below absolute zero and clamped, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChamberTempUnitBank
VAR_INPUT
    bEnable        : BOOL := TRUE;           // 使能，失能时全部通道保持上拍值 [-] / enable, all channels hold their last value when disabled
    bReset         : BOOL := FALSE;          // 复位上升沿清故障锁存与掩码 [-] / reset rising edge clears the fault latch and the mask
    eUnitIn        : E_DL_TempUnit := E_DL_TempUnit.eCelsius;    // 源温标 [枚举] / source temperature unit [enum]
    eUnitOut       : E_DL_TempUnit := E_DL_TempUnit.eCelsius;    // 目标温标 [枚举] / target temperature unit [enum]
    nChamberCount  : INT := 8;               // 参与换算的腔室数 [个]，域 1..8 / participating channels [count], domain 1 to 8
    bClampAbsZero  : BOOL := TRUE;           // 真 = 低于绝对零度钳位，假 = 仅置无效位不改值 [-] / true clamps below absolute zero, false only flags
END_VAR
VAR_IN_OUT
    afTempIn       : ARRAY[1..8] OF REAL;    // 逐腔室温度输入 [源温标单位]，引用型入参由调用方持有 / per chamber temperature inputs in source unit, reference parameter owned by the caller
END_VAR
VAR_OUTPUT
    afTempOut      : ARRAY[1..8] OF REAL := [8(0.0)]; // 逐腔室换算结果 [目标温标单位] / per chamber converted results in target unit
    wInvalidMask   : WORD := 16#0000;        // 无效通道掩码，位 i-1 对应通道 i [-] / invalid channel mask, bit i minus one maps to channel i
    nValidCount    : INT := 0;               // 本拍有效通道数 [个] / valid channel count of this scan
    bAllValid      : BOOL := FALSE;          // 全部参与通道有效 [-] / all participating channels valid
    bAnyInvalid    : BOOL := FALSE;          // 存在无效通道 [-] / at least one invalid channel
    fSumOut        : REAL := 0.0;            // 有效通道结果之和 [目标温标单位] / sum of the valid converted results
    fAvgOut        : REAL := 0.0;            // 有效通道结果均值 [目标温标单位] / mean of the valid converted results
    eCause         : E_DL_TubCause := E_DL_TubCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError         : BOOL := FALSE;          // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset        : R_TRIG;                 // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _eCause        : E_DL_TubCause := E_DL_TubCause.eNone;  // 内部成因，故障级锁存、信息级每拍重算 / internal cause, latched for faults and recomputed for information
    _bFault        : BOOL := FALSE;          // 故障锁存位（温标枚举非法）/ fault latch bit for an illegal unit enumeration
    _bInit         : BOOL := FALSE;          // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bUnitInOk     : BOOL := FALSE;          // 源温标枚举合法性 [-] / source unit enumeration validity
    _bUnitOutOk    : BOOL := FALSE;          // 目标温标枚举合法性 [-] / target unit enumeration validity
    _bChanOk       : BOOL := FALSE;          // 单通道输入有限性 [-] / single channel input finiteness
    _bResultOk     : BOOL := FALSE;          // 单通道结果有限性 [-] / single channel result finiteness
    _bChanBitBad   : BOOL := FALSE;          // 单通道无效位 [-] / single channel invalid bit
    _bAbsZeroHit   : BOOL := FALSE;          // 本拍出现绝对零度钳位 [-] / an absolute zero clamp occurred this scan
    _bChanNonFin   : BOOL := FALSE;          // 本拍出现非有限通道 [-] / a non-finite channel occurred this scan
    _bCountClamped : BOOL := FALSE;          // 通道数被回钳 [-] / the channel count was clamped
    _nUseCount     : INT := 0;               // 钳定后的参与通道数 [个] / clamped participating channel count
    _nIdx          : INT := 0;               // 通道游标（1 起，回钳 1..8）[通道号] / channel cursor, one-based, clamped one through eight
    _fCelsius      : REAL := 0.0;            // 归一到摄氏度的中间量 [摄氏度] / intermediate normalised to Celsius
    _fResult       : REAL := 0.0;            // 展开到目标温标的中间量 [目标温标单位] / intermediate expanded to the target unit
    _fLowLimit     : REAL := 0.0;            // 目标温标绝对零度 [目标温标单位] / absolute zero in the target unit
    _fSum          : REAL := 0.0;            // 有效结果累加 [目标温标单位] / running sum of valid results
    _wMask         : WORD := 16#0000;        // 掩码累加器，每拍清零重建 / mask accumulator, rebuilt every scan
    _wBitOne       : WORD := 16#0001;        // 单位位常量，供常量移位使用 [-] / single bit constant for the shift
END_VAR
VAR CONSTANT
    DL_TUB_MAX        : INT := 8;            // 通道容量，同时也是游标回钳上界 [个] / channel capacity and cursor clamp upper bound
    DL_TUB_K_OFFSET   : REAL := 273.15;      // 摄氏与开尔文零点偏移 [开尔文] / zero offset between Celsius and Kelvin
    DL_TUB_F_RATIO    : REAL := 1.8;         // 华氏与摄氏步长比 [无量纲] / scale ratio between Fahrenheit and Celsius
    DL_TUB_F_OFFSET   : REAL := 32.0;        // 华氏零点偏移 [华氏度] / zero offset of Fahrenheit
    DL_TUB_ABS_C      : REAL := -273.15;     // 摄氏绝对零度 [摄氏度] / absolute zero in Celsius
    DL_TUB_ABS_F      : REAL := -459.67;     // 华氏绝对零度 [华氏度] / absolute zero in Fahrenheit
    DL_TUB_ABS_K      : REAL := 0.0;         // 开尔文绝对零度 [开尔文] / absolute zero in Kelvin
    DL_TUB_ABS_MARGIN : REAL := 0.01;        // 绝对零度容差带，吸收换算舍入 [目标温标单位] / absolute zero tolerance absorbing rounding
    DL_TUB_MASK_NONE  : WORD := 16#0000;     // 空掩码常量 [-] / empty mask constant
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the reset edge, never inside a branch
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_TubCause.eNone; // 成因清零 / clear the cause
    _wMask := DL_TUB_MASK_NONE; // 掩码清零 / clear the mask
    _nIdx := 1; // 游标归位 / park the cursor at one
END_IF

// 段 2｜复位沿作用域：清锁存与清成因（通道输出保持，避免读数跳变）/ segment 2, reset edge scope, the latch and cause are cleared while channel outputs are held
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eCause := E_DL_TubCause.eNone; // 作用域一：清成因 / scope one, clear the cause
    _wMask := DL_TUB_MASK_NONE; // 作用域二：清无效掩码 / scope two, clear the invalid mask
END_IF

// 段 3｜温标枚举域闸：枚举有序直比，禁枚举转整数（跨平台安全）/ segment 3, unit enumeration gate by direct comparison, never by casting an enum to an integer
_bUnitInOk := (eUnitIn = E_DL_TempUnit.eCelsius) OR (eUnitIn = E_DL_TempUnit.eFahrenheit) OR (eUnitIn = E_DL_TempUnit.eKelvin); // 源温标三选一 / the source unit is one of three
_bUnitOutOk := (eUnitOut = E_DL_TempUnit.eCelsius) OR (eUnitOut = E_DL_TempUnit.eFahrenheit) OR (eUnitOut = E_DL_TempUnit.eKelvin); // 目标温标三选一 / the target unit is one of three
IF ((NOT _bUnitInOk) OR (NOT _bUnitOutOk)) AND (NOT _bFault) THEN // 枚举非法且未锁存 / illegal enumeration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eCause := E_DL_TubCause.eUnitBad; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF

// 段 4｜通道数回钳：越域走信息级成因，不锁存故障 / segment 4, channel count clamping with an informational cause
_bCountClamped := FALSE; // 回钳标志预置假 / preset the clamp flag to false
_nUseCount := nChamberCount; // 通道数直通 / channel count passes through
IF _nUseCount < 1 THEN // 下越界 / below the lower bound
    _nUseCount := 1; // 回钳到 1 / clamp to one
    _bCountClamped := TRUE; // 置回钳标志 / raise the clamp flag
ELSIF _nUseCount > DL_TUB_MAX THEN // 上越界 / above the upper bound
    _nUseCount := DL_TUB_MAX; // 回钳到容量上限 / clamp to the capacity ceiling
    _bCountClamped := TRUE; // 置回钳标志 / raise the clamp flag
END_IF
IF NOT bEnable THEN // 失能：不换算，全部通道保持上拍值（R191 显式声明冻结语义）/ disabled, no conversion and every channel holds its last value
    _nUseCount := 0; // 参与通道数置零使主循环不执行 / the participating count is zeroed so the main loop does not run
END_IF

// 段 5｜目标温标绝对零度选取（三支互异，非法枚举按摄氏兜底且故障已锁存）/ segment 5, absolute zero selection for the target unit
_fLowLimit := DL_TUB_ABS_C; // 绝对零度默认取摄氏 / absolute zero defaults to Celsius
IF eUnitOut = E_DL_TempUnit.eFahrenheit THEN // 目标华氏 / target Fahrenheit
    _fLowLimit := DL_TUB_ABS_F; // 华氏绝对零度 / Fahrenheit absolute zero
ELSIF eUnitOut = E_DL_TempUnit.eKelvin THEN // 目标开尔文 / target Kelvin
    _fLowLimit := DL_TUB_ABS_K; // 开尔文绝对零度 / Kelvin absolute zero
END_IF

// 段 6｜逐通道换算主循环 / segment 6, per channel conversion loop
_wMask := DL_TUB_MASK_NONE; // 掩码每拍清零重建 / the mask is rebuilt every scan
_fSum := 0.0; // 有效结果和清零 / clear the valid result sum
nValidCount := 0; // 有效通道计数清零 / clear the valid channel count
_bAbsZeroHit := FALSE; // 绝对零度钳位标志清零 / clear the absolute zero clamp flag
_bChanNonFin := FALSE; // 非有限通道标志清零 / clear the non-finite channel flag
_nIdx := 1; // 游标自 1 起，上界由 _nUseCount 约束 / the cursor starts at one, bounded by the usable count
WHILE _nIdx <= _nUseCount DO // 循环上界为钳定后的通道数，天然不越 8 / the loop bound is the clamped count, never beyond eight
    _bChanOk := (afTempIn[_nIdx] = afTempIn[_nIdx]) AND ((afTempIn[_nIdx] - afTempIn[_nIdx]) = (afTempIn[_nIdx] - afTempIn[_nIdx])); // 输入有限性闸，NaN 用自反、无穷用差值自减 / input finiteness gate
    _bChanBitBad := FALSE; // 单通道无效位预置假 / preset the single channel invalid bit to false
    IF NOT _bChanOk THEN // 输入非有限 / non-finite input
        _bChanBitBad := TRUE; // 置该通道无效位 / raise the invalid bit of that channel
        _bChanNonFin := TRUE; // 记非有限通道成因 / record the non-finite channel cause
    ELSE
        // 段 6.1｜先归一到摄氏度 / segment 6.1, normalise to Celsius first
        IF eUnitIn = E_DL_TempUnit.eFahrenheit THEN // 源华氏 / source Fahrenheit
            _fCelsius := (afTempIn[_nIdx] - DL_TUB_F_OFFSET) / DL_TUB_F_RATIO; // 除以常量 1.8，除子为非零常量 / divided by the constant one point eight
        ELSIF eUnitIn = E_DL_TempUnit.eKelvin THEN // 源开尔文 / source Kelvin
            _fCelsius := afTempIn[_nIdx] - DL_TUB_K_OFFSET; // 减零点偏移 / subtract the zero offset
        ELSE // 源摄氏或非法枚举（故障已锁存）/ source Celsius or an illegal enumeration with the fault latched
            _fCelsius := afTempIn[_nIdx]; // 直通 / pass through
        END_IF
        // 段 6.2｜再由摄氏度展开到目标温标 / segment 6.2, expand from Celsius to the target unit
        IF eUnitOut = E_DL_TempUnit.eFahrenheit THEN // 目标华氏 / target Fahrenheit
            _fResult := _fCelsius * DL_TUB_F_RATIO + DL_TUB_F_OFFSET; // 乘步长比加零点偏移 / scale then offset
        ELSIF eUnitOut = E_DL_TempUnit.eKelvin THEN // 目标开尔文 / target Kelvin
            _fResult := _fCelsius + DL_TUB_K_OFFSET; // 加零点偏移 / add the zero offset
        ELSE // 目标摄氏或非法枚举（故障已锁存）/ target Celsius or an illegal enumeration with the fault latched
            _fResult := _fCelsius; // 直通 / pass through
        END_IF
        _bResultOk := (_fResult = _fResult) AND ((_fResult - _fResult) = (_fResult - _fResult)); // 结果有限性闸 / result finiteness gate
        IF NOT _bResultOk THEN // 结果非有限 / non-finite result
            _bChanBitBad := TRUE; // 置该通道无效位 / raise the invalid bit of that channel
            _bChanNonFin := TRUE; // 记非有限通道成因 / record the non-finite channel cause
        ELSE
            IF _fResult < (_fLowLimit + DL_TUB_ABS_MARGIN) THEN // 低于绝对零度（含舍入容差带）/ below absolute zero including the rounding band
                _bAbsZeroHit := TRUE; // 记绝对零度成因 / record the absolute zero cause
                _bChanBitBad := TRUE; // 置该通道无效位 / raise the invalid bit of that channel
                IF bClampAbsZero THEN // 需要钳位 / clamping requested
                    _fResult := _fLowLimit; // 钳到绝对零点 / clamp to absolute zero
                END_IF
            END_IF
            afTempOut[_nIdx] := _fResult; // 结果落定到该通道 / settle the result into that channel
        END_IF
        IF NOT _bChanBitBad THEN // 该通道有效 / the channel is valid
            nValidCount := nValidCount + 1; // 有效计数递增 / increment the valid count
            _fSum := _fSum + afTempOut[_nIdx]; // 累加有效结果 / accumulate the valid result
        END_IF
    END_IF
    IF _bChanBitBad THEN // 该通道无效 / the channel is invalid
        _wMask := _wMask OR SHL(_wBitOne, _nIdx - 1); // 置无效位，位移量 0..7 由数组边界与循环上界共同证明 / set the invalid bit, the shift zero through seven is proven by the array bound and the loop bound
    END_IF
    _nIdx := _nIdx + 1; // 游标递增 / increment the cursor
END_WHILE

// 段 7｜统计与成因分派（R190 归因唯一，固定优先级：故障 > 回钳 > 非有限 > 绝对零度）/ segment 7, statistics and cause dispatch with a fixed priority
bAnyInvalid := _wMask <> DL_TUB_MASK_NONE; // 存在无效通道 / at least one invalid channel
bAllValid := (_wMask = DL_TUB_MASK_NONE) AND (_nUseCount >= 1); // 全部参与通道有效 / all participating channels valid
fSumOut := _fSum; // 有效和出口 / valid sum outlet
IF nValidCount > 0 THEN // 有有效通道才可算均值 / the mean needs at least one valid channel
    fAvgOut := _fSum / INT_TO_REAL(nValidCount); // 均值，除子已证大于零 / mean, divisor proven positive
ELSE
    fAvgOut := 0.0; // 无有效通道时均值为零 / zero mean when nothing is valid
END_IF
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    _eCause := E_DL_TubCause.eUnitBad; // 故障级成因锁存回放（禁按当下输入重推断）/ the fault cause is replayed from the latch
ELSIF _bCountClamped THEN // 通道数被回钳 / the channel count was clamped
    _eCause := E_DL_TubCause.eCountBad; // 信息级成因 / informational cause
ELSIF _bChanNonFin THEN // 存在非有限通道 / non-finite channels present
    _eCause := E_DL_TubCause.eChanBad; // 信息级成因 / informational cause
ELSIF _bAbsZeroHit THEN // 存在绝对零度钳位 / an absolute zero clamp occurred
    _eCause := E_DL_TubCause.eAbsZero; // 信息级成因 / informational cause
ELSE
    _eCause := E_DL_TubCause.eNone; // 无成因 / no cause
END_IF

// 段 8｜统一出口 / segment 8, unified outlet
wInvalidMask := _wMask; // 掩码出口 / mask outlet
eCause := _eCause; // 成因出口单点映射 / single-point cause outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
