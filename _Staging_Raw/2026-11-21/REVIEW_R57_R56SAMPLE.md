# R57 五抽终审报告（R56 批次抽样，2026-11-21）

**总结：严重 1 / 中 2 / 轻 2 / PASS 1**
抽件：FC_DL_Kalman2DSmoother、FB_DL_TwoDofPid、FB_DL_LossInWeightFeeder（指定必审）+ FB_DL_AxisAccelFeedforward、FB_DL_HydraulicAccumPreChg（自选复杂件）。七项红线五件全部通过；缺陷集中在语义/诊断保真层。

| 名称 | 严重度 | 位置(行) | 现象 | 修法建议 |
|---|---|---|---|---|
| FB_DL_LossInWeightFeeder | **严重**（安全侧错误） | 163–166（eIdle 分支）、169–171（eDose 失能迁移） | eIdle 分支不清零 `fRateOut`：给料中失能或 Done→Idle 后相位回 Idle、`bDosing=FALSE`，但 `fRateOut` 无限保持末次 PI 值（可至 fOutMax），外部螺旋继续给料，与头注释「失能时停给料」直接矛盾 | ① eIdle 分支首行补 `fRateOut := 0.0;`；② eDose 失能迁移前补 `fRateOut := 0.0;`。补丁片段见下 |
| FB_DL_LossInWeightFeeder | 轻 | 197–200（eNoLossRate 迁移当拍） | 故障迁移当拍 `fRateOut` 仍是末次值，下一拍 eFault 分支才归零（一拍延迟，量级 ≤1 周期） | 段 6 统一出口 `IF _bFault THEN` 分支内补 `fRateOut := 0.0;`（故障锁存优先段统一安全侧归零） |
| FB_DL_TwoDofPid | 中 | 121–129（段 5 手动相） | `fManOut` 无有限性闸：手动相输入 NaN 时 `fOut := fManOut` 经限幅比较（NaN 比较恒假）直通出口为 NaN，且 `_fI := fManOut − _fP − _fDfilt` 永久污染积分项（自动恢复后带 NaN，仅复位沿可清） | 段 5 入口补 fManOut 有限性闸（`x<>x` 与 `x-x<>x-x` 双判据）：无效拍 `bInvalid := TRUE`、`eFault := eInputBad`、fOut 冻结保持并早退，不进跟踪式 |
| FB_DL_AxisAccelFeedforward | 中 | 107–109（信息级成因）vs 117–127（有效拍） | `eInputBad` 信息级成因恢复后不撤销：有效拍分支未回写 `_eFaulC := eNone`，`eFault` 恒驻 eInputBad 直至复位沿。同族 FB_DL_TwoDofPid 段 10（191–193 行）有恢复撤销，家族内范式不一致 | 段 5 ELSE 有效拍内补 `IF (_eFaulC = E_DL_AffFault.eInputBad) AND (NOT _bFault) THEN _eFaulC := E_DL_AffFault.eNone; END_IF`（照抄 TwoDofPid 范式） |
| FB_DL_HydraulicAccumPreChg | 轻 | 116（段 3 域闸） | 温度域只设下界（fTempC < −270），无上界：超高温（如 >150 °C 传感器漂移）仍进入折算，293.15/_fTK 增益巨大，可能诱发伪过充故障（锁存安全侧不破，但归因保真差） | 段 3 域闸补上界 `fTempC > 150.0` 判入 eSensorBad（阈值提为常量并注明 [摄氏度]） |
| FC_DL_Kalman2DSmoother | PASS | — | 九输入有限性闸、dt 钳下界防 beta/dt 除零、alpha∈(0,1) 保证除子 2−alpha>1 结构性成立、失败冻结语义显式；alpha-beta 稳态增益公式与公开结果一致，数学内核未越界 | — |

**严重项精确补丁（供编码专家照抄，FB_DL_LossInWeightFeeder.st，≤10 行）：**

```iecst
// ① eIdle 分支（原 163 行）分支体首行补：
E_DL_LwfPhase.eIdle: // 空闲相：等启动沿 / the idle phase, waiting for the start edge
    fRateOut := 0.0; // 空闲相输出强制安全侧归零 / the outlet is force-zeroed on the safe side while idle

// ② eDose 失能迁移（原 169–171 行）改为：
    IF NOT bEnable THEN // 失能 / disabled
        fRateOut := 0.0; // 迁移前先归零（安全侧）/ zeroed on the safe side before the migration
        _ePhase := E_DL_LwfPhase.eIdle; // 回空闲相 / back to idle

// ③ 段 6 统一出口（原 241 行 IF _bFault THEN 块首）补：
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    fRateOut := 0.0; // 故障拍输出安全侧归零 / the outlet is zeroed on the safe side while faulted
```

**附注**：五件声明区 vs 标识符交叉核对、数组边界、首拍行为（Lwf 首扫快照取当拍防速率踢、TwoDofPid R310 首扫初始化）均未发现越界写或未声明引用；TON/R_TRIG 无条件周期刷新在 Lwf（段 0）与 TwoDofPid/AccelFeedforward（段 0）均合规。
