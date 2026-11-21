# DISPATCH_R29（派单：20 件可编码契约）

> 面向：PLC 编码专家 ｜ 依据：`ROUND_PLAN_R29.md` ｜ 日期：2026-11-17 ｜ 轮次 R29
> 编码前置铁律：文件名 = POU 名（含前缀，前缀须与 POU 实际类型一致）；每件落 `.st` 单文件；头部注释块必须含「组件名称 / 所属子库 / 版本 v1.0.0 / 兼容性 / 功能描述 / 开源溯源与合规 / 修订历史」七段。

## 0 样板（照抄，禁止漂移 — R50 教训）

```
// 变量注释一律行尾双斜杠 + 中英双语，例：bEnable : BOOL := TRUE;   // 使能 / Enable
// 错误码一律 eErr : UDINT，常量形如 16#0001_0A01（信息级）/ 16#0002_0A01（故障级）
// 禁止 (* *) 块注释（嵌套风险），禁止中文全角标点
```

枚举样板（R33 教训），成员一律 `:=` 赋值，**禁止单冒号**，`CASE` 必须带 `ELSE` 兜底：

```iecst
TYPE E_DL_Xxx :
(
    eIdle  := 0,    // 空闲 / Idle
    eRun   := 1,    // 运行 / Running
    eFault := 99    // 故障 / Fault
);
END_TYPE
```

**码位分档口径（全 20 件统一）**：每件 5 槽，槽 1 = 正常/信息级（每拍必写，供上位判活）；槽 2~3 = 故障级（置 `bError` 并锁存）；槽 4 = 信息级钳制/降级（**不置 `bError`**）；槽 5 = 组态错故障级（参数非法，静态可判）。`eErr` 每拍无条件刷新，锁存解除点必须在 `bReset` 或故障源消失的同一拍写明。

**全件通用防御三闸**（每件代码首部无条件执行，无需在表中重复）：
1. `bEnable = FALSE` → 全部输出回安全默认、`eErr` 保持槽 1 或静态错码，`TON`/`R_TRIG` 仍每拍刷新（R46 末拍快照纪律）；
2. 所有 REAL 输入做 `bIsFinite` 等价闸（`x = x` 且 `ABS(x) < 1.0E12`），NaN/±Inf → 槽 2 并走安全侧；
3. 除法/开方/比值前做分母下限闸（`ABS(den) < 1.0E-9` → 槽 2，禁止裸除）。

---

## 批次 1（Level 0 数学 + 纯滞后/多区算法）

### 1 · `FC_DL_GasFlowSqrt`（DL_MathData / FC / 16#0001_047B~047F / roadmap-L645 / T1-1◐ / 复杂度 3）

**功能语义**：差压式气体流量换算纯函数。正常路径：差压 `fDp_Pa` 经开方 → 乘流量系数 `fKFactor` → 乘温压补偿因子 `sqrt((P/Pref)*(Tref/T))`（绝对温标 K）→ 输出工况流量与参比流量。边界：差压 ≤ 死区 `fDpMin_Pa` 直接输出 0 并置标记（噪声开方会造出虚假小流量）；差压 < 0 视为接线反接 → 故障级；结果超量程上限 → 钳制 + 信息级；密度/温度参比 ≤ 0 → 故障级并保持输出 0（函数无状态，不得沿用上次值）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := TRUE;` | 使能，FALSE 时输出全 0 / Enable |
| IN | `fDp_Pa : REAL := 0.0;` | 实测差压 0~250000 Pa / Differential pressure |
| IN | `fKFactor : REAL := 1.0;` | 流量系数 0.001~100（含管道/孔板系数）/ Flow coefficient |
| IN | `fRhoRef_kgm3 : REAL := 1.2041;` | 参比密度 >0 kg/m³ / Reference density |
| IN | `fTRef_C : REAL := 20.0;` | 参比温度 -50~200 ℃ / Reference temperature |
| IN | `fTNow_C : REAL := 20.0;` | 当前温度 -50~200 ℃ / Actual temperature |
| IN | `fPRef_kPa : REAL := 101.325;` | 参比绝压 >0 kPa / Reference absolute pressure |
| IN | `fPNow_kPa : REAL := 101.325;` | 当前绝压 >0 kPa / Actual absolute pressure |
| IN | `fDpMin_Pa : REAL := 50.0;` | 开方死区 0~5000 Pa / Square-root dead band |
| IN | `fFlowMax_m3h : REAL := 100000.0;` | 量程上限 >0 m³/h / Full-scale flow |
| OUT | `fFlow_m3h : REAL;` | 工况流量 m³/h / Actual flow |
| OUT | `fFlowRef_m3h : REAL;` | 参比工况流量 m³/h / Reference flow |
| OUT | `bLowCut : BOOL;` | 死区截断生效 / Dead-band cut active |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0001_047B` | 信息 | 正常换算完成 |
| 2 | `16#0001_047C` | 故障 | 差压 < 0 或任一输入非有限 |
| 3 | `16#0001_047D` | 故障 | `fRhoRef_kgm3 ≤ 0` / `fPRef_kPa ≤ 0` / `fTRef_C ≤ -273.15` / `fTNow_C ≤ -273.15` |
| 4 | `16#0001_047E` | 信息 | 结果超 `fFlowMax_m3h` 已钳制 / 差压落在死区（`bLowCut` 同拍置 TRUE） |
| 5 | `16#0001_047F` | 故障 | `fKFactor ≤ 0` 或 `fFlowMax_m3h ≤ 0`（组态错） |

**防御**：死区判在开方前；温度转 K 后钳下限 1.0 K 防除零；`fDpMin_Pa < 0` 按 0 处理（不置错，属可容忍组态抖动）；`fFlowRef_m3h` 由 `fFlow_m3h × sqrt(rhoNow/rhoRef)` 得，rhoNow 非法时直接复制 `fFlow_m3h` 并置槽 2。
**依赖**：无（纯函数，不引用其他 DL_ 件；开方用标准 `SQRT`，**禁止**引入 `FC_DL_NthRoot` 造成 Level0 内部耦合）。
**验收**：
1. `fDp=10000 Pa, fK=0.05, T=P=参比` → `fFlow_m3h = 0.05×100 = 5.0`，槽 1。
2. `fDp = 30 Pa`（< 死区 50）→ `fFlow_m3h = 0.0`、`bLowCut = TRUE`、槽 4、`eErr` 不置故障级。
3. 反向：`fDp = -200 Pa` → 输出 0、槽 2（**不得**取绝对值后照算）。

### 2 · `FC_DL_CpkCalc`（DL_MathData / FC / 16#0001_0480~0484 / 自研 SPC·T2-8◐ / 复杂度 3）

**功能语义**：由外部统计量算过程能力指数。`Cp = (USL-LSL)/(6σ)`、`Cpu=(USL-μ)/(3σ)`、`Cpl=(μ-LSL)/(3σ)`、`Cpk=MIN(Cpu,Cpl)`。正常路径输出四值与 `bCapable`（`Cpk ≥ fCpkMin`）。边界：`σ ≤ σMin` → 退化（数据全同，Cp 记 999.0 哨兵 + 信息级，不得报除零）；`USL ≤ LSL` → 组态错；样本数 < `uSampleMin` → 不给结论（`bValid=FALSE`，输出保持 0）；Cpk 为负（均值越界）→ 照实输出负值，**禁止钳零**（钳零会掩盖偏移）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := TRUE;` | 使能 / Enable |
| IN | `fMean : REAL := 0.0;` | 样本均值（工程单位）/ Sample mean |
| IN | `fSigma : REAL := 0.0;` | 样本标准差 ≥0（同单位）/ Sample sigma |
| IN | `fUsl : REAL := 100.0;` | 规格上限 / Upper spec limit |
| IN | `fLsl : REAL := 0.0;` | 规格下限 / Lower spec limit |
| IN | `uSampleCount : UDINT := 0;` | 样本数 / Sample count |
| IN | `uSampleMin : UDINT := 25;` | 最小样本数 5~1000 / Minimum sample count |
| IN | `fSigmaMin : REAL := 1.0E-6;` | σ 下限 >0（退化判据）/ Sigma floor |
| IN | `fCpkMin : REAL := 1.33;` | 合格门限 0.5~3.0 / Capability threshold |
| OUT | `fCp : REAL;` | 潜在能力 / Potential capability |
| OUT | `fCpu : REAL;` | 上侧能力 / Upper capability |
| OUT | `fCpl : REAL;` | 下侧能力 / Lower capability |
| OUT | `fCpk : REAL;` | 实际能力 / Actual capability |
| OUT | `bValid : BOOL;` | 结论有效 / Result valid |
| OUT | `bCapable : BOOL;` | 达门限 / Capable |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0001_0480` | 信息 | 计算完成且结论有效 |
| 2 | `16#0001_0481` | 故障 | `fMean`/`fSigma`/`fUsl`/`fLsl` 非有限，或 `fSigma < 0` |
| 3 | `16#0001_0482` | 故障 | `fUsl ≤ fLsl`（组态错），或 `fSigmaMin ≤ 0` |
| 4 | `16#0001_0483` | 信息 | 退化：`fSigma < fSigmaMin` → Cp/Cpk 置 999.0 哨兵、`bValid=FALSE` |
| 5 | `16#0001_0484` | 信息 | 样本不足：`uSampleCount < uSampleMin` → 输出全 0、`bValid=FALSE` |

**防御**：`3σ` 与 `6σ` 同为除零热点 → 先钳 σ 下限再除；`fCpkMin` 非有限按 1.33 兜底（不置错，属上位下发脏值）；输出不做任何钳制，仅 `bValid=FALSE` 时清零。
**依赖**：无。
**验收**：
1. `μ=50, σ=2, USL=60, LSL=40, N=100` → `Cp=1.667, Cpk=1.667, bCapable=TRUE`。
2. `μ=58, σ=2`（同规格）→ `Cpu=0.333, Cpl=3.667, Cpk=0.333, bCapable=FALSE`。
3. 反向：`σ=0` → `fCp=999.0`、`bValid=FALSE`、槽 4，且**不得**出现除零异常码。

### 3 · `FC_DL_PipeFrictionLoss`（DL_MathData / FC / 16#0001_0485~0489 / 自研流体·T1-1◐ / 复杂度 4）

**功能语义**：Darcy-Weisbach 压降纯函数。`v = Q/(3600·π·d²/4)`；`Re = v·d·ρ/μ`；层流（`Re < 2300`）`λ = 64/Re`，湍流用 Swamee-Jain 显式式 `λ = 0.25/[log10(ε/(3.7d) + 5.74/Re^0.9)]²`；`Δp = (λ·L/d + ΣK)·ρ·v²/2`。边界：`Re` 落在 2300~4000 过渡区 → 按湍流式算 + 信息级提示（不中断）；`Re` 极小 → 钳 1.0 防 `1/Re^0.9` 溢出；`d ≤ 0`/`μ ≤ 0`/`ρ ≤ 0` → 故障级。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := TRUE;` | 使能 / Enable |
| IN | `fFlow_m3h : REAL := 0.0;` | 体积流量 ≥0 m³/h / Volumetric flow |
| IN | `fDia_mm : REAL := 50.0;` | 内径 >0 mm / Inner diameter |
| IN | `fLen_m : REAL := 10.0;` | 直管长度 ≥0 m / Straight length |
| IN | `fRough_mm : REAL := 0.05;` | 绝对粗糙度 ≥0 mm（不锈钢 0.05）/ Absolute roughness |
| IN | `fRho_kgm3 : REAL := 1000.0;` | 密度 >0 kg/m³ / Density |
| IN | `fMu_cP : REAL := 1.0;` | 动力粘度 >0 cP（水 20℃ 约 1.0）/ Dynamic viscosity |
| IN | `fKMinor : REAL := 0.0;` | 局部阻力系数和 ≥0 / Minor loss coefficient sum |
| IN | `fDpMax_kPa : REAL := 1000.0;` | 压降量程上限 >0 kPa / Pressure drop full scale |
| IN | `fReLam : REAL := 2300.0;` | 层流临界雷诺数 / Laminar critical Re |
| IN | `fReTurb : REAL := 4000.0;` | 湍流起始雷诺数 / Turbulent onset Re |
| OUT | `fVel_ms : REAL;` | 流速 m/s / Velocity |
| OUT | `fRe : REAL;` | 雷诺数 / Reynolds number |
| OUT | `fLambda : REAL;` | 沿程阻力系数 / Friction factor |
| OUT | `fDp_kPa : REAL;` | 总压降 kPa / Total pressure drop |
| OUT | `bTransition : BOOL;` | 处于过渡区 / In transition zone |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0001_0485` | 信息 | 正常计算完成 |
| 2 | `16#0001_0486` | 故障 | `fDia_mm ≤ 0` / `fMu_cP ≤ 0` / `fRho_kgm3 ≤ 0`，或任一输入非有限 |
| 3 | `16#0001_0487` | 故障 | `fReLam ≤ 0` / `fReTurb ≤ fReLam` / `fRough_mm < 0` / `fKMinor < 0`（组态错） |
| 4 | `16#0001_0488` | 信息 | 过渡区（`fReLam ≤ Re ≤ fReTurb`）→ 按湍流式 + `bTransition=TRUE`；或 `fDp_kPa` 超上限已钳制 |
| 5 | `16#0001_0489` | 信息 | 零流量（`fFlow_m3h ≤ 0`）→ 三项输出 0、`bTransition=FALSE` |

**防御**：`log10` 参数下限钳 `1.0E-6`；`Re^0.9` 在 Re=0 无定义 → Re 钳 1.0；`fDpMax_kPa ≤ 0` 按 1000.0 兜底；`fLen_m < 0` 按 0 处理并置槽 3。
**依赖**：无（自带开方与对数，禁止跨库调用 `FC_DL_FlowCompensate`）。
**验收**：
1. `Q=10 m³/h, d=50 mm, ρ=1000, μ=1.0, L=10, ε=0.05, K=0` → `v≈1.415 m/s, Re≈70700, λ≈0.0212, Δp≈4.2 kPa`（±5% 容差），槽 1。
2. `Q=0.1 m³/h` 同参数 → `Re≈707`（层流）`λ = 64/707 ≈ 0.0905`，`bTransition=FALSE`。
3. 反向：`d=0` → 三输出 0、槽 2，且不得抛除零。

### 4 · `FB_DL_CoatingThicknessCtrl`（DL_Algo / FB / 16#0002_371A~371E / roadmap-L208 / T2-2◐ / 复杂度 5）

**功能语义**：涂布面密度（β 射线/红外测厚）闭环。正常路径：测厚值经一阶滤波 → 与设定值偏差 → 纯滞后补偿（延时队列按 `tDeadTime` 延迟偏差）→ 积分型无差调节 → 换算成模头间隙增量 → 增量限速（`fRateMax_mm_s`）与总量限幅（`fTrimMax_mm`）→ 输出间隙命令。边界：测厚无效（`bMeasValid=FALSE`）→ 冻结积分、输出保持（绝不因无测量而推进）；间隙触限 → 停止同向积分（抗饱和）并置信息级；偏差在 `fBandPct` 内 → 不动作（防抖动磨模头）。

**状态机**：`E_DL_CoatingState : ( eIdle := 0, eRun := 1, eLimit := 2, eFault := 99 )`，`CASE` 带 `ELSE`。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能，FALSE 冻结输出 / Enable |
| IN | `bStart : BOOL := FALSE;` | 上升沿投入闭环 / Start on rising edge |
| IN | `bReset : BOOL := FALSE;` | 复位故障，仅 `eFault` 生效 / Fault reset |
| IN | `bMeasValid : BOOL := FALSE;` | 测厚数据有效 / Measurement valid |
| IN | `fMeas_gsm : REAL := 0.0;` | 实测面密度 0~500 g/m² / Measured coat weight |
| IN | `fSp_gsm : REAL := 120.0;` | 面密度设定 1~500 g/m² / Setpoint |
| IN | `fBandPct : REAL := 0.5;` | 死区带 0~5 % / Dead band |
| IN | `fGain_mm_per_gsm : REAL := 0.01;` | 间隙-面密度增益 0.0001~1 mm/(g/m²) / Gap gain |
| IN | `fGapInit_mm : REAL := 0.250;` | 初始间隙 0.05~2.0 mm / Initial gap |
| IN | `fTrimMax_mm : REAL := 0.100;` | 相对初始间隙最大修正 0.001~1.0 mm / Max trim |
| IN | `fRateMax_mm_s : REAL := 0.005;` | 修正速率上限 >0 mm/s / Trim rate limit |
| IN | `tDeadTime : TIME := T#30S;` | 纯滞后 T#1S~T#300S / Dead time |
| IN | `tCycle : TIME := T#100MS;` | 采样周期 T#10MS~T#5S / Sample cycle |
| OUT | `fGapCmd_mm : REAL;` | 模头间隙命令 0.05~2.0 mm / Gap command |
| OUT | `fDev_gsm : REAL;` | 滞后补偿后偏差 g/m² / Delayed deviation |
| OUT | `fTrim_mm : REAL;` | 当前累计修正 mm / Accumulated trim |
| OUT | `bInBand : BOOL;` | 偏差在带内 / Within dead band |
| OUT | `bActive : BOOL;` | 闭环投入中 / Loop active |
| OUT | `eState : E_DL_CoatingState;` | 状态 / State |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0002_371A` | 信息 | 闭环运行正常 / 带内不动作 |
| 2 | `16#0002_371B` | 故障 | 输入非有限，或 `tDeadTime`/`tCycle` 非法（0 或超出域） |
| 3 | `16#0002_371C` | 故障 | `fGain_mm_per_gsm ≤ 0` / `fTrimMax_mm ≤ 0` / `fRateMax_mm_s ≤ 0` / `fSp_gsm ≤ 0`（组态错） |
| 4 | `16#0002_371D` | 信息 | 修正触限（`ABS(fTrim_mm) ≥ fTrimMax_mm`）→ 停止同向积分，`eState=eLimit` |
| 5 | `16#0002_371E` | 信息 | 测厚无效（`bMeasValid=FALSE`）→ 冻结积分、输出保持、`bActive=FALSE` |

**防御**：延时队列长度 = `CEIL(tDeadTime/tCycle)`，上限 3000 拍（超限按 3000 并置槽 2，防内存爆）；首次扫描 `fGapCmd_mm := fGapInit_mm`（R16 首扫纪律）；`tCycle` 变化时清空队列并重新填充当前偏差（不留历史脏值）；`bStart` 上升沿才从 `eIdle → eRun`，非沿不重复初始化。
**依赖**：无外部件；滤波用内联一阶（`fAlpha` 提为内部常量 0.2，不越层调 `FB_DL_LowPassFilter`）。
**验收**：
1. `fSp=120, fMeas=118（稳定）`, `fGain=0.01`, `dead=30s`, 周期 100ms 运行 60s → `fGapCmd_mm` 单向增大且速率 ≤ 0.005 mm/s，`fTrim_mm` 收敛到 ≈ +0.020 mm。
2. `fMeas` 一直 = 120 ±0.3（带内 0.5%）→ `bInBand=TRUE`、`fGapCmd_mm` 保持 `fGapInit_mm` 不变、槽 1。
3. 反向：`bMeasValid=FALSE` 且测厚仍持续 130 → `fGapCmd_mm` **不得**继续变化，槽 5。

### 5 · `FB_DL_DryingOvenZone`（DL_Algo / FB / 16#0002_371F~3723 / roadmap-L211 / T1-1◐ / 复杂度 4）

**功能语义**：烘箱 8 温区串级控温。主环按各区偏差出加热百分比，副环按风量百分比做前馈增益修正（风量越大热损越大 → 给定补偿）；每区独立使能与独立超温联锁。正常路径：`eRun` 下逐区计算 `fOut_pct` 并做斜坡限速。边界：任一区 `fPv_C ≥ fOvertemp_C` → 全区输出清零 + 故障锁存（超温优先于调节，绝不"边降温边加热"）；`bFanRun=FALSE` → 前馈项禁用（不是零输出）；区使能全关 → `eIdle`，输出全 0。

**状态机**：`E_DL_OvenState : ( eIdle := 0, eRun := 1, eCool := 2, eFault := 99 )`。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bReset : BOOL := FALSE;` | 复位 / Reset |
| IN | `abZoneEnable : ARRAY[1..8] OF BOOL;` | 8 区独立使能 / Per-zone enable |
| IN | `afPv_C : ARRAY[1..8] OF REAL;` | 8 区实测温度 -20~300 ℃ / Zone PV |
| IN | `afSp_C : ARRAY[1..8] OF REAL;` | 8 区设定温度 0~250 ℃ / Zone SP |
| IN | `afKp : ARRAY[1..8] OF REAL;` | 8 区比例增益 0.1~20 %/K / Zone gain |
| IN | `fFanPct : REAL := 0.0;` | 循环风量 0~100 % / Fan duty |
| IN | `fKff : REAL := 0.0;` | 风量前馈系数 0~1 %/% / Fan feedforward |
| IN | `fOvertemp_C : REAL := 260.0;` | 超温阈值 50~300 ℃ / Overtemperature limit |
| IN | `fRateMax_pct_s : REAL := 5.0;` | 输出速率上限 >0 %/s / Output slew limit |
| IN | `bFanRun : BOOL := FALSE;` | 风机运行反馈 / Fan running |
| IN | `tCycle : TIME := T#100MS;` | 周期 T#10MS~T#2S / Cycle |
| OUT | `afOut_pct : ARRAY[1..8] OF REAL;` | 8 区加热输出 0~100 % / Heater output |
| OUT | `bOvertemp : BOOL;` | 任一区超温 / Any zone overtemp |
| OUT | `uOvertempZone : USINT;` | 首个超温区号 0=无 / First overtemp zone |
| OUT | `bReady : BOOL;` | 全部区进入 ±`fBandTol` 带 / All zones in band |
| OUT | `eState : E_DL_OvenState;` | 状态 / State |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0002_371F` | 信息 | 正常运行 |
| 2 | `16#0002_3720` | 故障 | 任一 `afPv_C`/`afSp_C` 非有限，或 `tCycle` 非法 |
| 3 | `16#0002_3721` | 故障 | `fOvertemp_C ≤ 0` / `fRateMax_pct_s ≤ 0` / 任一 `afKp ≤ 0`（组态错） |
| 4 | `16#0002_3722` | 信息 | `bFanRun=FALSE` → 前馈禁用（`fKff` 项按 0 计），调节继续 |
| 5 | `16#0002_3723` | 故障 | 任一区 `afPv_C ≥ fOvertemp_C` → 全输出清零、`bOvertemp=TRUE`、`uOvertempZone` 记首区、锁存 |

**防御**：数组下标 1..8 全用常量循环（禁 `FOR` 越界）；`afSp_C ≤ 0` 按 1 ℃ 处理（防冻结工况斜率无穷）；超温锁存解除 = `bReset` 且所有 `afPv_C < fOvertemp_C - 5 K`（回差，防抖）——**解除式必须可达**（R28 终审第一式）；`fRateMax_pct_s × tCycle` 为单拍步长，`tCycle` 转秒须钳 ≥0.01 s。
**依赖**：无（纯内联比例 + 前馈；不调 `FB_DL_CascadePid` 以免与存量串级件耦合）。
**验收**：
1. 8 区 `Sp=120`, `Pv=100`, `Kp=2`, `fKff=0`, `fFanPct=50`, `bFanRun=TRUE` → 各区 `fOut_pct` 上升且单拍增量 ≤ `5.0 × 0.1 = 0.5 %`。
2. 区 3 `Pv=265`（> 260）→ 8 区输出全 0、`uOvertempZone=3`、槽 5；`bReset` 后若 Pv 仍 256（未回差）→ **不得**解除。
3. 反向：`bFanRun=FALSE`、`fKff=0.5` → 输出不含前馈项（与 `fKff=0` 结果一致），槽 4。

---

## 批次 2（控制律 + 设备域）

### 6 · `FB_DL_HeatExchangerCtrl`（DL_Algo / FB / 16#0002_3724~3728 / roadmap-L307 / T1-4◐ / 复杂度 4）

**功能语义**：换热器出口温度分程控制。低温段开蒸汽阀（加热），高温段开凝水阀（冷却），死区带内双阀同关；两阀交接处给 ±`fBiasPct` 偏置防双阀抢动。边界：出口温度传感器失效（`bPvValid=FALSE`）→ 双阀回安全位（蒸汽关、凝水按 `fCondSafe_pct` 开，属工艺安全侧）；两阀同时非零（越过分程死区）→ 故障级（分程逻辑错）；蒸汽/凝水不可用 → 对应支路输出 0 并降级为单支路。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bPvValid : BOOL := FALSE;` | 温度有效 / PV valid |
| IN | `fPv_C : REAL := 20.0;` | 出口温度 -20~250 ℃ / Outlet temperature |
| IN | `fSp_C : REAL := 80.0;` | 设定 0~200 ℃ / Setpoint |
| IN | `fDeadBand_C : REAL := 1.0;` | 分程死区 0~10 K / Split dead band |
| IN | `fKp : REAL := 3.0;` | 比例增益 0.1~50 %/K / Gain |
| IN | `fTi_s : REAL := 60.0;` | 积分时间 >0 s / Integral time |
| IN | `fBiasPct : REAL := 2.0;` | 交接偏置 0~20 % / Handover bias |
| IN | `fCondSafe_pct : REAL := 30.0;` | 凝水阀安全位 0~100 % / Condensate safe position |
| IN | `bSteamAvail : BOOL := TRUE;` | 蒸汽可用 / Steam available |
| IN | `bCondAvail : BOOL := TRUE;` | 凝水可用 / Condensate available |
| IN | `tCycle : TIME := T#200MS;` | 周期 T#20MS~T#5S / Cycle |
| OUT | `fSteamOut_pct : REAL;` | 蒸汽阀 0~100 % / Steam valve |
| OUT | `fCondOut_pct : REAL;` | 凝水阀 0~100 % / Condensate valve |
| OUT | `fErr_C : REAL;` | 温度偏差 K / Deviation |
| OUT | `bSplitActive : BOOL;` | 分程动作中 / Split active |
| OUT | `bDegraded : BOOL;` | 单支路降级 / Degraded single branch |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0002_3724` | 信息 | 正常运行 |
| 2 | `16#0002_3725` | 故障 | 输入非有限 / `tCycle` 非法 / `fTi_s ≤ 0` |
| 3 | `16#0002_3726` | 故障 | `fKp ≤ 0` / `fDeadBand_C < 0` / `fBiasPct < 0`（组态错） |
| 4 | `16#0002_3727` | 信息 | 单支路降级（`bSteamAvail=FALSE` 或 `bCondAvail=FALSE`）→ `bDegraded=TRUE` |
| 5 | `16#0002_3728` | 故障 | 双阀同时 >0.5 % 且 `ABS(fErr_C) > fDeadBand_C`（分程互斥失效）→ 双阀归 0 锁存 |

**防御**：积分抗饱和：任一支路到 0/100 % 边沿即停同向积分；`fDeadBand_C = 0` 时按 0.5 K 兜底（防抖振）；`bPvValid=FALSE` 走安全侧（蒸汽 0、凝水 `fCondSafe_pct`）并置槽 2 的降级分支（信息登记在 `bDegraded`，不置 `bError`）；互斥闸解除 = `bReset` 且 `ABS(fErr_C) ≤ fDeadBand_C`。
**依赖**：无（内联 PI + 分程；禁止实例化两个 `FB_DL_PidController`，交接偏置双 PID 无法共享）。
**验收**：
1. `Sp=80, Pv=70, Kp=3, Ti=60s` → `fSteamOut_pct` 上升、`fCondOut_pct=0`、`bSplitActive=TRUE`。
2. `Sp=80, Pv=85`（超调）→ 蒸汽 0、凝水 >0，且任一时刻**不得**双阀同时 >0.5 %。
3. 反向：`fPv_C` 传 NaN → 蒸汽 0、凝水 `fCondSafe_pct`、槽 2。

### 7 · `FB_DL_CoolantLoopBal`（DL_Device / FB / 16#0003_03C0~03C4 / roadmap-L368 / T2-1◐ / 复杂度 4）

**功能语义**：机台冷却水 4 支路流量均衡。以支路平均流量为目标，逐支路按相对偏差做阀位增量修正，**增量总和强制归零**（保总流量守恒），并受单支路阀位限幅与最大增量限制。边界：任一流量计无效（`abFlowValid=FALSE`）→ 该支路阀位冻结（不参与均衡，也不被拉走流量）；总流量低于 `fFlowMin_lpm` → 全支路冻结（欠流下均衡会放大波动）；阀位触限 → 停止该支路同向修正并置信息级。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `abFlowValid : ARRAY[1..4] OF BOOL;` | 支路流量有效 / Branch flow valid |
| IN | `afFlow_lpm : ARRAY[1..4] OF REAL;` | 支路流量 0~500 L/min / Branch flow |
| IN | `fFlowMin_lpm : REAL := 5.0;` | 均衡投入最低总流量 >0 L/min / Min total flow |
| IN | `fGain : REAL := 0.5;` | 均衡增益 0.05~2.0 / Balance gain |
| IN | `fTrimMax_pct : REAL := 5.0;` | 单拍最大阀位增量 0.1~20 % / Max step |
| IN | `fDevMax_pct : REAL := 20.0;` | 失衡报警阈值 1~100 % / Imbalance alarm |
| IN | `tWin : TIME := T#2S;` | 均值窗口 T#200MS~T#30S / Averaging window |
| OUT | `afValve_pct : ARRAY[1..4] OF REAL;` | 支路阀位 0~100 % / Branch valve |
| OUT | `fFlowAvg_lpm : REAL;` | 窗口平均总流量 L/min / Average total flow |
| OUT | `fImb_pct : REAL;` | 最大支路偏差 % / Max imbalance |
| OUT | `bBalanced : BOOL;` | 失衡 ≤ 5 % / Balanced |
| OUT | `bFrozen : BOOL;` | 冻结中 / Frozen |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0003_03C0` | 信息 | 均衡运行正常 |
| 2 | `16#0003_03C1` | 故障 | 流量值非有限 / `tWin` 非法 |
| 3 | `16#0003_03C2` | 故障 | `fGain ≤ 0` / `fTrimMax_pct ≤ 0` / `fFlowMin_lpm ≤ 0`（组态错） |
| 4 | `16#0003_03C3` | 信息 | 单支路阀位触 0/100 % 或流量计无效 → 该路冻结 |
| 5 | `16#0003_03C4` | 信息 | 总流量 < `fFlowMin_lpm` → 全冻结（`bFrozen=TRUE`），`fImb_pct` 照算供上位看 |

**防御**：有效支路数 < 2 → 不均衡（单支路无相对量）并置槽 4；增量归零实现：先算各路增量再减均值；`afValve_pct` 为 `VAR_IN_OUT`？——**本件定 `VAR_OUTPUT`**（阀位由本件独占写，输入初值走 `afValveInit_pct` 以免输出初值不确定）；`fFlowAvg_lpm` 分母为有效路数，钳 ≥1。
**依赖**：无（窗口均值内联实现，不引用 `FB_DL_MovingAverage` 以免 Device 层回指 MathData 之外的耦合；如需统计口径统一，可后续单独立项）。
**验收**：
1. 初始化 4 路阀位 50 %，流量 100/80/120/100 L/min，`fGain=0.5` → 第 1 路阀位上升、第 3 路下降，四路增量代数和 = 0（±0.1 %）。
2. 支路 2 `abFlowValid=FALSE` → 支路 2 阀位保持不变，其余按 3 路均衡。
3. 反向：总流量 3 L/min（< 5）→ `bFrozen=TRUE`、全部阀位不变、槽 5。

### 8 · `FB_DL_AhuFilterDpBank`（DL_Device / FB / 16#0003_03C5~03C9 / roadmap-L441 / T1-2◐ / 复杂度 2）

**功能语义**：空调箱 4 段过滤器压差四级分档（洁净/初堵/中堵/更换）。每段独立迟滞分档（上升阈值/下降回落 10 Pa），并做 `tDebounce` 去抖。边界：风量过低（`fFanPct < fFanMinPct`）→ 分档冻结（低压差会被误判洁净，必须在有风工况判定）；压差传感器超量程（> `fDpMax_Pa`）→ 判"传感器故障/滤袋破损"档 + 故障级；任一区进入更换档 → `bChangeReq=TRUE`。

**枚举**：`E_DL_FilterStage : ( eClean := 0, eEarly := 1, eMid := 2, eChange := 3, eSensorFault := 9 )`。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `afDp_Pa : ARRAY[1..4] OF REAL;` | 段压差 0~2000 Pa / Stage dP |
| IN | `afDpEarly_Pa : ARRAY[1..4] OF REAL;` | 初堵阈值 10~500 Pa / Early threshold |
| IN | `afDpChange_Pa : ARRAY[1..4] OF REAL;` | 更换阈值 20~1000 Pa / Change threshold |
| IN | `fHyst_Pa : REAL := 10.0;` | 迟滞回差 0~100 Pa / Hysteresis |
| IN | `fDpMax_Pa : REAL := 1500.0;` | 传感器量程 >0 Pa / Sensor range |
| IN | `fFanPct : REAL := 0.0;` | 风机输出 0~100 % / Fan duty |
| IN | `fFanMinPct : REAL := 20.0;` | 判定最低风量 0~100 % / Min fan for judging |
| IN | `tDebounce : TIME := T#5S;` | 去抖 T#100MS~T#120S / Debounce |
| OUT | `aeStage : ARRAY[1..4] OF E_DL_FilterStage;` | 各段档位 / Stage level |
| OUT | `auMaxStage : USINT;` | 最高档 0~3 / Max stage |
| OUT | `bChangeReq : BOOL;` | 需更换 / Change required |
| OUT | `bFrozen : BOOL;` | 低风量冻结 / Frozen low airflow |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0003_03C5` | 信息 | 分档正常 |
| 2 | `16#0003_03C6` | 故障 | 压差非有限 / `tDebounce` 非法 |
| 3 | `16#0003_03C7` | 故障 | `afDpEarly_Pa ≥ afDpChange_Pa`（任一段阈值倒置）/ `fDpMax_Pa ≤ 0` |
| 4 | `16#0003_03C8` | 信息 | 低风量冻结（`fFanPct < fFanMinPct`）→ `bFrozen=TRUE`，档位保持 |
| 5 | `16#0003_03C9` | 故障 | 任一段 `afDp_Pa > fDpMax_Pa` 或压差为负 → 该段 `eSensorFault` |

**防御**：分档用「当前档 + 上升/下降双阈值」而非单阈值比较（防抖振）；`auMaxStage` 只统计非 `eSensorFault` 段；`E_DL_FilterStage` 的 `CASE` 必须含 `eSensorFault` 与 `ELSE` 两个标签（R128 枚举成员 ⊆ CASE 标签）。
**依赖**：无（去抖内联 `TON`，`TON` 每拍无条件刷新）。
**验收**：
1. 段 1 压差 60 Pa，`fDpEarly=80`、`fDpChange=200`、`fFanPct=60` → 持续 `tDebounce` 后 `aeStage[1]=eClean`、`auMaxStage=0`。
2. 段 2 压差 210 Pa 且持续 → `aeStage[2]=eChange`、`bChangeReq=TRUE`；降到 195 Pa（> 190 回差）仍保持 `eChange`。
3. 反向：`fFanPct=10` → `bFrozen=TRUE`、档位不变、槽 4。

### 9 · `FB_DL_CoilFreezeStat`（DL_Device / FB / 16#0003_03CA~03CE / roadmap-L386 / T1-2◐ / 复杂度 3）

**功能语义**：盘管防冻统计判据（只判不控）。累计"低于 `fFreezeLimit_C` 的持续时长"，并估计温降速率；累计超 `tAccumWarn` → 预警，超 `tAccumAlarm` → 报警锁存。边界：风机运行（`bFanRun=TRUE`）且水温正常时按 `fDecayFactor` 衰减累计（不让历史冷量永不消退——但**衰减不得低于 0**）；温度传感器无效 → 冻结累计（不增不减）+ 信息级；温降速率超 `fRateAlarm_Cmin` 直接报警（即使累计未到）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bReset : BOOL := FALSE;` | 复位锁存 / Reset |
| IN | `bTempValid : BOOL := FALSE;` | 温度有效 / Temp valid |
| IN | `fCoilTemp_C : REAL := 12.0;` | 盘管温度 -40~80 ℃ / Coil temperature |
| IN | `fFreezeLimit_C : REAL := 2.0;` | 冻结判定限 -10~10 ℃ / Freeze limit |
| IN | `fRateAlarm_Cmin : REAL := 1.0;` | 温降速率报警 0.1~20 K/min / Cooling rate alarm |
| IN | `tAccumWarn : TIME := T#5M;` | 累计预警 T#10S~T#2H / Accumulate warn |
| IN | `tAccumAlarm : TIME := T#10M;` | 累计报警 T#10S~T#8H / Accumulate alarm |
| IN | `fDecayFactor : REAL := 0.5;` | 回暖衰减系数 0~1 / Decay factor |
| IN | `bFanRun : BOOL := FALSE;` | 风机运行 / Fan running |
| IN | `tCycle : TIME := T#1S;` | 周期 T#100MS~T#10S / Cycle |
| OUT | `tColdAccum : TIME;` | 低温累计时长 / Cold accumulate |
| OUT | `fRate_Cmin : REAL;` | 温降速率 K/min / Cooling rate |
| OUT | `bWarn : BOOL;` | 预警 / Warning |
| OUT | `bAlarm : BOOL;` | 报警（锁存）/ Alarm latched |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0003_03CA` | 信息 | 统计正常（未越限） |
| 2 | `16#0003_03CB` | 故障 | 温度非有限 / `tCycle` 非法 |
| 3 | `16#0003_03CC` | 故障 | `tAccumAlarm ≤ tAccumWarn` / `fDecayFactor < 0` / `fDecayFactor > 1`（组态错） |
| 4 | `16#0003_03CD` | 信息 | `bTempValid=FALSE` → 累计冻结（不增不减） |
| 5 | `16#0003_03CE` | 故障 | `tColdAccum ≥ tAccumAlarm` 或 `fRate_Cmin ≥ fRateAlarm_Cmin` → `bAlarm=TRUE` 锁存 |

**防御**：速率用一阶差分 + 下限钳（`tCycle` ≥ 0.1 s）；累计加减都钳在 `[T#0S, 2×tAccumAlarm]`；锁存解除 = `bReset` 且 `fCoilTemp_C > fFreezeLimit_C + 2 K` 且 `fRate_Cmin < 0`（回暖中）——三条件同时满足才解除（**解除式可达性自证**：正常运行回暖即满足）；`tColdAccum` 用 TIME 加法每拍检查上界，防溢出。
**依赖**：无（衰减与差分内联，不调 `FB_DL_Integrator` / `FB_DL_Differentiator`，保持 Device 层自足）。
**验收**：
1. 温度恒 0.5 ℃（< 2.0），`tCycle=1s`，运行 11 min → `tColdAccum ≈ 11 min`、`bAlarm=TRUE`（超过 10 min）。
2. 温度从 12 ℃ 降到 6 ℃ 用 1 min（`fRate=6 K/min` > 1.0）→ `bAlarm=TRUE` 立即置位（累计尚为 0）。
3. 反向：`bTempValid=FALSE` 持续 5 min → `tColdAccum` 不增不减，槽 4。

### 10 · `FB_DL_LamDoorInterlock`（DL_Device / FB / 16#0003_03CF~03D3 / roadmap-L476 / T2-8◐ / 复杂度 4）

**功能语义**：层压机炉门-真空-温度三联锁。开门三条件全部满足才放行：真空已破（`bVacReleased`）、温度低于 `fTempSafe_C`、无加热输出（`fHeatPct < 0.5`）。反向联锁：门未关严 → 禁止抽真空与加热。首因定位：拒绝开门时按固定优先级（真空未破 → 温度过高 → 加热未撤 → 门信号异常）给出首个不满足项。边界：`bDoorClosed` 与 `bDoorLocked` 不一致 → 门信号异常故障；解锁保持超时（放行后 `tUnlockHold` 内门仍未开）→ 信息级提示（电磁铁/机械卡滞）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bReset : BOOL := FALSE;` | 复位 / Reset |
| IN | `bDoorClosed : BOOL := FALSE;` | 门关到位 / Door closed |
| IN | `bDoorLocked : BOOL := FALSE;` | 门锁定反馈 / Door locked |
| IN | `bUnlockReq : BOOL := FALSE;` | 开门请求 / Unlock request |
| IN | `bVacReleased : BOOL := FALSE;` | 真空已破（常开触点语义外置）/ Vacuum released |
| IN | `bVacReady : BOOL := FALSE;` | 真空泵就绪 / Vacuum pump ready |
| IN | `fVac_kPa : REAL := 101.3;` | 腔体绝压 0~101.3 kPa / Chamber pressure |
| IN | `fTemp_C : REAL := 25.0;` | 腔体温度 -20~250 ℃ / Chamber temperature |
| IN | `fTempSafe_C : REAL := 60.0;` | 允许开门温度 20~120 ℃ / Safe unlock temperature |
| IN | `fHeatPct : REAL := 0.0;` | 加热输出 0~100 % / Heater output |
| IN | `tUnlockHold : TIME := T#5S;` | 解锁保持超时监控 T#500MS~T#60S / Unlock hold timeout |
| OUT | `bDoorRelease : BOOL;` | 门解锁输出 / Door release |
| OUT | `bHeatPermit : BOOL;` | 允许加热 / Heat permit |
| OUT | `bVacPermit : BOOL;` | 允许抽真空 / Vacuum permit |
| OUT | `uFirstCause : USINT;` | 首因码 0=无 1=真空 2=温度 3=加热 4=门信号 / First cause |
| OUT | `bHoldTimeout : BOOL;` | 解锁保持超时 / Unlock hold timeout |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0003_03CF` | 信息 | 联锁判定正常 |
| 2 | `16#0003_03D0` | 故障 | 温度/压力非有限 / `tUnlockHold` 非法 |
| 3 | `16#0003_03D1` | 故障 | `fTempSafe_C` 出域（<20 或 >120）/ `fVac_kPa < 0`（组态错） |
| 4 | `16#0003_03D2` | 信息 | 解锁保持超时（放行后门未开）→ `bHoldTimeout=TRUE`，不撤放行 |
| 5 | `16#0003_03D3` | 故障 | `bDoorClosed ≠ bDoorLocked`（门信号矛盾）→ 禁止加热/抽真空，锁存 |

**防御**：三条件用 AND 且各自独立计布尔，`uFirstCause` 按固定优先级首个 FALSE 赋值（同拍只留一个原因，避免上位看花）；`bDoorClosed ≠ bDoorLocked` 允许 `tUnlockHold` 窗口内豁免（解锁瞬间锁反馈必然滞后 —— 否则联锁永不可用，属典型误锁）；锁存解除 = `bReset` 且 `bDoorClosed = bDoorLocked`；`bEnable=FALSE` 时三输出全 FALSE（安全侧）。
**依赖**：无（不复用 `FB_DL_GuardLockDoor`：本件是工艺域三联锁，解锁时序语义由 `tUnlockHold` 显式持有）。
**验收**：
1. 门关+锁定、真空已破、温度 40 ℃、加热 0 % → `bUnlockReq=TRUE` 时 `bDoorRelease=TRUE`、`uFirstCause=0`。
2. 温度 80 ℃（> 60）→ `bDoorRelease=FALSE`、`uFirstCause=2`。
3. 反向：`bDoorClosed=TRUE, bDoorLocked=FALSE` 且已过 `tUnlockHold` → 槽 5、`bHeatPermit=FALSE`、`bVacPermit=FALSE`。

---

## 批次 3（设备 + 运动）

### 11 · `FB_DL_FurnaceBeltTension`（DL_Device / FB / 16#0003_03D4~03D8 / roadmap-L244 / T2-4◐ / 复杂度 4）

**功能语义**：烧结炉网带张力闭环 + 边缘跑偏纠偏。张力环输出速度微调（`fTrimOut_pct`）叠加在主线速之上；跑偏环按边缘位置与中心偏差出纠偏量，两环共用执行器时按权重分配（张力 0.7 / 纠偏 0.3）。边界：边缘位置超 `fEdgeTol_mm` → `bEdgeAlarm`（网带跑偏，张力环输出冻结以免叠加扰动）；张力偏差超 `fTensionTolPct` → 张力报警；网带停（`bWebRun=FALSE`）→ 双环输出归 0 且积分保持（再启动无扰）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bWebRun : BOOL := FALSE;` | 网带运行 / Web running |
| IN | `fTension_N : REAL := 0.0;` | 实测张力 0~5000 N / Measured tension |
| IN | `fTensionSp_N : REAL := 800.0;` | 张力设定 0~5000 N / Tension setpoint |
| IN | `fEdgePos_mm : REAL := 0.0;` | 边缘位置 -50~50 mm（正=右偏）/ Edge position |
| IN | `fEdgeCenter_mm : REAL := 0.0;` | 边缘中心基准 -50~50 mm / Edge center |
| IN | `fEdgeTol_mm : REAL := 3.0;` | 跑偏容差 0.1~20 mm / Edge tolerance |
| IN | `fTensionTolPct : REAL := 5.0;` | 张力容差 0.5~50 % / Tension tolerance |
| IN | `fKpT : REAL := 0.02;` | 张力环增益 0.001~1 %/N / Tension gain |
| IN | `fKpE : REAL := 0.5;` | 纠偏环增益 0.01~5 %/mm / Edge gain |
| IN | `fTrimMax_pct : REAL := 10.0;` | 输出限幅 0.5~50 % / Output limit |
| IN | `fWeightT : REAL := 0.7;` | 张力权重 0~1 / Tension weight |
| OUT | `fTrimOut_pct : REAL;` | 速度微调 -100~100 % / Speed trim |
| OUT | `fDev_N : REAL;` | 张力偏差 N / Tension deviation |
| OUT | `fEdgeDev_mm : REAL;` | 边缘偏差 mm / Edge deviation |
| OUT | `bTensionAlarm : BOOL;` | 张力超差 / Tension alarm |
| OUT | `bEdgeAlarm : BOOL;` | 跑偏超差 / Edge alarm |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0003_03D4` | 信息 | 双环运行正常 |
| 2 | `16#0003_03D5` | 故障 | 输入非有限 |
| 3 | `16#0003_03D6` | 故障 | `fTensionSp_N ≤ 0` / `fTrimMax_pct ≤ 0` / `fKpT ≤ 0` / `fKpE < 0`（组态错） |
| 4 | `16#0003_03D7` | 信息 | `bWebRun=FALSE` 或 `bEdgeAlarm=TRUE` → 输出归 0 / 张力环冻结，积分保持 |
| 5 | `16#0003_03D8` | 故障 | 张力环输出持续 10 s 触限仍同向偏差 > 容差（执行器饱和/张力传感器失效）→ 锁存 |

**防御**：`fWeightT` 钳 [0,1]，纠偏权重 = `1-fWeightT`，权重和恒 1（不得双环各自满幅叠加）；输出限幅先钳后累加；饱和锁存需 `bReset`；`fEdgeTol_mm ≤ 0` 按 0.1 兜底并置槽 3。
**依赖**：无（内联比例 + 饱和计时用 `TON`）。
**验收**：
1. `Tsp=800, T=760`（偏差 -40 N）、`KpT=0.02` → `fTrimOut_pct` 上升，单拍增量 ≤ 0.02×40×权重 0.7 ≈ 0.56 %。
2. `fEdgePos_mm=8`（> 3 容差）→ `bEdgeAlarm=TRUE`、张力项冻结，`fTrimOut_pct` 只含纠偏项。
3. 反向：`fTensionSp_N=0` → 输出 0、槽 3、`bTensionAlarm=FALSE`（不误报超差）。

### 12 · `FB_DL_ScreenPrintAlign`（DL_Motion / FB / 16#0004_0340~0344 / roadmap-L235 / T1-6◐ / 复杂度 4）

**功能语义**：丝网印刷对位。相机给出 `dx/dy/dθ` 偏差 → 换算为工作台 XY 纠偏目标（含 θ 补偿的旋转臂分解：`Δx = dx - dθ·r·π/180` 形式由 `fRotRadius_mm` 给出）→ 单轴相对定位（复用 PLCopen 相对定位语义）→ 到位后判公差。边界：偏差超 `fCorrMax_mm` → 拒绝纠偏并置故障级（大幅偏差通常是误识别，纠偏会把工件撞出工位）；连续 `uRetryMax` 次未进公差 → 故障锁存；θ 偏差超 `fTolTheta_deg` → 只做 XY 不旋转（降级）并置信息级。

**状态机**：`E_DL_AlignState : ( eIdle := 0, eCalc := 1, eMove := 2, eVerify := 3, eDone := 4, eFault := 99 )`。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bTrigger : BOOL := FALSE;` | 上升沿启动一次对位 / Trigger |
| IN | `bReset : BOOL := FALSE;` | 复位故障 / Reset |
| IN | `fCamDx_mm : REAL := 0.0;` | 相机 X 偏差 -20~20 mm / Camera dX |
| IN | `fCamDy_mm : REAL := 0.0;` | 相机 Y 偏差 -20~20 mm / Camera dY |
| IN | `fCamDTheta_deg : REAL := 0.0;` | 相机角度偏差 -10~10 ° / Camera dTheta |
| IN | `fRotRadius_mm : REAL := 200.0;` | 旋转补偿半径 10~2000 mm / Rotation radius |
| IN | `fTol_mm : REAL := 0.02;` | XY 公差 0.001~2 mm / XY tolerance |
| IN | `fTolTheta_deg : REAL := 0.05;` | 角度公差 0.001~2 ° / Theta tolerance |
| IN | `fCorrMax_mm : REAL := 5.0;` | 最大可纠偏差 0.1~20 mm / Max correctable |
| IN | `fSpeed_mmS : REAL := 20.0;` | 定位速度 1~200 mm/s / Speed |
| IN | `tMoveMax : TIME := T#5S;` | 单次定位超时 T#100MS~T#60S / Move timeout |
| IN | `uRetryMax : USINT := 3;` | 最大重试次数 1~10 / Max retries |
| IN_OUT | `iAxisX : I_DL_MotionAxis;` | X 轴契约引用 / X axis interface |
| IN_OUT | `iAxisY : I_DL_MotionAxis;` | Y 轴契约引用 / Y axis interface |
| OUT | `fCorrX_mm : REAL;` | 本次 X 纠偏量 mm / X correction |
| OUT | `fCorrY_mm : REAL;` | 本次 Y 纠偏量 mm / Y correction |
| OUT | `bInTol : BOOL;` | 纠偏后进公差 / In tolerance |
| OUT | `bDegraded : BOOL;` | θ 超差不旋转降级 / Theta degraded |
| OUT | `uRetryCnt : USINT;` | 已重试次数 / Retry count |
| OUT | `eState : E_DL_AlignState;` | 状态 / State |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0004_0340` | 信息 | 对位完成（`eDone`） |
| 2 | `16#0004_0341` | 故障 | 偏差/参数非有限 / `tMoveMax` 非法 / 轴接口未就绪 |
| 3 | `16#0004_0342` | 故障 | `fTol_mm ≤ 0` / `fSpeed_mmS ≤ 0` / `uRetryMax = 0`（组态错） |
| 4 | `16#0004_0343` | 信息 | `ABS(fCamDTheta_deg) > fTolTheta_deg` → 仅 XY 纠偏（`bDegraded=TRUE`） |
| 5 | `16#0004_0344` | 故障 | `ABS(dx) > fCorrMax_mm` 或 `ABS(dy) > fCorrMax_mm` → 拒纠；或重试达 `uRetryMax` 仍未进公差 |

**防御**：`bTrigger` 上升沿受理，`bBusy` 期丢弃新触发（不排队）；每拍只发一次定位指令（`MC_MoveRelative` 类语义：Execute 上升沿）；换轴前清上一轴 `bDone`（R27 跨轴标志教训）；`tMoveMax` 超时 → 中止当前轴并置故障、**不再发新指令**；θ 补偿项用 `SIN` 于小角度近似（|θ|≤10° 内误差 <0.5 %，注释写明适用域）。
**依赖**：`I_DL_MotionAxis`（既有接口，只调其 `MoveRelative` / `bDone` / `bError` 成员，不内联实现轴逻辑）。
**验收**：
1. `dx=0.5, dy=-0.3, dθ=0, 半径 200, tol 0.02` → `fCorrX_mm=0.5`、`fCorrY_mm=-0.3`，两轴各发一次相对定位，`bInTol=TRUE`、`eDone`。
2. `dx=0.02, dy=0`（恰在公差边界）→ `bInTol=TRUE`（边界含等号）。
3. 反向：`dx=8 mm`（> 5）→ 一轴都不动、槽 5、`eState=eFault`。

### 13 · `FB_DL_FilmSpliceTensionHold`（DL_Motion / FB / 16#0004_0345~0349 / roadmap-L380 / T1-6◐ / 复杂度 4）

**功能语义**：接膜瞬间张力双回路无扰交接。A 卷张力闭环运行中接膜 → 张力给定从 A 实测向 B 目标按 `fRampUp_Ns` 斜坡过渡，交接期间两回路输出按时间权重交叉淡入淡出（和恒为 1，避免张力台阶）。边界：交接超 `tHoldMax` 未完成 → 中止并保持当前给定（**绝不裁切**，`bCutPermit` 保持 FALSE）+ 故障级；交接中张力偏差 > `fDevMax_N` → 立即冻结斜坡、停在当前权重（保张力优先）；B 张力实测无效 → 不启动交接。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bSpliceStart : BOOL := FALSE;` | 上升沿启动交接 / Splice start |
| IN | `bReset : BOOL := FALSE;` | 复位 / Reset |
| IN | `fTensionA_N : REAL := 0.0;` | A 卷实测张力 0~2000 N / A tension |
| IN | `fTensionANow_N : REAL := 0.0;` | A 卷当前指令值 0~2000 N / A command |
| IN | `fTensionBSp_N : REAL := 200.0;` | B 卷目标张力 0~2000 N / B setpoint |
| IN | `bBMeasValid : BOOL := FALSE;` | B 卷张力实测有效 / B measurement valid |
| IN | `fRamp_Ns : REAL := 200.0;` | 给定斜坡速率 1~5000 N/s / Ramp rate |
| IN | `fDevMax_N : REAL := 40.0;` | 交接允许偏差 1~500 N / Max deviation |
| IN | `tHoldMax : TIME := T#3S;` | 交接最长时间 T#100MS~T#30S / Max handover time |
| IN | `tCycle : TIME := T#10MS;` | 周期 T#1MS~T#200MS / Cycle |
| OUT | `fTensionCmd_N : REAL;` | 交接后张力给定 0~2000 N / Tension command |
| OUT | `fBlendPct : REAL;` | B 回路权重 0~100 % / Blend weight |
| OUT | `bHoldActive : BOOL;` | 交接进行中 / Handover active |
| OUT | `bHandoverDone : BOOL;` | 交接完成（单拍脉冲）/ Handover done |
| OUT | `bCutPermit : BOOL;` | 允许裁切 / Cut permit |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0004_0345` | 信息 | 交接完成 / 未启动 |
| 2 | `16#0004_0346` | 故障 | 张力非有限 / `tCycle` 非法 |
| 3 | `16#0004_0347` | 故障 | `fRamp_Ns ≤ 0` / `fTensionBSp_N ≤ 0` / `tHoldMax` 非法（组态错） |
| 4 | `16#0004_0348` | 信息 | 交接中偏差超 `fDevMax_N` → 冻结斜坡与权重，`bHoldActive` 保持 |
| 5 | `16#0004_0349` | 故障 | 交接超 `tHoldMax` 未达 100 % → 中止、`bCutPermit=FALSE` 锁存 |

**防御**：`fBlendPct` 单调递增且钳 [0,100]；两回路输出权重和恒 100（`A = fTensionCmd_N`，`B` 权重只决定给定来源而非叠加）；`bCutPermit` 仅当 `fBlendPct ≥ 100.0` 且无故障才 TRUE（**首扫 `bCutPermit=FALSE`**，R16 纪律）；完成脉冲单拍：`bHandoverDone` 在 `eDone` 进入拍置 TRUE，下一拍清；
**依赖**：无（不调 `FB_DL_WindingTensionCtrl`：交接期的交叉淡入由其无法表达；如需 A 回路闭环，由上位实例化并回喂 `fTensionA_N`）。
**验收**：
1. `fTensionANow_N=150`, `fTensionBSp_N=200`, `fRamp=200 N/s`, 周期 10 ms → 每拍给定增量 ≤ 2 N，0.25 s 后 `fTensionCmd_N≈200`、`fBlendPct=100`、`bHandoverDone` 单拍、`bCutPermit=TRUE`。
2. `tHoldMax=1s` 而 `fRamp=10 N/s`（需 5 s）→ 1 s 后槽 5、`bCutPermit` 保持 FALSE、给定停在中间值不回退。
3. 反向：`bBMeasValid=FALSE` 时 `bSpliceStart` 上升沿 → `bHoldActive=FALSE`、给定不变（拒绝启动，槽 1）。

### 14 · `FB_DL_TrackerMotDiag`（DL_Motion / FB / 16#0004_034A~034E / roadmap-L420 / T2-4◐ / 复杂度 3）

**功能语义**：跟踪支架回转减速机健康诊断。以电流相对基线的偏差 + 跟随误差 EWMA 构造 0~100 健康评分（基线 `fBaseCurrent_A` 由标定期给定）：评分 < 60 预警、< 30 报警。边界：支架静止（`ABS(fSpeed_degS) < fSpeedMin_degS`）时电流无意义 → 只更新跟随误差项（不误判堵转）；电流超基线 `fCurDevMax_pct` → 直接报警（堵转/异物）；跟随误差超 `fErrMax_deg` → 报警锁存；EWMA 系数 `fAlpha` 需在 (0,1]。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bReset : BOOL := FALSE;` | 复位锁存 / Reset |
| IN | `fCurrent_A : REAL := 0.0;` | 电机电流 0~200 A / Motor current |
| IN | `fBaseCurrent_A : REAL := 5.0;` | 标定基线电流 >0 A / Baseline current |
| IN | `fFollowErr_deg : REAL := 0.0;` | 跟随误差 -10~10 ° / Following error |
| IN | `fSpeed_degS : REAL := 0.0;` | 转速 -5~5 °/s / Speed |
| IN | `fSpeedMin_degS : REAL := 0.05;` | 判定运行的最小转速 >0 °/s / Min speed |
| IN | `fErrMax_deg : REAL := 1.0;` | 跟随误差报警 0.01~20 ° / Max following error |
| IN | `fCurDevMax_pct : REAL := 60.0;` | 电流偏差报警 5~300 % / Max current deviation |
| IN | `fAlpha : REAL := 0.2;` | EWMA 系数 (0,1] / EWMA factor |
| OUT | `fCurDev_pct : REAL;` | 电流相对偏差 % / Current deviation |
| OUT | `fEwmaErr_deg : REAL;` | 跟随误差 EWMA ° / EWMA error |
| OUT | `uScore : USINT;` | 健康评分 0~100 / Health score |
| OUT | `bWarn : BOOL;` | 预警（评分 < 60）/ Warning |
| OUT | `bAlarm : BOOL;` | 报警（评分 < 30 或越限）/ Alarm |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0004_034A` | 信息 | 诊断正常（评分 ≥ 60） |
| 2 | `16#0004_034B` | 故障 | 输入非有限 |
| 3 | `16#0004_034C` | 故障 | `fBaseCurrent_A ≤ 0` / `fAlpha ≤ 0` 或 >1 / `fErrMax_deg ≤ 0`（组态错） |
| 4 | `16#0004_034D` | 信息 | 静止（`ABS(fSpeed_degS) < fSpeedMin_degS`）→ 电流项保持上次值，仅更误差项 |
| 5 | `16#0004_034E` | 故障 | `fCurDev_pct > fCurDevMax_pct` 或 `ABS(fEwmaErr_deg) > fErrMax_deg` → `bAlarm=TRUE` 锁存 |

**防御**：`fCurDev_pct` 分母 `fBaseCurrent_A` 有下限闸（≤0 → 槽 3，输出 0）；评分公式 `100 - 0.5×max(0, fCurDev_pct-20) - 20×ABS(fEwmaErr_deg)/fErrMax_deg`，结果钳 [0,100] 并 `TRUNC` 后 `USINT`（**禁止 `TRUNC+1`**，R28 整数进位点纪律）；EWMA 首拍初值 = 当拍误差（R16 首扫）。
**依赖**：无（EWMA 内联 3 行，不调 `FB_DL_MovingAverage` 以免 diag 件被统计件绑死）。
**验收**：
1. 基线 5 A，实测 6 A（+20 %），误差 0.1°（限 1.0），运行中 → `fCurDev_pct=20.0`、`uScore≈98`、`bWarn=FALSE`、`bAlarm=FALSE`。
2. 实测 9 A（+80 % > 60）→ `bAlarm=TRUE`、槽 5。
3. 反向：`fSpeed_degS=0`（静止）且电流 12 A → 电流项保持上次值、不置报警，槽 4。

### 15 · `FB_DL_SocketPressTrend`（DL_Motion / FB / 16#0004_034F~0353 / roadmap-L352 / T2-7◐ / 复杂度 3）

**功能语义**：压装压力-位移曲线特征提取与包络判定（每完成一次压装给一次结论）。拾取峰值压力及其位移、峰值后 20 % 回弹区间的斜率当刚度估计、峰值落入的位移窗。判定：峰值压力在 `[fForceMin_N, fForceMax_N]` 且峰值位移在 `[fPosWinLo_mm, fPosWinHi_mm]` 且刚度 ≥ `fStiffMin_Nmm` → OK；否则 NG 并按首个违背项给出码。边界：压装未完成（`bPressDone=FALSE`）→ 不出结论；峰值压力 < `fForceMin_N`（空压/漏装）→ 独立码（最常见的现场缺陷）；位移倒退（负斜率段）→ 不计入刚度。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bPressStart : BOOL := FALSE;` | 上升沿开始采集一次 / Press start |
| IN | `bPressDone : BOOL := FALSE;` | 压装到行程结束 / Press done |
| IN | `fForce_N : REAL := 0.0;` | 实时压力 0~50000 N / Force |
| IN | `fPos_mm : REAL := 0.0;` | 实时位移 0~200 mm / Position |
| IN | `fForceMin_N : REAL := 500.0;` | 压力下限 >0 N / Min force |
| IN | `fForceMax_N : REAL := 5000.0;` | 压力上限 >下限 N / Max force |
| IN | `fPosWinLo_mm : REAL := 2.0;` | 峰值位移窗下限 ≥0 mm / Position window low |
| IN | `fPosWinHi_mm : REAL := 8.0;` | 峰值位移窗上限 >下限 mm / Position window high |
| IN | `fStiffMin_Nmm : REAL := 200.0;` | 刚度下限 ≥0 N/mm / Min stiffness |
| IN | `fReboundPct : REAL := 20.0;` | 峰值后取段百分比 5~50 % / Rebound segment |
| OUT | `fForcePeak_N : REAL;` | 峰值压力 N / Peak force |
| OUT | `fPosAtPeak_mm : REAL;` | 峰值处位移 mm / Position at peak |
| OUT | `fStiff_Nmm : REAL;` | 刚度估计 N/mm / Stiffness |
| OUT | `bCurveOk : BOOL;` | 曲线判 OK / Curve OK |
| OUT | `uCurveCnt : UDINT;` | 已判定曲线数 / Judged curve count |
| OUT | `uNgCode : USINT;` | NG 码 0=OK 1=低压 2=高压 3=位移窗 4=刚度 / NG code |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0004_034F` | 信息 | 曲线判定 OK |
| 2 | `16#0004_0350` | 故障 | 压力/位移非有限 |
| 3 | `16#0004_0351` | 故障 | `fForceMax_N ≤ fForceMin_N` / `fPosWinHi_mm ≤ fPosWinLo_mm` / `fStiffMin_Nmm < 0`（组态错） |
| 4 | `16#0004_0352` | 信息 | 曲线 NG（`bCurveOk=FALSE` 且 `uNgCode>0`）——信息级：NG 是产品判据不是设备故障 |
| 5 | `16#0004_0353` | 信息 | `bPressDone` 在从未收到 `bPressStart` 时置位（时序错）→ 丢弃本次、不出结论 |

**防御**：采集缓冲上限 512 采样点（到限即停止记录并置槽 4，不覆盖前段峰值）；`bPressDone` 上升沿才结算，同一曲线不重复结算（用 `bJudged` 内部标志）；刚度分母 `Δpos` 钳 ≥0.01 mm；`uNgCode` 优先级固定（低压 → 高压 → 位移窗 → 刚度），同拍只报首项。
**依赖**：无（特征提取内联；不用 `FB_DL_SignalStatistics`：本件要时序特征而非统计量）。
**验收**：
1. 峰值 2000 N 出现在位移 5 mm，`ΔF/Δx=300 N/mm`，窗 2~8 mm → `bCurveOk=TRUE`、`uNgCode=0`、`uCurveCnt` +1。
2. 峰值 300 N（< 500）→ `bCurveOk=FALSE`、`uNgCode=1`、槽 4。
3. 反向：`bPressDone` 单独置位（无 start）→ 不出结论、`uCurveCnt` 不变、槽 5。

---

## 批次 4（工艺工站）

### 16 · `FB_DL_PalletizerStation`（DL_Process / FB / 16#0005_044E~0452 / roadmap-L653 P0 / T2-7◐ / 复杂度 5）

**功能语义**：码垛整跺工站编排。相序：进箱等待 → 分层码放（`uBoxPerLayer` 循环，每箱调夹爪/升降气缸）→ 层完成（等 `bLayerDone`）→ 满跺判断 → 缠膜（等 `bStretchDone`）→ 出跺（等 `bOutReady`）→ 复位等下一跺。每相独立超时 `tStepMax`，超时 → 故障并停在当前相（不自动跳步）。边界：`uLayerCount = 0` 或 `uBoxPerLayer = 0` → 组态错；`bReset` 只清故障，未完成跺强制从"进箱等待"重起并清 `uLayerIdx`；夹爪未闭合就允许下压（联锁错）→ 故障锁存。

**状态机**：`E_DL_PalletizerState : ( eIdle := 0, eWaitBox := 1, ePlace := 2, eLayerDone := 3, eStretch := 4, eDischarge := 5, eDone := 6, eFault := 99 )`。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bStart : BOOL := FALSE;` | 上升沿启动一跺 / Start |
| IN | `bReset : BOOL := FALSE;` | 复位故障 / Reset |
| IN | `uLayerCount : USINT := 10;` | 每跺层数 1~30 / Layers per pallet |
| IN | `uBoxPerLayer : USINT := 6;` | 每层箱数 1~20 / Boxes per layer |
| IN | `bBoxPresent : BOOL := FALSE;` | 入口有箱 / Box present |
| IN | `bPlaceDone : BOOL := FALSE;` | 单箱落位确认 / Box placed |
| IN | `bLayerDone : BOOL := FALSE;` | 层排布完成（外部层序件回馈）/ Layer done |
| IN | `bStretchDone : BOOL := FALSE;` | 缠膜完成 / Stretch done |
| IN | `bOutReady : BOOL := FALSE;` | 出跺通道就绪 / Discharge ready |
| IN | `bGripClosed : BOOL := FALSE;` | 夹爪已闭合反馈 / Gripper closed |
| IN | `tStepMax : TIME := T#20S;` | 单相超时 T#1S~T#300S / Step timeout |
| IN_OUT | `iCylGrip : I_DL_Cylinder;` | 夹爪气缸契约 / Gripper cylinder |
| IN_OUT | `iCylLift : I_DL_Cylinder;` | 升降气缸契约 / Lift cylinder |
| OUT | `eState : E_DL_PalletizerState;` | 当前相 / State |
| OUT | `uLayerIdx : USINT;` | 当前层号 0~30 / Layer index |
| OUT | `uBoxIdx : USINT;` | 当前层内箱号 0~20 / Box index |
| OUT | `bBusy : BOOL;` | 运行中 / Busy |
| OUT | `bDone : BOOL;` | 一跺完成（单拍）/ Pallet done pulse |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0005_044E` | 信息 | 帧内正常运行 |
| 2 | `16#0005_044F` | 故障 | `tStepMax` 非法 / 气缸接口未就绪 |
| 3 | `16#0005_0450` | 故障 | `uLayerCount = 0` / `uBoxPerLayer = 0` / `bEnable` 期 `iCylGrip.bError`（组态/执行器错） |
| 4 | `16#0005_0451` | 信息 | 单相超时（`tStepMax` 到）→ 停在当前相、`bBusy=FALSE` |
| 5 | `16#0005_0452` | 故障 | `ePlace` 相内 `bGripClosed=FALSE`（联锁）或 `bReset` 于跺中途（非法复位）→ 锁存 |

**防御**：每相进入时重置 `TON`（**禁止**跨相复用同一 `TON` 实例，R21 教训）；相转移条件全部用 `bXxxDone` 的上升沿或电平 + 超时双闸；`bDone` 单拍脉冲（进入 `eDone` 拍置位，下一拍回 `eWaitBox` 并清零）；`uLayerIdx`/`uBoxIdx` 递增到上限即钳制（`USINT` 无溢出风险但需显式判等）；`bEnable=FALSE` 时气缸指令回安全位（夹爪保持、升降下落）并 `eIdle`。
**依赖**：`I_DL_Cylinder`（既有）；层排布几何调用 `FB_DL_PalletizerLayerSeq`（既有，**只通过 `bLayerDone` 回馈耦合，不内联其实例**，由工站装配层串联 —— 保持工站不含几何）。
**验收**：
1. `uLayerCount=2, uBoxPerLayer=2`，全信号按序到位 → `uLayerIdx` 由 1→2、`uBoxIdx` 1→2，最终 `bDone` 单拍、`eState` 回 `eWaitBox`。
2. `bLayerDone` 一直 FALSE → 在 `eLayerDone` 相停留 `tStepMax` 后槽 4，`bBusy=FALSE`，`uLayerIdx` 不变。
3. 反向：`uBoxPerLayer=0` 启动 → 立即槽 3，一箱不动。

### 17 · `FB_DL_StringBarcodeTrace`（DL_Process / FB / 16#0005_0453~0457 / roadmap-L475 P0 / T1-4◐ / 复杂度 3）

**功能语义**：电池串条码绑定与工位路由。扫码有效沿 → 校验长度/字符集（`uLenMin`~`uLenMax`，只允许数字与字母）→ 绑定已采集的工位参数（`sLotKey` + `uStationIdx`）→ 生成追溯键 `sBindingKey`（格式 `Lot|Station|Code`）→ 查重：同一码在本班次内二次出现 → `bDuplicate=TRUE` 且**不覆盖首次绑定**（首绑定为准，重码是严重质量事件）。边界：码格式非法 → 拒收 + 信息级；`uStationIdx` 超 `uStationCnt` → 组态错；连续 `uDupMax` 次重码 → 故障锁存（防扫码器配置错导致全线重码）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bReset : BOOL := FALSE;` | 复位（含清重码计数）/ Reset |
| IN | `bCodeValid : BOOL := FALSE;` | 扫码完成有效（脉冲）/ Code valid pulse |
| IN | `sCode : STRING(32) := '';` | 扫码内容，32 字符上限 / Scanned code |
| IN | `sLotKey : STRING(16) := '';` | 批次键（外部下发）/ Lot key |
| IN | `uStationIdx : USINT := 1;` | 当前工位号 1~99 / Station index |
| IN | `uStationCnt : USINT := 8;` | 工位总数 1~99 / Station count |
| IN | `uLenMin : USINT := 8;` | 码最小长度 1~32 / Min length |
| IN | `uLenMax : USINT := 24;` | 码最大长度 1~32 / Max length |
| IN | `uDupMax : USINT := 3;` | 连续重码报警次数 1~20 / Duplicate alarm count |
| OUT | `sBindingKey : STRING(64);` | 追溯键 `Lot|Station|Code` / Binding key |
| OUT | `uRouteIdx : USINT;` | 路由工位号 / Route index |
| OUT | `bRouteValid : BOOL;` | 路由有效（可放行）/ Route valid |
| OUT | `bDuplicate : BOOL;` | 重码（首绑定未被覆盖）/ Duplicate |
| OUT | `uDupCnt : USINT;` | 连续重码计数 / Consecutive duplicate count |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0005_0453` | 信息 | 绑定成功、码唯一 |
| 2 | `16#0005_0454` | 故障 | `sLotKey` 为空 / `sCode` 长度越界外的非有限态（空串）在 `bCodeValid` 时出现 |
| 3 | `16#0005_0455` | 故障 | `uStationIdx > uStationCnt` / `uStationCnt = 0` / `uLenMin > uLenMax`（组态错） |
| 4 | `16#0005_0456` | 信息 | 码格式非法（长度 / 字符集不符）→ 拒收，`bRouteValid=FALSE` |
| 5 | `16#0005_0457` | 故障 | `bDuplicate` 连续发生 `uDupMax` 次 → 锁存（`uDupCnt ≥ uDupMax`） |

**防御**：字符串比较与拼接用标准 `CONCAT`/`LEN`/`LEFT`/`MID`，**结果长度先算后拼**（`sBindingKey` 上限 64，超限按 63 截断并置槽 4，禁越界写）；重码表用 32 条环形记录（`_Staging_Raw` 无内存分配的替代方案），满后覆盖最旧并置信息；`bCodeValid` 上升沿才处理（连续值不重复绑定，R47 边沿纪律）；`bReset` 清 `uDupCnt` 与重码表。
**依赖**：`I_DL_BarcodeScanner`（既有接口，本件只消费其结果，不做设备驱动）。
**验收**：
1. `sLotKey='L2411'`, `uStationIdx=3`, `sCode='SN00001234'` → `sBindingKey='L2411|3|SN00001234'`、`bRouteValid=TRUE`、槽 1。
2. 同码再扫一次 → `bDuplicate=TRUE`、`sBindingKey` **保持首次值**、`uDupCnt=1`。
3. 反向：`sCode='SN-001'`（含 `-`，字符集非法）→ 拒收、`bRouteValid=FALSE`、槽 4、`uRouteIdx` 不变。

### 18 · `FB_DL_PowderDosingLoss`（DL_Process / FB / 16#0005_0458~045C / roadmap-L494 / T2-1◐ / 复杂度 4）

**功能语义**：粉料失重秤增量式配料。批开始取皮重 → 螺旋给料（高速至 `fTarget_g - fSlowBand_g`，再转慢速精给）→ 落差补偿：按上一批实际过冲量修正提前停止点（`fLead_g` 学习值，限幅 `fLeadMax_g`）→ 停料后等 `tSettleTime` 稳定 → 结算净重与偏差。边界：皮重为负/超量程 → 故障（称重异常）；进料中重量**上升**（失重秤应为下降）→ 判"称重方向反了"故障；单批超 `tBatchMax` → 中止并保留已投量；落差学习仅在本批偏差 ≤ `fDevMax_g` 时更新（异常批不污染学习值）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bStart : BOOL := FALSE;` | 上升沿开始一批 / Start batch |
| IN | `bReset : BOOL := FALSE;` | 复位 / Reset |
| IN | `fWeight_g : REAL := 0.0;` | 秤读数 0~500000 g / Scale weight |
| IN | `fTarget_g : REAL := 1000.0;` | 目标投料量 >0 g / Target dose |
| IN | `fTare_g : REAL := 0.0;` | 皮重 ≥0 g / Tare |
| IN | `fSlowBand_g : REAL := 100.0;` | 转慢速余量 >0 g / Slow-down band |
| IN | `fLead_g : REAL := 0.0;` | 落差学习初值 0~500 g / Lead compensation |
| IN | `fLeadMax_g : REAL := 300.0;` | 落差限幅 1~2000 g / Lead limit |
| IN | `fDevMax_g : REAL := 5.0;` | 允许偏差 >0 g / Allowed deviation |
| IN | `bSlowCmd : BOOL := FALSE;` | 慢速输出确认 / Slow feed ack |
| IN | `tSettleTime : TIME := T#500MS;` | 停料稳定时 T#10MS~T#10S / Settle time |
| IN | `tBatchMax : TIME := T#2M;` | 单批超时 T#1S~T#30M / Batch timeout |
| OUT | `fNet_g : REAL;` | 本批净投料 g / Net dosed |
| OUT | `fErr_g : REAL;` | 本批偏差 g / Deviation |
| OUT | `bDone : BOOL;` | 批完成（单拍）/ Batch done pulse |
| OUT | `bBusy : BOOL;` | 配料中 / Busy |
| OUT | `fLeadLearn_g : REAL;` | 更新后落差学习值 g / Learned lead |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0005_0458` | 信息 | 批完成、偏差在容差内 |
| 2 | `16#0005_0459` | 故障 | 秤值非有限 / 皮重为负或超量程 / `tSettleTime` 非法 |
| 3 | `16#0005_045A` | 故障 | `fTarget_g ≤ 0` / `fSlowBand_g ≥ fTarget_g` / `fLeadMax_g ≤ 0`（组态错） |
| 4 | `16#0005_045B` | 信息 | 批完成但偏差 > `fDevMax_g` → 结算照出、落差**不学习** |
| 5 | `16#0005_045C` | 故障 | 进料期重量上升（失重秤方向反）/ 超 `tBatchMax` → 中止锁存 |

| 槽补 | 说明 | — |
|---|---|---|
| — | 槽 5 兼役「称重方向反」与「批超时」，两者同时发生以方向反优先（根因优先） | — |

**防御**：净重 = `fWeight_g - fTare_g` 每拍算，负值钳 0 并置槽 2；落差学习 `fLeadLearn_g = LIMIT(0, fLead_g + 0.5×(fErr_g), fLeadMax_g)`（比例 0.5，阻尼防振荡，注释写明）；`bStart` 上升沿且 `bBusy=FALSE` 才受理；停料后 `TON` 到才结算（防冲击读数）；`bDone` 单拍。
**依赖**：`FB_DL_BatchDosingControl`（既有）作为上位批控时本件可作其"单料失重相"插件：由批控下发 `fTarget_g`、读回 `fNet_g`/`bDone`（**不内联其实例**）。
**验收**：
1. 皮重 200 g，目标 1000 g，读数涨到 1250 g 停料（净 1050 g，过冲 50 g）→ `fNet_g=1050`、`fErr_g=+50`、**`fLeadLearn_g` 保持初值 0.0（偏差 > 5 g 容差不学习）**、槽 4。
2. 同上但过冲 3 g（净 1003 g）→ `fErr_g=+3`、`fLeadLearn_g=1.5`（0 + 0.5×3）、槽 1。
3. 反向：`bReset` 前读数从 1000 涨到 1010（投料中上升）→ 槽 5、`bBusy=FALSE`。

> 编码注意：落差学习的更新条件以「`ABS(fErr_g) ≤ fDevMax_g` 才更新」为准，槽 4 分支**只结算不学习**。

### 19 · `FB_DL_RotaryIndexModulo`（DL_Process / FB / 16#0005_045D~0461 / roadmap-L496 / T2-7◐ / 复杂度 3）

**功能语义**：转盘工位索引与入料放行联锁。`uStationCnt` 工位环形推进：`bIndexReq` 上升沿 → 若 `bAtPos` 且无故障则放行一次分度（输出 `bPermitEntry=FALSE` 关闭入料）→ 等 `bIndexDone` 到位确认 → 工位号模 `uStationCnt` 递增 → `bPermitEntry=TRUE`。边界：分度超 `tIndexMax` 未到位 → 故障并保持关闭入料（**绝不带转盘运转放料**）；入料未清（`bEntryClear=FALSE`）→ 拒绝分度（不停机但拒动）；`uStationCnt = 0` → 组态错；`bAtPos` 在分度中出现 FALSE→TRUE→FALSE 抖动 → 迟滞计数（连续 2 拍稳定才认到位）。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bIndexReq : BOOL := FALSE;` | 分度请求（上升沿受理）/ Index request |
| IN | `bReset : BOOL := FALSE;` | 复位 / Reset |
| IN | `bAtPos : BOOL := FALSE;` | 转盘到位信号 / At position |
| IN | `bIndexDone : BOOL := FALSE;` | 分度电机完成 / Index done |
| IN | `bEntryClear : BOOL := FALSE;` | 入料通道已清空 / Entry clear |
| IN | `uStationCnt : USINT := 8;` | 工位数 1~64 / Station count |
| IN | `uStationInit : USINT := 1;` | 初始工位号 1~64 / Initial station |
| IN | `tIndexMax : TIME := T#5S;` | 分度超时 T#200MS~T#60S / Index timeout |
| OUT | `uStationIdx : USINT;` | 当前工位号 1~64 / Station index |
| OUT | `bPermitEntry : BOOL;` | 入料放行 / Entry permit |
| OUT | `bIndexing : BOOL;` | 分度中 / Indexing |
| OUT | `uIndexCnt : UDINT;` | 累计分度次数 / Index count |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0005_045D` | 信息 | 正常（等待分度 / 已放行） |
| 2 | `16#0005_045E` | 故障 | `tIndexMax` 非法 |
| 3 | `16#0005_045F` | 故障 | `uStationCnt = 0` / `uStationInit > uStationCnt`（组态错） |
| 4 | `16#0005_0460` | 信息 | 分度被拒（`bEntryClear=FALSE` 或 `bAtPos=FALSE`）→ `bPermitEntry` 保持 TRUE（不误关料），本次请求丢弃 |
| 5 | `16#0005_0461` | 故障 | 分度超 `tIndexMax` 未到位 → 关闭入料并锁存 |

**防御**：`uStationIdx` 用 `if idx >= uStationCnt then 1` 显式回绕（**禁 `MOD`+1 直算**，R28 整数进位点：`MOD` 在 `uStationCnt` 整除点会出 0 工位）；到位去抖 2 拍（内部 `USINT` 计数）；`bPermitEntry` 首扫 = FALSE（等一次到位确认后才放行）；超时锁存解除 = `bReset` 且 `bAtPos=TRUE` 且 `bEntryClear=TRUE`。
**依赖**：无（`FB_DL_ModuloCounter` 是纯计数件，本件含放行联锁与时序，不复用其内部）。
**验收**：
1. `uStationCnt=8`，从 1 开始，`bAtPos`/`bIndexDone` 正常 → 分度 7 次后 `uStationIdx` 回到 1（**不得出现 0**），`uIndexCnt=7`。
2. `bEntryClear=FALSE` 时请求分度 → `uStationIdx` 不变、`bPermitEntry=TRUE`、槽 4。
3. 反向：`uStationCnt=0` → 槽 3、`bPermitEntry=FALSE`、`bIndexing=FALSE`。

### 20 · `FB_DL_ConveyorMetalDetect`（DL_Process / FB / 16#0005_0462~0466 / roadmap-L830 / T2-8◐ / 复杂度 3）

**功能语义**：金属检测机剔除联动与过检率统计。检出脉冲 → 按 `tRejectDelay`（检测头到剔除器的输送延时）排队 → 出剔除脉冲 `tRejectWidth` → 等 `bRejectAck` 确认；统计 `uDetectCnt`/`uRejectCnt`/`fOverRejectPct`（确认失败率 = 过检率代理）。边界：剔除确认超 `tAckMax` 未回 → 故障锁存（漏剔是质量事故，宁可停线）；`tRejectDelay` 期间皮带停（`fLineSpeed_mpm < fSpeedMin`）→ 排队计时冻结（皮带不动时延时不走，否则位置算偏）；连续 `uJamCnt` 次确认失败 → 判剔除器卡滞并锁存。

| 方向 | 名 : 类型 := 默认值 | 注释 |
|---|---|---|
| IN | `bEnable : BOOL := FALSE;` | 使能 / Enable |
| IN | `bReset : BOOL := FALSE;` | 复位（清统计）/ Reset |
| IN | `bDetect : BOOL := FALSE;` | 检出脉冲（上升沿计数）/ Metal detected |
| IN | `bRejectAck : BOOL := FALSE;` | 剔除完成确认 / Reject acknowledged |
| IN | `fLineSpeed_mpm : REAL := 0.0;` | 线速 0~200 m/min / Line speed |
| IN | `fSpeedMin_mpm : REAL := 1.0;` | 有效输送最小线速 >0 m/min / Min line speed |
| IN | `tRejectDelay : TIME := T#300MS;` | 检测到剔除延时 T#10MS~T#5S / Reject delay |
| IN | `tRejectWidth : TIME := T#200MS;` | 剔除脉冲宽度 T#20MS~T#2S / Reject pulse width |
| IN | `tAckMax : TIME := T#2S;` | 确认超时 T#100MS~T#30S / Ack timeout |
| IN | `uJamCnt : USINT := 3;` | 连续失败判卡滞次数 1~20 / Jam count |
| OUT | `bRejectCmd : BOOL;` | 剔除输出 / Reject command |
| OUT | `uDetectCnt : UDINT;` | 累计检出数 / Detect count |
| OUT | `uRejectCnt : UDINT;` | 累计已剔除数 / Rejected count |
| OUT | `fAckFailPct : REAL;` | 确认失败率 0~100 % / Ack failure rate |
| OUT | `bPending : BOOL;` | 有剔除排队中 / Queue pending |
| OUT | `eErr : UDINT;` | 错误码 / Error code |

| 槽 | 常量 | 级别 | 触发条件 |
|---|---|---|---|
| 1 | `16#0005_0462` | 信息 | 正常（无检出 / 剔除正常） |
| 2 | `16#0005_0463` | 故障 | 线速非有限 / 任一 TIME 参数为 0 或非法 |
| 3 | `16#0005_0464` | 故障 | `fSpeedMin_mpm ≤ 0` / `tRejectWidth ≥ tAckMax`（组态错：脉冲比确认窗还长） |
| 4 | `16#0005_0465` | 信息 | 排队冻结（`fLineSpeed_mpm < fSpeedMin_mpm`）→ 延时计时不走、`bPending=TRUE` |
| 5 | `16#0005_0466` | 故障 | 单次确认超 `tAckMax`，或连续 `uJamCnt` 次确认失败 → 锁存（漏剔/卡滞） |

**防御**：排队队列上限 8（超限丢弃新检出并置槽 5 —— 宁可停线不可静默漏剔，注释写明取舍）；`fAckFailPct` 分母 `uDetectCnt` 下限闸（0 → 输出 0）；皮带停时冻结用 `TON` 不刷新（IN 保持 FALSE），恢复后**补偿**：按冻结前后线速比例折算剩余延时，注释写明折算公式；`bDetect` 上升沿计数（连续 TRUE 不重复）。
**依赖**：无（不复用 `FB_DL_AlarmManager`：本件输出剔除动作而非告警聚合）。
**验收**：
1. 线速 30 m/min（0.5 m/s），`tRejectDelay=300ms`、`tRejectWidth=200ms`、确认及时 → `bRejectCmd` 在检出后 0.3 s 出 0.2 s 脉冲，`uDetectCnt=uRejectCnt=1`、`fAckFailPct=0`。
2. 检出后线速降到 0（皮带停）→ 延时冻结，`bPending=TRUE`、槽 4，恢复后按剩余量补足再剔除（不丢件）。
3. 反向：`tRejectWidth = tAckMax`（2 s）→ 槽 3、`bRejectCmd=FALSE`。

---

## 附：编码自检清单（每件提交前逐项打勾，R25 §5.4 已扩至十项）

1. 文件名 = POU 名，前缀与类型一致（`FC_` 不得含状态）；2. 头部七段注释齐；3. 每变量行尾双语注释；4. 无 `GVL`/`VAR_EXTERNAL`/`%I`/`%Q`/`%M`；5. 仅 `Standard.library`；6. 浮点禁用 `=`（用 `ABS(a-b) < 1E-6`）；7. 除零/边界/NaN/首扫四闸齐；8. `CASE` 有 `ELSE`，枚举成员 `:=` 赋值且**成员集合 ⊆ CASE 标签集合**（R128）；9. 每件 5 槽码位与本文一致、`eErr` 每拍无条件刷新、故障锁存解除式可达（R28 终审第一式）；10. 整数进位点（`TRUNC`/`CEIL`/钳制）在整除点与上限+1 点各推一条向量（R28 第二式）。

*R29 派单 ｜ 2026-11-17 ｜ 道莅工控代码库产品总监*
