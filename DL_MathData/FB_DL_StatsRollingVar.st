(*
  ============================================================
  组件名 : FB_DL_StatsRollingVar
  分类   : DL_MathData
  功能   : 定长环形缓冲的滚动方差与滚动标准差，最旧样本先移出再插入新样本
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
  口径说明 : 方差为样本方差（分母 n-1），n 小于二时判无效；浮点误差使方差为负时钳到零。
             环形缓冲容量六十四，满后最旧样本先移出。
             复位沿作用域：清缓冲、清和与平方和、清游标与已填数；不清输出语义定义。
             bEnable 为假时冻结保持——不插入新样本，输出继续按既有缓冲计算。
*)

FUNCTION_BLOCK FB_DL_StatsRollingVar
VAR_INPUT
    rInput  : REAL; // 采样输入值 [工程单位] sample input value [engineering unit]
    bEnable : BOOL; // 采样使能，假为冻结保持 sampling enable, false freezes the buffer
    bReset  : BOOL; // 复位命令，上升沿清空缓冲 reset command clearing the buffer on its rising edge
END_VAR
VAR_OUTPUT
    rVariance : REAL; // 样本方差 [工程单位平方] sample variance [engineering unit squared]
    rStd      : REAL; // 样本标准差 [工程单位] sample standard deviation [engineering unit]
    rMean     : REAL; // 样本均值 [工程单位] sample mean [engineering unit]
    nCount    : INT; // 当前缓冲样本数 [个] buffered sample count [count]
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_CAP  : INT := 64; // 缓冲容量 [个] buffer capacity [count]
    DL_LAST : INT := 63; // 缓冲末下标 last buffer index
END_VAR
VAR
    _afBuf  : ARRAY[0..63] OF REAL := [64(0.0)]; // 环形样本缓冲 [工程单位] ring sample buffer [engineering unit]
    _nIdx   : INT := 0; // 写入游标 [个] write cursor [count]
    _nFilled: INT := 0; // 已填样本数 [个] filled sample count [count]
    _rSum   : REAL := 0.0; // 样本和 running sum [engineering unit]
    _rSumSq : REAL := 0.0; // 样本平方和 running sum of squares [engineering unit squared]
    _rVar   : REAL := 0.0; // 方差中间量 [工程单位平方] intermediate variance [engineering unit squared]
    _bInit  : BOOL := FALSE; // 首扫初始化标志 first scan initialisation flag
    i       : INT := 0; // 清缓冲游标 [个] clearing cursor [count]
    rtReset : R_TRIG; // 复位上升沿 reset rising edge
END_VAR

// 段 0｜复位沿实例无条件周期刷新 unconditional cyclic refresh of the reset edge
rtReset(CLK := bReset); // 复位沿刷新 refresh the reset edge
// 段 1｜出口预置 preset the exit
rVariance := 0.0; // 方差预置零 variance preset to zero
rStd := 0.0; // 标准差预置零 deviation preset to zero
rMean := 0.0; // 均值预置零 mean preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜首扫与复位沿初始化 first scan and reset edge initialisation
IF (NOT _bInit) OR rtReset.Q THEN
    FOR i := 0 TO DL_LAST DO
        _afBuf[i] := 0.0; // 逐槽清零 clear every slot
    END_FOR
    _nIdx := 0; // 游标归零 the cursor returns to zero
    _nFilled := 0; // 已填数归零 the filled count returns to zero
    _rSum := 0.0; // 样本和归零 the running sum returns to zero
    _rSumSq := 0.0; // 平方和归零 the sum of squares returns to zero
    _bInit := TRUE; // 首扫初始化完成 the first scan initialisation is done
END_IF
// 段 3｜采样插入，最旧样本先移出 sample insertion with the oldest leaving first
IF bEnable AND (rInput = rInput) THEN
    _rSum := _rSum - _afBuf[_nIdx]; // 移出最旧值占的和 remove the oldest from the sum
    _rSumSq := _rSumSq - _afBuf[_nIdx] * _afBuf[_nIdx]; // 移出最旧值占的平方和 remove the oldest from the squares
    _afBuf[_nIdx] := rInput; // 新样本写入游标位 write the new sample at the cursor
    _rSum := _rSum + rInput; // 累入新样本 accumulate the new sample
    _rSumSq := _rSumSq + rInput * rInput; // 累入新样本平方 accumulate the new square
    IF _nFilled < DL_CAP THEN
        _nFilled := _nFilled + 1; // 未满时已填数递增 count up while the buffer is not full
    END_IF
    _nIdx := _nIdx + 1; // 游标前进 advance the cursor
    IF _nIdx > DL_LAST THEN
        _nIdx := 0; // 满圈回绕 wrap around
    END_IF
END_IF
// 段 4｜统计量计算 statistics computation
nCount := _nFilled; // 样本数出口 map the buffered count
IF _nFilled >= 2 THEN
    rMean := _rSum / INT_TO_REAL(_nFilled); // 均值，除子为已证正样本数 mean over a proven positive count
    _rVar := (_rSumSq - (_rSum * _rSum) / INT_TO_REAL(_nFilled)) / INT_TO_REAL(_nFilled - 1); // 样本方差 sample variance
    IF _rVar < 0.0 THEN
        _rVar := 0.0; // 浮点误差致负时钳零 clamp a negative value caused by rounding
    END_IF
    rVariance := _rVar; // 方差落定 land the variance
    rStd := SQRT(_rVar); // 标准差为方差开方 the deviation is the square root of the variance
    bValid := TRUE; // 结果可用 result usable
ELSIF _nFilled = 1 THEN
    rMean := _rSum; // 单样本时均值即样本值 a single sample is its own mean
END_IF
END_FUNCTION_BLOCK
