# GATE_R82 — 编译验证席裁决回执

**轮次**：R82 ｜ **件数**：40（36 FC + 4 FB）｜ **裁决时间**：2026-11-24
**工具链**：RuSTy 1.0.8 (d1f14ee) 串行 jobs=1 ｜ dl_gate.py（selftest PASS 20/20 例）
**本席签名**：全部数字均由下列命令行复现，未引用任何预筛结果。

复现命令：
```
python C:\Library\_tools\l2_check.py <40 files...> --out _Staging_Raw\2026-11-24\_l2_r82_raw.json   # 串行
python C:\Library\_tools\dl_gate.py --file <each> --json-out ...                                     # 逐件
python C:\Library\_tools\dl_gate.py --selftest                                                       # 回归集 20 例
```

---

## 一、逐件裁决表

| # | 文件名 | 静态闸 | L2 编译 | 终裁 | 错误码/行号 | 建议动作 |
|---|---|---|---|---|---|---|
| 1 | FC_DL_CoagDoseFromJarTest | PASS | PASS | PASS | — | 入库 |
| 2 | FC_DL_FlocDilutionRatio | PASS | PASS | PASS | — | 入库 |
| 3 | FC_DL_SettleVelocityCalc | PASS | PASS | PASS | MINOR：粒径无 [>0] 闸 | 补 rDpUm<=0 闸（L50 后），入库 |
| 4 | FC_DL_SludgeBlanketLevel | PASS | PASS | PASS | — | 入库 |
| 5 | FC_DL_ClarifierSurfaceLoad | PASS | PASS | PASS | — | 入库 |
| 6 | FC_DL_SviCalc | PASS | PASS | PASS | — | 入库 |
| 7 | FC_DL_NtuCoagDoseAdj | PASS | PASS | PASS | — | 入库 |
| 8 | FC_DL_LamellaAreaCalc | PASS | PASS | PASS | — | 入库 |
| 9 | FC_DL_ScrewPressThroughput | PASS | PASS | PASS | — | 入库 |
| 10 | FC_DL_CakeSolidsCalc | PASS | PASS | PASS | — | 入库 |
| 11 | FC_DL_PolymerDoseCalc | PASS | PASS | PASS | — | 入库 |
| 12 | FC_DL_CentrateTurbidityIdx | PASS | PASS | PASS | — | 入库 |
| 13 | FC_DL_FiltrateRecycleRatio | PASS | PASS | PASS | — | 入库 |
| 14 | FC_DL_DewaterMassBalance | PASS | PASS | **MAJOR** | L70 回收率恒等式 | rRecoveryPct 恒等 100%，需补滤液 SS 输入或删除该输出 |
| 15 | FC_DL_BeltPressLoadRate | PASS | PASS | PASS | — | 入库 |
| 16 | FC_DL_ScrubberLiquidGasRatio | PASS | PASS | PASS | — | 入库 |
| 17 | FC_DL_PackedBedHtu | PASS | PASS | **MAJOR** | L61 缺总压 P 因子 | 增加 rPressAtm 入参，HTU=G/(Kga·A·P) |
| 18 | FC_DL_ReagentConsumeCalc | PASS | PASS | PASS | — | 入库 |
| 19 | FC_DL_CatalystActivityDecay | PASS | PASS | **MAJOR** | L91 RUL 符号错 | 改 `(LnInv07 - LN(1/rActivity))/rK` |
| 20 | FC_DL_VenturiScrubDpEst | PASS | PASS | PASS | — | 入库 |
| 21 | FC_DL_DemisterVelocityChk | PASS | PASS | PASS | — | 入库 |
| 22 | FC_DL_StackEmissionDilute | PASS | PASS | PASS | — | 入库 |
| 23 | FC_DL_ComponentRulEstimate | PASS | PASS | PASS | MINOR：\|slope\| 丢方向 | 补 slope>0 → 哨兵寿命 |
| 24 | FC_DL_BrgThermalDriftRate | PASS | PASS | PASS | — | 入库 |
| 25 | FC_DL_OilChangeInterval | PASS | PASS | PASS | — | 入库 |
| 26 | FC_DL_MtbfCalc | PASS | PASS | PASS | — | 入库 |
| 27 | FC_DL_SpareReorderPoint | PASS | PASS | PASS | — | 入库 |
| 28 | FC_DL_PmScheduleNext | PASS | PASS | PASS | — | 入库 |
| 29 | FC_DL_LubeIntervalCalc | PASS | PASS | PASS | — | 入库 |
| 30 | FC_DL_BiogasYieldCalc | PASS | PASS | PASS | — | 入库 |
| 31 | FC_DL_MethaneRatioCalc | PASS | PASS | **MAJOR** | L48-55 分量无负值闸 | CH4 可 >100%、LHV 超 35.8 物理上限；补逐分量 [0,100] 闸 |
| 32 | FC_DL_OrganicLoadRate | PASS | PASS | **MAJOR** | L54 COD 冒充 TS | VS 应由 TS×VS/TS 求，现用 COD → 低估 4 倍、bOver 不触发 |
| 33 | FC_DL_VfaAlkalinityRatio | PASS | PASS | PASS | — | 入库 |
| 34 | FC_DL_GasHolderLevel | PASS | PASS | PASS | — | 入库 |
| 35 | FC_DL_DigesterRetentionTime | PASS | PASS | PASS | MINOR：HRT 分母含排泥 | 口径已在头注声明，挂账 |
| 36 | FC_DL_FlareFlowSizing | PASS | PASS | PASS | — | 入库 |
| 37 | FB_DL_CoagDoseJarTestSeq | PASS | PASS | **MAJOR** | L313 eHold 冻结体积流量 | eHold 改出 `_rDoseCmd`（基准已保持），仅 eFault 用 LastGood |
| 38 | FB_DL_ScrewPressDewaterSeq | PASS | PASS | PASS | — | 入库 |
| 39 | FB_DL_ScrubberReagentDoseSeq | MAJOR→**改判 PASS** | PASS | PASS | R527@L222 假阳性（注释已声明累计看门狗） | 修 anchor 后入库 |
| 40 | FB_DL_AnaerobDigesterLoadCtrl | MAJOR→**改判 PASS** | PASS | PASS | R527@L222/226 假阳性 | 修 anchor 后入库 |

---

## 二、汇总

- **总数 40 ｜ L2 PASS 40 ｜ L2 FAIL 0 ｜ EXEMPT 0 ｜ 编译通过率 100%**
- **终裁：PASS 34 ｜ MAJOR（逻辑错值，须本轮修）6 ｜ FAIL 0 ｜ 逻辑一次通过率 85.0%**
- **首裁通过率（自愈前）= 40/40**：本轮**无需任何自愈**（E006/E007/E048/E052/METHOD 位置均零命中），stub_fix / iface_stub_gen / reorder_methods / fix_end_method **未执行**。
- **终裁通过率（自愈后）= 40/40 编译层不变；逻辑层 35/40。**
- 静态闸：BLOCK 0、MAJOR 2（均为 R527 假阳性，已改判）、MINOR 40（VER_HEADER）、WARN 26（DECL_UNKNOWN_TYPE，单件模式缺类型上下文，非件缺陷）。

> 口径澄清：编译闸 = 通过。**入库闸 = 需先修 5 件逻辑 MAJOR**。这 5 件不改逻辑也能编译，但会在合法输入下算出错值——这正是 R80/R81 的教训，我不放行。

---

## 三、FAIL 详情

**无编译 FAIL。** 40 件在 RuSTy 1.0.8 串行下全部 rc=0。

（首轮我误得 39 FAIL，原因是 xargs 后缀 `\r` 污染文件名导致"文件不存在"，非真实编译失败；已用 Python 传参重跑，40/40 PASS。此为**本席自身的工具调用事故**，记录在此以免后人复踩：Windows 下 `_paths.txt` 经 text-mode 写入为 CRLF，`cat|tr` 拼接会把 `\r` 带进文件名。）

---

## 四、EXEMPT 详情

**本轮 0 件豁免。** 不存在编译器不支持的合法 IEC 语法，无用 EXEMPT 掩盖缺陷的情况。

---

## 五、逻辑层抽检结论（12 件：4 FB + 8 FC）

| # | 件名 | 典型向量 | 期望 vs 代码 | 判定 |
|---|---|---|---|---|
| 1 | FC_DL_CatalystActivityDecay | k0=0.001/h, T=380, Tref=350, Kt=0.02, t=1000h | k=0.001822/h，act=0.1617；**物理 RUL=(LN(1/0.7)−LN(1/act))/k=−804h→0**；代码算出 **+1195.7h** | **MAJOR** |
| 1b | 同上，边界 | t=195h（act=0.7010，刚好到 70% 终点） | 物理 RUL=**0.7h≈0**；代码给 **390.7h** | **MAJOR** |
| 1c | 同上，边界 | act<0.7（已过寿命终点） | 加号使括号恒 ≥0.3567，**"rRulRaw<0 → 0" 分支永远走不到（死代码）** | **MAJOR** |
| 2 | FC_DL_OrganicLoadRate | Q=100 m3/d, COD=10000 mg/L, VS/TS=0.7, V=1000 m3 | 代码 VS=700 kg/d、OLR=0.70 kgVS/(m3·d)；按 TS=4%（40 kg/m3）应为 VS=2800、OLR=**2.80** | **MAJOR** |
| 2b | 同上，边界 | 上述叠加 V=500（真实 OLR=5.6 已过载） | 代码 OLR=1.4 → **bOver=FALSE，过载漏报**（阈值 5.0 永不触碰） | **MAJOR** |
| 3 | FC_DL_DewaterMassBalance | feed=100 m3/h, TS_in=2%, TS_cake=20% | cake=10 m3/h、滤液=90 m3/h ✓；**回收率 = cake·TS_c/(feed·TS_f)·100 ≡ 100.0，恒等式**（因 cake 就是由该式反解） | **MAJOR** |
| 3b | 同上，边界 | TS_in=2%, TS_cake=2.5%（几乎未脱水） | 代码仍报 **回收率 100%**，工程含义完全错误 | **MAJOR** |
| 4 | FC_DL_MethaneRatioCalc | CO2=35, N2=1, O2=0.3, H2S=200 | CH4=63.7%，LHV=22.8 MJ/m3 ✓ | PASS |
| 4b | 同上，边界 | CO2=−10（分析仪漂移）, N2=10, O2=0 | 代码 CH4=**100%**、LHV=**35.8**（=纯甲烷满值），bValid=TRUE | **MAJOR** |
| 5 | FC_DL_PackedBedHtu | G=10000 kg/h, Kga=150 kmol/(m3·h·atm), A=2 m2, NTU=4 | 代码 HTU=10000/29/(150·2)=**1.149 m**、H=5.52 m；Kga 单位含 **atm**，(kmol/h)/(kmol/(m3·h·atm)·m2)=**atm**，公式缺 P | **MAJOR**（1 atm 时无偏） |
| 5b | 同上，边界 | 塔压 0.95 atm（微负压洗涤塔） | 真值 1.090 m，代码 1.149 m，偏高 5.4%；液相流量仅作存在性闸，L/G 变化对 HTU 无影响 | **MAJOR** |
| 6 | FC_DL_SettleVelocityCalc | dp=50 µm, ρp=2650, ρf=1000, μ=1.0 mPa·s | v=9.80665·(50e-6)²·1650/(18·1e-3)=**2.25 mm/s**，Re=0.112<2 → bValid ✓ | PASS |
| 6b | 同上，边界 | dp=−50 µm | 平方后同 50 µm，bValid=TRUE（负粒径未闸） | MINOR |
| 7 | FC_DL_DigesterRetentionTime | V=3000, feed=100, waste=20 | HRT=3000/120=**25 d**（分母含排泥，教科书口径 V/Q进=30 d）；SRT=3000/22=136 d | PASS（口径已声明） |
| 7b | 同上，边界 | feed=100, waste=−500 | QTotal<0 → 码 1 拒算 ✓；waste=−50 → QOut<1e-9 → 码 2 兜底 ✓ | PASS |
| 8 | FC_DL_ComponentRulEstimate | health 100→92，Δ=500h，thr=60 | slope=−0.016 %/h，RUL=32/0.016=**2000 h** ✓，bAccel=TRUE ✓ | PASS |
| 8b | 同上，边界 | health 80→90（检修后回升），Δ=1000h | slope=+0.01，代码用 ABS → RUL=**3000 h**（视"变好"为"退化"）；方向丢失 | MINOR |
| 9 | FB_DL_CoagDoseJarTestSeq | base=20 mg/L, Q=100 m3/h, stock=10 g/L | 段 5：20×100/10=**200 L/h**；校验 20 mg/L×100000 L/h=2000 g/h ÷10 g/L=200 L/h ✓ 量纲正确 | PASS |
| 9b | 同上，边界 | 进 eHold 后流量 100→150 m3/h（基准确 20 mg/L） | eHold 出 `_rDoseLastGood`=200 L/h 冻结，实际投加率掉到 **13.3 mg/L**（-33%）；应出 `_rDoseCmd`=300 L/h | **MAJOR** |
| 9c | 同上，恢复路径 | stock=0 → 码 15 锁存 → 复位沿 | 残留条件 rStockGL<=EPS 仍在 → 不退出 ✓（电平进沿出，判据类型一致） | PASS |
| 10 | FB_DL_ScrewPressDewaterSeq | 段 2 运行期约束断言 → 码 27 fail-closed | 结构守 R7/R188/R191/R528；TON 全在 CASE 外无条件刷新 | PASS |
| 10b | 同上，边界 | 时间参数越域（tPress<MIN） | 两级回退到 `DL_SPR_T_PRESS_DEF`，不静默 ✓ | PASS |
| 11 | FB_DL_ScrubberReagentDoseSeq | piOut=Kp·err+Integ，限 [0, PumpMax]；泄漏 = 60s 窗边界单拍采样∧泵开 | 量纲 (L/h/pH)·pH+L/h=L/h ✓；泄漏判据为"窗边界采样"非电平，无重复置位 | PASS |
| 11b | 同上，边界 | pH 非法 | 码 35 锁存，泵出零，残留条件 `_bPhInvalid` 电平退出 ✓ | PASS |
| 12 | FB_DL_AnaerobDigesterLoadCtrl | VFA/Alk=0.35（HI=0.4），2 窗确认，步长 10% | 每窗只降一步（tonConfirm.Q 单拍脉冲，IN 带 NOT .Q）；限值×0.9 且地板 20% ✓ | PASS |
| 12b | 同上，边界 | 已到 20% 地板仍越限 | 码 48 故障锁存，段 7 流量归零 ✓（fail-closed 安全侧成立） | PASS |
| 12c | 同上，边界 | 回升相再越限 | `_iConfCnt:=0` + 立即降一步 + 回 eDerate ✓，计数容量与步进量匹配 | PASS |

---

## 六、库级共性缺陷与工具缺陷（需工具链修）

### 6.1 【工具缺陷·高优先】R527 假阳性：不读注释声明
`dl_gate.py:331-336` 的 R527 只做正则 `IN 实参含 OR 且 ≥2 个 e[A-Z]*`，**完全不看出现在同一行的声明注释**，而它自己的报错文案正是"须注释声明为累计看门狗或拆两个 TON"。本轮命中 3 处（Scrubber L222、AD L222/L226），三处注释都写着"跨相累计看门狗…非本相超时"，全部是假阳性。
- 涉及件数：2（3 命中）
- 建议修法：命中后截取该行 `//` 之后的文本，若含"累计看门狗 / Cumulative watchdog"则降为 INFO 或不再报。
- 风险：此锚点当前会把最规范写的件判为 MAJOR，**倒逼编码席删注释或拆 TON**，属于激励反转，必须修。

### 6.2 【工具缺陷·中优先】VER_HEADER 与全库头部约定不一致
`dl_gate.py:339` 要求 `VERSION: x.y.z`，但全库 **1681 个 .st 文件无一命中**（`grep -rl "VERSION:" --include=*.st` = 0），实际约定是 `版本: 1.0.0`（FB）或完全不写（FC）。
- 涉及件数：40（占 100%）；全库 1681 件同型
- 影响：该 MINOR 已退化为"恒定噪声"，掩盖真正的新增噪声
- 建议：正则改为 `(VERSION|版本)\s*[:：]`；FC 若无版本头则先补规范再开闸

### 6.3 【业务共性·逻辑】"差值法"输出未做恒等检测
`DewaterMassBalance` 的回收率、`CatalystActivityDecay` 的 RUL 属同一族：一个由定义反解出来的量又被当作独立指标输出，读者会误以为它是独立校验。
- 涉及件数：2
- 建议新增机检锚点 **R530_DERIVED_IDENTITY**：若 `VAR_OUTPUT` 的赋值表达式在代数上恒等于常数（回收率=100%、余量=0），报 MAJOR 提示"此输出无信息量"。

### 6.4 【业务共性·逻辑】浓度基准混用（COD 冒充 TS）
`OrganicLoadRate:54` 用 COD 浓度乘 VS/TS 比求 VS。COD 与 TS 是不同量纲的浓度，VS/TS 比只能作用于 TS。
- 涉及件数：1（同型风险件：`DigesterRetentionTime` 用固定 25 kgVS/m3 兜底，属已声明假设，不算缺陷）
- 建议新增机检锚点 **R531_RATIO_DIM_MISMATCH**：若某比率参数（名含 Ratio）被乘在语义不同的浓度变量上，且该浓度无 TS/SS 词根，报 MAJOR。

### 6.5 【业务共性·逻辑】单参数速率符号丢失
`ComponentRulEstimate:74` 用 `ABS(slope)` 求 RUL，把"健康度回升"当成"退化"。
- 涉及件数：1
- 建议锚点 **R532_RATE_SIGN_LOST**：`ABS(斜率) 作分母` 且无 `slope>0 → 哨兵/失效` 分支时报 MINOR。

---

## 七、裁决与放行

- **编译门（L1+L2）：40/40 通过，本轮零编译阻断。**
- **入库门：BLOCK 6 件** —— #14 DewaterMassBalance、#17 PackedBedHtu、#19 CatalystActivityDecay、#31 MethaneRatioCalc、#32 OrganicLoadRate、#37 FB_DL_CoagDoseJarTestSeq。**在编码席按第五节最小修法改完并重跑 `l2_check.py` 之前，注册脚本必须拒绝这 6 件写入 registry。**
- 其余 34 件：放行入库（含 3 件 MINOR 挂账：#3 SettleVelocityCalc、#23 ComponentRulEstimate、#35 DigesterRetentionTime）。
- 工具链：R527 假阳性修好之前，R527 的 MAJOR 结论**不得**用于阻断（本席已按人工复核改判）。
