# iron-044 std：惰性序列、记录、时间、测试等

- 里程碑：M9　依赖：iron-041　状态：完成
- 设计依据：[08](../designs/08-std-library.md) §2、§3

## 工作内容
`streams`（:41）、`lazy-sequences`（:127）、`generators`（:158，从 Chez 实现移植）、`comprehensions`（:42）、`records`（:99）、`conditions`（:35）、`time`（:19）、`random`（:27）、`testing`（:64 :78）、`regexp`（:115）、`args`（:37）、`system`（:98 :112）、`localization`（:29）、`format`（:54）、`ports`（:6 :38）、`queues`（:117），各带测试。

## 验收标准
- 原 SRFI 测试中对应部分全部通过；D2 守卫通过。

## 结论（2026-10-09）

完成。16 个库分两个并行分支实现，再合并验证。

| 库 | 来源 | 导出 | 测试 | 与原测试对照 |
|---|---|---|---|---|
| `streams` | :41（Philip L. Bewig，MIT 式） | 37 | 46 | chez-srfi 无测试；按 SRFI 41 文本编写（含 10 万元素的 stream-ref 不增长栈） |
| `lazy-sequences` | :127（John Cowan） | 29 | 109 | 原 109 项（SRFI 64）全部保留，109/109 |
| `generators` | :158（Kawai、Cowan、Gilray，MIT） | 55 | 79 | 原测试在新系统上无法运行（依赖 Chez 的 call/1cc），无基线；原 74 项全部通过，另加 5 项协程检查 |
| `comprehensions` | :42（Sebastian Egner） | 37 | 168 | 原 163 项中 162 通过；std 163/163（见基础库问题①），另补 5 项分派扩展接口 |
| `records` | :99 过程部分（William D Clinger，MIT） | 11 | 27 | chez-srfi 的 tests/records.sps 测的是 SRFI 9，不相关；按 SRFI 99 文本编写 |
| `conditions` | :35（Kelsey、Sperber） | 7 | 30 | chez-srfi 无测试；按 SRFI 35 文本编写 |
| `time` | :19（参照实现 I/NET, Inc.，MIT 式） | 80 | 111 | 原 8 组全部通过（各计一项）；原只打印的 date->string 演示改为对固定日期逐个格式检查；补写其余导出名 |
| `random` | :27（Sebastian Egner，MRG32k3a） | 11 | 14 | 原 check-basics-1、check-mrg32k3a 均通过，各计一项（含 L'Ecuyer 的 10^7 求和检查，整个脚本约 55 秒）；补写各导出名 |
| `testing` | :64（Per Bothner）+ :78（Sebastian Egner） | 78（72 + 6，无同名） | 78 | SRFI 64 元测试集原 51 通过 + 2 预期失败：外层判定改用 check.ss，53 项全部保留（2 项预期失败改为检查"确实与期望不同"）；SRFI 78 例子原 9 正确 4 失败：捕获输出后判定计数一致；另补 15 项覆盖元测试未涉及的 31 个导出名 |
| `regexp` | :115（Alex Shinn，Chibi） | 23 | 97 | 原 80 项全部保留且通过；补 17 项覆盖 11 个未测的导出名 |
| `args` | :37（Anthony Carrico） | 7 | 25 | 原无测试，按 SRFI 37 文本编写 |
| `system` | :98 + :112 | 8 | 11 | :98 原 4 项 check + 1 个 assert 全部保留；:112 按实际取值编写 |
| `localization` | :29（Scott G. Miller） | 8 | 16 | 原无测试，按 SRFI 29 文本（含例子）编写 |
| `format` | :54 cat（Joo ChurlSoo） | 1 | 30 | 原无测试，按 SRFI 54 文本编写 |
| `ports` | :6 独有 + :38（Larceny 实现） | 5 | 18 | 原无测试，按 SRFI 6 / 38 文本编写 |
| `queues` | :117（John Cowan） | 23 | 34 | 原 34 项全部保留且通过（经 srfi64-shim） |

全部 8 个测试通过；check-std（D2 守卫，含其他分支的库共 44 个）通过；每个导出名都有测试（脚本核对）。

全部 16 个测试通过；D2 守卫通过；每个导出名都有测试（脚本核对）。

**测试约定的补充**：`tests/std/srfi64-shim.ss` 把以 SRFI 64 写成的原测试（test-equal、test-assert、test-error 等）接到 check.ss 的计数上，不依赖被测的 testing 库。iron-043 分支另写了作用相同的 `check-64.ss`，已合并为这一个文件（保留了能显示测试名的版本）。新增许可证 `std/LICENSES/chibi-scheme.txt`（regexp）。

**取舍与改动：streams 等 8 个库（均写在各文件头）**
- streams：primitive 与 derived 两个库并为一个；流用参照实现自带的 SRFI 45 式强制，与基础库 delay/force 独立。
- generators（D6 移植）：参照实现的 make-coroutine-generator 用 call/cc 在 proc 与调用方之间来回跳转，新系统只有逃逸续延，不可行。改为 proc 在后台线程运行、与调用方用两个 SemaphoreSlim 严格交替（任一时刻只有一方运行）；proc 中的条件在调用方重新引发；未耗尽就丢弃的生成器线程停在 yield 处，不阻止进程退出。make-for-each-generator、make-unfold-generator 建立在它之上。限制：proc 在另一线程中，parameterize 的参数在 proc 中不可见。另：gcombine 中的 define-values 改为 let-values（基础库无 define-values）。
- comprehensions：:-dispatch 用参数实现；SRFI 23 的 error 在库内定义为 &assertion。
- records：helper、inspection、procedural 三个库并为一个；rtd 即 R6RS 记录类型描述符，与 R6RS 记录互通。define-record-type（冲突）用 R6RS 的；record? record-rtd 与基础库同一。
- conditions：参照实现自带一套与 R6RS 并行的条件系统，D2 不导出那些同名名字后，用户拿不到它的根类型，7 个过程无法使用。改为按 SRFI 35 文本在 R6RS 条件之上重写（参照代码未保留）：条件类型即 &condition 子类型的记录类型描述符，与 raise/guard/condition-message 等互通。对照表列出 &condition … condition-message、condition（R6RS 为过程）、define-condition-type（R6RS 多一个构造器名）。
- time：宿主接口（原 chez-srfi 的 (srfi :19 time compat) IronScheme 版）并入；时区偏移改用 TimeZoneInfo.Local（原兼容层用两次 (now) 相减再截断，常差 1 秒，表现为 +0759）；修正参照实现两处缺陷：time-difference! 总报"incompatible time types"（先改类型再比较），date->julian-day / date->modified-julian-day 括号错位（把一天的小数部分除以 (- offset)，时区为 0 时除零）。time-gc 不支持；闰秒表到 2017 年；:6 的字符串端口在库内用 R6RS 端口定义。
- random：参照实现原样并入；随机化种子取 (ironscheme std time) 的当前纳秒。

**取舍与对参照实现的修正：testing 等 8 个库**
- testing：SRFI 64 参照实现为 Kawa、MzScheme、Chicken 等写的 15 处 cond-expand 在生成时消解（按 chez-srfi 在
  IronScheme 上的特性 r6rs、srfi-9/23/34/39）；test-log-to-file 是存取过程（R6RS 不能导出被赋值的变量），
  缺省 #f 不写日志文件；**修正参照实现缺陷**：test-result-remove 用 `(eq? r p)` 拿表尾与要删的属性比较，
  永不相等，走到表尾时出错 → 改为 `(eq? (car r) p)`。:78 的 check:write 用基础库 pretty-print。check-ec 依赖
  (ironscheme std comprehensions)；用户写 check-ec 的限定式（:range 等）需自行导入 comprehensions。
- regexp：搜索器集合原用 SRFI 69 散列表（不收）→ R6RS 散列表（hashtable-values 不是 R6RS，用 hashtable-entries）；
  原 (srfi :115 regexp boundary) 的字形簇字符集并入本文件，其中未导出的 Control 集与正则实现自己的
  char-set:control 重名，改名 char-set:grapheme-control；记录用 compat 的 SRFI 9 形式。字符类 alpha、digit 等按
  ASCII（参照实现的做法）。regexp-match-submatch/list 是 Chibi 扩展，单次子匹配返回字符串。
- args：option 记录用 R6RS 记录并检查参数（chez-srfi 的做法），参照实现中 SRFI 9 定义的部分去掉。
- system：:112 各项按 IronScheme 实际取值：implementation-name "IronScheme"、implementation-version 为
  (ironscheme-version)（"0.1.0"）、cpu-architecture 取进程体系结构并与 std syntax 的 cond-expand 特性同名
  （"x86-64" "i386" "arm64"…）、machine-name 为 Environment.MachineName、os-name 为 "Windows"/"Linux"/"macOS"/
  "FreeBSD"、os-version 为 RuntimeInformation.OSDescription。chez-srfi 原适配把架构写死为 "x86"/"amd64"、
  os-name 取 PlatformID（"Unix"），已改。
- localization：current-language / current-country 缺省取 .NET CurrentCulture（不变区域时退回 en / us）；
  current-locale-details 参照实现未提供（chez-srfi 调用即报错）→ 缺省空表、可设置；SRFI 29 自带的 format（支持
  位置参数 ~n@*）与基础库同名，只在库内使用、不导出。
- format：只导出 cat。测试中 SRFI 54 文本的例子 `(cat 129.985 10 2.)` ⇒ "    129.99" 依赖十进制表示
  （129.985 的双精度值为 129.98499999…，正确舍入为 129.98），换成 129.986。
- ports：open-input-string 即 open-string-input-port；:38 的 fixup 对象原用 SRFI 99 过程式记录 → R6RS 记录，
  record? 取自 (rnrs records inspection)。写出时标号从 #1= 开始。
- queues：参照实现内部的 make-list、list-copy、list-set!、last-pair、map! 不导出。

**发现的基础库问题（只记录，未修改）**
1. `native-eol-style` 在 Linux 上也是 `crlf`，写入原生转码器端口的 `newline` 输出 `\r\n`。原 SRFI 42 测试唯一的失败项源于此；std 测试改用显式 `(eol-style lf)`。
2. 基础库 `format` 不认识 `~n@*`（位置参数），会原样输出而不报错，静默给出错误结果。SRFI 29 的本地化模板依赖位置参数，而 SRFI 29 的 format 因 D2 不导出，目前没有可用的对应格式化过程。
3. 基础库没有 `define-values`、`with-output-to-string`；SRFI 6 的字符串端口现在由 `(ironscheme std ports)` 提供。
