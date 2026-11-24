# GATE R81-B 编译闸席裁决书（一票否决）

- 轮次：R81 批 B ｜ 裁决人：dlf-compile-verifier（编译闸席）｜ 时间：2026-11-24
- 范围：4 件复杂 FB（C3/C4/C5）+ 1 件 A 批返修件（FC v1.0.1）复裁
- 工具链：L1 `_tools/dl_gate.py --file`（tree-sitter）；L2 `_tools/l2_check.py <file>`（RuSTy plc.exe，**串行 jobs=1**）
- 结论：**BLOCK**（2 件阻断：1 件编译阻断、1 件逻辑阻断；3 件放行并附挂账）

---

## ① 逐件裁决表

| # | 文件 | 裁决 | 错误码/缺陷级 | 一行理由 |
|---|---|---|---|---|
| 1 | `DL_Process/FB_DL_RotaryIndexerCycleSeq.st` | **FAIL** | E007（L2）、BLOCK | L237/L255/L291 用 `FOR … DOWNTO`，RuSTy 解析器只接受 `TO`，6 行最小复现即复现，非 IEC 61131-3 标准语法（IEC 仅 `TO`/`BY`），不能按"编译器不支持合法 IEC 语法"豁免 |
| 2 | `DL_Process/FB_DL_AsrsSlotAllocSeq.st` | **FAIL** | LOGIC（MAJOR→阻断） | `diReqSeq=0`（引脚默认值未写）时 `diAckSeq(=0)=_diOutSeq(=0)` 立即成立 → **零握手直接 bGrant 放行**，可编译但算错 |
| 3 | `DL_Process/FB_DL_FillPreactSelfLearn.st` | **PASS** | 挂账 2×MAJOR / 1×MINOR | 七态出口穷举、学习资产不被复位误清、学习律符号自证正确；缺陷为接口缺口（无 PREACT 回灌引脚）与 43 码同拍竞态，均非本轮阻断项 |
| 4 | `DL_Motion/FB_DL_MeasureInputLatch.st` | **PASS** | 挂账 3×MINOR | 五态出口穷举、tonArm 兜底齐备、三处边沿全 R_TRIG；仅出口/计数口径的 MINOR |
| 5 | `DL_Process/FC_DL_BeamToppleRiskChk.st`（v1.0.1 返修） | **PASS** | — | 修法正确：`1.0+ABS(offset)/depth` 消除符号依赖，域闸把系数封顶 1.5，未引入新阻断问题；2 条 MINOR 建议 |

L1/L2 计数：L1 5/5 PASS（BLOCK 0、MAJOR 0）；L2 4/5 PASS，1 FAIL（E007）。

---

## ② FAIL 的最小修法

### #1 FB_DL_RotaryIndexerCycleSeq —— E007 DOWNTO（3 处，逐行可照抄）

**依据**：`_tmp_r81/t_downto.st`（6 行，仅含 `FOR i := 3 DOWNTO 0 DO`）同样报 `E007 Unexpected token: expected KeywordTo but found DOWNTO` → 纯编译器限制，非上下文相关。库内已有 2 件同缺陷（`FC_DL_PolyEvalHorner`、`FB_DL_MarkPositionLatch` 本轮实测同样 E007），**不构成豁免先例**：IEC 61131-3 的 FOR 只有 `TO`/`BY`，`DOWNTO` 是 CODESYS/TwinCAT 系扩展，按裁决口径 4 不属于"合法 IEC 语法"。

改法用"镜像下标 + 升序"，遍历顺序与降序**逐拍等价**（已实测编译 PASS，见第 ④ 节验证批注）：

- L237（复位清寄位器，11→0 共 12 次）：
```pascal
        FOR _nIdx := DL_RIX_IDX_ZERO TO DL_RIX_ARR_MAX DO
            _aCupOk[DL_RIX_ARR_MAX - _nIdx] := FALSE;             // 寄位器全清（新批次起点）/ Cup register cleared, new batch origin
        END_FOR
```
- L255（移位 11→1，必须降序，否则低位被覆盖）：
```pascal
            FOR _nIdx := DL_RIX_IDX_ZERO TO (DL_RIX_ARR_MAX - DL_RIX_ONE) DO
                _aCupOk[DL_RIX_ARR_MAX - _nIdx] := _aCupOk[(DL_RIX_ARR_MAX - _nIdx) - DL_RIX_ONE];   // 第 n 工位承接第 n-1 工位的杯 / Station n inherits the cup of station n-1
            END_FOR
```
- L291（故障复位清寄位器）：
```pascal
            FOR _nIdx := DL_RIX_IDX_ZERO TO DL_RIX_ARR_MAX DO
                _aCupOk[DL_RIX_ARR_MAX - _nIdx] := FALSE;         // 复位：寄位器全清 / Reset: cup register cleared
            END_FOR
```
> 已用临时副本（`_tmp_r81/FB_DL_RotaryIndexerCycleSeq_fixprobe.st`，三处替换、其余零改动）实测 `PASS=1 FAIL=0`，证明 E007 是该件唯一 L2 阻断项，改写后无语义残留错误。**业务文件未改，由编码专家执行。**

另：L4 `码位 … （DL_Process 段内 21xx 子带首发，R83）` 轮次写错（应 R81），MINOR 挂账。

### #2 FB_DL_AsrsSlotAllocSeq —— 零握手假放行（阻断）

**缺陷**：`eValidate` 段（L204-207）无条件 `_diOutSeq := diReqSeq`，而 `eHandshake`（L211）以 `diAckSeq = _diOutSeq` 判回齐。`diReqSeq` 引脚默认值 0、`diAckSeq` 默认值 0，两者天然相等 → 首拍即 `eCommit`，`bGrant=TRUE`、`iAllocSlot=iReqSlot`，**对端未参与任何握手就放行**。同族二次缺陷：放行后 `_diOutSeq` 不复位，若上位复用同一序号再起请求，对端残留 ack 仍相等 → **同一序号二次放行**（R79 边沿纪律只防"同电平重触发"，防不住"陈旧 ack"）。

**修法 A（必需，3 行，eValidate 首因最前）** —— L197 `IF bSlotLocked THEN` 之前插入：
```pascal
        IF diReqSeq <= 0 THEN
            _iErrTmp   := 36;                                         // 故障级：请求序号非法（0 = 未初始化，禁止参与握手）/ Fault: illegal request sequence, 0 means uninitialised
            _bFaultReq := TRUE;                                       // 请求段 7 锁存 / Request the latch at segment 7
        ELSIF bSlotLocked THEN
```
（码表需补 `36 = 请求序号非法（≤0）` 一行；反证：该场景输出组合与"正常放行前拍"完全同形，必须独立成码。）

**修法 B（必需，3 行，防陈旧 ack 二次放行）**：
- L148 后新增一行声明：`_diAckAtPublish : DINT := 0;   // 下发时刻的对端 ack 快照，用于识别陈旧 ack / Snapshot of the peer ack taken at publish time`
- L205 发布处改为：
```pascal
            _diOutSeq       := diReqSeq;                              // 下发序号写入点①：请求序号下发 / Write point one: publish the request sequence
            _diAckAtPublish := diAckSeq;                              // 同拍快照对端 ack（陈旧 ack 识别基准）/ Snapshot the peer ack in the same scan
```
- L211 回齐判据改为：
```pascal
        IF (diAckSeq = _diOutSeq) AND (diAckSeq <> _diAckAtPublish) AND (NOT _bFaultLatch) THEN
```
（语义：同一序号必须有"新"回齐才算数；对端不刷新 ack 则走 tonAck 超时 33 → 回退 → 耗尽 34 → 故障，**fail-closed 方向正确**。）

修后需补验收向量 V7（diReqSeq=0 → 故障 36）、V8（同序号二次请求 → 不得二次 bGrant）。

---

## ③ 状态机逻辑级复核（R448/R449）逐件矩阵

证据脚本：ENUM 成员 vs CASE 标签集合差、ELSE 存在性、TON/R_TRIG 实例调用次数与是否落在 CASE 块内、`rtReset(CLK := bReset)` 形态（见文末复现命令）。

| 检查项 | #1 RotaryIndexer(6态) | #2 Asrs(6态) | #3 FillPreact(7态) | #4 MeasureLatch(5态) |
|---|---|---|---|---|
| 1 ENUM 成员全有 CASE 标签（缺失须为空集） | ✅ 6/6，缺失=空集 | ✅ 6/6，缺失=空集 | ✅ 7/7，缺失=空集 | ✅ 5/5，缺失=空集 |
| 2 每状态有出口（含 eFault 复位出口） | ✅ 8 条出口；eFault→eIdle(rtReset.Q)，不停留 | ✅ 12 条出口；eFault→eIdle(rtReset.Q) | ✅ 12 条出口；eFault→eIdle(rtReset.Q)，学习资产保留 | ✅ 10 条出口；eFault→eIdle(rtReset.Q) |
| 3 等待收敛相 TON 兜底 | ✅ eIndexing=tonIndex(域闸 20ms..60s)、eSettle=tonSettle(100ms 常量)+tonEject、eEject=tonEjectPulse+tonEject、eReady=tonReady(5s)；**无无界驻留相** | ✅ 唯一等待相 eHandshake=tonAck(两级回退 5s)；eValidate/eRetry/eCommit 分支内必迁（零驻留，论证成立） | ✅ eCoarse/eFine=tonPhase、eSettle=tonSettle；eLearn/eDone 单拍无需 | ✅ 唯一外部事件等待相 eArmed=tonArm；eHold=tonHold |
| 4 bReset 用 R_TRIG 取沿 | ✅ `rtReset(CLK:=bReset)`，CASE 内只读 .Q；无电平直判 | ✅ 同左；另 bAllocReq 亦 R_TRIG（R79 落实） | ✅ 同左 | ✅ 同左；bArm/bProbeRaw 亦 R_TRIG |
| 5 TON/R_TRIG 无条件周期刷新（R7） | ✅ 6 实例各调用 1 次，**CASE 内 0 次** | ✅ 3 实例各 1 次，CASE 内 0 次 | ✅ 3 实例各 1 次，CASE 内 0 次 | ✅ 5 实例各 1 次，CASE 内 0 次 |
| 6 CASE ELSE 兜底（码 99） | ✅ L304-309 | ✅ L252-257 | ✅ L365-370 | ✅ L289-294 |
| 7 输出在首个 RETURN 前预置 / 单点映射 | ✅ 无 RETURN；段 8 单点映射全 11 输出 | ✅ 段 8 全 9 输出；bGrant/bDone 先 `NOT _bFaultLatch` 再出 | ✅ 段 10 全 10 输出；三个连续量出口另有非有限兜底 | ✅ 段 8 全 9 输出；rLatchPosMm 有非有限兜底 |
| 8 计数器/序号回绕越界防护 | ⚠️ 工位号回绕+LIMIT 到 0..11 ✅；`iGoodCnt/iBadCnt/iEjectCnt`(DINT) 无钳（量级安全）；**`iCupPerCycle>1` 时寄位器只记 1 位、计数 +N，口径不一致（MINOR）** | ❌ DINT 直比无减法 ✅、冲突计数 ≥3 判耗尽 ✅，**但缺"序号 ≤0"域闸与"陈旧 ack"判据（见 ②，阻断）** | ✅ `iLearnCnt` DINT；限幅倒置有二级回退 | ⚠️ `iEdgeCnt/iOutsideCnt` 为 INT 且仅故障复位清零，无回绕钳（理论溢出，MINOR） |
| 9 学习类资产不被复位误清 | 无学习资产（N/A） | N/A | ✅ `_fPreactKg/_fMargin/_iLearnCnt/_bLearnClamped`：eFault 复位与撤使能路径**均不清**（L357-363、L389-391），符合 R191 声明 | N/A（`_fLatchPos` 复位亦保留，与头注一致） |

### 挂账缺陷明细（非本轮阻断，须 R82 前闭环）

- **#3 MAJOR-1｜学习资产无回灌入口**：头注 L23 称"掉电保持需上层把 rPreactKg 回写 RETENTIVE 变量"，但接口无 PREACT 种子引脚，段 6（L270-275）首扫无条件把 `_fPreactKg` 覆盖为限幅中位 → **每次上电即丢失学习成果，且上层无法回灌**（FB 内部 VAR 不可外写，输出侧回写会被下一拍覆盖）。需主控裁决：v1.0.1 增 `rPreactInit : REAL`，段 6 改 `_fPreactKg := LIMIT(_fPmin, REAL_TO_LREAL(rPreactInit), _fPmax)`，`rPreactInit ≤ 0` 时回中位起点。
- **#3 MAJOR-2｜43 码同拍竞态误锁**：段 9（L374）`IF tonPhase.Q` 与 CASE 事件分支（L299/L307 实称达标）**同拍**成立时，相已正常推进仍锁 43 → 误报故障停机。一行修：L374 改为 `IF tonPhase.Q AND ((_eState = E_DL_FillPreactSelfLearn_State.eCoarse) OR (_eState = E_DL_FillPreactSelfLearn_State.eFine)) AND (NOT _bFaultLatch) THEN`（迁相后状态已变，自然抑制）。
- **#3 MINOR**：`rPreactMax > rTargetKg` 时粗流阈值退化（`_fTarget - _fPreactKg < 0`）→ 直接跳细流，头注未声明该域。
- **#4 MINOR-1｜撤销的锁存仍污染出口**：eArmed 中 `rtProbe.Q` 与 `NOT bEnable` 同拍时，探针分支优先（L246）先写 `_fLatchPos`，段 7（L309-311）随即回 eIdle 并清 `_bLatchedLatch`，但段 8（L328）仍把该值映到 `rLatchPosMm` → 上层按 `bLatched` 取值才不会误用。一行修：L248 判据加 `AND bEnable`。
- **#4 MINOR-2**：`iEdgeCnt/iOutsideCnt` INT 无回绕钳（建议出口前 `LIMIT(0, x, 32767)` 或升 DINT）。
- **#4 MINOR-3**：软件沿锁存分辨率 = 1 个扫描周期（位置误差 = v×Tscan），头注只写"软件边沿锁存"，建议在"分工声明"补一句量化声明（本轮不阻断）。
- **#1 MINOR**：L4 轮次笔误 R83；`iCupPerCycle>1` 计数/寄位器口径不一致（见矩阵第 8 项）。

---

## ④ 修复件复裁：#5 FC_DL_BeamToppleRiskChk v1.0.1

**原缺陷**：v1.0.0 偏心系数用带符号偏移 → 负偏移时系数 < 1 → 有效载荷与利用率被低估 → `bRisk` 漏报（不安全方向）。

**修法正确性判定：正确，予以放行。**

| 维度 | 结论 |
|---|---|
| 符号方向 | L76 `rEccFactor := 1.0 + ABS(rCgOffset_mm) / rBeamDepth_mm` → 系数恒 ≥ 1、恒 ≥ 原值，**消除漏报方向**；负偏移与正偏移同权，属保守化（宁可多报）✅ |
| 域闸合理性 | L72 `ABS(offset) > depth*0.5 → RETURN`（bValid 保持段 1 预置的 FALSE）：既拦"重心跑到梁截面外"的不可信组态，又把系数**封顶 1.5**，杜绝系数无界放大 ✅ |
| 除零路径 | 段 4 已先闸 `ABS(rBeamDepth_mm) ≤ DL_EPS → RETURN`、`rBeamDepth_mm < 0 → RETURN`，L76 分母恒 > 1e-12 ✅（未新增除法点） |
| 非有限路径 | 段 3 逐项 `x = x` + `ABS(x) ≤ 3.0E38` 八项全枚举，NaN/±Inf 均提前 RETURN，**在 L76/L79 之前** ✅ |
| 闸序 | 段 4b 在段 5 之前，域闸先于系数计算；RETURN 时出口为段 1 预置（`rEccFactor=1.0`、`bValid=FALSE`、`bRisk=FALSE`），无残留脏值 ✅ |
| 边界连续 | `|offset| = depth/2` → 系数 1.5 有效；越界一档即无效返回（阶梯），与头注 L13-15 声明一致 ✅ |
| 是否引入新问题 | 无阻断项。仅 2 条 MINOR：① `rLoadKg` 允许到 3.0E38，乘 1.5 可溢出为 +Inf 并直接映射到 `rUtilPct` 出口（兄弟件 FB_DL_MeasureInputLatch/FillPreact 都在出口加了非有限兜底，本件没有）；建议 v1.0.2 出口加 `IF (rUtilPct-rUtilPct) <> (rUtilPct-rUtilPct) → 0.0` 或把 `DL_R_MAX` 降到 1.0E12。② 头注缺"修订历史"行（v1.0.0→v1.0.1 修法未留痕，回溯性差）。 |

L1 PASS、L2 PASS，返修可入库（版本号 1.0.1 与头注一致）。

---

## ⑤ 一句话总结

**5 件中 3 件放行（含 v1.0.1 返修件——修法方向与域闸均正确）、2 件阻断：`FB_DL_RotaryIndexerCycleSeq` 因 3 处 `DOWNTO`（E007，非 IEC 语法，非豁免范围）编译阻断，`FB_DL_AsrsSlotAllocSeq` 因 `diReqSeq=0` 可零握手直接 `bGrant` 放行的逻辑缺陷阻断；注册脚本本轮必须拒绝这 2 件写入 registry。**

---

## 复现命令（每个数字均可复算）

```bash
cd C:\Library
# L1（逐件，已跑：5/5 PASS，BLOCK 0 / MAJOR 0）
python _tools\dl_gate.py --file DL_Process\FB_DL_RotaryIndexerCycleSeq.st
python _tools\dl_gate.py --file DL_Process\FB_DL_AsrsSlotAllocSeq.st
python _tools\dl_gate.py --file DL_Process\FB_DL_FillPreactSelfLearn.st
python _tools\dl_gate.py --file DL_Motion\FB_DL_MeasureInputLatch.st
python _tools\dl_gate.py --file DL_Process\FC_DL_BeamToppleRiskChk.st
# L2（串行 jobs=1，已跑：4 PASS / 1 FAIL(E007)）
python _tools\l2_check.py DL_Process\FB_DL_RotaryIndexerCycleSeq.st
python _tools\l2_check.py DL_Process\FB_DL_AsrsSlotAllocSeq.st
python _tools\l2_check.py DL_Process\FB_DL_FillPreactSelfLearn.st
python _tools\l2_check.py DL_Motion\FB_DL_MeasureInputLatch.st
python _tools\l2_check.py DL_Process\FC_DL_BeamToppleRiskChk.st
# E007 归因最小复现（6 行）
python _tools\l2_check.py _tmp_r81\t_downto.st
# 修法验证副本（三处 DOWNTO→镜像下标，其余零改动）：PASS
python _tools\l2_check.py _tmp_r81\FB_DL_RotaryIndexerCycleSeq_fixprobe.st
# 库内同缺陷先例（2 件，均 E007）
python _tools\l2_check.py DL_MathData\FC_DL_PolyEvalHorner.st
python _tools\l2_check.py DL_Motion\FB_DL_MarkPositionLatch.st
```

> L3 向量门：本轮未执行（5 件均无 `_TESTS\<Name>.json`；且 #1/#2 已阻断，#2 修复后须先落 V7/V8 向量）。
> 说明：本机 L2 用 RuSTy；CI 权威位（MatIEC）对 `DOWNTO` 预期同样不接受（其 FOR 文法为 `TO [BY]`），#1 修好后须由 CI 实测复核，不得以本机 PASS 代替 CI 结论。

---

# 复裁（R81-C 收尾）— dlf-compile-verifier 最终裁决

- 时间：2026-11-24 ｜ 性质：对 R81-B 判 FAIL 的 2 件做**正式复裁**（本裁决为终局，主控不得代判）
- 工具链：L1 `dl_gate.py --file`（tree-sitter）｜ L2 `l2_check.py <file>`（RuSTy plc.exe，**串行 jobs=1，未使用 --jobs**）｜ L3 `_TESTS/*.json`（缺陷覆盖）
- 结论：**两件均 PASS，放行写 registry**（附 3 条纯注释类挂账，零行为变更，须在 R81 封版前由编码专家补齐）

## ① 复裁裁决表

| # | 文件 | 版本 | L1 | L2 | 原缺陷闭合 | 复裁 |
|---|---|---|---|---|---|---|
| 1 | `DL_Process/FB_DL_RotaryIndexerCycleSeq.st` | 1.0.1 | PASS | **PASS** | 是（逐拍等价，20 000 例零失配） | **PASS** |
| 2 | `DL_Process/FB_DL_AsrsSlotAllocSeq.st` | 1.0.1 | PASS | **PASS** | 是（零握手路径被码 36 前置拦截，fail-closed） | **PASS** |

L1 计数：2/2 PASS（BLOCK 0 / MAJOR 0）。L2 计数：2/2 PASS（首个 error 为空，`dep_rounds=0`）。

## ② 件 1 —— E007 修法验证（照抄主控要求：必须"先高位后低位"，不得覆盖）

修法为镜像下标升序：`FOR _nIdx := 0 TO (ARR_MAX-1)`，实际操作下标 `ARR_MAX-_nIdx`（L257-259）。

- **等价性证明**：目标下标序列为 11,10,…,1（严格单调递减），源下标为 10,9,…,0，与原 `FOR n := 11 DOWNTO 1` 的搬移顺序**逐拍同序同值**；因目标下标恒大于源下标，读到的永远是尚未被本拍覆盖的高位旧值 → **不可能发生覆盖**。
- **穷举验证**：12 位寄位器随机初值 × 20 000 例，`orig(downto)` 与 `mirror` 结果失配 **0/20000**（命令见 §复现）。单点抽检：`[1,0,0,0,0,0,0,0,0,0,0,0]` → 搬移后 `[0,1,0,…]`，第 0 位被新杯覆盖，符合"上料位装入新杯"的物理模型。
- **L237 / L293（清位循环）**：`0 TO ARR_MAX` 升序清零，与顺序无关，语义零变化。
- **残余 DOWNTO 扫描**：`DL_Process` 全目录仅 L255 注释文本命中，无代码级 `DOWNTO` → E007 根因消除（非"注释掉报错"式掩盖）。
- 顺带复核（R7 / 兜底 / CASE）：5×TON + rtReset 全在 CASE 外无条件调用（L205-217），IN 均含 `NOT .Q` 自复位；`CASE … ELSE` 在（L306）；ENUM 六态 `eIdle/eReady/eIndexing/eSettle/eEject/eFault` 逐态有分支，eFault 唯一出口为 rtReset.Q（L292-304），出口穷举；等待相 `tonSettle`（eSettle）、`tonEject`（坏杯在位的整定驻留 + 剔除相丢就绪）双兜底在。**均未受损。**

## ③ 件 2 —— 零握手假放行修法验证（含"是否引入新缺陷"专项）

三处改动（L198-200 码 36、L210 发布快照、L216 判据、L148 新 VAR）逐条核验：

1. **原缺陷是否真闭合**：是。`diReqSeq=0`/负 在 eValidate 首分支即置 `_iErrTmp=36 + _bFaultReq`，段 7 锁存并迁 eFault，**永不进 eHandshake**，因此 `diAckSeq(0)=_diOutSeq(0)` 的假等式不再可达。模拟：seq=0 → 第 1 拍 Fault/36/grant=False；seq=-1 同。原判场景（唯一可达路径）已被源头切断。
2. **是否误伤合法路径**：`_diAckPublish` 初值 0 只在"发布瞬间 ack 已等于 out"时命中。`out = diReqSeq > 0`，初值 0 与之必不等 → **合法首事务（含 seq=1）与重复事务均正常放行**，实测 3 条合法路径全 grant（V1 seq7/ack0→7、首事务 seq1、回退后重发）。唯一的拒放行域 = "ack 在发布时已经等于要发布的序号"（陈旧等值 / 对端提前应答 / 上位复用已确认序号），这是真实协议违例，拒之方向正确（fail-closed），但**必须写进接口契约**（否则集成方按"提前 ack"实现会得到 34 而非明确码）——见挂账 M2-2。
3. **`_diAckPublish` 是否需在 eRetry / 复位路径重置**：**功能上不需要**。全件进入 eHandshake 的入口唯一（L211），且入口前必在 L210 重写快照；eRetry 的 `_diOutSeq:=0`（L234）与 eFault 复位（L249-256）之后再次握手会先覆盖快照，不存留跨事务脏值。**结论：不必新增赋值点**（新增反而破坏"写入点集合"的单一性）。建议仅在注释里点明"快照随每次发布重写，故无需复位"。
4. **终止性**：陈旧等值进入握手后不 grant → `tonAck.Q` → 33 → eRetry → 同 seq 再发布（快照刷新为当前 ack，仍等值）→ 三轮 → **34 重试耗尽**，有界收敛，不出现活锁/无界等待。模拟 tick=12 收敛。
5. 顺带复核：ENUM 六态全覆盖 + `CASE … ELSE`（L258）；eFault 唯一出口 rtReset.Q；`tonAck` 在 eHandshake 唯一等待相兜底且 IN 含 `NOT .Q`；rtReset/rtAlloc/tonAck 全在 CASE 外（L181-184）→ R7 完好；三个 `_diOutSeq` 写入点仍各自单点、未新增同拍双写。

## ④ 挂账（全部为纯注释/文档，零行为变更；不阻断本轮 registry 写入，但阻断 R81 封版结项）

| 编号 | 文件 | 行 | 级别 | 内容 |
|---|---|---|---|---|
| M1-1 | 件1 | L3 / L86 | MINOR（审计留痕） | 头注版本仍 `1.0.0`、修订历史仅 v1.0.0 一条，与本次 v1.0.1 改动不符；两件均未入 registry，**必须以 1.0.1 入库并补修订历史行**，否则"内容已改、版本未动"违反版本头规则 |
| M2-1 | 件2 | L3 / L87 | MINOR（审计留痕） | 同上（版本 1.0.0 → 1.0.1 + 修订历史行） |
| M2-2 | 件2 | L37 / L61-73 / L88-99 | **MAJOR-DOC** | **新故障码 36 未登记**：迁移表⑤未含新判据、码表无 36（缺"反证"行）、验收向量无对应用例。集成方按码表排障会漏诊 36。须补：迁移⑤ 加 `AND (diAckSeq <> _diAckPublish)`；码表补 `36 = 请求序号非法（diReqSeq ≤ 0，未初始化），禁参与握手`；边界补 ack 契约「ack 必须为发布后新值，对端提前应答/复用已确认序号将走 33→34 耗尽，属 fail-closed 设计」；向量补 V7（diReqSeq=0 → 36）、V8（ack 恒等 → 三轮 → 34） |

## ⑤ L3 向量门现状（不阻断本轮，R82 前必须补）

`_TESTS/` 下两件均**无向量文件**（L3 覆盖 0/2）。须补最小集（每件 ≥4 例，禁只写 happy path）：

- 件1：V6 移位方向位序（相邻两杯交替好坏，索引 12 拍后逐位比对 aCupOk，专门锁死"高→低"顺序）；组态越域（iStationCnt=3→11）；剔除位不就绪超时（→21）；bReset 沿清寄位器/计数（→ 全 FALSE / 0）。
- 件2：V7 零握手（diReqSeq=0 → 36，bGrant=FALSE）；V8 陈旧等值（ack 恒 = seq → 33 → 34 耗尽，bGrant 全程 FALSE）；V1 正常（ack 0→7 → 单拍 bGrant，iAllocSlot=42）；V5 锁闭（→32）；复位路径（bReset → diOutSeq=0 / iErrCode=0）。

## ⑥ 复现命令（新增，件 1/件 2 修后重跑）

```bash
cd C:\Library
python _tools\dl_gate.py --file DL_Process\FB_DL_RotaryIndexerCycleSeq.st --round R81-C   # PASS 1 | MAJOR 0 | BLOCK 0
python _tools\dl_gate.py --file DL_Process\FB_DL_AsrsSlotAllocSeq.st  --round R81-C      # PASS 1 | MAJOR 0 | BLOCK 0
python _tools\l2_check.py DL_Process\FB_DL_RotaryIndexerCycleSeq.st                      # PASS=1 FAIL=0 TOTAL=1
python _tools\l2_check.py DL_Process\FB_DL_AsrsSlotAllocSeq.st                           # PASS=1 FAIL=0 TOTAL=1
```

镜像下标等价性（20 000 例穷举）与件 2 握手路径模拟为内联脚本，已在本轮执行：失配 `0/20000`；件 2 六路径终态 = {V1: grant, seq1: grant, 回退重发: grant, seq0: Fault/36, seq-1: Fault/36, 陈旧等值: Fault/34, 提前应答: Fault/34}。

## ⑦ 复裁结论

**2 件全部 PASS，放行写 registry（版本均按 1.0.1 登记）。** 原 2 项阻断（E007 编译阻断、零握手假放行）均已真正闭合，未引入新的编译或安全侧缺陷；`_diAckPublish` 无需在 eRetry/复位路径新增重置点。放行不等于结项：M1-1 / M2-1 / M2-2 三条注释级挂账与 L3 向量集须在 R81 封版前补齐，否则下一轮全库 L1（版本头核对）与 L3 会反打。
