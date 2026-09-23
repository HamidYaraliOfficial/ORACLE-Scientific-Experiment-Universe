/* ============================================================
   ORACLE Web UI — Application logic
   ============================================================ */

// ---------------------------------------------------------------
// Experiment state
// ---------------------------------------------------------------
let experiment = {
  name: "untitled_experiment",
  description: "",
  variables: [],   // { id, name, initial, unit }
  parameters: [],  // { id, name, default, min, max, unit, dist: {type,a,b} | null }
  constants: [],   // { id, name, value, unit }
  equations: [],   // { id, output, expr, unit }
  constraints: [], // { id, expr, severity }
};
let uid = 1;
const nextId = () => uid++;

let lastResult = null; // { kind: 'simulate'|'sweep'|'montecarlo'|'sensitivity', ... }
const registryList = [];
const chartInstances = {};

// ---------------------------------------------------------------
// Small utilities
// ---------------------------------------------------------------
function toast(message, kind) {
  const el = document.createElement("div");
  el.className = "toast";
  el.style.borderInlineStart = "3px solid " + (kind === "err" ? "var(--color-danger)" : kind === "warn" ? "var(--color-warning)" : "var(--color-accent)");
  el.textContent = message;
  document.getElementById("toast-container").appendChild(el);
  setTimeout(() => el.remove(), 3500);
}

function downloadText(filename, text, mime) {
  const blob = new Blob([text], { type: mime || "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = filename; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

function escapeHtml(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

function destroyChart(id) { if (chartInstances[id]) { chartInstances[id].destroy(); delete chartInstances[id]; } }

// ---------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------
function showPanel(name) {
  document.querySelectorAll(".panel").forEach(p => p.classList.remove("active"));
  document.querySelectorAll(".nav-item").forEach(n => n.classList.remove("active"));
  document.getElementById("panel-" + name).classList.add("active");
  document.querySelector(`.nav-item[data-panel="${name}"]`).classList.add("active");
}

document.querySelectorAll(".nav-item").forEach(item => {
  item.addEventListener("click", () => showPanel(item.getAttribute("data-panel")));
});

// ---------------------------------------------------------------
// Theme & language
// ---------------------------------------------------------------
document.getElementById("theme-select").addEventListener("change", e => {
  document.documentElement.setAttribute("data-theme", e.target.value);
});
document.getElementById("lang-select").addEventListener("change", e => {
  I18n.setLanguage(e.target.value);
  Availability.render();
  renderAllLists();
});
I18n.setLanguage("en");

// ---------------------------------------------------------------
// Editable list rendering (variables / parameters / constants / equations / constraints)
// ---------------------------------------------------------------
function renderVariables() {
  const c = document.getElementById("list-variables");
  c.innerHTML = experiment.variables.map(v => `
    <div class="list-row" data-id="${v.id}">
      <input type="text" placeholder="name" value="${escapeHtml(v.name)}" data-field="name" style="max-width:120px">
      <input type="number" placeholder="initial value" value="${v.initial}" data-field="initial" style="max-width:120px">
      <input type="text" placeholder="unit (e.g. m/s)" value="${escapeHtml(v.unit || "")}" data-field="unit" style="max-width:130px">
      <button class="btn small danger" data-action="remove-variable">${I18n.t("remove")}</button>
    </div>`).join("") || `<div class="empty-state" style="padding:10px">—</div>`;
  c.querySelectorAll(".list-row").forEach(row => wireRow(row, experiment.variables, onModelChanged));
}

function renderParameters() {
  const c = document.getElementById("list-parameters");
  c.innerHTML = experiment.parameters.map(p => `
    <div class="list-row" data-id="${p.id}" style="flex-wrap:wrap">
      <input type="text" placeholder="name" value="${escapeHtml(p.name)}" data-field="name" style="max-width:110px">
      <input type="number" placeholder="default" value="${p.default}" data-field="default" style="max-width:90px">
      <input type="number" placeholder="min" value="${p.min ?? ""}" data-field="min" style="max-width:80px">
      <input type="number" placeholder="max" value="${p.max ?? ""}" data-field="max" style="max-width:80px">
      <input type="text" placeholder="unit" value="${escapeHtml(p.unit || "")}" data-field="unit" style="max-width:90px">
      <select data-field="distType" style="max-width:110px">
        <option value="">—</option>
        <option value="uniform" ${p.dist?.type === "uniform" ? "selected" : ""}>${I18n.t("uniform")}</option>
        <option value="normal" ${p.dist?.type === "normal" ? "selected" : ""}>${I18n.t("normal")}</option>
        <option value="lognormal" ${p.dist?.type === "lognormal" ? "selected" : ""}>${I18n.t("lognormal")}</option>
      </select>
      <input type="number" placeholder="a (low/mean/mu)" value="${p.dist?.a ?? ""}" data-field="distA" style="max-width:110px">
      <input type="number" placeholder="b (high/std/sigma)" value="${p.dist?.b ?? ""}" data-field="distB" style="max-width:110px">
      <button class="btn small danger" data-action="remove-parameter">${I18n.t("remove")}</button>
    </div>`).join("") || `<div class="empty-state" style="padding:10px">—</div>`;
  c.querySelectorAll(".list-row").forEach(row => wireParamRow(row));
}

function wireParamRow(row) {
  const id = Number(row.getAttribute("data-id"));
  const p = experiment.parameters.find(x => x.id === id);
  row.querySelectorAll("[data-field]").forEach(input => {
    input.addEventListener("input", () => {
      const f = input.getAttribute("data-field");
      if (f === "distType") {
        if (!input.value) { p.dist = null; }
        else { p.dist = p.dist || { a: 0, b: 1 }; p.dist.type = input.value; }
      } else if (f === "distA") { p.dist = p.dist || { type: "uniform", b: 1 }; p.dist.a = parseFloat(input.value); }
      else if (f === "distB") { p.dist = p.dist || { type: "uniform", a: 0 }; p.dist.b = parseFloat(input.value); }
      else if (f === "min" || f === "max" || f === "default") { p[f] = input.value === "" ? null : parseFloat(input.value); }
      else { p[f] = input.value; }
      onModelChanged();
    });
  });
  row.querySelector('[data-action="remove-parameter"]').addEventListener("click", () => {
    experiment.parameters = experiment.parameters.filter(x => x.id !== id);
    renderParameters(); onModelChanged();
  });
}

function renderConstants() {
  const c = document.getElementById("list-constants");
  c.innerHTML = experiment.constants.map(k => `
    <div class="list-row" data-id="${k.id}">
      <input type="text" placeholder="name" value="${escapeHtml(k.name)}" data-field="name" style="max-width:120px">
      <input type="number" placeholder="value" value="${k.value}" data-field="value" style="max-width:120px">
      <input type="text" placeholder="unit" value="${escapeHtml(k.unit || "")}" data-field="unit" style="max-width:130px">
      <button class="btn small danger" data-action="remove-constant">${I18n.t("remove")}</button>
    </div>`).join("") || `<div class="empty-state" style="padding:10px">—</div>`;
  c.querySelectorAll(".list-row").forEach(row => wireRow(row, experiment.constants, onModelChanged));
}

function renderEquations() {
  const c = document.getElementById("list-equations");
  c.innerHTML = experiment.equations.map(eq => `
    <div class="list-row" data-id="${eq.id}">
      <select data-field="output" style="max-width:120px">
        ${experiment.variables.map(v => `<option value="${escapeHtml(v.name)}" ${eq.output === v.name ? "selected" : ""}>${escapeHtml(v.name)}</option>`).join("")}
      </select>
      <span style="color:var(--color-text-secondary)">d/dt =</span>
      <input type="text" placeholder="expr, e.g. -k*x" value="${escapeHtml(eq.expr)}" data-field="expr" style="flex:2">
      <input type="text" placeholder="unit" value="${escapeHtml(eq.unit || "")}" data-field="unit" style="max-width:110px">
      <button class="btn small danger" data-action="remove-equation">${I18n.t("remove")}</button>
    </div>`).join("") || `<div class="empty-state" style="padding:10px">—</div>`;
  c.querySelectorAll(".list-row").forEach(row => wireRow(row, experiment.equations, onModelChanged, "remove-equation"));
}

function renderConstraints() {
  const c = document.getElementById("list-constraints");
  c.innerHTML = experiment.constraints.map(cn => `
    <div class="list-row" data-id="${cn.id}">
      <input type="text" placeholder="expr, e.g. x >= 0" value="${escapeHtml(cn.expr)}" data-field="expr" style="flex:2">
      <select data-field="severity" style="max-width:110px">
        <option value="info" ${cn.severity === "info" ? "selected" : ""}>${I18n.t("info")}</option>
        <option value="warning" ${cn.severity === "warning" ? "selected" : ""}>${I18n.t("warning")}</option>
        <option value="error" ${cn.severity === "error" ? "selected" : ""}>${I18n.t("error")}</option>
      </select>
      <button class="btn small danger" data-action="remove-constraint">${I18n.t("remove")}</button>
    </div>`).join("") || `<div class="empty-state" style="padding:10px">—</div>`;
  c.querySelectorAll(".list-row").forEach(row => wireRow(row, experiment.constraints, onModelChanged, "remove-constraint"));
}

function wireRow(row, arr, onChange, removeAction) {
  const id = Number(row.getAttribute("data-id"));
  const item = arr.find(x => x.id === id);
  row.querySelectorAll("[data-field]").forEach(input => {
    input.addEventListener("input", () => {
      const f = input.getAttribute("data-field");
      const isNumeric = ["initial", "value"].includes(f);
      item[f] = isNumeric ? parseFloat(input.value) : input.value;
      onChange();
      if (f === "name") { renderEquations(); }
    });
  });
  const removeBtn = row.querySelector("[data-action]");
  if (removeBtn) {
    removeBtn.addEventListener("click", () => {
      const idx = arr.indexOf(item);
      if (idx >= 0) arr.splice(idx, 1);
      renderAllLists(); onChange();
    });
  }
}

function renderAllLists() {
  renderVariables(); renderParameters(); renderConstants(); renderEquations(); renderConstraints();
  Availability.render();
  liveValidate();
}

document.getElementById("btn-add-variable").addEventListener("click", () => {
  experiment.variables.push({ id: nextId(), name: "x" + experiment.variables.length, initial: 0, unit: "" });
  renderVariables(); renderEquations(); onModelChanged();
});
document.getElementById("btn-add-parameter").addEventListener("click", () => {
  experiment.parameters.push({ id: nextId(), name: "p" + experiment.parameters.length, default: 1, min: null, max: null, unit: "", dist: null });
  renderParameters(); onModelChanged();
});
document.getElementById("btn-add-constant").addEventListener("click", () => {
  experiment.constants.push({ id: nextId(), name: "c" + experiment.constants.length, value: 1, unit: "" });
  renderConstants(); onModelChanged();
});
document.getElementById("btn-add-equation").addEventListener("click", () => {
  const firstVar = experiment.variables[0]?.name || "";
  experiment.equations.push({ id: nextId(), output: firstVar, expr: "0", unit: "" });
  renderEquations(); onModelChanged();
});
document.getElementById("btn-add-constraint").addEventListener("click", () => {
  experiment.constraints.push({ id: nextId(), expr: "", severity: "error" });
  renderConstraints(); onModelChanged();
});

["exp-name", "exp-desc", "solver-method", "solver-step", "solver-tol", "solver-maxsteps",
 "time-start", "time-end", "exp-seed", "exp-replications"].forEach(id => {
  document.getElementById(id).addEventListener("input", onModelChanged);
});

function onModelChanged() { liveValidate(); }

// ---------------------------------------------------------------
// Live validation — mirrors Oracle.Validation's rule set
// ---------------------------------------------------------------
function collectExperimentFromForm() {
  experiment.name = document.getElementById("exp-name").value || "untitled_experiment";
  experiment.description = document.getElementById("exp-desc").value || "";
  return experiment;
}

function liveValidate() {
  collectExperimentFromForm();
  const violations = [];
  const declared = new Set(["t",
    ...experiment.variables.map(v => v.name),
    ...experiment.parameters.map(p => p.name),
    ...experiment.constants.map(c => c.name),
    ...experiment.equations.map(e => e.output)]);

  // STRUCT-002: duplicate names
  const allNames = [...experiment.variables.map(v => v.name), ...experiment.parameters.map(p => p.name),
                     ...experiment.constants.map(c => c.name), ...experiment.equations.map(e => e.output)];
  const seen = {}; allNames.forEach(n => { seen[n] = (seen[n] || 0) + 1; });
  Object.entries(seen).filter(([, n]) => n > 1).forEach(([name]) =>
    violations.push({ sev: "error", loc: "name:" + name, msg: "Duplicate declaration of name: " + name }));

  // dimension env from anything with a unit set
  const dimEnv = {};
  [...experiment.variables, ...experiment.parameters, ...experiment.constants].forEach(x => {
    if (x.unit) { try { dimEnv[x.name] = Units.parseUnit(x.unit).dim; } catch (e) { /* reported below */ } }
  });

  const parsedEquations = {};
  experiment.equations.forEach(eq => {
    if (!eq.expr) return;
    let ast;
    try { ast = Formula.parse(eq.expr); parsedEquations[eq.output] = ast; }
    catch (e) { violations.push({ sev: "fatal", loc: "equation:" + eq.output, msg: "Parse error: " + e.message }); return; }
    // STRUCT-001: undefined variables
    Formula.dependencies(ast).forEach(dep => {
      if (!declared.has(dep)) violations.push({ sev: "fatal", loc: "equation:" + eq.output, msg: "Undefined variable referenced: " + dep });
    });
    // DIM-001: dimensional consistency
    if (eq.unit) {
      try {
        const inferred = Units.inferDim(ast, dimEnv);
        const declaredDim = Units.parseUnit(eq.unit).dim;
        if (!Units.dimEq(inferred, declaredDim)) {
          violations.push({ sev: "error", loc: "equation:" + eq.output,
            msg: `Declared unit '${eq.unit}' (${Units.showDim(declaredDim)}) does not match inferred dimension (${Units.showDim(inferred)})` });
        }
      } catch (e) {
        violations.push({ sev: "error", loc: "equation:" + eq.output, msg: "Dimensional error: " + e.message });
      }
    }
  });

  experiment.constraints.forEach(cn => {
    if (!cn.expr) return;
    try {
      const ast = Formula.parse(cn.expr);
      Formula.dependencies(ast).forEach(dep => {
        if (!declared.has(dep)) violations.push({ sev: "fatal", loc: "constraint:" + cn.expr, msg: "Undefined variable referenced: " + dep });
      });
    } catch (e) { violations.push({ sev: cn.severity === "info" ? "warning" : "fatal", loc: "constraint:" + cn.expr, msg: "Parse error: " + e.message }); }
  });

  // BOUND-001
  experiment.parameters.forEach(p => {
    if (p.min != null && p.max != null && p.min > p.max) violations.push({ sev: "error", loc: p.name, msg: "min is greater than max" });
    if (p.default != null && p.min != null && p.default < p.min) violations.push({ sev: "error", loc: p.name, msg: "default value is below the declared minimum" });
    if (p.default != null && p.max != null && p.default > p.max) violations.push({ sev: "error", loc: p.name, msg: "default value is above the declared maximum" });
    if (p.dist) {
      if (p.dist.type === "uniform" && !(p.dist.a < p.dist.b)) violations.push({ sev: "error", loc: p.name, msg: "uniform distribution requires low < high" });
      if (p.dist.type === "normal" && !(p.dist.b > 0)) violations.push({ sev: "error", loc: p.name, msg: "normal distribution requires std > 0" });
      if (p.dist.type === "lognormal" && !(p.dist.b > 0)) violations.push({ sev: "error", loc: p.name, msg: "log-normal distribution requires sigma > 0" });
    }
  });

  // SOLVER-001 / TIME-001
  const step = parseFloat(document.getElementById("solver-step").value);
  const tol = parseFloat(document.getElementById("solver-tol").value);
  const maxSteps = parseInt(document.getElementById("solver-maxsteps").value, 10);
  const t0 = parseFloat(document.getElementById("time-start").value);
  const t1 = parseFloat(document.getElementById("time-end").value);
  const replications = parseInt(document.getElementById("exp-replications").value, 10);
  if (!(step > 0)) violations.push({ sev: "error", loc: "solver.stepSize", msg: "stepSize must be > 0" });
  if (!(tol > 0)) violations.push({ sev: "error", loc: "solver.tolerance", msg: "tolerance must be > 0" });
  if (!(maxSteps > 0)) violations.push({ sev: "error", loc: "solver.maxSteps", msg: "maxSteps must be > 0" });
  if (!(t1 > t0)) violations.push({ sev: "error", loc: "timeRange", msg: "timeRange end must be greater than start" });
  if (!(replications >= 1)) violations.push({ sev: "error", loc: "replications", msg: "replications must be >= 1" });
  if (experiment.equations.length === 0) violations.push({ sev: "warning", loc: "equations", msg: "No equations defined yet." });

  renderValidation(violations);
  return { violations, parsedEquations, blocking: violations.some(v => v.sev === "fatal" || v.sev === "error") };
}

function renderValidation(violations) {
  const c = document.getElementById("validation-list");
  if (violations.length === 0) { c.innerHTML = `<div class="validation-item ok">✓ ${I18n.t("validation_none")}</div>`; return; }
  c.innerHTML = violations.map(v => {
    const cls = v.sev === "warning" ? "warn" : (v.sev === "info" ? "" : "err");
    const label = v.sev === "fatal" ? I18n.t("error") : I18n.t(v.sev) || v.sev;
    return `<div class="validation-item ${cls}"><span class="badge ${cls === "err" ? "err" : cls === "warn" ? "warn" : "ok"}">${label}</span>
      <div><b>${escapeHtml(v.loc)}</b> — ${escapeHtml(v.msg)}</div></div>`;
  }).join("");
}

// ---------------------------------------------------------------
// Example experiment
// ---------------------------------------------------------------
document.getElementById("btn-load-example").addEventListener("click", () => {
  uid = 1;
  experiment = {
    name: "radioactive_decay",
    description: "First-order exponential decay: dx/dt = -k*x",
    variables: [{ id: nextId(), name: "x", initial: 100, unit: "mol" }],
    parameters: [{ id: nextId(), name: "k", default: 0.1, min: 0.01, max: 0.5, unit: "1/s", dist: { type: "uniform", a: 0.05, b: 0.2 } }],
    constants: [],
    equations: [{ id: nextId(), output: "x", expr: "-k * x", unit: "mol/s" }],
    constraints: [{ id: nextId(), expr: "x >= 0", severity: "error" }],
  };
  document.getElementById("exp-name").value = experiment.name;
  document.getElementById("exp-desc").value = experiment.description;
  document.getElementById("time-start").value = 0;
  document.getElementById("time-end").value = 50;
  document.getElementById("solver-step").value = 0.1;
  renderAllLists();
  toast("Example loaded: radioactive_decay");
});

// ---------------------------------------------------------------
// Export to the canonical ORACLE experiment JSON schema
// ---------------------------------------------------------------
function buildExportJson() {
  const initialConditions = {}; experiment.variables.forEach(v => { initialConditions[v.name] = v.initial; });
  return {
    name: experiment.name,
    description: experiment.description,
    variables: experiment.variables.map(v => ({ name: v.name, kind: "scalar", unit: v.unit || null })),
    parameters: experiment.parameters.map(p => ({
      name: p.name, kind: "scalar", unit: p.unit || null, default: p.default,
      min: p.min, max: p.max,
      distribution: p.dist ? distJson(p.dist) : null,
    })),
    constants: experiment.constants.map(c => ({ name: c.name, value: c.value, unit: c.unit || null })),
    equations: experiment.equations.map(e => ({ output: e.output, expr: e.expr, unit: e.unit || null })),
    constraints: experiment.constraints.map(c => ({ expr: c.expr, severity: c.severity })),
    initialConditions,
    solver: {
      method: document.getElementById("solver-method").value,
      stepSize: parseFloat(document.getElementById("solver-step").value),
      tolerance: parseFloat(document.getElementById("solver-tol").value),
      maxSteps: parseInt(document.getElementById("solver-maxsteps").value, 10),
    },
    seed: parseInt(document.getElementById("exp-seed").value, 10),
    replications: parseInt(document.getElementById("exp-replications").value, 10),
    timeRange: [parseFloat(document.getElementById("time-start").value), parseFloat(document.getElementById("time-end").value)],
    samplingRate: 1.0,
    metrics: [],
    outputSchema: ["t", ...experiment.variables.map(v => v.name)],
  };
}
function distJson(d) {
  if (d.type === "uniform") return { type: "uniform", low: d.a, high: d.b };
  if (d.type === "normal") return { type: "normal", mean: d.a, std: d.b };
  if (d.type === "lognormal") return { type: "lognormal", mu: d.a, sigma: d.b };
  return null;
}

document.getElementById("btn-export-json").addEventListener("click", () => {
  const { blocking } = liveValidate();
  if (blocking) { toast("Cannot export: resolve the blocking validation errors first.", "err"); return; }
  const json = buildExportJson();
  downloadText(experiment.name + ".json", JSON.stringify(json, null, 2));
  registryList.push({
    id: "exp_" + Date.now(), name: experiment.name, description: experiment.description,
    tags: [], version: 1, favorite: false, exportedAt: new Date(), json,
  });
  renderRegistry();
  toast(I18n.t("toast_exported"));
});

// ---------------------------------------------------------------
// Run simulation (Result Explorer)
// ---------------------------------------------------------------
function buildRuntimeModel() {
  const equationsAst = {};
  experiment.equations.forEach(e => { equationsAst[e.output] = Formula.parse(e.expr); });
  const constants = {}; experiment.constants.forEach(c => { constants[c.name] = c.value; });
  const y0 = {}; experiment.variables.forEach(v => { y0[v.name] = v.initial; });
  const defaultParams = {}; experiment.parameters.forEach(p => { defaultParams[p.name] = p.default ?? 0; });
  return { equationsAst, constants, y0, defaultParams };
}

document.getElementById("btn-run-simulation").addEventListener("click", () => {
  const { blocking } = liveValidate();
  if (blocking) { toast("Cannot run: resolve the blocking validation errors first.", "err"); return; }
  try {
    const { equationsAst, constants, y0, defaultParams } = buildRuntimeModel();
    const method = document.getElementById("solver-method").value === "euler" ? "euler" : "rk4";
    const step = parseFloat(document.getElementById("solver-step").value);
    const maxSteps = parseInt(document.getElementById("solver-maxsteps").value, 10);
    const t0 = parseFloat(document.getElementById("time-start").value);
    const t1 = parseFloat(document.getElementById("time-end").value);
    const result = Solver.integrate(equationsAst, constants, defaultParams, y0, t0, t1, method, step, maxSteps);
    lastResult = { kind: "simulate", result, stateNames: Object.keys(y0) };
    renderResults();
    showPanel("results");
    toast("Simulation complete (" + result.steps + " steps, " + result.flag + ")", result.flag === "STABLE" ? "ok" : "warn");
  } catch (e) { toast("Simulation error: " + e.message, "err"); }
});

// ---------------------------------------------------------------
// Formula Lab
// ---------------------------------------------------------------
document.getElementById("btn-evaluate-formula").addEventListener("click", () => {
  const expr = document.getElementById("formula-expr").value;
  const envText = document.getElementById("formula-env").value;
  const env = {};
  envText.split("\n").forEach(line => {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?[\d.eE+-]+)\s*$/);
    if (m) env[m[1]] = parseFloat(m[2]);
  });
  try {
    const ast = Formula.parse(expr);
    document.getElementById("formula-ast").textContent = JSON.stringify(ast, null, 2);
    const result = Formula.evaluate(ast, env);
    document.getElementById("formula-result").textContent = String(result);
    const deps = [...Formula.dependencies(ast)];
    document.getElementById("formula-deps").innerHTML = deps.map(d =>
      `<span class="chip">${escapeHtml(d)}${d in env ? " = " + env[d] : " (undefined)"}</span>`).join("") || "—";
  } catch (e) {
    document.getElementById("formula-ast").textContent = "—";
    document.getElementById("formula-result").textContent = "Error: " + e.message;
    document.getElementById("formula-deps").innerHTML = "";
  }
});

// ---------------------------------------------------------------
// Sweep Studio
// ---------------------------------------------------------------
document.getElementById("btn-run-sweep").addEventListener("click", () => {
  const { blocking } = liveValidate();
  if (blocking) { toast("Cannot run: resolve the blocking validation errors first.", "err"); return; }
  const sweepable = experiment.parameters.filter(p => p.min != null && p.max != null);
  if (sweepable.length === 0) { toast("No parameter has both min and max set.", "warn"); return; }
  try {
    const { equationsAst, constants, y0, defaultParams } = buildRuntimeModel();
    const method = document.getElementById("solver-method").value === "euler" ? "euler" : "rk4";
    const step = parseFloat(document.getElementById("solver-step").value);
    const maxSteps = parseInt(document.getElementById("solver-maxsteps").value, 10);
    const t0 = parseFloat(document.getElementById("time-start").value);
    const t1 = parseFloat(document.getElementById("time-end").value);
    const resolution = parseInt(document.getElementById("sweep-resolution").value, 10);
    const methodSweep = document.getElementById("sweep-method").value;

    let combos;
    if (methodSweep === "grid") {
      const ranges = {}; sweepable.forEach(p => { ranges[p.name] = [p.min, p.max, resolution]; });
      combos = SweepGen.gridSearch(ranges);
    } else {
      const bounds = {}; sweepable.forEach(p => { bounds[p.name] = [p.min, p.max]; });
      const seed = parseInt(document.getElementById("exp-seed").value, 10) || 1;
      combos = SweepGen.latinHypercube(bounds, resolution, Stats.mulberry32(seed));
    }

    const metricVar = experiment.variables[0]?.name;
    const runs = combos.map((combo, i) => {
      const params = Object.assign({}, defaultParams, combo);
      const result = Solver.integrate(equationsAst, constants, params, y0, t0, t1, method, step, maxSteps);
      const finalVal = result.states.length ? result.states[result.states.length - 1][metricVar] : NaN;
      return { index: i, params: combo, metric: finalVal, flag: result.flag };
    });
    lastResult = { kind: "sweep", runs, sweptParams: sweepable.map(p => p.name), metricVar };
    renderResults();
    showPanel("results");
    toast(`Sweep complete: ${runs.length} configurations`);
  } catch (e) { toast("Sweep error: " + e.message, "err"); }
});

// ---------------------------------------------------------------
// Monte Carlo Lab
// ---------------------------------------------------------------
document.getElementById("btn-run-mc").addEventListener("click", () => {
  const { blocking } = liveValidate();
  if (blocking) { toast("Cannot run: resolve the blocking validation errors first.", "err"); return; }
  try {
    const { equationsAst, constants, y0, defaultParams } = buildRuntimeModel();
    const method = document.getElementById("solver-method").value === "euler" ? "euler" : "rk4";
    const step = parseFloat(document.getElementById("solver-step").value);
    const maxSteps = parseInt(document.getElementById("solver-maxsteps").value, 10);
    const t0 = parseFloat(document.getElementById("time-start").value);
    const t1 = parseFloat(document.getElementById("time-end").value);
    const n = parseInt(document.getElementById("mc-nsamples").value, 10);
    const masterSeed = parseInt(document.getElementById("exp-seed").value, 10) || 1;
    const metricVar = experiment.variables[0]?.name;

    const samples = [];
    for (let i = 0; i < n; i++) {
      const rng = Stats.mulberry32((masterSeed * 2654435761 + i * 40503) >>> 0);
      const params = Object.assign({}, defaultParams);
      experiment.parameters.forEach(p => {
        if (p.dist) {
          if (p.dist.type === "uniform") params[p.name] = Stats.sampleUniform(rng, p.dist.a, p.dist.b);
          else if (p.dist.type === "normal") params[p.name] = Stats.sampleNormal(rng, p.dist.a, p.dist.b);
          else if (p.dist.type === "lognormal") params[p.name] = Stats.sampleLogNormal(rng, p.dist.a, p.dist.b);
        }
      });
      const result = Solver.integrate(equationsAst, constants, params, y0, t0, t1, method, step, maxSteps);
      const finalVal = result.states.length ? result.states[result.states.length - 1][metricVar] : NaN;
      if (isFinite(finalVal)) samples.push(finalVal);
    }
    const stats = Stats.descriptiveStats(samples);
    lastResult = { kind: "montecarlo", samples, stats, metricVar, n: samples.length };
    renderResults();
    showPanel("results");
    toast(`Monte Carlo complete: ${samples.length} valid samples`);
  } catch (e) { toast("Monte Carlo error: " + e.message, "err"); }
});

// ---------------------------------------------------------------
// Sensitivity Lab
// ---------------------------------------------------------------
document.getElementById("btn-run-sensitivity").addEventListener("click", () => {
  const { blocking } = liveValidate();
  if (blocking) { toast("Cannot run: resolve the blocking validation errors first.", "err"); return; }
  if (experiment.parameters.length === 0) { toast("Add at least one parameter first.", "warn"); return; }
  try {
    const { equationsAst, constants, y0, defaultParams } = buildRuntimeModel();
    const method = document.getElementById("solver-method").value === "euler" ? "euler" : "rk4";
    const step = parseFloat(document.getElementById("solver-step").value);
    const maxSteps = parseInt(document.getElementById("solver-maxsteps").value, 10);
    const t0 = parseFloat(document.getElementById("time-start").value);
    const t1 = parseFloat(document.getElementById("time-end").value);
    const metricVar = experiment.variables[0]?.name;

    const runFn = (params) => {
      const result = Solver.integrate(equationsAst, constants, params, y0, t0, t1, method, step, maxSteps);
      return result.states.length ? result.states[result.states.length - 1][metricVar] : NaN;
    };
    const oat = SensitivityGen.oneAtATime(defaultParams, runFn, 0.1);
    lastResult = { kind: "sensitivity", oat, metricVar };
    renderResults();
    showPanel("results");
    toast("Sensitivity analysis complete");
  } catch (e) { toast("Sensitivity error: " + e.message, "err"); }
});

// ---------------------------------------------------------------
// Result Explorer rendering
// ---------------------------------------------------------------
function renderResults() {
  const container = document.getElementById("results-container");
  if (!lastResult) { container.innerHTML = `<div class="empty-state">${I18n.t("no_results")}</div>`; return; }

  if (lastResult.kind === "simulate") {
    const { result, stateNames } = lastResult;
    container.innerHTML = `<canvas id="chart-simulate" height="100"></canvas>
      <div style="margin-top:14px"><span class="badge ${result.flag === "STABLE" ? "ok" : "warn"}">${result.flag}</span>
      &nbsp; ${result.steps} steps</div>
      <div id="simulate-table" style="margin-top:10px;max-height:260px;overflow:auto"></div>`;
    destroyChart("chart-simulate");
    const ctx = document.getElementById("chart-simulate").getContext("2d");
    chartInstances["chart-simulate"] = new Chart(ctx, {
      type: "line",
      data: {
        labels: result.times.map(t => t.toFixed(2)),
        datasets: stateNames.map((name, i) => ({
          label: name, data: result.states.map(s => s[name]),
          borderWidth: 2, pointRadius: 0, borderColor: palette(i), tension: 0.15,
        })),
      },
      options: { responsive: true, animation: false, scales: { x: { title: { display: true, text: "t" } } } },
    });
    const rows = result.times.filter((_, i) => i % Math.max(1, Math.floor(result.times.length / 200)) === 0)
      .map((t, idx) => { const s = result.states[idx * Math.max(1, Math.floor(result.times.length / 200))]; return { t, s }; });
    container.querySelector("#simulate-table").innerHTML = `<table><thead><tr><th>t</th>${stateNames.map(n => `<th>${n}</th>`).join("")}</tr></thead>
      <tbody>${result.times.map((t, i) => i % Math.max(1, Math.floor(result.times.length / 50)) === 0 ?
        `<tr><td class="ltr-num">${t.toFixed(3)}</td>${stateNames.map(n => `<td class="ltr-num">${result.states[i][n].toFixed(5)}</td>`).join("")}</tr>` : "").join("")}</tbody></table>`;
  }

  else if (lastResult.kind === "sweep") {
    const { runs, sweptParams, metricVar } = lastResult;
    container.innerHTML = `<canvas id="chart-sweep-result" height="100"></canvas>
      <div id="sweep-result-table" style="margin-top:14px;max-height:300px;overflow:auto"></div>`;
    destroyChart("chart-sweep-result");
    const ctx = document.getElementById("chart-sweep-result").getContext("2d");
    if (sweptParams.length === 1) {
      const sorted = [...runs].sort((a, b) => a.params[sweptParams[0]] - b.params[sweptParams[0]]);
      chartInstances["chart-sweep-result"] = new Chart(ctx, {
        type: "line",
        data: { labels: sorted.map(r => r.params[sweptParams[0]].toFixed(3)),
          datasets: [{ label: `final ${metricVar}`, data: sorted.map(r => r.metric), borderColor: palette(0), pointRadius: 2 }] },
        options: { responsive: true, animation: false, scales: { x: { title: { display: true, text: sweptParams[0] } } } },
      });
    } else {
      chartInstances["chart-sweep-result"] = new Chart(ctx, {
        type: "scatter",
        data: { datasets: [{ label: `final ${metricVar}`, data: runs.map(r => ({ x: r.params[sweptParams[0]], y: r.metric })), backgroundColor: palette(0) }] },
        options: { responsive: true, animation: false, scales: { x: { title: { display: true, text: sweptParams[0] + " (other dims not shown)" } } } },
      });
    }
    container.querySelector("#sweep-result-table").innerHTML = `<table><thead><tr>${sweptParams.map(p => `<th>${p}</th>`).join("")}<th>${metricVar}</th><th>flag</th></tr></thead>
      <tbody>${runs.map(r => `<tr>${sweptParams.map(p => `<td class="ltr-num">${r.params[p].toFixed(4)}</td>`).join("")}<td class="ltr-num">${r.metric.toFixed(5)}</td><td>${r.flag}</td></tr>`).join("")}</tbody></table>`;
  }

  else if (lastResult.kind === "montecarlo") {
    const { samples, stats, metricVar } = lastResult;
    container.innerHTML = `<canvas id="chart-mc-result" height="100"></canvas><dl class="kv-grid" id="mc-result-summary" style="margin-top:14px"></dl>`;
    const bins = 30;
    const min = stats.min, max = stats.max, width = (max - min) / bins || 1;
    const counts = new Array(bins).fill(0);
    samples.forEach(v => { let b = Math.floor((v - min) / width); if (b >= bins) b = bins - 1; if (b < 0) b = 0; counts[b]++; });
    destroyChart("chart-mc-result");
    const ctx = document.getElementById("chart-mc-result").getContext("2d");
    chartInstances["chart-mc-result"] = new Chart(ctx, {
      type: "bar",
      data: { labels: counts.map((_, i) => (min + i * width).toFixed(2)), datasets: [{ label: `final ${metricVar}`, data: counts, backgroundColor: palette(0) }] },
      options: { responsive: true, animation: false, plugins: { legend: { display: false } } },
    });
    document.getElementById("mc-result-summary").innerHTML = Object.entries(stats).map(([k, v]) =>
      `<dt>${k}</dt><dd class="ltr-num">${typeof v === "number" ? v.toFixed(5) : v}</dd>`).join("") +
      `<dt>empirical 95% interval</dt><dd class="ltr-num">[${Stats.percentile(samples, 2.5).toFixed(5)}, ${Stats.percentile(samples, 97.5).toFixed(5)}]</dd>`;
  }

  else if (lastResult.kind === "sensitivity") {
    const { oat, metricVar } = lastResult;
    const ranked = Object.entries(oat).sort((a, b) => b[1].range - a[1].range);
    container.innerHTML = `<canvas id="chart-sens-result" height="${Math.max(120, ranked.length * 34)}"></canvas>`;
    destroyChart("chart-sens-result");
    const ctx = document.getElementById("chart-sens-result").getContext("2d");
    chartInstances["chart-sens-result"] = new Chart(ctx, {
      type: "bar",
      data: {
        labels: ranked.map(([name]) => name),
        datasets: [
          { label: "effect (+10%)", data: ranked.map(([, v]) => v.effectPlus), backgroundColor: "#4cc9f0" },
          { label: "effect (-10%)", data: ranked.map(([, v]) => v.effectMinus), backgroundColor: "#ff5f6d" },
        ],
      },
      options: { indexAxis: "y", responsive: true, animation: false, plugins: { title: { display: true, text: `Effect on final ${metricVar}` } } },
    });
  }
}

function palette(i) { const colors = ["#0067c0", "#ff5f6d", "#107c10", "#9d5d00", "#7a3ea1", "#4cc9f0", "#c42b1c"]; return colors[i % colors.length]; }

// ---------------------------------------------------------------
// Report Studio
// ---------------------------------------------------------------
document.getElementById("btn-generate-report").addEventListener("click", () => {
  const json = buildExportJson();
  const now = new Date();
  let resultSection = "<p><em>No result recorded yet in this session.</em></p>";
  if (lastResult) {
    if (lastResult.kind === "simulate") {
      resultSection = `<p>Simulation finished with stability flag <b>${lastResult.result.flag}</b> after ${lastResult.result.steps} steps.</p>`;
    } else if (lastResult.kind === "montecarlo") {
      resultSection = `<table><tr><th>n</th><td>${lastResult.stats.n}</td></tr><tr><th>mean</th><td>${lastResult.stats.mean.toFixed(6)}</td></tr>
        <tr><th>std</th><td>${lastResult.stats.std.toFixed(6)}</td></tr>
        <tr><th>95% interval</th><td>[${Stats.percentile(lastResult.samples,2.5).toFixed(6)}, ${Stats.percentile(lastResult.samples,97.5).toFixed(6)}]</td></tr></table>`;
    } else if (lastResult.kind === "sweep") {
      resultSection = `<p>Sweep produced ${lastResult.runs.length} configurations over: ${lastResult.sweptParams.join(", ")}.</p>`;
    } else if (lastResult.kind === "sensitivity") {
      resultSection = `<p>One-at-a-time sensitivity computed for: ${Object.keys(lastResult.oat).join(", ")}.</p>`;
    }
  }
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${escapeHtml(experiment.name)} — ORACLE Report</title>
    <style>body{font-family:Segoe UI,sans-serif;max-width:820px;margin:2rem auto;padding:0 1rem;line-height:1.6}
    table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:6px 10px;text-align:left}
    pre{background:#1e1e1e;color:#d4d4d4;padding:1rem;overflow-x:auto;border-radius:6px}</style></head><body>
    <h1>ORACLE Experiment Report: ${escapeHtml(experiment.name)}</h1>
    <p><em>Generated: ${now.toISOString()}</em></p>
    <h2>Description</h2><p>${escapeHtml(experiment.description || "—")}</p>
    <h2>Configuration</h2><pre>${escapeHtml(JSON.stringify(json, null, 2))}</pre>
    <h2>Result summary</h2>${resultSection}
    <h2>Reproducibility</h2><p>Master seed: <b>${json.seed}</b>. Solver: <b>${json.solver.method}</b>, step ${json.solver.stepSize}.</p>
    <h2>Limitations</h2><p>This report was generated client-side in the ORACLE Web UI's built-in engine for quick inspection.
    For publication-grade reproducibility, run the same configuration JSON through the Haskell validator and Julia engine bundled with this project.</p>
    </body></html>`;
  document.getElementById("report-preview").textContent = html;
  const link = document.getElementById("btn-download-report");
  link.style.display = "inline-block";
  link.href = URL.createObjectURL(new Blob([html], { type: "text/html" }));
  link.download = "oracle_report_" + experiment.name + ".html";
  toast(I18n.t("toast_report_ready"));
});

// ---------------------------------------------------------------
// Resource Availability
// ---------------------------------------------------------------
document.getElementById("btn-add-resource").addEventListener("click", () => {
  const name = document.getElementById("avail-name").value.trim();
  const opens = document.getElementById("avail-opens").value;
  const closes = document.getElementById("avail-closes").value;
  if (!name || !opens || !closes) { toast("Please fill in the resource name and both times.", "warn"); return; }
  Availability.addResource(name, opens, closes);
  document.getElementById("avail-name").value = "";
});
Availability.startClock();

// ---------------------------------------------------------------
// Experiment Registry
// ---------------------------------------------------------------
function renderRegistry() {
  const c = document.getElementById("registry-container");
  if (registryList.length === 0) { c.innerHTML = `<div class="empty-state">${I18n.t("registry_empty")}</div>`; return; }
  c.innerHTML = `<table><thead><tr><th>${I18n.t("name_label")}</th><th>v</th><th>${I18n.t("desc_label")}</th><th></th></tr></thead>
    <tbody>${registryList.map(r => `<tr><td>${escapeHtml(r.name)}</td><td>${r.version}</td><td>${escapeHtml(r.description || "")}</td>
      <td><button class="btn small" onclick='downloadText("${escapeHtml(r.name)}.json", ${JSON.stringify(JSON.stringify(r.json)).replace(/'/g, "&apos;")})'>${I18n.t("export_json")}</button></td></tr>`).join("")}</tbody></table>`;
}

// ---------------------------------------------------------------
// Command palette
// ---------------------------------------------------------------
const COMMANDS = [
  { label: "Experiment Builder", run: () => showPanel("builder") },
  { label: "Formula Lab", run: () => showPanel("formula") },
  { label: "Parameter Sweep Studio", run: () => showPanel("sweep") },
  { label: "Monte Carlo Lab", run: () => showPanel("montecarlo") },
  { label: "Sensitivity Lab", run: () => showPanel("sensitivity") },
  { label: "Result Explorer", run: () => showPanel("results") },
  { label: "Report Studio", run: () => showPanel("report") },
  { label: "Resource Availability", run: () => showPanel("availability") },
  { label: "Experiment Registry", run: () => showPanel("registry") },
  { label: "Run simulation", run: () => document.getElementById("btn-run-simulation").click() },
  { label: "Export experiment JSON", run: () => document.getElementById("btn-export-json").click() },
  { label: "Load example experiment", run: () => document.getElementById("btn-load-example").click() },
];

function openPalette() {
  document.getElementById("command-palette-overlay").style.display = "flex";
  const input = document.getElementById("command-palette-input");
  input.value = ""; input.focus();
  renderPaletteResults(COMMANDS);
}
function closePalette() { document.getElementById("command-palette-overlay").style.display = "none"; }
function renderPaletteResults(list) {
  document.getElementById("command-palette-results").innerHTML = list.map((c, i) =>
    `<div class="nav-item" style="border-radius:0;padding:12px 18px" data-idx="${i}">${escapeHtml(c.label)}</div>`).join("");
  document.querySelectorAll("#command-palette-results .nav-item").forEach(el => {
    el.addEventListener("click", () => { list[Number(el.getAttribute("data-idx"))].run(); closePalette(); });
  });
}
document.getElementById("command-palette-hint").addEventListener("click", openPalette);
document.getElementById("command-palette-overlay").addEventListener("click", e => { if (e.target.id === "command-palette-overlay") closePalette(); });
document.getElementById("command-palette-input").addEventListener("input", e => {
  const q = e.target.value.toLowerCase();
  renderPaletteResults(COMMANDS.filter(c => c.label.toLowerCase().includes(q)));
});
document.addEventListener("keydown", e => {
  if ((e.ctrlKey || e.metaKey) && e.key === "k") { e.preventDefault(); openPalette(); }
  if (e.key === "Escape") closePalette();
});

// ---------------------------------------------------------------
// Boot
// ---------------------------------------------------------------
document.getElementById("btn-load-example").click();
