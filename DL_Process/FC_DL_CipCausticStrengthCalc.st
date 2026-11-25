// FC_DL_CipCausticStrengthCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: CIP 碱液调配：目标碱量 = 目标浓度·液量/100 [L·%]，当前碱量 = 当前浓度·液量/100，
        缺额 = 目标 − 当前，补浓碱体积 = 缺额/(浓碱浓度 − 目标浓度) [L]（稀释到目标的物料平衡）；
        当前浓度高于目标时补水体积 = 液量·(当前/目标 − 1) [L]。两工况互斥。
  邻件/码位: 与 FC_DL_KegFillingCounterPressureCalc 同属灌装/清洗线设备件（CIP 化学 vs 灌装压力）；
             16#0002_9238 = 非有限、目标浓度越界、液量非正、当前浓度为负或补碱补水互斥违例。
*)
FUNCTION FC_DL_CipCausticStrengthCalc : REAL
VAR_INPUT
    fConcNow    : REAL := 1.5;      // 当前碱液浓度 [%]，域 >= 0 / Current concentration [%]
    fVolNow     : REAL := 2000.0;   // 当前液量 [L]，域 > 0 / Current volume [L]
    fConcTarget : REAL := 2.0;      // 目标浓度 [%]，域 (0, 浓碱浓度) / Target concentration [%]
    fConcStock  : REAL := 30.0;     // 浓碱浓度 [%]，域 > 目标浓度 / Stock concentration [%]
END_VAR
VAR_OUTPUT
    fAddVol   : REAL;               // 需补浓碱体积 [L] / Stock caustic to add [L]
    fAddWater : REAL;               // 需补水体积 [L] / Water to add [L]
    bValid    : BOOL;               // 结果有效回执 [-] / Result validity receipt
    uErrorId  : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fAlkaliGap : REAL := 0.0;       // 碱量缺额 [L·%] / Alkali deficit [L percent]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fAddVol := 0.0;                     // 补碱体积缺省零 / Stock caustic default zero
fAddWater := 0.0;                   // 补水体积缺省零 / Water to add default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_CipCausticStrengthCalc := 0.0;    // 返回值缺省零（镜像补碱体积）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fConcNow <> fConcNow) OR (fVolNow <> fVolNow)
   OR (fConcTarget <> fConcTarget) OR (fConcStock <> fConcStock)
   OR (ABS(fConcNow) >= 3.0E38) OR (ABS(fVolNow) >= 3.0E38)
   OR (ABS(fConcTarget) >= 3.0E38) OR (ABS(fConcStock) >= 3.0E38) THEN
    uErrorId := 16#0002_9238;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（目标浓度区间 + 液量正 + 当前浓度非负，R4）/ Domain gate
IF (fConcTarget <= 1.0E-6) OR (fConcTarget >= fConcStock) THEN
    uErrorId := 16#0002_9238;   // 目标浓度越界（分母近零）/ Target concentration out of range
    RETURN;
END_IF
IF fVolNow <= 1.0E-6 THEN
    uErrorId := 16#0002_9238;   // 液量非正 / Non-positive liquid volume
    RETURN;
END_IF
IF fConcNow < 0.0 THEN
    uErrorId := 16#0002_9238;   // 当前浓度为负 / Negative current concentration
    RETURN;
END_IF
// 段 3：主计算（碱量差 → 补碱体积 / 补水体积，两工况互斥）/ Main computation
// 碱量衡算（R92-修正）：(C_n·V + C_s·x)/(V+x) = C_t  ⇒  x = (C_t − C_n)·V/(C_s − C_t)
// 说明：早期版本误把缺额再除 100（浓度已按 % 计），致补碱量偏小 100 倍、CIP 永久欠配
fAlkaliGap := (fConcTarget - fConcNow) * fVolNow;               // 碱量缺额 [%·L] / Alkali deficit
IF fAlkaliGap > 1.0E-6 THEN
    fAddVol := fAlkaliGap / (fConcStock - fConcTarget);          // 补浓碱体积 [L] / Stock to add
END_IF
IF fConcNow > fConcTarget THEN
    fAddWater := fVolNow * (fConcNow / fConcTarget - 1.0);       // 补水体积 [L] / Water to add
END_IF
// 段 4：出口闸（非有限复核 + 非负复核 + 互斥复核）/ Outlet gate
IF (fAddVol <> fAddVol) OR (fAddWater <> fAddWater)
   OR (ABS(fAddVol) >= 3.0E38) OR (ABS(fAddWater) >= 3.0E38)
   OR (fAddVol < 0.0) OR (fAddWater < 0.0)
   OR ((fAddVol > 1.0E-6) AND (fAddWater > 1.0E-6)) THEN
    fAddVol := 0.0;             // 复核失败回缺省（含互斥违例）/ Fallback on recheck failure
    fAddWater := 0.0;           // 复核失败回缺省（含互斥违例）/ Fallback on recheck failure
    uErrorId := 16#0002_9238;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_CipCausticStrengthCalc := fAddVol;        // 返回值镜像补碱体积 / Return mirrors stock volume
END_FUNCTION
