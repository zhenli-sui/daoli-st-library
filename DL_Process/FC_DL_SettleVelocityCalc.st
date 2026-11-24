(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_SettleVelocityCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: Stokes 自由沉降末速度，含雷诺数域校验（Re>2 判为超出 Stokes 层流域）
*)
FUNCTION FC_DL_SettleVelocityCalc : BOOL
VAR_INPUT
    rDpUm : REAL; // 颗粒粒径 [µm] / particle diameter in micrometre
    rRhoP : REAL; // 颗粒密度 [kg/m3] / particle density
    rRhoF : REAL; // 流体密度 [kg/m3] / fluid density
    rMuPas : REAL; // 流体动力黏度 [mPa·s] / dynamic viscosity in mPa·s
END_VAR
VAR_OUTPUT
    rVsMmS : REAL; // 沉降末速度 [mm/s] / terminal settling velocity
    bValid : BOOL; // 结果有效位（超出 Stokes 域时置 FALSE）[-] / valid flag, FALSE when outside Stokes regime
    iErrCode : INT; // 事件码 0=正常 1=黏度非法 2=密度差不正（按 0 处理）3=Re 超域 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rGravity : REAL := 9.80665; // 标准重力加速度 [m/s2] / standard gravity
    rUmToM : REAL := 1.0E-6; // 微米转米系数 [m/µm] / micrometre to metre factor
    rMpasToPas : REAL := 1.0E-3; // 毫帕秒转帕秒系数 [Pa·s/(mPa·s)] / mPa·s to Pa·s factor
    rStokesCoef : REAL := 18.0; // Stokes 阻力式系数（无量纲）[-] / Stokes drag coefficient
    rReLimit : REAL := 2.0; // Stokes 层流域上界雷诺数 [-] / upper Reynolds number of Stokes regime
END_VAR
VAR
    rDm : REAL; // 颗粒粒径 [m] / particle diameter in metre
    rMuPas2 : REAL; // 动力黏度 [Pa·s] / dynamic viscosity in Pa·s
    rVsMs : REAL; // 沉降末速度 [m/s] / terminal velocity in m/s
    rRe : REAL; // 颗粒雷诺数 [-] / particle Reynolds number
END_VAR

    // —— 段 0：全路径预清 —— //
    rDm := 0.0;
    rMuPas2 := 0.0;
    rVsMs := 0.0;
    rRe := 0.0;
    rVsMmS := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_SettleVelocityCalc := FALSE;
    // —— 段 1：分母闸（黏度）与单位归一到 SI —— //
    IF rMuPas <= 0.0 THEN
        iErrCode := 1; // 黏度非正，Stokes 式无定义 / non-positive viscosity, Stokes law undefined
        RETURN;
    END_IF;
    rMuPas2 := rMuPas * rMpasToPas; // [mPa·s] -> [Pa·s] / viscosity to SI
    rDm := rDpUm * rUmToM; // [µm] -> [m] / diameter to SI
    // —— 段 2：不上浮判据（固相密度不大于液相时按零速处理） —— //
    IF rRhoP <= rRhoF THEN
        rVsMmS := 0.0;
        iErrCode := 2; // 密度差不正，颗粒不沉降 / non-positive density difference, no settling
        RETURN;
    END_IF;
    // —— 段 3：量纲链 (m/s2)*(m2)*(kg/m3)/(Pa·s) = m/s —— //
    rVsMs := rGravity * rDm * rDm * (rRhoP - rRhoF) / (rStokesCoef * rMuPas2); // 末速度 [m/s] / terminal velocity
    IF ABS(rVsMs) > 1.0E15 THEN
        rVsMs := 0.0;
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    // —— 段 4：Re 校验（d*v*rhoF/mu），超 2 即离开 Stokes 层流域 —— //
    rRe := rDm * rVsMs * rRhoF / rMuPas2; // 雷诺数 [-] / particle Reynolds number
    rVsMmS := rVsMs * 1000.0; // [m/s] -> [mm/s] / velocity to mm/s
    IF rRe > rReLimit THEN
        iErrCode := 3; // 超出 Stokes 域，给值但标无效 / outside Stokes regime, value kept but flagged
        bValid := FALSE;
        FC_DL_SettleVelocityCalc := FALSE;
        RETURN;
    END_IF;
    bValid := TRUE;
    FC_DL_SettleVelocityCalc := TRUE;
END_FUNCTION
