/* ============================================================
   ORACLE Web UI — Client-side Scientific Engine
   A real (not mocked) implementation of the same formula grammar,
   dimensional-analysis rules, ODE integrator and sampling primitives
   used by the Haskell validation layer and Julia simulation engine,
   so the Formula/Sweep/Monte-Carlo/Sensitivity labs work standalone
   in the browser without a running backend, and produce the exact
   same AST-as-JSON shape (`{"type":"binop",...}`) those layers use.
   ============================================================ */

// ---------------------------------------------------------------
// Formula: tokenizer + recursive-descent parser + evaluator
// ---------------------------------------------------------------
const Formula = (() => {
  function tokenize(src) {
    const tokens = [];
    let i = 0;
    while (i < src.length) {
      const c = src[i];
      if (/\s/.test(c)) { i++; continue; }
      if (c === "(") { tokens.push({ t: "(" }); i++; continue; }
      if (c === ")") { tokens.push({ t: ")" }); i++; continue; }
      if (c === ",") { tokens.push({ t: "," }); i++; continue; }
      if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(src[i + 1] || ""))) {
        let j = i + 1; while (j < src.length && /[0-9.]/.test(src[j])) j++;
        if (src[j] === "e" || src[j] === "E") {
          j++; if (src[j] === "+" || src[j] === "-") j++;
          while (j < src.length && /[0-9]/.test(src[j])) j++;
        }
        const numStr = src.slice(i, j);
        const n = parseFloat(numStr);
        if (isNaN(n)) throw new Error("Invalid numeric literal near: " + src.slice(i, i + 8));
        tokens.push({ t: "num", v: n }); i = j; continue;
      }
      if (/[A-Za-z_]/.test(c)) {
        let j = i; while (j < src.length && /[A-Za-z0-9_]/.test(src[j])) j++;
        tokens.push({ t: "ident", v: src.slice(i, j) }); i = j; continue;
      }
      if ("<>=!".includes(c)) {
        if (src[i + 1] === "=") { tokens.push({ t: "op", v: c + "=" }); i += 2; }
        else { tokens.push({ t: "op", v: c }); i++; }
        continue;
      }
      if ("+-*/^".includes(c)) { tokens.push({ t: "op", v: c }); i++; continue; }
      throw new Error("Unexpected character in formula: '" + c + "'");
    }
    return tokens;
  }

  function parse(src) {
    const tokens = tokenize(src);
    let pos = 0;
    const peek = () => tokens[pos];
    const eat = () => tokens[pos++];

    function parseOr() {
      let l = parseAnd();
      while (peek() && peek().t === "ident" && peek().v === "or") { eat(); l = { type: "binop", op: "||", left: l, right: parseAnd() }; }
      return l;
    }
    function parseAnd() {
      let l = parseCompare();
      while (peek() && peek().t === "ident" && peek().v === "and") { eat(); l = { type: "binop", op: "&&", left: l, right: parseCompare() }; }
      return l;
    }
    function parseCompare() {
      let l = parseAdd();
      if (peek() && peek().t === "op" && ["<", "<=", ">", ">=", "==", "!="].includes(peek().v)) {
        const op = eat().v; return { type: "binop", op, left: l, right: parseAdd() };
      }
      return l;
    }
    function parseAdd() {
      let l = parseMul();
      while (peek() && peek().t === "op" && (peek().v === "+" || peek().v === "-")) {
        const op = eat().v; l = { type: "binop", op, left: l, right: parseMul() };
      }
      return l;
    }
    function parseMul() {
      let l = parseUnary();
      while (peek() && peek().t === "op" && (peek().v === "*" || peek().v === "/")) {
        const op = eat().v; l = { type: "binop", op, left: l, right: parseUnary() };
      }
      return l;
    }
    function parseUnary() {
      if (peek() && peek().t === "op" && peek().v === "-") { eat(); return { type: "unop", op: "-", expr: parseUnary() }; }
      if (peek() && peek().t === "op" && peek().v === "!") { eat(); return { type: "unop", op: "!", expr: parseUnary() }; }
      return parsePow();
    }
    function parsePow() {
      let l = parseAtom();
      if (peek() && peek().t === "op" && peek().v === "^") { eat(); return { type: "binop", op: "^", left: l, right: parseUnary() }; }
      return l;
    }
    function parseAtom() {
      const tok = peek();
      if (!tok) throw new Error("Unexpected end of expression");
      if (tok.t === "num") { eat(); return { type: "num", value: tok.v }; }
      if (tok.t === "(") { eat(); const e = parseOr(); expect(")"); return e; }
      if (tok.t === "ident") {
        if (tok.v === "if" && tokens[pos + 1] && tokens[pos + 1].t === "(") {
          eat(); eat();
          const c = parseOr(); expect(",");
          const th = parseOr(); expect(",");
          const el = parseOr(); expect(")");
          return { type: "if", cond: c, then: th, else: el };
        }
        eat();
        if (peek() && peek().t === "(") {
          eat();
          const args = [];
          if (!(peek() && peek().t === ")")) {
            args.push(parseOr());
            while (peek() && peek().t === ",") { eat(); args.push(parseOr()); }
          }
          expect(")");
          return { type: "call", name: tok.v, args };
        }
        return { type: "var", name: tok.v };
      }
      throw new Error("Expected a value near token " + JSON.stringify(tok));
    }
    function expect(t) {
      if (!peek() || peek().t !== t) throw new Error("Expected '" + t + "'");
      eat();
    }

    const ast = parseOr();
    if (pos !== tokens.length) throw new Error("Unexpected trailing tokens after expression");
    return ast;
  }

  function evaluate(ast, env) {
    switch (ast.type) {
      case "num": return ast.value;
      case "var":
        if (!(ast.name in env)) throw new Error("Undefined variable: " + ast.name);
        return env[ast.name];
      case "unop": {
        const v = evaluate(ast.expr, env);
        return ast.op === "-" ? -v : (v === 0 ? 1 : 0);
      }
      case "binop": {
        const l = evaluate(ast.left, env), r = evaluate(ast.right, env);
        switch (ast.op) {
          case "+": return l + r; case "-": return l - r;
          case "*": return l * r; case "/": if (r === 0) throw new Error("Division by zero"); return l / r;
          case "^": return Math.pow(l, r);
          case "<": return l < r ? 1 : 0; case "<=": return l <= r ? 1 : 0;
          case ">": return l > r ? 1 : 0; case ">=": return l >= r ? 1 : 0;
          case "==": return l === r ? 1 : 0; case "!=": return l !== r ? 1 : 0;
          case "&&": return (l !== 0 && r !== 0) ? 1 : 0; case "||": return (l !== 0 || r !== 0) ? 1 : 0;
          default: throw new Error("Unknown operator: " + ast.op);
        }
      }
      case "call": {
        const args = ast.args.map(a => evaluate(a, env));
        switch (ast.name) {
          case "sin": return Math.sin(args[0]); case "cos": return Math.cos(args[0]);
          case "tan": return Math.tan(args[0]); case "exp": return Math.exp(args[0]);
          case "log": return Math.log(args[0]); case "sqrt": return Math.sqrt(args[0]);
          case "abs": return Math.abs(args[0]); case "min": return Math.min(args[0], args[1]);
          case "max": return Math.max(args[0], args[1]); case "floor": return Math.floor(args[0]);
          case "ceil": return Math.ceil(args[0]);
          default: throw new Error("Unknown function or wrong arity: " + ast.name);
        }
      }
      case "if": return evaluate(ast.cond, env) !== 0 ? evaluate(ast.then, env) : evaluate(ast.else, env);
      default: throw new Error("Unknown AST node: " + ast.type);
    }
  }

  function dependencies(ast, acc) {
    acc = acc || new Set();
    switch (ast.type) {
      case "var": acc.add(ast.name); break;
      case "unop": dependencies(ast.expr, acc); break;
      case "binop": dependencies(ast.left, acc); dependencies(ast.right, acc); break;
      case "call": ast.args.forEach(a => dependencies(a, acc)); break;
      case "if": dependencies(ast.cond, acc); dependencies(ast.then, acc); dependencies(ast.else, acc); break;
    }
    return acc;
  }

  return { parse, evaluate, dependencies };
})();

// ---------------------------------------------------------------
// Units: lightweight dimensional-analysis mirror of Oracle.Units
// ---------------------------------------------------------------
const Units = (() => {
  const TABLE = {
    "1": { dim: {}, scale: 1 }, "rad": { dim: {}, scale: 1 },
    "m": { dim: { L: 1 }, scale: 1 }, "km": { dim: { L: 1 }, scale: 1000 },
    "cm": { dim: { L: 1 }, scale: 0.01 }, "mm": { dim: { L: 1 }, scale: 0.001 },
    "s": { dim: { T: 1 }, scale: 1 }, "ms": { dim: { T: 1 }, scale: 0.001 },
    "min": { dim: { T: 1 }, scale: 60 }, "h": { dim: { T: 1 }, scale: 3600 },
    "kg": { dim: { M: 1 }, scale: 1 }, "g": { dim: { M: 1 }, scale: 0.001 },
    "A": { dim: { I: 1 }, scale: 1 }, "K": { dim: { K: 1 }, scale: 1 },
    "mol": { dim: { N: 1 }, scale: 1 }, "cd": { dim: { J: 1 }, scale: 1 },
    "N": { dim: { M: 1, L: 1, T: -2 }, scale: 1 },
    "Pa": { dim: { M: 1, L: -1, T: -2 }, scale: 1 },
    "J": { dim: { M: 1, L: 2, T: -2 }, scale: 1 },
    "W": { dim: { M: 1, L: 2, T: -3 }, scale: 1 },
    "Hz": { dim: { T: -1 }, scale: 1 },
  };

  function mulDim(a, b, sign) {
    const out = Object.assign({}, a);
    for (const k in b) out[k] = (out[k] || 0) + sign * b[k];
    Object.keys(out).forEach(k => { if (out[k] === 0) delete out[k]; });
    return out;
  }

  function parseUnit(str) {
    const parts = str.replace(/\s+/g, "").split(/([*/])/);
    let dim = {}, scale = 1, op = "*";
    for (const part of parts) {
      if (part === "*" || part === "/") { op = part; continue; }
      if (part === "") continue;
      const m = part.match(/^([A-Za-z]+)(\^(-?\d+))?$/);
      if (!m) throw new Error("Invalid unit atom: " + part);
      const sym = m[1], exp = m[3] ? parseInt(m[3], 10) : 1;
      const info = TABLE[sym];
      if (!info) throw new Error("Unknown base unit: " + sym);
      const atomDim = {}; for (const k in info.dim) atomDim[k] = info.dim[k] * exp;
      const atomScale = Math.pow(info.scale, exp);
      if (op === "*") { dim = mulDim(dim, atomDim, 1); scale *= atomScale; }
      else { dim = mulDim(dim, atomDim, -1); scale /= atomScale; }
    }
    return { dim, scale };
  }

  function dimEq(a, b) {
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) if ((a[k] || 0) !== (b[k] || 0)) return false;
    return true;
  }

  function showDim(d) {
    const parts = Object.entries(d).filter(([, v]) => v !== 0).map(([k, v]) => `${k}^${v}`);
    return parts.length ? parts.join(" ") : "dimensionless";
  }

  function inferDim(ast, env) {
    switch (ast.type) {
      case "num": return {};
      case "var": return env[ast.name] || {};
      case "unop": return inferDim(ast.expr, env);
      case "binop": {
        const da = inferDim(ast.left, env), db = inferDim(ast.right, env);
        if (ast.op === "+" || ast.op === "-") {
          if (!dimEq(da, db)) throw new Error(`incompatible units in '${ast.op}': ${showDim(da)} vs ${showDim(db)}`);
          return da;
        }
        if (ast.op === "*") return mulDim(da, db, 1);
        if (ast.op === "/") return mulDim(da, db, -1);
        if (ast.op === "^") {
          if (ast.right.type === "num" && Number.isInteger(ast.right.value)) {
            const out = {}; for (const k in da) out[k] = da[k] * ast.right.value; return out;
          }
          if (Object.keys(da).length === 0) return {};
          throw new Error("non-integer or variable exponent on a dimensional base");
        }
        return {};
      }
      case "call": {
        const dims = ast.args.map(a => inferDim(a, env));
        if (["sin", "cos", "tan", "exp", "log"].includes(ast.name)) {
          if (dims.some(d => Object.keys(d).length > 0)) throw new Error(ast.name + "() requires a dimensionless argument");
          return {};
        }
        return dims[0] || {};
      }
      case "if": {
        const dt = inferDim(ast.then, env), de = inferDim(ast.else, env);
        if (!dimEq(dt, de)) throw new Error("if-branches have incompatible units");
        return dt;
      }
      default: return {};
    }
  }

  return { parseUnit, dimEq, showDim, inferDim, TABLE };
})();

// ---------------------------------------------------------------
// Solver: fixed-step RK4 / Euler integrator for the Formula AST system
// ---------------------------------------------------------------
const Solver = (() => {
  function integrate(equations, constants, params, y0, t0, t1, method, step, maxSteps) {
    const keys = Object.keys(y0);
    let t = t0, y = Object.assign({}, y0);
    const times = [t0], states = [Object.assign({}, y)];
    let flag = "STABLE", steps = 0;

    function rhs(tt, state) {
      const env = Object.assign({}, constants, state, params, { t: tt });
      const out = {};
      for (const k in equations) out[k] = Formula.evaluate(equations[k], env);
      return out;
    }
    function addState(a, b, scale) {
      const out = {}; for (const k of keys) out[k] = a[k] + scale * (b[k] || 0); return out;
    }
    function badState(s) { return keys.some(k => !isFinite(s[k])); }

    while (t < t1 && steps < maxSteps) {
      const h = Math.min(step, t1 - t);
      let yNew;
      if (method === "euler") {
        yNew = addState(y, rhs(t, y), h);
      } else {
        const k1 = rhs(t, y);
        const k2 = rhs(t + h / 2, addState(y, k1, h / 2));
        const k3 = rhs(t + h / 2, addState(y, k2, h / 2));
        const k4 = rhs(t + h, addState(y, k3, h));
        yNew = {};
        for (const k of keys) yNew[k] = y[k] + (h / 6) * (k1[k] + 2 * k2[k] + 2 * k3[k] + k4[k]);
      }
      if (badState(yNew)) { flag = "NAN_OR_INF"; break; }
      const norm = Math.sqrt(keys.reduce((s, k) => s + yNew[k] * yNew[k], 0));
      y = yNew; t += h; steps++;
      times.push(t); states.push(Object.assign({}, y));
      if (norm > 1e12) { flag = "DIVERGENT"; break; }
    }
    if (steps >= maxSteps && flag === "STABLE") flag = "MAX_STEPS_EXCEEDED";
    return { times, states, flag, steps };
  }
  return { integrate };
})();

// ---------------------------------------------------------------
// Stats: sampling + descriptive statistics (Box-Muller normal, etc.)
// ---------------------------------------------------------------
const Stats = (() => {
  function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function sampleUniform(rng, lo, hi) { return lo + (hi - lo) * rng(); }
  function sampleNormal(rng, mean, std) {
    const u1 = Math.max(rng(), 1e-12), u2 = rng();
    const z0 = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
    return mean + std * z0;
  }
  function sampleLogNormal(rng, mu, sigma) { return Math.exp(sampleNormal(rng, mu, sigma)); }

  function mean(xs) { return xs.reduce((a, b) => a + b, 0) / xs.length; }
  function variance(xs) { const m = mean(xs); return xs.reduce((a, b) => a + (b - m) * (b - m), 0) / Math.max(xs.length - 1, 1); }
  function percentile(xs, p) {
    const s = [...xs].sort((a, b) => a - b); const n = s.length;
    if (n === 1) return s[0];
    const rank = (p / 100) * (n - 1);
    const lo = Math.floor(rank), hi = Math.ceil(rank), frac = rank - lo;
    return s[lo] + frac * (s[hi] - s[lo]);
  }
  function descriptiveStats(xs) {
    const m = mean(xs), v = variance(xs);
    return {
      n: xs.length, mean: m, variance: v, std: Math.sqrt(v),
      min: Math.min(...xs), max: Math.max(...xs), median: percentile(xs, 50),
      p05: percentile(xs, 5), p95: percentile(xs, 95),
    };
  }
  return { mulberry32, sampleUniform, sampleNormal, sampleLogNormal, mean, variance, percentile, descriptiveStats };
})();

// ---------------------------------------------------------------
// Sweep: grid search + Latin Hypercube Sampling
// ---------------------------------------------------------------
const SweepGen = (() => {
  function gridSearch(ranges) {
    const names = Object.keys(ranges);
    const axes = names.map(nm => {
      const [lo, hi, n] = ranges[nm];
      if (n <= 1) return [lo];
      const pts = []; for (let i = 0; i < n; i++) pts.push(lo + (hi - lo) * (i / (n - 1)));
      return pts;
    });
    let combos = [{}];
    names.forEach((nm, idx) => {
      const next = [];
      for (const c of combos) for (const v of axes[idx]) next.push(Object.assign({}, c, { [nm]: v }));
      combos = next;
    });
    return combos;
  }

  function latinHypercube(bounds, nSamples, rng) {
    const names = Object.keys(bounds);
    const result = Array.from({ length: nSamples }, () => ({}));
    for (const nm of names) {
      const [lo, hi] = bounds[nm];
      const perm = Array.from({ length: nSamples }, (_, i) => i);
      for (let i = perm.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [perm[i], perm[j]] = [perm[j], perm[i]]; }
      for (let i = 0; i < nSamples; i++) {
        const u = rng();
        result[i][nm] = lo + (hi - lo) * ((perm[i] + u) / nSamples);
      }
    }
    return result;
  }

  return { gridSearch, latinHypercube };
})();

// ---------------------------------------------------------------
// Sensitivity: one-at-a-time local method
// ---------------------------------------------------------------
const SensitivityGen = (() => {
  function oneAtATime(baseParams, runFn, relDelta) {
    relDelta = relDelta || 0.1;
    const baseline = runFn(baseParams);
    const results = {};
    for (const name in baseParams) {
      const value = baseParams[name];
      const up = Object.assign({}, baseParams, { [name]: value * (1 + relDelta) });
      const down = Object.assign({}, baseParams, { [name]: value * (1 - relDelta) });
      const outUp = runFn(up), outDown = runFn(down);
      results[name] = {
        baseline, outputPlus: outUp, outputMinus: outDown,
        effectPlus: outUp - baseline, effectMinus: outDown - baseline,
        range: Math.abs((outUp - baseline) - (outDown - baseline)),
      };
    }
    return results;
  }
  return { oneAtATime };
})();
