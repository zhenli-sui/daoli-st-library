(*
  DL Factory R83 | FC_DL_YarnCountConvert
  功能：在棉英制支数 Ne、公制支数 Nm、特数 Tex、旦尼尔 Den 之间双向换算。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_YarnCountConvert : REAL
VAR_INPUT
    fCount   : REAL; // 输入支数值（须为正）[-] / Input count value, positive [-]
    iFromSys : INT;  // 源制式 1=Ne 2=Nm 3=Tex 4=Den / Source system code
    iToSys   : INT;  // 目标制式 1=Ne 2=Nm 3=Tex 4=Den / Target system code
    fDensity : REAL; // 纤维密度（量纲自检用）[g/cm³] / Fibre density for dimension check
END_VAR
VAR_OUTPUT
    fTexOut   : REAL; // 中间基准特数 [tex = g/1000m] / Intermediate linear density [tex]
    fCountOut : REAL; // 目标制式支数值 [-]/ Converted count in target system [-]
    xValid    : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fTex : REAL; // 基准特数中间量 [tex] / Intermediate tex value [tex]
END_VAR
fTexOut := 0.0; fCountOut := 0.0; xValid := FALSE;  // 出口预置（R256）
// 非有限拦截 + 制式码域闸 + 密度量纲自检（R20/R21）
IF NOT (fCount > -1.0E30 AND fCount < 1.0E30) OR NOT (fDensity > -1.0E30 AND fDensity < 1.0E30) OR fCount <= 0.0 OR iFromSys < 1 OR iFromSys > 4 OR iToSys < 1 OR iToSys > 4 OR fDensity <= 0.0 OR fDensity > 3.0 THEN
    FC_DL_YarnCountConvert := -1.0; RETURN;   // 哨兵 -1：支数非正、制式码或密度越界 / Sentinel -1
END_IF
// 第一段：源制式 → 基准特数 Tex（全部除式分母为 fCount，上面已判正）
IF iFromSys = 1 THEN
    fTex := 590.5 / fCount;         // 棉英制 Ne → Tex [tex] / Ne to tex
ELSIF iFromSys = 2 THEN
    fTex := 1000.0 / fCount;        // 公制支数 Nm → Tex [tex] / Nm to tex
ELSIF iFromSys = 3 THEN
    fTex := fCount;                 // 特数直通 [tex] / Tex passes through
ELSE
    fTex := fCount / 9.0;           // 旦尼尔 Den → Tex [tex] / Den to tex
END_IF
// 第二段：基准特数 Tex → 目标制式（fTex 由第一段保证为正，除法安全）
IF iToSys = 1 THEN
    fCountOut := 590.5 / fTex;      // Tex → 棉英制 Ne [-]/ Tex to Ne
ELSIF iToSys = 2 THEN
    fCountOut := 1000.0 / fTex;     // Tex → 公制支数 Nm [-]/ Tex to Nm
ELSIF iToSys = 3 THEN
    fCountOut := fTex;              // 特数直通 [-]/ Tex passes through
ELSE
    fCountOut := fTex * 9.0;        // Tex → 旦尼尔 Den [-]/ Tex to Den
END_IF
// 出口：正特数才视为有效，非正走故障缺省
IF fTex > 0.0 THEN fTexOut := fTex; xValid := TRUE; END_IF  // 输出基准特数并置有效 [tex]
FC_DL_YarnCountConvert := fCountOut; // 返回目标制式支数 [-]/ Return converted count [-]
END_FUNCTION
