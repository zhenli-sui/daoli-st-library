(*
  ============================================================
  组件名 : FC_DL_MembraneTmpCalc
  分类   : DL_Process
  功能   : 膜系统跨膜压差计算，进料侧取单点或浓水与进料均值，再扣除渗透压得净推动力
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_MembraneTmpCalc : REAL
VAR_INPUT
    rFeedPress_bar : REAL; // 进料侧压力 [bar] feed side pressure [bar]
    rConcPress_bar : REAL; // 浓水侧压力 [bar] concentrate side pressure [bar]
    rPermPress_bar : REAL; // 产水侧压力 [bar] permeate side pressure [bar]
    rOsmotic_bar   : REAL; // 渗透压 [bar] osmotic pressure [bar]
    bUseAvgFeed    : BOOL; // 真为进料与浓水取均值，假为取进料压力 average the feed and the concentrate when true
END_VAR
VAR_OUTPUT
    rTmp_bar       : REAL; // 跨膜压差 [bar] trans membrane pressure [bar]
    rNetDriving_bar: REAL; // 净推动力 [bar] net driving pressure [bar]
    bValid         : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_HALF : REAL := 0.5; // 均值系数 averaging factor
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 四实数输入有限性判定 finiteness verdict of the four real inputs
    _rFeed  : REAL := 0.0; // 进料侧有效压力 [bar] effective feed side pressure [bar]
    _rTmp   : REAL := 0.0; // 跨膜压差中间量 [bar] intermediate trans membrane pressure [bar]
    _rNet   : REAL := 0.0; // 净推动力中间量 [bar] intermediate net driving pressure [bar]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_MembraneTmpCalc := 0.0; // 缺省返回零 default zero return
rTmp_bar := 0.0; // 跨膜压差预置零 trans membrane pressure preset to zero
rNetDriving_bar := 0.0; // 净推动力预置零 net driving pressure preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rFeedPress_bar = rFeedPress_bar) AND (rConcPress_bar = rConcPress_bar) AND (rPermPress_bar = rPermPress_bar) AND (rOsmotic_bar = rOsmotic_bar); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜压力方向闸 pressure direction gate
IF (rFeedPress_bar < 0.0) OR (rConcPress_bar < 0.0) OR (rPermPress_bar < 0.0) OR (rOsmotic_bar < 0.0) THEN
    RETURN; // 负压力或负渗透压属配置非法 a negative pressure or osmotic value is illegal
END_IF
// 段 4｜进料侧有效压力选择 the effective feed side pressure
IF bUseAvgFeed THEN
    _rFeed := (rFeedPress_bar + rConcPress_bar) * DL_HALF; // 进料与浓水取均值 average the feed and the concentrate
ELSE
    _rFeed := rFeedPress_bar; // 直接取进料压力 take the feed pressure itself
END_IF
// 段 5｜跨膜压差与净推动力 trans membrane pressure and the net driving force
_rTmp := _rFeed - rPermPress_bar; // 进料侧减产水侧 feed side minus permeate side
rTmp_bar := _rTmp; // 跨膜压差落定 land the trans membrane pressure
_rNet := _rTmp - rOsmotic_bar; // 扣除渗透压 deduct the osmotic pressure
rNetDriving_bar := _rNet; // 净推动力落定 land the net driving force
IF _rTmp > 0.0 THEN
    bValid := TRUE; // 正跨膜压差判结果可用 a positive pressure makes the result usable
END_IF
FC_DL_MembraneTmpCalc := _rTmp; // 函数返回跨膜压差 return the trans membrane pressure
END_FUNCTION
