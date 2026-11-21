# FINAL REVIEW — Round 10（R10）总监终审记录

> 审查人：道莅工控代码库产品总监（六签流程中的人工语义终审闸口）
> 日期：2026-11-15 ｜ 规格基准：`C:\Library\_Staging_Raw\2026-11-15\ROUND_PLAN_R10.md`
> 规范依据：`daoli-library-director.md` + `daoli-st-standard/SKILL.md` + `references/`（coding-standard / directory-contract / doc-templates）
> 审查范围：R10 十六件（registry 136→152，库版本 v1.9.0，JSONL 152 条）
> 审查方式：逐行精读 + 逐拍状态机推演 + 独立数学复算 + 机检复跑 + JSONL 字节级再同步

---

## 一、终审结论

**结论：PASS with fixes（修复后准入）**

| 指标 | 数值 |
|---|---|
| 送审文件数 | 16（送审行数 5,385） |
| 判定 PASS（零修改） | 8 |
| 判定 FAIL → 已修复 | 8 |
| 缺陷总数 | **17**（致命 2 ／ 严重 3 ／ 中等 6 ／ 注释级 6） |
| 修复后最终行数 | **5,528**（+143，全部为修复注释与勘误留痕，无功能膨胀） |
| 版本变化 | 8 件 1.0.0 → **1.0.1**；8 件维持 1.0.0 |
| 机检复跑 | **16/16 PASS**，码位跨文件重复仅 `16#0000_0000`（无事件码语义，非串台） |
| JSONL 再同步 | 8 条 output 字节级重注入，其余 144 条**逐字节零漂移**，round-trip 8/8 |
| 剩余观察项 | 5 条（不阻断入库，留档 v1.1） |

**一句话裁定**：十六件的接口契约、码位段位、算法公式与量纲整体达标，R19/R20/R21/R22/R23/R24/R25/R26/R27/R28/R29/R30 逐条落地；但**机检 16/16 全过的表象下藏着 2 处致命缺陷——其一让拾放工站在三平台上永远无法执行（CASE 缺标签落入 ELSE 锁故障），其二让排线轴启动后位移恒为 0（方向量被每拍清零）**，另有一处空引用调用与一处屏蔽功能完全失效。这四处全部位于机检的语义盲区（CASE 标签集合完整性、变量在拍内的读写次序、可选接口的空引用、计数器装载与递减的同拍次序），再次印证「文本机检对时序与类型声明失明」的历史教训。

---

## 二、机检盲区说明（为什么 16/16 PASS 仍要逐拍推演）

官方脚本 `machine_check_r10.py` 覆盖 14 项文本级规则：禁记号、占位符、POU 计数、终结符成对、声明行双语注释、CASE/ELSE 兜底、实例调用位置、赋值目标声明性、孤立分号、浮点判等、码位重叠等。本轮 17 个缺陷**无一能被上述任一项捕获**，原因分类如下：

| 缺陷类别 | 机检为何失明 | 本轮实例 |
|---|---|---|
| **CASE 标签集合完整性** | 脚本只数 `CASE` / `END_CASE` / `ELSE` 是否成对，不校验枚举值是否被标签全覆盖；缺标签在语法上完全合法 | R-FIX-1（PickAndPlace）主状态机缺 `eExecute` 标签 |
| **拍内读写次序** | 脚本无数据流分析，同一变量在主体中先写后写、先清后置都被视为两次合法赋值 | R-FIX-1（WindingTraverse）方向量清零；R-FIX-3（PickAndPlace）错误码覆盖；R-FIX-1（Axioline）计数装载后递减 |
| **可选接口空引用** | 脚本不追踪 `<> 0` 判空与成员调用的支配关系；`iAxisY.Stop()` 在文本上完全合规 | R-FIX-2（PickAndPlace）未注入 Y 轴直接 Stop |
| **判据缺维度** | 脚本不理解「到达 A 端」必须隐含「正在向 A 端运动」这一物理前提 | R-FIX-2（WindingTraverse）端位判据无方向条件 |
| **参数域钳位** | 脚本不检查「声明了 MIN/MAX 常量但从未使用」这一浪费信号 | R-FIX-1（PdiReadScheduler）PT 未钳位 |
| **入参使用率** | 脚本不统计入参是否被读取 | R-FIX-1（RfidTagHandler）`uHwErrorCode` 声明后从无引用 |
| **文档-代码一致性** | 脚本只查注释存在性与双语率，不校验验收向量与实现的数值一致性 | 6 条注释级缺陷（向量矛盾、语义描述错、隐式类型提升说明缺失） |

因此本轮坚持「三段式推演」：① 枚举全值 → CASE 标签双向映射表；② 每个内部量列出「本拍所有写入点」并按源码次序排列；③ 每条外部判据反向自问「物理前提是否被编码」。

---

## 三、逐文件裁定

| # | 文件 | 版本 | 行数 | 判定 | 结论摘要 |
|---|---|---|---|---|---|
| 1 | `DL_Base/FC_DL_BitFieldExtract.st` | 1.0.0 | 216 | **PASS** | 32 位满宽走常量掩码分支，规避 `SHL(x, 32)` 未定义行为；`nWidth=0` 与越界双重拒绝；V1~V5 手工复算全中 |
| 2 | `DL_Base/FC_DL_WeekOfYearCalc.st` | 1.0.0 | 316 | **PASS** | Zeller 重排 + 周四归属法；闰年 1/2 月折算前置；V1~V5 含跨年边界全命中（见第六节） |
| 3 | `DL_Base/FB_DL_BidirectionalCounter.st` | 1.0.0 | 387 | **PASS** | 加/减/清零优先级链、饱和不回绕、`bAtLimit` 三律（预清零-置位-保持）、R27 保持态每拍重写全部正确 |
| 4 | `DL_MathData/FC_DL_SearchMinMax.st` | 1.0.0 | 202 | **PASS** | 首次/末次命中语义分离正确；NaN 用 `x <> x` 判据；全量非有限时返回首个有效位索引而非 0 号位 |
| 5 | `DL_MathData/FC_DL_NthRoot.st` | 1.0.0 | 211 | **PASS** | 奇偶次分治；`x=0` 与 `n=0`/`n<0` 守卫齐备；Newton 迭代后做结果有限性复检，防发散穿透 |
| 6 | `DL_MathData/FC_DL_FactorialSat.st` | 1.0.0→**1.0.1** | 211 | FAIL→修复 | 饱和边界正确（12! 通过、13! 饱和）；**R-FIX-1【注释级】** DINT×INT 依赖隐式提升，违反红线三 |
| 7 | `DL_Algo/FB_DL_SineGenerator.st` | 1.0.0→**1.0.1** | 401 | FAIL→修复 | 相位累加 + 回绕 + 频率/周期双入口互斥正确；**R-FIX-1【注释级】** 验收向量 V1 与逐拍推演自相矛盾 |
| 8 | `DL_Algo/FB_DL_SawtoothGenerator.st` | 1.0.0→**1.0.1** | 404 | FAIL→修复 | 对称度映射、上升/下降段分段、回绕清零正确；**R-FIX-1【注释级】** 向量与推演矛盾（同 Sine 病根） |
| 9 | `DL_Algo/FC_DL_CoilDiameterCalc.st` | 1.0.0 | 298 | **PASS** | 卷径递推 `D←D+2h·Δn/1000` 量纲正确；低速保护先于除零；卷芯保护；首拍无滞后；变化率次序正确（观察项 O-1） |
| 10 | `DL_Algo/FC_DL_AirDensity.st` | 1.0.0 | 219 | **PASS** | Magnus 饱和蒸气压分母恒正（`243.12+T` 在工况域内不为 0）；分压防负；量纲 kg/m³ 正确 |
| 11 | `DL_Device/I_DL_RfidReader.st` | 1.0.0 | 164 | **PASS** | 接口 7 个成员与方法签名与实现件 `FB_DL_RfidTagHandler` 逐一对齐；配套 DUT 同文件发布符合契约 |
| 12 | `DL_Device/FB_DL_RfidTagHandler.st` | 1.0.0→**1.0.1** | 582 | FAIL→修复 | 五态握手（eIdle/eWaitTag/eRead/eWrite/eFault）出口完整；**R-FIX-1【中等】** `uHwErrorCode` 声明后从未使用；**R-FIX-2【注释级】** 诊断刷新规则需同步 |
| 13 | `DL_Device/FB_DL_AxiolineDiagLatch.st` | 1.0.0→**1.0.1** | 398 | FAIL→修复 | 位域解析 7 位映射正确；**R-FIX-1【严重】** 屏蔽计数同拍先装载后递减 → 屏蔽恒 0；**R-FIX-2【中等】** 锁存未判使能；**R-FIX-3【注释级】** 事件计数语义描述错 |
| 14 | `DL_Device/FB_DL_PdiReadScheduler.st` | 1.0.0→**1.0.1** | 411 | FAIL→修复 | 五态重试链、退避、长度校验正确；**R-FIX-1【中等】** 超时值未钳位，PT=0 形成重试风暴；**R-FIX-2【注释级】** 码表 013F 语义 |
| 15 | `DL_Motion/FB_DL_WindingTraverse.st` | 1.0.0→**1.0.1** | 479 | FAIL→修复 | 五态换向时序；**R-FIX-1【致命】** 待机态每拍清方向 → 位移恒 0；**R-FIX-2【严重】** A 端判据无方向条件；**R-FIX-3【中等】** 到位判据分母 0/0；**R-FIX-4【中等】** 卷径首拍未预置 |
| 16 | `DL_Process/FB_DL_PickAndPlaceStation.st` | 1.0.0→**1.0.1** | 629 | FAIL→修复 | 九步序 + 七态；**R-FIX-1【致命】** 主 CASE 缺 `eExecute` 标签；**R-FIX-2【严重】** 未注入 Y 轴直接 Stop；**R-FIX-3【中等】** 步 1 清零覆盖同拍错误码 |

---

## 四、缺陷清单（17 条，按分级）

### 4.1 致命（2 条）

#### D-01【致命】主状态机 CASE 缺 `eExecute` 标签，执行态被兜底判为非法并锁故障

* **文件**：`DL_Process/FB_DL_PickAndPlaceStation.st`
* **位置**：段 7 主 `CASE _eState OF`（原 236 行附近）
* **问题**：七态枚举 `E_DL_SpState` 定义 `eIdle / eReady / eExecute / eDone / eFault / ePaused / eReset`，但主 CASE 只列了 `eIdle / eReady / eDone / eFault / ePaused / eReset` 六个标签，**漏掉 `eExecute`**。段 8~11 的时序逻辑写在 CASE **之外**、以 `IF _eState = eExecute` 形式处理，编码者据此认为「不需要标签」。实际执行流为：`CASE` 先跑，`eExecute` 命中 `ELSE` 兜底分支，兜底分支判定「非法状态」→ 置 `uErrorId := 16#0005_02B0` 并 `_eState := eFault`；随后段 8~11 的 `IF _eState = eExecute` 因状态已被改写为 eFault 而整段跳过。**后果：工站从 eReady 推进到 eExecute 的当拍即自杀，永远走不到第一个动作，全部九步序一行不执行。**这是本轮最严重的功能性缺陷，且机检 4 个 CASE / ELSE 齐全的全绿结论完全无法发现。
* **修复**：在 CASE 中显式加入 `eExecute` 标签分支，分支体内**只写注释、不写任何动作**，动作仍由段 8~11 承担，并在注释中固化「为何必须显式列出」的原因，防止后续维护者再次删除：

```iecst
E_DL_SpState.eExecute:
    (* 执行态本体在段 8 至段 11 中处理（步超时、动作下发、完成推进、循环超时）
       本分支必须显式列出：CASE 缺该标签会让 eExecute 落入 ELSE 兜底而被判为
       非法状态并锁故障，工站将永远无法执行。禁止在此分支内写任何动作。 *)
```

---

#### D-02【致命】待机态每拍把方向量清零且卷绕态从不重新赋值，排线位移恒为 0

* **文件**：`DL_Motion/FB_DL_WindingTraverse.st`
* **位置**：状态机待机分支（`E_DL_WindState.eIdle`）+ 卷绕分支的位移积分
* **问题**：待机分支写作 `nDirInt := 0;` 且位于分支体**最前**（无条件每拍执行），启动成功转入 `eWinding` 后，卷绕分支**从未把 `nDirInt` 赋回 ±1**，只在端点处做 `nDirInt := -nDirInt;`（0 取反仍是 0）。于是 `fTravPos := fTravPos + nDirInt * fSpeedUse * fDtUse` 每拍增量恒 0，排线轴原地不动；又因 `fTravPos` 恒为 0 使 A 端判据持续命中，状态在 eWinding 与 eDwell 之间空转抖动，表现为「轴不动但状态乱跳」。**后果：排线功能完全失效，收卷叠线，属现场可立即造成废料的失效。**
* **修复**：把方向赋值移入启动成功分支（固定正向启动），待机未启动时才清零：

```iecst
E_DL_WindState.eIdle:
    IF fbTrigStart.Q AND bEnable THEN
        IF NOT bAxisReady THEN
            uErrorId := 16#0004_01B3;
        ELSE
            nDirInt := 1;                // 启动方向固定为正向
            _eState := E_DL_WindState.eWinding;
        END_IF
    ELSE
        nDirInt := 0;
    END_IF
```

---

### 4.2 严重（3 条）

#### D-03【严重】故障停机对未注入的可选 Y 轴直接调用 `Stop()`，空引用

* **文件**：`DL_Process/FB_DL_PickAndPlaceStation.st`
* **位置**：段 12 故障安全停机
* **问题**：原实现为 `IF bAxisValid THEN iAxisX.Stop(); iAxisY.Stop(); iAxisZ.Stop(); iVacuum.CmdStop(); END_IF`，而 `bAxisValid` 只覆盖 X/Z/真空三路的有效性。Y 轴是可选注入（`iAxisY : I_DL_MotionAxis`，可为 0），当现场只用两轴模板时 `iAxisY = 0`，故障拍会执行 `0.Stop()`。CODESYS/TwinCAT 对接口指针空引用调用行为未定义（多数平台直接异常停机，汇川 InoProShop 报访问违例），**恰在最需要安全停机的时刻把 PLC 打死**。
* **修复**：四路逐个判空，不再依赖聚合布尔量：

```iecst
IF (_eState = E_DL_SpState.eFault) AND (NOT bFaultStopDone) THEN
    IF iAxisX <> 0 THEN iAxisX.Stop(); END_IF
    IF iAxisY <> 0 THEN iAxisY.Stop(); END_IF
    IF iAxisZ <> 0 THEN iAxisZ.Stop(); END_IF
    IF iVacuum <> 0 THEN iVacuum.CmdStop(); END_IF
    bFaultStopDone := TRUE;
END_IF
```

---

#### D-04【严重】A 端判据缺方向条件，启动首拍即误判「到达 A 端」

* **文件**：`DL_Motion/FB_DL_WindingTraverse.st`
* **位置**：卷绕态端点判定
* **问题**：原判据为 `IF fTravPos >= fTravUse THEN (到达 B 端) ELSIF fTravPos <= 0.0 THEN (到达 A 端)`。启动时 `fTravPos = 0`，第一拍即满足 `<= 0.0` 命中「到达 A 端」→ 进入停留、换向为负、反向走完全程。表现为**每次启动都先跑到 A 端再折返，首圈排线相位错乱**；叠加 D-02 时更退化为原地抖动。此缺陷在 D-02 修复后仍独立存在，必须单独修。
* **修复**：两个端位判据均加方向条件（只有「正在朝该端运动」才算到达）：

```iecst
IF (nDirInt > 0) AND (fTravPos >= fTravUse) THEN
    ... 到达 B 端 ...
ELSIF (nDirInt < 0) AND (fTravPos <= 0.0) THEN
    ... 到达 A 端 ...
END_IF
```

---

#### D-05【严重】确认屏蔽计数同拍先装载后递减，屏蔽长度恒为 0，`bAckDiag` 完全无效

* **文件**：`DL_Device/FB_DL_AxiolineDiagLatch.st`
* **位置**：确认沿处理段
* **问题**：原实现为
  ```iecst
  IF fbTrigAck.Q THEN nAckMute := DL_ACK_MUTE; END_IF
  IF nAckMute > 0 THEN nAckMute := nAckMute - 1; END_IF
  ```
  确认拍先装载为 N，紧接着同拍无条件递减为 N-1；但屏蔽判据 `IF nAckMute > 0` 在此之前已经求值（或读到的是递减后的值），等效屏蔽窗口只有 0 拍。**后果：`bAckDiag` 确认按钮形同虚设——操作员按下确认，下一拍诊断位原样复现，现场表现为「怎么按都消不掉」，而规格明确要求确认沿起屏蔽 N 拍以便故障源复位。**
* **修复**：装载拍不递减，只有非确认拍才递减：

```iecst
IF fbTrigAck.Q THEN
    nAckMute := DL_ACK_MUTE;             // 确认拍：装载屏蔽长度，当拍不清零
ELSIF nAckMute > 0 THEN
    nAckMute := nAckMute - 1;            // 非确认拍才递减
END_IF
```

---

### 4.3 中等（6 条）

#### D-06【中等】步 1 下发分支清零错误码，覆盖同拍刚置位的 `01B0`

* **文件**：`DL_Process/FB_DL_PickAndPlaceStation.st`｜**位置**：步 1 动作下发分支
* **问题**：段 8 在步超时判定中置 `uErrorId := 16#0005_01B0`，段 9 的步 1 下发分支又执行 `uErrorId := 16#0000_0000;`。段 8 先于段 9，故超时码在置位当拍被立即抹掉，HMI 上永远看不到「步 1 超时」。诊断不可见 = 现场无法定位。
* **修复**：删除该清零语句，改为纯注释说明「错误码清零只在段 13 单点出口执行」，避免多处写同一变量。

#### D-07【中等】轴到位判据分母为可变入参，参数非法时 0/0 得 NaN

* **文件**：`DL_Motion/FB_DL_WindingTraverse.st`｜**位置**：轴等待上限计算
* **问题**：`fAxisWaitMax := (2.0 * fTravUse / fSpeedUse) / fDtUse;`，`fSpeedUse`、`fDtUse` 均为外部入参。参数未配置（0）时先得 `Inf` 再得 `NaN`，`NaN` 参与一切比较均为 FALSE → 轴等待超时永不触发 → 卡死在等待态。
* **修复**：两处分母各加常量守卫：`MAX(fSpeedUse, DL_SPEED_MIN)`、`MAX(fDtUse, DL_CYCLE_MIN)`，并在注释中写明「入参为 0 表示未组态，按最小物理量处理以避免非数」。

#### D-08【中等】仲裁卷径首拍未预置，首拍输出 0 米并产生 -10 m/s 级假变化率

* **文件**：`DL_Motion/FB_DL_WindingTraverse.st`｜**位置**：首扫段与复位段
* **问题**：`fDiaArb`（仲裁后卷径）在首扫与复位路径均未赋值，保持 0。首拍 `fDia` 输出 0 m，`fDiaRate := (fDia - fDiaPrev) / fDt` 出现约 -10 m/s 的假跳变，触发下游「卷径突变」报警。R19 首扫范式要求所有派生量在首扫拍即达稳态。
* **修复**：首扫与复位两条路径均补 `fDiaArb := fCoreDia;` / `fDiaArb := fCoreUse;`，使首拍卷径等于卷芯直径。

#### D-09【中等】锁存条件未判使能，未使能仍锁存并累加事件

* **文件**：`DL_Device/FB_DL_AxiolineDiagLatch.st`｜**位置**：`eMonitor` 态锁存判定
* **问题**：原条件 `IF bStable AND (eLevelRaw <> E_DL_DiagLevel.eNone)`，缺 `bEnable`。块未使能（设备未投运）时仍锁存故障并累加 `uEventCnt`，与文件头「未使能只清实时位、保留历史」的声明直接矛盾，且会造成停机检修期间的虚假事件堆积。
* **修复**：条件改为 `IF bEnable AND bStable AND (eLevelRaw <> E_DL_DiagLevel.eNone) THEN`。

#### D-10【中等】单次超时未钳位，`PT := 0` 造成每拍立即超时的重试风暴

* **文件**：`DL_Device/FB_DL_PdiReadScheduler.st`｜**位置**：等待态定时器实例化
* **问题**：`fbTmo(IN := bTmoIn, PT := tTimeout)` 直接使用原值；`DL_TMO_MIN` / `DL_TMO_MAX` 两个常量**声明后从未使用**（这是可被静态检查捕获的浪费信号，机检未覆盖）。`tTimeout = T#0S` 时 TON 每拍立即 Q=TRUE → 重试计数每拍 +1 → 瞬间打满重试上限并报错，同时向从站发起高频请求。
* **修复**：新增成员 `tTmoUse : TIME := T#1S;`，在参数校验段钳位 `tTmoUse := LIMIT(DL_TMO_MIN, tTimeout, DL_TMO_MAX);`，定时器改用 `PT := tTmoUse`，越界时并入 `16#0003_013F` 参数域钳位事件。

#### D-11【中等】`uHwErrorCode` 入参声明后从未使用，硬件原始码无法透传进诊断

* **文件**：`DL_Device/FB_DL_RfidTagHandler.st`｜**位置**：`eWaitHw` 的 `bHwError` 分支 + 段 9 诊断刷新
* **问题**：规格要求「读写头原始错误码透传进诊断」，引脚已声明但函数体零引用，`stDiag.uLastErrorId` 只剩块级码，现场拿到 `01xx` 类块级码后无法再到厂家手册查具体原因（原始码才是厂家侧的可查键）。
* **修复**：`bHwError` 分支写入 `stDiag.uLastErrorId := uHwErrorCode;`；段 9 改为**条件刷新**，仅在块级码非零时覆盖，防止每拍把透传值清 0：
  ```iecst
  stDiag.nCommRetry := nRetryCnt;
  IF uErrorId <> 16#0000_0000 THEN
      stDiag.uLastErrorId := uErrorId;   // 仅在块级码非零时刷新，避免把透传的硬件原始码清掉
  END_IF
  stDiag.tLastComm := fbAge.ET;
  ```

---

### 4.4 注释级（6 条）

| 编号 | 文件 | 位置 | 问题 | 修复 |
|---|---|---|---|---|
| D-12 | `FB_DL_AxiolineDiagLatch.st` | 事件台账段落 | 把 `uEventCnt` 描述为「故障发生了几次」，实际语义是「锁存后不覆盖、复位前不再加一」= 锁存事件次数 | 按实际行为改写描述，与代码逐步对齐 |
| D-13 | `FB_DL_PdiReadScheduler.st` | 码表 `013F` 条目 | 语义仅写「期望长度越界」，修复后新增超时钳位也走该码 | 扩写为「期望长度或单次超时越界被钳位」 |
| D-14 | `FB_DL_RfidTagHandler.st` | 文件头诊断字段说明 | 未说明 `uLastErrorId` 的「硬件原始码 vs 块级码」优先级规则 | 同步为「硬件报错拍写原始码，块级码非零时才覆盖」 |
| D-15 | `FB_DL_SineGenerator.st` | 验收向量 V1 + 新增约定段 | 向量写「第 1 拍相位 90 度」，而同文件逐拍推演与实现均为「第 1 拍输出初相、第 2 拍 90 度」；R12 要求向量可复算，矛盾向量会让下游误用 | 按实际行为改写 V1，并新增「相位采样与拍号对应」段落显式声明一拍固有延迟 |
| D-16 | `FB_DL_SawtoothGenerator.st` | 验收向量 V1 + 新增约定段 | 向量写「第 1 拍 50、第 3 拍 50」，实现为「第 1 拍 0、第 2 拍 50、第 3 拍 100、第 4 拍 50」 | 同上，并向量改写为逐拍序列 + 采样约定段 |
| D-17 | `FC_DL_FactorialSat.st` | 累乘语句 | `nAcc := nAcc * i;` 为 DINT × INT，依赖隐式类型提升，违反红线三「不用隐式类型转换」，部分平台报隐式转换告警 | 改为 `nAcc := nAcc * INT_TO_DINT(i);`，数值结果与全部向量不变 |

---

## 五、修复件清单与版本留痕

| # | 文件 | 版本 | 行数变化 | 缺陷编号 | 修复类型 |
|---|---|---|---|---|---|
| 1 | `DL_Process/FB_DL_PickAndPlaceStation.st` | 1.0.0→1.0.1 | 596→629（+33） | D-01 / D-03 / D-06 | 代码 3 处 |
| 2 | `DL_Motion/FB_DL_WindingTraverse.st` | 1.0.0→1.0.1 | 459→479（+20） | D-02 / D-04 / D-07 / D-08 | 代码 4 处 |
| 3 | `DL_Device/FB_DL_AxiolineDiagLatch.st` | 1.0.0→1.0.1 | 390→398（+8） | D-05 / D-09 / D-12 | 代码 2 处 + 注释 |
| 4 | `DL_Device/FB_DL_PdiReadScheduler.st` | 1.0.0→1.0.1 | 390→411（+21） | D-10 / D-13 | 代码 1 处 + 注释 |
| 5 | `DL_Device/FB_DL_RfidTagHandler.st` | 1.0.0→1.0.1 | 562→582（+20） | D-11 / D-14 | 代码 1 处 + 注释 |
| 6 | `DL_Algo/FB_DL_SineGenerator.st` | 1.0.0→1.0.1 | 381→401（+20） | D-15 | 注释 |
| 7 | `DL_Algo/FB_DL_SawtoothGenerator.st` | 1.0.0→1.0.1 | 387→404（+17） | D-16 | 注释 |
| 8 | `DL_MathData/FC_DL_FactorialSat.st` | 1.0.0→1.0.1 | 207→211（+4） | D-17 | 代码 1 处 |

* 全部 8 件在文件头「修订历史」段落逐条列明 `R-FIX-n` 及其分级与成因，符合 R12「向量/描述自洽」与溯源要求。
* 修复前原件备份：`_Staging_Raw/2026-11-15/fix_backup_R10/*.st.v100`（8 个）。
* 版本号仅动 PATCH 位，未改任何对外引脚名、引脚顺序或类型（D-01/D-02/D-03/D-04/D-06/D-08 均为函数体内部逻辑；D-10 新增一个 VAR 内部成员 `tTmoUse`，不属接口）。

---

## 六、独立数学验算

全部向量由人工按实现语句逐步复算，不引用编码者给出的结论。

### 6.1 `FC_DL_WeekOfYearCalc`（V1~V5）

算法：Zeller 同余求星期（1=周一…7=周日）→ 判定本周归属年（周四原则）→ 序日差 / 7 取整。

| 向量 | 输入 | 星期 | 归属年 | 周数 | 结论 |
|---|---|---|---|---|---|
| V1 | 2024-01-01 | 周一 | 2024 | 1 | ✅ 与实现一致 |
| V2 | 2021-01-01 | 周五 | **2020** | **53** | ✅ 跨年回退正确 |
| V3 | 2027-01-01 | 周五 | **2026** | **53** | ✅ 同上（2026 为平年但 12-31 为周四，故 53 周成立） |
| V4 | 2026-11-15 | 周日 | 2026 | 46 | ✅ 周 1 起于 2025-12-29，序日 319 + 3 = 322，322/7 = 46 整 |
| V5 | 2020-12-31 | 周四 | 2020 | 53 | ✅ 周四原则边界 |

**关键边界复核**：V2/V3 是规格原公式的必错点。规格速算式对 2026-01-01 得 3，正确答案为 4（周四），且未对闰年 1/2 月做 31/30 折算——**规格公式本身有误**，详见第七节偏离裁定。

### 6.2 `FC_DL_NthRoot`（V1~V6）

| 向量 | 输入 → 输出 | 复算 |
|---|---|---|
| V1 | `27^(1/3)` → 3.0 | Newton 初值 `x0=27`，三步内收敛至 3±1E-9 ✅ |
| V2 | `16^(1/4)` → 2.0 | 偶次分支（直接幂）✅ |
| V3 | `-32^(1/5)` → -2.0 | 奇次分支取 `-((-x)^(1/5))` ✅ |
| V4 | `0^(1/n)` → 0.0 | 零守卫直返，未进迭代 ✅ |
| V5 | `-8^(1/2)` → 错误码 | 偶次 + 负底数拒绝 ✅ |
| V6 | `1E300^(1/3)` → ≈1E100 | 收敛性：迭代误差单调下降，结果有限性复检拦住 `Inf` ✅ |

### 6.3 信号发生族（Sine / Sawtooth）相位与频率换算

* 每拍相位增量 `Δφ = 360° × f × dt`；`f=1 Hz, dt=0.25 s` → `Δφ=90°`。
* 第 1 拍（进态拍）输出 `A·sin(φ0)+offset`，第 2 拍 `φ=φ0+90°`。**即一拍固有延迟**，这是 D-15/D-16 的根因，已在文件中显式约定。
* 回绕：`φ ≥ 360° → φ -= 360°`，用减法而非取模，避免 LREAL 取模的平台差异。
* Sawtooth 对称度 `r`：上升段占 `r` 比例，`r=0.5` 为对称三角波，`r→1` 为缓升陡降锯齿。V1 逐拍序列 `0 → 50 → 100 → 50`（幅值 100、`r=0.5`）复算正确。

### 6.4 `FC_DL_CoilDiameterCalc`

* 卷径递推：每圈厚度增量 `ΔD = 2h`（直径两侧各一层），`ΔD_m = 2h_mm/1000 × Δn`。
* 卷径-转速关系校验：`D = v / (π·n)`，取 `v=100 m/min`、`n=100 r/min` → `D = 100/(π×100) = 0.31831 m`，与实现一致，量纲 m 正确。
* 打滑判定：实测卷径与递推卷径偏差超阈值 → `bSlip`；低速保护（`n < nMin`）先于除法，避免 `n→0` 时 `D→∞`。
* 首拍不滞后：`fDiaPrev` 在首扫即置为当前卷径，变化率首拍为 0。

### 6.5 `FC_DL_AirDensity`

* Magnus：`psat = 610.94 × exp(17.625T/(243.04+T))`，`T=15℃` → `psat ≈ 1705 Pa`。
* `pv = RH × psat = 0`（0%RH）→ `pd = 101325 Pa`。
* `ρ = pd/(287.05 × 288.15) + pv/(461.495 × 288.15) = 1.2250 kg/m³` ✅ 与标准值一致。
* 分母恒正性：`243.04 + T` 在 `T > -243℃` 恒正，工况域内不可能为 0；`pv` 由 `MAX(0, ...)` 防负。

### 6.6 `FC_DL_FactorialSat`

* `12! = 479001600 < 2^31-1 = 2147483647` ✅ 正常返回。
* `13! = 6227020800 > 上限` → 返回 `2147483647` 饱和值 ✅。
* `0! = 1` 与负数拒绝（`n<0 → 错误码 011D`）✅。
* 修复 D-17 后数值路径不变（`INT_TO_DINT` 仅显式化提升）。

### 6.7 `FB_DL_BidirectionalCounter` 溢出绕回

* 加法饱和：`nVal > nMax - nStep` 时钳到 `nMax`，不绕回负数 ✅。
* 减法饱和同理；`bAtLimit` 三律：每拍先清 → 命中置位 → 保持态重写（R27）✅。
* 优先级：`bReset > bPreset > 加/减同时`（加优先）；同时加减小一个步长按「加」结算，规格一致。

### 6.8 `FC_DL_BitFieldExtract`（V1~V5）

* `width=32` 走 `16#FFFF_FFFF` 常量掩码分支，**规避 `SHL(x,32)` 未定义行为**（ARM/x86 表现不同，是三平台移植的经典坑）。
* `width=0` 拒绝（返回 0 并置码），`offset+width>32` 拒绝。
* V1 `(0xDEADBEEF, 8, 8) → 0xBE`；V2 `(0xDEADBEEF, 0, 8) → 0xEF`；V3 满宽恒等；V4 越界拒绝；V5 `width=0` 拒绝 —— 全部复算一致。

### 6.9 `FB_DL_WindingTraverse` 换向清零时序（修复后）

| 拍 | 状态 | `nDirInt` | `fTravPos` | 说明 |
|---|---|---|---|---|
| 1 | eIdle | 0 | 0 | 未启动，方向清 0 |
| 2 | eIdle→eWinding | **+1** | 0 | 启动沿：置正向并转态 |
| 3 | eWinding | +1 | +v·dt | Δ>0，A 端判据（需 `<0`）不命中 ✅ |
| … | eWinding | +1 | → fTravUse | |
| k | eWinding | +1 | ≥ fTravUse | B 端命中（方向>0）✅ → eDwell |
| k+m | eDwell→eWinding | **-1** | fTravUse | 停留结束换向 |
| … | eWinding | -1 | 递减 | |
| j | eWinding | -1 | ≤0 | A 端命中（方向<0）✅ |

修复前该表第 2 拍 `nDirInt=0` → 第 3 拍 `Δ=0` → 位置恒 0 → 每拍命中 A 端，即 D-02/D-04 的联动失效链。

---

## 七、规格偏离裁定

### 7.1 `FC_DL_WeekOfYearCalc`：算法整体替换为 Zeller + 周四归属法 —— **采纳，判定合理**

* **规格原公式的两处硬错**：
  1. 对 2026-01-01 得 3，实际为 4（周四）。任何以「周一为周首」的 ISO 周算法都必须命中 4，否则第 1 周起止整体错一周。
  2. 未对闰年 1/2 月做 31/30 折算（规格式隐含「每月按 30 天」），闰年 3 月后全部偏 1 天。
* **编码者做法**：改用 Zeller 同余求星期（无查表、无浮点、无平台差异）+ 周四归属法判定归属年 + 序日差求周数；在文件头 Deviations 段留档偏离原因，并给出 V1~V5 向量。
* **总监复核**：V1~V5 我独立手工复算全部命中（见 6.1）；Zeller 实现中 `(13(m+1))/5` 用整数除法，`m<=2` 时 `m+=12, y-=1` 已前置；`y` 的世纪项用 `y%100` 与 `y/100` 拆分，无 32 位溢出风险。
* **裁定**：**采纳**。规格公式有误时按 R11「规格与正确性冲突以正确性为准，但必须留档」处理，编码者做到了。**建议下一轮修订 ROUND_PLAN 模板，把该公式替换为 Zeller 或明确「参考 ISO 8601」**，避免后续组件继续抄错公式。

### 7.2 `FB_DL_PickAndPlaceStation` 接口适配（D1/D2/D3）—— **采纳，但要求文档线同步**

* **D1 新增 `fSafeZ` / `fPosTol` 两个输入引脚**：规格只以文字描述「抬升到安全位」「到位判据」，未给引脚。按「无魔法数」红线提为引脚（带默认值，向后兼容）合理。**但**：规格书的接口表与实际交付件已出现 2 个引脚差异，须由文档线在下一环节同步到 MANUAL 与 SOURCE_HUNTING_MATRIX，否则下一位编码者会按旧表继续写错。
* **D2 到位判据改为 `eState = eStandstill` + 容差窗**：`I_DL_MotionAxis` 确实无「到位位」属性（我已核对接口文件），编码者改为「静止态 + 位置在容差窗内」是**语义等价且更严格**的实现（静止但偏差异常仍判未到位）。裁定采纳，D2 说明已进头注释。
* **D3 循环超时复用 `02B7`**：`01B0~01B4` 与 `02B0~02B7` 已满，按 R30 不得跨块取 `02B8`。复用兜底码虽牺牲了「循环超时 vs 非法状态」的码级区分，但注释已写明，且不违反 R30。**裁定采纳，记入观察项 O-2**：下一 MAJOR 应为本族扩块（如 `02C0~02CF`）。

### 7.3 `I_DL_RfidReader` 的 METHOD 写法保留 —— **非缺陷，维持**

* 库内既有惯例为 CODESYS 内联成员声明（`METHOD X : BOOL` 直接结束，无 `END_METHOD`），全库 136 件同写法并已入库存续多轮。**不是缺陷**，机检 `INTERFACE=1/1`、`TYPE=4/4` 亦通过。若未来统一改为 IEC 标准写法，须全库一次性迁移，不属 PATCH 版范围。

### 7.4 码位块内尾号扩展（`1B01~1B11`、`1C01~1C10`、`1D01~1D10`、`1E01~1E10` 等）—— **采纳**

* 段位公约 `16#00SS_XXXX` 只约束 `SS`（子库段），`XXXX` 内部如何分块是子库自治。R10 四个算法件各占一个 `1x00` 编号带（`1B` 正弦 / `1C` 锯齿 / `1D` 卷径 / `1E` 空气密度），带内 `01~0F` 事件码、`10+` 信息码，结构清晰且不与既有件冲突（机检全库求差仅 `0000_0000` 重复）。**裁定采纳**，建议把「每件独占一个 `1x` 编号带」写入 coding-standard 作为算法族的推荐做法。

### 7.5 `FB_DL_WindingTraverse` 的 `nPitchPerRev : LREAL` 命名冲突（D1）—— **采纳「契约优先」，但限期整改**

* `n` 前缀表有符号整数，而实参为浮点物理量。因该引脚名与规格书、对外契约同源，PATCH 版改名属破坏性变更。登记为观察项 **O-3**，下一 MAJOR 统一改 `fPitchPerRev` 并同步规格书。

### 7.6 `FB_DL_RfidTagHandler` 的 D1（`stCfg` 同名遮蔽）/ D2（`bHwReq`/`bHwWr` 提为输出）—— **采纳**

* D1：方法形参遮蔽同名引脚，但方法体不引用形参，实际组态以块级引脚为准；改形参会破坏接口契约，保留合理，头注释已写明联调注意（同一实例同时接引脚与 `Init` 调用）。记观察项 **O-4**：下一 MAJOR 把形参改名为 `stInitCfg`。
* D2：`bHwReq`/`bHwWr` 是送协议/IO 层的指令电平，必须可外部观测与接线，提为 `VAR_OUTPUT` 属向后兼容的可见性扩展。**采纳**。

---

## 八、JSONL 再同步（字节级）

### 8.1 前置

| 项 | 值 |
|---|---|
| 目标文件 | `C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl` |
| 备份 | `daoli_st_sft_dataset.jsonl.backup_R10_FINAL`（3,158,798 B，与修改前逐字节相同） |
| 修改前 sha256 | `1734ffd8ea9b9f4ba3fe2052ab216c0e422ababe22f810d0aa7e11c5f3db2b90` |
| 修改前行数 / 字节 | 152 行 / 3,158,798 B |

### 8.2 重注入

脚本 `_Staging_Raw/2026-11-15/resync_jsonl_r10.py`，流程：**前置校验（当前文件必须与备份同 sha256，否则拒绝写入）→ 从 `output` 头注释「组件名称 (Component)」反查 POU 名定位（不依赖固定行号）→ `json.loads` → 仅替换 `output` 为修复后 `.st` 的 UTF-8 原文（`newline=''` 保原换行）→ `json.dumps(ensure_ascii=False)` 单行写回 → 漂移校验 → round-trip 校验 → 落盘**。

| 行号 | POU | 原 chars | 新 chars |
|---|---|---|---|
| 142 | `FC_DL_FactorialSat` | 8,796 | 9,070 |
| 143 | `FB_DL_SineGenerator` | 16,712 | 17,654 |
| 144 | `FB_DL_SawtoothGenerator` | 16,738 | 17,570 |
| 148 | `FB_DL_RfidTagHandler` | 24,022 | 24,959 |
| 149 | `FB_DL_AxiolineDiagLatch` | 17,545 | 18,141 |
| 150 | `FB_DL_PdiReadScheduler` | 17,429 | 18,300 |
| 151 | `FB_DL_WindingTraverse` | 20,891 | 22,043 |
| 152 | `FB_DL_PickAndPlaceStation` | 26,011 | 27,377 |

> 说明：R10 十六件在 JSONL 中占第 137~152 行（`FC_DL_BitFieldExtract`=137 … `FB_DL_PickAndPlaceStation`=152）。上表行号为 1-based。

### 8.3 校验结果

| 校验项 | 结果 |
|---|---|
| 行数 | 152（不变） |
| 仅上述 8 行发生字节变化 | ✅ `changed = [142,143,144,148,149,150,151,152]` |
| 其余 144 条逐字节零漂移 | ✅ |
| `instruction` / `architecture_thought` 字段 | ✅ 152 条全部一致（键集与内容） |
| 8 条 `output` 与修复后 `.st` 字节一致 | ✅ 8/8 MATCH |
| round-trip（`json.loads` 后 `output` 与 `.st` 全等） | ✅ 8/8 |
| 末行保留换行 | ✅ |

| 项 | 值 |
|---|---|
| 修改后字节 | 3,171,437 B（+12,639） |
| **修改后 sha256** | `57c47910907d722db79c16b6dae33aea9e69d39090ba9ffd7632f2e62b6aba79` |

---

## 九、机检复跑（修复后）

| 检查项 | 口径 | 结果 |
|---|---|---|
| 被禁记号（全局变量表/外部变量/绝对地址） | 全文命中 = 0 | 16/16 通过 |
| 占位符（TODO/FIXME/XXX） | = 0 | 16/16 通过 |
| POU 计数（声明数 = 终结符数） | 逐件相等 | 16/16 通过 |
| 末行终结符 | `END_FUNCTION_BLOCK` / `END_FUNCTION` / `END_INTERFACE` | 16/16 通过 |
| 声明行双语注释 | 缺注释 0 / 非双语 0 | 16/16 通过（共 580 个声明行） |
| CASE / ELSE 兜底 | 全库 11 个 CASE 全部带 ELSE | 16/16 通过 |
| 实例调用位置 | 分支内实例数 = 0 | 16/16 通过 |
| 赋值目标声明性（R29） | 未声明 0 | 16/16 通过（共 668 个赋值目标） |
| 孤立分号（R26） | = 0 | 16/16 通过 |
| 浮点判等 | = 0 | 16/16 通过 |
| 码位跨文件重叠 | 应 = 0 | 仅 `16#0000_0000`（无事件码自身，非串台） |
| **总计** | | **16/16 PASS，总行数 5,528** |

> 注：`FC_DL_BitFieldExtract.st` 中的 `16#DEAD_BEEF` / `16#FFFF_FFFF` / `16#0000_00BE` / `16#0000_00FF` 为**文档示例数据与掩码**，`FB_DL_PdiReadScheduler.st` 中的 `16#0000_0004` / `16#0000_0005` / `16#0000_FFFF` / `16#0002_8011` 为**索引与示例错误码**，均不参与事件码唯一性判定，人工已逐一核对。

---

## 十、剩余观察项（不阻断入库）

| 编号 | 文件 | 观察项 | 建议处置 |
|---|---|---|---|
| O-1 | `FC_DL_CoilDiameterCalc.st` | 常量 `DL_NMAX` 声明后从未使用（卷径上限判据改用引脚） | 下一 PATCH 删除或接入上限钳位 |
| O-2 | `FB_DL_PickAndPlaceStation.st` | 循环超时复用兜底码 `02B7`，与「非法状态」共码，HMI 无法区分 | 下一 MAJOR 扩块（`02C0~02CF`）并拆分 |
| O-3 | `FB_DL_WindingTraverse.st` | `nPitchPerRev : LREAL` 前缀与类型冲突 | 下一 MAJOR 改 `fPitchPerRev` 并同步规格书 |
| O-4 | `FB_DL_RfidTagHandler.st` | `Init` 形参 `stCfg` 与块级引脚同名遮蔽 | 下一 MAJOR 改名 `stInitCfg` |
| O-5 | `ROUND_PLAN_R10.md`（规格模板） | WeekOfYearCalc 速算式本身有误（周四归属与闰年折算双错） | 规格模板修订，改为 Zeller 或直接引用 ISO 8601 |

---

## 十一、边界声明

* 本记录**未**触碰 `VERSION.md` / `MANUAL` / `README` / `CHANGELOG` / `ROADMAP` / `SOURCE_HUNTING_MATRIX`（文档线职责，下一环节执行）。
* 本记录**未**新增任何组件，未改动任何组件名称、引脚名、引脚顺序。
* 唯一新增的声明性成员为 `FB_DL_PdiReadScheduler.tTmoUse`（`VAR` 内部量，非接口）。
* `INDEX_REGISTRY` 的 152 条记录与 `machine_check_r10_reg.json` 保持编码者交付状态；本环节只改 `.st` 与 JSONL `output`。

---

## 十二、签字

| 环节 | 角色 | 结论 | 时间 |
|---|---|---|---|
| 编码 | PLC 编程专家 | 交付 16 件，自报偏离 6 项 | 2026-11-15 |
| 机检 | 自动脚本 | 16/16 PASS | 2026-11-15 |
| **语义终审** | **产品总监（本记录）** | **PASS with fixes：17 缺陷全部修复，8 件升 1.0.1，JSONL 已再同步** | **2026-11-15** |

**终审结论：PASS with fixes —— 准许入库 v1.9.0。**
