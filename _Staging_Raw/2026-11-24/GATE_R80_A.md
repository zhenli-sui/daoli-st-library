# GATE_R80_A —— R80 批 A（36 简单件）编译闸裁决

- 轮次：R80 / 批 A｜日期：2026-11-24｜裁决人：编译闸席（一票否决）
- 环境：RuSTy `plc.exe 1.0.8` + `_tools/l2_check.py`（**jobs=1 全程串行**，非并行）
- 复现命令（每个数字可复跑，唯一一条）：
  ```
  python C:\Library\_tools\l2_check.py --out C:\Library\_Staging_Raw\2026-11-24\_l2_r80a_raw.json ^
    C:\Library\DL_Process\*.st(15 件) C:\Library\DL_Device\*.st(15 件) C:\Library\DL_MathData\*.st(6 件)
  ```
- 原始输出（不可省）：`接口预筛: 可用 22 / 排除(PROPERTY 等覆盖面缺口) 0 | 并行 1 进程 | 缓存 命中` → **`PASS=36 FAIL=0 TOTAL=36`**
- 落盘证据：`_Staging_Raw\2026-11-24\_l2_r80a_raw.json`（每件 `rc=0 / pass=true / first_error=""`）

---

## 一、L2 编译裁决表（36/36）

| # | 文件 | L2 | 错误码 | 逻辑级 | 备注（行号证据 → 最小修法） |
|---|---|---|---|---|---|
| 1 | FC_DL_WeighNetFromGross | PASS | — | 清 | L46 负净重早退，L31-33 出口三件全预置，无除零面 |
| 2 | FC_DL_WeighTareDriftCheck | PASS | — | 清 | L47 `ABS(rTareRef)<EPS` 挡 L50 除法；基准近零时 rDrift 已赋值而 bValid=FALSE，与契约一致 |
| 3 | FC_DL_WeighDoseTolBand | PASS | — | MINOR | L26 `_bFin` 注释写「三实数输入」，L38 实为五输入（复制残留）→ 改「五实在输入判定」 |
| 4 | FB_DL_WeighHopperRefillSeq | PASS | — | **MAJOR** | 见 §二-1：eFault 复位与电平停互锁，用停止复位必复跳 |
| 5 | FC_DL_WeighMultiHeadSum | PASS | — | MINOR | L53-63 255 组合穷举正确（L62 整数除 2 移位）；aWeight[] 未做有限闸，NaN 头只污染含该头的组合（不误报），契约未披露 |
| 6 | FC_DL_WeighBatchYieldCalc | PASS | — | 清 | L44 分母闸 `<=EPS` 先于 L48 除法；L53 双向公差带口径正确 |
| 7 | FC_DL_WeighCreepCompensate | PASS | — | 清 | L44 负时长/速率闸；L50 结果非有限兜底（1E30）在乘后、落定前，顺序正确 |
| 8 | FC_DL_WeighSpanCalibRatio | PASS | — | **MAJOR** | 见 §二-2：`_rPred` 量纲错误 → 正常标定被判无效 |
| 9 | FC_DL_MembraneFluxCalc | PASS | — | 清 | L44 面积/流量闸、L51 基准闸均在除法前；rFluxLmh 先落定后判无效属「保诊断值」口径，已披露 |
| 10 | FC_DL_MembraneTmpCalc | PASS | — | MINOR | L61 仅 `_rTmp>0` 置 bValid；`_rNet<0`（无净推动力）时 bValid 仍 TRUE，未分档 → 建议 nStatus 式分档 |
| 11 | FC_DL_WaterRecoveryRatio | PASS | — | 清 | L47 进料分母闸、L50 负流量闸；L59 平衡校核按需使能，口径正确 |
| 12 | FC_DL_SludgeAgeCalc | PASS | — | MINOR | L55-58 排泥固体浓度取 `max(WAS TSS, 出水 SS)`：出水 SS 与排泥量物理无关，取 max 抬高排泥量 → 泥龄偏小 → 建议仅取 WAS TSS，出水 SS 另设判据 |
| 13 | FC_DL_DoDeficitCalc | PASS | — | 清 | L50 分母闸；L61-64 阈值倒置自愈；L65-71 三档互斥完备 |
| 14 | FC_DL_CoagulantDoseCalc | PASS | — | MINOR | L58-64 上/下限倒置与负下限已整；但上下限**全负**时 L62 把 `_rLo` 抬到 0 而后 `_rHi<0` → `LIMIT(MN>MX)` 边界倒置，行为依编译器 → 建议 L62 后补 `IF _rHi<_rLo THEN _rHi:=_rLo;` |
| 15 | FC_DL_WaterLangelierIndex | PASS | — | MINOR | A/B/C/D 四项与 pHs 公式与标准 LSI 一致；L71-74 全部依赖 `LOG` 十进制语义（口径已声明）→ **须 L3 加锚定向量 `LOG(100)=2`**，否则 LN 实现会让整件静默偏 2.3 倍 |
| 16 | FC_DL_HydroCylForceCalc | PASS | — | MINOR | L70 `_rDpBar` 可为负（背压>供压）→ 推力为负且 bValid 仍 TRUE，未标注反向工况 → 建议 `IF _rDpBar<0 THEN RETURN;` |
| 17 | FC_DL_HydroCylFlowNeed | PASS | — | 清 | L44/47 面积与效率双闸；L51-53 单位换算链 cm²·cm/s→l/min 复核正确 |
| 18 | FC_DL_HydroAccumulatorSizing | PASS | — | **MAJOR** | 见 §二-3：容积分母口径错误，选型偏小 |
| 19 | FC_DL_PneuAirConsumeCalc | PASS | — | MINOR | L63 `_rVolL*(rPressBar+p_atm)` 漏除 `p_atm` → 标准状态体积偏高 1.013 倍（≈1.3%）→ 改为 `*(rPressBar+DL_ATM_BAR)/DL_ATM_BAR` |
| 20 | FC_DL_PneuCvFlowCalc | PASS | — | **MAJOR** | 见 §二-5：阀后压力不进入流量式 |
| 21 | FC_DL_HydroPipePressDrop | PASS | — | 清 | L66/69 双闸；L82 零流早退置 bValid=TRUE 且压降 0（正确）；L90 Re>1E30 兜底；层流 64/Re、湍流 Blasius 分区正确 |
| 22 | FB_DL_HydroPressRampSeq | PASS | — | MINOR | 状态机 5 相全可达、eFault 可复位且**不复跳**（L121 用沿，L83 待机不吃电平，与 #4 对照）；L113 泄压到位判据硬编码 `rPressAct<0.5` bar → 建议参数化 |
| 23 | FC_DL_PneuLeakRateCalc | PASS | — | MINOR | L54 时长/压力/容积闸已挡除零；终压>起压（温升）时 `_rLeak`、`_rPct` 为负且 bValid=TRUE → 建议 `IF rPressEnd>rPressStart THEN RETURN;` |
| 24 | FC_DL_RefCopCalc | PASS | — | 清 | L44 功率下限 0.01 kW 挡 L48 除法；L51 额定值闸；两出口分段落定，口径正确 |
| 25 | FC_DL_RefSuperheatCalc | PASS | — | 清 | 纯减法无除零面；L48-51 上下限倒置自愈；三档完备 |
| 26 | FC_DL_RefSubcoolCalc | PASS | — | 清 | 同上；L43 口径「饱和温度减液管温度」正确（易错点已标注） |
| 27 | FC_DL_RefSatPressToTemp | PASS | — | **MAJOR** | 见 §二-4：R410A 行表值与公开物性严重不符 |
| 28 | FC_DL_RefSatTempToPress | PASS | — | MINOR | 与 #27 同源同表（同样的 R410A 风险）；L12 头注释「温度为绝对压力 [bar abs] 输出」缺字 → 改「输出为绝对压力」 |
| 29 | FC_DL_RefCompressorCapacity | PASS | — | 清 | L48/51/54 三闸；L62 kg/h×kJ/kg÷3600=kW 量纲复核正确 |
| 30 | FC_DL_RefCondApproach | PASS | — | MINOR | **输入 `rApproachRef` 声明后从未参与任何计算（死输入）**，仅 L45 用 `rApproachAlarm` → 删除该输入或补「相对基准的偏离」输出 |
| 31 | FC_DL_StatsRangeCalc | PASS | — | 清 | L43 点数闸；L47/L55 双处非有限闸（首样本+遍历）；nCount=1 时 FOR 零次执行，nUsed=1 正确 |
| 32 | FC_DL_StatsIqrCalc | PASS | — | 清 | L56 点数闸（<2 无效）；L60-74 插入排序 + L78/L86 左邻钳位，无越界；分位 (n-1) 法口径与注释一致 |
| 33 | FC_DL_StatsPooledStd | PASS | — | 清 | L48/L53 双闸（n1+n2-2<=0）；L57 除子已证正；SQRT 前 rVar>=0 由 L45 保证 |
| 34 | FB_DL_StatsRollingVar | PASS | — | MINOR | 环形缓冲换出/换入成对（L66-70），`_nFilled` 封顶 64 正确；复位沿与采样同拍时「先清后插」未在口径披露；大偏置平方和抵消致负已披露并钳零 |
| 35 | FC_DL_StatsGeoMeanCalc | PASS | — | 清 | L46-50 下限整形含非有限分支；L53 剔除（NaN 与 <floor）；L61 全剔闸；L66 结果非有限兜底 |
| 36 | FC_DL_StatsDevSumSq | PASS | — | MINOR | L47 在 `bUseGivenMean=FALSE` 时仍强制校验 `rMeanGiven` 有限 → 无谓判无效，建议把该校验移入 L51 分支；另 L74/L78 用给定均值时仍除 n-1（总体方差口径应除 n），未披露 |

---

## 二、逻辑级 BLOCK/MAJOR 详情（BLOCK 等同 FAIL 处置）

### 1. FB_DL_WeighHopperRefillSeq —— MAJOR：eFault 复位路径不自洽，用停止复位必复跳
- 证据：段 2（L75）`IF bStop AND (_eState <> eFault)` 是**电平**判据；eFault 分支（L117）`IF rtStop.Q OR ...` 是**沿**判据。
- 推演：拍 N `rtStop.Q=TRUE` → L118-120 清码回 eIdle；拍 N+1 `bStop` 仍为 TRUE → 段 2 立即重新置码 3 并迁 eFault。**用停止复位无法保持**，实际只有「启动沿 + 停止已释放」一条路可退出故障。
- 影响：诊断屏上「按停止清故障」表现为故障闪回，运维会误判为硬件故障常驻。
- 最小修法（1 行）：L75 改成 `IF rtStop.Q AND (_eState <> E_DL_HopperState.eFault) THEN`（改沿后与 L117 同沿互斥，且停止保持不再复跳）。
- 状态机其余项复核：7 个 ENUM 成员全部可达（eDone 由 L104-106 进入，eValveOpen 单拍相由 L88 强制转出），ELSE 兜底在 L122，无悬挂相。

### 2. FC_DL_WeighSpanCalibRatio —— MAJOR：量程误差式量纲错误，正常标定被判无效
- 证据：L53 `_rRatio := rRefSpan / _rDelta`（kg/count）；L54 `_rPred := _rRatio * rRefSpan` → **kg²/count**（应为 `* _rDelta` 才是 kg）。
- 后果：L55 实际算的是 `(rRefSpan/_rDelta − 1)×100`。以典型标定 `rRawAtZero=0, rRawAtSpan=10000 count, rRefSpan=100 kg`：`_rPred=1`，误差 = **−99 %** → L59 `ABS>5%` 触发 → **bValid=FALSE，一件完全正确的标定被判无效**。
- 反向：若 count 量级恰等于 kg 量级（`_rDelta≈rRefSpan`）才通过，等于用「count 与 kg 数值巧合」当合格判据。
- 最小修法：L54 改 `_rPred := _rRatio * _rDelta;`（量纲自洽，但结果恒等于 rRefSpan、误差恒 0 → L58-61 的 5% 闸退化为死闸，须同时处理）；推荐正解是把误差定义改成「比例系数与标称比例的偏差」，需要新增一个独立标称输入（如 `rNominalRatio_kgPerCount`），否则本件不应输出 `rSpanErrorPct`。

### 3. FC_DL_HydroAccumulatorSizing —— MAJOR：容积公式分母口径错误 + 预充压力是死输入
- 证据：L59 `_rRatio := pmax/pmin`；L61/L63 `_rProc`；L65 `_rDen := _rProc − 1.0`；L70 `_rVol := demand/_rDen`。**`rPressPrecharge_bar` 只在 L52 做闸门，从未进入公式。**
- 与标准式对照（p0 预充、p1 最低、p2 最高，均绝对压力）：
  - 等温：ΔV = p0·V0·(1/p1 − 1/p2) ⇒ V0 = ΔV / [p0·(1/p1 − 1/p2)]；本件 = ΔV/(p2/p1 − 1)。
  - 取 p0=p1、pmax=200/pmin=100：标准 V0 = 2.000·ΔV，本件 = 1.000·ΔV → **偏小 2 倍**（= pmax/pmin 倍）。
  - 绝热：标准分母 `1 − (pmin/pmax)^(1/1.4) = 0.390`，本件 `(pmax/pmin)^(1/1.4) − 1 = 0.641` → V0 = 1.56·ΔV，标准 2.56·ΔV → **偏小 1.64 倍**。
- 影响：蓄能器选型偏小 → 保压能力不足 / 频繁补压，属工程安全侧（与 #8 相反方向）。
- 最小修法：L65 前改为
  `_rDen := EXPT(rPressPrecharge_bar, DL_ADIA_EXP) * (EXPT(rPressMin_bar, 0.0 - DL_ADIA_EXP) - EXPT(rPressMax_bar, 0.0 - DL_ADIA_EXP));`
  等温分支同理用 `_rDen := rPressPrecharge_bar * (1.0/rPressMin_bar - 1.0/rPressMax_bar);`（并在 L49-54 保留 p0<pmin 闸）。

### 4. FC_DL_RefSatPressToTemp / FC_DL_RefSatTempToPress —— MAJOR：R410A 行表值与公开物性严重不符
- 证据：两件同源同表（`afTemp` 第 2 行 L26 / L25），`nRefrigerant=2` 走 nRow=1。
- 锚点比对（R410A 公开物性）：`8 bar abs ↔ ≈0.0 °C`（表列 **11.4 °C**，偏 11.4 K）；`40 °C ↔ ≈24.2 bar abs`（表列 18 bar ↔ 45.0 °C，偏 ≈−5.8 bar / 17 K）。整行曲线形态更像 R22 一类的单工质，非 R410A 共沸混合物。
- 影响：`FC_DL_RefSuperheatCalc` / `RefSubcoolCalc` / `RefCondApproach` 的上游饱和温度源全部经过本表 → R410A 机组的过热度/过冷度/逼近度**系统性偏差 10 K 量级**，故障判据（分档、污染判据）会误动。
- 判定：编译无障碍（表语法正确），属数据级 MAJOR。**不做代码改写**，回派编码专家用 NIST REFPROP / ASHRAE 表重录第 2 行，并在 L3 向量里加 2 个锚点（0 °C↔7.99 bar、40 °C↔24.2 bar）。R134a 行抽核 `1 bar↔−26.1 °C`、`10 bar↔39.4 °C` 与公开数据一致，无需改。

### 5. FC_DL_PneuCvFlowCalc —— MAJOR：阀后压力是死输入，流量式与压差无关
- 证据：`rDownPressBarA` 只出现在 L53（合法性闸）与 L64-65（`_rRatio` → `rCritical` 标志）；L67 流量式只用 `rUpPressBarA`，`_rRatio` 未进入。
- 后果：任何 `rDown ∈ [0, rUp]` 都给出同一流量；非阻塞流（压比 < 0.528）工况按阻塞式给出**偏大流量**。方向偏保守（供气侧选型），但对「阀后背压升高导致流量下降」的在线诊断完全失效。
- 最小修法：非临界分支补 `_rFlow := _rFlow * SQRT(_rRatio);`（或按 IEC 60534 的 `1 − _rRatio` 因子），至少要在 `口径说明` 里明确「本式仅用于阻塞流选型」。

---

## 三、统计

| 项 | 值 |
|---|---|
| L2 真编译 | **PASS 36 / FAIL 0 / EXEMPT 0**，通过率 **100.0%** |
| EXEMPT 清单 | 无（本批 36 件均未触发 §5 PROPERTY 接口缺口，`iface_excluded=[]`） |
| 逻辑级 BLOCK | 0 |
| 逻辑级 MAJOR | **5**（#4 #8 #18 #20 #27；#28 与 #27 同源） |
| 逻辑级 MINOR | **14**（#3 #5 #10 #12 #14 #15 #16 #19 #22 #23 #28 #30 #34 #36） |
| 批 A 入库结论 | **编译门 PASS，业务门 BLOCK**：5 件 MAJOR 须本轮修或挂账后方可注册；其余 31 件准予入库 |

> 口径说明：L2 PASS 仅证明「语义可编译」，不证明「算得对」。本批 36 件全部 PASS 但仍有 3 件（#8 #18 #27/28）算出错误数值，正是「编译通过 ≠ 逻辑正确」的直接例证。

## 四、工具链自愈动作记录

| 触发条件 | 是否触发 | 动作 |
|---|---|---|
| 桩缺声明 E048/E052 | 否 | 未执行 `stub_fix.py --full`（`iec_std_stub.st` 已覆盖本批用到的 ABS/LIMIT/EXPT/SQRT/LN/EXP/LOG/FLOOR/TON/R_TRIG/类型转换，零 E048/E052） |
| 接口 E006/E007 | 否 | 未执行 `iface_stub_gen.py --verify`（`接口预筛: 可用 22 / 排除 0`，缓存命中） |
| METHOD expected expression | 否 | 未执行 `reorder_methods.py`（本批无 PROPERTY/METHOD 件） |
| 缺 END_METHOD | 否 | 未执行 `fix_end_method.py` |
| E004 Ambiguous callable（并行假阳性） | 否 | 全程 `--jobs` 未指定（默认 1），未出现 E004 |

**零自愈动作 = 零工具链缺陷暴露**；本批不给工具链留整改项。唯一建议（非缺陷）：`l2_check.py` 输出里加一列 `logic_gate` 占位，便于闸席把逻辑级结论直接并入 JSON，减少手抄。

## 五、下批前置建议（给 team-lead）

1. **#8 / #18 / #27 三件须回派**，其余 MAJOR 可随批挂账但要在 ROADMAP 记 R 编号。
2. 本批 5 件 MAJOR 全部属「算错但编译过」，说明 L1/L2 双层门禁**结构性拦不住数值错误** → 强烈建议 L3 向量门先落 5 条硬向量：SpanCalibRatio（典型标定）、AccumulatorSizing（200/100 bar）、SatPressToTemp（R410A 0 °C/40 °C 锚点）、WeighHopperRefillSeq（停止复位保持 3 拍）、WaterLangelierIndex（LOG 十进制锚点）。这 5 条都是本轮已定位的确切缺陷，正反馈收益最高。
