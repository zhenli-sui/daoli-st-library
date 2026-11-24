(*
  DL Factory R83 | FC_DL_SortChuteTimingCalc
  功能：按输送速度与到滑槽口距离算分拣释放延时，扣除物件半长与读码延时。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_SortChuteTimingCalc : REAL
VAR_INPUT
    fConvSpeedMps : REAL; // 输送线速度 [m/s] / Conveyor speed [m/s]
    fDistM        : REAL; // 读码位到滑槽口距离 [m] / Scanner-to-chute distance [m]
    fItemLenMm    : REAL; // 物件沿输送方向长度 [mm] / Item length along travel [mm]
    fScanDelayMs  : REAL; // 读码与决策固有延时 [ms] / Scan and decision latency [ms]
END_VAR
VAR_OUTPUT
    fReleaseDelayMs : REAL; // 从读码成功到释放的延时 [ms] / Release delay after good read [ms]
    fTransitMs      : REAL; // 纯输送通过时间 [ms] / Pure conveyor transit time [ms]
    fLeadM          : REAL; // 需提前释放的等效距离 [m] / Equivalent lead distance [m]
    xValid          : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
// 出口预置：四出口统一预置（R256）
fReleaseDelayMs := 0.0; fTransitMs := 0.0; fLeadM := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 速度零闸（R4/R20/R21）
IF NOT (fConvSpeedMps > -1.0E30 AND fConvSpeedMps < 1.0E30) OR NOT (fDistM > -1.0E30 AND fDistM < 1.0E30) OR NOT (fItemLenMm > -1.0E30 AND fItemLenMm < 1.0E30) OR NOT (fScanDelayMs > -1.0E30 AND fScanDelayMs < 1.0E30) OR fConvSpeedMps <= 0.0 OR fDistM < 0.0 OR fItemLenMm < 0.0 OR fScanDelayMs < 0.0 THEN
    FC_DL_SortChuteTimingCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 纯输送时间：m ÷ (m/s) = s，×1000 = ms（分母已判正，量纲自洽）
fTransitMs := (fDistM / fConvSpeedMps) * 1000.0;   // 输送时间 [ms] / Transit time [ms]
// 等效提前距离：物件半长使物件中心先到位，mm ÷ 1000 = m
fLeadM := (fItemLenMm / 1000.0) / 2.0;             // 半长提前量 [m] / Half-length lead [m]
// 释放延时：输送时间 + 读码延时 - 半长对应输送时间（m ÷ m/s × 1000 = ms）
fReleaseDelayMs := fTransitMs + fScanDelayMs - (fLeadM / fConvSpeedMps) * 1000.0; // 释放延时 [ms]
// 物理可实现性闸：延时为负说明读码位过近，判不可分拣
IF fReleaseDelayMs < 0.0 THEN
    fReleaseDelayMs := 0.0;         // 负延时不可执行，钳零 / Negative delay clamped to zero
    xValid          := FALSE;       // 标记不可分拣 / Flag as unsortable
ELSE
    xValid := TRUE;                 // 时序可实现 / Timing feasible
END_IF
FC_DL_SortChuteTimingCalc := fReleaseDelayMs; // 返回释放延时 [ms] / Return release delay [ms]
END_FUNCTION
