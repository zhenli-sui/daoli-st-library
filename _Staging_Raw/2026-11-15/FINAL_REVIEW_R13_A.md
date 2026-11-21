# FINAL REVIEW R13 ｜ A 泳道终审报告（DL_Device 6 件）

- 终审人：道莅工控代码库产品总监（专家子代理兜底，本人执行，拥有终审裁定权与定点修复权）
- 终审日期：2026-11-16
- 依据：`ROUND_PLAN_R13.md` §3.0 通用约定（第 126~152 行）、§3.1 泳道 A 逐件规格（第 153~587 行）、§6 新规则 R37~R40（第 1447~1547 行）、§7 历史范式点名（第 1548~1598 行）；`daoli-st-standard` 编码红线与 `references/coding-standard.md`；`AGENT_EVOLUTION_LOG.md` R19~R44
- 机检：`python audit_library_r13.py --files <6 件>` → **修复前 fail=2 / 修复后 fail=0，16 项规则 0 FAIL 0 WARN**
- 终审判定：**6 件全部 PASS**（4 件升 v1.0.1，2 件契约件零改动保持 v1.0.0）

---

## 0 终审范围与总账

### 0.1 范围

| # | 组件 | 路径 | 类型 | 行数 | 码位（信息/故障） | 判定 | 版本 |
|---|---|---|---|---|---|---|---|
| A1 | `I_DL_DeviceHealth` | `DL_Device\` | INTERFACE + 1 枚举 | 146 | —（契约件） | **PASS** | 1.0.0（未改） |
| A2 | `I_DL_PowerMeter` | `DL_Device\` | INTERFACE + 1 枚举 | 142 | —（契约件） | **PASS** | 1.0.0（未改） |
| A3 | `FB_DL_ModbusPowerMeter` | `DL_Device\` | FB | 998 | 0156~015B / 0316~031B | **PASS** | 1.0.0 → **1.0.1** |
| A4 | `FB_DL_ValveStictionDetect` | `DL_Device\` | FB | 735 | 015C~015E / 031D~031F | **PASS** | 1.0.0 → **1.0.1** |
| A5 | `FB_DL_AhuDamperStuckDiag` | `DL_Device\` | FB | 615 | 0160~0161 / 0321~0325 | **PASS** | 1.0.0 → **1.0.1** |
| A6 | `FB_DL_PumpCavitationGuard` | `DL_Device\` | FB | 559 | 0164~0165 / 0326~0329 | **PASS** | 1.0.0 → **1.0.1** |

合计 3195 行 / 199,186 字符。

### 0.2 缺陷总账（11 条记录 = 9 条确定缺陷全部已修 + 1 条判断项裁定保留 + 1 条留档补强）

| 编号 | 件 | 级别 | 缺陷一句话 | 处置 |
|---|---|---|---|---|
| A3-D1 | A3 | 中等 | `_bPfMismatch` 无清零点，一次 015A 即永久 `eDegraded`（R34/R44 违例，`eDegraded→eSampling` 不可达） | 已修 |
| A3-D2 | A3 | 中等（机检 FAIL×2） | 语句段直写裸类型名 `E_DL_ByteOrder.eAbcd/.eCdab`，子集机检 `undefined_identifier` FAIL，且与库内既有范式不一致 | 已修 |
| A3-D3 | A3 | 提示 | 32 位电能回绕与「换表」同路径，头注释未登记 | 已补留档 |
| A4-D1 | A4 | 提示 | 距上次停滞定时器 `PT := T#24H` 为裸时间字面量（无魔法数红线） | 已修 |
| A4-D2 | A4 | 中等（判断项） | 判据 (a) 在全行程单向斜坡下无可比反转点，黏滞带恒 0 → 等级恒 `eNone` | **裁定保留**（保守方向，见 §3.3） |
| A5-D1 | A5 | 中等 | 判定相 `IF NOT _bFbOk` 直接判 0324，绕开 `tIoFaultTime` 确认窗（三分类「判据须带确认延时」缺口） | 已修 |
| A6-D1 | A6 | 中等 | `_bHoldActive` 取「窗满那一拍」而非整个降速相 → 0165 仅一瞬可见、窗内判据未真被抑制 | 已修 |
| A6-D2 | A6 | 中等（V5 直接违例） | 额定流量/扬程非正时拿兜底值 1.0 当分母，输出伪比值而非 0 | 已修 |
| A6-D3 | A6 | 中等（R21 一致性） | 汽蚀确认 `bError=TRUE` 但 `_uErrFault` 恒 0（0326 从未写入 `uErrorId`） | 已修 |
| A6-D4 | A6 | 提示 | 急停级 0327 不受 `bRunning/bEnable` 抑制，停泵时邻近设备振动可致误锁存 | 已修 |
| A6-D5 | A6 | 提示 | 停泵不清 `_fRipple`，停泵前旧波动率可跨停机存活到重启首窗 | 已修 |

> 计数说明：A3-D3 为「留档缺失」，不计缺陷等级；A4-D2 为判断项（保守方向的设计取舍）裁定保留。**9 条确定缺陷全部修复**，无 FAIL 级遗留，无未修项。

### 0.3 机检结果

```
修复前：undefined_identifier FAIL 2（A3 第 713/716 行 E_DL_ByteOrder）
修复后：SUMMARY: files=6 fail=0 warn=0
```

| 规则 | 结果 | 规则 | 结果 |
|---|---|---|---|
| banned_hits | PASS 0 | undefined_identifier | PASS 0（修复后） |
| placeholder | PASS 0 | single_colon_or_semicolon | PASS 0 |
| terminator | PASS 0 | line_count | INFO |
| bilingual_comment | PASS 0 | duplicate_pou_name | PASS 0（4 个 POU） |
| case_else | PASS 0 | r37_left_clamp | PASS 0 |
| enum_case_completeness | PASS 0 | r38_dual_source | PASS 0 |
| enum_separator | PASS 0 | r39_pre_case_override | PASS 0 |
| nested_comment | PASS 0 | r40_ton_cross_segment | PASS 0 |

附加人工配平检查（注释剥离后关键字计数）：`IF/END_IF 61/61、45/45、29/29、36/36`，`CASE/END_CASE 1/1`（四件），`FOR/END_FOR 3/3、1/1`，块结构零悬空。

---

## 1 A1 ｜ `I_DL_DeviceHealth`（v1.0.0，零缺陷，PASS）

### 1.1 规格逐项对照（ROUND_PLAN §3.1 A1）

| 规格项 | 规格要求 | 实现 | 判定 |
|---|---|---|---|
| 类型 | INTERFACE + 同文件枚举 | `INTERFACE I_DL_DeviceHealth` + `TYPE E_DL_Ne107Status` 同文件 | ✔ |
| 枚举成员 | 6 个，0/10/20/30/40/99 | `eFailure 0 / eCheckFunction 10 / eMaintenanceReq 20 / eOutOfSpec 30 / eOk 40 / eUnknown 99` | ✔ 逐值一致 |
| 枚举分隔符 | `:=`（R33） | 全部 `:=` + 同行双语注释 | ✔ |
| 属性 | 10 条只读 GET，类型逐字对齐 | eHealth/uDiagCode/uSourceId/tDuration/bLatched/bDataValid/fQuality/nCodeHistory/sDeviceClass(STRING(16))/bSimulated = 10 条 | ✔ |
| 方法 | 2 个（≤6 红线内） | `CmdAck : BOOL`、`CmdReset : BOOL` | ✔ |
| 受理语义 | CmdAck 不得应答 eFailure；CmdReset 仅 bLatched=TRUE 受理 | 头注释与接口段注释两处写死该语义 | ✔ |
| 无 VAR 段 | 接口只允许属性与方法 | 全文无 VAR/VAR_INPUT 之外的段；方法内 `VAR_INPUT ... END_VAR` 为空形参块，与 `I_DL_TowerLight` 先例逐字同构 | ✔ |
| 编号语义 | 「编号即优先级」且 ≠ NE107 图标序 | 头注释「优先级声明」段落显式写死，并给出「按图改号会让全部实现块仲裁方向静默反转」的告警 | ✔ 超出规格要求 |

### 1.2 七项红线

零全局变量引用 ✔｜零物理地址 ✔｜纯 IEC 61131-3 ✔（无 `PROPERTY ... SET`）｜防除零/越界/浮点容差 —（无执行体，不适用）｜变量同行双语注释 ✔（10 条属性 + 6 个枚举成员全覆盖）｜ENUM+CASE+ELSE —（契约件无 CASE，不适用）｜TON/R_TRIG 无条件刷新 —（无实例）。

### 1.3 历史范式

R33（枚举 `:=`）✔｜R31（枚举→CASE 映射）不适用，但「6 个成员即 4 个实现块健康出口的全部合法取值」已在头注释的「枚举映射」段声明，等价承担了映射表的职责 ✔｜R19/R24/R25/R27/R32/R34~R40 均不适用（无状态）。

### 1.4 终审判定

**PASS，v1.0.0 不改。** 该件是本泳道唯一属主件，`E_DL_Ne107Status` 全库仅此一处 `TYPE` 定义（已实扫确认：`grep -rn "^TYPE E_DL_Ne107Status"` 命中 1 处），符合 §7.2 专项纪律 1。

---

## 2 A2 ｜ `I_DL_PowerMeter`（v1.0.0，零缺陷，PASS）

### 2.1 规格逐项对照（ROUND_PLAN §3.1 A2）

| 规格项 | 规格要求 | 实现 | 判定 |
|---|---|---|---|
| 属性条数 | 表头写「11 条」，表体实际列 12 行 | 按**表体 12 条**实现，并在头注释「规格偏离 ①」显式登记 | ✔ 合理偏离，采纳（见 §7.2） |
| 属性集合 | eState/eHealth/uDiagCode/三相量/功率/PF/频率/正反向电能/峰值需量 | 12 条逐字对齐，`fEnergyImport/Export` 为 LREAL、`fActivePowerTotal` 有符号 | ✔ |
| eHealth 类型 | 必须引用 A1 的 `E_DL_Ne107Status`，禁止重复定义 | 引用 A1 类型；本文件仅定义 `E_DL_PowerMeterState` | ✔ |
| 重复定义体检 | — | 全文件无 `TYPE E_DL_Ne107Status`；头注释「健康出口」段写死「只引用、不重复声明」及其编译隐患 | ✔ |
| 同文件枚举 | `E_DL_PowerMeterState`：eIdle 0/eSampling 10/eDegraded 20/eFault 99 | 逐值一致，`:=` 分隔，含「S 与 F 之别」的语义注释 | ✔ |
| 方法 | 3 个：CmdResetEnergy / CmdReset / CmdAck | 3 个齐备，均带 BOOL 受理返回 | ✔ |
| CmdResetEnergy 前置 | 需 bLatched=FALSE | 契约未暴露 `bLatched` 属性，故在头注释与段注释两处规定「`bLatched` 语义由实现块等同 bError」并说明「故障期清零会同时抹掉读数与基准，事后无法追溯换表真伪」 | ✔ 合理补全（契约层无该引脚，属规格自洽缺口，已在 §7.2 登记） |

### 2.2 七项红线

零全局变量 ✔｜零物理地址 ✔｜纯 IEC ✔｜防御性 —（无执行体）｜双语同行注释 ✔｜ENUM+CASE —（契约件）｜定时器实例 —（无）。

### 2.3 历史范式

R33 ✔｜「枚举唯一属主」（§7.2-1）✔｜契约三段式与 `I_DL_TowerLight` / `I_DL_Cylinder` 同构 ✔。

### 2.4 终审判定

**PASS，v1.0.0 不改。** 两处与规格文本的差异（11 vs 12、`bLatched` 无属性）均属**规格文本自身的自洽缺口**，实现取「按表体 + 显式留档」是正确处置，不判缺陷。

---

## 3 A3 ｜ `FB_DL_ModbusPowerMeter`（v1.0.1，缺陷 3 条，PASS）

### 3.1 规格逐项对照（ROUND_PLAN §3.1 A3）

**引脚**：VAR_INPUT 26 条（规格表 24 行 + 2 条补引脚）、VAR_OUTPUT 12 条 + PROPERTY 12 条（输出侧合计覆盖规格 18 个量）。规格表 24 条输入逐条在位；两条补引脚均由规格自身漏洞倒逼（`fLightLoadRatio` 需要额定电流基准、015A 需要表值来源），头注释「规格偏离 ①②」逐条说明并给了域与非法值处理路径 —— **合理偏离，采纳**。

**状态机**：

| 枚举值 | CASE 标签 | 迁移 | 判定 |
|---|---|---|---|
| eIdle 0 | ✔ | →eSampling（bEnable 且标定合法）/ →eFault（已有锁存） | ✔ |
| eSampling 10 | ✔ | →eFault / →eIdle（掉使能）/ →eDegraded（越规不改可信度） | ✔ |
| eDegraded 20 | ✔ | →eFault / →eIdle / →eSampling（恢复正常拍） | ✔（修复 A3-D1 后往返可达） |
| eFault 99 | ✔ | →eIdle（复位沿且原因消失：`_bExitFault AND NOT _bCalBad AND NOT _bStale`） | ✔ |
| ELSE | ✔ | 0319 + 锁存 + 终态 | ✔ R31 兜底 |

**码位表**：12 个码逐值逐义与规格一致（实扫 `16#0003_0156~015B / 0316~031B`，无越界、无自造、无跨文件重叠）。

**验收向量**：

| 向量 | 规格期望 | 实现路径 | 判定 |
|---|---|---|---|
| V1 基本换算 | 2200 LSB→220.0 V、1000 LSB→10.0 A、50000 LSB→50.0 kW | 段 5 `UINT_TO_REAL(raw) * 标定`；`DINT_TO_REAL(iActivePowerRaw) * 0.001` | ✔ |
| V2 需量 | 15 min 窗、50 kW 恒定 → avg=peak=50 | 段 4 `fbDemandWatch`（PT=窗长）+ 段 9 算术平均 + 峰值取大 | ✔（口径为「窗内拍算术平均」，等扫描周期下与时间加权等价，已在头注释「段序」外补充说明） |
| V3 跨相时序 | 全零 4 s 仍 eDegraded、5 s 转 eFault+0317、恢复必须 bReset | `_bAllZero`→`fbStaleWatch`（5 s）→0317 锁存；掉零立刻经欠压判 `_bDegradedNow` → eDegraded；故障退出需 `_bExitFault` + 原因消失 | ✔ |
| V4 首拍 | fEnergyImport=0、bValid=FALSE、eHealth=eUnknown、首拍只装基准不判回退 | 段 2 `_bEnergyBase:=FALSE`；段 9 仅装基准；`_bEverValid=FALSE` → eHealth=eUnknown；全零首拍 `_bValidInt=FALSE` | ✔（上电寄存器非零的极端工况下首拍即出 eOk，属 R19「只装基准不做判据」的合法边界，见 §7.4-O4） |
| V5 域外 | fKwhPerLsb=0 → 0316 锁存、电能保持上次值且在有效域内 | 标定闸门兜底 + `_bCalBad` 锁存；段 9 在 eFault 不推进；属性出口 `IF acc<0 THEN 0` | ✔ |

### 3.2 七项红线

| 红线 | 结论 |
|---|---|
| 零全局变量引用 | ✔ 无 GVL / VAR_EXTERNAL（机检 banned_hits 0） |
| 零物理地址 | ✔ 无 %I/%Q/%M |
| 纯 IEC 61131-3 | ✔ 仅 Standard.library（R_TRIG/TON/SQRT/LIMIT/SHL/OR）；显式类型转换 8 处全部写明舍入/扩位意图 |
| 防除零/越界/浮点容差 | ✔ 除零 3 处（`_fPf := _fP/_fS` 前判 `_fS>EPS`、`_fDemandAvg` 前判 `_nWinCount>0`、`_fUnbalance` 前判 `_fVoltAvg>EPS`）；数组 3 处 `LOWER_BOUND/UPPER_BOUND` 夹持；浮点全用区间判（NaN 双侧为假即判非法），无 `=` 判等 |
| 变量同行双语注释 | ✔ 26 入 + 12 出 + 95 内部 + 22 常量，全部声明行双语同行注释 |
| 状态机 ENUM+CASE+ELSE | ✔ 5 标签（4 成员 + ELSE） |
| 定时器无条件刷新 | ✔ 段 4 顶层调用 3 个实例（`fbTrigReset`/`fbStaleWatch`/`fbDemandWatch`），断输入拍一律**在实例调用之后**自清（R24 正解） |

### 3.3 历史范式逐条

| 范式 | 结论与证据 |
|---|---|
| R19 首扫（`NOT _bInit`） | ✔ 段 2 `IF NOT _bInit THEN`，只装基准（累计/窗口/锁存/字序基准），不做判据 |
| R24 单拍自清时序 | ✔ `_bStaleWatchBreak` / `_bDemandWatchBreak` 均在对应 TON 调用**之后**自清；置位点全在段 3/7/8/9，即下一拍断输入一拍 |
| R25 单拍标志三律 | ✔ `_bResetPulse`（预清段 1 / 置位段 7 / 消费段 7、8）、`_bExitFault`（预清段 1 / 置位段 7 / 消费段 8）、`_bCode01xx`（预清段 1 / 置位段 3~6 / 消费段 12）—— 头注释「单拍标志清单」逐条登记 |
| R31 枚举→CASE 完备 | ✔ 每成员一标签 + ELSE 只接脏值；枚举来自接口文件，无第二份定义 |
| R32 内部状态量写入点排序 | ✔ `_ePhase` 只在段 8 CASE 内写（4 个标签各一处 + ELSE）；无 CASE 外状态赋值 |
| R33 枚举 `:=` | ✔（枚举在 A2 文件，本件只引用） |
| R34 状态量只置必销 | ✔ 见 A3-D1（本轮唯一违例，已修） |
| R35 守卫与封顶同向 | ✔ `fVoltTolRatio` 钳 0~0.5 / 判据 `>` `<` 对称；`fPfLimit` 钳 0.5~1.0 / 判据 `ABS(PF) <`；`fThdLimit` 钳 1~50 / 判据 `>`；窗口钳 ≥1 s / 除数守卫 `> 0` |
| R36 跨件跟踪首拍 | 不适用（不消费下层 PID/积分量） |
| R37 定长串 | 不适用（无 STRING 写回） |
| R38 锁存副本 vs 实时镜像 | ✔ 无 `*Latched` 与实时量并存；`_eOrderPrev` 为变化检测唯一消费点（段 3），全文参考文献计数 3 次（含声明），符合「须能指出唯一消费点」 |
| R39 CASE 前置不得改状态 | ✔ 段 7 复位通道置于 CASE 之前且**只清与状态无关量**（锁存/窗口/峰值/基准/断输入拍），状态迁移全部收敛在段 8；`_bExitFault` 是唯一出口凭据，且在段 7 内显式判 `_ePhase = eFault` 才置位 |
| R40 分段定时器断输入 | ✔ `fbStaleWatch`/`fbDemandWatch` 的 IN 均串 `NOT _bXxxBreak`；断输入点登记于头注释「定时器清单」（进采样、复位、窗口结算、字序变更） |

### 3.4 逻辑深查（总监点名的 4 项）

1. **32 位电能拼装单调性/回绕**：四种字序按「高字在前 / 低字在前 / 字节内序不改字间排布」三支处理，`SHL(...)+OR` 无符号扩位；单调性由「大于才递推、小幅回退保持、大幅回退判换表并重载基准」三段实现；回绕（UDINT 16#FFFF_FFFF→0）在可观测信息上与换表不可区分，本件按换表路径处理（重载基准 + `uMeterSwapCount` + 0318 维护码），**已在头注释新增「分层声明 ⑤」留档**（A3-D3）。V4 的「首拍不判回退」由 `_bEnergyBase` 保证。
2. **功率因数复算交叉校验**：`_fPf := _fP/_fS`（含符号）后 `LIMIT(-1,·,1)`；表值仅在 `iPfRaw ≠ 0` 时可用（0 视为表未提供，不误报）；轻载不判；偏差 > 3% → 015A + `_bPfMismatch`。**修复前 `_bPfMismatch` 无清零点**，一次越差即永久降级（A3-D1）。
3. **`uDiagCode` 单一优先级链**：全文 `_uDiagCode` 仅在段 12 赋值一次，链序 F（`_uErrFault`）→ M（0318）→ 015A → 015B → 0159 → 0157 → 0158 → 0156 → 0；`uErrorId` 仅出口 `_uErrFault`，信息码不进（R21）。0318 落故障带但按裁定不置 `bError`（头注释「码位级裁定」段与 A5 的 0323 同源）。
4. **`bError` 派生**：仅 `_bFaultLatch`（0316/0317/031A/031B 四码）驱动；0318 走 `_bMaintLatch` 独立通道，`CmdAck` 可清、`CmdReset` 亦可清。

### 3.5 缺陷与修复

| 编号 | 级别 | 缺陷 | 根因 | 修复 | 影响面 |
|---|---|---|---|---|---|
| A3-D1 | 中等 | `_bPfMismatch` 全文只有 `:= TRUE`，无预清零/复位点；一旦 015A 触发，`_bDegradedNow` 恒真，`eDegraded→eSampling` 永不发生，且 015A 成为持续码 | 把「每拍判据」误当「锁存量」，违 R34 状态量生命周期四律与 R44「信息码按窗清」 | 段 1 增 `_bPfMismatch := FALSE;`（与 `_bContra` 同组，附双语注释） | 语义方向修正，不改码位、不改引脚 |
| A3-D2 | 中等 | 段 9 语句内直写 `E_DL_ByteOrder.eAbcd` / `.eCdab` → 子集机检 `undefined_identifier` FAIL 2；且与库内既有 `FB_DL_EnergyMeterAccum.eOrderAbcd` 范式不一致（枚举成员语义散落在语句段） | 跨文件枚举在「声明区外」被引用 | 新增两个声明区比较基准 `_eOrderAbcd` / `_eOrderCdab`，段 9 改为 `IF eWordOrder = _eOrderAbcd`；头注释新增「比较基准清单」段 | 零语义变化，机检转 PASS |
| A3-D3 | 提示 | 回绕处理未留档 | 头注释缺边界声明 | 「分层声明」新增 ⑤ | 纯文档 |

### 3.6 终审判定

**PASS，升 v1.0.1。** 缺陷 2 条已修（1 条为语义级、1 条为机检级），1 条留档；接口实现（12 属性 + 3 方法）逐字对齐 A2 契约，三平台语法无专有依赖。

---

## 4 A4 ｜ `FB_DL_ValveStictionDetect`（v1.0.1，缺陷 2 条，PASS）

### 4.1 规格逐项对照（ROUND_PLAN §3.1 A4）

- **引脚**：13 入 + 11 出，逐条在位、类型与默认值一致（`bPosValid` 默认 TRUE、`tStallTime` 2 s、`tReverseTime` 1 s、`nMinSamples` 30）。
- **枚举**：`E_DL_StictionLevel`（4 值）、`E_DL_StictionPhase`（6 值）同文件发布、`:=` 分隔、双语注释。
- **状态机**：6 成员 → 6 个 CASE 标签 + ELSE（031F）+ 兜底锁存，逐条与规格一致（`eCollect→eAnalyze→eVerdict→eCollect`、`eSuspend` 由 `bPosValid=FALSE` 进入、任何态→`eFault`）。
- **码位**：`015C/015D/015E/031D/031E/031F` 六码逐义一致，无越界。
- **等级→健康映射**：`eNone→eOk`；`eSlight/eModerate→eMaintenanceReq`；`eSevere→eOutOfSpec`；故障仅来自参数非法/非有限 → `eFailure`。与规格一致，且「黏滞是退化不是失效」的裁定写进头注释。

**验收向量**：

| 向量 | 规格期望 | 实现 | 判定 |
|---|---|---|---|
| V1 正常阀 | eNone、黏滞带≈0.3、停滞 0 | eNone ✔、停滞 0 ✔；黏滞带在**全行程单向斜坡**下为 0（见 A4-D2） | △ 部分达成（保守方向） |
| V2 黏滞阀 | 三判据全成立 → eSevere、停滞≥2、eOutOfSpec | 三条判据分别有独立实现与并发封顶逻辑；但 PV 阶梯 3% 的滞后样本 < `fDeadbandMax` 5% → 等级封顶 eModerate（默认阈值下 eSevere 需要 ≥5% 滞后带） | △ 规格向量与默认阈值不自洽（§7.1-E4） |
| V3 跨相复验 | 判定拍 bPosValid=FALSE → 不发布新等级 + 015D | 段 10 `_bCurValid := bPosValid`；`IF NOT _bCurValid THEN 015D`（等级/黏滞带均不动） | ✔ R42 正解 |
| V4 恢复首拍 | 挂起恢复样本从 0 重建、首拍不判 Severe | `eSuspend→eCollect` 清 `_nSampleCount/_fDbSum/_nDbCount/_bHaveRev` 并置 `_bRebuildWin`（首窗不发布，比规格更严），015C 提示 | ✔ 采纳（超规格） |
| V5 域外 | fCmd=NaN → 031D、黏滞带保持且夹 0~100 | 段 5 区间判有限性 → 段 6 `031D` 锁存；段 11 `LIMIT(0, _fDbHeld, 100)` | ✔ |

### 4.2 七项红线

零全局/零地址/纯 IEC ✔｜除零：`_fDbSum/_nDbCount`（前判 `>0`）、`fDeadbandEst/DL_REAL_MAX`（除数恒 100）、采样周期除 `_nMinUse`（钳 ≥5）✔｜数组：缓冲落位前 `LOWER_BOUND/UPPER_BOUND` + 计数闸门，`FOR 1..128` 内二次夹持 ✔｜浮点容差：方向判定用 `> DL_EPS`，无 `=` 判等 ✔｜双语同行注释 ✔（13 入 + 11 出 + 74 内部 + 16 常量）｜ENUM+CASE+ELSE ✔｜4 个 TON + 1 个 R_TRIG 全部段 4 顶层无条件调用 ✔。

### 4.3 历史范式逐条（重点 R38/R40/R41/R42/R43）

| 范式 | 证据 |
|---|---|
| R38 锁存副本 | `_bPosValidSnap` 在窗口关闭拍取快照，**唯一消费点**＝段 9 窗口合法性闸门；窗口内 OP/PV 一律取 `_afOpWin/_afPvWin`，分析相**不读实时 `fPos`**。实时 `bPosValid` 三处消费点（段 4 定时器输入 / 段 7 挂起迁移 / 段 10 本拍复验）均不含边界量含义。头注释「镜像量清单」逐点登记 ✔ |
| R40 分段定时器 | 5 个实例的 IN 均串 `NOT _bXxxBreak`；断输入点在段 7/8/10 段边界置位、段 4 调用后自清。停滞定时器事件后立即置 `_bStallBreak`，防同一停滞重复计次 ✔ |
| R41 恢复不重头 | `eSuspend→eCollect` 四项统计全部清零、基准重装、`_bRebuildWin=TRUE`（首窗只重建不发布）；复位亦置 `_bRebuildWin` ✔ |
| R42 跨相取值本拍复验 | 段 10 第 1 行 `_bCurValid := bPosValid`，与发布同拍；不满足则只出 015D ✔ |
| R43 保持值夹域 | `fDeadbandEst` 0~100、`fHysteresisRatio` 0~1（除全行程 100）、`fDeadbandEst`/`_fCandDb` 双处钳位；冷启动首拍 eLevel=eNone/fDbHeld=0 落在域内 ✔ |
| R34/R25 | `_uStallCount` 只增（`16#FFFF_FFFF` 上溢守卫）、复位清；`_bStallEvent`/`_bRevEvent` 预清段 1 / 置位段 4 / 消费段 8 |
| R27 保持语义 | `_eLevel/_fDbHeld/_uStallCount/_bSuspectHeld` 由段 11 每拍重写出口，复位为唯一清除通道 ✔ |
| R39 停机分支不屏蔽复位 | 段 6 复位通道在 CASE 之前且不改状态；掉使能分支一律写在 CASE 标签内 ✔ |

### 4.4 逻辑深查（三判据并发、停滞拍计数自清）

1. **并发升级**：等级先由判据 (a) 滞band 定档，再要求「Moderate 及以上必须有停滞或反转证据」，否则封顶 eSlight —— 实现的是「(b)(c) 为必要佐证、(a) 为充分条件」的合取式，与规格「缺一不升级」方向一致（**不会因单点指标越限而判重度**）。
2. **停滞拍计数**：`fbStallWatch` 触发 → `_bStallEvent` 单拍 → 段 8 计数 + 置证据 + `_bSinceBreak` 重启计时；事件后立刻 `_bStallBreak` 重启定时器，同一停滞不重复计次 ✔（自清路径唯一）。
3. **反转确认**：`_bRevPending` 由方向反转置位、由「阀位已动」或定时器到期清除，两条清除路径互斥且都当场消费 ✔。

### 4.5 缺陷与修复

| 编号 | 级别 | 缺陷 | 修复 |
|---|---|---|---|
| A4-D1 | 提示 | `fbSinceWatch(PT := T#24H)` 为裸时间字面量，违「无魔法数」 | 新增常量 `DL_SINCE_MAX : TIME := T#24H`（含双语注释），调用处改用常量 |
| A4-D2 | 中等（判断项） | 判据 (a) 只在准静态反转点取样本；全行程单向斜坡反转点 OP 差 ≫ `fDeadbandMax`，不出样本 → 黏滞带恒 0、等级恒 eNone | **裁定保留**：任何「同 OP 差分」在持续运动上都会把纯跟随滞后误算成黏滞（0.3% 滞 later 产 0.6% 假黏滞带），文献明确该法只在准静态可信；故现实现的保守盲区**优于**盲目补一条会误报的采样路径。已在头注释「边界声明 ⑤」写死语义、理由与替代做法 |

### 4.6 终审判定

**PASS，升 v1.0.1。** 一条确定性红线违例（魔法数）已修；A4-D2 作为「保守方向的设计取舍」留档，不判缺陷、不进 FAIL。R38/R40/R41/R42/R43 五个高危范式全部为**正解写法**，是本泳道范式的样板件。

---

## 5 A5 ｜ `FB_DL_AhuDamperStuckDiag`（v1.0.1，缺陷 1 条，PASS）

### 5.1 规格逐项对照（ROUND_PLAN §3.1 A5）

- **引脚**：15 入 + 11 出，逐条在位一致（`tTravelNominal` 30 s、`fTolPos` 3.0、`fDevLimit` 10.0、`tDevDelay` 10 s、`fDriftThr` 0.2、`tStallTime` 5 s、`tIoFaultTime` 3 s、`fSlowRatio` 1.5）。
- **三分类**：`eFullStall`（指令已动、位移 < 阈值持续 `tStallTime`）/ `eTransitStall`（已离位未达目标，超 `tTravelNominal×fSlowRatio` + 宽限）/ `eIoFault`（反馈失效超 `tIoFaultTime`）—— 三类判据各有独立证据量与确认窗。
- **两工艺级**：`eDeviation`（稳态偏差 > 限值持续 `tDevDelay`，0323 不置 bError）/ `eSlow`（到位但超倍率，0161）。
- **状态机**：5 成员 5 标签 + ELSE（0325），`eMoving` 进出必断行程定时器，`eVerdict` 单拍后回 `eIdle` 且结论保持。
- **码位**：`0160/0161/0321/0322/0323/0324/0325` 七码逐义一致；0323 的「故障带码 + 不置 bError」裁定在头注释「码位级裁定」段显式写死并给出理由（仍能调节 ≠ 不可继续运行）。
- **验收向量**：V1 Full Stall（5 s → eFullStall/0321/eFailure/bError=TRUE）✔；V2 Transit Stall（45 s 判据点 + `tStallTime` 宽限后才定性，头注释偏离 ① 说明为何不在 45 s 当拍判死）✔；V3 连续两次 20 s 行程不累加 40 s（进移动态 `_bTravelBreak` 置位、段 4 调用后自清，宽限与行程共用断输入拍且自清放在**两个实例调用之后**）✔；V4 反馈恢复首拍只重装基准、不判 Full Stall ✔；V5 fCmd=120% 钳位并置 0161、fPosFb=NaN 走反馈失效路径且偏差夹 −100~100 ✔。

### 5.2 七项红线

零全局/零地址/纯 IEC ✔｜除零：全文无除法（限值全为乘加与比较）✔｜数组：无数组 ✔｜浮点：`ABS(a-b) > eps` 与区间判（`fCmd`/`fPosFb` 的有限性用 `>= -LIM && <= LIM`）✔｜双语同行注释 ✔（15 入 + 11 出 + 58 内部 + 13 常量）｜ENUM+CASE+ELSE ✔（两套枚举各自 5 标签/6 标签无 CASE 需求，`E_DL_DamperDiag` 由码位链全覆盖）｜6 个 TON + 2 个 R_TRIG 全部段 4 顶层无条件调用 ✔。

### 5.3 历史范式逐条

| 范式 | 证据 |
|---|---|
| R19 | 段 2 `IF NOT _bInit` 只装基准（状态/结论/计数/基准/上拍值），不做判据 |
| R24/R25 | `_bResetPulse`（预清段 1 / 置位段 5 / 消费段 5）、`_bVerdictPending`（预清段 1 / 置位段 6 / 消费段 7）、`_bFbRestore`（预清段 1 / 置位段 4 / 消费段 6）；六个断输入标志就地置位、段 4 调用后自清 |
| R27 | `_eDiag/_fDevHeld/_tTravelHeld/_uStallCount/_uTravelCount` 五个保持量段 8 每拍重写；结论在 `eVerdict` 产生后一直保持 |
| R31 | 5 个状态成员各一标签 + ELSE 接脏值；6 个结论成员在段 9 码位链全值可达（`eFullStall/eTransitStall/eIoFault` 经 `_bFaultLatch` 首出码、`eDeviation` 独立支、`eSlow`+超域合支、`eOk` 兜底） |
| R32 | `_eState` 只在段 6 CASE 内写；段 5 复位通道零状态写 |
| R35 | `fSlowRatio` 钳 1.1~3.0 且越域判 0325、判据 `>=`；`fTolPos` 钳 0.5~10 且判据 `<=`；`fDevLimit` 钳 1~50 且判据 `>`；`fDriftThr` 钳 0.05~2 且判据 `>` |
| R39 | 段 5 复位 + 参数锁存均在 CASE 之前且不改状态；掉使能分支写在 CASE 标签内 |
| R40 | `fbTravelWatch` / `fbGraceWatch` 共用 `_bTravelBreak`，**自清语句放在两个实例调用之后**（头注释专门写了这一陷阱），是本轮 R40 最高危点的正解；`fbStallWatch/fbDevWatch/fbSettleWatch/fbIoWatch` 各自串 `NOT _bXxxBreak` |
| R41 | `_bFbRestore` 首拍重装 `_fCmdBase/_fPosBase`、清证据、清超时、重启三个定时器，**不判任何卡滞** |
| R43 | `fDeviation` 夹 −100~100；`bAtOpen/bAtClose` 含容差与限位或判 |

### 5.4 逻辑深查（三分类判据带确认窗）

**本轮唯一缺陷在此暴露**：`eSettling` 的 `fbDevWatch`/`fbSettleWatch` 的 IN 不含反馈有效性门（这是对的——偏差与到位判据应在反馈有效时才有意义，但它们不以 `_bFbOk` 为输入，因此反馈中途失效仍会到期）。原实现在判定相用 `IF NOT _bFbOk` 直接出 `eIoFault` + 0324 锁存，等于**只要判定拍反馈恰好无效就判 I/O 失效**，绕开了 `tIoFaultTime`（默认 3 s）的确认窗 —— 与 T2-6「每告警带确认延时」的结构借用直接冲突，且会把「瞬时断线」升级成不可继续运行的失效。

修复：判定相改为 `IF fbIoWatch.Q`（必须满确认窗）→ `ELSIF NOT _bFbOk` 时不发布任何结论（保持上次值，由 `fbIoWatch` 计时满后再定性）。修复后三分类各自满足：Full Stall = `tStallTime`、Transit Stall = 倍率 + 宽限、I/O Fault = `tIoFaultTime`。

### 5.5 缺陷与修复

| 编号 | 级别 | 缺陷 | 修复 |
|---|---|---|---|
| A5-D1 | 中等 | 判定相 `IF NOT _bFbOk` 绕过 `tIoFaultTime` 确认窗直接锁存 0324；触发路径为 `eSettling` 的 `fbSettleWatch.Q`/`fbDevWatch.Q`（其 IN 不以反馈有效性为输入） | 改为 `IF fbIoWatch.Q`；新增 `ELSIF NOT _bFbOk` 空分支（**注释-only，无孤立分号**）承担「本拍不发布结论」；段 7 末尾消费注释同步改写。码位/引脚零变化 |

### 5.6 终审判定

**PASS，升 v1.0.1。** 三分类判据的确认窗在修复后完整闭合；R40 双实例共用断输入拍的自清位置是本轮最值得复用的写法（已记入 §8 沉淀）。

---

## 6 A6 ｜ `FB_DL_PumpCavitationGuard`（v1.0.1，缺陷 5 条，PASS）

### 6.1 规格逐项对照（ROUND_PLAN §3.1 A6）

- **引脚**：17 入 + 12 出，逐条在位（`fFlowLowRatio` 0.60、`fHeadDropRatio` 0.15、`fVibLimit` 4.5、`fCurrentRippleLimit` 0.15、`tRippleWindow` 2 s、`tConfirm` 3 s、`tHoldOff` 30 s、`fDerateStep` 0.10）。
- **三判据**：流量偏低 + 扬程跌落 + （振动超限 **或** 电流波动超限），同拍成立并持续 `tConfirm` 才确认；单条只到嫌疑（0164，不锁存）。
- **降速语义**：只输出 `fDerateRatio` / `bDerateRequest`，不写变频器频率；每次确认 −1 步、下限 0.3、不自动回升（回升交上层斜坡）。
- **状态机**：6 成员 6 标签 + ELSE（0329），`eIdle→eMonitor→eSuspect→eConfirm→eDerate`，`eDerate` 窗满回 `eMonitor`，任何态→`eFault`。
- **码位**：`0164/0165/0326/0327/0328/0329` 六码逐义一致。
- **验收向量**：V1 单判据（流量 0.5 倍额定）→ eSuspect + 0164、不锁存 ✔（但默认 `fHeadDropRatio`=0.15 下扬程 0.8 倍额定也会成立 → 规格向量与默认阈值不自洽，头注释偏离 ① 已裁定「不改判据语义以迁就向量」）；V2 三判据持续 3 s → 0326、比率每次 −0.10、下限 0.3 ✔；V3 确认定时器在嫌疑↔监视来回时断输入 ✔；V4 复位不直接回 1.0、夹 0.3~1.0 ✔（回升一步的折中已在偏离 ③ 留档）；V5 额定流量 0 → 0328 且 `fFlowRatio` 输出 0 —— **修复前不成立**（见 A6-D2）。

### 6.2 七项红线

零全局/零地址/纯 IEC ✔｜除零：三处比值前判分母（`_fFlowNomUse`/`_fHeadNomUse`/`_fVibUse` > EPS），波动率前判均值 > EPS，且样本数 > 0 ✔｜数组：无 ✔｜浮点：全比较式，无 `=` 判等 ✔｜双语同行注释 ✔（17 入 + 12 出 + 49 内部 + 13 常量）｜ENUM+CASE+ELSE ✔｜3 个 TON + 1 个 R_TRIG 全部段 4 顶层无条件调用 ✔。

### 6.3 历史范式逐条

| 范式 | 证据 |
|---|---|
| R19 | 段 2 只装基准（相位/锁存/比率 1.0/计数/波动窗四项） |
| R24/R25 | `_bResetPulse`（预清段 1 / 置位段 6 / 消费段 6）、`_bDerateStep`（预清段 1 / 置位段 8 / 消费段 8）、`_bConfirmEvent`（预清段 1 / 置位段 7 / 消费段 8）；三个断输入标志就地置位、调用后自清 |
| R27 | `bDerateRequest`/`fDerateRatio`/`bCavitation`/`nEventCount` 段 9 每拍重写；降速请求在 `eDerate` 与故障态内保持 |
| R31 | 6 成员 6 标签 + ELSE；`E_DL_CavitationState` 被 CASE 选择子使用，覆盖完备 |
| R34 | `_uEventCount` 只增（上溢守卫）、复位清；`_fDerateRatio` 单点递减、单点回升 |
| R35 | `fFlowLowRatio` 钳 0.2~0.95 / 判据 `<`；`fHeadDropRatio` 钳 0.05~0.5 / 判据 `(1-r) >`；`fVibLimit` 钳 1~20 / 判据比值 `>1`、急停 `>2`，**振动比值上限 5.0 高于急停倍率 2（同向）**；`fDerateStep` 钳 0.02~0.3 / 递减后与 0.3 取大 |
| R39 | 段 6 复位 + 参数锁存均在 CASE 前且零状态写 |
| R40 | `fbConfirmWatch` 的 IN 串 `NOT _bConfirmBreak` 且含 `state=eSuspect`；`fbRippleWatch`/`fbHoldOffWatch` 各自断输入；三处断输入点在段 6/7/8 置位、段 4 调用后自清 |
| R41 | 复位后比率只回升一步、不重头；停泵/重启时四项统计清零，**本轮补清 `_fRipple`**（A6-D5） |
| R43 | `fDerateRatio` 出口夹 0.3~1.0；`fFlowRatio/fHeadRatio` 夹 0~2；`fVibRatio` 夹 0~5；`fRippleMeas` 夹 0~10 |

### 6.4 逻辑深查（判据时序）

1. **确认定时器一拍滞后**：`_bAllThree` 在段 5 才算，而定时器在段 4 调用 → 读到上一拍照的判据值。头注释「拍间依赖」段显式登记该设计取舍（3 s 量级判据上一拍滞后无实质影响，换取「所有实例同段无条件调用」的强纪律）—— **采纳，不判缺陷**。
2. **抑制窗语义**：原 `_bHoldActive := fbHoldOffWatch.Q` 取的是「窗满那一拍」，导致 ①窗内判据并未真被抑制（只是状态机不看它），②`0165` 只在一瞬间可见。修复为「整个 `eDerate` 相 + 窗满拍」。
3. **降速执行与保持**：`eConfirm` 当拍 `_bConfirmEvent` → 段 8 锁存 + 计次 + 降一步；`eDerate` 内每拍重写 `_bDerateHeld=TRUE`；窗满撤请求回监视，判据仍成立则再次进嫌疑并再降一步 —— 闭环正确，无双写冲突。

### 6.5 缺陷与修复

| 编号 | 级别 | 缺陷 | 根因 | 修复 |
|---|---|---|---|---|
| A6-D1 | 中等 | `_bHoldActive` 仅等于 `fbHoldOffWatch.Q` → 0165 只在抑制窗到期那一拍可见，窗内 4 条判据实际仍在计算（`NOT _bHoldActive` 恒真） | 把「窗满」误当「窗内」 | 改为 `(_eState = eDerate) OR fbHoldOffWatch.Q`，附双语注释说明「抑制生效＝整个降速相」 |
| A6-D2 | 中等（V5 直接违例） | 比值门用 `_fFlowNomUse > DL_EPS`，而 `_fFlowNomUse` 在额定非正时已被兜底成 1.0 → 恒进第一支，输出 `fFlow/1.0` 的伪比值（V5 要求 0）；`fHead` 同病 | 兜底值污染判据门 | 比值门改用**原始额定值** `fFlowNominal/fHeadNominal > DL_EPS`，兜底值只保留为除零守卫 |
| A6-D3 | 中等（R21） | 汽蚀确认置 `bError`（含 `_bCavLatch`）但 `_uErrFault` 从未写 0326 → `uErrorId=0` 与 `bError=TRUE` 并存 | 0326 只走了码位链，未进首出码寄存器 | `_bConfirmEvent` 分支内、`NOT _bFaultLatch` 时写 `_uErrFault := 16#0003_0326`（保首出、不覆盖更高优先级的 0327/0328） |
| A6-D4 | 提示 | 急停级 0327 不受 `bRunning/bEnable` 抑制，停泵时邻近设备振动/传感器卡值可致误锁存 | 判据门只加在四条常规判据上 | 加 `bRunning AND bEnable` 门，与「停泵全部判据抑制」同纪律；降速抑制窗内仍照判（等级高于判据） |
| A6-D5 | 提示 | 停泵分支清四项统计但不清 `_fRipple` → 旧波动率可跨停机存活到重启首窗 | 清理点漏项 | 停泵分支补 `_fRipple := 0.0` |

### 6.6 终审判定

**PASS，升 v1.0.1。** 五项修复中三项（A6-D1/D2/D3）属「文本全绿、语义出错」家族，机检无法捕获，只能靠逐拍推演 —— 与本轮 R13 新增机检规则的定位一致。

---

## 7 跨文件一致性与规格侧裁定

### 7.1 跨文件一致性（逐条核对）

| 检查项 | 结论 |
|---|---|
| `E_DL_Ne107Status` 唯一属主 | ✔ 全库仅 `I_DL_DeviceHealth.st:91` 一处 `TYPE`；A2 只引用，A3/A4/A5/A6 只用作引脚类型与赋值源 |
| 枚举分隔符 `:=` | ✔ 本轮 6 个枚举（Ne107/PMState/StictionLevel/StictionPhase/DamperDiag/DamperState/CavitationState）全部 `:=` + 双语 |
| FB 属性与接口逐字对齐 | ✔ A3 的 12 个 PROPERTY 与 `I_DL_PowerMeter` 的 12 条类型逐字一致（`LREAL` 两处、`STRING` 无、`E_DL_Ne107Status` 一处）；3 个方法签名一致 |
| 状态枚举复用而非重造 | ✔ A3 复用 `E_DL_PowerMeterState`（规格正文曾写 `E_DL_PowerMeterPhase`，已在 A3 偏离 ③ 与 A2 偏离 ② 双向留档，避免同构双枚举） |
| 码位跨文件重叠 | ✔ 本轮 30 个码位在全库（排除本 4 件）实扫 **0 命中** |
| 与既有件分层 | ✔ A3 头注释写明与 `FB_DL_EnergyMeterAccum`（NE43）的分层：口径可沿用、码位严禁复制；本件未引用其类型 |
| 依赖方向 | ✔ 四件仅依赖 `Standard.library` + `E_DL_ByteOrder`（DL_MathData 低层）+ `E_DL_Ne107Status`（同层 A1 契约），无 DL_Process 反向依赖 |

### 7.2 规格侧裁定（1 条）

**A2「属性段（11 条）」与表体 12 行矛盾** → 裁定按**表体 12 条**实现（表体是引脚级契约，表头是笔误），实现方已在头注释留档；建议下轮在规格书修正为「12 条」。同类：A2 方法表引用 `bLatched` 但属性表未暴露该属性 → 裁定「实现块内部以 `bError` 等价」，已在 A2/A3 两处留档。

### 7.3 观察项（不判缺陷，下轮并入）

| 编号 | 件 | 观察 | 建议 |
|---|---|---|---|
| O1 | A3 | 需量平均为「窗内拍算术平均」，非时间加权；等扫描周期下等价，抖动大时偏差 | R14 若做需量件，加时间加权口径开关 |
| O2 | A3 | 0318（换表）同时清 `fDemandPeak`，规格只说「仅复位可清」 | 语义可接受（CmdResetEnergy 即需量复位），MANUAL 注明 |
| O3 | A4 | `tSinceLastStall` 由 TON 封顶 24 h，超过即饱和 | MANUAL 注明「饱和值 24 h」 |
| O4 | A3 | 上电首拍若寄存器非零，`bValid` 首拍即 TRUE（R19 只要求「只装基准不判回退」，未要求首拍无效） | 与 V4 的「全零上电」成立域一致，已在报告留痕 |

### 7.4 条件项（移交，非本泳道写权限）

1. **R13 规格勘误 3 条**须由总监在 `ROUND_PLAN_R13.md` 侧回写：A2 属性 11→12；A4 V2 的「3% 阶梯 → eSevere」与默认 `fDeadbandMax` 5% 不自洽；A6 V1 的「扬程 0.8 倍额定只成立流量判据」与默认 `fHeadDropRatio` 0.15 不自洽。
2. **MANUAL_DL_Device** 故障码表需为 0323 / 0318 两码增列「是否置 bError」列（A5/A3 头注释已要求）。
3. **编译验证仍为第 13 轮悬置项**：本泳道 4 件实现块未经三平台编译，仅完成机检 + 逐拍推演 + 关键字配平。风险清单：空 `ELSIF` 分支（A5）、`LOWER_BOUND/UPPER_BOUND` 在汇川 InoProShop 的可用性（A3/A4）、`STRING(16)` 属性在 TwinCAT 的接口实现一致性（A1/A2）。

---

## 8 本轮沉淀（供 R14 起沿用）

1. **「故障带码 + 不置 bError」需要一个配套的码位来源**：A3 的 0318 与 A5 的 0323 都按裁定不置 `bError`，但若同一件里还有「bError 为真」的类别（A6 的 0326 汽蚀确认），就必须把该码写进 `uErrorId`，否则出现「`bError=TRUE` 而 `uErrorId=0`」的自相矛盾态（A6-D3）。**新规则候选 R45：`bError` 的每一个置位源，必须能在 `uErrorId` 找到对应码（首出码或当前码）。**
2. **跨文件枚举的比较基准应声明在声明区**：语句段直写裸类型名会让「子集机检」误报，也让枚举语义散落。既有 `FB_DL_EnergyMeterAccum.eOrderAbcd` 已是正解，本轮 A3 补齐同范式。**新规则候选 R46：枚举比较一律对声明区基准量做，语句段禁裸类型名。**
3. **「窗满」与「窗内」是两个不同语义**：抑制/保持类标志若取定时器的 `Q`，拿到的永远只是「窗满那一拍」（A6-D1）。凡「某相内生效」的标志，必须是「相位表达式 OR 定时器 Q」。
4. **不以反馈有效性为输入的判据定时器**（A5 的 `fbDevWatch`/`fbSettleWatch`）在给结论时必须**本拍复验**反馈有效性，且复验不通过时**不得**用「另一类失效」去顶替结论（A5-D1）—— 那是「用一次瞬时断线否掉整段行程」的典型形态。
5. **兜底值只能当除数守卫，不能当判据门**（A6-D2）：一旦兜底值进入判据比较，就产生「永远成立的伪判据」与「伪比值输出」双面污染。

---

## 9 交付清单

| 文件 | 动作 | 版本 |
|---|---|---|
| `DL_Device\I_DL_DeviceHealth.st` | 终审通过，未改 | 1.0.0 |
| `DL_Device\I_DL_PowerMeter.st` | 终审通过，未改 | 1.0.0 |
| `DL_Device\FB_DL_ModbusPowerMeter.st` | 修复 2 处 + 留档 1 处 | 1.0.0 → 1.0.1 |
| `DL_Device\FB_DL_ValveStictionDetect.st` | 修复 1 处 + 留档 1 处 | 1.0.0 → 1.0.1 |
| `DL_Device\FB_DL_AhuDamperStuckDiag.st` | 修复 1 处 | 1.0.0 → 1.0.1 |
| `DL_Device\FB_DL_PumpCavitationGuard.st` | 修复 5 处 | 1.0.0 → 1.0.1 |
| `_Staging_Raw\2026-11-15\FINAL_REVIEW_R13_A.md` | 本报告 | — |

机检终态：`SUMMARY: files=6 fail=0 warn=0`（16 项规则全 PASS）。
