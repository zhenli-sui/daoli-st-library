# ROUND_PLAN_R76 — 2026-11-23 15:54 起（冲刺模式：复杂≤4，简单≥36）

> 冲刺触发：当日 85/300（28.3%），远低于轮次进度 → 复杂件上限降为 4，其余全部简单件。
> 简单件按族模板派生：5 族 / 36 件，编码席**一次调用批量写盘**（严禁一件一调用）。
> 撞名三查：全部 40 个名称对 INDEX_REGISTRY（1,288 条）实时精确匹配 + 语义邻件人工比对，初始 5 个撞名已改名（BitCountOnes→BitCountTransitions、WrapAngleDeg 系→AngleUnwrapStep、GrayToBin→BitSwapPairs、WordToBytes→BitFillLowestZero、PumpCavitationGuard→ChillerDoorPurgeSeq）。

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | FB_DL_BrakeReleaseInterlock | DL_Motion | FB_DL_ | 伺服抱闸释放互锁：力矩确认+释放超时+故障码+状态机 | oscat-semantic | C3 | B0 | 复杂 |
| 2 | FB_DL_HeaterBankLoadBalance | DL_Device | FB_DL_ | 加热器组负载均衡轮换：累计工时排序选主+超温降额 | oscat-semantic | C3 | B0 | 复杂 |
| 3 | FB_DL_ChillerDoorPurgeSeq | DL_Process | FB_DL_ | 冷机检修门吹扫联锁时序：门位/风压/延时/异常回退 | oscat-semantic | C3 | B0 | 复杂 |
| 4 | FB_DL_AnalogDriftWatch | DL_Device | FB_DL_ | 模拟量双通道漂移监测：偏差积分+分级报警+校验 | clean-room | C3 | B0 | 复杂 |
| 5 | FC_DL_BitMaskRange | DL_Base | FC_DL_ | 由 bitLo..bitHi 构造 DWORD 掩码（越界钳位） | oscat-semantic | C1 | B1 | 简单 |
| 6 | FC_DL_BitReverse8 | DL_Base | FC_DL_ | BYTE 位序完全反转 | oscat-semantic | C1 | B1 | 简单 |
| 7 | FC_DL_BitReverse16 | DL_Base | FC_DL_ | WORD 位序完全反转 | oscat-semantic | C1 | B1 | 简单 |
| 8 | FC_DL_BitRunLength | DL_Base | FC_DL_ | 最长连续 1 游程长度与起始位 | clean-room | C2 | B1 | 简单 |
| 9 | FC_DL_BitLowestSet | DL_Base | FC_DL_ | 最低置位位号与单比特隔离值 | oscat-semantic | C1 | B1 | 简单 |
| 10 | FC_DL_BitSwapPairs | DL_Base | FC_DL_ | 相邻比特对交换（BYTE 内 4 对） | clean-room | C1 | B1 | 简单 |
| 11 | FC_DL_BitCountTransitions | DL_Base | FC_DL_ | WORD 位跳变次数统计（0→1 与 1→0 分计） | clean-room | C2 | B1 | 简单 |
| 12 | FC_DL_BitFillLowestZero | DL_Base | FC_DL_ | 最低 0 位填 1 并回传该位号 | clean-room | C1 | B1 | 简单 |
| 13 | FC_DL_AngleDiffDeg | DL_MathData | FC_DL_ | 两角度差归一到 [-180,180) | oscat-semantic | C2 | B2 | 简单 |
| 14 | FC_DL_AngleLerpShort | DL_MathData | FC_DL_ | 最短弧角度插值（跨 0/360 正确） | oscat-semantic | C2 | B2 | 简单 |
| 15 | FC_DL_AngleQuadrant | DL_MathData | FC_DL_ | 象限判定 0..3 + 轴上标志 | clean-room | C1 | B2 | 简单 |
| 16 | FC_DL_AngleBisector | DL_MathData | FC_DL_ | 两角平分线（钝角取短弧中点） | clean-room | C2 | B2 | 简单 |
| 17 | FC_DL_AngleToCompass | DL_MathData | FC_DL_ | 方位角→16 方位码 + 中文向名索引 | clean-room | C1 | B2 | 简单 |
| 18 | FC_DL_AngleTolInside | DL_MathData | FC_DL_ | 角度容差窗口判定（跨 0° 正确） | clean-room | C2 | B2 | 简单 |
| 19 | FC_DL_AngleReflect | DL_MathData | FC_DL_ | 关于轴线角镜像反射并归一 | clean-room | C1 | B2 | 简单 |
| 20 | FC_DL_AngleUnwrapStep | DL_MathData | FC_DL_ | 增量解卷绕累加（连续多圈跟踪） | oscat-semantic | C2 | B2 | 简单 |
| 21 | FC_DL_BytesToWord | DL_Base | FC_DL_ | 2 字节按指定序组装 WORD | oscat-semantic | C1 | B3 | 简单 |
| 22 | FC_DL_DwordToWords | DL_Base | FC_DL_ | DWORD 拆 2 WORD（高低序可选） | oscat-semantic | C1 | B3 | 简单 |
| 23 | FC_DL_WordsToDword | DL_Base | FC_DL_ | 2 WORD 合成 DWORD（高低序可选） | oscat-semantic | C1 | B3 | 简单 |
| 24 | FC_DL_EndianProbe | DL_Base | FC_DL_ | 运行期字节序探针（大端/小端判定） | clean-room | C2 | B3 | 简单 |
| 25 | FC_DL_LwordToDwords | DL_Base | FC_DL_ | LWORD 拆 2 DWORD（序可选） | clean-room | C1 | B3 | 简单 |
| 26 | FC_DL_DwordsToLword | DL_Base | FC_DL_ | 2 DWORD 合 LWORD（序可选） | clean-room | C1 | B3 | 简单 |
| 27 | FC_DL_SinDeg | DL_MathData | FC_DL_ | 角度制正弦（内部转弧度） | oscat-semantic | C1 | B4 | 简单 |
| 28 | FC_DL_CosDeg | DL_MathData | FC_DL_ | 角度制余弦 | oscat-semantic | C1 | B4 | 简单 |
| 29 | FC_DL_TanDegChk | DL_MathData | FC_DL_ | 角度制正切 + 90° 邻域钳位与有效位 | oscat-semantic | C2 | B4 | 简单 |
| 30 | FC_DL_AsinDegChk | DL_MathData | FC_DL_ | 反正弦→角度 + 定义域钳位 | oscat-semantic | C1 | B4 | 简单 |
| 31 | FC_DL_AcosDegChk | DL_MathData | FC_DL_ | 反余弦→角度 + 定义域钳位 | oscat-semantic | C1 | B4 | 简单 |
| 32 | FC_DL_Atan2Deg | DL_MathData | FC_DL_ | 四象限反正切→角度（含 0,0 兜底） | oscat-semantic | C2 | B4 | 简单 |
| 33 | FC_DL_SincSafe | DL_MathData | FC_DL_ | sinc(x)=sin(x)/x，x→0 用泰勒展开 | clean-room | C2 | B4 | 简单 |
| 34 | FC_DL_HypotChk | DL_MathData | FC_DL_ | 2D 斜边（防溢出缩放算法）+ 有效性 | clean-room | C2 | B4 | 简单 |
| 35 | FC_DL_HystWindow3 | DL_Algo | FC_DL_ | 三带迟滞窗口（低/中/高，双阈值带回差） | oscat-semantic | C2 | B5 | 简单 |
| 36 | FC_DL_HystLatchAlarm | DL_Algo | FC_DL_ | 迟滞 + 报警锁存（需外部复位） | clean-room | C2 | B5 | 简单 |
| 37 | FC_DL_HystCounterStep | DL_Algo | FC_DL_ | 迟滞跨带计数器（上穿+1/下穿-1，限幅） | clean-room | C2 | B5 | 简单 |
| 38 | FC_DL_HystTimeQualified | DL_Algo | FC_DL_ | 迟滞 + 时间确认（持续满足才翻转） | clean-room | C2 | B5 | 简单 |
| 39 | FC_DL_ClampDintChk | DL_Algo | FC_DL_ | DINT 限幅 + 越界方向标志 | oscat-semantic | C1 | B5 | 简单 |
| 40 | FC_DL_WrapToRange | DL_Algo | FC_DL_ | REAL 周期量卷绕到 [lo,hi)（防除零） | clean-room | C2 | B5 | 简单 |

## 分档统计
- 复杂（C3）：4 件（序号 1~4）
- 简单（C1~C2）：36 件（序号 5~40），5 族：位运算 8 / 角度 8 / 字节序 6 / 三角 8 / 迟滞限幅 6
- 存量修复名额：0（当日非首轮，铁律 1）

## 批次编排
- B0（复杂 4）：一次派发
- B1~B5（简单 36）：**两次派发**（B1+B2 共 16 件一次；B3+B4+B5 共 20 件一次），同族连号顺序写盘
- 入库串行；L2 闸串行 jobs=1
