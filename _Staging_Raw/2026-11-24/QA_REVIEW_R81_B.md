# QA_REVIEW_R81_B — 精简版 12 项扫查 + 三道去重（4 件）

日期 2026-11-24 ｜ 抽检 4/4（本轮批 B 全量）｜ 结论：**PASS 2 / 存疑 2 / 拒收 0**

## 1. 分级统计
| 件 | 版本 | 级 | 缺陷 | 判定 |
|---|---|---|---|---|
| FB_DL_RotaryIndexerCycleSeq | 1.0.1 | C5 | MAJOR×2 MINOR×2 | **存疑** |
| FB_DL_AsrsSlotAllocSeq | 1.0.1 | C4 | MINOR×2 | **PASS** |
| FB_DL_FillPreactSelfLearn | 1.0.0 | C4 | MAJOR×1 MINOR×3 | **存疑** |
| FB_DL_MeasureInputLatch | 1.0.0 | C3 | MINOR×2 | **PASS** |

BLOCK 0 ｜ MAJOR 3 ｜ MINOR 7 ｜ 全轮无编译阻断、无安全侧缺陷 → **无就地修**（R333 未触发）。

## 2. MAJOR 明细
**M1｜RotaryIndexerCycleSeq｜L213-216（+128/177/197/316-319）｜数值误报｜MAJOR**
tonEject 使能域 `eSettle AND NOT _aCupOk[_iEjectIdx]` 与「坏杯在位」**不等价：空工位同样满足**。tEjectTimeout 合法域下限 20ms（L128/L197），而 eSettle 整定窗固定 100ms（L177/L210）→ 当 tEjectTimeout∈[20ms,100ms) 时，**无杯空转也会在整定窗内先到 21**，正常生产被判「剔除位未就绪超时」。默认 3s 下 V1/V3 全绿，故编译与验收向量均不暴露。
修法：增相内保持位 `_bBadAtEject`（只在该位确实装入坏杯时置位），timer 用它而非 `NOT _aCupOk`；或在段 2 加域闸 `tEjectTimeout > DL_RIX_SETTLE`。

**M2｜RotaryIndexerCycleSeq｜L261-268（+124/203）｜计数口径不自洽｜MAJOR**
寄位器每拍只装 1 杯（L261 单布尔），计数器却按 `_iCupPer`（1..4）累加（L264/266）。`iCupPerCycle=4` 时 iGoodCnt 每拍 +4 而 aCupOk 只多 1 个 TRUE → **产量虚计 4 倍**；且该输入不入组态闸（L203 仅 LIMIT 回退，注释"不故障"）。件头 L11-12 自身写的是"上料位装入一杯"，与引脚语义直接矛盾。
修法：二者取一——计数改 `+1`，或寄位器扩为每工位 4 位（`ARRAY[0..11] OF ARRAY[0..3] OF BOOL`）。推荐前者（改一行，零行为风险于默认值 1）。

**M3｜FillPreactSelfLearn｜L279-282（对照 L58-61、L148）｜时限口径与实现不符｜MAJOR**
tonPhase 的 IN 为 `(eCoarse OR eFine)`：eCoarse→eFine 相迁移时 IN 连续为 TRUE，**TON 不复位**，实际是「粗流+细流累计」看门狗；而边界②L58-61 与引脚注释 L148 均明写「单相驻留上限」。实测场景：tSettleTimeout=3s、粗流 1.8s + 细流 1.5s（各自 < 3s）→ 合计 3.3s → **误锁 43**，正常慢速灌装被判设备故障。V7 只测粗流单相，覆盖不到。
修法：拆两个 TON（各串本相闸，与 L283 tonSettle 同款），或改文档口径为「粗+细流合计上限」并同步 L148/边界②——前者正确，后者只是记录缺陷。

## 3. MINOR 明细
- **RotaryIndexer｜L120+293**：非故障态 bReset 为死输入（rtReset 只在 eFault 分支消费）。全库一致约定，但接口注释"清锁存与寄位器与计数"应改为"仅故障退出"。
- **RotaryIndexer｜L227/244/217/320-323**：eReady 的 ELSE 出口本拍不可达（判据与入口同源），tonReady(5s) 与码 12 实际不可触发；作 R448 出口互补保留，建议注释标注"结构性冗余"。
- **AsrsSlotAllocSeq｜L211/229/297**：`_iInfoCode` 只在 L197、L257 清零。冲突/超时轮之后若本轮最终放行，**放行拍同时输出 iErrCode=31/33 与 bGrant=TRUE**（"货位非空 + 已放行"矛盾组合）。修法：eCommit 内清 `_iInfoCode`。
- **AsrsSlotAllocSeq｜L195**：bAllocReq 上升沿仅在 eIdle 消费，事务进行中来的请求沿静默丢弃且无丢弃计数 → 上位无法判断是否需重发。
- **FillPreactSelfLearn｜L146/264/299/307**：缺 PREACT ≥ margin 交叉约束，`_fPreactKg < _fMargin` 时 eFine 阈值低于 eCoarse 阈值，**细流段退化为 0 拍**（精度只靠粗流终点）。
- **FillPreactSelfLearn｜L256-262**：rPreactMax=0 时（Pmin 已钳 0，`_fPmin > _fPmax` 为假）有效限幅退化为 [0,0]，学习恒夹 0、bLearnClamped 恒真但**无故障码**，静默失效。
- **FillPreactSelfLearn｜L161**：`bLearnClamped` 无 `:=` 初值，与同文件其余输出不一致（段 10 恒赋值，无实害）。
- **MeasureInputLatch｜L144-145/160-161/247/252**：iEdgeCnt/iOutsideCnt 为 INT 无回绕防护（同批 FillPreactSelfLearn 计数用 DINT）。高频抖动 32767 次后回绕为负。
- **MeasureInputLatch｜L171 + L7**：`DL_MIL_ZERO` 声明未引用（判据只用 DL_MIL_EPS）；L7 兼容性声明列 ABS 而全文无 ABS 调用。

## 4. 已通过的关键项（逐件）
- 组态闸**结构早退**：4 件均为「段 2/4 置首因 → 段 7 段尾统一锁存并迁相」，无"只置标志不迁相"（R80 M 型缺陷零复现）。
- 除子：4 件均无除法；FillPreactSelfLearn 以量纲闸 `target<=EPS → 42`（L233）替代下游除零防护，成立。
- 非有限：3 件浮点件全用 `x<>x` + `(x-x)<>(x-x)` **字面双判**，7 处一处未漏（Fill L228/239/245-248/333/406/412/417；Measure L204/209/221/325），**零 ABS(x−x)**。
- 同拍竞态：4 件均「本拍合法事件优先、超时判定列最后」（Rotary L274/L285；Asrs L221→227；Fill L315→318；Measure L246→254）。
- `TON/R_TRIG` 全在 CASE 外无条件调用且 IN 含 `NOT .Q` 自复位：4/4 合规。
- 输出全覆盖：4 件段 8 均单点映射，iErrCode 双分支全覆盖，无"漏赋值保上拍脏值"。
- 复位清单完整性 4/4；学习/累计类资产不被复位误清（Fill L357-363 保留 PREACT/Margin/计数/限幅标志 ✓）。

## 5. 三道去重
**道 1 名称**：4 件规范化（去 `FB_DL_`）后与 `_names_r81.txt` 1,489 条**零命中**；同义邻件全量扫描（rotary/indexer/cup/slot/asrs/queue/fill/preact/weigh/dose/latch/measure/probe/mark）已比对，无同名、无同义裸名。
**道 2 指纹**：`_Staging_Raw/_dedup_fingerprints.json` 仅 **84 条**、值为符号名（样本 `'VAR'/'Direction'/'LOGLEVEL'`），覆盖 84/1489=**5.6%**，形态不可用 → **本道降级**为批内互比：4 件状态数 6/6/7/5、输入类型序列互异、指纹 `487a…/a94c…/e165…/3458…` 互不相同，**批内零重复**。**挂账：指纹库需按「规范化签名+输入类型序列+相数」重建（当前形同虚设）。**
**道 3 语义（4 组近邻逐组判定，均判有效变体，零误杀）**
| 新件 | 近邻 | 判定 | 依据 |
|---|---|---|---|
| RotaryIndexerCycleSeq | RotaryIndexTable | **有效变体** | 邻件=工站调度（bAtPos/bIndexDone 外部反馈驱动、启用表+工艺号+空跑、5 态、无寄位器）；新件=**内部计时推进 + 12 位环形杯位寄位器 + 坏杯剔除裁决**，动因是物料追踪而非工位放行。⚠️ L72-74 分工声明**未提** RotaryIndexTable（只提轴件/检测件/气缸），建议补边界一行 |
| 同上 | CupFillDenest / PalletizerLayerSeq | 不判重 | 前者取放料、后者码垛层序，无寄位器与剔除语义 |
| AsrsSlotAllocSeq | WaferCassetteSlot / MotionCmdQueue | **有效新件** | 库内无 PalletSlotJobQueue/Asrs 类件；唯一「序号三律 + 单事务校验-握手-放行」，域唯一 |
| FillPreactSelfLearn | FillWeightCtrl / WeighHopperRefillSeq / BatchDoseSeq | **有效变体** | 邻件均为**控制器/时序器**（出阀命令/补料时序）；新件出**学习参数**（单参数在线学习 + 限幅 + 不稳定样本跳过），新增工程价值成立 |
| MeasureInputLatch | MarkPositionLatch | **有效变体（存疑放行）** | 重叠最高：两者都是「布防沿→触发沿→锁存→读」。但邻件布防窗是**时间窗**(tArmWindow)且带速度锁存/增量/历史环缓/一次布防只认首沿；新件是**位置窗**[start,end]、窗口外沿只计数不废布防、tLatchHold 自动解除布防。策略互补（毛刺容忍 vs 首沿优先），C3 vs 更高复杂度 |
| 同上 | AxisProbeMeasCycle | 不判重 | 邻件为完整测量循环（趋近/回退/重复/离散度/超程），上游依赖轴运动；新件无运动命令 |
| 同上 | ExternalEncoderLatch | 不判重 | 编码器快照采样，无窗口裁决 |

## 6. 存疑放行（请总监复议，未判拒）
1. **MeasureInputLatch ↔ MarkPositionLatch**：功能面 >70% 覆盖，判"有效变体"但**建议二者择一收敛**或在新件头加一行"与 MarkPositionLatch 的边界"。误判风险双向均存在，交总监裁定。
2. **RotaryIndexerCycleSeq M2**：若 `iCupPerCycle` 实际是多腔模设计意图，则正解是寄位器扩维而非改计数——需产品口径确认后再修，勿按我方单方判断改。
3. **MeasureInputLatch 软件扫描沿**：高速轴下 ±v·Tscan 定位误差，已由 L10/L76-79 声明划归上游，判定非缺陷；但件名含 "MeasureInput" 易被误解为 MC_MeasuringInput 硬件锁存替代，建议件头加免责一行。

## 7. 挂账（按下轮优先级）
P0 FillPreactSelfLearn M3（拆 tonPhase，误报故障 43）→ P0 RotaryIndexer M1（tEjectTimeout 域闸/坏杯标志位）→ P1 RotaryIndexer M2（口径，待产品确认）→ P1 AsrsSlotAllocSeq 信息码陈旧（eCommit 清码）→ P2 FillPreactSelfLearn margin 交叉约束 + Pmax=0 退化闸 → P2 MeasureInputLatch 计数升 DINT → P3 死常量/死输入注释订正 4 处 → P3 指纹库重建（机检锚点，交编译验证席）。

## 8. 逃逸反推（机检锚点建议，交 `dl_gate.py`）
- A1：`TON` 实例的 IN 表达式中若出现 `OR` 连接两个不同相位判据 → 报「跨相累计看门狗」嫌疑（M3 唯一机检点）。
- A2：定时器 PT 引脚的组态下限 < 同相其它定时器 PT 常量 → 报「相内双窗配比未证」（M1 唯一机检点）。
- A3：`+ <变量>` 形式的计数器步进，若该变量未出现在同一 FB 的存储/容器写入式中 → 报「计数口径无对应容量」（M2 唯一机检点）。
