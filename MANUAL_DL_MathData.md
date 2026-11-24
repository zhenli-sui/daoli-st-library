
## R24 批次追加（2026-11-17 ｜ 行业纵深轮：本子库新增 3 件 + 修复件 0 件）

### FC_DL_Affine2DCompose（函数 FC，）｜ v1.0.0

- **功能**：两片 3x3 仿射矩阵按「先施加 M1、后施加 M2」的次序合成为单片
- **码位带**：16#0001_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `afM1` | ARRAY[0..2, 0..2] OF LREAL | 先施加的变换矩阵 M1 [无量纲+用户单位混合]，行主序 |
| INPUT | `afM2` | ARRAY[0..2, 0..2] OF LREAL | 后施加的变换矩阵 M2 [无量纲+用户单位混合]，行主序 |
| OUTPUT | `afMOut` | ARRAY[0..2, 0..2] OF LREAL | 合成矩阵 MOut = M2 x M1 [无量纲+用户单位混合] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0001_0466 起信息级、16#0001_03B7 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 结果可用标志 |

### FC_DL_Affine2Apply（函数 FC，）｜ v1.0.0

- **功能**：单片 3x3 仿射矩阵对单点坐标 (x, y) 应用变换，p' = M x [x, y, 1]^T
- **码位带**：16#0001_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `afM` | ARRAY[0..2, 0..2] OF LREAL | 仿射变换矩阵 [无量纲+用户单位混合]，行主序，p' = M x p |
| INPUT | `fX` | LREAL | 源点 X [用户单位] |
| INPUT | `fY` | LREAL | 源点 Y [用户单位] |
| OUTPUT | `fOutX` | LREAL | 变换后 X [用户单位] |
| OUTPUT | `fOutY` | LREAL | 变换后 Y [用户单位] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0001_0469 起信息级、16#0001_03B9 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 结果可用标志 |

### FC_DL_FanLawRootCalc（函数 FC，）｜ v1.0.0

- **功能**：风机相似定律（Fan Affinity Laws）双向换算：
- **码位带**：16#0001_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `fSpeedRatio` | LREAL := 1.0 | 转速比 N2/N1 [比值]，正向模式输入，有效域 0.1..5.0，域外钳位照算 |
| INPUT | `fFlowRatio` | LREAL := 1.0 | 流量比 Q2/Q1 [比值]，反向模式输入，须 > 0（负开方域闸） |
| INPUT | `xReverse` | BOOL  := FALSE | FALSE = 由转速比正算三参数；TRUE = 由流量比反算转速比（开方域） |
| INPUT | `fQ1` | LREAL := 0.0 | 基准工况流量 [立方米每小时] |
| INPUT | `fP1` | LREAL := 0.0 | 基准工况全压 [帕] |
| INPUT | `fW1` | LREAL := 0.0 | 基准工况轴功率 [千瓦] |
| OUTPUT | `fSpeedRatioOut` | LREAL | 生效转速比 [比值]（含钳位后值） |
| OUTPUT | `fQ2` | LREAL | 换算流量 [立方米每小时] |
| OUTPUT | `fP2` | LREAL | 换算全压 [帕] |
| OUTPUT | `fW2` | LREAL | 换算轴功率 [千瓦] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0001_046C 起信息级、16#0001_03BB 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 结果可用标志 |


## R27 新增接口表（2 件 · 2026-11-17）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FC_DL_OrificeFlowCalc` | FC | IN `fDiffPress_Pa`/`fAbsPress_Pa`/`fTemp_C`/`fKCoefficient`/`fFlowRangeMax`；OUT `fFlow_m3h`/`eError` | 孔板差压流量：密度委托 AirDensity、开方委托 NthRoot(2)，越界钳制、差压负判故障 |
| `FC_DL_WaferCountYield` | FC | IN `uInputCnt`/`uOutputGood`/`uReworkCnt`；OUT `fYieldPct`/`eGrade`/`bValid`/`eError` | 三计数良率与 A~D 分档，无符号减法先验下界防下溢，投入为 0 拒算 |
