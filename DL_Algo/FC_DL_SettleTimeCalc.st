// FC_DL_SettleTimeCalc v1.0.0
// 开源溯源：self-cleanroom / 回路 KPI 族
(*
  道莅工业代码库 | DL_Algo | FC_DL_SettleTimeCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 阶跃响应整定时间：以 ±容差带（相对 y_final）进入判据，扫响应序列
        找最后一次越界采样，整定时间 = 最后越界点之后一拍时刻；
        从未进带 → bSettled=FALSE，带内起步 → 整定时间为 0
  邻件关系: 与 FC_DL_OvershootPctCalc（本批 S22，超调量）成对；与
            FB_DL_WindowExtremaStat（窗口极值统计）差异点：极值件做
            滑窗在线统计，本件为离线序列一次性判据扫描
  序列契约: aResp 为定长显式上界 200 数组，nCount 个有效采样（1..200），
            fTs 为采样周期；本件不改写输入数组
*)
FUNCTION FC_DL_SettleTimeCalc : REAL
VAR_INPUT
    aResp     : ARRAY[1..200] OF REAL;   // 阶跃响应序列（前 nCount 个有效）[工程单位] / Step response samples
    nCount    : INT;                     // 有效采样数 [点]，域 1..200 / Valid sample count, domain 1..200
    fTs       : REAL := 0.1;             // 采样周期 [s]，域 > 0 / Sampling period [s]
    fYFinal   : REAL := 0.0;             // 目标稳态值 [工程单位] / Target steady value
    fBandHalf : REAL := 2.0;             // 容差半带宽 [工程单位]，域 >= 0 / Half tolerance band
END_VAR
VAR_OUTPUT
    bSettled  : BOOL;                    // 序列内已进入容差带并保持 [-] / Settled within band
    bValid    : BOOL;                    // 结果有效回执 [-] / Result validity receipt
    uErrorId  : UDINT;                   // 事件码，0 = 无事件；16#0002_2A01 = 入参域外 / Event code
END_VAR
VAR
    i         : INT;                     // 扫描索引 [点] / Scan index
    nLastViol : INT;                     // 最后越界采样索引 [点]，0 = 从未越界 / Last violating index, 0 = never violated
    fDev      : REAL;                    // 当前偏差 [工程单位] / Current deviation
END_VAR

// —— 段 0：全路径缺省 —— //
bSettled := FALSE;                       // 整定标志预清 / Settled preset
bValid := FALSE;                         // 有效回执预清 / Validity preset
uErrorId := 16#0000;                     // 事件码预清 / Event code preset
nLastViol := 0;                          // 最后越界索引预清（0 = 无越界）/ Last violation preset
FC_DL_SettleTimeCalc := 0.0;             // 返回值缺省零 / Return default zero

// —— 段 1：入参域闸（计数/周期/带宽） —— //
IF (nCount < 1) OR (nCount > 200) OR (fTs <= 0.0) OR (fTs <> fTs)
   OR (fBandHalf < 0.0) OR (fYFinal <> fYFinal) THEN
    uErrorId := 16#0002_2A01;            // 信息级：计数/周期/带宽非法 / Info level: illegal parameters
    RETURN;                              // 不扫描返回 / Return without scan
END_IF

// —— 段 2：序列扫描（找最后一次越出 ±容差带的采样） —— //
FOR i := 1 TO nCount DO                  // 逐点扫描（i ≤ nCount ≤ 200 判界安全）/ Scan points, index safe
    fDev := aResp[i] - fYFinal;          // 与稳态偏差 [工程单位] / Deviation from final
    IF (aResp[i] <> aResp[i]) OR (ABS(fDev) >= 3.0E38) THEN
        uErrorId := 16#0002_2A01;        // 序列含非有限值：拒收（R4 域闸）/ Non-finite sample: reject
        bSettled := FALSE;               // 整定标志回清 / Settled cleared
        RETURN;
    END_IF
    IF ABS(fDev) > fBandHalf THEN        // 越出容差带 / Outside tolerance band
        nLastViol := i;                  // 记录最后越界索引 / Record last violation
    END_IF
END_FOR

// —— 段 3：判据收口（进入带并保持 = 最后越界之后无越界） —— //
IF nLastViol = 0 THEN
    bSettled := TRUE;                    // 全程带内：整定时间 0 / In band from start
    FC_DL_SettleTimeCalc := 0.0;         // 整定时间零 / Settle time zero
ELSE
    IF nLastViol >= nCount THEN
        bSettled := FALSE;               // 末点仍越界：序列内未整定 / Still violating at end
        FC_DL_SettleTimeCalc := 0.0;     // 时间无意义置零 / Time meaningless, zero
    ELSE
        bSettled := TRUE;                // 最后越界后保持带内 / In band after last violation
        FC_DL_SettleTimeCalc := DINT_TO_REAL(nLastViol) * fTs;   // 整定时间 = 越界点后一拍时刻 [s] / Settle time after last violation
    END_IF
END_IF
bValid := TRUE;                          // 有效回执 / Validity receipt
END_FUNCTION
