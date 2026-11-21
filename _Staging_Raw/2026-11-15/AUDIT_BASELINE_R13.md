# 机检基线 R13 ｜ AUDIT BASELINE R13

> **脚本**：`C:\Library\_Staging_Raw\2026-11-15\audit_library_r13.py`（R12 → R13 扩写，16 项规则）
> **自检样本**：`C:\Library\_Staging_Raw\2026-11-15\audit_library_r13_selftest.st`（不属于代码库，不参与全库扫描，仅作检测能力回归）
> **实跑时间**：2026-11-15 22:3x ｜ **范围**：全库 `DL_*/*.st` 共 **204 件**（含泳道本轮落库件）
> **末行**：`SUMMARY: files=204 fail=5 warn=2`
> **执行者**：PLC编程专家（兜底模式代行）

---

## 一、脚本用法

```bash
python audit_library_r13.py                       # 全库 16 项
python audit_library_r13.py --rules r37_left_clamp,r38_dual_source,r39_pre_case_override,r40_ton_cross_segment
python audit_library_r13.py --rules r39_pre_case_override --files DL_Algo/FB_DL_Integrator.st
```

- 与 R12 **完全兼容**：`--files` / `--rules` 语义不变，12 条老规则判定逻辑一字未改。
- 输出末行新增 `warn=`：`SUMMARY: files=N fail=M warn=K`。**`fail` 只计 FAIL 级命中**，WARN 单列、不计入 fail、不影响返回码（`fail>0` 才返回 1）。
- 每条命中前带 `[FAIL]` / `[WARN]` 标记，便于终审分流。

---

## 二、四条新规则实现口径（对照 ROUND_PLAN §6）

| 规则 | 子规则 | 判据实现 | 级别 | 确定性 |
|---|---|---|---|---|
| `r37_left_clamp` | r37.1 自赋值回夹 | `^\s*(X)\s*:=\s*LEFT\s*\(\s*\1\s*,` | FAIL | 确定性 |
| | r37.2 拼接无上界判定 | 有 `CONCAT(`/`INSERT(`，全文无「长度量 vs 上界」比较 | WARN | 启发式 |
| | r37.3 截断标志死码 | 声明 `*Truncated/*Overflow/*Saturated/*Clamped`（BOOL）且仅有 `:= FALSE` 或从未赋值 | FAIL | 确定性 |
| `r38_dual_source` | r38.a 同名双源边界 | `LEN(xLatched|Snap|Buf|Buffer|Mirror)` 与 `LEN(x)` 同基名并存、均参与边界判定，且锁存副本存在**非比较式取段消费** | FAIL | 半确定性 |
| | r38.b 镜像量多点消费 | `*Live/*Real/*Raw` 且**仅一次拷贝赋值**、有效引用 > 3 | WARN | 启发式 |
| `r39_pre_case_override` | 前置 IF 块屏蔽复位沿 | CASE 紧邻前置 IF 块内把状态变量强置 `eIdle/eStopped/eDisabled/eReset/eWait`，条件无故障态排除 | FAIL | 半确定性 |
| `r40_ton_cross_segment` | IN 跨段恒真 | TON/TOF 的 IN 根变量：被置 TRUE、全文无 FALSE、所在 CASE 有段推进写 | FAIL（实例名含 Watch/Step/Seg/Phase）/ WARN（其余） | 半确定性 |

### 误报抑制（已实现，逐条实测）

| 规则 | 抑制条件 | 依据 |
|---|---|---|
| r37.1 | 紧邻上文处于「长度量 vs 上界」的 `IF/ELSIF` 守卫内（遇 `END_IF` 截止） | 合规回夹 `IF nLen > nMax THEN x := LEFT(x, nMax)` |
| r37.1 | 邻近 25 行内已预置 `*Trunc := TRUE` | 「先判后夹」合规写法 |
| r37.2 | 比较两侧任一侧名含 `Len/Max/Length/Width`（含 `nMaxLenUse` 等） | 上界量未必经 `LEN()` 现算 |
| r37.3 | 标志由 `:= <表达式>` / 透传下层件输出赋值 | 非「恒假」 |
| r38.a | 锁存副本只出现在 `MID/LEFT/RIGHT` 且同行含 `<>`（逐字符变化检测） | 变化检测是合法用法 |
| r38.b | 镜像量被多次赋值（中间量）或引用 ≤ 3 | 只锁「单次拷贝 + 多点消费」 |
| r39 | 块内同时清码（`*ErrorId := 0/16#0…` + `*Fault := FALSE`）→ WARN | 首扫初始化 / 整体置安全态 |
| r39 | 块内另置故障锁存（`*Fault/*Latch := TRUE` 或非零码）→ WARN | 故障未被抹掉 |
| r39 | 块内已出现 `bReset/TrigReset` 判据；或 IF 条件含 `<>`、`NOT (x =`、`<=`/`>=` | R39 的合法替代写法 |
| r40 | IN 含 `NOT …Break/Brk/Abort/Cancel/Clear`；或含 `>`/`<`/裸 `=`（纯比较式） | 断输入拍标志是合规指纹 |
| r40 | 全文该根变量存在 `:= FALSE/0` | 会被清零 → 非跨段保持型 |

### 已知能力边界（诚实声明）

1. **r40 只认「状态位型 IN」**：`IN := (eState = eX) AND …` 这类含等号比较的表达式一律 PASS（其语义是「条件成立即计时，跨段合法」，也是本库 159 处 IN 的主流写法）。因此 R40 在本库**全 PASS** 属真实结论，非检测失效——已用自检样本验证可触发。
2. **r39 是结构近似**：「CASE 紧邻前置 IF 块」以「其间仅空行」判定，若中间夹非空段注释块则不会取到该 IF，可能漏报。宁可漏、不可误。
3. **r38.a 依赖命名后缀**（Latch/Snap/Buf/Mirror）；不定名则不进硬判——与 §6.2 的「需人工复核」口径一致。

---

## 三、检测能力自检（fixture 回归）

`audit_library_r13_selftest.st` 内含 5 处人为缺陷，实跑结果：

| 规则 | 期望 | 实测 |
|---|---|---|
| r37.3 | 1（`bTruncated` 从不置真） | ✅ L12 |
| r37.1 | 1（`sBuf := LEFT(sBuf, 200)` 无守卫） | ✅ L30 |
| r38.a | 1（`LEN(sFrame)` 与 `LEN(sFrameLatched)` 双源 + 锁存取段消费） | ✅ L26 |
| r39 | 1（`IF NOT bEnable THEN eState := eIdle`） | ✅ L34 |
| r40 | 1（`fbTonWatch(IN := bStepRun, …)` 跨段恒真 + 段推进写） | ✅ L43 |

`SUMMARY: files=1 fail=5 warn=0` —— 五条子规则全部可触发，排除「恒 PASS 假象」。

---

## 四、全库基线（204 件）

| 规则 | 结果 | 命中 |
|---|---|---|
| 12 项老规则（banned/placeholder/terminator/bilingual/case_else/enum×2/nested/undefined/semicolon/dup） | **全 PASS** | 0 |
| `r37_left_clamp` | PASS | 0 |
| `r38_dual_source` | PASS | 0 |
| `r39_pre_case_override` | **FAIL** | 7（FAIL 5 / WARN 2） |
| `r40_ton_cross_segment` | PASS | 0 |

> 老规则零命中确认了两件事：① R13 存量清理（见 `LEGACY_CLEANUP_R13.md`）已收口；② 新增规则**未污染**既有判定。

### 4.1 R39 命中清单与初判（**未做任何修改**，转呈总监裁量）

| # | 文件:行 | 目标 / 值 | 级别 | 初判 |
|---|---|---|---|---|
| 1 | `DL_Algo/FB_DL_Integrator.st:L149`（CASE L156） | `eState := eIdle` | FAIL | **疑似合规（低风险）**。该件 `eFault` 定义为「自动恢复空闲、无锁死」，且 `uErrorId` 每拍重算（L102）→ 掉使能强置空闲不丢故障信息。仅「掉使能期间 CASE 的 eFault 分支不执行」这一点形式上命中。建议：豁免，或条件补 `AND (eState <> eFault)` |
| 2 | `DL_Algo/FB_DL_PidController.st:L172`（CASE L183） | `eState := eIdle` + `RETURN` | FAIL | **疑似合规（低风险）**。同上：码每拍重算（L118），块内同时把输出回安全下限后 `RETURN`，属「掉使能安全态」设计。建议同上处理 |
| 3 | `DL_Base/FB_DL_InterlockMatrix.st:L240`（CASE L247） | `eStateInt := eDisabled` | FAIL | **风险中，建议人工推演**。该件有「首因锁存 + `bResetPending`」，清码路径在 `CASE … eFault`（L289~L294）；掉使能强置 `eDisabled` 会绕开该清码路径。需确认「掉使能 → 重新使能」是否仍保留故障首因 |
| 4 | `DL_Device/FB_DL_PortDiagBoard.st:L214`（CASE L222） | `ePhase := eIdle` | WARN | **误报，建议豁免**。该块是**首扫初始化**（`bInit := TRUE`），同时清 `uErrInt` 与 `bFaultLatch`，不是停机分支 |
| 5 | `DL_Device/FB_DL_PulseDirStepper.st:L285`（CASE L293） | `_eState := eIdle` | FAIL | **疑似合规（中风险）**。掉使能同时清零频率/相位/剩余步数（安全），故障由 `_bFaultLatch` 独立锁存并在 CASE `eIdle` 内判（L297）。需确认 eFault 的复位通道是否只在 CASE 内 |
| 6 | `DL_Motion/FB_DL_AxisVelocityMove.st:L151`（CASE L155） | `eStep := eIdle` | WARN | **误报，建议豁免**。该块是「发现轴故障 → 置 `bFaultLatch := TRUE` + 非零码」的**故障入口**分支，不是抹除故障 |
| 7 | `DL_Process/FB_DL_AgvDockingHandshake.st:L266`（CASE L271） | `_eState := eIdle` | FAIL | **建议整改（中风险）**。L262 刚置 `eFault`，L265~268 在 `bEnable=FALSE` 时又强制覆盖为 `eIdle` → **同一拍内 `eFault` 不可观测**。建议改为 `IF NOT bEnable AND (NOT _bFaultLatch) THEN` |

**共性结论**：7 处中 1 处为真误报（首扫初始化）、1 处为故障入口分支、4 处为「掉使能回安全态」的设计选择、1 处（AgvDocking）疑似真缺陷（同拍覆盖）。**建议总监按「豁免 / 补条件 / 整改」三分法逐条裁定，并把裁定结论写回 R14 计划**；本次一律未动业务逻辑。

### 4.2 计划预期命中与实测差异说明

| 计划预期（§6.5） | 实测 | 原因 |
|---|---|---|
| `r37.1/r37.3` → `FC_DL_StringReplaceAll`（A-D01） | 0 | R12 已整改：段 5 在 L203~L208 **先判后夹**（`LEN(sHead)+nLenRep+LEN(sTail) > DL_STR_MAX` → 置 `bTruncated := TRUE`），L211 的回夹属护栏；触发「先判后夹」抑制 |
| `r38.a` → `FB_DL_StringTokenStream`（A-D02） | 0 | 现为逐字符变化检测（L144~L157：先比 `nFrameLen <> LEN(sFrameLatched)`，再 `MID(sFrame,1,i) <> MID(sFrameLatched,1,i)`），两侧同为实时量，锁存副本只用于**比较**，触发「变化检测」抑制 |
| `r40` → `FB_DL_BatchPhaseBase` 等四件 | 0 | 四件均已采用「`NOT xBreak` 断输入拍」合规指纹（如 `fbStepWatch(IN := bEnable AND bStepMon AND (NOT bStepWatchBreak) …)`），符合 §6.4 的 PASS 条件 |
| `r38.b` → 缓存与实时量并存件 | 0 | 全库 5 处 `*Raw` 多点消费件经查均为**中间计算量**（`fRaw := fQ * DL_PCT_MAX` 等多次赋值），非入参镜像，收紧为「单次拷贝 + >3 消费」后归零 |

> 结论：**四条规则在存量 204 件上共 7 条命中，全部来自 R39**；R37/R38/R40 为 0 属真实收口，而非检测失效（见第三节 fixture）。

---

## 五、复现命令与产物

```bash
cd C:\Library\_Staging_Raw\2026-11-15
python audit_library_r13.py > AUDIT_BASELINE_R13_run.log      # 全量 16 项
python audit_library_r13.py --rules r37_left_clamp,r38_dual_source,r39_pre_case_override,r40_ton_cross_segment
python audit_library_r13.py --rules r39_pre_case_override --files DL_Algo/FB_DL_Integrator.st
```

| 产物 | 说明 |
|---|---|
| `audit_library_r13.py` | 16 项机检脚本（R12 兼容 + R37~R40） |
| `audit_library_r13_selftest.st` | 检测能力回归样本（5 处人造缺陷，期望 5 条命中） |
| `AUDIT_BASELINE_R13.md` | 本文件 |
| `LEGACY_CLEANUP_R13.md` | 存量 28 处清理留痕 |

---

## 六、给泳道/终审的接入建议

1. **新 18 件入库后必须跑**：`--rules r37_left_clamp,r38_dual_source,r39_pre_case_override,r40_ton_cross_segment`，重点看 A 泳道六件的 R39（`bEnable=FALSE` 冻结分支）与 `FC_DL_StringFixedField` 的 R37。
2. **`fail` 口径变化**：本轮起 `fail` 不含 WARN。若终审要求「WARN 也必须清零」，用 `grep '\[WARN\]'` 单独过滤，不要把 WARN 塞进 `fail` 计数。
3. **R39 的 7 条裁定**建议在 R14 计划里固化，避免每轮重复出现在基线里造成噪声积累。
