(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_LubeIntervalCalc
  分类: DL_Device
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 按负荷、温度、粉尘三指数折算润滑间隔（基准除以三因子乘积），含因子与乘积双闸
*)
FUNCTION FC_DL_LubeIntervalCalc : BOOL
VAR_INPUT
    rBaseH : REAL; // 基准润滑间隔 [h] / base lubrication interval
    rLoadIdx : REAL; // 负荷指数 [-]，域 0~1.5 / load index
    rTempIdx : REAL; // 温度指数 [-]，域 0~1.5 / temperature index
    rDustIdx : REAL; // 粉尘指数 [-]，域 0~1.5 / dust index
END_VAR
VAR_OUTPUT
    rIntervalH : REAL; // 折算后润滑间隔 [h] / corrected lubrication interval
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=基准间隔非法 2=因子乘积过小已钳位 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rIdxLo : REAL := 0.2; // 单因子钳位下限 [-] / per-factor clamp floor
    rIdxHi : REAL := 2.0; // 单因子钳位上限 [-] / per-factor clamp ceiling
    rProdMin : REAL := 0.1; // 乘积下限，低于此则间隔不可信 [-] / product floor
    rProdFloor : REAL := 0.2; // 乘积过小时的替代值 [-] / substitute product applied when floored
END_VAR
VAR
    rLoadUse : REAL; // 生效负荷因子 [-] / effective load factor
    rTempUse : REAL; // 生效温度因子 [-] / effective temperature factor
    rDustUse : REAL; // 生效粉尘因子 [-] / effective dust factor
    rProd : REAL; // 三因子乘积 [-] / product of factors
    rProdUse : REAL; // 生效乘积 [-] / effective product
    rIntRaw : REAL; // 未校验间隔 [h] / unchecked interval
END_VAR

    // —— 段 0：全路径预清 —— //
    rLoadUse := 1.0;
    rTempUse := 1.0;
    rDustUse := 1.0;
    rProd := 0.0;
    rProdUse := rProdFloor; // 生效乘积缺省取替代值 [-] / effective product defaults to the floor
    rIntRaw := 0.0;
    rIntervalH := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_LubeIntervalCalc := FALSE;
    // —— 段 1：基准间隔域闸（兼最终分母的来源量） —— //
    IF rBaseH <= 0.0 THEN
        iErrCode := 1; // 基准间隔非法，间隔无定义 / invalid base interval
        RETURN;
    END_IF;
    // —— 段 2：三因子各自钳位到 [0.2, 2.0]（配置越界按边界处理，不中断） —— //
    IF rLoadIdx < rIdxLo THEN
        rLoadUse := rIdxLo; // 下限钳位 / clamp low
    ELSIF rLoadIdx > rIdxHi THEN
        rLoadUse := rIdxHi; // 上限钳位 / clamp high
    ELSE
        rLoadUse := rLoadIdx;
    END_IF;
    IF rTempIdx < rIdxLo THEN
        rTempUse := rIdxLo;
    ELSIF rTempIdx > rIdxHi THEN
        rTempUse := rIdxHi;
    ELSE
        rTempUse := rTempIdx;
    END_IF;
    IF rDustIdx < rIdxLo THEN
        rDustUse := rIdxLo;
    ELSIF rDustIdx > rIdxHi THEN
        rDustUse := rIdxHi;
    ELSE
        rDustUse := rDustIdx;
    END_IF;
    // —— 段 3：乘积闸（分母不得过小，否则间隔被无限拉长） —— //
    rProd := rLoadUse * rTempUse * rDustUse; // 三因子乘积 [-] / product
    IF rProd < rProdMin THEN
        rProdUse := rProdFloor; // 取替代常数（0.2），间隔最多放大 5 倍 / substitute product, interval at most 5x
        iErrCode := 2; // 信息级：乘积过小已钳位 / info level: product floored
    ELSE
        rProdUse := rProd;
    END_IF;
    // —— 段 4：量纲链 (h)/((-)×(-)×(-)) = h —— //
    rIntRaw := rBaseH / rProdUse; // 折算间隔 [h] / corrected interval
    IF ABS(rIntRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rIntervalH := rIntRaw;
    bValid := TRUE;
    FC_DL_LubeIntervalCalc := TRUE;
END_FUNCTION
