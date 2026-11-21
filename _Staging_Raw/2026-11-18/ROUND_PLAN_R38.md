# ROUND_PLAN_R38 — 第 38 轮阶段一派单（7 RESUME + 13 新 = 20 件）

> **轮次**：R38（常态化轮，零检索轮）
> **编制**：2026-11-18 道莅工控代码库产品总监（阶段一：仅盘点与锁定；不写 `.st`、不改 `INDEX_REGISTRY.json`、不改 JSONL）
> **来源策略**：WebSearch **0 次**。7 件 RESUME 规格照抄 `ROUND_PLAN_R36.md` §4（不重造）；13 件新件 100% 取自 `ROADMAP.md` 未勾选真池与 `SOURCE_HUNTING_MATRIX.md` 既有 ☐/◐ 组语义，clean-room 实现。
> **序号口径**：本轮统一重排为 1~20，**序号 1~7 = 新件（低层）**，**序号 8~20 中含 6 件新件 + 7 件 RESUME**——RESUME 7 件的「R36 原序号」在 §1 单独列，双向可追。详见 §1 注 ①。

---

## 0 统计快照（实测脚本读 `INDEX_REGISTRY.json` v2.29.0 + 磁盘 + `ROADMAP.md`）

| 口径 | 数值 | 实测方式 |
|---|---|---|
| 总库已注册 | **650 / 10,000** | `total_components` = 650；`components[]` 长度 = 650；磁盘 `DL_*/*.st` = **650** → 三向一致 ✅ |
| 今日（2026-11-18）已入册 | **131 / 200** | `registered_at` 日期聚合（主控实测，本轮采信未复算） |
| 距 500 件计划 | **已达成 +150** | 650 − 500 |
| 距下一里程碑（1,000） | **350 件** | 1,000 − 650 |
| 子库分布 | `DL_MathData` **176** ｜ `DL_Process` **145** ｜ `DL_Device` **128** ｜ `DL_Base` **75** ｜ `DL_Algo` **64** ｜ `DL_Motion` **62** | `registry.counts` 实测，合计 650 |
| ROADMAP 未勾选条目 | **183 条**（`^- \- \[ \]` 计数） | 脚本实测；名称提及 442 次 |
| 其中**已注册仍显示未勾** | **138 个不同组件名** | 脚本交叉比对 → **勾选漏账挂账 138 件**（本轮不修，见 §6 ⑤，R39 专项回写） |
| 本轮目标 | **+20 → 670 / 10,000** | — |
| 今日预计收尾 | 131 + 20 = **151 / 200** | — |

**本轮平衡口径（实测驱动）**：`DL_Process` 已达 145（全库第二高）且 R36 曾 12/20 押在 Process，本轮**只补 RESUME 尚未落地的 6 件 Process（不新增 Process 选题）**；反补最低两库 `DL_Motion`(62)、`DL_Algo`(64) 共 5 件；`DL_MathData`(176) 仅补 2 件原子件、`DL_Base`(75) 补 2 件 T0 原子件（新补 T0 池，见 §5 与注 ②）。

**口径更正三则（实测优先，写入本轮留痕）**：
1. RESUME 7 件的库别为 **Process 6 / Device 1**（主控交办称「Process 5」，按 R36 §1 序号 14~20 逐条复核，Process 为 15/16/17/18/19/20 共 6 件，VavBoxZeroCal 属 Device）→ 本轮按 6/1 排布，新 13 件仍守住 Device ≤4、Algo ≤3、Motion ≤2、MathData ≤2、Base ≤2。
2. 主控交办「已知占用 `06_0` 80~99 与 **B0~B5**」与实测不符：`06_0_B*`/`C*`/`D*` **全库 0 命中**（实测见 §2）。R36 §2 已把 `B0~B5` 预留给序号 15~20，但该 6 件属 RESUME 未落地，故 `B0~B5` 至今空置 → 本轮直接把 R36 预分配落为实测确认，无需另开新段。
3. `03_2` 段实测 `05` 为历史空穴（R37 判「留存不占用」），本轮继续不占用，从 `12` 起续号。

---

## 1 目标清单（20 件；序号 1~7 新件低层，8~14 新件中段，15~20 Process 段）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能（含差异化判据） | 来源标签 | 复杂度 | 批次 | R36 原序号 |
|---|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_SaturateAdd` | DL_Base | FC | 饱和加减：`S = A ± B` 按目标类型上下限钳制，**溢出判据走「先算宽类型再比界」而非事后回绕检测**，杜绝 INT/DINT 加减溢出静默翻转 | `t2-1-lgf-math` | 中 | 1 | 新 |
| 2 | `FB_DL_ToggleButtonBank` | DL_Base | FB | 多路启停按钮组解算：单按钮切换 / 双按钮点动 / 三位置选择三种模式 + 通道互斥 + 失电来电恢复策略（保持/复位/脉冲） | `t1-5-tcopen` | 中 | 1 | 新 |
| 3 | `FC_DL_LinearRegression2Var` | DL_MathData | FC | 二元最小二乘回归：输出两斜率、截距、R² 与**共线性判据（|r12| 越限即判「不可辨识」而非照算）** | `t2-1-lgf-math` | 中 | 1 | 新 |
| 4 | `FC_DL_OscillationIndex` | DL_MathData | FC | 回路振荡指数：过零率 × 幅值离散度的归一化合成（0~1），**与 `FC_DL_CpkIndex` 严格分工：前者判「在抖」，后者判「偏离」** | `t2-4-s7-motion` | 中 | 1 | 新 |
| 5 | `FC_DL_PidLambdaTune` | DL_Algo | FC | IMC/λ 整定：由 FOPDT 三参数（K/T/τ）与闭环时间常数 λ 直接算 Kc/Ti/Td，**与 `FB_DL_AutoTuneRelay`（在线辨识）分工：本件只做纯换算、不产生激励** | `t2-1-lgf-math` | 中 | 1 | 新 |
| 6 | `FC_DL_HeatExchangerLmtd` | DL_Algo | FC | 换热器对数平均温差 + ε-NTU 效能：逆流/并流/1-2 程修正系数 F 分路，**判据含「端差趋零 → LMTD 除零改用算术平均」的退化分支** | `t2-1-lgf-technology` | 中 | 2 | 新 |
| 7 | `FB_DL_CrossCorrelationDelay` | DL_Algo | FB | 互相关时延估计：两路信号滑动互相关峰值定位 + 抛物线插值亚采样 + 置信度门限，用于输送滞后对齐与前馈超前量标定 | `t2-4-s7-motion` | 高 | 2 | 新 |
| 8 | `FB_DL_SpindleOrientationStop` | DL_Motion | FB | 主轴/C 轴定向停止：低速寻标 → 定向到位锁存 → 抱闸释放时序，**与 `FB_DL_AxisBrakeSeq`（通用抱闸）和 `FB_DL_AxisInPosMonitor`（在位判）差异化：本件管「角度定向」闭环** | `t1-6-plcopen` | 高 | 2 | 新 |
| 9 | `FB_DL_ElectronicCamSwitchBank` | DL_Motion | FB | 电子凸轮开关组（MC_CamSwitch 语义）：多组位置触发点 + 相位偏移 + 触发脉宽 + 单次/周期模式，**与 `FB_DL_MarkPositionLatch`（反向锁存位置）方向相反：本件由位置产生输出** | `t1-6-plcopen` | 中 | 2 | 新 |
| 10 | `FB_DL_VavBoxZeroCal` | DL_Device | FB | 变风量末端风量零点标定（静流稳定判据 + 两点标定 + 标定期冻结调节） | `t1-2-oscat-building` | 中 | 2 | **14** |
| 11 | `FB_DL_ElectrodeTabBendCtrl` | DL_Device | FB | 极耳折弯角度与回弹补偿：单向逼近 + 回弹量按批学习（学习值上限钳制），**与 `FB_DL_RollerGapAdjust`（间隙调整）差异：本件按「角度—回弹」双变量收敛** | `t2-2-lbp` | 高 | 3 | 新 |
| 12 | `FB_DL_JunctionBoxPottingCheck` | DL_Device | FB | 接线盒灌胶量与固化判定：灌胶流量积分积分值窗 + 固化温度-时长累积当量（`°C·min`），**双判据独立记账，不互相掩盖** | `t2-1-lgf-technology` | 中 | 3 | 新 |
| 13 | `FB_DL_PouchSwellingGauge` | DL_Device | FB | 软包电芯鼓胀厚度巡检分级：厚度标定 + 按批次一致性（离散度）与绝对限双口径分级，**判据取「批内异常」而非单件越限** | `t2-1-lgf-measurement` | 中 | 3 | 新 |
| 14 | `FB_DL_FreshAirStepperDamper` | DL_Device | FB | 新风阀步进执行器开环驱动：步数↔开度当量换算 + 反向间隙单向补偿 + 行程端点自学习，**与 `FB_DL_PulseDirStepper`（脉冲/方向驱动）差异：本件带开度当量与端点学习** | `t1-2-oscat-building` | 中 | 3 | 新 |
| 15 | `FB_DL_HeatSealProfile` | DL_Process | FB | 热封温度-压力-时间三参数配方曲线管理（段切换 + 超窗判废 + 配方校验） | `t2-7-packml` | 中 | 3 | **15** |
| 16 | `FB_DL_AhuEconomizer` | DL_Process | FB | 空调箱新风经济器（焓值/干球双判据切换 + 最小新风位 + 低温防冻锁定） | `t1-2-oscat-building` | 高 | 4 | **16** |
| 17 | `FB_DL_TerminalReheatSeq` | DL_Process | FB | 末端再热级联联锁（最小风量约束 + 再热上限级联 + 过热度保护） | `t1-2-oscat-building` | 中 | 4 | **17** |
| 18 | `FB_DL_RfReflectedMonitor` | DL_Process | FB | 射频正向/反射功率比监视与匹配器联动告警（仅监视，不闭环调谐） | `t2-1-lgf-measurement` | 中 | 4 | **18** |
| 19 | `FB_DL_StringSolderQuality` | DL_Process | FB | 串焊焊接质量在线判据（红外温度曲线特征窗 + 拉力抽检窗 + 逐通道分级） | `t2-1-lgf-technology` | 高 | 4 | **19** |
| 20 | `FB_DL_ModuleLamVacuumSeq` | DL_Process | FB | 组件层压真空顺控（抽气-加热-加压-放气四段 + 段超时升级 + 真空度联锁） | `t2-7-packml` | 高 | 4 | **20** |

> **注 ①（序号口径）**：主控交办「13 新件占序号 8~20」与「7 件 RESUME 承接 R36 序号 14~20」在数字上互斥。本轮取**统一重排 1~20 且与批次顺序对齐**方案：1~7 为新件（Level 0 底噪 + Algo 纯函数，批 1）、8~14 为新件中段（Motion/Device，批 2~3 前半）、15~20 为 RESUME Process 段（批 3 末 + 批 4）。R36 原序号在末列逐一对应，双向可追，不丢件。
> **注 ②（T0 真池）**：R34 裁定 `FC_DL_ShlDwordEx`/`ShrDwordEx` 弃立项的结论**继续有效，本轮不重开**。本轮 2 件 DL_Base 属**新发现的 T0 空位**（饱和运算、按钮组解算），均有独立工程判据，非弃判项回填。
> **分布**：DL_Process 6 ｜ DL_Device 5 ｜ DL_Algo 3 ｜ DL_Motion 2 ｜ DL_MathData 2 ｜ DL_Base 2 = 20 ✅（新 13 件 = Device 4 / Algo 3 / Motion 2 / MathData 2 / Base 2，全部落在额度内）
> **配额结论**：T2 标签 11 件，覆盖 `t2-1-lgf`(math/technology/measurement 三子组) / `t2-2-lbp` / `t2-4-s7-motion` / `t2-7-packml` 四族；T1 标签 7 件，覆盖 `t1-2-oscat-building` / `t1-5-tcopen` / `t1-6-plcopen` 三组 → **硬约束「≥1 个 T2 组件族或 1 个 T1 组」双满足**。

---

## 2 码位窗口（实测 6+1 窗口，写死本节；编码专家不得越窗）

> **实测方法（本轮口径 R217 沿用 + 加严）**：对磁盘 **650 个 `DL_*/*.st` 全文**（非仅头部 1504 字节）跑正则 `16#(\d\d)_(\d)_([0-9A-F]{2})`，构建占用集合；`code_segment` 字段（仅 62/650 有值）**不作依据**。
> **实测占用全集**（脚本原样输出，供 R39 起复用）：
> - `02_3`：38 3C 40 44 48 4C 50 54 58 5C 5D 5E 5F 80 81 82（16 个）
> - `03_1`：01 02 03 04 05（5 个）
> - `03_2`：00 01 02 03 04 06 07 08 09 0A 0B 0C 0D 0E 0F 10 11（17 个；**05 为空穴，留存不占**）
> - `04_0`：6C A0 A1 A2 A3（5 个）
> - `05_0`：00 01（2 个）
> - `06_0`：00 05 0A 0F 14 19 1E 23 28 2D 32 37 38 39 3A 3B 3C 3D 3E 3F 40 80~8F 90~99（52 个；**`B*`/`C*`/`D*` 全空，实测 0 命中**）
> - `01_*`：**全段 0 命中**（DL_Base 历史 75 件从未启用码位体系，同 R36 开 `05_0_*` 之先例）

| 窗口 | 码段（闭区间） | 容量 | 归属 | 本轮占用（序号） | 实测依据 |
|---|---|---|---|---|---|
| **W1** | `16#01_0_00` ~ `16#01_0_01` | 2 | DL_Base | 1、2 | `01` = DL_Base 分类位；全库 `01_x_xx` 正则 **0 命中**（`SEG` 实测无 `01` 键），**首开**该段，从 `00` 连续给号不留空洞 |
| **W2** | `16#05_0_02` ~ `16#05_0_03` | 2 | DL_MathData | 3、4 | `05_0` 已占 `00`/`01`（R36 批 1 两件），紧接 `02/03` 续号，`04` 以上留存 |
| **W3** | `16#02_3_83` ~ `16#02_3_85` | 3 | DL_Algo | 5、6、7 | `02_3` 已占至 `82`（含 R37 件 `82`），`83/84/85` 实测空 |
| **W4** | `16#04_0_A4` ~ `16#04_0_A5` | 2 | DL_Motion | 8、9 | `04_0` 已占 `6C`/`A0~A3`，`A4/A5` 空，沿用 `A` 段体例（`6D` 起为历史 `6x` 段，不插队） |
| **W5** | `16#03_2_12` ~ `16#03_2_16` | 5 | DL_Device | 10、11、12、13、14 | `03_2` 已占 `00~04`/`06~11`（R37 件占 `10`/`11`），`12` 起连续空；`05` 空穴按 R37 裁**留存不占**。**分段理由（R192）**：`03_2` 低半字节 `00~0F` 已满（`05` 除外且留存），本轮新件从 `12` 起**跨入 `1x` 段**，须在各件头注释「码位 Code」行注明「`03_2` 段 `00~0F` 已满/留存，进位 `12` 段续号」 |
| **W6** | `16#06_0_B0` ~ `16#06_0_B5` | 6 | DL_Process | 15、16、17、18、19、20 | R35 撞码整改硬约束（`80~99` 判错位段且已满）+ R36 §2 预分配；本轮实测 `06_0_B*` **全库 0 命中**，与既有占用零重叠，直接落为确认 |
| **W7** | `16#06_0_B6` ~ `16#06_0_BF` | 10 | DL_Process（预留） | 未占用 | 实测空段，登记为 R39 起的 Process 首选段（本轮不动） |

**窗口纪律（写死，编码期逐条自检）**：
1. **一窗一件**：每件只占本表指派的那一格；件内多码（信息级/告警级/故障级细分）只能在本件格内 `+0x01` 递增（如 `06_0_B0`→`06_0_B1`），**不得跨入下一件的格**。
2. **空穴与余量保留**：`03_2_05`（历史空穴）、`03_2_17~1F`、`05_0_04+`、`04_0_A6+`、`02_3_86+` 一律登记保留，禁止顺手挪用。
3. **溢出须改派**：若编码期发现某件判据溢出本格（如故障码超格），先报总监改派相邻空窗（W7 或 `06_0_41~7F`），**不得就地连号**占下一件格。
4. **格式硬约束**：头注释「码位 Code」行必须与既有件同格式：`码位 Code     : 16#NN_N_XX`；跨段件（序号 11~14）须另加一行「段位说明」写清进位理由（R192）。

---

## 3 批次切分（4 批 × 5 件，自底向上，批内依赖全部为已注册件）

| 批次 | 序号 —— 组件名 | 批内依赖（`registry` 实测存在，禁新建依赖） |
|---|---|---|
| **批 1**（Level 0 原子 + 首个 Algo 纯函数，最独立，可离平台编译） | 1 `SaturateAdd` ｜ 2 `ToggleButtonBank` ｜ 3 `LinearRegression2Var` ｜ 4 `OscillationIndex` ｜ 5 `PidLambdaTune` | 仅 `Standard.library`；#3 参考 `FC_DL_LinearScale`（已注册）；#4 参考 `FB_DL_SignalStatistics`（已注册）；#5 参考 `FB_DL_PidController`（已注册，仅对齐引脚命名） |
| **批 2**（Algo 稳态 + Motion 定向/凸轮 + 首个 Device RESUME） | 6 `HeatExchangerLmtd` ｜ 7 `CrossCorrelationDelay` ｜ 8 `SpindleOrientationStop` ｜ 9 `ElectronicCamSwitchBank` ｜ 10 `VavBoxZeroCal` | #7 `FB_DL_MedianFilter`、`FB_DL_LowPassFilter`；#8/#9 `I_DL_MotionAxis`、`FB_DL_AxisInPosMonitor`、`FB_DL_ElectronicCam`；#10 `FC_DL_LinearScale`、`FB_DL_SignalDebounce` |
| **批 3**（Device 诊断族 + 首个 Process） | 11 `ElectrodeTabBendCtrl` ｜ 12 `JunctionBoxPottingCheck` ｜ 13 `PouchSwellingGauge` ｜ 14 `FreshAirStepperDamper` ｜ 15 `HeatSealProfile` | #11 `I_DL_Cylinder`、`FB_DL_RateLimiter`、`FB_DL_ToleranceWindow`；#12 `FB_DL_Integrator`、`FB_DL_ToleranceWindow`、`I_DL_TemperatureZone`；#13 `FC_DL_LinearScale`、`FC_DL_LimitClassify`、`FB_DL_SignalStatistics`；#14 `I_DL_StepperOpenLoop`、`FB_DL_ToleranceWindow`；#15 `FB_DL_RampSoakProfile`、`FB_DL_StepSequencer` |
| **批 4**（Process 整段，全部 RESUME，最高复杂度） | 16 `AhuEconomizer` ｜ 17 `TerminalReheatSeq` ｜ 18 `RfReflectedMonitor` ｜ 19 `StringSolderQuality` ｜ 20 `ModuleLamVacuumSeq` | #16 `FC_DL_HumidAirEnthalpy`、`FC_DL_Hysteresis`、`FB_DL_SplitRangeControl`；#17 `FB_DL_RateLimiter`、`FB_DL_SignalDebounce`；#18 `FB_DL_SignalStatistics`、`FB_DL_ToleranceWindow`；#19 `FB_DL_AlarmManager`、`FB_DL_SignalStatistics`；#20 `I_DL_VacuumGenerator`、`I_DL_TemperatureZone`、`I_DL_Cylinder`、`FB_DL_StepSequencer` |

> **依赖实测注记**：本轮脚本核验 40 个候选依赖名，2 个不存在——`E_DL_AxisState`（库内枚举未进 registry 计数）与 `FB_DL_Hysteresis`（**实为 `FC_DL_Hysteresis`**）。已在上表按真实名改引，编码期不得写不存在类型。

---

## 4 每批需求规格（编码专家任务书；RESUME 7 件照抄 R36 §4，仅补码位与注记）

### 批 1（Level 0 原子 + Algo 纯函数）

| # | 规格 |
|---|---|
| 1 | **`FC_DL_SaturateAdd`**（DL_Base/FC，码位 `16#01_0_00`，纯函数）：输入 `nInA`/`nInB`（`DINT`）、`eOp`（`E_DL_SatOp`：Add/Sub）、`nLimitHi`/`nLimitLo`（`DINT`）；输出 `nOut`（`DINT`）、`bClamped`、`nErrId`。算法：以 `LINT` 中间量算 `nInA ± nInB` 后再与 `[nLimitLo, nLimitHi]` 比较钳制，**禁止先 `DINT` 相加再判溢出**（回绕会静默翻号）。边界：`nLimitLo > nLimitHi` 判组态错置码并输出 `nLimitLo`（安全侧）；结果超出 `LINT` 表达域时饱和到对应 `DINT` 极限并 `bClamped := TRUE`；`bClamped` 每周期无条件刷新（无 `R_TRIG`）。自证：`bClamped` 解除式 = 下一拍结果重新落入区间（无需 `bReset`，无锁存）。 |
| 2 | **`FB_DL_ToggleButtonBank`**（DL_Base/FB，码位 `16#01_0_01`）：输入 `abBtn`（按钮数组，`ARRAY[0..nMaxCh-1] OF BOOL`）、`uChannelCount`、`eMode`（`E_DL_BtnMode`：Toggle/SingleAct/Selector3）、`eRestorePolicy`（`E_DL_RestorePolicy`：Hold/Reset/Pulse）；输出 `abOut`（通道输出）、`nActiveChannel`（0 = 无，1..n = 活动通道）、`nErrId`、`bCfgFault`。算法：`Toggle` 用 `R_TRIG` 逐通道翻转；`SingleAct` 点动直通；`Selector3` 通道互斥（新通道置位时旧通道清零）。边界：`uChannelCount = 0` 或 > 数组上界判组态错并全输出 FALSE；`R_TRIG` 在主周期**无条件刷新**（不得置于 `IF` 内）；`Selector3` 同时按两键按「低通道号优先」并置信息码（不做静默双通）；`eRestorePolicy = Pulse` 上电首拍输出单周期 TRUE（注释标注「脉冲语义：置位 1 个 PLC 周期」）。 |
| 3 | **`FC_DL_LinearRegression2Var`**（DL_MathData/FC，码位 `16#05_0_02`，纯函数）：输入 `afX1`/`afX2`/`afY`（样本数组）、`nSampleCount`；输出 `fK1`/`fK2`/`fB`、`fR2`、`bIdentifiable`、`bDegenerate`、`nErrId`。算法：正规方程（3×3 行列式解），共线性由 `|r12|` 检出。边界：`nSampleCount < 4` 判样本不足置码（3 参数 3 方程不可给 R²）；`|r12| > fCollinearLimit`（默认 0.995）置 `bIdentifiable := FALSE` 并**不输出斜率**（防病态解误导）；行列式 `|det| < 1E-12` 判退化置 `bDegenerate`；任一样本非有限（NaN/Inf）整批无效；`fR2` 在 `bIdentifiable = FALSE` 时置 0（不给看似可信数字）。 |
| 4 | **`FC_DL_OscillationIndex`**（DL_MathData/FC，码位 `16#05_0_03`，纯函数）：输入 `afSampleBuffer`（等间隔采样窗）、`nWindowSize`、`fSampleDt`（s）、`fDeadband`（判抖死区，工程量单位）；输出 `fOscIndex`（0~1 无量纲）、`fZeroCrossRateHz`、`fAmpDispersion`、`bOscillating`、`nErrId`。算法：先去均值 → 统计越过 `±fDeadband` 的过零次数得频率，再取「幅值标准差 / 幅值均值」为离散度，两者归一化后几何平均得指数。边界：`nWindowSize < 8` 或越数组上界判码；`fSampleDt <= 0` 防除零；幅值均值 < `fAmpFloor` 时 `fOscIndex := 0` 且 `bOscillating := FALSE`（静止段不判抖）；`fDeadband < 0` 取 `ABS` 并置信息码；**头注释必须写明与 `FC_DL_CpkIndex` 的分工**（在抖 vs 偏离）。 |
| 5 | **`FC_DL_PidLambdaTune`**（DL_Algo/FC，码位 `16#02_3_83`，纯函数）：输入 `fProcGain`（K，无量纲）、`fTimeConstS`（T，s）、`fDeadTimeS`（τ，s）、`fLambdaS`（λ，s，闭环目标时间常数）、`bDerivativeOn`；输出 `fKc`、`fTiS`、`fTdS`、`bFeasible`、`nErrId`、`fMsgCode`。算法：SIMC/λ 整定式 `Kc = T / (K·(λ+τ))`、`Ti = MIN(T, 4(λ+τ))`、`Td = 0`（一阶对象不投 D）；`bDerivativeOn` 时按 λ 变小取 `Td = τ/2` 变体。边界：`fProcGain = 0`/`fLambdaS <= 0`/`fTimeConstS <= 0`/`fDeadTimeS < 0` 均判组态错置码**不输出系数**（防除零与负增益误导）；`λ < τ/2` 判「整定过激」`bFeasible := FALSE` 但**仍给系数**并置告警（可由工艺决定是否采纳）；`fKc` 输出上限 `fKcMax` 由 `VAR_INPUT` 给（禁魔法数）；反向作用（K<0）按 `ABS(K)` 计算并置「反向作用」信息码。 |

### 批 2（Algo 稳态 + Motion 定向/凸轮 + 首个 Device RESUME）

| # | 规格 |
|---|---|
| 6 | **`FC_DL_HeatExchangerLmtd`**（DL_Algo/FC，码位 `16#02_3_84`，纯函数）：输入 `fHotInC`/`fHotOutC`/`fColdInC`/`fColdOutC`（°C）、`eFlowType`（`E_DL_FlowArrangement`：Counter/Parallel/OneShellTwoTube）、`fAreaM2`、`fUwPerM2K`、`fMassFlowHotKgS`、`fCpHotJkgK`；输出 `fLmtdK`、`fEpsilon`（效能）、`fQkw`（kW）、`bTempCross`、`bDegenerate`、`nErrId`。算法：两端差 `ΔT1/ΔT2` → `LMTD = (ΔT1−ΔT2)/LN(ΔT1/ΔT2)`，1-2 程乘 F 修正；效能按 `NTU = UA/(m·cp)` 与 `Cr` 计算。边界：`ΔT1` 与 `ΔT2` 符号相反 → `bTempCross := TRUE` 置码（温度交叉，物理不可能）；`|ΔT1−ΔT2| < 1E-3 K` **退化分支改算术平均**（`LMTD = (ΔT1+ΔT2)/2`，禁止 `LN(1)` 除零）；任一 `ΔT` ≤ 0 判无效；`fMassFlowHotKgS <= 0`/`fCpHotJkgK <= 0` 防除零判组态错；`fUwPerM2K <= 0` 时仅输出 `fLmtdK`，`fEpsilon` 置 0 并置「UA 未组态」信息码。 |
| 7 | **`FB_DL_CrossCorrelationDelay`**（DL_Algo/FB，码位 `16#02_3_85`）：输入 `afSignalRef`/`afSignalFb`（等长缓冲）、`nWindowSize`、`fSampleDt`（s）、`nMaxLagSamples`、`fConfidenceMin`；输出 `fDelayS`（s，可为负 = 超前）、`fPeakCorr`（-1~1）、`bValid`、`bWindowFull`、`nErrId`、`eState`（`E_DL_XCorrState`：Fill/Search/Locked/Fault）。算法：去均值后滑动互相关，取 `|lag| ≤ nMaxLagSamples` 内峰值 → 三点抛物线插值得亚采样滞后；`fPeakCorr` 低于 `fConfidenceMin` 判不可信。边界：`fSampleDt <= 0` 判组态错；`nWindowSize < 16` 或 `2·nMaxLagSamples ≥ nWindowSize` 判组态错（滞后窗不得吃掉相关样本）；缓冲未填满时 `bWindowFull := FALSE` 且不出时延结论；参考信号方差近零（`< 1E-12`）判「激励不足」置码且 `bValid := FALSE`（不得输出随机滞后）；峰值落边界（`|lag| = nMaxLagSamples`）判「滞后超窗」置码而非当有效值。解除式自证：`Fault` 退出 = `bReset AND 三组态参数合法`（引脚均可满足）。 |
| 8 | **`FB_DL_SpindleOrientationStop`**（DL_Motion/FB，码位 `16#04_0_A4`）：注入 `iAxis`（`I_DL_MotionAxis`）；输入 `bOrientCmd`、`fTargetAngleDeg`（0~360）、`fCreepSpeedRpm`、`fTolDeg`、`tOrientTimeout`（ms）、`bBrakeReleaseReq`；输出 `bOriented`、`fAngleErrorDeg`、`bBrakeReleased`、`bTimeout`、`nErrId`、`eState`（`E_DL_OrientState`：Idle/Seek/Creep/Locked/Timeout/Fault）。算法：先按最短角路径（模 360 取差）低速寻标，进 `fTolDeg` 带后切爬行速锁定，`Locked` 稳定 `tLockDwell`（本件常量 100 ms）才置 `bOriented` 并允许抱闸释放。边界：`iAxis` 未装配（引用 0）判组态错不动作；轴 `bError`/未使能拒绝启动；`fCreepSpeedRpm <= 0` 或 `fTolDeg <= 0` 判组态错；角度差算法在 `350°→10°` 跨界点必须走模运算（**R28-2 进位点向量：`0/359.9/180/180.1` 四点各推一条**）；超 `tOrientTimeout` 进 `Timeout` 并撤 `bBrakeReleased`。解除式自证：`Timeout` 解除 = `bReset AND iAxis.bStandstill AND NOT bOrientCmd`（三条件可满足）。 |
| 9 | **`FB_DL_ElectronicCamSwitchBank`**（DL_Motion/FB，码位 `16#04_0_A5`）：注入 `iAxis`（`I_DL_MotionAxis`）；输入 `anSwitchPosDeg`（`ARRAY[0..nMaxSw-1] OF LREAL`，开关位置表）、`afSwitchWidthDeg`（触发宽度）、`auPhaseOffsetDeg`（相位偏移）、`uSwitchCount`、`bEnable`、`eTriggerMode`（`E_DL_CamSwMode`：Single/Cyclic）、`bReset`；输出 `abSwitchOut`（各开关输出）、`bAnyActive`、`nActiveMask`（DWORD，≤32 路）、`nErrId`、`eState`（`E_DL_CamSwState`：Idle/Run/Fault）。算法：轴位置（模 360）逐路判是否落在 `[pos+offset, pos+offset+width]`，跨界（窗口跨 0°）按两段拆判；`Cyclic` 每圈重复触发，`Single` 每开关只触发一次（`abFired` 锁存）。边界：`uSwitchCount = 0` 或 > 数组上界判码返回；`uSwitchCount > 32` 时**不生成** `nActiveMask`（判组态错，禁静默截断）；`afSwitchWidthDeg ≤ 0` 或 `≥ 360` 判组态错；轴位置非有限（NaN）置故障态并全输出 FALSE（安全侧）；`Single` 模式的重置只能经 `bReset` 上升沿（解除式自证：`abFired` 清零 = `bReset`，引脚可满足）。 |
| 10 | **`FB_DL_VavBoxZeroCal`**（DL_Device/FB，码位 `16#03_2_12`，**RESUME — 照抄 R36 §4 #14**）：输入 `fAirflowRaw`（原始风量信号）、`bDamperClosed`/`bDamperOpen`（两点位置反馈）、`tStableTime`（ms）、`fStableBandPa`；输出 `fZeroOffset`、`fSpanGain`、`bCalValid`、`bCalInProgress`、`bRegulateFrozen`、`nErrId`、`eState`（`E_DL_CalState`）。算法：阀门关位且信号在 `fStableBandPa` 内稳定 `tStableTime` 采零点；开位同理采满量程点算 span；两点标定完成才 `bCalValid`；标定全程 `bRegulateFrozen := TRUE`（冻结调节，防标定期误调）。边界：两点顺序反了（先开位后关位）判顺序错置码；零点与满量程差不满足最小分辨率判标定失败（不透传负 span）；标定超 `tCalTimeout` 退出并保持旧参数；解除式自证：`bCalValid` 置位路径 = 零点/满量程两次采样均成功。 |

### 批 3（Device 诊断族 + 首个 Process）

| # | 规格 |
|---|---|
| 11 | **`FB_DL_ElectrodeTabBendCtrl`**（DL_Device/FB，码位 `16#03_2_13`）：注入 `iPressCyl`（`I_DL_Cylinder`）；输入 `bStart`、`fTargetAngleDeg`、`fSpringbackInitDeg`（初始回弹量）、`fAngleTolDeg`、`fLearnGain`（0~1）、`nMaxIteration`、`tStepTimeout`（ms）；输出 `fCmdAngleDeg`（下发弯折角 = 目标 + 回弹）、`fMeasAngleDeg`、`fSpringbackLearnedDeg`、`bInTolerance`、`bIterationExhausted`、`nIteration`、`nErrId`、`eState`（`E_DL_TabBendState`：Idle/Approach/Bend/Measure/Correct/Done/Fault）。算法：单向逼近（只增不减，防反向回弹迟滞）——测角 → 误差超 `fAngleTolDeg` 则按 `fLearnGain` 修正回弹学习值再弯一次，累计回弹学习值**限幅到 `fSpringbackMaxDeg`**。边界：`fTargetAngleDeg ≤ 0` 或超 `fAngleMaxDeg` 判组态错；`iPressCyl` 未装配判组态错不启动；迭代数超 `nMaxIteration` 置 `bIterationExhausted`（**不静默当作 OK**，`bInTolerance := FALSE`）；回弹学习值在 `fLearnGain = 0` 时冻结（组态可关学习）；学习值跨批次掉电不保（本件不持非易失，头注释写明由上层持久化）；解除式自证：`bIterationExhausted` 解除 = `bReset AND eState = Idle`。 |
| 12 | **`FB_DL_JunctionBoxPottingCheck`**（DL_Device/FB，码位 `16#03_2_14`）：注入 `iTempZone`（`I_DL_TemperatureZone`）；输入 `bCycleStart`、`fGlueFlowLpm`、`fGlueTargetMl`、`fGlueTolPct`、`fCureTempMinC`、`fCureDoseMinCmin`（固化当量下限，`°C·min`）、`tCureMax`（ms）；输出 `fGlueDosedMl`、`fCureDoseCmin`、`bGlueOk`、`bCureOk`、`bCycleOk`、`nErrId`、`eState`（`E_DL_PottingState`：Dose/Cure/Done/Fault）。算法：灌胶量由流量对时间积分（`FB_DL_Integrator`）得 mL，与 `fGlueTargetMl ± fGlueTolPct` 比较；固化当量 = Σ(max(T − fCureTempMinC, 0) × Δt) 累积，达 `fCureDoseMinCmin` 判固化完成。边界：`fGlueFlowLpm < 0`（负流量 = 倒吸）判传感器故障置码；`fGlueTargetMl ≤ 0` 或 `fCureDoseMinCmin ≤ 0` 判组态错；`fCureTempMinC` 高于环境上限判组态错（将永不固化）；超 `tCureMax` 置 `bCureOk := FALSE` 并进 `Fault`；**灌胶判据与固化判据独立记账**（`bGlueOk`/`bCureOk` 不互相覆盖），`bCycleOk` 仅在两者皆真时为真；解除式自证：`Fault` 解除 = `bReset AND eState` 回 `Dose`（`bCycleStart` 新上升沿可满足）。 |
| 13 | **`FB_DL_PouchSwellingGauge`**（DL_Device/FB，码位 `16#03_2_15`）：输入 `fThicknessMm`（测厚原始值）、`fZeroOffsetMm`、`fAbsLimitMm`（绝对上限）、`nBatchSize`（批内样本数上限）、`fBatchSigmaLimitMm`（批内离散度上限）、`fZScoreLimit`；输出 `fThicknessNormMm`、`fBatchMeanMm`、`fBatchSigmaMm`、`abItemNg`、`bItemNg`、`bBatchAbnormal`、`nErrId`。算法：批内滚动统计（均值/标准差，Welford 递推防累加误差）→ 绝对限与 `Z` 分数双口径分级；批尾清零。边界：`fAbsLimitMm ≤ 0` 或 `nBatchSize < 2`（无法算 σ）判组态错；`nBatchSize > 数组上界` 钳制并置信息码（**禁用 TRUNC(x)+1 型写法，按 `MIN` 取上界**）；批内 σ 近零（`< 1E-6 mm`）时 `Z` 分数不计算、只走绝对限（防除零）；单件越限立刻置 `abItemNg[k]` 且本件锁存至批尾（解除式 = 批尾清零，可由 `nBatchSize` 满足）；`fThicknessMm` 非有限判信号无效置码且不纳入统计（不污染均值）。 |
| 14 | **`FB_DL_FreshAirStepperDamper`**（DL_Device/FB，码位 `16#03_2_16`）：注入 `iStepper`（`I_DL_StepperOpenLoop`）；输入 `fOpenCmdPct`（0~100）、`bHomingCmd`、`nStepsFullStroke`（全行程步数）、`nBacklashSteps`（反向间隙步数）、`fStepRateHz`；输出 `fActualPosPct`、`nStepCount`、`bHoming`、`bHomed`、`bAtEndStop`、`nErrId`、`eState`（`E_DL_DamperState`：Unhomed/Homing/Ready/Moving/Fault）。算法：开度↔步数当量换算 + **反向行进时额外补 `nBacklashSteps` 间隙步**（同向不补）；端点自学习：撞端点电流判据或超步数判 `bAtEndStop` 后清计数定标。边界：`nStepsFullStroke ≤ 0` 防除零判组态错；`fStepRateHz ≤ 0` 判组态错；未 `bHomed` 时拒绝按开度指令运行（只允许回零），置信息码；`fOpenCmdPct` 越 0~100 钳制并置码；`nBacklashSteps < 0` 取 `ABS` 并置信息码；位置计数用 `DINT` 且到 `nStepsFullStroke` 边界钳制（**禁回绕**，R28-2 两点向量：`0%` 与 `100%` 各推一条）。 |
| 15 | **`FB_DL_HeatSealProfile`**（DL_Process/FB，码位 `16#06_0_B0`，**RESUME — 照抄 R36 §4 #15**）：输入 `bStart`、`bAbort`、配方表（温度/压力/时间三段 `ARRAY[0..2]`）、`fTempTolC`/`fPressTolBar`、`tSealMax`（ms）；输出 `bSealing`、`bProfileOk`、`bReject`、`nSegment`、`fElapsedMs`、`nErrId`、`eState`（`E_DL_SealPhase`：Idle/Heat/Press/Cool/Done/Reject/Fault）。算法：升温→加压→冷却三段按配方时长推进，各段温度/压力必须落在容差带内（越带记段不合格，末段汇总 `bProfileOk`）；单段超 `tSealMax` 升级为 `Fault`。边界：配方时长为 0 的段跳过但记信息码；配方三段全为 0 判组态错不启动；`bAbort` 在任意段立即进 `Fault` 并置 `bReject`；`CASE ... ELSE` 必须有兜底分支（未知状态回 Idle 并置码）；解除式自证：`bReject` 解除 = `bStart` 上升沿且 `bReset`。 |

### 批 4（Process 整段，全部 RESUME，最高复杂度）

| # | 规格 |
|---|---|
| 16 | **`FB_DL_AhuEconomizer`**（DL_Process/FB，码位 `16#06_0_B1`，**RESUME — 照抄 R36 §4 #16**）：输入 `fOutdoorTempC`/`fReturnTempC`、`fOutdoorRhPct`/`fReturnRhPct`、`bFreezeStat`、`fMinFreshPct`；输出 `fDamperCmdPct`、`bFreeCooling`、`bFreezeLockout`、`bEnthalpyModeActive`、`nErrId`、`eState`。算法：焓值（`FC_DL_HumidAirEnthalpy`）比较为主判据、干球差为后备判据（`eCompareMode` 组态），新风开度在 `[fMinFreshPct, 100]` 区间随需求线性映射；`bFreezeStat` 触发 `bFreezeLockout` 关至最小位并锁存，须温度回升 + `bReset` 解除。边界：两个 RH 信号任一质量坏 → **退到干球判据**（不得用缺省 RH 冒充），并置信息码；`fMinFreshPct` 越 0~100 钳制；焓值差在 `±fDeadbandKjKg` 内保持当前模式（迟滞，防抖）；`bFreezeLockout` 解除式自证：`fOutdoorTempC > fFreezeReleaseC` 且 `bReset`。 |
| 17 | **`FB_DL_TerminalReheatSeq`**（DL_Process/FB，码位 `16#06_0_B2`，**RESUME — 照抄 R36 §4 #17**）：输入 `fZoneTempC`/`fZoneSetC`、`fAirflowPct`、`fMinAirflowPct`、`fReheatMaxPct`、`fReheatStageStepPct`；输出 `fReheatCmdPct`、`bMinAirflowLimit`、`bReheatInhibit`、`nActiveStage`、`nErrId`。算法：风量低于 `fMinAirflowPct` 时再热**按级降档**（级间延时 `tStageDelay`），并置 `bMinAirflowLimit`；`bReheatInhibit`（如制冷季互锁输入）时再热全关。边界：`fMinAirflowPct ≥ 100` 判组态错（将使再热永久抑制）；级数计算 `nStage = (INT)(fReheatCmdPct / fReheatStageStepPct)` 后**按级数上限钳制**，`fReheatStageStepPct <= 0` 防除零判组态错（R28-2：整除点与上限+1 两点各推向量）；温度/风量信号质量坏 → 保持当前级并置码（不跳变）。 |
| 18 | **`FB_DL_RfReflectedMonitor`**（DL_Process/FB，码位 `16#06_0_B3`，**RESUME — 照抄 R36 §4 #18**）：输入 `fPowerFwdW`、`fPowerReflW`、`fReflRatioWarnPct`/`fReflRatioFaultPct`（%）、`tRatioDebounce`（ms）；输出 `fReflRatioPct`、`bReflWarn`、`bReflFault`、`bMatcherRequest`（请求调谐，仅请求不闭环）、`nErrId`。算法：反射比 = 反射/正向 ×100，两级阈值带迟滞 + 去抖；`bMatcherRequest` 在越 `fReflRatioWarnPct` 时置位持续 `tMatcherReqHold`。边界：`fPowerFwdW <= 0` 时比值不计算（防除零），输出 0 并置「无正向功率」信息码；反射功率 > 正向功率（比值 > 100%）属异常物理值，钳到 100 并置码；「仅监视」语义写进头注释（不得暗示闭环调谐）；解除式自证：`bReflFault` 解除 = 比值回落到 `fReflRatioWarnPct` 以下且 `bReset`。 |
| 19 | **`FB_DL_StringSolderQuality`**（DL_Process/FB，码位 `16#06_0_B4`，**RESUME — 照抄 R36 §4 #19**）：输入多通道焊接温度曲线采样（`ARRAY OF` 峰值/升温斜率/保温时长）、`fPeakMinC`/`fPeakMaxC`、`fSlopeMinCs`/`fSlopeMaxCs`、`fPullMinN`（拉力抽检下限）；输出逐通道 `abChannelOk`、`abPeakViolate`/`abSlopeViolate`、`nNgChannelMask`（DWORD）、`bLotReject`、`nErrId`。算法：逐通道三判据（峰值窗、升温斜率窗、保温时长窗）→ 通道 NG 聚合到位掩码；拉力抽检仅对「抽中通道」生效（`abPullSampled`），抽检不合格则整批 `bLotReject`。边界：通道数 `nChannelCount = 0` 或超数组上限判码返回；位掩码只在 `nChannelCount <= 32` 时生成（超 32 判组态错，禁止静默截断）；`fSlopeMaxCs <= fSlopeMinCs` 判组态错；抽检通道与 NG 通道不一致时按「双判据独立记账」，不互相掩盖；**整数位段赋值用 `SHL` 显式位号，禁魔法掩码**。 |
| 20 | **`FB_DL_ModuleLamVacuumSeq`**（DL_Process/FB，码位 `16#06_0_B5`，**RESUME — 照抄 R36 §4 #20**）：注入 `iVac`（`I_DL_VacuumGenerator`）、`iTempZone`（`I_DL_TemperatureZone`）、`iPressCyl`（`I_DL_Cylinder`）；输入 `fVacTargetKpa`、`fPressTargetBar`、配方四段时长（抽气/加热/加压/放气，ms）、`tSegmentTimeout`；输出 `bCycleDone`、`bSegmentTimeoutFault`、`nSegment`、`fVacKpa`、`nErrId`、`eState`（`E_DL_LamPhase`：Idle/Evac/Heat/Press/Vent/Done/Fault）。算法：四段顺控，每段带 `tSegmentTimeout` 超时升级；加压段须真空度与温度**双到位**才允许升压（联锁内置）；放气段结束真空度须回到常压确认。边界：任一注入接口引用为 0（未装配）判组态错不启动；`fPressTargetBar` 超组态上限钳制并置码；配方时长全 0 判组态错；`CASE` 全态覆盖 + `ELSE` 兜底置 Fault；解除式自证：`bSegmentTimeoutFault` 解除 = `bReset AND eState = Idle`，且 Idle 可达路径（每段正常推进 + 超时回 Idle）逐条给出。 |

---

## 5 判弃清单（本轮实测剔除 12 条，防同义邻件与凑数变体 —— R28 选题双查 / R184 / R193）

| 曾候选 | 邻件（registry 实测） | 判弃理由 |
|---|---|---|
| `FC_DL_GasFlowSqrt` | **已注册**（同名命中） | ROADMAP 未勾但已在册 → 属**勾选漏账**，不是选题缺口 |
| `FB_DL_WindingAlignEdge` | **已注册** | 同上（勾选漏账） |
| `FB_DL_PumpDryRunGuard` | **已注册**；且邻 `FB_DL_PumpCavitationGuard` | 勾选漏账 + 干转/汽蚀双件已覆盖 |
| `FB_DL_CoilFrostWindow` | **已注册** | 勾选漏账 |
| `FB_DL_MfcSetpointRamp` | **已注册**；邻 `FB_DL_RampGenerator`/`FB_DL_CvdTempRamp` | 勾选漏账 + 斜坡族已 3 件 |
| `FB_DL_LamDoorInterlock` | **已注册**；邻 `FB_DL_OvenDoorInterlock`/`FB_DL_EfEmDoorInterlockPlus`/`FB_DL_SlitValveInterlock` | 勾选漏账 + 炉门互锁族已 4 件，第 5 件无新判据 |
| `FB_DL_AxisBacklashComp` | `FB_DL_BacklashCompensator` | 同义，仅词形差异（`*Comp` vs `*Compensator`），典型凑数变体 |
| `FB_DL_HistogramBin` | `FB_DL_HistogramAccum` | 直方图分箱已被覆盖，再立即成重复 |
| `FC_DL_PercentileRank` | `FC_DL_PercentileLReal` | 分位数已存在，秩次为同义包装 |
| `FB_DL_GlassFeederAccum` | `FB_DL_ConveyorZone`（多区级联积放） | 积放语义已由输送区族覆盖 |
| `FC_DL_AirDensityFanPower` / `FB_DL_GasDensityComp` | `FC_DL_AirDensity` | 介质常量替换型变体，无新增判据（R36 已同判 `GasDensityComp`） |
| `FB_DL_AxisHomingOrderGuard` / `FB_DL_GantrySquaring` | `FB_DL_AxisHomingSeq` / `FB_DL_GantrySyncAxis` | 分别为回零序列与龙门同步的变体，红线 8「禁凑数变体」直接否决 |

> **替补充足性**：剔除 12 条后，13 件新件全部从「真池 + 实测零命中」的候选集中足额锁定，**未回填任何被剔除项**。`FC_DL_SaturateAdd` / `FB_DL_ToggleButtonBank` 属本轮新探明 T0 空位（`Satur`/`Toggle` 词干全库 0 命中，实测见 §6）。

---

## 6 查重声明（四项 + 两项一致性，全部给实测数字）

> ① **name 查**：`INDEX_REGISTRY.json` 650 条 `components[].name` 精确匹配（大小写不敏感）→ 20 个目标名 **0 命中**（脚本 `FINAL_HITS []`）。
> ② **file_path 查**：磁盘 `DL_*/*.st` 650 个文件名 → 20 名 **0 命中**；registry 长度 650 = 磁盘 650 = `total_components` 650，**三向零差额**（`registry.counts` 六库合计亦 650）。
> ③ **同义邻件查**：按 CamelCase 词干拆分对 650 名做词干包含扫描，逐件判定——`Saturate`/`Toggle`/`Regress`/`Oscill`/`Lmtd`/`Lambda`/`CrossCorr`/`CamSwitch`/`Orient`/`Swelling`/`Wear` 十一个词干**全库 0 命中**；`Cam`（`ElectronicCam`/`CamPhaseTrim`/`CamTableInterp`）、`Interlock`、`Trend` 等高密族已逐条比对，均在 §5 剔除或已给出差异化说明（每件「一句话功能」均写明与既有件的分工判据）。
> ④ **码位查**：对 650 个 `.st` 全文跑 `16#(\d\d)_(\d)_([0-9A-F]{2})`，得 7 段占用集合（见 §2 实测全集，共 **97 个不同码位**）；本轮 7 个窗口 `01_0_00~01`、`05_0_02~03`、`02_3_83~85`、`04_0_A4~A5`、`03_2_12~16`、`06_0_B0~B5` 与占用集合**零交集**，W7 预留段 `06_0_B6~BF` 亦零命中。
> ⑤ **三向一致性挂账（本轮新发现，必须记账）**：`ROADMAP.md` 未勾选 183 条中，名称提及 442 次，其中 **138 个不同组件名已存在于 registry**（勾选漏账）。按 R192「未勾条目 > 10 条即出专项回写」→ 已触发，**R39 需出 ROADMAP 勾选回写专项**；本轮只记账不改文件（阶段一禁改）。
> ⑥ **依赖可达性查**：40 个候选依赖名核验，**2 个不存在**（`E_DL_AxisState`、`FB_DL_Hysteresis` → 实为 `FC_DL_Hysteresis`），已在 §3 全部改引为真实名并留痕。

---

## 7 交付自检（阶段一四查）

| 检查项 | 结果 |
|---|---|
| 20 件是否全部零查重命中 | ✅ name / file / 码位三查全零 |
| 分布是否守额度（新 13 件） | ✅ Device 4 / Algo 3 / Motion 2 / MathData 2 / Base 2 |
| 是否满足「≥1 T2 族或 1 T1 组」 | ✅ 双满足（T2 四族 11 件 + T1 三组 7 件） |
| 是否触碰 T0 弃判项 | ✅ 未重开 `FC_DL_ShlDwordEx`/`ShrDwordEx` |
| 批次依赖是否全为已注册件 | ✅ 40 项核验，2 处名误已改引 |

*编制：道莅工控代码库产品总监（R38 阶段一）｜ 2026-11-18*
