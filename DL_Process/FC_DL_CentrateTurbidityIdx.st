(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_CentrateTurbidityIdx
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 离心液（分离液）浊度相对基线指数与跑料（携带固体）判定
*)
FUNCTION FC_DL_CentrateTurbidityIdx : BOOL
VAR_INPUT
    rNtuNow : REAL; // 当前离心液浊度 [NTU] / current centrate turbidity
    rNtuBase : REAL; // 清洁运行基线浊度 [NTU] / clean-operation baseline turbidity
    rNtuLimit : REAL; // 跑料报警浊度门槛 [NTU] / carry-over alarm threshold
END_VAR
VAR_OUTPUT
    rIdx : REAL; // 浊度指数 = 当前/基线 [-]，1.0 = 与基线持平 / turbidity index, 1.0 equals baseline
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bCarryOver : BOOL; // 跑料标志（浊度超门槛）[-] / solids carry-over flag
    iErrCode : INT; // 事件码 0=正常 1=基线浊度非法 2=指数超可观测上限 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rIdxCap : REAL := 1000.0; // 指数输出饱和上限 [-] / index saturation cap
END_VAR
VAR
    rIdxRaw : REAL; // 未限幅指数 [-] / unlimited index
END_VAR

    // —— 段 0：全路径预清 —— //
    rIdxRaw := 0.0;
    rIdx := 0.0;
    bValid := FALSE;
    bCarryOver := FALSE;
    iErrCode := 0;
    FC_DL_CentrateTurbidityIdx := FALSE;
    // —— 段 1：分母闸（基线浊度，清洗后近零会导致指数爆炸） —— //
    IF rNtuBase <= 0.0 THEN
        iErrCode := 1; // 基线浊度非法，指数无定义 / invalid baseline, index undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (NTU)/(NTU) = 无量纲指数 —— //
    rIdxRaw := rNtuNow / rNtuBase; // 浊度指数 [-] / turbidity index
    // —— 段 3：结果域闸、负值防御与饱和 —— //
    IF ABS(rIdxRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rIdxRaw < 0.0 THEN
        rIdx := 0.0; // 负浊度不可能，钳零 / negative turbidity impossible
    ELSIF rIdxRaw > rIdxCap THEN
        rIdx := rIdxCap; // 超可观测上限饱和 / saturate at observable cap
        iErrCode := 2; // 信息级：指数超上限，基线可能失效 / info: index capped, baseline suspect
    ELSE
        rIdx := rIdxRaw;
    END_IF;
    // —— 段 4：跑料判定（比较用原始浊度，不用饱和后的指数） —— //
    bCarryOver := rNtuNow > rNtuLimit; // 跑料标志 [-] / carry-over flag
    bValid := TRUE;
    FC_DL_CentrateTurbidityIdx := TRUE;
END_FUNCTION
