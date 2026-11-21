(*
  ==================================================================
  组件名 Component  : FC_DL_Affine2DChain
  分类   Category   : DL_MathData
  复杂度 Complexity  : 中
  版本   Version    : 1.0.1
  功能   Purpose    : N 级 2D 仿射链一次合成。输入 nCount 个 3×3 齐次矩阵，按
                      固定次序合成 MOut = Mn × … × M2 × M1（列向量约定，先施加
                      M1），中间任一奇异即整体失效并置故障码，不外泄半结果。
  来源   Source     : t2-1-lgf-math（LGF Math 仿射族多级链合成）
  溯源   Origin     : 矩阵链式合成属公开线性代数语义，clean-room 自研实现（逐级
                      委托本库 FC_DL_Affine2DCompose 内核），未复制任何厂商源码。
  平台   Platform   : 纯 IEC 61131-3（仅 FOR / 数组 / 委托调用），三平台通用
  分工声明 Split     : 与 FC_DL_Affine2DCompose（两级属主）互补——后者只合成
                      两级并负责行列式相对判据；本件做 N 级链调度、退化分支与
                      链级码位装配，不重实现乘法内核、不重声明任何矩阵类型。
  依赖     Depends  : FC_DL_Affine2DCompose（DL_MathData 属主，本件逐级委托）
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 合成次序写死列向量约定 MOut = Mn × … × M1：M1 先施加，
                         Mn 后施加；调用方若要行向量约定须自行转置，本件不设开关；
                      二 链长退化显式：nCount ≤ 0 输出单位阵并置信息级码；nCount
                         超 8 级钳位续算并置信息级码（不静默截断）；
                      三 有限性闸逐个枚举浮点输入：本件声明区 LREAL 输入集合 =
                         afMats 的 9 × nCount 个元素，闸内逐元素引用同一集合，
                         无标量 LREAL 引脚（R272 覆盖自证：9×nUsed 全枚举）；
                      四 中途奇异或中途非有限即整体失效：bValid = FALSE、输出
                         保持单位阵（不外泄半结果），故障码一次锁存于本次调用；
                      五 只读输入矩阵，不改调用方数组（PercentileLReal 纪律）。
  错误码   Codes    :
    16#0001_0620【故障级】中间阵奇异或委托内核判不可用，链合成终止
    16#0001_0621【故障级】输入矩阵含非有限元素（NaN / Inf），链合成终止
    16#0001_0622【信息级】链长越域已钳位（≤0 出单位阵，>8 钳到 8 级）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 两级：M1 平移 (1,2)、M2 缩放 ×2 → 单位点 (0,0) 过链得 (2,4)
    V2 nCount=0 → 单位阵、bValid=TRUE、码 0622
    V3 第二级首行全零（奇异）→ bValid=FALSE、码 0620、输出仍为单位阵
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 2 · 序号 6）
    2026-11-21  v1.0.1  R61 返修：D5 累加器改单位阵起步、逐级全委托（含
                        nUsed=1 单级链奇异判，R284）；D6 信息级 0622 两处
                        不再置 bError（R285 口径统一）
  ==================================================================
*)
FUNCTION FC_DL_Affine2DChain : BOOL
VAR_IN_OUT
    afMats : ARRAY[0..7, 0..2, 0..2] OF LREAL; // 链矩阵组 [无量纲 + 用户单位混合]，行主序，第 0 级先施加 / the chain matrices, row major, level zero applied first
END_VAR
VAR_INPUT
    nCount : DINT; // 链级数 [级]，合法域 1..8 / the chain level count, legal from one to eight
END_VAR
VAR_OUTPUT
    afMOut : ARRAY[0..2, 0..2] OF LREAL; // 合成矩阵 [无量纲 + 用户单位混合] / the composed matrix
    bValid : BOOL;                       // 结果可用标志（链中任一级失效即假）[-] / the result usable flag
    eErr   : UDINT;                      // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;                       // 故障锁存标志 [-] / the fault flag
END_VAR
VAR
    afAcc     : ARRAY[0..2, 0..2] OF LREAL; // 累加矩阵（当前已合成结果） / the accumulator of the composed so far
    afTmp     : ARRAY[0..2, 0..2] OF LREAL; // 本级乘积暂存（检过才接替累加器） / the staging product of this level
    afMk      : ARRAY[0..2, 0..2] OF LREAL; // 本级矩阵切片副本（三维数组不可直接切片传参） / the slice copy of this level
    nLevel    : DINT;  // 级遍历索引 [级] / the level loop index
    nI        : DINT;  // 行索引 [行] / the row index
    nJ        : DINT;  // 列索引 [列] / the column index
    nUsed     : DINT;  // 钳位后的实际级数 [级] / the clamped level count
    bAbort    : BOOL;  // 链终止标志（有限闸或奇异闸命中）[-] / the chain abort flag
    bClamped  : BOOL;  // 链长钳位标记 [-] / the level clamp flag
    bSubValid : BOOL;  // 委托内核结果可用位 [-] / the delegate usable bit
    bSubErr   : BOOL;  // 委托内核故障位 [-] / the delegate fault bit
    uSubErr   : UDINT; // 委托内核错误码 [码] / the delegate error code
END_VAR
VAR CONSTANT
    DL_A2CH_CHMAX : DINT := 8; // 链级数上界 [级]，与数组第 1 维一致 / the level bound aligned with the first dimension
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 输出预置单位阵 / segment 1, the preset of the return, the codes and the identity matrix
FC_DL_Affine2DChain := FALSE; // 返回值预置假 / preset the return false
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the error flag false
bAbort := FALSE; // 终止标志预置假 / preset the abort flag false
bClamped := FALSE; // 钳位标记预置假 / preset the clamp flag false
bSubValid := FALSE; // 委托有效位预置假 / preset the delegate usable bit false
bSubErr := FALSE; // 委托故障位预置假 / preset the delegate fault bit false
uSubErr := 16#0000_0000; // 委托码预置零 / preset the delegate code zero
nUsed := 0; // 实际级数预置零 / preset the used level zero
FOR nI := 0 TO 2 DO // 单位阵装配 / build the identity matrix
    FOR nJ := 0 TO 2 DO // 列遍历 / the column loop
        IF nI = nJ THEN // 主对角 / the main diagonal
            afMOut[nI, nJ] := 1.0; // 对角置一 / unit on the diagonal
            afAcc[nI, nJ] := 1.0; // 累加器同步置一 / the accumulator seeded the same
        ELSE // 非对角 / the off diagonal
            afMOut[nI, nJ] := 0.0; // 非对角置零 / zero off the diagonal
            afAcc[nI, nJ] := 0.0; // 累加器同步置零 / the accumulator seeded the same
        END_IF
        afTmp[nI, nJ] := 0.0; // 暂存阵清零 / clear the staging matrix
        afMk[nI, nJ] := 0.0; // 切片副本清零 / clear the slice copy
    END_FOR
END_FOR

// 段 2｜链长域闸（退化与钳位显式，边界二）/ segment 2, the level count gate with the explicit degenerate branch
IF nCount < 1 THEN // 链长为零或负：退化为单位阵 / a non positive count degenerates to the identity
    eErr := 16#0001_0622; // 信息级：链长越域已钳位（信息级不置 bError，R285 口径统一，D6 返修）/ informational, the level count clamped, no fault bit
    bValid := TRUE; // 单位阵是合法结果 / the identity is a legal result
    FC_DL_Affine2DChain := TRUE; // 返回成功 / return success
    RETURN; // 早退：afMOut 已为单位阵（段 1 预置）/ early return with the identity already preset
END_IF
nUsed := nCount; // 域内接管级数 / take the count inside the domain
IF nUsed > DL_A2CH_CHMAX THEN // 超上界 / above the bound
    nUsed := DL_A2CH_CHMAX; // 钳到 8 级 / clamp to eight levels
    bClamped := TRUE; // 置钳位标记 / raise the clamp flag
END_IF

// 段 3｜有限性闸：9 × nUsed 个浮点元素逐个枚举（R272 覆盖自证，边界三）/ segment 3, the finiteness gate over every enumerated element
FOR nLevel := 0 TO nUsed - 1 DO // 级遍历 / the level loop
    FOR nI := 0 TO 2 DO // 行遍历 / the row loop
        FOR nJ := 0 TO 2 DO // 列遍历 / the column loop
            IF (afMats[nLevel, nI, nJ] <> afMats[nLevel, nI, nJ])
            OR ((afMats[nLevel, nI, nJ] - afMats[nLevel, nI, nJ]) <> (afMats[nLevel, nI, nJ] - afMats[nLevel, nI, nJ])) THEN // NaN 自反判 + Inf 差值自减判 / the NaN reflexive and the Inf difference tests
                bAbort := TRUE; // 置终止标志 / raise the abort flag
            END_IF
        END_FOR
    END_FOR
END_FOR
IF bAbort THEN // 输入含非有限 / a non finite input exists
    eErr := 16#0001_0621; // 故障级：输入矩阵含非有限元素 / fault grade, a non finite element in the input
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退：afMOut 保持单位阵（不外泄半结果，边界四）/ early return with the identity kept
END_IF

// 段 4｜逐级合成：MOut = Mn × … × M1（累加器以单位阵起步、逐级全委托；D5 返修：nUsed=1 单级链也走一次委托补奇异判，R284）/ segment 4, the per level composition, the accumulator starts from the identity and every level is delegated
FOR nLevel := 0 TO nUsed - 1 DO // 第 0..nUsed-1 级逐级合成（单位阵为左乘起点）/ compose from level zero with the identity seeded accumulator
  IF NOT bAbort THEN // 链未终止才继续合成（终止后不再用半结果继续乘）/ compose only while the chain is alive
    afMk[0, 0] := afMats[nLevel, 0, 0]; // 切片副本第 0 行第 0 列 / slice row zero column zero
    afMk[0, 1] := afMats[nLevel, 0, 1]; // 切片副本第 0 行第 1 列 / slice row zero column one
    afMk[0, 2] := afMats[nLevel, 0, 2]; // 切片副本第 0 行第 2 列 / slice row zero column two
    afMk[1, 0] := afMats[nLevel, 1, 0]; // 切片副本第 1 行第 0 列 / slice row one column zero
    afMk[1, 1] := afMats[nLevel, 1, 1]; // 切片副本第 1 行第 1 列 / slice row one column one
    afMk[1, 2] := afMats[nLevel, 1, 2]; // 切片副本第 1 行第 2 列 / slice row one column two
    afMk[2, 0] := afMats[nLevel, 2, 0]; // 切片副本第 2 行第 0 列 / slice row two column zero
    afMk[2, 1] := afMats[nLevel, 2, 1]; // 切片副本第 2 行第 1 列 / slice row two column one
    afMk[2, 2] := afMats[nLevel, 2, 2]; // 切片副本第 2 行第 2 列 / slice row two column two
    IF NOT FC_DL_Affine2DCompose(afM1 := afAcc, afM2 := afMk, afMOut => afTmp, eErr => uSubErr, bError => bSubErr, bValid => bSubValid) THEN // 委托两级内核（含行列式相对判据；nUsed=1 时 afAcc 为单位阵，单位阵左乘精确无损，单级奇异判由本次委托补齐，D5）/ delegate the two level kernel, the identity left multiply is exact
        bAbort := TRUE; // 本级不可用 / this level is unusable
    END_IF
    IF bAbort OR (NOT bSubValid) THEN // 奇异或不可用即整体终止 / a singular or unusable level aborts the chain
        bAbort := TRUE; // 锁住终止标志 / hold the abort flag
    ELSE // 本级通过：接替累加器 / this level passed, take over the accumulator
        afAcc[0, 0] := afTmp[0, 0]; // 累加器接替第 0 行第 0 列 / take over row zero column zero
        afAcc[0, 1] := afTmp[0, 1]; // 累加器接替第 0 行第 1 列 / take over row zero column one
        afAcc[0, 2] := afTmp[0, 2]; // 累加器接替第 0 行第 2 列 / take over row zero column two
        afAcc[1, 0] := afTmp[1, 0]; // 累加器接替第 1 行第 0 列 / take over row one column zero
        afAcc[1, 1] := afTmp[1, 1]; // 累加器接替第 1 行第 1 列 / take over row one column one
        afAcc[1, 2] := afTmp[1, 2]; // 累加器接替第 1 行第 2 列 / take over row one column two
        afAcc[2, 0] := afTmp[2, 0]; // 累加器接替第 2 行第 0 列 / take over row two column zero
        afAcc[2, 1] := afTmp[2, 1]; // 累加器接替第 2 行第 1 列 / take over row two column one
        afAcc[2, 2] := afTmp[2, 2]; // 累加器接替第 2 行第 2 列 / take over row two column two
    END_IF
  END_IF
END_FOR

// 段 5｜出口装配：仅在全链通过时外泄合成阵（边界四）/ segment 5, the outlet assembly, exported only when the whole chain passed
IF bAbort THEN // 链终止 / the chain aborted
    eErr := 16#0001_0620; // 故障级：中间阵奇异或不可用 / fault grade, a singular or unusable intermediate
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    FC_DL_Affine2DChain := FALSE; // 返回失败（afMOut 保持单位阵）/ return failure with the identity kept
ELSE // 全链通过 / the whole chain passed
    afMOut[0, 0] := afAcc[0, 0]; // 出口第 0 行第 0 列 / outlet row zero column zero
    afMOut[0, 1] := afAcc[0, 1]; // 出口第 0 行第 1 列 / outlet row zero column one
    afMOut[0, 2] := afAcc[0, 2]; // 出口第 0 行第 2 列 / outlet row zero column two
    afMOut[1, 0] := afAcc[1, 0]; // 出口第 1 行第 0 列 / outlet row one column zero
    afMOut[1, 1] := afAcc[1, 1]; // 出口第 1 行第 1 列 / outlet row one column one
    afMOut[1, 2] := afAcc[1, 2]; // 出口第 1 行第 2 列 / outlet row one column two
    afMOut[2, 0] := afAcc[2, 0]; // 出口第 2 行第 0 列 / outlet row two column zero
    afMOut[2, 1] := afAcc[2, 1]; // 出口第 2 行第 1 列 / outlet row two column one
    afMOut[2, 2] := afAcc[2, 2]; // 出口第 2 行第 2 列 / outlet row two column two
    bValid := TRUE; // 结果可用 / the result is usable
    FC_DL_Affine2DChain := TRUE; // 返回成功 / return success
    IF bClamped THEN // 链长被钳位 / the level count was clamped
        eErr := 16#0001_0622; // 信息级：链长越域已钳位（信息级不置 bError，R285 口径统一，D6 返修）/ informational, the level count clamped, no fault bit
    END_IF
END_IF
END_FUNCTION
