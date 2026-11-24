(*
  FB_DL_VavDischargeAirReset  —  送风温度重置（末端阀位加权平均 → 送风设定值） / VAV discharge-air reset from terminal damper weighted mean
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat — 末端重置族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 末端阀位有效性门控：权重 = 有效末端数量（阀位域 [0,100] 且有限），
                  加权平均 fWMean := SUM(有效阀位)/有效末端数；
                  2) 重置律：fAirSet := fBaseSet + fResetSpan × fWMean/100，输出钳位
                  [fSetMin, fSetMax]，钳位发生置信息级 0494；
                  3) 权重和 = 0（全部末端无效）→ 防除零退回默认设定值 fBaseSet +
                  信息级 0492（不置故障）；
                  4) 部分末端无效置信息级 0493；非有限阀位 → 036B 锁存；
                  质量判定 CASE 全覆盖 + ELSE 兜底落 036C。
  边界 Boundary : ① 组态闸：uTermCnt < 1 或 > 8、fResetSpan < 0、设定钳位域颠倒 → 036A；
                  ② 除零防御：有效末端数 >= 1 过闸后才做除法；
                  ③ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（ABS / LREAL 算术）
  码表 Error codes（Process 段 0005，窗口 036A~036C / 0492~0494）:
    16#0005_036A 故障级：组态非法（末端数界外 / 重置幅值为负 / 钳位域颠倒），锁存至 bReset
    16#0005_036B 故障级：阀位非有限（NaN 自反判），锁存至 bReset
    16#0005_036C 故障级：质量判定落 ELSE 兜底（非法质量 ID），锁存至 bReset
    16#0005_0492 信息级：全部末端无效，退回默认设定值
    16#0005_0493 信息级：部分末端无效提示（有效末端照常聚合）
    16#0005_0494 信息级：设定值钳位提示
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 4 · 序号 4）
*)

TYPE E_DL_VarResetQual :
(
    eAllValid   := 0,    // 全部末端有效 / All terminals valid
    ePartValid  := 10,   // 部分末端无效 / Some terminals invalid
    eNoneValid  := 20    // 全部末端无效 / No terminal valid
);
END_TYPE

FUNCTION_BLOCK FB_DL_VavDischargeAirReset
VAR_INPUT
    aDamper      : ARRAY[1..8] OF LREAL;  // 末端阀位 [0..100 %] / Terminal damper positions
    uTermCnt     : UINT := 1;         // 末端数 [个]，域 1..8 / Terminal count
    fBaseSet     : LREAL := 18.0;     // 基础送风设定 [°C] / Base discharge-air setpoint
    fResetSpan   : LREAL := 2.0;      // 重置幅值 [K]，域 >= 0（阀位 100% 时加满）/ Reset span
    fSetMin      : LREAL := 12.0;     // 设定值下限 [°C] / Setpoint lower clamp
    fSetMax      : LREAL := 26.0;     // 设定值上限 [°C] / Setpoint upper clamp
    bEnable      : BOOL := FALSE;     // 使能 [-] / Enable
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    fAirSet      : LREAL;             // 送风设定值出口 [°C] / Discharge-air setpoint outlet
    fWMean       : LREAL;             // 阀位加权平均 [0..100 %] / Weighted damper mean
    bValid       : BOOL;              // 输出有效标志 / Output valid flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _nCap        : INT;               // 生效末端数 [个] / Effective terminal count
    _nValid      : INT;               // 有效末端数 [个] / Valid terminal count
    _fSum        : LREAL;             // 阀位累加器 [0..100 %] / Damper sum accumulator
    _eQual       : E_DL_VarResetQual; // 质量判定（CASE 唯一写入目标）/ Quality verdict
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    i            : INT;               // 聚合循环游标 [索引] / Aggregation loop cursor
    _nGuard      : INT;               // 聚合守卫计数 [次] / Aggregation guard counter
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);             // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bValid := FALSE;                    // 有效出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件
fAirSet := fBaseSet;                // 设定值缺省 = 默认设定值（退回口径）
fWMean := 0.0;                      // 均值缺省 0
_nValid := 0;                       // 有效计数清零
_fSum := 0.0;                       // 累加器清零
_nGuard := 0;                       // 守卫清零

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
_nCap := UINT_TO_INT(uTermCnt);     // 末端数快照
IF (_nCap < 1) OR (_nCap > 8) OR (fResetSpan < 0.0) OR (fSetMin >= fSetMax) THEN
    _uFault := 16#0005_036A;        // 故障级：组态非法
    _bFault := TRUE;
END_IF

(* —— 段 3：末端聚合（有效性门控；非有限 → 036B 锁存；守卫循环） —— *)
IF (NOT _bFault) AND (_nCap >= 1) AND (_nCap <= 8) THEN
    FOR i := 1 TO _nCap DO
        _nGuard := _nGuard + 1;     // 守卫递增
        IF _nGuard > 8 THEN
            EXIT;                   // 守卫兜底退出（理论不可达）
        END_IF
        IF (aDamper[i] <> aDamper[i]) OR ((aDamper[i] - aDamper[i]) <> (aDamper[i] - aDamper[i])) THEN
            _uFault := 16#0005_036B;    // 故障级：阀位非有限
            _bFault := TRUE;
        ELSIF (aDamper[i] >= 0.0) AND (aDamper[i] <= 100.0) THEN
            _nValid := _nValid + 1;     // 有效末端计数（权重 = 有效性门控）
            _fSum := _fSum + aDamper[i];    // 阀位累加
        END_IF
    END_FOR
END_IF

(* —— 段 4：质量判定（CASE 全覆盖 + ELSE 兜底） —— *)
IF (NOT _bFault) AND (_nCap >= 1) AND (_nCap <= 8) THEN
    IF _nValid = _nCap THEN
        _eQual := E_DL_VarResetQual.eAllValid;      // 全部有效
    ELSIF _nValid >= 1 THEN
        _eQual := E_DL_VarResetQual.ePartValid;     // 部分有效
        _uInfo := 16#0005_0493;                     // 信息级：部分无效提示
    ELSE
        _eQual := E_DL_VarResetQual.eNoneValid;     // 全部无效
    END_IF

    CASE _eQual OF
    E_DL_VarResetQual.eAllValid:
        fWMean := _fSum / INT_TO_LREAL(_nValid);    // 加权平均（分母 = 末端数 >= 1，防除零）
    E_DL_VarResetQual.ePartValid:
        fWMean := _fSum / INT_TO_LREAL(_nValid);    // 有效末端口径平均（同上防除零）
    E_DL_VarResetQual.eNoneValid:
        fWMean := 0.0;                              // 无有效样本
        _uInfo := 16#0005_0492;                     // 信息级：退回默认设定值
        fAirSet := fBaseSet;                        // 防除零退默认
    ELSE
        _uFault := 16#0005_036C;                    // 故障级：非法质量 ID 兜底
        _bFault := TRUE;
        fAirSet := fBaseSet;                        // 安全侧退默认
    END_CASE
END_IF

(* —— 段 5：重置律与钳位（分母 100.0 为常量恒非零） —— *)
IF (NOT _bFault) AND (_nValid >= 1) THEN
    fAirSet := fBaseSet + fResetSpan * fWMean / 100.0;  // 重置律
    IF fAirSet < fSetMin THEN
        fAirSet := fSetMin;         // 下界钳位
        _uInfo := 16#0005_0494;     // 信息级：钳位提示
    ELSIF fAirSet > fSetMax THEN
        fAirSet := fSetMax;         // 上界钳位
        _uInfo := 16#0005_0494;     // 信息级：钳位提示
    END_IF
END_IF

(* —— 段 6：出口单点映射（锁存码回放，禁同拍抹除） —— *)
bValid := (NOT _bFault) AND bEnable AND (_nValid >= 1);  // 有效出口
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bValid := FALSE;                // 故障期强制 FALSE（安全侧）
    fAirSet := fBaseSet;            // 故障期退默认（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源

END_FUNCTION_BLOCK
