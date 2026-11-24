# ROUND_PLAN_R63（阶段一派单｜2026-11-21｜预算 ≤15 分钟）

> 配额裁决：R62 五抽挂账 7 处 ≥3 → R193 扩面触发：新件配额 16 → **13**，扩面族①「二阶/结构滤波族」≤6、族②「直流母线/ADC/测点监视族」≤5（本轮按族内深化取材，宁少勿滥）。
> **本轮目标 = 返修 5 件 + 新件 13 件 = 18 项动作**（如实登记，不注水）。
> 阶段一范围：仅盘点、锁定与派单，**不改任何组件代码、不写 JSONL / registry / ROADMAP**（阶段三执行）。
> 本轮**零检索**（WebSearch 0 次）：全部取材复用既有 RAW_NOTES 公开公式与 T0 标准语义，详见 `RAW_NOTES_R63.md`。

---

## 0 盘点看板（R63 阶段一实测）

| 指标 | 实测值 | 说明 |
|---|---|---|
| 总库组件数 | **1,112 / 10,000（11.12%）** | R62 收口后基数（+11 新件） |
| 今日（11-21） | **115 / 200** | R57~R62 六轮累计 |
| 距 1,200 里程碑 | **-88** | R63 完成后 1,125，余 75（约 7~8 轮） |
| ROADMAP 待办 | **41 条未勾 / 546 条已勾** | > 30 条阈值 → **按纪律本轮不追加新待办**（§5 只做卫生注记） |
| 源矩阵组级覆盖 | ✔ 9 / ◐ 30 / ☐ 0（共 39 组） | 全部组已开，处于「组内深化」阶段；本轮深化 T1-8 dsp-public-cookbook、T2-1 lgf-measurement 两个 ◐ 组 |
| 撞名拒单 | 本轮 12 条留痕（§2.3） | 含 R62 转办项 `ShlDwordEx/ShrDwordEx` 实测结论：**同义，拒立项** |

---

## 1 返修 5 项（批次 R，全部 P0/P1 优先于新件，PLC 专家单调用内完成）

| 序号 | 组件名 | 分类 | 版本 | 缺陷 | 修法要点 |
|---|---|---|---|---|---|
| R1 | `FB_DL_VfdDcBusRipple` | DL_Device | v1.0.1 → **v1.0.2** | R62-D1 严重 | 组态非法 `_bCfgBad` 只置标志不早退，`fUdNom=0` 直穿 L244 除法 → 段 3 末尾**结构早退**（出口三件套 bValid=FALSE + eErr 码 0710 + bError + RETURN），与同族 `FC_` 件口径一致 |
| R2 | `FB_DL_BiquadFilter` | DL_Algo | v1.0.1 → **v1.0.2** | R62-D2 严重 + D5 轻 | 稳定判据换 **Jury 三条件** `ABS(fA2)<1 AND (1+fA1+fA2)>0 AND (1-fA1+fA2)>0`；码 3735 语义与头注释同步；**V2b**（a1=−1.9, a2=−0.95 → 判 3735+冻结）与 **V2c**（a1=0, a2=−0.99 → 合法放行）写入头注释验收向量；D5：373A 路径不再复用 `bCfgBad`（改 `bValid+eErr` 表达） |
| R3 | `FB_DL_IonFanInterlock` | DL_Device | v1.0.1 → **v1.0.2** | R62-D3 中 | 按 R300 取「**实现串 bEnable**」口径：出口三报警位（bAlarmSpeed/bAlarmBalance/bAlarmFan）与 `bError` 全部串 `bEnable`，失能相不再外显 Failure 级假故障；头注释边界八同步订正 |
| R4 | `FB_DL_RailPowerSequence` | DL_Base | v1.0.2 → **v1.0.3** | R62-D4 中 | 单轨超时门控与推进判据同源致静默挂死 → 推进判据改「**沿 OR 电平**」双路（`rtFb.Q` 或电平已就位直过）；头注释写明「反馈预闭合」处置口径 |
| R5 | `FC_DL_PercentileRank` | DL_MathData | v1.0.1 → **v1.0.2** | R62-D7 轻 | `nNonFinite` 维持不外显，头注释改「**不外显，诊断请用 `FC_DL_SignalStatistics`**」二选一定稿（不改接口，只订正口径） |

### R4 附带核验（R62-D7 转办项）：`FB_DL_LineClearanceVerify` nResidueMax 负值前置判据

- **实测结论：已前置，免返修**。L119 组态闸第一判据 `(tConfirmWin <= T#0S) OR (nResidueMax < 0)` 先于 L174 的 `DINT_TO_UDINT(nResidueMax)` 执行，负值在转换前已被故障闸捕获；L174 另有 `OR (nResidueMax < 0)` 兜底项，负值路径无错误行为（3036 为信息级且居链末位，不覆盖故障码）。
- 处置：**不升级 v1.0.2**；R62-D7 该条在 REVIEW 挂账中按「复核不成立」销账（阶段三记账）。

### R3 同件顺带复核（不扩单，仅随单核对）

- R62-D6（轻）：段 0 `tonConfirm` 使用段 2 才计算的 `_bCfgBad`（上一拍值）。随 R3 返修时**仅核段序**：若段序调整代价小则一并消除（段 0 改用段 1 预派生组态位）；若牵动大则维持挂账，**禁止扩单**。

---

## 2 新件 13 件（批次 1–4，按依赖切 3/4/3/3）

### 2.1 候选表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_BcdToDint` | DL_MathData | FC_DL_ | 8 位 BCD→DINT（逐码元合法性闸） | `iec-std-wrapper`（T0-5 BCD 族 DWORD 位宽补口） | 低 | 1 |
| 2 | `FC_DL_DintToBcd` | DL_MathData | FC_DL_ | DINT→8 位 BCD（负值/越域闸） | `iec-std-wrapper`（T0-5 BCD 族 DWORD 位宽补口） | 低 | 1 |
| 3 | `FB_DL_EwmaFilter` | DL_Algo | FB_DL_ | EWMA 指数加权滑动平均（α 直接入参口径） | `self`（公开 EWMA 统计公式 clean-room） | 低 | 1 |
| 4 | `FC_DL_TrimmedMeanCalc` | DL_MathData | FC_DL_ | 双端截尾均值（稳健统计，委托排序） | `iec-std-wrapper`（T0 统计族补口） | 中 | 2 |
| 5 | `FC_DL_PearsonCorrCalc` | DL_MathData | FC_DL_ | 双通道皮尔逊相关系数（测点交叉诊断基元） | `iec-std-wrapper`（T0 统计族补口） | 中 | 2 |
| 6 | `FC_DL_BiquadCoeff` | DL_Algo | FC_DL_ | 二阶节系数生成（低通/高通/带通/陷波四型，RBJ 公式 clean-room） | `dsp-public-cookbook`（T1-8 ◐ 深化） | 中 | 2 |
| 7 | `FB_DL_OutlierFilter` | DL_Algo | FB_DL_ | MAD 野点剔除滤波（保持上有效值 + 真阶跃重基线） | `self`（公开 MAD 判据 clean-room，委托排序） | 中 | 2 |
| 8 | `FB_DL_BiquadCascade` | DL_Algo | FB_DL_ | 多节二阶节级联（≤4 节，逐节 Jury 稳定闸） | `dsp-public-cookbook`（T1-8 ◐ 深化） | 高 | 3 |
| 9 | `FB_DL_AdcNoiseFloorWatch` | DL_Device | FB_DL_ | ADC 测点底噪监视（静态期标准差 + 双限值） | `lgf-measurement`（T2-1 ◐ 深化） | 中 | 3 |
| 10 | `FB_DL_VfdOutputImbalance` | DL_Device | FB_DL_ | 变频输出三相电流不平衡/断相双判据监视 | `lgf-measurement`（T2-1 ◐ 深化） | 中 | 3 |
| 11 | `FB_DL_AdaptiveLmsFilter` | DL_Algo | FB_DL_ | LMS 自适应横向滤波（在线权重更新，干扰对消） | `dsp-public-cookbook`（T1-8 ◐ 深化） | 高 | 4 |
| 12 | `FB_DL_VfdCapAgingEst` | DL_Device | FB_DL_ | 母线电容老化趋势估计（纹波率长期基线漂移比） | `lgf-measurement`（T2-1 ◐ 深化） | 中 | 4 |
| 13 | `FB_DL_VfdPrechargeSeq` | DL_Device | FB_DL_ | 直流母线预充电回路时序监视（反馈窗+斜率+时限三闸） | `lgf-measurement`（T2-1 ◐ 深化） | 中 | 4 |

- 族①「二阶/结构滤波族」新件 = 5 件（#3/#6/#7/#8/#11）**≤ 6 ✔**；族②「直流母线/ADC/测点监视族」新件 = 5 件（#9/#10/#12/#13 + #5 相关性基元归统计族不计）→ 实际族② = 4 件（#9/#10/#12/#13）**≤ 5 ✔**。
- 子库分布：DL_Algo 5 / DL_Device 4 / DL_MathData 4（Base/Motion/Process 本轮无缺口候选，Algo 为 R267 族避让豁免——本轮主题即滤波族深化）。

### 2.2 批次依赖切分

- **批 1**（Level 0 纯函数 + 轻滤波 FB，零批内依赖）：1 / 2 / 3。
- **批 2**（统计/系数纯函数 + 委托件）：4 / 5（均委托 `FC_DL_SortIndexLReal` 或纯公式）；6（独立纯函数）；7（委托 `FC_DL_SortIndexLReal` 双次承接，R295 双承接口径）。
- **批 3**（有状态滤波/监视件）：8（判据与返修 R2 同源，头注释互引）；9 / 10（独立监视件）。
- **批 4**（有状态自适应/趋势/时序件）：11 / 12 / 13。
- 返修批 R 与批 1 并行启动；全部批次完成后统一终审。

### 2.3 撞名三查拒单留痕（12 条，R214 口径：同名精确 + 同义邻件 + 文件树三查）

| 拒单候选 | 查重结论 | 处置 |
|---|---|---|
| `FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx` | **R62 转办实测完成**：`FC_DL_ShlEx`/`FC_DL_ShrEx` 头注释明示「按 DWORD（32 位）主类型实现，BYTE/WORD 显式转换后调用」→ 显式命名对为凑数变体 | 拒立项；ROADMAP L948 建议阶段三勾销注记「同义，实测 R63」 |
| `FC_DL_ExpSat` | registry 已有同名（reg=1） | 拒（重复提案） |
| `FC_DL_PowSafe` / `FC_DL_Atan2Safe` / `FC_DL_HypotSafe` | `FC_DL_ExptEx` / `FC_DL_Atan2Ex` / `FC_DL_Hypot3D` 已存 | 拒（同义邻件） |
| `FC_DL_LogSafe` | registry 已有（reg=1） | 拒（重复提案） |
| `FB_DL_HysteresisSwitch` | `FC_DL_Hysteresis` 已存（迟滞比较属主） | 拒（同义邻件） |
| `FB_DL_RtoKeeper` / `FB_DL_RtoTimer` | `FB_DL_RtoEx` 已存（保持型定时器属主） | 拒（同义邻件） |
| `FB_DL_FreqDivide` | `FB_DL_EdgeDivider` 已存（分频属主） | 拒（同义邻件） |
| `FC_DL_LinRegSlope` / `FC_DL_LinRegress` | `FC_DL_TrendSlopeCalc` 已存（回归斜率属主） | 拒（同义邻件） |
| `FB_DL_AllpassFilter` | `FB_DL_BiquadFilter` eType 已覆盖全通结构 | 拒（拆件即凑数） |
| `FB_DL_MasterSlaveEdge` / `FB_DL_EdgeSync` | `FB_DL_EdgeMasterSlaveSync` 已存 | 拒（同义邻件） |
| `FB_DL_BacklashComp` | `FB_DL_AxisBacklashComp` 族 3 件 + `FB_DL_BacklashCompensator` 已存 | 拒（同义邻件） |
| `FB_DL_MovingAverageFilter` / `FB_DL_MeanFilter` / `FB_DL_MedianFilter` | `FB_DL_MovingAverage` / `FB_DL_MedianFilter` 已存 | 拒（重复/同义） |

---

## 3 扩面复核（R193 两族逐件扫查，文本锚定 + 语义通读，2026-11-21 实测）

### 族①「二阶/结构滤波族」（DL_Algo，核「稳定/系数闸」是否存在 R62-D2 同族缺陷）

| 件 | 扫查锚点 | 结论 |
|---|---|---|
| `FB_DL_LowPassFilter` | 系数内部派生（L126 `MIN(MAX(fDt/(fTfEff+fDt),0),1)`），无外部系数判据；L133 非有限双判 + L137 RETURN | **PASS**（系数受约束在 0..1，无 Jury 判据需求） |
| `FB_DL_HighPassFilter` | L135 零常数旁路 + L137 系数钳位；L144 非有限 + L149 RETURN；限幅对调自修复 | **PASS** |
| `FB_DL_NotchFilter` | L19/L25 系数分母闸（1+α 近零拒绝重算旁路）+ 中心频率奈奎斯特 0.45 闸 + L124 故障级提前 RETURN | **PASS** |
| `FB_DL_FirFilter` | 系数和归一锁存（`|Σ−1|<1E-6`，L11/L119-120），系数 NaN 归一破约路径覆盖，样本非有限跳过不入栈 | **PASS** |
| `FB_DL_SecondOrderFilter` | L116 tSampleTime<10ms 钳位闸先于 L126 `1.0/fDt`；系数双线性内部重算 + L24 直流增益守恒校验；无外部稳定判据 | **PASS** |
| `FB_DL_BiquadFilter` | R62-D2 已挂账（Jury 三条件缺失，`|a2−a1|<1` 伪判据） | **挂账 → 本轮返修 R2** |

- 族①定性：缺陷仅存在于「外部下发系数 + 显式稳定判据」形态的 BiquadFilter；其余五件系数均为内部派生（α∈[0,1] 钳位 / 归一锁存 / 分母闸），**无 R62-D2 同族缺陷**。新件 #6/#8 的系数闸判据一律采用 Jury 三条件（返修 R2 固化口径），禁沿用伪判据。

### 族②「直流母线/ADC/测点监视族」（DL_Device，核「入参兼作除子是否结构早退 RETURN」）

| 件 | 扫查锚点 | 结论 |
|---|---|---|
| `FB_DL_VfdDcBusRipple` | L160/L166 置 `_bCfgBad` **无 RETURN**，L244 `(_fAvg / fUdNom)` 在 L292 早退段之前仍可达 → `fUdNom=0` 直穿除法 | **挂账（确认 R62-D1）→ 本轮返修 R1** |
| `FB_DL_InverterGridSync` | 段 3（输入非有限）/段 4（容差组态）两处**结构早退**（三件套 + 掩码 + 定时器断输入 + RETURN，L154/L170） | **PASS** |
| `FB_DL_BrakeResistorThermal` | L85 组态闸先行（周期/电流/电阻/τ/额度五路正域闸 + 额度一致性校验，除子先过闸）；L112 组态非法同拍锁存 `_bFault` 并迁 eFault，除法（L121/L127/L150/L157）位于 eIdle/eRun 分支，组态故障拍分支不可达 | **PASS** |
| `FB_DL_AnalogTransmitter` | 全件唯一除法 L277 受 L273 `_bSpanDegenerate`（NaN 或 ABS<1E-9）分支闸保护，退化走回退分支不执行除法；量程对调自修复为该件声明设计 | **PASS**（分支闸等效防护，无结构早退但除法不可达） |
| `FB_DL_NtcChannelHealth` | 全件无除法（纯分级逻辑，仅 ABS/MIN） | **PASS** |

- 族②定性：监视族「除子结构早退」纪律在 GridSync/BRT 两件已完整落地；AT 件以分支闸等效满足；唯一实锤即 VfdDcBusRipple（已挂账返修）。新件 #9/#10/#12/#13 一律执行「组态域闸 → 出口三件套 → RETURN」结构早退口径（族② 判据固化）。

---

## 4 新件功能规格（可直接转发编码专家）

### 通用要求（13 件一律适用，与 ROUND_PLAN_R62 §3 相同口径，摘要重申）

1. 头注释七项齐全 + 溯源三行（Origin / License MIT / Reference）；零检索轮 Origin 写「公开公式 clean-room，参考 <出处> 分类与参数域」。
2. 100% 中英双语同行注释，单位标注定裂（`[%]` `[位]` `[拍]` `[Hz]` `[V]` `[A]` `[ms]` `[工程单位]`）。
3. FC_ 纯函数：域闸 → 出口三件套（返回 BOOL + bValid + bError）+ eErr 逐出口赋值 + RETURN 早退；委托调用返回值与输出映射**双承接后合取**（R295）。
4. FB_ 有状态件：段 0 无条件刷新边沿/定时器；CASE+ELSE 兜底落安全相；首拍 `_bInit` 全量初始化；组态域闸 → 三件套 → **RETURN 结构早退**（族② 判据固化，R1 教训）。
5. 浮点禁 `=` 判等；NaN/±Inf 逐个点名闸；除子与窗长 `≥1` 证明注释；禁 GVL / VAR_EXTERNAL / 物理地址 / 厂商库 / 指针。
6. 码位阶段三按子库游标实测分配，禁沿用本文件建议段。

---

### 批 1-① `FC_DL_BcdToDint`｜DL_MathData｜FC_DL_｜低｜`iec-std-wrapper`

**功能规格**：8 位 BCD（DWORD，8 个半字节）→ DINT。输入 `udBcd : DWORD`；输出 `nOut : DINT`、`bBadDigit : BOOL`（非法码元）、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`，返回 BOOL。
- 判据：逐半字节（SHR+AND 16#F，常量提级）取 8 个码元，任一 >9 → `nOut:=0`、故障级码、早退（**禁静默按半字节折算**）；合法则按权值 `10^k` 累加（权值表常量，禁运行时 EXPT）。
- 域证明（头注释）：BCD 8 位最大 99999999 < 2,147,483,647（DINT 域），**无溢出可能**，注释写死，无溢出分支。
- 分工声明：`FC_DL_BcdToByte/BcdToWord/BcdToUdint` 为既有 BCD 族，本件补 DWORD 8 位宽，互引。

**边界向量**：① `16#00000000`→0；② `16#99999999`→99999999 精确；③ `16#0000000A`→故障+`bBadDigit`；④ `16#12345678`→12345678；⑤ `16#00000007`→7（前导零）；⑥ 每个半字节逐一为 A~F 各一条（或抽验 A/F 两端）。

---

### 批 1-② `FC_DL_DintToBcd`｜DL_MathData｜FC_DL_｜低｜`iec-std-wrapper`

**功能规格**：DINT → 8 位 BCD（DWORD）。输入 `nIn : DINT`；输出 `udBcd : DWORD`、`bOvF : BOOL`（越域）、`bValid/eErr/bError`，返回 BOOL。
- 判据顺序：① `nIn < 0` → 故障级码 + `udBcd:=0` 早退（负值不可 BCD 表示，禁取绝对值回绕）；② `nIn > 99999999` → 越域故障 + `bOvF` 早退；③ 正常：逐位 `MOD 10 / DIV 10` 提取（常量 DL_BCD_MAX=99999999，权值累装入 DWORD）。
- 分工声明：与 `FC_DL_ByteToBcd/WordToBcd/UdintToBcd` 互引，本件为 DINT 带符号域入口（负值显式拒绝为与 UDINT 版本的**行为差异**，头注释写死）。

**边界向量**：① `0`→`16#00000000`；② `99999999`→`16#99999999`；③ `-1`→故障早退；④ `100000000`→越域故障+`bOvF`；⑤ `12345678`→`16#12345678`。

---

### 批 1-③ `FB_DL_EwmaFilter`｜DL_Algo｜FB_DL_｜低｜`self`（公开 EWMA 公式 clean-room）

**功能规格**：EWMA 指数加权滑动平均，`fOut := fOut + fAlpha × (fIn − fOut)`，α **直接入参**（离散统计/SPC 口径）。
- 引脚：`bEnable : BOOL`；`fIn : LREAL`（输入 [工程单位]）；`fAlpha : LREAL`（平滑系数 [−]，域闸 (0, 1]，开区间下界防输出冻结）；输出 `fOut : LREAL`、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`。
- 实现口径：α 域闸 `fAlpha <= 0 OR fAlpha > 1` → 组态码 + 三件套 + RETURN（**组态非法结构早退**）；`fIn` 非有限 → 本拍拒绝更新保持上拍 + 故障码；`bEnable=FALSE` → `fOut` 冻结最后有效值（纯监视滤波，不驱动功率级，注释写明理由）；首拍 `_bInit` → `fOut := fIn`（首样本直通，禁输出 0 假跳变）。
- 分工声明（R216）：`FB_DL_LowPassFilter` 为**连续时间常数口径**（α 由 tTf/tDt 派生，一阶 RC 语义）；本件为**调用方直接给 α 的统计平滑口径**（EWMA/SPC 语义）；`FB_DL_MovingAverage` 为等权滑窗。三者选型对照进 `MANUAL_DL_Algo`。

**边界向量**：① α=1 → 直通 `fOut=fIn`；② α=0 → 组态码早退（禁冻结伪装正常）；③ α=0.5 阶跃 → 逐拍 50% 收敛无超调；④ `fIn=NaN` → 保持 + 故障码；⑤ 首拍直通；⑥ `bEnable=FALSE` → 冻结。

---

### 批 2-① `FC_DL_TrimmedMeanCalc`｜DL_MathData｜FC_DL_｜中｜`iec-std-wrapper`

**功能规格**：双端截尾均值（稳健统计，抗野点污染的均值口径）。
- 引脚：`afSamples : ARRAY[0..255] OF LREAL`（样本 [工程单位]）；`nCount : DINT`（有效样本数 [个]，1..256）；`uTrimLo : USINT`（低端截去个数 [个]）；`uTrimHi : USINT`（高端截去个数 [个]）；输出 `fMean : LREAL`（截尾均值 [工程单位]）、`nEff : DINT`（参与均值样本数 [个]）、`bValid/eErr/bError`，返回 BOOL。
- 实现口径：NaN 样本逐条剔除（`nNonFinite` 局部计数，**不外显**，头注释注明「诊断请用 `FC_DL_SignalStatistics`」，R62-D7 口径固化）；剔除后 `nEff := nCount − nNonFinite`；域闸 `nEff ≤ 0` → 故障早退；`uTrimLo + uTrimHi >= nEff` → 组态码早退（禁把截尾做成空集）；**委托** `FC_DL_SortIndexLReal` 升序索引（返回值/输出双承接 R295），对索引区间 `[uTrimLo, nEff−1−uTrimHi]` 求均值；除子 `(nEff − uTrimLo − uTrimHi) ≥ 1` 证明注释。
- 分工声明：`FC_DL_MeanAbsDevCalc`（离散度）/ `FC_DL_MedianAbsDev`（稳健离散度）/ `FB_DL_MovingAverage`（滑窗均值）互引；本件为**双端截尾均值**（位置量），填稳健位置估计缺口。

**边界向量**：① 全同样本 + 任意 trim → 均值=该值；② trim=0/0 → 等价普通均值（与 `FC_DL_` 普通均值口径一致）；③ `uTrimLo+uTrimHi = nEff` → 组态码早退；④ `nEff−trim = 1`（只余 1 个）→ 均值=该样本；⑤ `nCount=0` → 故障；⑥ `nCount=257` → 越域早退；⑦ 含 2 个 NaN → `nEff` 正确缩减（向量给量化值）；⑧ trim 单端不对称（lo=2, hi=0）→ 区间正确。

---

### 批 2-② `FC_DL_PearsonCorrCalc`｜DL_MathData｜FC_DL_｜中｜`iec-std-wrapper`

**功能规格**：双通道皮尔逊相关系数 r ∈ [−1, 1]，测点交叉诊断（同源传感器相关失效、通道接错线检测）基元。
- 引脚：`afX : ARRAY[0..255] OF LREAL`（通道 X [工程单位]）；`afY : ARRAY[0..255] OF LREAL`（通道 Y [工程单位]）；`nCount : DINT`（样本对数 [对]，1..256）；输出 `fCorr : LREAL`（相关系数 [−]）、`nPairs : DINT`（有效样本对数 [对]）、`bValid/eErr/bError`，返回 BOOL。
- 实现口径：**配对剔除**——X 或 Y 任一为非有限则整对剔除（头注释写死口径，非各自剔除）；`nPairs ≤ 2`（相关系数无定义）→ 故障早退；均值/协方差/标准差逐对累加，除子 `SQRT(Sxx×Syy)`：`Sxx≤0 OR Syy≤0`（常数通道）→ 常量退化故障码早退（**禁除零**）；`ABS(fCorr) > 1.0`（浮点数值误差）→ 钳回 ±1 并置信息级码；`ABS(Sxx×Syy) < 1.0E-12` 防下溢分支。
- 分工声明：`FB_DL_CrossCorrelationDelay` 为**互相关时延估计**属主（求滞后拍数）；本件为**归一化相关强度**；`FB_DL_SensorPairPlausibility` 为偏差/漂移互校。三件互引。

**边界向量**：① 完全线性 `y=2x` → r≈+1（|r|≤1 断言）；② `y=−x` → r≈−1；③ 独立随机 → |r|<0.1；④ X 常数 → 常量退化故障；⑤ 单样本/双样本 → 故障早退；⑥ X 含 1 个 NaN → 该对剔除，`nPairs` 量化断言；⑦ `nCount=0` → 故障。

---

### 批 2-③ `FC_DL_BiquadCoeff`｜DL_Algo｜FC_DL_｜中｜`dsp-public-cookbook`（T1-8）

**功能规格**：二阶节五系数生成器（低通/高通/带通/陷波四型），为 `FB_DL_BiquadFilter` / `FB_DL_BiquadCascade` 提供下发系数，闭合「设计→下发」链。
- 引脚：`eType : E_DL_BiquadType`（属主本文件：eLowPass / eHighPass / eBandPass / eNotch，每项中文注释）；`fFs : LREAL`（采样频率 [Hz]，>0）；`fF0 : LREAL`（中心/截止频率 [Hz]，`0 < fF0 < 0.45×fFs` 奈奎斯特闸）；`fQ : LREAL`（品质因数 [−]，域闸 `DL_BQ_Q_MIN=0.1 .. DL_BQ_Q_MAX=20.0`）；输出 `fB0,fB1,fB2,fA1,fA2 : LREAL`（归一化系数 a0=1 [−]）、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`，返回 BOOL。
- 实现口径：域闸（fFs≤0 / fF0 越域 / fQ 越域 / 任一非有限）→ 五系数全 0 + 故障级码 + 三件套 + **RETURN 早退**；四型系数式按公开二阶节设计公式（RBJ Audio EQ Cookbook 类公开公式）clean-room 重写，中间量 `fW0=2π·fF0/fFs`、`fAlpha=sin(w0)/(2Q)` 全部常量提级（2π、0.45 等禁魔法数）；`fA2` 归一化除法除子 `1+fAlpha/fA0` 用 `ABS(fA0den) < DL_FLOAT_EPS` 闸（分母近零故障，NotchFilter 同款防御）。
- ** Jury 一致性声明（R2 教训）**：头注释写明「本件产出的系数建议由 `FB_DL_BiquadFilter`/`BiquadCascade` 的 Jury 三条件闸复验；两闸口径一致（`|a2|<1 ∧ 1+a1+a2>0 ∧ 1−a1+a2>0`）」。
- 分工声明：`FB_DL_NotchFilter`（陷波一体机：内算内滤）/ `FB_DL_SecondOrderFilter`（巴特沃斯二阶：内算内滤）为**内算型**；本件只产系数**不下发执行**，与两个内算型互引写明「现场自行组合」用途。

**边界向量**：① `fFs=1000, fF0=100, fQ=0.7071` 低通（巴特沃斯）→ b0≈0.06745、b1≈0.1349、b2≈0.06745、a1≈−1.1430、a2≈0.4128（公开设计值，头注释作验收向量）；② 同参高通 → 系数为低通镜像（b0/b2 互换语义）；③ `fF0=0.46×fFs` → 奈奎斯特闸故障早退；④ `fQ=0` → 故障；⑤ `fFs=0` → 故障；⑥ 陷波型 `fF0=50, fFs=1000, fQ=5` → 在 50Hz 处增益 ≈0（定性向量）；⑦ `fQ=25` → 越域故障。

---

### 批 2-④ `FB_DL_OutlierFilter`｜DL_Algo｜FB_DL_｜中｜`self`（公开 MAD 判据 clean-room）

**功能规格**：MAD 野点剔除滤波器：滑窗中值 + 绝对偏差中值（MAD）判野点，野点丢弃并保持上次有效输出。
- 引脚：`bEnable : BOOL`；`fIn : LREAL`（输入 [工程单位]）；`nWinLen : DINT`（窗长 [个]，域 4..64，变更沿清窗）；`fNSigma : LREAL`（MAD 倍数 [−]，域 (0, 10]，默认 4.0）；`tHoldMax : TIME`（野点连续保持上限 [ms]，超时判测点坏）；输出 `fOut : LREAL`（滤波输出 [工程单位]）、`nReject : UDINT`（累计剔除计数 [个]）、`bHold : BOOL`（本拍处于保持态）、`bValid/eErr/bError : BOOL/UDINT/BOOL`。
- 实现口径：
  - 委托 `FC_DL_SortIndexLReal` 两次（窗内样本取中值；窗内 `|x−median|` 序列再取中值 ×1.4826 得稳健 σ̂），**两次委托均双承接**（R295）；窗长固定容量 64 数组，禁动态分配；
  - 判据 `ABS(fIn − fMedian) > fNSigma × fSigmaHat + DL_MAD_EPS` → 野点：不入窗、`fOut` 保持上次有效、`bHold:=TRUE`、`nReject+1`；
  - **真阶跃处置（关键边界，头注释写死）**：连续剔除计数 `_nRejectRun ≥ nWinLen/2` → 判「真实阶跃」（不是野点），以新样本重置窗基线（清窗 + `fIn` 入窗直通）+ 信息级码——禁「持续阶跃被永久拒绝」死锁；
  - `tHoldMax` 到时仍保持 → 故障级码 + `bValid=FALSE`（测点疑似坏）；
  - 非有限 `fIn` → 视同野点丢弃（计数单列 `nNonFinite` 局部，不外显）；
  - `bEnable=FALSE` → 输出冻结 + 窗保留（纯监视件注释）。
- 分工声明：`FB_DL_MedianFilter`（输出=中值，无判据）/ `FB_DL_SignalFrozenDetect`（不变性监视）/ `FB_DL_SensorDriftBaseline`（基线漂移）互引；本件为**单点野点剔除 + 保持**。

**边界向量**：① 平稳序列 + 单点尖峰（10×σ）→ 剔除、`fOut` 保持、`bHold` 单拍；② 尖峰后立即回落 → 窗无污染；③ 真阶跃（后续全部为新值）→ 连续剔除达 `nWinLen/2` 后重基线直通；④ `fNSigma=0` → 组态码早退；⑤ 保持超 `tHoldMax` → `bValid=FALSE`；⑥ `nWinLen=3` → 越域钳位+码；⑦ `nWinLen` 变更沿清窗；⑧ 首拍直通。

---

### 批 3-① `FB_DL_BiquadCascade`｜DL_Algo｜FB_DL_｜高｜`dsp-public-cookbook`（T1-8）

**功能规格**：多节二阶 IIR 级联（≤4 节，Direct Form II 每节独立状态），用于高阶滤波（8 阶=4 节）现场组合。
- 引脚：`bEnable/bResetState : BOOL`；`fIn : LREAL`；`aB0,aB1,aB2,aA1,aA2 : ARRAY[0..3] OF LREAL`（各节系数 [−]）；`nStages : DINT`（节数 [节]，域 1..4）；`fOutMin/fOutMax : LREAL`（输出钳位域 [工程单位]）；输出 `fOut : LREAL`、`bSat : BOOL`、`bCfgBad : BOOL`、`bValid/eErr/bError`。
- 实现口径：
  - **逐节 Jury 稳定闸**（返修 R2 固化判据）：任一节 `NOT (ABS(a2)<1 AND (1+a1+a2)>0 AND (1−a1+a2)>0)` 或任一系数非有限 → `bCfgBad` + 故障级码 + 三件套 + **RETURN 结构早退**（`fOut` 冻结最后有效值）；
  - 节间串接：`fMid[i]` 逐节递推（固定 `ARRAY[0..3] OF LREAL` 状态 `w1[i],w2[i]`），仅前 `nStages` 节参与；
  - 系数变更沿（任一活动系数 `ABS(new−old)>1.0E-9`）→ 全链状态清零（防新旧系数混算，BiquadFilter 同口径）；
  - 输出钳位 + `bSat`；`bResetState` 单拍清全链；`bEnable=FALSE` → `fOut:=0`、全链状态清零（安全侧：下游控制量，注释写明）；
  - `nStages` 越域 → 组态码早退；未激活节（`i >= nStages`）的系数**不参与判据**（头注释写明，避免死节坏系数误锁）。
- 分工声明：`FB_DL_BiquadFilter` 单节属主（R2 返修件）；本件多节级联，互引并注明「单节需求禁用本件（状态开销×4）」。

**边界向量**：① 4 节低通级联（每节 RBJ 巴特沃斯 2 阶）阶跃 → 单调收敛无发散；② 节 3 系数失稳（a2=−1.5, a1=−1.9 违 Jury）→ `bCfgBad` + 全链冻结（V2b 反例族向量）；③ `nStages=0` / `=5` → 越域故障早退；④ 节 4 系数坏但 `nStages=2` → 不影响（死节豁免）；⑤ 在线改节 1 系数 → 全链清零；⑥ `bEnable=FALSE` → 全零；⑦ 输出大信号钳位 + `bSat`。

---

### 批 3-② `FB_DL_AdcNoiseFloorWatch`｜DL_Device｜FB_DL_｜中｜`lgf-measurement`（T2-1）

**功能规格**：ADC 测点底噪监视：静态期窗内标准差与上限比较（接地/屏蔽劣化、前端供电噪声的早期征兆）。
- 引脚：`bEnable : BOOL`；`fMeas : LREAL`（测点实测值 [工程单位]）；`bStatic : BOOL`（静态期标志：过程稳态且无操作，由调用方给）；`nWinLen : DINT`（窗长 [个]，域 16..256，变更沿清窗）；`fNoiseLim : LREAL`（底噪上限 [工程单位]，>0）；`fHystPct : LREAL`（判据迟滞 [%]，默认 10.0）；输出 `fNoiseStd : LREAL`（窗内标准差 [工程单位]）、`bNoiseHigh : BOOL`（带迟滞）、`nFill : DINT`（窗填充数 [个]）、`bValid/eErr/bError`。
- 实现口径：
  - 环形窗 + `_nFill` 除子（**钳 ≥1**，首填期均值偏小防错，R61-D4 固化）；`bStatic` 变更沿清窗（防静/动混合窗污染标准差口径，头注释写明）；
  - 标准差除子 `DINT_TO_LREAL(_nFill − 1)`：`_nFill < 2` → 不计算（判据挂起，`bValid=FALSE`，除零防护）；
  - `fNoiseLim ≤ 0` 或非有限 → 组态码 + 三件套 + **RETURN 结构早退**（族② 判据固化）；
  - `fMeas` 非有限 → 丢弃不入窗、`nNonFinite` 局部计数超窗半 → 故障 + `bValid=FALSE`；
  - 判据迟滞：`fNoiseStd > fNoiseLim` 触发，回落 `< fNoiseLim×(1−fHystPct/100)` 复原；
  - `bEnable=FALSE` → 判据复位 + `fNoiseStd` 冻结（纯监视件注释）。
- 分工声明：`FB_DL_SignalFrozenDetect`/`FB_DL_SignalStuckWatch` 监视**不变性**；`FB_DL_SignalStatistics` 为通用统计出口；本件为**静态期噪声幅度**监视（动静时序由 `bStatic` 外部给定），四件互引。

**边界向量**：① 恒定值 → std=0、`bNoiseHigh=FALSE`；② 注入 ±0.5 [工程单位] 方波抖动 → std≈0.5，超限触发；③ 迟滞抖动（限值上下 5% 波动 < 迟滞 10%）→ 不反复跳；④ `fNoiseLim=0` → 组态早退；⑤ `_nFill=1` → 判据挂起 `bValid=FALSE`；⑥ `bStatic` 翻转 → 清窗 `nFill=0`；⑦ 全 NaN → 故障。

---

### 批 3-③ `FB_DL_VfdOutputImbalance`｜DL_Device｜FB_DL_｜中｜`lgf-measurement`（T2-1）

**功能规格**：变频器输出侧电机三相电流不平衡 + 断相双判据监视（匝间短路/断线/接触器单相粘连的早期征兆）。
- 引脚：`bEnable : BOOL`；`fIu, fIv, fIw : LREAL`（三相电流实测 [A]）；`fImbLimPct : LREAL`（不平衡度上限 [%]，默认 10.0）；`fDropPct : LREAL`（断相判据：最小相低于均值的百分比 [%]，默认 20.0）；`fHystPct : LREAL`（迟滞 [%]，默认 5.0）；输出 `fImbPct : LREAL`（不平衡度 `(Imax−Imin)/Iavg×100` [%]）、`bImbHigh : BOOL`、`bPhaseDrop : BOOL`、`bValid/eErr/bError`。
- 实现口径：
  - 三相任一非有限 → 故障码 + 三件套 + **RETURN 结构早退**；
  - 待机判据：`Iavg < DL_VOI_IDLE_EPS`（常量 0.5 [A]，提级禁魔法数）→ 不计算、`bImbHigh/bPhaseDrop:=FALSE`（待机态无判据意义，注释写明）；
  - 组态闸 `fImbLimPct ≤ 0 OR fDropPct ≤ 0 OR fHystPct < 0` → 组态码 + 早退；`fImbLimPct ≥ 100` → 组态警告（信息级，判据永假）；
  - 两判据独立输出、独立迟滞（上升触发 / 回落 `lim×(1−fHyst/100)` 复原）；
  - `bEnable=FALSE` → 双判据复位 FALSE、`fImbPct` 冻结（纯监视注释）。
- 分工声明：`FB_DL_PhaseLossGuard` 为**电网输入侧断相**、`FB_DL_PhaseNeutralImbalance` 为**相-中性不平衡**、`FB_DL_VfdThermalDerate` 为**变频热降额**；本件为**变频输出侧电机电流**，四件互引（`MANUAL_DL_Device` 写明「输入侧/输出侧勿混用」）。

**边界向量**：① 三相均衡（500/500/500）→ 双 FALSE；② `fIu=250`（掉 50%）→ `fImbPct≈50`、`bPhaseDrop=TRUE`；③ 单相 `=0`（断相）→ `bPhaseDrop=TRUE` + 不平衡超限；④ `fImbLimPct=0` → 组态早退；⑤ 待机（三相 <0.5A）→ 双 FALSE 不计算；⑥ `fIu=NaN` → 结构早退故障；⑦ 迟滞抖动不反复跳；⑧ `bEnable=FALSE` → 复位。

---

### 批 4-① `FB_DL_AdaptiveLmsFilter`｜DL_Algo｜FB_DL_｜高｜`dsp-public-cookbook`（T1-8）

**功能规格**：LMS 自适应横向滤波器（N 抽头权重在线更新 `w[k] += 2μ·e·x[k]`），周期干扰对消/主动降噪的现场可整定基元。
- 引脚：`bEnable : BOOL`；`bWipeW : BOOL`（单拍权重清零）；`fRef : LREAL`（参考输入 [工程单位]——与干扰相关的信号）；`fDesired : LREAL`（主输入 [工程单位]）；`uTaps : USINT`（抽头数 [个]，域 4..32，变更沿清权重）；`fMu : LREAL`（步长 [−]，域 (0, `DL_LMS_MU_MAX=0.1`]）；输出 `fErr : LREAL`（误差 = fDesired − fOut [工程单位]）、`fOut : LREAL`（滤波输出 [工程单位]）、`fWEnergy : LREAL`（权重平方和 [−]，收敛/发散诊断）、`bValid/eErr/bError`。
- 实现口径：
  - 延迟线固定 `ARRAY[0..31] OF LREAL`，每拍移位入 `fRef`（`uTaps` 越域钳位 + 信息级码，活动抽头数才参与）；
  - `fMu` 域闸（≤0 或 > 上限）→ 组态码 + 权重冻结 + RETURN 早退；
  - 任一输入非有限 → **权重冻结 + 故障码 + `bValid=FALSE`**（禁污染权重——权重污染后需 `bWipeW` 才能恢复，头注释写明该不可自动恢复性）；
  - `fWEnergy > DL_LMS_W_MAX`（常量 1.0E12 [−]）→ 发散监视信息级码 + 建议减小 μ（不自动清权重，诊断出口）；
  - `bWipeW` 单拍 → 全权重清零（段 0 R_TRIG 无条件刷新）；
  - `bEnable=FALSE` → 权重保留但停止更新、`fErr` 冻结（注释写明理由：现场断使能调试时不丢已收敛权重）。
- 分工声明：`FB_DL_BiquadFilter`/`BiquadCascade` 为**固定系数**族；本件为**在线自适应**族；`FB_DL_DisturbanceObserver` 为观测器路线。互引 + MANUAL 选型段（「系数已知用 Biquad、干扰特征未知用 LMS」）。

**边界向量**：① `fRef=0` → 权重不增长、`fErr=fDesired`；② 正弦干扰 + 相关参考 → `fErr` 包络逐拍递减（定性收敛向量，头注释给 N 拍对比表）；③ `fMu=0` → 组态早退权重冻结；④ `fRef=NaN` 单拍 → 权重冻结 + 故障（下一拍恢复后 `fErr` 不含污染：权重未变断言）；⑤ `uTaps=100` → 钳 32 + 信息级；⑥ `bWipeW` → `fWEnergy=0`；⑦ 权重平方和超阈 → 信息级不锁存。

---

### 批 4-② `FB_DL_VfdCapAgingEst`｜DL_Device｜FB_DL_｜中｜`lgf-measurement`（T2-1）

**功能规格**：母线电容老化趋势估计：纹波率实测值相对投运基线的长期比值监视（电解电容容值衰减 → 纹波率单调爬升的运维预警）。
- 引脚：`bEnable : BOOL`；`fRipplePct : LREAL`（纹波率实测 [%]，**由 `FB_DL_VfdDcBusRipple` 出口注入**，本件不实例依赖只收数值）；`fRippleBasePct : LREAL`（投运基线纹波率 [%]，>0）；`fAgingLimPct : LREAL`（劣化阈值 [−] 相对基线百分比，默认 50.0 即 150% 判劣化）；`fHystPct : LREAL`（迟滞 [%]，默认 5.0）；输出 `fRippleRatioPct : LREAL`（基线比 `fRipplePct/fRippleBasePct×100` [%]）、`bAgingHigh : BOOL`（带迟滞）、`bValid/eErr/bError`。
- 实现口径：
  - **组态闸结构早退（族② 判据）**：`fRippleBasePct ≤ 0` 或非有限 → 组态码 + 三件套 + RETURN（除子直穿防线，R1 同族教训出厂即正确）；
  - `fRipplePct < 0` → 该拍拒绝（丢弃 + 信息级计数），不影响趋势判据；
  - 判据：`fRippleRatioPct > 100 + fAgingLimPct` 触发 `bAgingHigh`，回落 `100 + fAgingLimPct×(1−fHystPct/100)` 复原；
  - `fAgingLimPct ≤ 0` → 组态码早退；
  - 负载可比性声明（头注释写死）：本件假设同负载段比较，负载段切换时调用方应 `bEnable` 短暂断开复位迟滞态——本件不自动判负载（保持单一职责）；
  - `bEnable=FALSE` → `bAgingHigh` 复位 + 比值冻结（运维趋势件，不丢历史，注释写明）。
- 分工声明：`FB_DL_VfdDcBusRipple`（瞬时纹波，R1 返修件）/ `FB_DL_BrakeResistorThermal`（制动热）/ `FB_DL_VfdThermalDerate`（降额策略）互引；本件为**长期老化趋势**，MANUAL 写明「瞬时监视与趋势估计分层使用」。

**边界向量**：① `fRipplePct=fRippleBasePct` → 比值 100%、`bAgingHigh=FALSE`；② 比值爬到 151%（限 150%）→ 触发；③ 回落 148%（迟滞未满足）→ 保持触发；④ 回落 142% → 复原；⑤ `fRippleBasePct=0` → 组态早退（R1 同族回归向量）；⑥ `fRippleBasePct=NaN` → 组态早退；⑦ `fRipplePct=NaN` → 该拍拒绝不触发；⑧ `fAgingLimPct=0` → 组态早退（判据永假）。

---

### 批 4-③ `FB_DL_VfdPrechargeSeq`｜DL_Device｜FB_DL_｜中｜`lgf-measurement`（T2-1）

**功能规格**：直流母线预充电回路时序监视：接触器反馈窗 + 电压上升斜率 + 总时限三闸（预充电阻过热、接触器卡阻、整流缺相的启动期保护）。
- 引脚：`bEnable : BOOL`；`bKmCmd : BOOL`（预充接触器指令）；`bKmFb : BOOL`（接触器辅助反馈）；`fUdMeas : LREAL`（母线电压实测 [V]）；`fUdNom : LREAL`（额定母线电压 [V]，>0）；`fUdTargetPct : LREAL`（预充完成阈值 [%] 相对额定，域 (0,100]，默认 90.0）；`fSlopeMinPctS : LREAL`（最小电压上升斜率 [%/秒]，>0，默认 5.0）；`tFbWindow : TIME`（反馈确认窗 [ms]，默认 T#2S）；`tPrechargeMax : TIME`（预充总时限 [ms]，默认 T#15S）；输出 `bPrechargeDone : BOOL`、`bPrechargeFault : BOOL`（锁存）、`eState : E_DL_PrechargePhase`（属主本文件）、`bValid/eErr/bError`。
- 实现口径：
  - **组态闸结构早退（族② 判据）**：`fUdNom ≤ 0` / `fUdTargetPct` 越域 / `fSlopeMinPctS ≤ 0` / `tFbWindow ≤ 0` / `tPrechargeMax ≤ 0` / 任一非有限 → 组态码 + 三件套 + RETURN；
  - 状态机 `E_DL_PrechargePhase`（每项中文注释）：`eIdle`（待机）/ `eWaitFb`（指令后等反馈，`TON` 反馈窗）/ `eRamp`（斜率监视：斜率 = 移动窗 `Δ(电压%) / Δt`，窗常量提级）/ `eDone`（完成）/ `eFault`（锁存故障）——`CASE + ELSE` 兜底落 `eFault`；
  - 失败锁存 `bPrechargeFault` + `_bFaultLatch`：反馈超窗 / 斜率低于下限持续 `fSlopeGraceT`（常量）/ 总时限到 —— 任一触发；**锁存解除式**：`bResetCmd`（输入引脚）上升沿清锁存回 `eIdle`（终审两式 1：解除式可达自证写入头注释）；
  - `fUdMeas` 非有限 → 故障级码（运行期测点坏，斜率计算挂起不误判卡阻——该拍跳过斜率判据，头注释写明）；
  - `bKmCmd` 撤回且未锁存 → 回 `eIdle`（`bPrechargeDone` 复位）；`eDone` 相指令撤回 → 亦回 `eIdle`（监视件不锁完成态）；
  - `bEnable=FALSE` → 强制 `eIdle` + 双出口复位（不 faults，注释写明：使能断开 ≠ 预充故障）。
- 分工声明：`FB_DL_RailPowerSequence`（多轨分级上电时序，DL_Base）/ `FB_DL_VfdDcBusRipple`（运行期母线监视）/ `FB_DL_VfdGeneric`（变频器通用抽象）互引；本件为**启动期预充回路**专用时序。

**边界向量**：① 正常预充：指令→反馈在窗内→斜率达标→电压达 90% → `eDone` 单拍 `bPrechargeDone=TRUE`；② 反馈超 `tFbWindow` → 锁存故障；③ 斜率持续低于限（卡阻）→ 锁存故障；④ 总时限到 → 锁存故障；⑤ `fUdNom=0` → 组态早退（族② 回归向量）；⑥ 故障态 `bResetCmd` 上升沿 → 解锁回 `eIdle`（锁存解除可达向量）；⑦ 完成后指令撤回 → 回 `eIdle`；⑧ `fUdTargetPct=101` → 组态早退；⑨ 非法枚举态（强改 `eState`）→ ELSE 兜底落 `eFault`。

---

## 5 ROADMAP 卫生注记（本轮不改写 ROADMAP：未勾 41 条 > 30 条阈值，按纪律不追加）

| 项 | 处置 |
|---|---|
| L948 `FC_DL_ShlDwordEx` / `ShrDwordEx` | R62 转办实测完成：与 `ShlEx/ShrEx`（DWORD 主类型）**同义**，拒立项；建议阶段三勾销注记「同义实测（R63），不立项」 |
| R62-D7 转办项（LineClearanceVerify 负值前置） | 复核不成立（L119 已为第一判据），按「复核销账」记 REVIEW_R63 |

---

## 6 阶段三交接清单（不改代码、不改 registry，仅列动作）

1. 返修 5 件落盘 + 版本递增（R1/R3 → v1.0.2、R2 → v1.0.2、R4 → v1.0.3、R5 → v1.0.2）+ JSONL 对应行重注入（sha256 逐行复验 + 全量行数校验，R102）。
2. 新件 13 件落盘 + `INDEX_REGISTRY.json` 增补（Base 134 / MathData 253+4=257 / Algo 128+5=133 / Device 199+4=203 / Motion 120 / Process 273 → 总 **1,125**；今日 115 → **128**/200）。
3. 码位分配：阶段三按子库游标实测；分配后头注释 / MANUAL / registry `code_segment` 三处同改。
4. 文档五件套增量：六本 `VERSION.md`、六本 `MANUAL_DL_*.md`、`CHANGELOG.md`、`LIBRARY_MANUAL.md`、`README.md`、`SOURCE_HUNTING_MATRIX.md`（R63 台账行：零检索轮 + T1-8 / T2-1 深化记录，FB50-D2 口径）。
5. ROADMAP 勾选 ≤10 条：L948 勾销注记 + 本轮落地件对应条目（如有在册）。
6. 终审复扫：R1/R2（严重）逐件推演；R3/R4（中）逐条对指令；新件 13 件按五抽 + 定向扫查（闸覆盖率 / 相迁移闸位复检 / 同拍竞态 / 冻结分支出口，R279 两段式）；**新件专项复检点**：族② 四件（#9/#10/#12/#13）核「组态闸 RETURN 早退」、族① 三件（#6/#8/#11）核「判据充分性（Jury/域闸）」——本轮扩面正是为这两族缺陷模式，终审必查。
7. REVIEW_R63 尾部滚动更新模板清单（R279）：新增「外部系数稳定判据充分性」「组态标志置位但除法可达」两条定向模式。

---

*R63 阶段一 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监 ｜ 零检索轮*
