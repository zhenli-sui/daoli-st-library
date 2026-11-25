(*
  Name: FC_DL_QuenchDelayCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：淬火转移延迟允许上限核算：按转移距离与速度算转移时间，估算空冷温降并判是否超允降。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 转移速度为除子，按 0.05~10 m/s 域闸拦截，绝无零除；
            ③ 温降估算按空冷速率线性近似（忽略辐射非线性段），结论用于上限校核不用于工艺反算。
  量纲自证：m ÷ (m/s) = s；s × (℃/s) = ℃；与 fTempDropMaxC[℃] 同量纲比较。
*)
FUNCTION FC_DL_QuenchDelayCalc : REAL
VAR_INPUT
    fTransferDistM : REAL;      (* 转移距离（炉口至淬火槽） [m] Transfer distance [m] *)
    fTransferSpeedMps : REAL;   (* 转移机构平均速度 [m/s] Transfer speed [m/s] *)
    fTempDropMaxC : REAL;       (* 允许最大温降 [℃] Allowed maximum temperature drop [degC] *)
    fCoolRateCps : REAL;        (* 空冷速率（转移区间） [℃/s] Air cooling rate [degC/s] *)
END_VAR
VAR_OUTPUT
    fDelayS : REAL;             (* 转移时间（允许延迟上限的基准） [s] Transfer time [s] *)
    fTempDropEstC : REAL;       (* 估算温降 [℃] Estimated temperature drop [degC] *)
    xWithinLimit : BOOL;        (* 温降在允许范围内 [-] Drop within limit *)
    xValid : BOOL;              (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_DIST_MAX : REAL := 50.0;     (* 转移距离上限 [m] Distance ceiling [m] *)
    DL_V_MIN : REAL := 0.05;        (* 转移速度下限 [m/s] Speed floor [m/s] *)
    DL_V_MAX : REAL := 10.0;        (* 转移速度上限 [m/s] Speed ceiling [m/s] *)
    DL_DROP_MIN : REAL := 5.0;      (* 允许温降下限 [℃] Drop allowance floor [degC] *)
    DL_DROP_MAX : REAL := 500.0;    (* 允许温降上限 [℃] Drop allowance ceiling [degC] *)
    DL_CR_MIN : REAL := 0.1;        (* 空冷速率下限 [℃/s] Cooling rate floor [degC/s] *)
    DL_CR_MAX : REAL := 100.0;      (* 空冷速率上限 [℃/s] Cooling rate ceiling [degC/s] *)
END_VAR
(* 出口预置：四出口统一预置（R256） *)
fDelayS := 0.0; fTempDropEstC := 0.0; xWithinLimit := FALSE; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fTransferDistM <> fTransferDistM) OR ((fTransferDistM - fTransferDistM) <> 0.0)
   OR (fTransferSpeedMps <> fTransferSpeedMps) OR ((fTransferSpeedMps - fTransferSpeedMps) <> 0.0)
   OR (fTempDropMaxC <> fTempDropMaxC) OR ((fTempDropMaxC - fTempDropMaxC) <> 0.0)
   OR (fCoolRateCps <> fCoolRateCps) OR ((fCoolRateCps - fCoolRateCps) <> 0.0) THEN
    FC_DL_QuenchDelayCalc := -1.0;          (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：距离、速度为除子、允许温降、空冷速率逐项定域 *)
IF (fTransferDistM < 0.0) OR (fTransferDistM > DL_DIST_MAX)
   OR (fTransferSpeedMps < DL_V_MIN) OR (fTransferSpeedMps > DL_V_MAX)
   OR (fTempDropMaxC < DL_DROP_MIN) OR (fTempDropMaxC > DL_DROP_MAX)
   OR (fCoolRateCps < DL_CR_MIN) OR (fCoolRateCps > DL_CR_MAX) THEN
    FC_DL_QuenchDelayCalc := -1.0;          (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 转移时间：m ÷ (m/s) = s，速度已过下限闸，绝无零除 *)
fDelayS := fTransferDistM / fTransferSpeedMps;
(* 温降估算：s × (℃/s) = ℃，线性近似（辐射非线性段由工艺余量覆盖） *)
fTempDropEstC := fDelayS * fCoolRateCps;
(* 校核：温降不超过允许值（两侧同量纲 ℃，禁浮点判等） *)
xWithinLimit := fTempDropEstC <= fTempDropMaxC;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_QuenchDelayCalc := fDelayS;
END_FUNCTION
