(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ShewhartRules
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : Shewhart 控制图判异位图（Western Electric/Nelson 8 条
 *                         判异准则，公开判据 clean-room 自实现，零文本移植）：
 *                           bit1 单点越 3σ ｜ bit2 连续 9 点同侧 CL
 *                           bit3 连续 6 点单调递升或递降 ｜ bit4 连续 14 点
 *                           交替升降 ｜ bit5 连续 3 点中 2 点越 2σ 同侧
 *                           bit6 连续 5 点中 4 点越 1σ 同侧 ｜ bit7 连续 15 点
 *                           在 1σ 带内 ｜ bit8 连续 8 点在 1σ 带外
 *                         z = (fSample − fCL) ÷ fSigma；连长计数 nRunLen（同侧
 *                         CL 连续点数，换侧归 1）；滚动历史窗 15 点（aZ 倒序
 *                         数组，[0] 最新），窗未填满只评低深度规则（边界防御，
 *                         规格指定）。复位清全部计数与历史。
 * 接口     (Interface)  : 输入 fSample 观测样本、fCL 中心线、fSigma 标准差
 *                         （域 > 0）、bReset 复位；输出 uRuleBits 判异位图
 *                         （bit1..bit8）、nRunLen 同侧连长 [点]、bAlarm 任一
 *                         判异命中、nFill 历史窗填充数（诊断透读）、eErrCode
 *                         错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做判异位图与连长计数，
 *                         不做控制限计算、不接管报警管理**；σ 估计归统计件。
 *                         ② 滚动窗边界防御：aZ 定长 0..14，入窗移位 FOR 自深
 *                         至浅（界宽常量 15，无越界）；规则 k 只在 nFill >= k
 *                         所需深度时评估（bit4 需 14 点、bit7 需 15 点，未填
 *                         满不评，防上电零历史假阳性）。
 *                         ③ 连长窗口滚动：换侧（z 符号变化）或 z=0 归 1；
 *                         同侧递增；bit2 = nRunLen >= 9。
 *                         ④ 非有限判据（R79 双判）：样本非有限 → 跳过入窗与
 *                         计数（窗口不污染），信息码 eSampleSkip，位图保持
 *                         上拍（锁存语义，非单拍抹除）。
 *                         ⑤ 组态闸：fSigma <= 0 或非有限 → 锁存故障 eCfgBad，
 *                         位图清零安全侧，解除沿 = bReset 上升沿（R45 配对）。
 *                         ⑥ 单调判据用严格不等号（相等点不打断单调链的口径
 *                         为「相等即中断」保守侧，头注释声明）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_CpkCalc`/`FB_DL_CpkIndex` 分工：过程能力
 *                         指数归那件、逐点判异归本件；与 `FB_DL_ParticleCounterStat`
 *                         分工：粒子计数统计归那件。
 * 来源标签 (Source Tag) : 自研线（Western Electric/Nelson 8 判异准则为公开 SPC
 *                         定义 clean-room 自实现，零文本移植）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 WORD 位图 +
 *                         DINT 连长 + BOOL 组 + ENUM 错误码；数字码位待主控
 *                         收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 窗界防御 + 除数前置闸 + 非有限跳过 + 组态锁存
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 4 · 序号 16）
 * 验收向量 (Acceptance) : ① fCL=10, fSigma=1：单点 x=13.5 → z=3.5 > 3 →
 *                         uRuleBits.bit1=1，bAlarm=TRUE；② 连续 9 点
 *                         x=10.5（z=0.5 同侧）→ nRunLen=9，bit2=1；③ bit6：
 *                         最近 5 点 z=[1.2,1.1,1.4,1.0,1.3]（4 点 >=1）→
 *                         bit6=1；④ fSigma=0 → 锁存 eCfgBad；⑤ x=NaN →
 *                         eSampleSkip，窗不移位。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ShewErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ShewErr :
(
    eOk         := 0,   // 正常 / Normal
    eCfgBad     := 1,   // 故障级：fSigma 域非法（<=0 或非有限） / Fault: sigma illegal
    eSampleSkip := 2    // 信息级：样本非有限跳过，窗不移位 / Info: sample skipped, window held
);
END_TYPE

FUNCTION_BLOCK FB_DL_ShewhartRules
VAR_INPUT
    fSample : LREAL := 0.0;           // 观测样本 [工程单位] / Observed sample
    fCL     : LREAL := 0.0;           // 中心线 [工程单位] / Centre line
    fSigma  : LREAL := 1.0;           // 标准差，域 > 0 [工程单位] / Standard deviation
    bReset  : BOOL := FALSE;          // 复位，上升沿清位图/连长/历史窗全部计数 [-] / Reset clears all counters and window
END_VAR
VAR_OUTPUT
    uRuleBits : WORD;                 // 判异位图（bit1..bit8 对应 8 条准则） [-] / Rule bitmap, bits 1..8
    nRunLen   : DINT := 0;            // 同侧 CL 连长（换侧归 1） [点] / Same-side run length
    bAlarm    : BOOL;                 // 任一判异命中 [-] / Any rule hit
    nFill     : DINT := 0;            // 历史窗填充数（0..15，诊断透读） [点] / Window fill count
    eErrCode  : E_DL_ShewErr;         // 错误码出口 / Error code outlet
    bError    : BOOL;                 // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _aZ       : ARRAY[0..14] OF LREAL;   // z 值滚动历史窗（[0] 最新） [-] / Rolling z history window
    _uBits    : WORD;                 // 位图内部单源 / Bitmap internal source
    _nRun     : DINT := 0;            // 连长内部锁存 [点] / Run length latch
    _z        : LREAL;                // 当拍 z 分数 [-] / z score this scan
    _bSide    : BOOL;                 // 当拍样本在 CL 上侧（z > 0） [-] / Sample above CL
    _bSidePrev: BOOL := FALSE;        // 前拍样本侧别快照（换侧判据源） [-] / Previous sample side snapshot
    _bOk      : BOOL;                 // 当拍样本可入窗（有限 ∧ 无故障） [-] / Sample acceptable this scan
    _bNonFin  : BOOL;                 // 样本非有限当拍量 [-] / Sample non-finite
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    _bAlt     : BOOL;                 // 交替升降判据中间量 [-] / Alternation test intermediate
    _nHi3     : DINT;                 // 最近 3 点越 2σ 上侧计数 [点] / Count beyond +2 sigma in last 3
    _nLo3     : DINT;                 // 最近 3 点越 2σ 下侧计数 [点] / Count beyond -2 sigma in last 3
    _nHi5     : DINT;                 // 最近 5 点越 1σ 上侧计数 [点] / Count beyond +1 sigma in last 5
    _nLo5     : DINT;                 // 最近 5 点越 1σ 下侧计数 [点] / Count beyond -1 sigma in last 5
    _bIn15    : BOOL;                 // 最近 15 点全在 1σ 带内 [-] / All 15 within 1 sigma
    _bOut8    : BOOL;                 // 最近 8 点全在 1σ 带外 [-] / All 8 beyond 1 sigma
    _bMonoUp  : BOOL;                 // 最近 6 点单调递升 [-] / Six points monotonic rising
    _bMonoDn  : BOOL;                 // 最近 6 点单调递降 [-] / Six points monotonic falling
    i         : DINT;                 // 窗循环索引 / Window loop index
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_SHW_NWIN   : DINT  := 15;      // 历史窗定长 [点] / History window length
    DL_SHW_ZERO   : LREAL := 0.0;     // 判零基准 [-] / Zero base
    DL_SHW_SIG3   : LREAL := 3.0;     // bit1 判异倍率 [-] / Rule 1 sigma multiple
    DL_SHW_SIG2   : LREAL := 2.0;     // bit5 判异倍率 [-] / Rule 5 sigma multiple
    DL_SHW_SIG1   : LREAL := 1.0;     // bit6/7/8 判异倍率 [-] / Rule 6/7/8 sigma multiple
    DL_SHW_RUN9   : DINT  := 9;       // bit2 连长阈 [点] / Rule 2 run threshold
    DL_SHW_BIT1   : WORD  := 1;       // bit0 基准掩码（SHL 位移基准） [-] / Bit zero base mask
    DL_SHW_ZTOL   : LREAL := 1.0E-12; // 过零容差（|z| 低于此归换侧，禁浮点 = 判等） [-] / Zero-crossing tolerance
END_VAR

(* —— 段 0：组态闸 + 非有限判 + 沿刷新 —— *)
_bCfgBad := (fSigma <= DL_SHW_ZERO) OR (fSigma <> fSigma) OR ((fSigma - fSigma) <> DL_SHW_ZERO);   // σ 域闸（除数前置，R79 双判） / Sigma domain gate
_bNonFin := (fSample <> fSample) OR ((fSample - fSample) <> DL_SHW_ZERO);   // 样本非有限 / Sample non-finite
rtReset(CLK := bReset);               // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿（清位图/连长/填充数/历史窗全部计数，规格指定） —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;              // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
    _nRun := 0;                       // 清连长 / Clear run length
    nRunLen := 0;                     // 清连长出口 / Clear run outlet
    nFill := 0;                       // 清填充数 / Clear fill count
    _uBits := 0;                      // 清位图 / Clear bitmap
    FOR i := 0 TO (DL_SHW_NWIN - 1) DO
        _aZ[i] := DL_SHW_ZERO;        // 清历史窗 / Clear history window
    END_FOR
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;               // 锁存 / Latch
END_IF

(* —— 段 2：故障/正常分支分派（故障期位图安全侧清零、窗冻结） —— *)
IF _bErrLatch THEN
    _uBits := 0;                      // 故障安全侧位图清零（规格⑤） / Safe-side bitmap zero
ELSE
    _bOk := (NOT _bNonFin);           // 样本可入窗判据 / Sample acceptable
    IF _bOk THEN
        _uBits := 0;                  // 位图当拍重建（跳过拍保持上拍位图，规格④） / Rebuild bitmap on accepted samples
        _z := (fSample - fCL) / fSigma;   // z 分数（除数已闸，无除零） / z score
        _bSide := _z > DL_SHW_ZERO;   // 上侧判据（z=0 归换侧处理） / Above-CL test
        (* 滚动窗移位：自深至浅倒序拷贝，界宽常量 15 无越界 *)
        FOR i := (DL_SHW_NWIN - 1) TO 1 BY -1 DO
            _aZ[i] := _aZ[i - 1];     // 倒序拷贝 / Shift down
        END_FOR
        _aZ[0] := _z;                 // 最新样本入窗（唯一写入点） / Push newest
        IF nFill < DL_SHW_NWIN THEN
            nFill := nFill + 1;       // 填充数递增（上限 15） / Fill count up
        END_IF
        (* 连长计数：过零（容差）或换侧归 1，同侧递增 *)
        IF ABS(_z) < DL_SHW_ZTOL THEN
            _nRun := 1;               // 过零（|z| 低于容差）：连长归 1 / Zero crossing: reset to one
        ELSIF (nRunLen > 0) AND (_bSide <> _bSidePrev) THEN
            _nRun := 1;               // 换侧：连长归 1 / Side change: reset to one
        ELSE
            _nRun := nRunLen + 1;     // 首点（nRunLen=0）或同侧：递增 / First point or same side: increment
        END_IF
        nRunLen := _nRun;             // 连长落出口 / Run length outlet
        _bSidePrev := _bSide;         // 前拍侧别快照（下拍换侧判据源） / Side snapshot for next scan

        (* —— bit1：单点越 3σ —— *)
        IF ABS(_z) > DL_SHW_SIG3 THEN
            _uBits := _uBits OR SHL(DL_SHW_BIT1, 1);   // bit1 置位 / Set rule 1
        END_IF
        (* —— bit2：连续 9 点同侧 —— *)
        IF nRunLen >= DL_SHW_RUN9 THEN
            _uBits := _uBits OR SHL(DL_SHW_BIT1, 2);   // bit2 置位 / Set rule 2
        END_IF
        (* —— bit3：连续 6 点单调（相等即中断，保守侧，头注释⑥） —— *)
        IF nFill >= 6 THEN
            _bMonoUp := (_aZ[0] > _aZ[1]) AND (_aZ[1] > _aZ[2]) AND (_aZ[2] > _aZ[3])
                     AND (_aZ[3] > _aZ[4]) AND (_aZ[4] > _aZ[5]);   // 递升链 / Rising chain
            _bMonoDn := (_aZ[0] < _aZ[1]) AND (_aZ[1] < _aZ[2]) AND (_aZ[2] < _aZ[3])
                     AND (_aZ[3] < _aZ[4]) AND (_aZ[4] < _aZ[5]);   // 递降链 / Falling chain
            IF _bMonoUp OR _bMonoDn THEN
                _uBits := _uBits OR SHL(DL_SHW_BIT1, 3);   // bit3 置位 / Set rule 3
            END_IF
        END_IF
        (* —— bit4：连续 14 点交替升降（窗深 14） —— *)
        IF nFill >= 14 THEN
            _bAlt := TRUE;            // 交替判据起步 / Alternation preset
            FOR i := 1 TO 13 DO
                IF (( _aZ[i - 1] - _aZ[i]) * (_aZ[i] - _aZ[i + 1])) >= DL_SHW_ZERO THEN
                    _bAlt := FALSE;   // 相邻两差同号（含零差）：交替链断 / Same-sign diff: chain broken
                END_IF
            END_FOR
            IF _bAlt THEN
                _uBits := _uBits OR SHL(DL_SHW_BIT1, 4);   // bit4 置位 / Set rule 4
            END_IF
        END_IF
        (* —— bit5：最近 3 点中 2 点越 2σ 同侧 —— *)
        IF nFill >= 3 THEN
            _nHi3 := 0;               // 上侧计数清 / Hi count clear
            _nLo3 := 0;               // 下侧计数清 / Lo count clear
            FOR i := 0 TO 2 DO
                IF _aZ[i] >= DL_SHW_SIG2 THEN
                    _nHi3 := _nHi3 + 1;   // 越 +2σ 计数 / Count beyond +2 sigma
                ELSIF _aZ[i] <= (-DL_SHW_SIG2) THEN
                    _nLo3 := _nLo3 + 1;   // 越 -2σ 计数 / Count beyond -2 sigma
                END_IF
            END_FOR
            IF (_nHi3 >= 2) OR (_nLo3 >= 2) THEN
                _uBits := _uBits OR SHL(DL_SHW_BIT1, 5);   // bit5 置位 / Set rule 5
            END_IF
        END_IF
        (* —— bit6：最近 5 点中 4 点越 1σ 同侧 —— *)
        IF nFill >= 5 THEN
            _nHi5 := 0;               // 上侧计数清 / Hi count clear
            _nLo5 := 0;               // 下侧计数清 / Lo count clear
            FOR i := 0 TO 4 DO
                IF _aZ[i] >= DL_SHW_SIG1 THEN
                    _nHi5 := _nHi5 + 1;   // 越 +1σ 计数 / Count beyond +1 sigma
                ELSIF _aZ[i] <= (-DL_SHW_SIG1) THEN
                    _nLo5 := _nLo5 + 1;   // 越 -1σ 计数 / Count beyond -1 sigma
                END_IF
            END_FOR
            IF (_nHi5 >= 4) OR (_nLo5 >= 4) THEN
                _uBits := _uBits OR SHL(DL_SHW_BIT1, 6);   // bit6 置位 / Set rule 6
            END_IF
        END_IF
        (* —— bit7：连续 15 点在 1σ 带内（窗满才评） —— *)
        IF nFill >= DL_SHW_NWIN THEN
            _bIn15 := TRUE;           // 带内判据起步 / Within preset
            FOR i := 0 TO (DL_SHW_NWIN - 1) DO
                IF ABS(_aZ[i]) >= DL_SHW_SIG1 THEN
                    _bIn15 := FALSE;  // 任一点越带：判据断 / Any beyond band: broken
                END_IF
            END_FOR
            IF _bIn15 THEN
                _uBits := _uBits OR SHL(DL_SHW_BIT1, 7);   // bit7 置位 / Set rule 7
            END_IF
        END_IF
        (* —— bit8：连续 8 点在 1σ 带外 —— *)
        IF nFill >= 8 THEN
            _bOut8 := TRUE;           // 带外判据起步 / Beyond preset
            FOR i := 0 TO 7 DO
                IF ABS(_aZ[i]) < DL_SHW_SIG1 THEN
                    _bOut8 := FALSE;  // 任一点回带：判据断 / Any within band: broken
                END_IF
            END_FOR
            IF _bOut8 THEN
                _uBits := _uBits OR SHL(DL_SHW_BIT1, 8);   // bit8 置位 / Set rule 8
            END_IF
        END_IF
    END_IF
END_IF

(* —— 段 3：出口单点映射（名实双出口同源，R191） —— *)
uRuleBits := _uBits;                  // 位图出口 / Bitmap outlet
bAlarm := (_uBits <> 0);              // 任一判异命中 / Any rule hit
IF _bErrLatch THEN
    bError := TRUE;                   // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_ShewErr.eCfgBad; // 故障级码 / Fault code
ELSE
    bError := FALSE;                  // 无故障级条件 / No fault
    IF _bNonFin THEN
        eErrCode := E_DL_ShewErr.eSampleSkip;   // 信息级：样本跳过 / Info: skipped
    ELSE
        eErrCode := E_DL_ShewErr.eOk;           // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
