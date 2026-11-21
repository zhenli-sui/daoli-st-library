(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TankFarmInventory
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（Building 族借形 + 规划新增线）
 * 所属子库 (Sublibrary) : DL_Process / Inventory
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 罐区库存计量
 * 功能一句话 (Summary)  : 液位经罐表插值转体积，温度补偿后计质量，多罐合计。
 * 边界与安全 (Boundary) : ①罐表点数不足或未升序 → 该罐错误标志并跳过；
 *                         ②密度小于 0.5 g/cm3 或样本非有限（液位/密度/温度 NaN、Inf）
 *                           拒收该样本（保持上拍质量，防毒化保持槽与合计）；
 *                         ③液位界外钳端点插值；
 *                         ④质量含固定热膨胀系数 0.0006 每摄氏度补偿
 *                           （电解液典型值，文件头注记：规格未给系数按红线自裁定）；
 *                         ⑤数组下标全程钳位（禁越界访问）。
 * 错误码    : 16#0005_0363 罐表非法（点数不足或未升序）——故障级（持续态）
 *             16#0005_0364 密度拒收（低于 0.5 或非有限）——故障级（持续态）
 * 码位总账  : 16#0005_0363 用 / 16#0005_0364 用
 * 修改记录  : v1.0.0 R26 初版
 *             v1.0.1 R26 终审修复：新增非有限结果闸——NaN 液位/温度曾可穿透插值
 *             与温补链路，把 NaN 写入 fMassKeep 毒化保持槽与罐区合计（永久 NaN）
 *==============================================================================*)
TYPE ST_DL_TankPoint :
STRUCT
    fLevel    : LREAL;              // 罐液位 [%] / Tank level [%]
    fDensity  : LREAL;              // 介质密度 [kg/L] / Medium density [kg/L]
    fTemp     : LREAL;              // 介质温度 [℃] / Medium temperature [degC]
    aStrapLvl : ARRAY[0..19] OF LREAL; // 罐表液位锚点 [%] / Strapping level anchors [%]
    aStrapVol : ARRAY[0..19] OF LREAL; // 罐表体积锚点 [m3] / Strapping volume anchors [m3]
    nStrapPts : DINT;               // 罐表有效点数 / Valid strapping point count
    fMassKeep : LREAL;              // 该罐上拍质量保持槽 [t] / Per-tank mass hold slot [t]
    bErrKeep  : BOOL                // 该罐错误保持槽 / Per-tank error hold slot
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_TankFarmInventory
VAR_IN_OUT
    aTanks : ARRAY[*] OF ST_DL_TankPoint; // 罐位数据表 / Tank data table
END_VAR
VAR_OUTPUT
    aVolume   : ARRAY[*] OF LREAL; // 各罐体积 [m3] / Per-tank volume [m3]
    aMass     : ARRAY[*] OF LREAL; // 各罐质量 [t] / Per-tank mass [t]
    fTotalMass: LREAL; // 罐区合计质量 [t] / Farm total mass [t]
    abTankErr : ARRAY[*] OF BOOL; // 各罐错误标志 / Per-tank error flags
    eErr      : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cMaxPts   : DINT  := 20;   // 罐表容量上限 / Strapping capacity limit
    cDensMin  : LREAL := 0.5;  // 密度下限 [kg/L] / Density lower bound
    cExpCoef  : LREAL := 0.0006; // 固定热膨胀补偿系数 [1/℃] / Fixed expansion coefficient
    cTempRef  : LREAL := 20.0; // 补偿基准温度 [℃] / Compensation reference temperature
END_VAR
VAR
    iTanks : INT;  // 罐数 / Tank count
    i      : INT;  // 罐游标 / Tank cursor
    j      : INT;  // 罐表游标 / Strapping cursor
    nPts   : DINT; // 本罐表点数 / This tank point count
    bStrapOk: BOOL; // 本罐表合法性 / This tank strapping legality
    fLvl   : LREAL; // 液位守卫副本 / Level guard copy
    fDen   : LREAL; // 密度守卫副本 / Density guard copy
    fVol   : LREAL; // 插值体积临时量 / Interpolated volume temp
    fDen2  : LREAL; // 段宽临时量 / Segment width temp
    fRatio : LREAL; // 插值比例 / Interpolation ratio
END_VAR

// ---------- 周期起点：错误码与合计先清 ----------
eErr := 0;
fTotalMass := 0.0;

iTanks := UPPER_BOUND(aTanks, 1) + 1;         // 罐数 / Tank count

FOR i := 0 TO iTanks - 1 DO
    // ---------- 逐罐处理（下标全程钳位） ----------
    abTankErr[i] := FALSE;
    fLvl := aTanks[i].fLevel;                 // 液位守卫副本 / Level guard
    fDen := aTanks[i].fDensity;               // 密度守卫副本 / Density guard

    // ---------- 罐表合法性：点数与单调性 ----------
    nPts := aTanks[i].nStrapPts;
    IF nPts > cMaxPts THEN
        nPts := cMaxPts;                      // 点数钳上限 / Clamp point count
    END_IF
    bStrapOk := nPts >= 2;
    IF bStrapOk THEN
        FOR j := 0 TO INT_TO_DINT(nPts) - 2 DO
            IF NOT (aTanks[i].aStrapLvl[DINT_TO_INT(j)] < aTanks[i].aStrapLvl[DINT_TO_INT(j) + 1]) THEN
                bStrapOk := FALSE;            // 单调性破坏 / Monotonicity violated
            END_IF
        END_FOR
    END_IF
    IF NOT bStrapOk THEN
        abTankErr[i] := TRUE;                 // 该罐错误标志 / Tank error flag
        eErr := 16#0005_0363;                 // 罐表非法码 / Illegal strapping code
        aVolume[i] := 0.0;
        aMass[i] := aTanks[i].fMassKeep;      // 跳过：保持上拍质量 / Skipped: hold last mass
        fTotalMass := fTotalMass + aMass[i];  // 保持值入合计 / Held value into total
        aTanks[i].bErrKeep := TRUE;
    ELSE
        // ---------- 液位界外钳端点插值 ----------
        IF fLvl <= aTanks[i].aStrapLvl[0] THEN
            fVol := aTanks[i].aStrapVol[0];   // 界下钳首点 / Clamp to first
        ELSIF fLvl >= aTanks[i].aStrapLvl[DINT_TO_INT(nPts) - 1] THEN
            fVol := aTanks[i].aStrapVol[DINT_TO_INT(nPts) - 1]; // 界上钳末点 / Clamp to last
        ELSE
            j := 0;
            WHILE (DINT_TO_INT(j) < DINT_TO_INT(nPts) - 2)
              AND (fLvl > aTanks[i].aStrapLvl[DINT_TO_INT(j) + 1]) DO
                j := j + 1;                   // 定位段 / Locate segment
            END_WHILE
            fDen2 := aTanks[i].aStrapLvl[DINT_TO_INT(j) + 1] - aTanks[i].aStrapLvl[DINT_TO_INT(j)];
            IF fDen2 > 0.0 THEN
                fRatio := (fLvl - aTanks[i].aStrapLvl[DINT_TO_INT(j)]) / fDen2; // 除法前判零 / Zero-guarded
                fVol := aTanks[i].aStrapVol[DINT_TO_INT(j)]
                      + fRatio * (aTanks[i].aStrapVol[DINT_TO_INT(j) + 1] - aTanks[i].aStrapVol[DINT_TO_INT(j)]);
            ELSE
                fVol := aTanks[i].aStrapVol[DINT_TO_INT(j)]; // 零段宽防御 / Zero-width defensive
            END_IF
        END_IF
        aVolume[i] := fVol;                   // 体积输出 / Volume output

        // ---------- 密度防御与质量计算 ----------
        IF (fDen < cDensMin) OR (fDen <> fDen) OR ((fDen - fDen) <> (fDen - fDen)) THEN
            abTankErr[i] := TRUE;             // 密度拒收标志 / Density rejected flag
            eErr := 16#0005_0364;             // 密度拒收码 / Density rejection code
            aMass[i] := aTanks[i].fMassKeep;  // 拒收保持上拍质量 / Hold last mass
        ELSE
            aMass[i] := fVol * fDen * (1.0 - cExpCoef * (aTanks[i].fTemp - cTempRef)); // 温补质量 / Compensated mass
            IF (aMass[i] <> aMass[i]) OR ((aMass[i] - aMass[i]) <> (aMass[i] - aMass[i])) THEN
                // 非有限结果闸：NaN 液位/温度泄漏拒收样本，防毒化保持槽与合计 / Non-finite result gate
                aMass[i] := aTanks[i].fMassKeep;  // 拒收保持上拍质量 / Rejected: hold last mass
                abTankErr[i] := TRUE;             // 样本拒收标志 / Sample rejected flag
                eErr := 16#0005_0364;             // 样本拒收码（非有限归同一码位）/ Sample rejection code
            ELSIF aMass[i] < 0.0 THEN
                aMass[i] := 0.0;              // 过补偿负值钳零 / Over-compensation clamp
                aTanks[i].fMassKeep := aMass[i];  // 更新保持槽 / Update hold slot
            ELSE
                aTanks[i].fMassKeep := aMass[i];  // 更新保持槽 / Update hold slot
            END_IF
        END_IF
        fTotalMass := fTotalMass + aMass[i];  // 合计累加 / Total accumulation
        aTanks[i].bErrKeep := FALSE;
    END_IF
END_FOR

END_FUNCTION_BLOCK
