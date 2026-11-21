(*
  FB_DL_RatioStationCalc  —  比值站：随动设定 = K×主流量 + 偏置 / Ratio station: K times master flow plus offset
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 比值控制族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 双模式：eRatio（随动 fSetpoint := K×fMaster + fOffset）/
                  eFixed（fSetpoint := fFixedSet）；eMode 落枚举域外 → CASE ELSE → 03AA；
                  2) 主流量非有限（NaN 自反判 / Inf 差值自减判）→ bMasterOk FALSE，
                  强制切固定模式并置信息级 048F；恢复有限自动回比值模式；
                  3) K 组态域钳位 [0.0, 100.0]，钳位发生置信息级 0490；
                  4) 模式变更沿 bModeChg 单拍脉冲（当拍量比较，禁锁存量自指）。
  边界 Boundary : ① 组态闸：fK / fOffset / fFixedSet 非有限 → 03A9 锁存；
                  ② 模式切换 bModeChg 为单拍脉冲：内部 _b* 置位 → 统一出口映射（禁同拍抹除）；
                  ③ 钳位域常量固定，域内无除法，无除零路径；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（ABS / REAL 算术）
  码表 Error codes（Algo 段 0002，窗口 03A9~03AA / 048F~0490）:
    16#0002_03A9 故障级：组态非有限（fK/fOffset/fFixedSet 任一非有限），锁存至 bReset
    16#0002_03AA 故障级：模式落 CASE ELSE 兜底（非法 eMode），锁存至 bReset
    16#0002_048F 信息级：主流量无效，强制固定模式（恢复有限自动回比值）
    16#0002_0490 信息级：K 已钳位至组态域 [0, 100]
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 3 · 序号 4）
*)

TYPE E_DL_RatioMode :
(
    eRatio := 0,   // 比值模式：随动设定 / Ratio mode, slave setpoint
    eFixed := 10   // 固定模式：固定设定 / Fixed mode, constant setpoint
);
END_TYPE

FUNCTION_BLOCK FB_DL_RatioStationCalc
VAR_INPUT
    fMaster      : REAL := 0.0;       // 主流量 [EU] / Master flow
    fK           : REAL := 1.0;       // 比值系数 [无量纲]，域 [0, 100] 钳位生效 / Ratio factor
    fOffset      : REAL := 0.0;       // 偏置 [EU] / Offset
    fFixedSet    : REAL := 0.0;       // 固定模式设定值 [EU] / Fixed-mode setpoint
    eMode        : E_DL_RatioMode := E_DL_RatioMode.eRatio;  // 模式选择 / Mode select
    bEnable      : BOOL := FALSE;     // 投运使能 [-] / Enable
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    fSetpoint    : REAL;              // 随动/固定设定值出口 [EU] / Setpoint outlet
    bMasterOk    : BOOL;              // 主流量有效标志 [-] / Master validity flag
    bModeChg     : BOOL;              // 模式变更单拍脉冲 [-] / Mode change one-shot pulse
    bValid       : BOOL;              // 输出有效标志 / Output valid flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _fKEff       : REAL;              // 钳位后生效比值系数 / Effective clamped factor
    _bMasterFin  : BOOL;              // 主流量有限当拍量 [-] / Master finite current-scan flag
    _eModePrev   : E_DL_RatioMode := E_DL_RatioMode.eRatio;  // 上拍模式快照（变更沿判据）/ Previous mode
    _bModeChgInt : BOOL;              // 模式变更内部脉冲（两段式出口）/ Internal mode-change pulse
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR
VAR CONSTANT
    DL_RSC_K_MIN : REAL := 0.0;      // 比值系数下限 [无量纲] / Factor lower bound
    DL_RSC_K_MAX : REAL := 100.0;    // 比值系数上限 [无量纲] / Factor upper bound
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);             // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单；脉冲两段式出口） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bModeChg := FALSE;                  // 模式变更脉冲缺省 FALSE
bValid := FALSE;                    // 有效出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件
_bModeChgInt := FALSE;              // 内部脉冲清零
fSetpoint := 0.0;                   // 设定值缺省 0

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fK <> fK) OR (fOffset <> fOffset) OR (fFixedSet <> fFixedSet)
   OR ((fK - fK) <> (fK - fK)) OR ((fOffset - fOffset) <> (fOffset - fOffset))
   OR ((fFixedSet - fFixedSet) <> (fFixedSet - fFixedSet)) THEN
    _uFault := 16#0002_03A9;        // 故障级：组态非有限
    _bFault := TRUE;
END_IF

(* —— 段 3：K 钳位与主流量有效性（当拍量判据） —— *)
_fKEff := fK;                       // 生效系数初值
IF _fKEff < DL_RSC_K_MIN THEN
    _fKEff := DL_RSC_K_MIN;         // 下界钳位
    _uInfo := 16#0002_0490;         // 信息级：K 已钳位
ELSIF _fKEff > DL_RSC_K_MAX THEN
    _fKEff := DL_RSC_K_MAX;         // 上界钳位
    _uInfo := 16#0002_0490;         // 信息级：K 已钳位
END_IF
_bMasterFin := (fMaster = fMaster) AND ((fMaster - fMaster) = (fMaster - fMaster));
                                    // 主流量有限判定：NaN 自反取反 AND Inf 差值自减取反
bMasterOk := _bMasterFin;           // 有效性出口镜像

(* —— 段 4：模式变更沿（当拍量比较，禁锁存量自指） —— *)
IF eMode <> _eModePrev THEN
    _bModeChgInt := TRUE;           // 内部脉冲置位（出口段统一映射）
END_IF
_eModePrev := eMode;                // 模式快照推进（段末统一写口径前移）

(* —— 段 5：设定值仲裁（CASE 全覆盖 + ELSE 兜底） —— *)
CASE eMode OF

E_DL_RatioMode.eRatio:
    IF _bMasterFin THEN
        fSetpoint := fMaster * _fKEff + fOffset;    // 比值随动设定
    ELSE
        fSetpoint := fFixedSet;     // 主流量无效：退固定模式
        _uInfo := 16#0002_048F;     // 信息级：无效退固定
    END_IF

E_DL_RatioMode.eFixed:
    fSetpoint := fFixedSet;         // 固定设定直通

ELSE
    _uFault := 16#0002_03AA;        // 故障级：非法模式兜底
    _bFault := TRUE;
    fSetpoint := 0.0;               // 安全侧归零

END_CASE

(* —— 段 6：出口单点映射（脉冲两段式：内部 _b* → 统一出口；锁存码回放） —— *)
IF _bModeChgInt THEN
    bModeChg := TRUE;               // 模式变更脉冲单拍出口
END_IF
bValid := (NOT _bFault) AND bEnable;    // 有效出口
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bValid := FALSE;                // 故障期强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源

END_FUNCTION_BLOCK
