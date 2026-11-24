(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoopSignGuard
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商私有库
 * 功能描述 (Function)   : 回路正反作用符号在线自检（调试期防呆）。以增量对
 *                         (dCV, dPV) 为样本，窗口内计算皮尔逊相关系数
 *                         r = (nΣxy - ΣxΣy) / sqrt((nΣx²-(Σx)²)·(nΣy²-(Σy)²))：
 *                         r > fSignThresh → 判正向作用（CV 增大 PV 随之增大）；
 *                         r < -fSignThresh → 判反向作用；|r| 不足 → 未定。
 *                         期望作用 eExpect 与实测作用不一致 → bSignSuspect
 *                         锁存（接线反接/正反作用组态错防呆）。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 边界语义 (Boundary)   : ① 相关系数除零防御：分母任一因子 <= eps（窗口内
 *                         CV 或 PV 无变化，如手动手假输入）→ r 按 0 处理（未定），
 *                         不产生 Inf/NaN；
 *                         ② 样本拒收：dCV/dPV 非有限（NaN/Inf 差判）不入窗；
 *                         ③ 判据串相位因子：仅 nSample >= 窗深 60% 后才判
 *                         （样本不足不判，防启动段误报，R281 口径）；
 *                         ④ 组态闸：窗深 < 8 / 阈值域 (0,1) 外 → 故障。
 * 输出语义 (Fallback)   : 【R191】样本不足期 → eSignOut = eUnknown，bSignSuspect
 *                         保持 FALSE；eFault 相 → 判据输出冻结保持末值。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（双因子 eps 闸）/NaN 拒收/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 同向增量样本 32 点 → r≈1 → eSignOut=eDirect；
 *                         V2 反向增量样本 → r≈-1 → eSignOut=eReverse，若
 *                         eExpect=eDirect → bSignSuspect=TRUE；
 *                         V3 恒定 PV（分母 0）→ eSignOut=eUnknown，不误报。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 3 · 序号 11）
 *==============================================================================*)
TYPE E_DL_LsgSign :
(
    eUnknown := 0,                           (* 未定（样本不足或相关性弱） / Unknown *)
    eDirect  := 1,                           (* 正向作用：CV↑ → PV↑ / Direct acting *)
    eReverse := 2                            (* 反向作用：CV↑ → PV↓ / Reverse acting *)
);
END_TYPE

TYPE E_DL_LsgState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eLearn := 10,                            (* 增量样本采集学习中 / Learning *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_LsgCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：窗深/阈值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_LoopSignGuard
VAR_INPUT
    fCvNow    : LREAL := 0.0;                (* 控制量当前值（CV）[工程单位] / CV current value *)
    fPvNow    : LREAL := 0.0;                (* 过程量当前值（PV）[工程单位] / PV current value *)
    nWinDepth : INT := 32;                   (* 增量样本窗深，域 8..64 [点] / Sample window depth *)
    fSignThresh : LREAL := 0.6;              (* 判向阈值（|r| 门限），域 (0.0, 1.0) [-] / Sign verdict threshold *)
    eExpect   : E_DL_LsgSign := E_DL_LsgSign.eDirect;   (* 期望作用方向（组态声明）[-] / Expected acting direction *)
    bEnable   : BOOL := TRUE;                (* 自检使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清全部样本与锁存 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    eSignOut     : E_DL_LsgSign;             (* 实测作用方向出口 / Measured sign outlet *)
    fCorrCoef    : LREAL;                    (* 当前窗口皮尔逊相关系数 [-] / Pearson correlation of window *)
    nSampleCnt   : INT;                      (* 窗口内有效样本数 [点] / Valid sample count *)
    bSignSuspect : BOOL;                     (* 作用方向与期望不符锁存位（复位沿清）[-] / Sign-suspect latch *)
    eState       : E_DL_LsgState;            (* 状态出口 / State outlet *)
    eCause       : E_DL_LsgCause;            (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError       : BOOL;                     (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_LsgState := E_DL_LsgState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_LsgCause := E_DL_LsgCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fCvPrev : LREAL;                        (* 上拍 CV（增量基准）[工程单位] / Previous CV *)
    _fPvPrev : LREAL;                        (* 上拍 PV（增量基准）[工程单位] / Previous PV *)
    _aDx     : ARRAY[1..64] OF LREAL;        (* dCV 样本窗 [工程单位] / dCV window *)
    _aDy     : ARRAY[1..64] OF LREAL;        (* dPV 样本窗 [工程单位] / dPV window *)
    _nHead   : INT;                          (* 环形头游标 [-] / Ring head cursor *)
    _nFill   : INT;                          (* 窗口填充数 [点] / Window fill count *)
    _nEff    : INT;                          (* 钳位后生效窗深 [点] / Clamped effective depth *)
    _fSumX   : LREAL;                        (* Σx 累计 [工程单位] / Sum x *)
    _fSumY   : LREAL;                        (* Σy 累计 [工程单位] / Sum y *)
    _fSumXY  : LREAL;                        (* Σxy 累计 [工程单位²] / Sum xy *)
    _fSumX2  : LREAL;                        (* Σx² 累计 [工程单位²] / Sum x2 *)
    _fSumY2  : LREAL;                        (* Σy² 累计 [工程单位²] / Sum y2 *)
    _fDenX   : LREAL;                        (* 分母因子 1：nΣx²-(Σx)² [-] / Denominator factor 1 *)
    _fDenY   : LREAL;                        (* 分母因子 2：nΣy²-(Σy)² [-] / Denominator factor 2 *)
    _fDen    : LREAL;                        (* 相关系数分母（开方前乘积）[-] / Correlation denominator *)
    _fR      : LREAL;                        (* 本拍相关系数 [-] / Correlation this scan *)
    _eSign   : E_DL_LsgSign := E_DL_LsgSign.eUnknown;     (* 实测方向锁存 / Measured sign latch *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _i       : INT;                          (* 统计扫描游标（每趟重置，R227）[-] / Stats cursor *)
END_VAR
VAR CONSTANT
    DL_LSG_EPS   : LREAL := 1.0E-12;         (* 分母因子判零容差 [-] / Denominator epsilon *)
    DL_LSG_NMAX  : INT   := 64;              (* 窗深容量上限 [点] / Window capacity limit *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nWinDepth < 8) OR (nWinDepth > DL_LSG_NMAX) OR (fSignThresh <= 0.0) OR (fSignThresh >= 1.0);   (* 组态闸（R151 全引脚） / Config gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_nEff := nWinDepth;                          (* 生效窗深初值 / Effective depth init *)
IF _nEff < 8 THEN
    _nEff := 8;                              (* 窗深下限钳位 / Depth lower clamp *)
END_IF
IF _nEff > DL_LSG_NMAX THEN
    _nEff := DL_LSG_NMAX;                    (* 窗深上限钳位（R308） / Depth upper clamp *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_fSumX := 0.0;                               (* 累计量清零重算（每拍全路径派生，R285） / Sums recompute *)
_fSumY := 0.0;                               (* Σy 清零 / Sum y clear *)
_fSumXY := 0.0;                              (* Σxy 清零 / Sum xy clear *)
_fSumX2 := 0.0;                              (* Σx² 清零 / Sum x2 clear *)
_fSumY2 := 0.0;                              (* Σy² 清零 / Sum y2 clear *)
_fDen := 0.0;                                (* 分母清零（防 _nFill=0 残留触发除零） / Denominator clear *)
_fR := 0.0;                                  (* 相关系数缺省 0（未定语义） / Correlation default zero *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清窗 + 清方向锁存 + 清嫌疑锁存 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_LsgCause.eNone;          (* 清成因 / Clear cause *)
    _nFill := 0;                             (* 清窗填充 / Clear fill *)
    _nHead := 1;                             (* 头游标复位 / Head reset *)
    _eSign := E_DL_LsgSign.eUnknown;         (* 方向回未定 / Sign back to unknown *)
    bSignSuspect := FALSE;                   (* 清嫌疑锁存 / Clear suspect latch *)
    _fCvPrev := fCvNow;                      (* 增量基准重锚（防复位后巨增量） / Re-anchor increment base *)
    _fPvPrev := fPvNow;                      (* 同前一项，基准跟锚 / Same as previous line, anchor follow *)
    _eState := E_DL_LsgState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_LsgCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_LsgState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_LsgState.eIdle:                     (* 待机相 / Idle *)
        _fCvPrev := fCvNow;                  (* 增量基准持续跟锚（防待机期累积巨增量） / Anchor follow *)
        _fPvPrev := fPvNow;                  (* 同前一项，基准跟锚 / Same as previous line, anchor follow *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_LsgState.eLearn; (* 进入学习 / Enter learn *)
        END_IF
    E_DL_LsgState.eLearn:                    (* 学习相：增量采样 + 窗口统计 / Learn *)
        IF NOT bEnable THEN
            _eState := E_DL_LsgState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSE
            _aDx[_nHead] := fCvNow - _fCvPrev;   (* dCV 增量入窗 / dCV into window *)
            _aDy[_nHead] := fPvNow - _fPvPrev;   (* dPV 增量入窗 / dPV into window *)
            IF (_aDx[_nHead] <> _aDx[_nHead]) OR (_aDy[_nHead] <> _aDy[_nHead])
               OR ((_aDx[_nHead] - _aDx[_nHead]) <> (_aDx[_nHead] - _aDx[_nHead]))
               OR ((_aDy[_nHead] - _aDy[_nHead]) <> (_aDy[_nHead] - _aDy[_nHead])) THEN
                (* 非有限增量：不入统计、不推进游标，基准照常跟锚（NaN 拒收口径） / Non-finite: skip, anchor follows *)
                _fCvPrev := fCvNow;          (* 基准照常跟锚 / Anchor follow *)
                _fPvPrev := fPvNow;          (* 同前一项，基准跟锚 / Same as previous line, anchor follow *)
            ELSE
                _nHead := _nHead + 1;        (* 有效样本：头游标递进 / Head advance *)
                IF _nHead > _nEff THEN
                    _nHead := 1;             (* 环回卷（下标先判后增） / Ring wrap *)
                END_IF
                IF _nFill < _nEff THEN
                    _nFill := _nFill + 1;    (* 填充计数封顶 / Fill cap *)
                END_IF
                _fCvPrev := fCvNow;          (* 基准推进 / Base advance *)
                _fPvPrev := fPvNow;          (* 同前一项，基准跟锚 / Same as previous line, anchor follow *)
            END_IF
            _i := 1;                         (* 统计游标起头重置（R227） / Cursor reset *)
            WHILE _i <= _nFill DO            (* 逐点累计（窗口内下标已钳位） / Per-point sums *)
                _fSumX := _fSumX + _aDx[_i]; (* Σx / Sum x *)
                _fSumY := _fSumY + _aDy[_i]; (* Σy / Sum y *)
                _fSumXY := _fSumXY + _aDx[_i] * _aDy[_i];   (* Σxy / Sum xy *)
                _fSumX2 := _fSumX2 + _aDx[_i] * _aDx[_i];   (* Σx² / Sum x2 *)
                _fSumY2 := _fSumY2 + _aDy[_i] * _aDy[_i];   (* Σy² / Sum y2 *)
                _i := _i + 1;                (* 游标递进 / Cursor advance *)
            END_WHILE
            IF _nFill >= 1 THEN
                _fDenX := DINT_TO_LREAL(_nFill) * _fSumX2 - _fSumX * _fSumX;   (* 分母因子 1 / Denominator factor 1 *)
                _fDenY := DINT_TO_LREAL(_nFill) * _fSumY2 - _fSumY * _fSumY;   (* 分母因子 2 / Denominator factor 2 *)
                _fDen := _fDenX * _fDenY;    (* 开方前乘积 / Product before sqrt *)
            END_IF
            IF (_fDen > DL_LSG_EPS * DL_LSG_EPS) AND (_nFill >= 1) THEN
                _fR := (DINT_TO_LREAL(_nFill) * _fSumXY - _fSumX * _fSumY) / SQRT(_fDen);   (* 皮尔逊 r：分母已过乘积 eps 闸（乘积闸等价双因子闸），无除零 / Pearson r, denominator gated *)
                IF _fR > fSignThresh THEN
                    _eSign := E_DL_LsgSign.eDirect;      (* 判正向 / Direct *)
                ELSIF _fR < (-fSignThresh) THEN
                    _eSign := E_DL_LsgSign.eReverse;     (* 判反向 / Reverse *)
                ELSE
                    _eSign := E_DL_LsgSign.eUnknown;     (* 相关性弱：未定（IF 链带 ELSE 兜底，R285） / Weak: unknown *)
                END_IF
            ELSE
                _eSign := E_DL_LsgSign.eUnknown;         (* 窗内无变化/无样本：未定（边界①） / Degenerate: unknown *)
            END_IF
            fCorrCoef := _fR;                (* 相关系数出口镜像 / Correlation mirror *)
            nSampleCnt := _nFill;            (* 样本数出口镜像 / Sample count mirror *)
            eSignOut := _eSign;              (* 方向出口镜像 / Sign mirror *)
            IF (_nFill * 10 >= 6 * _nEff) THEN
                (* 判据串相位因子：填充 >= 60% 才比对期望（R281 口径，整数交叉乘比避免浮点除） / Verdict gated at 60% fill, integer cross-multiply *)
                IF (_eSign = E_DL_LsgSign.eDirect OR _eSign = E_DL_LsgSign.eReverse)
                   AND (_eSign <> eExpect) THEN
                    bSignSuspect := TRUE;    (* 方向与期望不符：嫌疑锁存至复位沿 / Suspect latch *)
                END_IF
            END_IF
        END_IF
    E_DL_LsgState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_LsgState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_LsgCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
