(*
  组件名 Component   : FC_DL_DewPointToPpmV
  子库 Sublibrary    : DL_MathData
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 露点温度 → 气体水分含量 ppmV 换算（饱和压比值法）：
                       1) 复用饱和蒸气压唯一属主 FC_DL_VaporPressureSat（DL_Algo）求露点温度
                       对应饱和水蒸气压 p_sat，本件零 Magnus 常数复制、零重复声明；
                       2) 摩尔分数 x_w = p_sat / p_total（分母总压前置正域判据，不进入除法）；
                       3) ppmV = x_w × 1E6，比值 > 1 时饱和钳位到 1.0 并置信息标志；
                       4) 非有限输入（NaN 自反判 + 无穷差值自减判）直接判无效返回 0.0。
  边界 Boundary      : ① 纯函数、无状态机、无内部实例，可重入；
                       ② 总压域 [1.0E-3, 2.0E7] Pa，域外判无效不外推；
                       ③ 露点温度域检查由属主承担，钳位标志透传（bClamped）；
                       ④ 无全局变量引用、无外部变量声明、无物理地址寻址；
                       ⑤ 结果仅当 bValid = TRUE 才可被工艺判据引用。
  依赖 Depends       : FC_DL_VaporPressureSat（DL_Algo，饱和压唯一属主，按 registry 实名调用）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-1-lgf-converter 行为定义分类与参数域，
                       零代码行复制；饱和压计算完全委托既有属主）
  码位 Code          : 16#05_0_06
  码表 Error codes   : 纯函数件无状态机码轨；无效结果经 bValid = FALSE 表达（哨兵返回 0.0），
                       本件不占用故障码位（MathData 段 0005 内 0506 为本格独占声明，保留不用）。
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 1 · 序号 1）
*)

FUNCTION FC_DL_DewPointToPpmV : LREAL
VAR_INPUT
    fDewPointC : LREAL;                 // 露点温度 [摄氏度]，域 -40.0..100.0（域检查属主承担）/ Dew point temperature
    fPressPa   : LREAL;                 // 气体总压 [Pa]，域 1.0E-3..2.0E7 / Total gas pressure
END_VAR
VAR_OUTPUT
    bValid     : BOOL;                  // 结果有效标志，FALSE 时返回值为哨兵 0.0 / Result validity flag
    bClamped   : BOOL;                  // 饱和压属主输入钳位标志透传 / Saturation owner clamped flag
    bSatRatio  : BOOL;                  // 比值超 1 已饱和钳位标志 / Ratio saturated and clamped flag
END_VAR
VAR
    fPsatPa   : LREAL;                  // 属主返回的饱和水蒸气压 [Pa] / Saturation vapor pressure from owner
    bSatOk    : BOOL;                   // 属主调用受理标志 / Owner call acceptance flag
END_VAR
VAR CONSTANT
    DL_PPM_SCALE : LREAL := 1.0E6;      // 摩尔分数 → ppmV 放大系数 [ppmV] / Mole fraction to ppmV scale
    DL_P_MIN     : LREAL := 1.0E-3;     // 总压有效下限 [Pa] / Pressure valid floor
    DL_P_MAX     : LREAL := 2.0E7;      // 总压有效上限 [Pa] / Pressure valid ceiling
    DL_RATIO_MAX : LREAL := 1.0;        // 摩尔分数物理上界 [无量纲] / Mole fraction physical ceiling
    DL_ZERO      : LREAL := 0.0;        // 无效哨兵返回值 [ppmV] / Sentinel return for invalid
END_VAR

(* —— 段 1｜出口预清零（纯函数无实例，无定时器/沿刷新义务） —— *)
bValid    := FALSE;                     // 缺省无效
bClamped  := FALSE;                     // 属主钳位标志缺省 FALSE
bSatRatio := FALSE;                     // 饱和钳位标志缺省 FALSE

(* —— 段 2｜输入防御：非有限值（NaN 自反 + 无穷差值自减）与总压域闸 —— *)
IF (fDewPointC <> fDewPointC) OR ((fDewPointC - fDewPointC) <> DL_ZERO)
   OR (fPressPa <> fPressPa) OR ((fPressPa - fPressPa) <> DL_ZERO)
   OR (fPressPa < DL_P_MIN) OR (fPressPa > DL_P_MAX) THEN
    FC_DL_DewPointToPpmV := DL_ZERO;    // 无效输入：哨兵零返回，不进入除法
    RETURN;
END_IF

(* —— 段 3｜委托饱和压唯一属主：禁在本件重复声明 Magnus 常数 —— *)
bSatOk := FC_DL_VaporPressureSat(fTempC := fDewPointC, fPvSat => fPsatPa, bClamped => bClamped);
IF NOT bSatOk THEN
    FC_DL_DewPointToPpmV := DL_ZERO;    // 属主判无效：哨兵零返回
    RETURN;
END_IF

(* —— 段 4｜饱和压比值法：分母已过正域闸，除法安全；比值超 1 饱和钳位 —— *)
IF fPsatPa > (fPressPa * DL_RATIO_MAX) THEN
    bSatRatio := TRUE;                  // 比值超物理上界：钳位并留痕
    FC_DL_DewPointToPpmV := DL_PPM_SCALE * DL_RATIO_MAX;
ELSE
    FC_DL_DewPointToPpmV := DL_PPM_SCALE * (fPsatPa / fPressPa);
END_IF
bValid := TRUE;                         // 全部防御通过：结果有效
END_FUNCTION
