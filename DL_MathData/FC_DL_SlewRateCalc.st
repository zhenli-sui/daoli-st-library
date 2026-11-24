(*
  ==================================================================
  组件名 Component  : FC_DL_SlewRateCalc
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : 采样间变化率：fRate = (fCurVal − fPrevVal) / fDtSec
                      [工程单位/s]。fDtSec ≤ 0 闸（除法前置，含容差判零
                      语义：≤0 即拒）；输入非有限闸；差值/结果非有限复
                      核（有限大数相减可溢出 Inf）。纯无状态函数，采样
                      时刻由调用方维护（前后两次采样值由调用方快照传入），
                      本件不驻留上拍数据。
  来源   Source     : t2-1-lgf-technology（差分变化率为公开数值口径，
                      实现零源码复制）
  互引   Cross-ref  : FB_DL_CycleTimeMeasure（同族周期测量件：其扫描周期
                      口径可作 fDtSec 注入来源）；FC_DL_NormTo01（同族
                      数学原子邻件）
  平台   Platform   : 纯 IEC 61131-3 四则 + ABS，三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 除零闸（dt ≤ 0 前置）+ 非有限三面闸（输入/差值/
                      结果）/R5 全变量双语同行注释/R6 纯函数无状态机
                      （CASE 不适用）/R7 无定时器与沿检测/R8 容差常量化
  错误码 Codes      : 01【失效级】采样间隔非法（fDtSec ≤ 0），返回 0
                      02【失效级】任一输入非有限（NaN 自反判 / Inf 上限
                      兜底判）或差值/结果非有限，返回 0
  码位反证 Note     : 01/02 分立依据（R90）：01 在时基面（调用方采样节拍
                      组态/断拍）、02 在数据面可观测；02 若并入 01，则
                      「时基正常仍失败」的数据病态将不可观测，故必须分立。
  验收   Acceptance : V1 10→12 / dt=0.5s → 4 [u/s] ｜ V2 dt=0 → 码 01
                      ｜ V3 dt=−1 → 码 01 ｜ V4 含 NaN → 码 02 ｜
                      V5 1E308→−1E308 / dt=1 → 码 02（差值 Inf）
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 2 序 4）
  ==================================================================
*)
FUNCTION FC_DL_SlewRateCalc : LREAL
VAR_INPUT
    fCurVal  : LREAL;  // 当前采样值 [工程单位] / the current sample value
    fPrevVal : LREAL;  // 前一采样值（调用方快照）[工程单位] / the previous sample value, snapshot by the caller
    fDtSec   : LREAL;  // 采样间隔 [s]，须 > 0 / the sample interval in seconds, must be positive
END_VAR
VAR_OUTPUT
    bValid : BOOL;     // 变化率可用标志 [-] / the slew rate usable flag
    nErrId : UDINT;    // 错误码，0=正常，01/02 见头注 [码] / the error code [code]
END_VAR
VAR
    fDelta : LREAL;    // 差值工作寄存器 [工程单位] / the delta working register
END_VAR
VAR CONSTANT
    SRC_FIN_MAX  : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    SRC_ERR_NONE : UDINT := 16#0000_0000;           // 无错误 [码] / no error [code]
    SRC_ERR_DT   : UDINT := 16#0000_0001;           // 码 01：采样间隔非法 / code 01, illegal interval
    SRC_ERR_NAN  : UDINT := 16#0000_0002;           // 码 02：非有限 / code 02, non finite
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
FC_DL_SlewRateCalc := 0.0;  // 失效缺省返回 0 / fault default returns zero
bValid := FALSE;            // 预置不可用 / preset unusable
nErrId := SRC_ERR_NONE;     // 预置无错误 / preset no error

// 段 2｜采样间隔闸（码 01）：除法前置，≤0 即拒（含 dt 非有限：NaN 与任何
//      比较为 FALSE，会漏闸，故先自反判）/ segment 2, the interval gate
IF (fDtSec <> fDtSec) OR (fDtSec <= 0.0) THEN
    nErrId := SRC_ERR_DT;   // 时基面失效 / the time base failure
    RETURN;
END_IF

// 段 3｜输入非有限闸（码 02）/ segment 3, the input finite gate
IF (fCurVal <> fCurVal) OR (fPrevVal <> fPrevVal)
   OR (ABS(fCurVal) > SRC_FIN_MAX) OR (ABS(fPrevVal) > SRC_FIN_MAX) OR (ABS(fDtSec) > SRC_FIN_MAX) THEN
    nErrId := SRC_ERR_NAN;
    RETURN;
END_IF

// 段 4｜差分与除法（分母 = fDtSec，段 2 已闸）/ segment 4, the delta and the division
fDelta := fCurVal - fPrevVal;             // 差值 [工程单位] / the delta
IF (fDelta <> fDelta) OR (ABS(fDelta) > SRC_FIN_MAX) THEN
    nErrId := SRC_ERR_NAN;                // 有限差溢出 Inf 兜底 / the delta overflow fallback
    RETURN;
END_IF
FC_DL_SlewRateCalc := fDelta / fDtSec;    // 变化率 [工程单位/s] / the slew rate
IF (FC_DL_SlewRateCalc <> FC_DL_SlewRateCalc) OR (ABS(FC_DL_SlewRateCalc) > SRC_FIN_MAX) THEN
    nErrId := SRC_ERR_NAN;                // 结果非有限复核 / the result finiteness recheck
    FC_DL_SlewRateCalc := 0.0;            // 失效回缺省 0 / fault default zero
    RETURN;
END_IF
bValid := TRUE;                           // 变化率可用 / the slew rate is usable
END_FUNCTION
