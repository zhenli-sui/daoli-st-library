(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_ComponentRulEstimate
  分类: DL_Device
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 依据健康度两次采样外推退化斜率与剩余寿命 RUL，并判定退化加速
*)
FUNCTION FC_DL_ComponentRulEstimate : BOOL
VAR_INPUT
    rHealthNow : REAL; // 本次健康度采样 [%]，100 = 全新 / current health sample in percent, 100 is new
    rHealthPrev : REAL; // 上次健康度采样 [%] / previous health sample
    rHoursDelta : REAL; // 两次采样间隔运行小时 [h] / operating hours between samples
    rFailThr : REAL; // 失效门限健康度 [%] / failure threshold health
END_VAR
VAR_OUTPUT
    rRulHours : REAL; // 剩余寿命 [h]，上限哨兵 99999 / remaining useful life, sentinel 99999
    rSlopePerH : REAL; // 退化斜率 [%/h] / degradation slope
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bAccel : BOOL; // 退化加速标志（斜率低于 -0.001 %/h）[-] / accelerated degradation flag
    iErrCode : INT; // 事件码 0=正常 1=间隔非法 2=无退化（哨兵寿命）3=已到门限 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rSlopeDead : REAL := 1.0E-9; // 斜率死区（视作无退化）[%/h] / slope dead band
    rSlopeAccel : REAL := -0.001; // 加速退化判据斜率 [%/h] / accelerated degradation slope threshold
    rRulCap : REAL := 99999.0; // 剩余寿命上限哨兵 [h] / remaining life sentinel cap
END_VAR
VAR
    rSlopeRaw : REAL; // 未限幅斜率 [%/h] / unchecked slope
    rRulRaw : REAL; // 未限幅剩余寿命 [h] / unchecked remaining life
    rHeadRoom : REAL; // 剩余健康度余量 [%] / health headroom
END_VAR

    // —— 段 0：全路径预清 —— //
    rSlopeRaw := 0.0;
    rRulRaw := 0.0;
    rHeadRoom := 0.0;
    rRulHours := 0.0;
    rSlopePerH := 0.0;
    bValid := FALSE;
    bAccel := FALSE;
    iErrCode := 0;
    FC_DL_ComponentRulEstimate := FALSE;
    // —— 段 1：分母闸（采样间隔必须为正） —— //
    IF rHoursDelta <= 0.0 THEN
        iErrCode := 1; // 采样间隔非法，斜率无定义 / invalid interval, slope undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (% - %)/(h) = %/h —— //
    rSlopeRaw := (rHealthNow - rHealthPrev) / rHoursDelta; // 退化斜率 [%/h] / degradation slope
    IF ABS(rSlopeRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rSlopePerH := rSlopeRaw;
    // —— 段 3：无退化判据（死区内视作零斜率，寿命取哨兵） —— //
    IF ABS(rSlopePerH) < rSlopeDead THEN
        rRulHours := rRulCap; // 哨兵寿命 [h] / sentinel life
        iErrCode := 2; // 信息级：无退化 / info level: no degradation
        bValid := TRUE;
        FC_DL_ComponentRulEstimate := TRUE;
        RETURN;
    END_IF;
    // —— 段 4：剩余健康度余量与 RUL（分母闸：|斜率| 已过死区） —— //
    rHeadRoom := rHealthNow - rFailThr; // 剩余健康度 [%] / health headroom
    IF rHeadRoom <= 0.0 THEN
        rRulHours := 0.0; // 已到或越过失效门限 / threshold already reached
        iErrCode := 3; // 信息级：寿命耗尽 / info level: life exhausted
        bAccel := rSlopePerH < rSlopeAccel; // 仍给出加速判据 / acceleration still reported
        bValid := TRUE;
        FC_DL_ComponentRulEstimate := TRUE;
        RETURN;
    END_IF;
    rRulRaw := rHeadRoom / ABS(rSlopePerH); // 量纲 %/(%/h) = h / remaining life in hours
    IF ABS(rRulRaw) > 1.0E15 THEN
        rRulHours := 0.0;
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rRulRaw > rRulCap THEN
        rRulHours := rRulCap; // 上限饱和 / saturate at cap
    ELSE
        rRulHours := rRulRaw;
    END_IF;
    bAccel := rSlopePerH < rSlopeAccel; // 退化加速标志 [-] / accelerated degradation flag
    bValid := TRUE;
    FC_DL_ComponentRulEstimate := TRUE;
END_FUNCTION
