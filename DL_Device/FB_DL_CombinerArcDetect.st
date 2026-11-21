(*
  FB_DL_CombinerArcDetect  —  汇流箱直流拉弧特征判据 / Combiner box DC arc feature detection
  分类 Category : DL_Device
  码位 Code     : 16#03_2_00
  版本 Version  : 1.0.1
  溯源 Source   : NAMUR NE107 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  修订 Revision : v1.0.1 (R34 终审抽检) — ① 段 1 复位只清组态码 16#0002_0300，不再连带清 16#0002_0310
                  （原「无条件清锁存」使拉弧仍在时 bError 掉为 FALSE、uErrorId 归 0，而 eNe107 仍报 eFailure，
                  故障位/事件码/NE107 三者不同步，且 eAlarm 解除需第二次复位沿）；
                  ② bCfgOk 补 tSampleTime / tFilterTC 正域闸（原 0 或负值时高通静默不动作、永不告警，违 R179）。
                  接口、码表、NE107 映射不变。
  功能 Function : 1) 高通滤波提取电流高频分量，超门限按多拍持续确认才升故障（单拍尖峰只计信息级）；
                  2) 采样率与滤波截止频率配比校验（截止 >= 采样率/2 即出厂报码，不进入判据）；
                  3) 分级出口按 NE107 六态映射，未知态归 eUnknown 绝不归 eOk。
  边界 Boundary : ① 高频分量提取前确认采样率/截止频率配比合法（截止 >= 采样率/2 即报码）；
                  ② 拉弧判据多拍持续确认，单拍尖峰只计信息级不升故障；
                  ③ 分级出口按 NE107 六态映射，未知态归 eUnknown（不归 eOk）；
                  ④ 输出三行同向：高频分量 → 确认计数 → 拉弧标志。
  依赖 Depends  : FB_DL_HighPassFilter（高频分量提取，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0300 故障级：采样率/截止频率配比非法（截止 >= 采样率/2）或采样率 <= 0
    16#0002_0310 故障级：拉弧已确认（多拍持续超门限），需 bReset 清除
    16#0002_0320 信息级：单拍尖峰（未达确认拍数，不置 bError）
*)

TYPE E_DL_CadNe107 :
(
    eOk                  := 0,   // 正常 / Normal
    eFailure             := 10,  // 故障 / Failure
    eCheckFunction       := 20,  // 功能检查 / Function check
    eOutOfSpec           := 30,  // 超出规格 / Out of specification
    eMaintenanceRequired := 40,  // 需要维护 / Maintenance required
    eUnknown             := 90   // 未知态（兜底）/ Unknown fallback
);
END_TYPE

TYPE E_DL_CadPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eWatch   := 10,  // 常规监视 / Normal watch
    eConfirm := 20,  // 多拍确认中 / Multi-scan confirmation
    eAlarm   := 30,  // 拉弧告警 / Arc alarm
    eFault   := 90   // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_CombinerArcDetect
VAR_INPUT
    bEnable       : BOOL;                         // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                          // 复位，上升沿清告警与故障 / Reset
    fCurrentA     : REAL;                         // 直流支路电流 [A]，域 0~30 / DC branch current [A]
    fSampleRateHz : REAL := 10000.0;              // 电流采样率 [Hz]，域 > 0 / Current sampling rate [Hz]
    fCutoffHz     : REAL := 2000.0;               // 高通截止频率 [Hz]，须 < 采样率/2 / High-pass cutoff [Hz]
    fHfThreshA    : REAL := 0.15;                 // 高频分量门限 [A]，域 > 0 / HF component threshold [A]
    nConfirmScans : INT := 5;                     // 持续确认拍数 [拍]，域 1~100 / Confirmation scans, 1..100
    tFilterTC      : TIME := T#20MS;              // 高通时间常数 [ms] / High-pass time constant [ms]
    tSampleTime   : TIME := T#10MS;               // 任务采样周期 [ms]，域 > 0 / Task sample period [ms]
    fEps          : REAL := 1.0E-6;               // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fHfOutA       : REAL;                         // 高频分量输出 [A] / HF component output [A]
    nConfirmCnt   : INT;                          // 当前确认计数 [拍] / Current confirmation counter
    bArcAlarm     : BOOL;                         // 拉弧告警（保持型）/ Arc alarm, held
    bSpikeOnly    : BOOL;                         // 仅单拍尖峰（信息级）/ Single-scan spike only
    eNe107        : E_DL_CadNe107;                // NE107 六态映射出口，段尾单点赋值 / NE107 mapping, single write
    bError        : BOOL;                         // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId      : UDINT;                        // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut     : E_DL_CadPhase;                // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_CadPhase := E_DL_CadPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                       // 复位沿 / Reset edge
    fbHp          : FB_DL_HighPassFilter;         // 高通滤波实例（无条件调用）/ High-pass filter instance
    bCfgOk        : BOOL;                         // 配比组态合法 / Ratio configuration valid
    bSigOk        : BOOL;                         // 电流采样有效 / Current sample valid
    bOver         : BOOL;                         // 本拍超门限 / Over threshold this scan
    nCnt          : INT;                          // 确认计数暂存 [拍] / Confirmation counter buffer
    eMap          : E_DL_CadNe107;                // NE107 映射暂存（单点写入源）/ NE107 mapping buffer
    uFault        : UDINT;                        // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                        // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_CAD_CNTMAX : INT := 1000;                  // 确认计数上限 [拍]，防溢出 / Confirmation counter ceiling
    DL_CAD_SRMAX  : REAL := 1.0E6;                // 采样率物理域上限 [Hz] / Sampling rate domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸：采样率/截止频率配比（截止 >= 采样率/2 即报码）=== *)
bCfgOk := (fSampleRateHz > fEps) AND (fSampleRateHz <= DL_CAD_SRMAX)
          AND (fCutoffHz > fEps)
          AND (fCutoffHz < (fSampleRateHz * 0.5))          // Nyquist 配比硬判据
          AND (fHfThreshA > fEps) AND (nConfirmScans >= 1) AND (nConfirmScans <= 100)
          AND (TIME_TO_LREAL(tSampleTime) > 0.0) AND (TIME_TO_LREAL(tFilterTC) > 0.0)   // 节拍/时间常数正域闸（R179）
          AND (fSampleRateHz = fSampleRateHz) AND (fCutoffHz = fCutoffHz)
          AND (fHfThreshA = fHfThreshA);                   // 含 NaN 自反判据
IF NOT bCfgOk THEN
    uFault := 16#0002_0300;                       // 故障级：配比非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    IF uFault <> 16#0002_0310 THEN
        uFault := 16#0000;                        // 复位沿清锁存（拉弧码由 eAlarm 相专清，保持位码同步）
    END_IF
    IF NOT bArcAlarm THEN
        nCnt := 0;                                // 未进入告警时清确认计数
    END_IF
END_IF
bSigOk := (fCurrentA = fCurrentA) AND (ABS(fCurrentA) < 1.0E30) AND (fCurrentA >= 0.0);   // NaN 自反 + 域闸
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 高频分量实例（每拍无条件调用）=== *)
fbHp(bEnable := bEnable AND bSigOk AND bCfgOk,    // 配比非法/信号无效时不使能（禁误判）
     fIn := fCurrentA,                            // 电流采样
     tTimeConst := tFilterTC,                     // 高通时间常数
     tSampleTime := tSampleTime,                  // 采样周期
     rOutMin := -1000.0,                          // 输出下限 [A]
     rOutMax := 1000.0,                           // 输出上限 [A]
     bTrack := rtrReset.Q,                        // 复位沿清基线
     fTrackValue := 0.0);                         // 跟踪值 0
fHfOutA := fbHp.fOut;                             // 高频分量输出
bOver := bCfgOk AND bSigOk AND fbHp.bValid AND (ABS(fHfOutA) >= fHfThreshA);   // 超门限判据

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_CadPhase.eIdle :
    nCnt := 0;                                    // 空闲计数清零
    bSpikeOnly := FALSE;                          // 尖峰标志复位
    IF uFault = 16#0002_0300 THEN
        _eState := E_DL_CadPhase.eFault;          // 组态故障优先
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_CadPhase.eWatch;          // 进入监视相
    END_IF

E_DL_CadPhase.eWatch :
    IF bOver THEN
        nCnt := 1;                                // 首拍超门限：进入确认
        _eState := E_DL_CadPhase.eConfirm;
    ELSE
        IF bSpikeOnly THEN
            uInfo := 16#0002_0320;                // 信息级：单拍尖峰记录（不升故障）
        END_IF
        bSpikeOnly := bSpikeOnly AND bOver;       // 无超门限拍则尖峰记录清除
    END_IF

E_DL_CadPhase.eConfirm :
    IF bOver THEN
        nCnt := nCnt + 1;                         // 连续超门限：计数累加
        IF nCnt > DL_CAD_CNTMAX THEN
            nCnt := DL_CAD_CNTMAX;                // 饱和防溢出
        END_IF
        IF nCnt >= nConfirmScans THEN
            bArcAlarm := TRUE;                    // 置位型：拉弧确认告警（段尾不清零）
            uFault := 16#0002_0310;               // 故障级：拉弧已确认
            _eState := E_DL_CadPhase.eAlarm;      // 转告警相
        END_IF
    ELSE
        bSpikeOnly := TRUE;                       // 未达确认拍数即回落：只计单拍尖峰
        uInfo := 16#0002_0320;                    // 信息级：单拍尖峰
        nCnt := 0;                                // 计数清零（要求连续）
        _eState := E_DL_CadPhase.eWatch;          // 回监视相
    END_IF

E_DL_CadPhase.eAlarm :
    bArcAlarm := TRUE;                            // 告警保持
    IF NOT bOver AND rtrReset.Q THEN
        uFault := 16#0000;                        // 超门限消失且复位沿：清锁存
        bArcAlarm := FALSE;                       // 告警解除（可到达的解除路径）
        nCnt := 0;                                // 计数清零
        _eState := E_DL_CadPhase.eWatch;
    END_IF

E_DL_CadPhase.eFault :
    nCnt := 0;                                    // 故障态计数清零
    bArcAlarm := FALSE;                           // 故障态不告警（配置错误优先）
    IF uFault = 16#0000 THEN
        _eState := E_DL_CadPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_CadPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0300;                       // 故障级：相 ID 越界
    bArcAlarm := FALSE;                           // 安全侧不告警
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_CadPhase.eIdle;               // 失能最高优先回空闲
    bArcAlarm := FALSE;                           // 失能清告警
    nCnt := 0;                                    // 失能清计数
    IF uFault = 16#0002_0310 THEN
        uFault := 16#0000;                        // 失能同拍清拉弧锁存：相序丢失后 eAlarm 不可达，防锁死（终审式 1）
    END_IF
END_IF

(* === 段 4 · 输出映射与 NE107 六态（段尾单点赋值）=== *)
nConfirmCnt := nCnt;                              // 确认计数输出
CASE _eState OF
E_DL_CadPhase.eWatch :
    eMap := E_DL_CadNe107.eOk;                    // 常规监视：正常态
E_DL_CadPhase.eConfirm :
    eMap := E_DL_CadNe107.eMaintenanceRequired;   // 确认中：需维护关注
E_DL_CadPhase.eAlarm :
    eMap := E_DL_CadNe107.eFailure;               // 拉弧确认：故障态
E_DL_CadPhase.eFault :
    eMap := E_DL_CadNe107.eOutOfSpec;             // 组态越规格
E_DL_CadPhase.eIdle :
    eMap := E_DL_CadNe107.eCheckFunction;         // 空闲未监视：功能检查
ELSE
    eMap := E_DL_CadNe107.eUnknown;               // 未知态兜底：绝不归 eOk
END_CASE
IF bSpikeOnly AND (eMap = E_DL_CadNe107.eOk) THEN
    eMap := E_DL_CadNe107.eMaintenanceRequired;   // 单拍尖峰：提升到需维护（信息级）
END_IF
eNe107 := eMap;                                   // 单点写入 NE107 出口
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
