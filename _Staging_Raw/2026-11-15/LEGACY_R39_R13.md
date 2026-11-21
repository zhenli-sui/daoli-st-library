# 存量件 R39 人工推演与裁定（R13 轮）

规则：`r39_pre_case_override`（见 ROUND_PLAN_R13.md §6.3）
对象：机检基线命中的 7 处存量已注册文件（FAIL 5 / WARN 2）
方法：逐件取完整状态机上下文，按拍推演「复位沿发生那一拍」的语句执行次序，判断前置改写是否使复位判据不可达、是否清掉待保留的故障码
执行日期：2026-11-16

---

## 0. 结论总览

| # | 文件 | 行 | 级别 | 裁定 | 升版 |
|---|---|---|---|---|---|
| 1 | DL_Base/FB_DL_InterlockMatrix.st | L240（CASE L262） | FAIL | **真缺陷，已修** | 1.0.0 → 1.0.1 |
| 2 | DL_Process/FB_DL_AgvDockingHandshake.st | L266（CASE L283） | FAIL | **真缺陷，已修** | 1.0.0 → 1.0.1 |
| 3 | DL_Algo/FB_DL_Integrator.st | L149（CASE L156） | FAIL | 误报，不修 | 否（已 1.0.1） |
| 4 | DL_Algo/FB_DL_PidController.st | L172（CASE L183） | FAIL | 误报，不修 | 否（已 1.0.1） |
| 5 | DL_Device/FB_DL_PulseDirStepper.st | L285（CASE L293） | FAIL | 误报，不修 | 否（已 1.0.1） |
| 6 | DL_Device/FB_DL_PortDiagBoard.st | L214（CASE L222） | WARN | 误报，不修 | 否 |
| 7 | DL_Motion/FB_DL_AxisVelocityMove.st | L151（CASE L155） | WARN | 误报，不修 | 否 |

审计终值（仅 r39 规则，全库 204 件）：**fail 5 → 3，warn 2 → 2**。
残余 3 条 FAIL 均为上表 #3~#5 的误报件，判据依据见各节；**未采用任何仅为让机检变绿的写法改动**。
两件已修文件全 16 条规则复检均 PASS（`--files` 定向复核，见 §8）。

---

## 1. DL_Base/FB_DL_InterlockMatrix.st — 真缺陷（已修，v1.0.1）

### 1.1 命中位置
- 规则报点：L240（基线行号；本修复增补注释后，该写点现位于 L255）
- 目标 CASE：L262 `CASE eStateInt OF`
- 修复前语句：
  ```st
  IF NOT bEnable THEN
      eStateInt := E_DL_InterlockState.eDisabled;
  END_IF
  ```

### 1.2 本件复位通道的结构
- 复位沿实例 `fbTrigReset` 在段 1 无条件刷新（L124），`Q` 只在上升沿那一拍为真。
- 消化该沿的分支有两处，**都在 CASE 内**：
  - `E_DL_InterlockState.eLatched`（L287 起）：`IF fbTrigReset.Q THEN` 且条件已恢复 → 清 `nLatchIdx / uLatchMask / uFirstOutSeqInt / bFirstOutSimult / bLatchedAtStartup`，转 eBlocked；条件未恢复 → 只置 `bResetPending`。
  - `E_DL_InterlockState.eFault`（L304 起）：`IF fbTrigReset.Q AND (NOT bConfigInvalid) THEN` → 清 `bConfigLatch / uErrorId`，转 eBlocked。
- 段 7（L235 起）在 `bConfigLatch` 为真时**每拍**把 `eStateInt` 强置 eFault。

### 1.3 时序推演（故障态 + 禁用 + 复位沿同拍）
拍 N：`eStateInt = eLatched`、`nLatchIdx = 3`、`bFirstOutValid = TRUE`、`uTripNow = 16#0000`（条件已恢复）、`bEnable = FALSE`、`bReset` 上升沿。

| 执行点 | 修复前行为 | 后果 |
|---|---|---|
| 段 1 `fbTrigReset(CLK := bReset)` | `Q := TRUE`（仅本拍） | 沿已就绪 |
| 段 2 首扫块 | 判据 `bStartupScan` 为假 | 不参与 |
| 段 7 配置校验 | `bConfigLatch` 为假 | 不参与 |
| 段 8 未使能处理 | **`eStateInt := eDisabled`** | eLatched 分支在本拍不再被执行 |
| 段 9 CASE | 走 eDisabled 分支；其 `IF bEnable THEN` 为假 | **无任何动作** |
| 段 10 输出 | `bFirstOutValid := (nLatchIdx >= 0) = TRUE` | 首因锁存留存，HMI 仍显示旧首因 |
| 拍 N+1 | `fbTrigReset.Q := FALSE` | **该沿永久丢失** |

结果是首因锁存必须靠操作员补按第二次复位（且第二次必须发生在 `bEnable = TRUE` 期间）才能清除——正是 R39 定义的「需二次复位」缺陷。

同型缺陷在 eFault 上更隐蔽：`bConfigLatch` 为真时，段 7 每拍把状态强置 eFault，段 8 紧随其后改写 eDisabled，CASE 只能走 eDisabled，`eFault` 分支的 `IF fbTrigReset.Q AND (NOT bConfigInvalid)` **永远摸不到任何复位沿**；即「掩码改对以后仍无法退出配置故障态」。

### 1.4 修改内容（diff 摘要）
```diff
-IF NOT bEnable THEN
+IF (eStateInt <> E_DL_InterlockState.eLatched)
+AND (eStateInt <> E_DL_InterlockState.eFault)
+AND (NOT bEnable) THEN
     eStateInt := E_DL_InterlockState.eDisabled;
 END_IF
```
理由：复位沿只有一拍寿命，其消化权归 eLatched / eFault 两态，禁用覆盖不得抢占；其余状态（eBlocked / ePermitted / eDisabled）行为与修复前完全一致，仍立即回 eDisabled。

### 1.5 语义披露（修复的代价，须知会下游）
1. 禁用期间若首因已锁存，`eState` 输出保持 `eLatched`（不再显示 `eDisabled`）——与枚举注释「eLatched：首因已锁存，等待复位」「eDisabled：未使能，锁存内容保持」一致，HMI 读到的相位更真实。
2. 首因清除后当拍落 eBlocked，下一拍才被段 8 改写为 eDisabled（相差一拍）。
3. 使能回升不再"顺带"越过 eLatched：禁用于首因锁存期间后重新使能，仍需一次复位才回 eBlocked。旧实现在此种时序下会带着陈旧首因直接走到 ePermitted（`bFirstOutValid` 仍为 TRUE、`nFirstOutIndex` 仍为旧通道号），属诊断说谎；本次改动同时消除了该隐患。
4. 放行安全无变化：`bPermitToRun` 恒由 `eStateInt = ePermitted` 与 `bEnable` 共同派生（L326，段 10 单一出口），禁用期间不可能放行。

### 1.6 是否升版
是。`1.0.0 → 1.0.1`，文件头「当前版本」与「修订历史」各追加一行（2026-11-16）。

### 1.7 规则判据局限（供规则维护者参考，非绕行）
`r39` 的排除项判据取自 `_if_blocks` 记录的 **IF 首行文本**（`ln[m.end():]`），多行条件若把排除项写在第二、三行，仍被判为「未见故障态排除」。本轮第一版修复把 `(NOT bEnable)` 写在首行、两个比较写在续行，机检仍报 FAIL；最终把状态比较提到首行（语义完全相同，且更符合「先排除状态、再判使能」的阅读顺序）后通过。若要让本规则对多行条件稳健，应把条件拼接范围扩到 `THEN` 之前整段。

---

## 2. DL_Process/FB_DL_AgvDockingHandshake.st — 真缺陷（已修，v1.0.1）

### 2.1 命中位置
- 规则报点：L266（基线行号；本修复增补注释后，该写点现位于 L278）
- 目标 CASE：L283 `CASE _eState OF`
- 修复前语句：
  ```st
  IF NOT bEnable THEN
      _eState   := E_DL_AgvDockState.eIdle;
      _bMatSnap := FALSE;
  END_IF
  ```

### 2.2 本件复位通道的结构
- `fbTrigReset` 在段 3 无条件刷新（L204）。
- 唯一清故障的出口是 CASE 的 `E_DL_AgvDockState.eFault` 分支（L355 起）：`IF fbTrigReset.Q THEN` → 清 `_bFaultLatch / _uErrorIdInt / _bMatSnap`，回 eIdle。
- 故障锁存 `_bFaultLatch` 一旦为真，`eIdle` 分支的进入条件 `IF bEnable AND bAgvArrived AND (NOT _bFaultLatch)` 恒假，其它分支也不清除锁存——**复位沿是唯一出口**。

### 2.3 时序推演（故障态 + 禁用 + 复位沿同拍）
拍 N：`_eState = eFault`、`_bFaultLatch = TRUE`、`_uErrorIdInt = 16#0005_02E0`、`bEnable = FALSE`、`bReset` 上升沿。

| 执行点 | 修复前行为 | 后果 |
|---|---|---|
| 段 3 | `fbTrigReset.Q := TRUE` | 沿已就绪 |
| 段 5 中止（L256） | 判据含 `bEnable`，为假 | 不参与 |
| 段 5 失序（L263） | 判据含 `bEnable`，为假 | 不参与 |
| 段 5 之三 使能撤销（L277） | **`_eState := eIdle`** | eFault 分支本拍不再被执行 |
| 段 6 CASE | 走 eIdle 分支，进入条件含 `NOT _bFaultLatch`，全假 | **无任何动作** |
| 段 8 出口 | `bError := _bFaultLatch = TRUE`，`eState := eIdle` | 状态与故障标志互相矛盾；放行位为假，机器静止 |
| 拍 N+1 | `fbTrigReset.Q := FALSE` | **该沿永久丢失** |

后续后果：即使 `bEnable` 回升，`eIdle` 分支被 `NOT _bFaultLatch` 挡住，机器停在上电待机语义、`bError` 恒真；操作员必须再按一次复位才能恢复，且期间没有任何信号说明"还差一次复位"。属 R39 判定缺陷。

### 2.4 修改内容（diff 摘要）
```diff
-IF NOT bEnable THEN
+IF (NOT bEnable) AND (_eState <> E_DL_AgvDockState.eFault) THEN
     _eState   := E_DL_AgvDockState.eIdle;
     _bMatSnap := FALSE;
 END_IF
```
并在块前补 4 行 R39 纪律说明（中英双语）。

### 2.5 语义披露
1. eFault 态不再被使能撤销覆盖：故障期间 `eState` 如实报 eFault，`bError` 保持 TRUE，复位沿当拍即可清锁存回 eIdle。
2. 非故障态（eWaitArrive / eDockConfirm / ePermitTransfer / eTransferMonitor / eComplete / eIdle）禁用行为完全不变：仍立即回 eIdle、快照作废。
3. 放行安全无变化：`bDockLamp` 与 `bTransferPermit` 由状态派生，eFault 与 eIdle 均为假。

### 2.6 是否升版
是。`1.0.0 → 1.0.1`，文件头「当前版本」与「修订历史」各追加一行（2026-11-16）。

---

## 3. DL_Algo/FB_DL_Integrator.st — 误报（不修）

命中 L149（CASE L156）：
```st
IF NOT bEnable THEN
    eState := eIdle;                    // 未使能：强制空闲、累加器保持
END_IF
```

**推演依据（为何任何时序下都安全）**

1. 本件不存在"待复位保住的故障锁存"。`uErrorId` 与 `bError` 在段 1 每拍先被重算（L102~L103 `uErrorId := 16#0000_0000; bError := FALSE;`），是逐拍瞬态量，**语义上就没有"必须跨拍保留、只能由复位沿清除"的故障码**，因此"故障码被清"这一危害形态在本件不成立。
2. eFault 只是 CASE 的 ELSE 对非法枚举值的兜底，其分支体是 `eState := eIdle`（L191）——**无复位依赖，自动恢复**，不需要任何复位沿。
3. 复位是电平语义（头注释 B2 与变量注释均写明 `bReset` 电平触发），处理点在 L140~L146，**严格位于 L149 之前**，且其执行条件只有 `bReset` 与 `bInFinite`，**与 `eState` 取值无关**：
   - 拍 N（`bEnable = FALSE`，`bReset = TRUE`）：L141 累加器清零、L143 端点同步、L145 `eState := eIdle`；L149 再写 eIdle 为同值写，零信息损失。
   - 拍 N+k（`bReset` 仍为 TRUE）：每拍重复清零，电平复位不存在"沿被吞"。
   - `bEnable` 回升拍：状态为 eIdle，CASE eIdle 在 `bEnable AND bInFinite AND NOT bReset AND NOT bHold` 成立时迁移 eIntegrating，行为与复位前一致。
4. 状态覆盖不造成积分丢失：四种非空闲态（eHold / eIntegrating / eLimited / eFault）在 CASE 内各自都已有 `IF NOT bEnable THEN eState := eIdle` 的等效处理，L149 与该四处等价，不存在"某个态被强行抹掉导致不可恢复"的路径；累加器 `fSumLReal` 在其后不被清零（"累加器保持"成立）。

**裁定**：误报，不修。保留命中（规则缺少"状态量不参与任何复位判据 / 故障码为逐拍瞬态"的豁免形态）。

---

## 4. DL_Algo/FB_DL_PidController.st — 误报（不修）

命中 L172（CASE L183）。本件是全库中"复位沿 + 禁用分支"结构最完整的一件，正因如此可以给出严格的时间序证明。

**推演依据**

1. 复位沿实例 `fbTrigReset` 在段 1（L112）**无条件刷新**，满足周期刷新红线。
2. 复位动作（段 3，L145~L154）**无条件执行且位于段 5（L171）之前**，其内部四条语句（清积分 / 清增量式历史 / 清滤波偏差 / `eState := eIdle`）没有任何分支守卫。
3. 段 5 的覆盖语句只写 `eState` 与 `fOut`，**不触碰 `uErrorId` 与 `bError`**；而 `bError` 在段 6 之后由 `uErrorId` 的分类派生（L347~L348），信息级码不置故障位。
4. 逐拍推演（故障态 + 禁用 + 复位沿同拍）：
   - 拍 N：`fbTrigReset.Q = TRUE` → 段 2 参数钳位 → **段 3 已完成全部复位动作**（含 eFault → eIdle）→ 段 4 若输入有限不返回 → 段 5 `eState := eIdle`（同值写）、`fOut := fLimLow`、`RETURN`。
   - 结论：复位动作与复位沿发生在**同一拍、同一段**，且早于任何状态覆盖；覆盖写的是同一个 eIdle，不构成"跳过一次复位"。
   - 拍 N+1：`Q = FALSE`，但复位已在拍 N 生效完成，无遗留。
5. 若复位沿发生在段 4 的非有限值返回拍（`RETURN` 在 L165），段 3 仍已执行完毕；即复位通道不受任何前置返回影响。
6. eFault 态的唯一进入点是 CASE 的 ELSE（非法枚举值），其唯一出口恰为段 3 的 `eState := eIdle`——该写点位于段 5 之前，故即便在禁用期间也能退出 eFault。

**裁定**：误报，不修。规则把"前置 IF 内改写状态"当作指纹，但本件复位判据在文本与执行序上都先于覆盖（属于 §6.3 误报抑制第 2 条的同类合法写法：已把复位提到前面）。

---

## 5. DL_Device/FB_DL_PulseDirStepper.st — 误报（不修）

命中 L285（CASE L293）：
```st
IF NOT _bEnableCmd THEN
    _eState      := E_DL_StepperState.eIdle;
    _fFreqNow    := 0.0;
    _fPhaseAcc   := 0.0;
    _bMoveActive := FALSE;
    _fStepsRemain := 0.0;
END_IF
```

**推演依据**

1. 本件的复位请求**不是沿**，而是方法旗标：`Reset()`（METHOD，L536 起）在 `_bFaultLatch OR _eState = eFault` 时置 `_bPendReset := TRUE`，由主体段 6 第一段（L261~L271）**无条件消费**：
   - `_bPendReset := FALSE`（单拍消费）
   - `IF NOT bAlarmIn THEN` 清 `_bFaultLatch / _bStallLat / _uErrInt`，且 `IF _eState = eFault THEN _eState := eIdle`。
2. 该复位段（L261）位于禁用覆盖段（L281）**之前**，两者之间只隔着停车段（L272），而停车段不写 `_eState` 之外与故障相关的内容；因此**任何使能电平取值下，复位请求都在覆盖之前完成**。
3. 禁用覆盖段**不触碰任何故障量**：`_bFaultLatch`、`_bStallLat`、`_uErrInt` 均未被写；它只清运动量（频率 / 相位 / 运动标志 / 剩余步数）。故"故障码被清"不成立。
4. 逐拍推演（故障态 + 禁用 + 复位同拍）：
   - 拍 N：应用调用 `Reset()` → `_bPendReset := TRUE`（`_eState = eFault`，受理）。
   - 拍 N+1：段 5 故障源监视（`_bMoveActive` 仍为旧值，可能重锁存）→ **段 6 复位消费**（报警源已消失则清锁存、清码、状态回 eIdle）→ 段 6 禁用覆盖（再写 eIdle，同值）→ CASE 走 eIdle，其 `IF _bFaultLatch THEN` 此时为假，不回 eFault。
   - 复位后在同拍不会被重新拉回 eFault：故障源监视段在复位段之前，锁存只在运动中出现新的限位/报警/堵转时产生。
5. 若禁用发生在无故障态（eAccel / eRun / eDecel），被置 eIdle 并清运动量，属设计意图（头注释 V6：去使能本拍停发、再使能不自动续走），与故障复位无关。

**裁定**：误报，不修。真正会"吞掉复位"的形态是把复位判据放进 CASE 的 eFault 分支、让前置分支改写状态；本件复位判据在 CASE 之外且先执行，属安全写法。

---

## 6. DL_Device/FB_DL_PortDiagBoard.st — 误报（WARN，不修）

命中 L214（CASE L222）。被检块是**段 3 首扫初始化**，判据 `IF NOT bInit THEN`（L194），块末 `bInit := TRUE`（L215），**全生命周期只执行一次**，且执行时故障不可能已存在（上一拍尚无状态机）。

**推演依据**

1. 首扫块内 `uErrInt := 0` / `bFaultLatch := FALSE` / `ePhase := eIdle` 属"上电整体置安全态"，规则已按 §6.3 误报抑制第 1 条降级为 WARN，与"每逢禁用就抹掉故障"的缺陷形态无共同点：它不可能在任何一次故障之后再次执行。
2. 本件的故障复位通道与首扫块无关：
   - CASE 的 `E_DL_BoardPhase.eFault` 分支（L393）只做输出保持；
   - 复位在**段 6（L415，位于 CASE 之后）**，判据 `IF fbTrigReset.Q THEN` 无状态守卫，内部 `IF ePhase = eFault THEN ePhase := eIdle`（L425~L426）显式退出故障态，并清 `bFaultLatch / uErrInt` 与首出锁存。
3. 使能关闭的处理在 **CASE 内的 eIdle 分支**（L225），不在 CASE 之前，本身不在本规则范围内；且该分支只清掩码与总数派生量，不清 `bFaultLatch / uErrInt`。

**裁定**：误报，不修（保留 WARN 命中）。

---

## 7. DL_Motion/FB_DL_AxisVelocityMove.st — 误报（WARN，不修）

命中 L151（CASE L155）：`eStep := E_DL_VelStep.eIdle;`

**推演依据**

1. 本件**没有故障状态枚举**：`E_DL_VelStep` 只有 `eIdle` / `eRunning`；故障由独立布尔 `bFaultLatch` 承担，"故障态"在状态轴上根本不存在，因此"状态机被拉回 eIdle 导致故障复位流程不可达"的因果链不成立。
2. 被检语句属于**故障入口本身**（段 6「运行中轴故障中断」，L147~L152）：运行中轴报错 → 锁存 `bFaultLatch`、置码 0004_0230、退速度模式回 eIdle。这是缺陷诊断动作，不是"前置覆盖"。
3. 锁存清除路径在 CASE 的 `eIdle` 分支内：`IF rtrigStart.Q THEN bFaultLatch := FALSE;`（L159~L160）。因为段 6 把状态**放进** eIdle，下一拍的启动上升沿必然落在该分支内并清除锁存——即"复位通道恰好位于被置入的态"，不存在沿被跳。
4. 逐拍：拍 N 轴故障 → 锁存 + 退 eIdle（本拍 `bBusy := FALSE`）；拍 N+1 起处于 eIdle，任何 `bCmdStart` 上升沿都先清锁存再走门禁重新启动。若轴仍故障，`MoveVelocity` 返回假 → 重新锁存并置码，属设计意图（不隐瞒故障）。
5. 规则降级理由（块内另置故障锁存）与上述结构一致；WARN 为启发式分级，此处不构成缺陷。

**裁定**：误报，不修（保留 WARN 命中）。

---

## 8. 复跑与验收

### 8.1 两件已修文件全规则复核
```
python audit_library_r13.py --files DL_Base/FB_DL_InterlockMatrix.st DL_Process/FB_DL_AgvDockingHandshake.st
→ SUMMARY: files=2 fail=0 warn=0（16 条规则全部 PASS）
```

### 8.2 全库 r39 终值
```
python audit_library_r13.py --rules r39_pre_case_override
→ SUMMARY: files=204 fail=3 warn=2
```
命中明细（与基线对比）：

| 文件 | 基线 | 现状 | 说明 |
|---|---|---|---|
| DL_Base/FB_DL_InterlockMatrix.st | FAIL | 已消除 | §1 真缺陷已修 |
| DL_Process/FB_DL_AgvDockingHandshake.st | FAIL | 已消除 | §2 真缺陷已修 |
| DL_Algo/FB_DL_Integrator.st | FAIL | 仍 FAIL | §3 误报，见推演 |
| DL_Algo/FB_DL_PidController.st | FAIL | 仍 FAIL | §4 误报，见推演 |
| DL_Device/FB_DL_PulseDirStepper.st | FAIL | 仍 FAIL | §5 误报，见推演 |
| DL_Device/FB_DL_PortDiagBoard.st | WARN | 仍 WARN | §6 误报，见推演 |
| DL_Motion/FB_DL_AxisVelocityMove.st | WARN | 仍 WARN | §7 误报，见推演 |

### 8.3 残余命中的保留理由（汇总）
- 三条残余 FAIL 的共同点：**复位判据（电平 / 沿实例 / 挂起旗标）在文本与执行序上都位于前置改写之前，且被改写的状态量不参与任何复位条件**；故障码或为逐拍瞬态（Integrator、PID），或由独立布尔承担且清码路径在覆盖段之外（PulseDirStepper）。按 §6.3 的判定三要素②③，这三处不满足"复位沿被整拍跳过"的因果要求。
- 两条残余 WARN：一条是首扫一次性初始化块（PortDiagBoard），一条是故障入口本身而非覆盖（AxisVelocityMove）。
- 未采用任何仅为使机检变绿的写法（例如给本无故障态的条件硬塞 `<> eFault` 比较），因为那会改变禁用期间的状态语义并在块内引入与实际不存在的状态。

### 8.4 给规则维护者的两条建议（本轮不改脚本）
1. 排除项判据应覆盖 IF 条件的完整文本（首个 `THEN` 之前），而不是仅首行；否则多行条件的排除项会被漏读（§1.7）。
2. 建议为"复位判据在文本上先于前置改写且无条件守卫"增加豁免形态（可判：前置块起始行之前已出现 `bReset` / `TrigReset` / `_bPendReset` 且其间无 `END_IF` 之外的阻断），可一次性消掉 §3~§5 的启发式噪声。
