(*
  ============================================================
  组件名 : FC_DL_SludgeAgeCalc
  分类   : DL_Process
  功能   : 活性污泥泥龄计算，由曝气池泥量与每日排泥量求污泥停留时间
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_SludgeAgeCalc : REAL
VAR_INPUT
    rMlss_mgL      : REAL; // 曝气池混合液悬浮固体浓度 [mg/L] mixed liquor suspended solids [mg per litre]
    rAerationVol_m3: REAL; // 曝气池有效容积 [m3] aeration tank effective volume [m3]
    rWasFlow_m3d   : REAL; // 剩余污泥排放流量 [m3/d] waste activated sludge flow [m3 per day]
    rWasTss_mgL    : REAL; // 剩余污泥悬浮固体浓度 [mg/L] waste sludge suspended solids [mg per litre]
    rEffTss_mgL    : REAL; // 出水悬浮固体浓度 [mg/L] effluent suspended solids [mg per litre]
END_VAR
VAR_OUTPUT
    rSrtDay        : REAL; // 污泥停留时间 [d] sludge retention time [day]
    rSludgeMass_kg : REAL; // 曝气池污泥总量 [kg] sludge mass in the aeration tank [kg]
    rWasteMass_kgd : REAL; // 每日排泥量 [kg/d] daily wasted sludge mass [kg per day]
    bValid         : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_MG_PER_KG : REAL := 1000.0; // 每千克毫克数 milligrams per kilogram
END_VAR
VAR
    _bFin    : BOOL := FALSE; // 五输入有限性判定 finiteness verdict of the five inputs
    _rSolid  : REAL := 0.0; // 排泥固体浓度 [mg/L] solids concentration of the waste stream [mg per litre]
    _rMass   : REAL := 0.0; // 污泥总量中间量 [kg] intermediate sludge mass [kg]
    _rWaste  : REAL := 0.0; // 排泥量中间量 [kg/d] intermediate waste mass [kg per day]
    _rSrt    : REAL := 0.0; // 泥龄中间量 [d] intermediate retention time [day]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_SludgeAgeCalc := 0.0; // 缺省返回零 default zero return
rSrtDay := 0.0; // 泥龄预置零 retention time preset to zero
rSludgeMass_kg := 0.0; // 污泥总量预置零 sludge mass preset to zero
rWasteMass_kgd := 0.0; // 排泥量预置零 waste mass preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rMlss_mgL = rMlss_mgL) AND (rAerationVol_m3 = rAerationVol_m3) AND (rWasFlow_m3d = rWasFlow_m3d) AND (rWasTss_mgL = rWasTss_mgL) AND (rEffTss_mgL = rEffTss_mgL); // 五输入自反判定 self comparison of the five inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜浓度与容积方向闸 concentration and volume gate
IF (rMlss_mgL < 0.0) OR (rAerationVol_m3 <= 0.0) OR (rWasFlow_m3d < 0.0) OR (rWasTss_mgL < 0.0) OR (rEffTss_mgL < 0.0) THEN
    RETURN; // 负浓度或非正容积属配置非法 an illegal concentration or a non positive volume
END_IF
// 段 4｜泥量与排泥量 sludge mass and the daily waste mass
_rMass := rMlss_mgL * rAerationVol_m3 / DL_MG_PER_KG; // 浓度乘容积折千克 concentration times volume in kilograms
_rSolid := rWasTss_mgL; // 排泥固体先取剩余污泥浓度 the waste solids start at the waste sludge concentration
IF rEffTss_mgL > _rSolid THEN
    _rSolid := rEffTss_mgL; // 出水带泥更高时取出水浓度 the higher of the two concentrations governs
END_IF
_rWaste := rWasFlow_m3d * _rSolid / DL_MG_PER_KG; // 流量乘浓度折千克流量 times concentration in kilograms
rSludgeMass_kg := _rMass; // 泥量落定 land the sludge mass
rWasteMass_kgd := _rWaste; // 排泥量落定 land the waste mass
// 段 5｜泥龄与出口 retention time and the exit
IF _rWaste <= 0.0 THEN
    RETURN; // 排泥为零时泥龄无定义 a zero waste flow leaves the retention time undefined
END_IF
_rSrt := _rMass / _rWaste; // 泥龄等于泥量除排泥量 retention time is the mass over the daily waste
rSrtDay := _rSrt; // 泥龄落定 land the retention time
bValid := TRUE; // 结果可用 result usable
FC_DL_SludgeAgeCalc := _rSrt; // 函数返回泥龄 return the retention time
END_FUNCTION
