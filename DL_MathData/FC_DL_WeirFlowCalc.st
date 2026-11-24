(*
  道莅工业代码库 | DL_MathData | FC_DL_WeirFlowCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；薄壁堰/宽顶堰过流公式为水力学公开公式，零代码行复制）
  功能: 堰流过流量计算——薄壁堰 Q = (2/3)·Cd·b·√(2g)·hu^1.5 与宽顶堰
        Q = Mb·b·√(2g)·hu^1.5，含淹没流判别（hd/hu > 阈值）与淹没折减因子。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 SQRT/ABS，零厂商私有库
  接口: 输入堰上水头/堰下（下游）水头/堰宽/堰型/两系数/淹没判别比；函数返回值
        = 过流量 [m3/s]（非法入参返回 0.0），输出 bSubmerged/bValid/eErr。
        纯函数：无内部状态，每拍独立全量重算。
  码表: 16#0001_03FF 故障级：入参域非法（水头/宽度/系数越域或非有限）→ bValid=FALSE
        码段说明：0001 段故障子带 03xx，03FF 槽经全库实扫空闲。
  边界: ① 域闸：hu > 0、b > 0、Cd > 0、Mb > 0、0 < 淹没比 < 1，全部入参 NaN 自反判；
        ② 淹没判别 hd/hu 除法前由 hu > 0 域闸保证；
        ③ 淹没折减因子 √(1 - r^1.5) 底数用 MAX(0, ·) 钳非负，杜绝负数开方；
        ④ hu^1.5 以 hu·√hu 实现（同幂等价，免 EXPT 泛型疑义）；
        ⑤ 全部输出在所有路径（含提前返回）赋值；⑥ 零全局耦合。
  邻件比对: OrificeFlowCalc（孔口流 vs 堰流，公式域不同）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B2 · C06）
*)

FUNCTION FC_DL_WeirFlowCalc : REAL
VAR_INPUT
    fHeadUp     : REAL := 0.0;    // 堰上水头（高于堰顶），域 > 0 [m] | Upstream head above crest
    fHeadDown   : REAL := 0.0;    // 堰下（下游）水头（高于堰顶）[m] | Downstream head above crest
    fWidth      : REAL := 1.0;    // 堰宽（垂直流向有效宽度），域 > 0 [m] | Weir crest width
    bBroadCrest : BOOL := FALSE;  // 堰型选择：TRUE=宽顶堰，FALSE=薄壁堰 [-] | TRUE = broad-crested, FALSE = thin-plate
    fCd         : REAL := 0.611;  // 薄壁堰流量系数，域 > 0 [-] | Thin-plate discharge coefficient
    fMb         : REAL := 0.36;   // 宽顶堰流量系数，域 > 0 [-] | Broad-crested discharge coefficient
    fSubmRatio  : REAL := 0.75;   // 淹没判别比阈值，域 (0, 1) [-] | Submergence ratio threshold
END_VAR
VAR_OUTPUT
    bSubmerged : BOOL;            // 本拍淹没流判别结果 [-] | Submerged flow judgement
    bValid     : BOOL;            // 本次计算有效 [-] | Computation valid
    eErr       : UDINT;           // 错误码，0 = 无错 | Error code, 0 = none
END_VAR
VAR
    fHu15    : REAL;              // 堰上水头 1.5 次幂 hu^1.5 [m^1.5] | Upstream head to power 1.5
    fRatio   : REAL;              // 淹没比 hd/hu [-] | Submergence ratio
    fRatio15 : REAL;              // 淹没比 1.5 次幂 r^1.5 [-] | Ratio to power 1.5
    fFactor  : REAL;              // 淹没折减因子 [-] | Submergence reduction factor
    fCoef    : REAL;              // 按堰型选定的合成系数 [-] | Combined coefficient by weir type
    fQ       : REAL;              // 过流量暂存 [m3/s] | Flow staging
    bInOk    : BOOL;              // 入参域合法当拍量 [-] | Input domain legal this call
END_VAR
VAR CONSTANT
    DL_WFC_G2   : REAL := 19.62;      // 重力加速度二倍 2g [m/s2] | Twice gravity
    DL_WFC_EPS  : REAL := 1.0E-6;     // 判零容差（水头/宽度近零判据） | Zero threshold tolerance
    DL_WFC_ERR  : UDINT := 16#0001_03FF;  // 入参域非法码 | Illegal input domain code
END_VAR

(* —— 段 0：输出缺省全赋值（全路径覆盖） —— *)
bSubmerged := FALSE;              // 淹没判别预置 FALSE / Submerged preset FALSE
bValid := FALSE;                  // 有效标志预置 FALSE / Valid preset FALSE
eErr := 0;                        // 错误码缺省 / Error default
fQ := 0.0;                        // 流量暂存清零（防御） / Flow staging cleared
FC_DL_WeirFlowCalc := 0.0;        // 返回值缺省零（非法路径出口） / Return default zero

(* —— 段 1：入参域闸（NaN 自反判 + 域上下界） —— *)
bInOk := (fHeadUp > DL_WFC_EPS) AND (fWidth > DL_WFC_EPS)
      AND (fCd > 0.0) AND (fMb > 0.0)
      AND (fSubmRatio > 0.0) AND (fSubmRatio < 1.0)
      AND (fHeadUp = fHeadUp) AND (fHeadDown = fHeadDown)
      AND (fWidth = fWidth) AND (fCd = fCd) AND (fMb = fMb) AND (fSubmRatio = fSubmRatio);
IF NOT bInOk THEN
    eErr := DL_WFC_ERR;           // 域非法码 / Domain illegal code
    RETURN;                       // 提前返回：输出已全赋值 / Early return, outputs assigned
END_IF

(* —— 段 2：淹没判别（除法分母 hu > EPS 已由域闸证明） —— *)
fRatio := fHeadDown / fHeadUp;    // 淹没比 hd/hu / Submergence ratio
bSubmerged := fRatio > fSubmRatio;  // 淹没判别 / Submerged judgement
IF fRatio < 0.0 THEN
    fRatio := 0.0;                // 负下游水头（低于堰顶）钳零 / Negative downstream head clamped
END_IF

(* —— 段 3：过流量主式（按堰型选系数） —— *)
fHu15 := fHeadUp * SQRT(fHeadUp); // hu^1.5 = hu·√hu / Head to power 1.5
IF bBroadCrest THEN
    fCoef := fMb;                 // 宽顶堰系数 / Broad-crested coefficient
ELSE
    fCoef := (2.0 / 3.0) * fCd;   // 薄壁堰系数 (2/3)·Cd / Thin-plate coefficient
END_IF
fQ := fCoef * fWidth * SQRT(DL_WFC_G2) * fHu15;   // 自由出流过流量 [m3/s] / Free flow discharge

(* —— 段 4：淹没折减（因子底数钳非负，杜绝负数开方） —— *)
IF bSubmerged THEN
    fRatio15 := fRatio * SQRT(fRatio);                  // r^1.5 = r·√r（r ≥ 0 已钳）/ Ratio to power 1.5
    fFactor := SQRT(MAX(0.0, 1.0 - fRatio15));          // 折减因子 ∈ [0, 1] / Reduction factor clamped non-negative
    fQ := fQ * fFactor;                                 // 淹没过流量 [m3/s] / Submerged discharge
END_IF

(* —— 段 5：出口赋值 —— *)
FC_DL_WeirFlowCalc := fQ;         // 返回过流量 [m3/s] / Return discharge
bValid := TRUE;                   // 计算有效 / Valid

END_FUNCTION
