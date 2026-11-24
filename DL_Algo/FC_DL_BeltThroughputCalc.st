(*
  DL Factory R83 | FC_DL_BeltThroughputCalc
  功能：按线速、件间距与利用率算皮带小时通过量，并给出件间净空隙。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_BeltThroughputCalc : REAL
VAR_INPUT
    fSpeedMps  : REAL; // 皮带线速度 [m/s] / Belt linear speed [m/s]
    fItemPitchM: REAL; // 相邻物件中心距（节距）[m] / Item pitch between centres [m]
    fItemLenM  : REAL; // 物件沿输送方向长度 [m] / Item length along travel [m]
    fUtilPct   : REAL; // 有效利用率（0~100，含停机与空载）[%] / Uptime utilisation [%]
END_VAR
VAR_OUTPUT
    fPph     : REAL; // 小时通过量 [件/h] / Throughput per hour [pcs/h]
    fGapM    : REAL; // 件间净空隙（节距-件长）[m] / Clear gap between items [m]
    fCapPps  : REAL; // 理论极限通过率（利用率 100%）[件/s] / Theoretical rate at full utilisation [pcs/s]
    xValid   : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR

// ---------- 输出预置 ----------
fPph    := 0.0;                     // 通过量清零 [件/h] / Throughput zeroed
fGapM   := 0.0;                     // 空隙清零 [m] / Gap zeroed
fCapPps := 0.0;                     // 极限率清零 [件/s] / Capability zeroed
xValid  := FALSE;                   // 有效性预置 FALSE / Validity preset FALSE

// ---------- 非有限拦截 + 量纲自检 + 节距零闸（R4/R20/R21） ----------
IF NOT (fSpeedMps > -1.0E30 AND fSpeedMps < 1.0E30) OR NOT (fItemPitchM > -1.0E30 AND fItemPitchM < 1.0E30) OR NOT (fItemLenM > -1.0E30 AND fItemLenM < 1.0E30) OR NOT (fUtilPct > -1.0E30 AND fUtilPct < 1.0E30) OR fSpeedMps <= 0.0 OR fItemPitchM <= 0.0 OR fItemLenM <= 0.0 OR fItemLenM > fItemPitchM OR fUtilPct <= 0.0 THEN
    FC_DL_BeltThroughputCalc := -1.0; // 哨兵 -1：非有限或量纲/节距越界 / Sentinel -1: non-finite or domain violation
    RETURN;
END_IF

// ---------- 利用率域闸：0~100% 之外钳位 ----------
IF fUtilPct > 100.0 THEN
    fUtilPct := 100.0;              // 上限钳位 [%] / Clamp upper bound
END_IF

// ---------- 理论极限率：m/s ÷ m = 件/s，节距分母已判正（量纲自洽） ----------
fCapPps := fSpeedMps / fItemPitchM;            // 极限通过率 [件/s] / Capability rate [pcs/s]

// ---------- 小时通过量：件/s × 3600 = 件/h，再乘利用率（含停机损失，故非恒等式） ----------
fPph := fCapPps * 3600.0 * (fUtilPct / 100.0); // 小时通过量 [件/h] / Throughput per hour [pcs/h]

// ---------- 件间净空隙：节距 - 件长，同量纲相减得 m ----------
fGapM  := fItemPitchM - fItemLenM;             // 净空隙 [m] / Clear gap [m]
xValid := TRUE;                                // 链路有效 / Chain valid
FC_DL_BeltThroughputCalc := fPph;              // 返回小时通过量 [件/h] / Return throughput [pcs/h]
END_FUNCTION
