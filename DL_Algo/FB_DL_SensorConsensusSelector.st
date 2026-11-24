(*
  FB_DL_SensorConsensusSelector —— 多通道传感器共识选择：中位基准+偏差带剔除+通道不足降级到单通道，ENUM 状态机
  分类：DL_Algo | 复杂度：3 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT

  职责：对 5 路同类传感器做共识表决——有效通道数 ≥3 时取中位数作基准、剔除超出偏差带的通道后取平均（NORMAL）；
        有效数 =2 取均值、=1 直通（DEGRADED）；有效数 =0 保持上值并置 xLost（LOST）。
  输入契约：arrVal 通道值 [工程单位]；arrValid 通道有效位；fDevBand 偏差带半宽 [工程单位]（> 0）；
            fAbsMax 非有限闸与量程闸的绝对上限 [工程单位]。
  输出契约：fOut 共识值 [工程单位]；nValidOut 参与表决的有效通道数；xValid 本次输出可信；
            xDegraded / xLost 分级标志；eMode 表决模式枚举。
  边界：① 非有限双判（x <> x 判 NaN、ABS(x) > fAbsMax 判 Inf / 越界）逐通道执行；
        ② 除零防护：所有均值前判分母 > 0；③ 排序用插入法（FOR + WHILE 递减），无 FOR..DOWNTO；
        ④ CASE 含 ELSE 兜底把非法模式拦入 LOST；⑤ 零全局耦合、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ConsMode（共识表决模式，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ConsMode :
(
    eNormal   := 0,   // 正常共识（≥3 通道且带内 ≥3） [—] / Normal consensus with at least three in band channels
    eDegraded := 1,   // 降级（2 通道均值 / 1 通道直通 / 带内不足 3） [—] / Degraded consensus
    eLost     := 2    // 失效（零有效通道，保持上值） [—] / Lost, holds the previous value
);
END_TYPE

FUNCTION_BLOCK FB_DL_SensorConsensusSelector
VAR_INPUT
    xEnable  : BOOL  := TRUE;                             // 使能，FALSE 时按失效模式处理 [—] / Enable, false is treated as lost
    arrVal   : ARRAY[0..4] OF REAL;                       // 五路通道采样值 [工程单位] / Five channel samples
    arrValid : ARRAY[0..4] OF BOOL;                       // 五路通道有效位 [—] / Five channel validity flags
    fDevBand : REAL  := 1.0;                              // 偏差带半宽，必须 > 0 [工程单位] / Deviation band half width
    fAbsMax  : REAL  := 1.0E30;                           // 数值绝对上限（非有限 / 越界闸） [工程单位] / The absolute magnitude gate
END_VAR
VAR_OUTPUT
    fOut       : REAL;                                    // 共识输出值 [工程单位] / The consensus output value
    nValidOut  : INT;                                     // 参与表决的有效通道数 [个] / The number of channels taking part
    xValid     : BOOL;                                    // 本次输出可信 [—] / The output is trustworthy
    xDegraded  : BOOL;                                    // 降级标志 [—] / The degraded flag
    xLost      : BOOL;                                    // 失效标志 [—] / The lost flag
    eMode      : E_DL_ConsMode;                           // 表决模式枚举 [—] / The consensus mode enumeration
END_VAR
VAR
    afSort    : ARRAY[0..4] OF REAL;                      // 有效值排序缓冲（升序） [工程单位] / The ascending sort buffer
    nCnt      : INT;                                      // 有效通道数 [个] / The valid channel count
    nIn       : INT;                                      // 偏差带内通道数 [个] / The in band channel count
    k         : INT;                                      // 外层遍历索引 [下标] / The outer loop index
    j         : INT;                                      // 插入排序内层索引 [下标] / The insertion sort index
    fTmp      : REAL;                                     // 插入排序暂存量 [工程单位] / The insertion sort temporary
    fMed      : REAL;                                     // 中位数基准 [工程单位] / The median reference
    fSum      : REAL;                                     // 带内累加和 [工程单位] / The in band accumulation
    fMean     : REAL;                                     // 带内均值 [工程单位] / The in band mean
    fCand     : REAL;                                     // 候选输出值 [工程单位] / The candidate output value
    fDiff     : REAL;                                     // 单通道与中位数的偏差 [工程单位] / The deviation from the median
    fLastOut  : REAL;                                     // 上拍共识输出保持量 [工程单位] / The held previous output
    xHasLast  : BOOL;                                     // 是否已有可用上拍值 [—] / Whether a previous value exists
    eCand     : E_DL_ConsMode;                            // 候选表决模式 [—] / The candidate mode
END_VAR
VAR CONSTANT
    DL_CM_ZERO : INT := 0;                                // 整型零常量 [个] / The integer zero constant
    DL_CM_ONE  : INT := 1;                                // 整型一常量 [个] / The integer one constant
    DL_CM_NCH  : INT := 5;                                // 通道总数 [个] / The total channel count
    DL_CM_MINC : INT := 3;                                // 正常共识所需最少通道数 [个] / The minimum channels for normal consensus
    DL_CM_R0   : REAL := 0.0;                             // 浮点零常量 [工程单位] / The floating point zero constant
    DL_CM_EPS  : REAL := 1.0E-6;                          // 浮点比较容差 [工程单位] / The floating point comparison tolerance
END_VAR

// 段 1｜输出预置（单点预置，CASE 之后不再无条件清零）
xValid := FALSE;                                          // 可信位预置假 / preset the valid flag false
xDegraded := FALSE;                                       // 降级位预置假 / preset the degraded flag false
xLost := FALSE;                                           // 失效位预置假 / preset the lost flag false
nValidOut := DL_CM_ZERO;                                  // 有效通道数预置零 [个] / preset the valid count zero
nCnt := DL_CM_ZERO;                                       // 排序缓冲计数预置零 [个] / preset the buffer count zero
fMed := DL_CM_R0;                                         // 中位数预置零 [工程单位] / preset the median zero
fCand := fLastOut;                                        // 候选值默认继承上拍值 [工程单位] / default the candidate to the held value

// 段 2｜逐通道有效性 + 非有限闸，有效值收集进排序缓冲
FOR k := DL_CM_ZERO TO DL_CM_NCH - 1 DO                   // 五通道遍历（上界 4 已由常量钉死） / traverse all channels
    IF arrValid[k] THEN                                   // 通道有效位为真 / the channel is flagged valid
        IF (arrVal[k] <> arrVal[k]) THEN                  // 自反判 NaN / the self comparison catches NaN
            fTmp := DL_CM_R0;                             // 置暂存零（本通道将被剔除） / stage zero, channel dropped
        ELSIF ABS(arrVal[k]) > fAbsMax THEN               // 越绝对上限判 Inf / 越界 / beyond the magnitude gate
            fTmp := DL_CM_R0;                             // 置暂存零（本通道将被剔除） / stage zero, channel dropped
        ELSE
            afSort[nCnt] := arrVal[k];                    // 有效值入缓冲 [工程单位] / store the valid value
            nCnt := nCnt + DL_CM_ONE;                     // 有效计数自增 [个] / increment the valid count
        END_IF
    END_IF
END_FOR
nValidOut := nCnt;                                        // 有效通道数出口 [个] / publish the valid count

// 段 3｜插入排序升序（WHILE 显式递减，禁 FOR..DOWNTO）
FOR k := DL_CM_ONE TO nCnt - DL_CM_ONE DO                 // 从第二个元素起逐个插入 / insert every element from the second
    IF k >= DL_CM_ONE THEN                                // k 合法且缓冲至少有 k+1 个元素 / k is legal with enough elements
        fTmp := afSort[k];                                // 取出待插入元素 [工程单位] / take the element to insert
        j := k - DL_CM_ONE;                               // 内层索引从 k-1 起 / the inner index starts at k minus one
        WHILE (j >= DL_CM_ZERO) AND (afSort[j] > fTmp) DO // 显式递减并判下界 / explicit decrement with a bound check
            afSort[j + DL_CM_ONE] := afSort[j];           // 逆序元素右移一格 / shift the larger element right
            j := j - DL_CM_ONE;                           // 内层索引递减 [下标] / decrement the inner index
        END_WHILE
        afSort[j + DL_CM_ONE] := fTmp;                    // 待插入元素落位 [工程单位] / land the element
    END_IF
END_FOR

// 段 4｜按有效通道数分档：中位数基准 + 偏差带剔除 + 候选模式判定
IF (NOT xEnable) OR (nCnt = DL_CM_ZERO) THEN              // 未使能或零有效通道 / disabled or no valid channel
    eCand := E_DL_ConsMode.eLost;                         // 候选模式判失效 / the candidate mode is lost
ELSIF nCnt = DL_CM_ONE THEN                               // 单通道直通 / a single channel passes through
    fCand := afSort[0];                                   // 直通该通道值 [工程单位] / pass the single value
    eCand := E_DL_ConsMode.eDegraded;                     // 候选模式判降级 / the candidate mode is degraded
ELSIF nCnt = DL_CM_ONE + DL_CM_ONE THEN                   // 双通道取均值 / two channels take the mean
    fCand := (afSort[0] + afSort[1]) / 2.0;               // 双通道均值 [工程单位] / the mean of the two channels
    eCand := E_DL_ConsMode.eDegraded;                     // 候选模式判降级 / the candidate mode is degraded
ELSE                                                      // 三通道及以上做中位基准表决 / three or more channels vote
    IF (nCnt MOD 2) = DL_CM_ONE THEN                      // 奇数个取正中位 / odd count takes the middle element
        fMed := afSort[nCnt / 2];                         // 中位数基准 [工程单位] / the median reference
    ELSE
        fMed := (afSort[nCnt / 2 - DL_CM_ONE] + afSort[nCnt / 2]) / 2.0; // 偶数个取中间两值均值 [工程单位]
    END_IF
    nIn := DL_CM_ZERO;                                    // 带内计数清零 [个] / clear the in band count
    fSum := DL_CM_R0;                                     // 带内和清零 [工程单位] / clear the in band sum
    FOR k := DL_CM_ZERO TO nCnt - DL_CM_ONE DO             // 遍历有效通道做偏差带剔除 / filter by the deviation band
        fDiff := afSort[k] - fMed;                        // 与中位数的偏差 [工程单位] / the deviation from the median
        IF ABS(fDiff) <= fDevBand THEN                    // 带内（含边界，容差口径） / inside the band
            fSum := fSum + afSort[k];                     // 累加带内值 [工程单位] / accumulate the in band value
            nIn := nIn + DL_CM_ONE;                       // 带内计数自增 [个] / increment the in band count
        END_IF
    END_FOR
    IF nIn >= DL_CM_MINC THEN                             // 带内至少 3 通道 / at least three channels stay in band
        fMean := fSum / INT_TO_REAL(nIn);                 // 带内均值（分母 ≥3 已证非零） [工程单位] / the in band mean
        fCand := fMean;                                   // 候选输出取带内均值 [工程单位] / the candidate is the mean
        eCand := E_DL_ConsMode.eNormal;                    // 候选模式判正常 / the candidate mode is normal
    ELSIF nIn = DL_CM_ONE + DL_CM_ONE THEN                // 带内仅剩 2 通道 / only two channels stay in band
        fMean := fSum / 2.0;                              // 两通道均值 [工程单位] / the mean of the two channels
        fCand := fMean;                                   // 候选输出取该均值 [工程单位] / the candidate is that mean
        eCand := E_DL_ConsMode.eDegraded;                 // 候选模式判降级 / the candidate mode is degraded
    ELSE                                                  // 带内不足 2 通道，退回中位基准 / too few in band, fall back to the median
        fCand := fMed;                                    // 候选输出取中位数 [工程单位] / the candidate is the median
        eCand := E_DL_ConsMode.eDegraded;                 // 候选模式判降级 / the candidate mode is degraded
    END_IF
END_IF

// 段 5｜模式出口分派（ENUM + CASE，ELSE 拦截非法模式）
CASE eCand OF
    E_DL_ConsMode.eNormal:
        fOut := fCand;                                    // 正常模式直接输出候选值 [工程单位] / publish the candidate
        xValid := TRUE;                                   // 置可信位 [—] / raise the valid flag
        xDegraded := FALSE;                               // 清降级位 [—] / clear the degraded flag
        xLost := FALSE;                                   // 清失效位 [—] / clear the lost flag
        fLastOut := fOut;                                 // 刷新保持量 [工程单位] / refresh the held value
        xHasLast := TRUE;                                 // 保持量可用 [—] / the held value is now available
    E_DL_ConsMode.eDegraded:
        fOut := fCand;                                    // 降级模式输出候选值 [工程单位] / publish the candidate
        xValid := TRUE;                                   // 降级输出仍可信 [—] / a degraded output is still valid
        xDegraded := TRUE;                                // 置降级位 [—] / raise the degraded flag
        xLost := FALSE;                                   // 清失效位 [—] / clear the lost flag
        fLastOut := fOut;                                 // 刷新保持量 [工程单位] / refresh the held value
        xHasLast := TRUE;                                 // 保持量可用 [—] / the held value is now available
    E_DL_ConsMode.eLost:
        IF xHasLast THEN                                  // 已有上拍值 / a previous value exists
            fOut := fLastOut;                             // 保持上拍值 [工程单位] / hold the previous value
        ELSE
            fOut := DL_CM_R0;                             // 无上拍值输出零哨兵 [工程单位] / zero sentinel without history
        END_IF
        xValid := FALSE;                                  // 失效输出不可信 [—] / the lost output is not valid
        xDegraded := TRUE;                                // 失效同时视为降级 [—] / lost is also degraded
        xLost := TRUE;                                    // 置失效位 [—] / raise the lost flag
ELSE
    fOut := DL_CM_R0;                                     // 非法模式输出零哨兵 [工程单位] / illegal mode outputs the zero sentinel
    xValid := FALSE;                                      // 非法模式不可信 [—] / an illegal mode is not valid
    xDegraded := TRUE;                                    // 非法模式视为降级 [—] / an illegal mode is degraded
    xLost := TRUE;                                        // 非法模式视为失效 [—] / an illegal mode is lost
    eCand := E_DL_ConsMode.eLost;                          // 非法模式回写为失效 [—] / normalise the illegal mode to lost
END_CASE
eMode := eCand;                                           // 模式枚举单点出口 / the single point mode outlet
END_FUNCTION_BLOCK
