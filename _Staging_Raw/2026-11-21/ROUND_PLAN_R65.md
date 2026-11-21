# ROUND_PLAN_R65（2026-11-21 23:39 锁定）

> 本轮特点：pipeline v2 首轮——写件 → `_tools/dl_gate.py --changed-only` → registry(origin) → JSONL → git commit。
> 配额：13 项 = 3 点修 + 10 新件（R64 收尾裁定「常态 10~13」，如实执行）。
> 召唤模式：原生 plc-programming-expert ×1 单调用；终审与收口由主控执行。

## 目标清单

| 批 | 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 类型 |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | FC_DL_StringEditDistance | DL_Base | FC_ | Levenshtein 编辑距离（配方名/批次号模糊匹配，滚动一行 DP，O(min) 内存） | t1-original | 6 | 新件 |
| 1 | 2 | FC_DL_StringWildMatch | DL_Base | FC_ | 通配符 * ? 匹配（报警过滤/点名匹配，迭代双指针无递归） | t1-original | 5 | 新件 |
| 1 | 3 | FC_DL_ArrFillEx | DL_Base | FC_ | LREAL 数组段填充（起止下标钳位、零长早退、非有限值拒绝） | lgf-datahandling | 4 | 新件 |
| 1 | 4 | FC_DL_ArrCopySeg | DL_Base | FC_ | LREAL 数组段拷贝（源/目标越界截断、零长早退、计数回报） | lgf-datahandling | 4 | 新件 |
| 2 | 5 | FC_DL_SortIndexInt | DL_Base | FC_ | INT 数组稳定排序索引（插入排序输出索引表，不改原数组） | lgf-datahandling | 5 | 新件 |
| 2 | 6 | FB_DL_HysteresisBandMon | DL_Base | FB_ | 带滞回区间监视（-1/0/+1 区间态 + 越带沿脉冲；与 FC_DL_Hysteresis 互引分工：点值计算 vs 状态监视） | lgf-comparator | 6 | 新件 |
| 2 | 7 | FC_DL_AngleUnitConvert | DL_MathData | FC_ | 角度单位换算 deg/rad/grad（模式枚举 + 非有限守卫） | t1-original | 3 | 新件 |
| 3 | 8 | FC_DL_TankVolumeHoriCyl | DL_Process | FC_ | 卧式圆柱罐解析体积（弦高→弓形面积公式；与 FB_DL_TankLevelStrapping 互引：解析法 vs 查表法） | t1-original | 5 | 新件 |
| 3 | 9 | FB_DL_AnalogSignalHealth | DL_Device | FB_ | 4-20mA 信号健康诊断（断线/超量程/卡滞三态 + 沿报警 + 复位） | lgf-measurement | 7 | 新件 |
| 4 | 10 | FB_DL_PneuCylinderDiag | DL_Device | FB_ | 双阀气缸行程诊断（伸出/缩回超时、中途卡滞、传感器矛盾） | lgf-device | 7 | 新件 |
| 4 | 11 | FB_DL_DualValveBlockSet | DL_Device | FB_ | v1.0.1 点修：tonMismatch 补相位闸（非运行相不计时）+ 残留蚀窗清账 | r64-终审挂账 | - | 点修 |
| 4 | 12 | FB_DL_ReworkLotGate | DL_Process | FB_ | v1.0.1 点修：eReleased 不回迁（放行后状态机应回迁待判相） | r64-终审挂账 | - | 点修 |
| 4 | 13 | FB_DL_UnscramblerSeq | DL_Base | FB_ | v1.0.1 点修：_bHold 跨相粘滞（离相清零） | r64-终审挂账 | - | 点修 |

## 红线（7 项，沿用 R45~R318 账本）

零 GVL/VAR_EXTERNAL、零 %I/%Q、纯 IEC 61131-3 跨平台、防除零/越界/浮点容差、变量同行中英双语注释、ENUM+CASE 含 ELSE 兜底、TON/R_TRIG 实例无条件周期刷新；重点防：漏 VAR_OUTPUT、注释嵌套 (* *)、枚举单冒号、隐性回夹、锁存副本与实时镜像混用、推进/超时同源无进展超时（R300）、失能相清零串使能（R303）。

## 收口承诺（主控执行）

gate --changed-only 全 PASS（方言待裁决 71 件遗留不计本轮）→ registry 注册（origin 必填）→ JSONL +13 → ROADMAP 勾选 → git commit → 文档增量 → 战报 → 飞书播报 → 删锁。
