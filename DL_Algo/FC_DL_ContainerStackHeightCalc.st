(*
 * FC_DL_ContainerStackHeightCalc | C2 | DL_Algo
 * 功能：堆场贝位层高与箱位换算（顶面标高、剩余层数、超高判定）       单位：层 [1]、层高 [m]、标高 [m]
 * 工况边界：nTier 须落在 [1, nMaxTier] 且 nMaxTier≥1，否则判故障 9611 并输出安全值（超高置 TRUE 阻止堆箱）；堆高上限 rMaxStackHm 须 >0；层高须 >0 且有限
 * 代数值回代：nTier=5、rTierHm=2.591、rBaseHm=0.30 → top=0.30+4×2.591+2.591=13.255 m（spec 记 13.25 m，取两位小数一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_ContainerStackHeightCalc : BOOL
VAR_INPUT
    nTier        : INT;              // 目标层号（1 起）| target tier, one based [层]
    nMaxTier     : INT;              // 该贝位允许的最大层数 | maximum tier count of this bay [层]
    rTierHm      : REAL := 2.591;    // 单层箱高（含层间间隙）| container height including the gap [m]
    rBaseHm      : REAL := 0.30;     // 基础标高（码头面至第一层箱底）| base elevation from the quay to the first box bottom [m]
    rMaxStackHm  : REAL := 30.0;     // 堆场允许最大标高 | maximum permitted stack elevation [m]
END_VAR
VAR_OUTPUT
    rTopElevM  : REAL;               // 目标层顶面标高 | top elevation of the target tier [m]
    nFreeTier  : INT;                // 剩余可用层数 | remaining tier capacity [层]
    xOverHeight: BOOL;               // 超高（顶面超 rMaxStackHm）| over height, the top exceeds rMaxStackHm
    xValid     : BOOL;               // 输出有效 | outputs valid
    nFaultCode : INT;                // 0=无 / 9611=层号或配置非法 | 0 none, 9611 illegal tier or configuration
END_VAR
VAR
    xFinTierH : BOOL;                // 层高有限性 | tier height is finite
    xFinBase  : BOOL;                // 基础标高有限性 | base elevation is finite
    xFinMaxH  : BOOL;                // 堆高上限有限性 | stack height limit is finite
END_VAR
VAR CONSTANT
    DL_CSH_TOL_M : REAL := 1.0E-6;   // 浮点比较容差 | floating comparison tolerance [m]
END_VAR

// 段1｜非有限闸（R19）
xFinTierH := (rTierHm = rTierHm) AND ((rTierHm - rTierHm) = 0.0);
xFinBase := (rBaseHm = rBaseHm) AND ((rBaseHm - rBaseHm) = 0.0);
xFinMaxH := (rMaxStackHm = rMaxStackHm) AND ((rMaxStackHm - rMaxStackHm) = 0.0);
IF (NOT xFinTierH) OR (NOT xFinBase) OR (NOT xFinMaxH) THEN
    rTopElevM := 0.0;                // 安全值：标高 0 | safe value, zero elevation
    nFreeTier := 0;                  // 安全值：无剩余层 | safe value, no capacity left
    xOverHeight := TRUE;             // 安全值：判超高，禁止堆箱 | safe value, over height so stacking is blocked
    xValid := FALSE;
    nFaultCode := 9611;
    FC_DL_ContainerStackHeightCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：层号范围与几何配置（先判后用）
IF (nMaxTier < 1) OR (nTier < 1) OR (nTier > nMaxTier)
   OR (rTierHm <= 0.0) OR (rMaxStackHm <= 0.0) THEN
    rTopElevM := 0.0;
    nFreeTier := 0;
    xOverHeight := TRUE;
    xValid := FALSE;
    nFaultCode := 9611;
    FC_DL_ContainerStackHeightCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：top = base + (tier-1)*tierH + tierH
rTopElevM := rBaseHm + INT_TO_REAL(nTier - 1) * rTierHm + rTierHm;
nFreeTier := nMaxTier - nTier;                          // 剩余层数（同型整数运算，无跨型转换）| remaining tiers, same integer type
IF nFreeTier < 0 THEN
    nFreeTier := 0;                                     // 保险钳位（段2已保证非负）| defensive clamp
END_IF

// 段4｜超高判定：用未截断的原始标高与限值直接比较
xOverHeight := rTopElevM > (rMaxStackHm + DL_CSH_TOL_M);
nFaultCode := 0;
xValid := TRUE;
FC_DL_ContainerStackHeightCalc := TRUE;
END_FUNCTION
