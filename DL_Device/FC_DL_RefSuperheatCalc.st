(*
  ============================================================
  组件名 : FC_DL_RefSuperheatCalc
  分类   : DL_Device
  功能   : 吸气过热度计算，由吸气温度与对应饱和温度求过热度并分档判定
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_RefSuperheatCalc : REAL
VAR_INPUT
    rSuctionTempC    : REAL; // 吸气实测温度 [摄氏度] measured suction temperature [degree celsius]
    rSatSuctionTempC : REAL; // 吸气饱和温度 [摄氏度] saturation temperature at the suction pressure [degree celsius]
    rShLow           : REAL; // 过热度下限 [K] lower superheat bound [kelvin]
    rShHigh          : REAL; // 过热度上限 [K] upper superheat bound [kelvin]
END_VAR
VAR_OUTPUT
    rSuperheatK : REAL; // 吸气过热度 [K] suction superheat [kelvin]
    nStatus     : INT; // 分档 0正常 1偏低 2偏高 [档] status 0 normal, 1 low, 2 high [band]
    bValid      : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 四输入有限性判定 finiteness verdict of the four inputs
    _rSh   : REAL := 0.0; // 过热度中间量 [K] intermediate superheat [kelvin]
    _rLo   : REAL := 0.0; // 钳位后的下限 [K] clamped lower bound [kelvin]
    _rHi   : REAL := 0.0; // 钳位后的上限 [K] clamped upper bound [kelvin]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_RefSuperheatCalc := 0.0; // 缺省返回零 default zero return
rSuperheatK := 0.0; // 过热度预置零 superheat preset to zero
nStatus := 0; // 分档预置正常 status preset normal
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rSuctionTempC = rSuctionTempC) AND (rSatSuctionTempC = rSatSuctionTempC) AND (rShLow = rShLow) AND (rShHigh = rShHigh); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜主体过热度 main superheat
_rSh := rSuctionTempC - rSatSuctionTempC; // 吸气温度减饱和温度 suction minus saturation
rSuperheatK := _rSh; // 过热度落定 land the superheat
// 段 4｜上下限整形 bound reshape
_rLo := rShLow; // 取下限 take the lower bound
_rHi := rShHigh; // 取上限 take the upper bound
IF _rLo > _rHi THEN
    _rLo := rShHigh; // 上下限倒置时下限取原上限 an inverted pair swaps the lower bound
    _rHi := rShLow; // 上下限倒置时上限取原下限 an inverted pair swaps the upper bound
END_IF
// 段 5｜双向分档判定 directional status verdict
IF _rSh < _rLo THEN
    nStatus := 1; // 过热度偏低 superheat too low
ELSIF _rSh > _rHi THEN
    nStatus := 2; // 过热度偏高 superheat too high
ELSE
    nStatus := 0; // 区间内正常 inside the normal band
END_IF
bValid := TRUE; // 结果可用 result usable
FC_DL_RefSuperheatCalc := _rSh; // 函数返回过热度 return the superheat
END_FUNCTION
