# AUDIT_R4 — Round 04 阶段五终审报告（DL_Algo · 16 组件 · 双签入库最后一签）

> 日期：2026-11-15 ｜ 终审人：道莅工控代码库产品总监（架构视角）
> 终审对象：`C:\Library\DL_Algo\` 下 16 个 .st（全部逐行通读，未抽样）
> 依据：`ROUND_PLAN_R4.md` + `daoli-st-standard`（coding-standard / directory-contract / doc-templates）
> 结论：**终审通过**。16/16 PASS（其中 10 个 PASS(修后)），终审共修复缺陷 16 处（含预确认 3 处），修后机检 ALL PASS。

---

## 一、16 组件逐个结论与双签表

| # | 组件 | 终审结论 | 修复数 | 架构定稿 | 编码自检 | 终审 |
|---|---|---|---|---|---|---|
| 1 | FB_DL_PidController | **PASS(修后)** | 6 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 2 | FB_DL_CascadePid | PASS | 0 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 3 | FB_DL_SplitRangeControl | PASS | 0 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 4 | FB_DL_FeedforwardComp | **PASS(修后)** | 1 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 5 | FB_DL_SmithPredictor | **PASS(修后)** | 1 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 6 | FB_DL_RateLimiter | PASS | 0 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 7 | FB_DL_RampGenerator | **PASS(修后)** | 1 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 8 | FB_DL_SCurveGenerator | **PASS(修后)** | 3 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 9 | FB_DL_PwmDutyController | **PASS(修后)** | 3 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 10 | FB_DL_Integrator | **PASS(修后)** | 1 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 11 | FB_DL_Differentiator | **PASS(修后)** | 1 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 12 | FB_DL_LowPassFilter | PASS | 0 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 13 | FB_DL_SecondOrderFilter | **PASS(修后)** | 2 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 14 | FB_DL_HighPassFilter | PASS | 0 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 15 | FC_DL_DewPointCalc | PASS | 0 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |
| 16 | FC_DL_FlowCompensate | **PASS(修后)** | 1 | 总监 ✓ | PLC专家 ✓ | 总监 ✓ |

改动文件 10 个，版本号一律 1.0.0 → **1.0.1**（PATCH 级：缺陷修复与注释完善，未动任何对外引脚契约）。通过 PASS 的 6 个保持 v1.0.0。

## 二、缺陷清单与修法

### 预确认缺陷（总监预审下达，编码侧未修，本次终审就地修复）

| # | 文件 | 缺陷 | 修法 | 影响 |
|---|---|---|---|---|
| A | FB_DL_PidController | `fInt`/`DL_PID_ERR_MAX`/段3复位共 3 处注释单位写成 `[EU*s]`，实际为 `[%]`（Kp·err·dt/Ti 无量纲缩放后仍是输出百分数） | 3 处注释统一改 `[%]`；`DL_PID_ERR_MAX` 存在意义明示为「防浮点溢出的极端钳位」 | 注释级；量纲口径归一 |
| B | FB_DL_PidController | `eIdle` 分支未把 `bActive := FALSE`，自动态复位/失能后 bActive 残留 TRUE | eIdle 分支入口补 `bActive := FALSE` | 状态标志跨拍残留，下游联锁误判 |
| C | FB_DL_PidController | 结尾 `bError := (uErrorId <> 0)` 把信息级码 0002_0101（输出饱和）/ 0002_0102（手动值钳位）也算成故障 | bError 仅对非信息级码置位（显式排除 0101/0102） | 饱和/钳位是调节常态，误置 bError 会导致下游报警抖动 |

### 终审新发现缺陷（算术与工程语义级，机检盲区）

| # | 文件 | 缺陷 | 修法 | 影响 |
|---|---|---|---|---|
| 4 | FB_DL_PidController | `bInit := FALSE` 声明且判据为 `IF bInit`：首扫永不同步微分/增量历史 | 声明改为 `bInit := TRUE`（首扫即同步） | 首扫增量式输出含 `Kp·fErr` 伪增量跳变 |
| 5 | FB_DL_PidController | 手动期不滚动 `fErrF/fErrFPrev/fErrPrev1/fErrPrev2`，手→自动瞬间微分/增量踢腿 | eManual 分支逐拍同步 4 个历史变量 | 切回自动瞬间输出尖峰（终审重点 5） |
| 6 | FB_DL_FeedforwardComp | `tLagTime = T#0S` 是规格合法口径（0=直通），却误置 0002_0401 | 删除该分支的置码，保留直通 | 合法配置常年挂故障码 |
| 7 | FB_DL_SmithPredictor | 信息级码 0002_0502（模型滞后截断）被 `bError := (uErrorId<>0)` 误升级为故障 | 显式排除 0502 | 截断是自愈钳位，不应报警 |
| 8 | FB_DL_RampGenerator | 首扫判据 `IF bInit OR bTrack`（bInit 初值 FALSE）→ 首扫不自动跟踪，违反通用约定 0-6 | 改 `IF bTrack OR (NOT bInit)` | 首扫从 0 起步而非 fTrackValue |
| 9 | FB_DL_Integrator | 同判据反向，且后果更重：bTrack 一旦来过一拍，`bInit:=TRUE` 后**每拍**强制 `fSumLReal := fTrackValue`，累加器永久锁死 | 同上改判据 | **致命级**：一次跟踪脉冲后积分器彻底失效 |
| 10 | FB_DL_SCurveGenerator | 同判据反向：一次跟踪后每拍 `fOut:=fTrackValue` 且运动量清零，轨迹锁死 | 同上改判据 | **致命级**：一次跟踪脉冲后不再运动 |
| 11 | FB_DL_SCurveGenerator | eDone 分支先 `fOut := fTgtMem` 再判 `ABS(fTgtMem-fOut)>TOL`，恒差 0，**新目标永不触发** | 改为先判差再吸附（ELSE 保持吸附） | 到位后换目标永远不动（终审重点 7） |
| 12 | FB_DL_PwmDutyController | 首周期配额未结算（`fDutyEffInt=0`），占空比 100% 也先关断整整一个周期；`bInit` 为死变量 | 使能当拍（`NOT bInit`）立即结算配额；失能清 `bInit`；结算尾置 `bInit:=TRUE` | 100% 加热命令首 10s 无输出；V2 验收向量原本不成立 |
| 13 | FB_DL_Differentiator | `IF bInit THEN ... bInit := TRUE` 恒假死代码，首扫同步实际靠枚举默认值 0（eInit）隐式兜底 | 判据改 `IF NOT bInit`，路径显式化 | 隐患级：隐式依赖枚举零值，重构易踩 |
| 14 | FB_DL_SecondOrderFilter | 状态派生 `(eState=eInit) OR bCoeffDirty` 使首扫直跳 eCoeffCalc：eInit 分支不可达，首拍 fOut=0 且历史未预载，第二拍按全零历史递推出 `b0·fIn`（约 2% 输入） | 派生拆分让首扫先进 eInit（采样直通+历史预载），eInit 末尾显式转 eCoeffCalc | 首拍输出跳零、无扰启动失效 |
| 15 | FC_DL_FlowCompensate | 非有限值防御漏掉 `fAtmPress/rNormPressPs/rNormTempTs`：NaN 大气压经 `fPaAbs<下限`（NaN 比较恒 FALSE）穿透，**带 0 码返回 NaN** | 防御 IF 扩展覆盖 3 个参数 | NaN 以"无故障"身份进贸易交接计量链 |
| 16 | FB_DL_PidController | `fTrackValue` 注释 `[EU]` 与其实际量纲（输出域 `[%]`，被 fLimLow/High 钳位）不符；ROUND_PLAN 规格此处亦注 `[EU]`，属规格勘误，随代码一并修正 | 注释改 `[%]，与输出同量纲` 并在修订历史记录 | 量纲自洽（终审重点 1） |

## 三、本轮新增编码范式沉淀（供 AGENT_EVOLUTION_LOG 追加）

1. **R8 首扫标志唯一合法范式**：`bInit` 必须声明为初值 FALSE 且判据写 `IF bTrack OR (NOT bInit)`（或语义等价的显式首扫分支），禁止 `IF bInit OR bTrack THEN ... bInit := TRUE`——该写法在"标志只在自己块内置位"的前提下首扫永不触发、且一旦触发就每拍触发，属双向皆错。本轮 Integrator / SCurve 因此各藏一个致命锁死。
2. **R9 信息级码白名单出口**：`bError := (uErrorId <> 0)` 一律改为「显式排除信息级码」的派生式；每个 FB 的故障码表必须标注信息级/故障级，信息级码只进 uErrorId 趋势，不得进 bError 报警链。
3. **R10 模式切换 = 历史同步义务**：任何含微分/增量历史的 FB，在 eManual / eIdle / 跟踪等所有"不计算"分支里必须逐拍同步历史变量（fErrF/fErrPrev1/2 等），切回自动首拍的增量必须恒为 0；验收向量必须含「手→自首拍输出连续」断言。
4. **R11 状态自比对禁令**：状态机分支内禁止"先赋值再与刚赋的值比较"做事件检测（如 eDone 先吸附再判新目标，恒差 0）；事件检测的比较基准必须是"上一拍记忆"或比较顺序先于赋值。
5. **R12 FC 参数级非有限值防御全覆盖**：FC 的 NaN/Inf 防御必须覆盖**全部** REAL 输入（含大气压、标准态这类"看似常量"的参数），NaN 与任何下限比较恒 FALSE 会带 0 码穿透；出口默认值赋值必须在第一条 IF 之前完成。

## 四、风险与遗留项

1. **【最高优先】全库仍无一次真实编译器验证**：16 个组件从未在 CODESYS V3.5 / TwinCAT 3 / InoProShop 任一目标环境中编译。机检仅覆盖静态文本规则，语法方言（TIME 比较、TRUNC/REAL_TO_INT 显式转换、枚举字面量作用域、`TIME + TIME` 溢出等）需真机编译确认。**下一轮 P0 动作：建立最小 CODESYS 工程做全量编译 + 验收向量（V1..V6）逐条回放。**
2. 验收向量为人工推导，未做数值仿真回放；LowPass/HighPass/SecondOrder 三个滤波器头注释声称 python 核验过，但核验脚本未归档，建议入库 `_Staging_Raw` 留痕。
3. PwmDutyController 的 `nCycleCount` 在首次使能结算配额时即 +1，把首个未满周期计为完成周期（诊断口径偏差 ±1，不影响输出语义）。
4. CascadePid / SmithPredictor 的 eFault 兜底态不调用子 FB，子块内 R_TRIG 当拍不刷新；因 eFault 仅由非法状态 ELSE 进入、实际不可达，列为观察项不做改动。
5. 主/副 PID 的输出域注释统一用 `[%]`（默认量纲），CascadePid 中主环实际工作在副设定域 `[EU]`——通用 PID 复用时量纲随 rOutMin/rOutMax 走，已在手册层面（后续阶段）需明示。
6. 本轮未触碰 INDEX_REGISTRY.json / ROADMAP.md / JSONL / README / CHANGELOG / VERSION.md（按边界约定由后续阶段统一同步；10 个文件已在代码头修订历史记 v1.0.1，文档同步时请对齐）。

## 五、修后机检结果（自写脚本 check_r4.py 全量重跑）

```text
文件                               行数  禁记 占位 声明  IF/END_IF CASE/END_CASE 结论
FB_DL_PidController.st             349    0    0    0   27/27     1/1      PASS
FB_DL_CascadePid.st                267    0    0    0   13/13     1/1      PASS
FB_DL_SplitRangeControl.st         237    0    0    0   10/10     1/1      PASS
FB_DL_FeedforwardComp.st           245    0    0    0   12/12     1/1      PASS
FB_DL_SmithPredictor.st            316    0    0    0   15/15     1/1      PASS
FB_DL_RateLimiter.st               232    0    0    0   11/11     1/1      PASS
FB_DL_RampGenerator.st             262    0    0    0   16/16     1/1      PASS
FB_DL_SCurveGenerator.st           334    0    0    0   31/31     1/1      PASS
FB_DL_PwmDutyController.st         236    0    0    0   14/14     1/1      PASS
FB_DL_Integrator.st                229    0    0    0   18/18     1/1      PASS
FB_DL_Differentiator.st            236    0    0    0   14/14     1/1      PASS
FB_DL_LowPassFilter.st             206    0    0    0    7/7      1/1      PASS
FB_DL_SecondOrderFilter.st         278    0    0    0    8/8      1/1      PASS
FB_DL_HighPassFilter.st            233    0    0    0    9/9      1/1      PASS
FC_DL_DewPointCalc.st              180    0    0    0    5/5      —        PASS
FC_DL_FlowCompensate.st            195    0    0    0    9/9      —        PASS
机检总结论: ALL PASS（禁用记号 0 / 占位符 0 / 声明双语注释 100% / 终结符齐全 / 配平 / CASE 有 ELSE / 行数 180~360）
```

—— 终审签署：架构定稿与终审 = 工控代码库产品总监；编码与自检 = PLC 编程专家。双签齐备，Round 04 准入后续文档同步阶段。
