# R82 编码规格（编码席按序号 1→40 顺序写盘）

**输出目录**：`C:\Library\DL_Process\`（序号 1-22、30-40）、`C:\Library\DL_Device\`（序号 23-29）
**硬度约定**：每件 20~50 行（简单件）/ 120~220 行（复杂件），零占位符，100% 完整可编译。

## 全局硬规则（违者直接拒收）
- R1 零 GVL / 零 VAR_EXTERNAL；R2 零 `%I` `%Q` 物理地址；R3 纯 IEC 61131-3 跨平台语法
- R4 所有除法/开方/对数前必须有分母闸（`ABS(den) > DL_EPS`）与结果域闸（`ABS(x) > DL_FIN`）
- R5 每个变量声明行尾必须带中英双语注释，格式：`x : REAL; // 中文说明 / english note`
- R6 状态机用 ENUM + CASE，CASE 必须有 `ELSE` 兜底转安全态
- R7 TON / R_TRIG 实例必须在每个周期无条件刷新（不得放在 IF 分支内）
- R9 每个 METHOD 必有 END_METHOD（本轮简单件建议不写 METHOD）
- R10 禁用 `LREAL(x)` `DWORD(1)` 这类构造函数式转换，一律 `REAL_TO_LREAL(x)` `INT_TO_DWORD(1)` `INT_TO_UINT(n)` `DINT_TO_REAL(i)`
- R11 所有 VAR 声明以分号结尾（有行尾注释时分号在注释之前）
- R12 ENUM 成员赋值用 `:=`；ENUM 类型只在接口文件/本文件定义一次，不重复定义
- **R14 FB 内禁用 PROPERTY**
- **R15 禁 VLA→VLA 透传**，需数组一律显式定长（如 `ARRAY[0..15] OF REAL`）
- **R509 禁用 `FOR ... DOWNTO`**（RuSTy 1.0.8 报 E007），倒序遍历一律改镜像下标升序：`FOR i := 0 TO n-1 DO idx := (n-1) - i; ... END_FOR`
- **R525 常量命名与单位必须一致**：若常量名含单位语义（如 `DL_RAD_TO_DEG`），其数值必须使「乘该常量」得到目标单位；若算符是除法，常量名必须写成 `DL_DEG_PER_RAD` 形式。本轮所有角度换算统一用 `DL_DEG_PER_RAD : REAL := 57.29577951;` 与 `DL_RAD_PER_DEG : REAL := 0.01745329252;`
- **R526 每个声明的常量必须至少被引用一次**（禁止「声明常量零引用」噪声）
- **R527 分母必须与分子同量纲可消**：投加量、浓度、比值类公式必须写出量纲链注释 `// 量纲: (mg/L)*(m3/h)/1000 = kg/h`
- **R528 状态机必须检查「默认引脚值组合」**：不得因入参默认 0 而绕过握手直达放行相

## 简单件清单（36 件，每件必须 2 个出参：主结果 + `bValid` 有效位；另有 `sMsg` 字符串可选）

| # | 文件名 | 签名要点 | 公式/边界（务必实现） |
|---|---|---|---|
| 1 | `FC_DL_CoagDoseFromJarTest.st` | `FUNCTION FC_DL_CoagDoseFromJarTest : BOOL` IN: `rJarDoseMgL, rFlowM3h, rDoseTrim, rDoseMaxLh` OUT: `rDoseLh, bValid`, `sMsg` | 投加量 L/h = 罐试剂量(mg/L) × 流量(m3/h) / 母液浓度(g/L) / 1000 × 1000；简化：`rDoseLh := rJarDoseMgL * rFlowM3h / rStockGL * rDoseTrim`；限幅 `[0, rDoseMaxLh]`；`rStockGL<=0` → bValid FALSE 码 1；`rFlowM3h<=0` → 码 2；超上限设码 3 并饱和。量纲链注释必写 |
| 2 | `FC_DL_FlocDilutionRatio.st` | 稀释比与配液体积 | IN `rStockPct, rTargetPct, rTankVolL`；OUT `rRatio, rStockVolL, bValid`；`rRatio := rTargetPct / rStockPct`；`rStockVolL := rTankVolL * rRatio`；`rStockPct<=0` 码 1；`rTargetPct>rStockPct` → 码 2（无法稀释到更高浓度）并用 `rStockPct` 饱和 |
| 3 | `FC_DL_SettleVelocityCalc.st` | Stokes 沉降末速度 | IN `rDpUm`（粒径 µm）, `rRhoP`（颗粒密度 kg/m3）, `rRhoF`, `rMuPas`（动力黏度 mPa·s）；OUT `rVsMmS, bValid`；`v = g*d^2*(rhoP-rhoF)/(18*mu)`，d 换成 m、mu 换成 Pa·s；`rMuPas<=0` 码 1；`rRhoP<=rRhoF` → `rVsMmS:=0` 码 2（不上浮，按 0 处理）；Re 校验 `Re=d*v*rhoF/mu > 2` → 码 3（超出 Stokes 域，仍给值但标 bValid FALSE） |
| 4 | `FC_DL_SludgeBlanketLevel.st` | 静压差法泥位 | IN `rP1Bar, rP2Bar, rRhoSludge, rRhoWater, rSpanM`；OUT `rLevelM, bValid`；`dP = (rP2Bar-rP1Bar)*1.0E5`；`h = dP/((rRhoSludge-rRhoWater)*9.80665)`；限幅 `[0, rSpanM]`；`ABS(rRhoSludge-rRhoWater)<1.0` 码 1（密度差过小不可测） |
| 5 | `FC_DL_ClarifierSurfaceLoad.st` | 表面水力负荷 | IN `rFlowM3h, rAreaM2, rLimitM3m2h`；OUT `rLoadM3m2h, bValid, bOver`；`rLoadM3m2h := rFlowM3h/rAreaM2`；`rAreaM2<=0` 码 1；`bOver := rLoadM3m2h > rLimitM3m2h` |
| 6 | `FC_DL_SviCalc.st` | SVI | IN `rSettledVolMl, rMlssMgL`；OUT `rSviMlg, bValid`；`SVI = 沉降体积(mL/L) × 1000 / MLSS(mg/L)`；`rMlssMgL<=0` 码 1；SVI 合理域 40~500，超域标码 2 但 `bValid` 仍 TRUE（仅告警），`rSviMlg` 上限 999 饱和 |
| 7 | `FC_DL_NtuCoagDoseAdj.st` | 浊度反馈微调 | IN `rNtuOut, rNtuSp, rDoseBase, rKp, rStepMax`；OUT `rDoseOut, bValid`；`err := rNtuOut - rNtuSp`；`delta := rKp*err`，限幅 `[-rStepMax, +rStepMax]`；`rDoseOut := rDoseBase + delta`，再限 `[0, 2*rDoseBase]`；`rStepMax<=0` 码 1 |
| 8 | `FC_DL_LamellaAreaCalc.st` | 斜板面积 | IN `rFlowM3h, rVsMmS, rCosTheta, rAreaSafety`；OUT `rAreaM2, bValid`；`A = Q/(Vs*cos) × safety`，Q 换 m3/s、Vs 换 m/s；`rVsMmS<=0` 码 1；`rCosTheta<=0.1` 码 2（倾角过大） |
| 9 | `FC_DL_ScrewPressThroughput.st` | 干固体处理量 | IN `rFlowM3h, rTsPct, rRunHours`；OUT `rDsKgH, rDsKgDay, bValid`；`DS = Q × TS% × 1000/100`；`rTsPct` 域闸 `(0,100]`；`rRunHours` 域闸 `(0,24]` |
| 10 | `FC_DL_CakeSolidsCalc.st` | 泥饼含固率 | IN `rFeedTsPct, rFeedM3h, rCakeM3h`；OUT `rCakeTsPct, rRecoveryPct, bValid`；质量平衡：`cakeTs = feedTs*feedQ/cakeQ`（同密度近似）；`rCakeM3h<=0` 码 1；`rCakeM3h > rFeedM3h` → 码 2（不守恒）；回收率 = `cakeTs*cakeQ/(feedTs*feedQ)*100`，>100 饱和 100 |
| 11 | `FC_DL_PolymerDoseCalc.st` | PAM 投加 | IN `rDsKgH, rDoseKgT, rStockPct`；OUT `rPolyKgH, rPolyLh, bValid`；`polyKgH = DS(t/h) × dose(kg/t)`；`rPolyLh = polyKgH / (rStockPct/100)`（1 kg ≈ 1 L 母液近似，注释声明）；`rStockPct` 域闸 `(0,100]` |
| 12 | `FC_DL_CentrateTurbidityIdx.st` | 离心液浊度指数 | IN `rNtuNow, rNtuBase, rNtuLimit`；OUT `rIdx, bValid, bCarryOver`；`rIdx := rNtuNow / rNtuBase`；`rNtuBase<=0` 码 1；`bCarryOver := rNtuNow > rNtuLimit`（跑料） |
| 13 | `FC_DL_FiltrateRecycleRatio.st` | 滤液回流比 | IN `rFiltrateM3h, rFeedM3h, rFiltrateTsPct`；OUT `rRatio, rSolidRecycleKgH, bValid`；`rRatio := rFiltrateM3h/rFeedM3h`；`rFeedM3h<=0` 码 1；`rRatio>0.5` 码 2（回流过高） |
| 14 | `FC_DL_DewaterMassBalance.st` | 脱水物料平衡 | IN `rFeedM3h, rFeedTsPct, rCakeTsPct`；OUT `rCakeM3h, rFiltrateM3h, rRecoveryPct, bValid`；`cakeQ = feedQ*feedTs/cakeTs`；`filQ = feedQ - cakeQ`；`rCakeTsPct<=0` 或 `rCakeTsPct<=rFeedTsPct` → 码 1；`filQ<0` → 码 2 并置 0 |
| 15 | `FC_DL_BeltPressLoadRate.st` | 带压机比负荷 | IN `rDsKgH, rBeltWidthM, rBeltSpeedMmin`；OUT `rLoadKgM2h, bValid, bOver`；`area = width × speed × 60`（m2/h），`load = DS/area`；分母闸；`rLoadKgM2h > 500` → bOver |
| 16 | `FC_DL_ScrubberLiquidGasRatio.st` | 液气比 | IN `rLiquidM3h, rGasNm3h`；OUT `rLG, rLiquidNeedM3h, bValid, bLow`；`rLG := rLiquidM3h/rGasNm3h`（L/m3 = 1000×）；`rGasNm3h<=0` 码 1；`rLG < 2.0` → bLow |
| 17 | `FC_DL_PackedBedHtu.st` | HTU 与塔高 | IN `rGasKgH, rLiquidKgH, rKgaKmolM3h, rAreaM2, rNtu`；OUT `rHtuM, rHeightM, bValid`；`HTU = G/(Kga × A)`（G 换 kmol/h，注释给分子量 29 假设）；`Z = HTU × NTU × 1.2` 余量；`rKgaKmolM3h<=0` 码 1；`rAreaM2<=0` 码 2 |
| 18 | `FC_DL_ReagentConsumeCalc.st` | 药剂日耗 | IN `rGasNm3h, rInMgNm3, rOutMgNm3, rStoichRatio, rTankKg`；OUT `rKgH, rKgDay, rDaysLeft, bValid`；脱除量 = `(in-out)×Q/1e6 × stoich`（kg/h）；`rTankKg<=0` 码 1，`rDaysLeft` 置 0 |
| 19 | `FC_DL_CatalystActivityDecay.st` | 催化活性衰减 | IN `rDeactBase, rHoursRun, rTempC, rTempRefC, rKt`；OUT `rActivity, rRulHours, bValid`；`k = rDeactBase × EXP(rKt*(T-Tref))`；`act = EXP(-k*hours)`；`act` 限 `[0.0001, 1]`；RUL = 活性降到 0.7 所需小时 `(LN(1/0.7)-(-k*hours))/k`，用 `LN` 前闸 `act>0`；`rDeactBase<=0` 码 1 |
| 20 | `FC_DL_VenturiScrubDpEst.st` | 文丘里压降 | IN `rGasM3h, rThroatDm, rLiquidLM3h, rRhoGas`；OUT `rDpKpa, bValid`；喉速 `v = Q/(3600*A)`；`dP ≈ (rhoGas*v^2/2)*(1+rLiquid*...)`/1000，给出简化式并在注释写明；`rThroatDm<=0` 码 1 |
| 21 | `FC_DL_DemisterVelocityChk.st` | 除雾器流速 | IN `rGasM3h, rAreaM2, rRhoL, rRhoG, rKFactor`；OUT `rVelMs, rVcritMs, bValid, bCarryOver`；`vCrit = K*sqrt((rhoL-rhoG)/rhoG)`；`rRhoG<=0` 码 1；`bCarryOver := rVelMs > rVcritMs` |
| 22 | `FC_DL_StackEmissionDilute.st` | 排放折算 | IN `rMeasMgNm3, rO2MeasPct, rO2RefPct, rMoistPct`；OUT `rDryMgNm3, rRefMgNm3, bValid`；干基 `= meas/(1-moist/100)`；折算 `= dry*(20.9-rO2Ref)/(20.9-rO2Meas)`；`ABS(20.9-rO2Meas)<0.5` 码 1（分母过小）；`rMoistPct` 域闸 `[0,99]` |
| 23 | `FC_DL_ComponentRulEstimate.st` | 剩余寿命外推 | IN `rHealthNow, rHealthPrev, rHoursDelta, rFailThr`；OUT `rRulHours, rSlopePerH, bValid, bAccel`；`slope=(now-prev)/dt`；`dt<=0` 码 1；`ABS(slope)<1e-9` → RUL 置 99999 码 2（无退化）；`rul=(health-failThr)/ABS(slope)`，限 `[0,99999]`；`bAccel := slope < -2*...` 简化：slope 更负于前次号则置位（用固定阈 `-0.001`/h） |
| 24 | `FC_DL_BrgThermalDriftRate.st` | 轴承温升速率 | IN `rTempNow, rTempPrev, rDtMin, rAmbC, rAlarmRisePerMin`；OUT `rRisePerMin, rOverAmbC, bValid, bFastRise`；`dt<=0` 码 1；`rRisePerMin=(now-prev)/dt`；`rOverAmbC = now - amb`；`bFastRise := rRisePerMin > rAlarmRisePerMin` |
| 25 | `FC_DL_OilChangeInterval.st` | 换油周期 | IN `rBaseHours, rLoadFactor, rTempFactor, rContamFactor, rHoursSince`；OUT `rIntervalH, rRemainH, bValid, bDue`；`interval = base*load*temp*contam`；三因子域闸 `(0.1, 5.0]`；`rRemainH := rIntervalH` 减 `rHoursSince`，可为负；`bDue := rRemainH <= 0` |
| 26 | `FC_DL_MtbfCalc.st` | MTBF/可用率 | IN `rRunHours, rFailCount, rRepairHours`；OUT `rMtbfH, rMttrH, rAvailPct, bValid`；`rFailCount < 0` 码 1；`rFailCount = 0` → MTBF 置 `rRunHours` 码 2（无失效样本）；`MTTR = repair/fails`；`avail = MTBF/(MTBF+MTTR)*100` 限 `[0,100]` |
| 27 | `FC_DL_SpareReorderPoint.st` | 备件订货点 | IN `rDailyUse, rLeadDays, rSafetyDays, rOnHand`；OUT `rRop, rShortQty, bValid, bReorder`；`rop = dailyUse*(lead+safety)`；`rDailyUse<0` 码 1；`bReorder := rOnHand <= rRop`；`rShortQty := MAX(0, rRop - rOnHand)` |
| 28 | `FC_DL_PmScheduleNext.st` | 下次 PM 日期 | IN 用 `DT` 类型：`dtLast, dtNow, iIntervalDays`；OUT `dtNext : DT, iOverdueDays : INT, bValid, bOverdue`；Interval 域闸 `(0, 3650]`；`dtNext := dtLast + DWORD_TO_TIME(...)` 写法：`dtNext := dtLast + INT_TO_TIME(iIntervalDays*86400)` 再 `TIME_TO_DT` 不可用时改用 `dtNext := dtLast + DINT_TO_TIME(DINT#86400 * INT_TO_DINT(iIntervalDays))`，务必用 `DT_TO_DATE` 输出辅助；逾期天数 = `DT_TO_DINT(dtNow-dtNext)/86400` 取 MAX(0,...) |
| 29 | `FC_DL_LubeIntervalCalc.st` | 润滑间隔 | IN `rBaseH, rLoadIdx (0~1.5), rTempIdx (0~1.5), rDustIdx (0~1.5)`；OUT `rIntervalH, bValid`；`interval = base/(load*temp*dust)`；三因子各限 `[0.2, 2.0]`；乘积闸 `>0.1` |
| 30 | `FC_DL_BiogasYieldCalc.st` | 沼气产率 | IN `rVsKgDay, rVsDestroyPct, rYieldM3KgVs`；OUT `rGasM3Day, rGasM3h, bValid`；`gas = Vs(kg/d) × destroy% /100 × yield(m3/kgVS)`；`rVsKgDay` 域闸 `>=0`；destroy 域 `(0,100]` |
| 31 | `FC_DL_MethaneRatioCalc.st` | 甲烷含量 | IN `rCo2Pct, rN2Pct, rO2Pct, rH2sPpm`；OUT `rCh4Pct, rLhvMJm3, bValid`；`CH4 = 100 - CO2 - N2 - O2`；和为负码 1；`CH4<0` 饱和 0；LHV ≈ `CH4/100 × 35.8` MJ/m3；H2S 超 500 ppm 置告警码 2 |
| 32 | `FC_DL_OrganicLoadRate.st` | OLR | IN `rFeedM3Day, rCodMgL, rVsTsRatio, rReactorM3`；OUT `rOlrKgVsM3d, rVsKgDay, bValid, bOver`；`Vs = Q × COD(mg/L) × 0.001 × vsTs`（kg/d）；`olr = Vs/reactorM3`；`rReactorM3<=0` 码 1；`rOlrKgVsM3d > 5.0` → bOver |
| 33 | `FC_DL_VfaAlkalinityRatio.st` | VFA/碱度 | IN `rVfaMgL, rAlkMgLcaco3`；OUT `rRatio, bValid, iRisk`；`ratio = vfa/alk`；`rAlkMgLcaco3<=0` 码 1；风险分级：`<0.25` iRisk=0 正常 / `0.25~0.4` =1 关注 / `>0.4` =2 酸化预警 |
| 34 | `FC_DL_GasHolderLevel.st` | 气柜储量 | IN `rPressKpa, rTempC, rVolM3, rLevelPct`；OUT `rNormM3, rEnergyKwh, bValid`；标态折算 `Vn = V*P*273.15/((273.15+T)*101.325)`；`rTempC` 域闸 `> -50`；`rVolM3<=0` 码 1；能量 = `rNormM3 × 0.55 × CH4假设0.6` 简化并在注释声明 |
| 35 | `FC_DL_DigesterRetentionTime.st` | 停留时间 | IN `rReactorM3, rFeedM3Day, rRecycleM3Day`；OUT `rHrtDay, rSrtDay, rLoadingKgM3d, bValid`；`HRT = V/Q`；`Q<=0` 码 1；`SRT = V/(Q*frac)`，frac 用 `rRecycleM3Day` 作废弃污泥流量：`SRT=V/(recycle+feed*0.02)`；`rSrtDay<HRT` → 码 2（不可能，饱和到 HRT） |
| 36 | `FC_DL_FlareFlowSizing.st` | 火炬 sizing | IN `rMaxGasM3h, rPressBar, rTempC, rVelLimitMs`；OUT `rDiaM, rVelMs, bValid, bOver`；`Q = maxGas/3600 * (1.01325/press) * ((273.15+T)/273.15)` 实况；`dia = SQRT(4*Q/(PI*vel))`；`rVelLimitMs<=0` 码 1；`rPressBar<=0` 码 2 |

## 复杂件清单（4 件，120~220 行，FB + ENUM 状态机 + CASE ELSE 兜底）

### 37 `FB_DL_CoagDoseJarTestSeq`（C4）
工况：水厂混凝加药闭环。前馈按进水浊度查投加基准，烧杯试验结果到达后修正基准，沉后浊度复核超限则触发再整定。
- IN：`bEnable, bReset, bJarResultReady, rJarResultMgL, rInNtu, rOutNtu, rOutNtuSp, rFlowM3h, rStockGL, rDoseMaxLh, tSettleTime, tVerifyTimeout`
- OUT：`rDoseLh, bDoseOn, iErrCode, sMsg`
- ENUM `E_DL_COAG_STATE := (eIdle := 0, eFeedForward := 1, eJarTestWait := 2, eTrim := 3, eVerify := 4, eHold := 5, eFault := 6)`
- 相序：eIdle → （bEnable 沿）eFeedForward（按 rInNtu 分段给基准，3 段阈值 20/50 NTU）→ eJarTestWait（等 `bJarResultReady` 沿，超时 `tVerifyTimeout` 转 eFault 码 11 但**保持当前投加量**不掉零）→ eTrim（用 `rJarResultMgL` 修正基准，限幅 ±20%/次）→ eVerify（等 `tSettleTime` 后比较 `rOutNtu` 与 `rOutNtuSp`，超 1.15 倍回 eTrim，最多 3 次循环，超次转 eHold 码 12）→ eHold（保持最后有效投加，`bReset` 沿回 eIdle）
- 必含：`bReset` 用 R_TRIG 沿判据；`tSettleTime`/`tVerifyTimeout` 两个 TON 无条件刷新；每次相迁移记录 `_rDoseLastGood`；除零闸每处；默认引脚全 0 时必须停在 eIdle 不直达 eFeedForward

### 38 `FB_DL_ScrewPressDewaterSeq`（C4）
工况：污泥螺旋压榨脱水机单循环。进泥 → 加药混合 → 压榨 → 冲洗 → 退让复位。
- IN：`bStart, bStop, bReset, bFeedOk, bPolyOk, bPressHigh, bPressFault, rCakeTsPct, rCakeTsSp, tFeed, tMix, tPress, tFlush, tRetract`
- OUT：`bFeedValve, bPolyPump, bPressMotor, bFlushValve, iErrCode, sMsg`
- ENUM `E_DL_SPR_STATE := (eIdle, eFeed, eMix, ePress, eFlush, eRetract, eFault)`
- 相序与互锁：eFeed 要求 `bFeedOk AND bPolyOk`，缺料转 eFault 码 21；ePress 期间 `bPressHigh` 持续 `tPress` 的 30% 以上 → 提前转 eFlush 码 22（过压保护，安全侧）；`bPressFault` 任意相 → eFault 码 23 并**立即断 bPressMotor**；eFault 必须有出口（`bReset` 沿且 `bPressFault` 消失才回 eIdle）；`bStop` 任意相 → eRetract
- 必含：单稳态输出每拍重算（不锁存）；`tPress` 相内 PT 域间不等式断言注释 `// 约束: tPress > tMix`；所有输出在 eFault 全部 FALSE

### 39 `FB_DL_ScrubberReagentDoseSeq`（C4）
工况：湿式洗涤塔碱液投加闭环。pH 反馈调节计量泵，循环液电导超限触发补排水，药剂罐耗尽锁停。
- IN：`bEnable, bReset, rPh, rPhSp, rCondMsCm, rCondHi, rTankPct, rTankLoPct, rPumpMaxLh, tPhStable, tTankLowDelay`
- OUT：`rPumpLh, bPumpOn, bMakeupValve, bDrainValve, iErrCode, sMsg`
- ENUM `E_DL_SCRUB_STATE := (eIdle, eDose, eStabilize, eBlowdown, eTankLow, eFault)`
- 相序：eIdle（bEnable 沿且 `rTankPct > rTankLoPct` 才进 eDose，否则 eTankLow 码 31）→ eDose（PI 简化：`pump = kp*err + ki*integ`，integ 抗饱和限幅，`pump` 限 `[0, rPumpMaxLh]`）→ eStabilize（pH 进 `rPhSp±0.2` 并持续 `tPhStable` 后回 eDose 的保持态或转 eBlowdown）→ eBlowdown（`rCondMsCm > rCondHi` 触发，开补排，pH 恢复后回 eDose）→ eTankLow（泵停、告警，`rTankPct` 恢复 > lo+5% 才回 eDose）
- 必含：`integ` 必须显式清零条件（eIdle/eFault/eTankLow 进相即清）；`rTankPct` 下降速率 > 5%/min 且泵在开 → 码 32 泄漏疑似；除零闸在 `rCondHi<=0` 与 `rPumpMaxLh<=0`；`tPhStable`/`tTankLowDelay` 无条件刷新

### 40 `FB_DL_AnaerobDigesterLoadCtrl`（C4）
工况：厌氧消化罐进料负荷控制。VFA/碱度比越限降载，产气量骤降联动降载，恢复需两级确认。
- IN：`bEnable, bReset, rVfaMgL, rAlkMgL, rGasM3h, rGasBaseM3h, rFeedM3h, rFeedMaxM3h, rStepDownPct, tConfirm, tRecover`
- OUT：`rFeedOutM3h, bFeedOn, iLoadLevel : INT, iErrCode, sMsg`
- ENUM `E_DL_AD_STATE := (eIdle, eNormal, eWatch, eDerate, eRecover, eFault)`
- 逻辑：`ratio = vfa/alk`（除零闸）；`ratio>0.4` → eDerate 每次降 `rStepDownPct`（默认 10%），下限 20% 流量；`ratio 0.25~0.4` → eWatch 保持不增；`gas < 0.7*base` 且 `ABS(base)>FIN` 连续 `tConfirm` → 直接 eDerate 码 41；eDerate 后 ratio 回 <0.25 且产气回 >0.9*base 持续 `tRecover` → eRecover（每 `tRecover` 升 5%，最多回到 100%）→ eNormal
- 必含：`iLoadLevel` 0~10 级显式映射；`bReset` 沿回 eIdle 且流量归 0；两级确认（必须连续两个 `tConfirm` 窗都不越限才降级），防抖；`tConfirm`/`tRecover` 无条件刷新；越限降载路径必须是安全侧（先降后报）

## 溯源头（file header 必写，简单件照此格式）
```
(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_XxxYyy
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
*)
```
