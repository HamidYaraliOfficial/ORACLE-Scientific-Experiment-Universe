/* ============================================================
   ORACLE Web UI — i18n
   Three languages: English (ltr), Persian/Farsi (rtl), Chinese (ltr).
   ============================================================ */

const ORACLE_I18N = {
  en: {
    dir: "ltr", locale: "en-US", name: "English",
    appName: "ORACLE", tagline: "Scientific Experiment Universe",
    nav_builder: "Experiment Builder", nav_formula: "Formula Lab",
    nav_sweep: "Parameter Sweep Studio", nav_montecarlo: "Monte Carlo Lab",
    nav_sensitivity: "Sensitivity Lab", nav_results: "Result Explorer",
    nav_report: "Report Studio", nav_availability: "Resource Availability",
    nav_registry: "Experiment Registry", nav_about: "About",
    theme_label: "Theme", lang_label: "Language",
    theme_light: "Windows Light", theme_dark: "Windows Dark",
    theme_default: "Windows Default", theme_red: "Red", theme_blue: "Blue",
    builder_title: "Experiment Builder", builder_subtitle: "Define variables, parameters, equations, constraints and solver settings — validated live, exactly as ORACLE's Haskell layer would.",
    name_label: "Experiment name", desc_label: "Description",
    variables_title: "Variables & Parameters", add_variable: "Add variable",
    equations_title: "Equations (dState/dt)", add_equation: "Add equation",
    constraints_title: "Constraints", add_constraint: "Add constraint",
    solver_title: "Solver & Time Settings", solver_method: "Method",
    step_size: "Step size", tolerance: "Tolerance (RK45)", max_steps: "Max steps",
    time_start: "Time start", time_end: "Time end", seed_label: "Master seed",
    replications_label: "Replications",
    validation_title: "Live Validation", validation_none: "No issues found.",
    load_example: "Load example", export_json: "Export experiment JSON",
    run_simulation: "Run simulation",
    formula_title: "Formula Lab", formula_subtitle: "Parse and evaluate a single expression against a variable environment — the same grammar the Haskell Formula Engine and Julia evaluator share.",
    expression_label: "Expression", environment_label: "Variable environment (name = value, one per line)",
    evaluate: "Evaluate", ast_label: "Parsed AST", result_label: "Result", deps_label: "Dependencies",
    sweep_title: "Parameter Sweep Studio", sweep_subtitle: "Grid search or Latin Hypercube Sampling over parameter ranges, each combination run as an independent simulation.",
    sweep_method: "Sampling method", grid: "Grid search", lhs: "Latin Hypercube",
    resolution_label: "Resolution per dimension", n_samples_label: "Number of samples",
    run_sweep: "Run sweep", sweep_results_title: "Sweep results",
    mc_title: "Monte Carlo Lab", mc_subtitle: "Sample parameters from declared distributions and propagate uncertainty through the model.",
    distribution_label: "Distribution", uniform: "Uniform", normal: "Normal", lognormal: "Log-normal",
    run_montecarlo: "Run Monte Carlo", mc_summary_title: "Summary statistics",
    sensitivity_title: "Sensitivity Lab", sensitivity_subtitle: "One-at-a-time local sensitivity: perturb each parameter by ±10% and observe the effect on the chosen output metric.",
    run_sensitivity: "Run sensitivity analysis", tornado_title: "Sensitivity tornado",
    results_title: "Result Explorer", results_subtitle: "The most recent run from any lab, rendered as a table and chart.",
    no_results: "No results yet — run a simulation, sweep, or Monte Carlo study first.",
    report_title: "Report Studio", report_subtitle: "Compile the current experiment definition and latest results into a shareable scientific report.",
    generate_report: "Generate HTML report", download_report: "Download report",
    availability_title: "Resource Availability", availability_subtitle: "Register the operating hours of a compute resource, lab instrument, or worker pool — entirely user-defined, nothing hard-coded.",
    resource_name: "Resource name", opens_at: "Opens at", closes_at: "Closes at",
    add_resource: "Add resource", status_open: "Open", status_closed: "Closed",
    next_change_in: "Next change in", no_resources: "No resources registered yet.",
    registry_title: "Experiment Registry", registry_subtitle: "Every experiment defined in this session, with tags, favorites and version.",
    registry_empty: "Nothing registered yet — build an experiment and click \"Export experiment JSON\" to register it here.",
    about_title: "About ORACLE", about_body: "ORACLE is a Scientific Experiment Universe: a unified environment for defining, validating, running, analyzing and reproducing scientific, engineering and computational experiments. Julia drives numerical simulation, Scala orchestrates distributed execution, and Haskell provides the formal validation layer — see the bundled README for the full architecture.",
    metric: "Metric", value: "Value", parameter: "Parameter", severity: "Severity",
    location: "Location", message: "Message", info: "Info", warning: "Warning", error: "Error",
    save: "Save", cancel: "Cancel", remove: "Remove", close: "Close",
    toast_registered: "Experiment registered", toast_exported: "Experiment JSON downloaded",
    toast_report_ready: "Report generated", command_palette: "Search commands…",
  },
  fa: {
    dir: "rtl", locale: "fa-IR", name: "فارسی",
    appName: "اوراکل", tagline: "جهان آزمایش‌های علمی",
    nav_builder: "سازنده آزمایش", nav_formula: "آزمایشگاه فرمول",
    nav_sweep: "استودیوی جاروب پارامتر", nav_montecarlo: "آزمایشگاه مونت‌کارلو",
    nav_sensitivity: "آزمایشگاه حساسیت", nav_results: "کاوشگر نتایج",
    nav_report: "استودیوی گزارش", nav_availability: "در دسترس‌بودن منابع",
    nav_registry: "ثبت آزمایش‌ها", nav_about: "درباره",
    theme_label: "تم", lang_label: "زبان",
    theme_light: "روشن ویندوز", theme_dark: "تاریک ویندوز",
    theme_default: "پیش‌فرض ویندوز", theme_red: "قرمز", theme_blue: "آبی",
    builder_title: "سازنده آزمایش", builder_subtitle: "متغیرها، پارامترها، معادلات، محدودیت‌ها و تنظیمات حل‌کننده را تعریف کنید — دقیقاً مطابق لایه اعتبارسنجی Haskell به صورت زنده بررسی می‌شود.",
    name_label: "نام آزمایش", desc_label: "توضیحات",
    variables_title: "متغیرها و پارامترها", add_variable: "افزودن متغیر",
    equations_title: "معادلات (dState/dt)", add_equation: "افزودن معادله",
    constraints_title: "محدودیت‌ها", add_constraint: "افزودن محدودیت",
    solver_title: "تنظیمات حل‌کننده و زمان", solver_method: "روش",
    step_size: "اندازه گام", tolerance: "دقت (RK45)", max_steps: "حداکثر گام‌ها",
    time_start: "زمان شروع", time_end: "زمان پایان", seed_label: "بذر اصلی",
    replications_label: "تعداد تکرار",
    validation_title: "اعتبارسنجی زنده", validation_none: "هیچ مشکلی یافت نشد.",
    load_example: "بارگذاری نمونه", export_json: "خروجی JSON آزمایش",
    run_simulation: "اجرای شبیه‌سازی",
    formula_title: "آزمایشگاه فرمول", formula_subtitle: "یک عبارت را در برابر محیط متغیرها تجزیه و ارزیابی کنید — همان دستور زبانی که موتور فرمول Haskell و ارزیاب Julia به اشتراک می‌گذارند.",
    expression_label: "عبارت", environment_label: "محیط متغیرها (نام = مقدار، هر خط یکی)",
    evaluate: "ارزیابی", ast_label: "درخت تجزیه‌شده", result_label: "نتیجه", deps_label: "وابستگی‌ها",
    sweep_title: "استودیوی جاروب پارامتر", sweep_subtitle: "جستجوی شبکه‌ای یا نمونه‌گیری Latin Hypercube روی بازه‌های پارامتر، هر ترکیب به‌صورت یک شبیه‌سازی مستقل اجرا می‌شود.",
    sweep_method: "روش نمونه‌گیری", grid: "جستجوی شبکه‌ای", lhs: "Latin Hypercube",
    resolution_label: "وضوح در هر بعد", n_samples_label: "تعداد نمونه‌ها",
    run_sweep: "اجرای جاروب", sweep_results_title: "نتایج جاروب",
    mc_title: "آزمایشگاه مونت‌کارلو", mc_subtitle: "نمونه‌برداری پارامترها از توزیع‌های تعریف‌شده و انتشار عدم قطعیت در مدل.",
    distribution_label: "توزیع", uniform: "یکنواخت", normal: "نرمال", lognormal: "لگ‌نرمال",
    run_montecarlo: "اجرای مونت‌کارلو", mc_summary_title: "آمار خلاصه",
    sensitivity_title: "آزمایشگاه حساسیت", sensitivity_subtitle: "حساسیت محلی یک‌به‌یک: هر پارامتر را ±۱۰٪ تغییر دهید و اثر آن را روی معیار خروجی انتخابی مشاهده کنید.",
    run_sensitivity: "اجرای تحلیل حساسیت", tornado_title: "نمودار طوفانی حساسیت",
    results_title: "کاوشگر نتایج", results_subtitle: "آخرین اجرا از هر آزمایشگاه، به صورت جدول و نمودار.",
    no_results: "هنوز نتیجه‌ای نیست — ابتدا یک شبیه‌سازی، جاروب یا مطالعه مونت‌کارلو اجرا کنید.",
    report_title: "استودیوی گزارش", report_subtitle: "تعریف آزمایش فعلی و آخرین نتایج را به یک گزارش علمی قابل اشتراک‌گذاری تبدیل کنید.",
    generate_report: "تولید گزارش HTML", download_report: "دانلود گزارش",
    availability_title: "در دسترس‌بودن منابع", availability_subtitle: "ساعات کاری یک منبع محاسباتی، دستگاه آزمایشگاهی یا استخر Worker را ثبت کنید — کاملاً توسط کاربر تعریف می‌شود، هیچ مقداری از پیش تعیین‌شده نیست.",
    resource_name: "نام منبع", opens_at: "زمان باز شدن", closes_at: "زمان بسته شدن",
    add_resource: "افزودن منبع", status_open: "باز", status_closed: "بسته",
    next_change_in: "زمان باقی‌مانده تا تغییر بعدی", no_resources: "هنوز منبعی ثبت نشده است.",
    registry_title: "ثبت آزمایش‌ها", registry_subtitle: "هر آزمایش تعریف‌شده در این جلسه، همراه با برچسب‌ها، موردعلاقه‌ها و نسخه.",
    registry_empty: "هنوز چیزی ثبت نشده — یک آزمایش بسازید و روی «خروجی JSON آزمایش» کلیک کنید تا اینجا ثبت شود.",
    about_title: "درباره اوراکل", about_body: "اوراکل یک جهان آزمایش علمی است: محیطی یکپارچه برای تعریف، اعتبارسنجی، اجرا، تحلیل و بازتولید آزمایش‌های علمی، مهندسی و محاسباتی. Julia موتور شبیه‌سازی عددی، Scala هماهنگ‌کننده اجرای توزیع‌شده و Haskell لایه اعتبارسنجی صوری را فراهم می‌کند — برای معماری کامل به README پیوست مراجعه کنید.",
    metric: "معیار", value: "مقدار", parameter: "پارامتر", severity: "شدت",
    location: "محل", message: "پیام", info: "اطلاع", warning: "هشدار", error: "خطا",
    save: "ذخیره", cancel: "انصراف", remove: "حذف", close: "بستن",
    toast_registered: "آزمایش ثبت شد", toast_exported: "JSON آزمایش دانلود شد",
    toast_report_ready: "گزارش تولید شد", command_palette: "جستجوی دستورات…",
  },
  zh: {
    dir: "ltr", locale: "zh-CN", name: "中文",
    appName: "ORACLE", tagline: "科学实验宇宙",
    nav_builder: "实验构建器", nav_formula: "公式实验室",
    nav_sweep: "参数扫描工作室", nav_montecarlo: "蒙特卡洛实验室",
    nav_sensitivity: "灵敏度实验室", nav_results: "结果浏览器",
    nav_report: "报告工作室", nav_availability: "资源可用性",
    nav_registry: "实验注册表", nav_about: "关于",
    theme_label: "主题", lang_label: "语言",
    theme_light: "Windows 浅色", theme_dark: "Windows 深色",
    theme_default: "Windows 默认", theme_red: "红色", theme_blue: "蓝色",
    builder_title: "实验构建器", builder_subtitle: "定义变量、参数、方程、约束和求解器设置——与 ORACLE 的 Haskell 验证层完全一致的实时校验。",
    name_label: "实验名称", desc_label: "描述",
    variables_title: "变量与参数", add_variable: "添加变量",
    equations_title: "方程 (dState/dt)", add_equation: "添加方程",
    constraints_title: "约束条件", add_constraint: "添加约束",
    solver_title: "求解器与时间设置", solver_method: "方法",
    step_size: "步长", tolerance: "容差 (RK45)", max_steps: "最大步数",
    time_start: "起始时间", time_end: "结束时间", seed_label: "主随机种子",
    replications_label: "重复次数",
    validation_title: "实时校验", validation_none: "未发现问题。",
    load_example: "载入示例", export_json: "导出实验 JSON",
    run_simulation: "运行仿真",
    formula_title: "公式实验室", formula_subtitle: "针对变量环境解析并求值一个表达式——与 Haskell 公式引擎和 Julia 求值器共用的同一套语法。",
    expression_label: "表达式", environment_label: "变量环境（名称 = 值，每行一个）",
    evaluate: "求值", ast_label: "解析后的语法树", result_label: "结果", deps_label: "依赖项",
    sweep_title: "参数扫描工作室", sweep_subtitle: "对参数范围进行网格搜索或拉丁超立方采样，每个组合作为独立仿真运行。",
    sweep_method: "采样方法", grid: "网格搜索", lhs: "拉丁超立方",
    resolution_label: "每维分辨率", n_samples_label: "样本数量",
    run_sweep: "运行扫描", sweep_results_title: "扫描结果",
    mc_title: "蒙特卡洛实验室", mc_subtitle: "从声明的分布中采样参数，并将不确定性传播到模型中。",
    distribution_label: "分布", uniform: "均匀分布", normal: "正态分布", lognormal: "对数正态分布",
    run_montecarlo: "运行蒙特卡洛", mc_summary_title: "汇总统计",
    sensitivity_title: "灵敏度实验室", sensitivity_subtitle: "一次一个参数的局部灵敏度：将每个参数扰动 ±10%，观察其对所选输出指标的影响。",
    run_sensitivity: "运行灵敏度分析", tornado_title: "灵敏度龙卷风图",
    results_title: "结果浏览器", results_subtitle: "来自任一实验室的最新一次运行结果，以表格和图表呈现。",
    no_results: "尚无结果——请先运行仿真、扫描或蒙特卡洛研究。",
    report_title: "报告工作室", report_subtitle: "将当前实验定义与最新结果编译为可分享的科学报告。",
    generate_report: "生成 HTML 报告", download_report: "下载报告",
    availability_title: "资源可用性", availability_subtitle: "登记计算资源、实验设备或工作节点池的运行时间——完全由用户自行定义，没有任何硬编码。",
    resource_name: "资源名称", opens_at: "开放时间", closes_at: "关闭时间",
    add_resource: "添加资源", status_open: "开放", status_closed: "关闭",
    next_change_in: "距下次变化还有", no_resources: "尚未登记任何资源。",
    registry_title: "实验注册表", registry_subtitle: "本会话中定义的每个实验，包含标签、收藏和版本号。",
    registry_empty: "尚未注册任何内容——构建一个实验并点击“导出实验 JSON”即可在此注册。",
    about_title: "关于 ORACLE", about_body: "ORACLE 是一个科学实验宇宙：用于定义、验证、运行、分析和复现科学、工程与计算实验的统一环境。Julia 驱动数值仿真，Scala 编排分布式执行，Haskell 提供形式化验证层——完整架构请参见随附的 README。",
    metric: "指标", value: "值", parameter: "参数", severity: "严重程度",
    location: "位置", message: "信息", info: "提示", warning: "警告", error: "错误",
    save: "保存", cancel: "取消", remove: "移除", close: "关闭",
    toast_registered: "实验已注册", toast_exported: "实验 JSON 已下载",
    toast_report_ready: "报告已生成", command_palette: "搜索命令…",
  },
};

const I18n = (() => {
  let current = "en";
  const listeners = [];

  function t(key) {
    const dict = ORACLE_I18N[current] || ORACLE_I18N.en;
    return dict[key] !== undefined ? dict[key] : (ORACLE_I18N.en[key] || key);
  }

  function setLanguage(lang) {
    if (!ORACLE_I18N[lang]) return;
    current = lang;
    const dict = ORACLE_I18N[lang];
    document.documentElement.setAttribute("lang", lang);
    document.documentElement.setAttribute("dir", dict.dir);
    document.querySelectorAll("[data-i18n]").forEach(el => {
      el.textContent = t(el.getAttribute("data-i18n"));
    });
    document.querySelectorAll("[data-i18n-placeholder]").forEach(el => {
      el.setAttribute("placeholder", t(el.getAttribute("data-i18n-placeholder")));
    });
    listeners.forEach(fn => fn(lang));
  }

  function onChange(fn) { listeners.push(fn); }

  function formatNumber(n, opts) {
    try {
      return new Intl.NumberFormat(ORACLE_I18N[current].locale, opts).format(n);
    } catch (e) { return String(n); }
  }

  function formatDateTime(date) {
    try {
      return new Intl.DateTimeFormat(ORACLE_I18N[current].locale, { dateStyle: "medium", timeStyle: "short" }).format(date);
    } catch (e) { return date.toString(); }
  }

  function getLang() { return current; }

  return { t, setLanguage, onChange, formatNumber, formatDateTime, getLang };
})();
