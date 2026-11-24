# RAW_NOTES_R64（R64 选源留痕｜2026-11-21｜零检索轮，WebSearch 0 次）

> 本轮全部取材为「内部来源零检索」+「既有源矩阵 ◐ 组 clean-room 借骨」，无任何新抓取代码文件入 `_Staging_Raw`。

## 1 选源记录

| # | 组件名 | 来源标签 | 来源 / URL | 许可证 | 提取点 | 合规结论 |
|---|---|---|---|---|---|---|
| 1 | FC_DL_TriStateCompare | lgf-comparator（T2-1 ◐） | 西门子 LGF V5.3.0（文档 ID 109479728）Comparator 组功能分类骨架（闭源免费） | 闭源版权——**只借骨不抄肉** | 仅借「比较结果归一化分级」分类事实与接口参数域；实现 clean-room（fEps 容差判据独立推导） | 零代码复制，可商用 |
| 2 | FC_DL_ArrayFindValue | lgf-datahandling（T2-1 ◐） | 同上 Data Handling 组「数组搜索」子族骨架 | 同上 | 仅借「无序线性查找 + 首/末/计数三口径」功能分类；实现 clean-room | 零代码复制，可商用 |
| 3 | FC_DL_GcdUdintCalc | T0 数论原子（内部来源） | 零检索；欧几里得算法为公共领域数学事实 | —（数学事实） | WHILE 迭代 + DL_GUARD_MAX 守卫计数，道莅防御性范式 | 可商用 |
| 4 | FC_DL_IntervalGapCalc | lgf-comparator（T2-1 ◐） | 同 #1 | 同 #1 | 仅借「区间关系」分类事实（R11 RangeOverlapCheck 同组既有件互引）；间隙计算 clean-room | 零代码复制，可商用 |
| 5 | FC_DL_ArraySliceCopy | lgf-datahandling（T2-1 ◐） | 同 #2 | 同 #2 | 仅借「定长缓冲搬运（无动态内存）」分类学口径（R12 结论沿用）；实现 clean-room | 零代码复制，可商用 |
| 6 | FC_DL_FlowUnitConvert | T0-4 单位换算族补口（内部来源） | 零检索；换算因子取 NIST 公开物理常数口径 | —（公开常数） | 与 FC_DL_TempUnitConvert / PressUnitConvert 同族骨架复用（本库自有范式） | 可商用 |
| 7 | FC_DL_RunningSumCalc | T0 统计族补口（内部来源） | 零检索；Kahan 补偿求和为公共领域算法（Kahan 1965） | —（公共领域） | 增量式运行口径 + 非有限闸为本库扩展 | 可商用 |
| 8 | FB_DL_DualValveBlockSet | T2-2 LBP 次源 | 西门子 LBP（免费闭源）阀特性「设备工艺参数」组织方式（R26 沿用） | 闭源版权——只借骨不抄肉 | 仅借「命令-监视-判定」三段分层组织方式；双阀不一致窗判据 clean-room | 零代码复制，可商用 |
| 9 | FB_DL_ReworkLotGate | T2-8 ISA-88 / T2-7 PackML 纪律次源 + 自研 | ISA-88 批次相状态模型（公开条款，R12 沿用）；零检索 | —（公开标准条款引用） | 仅借「批次相语义」状态命名组织；返工闸逻辑完全自研 | 可商用 |
| 10 | FB_DL_UnscramblerSeq | T2-7 PackML 相语义次源 + 自研 | OMAC PackML 状态模型（公开条款） | —（公开标准） | 仅借 17 态模型的相语义聚合口径；理瓶顺控自研 | 可商用 |

## 2 点修件（无新选源，R63 挂账承接）

- `FB_DL_VfdPrechargeSeq` / `FB_DL_AdaptiveLmsFilter`：缺陷描述与锚点全取自 `REVIEW_R63.md` S2/S3 节 + 现行源码实测行号（L142 / L220-246 / L144 / L161 / L196-205 / L211-218），零检索。

## 3 矩阵陈旧行实测记录（供 R64 收口订正）

- T2-1 Data Handling 行备注「CRC-16 反射 / LWORD 累加和待挖」**已失效**：registry 实测 `FC_DL_Crc16Generic` / `Crc16Ccitt` / `Crc16Modbus` / `FC_DL_ChecksumLwordSum` 均已注册，两候选按三查拒单。
- T2-1 Math 行备注「三角/极分解仍待挖」**部分失效**：`FC_DL_PolarDecomp2D` / `PolarTransform2D` / `Affine2DChain` 已注册。

---

*R64 阶段一 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监 ｜ 零检索轮（WebSearch 0 次）*
