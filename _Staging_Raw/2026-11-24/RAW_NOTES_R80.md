# RAW_NOTES R80 — 来源表（2026-11-24）

通道：`codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/{main|master}`（整仓下载，零 REST 配额）。
下载落盘：`%TEMP%\r80\*.tgz` → 解包 `x/`。**注意**：Git Bash 的 `/tmp` 与 Windows 原生 Python 的 `/tmp` 不是同一路径，
给 python 的路径必须用 `cygpath -w` 结果（本轮踩坑 1 次，空扫描）。

## 来源表

| 源 | 许可 | 提取点 | 入队名 | tier |
|---|---|---|---|---|
| menes97/ayran-mini-fabrika `plc/src/FB_Dolum.st` | MIT | 8 工位回转链节拍 + 每杯移位寄存器 + 剔除工位 | FB_DL_CupFillSealIndexer | green |
| 同上 `FB_Dolum.st#PREACT` | MIT | 粗/细流切点 + PREACT/COARSE_MARGIN 自学习（下落量补偿） | FB_DL_FillPreactSelfLearn | green |
| 同上 `FB_Tank.st` | MIT | 液位 40/80 双点滞环 + PRODUCT_REQ 供需握手 | FB_DL_TankDemandHysteresis | green |
| 同上 `FB_Asrs.st` | MIT | ack_seq/res_seq 货位分配握手状态机 | FB_DL_AsrsSlotAllocSeq | green |
| 同上 `FB_Agv.st` | MIT | 电量阈值机会充电 + D_READY/IN_READY 对接 | FB_DL_AgvOppChargeDock | green |
| 同上 `FB_Shrink.st` | MIT | 多通道节拍均衡 + 膜/垫料消耗 + PLATE 位图 | FB_DL_ShrinkFilmLaneBalance | green |
| 同上 `FB_Pallet.st` | MIT | 槽位作业队列 + 机器人 ack + turns 奇偶层 | FB_DL_PalletSlotJobQueue | green |
| ThorstenBrach/SRCI_CLIENT_PLC `POUs/Additional/MC_AvoidSingularity` | MIT | 奇异判定 + 逃逸方向状态机相序 | FB_DL_RobotSingularityGuard | green |
| 同上 `MC_CollisionDetection` | MIT | ProcessingMode×SequenceFlag 组合 + Aborting 路径 | FB_DL_RobotCollisionZoneGuard | green |
| 同上 `MC_BrakeTest` | MIT | 制动测试时序（加载-保持-位置差判据） | FB_DL_BrakeHoldTestSeq | green |
| 同上 `Path/MC_PathAccuracyMode` | MIT | 路径精度/过渡档位语义与参数域 | FB_DL_PathAccuracyBlendMode | green |
| 同上 `MC_SoftSwitchTcp` | MIT | 软限位表结构与越界抑制语义 | FB_DL_TcpSoftLimitGuard | green |
| 同上 `MC_ShiftPosition` | MIT | 位姿偏移增量/绝对叠加与复位 | FB_DL_ToolFrameShift | green |
| 同上 `MC_MeasuringInput` | MIT | 探针锁存窗口：布防-触发-锁存-读取 | FB_DL_MeasureInputLatch | green |
| 同上 `MC_FreeDrive` | MIT | 自由驱动进入/退出握手 + 使能丢失 | FB_DL_FreeDriveHandback | green |

## 拒收 / 未出料

| 源 | 原因 |
|---|---|
| MrLostInTheInternet/FluidPyPLC | **GPL-3.0 红区**，0 行代码；仅记思想：气动 A+/B-/C+ 序列按「缸位反馈一致才算完成」推进 |
| guicasagrandem/OEE_Calculator_S7-1200 | 无 LICENSE（unknown）+ TIA 二进制工程，无文本块 |
| kibelin/TIA-Portal-Chiller-Control-System | 无 LICENSE（unknown）+ TIA 二进制工程 |
| mrvluiz/OEE | 无 LICENSE（unknown）+ TIA 二进制工程 |
| WengerAG/structured-text-utilities | MIT 但内容与 T0-6 字符串/时间族饱和重合，无增量 |
| Aliazzzz/* (2 仓)、MichielVanwelsenaere/HomeAutomation | 无独立文本 ST 块（工程导出包） |
