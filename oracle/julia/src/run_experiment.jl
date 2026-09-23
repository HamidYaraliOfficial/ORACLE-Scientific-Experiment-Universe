#!/usr/bin/env julia
#
# ORACLE Julia CLI — the Simulation Engine's command-line entry point.
#
#   julia run_experiment.jl <mode> <validated_experiment.json> [output_dir] [n_samples]
#
# <mode> is one of: simulate | montecarlo | sweep | sensitivity
#
# `validated_experiment.json` must already have passed the Haskell
# `oracle-validate` tool (see ../../haskell). This script does not
# re-validate structural or dimensional correctness — that is the
# Haskell layer's job — it only performs the numerical work.

include(joinpath(@__DIR__, "Oracle.jl"))
using .Oracle
using .Oracle.JsonMini
using .Oracle.FormulaEval
using .Oracle.Solvers
using .Oracle.Sweep
using .Oracle.Sensitivity
using .Oracle.MonteCarloEngine
using .Oracle.ResultStore
using .Oracle.Reproducibility
using Random

function load_experiment(path::AbstractString)
    text = read(path, String)
    return JsonMini.parse_json(text)
end

"""Build the static environment (constants) and the equation ASTs
(state-variable name => AST node) from a parsed experiment dict."""
function build_model(exp_dict::Dict{String,Any})
    constants = Dict{String,Float64}()
    for c in get(exp_dict, "constants", Any[])
        constants[c["name"]] = Float64(c["value"])
    end
    equations = Dict{String,Any}()
    for eq in get(exp_dict, "equations", Any[])
        equations[eq["output"]] = eq["expr"]
    end
    return constants, equations
end

function make_rhs(equations::Dict{String,Any}, constants::Dict{String,Float64}, params::Dict{String,Float64})
    return (t, state, p) -> begin
        env = Dict{String,Float64}()
        merge!(env, constants)
        merge!(env, state)
        merge!(env, p)
        env["t"] = t
        out = Dict{String,Float64}()
        for (varname, ast) in equations
            out[varname] = FormulaEval.eval_ast(ast, env)
        end
        out
    end
end

function initial_state(exp_dict::Dict{String,Any})
    ic = get(exp_dict, "initialConditions", Dict{String,Any}())
    return Dict{String,Float64}(k => Float64(v) for (k, v) in ic)
end

function solver_config(exp_dict::Dict{String,Any})
    s = exp_dict["solver"]
    method = Symbol(s["method"])
    step = Float64(s["stepSize"])
    tol = Float64(s["tolerance"])
    maxSteps = Int(round(s["maxSteps"]))
    return method, step, tol, maxSteps
end

function time_range(exp_dict::Dict{String,Any})
    tr = exp_dict["timeRange"]
    return Float64(tr[1]), Float64(tr[2])
end

function run_single_simulation(exp_dict::Dict{String,Any}, params::Dict{String,Float64})
    constants, equations = build_model(exp_dict)
    y0 = initial_state(exp_dict)
    method, step, tol, maxSteps = solver_config(exp_dict)
    t0, t1 = time_range(exp_dict)
    rhs = make_rhs(equations, constants, params)
    result = Solvers.integrate(rhs, y0, t0, t1, params, method, step, tol, maxSteps)
    return result
end

function metrics_from_result(result::Solvers.StepResult, exp_dict::Dict{String,Any})
    metrics = Dict{String,Float64}()
    if isempty(result.states)
        return metrics
    end
    final = result.states[end]
    for (k, v) in final
        metrics["final_" * k] = v
    end
    for k in keys(final)
        series = [s[k] for s in result.states]
        metrics["mean_" * k] = sum(series) / length(series)
        metrics["max_" * k] = maximum(series)
        metrics["min_" * k] = minimum(series)
    end
    return metrics
end

function cmd_simulate(exp_dict::Dict{String,Any}, output_dir::AbstractString)
    params = default_params(exp_dict)
    result = run_single_simulation(exp_dict, params)
    metrics = metrics_from_result(result, exp_dict)
    payload = Dict{String,Any}(
        "times" => result.times,
        "states" => result.states,
        "stabilityFlag" => string(result.flag),
        "stepsTaken" => result.steps_taken,
        "metrics" => metrics,
    )
    cfg_hash = Reproducibility.config_hash(JsonMini.to_json(exp_dict))
    run_id = exp_dict["name"] * "_simulate_" * cfg_hash[1:min(8,length(cfg_hash))]
    path = ResultStore.write_quality_flagged(output_dir, run_id, exp_dict["name"], payload,
                                              string(result.flag); config_hash=cfg_hash,
                                              solver_method=exp_dict["solver"]["method"])
    println("Wrote simulation result to: ", path)
end

function default_params(exp_dict::Dict{String,Any})
    params = Dict{String,Float64}()
    for p in get(exp_dict, "parameters", Any[])
        if haskey(p, "default") && p["default"] !== nothing
            params[p["name"]] = Float64(p["default"])
        end
    end
    return params
end

function cmd_montecarlo(exp_dict::Dict{String,Any}, output_dir::AbstractString, n_samples::Int)
    specs = MonteCarloEngine.ParameterDistSpec[]
    for p in get(exp_dict, "parameters", Any[])
        dist = get(p, "distribution", nothing)
        if dist === nothing
            default = get(p, "default", 0.0)
            push!(specs, MonteCarloEngine.ParameterDistSpec(p["name"], "constant", Float64(default), 0.0, String[]))
        else
            t = dist["type"]
            if t == "uniform"
                push!(specs, MonteCarloEngine.ParameterDistSpec(p["name"], "uniform", Float64(dist["low"]), Float64(dist["high"]), String[]))
            elseif t == "normal"
                push!(specs, MonteCarloEngine.ParameterDistSpec(p["name"], "normal", Float64(dist["mean"]), Float64(dist["std"]), String[]))
            elseif t == "lognormal"
                push!(specs, MonteCarloEngine.ParameterDistSpec(p["name"], "lognormal", Float64(dist["mu"]), Float64(dist["sigma"]), String[]))
            elseif t == "constant"
                push!(specs, MonteCarloEngine.ParameterDistSpec(p["name"], "constant", Float64(dist["value"]), 0.0, String[]))
            else
                error("Monte Carlo sampling does not support distribution type: $t")
            end
        end
    end

    evaluate = params -> begin
        result = run_single_simulation(exp_dict, params)
        metrics_from_result(result, exp_dict)
    end

    master_seed = Int(get(exp_dict, "seed", 0))
    cfg_hash = Reproducibility.config_hash(JsonMini.to_json(exp_dict))
    mc_result = MonteCarloEngine.run_monte_carlo(specs, evaluate, n_samples, master_seed;
                                                  config_hash_str=cfg_hash)
    run_id = exp_dict["name"] * "_montecarlo_" * cfg_hash[1:min(8,length(cfg_hash))]
    path = ResultStore.write_result(output_dir, run_id, exp_dict["name"], mc_result;
                                     config_hash=cfg_hash, solver_method=exp_dict["solver"]["method"])
    println("Wrote Monte Carlo result (", n_samples, " samples) to: ", path)
end

function cmd_sweep(exp_dict::Dict{String,Any}, output_dir::AbstractString, resolution::Int)
    bounds = Dict{String,Tuple{Float64,Float64,Int}}()
    for p in get(exp_dict, "parameters", Any[])
        if haskey(p, "min") && p["min"] !== nothing && haskey(p, "max") && p["max"] !== nothing
            bounds[p["name"]] = (Float64(p["min"]), Float64(p["max"]), resolution)
        end
    end
    isempty(bounds) && error("sweep mode requires at least one parameter with 'min' and 'max' set")
    combos = Sweep.grid_search(bounds)
    println("Sweep generated ", length(combos), " configurations.")
    summaries = Vector{Dict{String,Any}}()
    for (i, combo) in enumerate(combos)
        result = run_single_simulation(exp_dict, combo)
        metrics = metrics_from_result(result, exp_dict)
        push!(summaries, Dict{String,Any}("index" => i, "params" => combo, "metrics" => metrics,
                                           "stabilityFlag" => string(result.flag)))
    end
    cfg_hash = Reproducibility.config_hash(JsonMini.to_json(exp_dict))
    run_id = exp_dict["name"] * "_sweep_" * cfg_hash[1:min(8,length(cfg_hash))]
    path = ResultStore.write_result(output_dir, run_id, exp_dict["name"],
                                     Dict{String,Any}("runs" => summaries, "count" => length(summaries));
                                     config_hash=cfg_hash, solver_method=exp_dict["solver"]["method"])
    println("Wrote sweep result to: ", path)
end

function cmd_sensitivity(exp_dict::Dict{String,Any}, output_dir::AbstractString)
    base = default_params(exp_dict)
    isempty(base) && error("sensitivity mode requires parameters with default values")
    run_fn = params -> begin
        result = run_single_simulation(exp_dict, params)
        m = metrics_from_result(result, exp_dict)
        isempty(m) ? 0.0 : first(values(m))
    end
    oat = Sensitivity.one_at_a_time(base, run_fn)
    tornado = Sensitivity.tornado_data(oat)
    cfg_hash = Reproducibility.config_hash(JsonMini.to_json(exp_dict))
    run_id = exp_dict["name"] * "_sensitivity_" * cfg_hash[1:min(8,length(cfg_hash))]
    path = ResultStore.write_result(output_dir, run_id, exp_dict["name"],
                                     Dict{String,Any}("oneAtATime" => oat, "tornado" => tornado);
                                     config_hash=cfg_hash, solver_method=exp_dict["solver"]["method"])
    println("Wrote sensitivity analysis to: ", path)
end

function main()
    if length(ARGS) < 2
        println(stderr, "Usage: julia run_experiment.jl <simulate|montecarlo|sweep|sensitivity> <validated_experiment.json> [output_dir] [n_samples_or_resolution]")
        exit(1)
    end
    mode = ARGS[1]
    exp_path = ARGS[2]
    output_dir = length(ARGS) >= 3 ? ARGS[3] : "results"
    exp_dict = load_experiment(exp_path)

    if mode == "simulate"
        cmd_simulate(exp_dict, output_dir)
    elseif mode == "montecarlo"
        n = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 1000
        cmd_montecarlo(exp_dict, output_dir, n)
    elseif mode == "sweep"
        res = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 5
        cmd_sweep(exp_dict, output_dir, res)
    elseif mode == "sensitivity"
        cmd_sensitivity(exp_dict, output_dir)
    else
        println(stderr, "Unknown mode: $mode")
        exit(1)
    end
end

main()
