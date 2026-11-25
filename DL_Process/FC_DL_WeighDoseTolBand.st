(*
  ============================================================
  组件名 : FC_DL_WeighDoseTolBand
  分类   : DL_Process
  功能   : 配料实绩对目标值的公差带判定，返回欠量、合格、超量或无效分档
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WeighDoseTolBand : INT
VAR_INPUT
    rTarget      : REAL; // 配料目标值 [kg] dosing target [kg]
    rActual      : REAL; // 配料实绩值 [kg] actual dosed weight [kg]
    rTolMinus    : REAL; // 下公差（欠量侧）[kg] minus tolerance on the under side [kg]
    rTolPlus     : REAL; // 上公差（超量侧）[kg] plus tolerance on the over side [kg]
    rMinEffective: REAL; // 有效称量下限 [kg] minimum effective reading [kg]
END_VAR
VAR_OUTPUT
    nBand  : INT; // 分档结果 -2无效 -1欠 0合格 1超 [档] band code -2 void, -1 under, 0 ok, 1 over [band]
    bValid : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 三实数输入有限性判定 finiteness verdict of the three real inputs
    _rTolM : REAL := 0.0; // 钳位后的下公差 [kg] clamped minus tolerance [kg]
    _rTolP : REAL := 0.0; // 钳位后的上公差 [kg] clamped plus tolerance [kg]
    _rLow  : REAL := 0.0; // 合格带下沿 [kg] lower edge of the band [kg]
    _rHigh : REAL := 0.0; // 合格带上沿 [kg] upper edge of the band [kg]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WeighDoseTolBand := -2; // 缺省按无效分档 default void band
nBand := -2; // 分档码预置无效 band code preset void
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rTarget = rTarget) AND (rActual = rActual) AND (rTolMinus = rTolMinus) AND (rTolPlus = rTolPlus) AND (rMinEffective = rMinEffective); // 五输入自反判定 self comparison of the five inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜有效称量下限闸 minimum effective reading gate
IF rActual < rMinEffective THEN
    RETURN; // 读数低于有效下限按无效处理 a reading below the floor is void
END_IF
// 段 4｜公差整形与带沿计算 tolerance reshape and band edges
_rTolM := rTolMinus; // 取下公差 take the minus tolerance
IF _rTolM < 0.0 THEN
    _rTolM := ABS(_rTolM); // 负下公差取幅值 a negative minus tolerance becomes its magnitude
END_IF
_rTolP := rTolPlus; // 取上公差 take the plus tolerance
IF _rTolP < 0.0 THEN
    _rTolP := ABS(_rTolP); // 负上公差取幅值 a negative plus tolerance becomes its magnitude
END_IF
_rLow := rTarget - _rTolM; // 合格带下沿 lower edge of the acceptance band
_rHigh := rTarget + _rTolP; // 合格带上沿 upper edge of the acceptance band
// 段 5｜双向分档判定 directional band verdict
IF rActual < _rLow THEN
    nBand := -1; // 欠量 under weight
ELSIF rActual > _rHigh THEN
    nBand := 1; // 超量 over weight
ELSE
    nBand := 0; // 带内合格 in band
END_IF
bValid := TRUE; // 结果可用 result usable
FC_DL_WeighDoseTolBand := nBand; // 函数返回分档码 return the band code
END_FUNCTION
