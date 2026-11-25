(*
  ============================================================
  组件名 : FC_DL_WeighNetFromGross
  分类   : DL_Process
  功能   : 毛重去皮与零点偏置扣除求净重，负净重超出容差判无效并清零
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WeighNetFromGross : REAL
VAR_INPUT
    rGross      : REAL; // 毛重 [kg] gross weight [kg]
    rTare       : REAL; // 皮重 [kg] tare weight [kg]
    rZeroOffset : REAL; // 零点偏置 [kg] zero offset [kg]
    rNegTol     : REAL; // 负净重容差 [kg] negative net tolerance [kg]
END_VAR
VAR_OUTPUT
    rNet   : REAL; // 净重结果 [kg] net weight result [kg]
    bValid : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR
    _bFin : BOOL := FALSE; // 四输入有限性判定 finiteness verdict of the four inputs
    _rTol : REAL := 0.0; // 钳位后的负容差 [kg] clamped negative tolerance [kg]
    _rNet : REAL := 0.0; // 净重中间量 [kg] intermediate net weight [kg]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WeighNetFromGross := 0.0; // 缺省返回零 default zero return
rNet := 0.0; // 净重预置零 net weight preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rGross = rGross) AND (rTare = rTare) AND (rZeroOffset = rZeroOffset) AND (rNegTol = rNegTol); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效，出口保持零点 non finite means invalid and the zero output stays
END_IF
// 段 3｜负容差整形 reshape the negative tolerance
_rTol := rNegTol; // 取入参容差 take the tolerance input
IF _rTol < 0.0 THEN
    _rTol := 0.0; // 负容差按零处理 a negative tolerance becomes zero
END_IF
// 段 4｜主体扣减与负净重拦截 main subtraction and the negative net gate
_rNet := rGross - rTare - rZeroOffset; // 毛重去皮去零点 gross minus tare minus zero offset
IF _rNet < -_rTol THEN
    rNet := 0.0; // 超负容差净重清零 clear the net weight beyond tolerance
    RETURN; // 判无效并早退 invalid and early return
END_IF
rNet := _rNet; // 净重落定 land the net weight
bValid := TRUE; // 结果可用 result usable
FC_DL_WeighNetFromGross := _rNet; // 函数返回净重 return the net weight
END_FUNCTION
