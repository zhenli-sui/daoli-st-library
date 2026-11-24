# RAW_NOTES_R63 — 取源留痕（零检索轮）

> 时间：2026-11-21 ｜ WebSearch **0 次**（全程零检索，无新 URL 抓取）
> 本轮全部取材 = ①既有 `RAW_NOTES` 历史来源的延续深化（T1-8 / T2-1 两 ◐ 组）；②IEC 61131-3 标准语义（不构成版权文本）；③公开数学/统计/信号处理公式（公有领域知识，clean-room 重写，零代码行复制）。

---

## 1 按新件取源清单

| 组件 | 来源标签 | 出处 / 提取点 | 许可证 / 合规结论 |
|---|---|---|---|
| `FC_DL_BcdToDint` / `FC_DL_DintToBcd` | `iec-std-wrapper` | IEC 61131-3:2013 标准转换语义 + BCD 8421 码公有领域编码规则；与既有 `FC_DL_BcdToByte/BcdToWord/BcdToUdint` 同族口径（T0-5 BCD 族 DWORD 位宽补口） | 无第三方代码；clean-room，可商用 |
| `FB_DL_EwmaFilter` | `self` | 公开 EWMA（指数加权移动平均）递推公式 `y←y+α(x−y)`（ Hunter 1956 类公有领域统计公式）；α 直接入参口径为本库原创组织 | 公有领域公式；clean-room，可商用 |
| `FC_DL_TrimmedMeanCalc` | `iec-std-wrapper` | 截尾均值（trimmed mean）公开统计定义；实现沿用本库既有委托链（`FC_DL_SortIndexLReal`） | 公有领域定义；clean-room，可商用 |
| `FC_DL_PearsonCorrCalc` | `iec-std-wrapper` | 皮尔逊积矩相关系数公开公式（Pearson 1890s 公有领域）；配对剔除/退化防护为本库防御口径 | 公有领域公式；clean-room，可商用 |
| `FC_DL_BiquadCoeff` | `dsp-public-cookbook`（T1-8 ◐ 深化） | 公开二阶节设计公式（RBJ Audio EQ Cookbook 类公开公式结构）：w0=2π·f0/fs、α=sin(w0)/2Q 及四型分子/分母系数式——只借公式结构，系数式/闸门/码位 100% 自有（R62 BiquadFilter 同源合规口径延续） | 公开公式，无代码行；clean-room，可商用 |
| `FB_DL_OutlierFilter` | `self` | MAD（中位绝对偏差）+ 1.4826 一致性因子（正态一致性常数，公有领域）；「连续半窗拒绝→判真阶跃重基线」为本库原创处置口径 | 公有领域公式；clean-room，可商用 |
| `FB_DL_BiquadCascade` | `dsp-public-cookbook`（T1-8 ◐ 深化） | R62 RAW_NOTES_R62 已登记「多节级联待挖」方向；Direct Form II 节结构为教科书公有领域；逐节 Jury 稳定闸为 R63 返修 R2 固化判据 | 公有领域结构；clean-room，可商用 |
| `FB_DL_AdaptiveLmsFilter` | `dsp-public-cookbook`（T1-8 ◐ 深化） | LMS 算法（Widrow–Hoff 1960 公开算法结构）：`w[k]+=2μ·e·x[k]`；延迟线/权重冻结/发散监视为本库防御组织（T1-8 组 R62 登记的「自适应待挖」方向承接） | 公开算法结构，零代码行；clean-room，可商用 |
| `FB_DL_AdcNoiseFloorWatch` | `lgf-measurement`（T2-1 ◐ 深化） | 沿用 R62 `FB_DL_VfdDcBusRipple` 同款「均值/两级统计 + 双限值迟滞判据」的组织方式（LGF Measurement 分类骨架借鉴，零代码行）；标准差为公有领域统计量 | 只借分类组织；clean-room，可商用 |
| `FB_DL_VfdOutputImbalance` | `lgf-measurement`（T2-1 ◐ 深化） | 同上组织方式借鉴；不平衡度 `(Imax−Imin)/Iavg×100` 与断相 `Imin<Iavg×(1−k)` 为公开电气监视判据常识 | 只借分类组织；clean-room，可商用 |
| `FB_DL_VfdCapAgingEst` | `lgf-measurement`（T2-1 ◐ 深化） | 电解电容容值衰减→纹波率爬升为公开运维常识；「基线比值 + 迟滞」结构沿用本库 R62 Measurement 骨架 | 只借分类组织；clean-room，可商用 |
| `FB_DL_VfdPrechargeSeq` | `lgf-measurement`（T2-1 ◐ 深化） | 预充回路「反馈窗 + 斜率 + 总时限」三闸为公开变频启动保护常识；状态机组织沿用本库 `FB_DL_RailPowerSequence` / `FB_DL_AirShowerInterlockSeq` 既有范式（self 延续） | 公开常识 + 自有范式；clean-room，可商用 |

## 2 返修 5 件取源

全部为**内部缺陷台账**（`REVIEW_R62.md` R62-D1~D5/D7），无外部取源；Jury 稳定判据（`|a2|<1 ∧ 1+a1+a2>0 ∧ 1−a1+a2>0`）为经典 Jury 判据公有领域数学。

## 3 扩面复核取源

纯文本锚定扫查（Grep `C:\Library\DL_Algo` / `DL_Device` 相关 `.st`），无外部取源；扫查锚点与逐件结论见 `ROUND_PLAN_R63.md` §3。

## 4 拒单实测留痕

`FC_DL_ShlDwordEx`/`FC_DL_ShrDwordEx` 同义实测：`C:\Library\DL_Base\FC_DL_ShlEx.st` 头注释「支持位宽 (Width Note)：本件按 DWORD（32 位）主类型实现」——R62 转办项定案：同义，拒立项。

---

*R63 零检索轮台账 ｜ 道莅工控代码库产品总监 ｜ 合规：全轮零代码行复制，闭源源零触碰*
