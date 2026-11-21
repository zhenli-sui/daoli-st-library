# R32 原始备注（RAW_NOTES_R32）· 2026-11-18 零检索轮

## 1 本轮零检索说明

- **WebSearch 使用 0/3 次**。选题全部来自三类既有来源：① T0 变体线（IEC 61131-3 标准语义 clean-room 防御性包装，file 头溯源统一写「IEC 61131-3 标准语义的道莅防御性实现」，严禁重实现数学内核）；② ROADMAP §23/§24 与 R24/R25 增补段既有挂账条目；③ SOURCE_HUNTING_MATRIX 第 5 节 ◐ 行既有「待挖」备注（借行为定义，零代码行、零符号名复制）。
- 唯一剔除换件：`FB_DL_EnthalpyPrioritySwitchover` 与存量 `FB_DL_EnthalpyChangeover` 同义（R148 同义查命中），换为 `FB_DL_BlindPositionCtrl`（OSCAT Building BLIND 行为定义，未开挖）。
- 全部 20 名已对 INDEX_REGISTRY.json（558 名）+ `C:\Library\DL_*\` 目录文件名双查，零同名零同义撞车。

## 2 逐件账目

| 序号 | 组件名 | 来源标签 | 提取点（借了什么语义） | 许可证口径 | clean-room 声明 |
|---|---|---|---|---|---|
| 1 | FC_DL_StringToUpperEx | T0 变体线 | 仅借 IEC 标准字符串语义 + ASCII 大小写映射公开事实（Unicode-ASCII 码表为公有领域事实） | 公有领域事实，无许可依赖 | 100% 自研，零外部代码 |
| 2 | FC_DL_StringStripCharsEx | T0 变体线 | 仅借「trim 语义推广到自定义字符集」的公开惯例 | 公有领域语义 | 100% 自研 |
| 3 | FC_DL_BytesToHexString | T0 变体线 | 仅借 hex 编码公开事实（ nibble→字符映射） | 公有领域事实 | 100% 自研 |
| 4 | FC_DL_HexStringToLword | T0 变体线 | 仅借 hex 解析语义与三闸防御结构（非法字符/溢出/奇偶长度），同族内部先例 HexStringToBytes | 公有领域语义 | 100% 自研 |
| 5 | FC_DL_ReverseBitsWord | T0 变体线 | 仅借位反转公开算法事实（分治交换/查表两种实现，选分治） | 公有领域算法 | 100% 自研 |
| 6 | FC_DL_DtAddSecondsSat | T0 变体线 | 仅借 IEC DT 语义 + R81「反解不饱和、正解可饱和」纪律（本件为正解方向，饱和 + 故障级） | 公有领域语义 | 100% 自研；纪元口径沿用库内 DtToDintEpoch 属主 |
| 7 | FC_DL_DivDintSafeChk | T0 变体线 | 仅借 DivLrealSafe 库内防御结构先例（除零哨兵 + 标志） | 公有领域语义 | 100% 自研，复用库内错误码风格 |
| 8 | FC_DL_ModLrealSafe | T0 变体线 | 仅借取模语义 + 非有限闸纪律（R133/R135） | 公有领域语义 | 100% 自研 |
| 9 | FB_DL_SteamTrapDiagTrend | ROADMAP §24.2 P1 | 只借「趋势累积 + 分级判定」通用诊断范式，前置件 SteamTrapMonitor 为库内属主 | 自研（库内组合） | 100% 自研 |
| 10 | FB_DL_ColumnDpSteadyWatch | ROADMAP §24.2 P1 | 只借「稳态窗学习 + 偏差预判」范式，压差调节属主 ColumnDpCtrl | 自研（库内组合） | 100% 自研 |
| 11 | FC_DL_BitArrayReverse | T2-1 LGF Bit Logic（◐ 待挖） | 只借「位数组段操作」的段语义组织方式，不复制 LGF 任何函数体/名 | GPL 只读（LGF 为公开源码，仅借语义，不引实现） | clean-room，零行复制 |
| 12 | FB_DL_VavCouplingFeedforward | T1-2 OSCAT Building（ROOM_CONTROL 待挖） | 只借「送风温度-风量耦合前馈」行为定义与参数域 | LGPL 只读（OSCAT 协议，借语义不借实现） | clean-room，常数/符号名 100% 自有 |
| 13 | FB_DL_BlindPositionCtrl | T1-2 OSCAT Building（BLIND 待挖） | 只借「光照目标 + 风雨联锁 + 行程时间标定」行为定义 | LGPL 只读 | clean-room |
| 14 | FB_DL_CompressorFleetStaging | 行业池自研线 | 工程惯例（母管压力带控制、轮值防同时启停），无具体开源源 | 不适用 | 100% 自研；TRUNC 进位点按 R149 两式终审 |
| 15 | FB_DL_AhuSupplyAirReset | 行业池自研线 | ASHRAE 串级重置公开工程惯例（公开标准条款可引用） | 公开标准条款，只借条款不借文本 | 100% 自研 |
| 16 | FB_DL_BatteryModuleBalanceMonitor | 行业池自研线 | 电池管理公开常识（压差均衡分级），无开源源 | 不适用 | 100% 自研；哨兵可区分性按 R25 P2 纪律 |
| 17 | FB_DL_WaferThermalBudgetAccum | 行业池自研线 | Arrhenius 加权为公开物理事实；量纲链头注释结构按 R25 P2 模板化条目落地 | 公有领域物理事实 | 100% 自研 |
| 18 | FB_DL_CaseSealerFlapFoldSeq | 行业池自研线 | 包装机械折盖时序工程惯例，无开源源 | 不适用 | 100% 自研 |
| 19 | FB_DL_NitrideFurnaceAmmoniaPurge | ROADMAP R24 增补 | 氨分解率判据为公开工艺事实，吹扫顺控按 T2-7「最小子集 + 明确终止态」组织 | 公开工艺事实 | 100% 自研 |
| 20 | FB_DL_BusbarWeldMonitor | ROADMAP R24 增补 | 三维能量包络窗机制（功率-振幅-时间），与 LaserTabWeldTrack 为不同物理域，机制借鉴库内自身 | 自研（库内组合） | 100% 自研 |

## 3 矩阵回写建议表（收口轮执行，规划线只留建议）

| 矩阵行 | 建议动作 | 追加备注内容 |
|---|---|---|
| T0 变体线（第 5 节 T0 行） | 备注追加 | R32 收口 8 件 T0 原子：字符串 4（ToUpperEx/StripCharsEx/BytesToHexString/HexStringToLword）+ 位串 1（ReverseBitsWord）+ 日历 1（DtAddSecondsSat）+ 数学安全 2（DivDintSafeChk/ModLrealSafe）；全部防御性包装，零数学内核重实现 |
| T2-1 LGF · Bit Logic | 备注追加 | R32 深化 1 件：BitArrayReverse（位数组段镜像），行保持 ◐ |
| T1-2 OSCAT Building | 备注追加 | R32 深化 2 件：VavCouplingFeedforward（ROOM_CONTROL 待挖三项之一收口）+ BlindPositionCtrl（BLIND 行为定义开借）；ROOM_CONTROL 余两项（夜间吹扫已由 NightPurgeCtrl 覆盖、焓值切换已由 EnthalpyChangeover 覆盖）→ 建议子族标注「✔ 子族收口候选，收口轮核定」 |
| ROADMAP 引用行（§6） | 不动 | 本轮 4 件（序号 9/10/19/20）为 ROADMAP 挂账勾销件，由收口轮按 R164 registry 反查回写勾选，规划线不代勾 |
| 半导体 ESC 自研线 | 备注追加 | R32 深化 1 件：WaferThermalBudgetAccum（热预算累计，量纲链模板首个落地件） |

*R32 规划线 ｜ 2026-11-18 ｜ 逐件账目供收口轮与审计追溯*
