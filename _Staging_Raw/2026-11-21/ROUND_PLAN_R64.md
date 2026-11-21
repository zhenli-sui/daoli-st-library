# ROUND_PLAN_R64（阶段一派单｜2026-11-21｜无人值守轮｜预算 ≤8 分钟）

> 配额裁决：R63 五抽挂账 4 处分散 3 族 → R309 判**分散型点修不扩面**：新件配额固定 **10** + 点修 **4 处（2 个文件）**。
> **本轮目标 = 点修 2 件 + 新件 10 件 = 12 项动作**（如实登记，不注水）。
> 分流约束：R63 分流族①「二阶/结构滤波族」与族②「直流母线/ADC/测点监视族」**本轮零扩面**（Algo 滤波件 / Device 监视件均不派单）。
> 编译债纪律（R195）：R63 已完成首位实编译抽样（SELFHECK_R63 §编译段），闸视为已开；本轮仍按保守口径**只派低/中复杂度件，不新增任何编解码/转换类高复杂度件**。
> 本轮**零检索**（WebSearch 0 次）：取材 = T0 族内深化 + LGF Comparator/DataHandling 两 ◐ 组剩余件试点（≤4 件，R63 下轮计划既定）+ Process/Device 自研线。逐源留痕见 `RAW_NOTES_R64.md`。

---

## 0 盘点看板（R64 阶段一实测）

| 指标 | 实测值 | 说明 |
|---|---|---|
| 总库组件数 | **1,125**（v2.55.0） | registry 实测，counts Base134/MathData261/Algo134/Device203/Motion120/Process273 与背景一致 ✔ |
| ROADMAP 待办 | 约 42 条未勾 | > 30 条阈值 → **本轮不追加新待办**，只做卫生注记 |
| 源矩阵 | ✔ 9 / ◐ 30 / ☐ 0 | 全部组已开，组内深化阶段；本轮深化 T2-1 Comparator / Data Handling 两行 |
| 撞名拒单 | **6 拒 + 1 配额顺延**（§2.3） | 矩阵行陈旧 2 条被三查拦截（CRC-16 反射 / LWORD 累加和**均已有属主**），矩阵两行待 R64 收口时订正备注 |

---

## 1 点修规格（R63 挂账 4 处 × 2 文件，P0，全部前置批次 R）

### P0-1 `FB_DL_VfdPrechargeSeq`（DL_Device，v1.0.0 → **v1.0.1**）——R63-D1【中】+ D2【轻】

**修法 A（R63-D1，宽限计时串测点坏闸）**

- 锚点：段 0 无条件刷新区，`tonSlopeLow` 现行（L142）：
  `tonSlopeLow(IN := (_eState = E_DL_PrechargePhase.eRamp) AND _bSlopeLow AND (NOT _bFaultLatch), PT := DL_VPS_SLOPEGRACE);`
- 改为串入 `NOT _bMeasBad`：
  `tonSlopeLow(IN := (_eState = E_DL_PrechargePhase.eRamp) AND _bSlopeLow AND (NOT _bMeasBad) AND (NOT _bFaultLatch), PT := DL_VPS_SLOPEGRACE);`
- 语义：测点中断期（`_bMeasBad = TRUE`，L118/L197 逐拍重算）宽限计时**同步挂起**；测点恢复后 `_bSlopeLow` 重新采样刷新、计时清零续算（判据挂起 ≠ 计时挂起，FB51-4 对偶修复）。
- **撤令判据前置（修法 B，R63-D2）**：`eWaitFb` 分支序（L220-232）与 `eRamp` 分支序（L234-246）中，`NOT bKmCmd` 判据（现 L230 `ELSIF NOT bKmCmd`）**上移为该分支首个 ELSIF**（事件优先段），先于 `tonTotal.Q` / `tonFb.Q` / 斜率超时命中判定，消除「撤令与窗口到期同拍竞态假锁存 0729/072B/072A」。
- 头注释同步：边界五补一句「测点坏期间宽限计时同步挂起」；边界二「本拍合法事件」清单补入「撤令」。
- 版本递增 v1.0.1 + JSONL 对应行重注入（sha256 复验）。

**grep 复核锚点**（返修后）：
1. `grep tonSlopeLow FB_DL_VfdPrechargeSeq.st` → 该行必须含 `NOT _bMeasBad`；
2. `grep -n "NOT bKmCmd"` → 出现行号必须早于同分支 `tonTotal.Q` 出现行号（两分支各验一次）；
3. 头注释边界五含「宽限计时同步挂起」、边界二含「撤令」。

### P0-2 `FB_DL_AdaptiveLmsFilter`（DL_Algo，v1.0.0 → **v1.0.1**）——R63-D3【轻】+ D4【轻】

**修法 A（R63-D3，段间消费顺序）**

- 现状：段 4 变更沿检测 `_nTapsPrev`（L144）消费的是段 6 才更新的 `_nTaps`（L161 `_nTaps := USINT_TO_DINT(uTaps)`），变更沿晚一拍生效，其间一拍「新 `_nTaps` 配旧权重/延迟线」混算。
- 改法：**段 6 钳位赋值整体上移至段 4 之前**（与 `rtWipe` 刷新并列段序），保证段 4 检测到的是本拍已钳位的 `_nTaps`；快照推进 `_nTapsPrev := _nTaps` 保持随段 4 同步。
- 头注释边界段同步：声明「抽头数变更沿以本拍钳位值判定，无晚一拍混算窗口」。

**修法 B（R63-D4，溢出当拍误报 374B → 一次性报告）**

- 现状：段 10 复检只覆盖 `_fErrUse`/`fOut`（L196-197）；段 11 写回 `_afW[_i] + _fCorr * _afX[_i]`（L205 `_fCorr := DL_LMS_TWO * fMu * _fErrUse` 之后）无复检，`|corr·x|` 溢出可把权重写成 Inf → 段 12 `_fEng`（L211-218）当拍误报信息级 374B、次拍才 374C 且 Inf 权重粘滞。
- 改法：段 11 写回前对 `ABS(_fCorr * _afX[_i])` **预检**（非有限即命中），命中路径：置故障级 **374C** + 冻结权重（跳过写回，`_bFrozen` 口径）+ 本拍不再进入段 12 的 374B 判定（**溢出一次性报告，374B 保留为持续发散监视**，不做逐拍重报）；头注释边界三订正「更新前置闸保证权重不被写入污染物」表述，并拆明两条恢复路径（NaN 输入：下一拍自动恢复；溢出污染：需 `bWipeW`），删除「理论上不可达」失准表述。
- 版本递增 v1.0.1 + JSONL 对应行重注入。

**grep 复核锚点**（返修后）：
1. `grep -n "_fCorr \* _afX"` → 预检出现行号必须早于权重写回行号；
2. `grep -n "_nTaps := USINT_TO_DINT"` → 其行号必须早于 `_nTapsPrev` 变更沿比较出现行号；
3. `grep -n "374B"` → 上下文含「持续发散监视 / 一次性」区分口径；边界三含「bWipeW」与「自动恢复」两路径区分。

---

## 2 新件 10 件（批次 1–3，按依赖切 4/3/3）

### 2.1 候选表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_TriStateCompare` | DL_Base | FC_DL_ | 三态比较器（-1/0/+1 归一判定，fEps 浮点容差闸） | lgf-comparator（T2-1 ◐ 深化，Comparator 组第 7 件） | 低 | 1 |
| 2 | `FC_DL_ArrayFindValue` | DL_MathData | FC_DL_ | LREAL 数组线性查找（首/末下标 + 命中计数，非有限值跳过口径声明） | lgf-datahandling（T2-1 ◐ 深化，数组搜索子族） | 低 | 1 |
| 3 | `FC_DL_GcdUdintCalc` | DL_MathData | FC_DL_ | UDINT 最大公约数（欧几里得迭代 + WHILE 守卫计数，供电子齿轮比约分） | T0 数论原子补口（内部来源，零检索） | 低 | 1 |
| 4 | `FC_DL_IntervalGapCalc` | DL_MathData | FC_DL_ | 两区间相离间隙计算（相离返回间隙宽，相接/重叠/包含返回 0 并带关系码） | lgf-comparator（T2-1 ◐ 深化，与 RangeOverlapCheck 五分支互引） | 中 | 1 |
| 5 | `FC_DL_ArraySliceCopy` | DL_MathData | FC_DL_ | 数值数组段拷贝（起止索引边界闸 + 重叠自检，LREAL 主类型） | lgf-datahandling（T2-1 ◐ 深化） | 低 | 2 |
| 6 | `FC_DL_FlowUnitConvert` | DL_MathData | FC_DL_ | 流量单位换算（m³/h ↔ L/min ↔ NL/min ↔ SCFM，域闸 + 非有限闸） | T0-4 单位换算族补口（内部来源，零检索，与 Temp/PressUnitConvert 三件齐） | 低 | 2 |
| 7 | `FC_DL_RunningSumCalc` | DL_MathData | FC_DL_ | LREAL 运行累加和（Kahan 补偿求和防累积误差 + 非有限闸 + DINT 拍数饱和） | T0 统计族补口（内部来源，零检索） | 中 | 2 |
| 8 | `FB_DL_DualValveBlockSet` | DL_Device | FB_DL_ | 双阀冗余块组控（双阀同令同闭 + 两路位置反馈不一致窗判定） | T2-2 LBP 阀特性组织方式次源（clean-room，只借骨） | 中 | 3 |
| 9 | `FB_DL_ReworkLotGate` | DL_Process | FB_DL_ | 返工批拦截闸（返工标记登记 + 复检放行计数 + 越权放行锁存，锁存解除式可达自证） | T2-8 ISA-88 / T2-7 PackML 纪律次源 + 自研 | 中 | 3 |
| 10 | `FB_DL_UnscramblerSeq` | DL_Process | FB_DL_ | 理瓶整理顺控（乱瓶分拣相序 + 卡瓶监视窗 + 料满停进） | T2-7 PackML 相语义次源 + 自研 | 中 | 3 |

- 分流约束核验：滤波族 0 件 / 监视族 0 件 ✔；LGF Comparator/Data Handling 试点合计 **4 件**（#1/#4/#2/#5）≤ 4 ✔。
- 子库分布：DL_Base 1 / DL_MathData 6 / DL_Device 1 / DL_Process 2（**4 个子库覆盖** ✔）。Algo/Motion/Process(Algo 向) 无缺口候选，宁少勿滥。
- 复杂度：低 6 / 中 4 / 高 0（R195 保守口径：无高复杂度编解码/转换件）。
- 码位分配：阶段三按子库游标实测；MathData 新 6 件注意与既有码段连续性，分段理由按 R192 写头注释。

### 2.2 批次依赖切分

- **批 1**（纯函数原子，零批内依赖）：1 / 2 / 3 / 4。
- **批 2**（纯函数 + 换算，零高层依赖）：5（与 #2 同组，边界声明互引）/ 6（与 Temp/PressUnitConvert 族互引）/ 7（独立）。
- **批 3**（有状态 FB，需状态机 + 锁存解除式）：8 / 9 / 10。
- 点修批 R 与批 1 并行启动；全部批次完成后统一终审。

### 2.3 撞名三查拒单留痕（6 拒 + 1 配额顺延，R214 口径：全量名精确比对 + 同义邻件 + 文件树）

| 拒单候选 | 查重结论 | 处置 |
|---|---|---|
| `FC_DL_Crc16Reflected` | 同义邻件：`FC_DL_Crc16Generic`（参数化变体族）/ `Crc16Ccitt` / `Crc16Modbus` 已存——**源矩阵 Data Handling 行备注「CRC-16 反射待挖」已陈旧** | 拒立项；矩阵行订正挂 R64 收口 |
| `FC_DL_LwordChecksum` | 同名精确命中：`FC_DL_ChecksumLwordSum` 已存（reg=1）——矩阵行同上陈旧 | 拒立项；矩阵行订正挂 R64 收口 |
| `FC_DL_BitFieldExtractLword` 变体 | 同名精确命中：reg 已有同名（LWORD 位段族 R13~R14 已收口） | 拒立项（重复提案） |
| `FC_DL_Affine2DPolarDecomp` | 同义邻件：`FC_DL_PolarDecomp2D` / `PolarTransform2D` / `Affine2DChain` 已存——矩阵 Math 行「三角/极分解待挖」已部分陈旧 | 拒立项；矩阵 Math 行订正挂 R64 收口 |
| `FB_DL_GripperClampSeq` | 同义邻件：`I_DL_Gripper` / `FB_DL_ParallelGripper` / `FB_DL_GripperForceVerify` 族已存，夹持-保压-释放语义被属主覆盖 | 拒立项（拆件即凑数） |
| `FB_DL_RejectDivertGate` | 同义邻件：`FB_DL_WeightCheckReject`（重量检剔除属主）已存 | 拒立项（同义邻件） |
| `FC_DL_StringEditDistance` | 三查通过（无同名无同义），但会使 LGF Data Handling 试点超 4 件配额 | **配额顺延 R65 首位候选**（如实登记，不硬凑） |

---

## 3 ROADMAP 卫生注记（不改写 ROADMAP：未勾 ~42 条 > 30 条阈值，按纪律不追加）

| 项 | 处置 |
|---|---|
| 源矩阵 Comparator / Data Handling / Math 三行备注陈旧（§2.3 前 4 条） | R64 收口时逐行订正备注（「实测 R64，已有属主」口径） |
| `FC_DL_StringEditDistance` | R65 首位候选，已在 §2.3 留痕 |

---

## 4 阶段三交接清单

1. 点修 2 件落盘（§1 规格）+ v1.0.1 + JSONL 对应行重注入（sha256 逐行复验）。
2. 新件 10 件落盘 + registry 增补（Base 134+1 / MathData 261+6 / Device 203+1 / Process 273+2 → 总 **1,135**）。
3. 文档五件套增量：六本 VERSION / MANUAL、CHANGELOG、LIBRARY_MANUAL、README、SOURCE_HUNTING_MATRIX（R64 台账行 + 三行陈旧备注订正）。
4. 终审复扫：P0-1/P0-2 按 grep 复核锚点逐条验证；新件 10 件按五抽 + 定向扫查（闸覆盖率 / 相迁移闸位 / 同拍竞态 / 冻结分支出口，R279 两段式）；**新件专项复检点**：批 3 三件核「锁存解除式可达自证 + ELSE 兜底」，MathData 六件核「非有限闸前置 + WHILE 守卫计数」。
5. REVIEW_R64 尾部滚动更新模板清单（R279）。

---

*R64 阶段一 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监 ｜ 零检索轮*
