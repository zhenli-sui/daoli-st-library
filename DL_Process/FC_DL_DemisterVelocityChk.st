(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_DemisterVelocityChk
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 除雾器截面气速与临界携带速度（Souders-Brown）比较，判定雾沫夹带
*)
FUNCTION FC_DL_DemisterVelocityChk : BOOL
VAR_INPUT
    rGasM3h : REAL; // 实际工况烟气量 [m3/h] / actual gas flow
    rAreaM2 : REAL; // 除雾器有效流通面积 [m2] / demister free area
    rRhoL : REAL; // 液相密度 [kg/m3] / liquid density
    rRhoG : REAL; // 气相密度 [kg/m3] / gas density
    rKFactor : REAL; // Souders-Brown 经验系数 [m/s] / Souders-Brown coefficient
END_VAR
VAR_OUTPUT
    rVelMs : REAL; // 截面气速 [m/s] / superficial gas velocity
    rVcritMs : REAL; // 临界夹带速度 [m/s] / critical carry-over velocity
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bCarryOver : BOOL; // 雾沫夹带标志（气速超临界）[-] / carry-over flag
    iErrCode : INT; // 事件码 0=正常 1=气相密度非法 2=流通面积非法 3=密度差不正 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rSecPerHour : REAL := 3600.0; // 每小时秒数 [s/h] / seconds per hour
END_VAR
VAR
    rRhoRatio : REAL; // 密度比 (ρL-ρG)/ρG [-] / density ratio
    rVelRaw : REAL; // 未限幅气速 [m/s] / unlimited velocity
    rVcritRaw : REAL; // 未限幅临界速度 [m/s] / unlimited critical velocity
END_VAR

    // —— 段 0：全路径预清 —— //
    rRhoRatio := 0.0;
    rVelRaw := 0.0;
    rVcritRaw := 0.0;
    rVelMs := 0.0;
    rVcritMs := 0.0;
    bValid := FALSE;
    bCarryOver := FALSE;
    iErrCode := 0;
    FC_DL_DemisterVelocityChk := FALSE;
    // —— 段 1：分母闸（气相密度、流通面积） —— //
    IF rRhoG <= 0.0 THEN
        iErrCode := 1; // 气相密度非法，临界速度无定义 / invalid gas density
        RETURN;
    END_IF;
    IF rAreaM2 <= 0.0 THEN
        iErrCode := 2; // 流通面积非法，气速无定义 / invalid free area
        RETURN;
    END_IF;
    // —— 段 2：截面气速（量纲 (m3/h)/(s/h)/(m2) = m/s） —— //
    rVelRaw := rGasM3h / rSecPerHour / rAreaM2; // 截面气速 [m/s] / superficial velocity
    IF ABS(rVelRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rVelRaw < 0.0 THEN
        rVelMs := 0.0; // 负流量防御 / negative flow guard
    ELSE
        rVelMs := rVelRaw;
    END_IF;
    // —— 段 3：临界速度 = K·SQRT((ρL-ρG)/ρG)（开方前闸 >= 0） —— //
    rRhoRatio := (rRhoL - rRhoG) / rRhoG; // 密度比 [-] / density ratio
    IF rRhoRatio < 0.0 THEN
        rVcritMs := 0.0;
        iErrCode := 3; // 密度差不正（气相重于液相），临界速度无意义 / non-positive density difference
        bValid := TRUE;
        FC_DL_DemisterVelocityChk := TRUE;
        RETURN;
    END_IF;
    rVcritRaw := rKFactor * SQRT(rRhoRatio); // 临界速度 [m/s] / critical velocity
    IF ABS(rVcritRaw) > 1.0E15 THEN
        rVcritMs := 0.0;
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rVcritRaw < 0.0 THEN
        rVcritMs := 0.0; // 负系数防御 / negative coefficient guard
    ELSE
        rVcritMs := rVcritRaw;
    END_IF;
    // —— 段 4：夹带判定与收口 —— //
    bCarryOver := rVelMs > rVcritMs; // 夹带标志 [-] / carry-over flag
    bValid := TRUE;
    FC_DL_DemisterVelocityChk := TRUE;
END_FUNCTION
