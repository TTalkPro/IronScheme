# iron-059 大整数改用 System.Numerics.BigInteger

- 里程碑：M9　依赖：—　状态：完成
- 设计依据：[02](../designs/02-runtime.md) 数的表示

## 目标
用 .NET 自带的 `System.Numerics.BigInteger` 取代第三方的 `Oyster.IntX`，删除 `src/Oyster.IntX`，少维护一个项目。

## 工作内容
1. Core 中的 `using BigInteger = Oyster.Math.IntX;` 改为 `System.Numerics.BigInteger`；IntX 特有的成员（`Create`、`ToFloat64`、`ToInt32`、`IsInt32`、`BitLength`、`Power`、`Normalize`、按进制的 `ToString` 等）换成 BCL 的对应写法。
2. 语义核对：除法截断、余数符号、补码位运算、补码字节序列（`$bignum->bytes`）、到 double 的舍入。
3. 去掉对 `Oyster.IntX` 的引用：解决方案、项目、`tools/build.cs`、Bootstrap 测试、Emit 的 Lcil 数据转换、`.editorconfig`、`license.txt`、设计文档。
4. 大整数与字符串的转换改由宿主完成（用户追加）：新增原语 `$bignum->string`，`string->number` 的整数部分不再逐位累加。
5. 位运算（用户追加）：去掉 O(n²) 的逐位循环，大整数取负不再走乘法。
6. 数的比较的快速路径（用户追加，排查基准循环本身的开销时发现）。
7. 重建 boot、种子不动点、全部测试；大数基准前后对比。

## 基线（IntX，Release）
同一组运算各跑一次、未热身（即后来的 `tests/bignum-bench.sps` 的前身）：fact 20000 193ms，fib 100000 257ms，十进制输出 4215ms，十进制解析 524ms，十六进制输出 3474ms，平方 11ms，除法 50ms，gcd 17ms，调和级数 2000 项 367ms，位运算 1267ms。

已知错误：`(inexact (expt 2 1100))` 得 `+nan.0`（应为 `+inf.0`）；分子分母都很大的分数转浮点得 `+nan.0`（调和级数 2000 项）。

## 结论（2026-10-09）

完成。

- **替换**：`src/Oyster.IntX` 已删除。Core 中的别名改为 `using BigInteger = System.Numerics.BigInteger;`。IntX 特有的成员改写如下：
  - `Create(...)` 改用构造函数；`Power` 改为 `BigInteger.Pow`；`Abs()`、`Negative` 改为 `BigInteger.Abs`、`Sign`。
  - `ToInt32` 改为 `(int)`；散列值改为取低 32 位。
  - `BitLength` 改为 `GetBitLength()`；`Fraction` 的三个 `Gcd` 合并为 `BigInteger.GreatestCommonDivisor`。
  - 新增 `Numbers/BigIntegers.cs`，提供 `IsInt32`、`ToFloat64`、`RationalToDouble`、按进制的 `ToString` 与 `TryParse`。
- **语义核对**：
  - 两者的除法都向零截断，余数的符号都跟被除数一致。
  - 位运算都按补码计算；`$bignum->bytes` / `$bytes->bignum` 都用最短的小端补码，格式不变。
  - Scheme 侧的负数右移本来就经 `bitwise-not` 转换，不受影响。
  - `BigInteger` 是值类型，相应删掉了两处 `ReferenceEquals(i, null)`。
  - `ToString()` 受当前区域设置影响（负号），Fasl 与 `Fraction.ToString` 改用不变区域。
  - 互操作转 `decimal`、`long` 改为直接转换，超出范围时抛溢出异常。
- **修正**：IntX 的 `ToFloat64` 逐个 32 位块累加，有多次舍入，超出范围时得 NaN；分数原来分别转换分子分母再相除。
  - 现在由 `RationalToDouble` 统一实现：就近舍入、平局取偶，含次正规数，溢出为 ±∞。
  - 因此修好了 `(inexact (expt 2 1100))` 得 `+nan.0`、调和级数 2000 项得 `+nan.0` 这两个错误。
  - 新增测试：`NumbersTests.RationalToDoubleIsCorrectlyRounded`（3000 组随机数，用精确有理数比较相邻的 double，另含上溢、次正规数和平局的边界）、`BignumToDoubleOutsideRange`、`BignumRadixConversionRoundTrips`、`RealCompareMatchesExactComparison`（2000 组随机分数，每组与约 17 个 double 正反比较，以"flonum 精确转为分数再比"作参照；double 包括恰好相等的值、相邻的 double、次正规数和很大的指数）、`LargeDecimalOutputMatchesBcl`（分治结果与 BCL 逐字相同：随机的 1000–29000 位数、10 的幂及其邻数、低半全为 0 的值；第二轮使用缓存的幂表）。
- **大数与字符串的转换**：
  - 新原语 `$bignum->string`（`HostPrimitives`）已登记在两个构建脚本的 `(ironscheme unsafe)` 表中，`primitives.ss` 已重新生成（467 项）。`boot/numbers.sls` 的 `bignum->string` 改为调用它，删掉了原来逐位 div/mod 的写法和 `hex-char`。
  - 十进制：BCL 的 `BigInteger.ToString` 耗时随位数平方增长（77338 位约 130ms，143137 位约 440ms），而它的除法是次平方的。所以超过约 1000 位时改为分治（`BigIntegers.ToDecimalString`，用户追加）：按 10^(256·2^k) 拆成高低两半递归，低半左补 0，叶子交给 BCL。纯 .NET 下这两个数分别只要约 14ms、37ms。10 的幂表缓存到约 126 万位（512KB），更大的每次现算。Fasl 与 `Fraction.ToString` 也改用它。
  - 2、8、16 进制直接从字节取位，是线性时间。
  - 读数的整数部分：十进制用 `BigInteger.Parse`，2 的幂进制直接拼字节。
  - 十进制解析没有再自己分治：.NET 9 起 `BigInteger.Parse` 本身就是分治实现（按 9 位一块装入数位）。复用输出用的 10 的幂表试过递归计算"高半 × 10^k + 低半"，叶子大小从 64 调到 512，反而更慢：77338 位为 10.8ms 对 7.8ms，143137 位为 27.4ms 对 12.9ms，477122 位为 137ms 对 89ms。Scheme 中 `string->number` 的耗时（约 7.2ms）与纯 .NET 持平。
- **位运算**：
  - 新原语 `$bignum-bit-count`（`BigInteger.PopCount`）、`$bignum-first-bit-set`（`TrailingZeroCount`）、`$bignum-bit-set?`、`$bignum-reverse-bits`。`bitwise-bit-count`、`bitwise-first-bit-set`、`bitwise-reverse-bit-field` 原来每轮右移 1 位，是 O(n²)，现在由宿主一次算出。
  - `bitwise-length` 对负数直接用 `GetBitLength`：它不含符号位，正好就是补数的位数。
  - 负数右移去掉了前后两次 `bitwise-not`。BigInteger 的右移就是向下取整的算术右移；IntX 的右移对负数结果不对，原来才需要这样绕。
  - `generic-negate` 对 bignum 直接取负。原来按 `(* -1 x)` 做整数乘法；现在 BigInteger 只翻转符号、共享数位，几乎不花时间。
  - 移位的快速路径（用户追加）：移位量是 fixnum 时，`bitwise-arithmetic-shift`、`-left`、`-right` 直接调用 `$bignum-shift-left/right`。原来先经通用的 `negative?` 检查，再进入外面套着 `exact` 的 `cond`。移位量为大整数的情况仍走原来的分支，语义不变。小整数左移 50 万次，扣掉空循环后由每次约 350ns 降到约 42ns；直接调用原语约 15ns。
  - 与纯 .NET 的对比（热身后中位数，60KB 的数各 5000 次）：
    - 取负：0.1 对 1.0ms；加 fixnum：21.0 对 24.0；左移：60.5 对 67.8；异或：72.2 对 75.5；负数右移：90.9 对 94.8。
    - 整个位运算循环：748 对 846（单次运行 769–846）。
    - 直接调用原语时，耗时与纯 .NET 相同。差距来自 Scheme 外层的包装，以及循环本身：每轮约 210ns，含通用的 `=`、`+` 与闭包调用，属于 iron-034 的范围。
  - 顺带修了一个隐患：`bitwise-bit-set?` 原来先把 k 转成 bignum 再右移，下标超出 fixnum 时也照样去移位。现在这种情况直接按符号位回答。
  - 回归测试 `tests/bignums.sps`（`OtherTests.Bignums`，269 项）：用原来逐位的算法作参照，核对位运算、移位、进制输出与解析以及到 flonum 的舍入；样本含正负数、fixnum 边界和 2 的幂附近的值。
- **数的比较的快速路径**：
  - 排查：基准循环每轮约 210ns，拆开测（100 万次）后发现时间几乎全在 `=` 上：
    - 只用 `$fx=?`、`$fx+` 为 5ms；
    - `$fx=?` 加通用 `+` 为 24ms，即 `+` 每次约 19ns；
    - 通用 `=` 加 `$fx+` 为 167ms，即 `=` 每次约 160ns；
    - 闭包调用几乎不花时间。

    原因是 `boot/numbers.sls` 的 `define-comparer` / `define-real-comparer` 没有类型快速路径：两个 fixnum 也要先调 `real?`、`finite?`、`nan?` 各两次，再调两次 `exact`，再经 `$exact-compare` 在 C# 中按类型分派。
  - 改动：两参数分支的开头加三条快速路径，`=`、`<`、`<=`、`>`、`>=` 都适用。
    - 同为 fixnum：`$fx…?`。
    - 同为 flonum：`$fl…?`。IEEE 比较与通用路径的结果一致：有 NaN 为 #f，无穷正常比较，-0.0 与 0.0 相等。
    - fixnum 与 flonum 混合：先把 fixnum 转为 flonum。32 位整数转换是精确的，所以结果与精确比较相同。
  - 效果：
    - 计数循环（`=` 加 `+`）从 184ms 降到 49ms；`=` 每次从约 160ns 降到约 24ns。
    - 混合比较 `(< 1 2.0)` 每次从约 570ns 降到约 100ns。
  - 通用路径（用户追加）：其余实数改为一次 `$real-compare`（新原语，C# `Builtins.RealCompare`）。它返回 -1 / 0 / 1；有 NaN 时返回 2，有非实数时返回 #f，再交给复数的 `inexact=?` 或报错。
    - 精确数与 flonum：正无穷大于、负无穷小于一切精确数；大整数与有限 flonum 比较时，与 ⌊d⌋ 转成的 BigInteger 比，相等时再看有没有小数部分。分数 n/den 与 flonum 比较时不构造分数（用户追加）：
      - 分子、分母都在 53 位内时，先算 `(double)n/(double)den`。IEEE 除法是正确舍入的，舍入不改变大小顺序，所以结果不等于 d 就能直接判定。
      - 否则（或恰好相等时）做精确比较：d = m·2^k，比较整数 n·2^(-k) 与 m·den。
    - 精确数之间（用户追加）：`RealCompare` 直接按两个参数的类型分派，不再经 `ExactCompare`。在 C# 里测，后者的 `GetNumberClass` 分派加取分子分母约 50ns，比比较本身还贵。
      - 整数与分数比较时，比较 n 与 x·den，不再先把整数包成 Fraction（构造时要求最大公约数）。
      - 分数与分数比较用 `CompareRationals`：符号不同、分母相同时不必相乘，否则交叉相乘。
      - 试过先按位数估计（l = len(n1)+len(d2)，两边相差 2 以上即可定序）、在 63 位内用 Int128 相乘，都没有采用：小分数时 `GetBitLength` 每次约 8ns，四次就比交叉相乘（约 20ns）还贵。
      - C# 中的耗时：`RealCompare(1/3, 2/5)` 92 → 41ns，`(1/3, 1)` 92 → 31ns，`(5, 2^100)` 52 → 24ns。
      - 新增 C# 测试 `RationalComparisonMatchesCrossMultiplication`：3000 组随机分数，两边位数之和相差 -2 到 2；另有 int、BigInteger、分数两两混合的情况。
    - 修正了原有的错误：原来有 ±∞ 时两边都先转为 flonum，超出 double 范围的精确数变成 ∞，结果全反。例如 `(< (expt 2 2000) +inf.0)` 得 #f，`(= (expt 2 2000) +inf.0)` 得 #t。
    - `numbers.sls` 中不再用到的 `exact-compare` / `inexact-compare` 宏已删除。
    - 速度（100 万次的循环，含循环本身约 100ms）：
      - fixnum 与大整数、分数与 fixnum、分数与分数：143–166ms；改为直接按类型分派后为 126–139ms（分数与分数 152 → 127）；
      - 大整数与 flonum：最初 771ms，改为取整比较后 148ms；
      - 分数与 flonum：282ms，改为不构造分数后 134ms，再改为直接按类型分派后 128ms；
      - 大整数与 `+inf.0`：129ms。
      - 原来的通用路径每次约 570ns（以 `(< 1 2.0)` 测）。
  - 回归测试：`tests/base-library.sps` 新增 K 组 44 项，覆盖五个比较在 fixnum、flonum、NaN、±inf、-0.0、fixnum 边界、混合类型、多参数和非数参数下的结果；还覆盖超出 double 范围的精确数与 ±inf、大整数与带小数的 flonum、`0.1` 与 `1/10`。
  - `+` 的 `define/contract` 检查只占约 10ns。剩下的开销是跨库调用、装箱和命名 let 新建对象，属于 iron-034 的 D2、D4、D5。
  - 对照 Chez：它把这些运算当作编译器认识的原语，在调用处内联 fixnum 快速路径（`s/cpprim.ss`），库函数只处理其余类型。仿照它在调用处内联，已写入 [iron-034](iron-034-compiler-optimizations.md) 的 D8（子任务 034f）。
- **引用清理**：解决方案、Core 项目引用、Hosting 的 `BootImageInput`、`tools/build.cs` 与 Bootstrap 测试的 ilverify 引用、Emit 的 Lcil 数据转换（改按 `BigInteger` 识别）、`.editorconfig` 的第三方节、`.gitignore`、`Directory.Build.props` 的 `SYSLIB0050/0051`（只有 IntX 需要）、`docs/license.txt` 的 IntX 许可，以及设计 02、07、09。
- **基准**：脚本为 `src/scheme/tests/bignum-bench.sps`，不在测试中运行，需手动运行，说明见文件头。每项先热身 2 轮，再计时 5 轮，取中位数。IntX 一列是改动前的单次运行，未热身。单位 ms，Release 构建。

  | 项目 | IntX（单次） | BigInteger（单次） | BigInteger（热身后中位数） |
  |---|---|---|---|
  | fact 20000 | 193 | 81–86 | 76–78 |
  | fib 100000 | 257 | 168–332 | 149–152 |
  | 十进制输出（77338 位） | 4215 | 127 | 21（分治） |
  | 十进制解析 | 524 | 9 | 7.8 |
  | 十六进制输出 | 3474 | 3 | 1.1 |
  | 平方 | 11 | 10–12 | 10 |
  | 除法 | 50 | 15–18 | 16 |
  | gcd | 17 | 10–14 | 8 |
  | 调和级数 2000 项 | 367（结果为 `+nan.0`） | 24–30 | 21 |
  | 位运算 | 1267 | 844–952 | 769–786（纯 .NET 约 750） |

  前后的校验值一致（各结果对 1000000007 取模）。
  另测单项（各 5000 次，60KB 的数）：取负 70 → 5，移位、异或与纯 .NET 相差 10–20%（装箱与分派）。
- **fib 的波动**：GC 次数每轮相同（约 35 次 gen0），波动来自 .NET 的分层编译。BCL 中 BigInteger 的方法从预编译代码换到 PGO 插桩版本（更慢），再换到 tier1。同一进程连跑 6 轮的结果：
  - 默认设置为 183、323、135、122、119、126ms；
  - 关闭分层编译为 150、129、130、138、138、136ms，没有尖峰，但稳定后略慢；
  - 纯 .NET 写同样的循环，稳定后约 100ms，前几轮同样偏慢。

  不改运行时配置：关闭 PGO 会牺牲所有代码稳定后的性能。测性能时应先热身，取稳定值。
- **验证**：种子已重新生成，`seed` 与 `seed --stage0` 逐字节相同。Core.Tests 258/258，IronScheme.Tests 85/85（含新增的 `Bignums`）。`dotnet format whitespace` 通过；样式检查对本任务的文件没有报告。
