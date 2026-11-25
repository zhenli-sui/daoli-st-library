# QA_REVIEW_R77（审校与去重席 / 独立于主控）2026-11-23

**汇总：41 件 | PASS 34 | 存疑放行 6 | 拒收 1 | BLOCK 0 | MAJOR 3（均 1 件）| MINOR 2 | 去重拦截 1**

- 名称级：41 件 × 全库 1,327 名（含 `_names_R77.txt` 全量）精确/不区分大小写比对 → **0 命中**。
- 签名指纹：入/出/IN_OUT 类型序列归一化 SHA1 × 全库 1,327 件 → **0 完全碰撞**；41 件内部互比亦 0 重复。
- 语义级：9 组邻件逐对复核（见下）。

## 一、拒收（1 件，请主控移入 `_quarantine/`）

| 件名 | 与谁重复 | 判定依据 |
|---|---|---|
| FC_DL_StringPadLeftZeros | `DL_MathData/FC_DL_StringPad` | 输入形态同（源串 + 填充字符 + 目标长度），输出语义同（sOut/bTruncated/eErr）。在库件入参 `sIn/sPadChar/nTargetLen/eSide(E_DL_PadSide 左/右/居中)`，**左填充已被 eSide 参数完全覆盖，填充字符亦为入参**。新件唯一增量 = `uiOutLen`（= LEN(sOut) 可得）、`sPadChar` 缺省 '0'。同族+同输入形态+同输出语义，未给出新边界/新数据类型域/新行业约束 → 判同义变体。 |

## 二、存疑放行（6 件，请总监复议；我不做终裁）

| 件名 | 邻件 | 放行理由（弱差异） |
|---|---|---|
| FC_DL_StatsRmsCalc | `FC_DL_RmsCalc` | 同族同语义；差异仅为 LREAL 精度、窗口 1..64 对 1..4096、附加 fPeak/fSumSq 出口。属精度变体，但**新件头注未写对本件的分工声明**，建议补 |
| FC_DL_StringSplitPair | `FC_DL_StringSplit` | 输出形态不同：单对 key/value 双 STRING 对字段数组(VAR_IN_OUT)+uMaxFields |
| FC_DL_StatsPercentile | `FC_DL_MedianAbsDev` | 仅"中位"一点重叠；本件为任意百分位+线性插值，域 1..64 vs 1..16 |
| FC_DL_InterpHoldLast | `FC_DL_InterpStepNearest` / `FC_DL_InterpolateTable2D` | 本件不插值、超末节点保末值；在库件为步进/双线性插值 |
| FC_DL_HumidityUnitConvert | `FC_DL_HumidityRatioCalc` | 输出语义不同（RH%↔AH g/m³ 对含湿量 W kg/kg）；饱和压近似式重叠可接受 |
| FC_DL_TableLookupNearestIndex | `FC_DL_InterpStepNearest` | 仅返回索引、允许无序表；在库件返回插值结果并钳位 |

**判定为有效变体（无条件放行）**：`FB_DL_DeadbandFilter`（有状态保持 ↔ 无状态 FC_DL_Deadband，接口 4 入 6 出 vs 4 入 4 出）、`FB_DL_QuantizeFilter`（+fHyst 回差防抖状态 ↔ FC_DL_QuantizeStep 单拍取整）、`FC_DL_ViscosityUnitConvert`（单位换算 ↔ FB_DL_SlurryViscosityComp 温度补偿曲线，零重叠）、`FC_DL_StringRepeat`（次数重复 ↔ FC_DL_StringConcatEx 二串拼接）。

## 三、MAJOR（3 条，全部集中于 FB_DL_RunningAverageN → 建议挂账，本轮不入库）

1. **FB_DL_RunningAverageN:135+140+143 环形写指针语义错位 → 均值恒错**
   填充相 `_iHead := _iFill`（指向**最新**槽），满窗相却把 `_iHead` 当**最老**槽用：`_fSum := _fSum - _afBuf[_iHead] + fIn`。第 5 拍（iWindow=4，输入 1..5）：`_iHead=4` → `_fSum=10-4+5=11`，`fOut=2.75`；**头注验收向量②要求 3.5**（应为 10-1+5=14 → 3.5）。被挤掉的是最新样本，窗口内容变 {1,2,3,5}，此后持续偏差。
   建议：满窗时 `_iHead` 应指向最老槽（填充相结束置 `_iHead:=1`），或改双指针 `_iOld/_iNew`。
2. **FB_DL_RunningAverageN:82+174 故障码不锁存 → 故障态中 bError 归 FALSE**
   每拍 `uErrorId := 16#0003_0000` 无条件清零；单拍 NaN 进 eFault 后，下一拍合法输入即把码清 0，而 `bError := (uErrorId<>0)` → FALSE，状态仍在 eFault、输出仍冻结。**名实分裂**（下游读到"无故障"）。建议：故障码随状态锁存，仅在 eInit/eRun 入口清。
3. **FB_DL_RunningAverageN:7-8 声明「运行中变更窗口自动清表重建」，实现中无此分支**
   段 3 仅处理 bReset（:99-101），全文件无 `iWindow` 变化检测。窗口 32→4 时 `_iFill=32 > _iWinEff=4`，`_afBuf[5..32]` 旧样本永不覆盖却一直计入 `_fSum`、并恒除以 32 → 永久脏均值。建议：头注二选一，要么实现窗口变更清表，要么删除该声明并把 `iWindow` 列为"仅上电可改"。

## 四、MINOR（2 条）

- **FC_DL_StatsPercentile:147** `_i := iCount;` 在 FOR 内改循环控制变量做提前收敛，CODESYS 可用但违背 IEC 语义中立性 → 建议改 `WHILE` + 显式 `_bSorted` 退出。
- **FC_DL_StatsPercentile:139/141/142** 同段内 `_afBuf[_j + DL_SPC_ONE_I]` 与 `_afBuf[_j + 1]` 常量/字面量混用（同一语义两种写法），建议统一为常量形式。

## 五、12 项定向扫查（深度 5 件：StatsPercentile / StringRepeat / RunningAverageN / StatsMinMaxWindow / ConcentrationUnitConvert；其余 36 件快扫 + 机检脚本）

| # | 扫查项 | 结论 |
|---|---|---|
| 1 | 安全侧默认值 | 通过。5 件均段 0 预置（StatsPercentile:98-103、StringRepeat:76-81、Concentration:97-99）；RunningAverageN 无预置段但 eInit 播种，出参全覆盖 |
| 2 | 除零防护 | 通过。StringRepeat:85 先判 LEN=0 再 :99 做 255 DIV；Concentration:126 判 M≥1E-9 才走 :138/:147；RunningAverageN:147 判 `_iFill>=1` 再 :148 除法；StatsPercentile 仅 /100 常量 |
| 3 | 数组/字符串越界钳位 | 部分命中 → 见 MAJOR-1（RunningAverageN:140 取错槽，非越界）。StatsPercentile:159-161 上限钳位、:171 插值上界退化；StringRepeat:99-102 反算可容次数后 :126 复检，无越界 |
| 4 | 非有限值拦截 | 通过。全 41 件均含 `x<>x` + `(x-x)<>0` 双判（StatsPercentile:120、MinMax:111/114、Concentration:102-103、RunningAverageN:93）；RunningAverageN 拦截了但**码不锁存**（MAJOR-2） |
| 5 | 浮点容差 | 通过。Concentration:93 TINY=1E-9；头注容差声明（StatsPercentile:42 容差 1E-9） |
| 6 | ENUM 越域防御 | 通过。Concentration:110-115 三段与判；RunningAverageN eState ELSE 兜底 :164-168 |
| 7 | CASE 含 ELSE | 通过。7 件 FB 全部 `CASE…ELSE`（CASE 计数 = ELSE≥4，机检无裸 CASE） |
| 8 | 状态机无出口驻留 | 通过。RunningAverageN eFault 出口可达（bEnable 跌落 :104 / bReset :99）；eHold 可回 eRun |
| 9 | 出参全路径赋值 | 机检 41/41 无遗漏出参；但 RunningAverageN `bError` 语义路径不全（MAJOR-2） |
| 10 | TON/边沿无条件周期刷新 | N/A。机检 41 件 TON/TOF/R_TRIG/F_TRIG 命中数仅来自头注文字，实体内**无定时器/边沿实例** |
| 11 | 变量注释双语 | 通过。抽检 5 件逐行 `// 中文 / English` 齐备 |
| 12 | 头注 ↔ 实现一致性 | **命中 1 件**：RunningAverageN:8 声明窗口变更清表，实现缺（MAJOR-3）；验收向量②与实现不符（MAJOR-1，说明验收向量未被执行/未被闸机覆盖） |

## 六、挂账（按下轮优先级）

1. `FB_DL_RunningAverageN` 三项 MAJOR 修复（环形指针 / 故障码锁存 / 窗口变更）——**最高优先，且验收向量② 必须重跑**。
2. **扩面复审请求**：B3 滤波族同模板派生 7 件（`FB_DL_PeakHoldFilter:164`、`GatedUpdateFilter:167`、`HoldLastGoodFilter:186`、`RateOfChangeFilter:175` 等）请主控授权按 RunningAverageN 同型缺陷（环形/保持指针语义、故障码锁存、头注声明）逐件复核——本轮时间窗不足以逐件通读。
3. `FC_DL_StringPadLeftZeros` 拒收（或按总监裁定改为合并进 `FC_DL_StringPad` 的别名）。
4. `FC_DL_StatsRmsCalc` 补写对 `FC_DL_RmsCalc` 的分工声明。

## 七、闸机逃逸备注（对编译验证席）

GATE_R77 报 41/41 PASS，但 `FB_DL_RunningAverageN` 的验收向量② 结果实测 2.75 ≠ 声明的 3.5 —— **说明闸只做结构与静态检查，未执行头注验收向量**。建议 `dl_gate.py` 新增锚点：解析头注"验收向量"中的 `fOut=` / `fResult=` 期望值，对纯算法 FB 走一次参考实现比对（至少覆盖滑动窗口/环形缓冲类）。
