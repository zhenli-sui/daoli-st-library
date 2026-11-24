(*
  ============================================================
  组件名 : FC_DL_ShuttleAisleLockChk
  分类   : DL_Process
  功能   : 穿梭车巷道互锁裁决，按请求巷道与两车当前巷道及忙碌状态给出放行或拒绝码
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      拒绝码 iDenyCode 语义：0=允许放行，1=已有单车占用该巷道，2=双车同时冲突，3=请求巷道号非法。
      巷道号非法属业务级判定而非计算失败，因此 bValid 仍为 TRUE，由 iDenyCode=3 表达。
      bGrant 仅在 iDenyCode=0 时为 TRUE，两者同源赋值，不存在对立表述。
  ============================================================
*)
FUNCTION FC_DL_ShuttleAisleLockChk : BOOL
VAR_INPUT
    bEnable    : BOOL; // 使能：TRUE 时裁决 / Enable: TRUE to arbitrate
    bErr       : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    iAisleReq  : INT;  // 请求巷道号 [无量纲序号] / requested aisle number [dimensionless index]
    iAisleOwn1 : INT;  // 一号车当前所在巷道号 [无量纲序号] / aisle currently held by car one [dimensionless index]
    iAisleOwn2 : INT;  // 二号车当前所在巷道号 [无量纲序号] / aisle currently held by car two [dimensionless index]
    bCar1Busy  : BOOL; // 一号车忙碌标志，TRUE 表示其占位有效 / car one busy flag, TRUE means its hold is effective
    bCar2Busy  : BOOL; // 二号车忙碌标志，TRUE 表示其占位有效 / car two busy flag, TRUE means its hold is effective
END_VAR
VAR_OUTPUT
    bGrant     : BOOL; // 放行请求：TRUE 表示允许进入请求巷道 / grant flag, TRUE allows entering the requested aisle
    iDenyCode  : INT;  // 拒绝码：0 允许 / 1 一车占用 / 2 双车冲突 / 3 巷道号非法 / deny code 0 allow 1 single hold 2 double conflict 3 illegal aisle
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_AISLE_MIN : INT := 1;  // 合法巷道号下界 [无量纲序号] / lower bound of a legal aisle number [dimensionless index]
    DL_AISLE_MAX : INT := 64; // 合法巷道号上界 [无量纲序号] / upper bound of a legal aisle number [dimensionless index]
END_VAR
VAR
    _iConf : INT := 0; // 与请求巷道冲突的忙碌车数量 [台] / number of busy cars conflicting with the request [unit]
END_VAR

    // 段 1｜出口预置：放行先置 FALSE，拒绝码先置 0，避免上一拍残值被误用
    bGrant := FALSE;
    iDenyCode := 0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜请求巷道号域闸：越界属业务级非法，给出 3 号码后放行位保持 FALSE
    IF (iAisleReq < DL_AISLE_MIN) OR (iAisleReq > DL_AISLE_MAX) THEN
        iDenyCode := 3;
        bValid := TRUE;
        FC_DL_ShuttleAisleLockChk := bValid;
        RETURN;
    END_IF;
    // 段 4｜冲突计数：仅忙碌且巷道号相等的车计入冲突
    _iConf := 0;
    IF bCar1Busy AND (iAisleOwn1 = iAisleReq) THEN
        _iConf := _iConf + 1;
    END_IF;
    IF bCar2Busy AND (iAisleOwn2 = iAisleReq) THEN
        _iConf := _iConf + 1;
    END_IF;
    // 段 5｜按冲突数裁决
    IF _iConf = 0 THEN
        iDenyCode := 0;
        bGrant := TRUE;
    ELSIF _iConf = 1 THEN
        iDenyCode := 1;
        bGrant := FALSE;
    ELSE
        iDenyCode := 2;
        bGrant := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_ShuttleAisleLockChk := bValid;
END_FUNCTION
