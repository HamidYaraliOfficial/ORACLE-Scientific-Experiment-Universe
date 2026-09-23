# ORACLE — Scientific Experiment Universe

*A unified environment for defining, validating, running, analyzing and reproducing scientific, engineering, mathematical, and computational experiments — with Haskell as the formal validation layer, Julia as the numerical simulation core, Scala as the distributed orchestration layer, and a trilingual, five-theme web workbench on top.*

**Languages:** [English](#english) · [فارسی](#فارسی) · [中文](#中文)

---

<a id="english"></a>
## 🇬🇧 English

### 1. What ORACLE is

ORACLE is a scientific experimentation platform built around one idea: **an experiment should be a typed, validated, versioned object** — not a loose script — so that it can be checked for correctness *before* it burns compute, re-run byte-for-byte later, compared against other runs, and turned into a report automatically.

Three languages each own a distinct layer, exactly as designed:

| Layer | Language | Responsibility |
|---|---|---|
| **Verification Layer** | **Haskell** | Formal Experiment Definition Language, the Formula Engine (parser + AST + dimensional analysis), and the Rule/Validation Engine. Nothing reaches the simulation engine until it has passed structural, dimensional, and bounds validation. |
| **Numerical Core** | **Julia** | The Simulation Engine (Euler / RK4 / adaptive Dormand–Prince RK45 integrators), the Monte Carlo Engine, the Parameter Sweep Engine, the Sensitivity Analysis Engine, and the Statistical Analysis Engine (regression, t-tests, bootstrap CIs — all implemented from first principles). |
| **Orchestration Layer** | **Scala** | The Experiment Registry, the Distributed-style Job Scheduler (priority queue, retries, timeouts, worker health), the REST API, the Result Comparison Engine, the Report Generator, and the professional CLI. |
| **Workbench** | **HTML/CSS/JS** | A full client-side workbench — Experiment Builder, Formula Lab, Parameter Sweep Studio, Monte Carlo Lab, Sensitivity Lab, Result Explorer, Report Studio, Resource Availability, and an Experiment Registry — with 5 themes and 3 languages, usable standalone in any browser. |

All four layers agree on **one shared JSON schema** for an Experiment Definition and **one shared JSON AST format** for formulas, so a formula parsed by Haskell, evaluated by Julia, and re-evaluated live in the browser always means exactly the same thing.

### 2. Design philosophy: zero third-party dependencies

Every layer — Haskell, Julia, and Scala — is built on nothing but its own standard library. There is no `aeson`, no `Distributions.jl`, no `circe`, no `Akka`. Each layer ships its own ~150–250 line JSON parser/encoder and, where needed, its own numerical primitives (Box–Muller sampling, the regularized incomplete beta function for t-tests, a Dormand–Prince Butcher tableau). This is a deliberate reproducibility decision: a fresh install of GHC, Julia, or sbt is enough to build and run every layer, with no dependency-resolution surprises months or years later.

### 3. Honest scope note

The original specification for a system like ORACLE describes an enterprise platform with dozens of subsystems (a full plugin marketplace, a knowledge graph, GPU cluster scheduling, peer review workflows, a natural-language research assistant, and more) that would take a large engineering team a long time to build. This repository implements a real, working, end-to-end **core pipeline** — Define → Validate → Simulate → Sweep / Monte Carlo / Sensitivity → Orchestrate → Compare → Report — with genuine logic at every step and no mocked functions. It is a serious foundation to extend, not the complete enterprise vision. Treat the modules under each language folder as the seams to build additional engines (PDE solvers, Bayesian optimization, a knowledge graph, etc.) onto.

### 4. Repository layout

```
oracle/
├── haskell/                  Formal validation layer
│   ├── oracle-core.cabal
│   ├── src/Oracle/{Json,Units,Formula,Types,Validation}.hs
│   └── app/Main.hs           `oracle-validate` CLI
├── julia/                    Numerical simulation engine
│   ├── Project.toml
│   └── src/{JsonMini,FormulaEval,Reproducibility,StatsEngine,
│             Solvers,Sweep,Sensitivity,MonteCarlo,ResultStore,
│             Oracle,run_experiment}.jl
├── scala/                    Orchestration layer
│   ├── build.sbt, project/build.properties
│   └── src/main/scala/oracle/{JsonMini,Domain,Registry,Scheduler,
│             ApiServer,ResultComparison,ReportGenerator,Cli,Main}.scala
├── web/                      Trilingual, 5-theme workbench (standalone)
│   ├── index.html
│   ├── css/{themes,styles}.css
│   └── js/{i18n,engine,availability,app}.js
└── examples/
    └── radioactive_decay.json
```

### 5. Installing the toolchains

No package-manager libraries are required for the Haskell/Julia/Scala layers — only the language toolchains themselves:

```bash
# Haskell (GHC + cabal), via GHCup
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ghcup install ghc && ghcup install cabal

# Julia (1.8+)
curl -fsSL https://install.julialang.org | sh
# ...or on Debian/Ubuntu:  sudo apt install julia

# Scala + sbt (needs a JDK 11+ first)
sudo apt install openjdk-17-jdk
curl -fL https://github.com/coursier/coursier/releases/latest/download/cs-x86_64-pc-linux.gz | gzip -d > cs
chmod +x cs && ./cs setup   # installs sbt, scala, scalac on PATH
```

The web workbench needs nothing but a modern browser (it pulls Chart.js from a CDN for charts; everything else is self-contained).

### 6. Running the full pipeline end to end

```bash
# 1. Validate an experiment definition with the Haskell layer
cd haskell
cabal build
cabal run oracle-validate -- ../examples/radioactive_decay.json validated_decay.json

# 2. Run it through the Julia Simulation Engine
cd ../julia/src
julia run_experiment.jl simulate ../../haskell/validated_decay.json ../../results
julia run_experiment.jl montecarlo ../../haskell/validated_decay.json ../../results 5000
julia run_experiment.jl sweep ../../haskell/validated_decay.json ../../results 10
julia run_experiment.jl sensitivity ../../haskell/validated_decay.json ../../results

# 3. Register it and orchestrate runs through Scala
cd ../../scala
export ORACLE_JULIA_ENTRY=../julia/src/run_experiment.jl
sbt "run experiment create radioactive_decay ../haskell/validated_decay.json"
sbt "run experiment list"
sbt "run montecarlo <experiment-id> 2000"
sbt "run report <experiment-id> <path-to-a-result.json> html"

# Or start the REST API and worker pool together:
sbt "run api 8080"

# 4. Open the standalone Web UI
cd ../web
python3 -m http.server 8000   # or just double-click index.html
# then visit http://localhost:8000
```

### 7. The Web Workbench

Open `web/index.html` (locally or via any static file server). It includes:

- **Experiment Builder** — define variables, parameters (with distributions and bounds), constants, equations and constraints, with the same structural/dimensional/bounds validation rules as the Haskell layer running live in the browser.
- **Formula Lab**, **Parameter Sweep Studio**, **Monte Carlo Lab**, **Sensitivity Lab** — each backed by a real, from-scratch JavaScript implementation of the parser, RK4 integrator, sampling distributions, and OAT sensitivity method (mirroring the Julia engine, so results are consistent, and the workbench works fully offline for exploration without needing the backend running).
- **Result Explorer** and **Report Studio** — charts (via Chart.js) and a downloadable, self-contained HTML report.
- **Resource Availability** — a genuinely interactive, fully user-defined widget: type in a resource's name and its opening/closing time, and the page computes live whether it is currently open and how long until the next change — nothing about the hours is hard-coded.
- **5 themes** (Windows 11 Light, Windows 11 Dark, Windows 11 Default/Mica, Red, Blue) and **3 languages** (English, Persian/فارسی with full right-to-left layout, and Chinese/中文), switchable instantly from the title bar.

### 8. License

MIT — see the license header in `haskell/oracle-core.cabal`; apply the same terms across the repository unless you replace it with your organization's preferred license.

---

<a id="فارسی"></a>
## 🇮🇷 فارسی

### ۱. اوراکل چیست

اوراکل یک بستر آزمایش علمی است که حول یک ایده اصلی ساخته شده: **یک آزمایش باید یک شیء تایپ‌شده، اعتبارسنجی‌شده و نسخه‌بندی‌شده باشد** — نه یک اسکریپت پراکنده — تا پیش از مصرف منابع محاسباتی از صحت آن اطمینان حاصل شود، بعداً به‌صورت کاملاً یکسان دوباره اجرا شود، با اجراهای دیگر مقایسه گردد و به‌طور خودکار به یک گزارش تبدیل شود.

سه زبان، هرکدام دقیقاً یک لایه را بر عهده دارند:

| لایه | زبان | مسئولیت |
|---|---|---|
| **لایه اعتبارسنجی صوری** | **Haskell** | زبان تعریف صوری آزمایش، موتور فرمول (تجزیه‌گر + AST + تحلیل ابعادی) و موتور قوانین/اعتبارسنجی. هیچ‌چیز پیش از عبور از اعتبارسنجی ساختاری، ابعادی و محدودیت‌ها به موتور شبیه‌سازی نمی‌رسد. |
| **هسته عددی** | **Julia** | موتور شبیه‌سازی (حل‌کننده‌های اویلر / RK4 / Dormand–Prince RK45 تطبیقی)، موتور مونت‌کارلو، موتور جاروب پارامتر، موتور تحلیل حساسیت و موتور تحلیل آماری (رگرسیون، آزمون t، بازه اطمینان بوت‌استرپ — همگی از پایه پیاده‌سازی شده‌اند). |
| **لایه هماهنگ‌سازی** | **Scala** | ثبت آزمایش‌ها، زمان‌بند کار به سبک توزیع‌شده (صف اولویت‌دار، تلاش مجدد، مهلت زمانی، سلامت Worker)، رابط REST، موتور مقایسه نتایج، تولیدکننده گزارش و CLI حرفه‌ای. |
| **میزکار** | **HTML/CSS/JS** | یک میزکار کامل سمت کاربر — سازنده آزمایش، آزمایشگاه فرمول، استودیوی جاروب پارامتر، آزمایشگاه مونت‌کارلو، آزمایشگاه حساسیت، کاوشگر نتایج، استودیوی گزارش، در دسترس‌بودن منابع و ثبت آزمایش‌ها — با ۵ تم و ۳ زبان، قابل استفاده به‌صورت مستقل در هر مرورگر. |

هر چهار لایه روی **یک شمای مشترک JSON** برای تعریف آزمایش و **یک قالب مشترک JSON AST** برای فرمول‌ها توافق دارند، بنابراین فرمولی که توسط Haskell تجزیه، توسط Julia ارزیابی و به‌صورت زنده در مرورگر دوباره ارزیابی می‌شود، همیشه دقیقاً معنای یکسانی دارد.

### ۲. فلسفه طراحی: صفر وابستگی به کتابخانه‌های شخص ثالث

هر لایه — Haskell، Julia و Scala — تنها بر پایه کتابخانه استاندارد خودش ساخته شده است. هیچ `aeson`، هیچ `Distributions.jl`، هیچ `circe` و هیچ `Akka` وجود ندارد. هر لایه تجزیه‌گر/رمزگذار JSON حدود ۱۵۰ تا ۲۵۰ خطی خودش را دارد و در صورت نیاز، عملیات عددی خودش را نیز پیاده‌سازی می‌کند (نمونه‌برداری Box–Muller، تابع بتای ناقص منظم برای آزمون t، جدول Butcher روش Dormand–Prince). این یک تصمیم آگاهانه برای بازتولیدپذیری است: یک نصب تازه از GHC، Julia یا sbt برای ساخت و اجرای هر لایه کافی است، بدون هیچ شگفتی در حل وابستگی‌ها پس از ماه‌ها یا سال‌ها.

### ۳. یادداشت صادقانه درباره محدوده کار

مشخصات اولیه‌ای که برای سیستمی مانند اوراکل توصیف شده، یک پلتفرم سازمانی با ده‌ها زیرسیستم (بازار کامل افزونه، گراف دانش، زمان‌بندی خوشه GPU، گردش کار داوری همتا، دستیار پژوهشی زبان طبیعی و موارد دیگر) را شرح می‌دهد که ساخت آن توسط یک تیم مهندسی بزرگ زمان زیادی می‌برد. این مخزن یک **خط لوله هسته‌ای** واقعی، کاربردی و سرتاسری را پیاده‌سازی می‌کند — تعریف ← اعتبارسنجی ← شبیه‌سازی ← جاروب/مونت‌کارلو/حساسیت ← هماهنگ‌سازی ← مقایسه ← گزارش — با منطق واقعی در هر مرحله و بدون هیچ تابع ساختگی. این یک پایه جدی برای توسعه است، نه چشم‌انداز کامل سازمانی. ماژول‌های زیر هر پوشه زبان را به‌عنوان نقاط اتصال برای افزودن موتورهای بیشتر (حل‌کننده‌های PDE، بهینه‌سازی بیزی، گراف دانش و غیره) در نظر بگیرید.

### ۴. ساختار مخزن

```
oracle/
├── haskell/                  لایه اعتبارسنجی صوری
│   ├── oracle-core.cabal
│   ├── src/Oracle/{Json,Units,Formula,Types,Validation}.hs
│   └── app/Main.hs           ابزار خط فرمان `oracle-validate`
├── julia/                    موتور شبیه‌سازی عددی
│   ├── Project.toml
│   └── src/{JsonMini,FormulaEval,Reproducibility,StatsEngine,
│             Solvers,Sweep,Sensitivity,MonteCarlo,ResultStore,
│             Oracle,run_experiment}.jl
├── scala/                    لایه هماهنگ‌سازی
│   ├── build.sbt, project/build.properties
│   └── src/main/scala/oracle/{JsonMini,Domain,Registry,Scheduler,
│             ApiServer,ResultComparison,ReportGenerator,Cli,Main}.scala
├── web/                      میزکار سه‌زبانه با ۵ تم (مستقل)
│   ├── index.html
│   ├── css/{themes,styles}.css
│   └── js/{i18n,engine,availability,app}.js
└── examples/
    └── radioactive_decay.json
```

### ۵. نصب زنجیره ابزارها

برای لایه‌های Haskell/Julia/Scala نیازی به کتابخانه‌های مدیر بسته نیست — فقط خود زنجیره‌های ابزار زبان لازم است:

```bash
# Haskell (GHC + cabal) از طریق GHCup
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ghcup install ghc && ghcup install cabal

# Julia (نسخه ۱.۸ به بالا)
curl -fsSL https://install.julialang.org | sh
# یا در دبیان/اوبونتو:  sudo apt install julia

# Scala + sbt (ابتدا به JDK 11 یا بالاتر نیاز است)
sudo apt install openjdk-17-jdk
curl -fL https://github.com/coursier/coursier/releases/latest/download/cs-x86_64-pc-linux.gz | gzip -d > cs
chmod +x cs && ./cs setup   # sbt، scala و scalac را در PATH نصب می‌کند
```

میزکار وب فقط به یک مرورگر مدرن نیاز دارد (برای نمودارها Chart.js را از یک CDN بارگذاری می‌کند؛ بقیه کاملاً مستقل است).

### ۶. اجرای کامل خط لوله سرتاسر

```bash
# ۱. اعتبارسنجی یک تعریف آزمایش با لایه Haskell
cd haskell
cabal build
cabal run oracle-validate -- ../examples/radioactive_decay.json validated_decay.json

# ۲. اجرای آن از طریق موتور شبیه‌سازی Julia
cd ../julia/src
julia run_experiment.jl simulate ../../haskell/validated_decay.json ../../results
julia run_experiment.jl montecarlo ../../haskell/validated_decay.json ../../results 5000
julia run_experiment.jl sweep ../../haskell/validated_decay.json ../../results 10
julia run_experiment.jl sensitivity ../../haskell/validated_decay.json ../../results

# ۳. ثبت و هماهنگ‌سازی اجراها از طریق Scala
cd ../../scala
export ORACLE_JULIA_ENTRY=../julia/src/run_experiment.jl
sbt "run experiment create radioactive_decay ../haskell/validated_decay.json"
sbt "run experiment list"
sbt "run montecarlo <experiment-id> 2000"
sbt "run report <experiment-id> <path-to-a-result.json> html"

# یا شروع همزمان REST API و استخر Worker:
sbt "run api 8080"

# ۴. باز کردن رابط وب مستقل
cd ../web
python3 -m http.server 8000   # یا فقط روی index.html دوبار کلیک کنید
# سپس به http://localhost:8000 مراجعه کنید
```

### ۷. میزکار وب

فایل `web/index.html` را باز کنید (به‌صورت محلی یا از طریق هر سرور فایل استاتیک). این میزکار شامل موارد زیر است:

- **سازنده آزمایش** — تعریف متغیرها، پارامترها (با توزیع و محدودیت)، ثابت‌ها، معادلات و محدودیت‌ها، با همان قوانین اعتبارسنجی ساختاری/ابعادی/محدودیت‌ها که در لایه Haskell وجود دارد و به‌صورت زنده در مرورگر اجرا می‌شود.
- **آزمایشگاه فرمول**، **استودیوی جاروب پارامتر**، **آزمایشگاه مونت‌کارلو**، **آزمایشگاه حساسیت** — هرکدام با یک پیاده‌سازی واقعی و از-پایه در جاوااسکریپت از تجزیه‌گر، انتگرال‌گیر RK4، توزیع‌های نمونه‌برداری و روش حساسیت یک‌به‌یک (که با موتور Julia هم‌راستا است، بنابراین نتایج سازگارند و میزکار به‌طور کامل بدون نیاز به اجرای بک‌اند قابل استفاده است).
- **کاوشگر نتایج** و **استودیوی گزارش** — نمودارها (با Chart.js) و یک گزارش HTML مستقل و قابل دانلود.
- **در دسترس‌بودن منابع** — ابزاری واقعاً تعاملی و کاملاً تعریف‌شده توسط کاربر: نام یک منبع و زمان باز و بسته شدن آن را وارد کنید، و صفحه به‌صورت زنده محاسبه می‌کند که آیا اکنون باز است یا خیر و چه مدت تا تغییر بعدی باقی مانده — هیچ‌چیز درباره ساعات از پیش تعیین‌شده نیست.
- **۵ تم** (روشن ویندوز ۱۱، تاریک ویندوز ۱۱، پیش‌فرض/Mica ویندوز ۱۱، قرمز، آبی) و **۳ زبان** (انگلیسی، فارسی با چیدمان کامل راست‌به‌چپ، و چینی) که بلافاصله از نوار عنوان قابل تغییرند.

### ۸. مجوز

MIT — به سربرگ مجوز در `haskell/oracle-core.cabal` مراجعه کنید؛ همان شرایط را در کل مخزن اعمال کنید مگر اینکه آن را با مجوز مورد نظر سازمان خود جایگزین کنید.

---

<a id="中文"></a>
## 🇨🇳 中文

### 一、ORACLE 是什么

ORACLE 是一个科学实验平台，其核心理念是：**实验应当是一个有类型、经过验证、可版本化的对象**，而不是一段松散的脚本——这样才能在消耗计算资源之前检查其正确性，之后逐字节精确复现，与其他运行结果比较，并自动生成报告。

三种语言各自负责一个明确的层次：

| 层 | 语言 | 职责 |
|---|---|---|
| **形式化验证层** | **Haskell** | 形式化实验定义语言、公式引擎（解析器 + 抽象语法树 + 量纲分析）以及规则/验证引擎。任何内容在通过结构、量纲和边界验证之前都无法进入仿真引擎。 |
| **数值核心** | **Julia** | 仿真引擎（欧拉法 / RK4 / 自适应 Dormand–Prince RK45 积分器）、蒙特卡洛引擎、参数扫描引擎、灵敏度分析引擎，以及统计分析引擎（回归、t 检验、自助法置信区间——均从头实现）。 |
| **编排层** | **Scala** | 实验注册表、分布式风格的任务调度器（优先级队列、重试、超时、工作节点健康检查）、REST API、结果比较引擎、报告生成器，以及专业级命令行工具。 |
| **工作台** | **HTML/CSS/JS** | 一个完整的客户端工作台——实验构建器、公式实验室、参数扫描工作室、蒙特卡洛实验室、灵敏度实验室、结果浏览器、报告工作室、资源可用性面板与实验注册表——支持 5 种主题和 3 种语言，可在任意浏览器中独立使用。 |

以上四层共用**同一套 JSON 实验定义模式**和**同一套公式 JSON 语法树格式**，因此一个由 Haskell 解析、由 Julia 求值、并在浏览器中实时再次求值的公式，其含义始终完全一致。

### 二、设计理念：零第三方依赖

Haskell、Julia 和 Scala 三层均仅基于各自语言的标准库构建，不使用 `aeson`、`Distributions.jl`、`circe` 或 `Akka`。每一层都自带约 150–250 行的 JSON 解析/编码模块，并在需要时自行实现数值算法（Box–Muller 采样、用于 t 检验的正则化不完全贝塔函数、Dormand–Prince 的 Butcher 表）。这是一项刻意的可复现性设计：只需全新安装 GHC、Julia 或 sbt，即可构建并运行每一层，多年后也不会遇到依赖解析方面的意外。

### 三、关于范围的坦诚说明

ORACLE 最初的规格描述了一个拥有数十个子系统的企业级平台（完整的插件市场、知识图谱、GPU 集群调度、同行评审工作流、自然语言研究助手等），需要一个庞大的工程团队花费很长时间才能构建完成。本仓库实现的是一条真实、可运行的**端到端核心流水线**——定义 → 验证 → 仿真 → 扫描/蒙特卡洛/灵敏度分析 → 编排 → 比较 → 报告——每一步都具备真实逻辑，没有任何模拟（mock）函数。它是一个可供扩展的坚实基础，而非完整的企业级愿景。可以将各语言目录下的模块视为接入点，用于添加更多引擎（偏微分方程求解器、贝叶斯优化、知识图谱等）。

### 四、仓库结构

```
oracle/
├── haskell/                  形式化验证层
│   ├── oracle-core.cabal
│   ├── src/Oracle/{Json,Units,Formula,Types,Validation}.hs
│   └── app/Main.hs           `oracle-validate` 命令行工具
├── julia/                    数值仿真引擎
│   ├── Project.toml
│   └── src/{JsonMini,FormulaEval,Reproducibility,StatsEngine,
│             Solvers,Sweep,Sensitivity,MonteCarlo,ResultStore,
│             Oracle,run_experiment}.jl
├── scala/                    编排层
│   ├── build.sbt, project/build.properties
│   └── src/main/scala/oracle/{JsonMini,Domain,Registry,Scheduler,
│             ApiServer,ResultComparison,ReportGenerator,Cli,Main}.scala
├── web/                      三语言、5 主题工作台（独立运行）
│   ├── index.html
│   ├── css/{themes,styles}.css
│   └── js/{i18n,engine,availability,app}.js
└── examples/
    └── radioactive_decay.json
```

### 五、安装工具链

Haskell / Julia / Scala 三层均不需要任何包管理器中的第三方库——只需安装语言工具链本身：

```bash
# Haskell（GHC + cabal），通过 GHCup 安装
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ghcup install ghc && ghcup install cabal

# Julia（1.8 及以上版本）
curl -fsSL https://install.julialang.org | sh
# 或在 Debian/Ubuntu 上：sudo apt install julia

# Scala + sbt（需先安装 JDK 11 及以上版本）
sudo apt install openjdk-17-jdk
curl -fL https://github.com/coursier/coursier/releases/latest/download/cs-x86_64-pc-linux.gz | gzip -d > cs
chmod +x cs && ./cs setup   # 将 sbt、scala、scalac 安装到 PATH 中
```

Web 工作台只需要一个现代浏览器（图表通过 CDN 加载 Chart.js；其余部分完全自包含）。

### 六、端到端运行完整流水线

```bash
# 1. 使用 Haskell 层验证实验定义
cd haskell
cabal build
cabal run oracle-validate -- ../examples/radioactive_decay.json validated_decay.json

# 2. 通过 Julia 仿真引擎运行
cd ../julia/src
julia run_experiment.jl simulate ../../haskell/validated_decay.json ../../results
julia run_experiment.jl montecarlo ../../haskell/validated_decay.json ../../results 5000
julia run_experiment.jl sweep ../../haskell/validated_decay.json ../../results 10
julia run_experiment.jl sensitivity ../../haskell/validated_decay.json ../../results

# 3. 通过 Scala 注册并编排运行
cd ../../scala
export ORACLE_JULIA_ENTRY=../julia/src/run_experiment.jl
sbt "run experiment create radioactive_decay ../haskell/validated_decay.json"
sbt "run experiment list"
sbt "run montecarlo <experiment-id> 2000"
sbt "run report <experiment-id> <path-to-a-result.json> html"

# 或同时启动 REST API 与工作节点池：
sbt "run api 8080"

# 4. 打开独立的 Web 界面
cd ../web
python3 -m http.server 8000   # 或直接双击 index.html
# 然后访问 http://localhost:8000
```

### 七、Web 工作台

打开 `web/index.html`（可本地打开，也可通过任意静态文件服务器访问）。其中包含：

- **实验构建器**——定义变量、参数（含分布与边界）、常量、方程与约束，并在浏览器中实时执行与 Haskell 层相同的结构/量纲/边界验证规则。
- **公式实验室**、**参数扫描工作室**、**蒙特卡洛实验室**、**灵敏度实验室**——均由一套真实的、从零实现的 JavaScript 解析器、RK4 积分器、采样分布和一次一参数（OAT）灵敏度方法驱动（与 Julia 引擎保持一致，因此结果相符，且工作台无需后端运行即可完全离线使用）。
- **结果浏览器**与**报告工作室**——图表（基于 Chart.js）以及可下载的自包含 HTML 报告。
- **资源可用性**——一个真正可交互、完全由用户自定义的组件：输入资源名称及其开放/关闭时间，页面会实时计算该资源当前是否开放，以及距下次状态变化还有多长时间——时间完全没有任何硬编码。
- **5 种主题**（Windows 11 浅色、Windows 11 深色、Windows 11 默认/Mica、红色、蓝色）与**3 种语言**（英语、带完整从右到左布局的波斯语，以及中文），均可在标题栏即时切换。

### 八、许可证

MIT——详见 `haskell/oracle-core.cabal` 中的许可证声明；除非替换为贵组织首选的许可证，否则请在整个仓库中应用相同条款。
