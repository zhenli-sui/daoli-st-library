(*
  Name        : FC_DL_ZnTune
  Category    : DL_Algo
  Version     : 1.0.0
  Purpose     : Ziegler-Nichols 临界比例度法整定：由临界增益 Ku 与临界振荡周期 Tu 推算 P/PI/PID 三组参数（Kp/Ti/Td 及 Ki/Kd 派生）；/ Ziegler-Nichols ultimate-gain tuning: derive P/PI/PID parameters (Kp, Ti, Td plus Ki, Kd) from Ku and Tu
  溯源        : 借 t2-5-modpid·tune 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：Ku <= 0 或 Tu <= 0 → 返回 FALSE，全部输出置 0 哨兵（非故障级）；
                ② Ti 派生 Ki 前先判 Ti > eps（P 模式 Ti = 0 → Ki 直接置 0，不做除法）；
                ③ 系数为 ZN 经典表值，属公开表格数据，不含源实现细节；
                ④ 枚举 CASE 含 ELSE 兜底（缺省按 PID 处理，绝不静默输出全零以外的值）。
*)
TYPE E_DL_ZnMode :
(
    eP   := 0,                               (* 纯比例模式 / Pure proportional mode *)
    ePi  := 10,                              (* 比例积分模式 / Proportional-integral mode *)
    ePid := 20                              (* 比例积分微分模式（缺省） / Proportional-integral-derivative mode *)
);
END_TYPE

FUNCTION FC_DL_ZnTune : BOOL
VAR_INPUT
    fKu    : LREAL := 0.0;                   (* 临界增益（等幅振荡时的纯比例增益），域 > 0 [-] / Ultimate gain, must be > 0 *)
    fTu    : LREAL := 0.0;                   (* 临界振荡周期，域 > 0 [s] / Ultimate period, must be > 0 *)
    eMode  : E_DL_ZnMode := E_DL_ZnMode.ePid; (* 整定模式（P/PI/PID）[-] / Tuning mode *)
END_VAR
VAR_OUTPUT
    fKp : LREAL;                             (* 比例增益（无量纲）[-] / Proportional gain *)
    fTi : LREAL;                             (* 积分时间（复位时间），P 模式为 0 [s] / Integral (reset) time, 0 in P mode *)
    fTd : LREAL;                             (* 微分时间（速率时间），P/PI 模式为 0 [s] / Derivative (rate) time, 0 in P/PI *)
    fKi : LREAL;                             (* 积分增益 = Kp / Ti（Ti = 0 时置 0）[1/s] / Integral gain Kp/Ti *)
    fKd : LREAL;                             (* 微分增益 = Kp * Td [s] / Derivative gain Kp*Td *)
END_VAR
VAR CONSTANT
    DL_ZN_EPS    : LREAL := 1.0E-9;          (* 时间量判零容差 [s] / Time epsilon *)
    DL_ZN_KU_P   : LREAL := 0.50;            (* ZN 表：P 模式 Kp = 0.50·Ku [-] / ZN table: P Kp factor *)
    DL_ZN_KU_PI  : LREAL := 0.45;            (* ZN 表：PI 模式 Kp = 0.45·Ku [-] / ZN table: PI Kp factor *)
    DL_ZN_TI_PI  : LREAL := 1.2;             (* ZN 表：PI 模式 Ti = Tu / 1.2 [-] / ZN table: PI Ti divisor *)
    DL_ZN_KU_PID : LREAL := 0.60;            (* ZN 表：PID 模式 Kp = 0.60·Ku [-] / ZN table: PID Kp factor *)
    DL_ZN_TI_PID : LREAL := 2.0;             (* ZN 表：PID 模式 Ti = Tu / 2.0 [-] / ZN table: PID Ti divisor *)
    DL_ZN_TD_PID : LREAL := 8.0;             (* ZN 表：PID 模式 Td = Tu / 8.0 [-] / ZN table: PID Td divisor *)
    DL_ZN_ZERO   : LREAL := 0.0;             (* 零常量（哨兵与占位）[#] / Zero constant *)
END_VAR

(* —— 段 1：输出全路径预置（任何分支都不会留旧值，R191 名实双出口） —— *)
fKp := DL_ZN_ZERO;                           (* Kp 预置 0 / Kp preset *)
fTi := DL_ZN_ZERO;                           (* Ti 预置 0 / Ti preset *)
fTd := DL_ZN_ZERO;                           (* Td 预置 0 / Td preset *)
fKi := DL_ZN_ZERO;                           (* Ki 预置 0 / Ki preset *)
fKd := DL_ZN_ZERO;                           (* Kd 预置 0 / Kd preset *)
FC_DL_ZnTune := FALSE;                       (* 返回值预置 FALSE：仅合法分支翻 TRUE / Return preset FALSE *)

(* —— 段 2：非有限输入拒收（NaN 自反 + Inf 差判） —— *)
IF (fKu <> fKu) OR (fTu <> fTu) THEN
    RETURN;                                  (* NaN 拒收 / NaN rejected *)
END_IF
IF ((fKu - fKu) <> (fKu - fKu)) OR ((fTu - fTu) <> (fTu - fTu)) THEN
    RETURN;                                  (* Inf 拒收 / Inf rejected *)
END_IF

(* —— 段 3：组态闸（Ku/Tu 正域，除子唯一出入口） —— *)
IF (fKu <= DL_ZN_EPS) OR (fTu <= DL_ZN_EPS) THEN
    RETURN;                                  (* 临界参数非正：无整定语义，返回 FALSE + 零哨兵 / Non-positive Ku/Tu: sentinel *)
END_IF

(* —— 段 4：按模式取 ZN 表系数（CASE 含 ELSE 兜底为 PID） —— *)
CASE eMode OF
    E_DL_ZnMode.eP:                          (* P 模式：仅 Kp，Ti/Td 保持 0 / P mode *)
        fKp := DL_ZN_KU_P * fKu;             (* Kp = 0.50·Ku [-] / Kp *)
    E_DL_ZnMode.ePi:                         (* PI 模式：Kp + Ti / PI mode *)
        fKp := DL_ZN_KU_PI * fKu;            (* Kp = 0.45·Ku [-] / Kp *)
        fTi := fTu / DL_ZN_TI_PI;            (* Ti = Tu/1.2，除子为表常量非 0 [s] / Ti *)
    E_DL_ZnMode.ePid:                        (* PID 模式：Kp + Ti + Td / PID mode *)
        fKp := DL_ZN_KU_PID * fKu;           (* Kp = 0.60·Ku [-] / Kp *)
        fTi := fTu / DL_ZN_TI_PID;           (* Ti = Tu/2.0 [s] / Ti *)
        fTd := fTu / DL_ZN_TD_PID;           (* Td = Tu/8.0 [s] / Td *)
    ELSE                                     (* 非法模式：按 PID 兜底，不静默清零 / Illegal mode: fallback to PID *)
        fKp := DL_ZN_KU_PID * fKu;           (* 兜底 Kp = 0.60·Ku [-] / Fallback Kp *)
        fTi := fTu / DL_ZN_TI_PID;           (* 兜底 Ti [s] / Fallback Ti *)
        fTd := fTu / DL_ZN_TD_PID;           (* 兜底 Td [s] / Fallback Td *)
END_CASE

(* —— 段 5：Ki/Kd 派生（Ti 判零后再除，P 模式 Ki 保持 0） —— *)
IF ABS(fTi) > DL_ZN_EPS THEN
    fKi := fKp / fTi;                        (* Ki = Kp/Ti，除子已过容差闸 [1/s] / Ki, divisor gated *)
ELSE
    fKi := DL_ZN_ZERO;                       (* Ti = 0：积分增益无定义，置 0 / Ti zero: Ki 0 *)
END_IF
fKd := fKp * fTd;                            (* Kd = Kp·Td（乘性派生无除零）[s] / Kd, multiplicative *)
FC_DL_ZnTune := TRUE;                        (* 参数全套有效 / All parameters valid *)
END_FUNCTION
