(*
  Component : FB_DL_InverterDeratingCtrl
  Category  : DL_Device
  Type      : FB
  Version   : 1.0.1
  CodeSeg   : 16#03_1_04
  Summary   : 逆变器温度/电压分段降额与功率限值：NE107 四态降额状态机，降额原因独立枚举上报。
              Inverter staged derating and power limit: NE107 four-state machine with a separate reason enum.
  溯源声明  : 仅借 NE107 分类与参数域，代码 clean-room（T2 借鉴件）
  边界安全  : 温度/电压非有限（NaN 自反 + Inf 上限）拦截，故障时强制转入停机安全相；
              阈值域闸（tDer1 < tDer2 < tStop，vMax > 0）防止整定倒置；
              状态机 ENUM + CASE 且 ELSE 回 Normal 降级路径；降额原因枚举与 _eState 分离不复用；
              CASE 内禁止给输出枚举赋值，段 3 统一映射；迟滞回差防阈值抖动。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_InverterDeratingCtrl
VAR_INPUT
    bRun     : BOOL;                    (* 使能，假则回 Normal 并封零 · Enable *)
    fTempC   : LREAL;                   (* 逆变器温度 [degC] · Inverter temperature *)
    fVoltV   : LREAL;                   (* 直流母线电压 [V] · DC link voltage *)
    fT1C     : LREAL := 70.0;           (* 一级降额温度阈 [degC] · Level 1 derating temp *)
    fT2C     : LREAL := 80.0;           (* 二级降额温度阈 [degC] · Level 2 derating temp *)
    fTStopC  : LREAL := 90.0;           (* 停机温度阈 [degC] · Stop temperature *)
    fVoltMaxV: LREAL := 850.0;          (* 电压降额阈 [V] · Voltage derating threshold *)
    fPowerNomKw: LREAL := 100.0;        (* 额定功率 [kW] · Nominal power *)
    fHysC    : LREAL := 3.0;            (* 温度回差 [degC] · Temperature hysteresis *)
    fEps     : LREAL := 1.0E-6;         (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    eMode      : (eMNormal := 0, eMDerat1 := 1, eMDerat2 := 2, eMStop := 3);    (* 相枚举输出 / Mode output enum *)
    eReason    : (eRsnNone := 0, eRsnOverTemp := 1, eRsnOverVolt := 2);         (* 降额原因枚举，与相枚举分离 / Reason enum, separate type *)
    fPowerLimKw: LREAL;                (* 功率限值输出 [kW] · Power limit output *)
    bDerating  : BOOL;                  (* 降额激活标志 · Derating active flag *)
    bError     : BOOL;                  (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId   : UDINT;                 (* 事件码 16#0000_0104，0 无事件 · Event code *)
END_VAR
VAR
    _eState : (eStNormal := 0, eStDer1 := 1, eStDer2 := 2, eStStop := 3);   (* 内部状态机，与输出枚举分离 / Internal state *)
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    bSigOk  : BOOL;     (* 输入有效标志 · Input validity flag *)
    bThrOk  : BOOL;     (* 阈值整定域标志 · Threshold tuning validity *)
    eRsn    : (eIRsnNone := 0, eIRsnOverTemp := 1, eIRsnOverVolt := 2);        (* 内部原因枚举，成员名加 I 前缀防重声明 / Internal reason enum, prefixed members *)
END_VAR
VAR CONSTANT
    DL_IDC_PCT1 : LREAL := 0.8;         (* 一级降额功率比 [比值] · Level 1 power ratio *)
    DL_IDC_PCT2 : LREAL := 0.5;         (* 二级降额功率比 [比值] · Level 2 power ratio *)
END_VAR

(* === 段 0 · 实例刷新 === *)
(* 无 TON/R_TRIG 实例：本件为阈值状态机；No timer instances, threshold state machine *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fTempC = fTempC) AND (fVoltV = fVoltV)                   // NaN 自反判据 / NaN reflexivity
          AND (ABS(fTempC) < 1.0E308) AND (ABS(fVoltV) < 1.0E308);  // Inf 上限判据 / Inf limit
bThrOk := (fT1C < fT2C) AND (fT2C < fTStopC) AND (fVoltMaxV > fEps) // 阈值倒置闸 / Threshold order gate
          AND (fPowerNomKw > fEps) AND (fHysC >= 0.0);              // 功率/回差域闸 / Power and hysteresis gates
IF NOT bSigOk OR NOT bThrOk THEN
    uCode := 16#0104;                   // 故障级：域外或整定倒置 / Fault: domain or tuning invalid
END_IF

(* === 段 2 · 主逻辑：NE107 四态降额状态机 === *)
IF NOT bRun THEN
    _eState := eStNormal;               (* 撤使能回 Normal，输出封零在段 3 / Back to normal on disable *)
    eRsn := eIRsnNone;
ELSIF NOT bSigOk THEN
    _eState := eStStop;                 (* 输入非有限强制停机安全相 / Non-finite forces the stop state *)
    eRsn := eIRsnOverTemp;
ELSIF NOT bThrOk THEN
    (* 整定倒置：保持当前相不迁移，段 3 报码 / Bad tuning: hold state, code in segment 3 *)
ELSE
    eRsn := eIRsnNone;                  (* 默认无原因 / Default no reason *)
    CASE _eState OF
        eStNormal:                      (* 正常相：越阈升相 / Normal: escalate on thresholds *)
            IF (fTempC > fTStopC) OR (fVoltV > fVoltMaxV) THEN
                _eState := eStDer2;     (* 拍 N 越阈，拍 N+1 生效二级降额 / To derating 2 *)
                IF fVoltV > fVoltMaxV THEN
                    eRsn := eIRsnOverVolt;  (* 过压触发须归因过压，不得归因过温 / Over-volt attribution *)
                ELSE
                    eRsn := eIRsnOverTemp;  (* 过温触发归因过温 / Over-temp attribution *)
                END_IF
            ELSIF fTempC > fT1C THEN
                _eState := eStDer1;     (* 拍 N+1 一级降额 / To derating 1 *)
                eRsn := eIRsnOverTemp;
            END_IF
        eStDer1:                        (* 一级降额相：带回差迁移 / Level 1 with hysteresis *)
            IF (fTempC > fTStopC) OR (fVoltV > fVoltMaxV) THEN
                _eState := eStDer2;
                IF fVoltV > fVoltMaxV THEN
                    eRsn := eIRsnOverVolt;  (* 过压归因 / Over-volt attribution *)
                ELSE
                    eRsn := eIRsnOverTemp;
                END_IF
            ELSIF fTempC < (fT1C - fHysC) THEN
                _eState := eStNormal;   (* 回差解除 / Release by hysteresis *)
            END_IF
        eStDer2:                        (* 二级降额相 / Level 2 *)
            IF (fTempC < fT1C) AND (fVoltV < fVoltMaxV) THEN
                _eState := eStDer1;     (* 双条件回落才降级 / Demote only when both recover *)
            ELSIF fTempC > fTStopC THEN
                _eState := eStStop;     (* 升停机相 / To stop *)
                eRsn := eIRsnOverTemp;  (* 停机相为过温专用 / Stop phase is over-temp only *)
            END_IF
        eStStop:                        (* 停机相：降温回差后回一级 / Stop: recover to level 1 *)
            IF (fTempC < fTStopC - fHysC) AND (fVoltV < fVoltMaxV) THEN
                _eState := eStDer1;
            END_IF
    ELSE
        _eState := eStNormal;           (* ELSE 兜底回 Normal 降级路径 / ELSE fallback to Normal *)
        uCode := 16#0104;               (* 状态越界报码 / Code on illegal state *)
    END_CASE
END_IF

(* === 段 3 · 输出映射与故障码（CASE 内未触碰输出枚举）=== *)
eMode := eMNormal;                      (* 相映射默认 / Default mapping *)
IF _eState = eStDer1 THEN
    eMode := eMDerat1;                  (* 一级降额映射 / Map level 1 *)
ELSIF _eState = eStDer2 THEN
    eMode := eMDerat2;                  (* 二级降额映射 / Map level 2 *)
ELSIF _eState = eStStop THEN
    eMode := eMStop;                    (* 停机映射 / Map stop *)
END_IF
eReason := eRsnNone;                    (* 原因映射默认 / Default reason *)
IF eRsn = eIRsnOverTemp THEN
    eReason := eRsnOverTemp;            (* 过温原因映射 / Map over-temp *)
ELSIF eRsn = eIRsnOverVolt THEN
    eReason := eRsnOverVolt;            (* 过压原因映射 / Map over-volt *)
END_IF
IF (NOT bRun) OR (_eState = eStStop) THEN
    fPowerLimKw := 0.0;                 (* 停机或撤使能封零 / Zero power limit *)
ELSIF _eState = eStDer2 THEN
    fPowerLimKw := fPowerNomKw * DL_IDC_PCT2;   (* 二级限值 [kW] / Level 2 limit *)
ELSIF _eState = eStDer1 THEN
    fPowerLimKw := fPowerNomKw * DL_IDC_PCT1;   (* 一级限值 [kW] / Level 1 limit *)
ELSE
    fPowerLimKw := fPowerNomKw;         (* 额定限值 [kW] / Nominal limit *)
END_IF
bDerating := (_eState = eStDer1) OR (_eState = eStDer2);    (* 降额激活标志 / Derating active *)
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_0104 形态）/ Single write point *)
END_FUNCTION_BLOCK
