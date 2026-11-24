(*
  DL Factory R83 | FC_DL_StenterHeatSetCalc
  功能：由烘箱长度与链速算热定形停留时间，并算幅宽伸长率与净超喂量。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_StenterHeatSetCalc : REAL
VAR_INPUT
    fChamberLenM   : REAL; // 定型机有效烘箱长度 [m] / Effective chamber length [m]
    fChainSpeedMpm : REAL; // 链条线速度 [m/min] / Chain speed [m/min]
    fWidthInMm     : REAL; // 进机幅宽 [mm] / Infeed fabric width [mm]
    fWidthOutMm    : REAL; // 出机幅宽 [mm] / Outfeed fabric width [mm]
    fOverfeedPct   : REAL; // 设定超喂率（0~50）[%] / Set overfeed ratio [%]
END_VAR
VAR_OUTPUT
    fDwellS         : REAL; // 热定形停留时间 [s] / Heat-set dwell time [s]
    fStretchPct     : REAL; // 幅宽伸长率（正=拉宽）[%] / Width stretch ratio [%]
    fNetOverfeedPct : REAL; // 净超喂率（设定扣除拉宽损耗）[%] / Net overfeed after stretch [%]
    xValid          : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
// 出口预置：四出口统一预置（R256）
fDwellS := 0.0; fStretchPct := 0.0; fNetOverfeedPct := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fChamberLenM > -1.0E30 AND fChamberLenM < 1.0E30) OR NOT (fChainSpeedMpm > -1.0E30 AND fChainSpeedMpm < 1.0E30) OR NOT (fWidthInMm > -1.0E30 AND fWidthInMm < 1.0E30) OR NOT (fWidthOutMm > -1.0E30 AND fWidthOutMm < 1.0E30) OR NOT (fOverfeedPct > -1.0E30 AND fOverfeedPct < 1.0E30) OR fChamberLenM <= 0.0 OR fWidthInMm <= 0.0 OR fWidthOutMm <= 0.0 THEN
    FC_DL_StenterHeatSetCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 停留时间：m ÷ (m/min) = min，×60 = s；链速分母显式零闸（R4/R21）
IF ABS(fChainSpeedMpm) > 1.0E-9 THEN          // 链速分母显式零闸 / Explicit zero gate on chain speed
    fDwellS := fChamberLenM / fChainSpeedMpm * 60.0; // 停留时间 [s] / Dwell time [s]
ELSE
    fDwellS := 0.0;                 // 停机时不可估时，缺省零 / Machine stopped, default zero
END_IF
// 伸长率：(出机 - 进机) ÷ 进机 × 100，进机幅宽分母显式零闸（R4/R21）
IF ABS(fWidthInMm) > 1.0E-9 THEN              // 幅宽分母显式零闸 / Explicit zero gate on width
    fStretchPct := (fWidthOutMm - fWidthInMm) / fWidthInMm * 100.0; // 幅宽伸长率 [%]
ELSE
    fStretchPct := 0.0;             // 除零防御缺省 [%] / Divide-by-zero default
END_IF
// 超喂域闸：0~50% 之外按边界钳位后继续（码级不断链）
IF fOverfeedPct < 0.0 THEN
    fOverfeedPct := 0.0;            // 下限钳位 [%] / Clamp lower bound
ELSIF fOverfeedPct > 50.0 THEN
    fOverfeedPct := 50.0;           // 上限钳位 [%] / Clamp upper bound
END_IF
// 净超喂：设定超喂扣减被拉宽吸收的部分，含工艺设定量故非恒等式
fNetOverfeedPct := fOverfeedPct - fStretchPct; // 净超喂率 [%] / Net overfeed [%]
xValid          := TRUE;                       // 链路有效 / Chain valid
FC_DL_StenterHeatSetCalc := fDwellS;           // 返回停留时间 [s] / Return dwell time [s]
END_FUNCTION
