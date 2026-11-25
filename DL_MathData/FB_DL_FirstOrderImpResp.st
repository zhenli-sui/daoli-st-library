// FB_DL_FirstOrderImpResp v1.0.0
// 开源溯源：brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴 FT_IMP 一阶惯性环节脉冲响应语义，clean-room 重写
(*
  道莅工业代码库 | DL_MathData | FB_DL_FirstOrderImpResp
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 一阶惯性环节脉冲响应序列计算：h(t) = (K/T)·e^(-t/T)，采样 t_k = k·Ts
  邻件关系: 与 FB_DL_FirstOrderIdent 同族不同用 —— 辨识件由数据反推 K/T，
            本件由 K/T 正推响应序列（辨识 vs 响应），口径互不引用
  接口契约: bExecute 上升沿触发整段序列计算（单拍完成，非逐拍递推）；
            nLen 为本次计算点数，域 1..64，超域按 64 钳位并置信息码
*)
FUNCTION_BLOCK FB_DL_FirstOrderImpResp
VAR_INPUT
    bExecute  : BOOL := FALSE;                   // 执行触发（上升沿整段计算）/ Execute trigger, rising edge
    fGain     : REAL := 1.0;                     // 增益 K [1]，域 > 0 / DC gain, domain > 0
    fTimeConst: REAL := 1.0;                     // 时间常数 T [s]，域 > 0 / Time constant [s]
    fTs       : REAL := 0.1;                     // 采样周期 Ts [s]，域 > 0 / Sampling period [s]
    nLen      : INT := 16;                       // 序列点数 [点]，域 1..64 / Sequence length [points], domain 1..64
END_VAR
VAR_OUTPUT
    aResp     : ARRAY[1..64] OF REAL;            // 脉冲响应序列 h(t_k) [1/s·(s/点)，随增益] / Impulse response sequence
    nCount    : INT;                             // 本次实际写出点数 [点] / Actual points written
    bDone     : BOOL;                            // 本次序列计算完成脉冲（单拍自清）/ Sequence done pulse, one cycle
    bValid    : BOOL;                            // 参数有效且序列可用 [-] / Parameters valid and sequence usable
    bError    : BOOL;                            // 故障标志，与故障级码配对 / Fault flag paired with fault code
    uErrorId  : UDINT;                           // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    rtrExec   : R_TRIG;                          // 执行沿检测（每拍无条件刷新）/ Execute edge, refreshed every cycle
    bCfgOk    : BOOL;                            // 参数闸结果 [-] / Parameter gate result
    nLenEff   : INT;                             // 钳位后生效点数 [点] / Effective clamped length
    fDecay    : REAL;                            // 单步衰减因子 e^(-Ts/T) [1] / Per-step decay factor
    fPeak     : REAL;                            // 脉冲响应峰值 K/T [1/s] / Impulse peak K/T
    fTerm     : REAL;                            // 当前项 K/T·decay^k [1/s] / Current term
    i         : INT;                             // 循环索引 [点] / Loop index
END_VAR
VAR CONSTANT
    DL_FIR_LENMAX : INT := 64;                   // 序列上限（数组显式上界一致）[点] / Sequence upper bound, matches array
END_VAR

// —— 段 0：实例无条件刷新 + 输出缺省 —— //
rtrExec(CLK := bExecute);                        // 执行沿每拍刷新 / Execute edge refreshed every cycle
bDone := FALSE;                                  // 完成脉冲单拍自清 / Done pulse self-clearing

// —— 段 1：参数闸（有限性 + 正数域 + 点数域） —— //
bCfgOk := (fGain > 0.0) AND (fTimeConst > 0.0) AND (fTs > 0.0)
          AND (fGain = fGain) AND (fTimeConst = fTimeConst) AND (fTs = fTs);   // 正数域 + NaN 自反判 / Positive domain and NaN gate
bValid := bCfgOk;                                // 有效回执随参数闸 / Validity follows gate
IF NOT bCfgOk THEN
    bError   := TRUE;                            // 故障级：参数非法 / Fault level: invalid parameters
    uErrorId := 16#0002_1A01;                    // 本件故障码（1Axx 步进）/ Fault code of this component
    RETURN;                                      // 参数非法不计算 / No calculation on invalid params
END_IF
bError   := FALSE;                               // 参数恢复：故障清零（解除路径）/ Fault cleared on valid params
uErrorId := 16#0000;                             // 事件码清零 / Event code cleared
nLenEff := nLen;                                 // 生效点数初值 / Effective length init
IF nLenEff < 1 THEN
    nLenEff := 1;                                // 下限钳位 / Clamp to lower bound
END_IF
IF nLenEff > DL_FIR_LENMAX THEN
    nLenEff := DL_FIR_LENMAX;                    // 上限钳位至数组上界 / Clamp to array bound
END_IF
nCount := nLenEff;                               // 实际点数输出 / Actual count output

// —— 段 2：上升沿触发整段序列计算 —— //
IF rtrExec.Q THEN                                // 仅执行沿拍计算（避免每拍重算）/ Compute only on execute edge
    fDecay := EXP(-fTs / fTimeConst);            // 单步衰减 e^(-Ts/T)，T 非零已过闸 / Per-step decay, T nonzero gated
    fPeak  := fGain / fTimeConst;                // 峰值 K/T / Peak value K/T
    fTerm  := fPeak;                             // 首项 k=0 / First term k=0
    FOR i := 1 TO nLenEff DO                       // 逐点写出（显式上界，无 VLA）/ Write points with explicit bound
        aResp[i] := fTerm;                       // h(t_k) = (K/T)·e^(-k·Ts/T) / Sampled impulse response
        fTerm := fTerm * fDecay;                 // 迭代衰减（避免逐点 EXP 开销）/ Iterative decay
    END_FOR
    bDone := TRUE;                               // 完成脉冲（单拍，段 0 下拍自清）/ Done pulse for one cycle
END_IF
END_FUNCTION_BLOCK
