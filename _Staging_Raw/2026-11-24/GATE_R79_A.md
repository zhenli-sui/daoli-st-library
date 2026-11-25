# GATE_R79_A —— R79 批 1 编译闸裁决（dlf-compile-verifier 本人产出）

- 轮次：R79 / 批 1｜日期：2026-11-24｜裁决人：编译闸席（一票否决）
- 环境：RuSTy（`_tools/l2_check.py`，**jobs=1 全程串行**）+ 自研 L1 静态门（`_tools/dl_gate.py`）
- 复现命令（每个数字都可复跑）：
  - L1：`python C:\Library\_tools\dl_gate.py --file <file>`（29 次，逐件）
  - L2：`python C:\Library\_tools\l2_check.py <file1> <file2> ...`（4 批，A9+B8+C8+D4，默认串行）

## 一、门禁原始输出（不可省）

| 批次 | 命令 | 输出 |
|---|---|---|
| A 日历族 9 件 | `l2_check.py DL_MathData/FC_DL_Cal*.st` | `PASS=9 FAIL=0 TOTAL=9` |
| B 数论族 8 件 | `l2_check.py DL_MathData/FC_DL_Int*.st` | `PASS=8 FAIL=0 TOTAL=8` |
| C 几何族 8 件 | `l2_check.py DL_MathData/FC_DL_Geo*.st` | `PASS=8 FAIL=0 TOTAL=8` |
| D 存量修复 4 件 | `l2_check.py .../FC_DL_RoundToMultipleInt.st ...` | `PASS=4 FAIL=0 TOTAL=4` |
| L1 静态 29 件 | `dl_gate.py --file` × 29 | 逐件 `PASS 1 / MAJOR 0 / BLOCK 0` |

> L2 说明：本机 RuSTy 可用（接口预筛 22/22，缓存命中），**本轮 L2 非 pending-ci，为实测 29/29 PASS**。

## 二、逐件裁决表

| # | 文件 | 结论 | 错误码 | L1 复核 | L1 行号证据 | 建议动作 |
|---|---|---|---|---|---|---|
| 1 | FC_DL_CalIsLeapYear | PASS | — | 清 | 45-48 域闸先判年份；51-53 取余除数均常量；无除零/溢出面 | 入库 |
| 2 | FC_DL_CalMonthDays | PASS | — | 清 | 49-52 月份域闸为唯一故障口；57-59 nYear<1583 按平年（契约+遗留假设已声明） | 入库 |
| 3 | FC_DL_CalDayOfYear | PASS | — | **MAJOR** | L78 `nY2:=nYear+4800`、L80 `365*nY2`、L83 `365*(nYear+4799)`：**nYear 无上界闸**，nYear>≈5,878,716 时 365*(nYear+4799) 超 DINT_MAX 回绕。实测域 1583~1e6 内正确（已验 2024-03-01→61） | 挂账：加 `nYear>9999 → bError` 上界闸（4 件同源，统一修） |
| 4 | FC_DL_CalDateFromDayOfYear | PASS | — | 清 | 62-65 双域闸（年份+序号上界 366）；70-85 逐月递减无乘大数；已验 365(平年)→(12,31)、1→(1,1) | 入库 |
| 5 | FC_DL_CalWeekdayIndex | PASS | — | **MAJOR** | L78/L80 JDN 式与 #3 同源溢出面（nYear 无上界）。JDN 口径已验：2024-03-01 JDN=2460371，mod7=4→周五 ✔ | 挂账同上 |
| 6 | FC_DL_CalIsoWeekNo | PASS | — | **MAJOR** | L101/L103/L104 同源溢出面。跨年归属已验 3 例：2024-01-01→W01、2021-01-01→2020-W53、2025-12-29→2026-W01 ✔；53 周判据（1/1 周四 or 闰年周三）与 ISO 等价 ✔ | 挂账同上 |
| 7 | FC_DL_CalQuarterIndex | PASS | — | 清 | 39-42 月份域闸；45 除数为常量 3，`(m-1)/3+1` 边界 3/6/9/12 正确 | 入库 |
| 8 | FC_DL_CalIsWeekend | PASS | — | **MAJOR** | L82/L84 同源溢出面；nDow≥5 判周末正确（0=周一） | 挂账同上 |
| 9 | FC_DL_CalMonthEndDate | PASS | — | 清 | 50-53 双域闸；59-68 月长选择覆盖 2/30 天月/其余，无越界路径 | 入库 |
| 10 | FC_DL_IntSqrtFloorUdint | PASS | — | MINOR | L52 初值 nVal/2+1 恒≥√n（除零不可达）；L56 和式实测上界 nApprox+√n≤2^31+65536 不溢出；**MINOR**：L64 `nIter>=64` 会在「恰在第 64 次迭代收敛」时误置 bError（结构性不可达，非缺陷但属判据口径瑕疵） | 入库；口径改 `nConverged` 布尔位（可选） |
| 11 | FC_DL_IntIsPerfectSquareUdint | PASS | — | MINOR | L72 回乘前 L68 拦根>65535 正确；**MINOR**：因 ⌊√UDINT_MAX⌋=65535，L68 分支恒不成立（死分支，无害） | 留档 |
| 12 | FC_DL_IntDigitSumUdint | PASS | — | 清 | 45-49 除数常量 10；守卫 10 恰好覆盖 UDINT 最大 10 位（4294967295 第 10 拍降为 0）✔ | 入库 |
| 13 | FC_DL_IntDigitCountUdint | PASS | — | 清 | 44-48 同上；0→1 位语义正确 | 入库 |
| 14 | FC_DL_IntPowSatUdint | PASS | — | **MAJOR** | L61/L70 乘前反算本身正确；**但 L70-74 底数平方被钳到 `DL_MAX_UDINT` 时未置 bOverflow**，随后 L61 反算 `1 > MAX/MAX` 为假 → 直接乘得 MAX 返回。实测：nBase=2,nExp=32 → 返回 16#FFFF_FFFF 且 **bOverflow=FALSE**（nBase=3,nExp=32 同）→ 与契约「饱和时 bOverflow:=TRUE」矛盾（数值恰为 MAX，故只剩标志漏报） | 挂账→回派：L70 钳位分支内补 `bOverflow := TRUE;` |
| 15 | FC_DL_IntDivModSafe | PASS | — | 清 | 48-51 除零闸；54-57 DINT_MIN/-1 特判；62 余数由乘法自证，`nQ*nDen` 恒 ≤\|nNum\| 不溢出 | 入库 |
| 16 | FC_DL_IntSignExtractLreal | PASS | — | 清 | 46 NaN 用 `x<>x`；54 Inf 用 `ABS>1.0E308`；61 死区；66-70 死区外无零值歧义 | 入库（本件即全库非有限判据的**正确范式**） |
| 17 | FC_DL_IntReverseDigitsUdint | PASS | — | 清 | 54 `nRev>(MAX-nDigit)/10` 反算正确；守卫 10 覆盖 10 位数（已验 1e9→1） | 入库 |
| 18 | FC_DL_GeoPointLineDist | PASS | — | 清 | 51 NaN 闸；60 平方和溢出由 61 接住；66 `fLen<EPS` 在除前拦（L79 除法分母已证非零有限） | 入库 |
| 19 | FC_DL_GeoLineIntersectXY | PASS | — | 清 | 60 只判 NaN，Inf 输入经 71（den 非有限）/74 兜住；t/u 公式核对 `t=((C−A)×d2)/den`、`u=((C−A)×d1)/den` ✔；85 线段域闸不置 bError（合契约） | 入库 |
| 20 | FC_DL_GeoPointInRectXY | PASS | — | MINOR | 70 四点容差窗口含边界 ✔；**MINOR**：L64 退化判据要求宽**与**高同时 <EPS，「零宽长条」被判合法，点在线上返回 TRUE（与契约「宽高均小于容差」一致，属设计缺口而非实现错误） | 留档 |
| 21 | FC_DL_GeoPointInConvexQuadXY | PASS | — | 清 | 66 鞋带式核对（单位方→2A=2 ✔）；71 面积下限；77-80 四边叉积；83-84 同号（含近零） | 入库 |
| 22 | FC_DL_GeoCentroid3Pt | PASS | — | 清 | 56-64 共线闸在除法前；67-68 除数常量 3 | 入库 |
| 23 | FC_DL_GeoPolylineLenFixed | PASS | — | 清 | 53-59 先钳位后循环；63-64 下标 i∈[1,nUse-1]、i+1≤10 **全在 [1..10] 内**；70 出口自证非有限/负 | 入库 |
| 24 | FC_DL_GeoBBoxFromPtsFixed | PASS | — | 清 | 60-66 钳位；70-72 下标 1..nUse≤10 **不越界**；73 非有限点跳过并计数；98 全非有限→bError | 入库 |
| 25 | FC_DL_GeoLineAngleXY | PASS | — | 清 | 51 NaN；69-77 dx 近零走 ±π/2（除前分列）；81-90 象限补偿核对二/三象限与 `−π→+π` 归一，值域 (−π,π] ✔ | 入库 |
| 26 | FC_DL_RoundToMultipleInt | PASS | — | 清 | **v1.0.1 饱和闸实测有效**：手算 3 例 —— (a) nValue=DINT_MAX, m=4 → nLo=2147483644 > MAX−4 → 饱和 MAX+bSat ✔；(b) nValue=DINT_MIN+1, m=4 → nLo−m=−2147483648 恰可表示，**未误饱和** ✔；(c) L50 `(nValue/m)*m` 恒 ≤\|nValue\| 不溢出 ✔。原缺陷（进位侧回绕）确已修好 | 入库 |
| 27 | FB_DL_MultiZoneSetpointScheduler | PASS | — | **MAJOR** + MINOR | **J1 修复验真**：L155 `_rtReset(CLK:=bReset)` 在段 1、CASE 之外无条件调用，L292 eFault 出口用 `_rtReset.Q` ✔。**MAJOR**：L218-219 `(fSetpoint−fSetpoint)<>0.0` 用 x−x 判 Inf —— 与 fc_signextract 头注释自述「已被 R77 列为死谓词、优化编译可能常量折叠」直接冲突；一旦折叠，Inf 设定值通过校验写入 `afActiveSp[]`（下游无第二道有限性闸）→ 安全侧漏闸。**MINOR**：文件头 Version 仍 1.0.0，正文却标 v1.0.1 修复，修订历史 v1.0.1 条目未记录该修复 | MAJOR 回派：改 `ABS(fSetpoint) > 1.0E308`；MINOR：版本头补 1.0.1 + 记一条修订 |
| 28 | FB_DL_PalletizerLayerBuildSeq | PASS | — | MINOR×2 | **J1 修复验真**：L176 `_rtReset` 在段 4、CASE 之外无条件调用，L250 eFault 用 `_rtReset.Q` ✔。**MINOR**：`_bCfgOk`（L132/154/159）**只写不读**（组态越域已由锁存兜住，无行为影响）；L240 eFull 仍用 bReset **电平**（契约 R98 明文两条出口，属有意保留，非残留缺陷）；**MINOR**：修订历史止于 v1.0.0，缺 v1.0.1/v1.0.2 记录（头标 1.0.2） | 入库；MINOR 挂账（删死变量、补修订历史） |
| 29 | FB_DL_AnalogSensorHealthClassify | PASS | — | **MAJOR** + MINOR×2 | **J1 修复验真**：L198 `_rtReset` 在段 4、CASE 之外无条件调用，L304 eFault 用 `_rtReset.Q` ✔；L258 除零由 L248 `_nCnt<1` 兜住 ✔。**MAJOR（行为级，必回派）**：`_bOverHigh/_bOverLow` 是**单拍标志**（L148-149 注释「本拍超量程标志」），段 1（L162-163）**每拍清零**；而 eClassify 在**下一拍**才执行，读到的恒为 FALSE → L269-276「超量程优先（安全侧）」分级分支**恒不成立**，含超量程样本的窗在窗末被误分为 eNoisy/eStuck/eNormal，把当拍已上报的 eOverHigh 覆盖掉。**MINOR**：L166-170 同样用 x−x 判 Inf（但 L231/236 超量程闸可兜住 Inf 输入）；**MINOR**：修订历史止于 v1.0.0（头标 1.0.2） | MAJOR 回派：把两个标志改为**窗作用域**（在 eIdle→eCollect 初始化处清零、段 1 删去清零，或另设 `_bSeenOverHigh` 窗内锁存位）；MINOR 挂账 |

## 三、汇总

**本批 29 件｜PASS 29｜FAIL 0｜EXEMPT 0｜通过率 100%**

- BLOCK：0（无编译失败、无未声明标识符、无开闭不配平、无码段重复）
- MAJOR：**7**（#3 #5 #6 #8 同源 JDN 溢出面 4 件；#14 bOverflow 漏报；#27 Inf 死谓词；#29 超量程分级死分支）
- MINOR：**8**（#10 #11 #20 #27 版本头 #28 ×2 #29 ×2）
- EXEMPT：0（**本批无一件是编译器不支持但合法的 IEC 语法**；29 件全为 FC 或普通 FB，与派单预期一致）
- 就地修复：**0 件**（本轮无机械可修项——29 件 L2 一次过；7 项 MAJOR 全属行为/语义缺陷，按 R459 口径不在闸席改动范围）

## 四、回派清单（交主控 → 编码专家，闸席不动业务代码）

| 序 | 件 | 缺陷 | 修法（最小改动） | 级别 |
|---|---|---|---|---|
| P1 | FB_DL_AnalogSensorHealthClassify | 窗末超量程分级死分支 | 删 L162-163 的两行清零，改在 L202-205 清窗处（eIdle→eCollect）一并清零 `_bOverHigh/_bOverLow`；其余不动 | MAJOR |
| P2 | FC_DL_IntPowSatUdint | 饱和标志漏报（值不误） | L71 `nBaseUse := DL_MAX_UDINT;` 之后补 `bOverflow := TRUE;` | MAJOR |
| P3 | FB_DL_MultiZoneSetpointScheduler | Inf 设定值漏闸 | L219 改 `OR (ABS(aSlots[_nZ][_nK].fSetpoint) > DL_MZS_FIN)`（需新增常量 `DL_MZS_FIN : REAL := 1.0E308`），删 x−x 子句 | MAJOR |
| P4 | 4 件 JDN 族（#3/#5/#6/#8） | 年份无上界闸 | 各件域闸加 `OR (nYear > 9999)`（新增 `DL_GREG_END : DINT := 9999`）→ bError。属加固，非阻塞 | MAJOR（可挂账） |
