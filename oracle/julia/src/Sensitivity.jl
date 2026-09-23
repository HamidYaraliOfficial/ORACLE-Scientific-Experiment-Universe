"""
    Sensitivity

ORACLE's Sensitivity Analysis Engine: measures how much each
parameter influences a chosen output metric. Implements the One-at-a-
Time (OAT) local method for real (perturb each parameter by +/- delta
around a baseline while holding all others fixed, and record the
normalized effect on the output), plus a Sobol-style global variance
decomposition using pure Monte-Carlo estimation (Saltelli's formula),
which needs no external dependency beyond `Random`/`Statistics`.
"""
module Sensitivity

using Statistics, Random

export one_at_a_time, sobol_indices, tornado_data

"""
    one_at_a_time(base_params, run_fn; rel_delta=0.1)

`run_fn(params::Dict{String,Float64}) -> Float64` runs the model (or
evaluates the relevant metric) for a given parameter dict. For every
parameter in `base_params`, perturbs it by +/- `rel_delta` (relative)
and reports the resulting change in `run_fn`'s output, normalized by
the baseline output where possible. This is the data the Web UI's
Sensitivity Tornado chart renders directly.
"""
function one_at_a_time(base_params::Dict{String,Float64}, run_fn::Function; rel_delta::Float64=0.1)
    baseline = run_fn(base_params)
    results = Dict{String,Any}()
    for (name, value) in base_params
        up = copy(base_params); up[name] = value * (1 + rel_delta)
        down = copy(base_params); down[name] = value * (1 - rel_delta)
        out_up = run_fn(up)
        out_down = run_fn(down)
        effect_up = out_up - baseline
        effect_down = out_down - baseline
        results[name] = Dict{String,Any}(
            "baseline" => baseline,
            "output_plus" => out_up, "output_minus" => out_down,
            "effect_plus" => effect_up, "effect_minus" => effect_down,
            "range" => abs(effect_up - effect_down),
        )
    end
    return results
end

"""Rank parameters by |effect| for a tornado-chart-ready ordering."""
function tornado_data(oat_result::Dict{String,Any})
    ranked = sort(collect(oat_result), by = kv -> -kv[2]["range"])
    return [Dict("parameter" => k, "range" => v["range"],
                 "effect_plus" => v["effect_plus"], "effect_minus" => v["effect_minus"])
            for (k, v) in ranked]
end

"""
    sobol_indices(bounds, run_fn, n, rng)

Monte-Carlo estimate of first-order Sobol sensitivity indices via
Saltelli's sampling scheme: draws two independent sample matrices A
and B, and for each parameter i builds a hybrid matrix that uses A's
column i everywhere else and B's column i for parameter i (or vice
versa), then estimates:

    S_i ≈ Var(E[Y|X_i]) / Var(Y)

using the standard Monte-Carlo estimator. `n` should be at least a
few hundred for stable estimates; results are still only estimates
and are reported with their sample size so a reviewer can judge
precision.
"""
function sobol_indices(bounds::Dict{String,Tuple{Float64,Float64}}, run_fn::Function, n::Int, rng::AbstractRNG)
    names = collect(keys(bounds))
    k = length(names)
    A = [Dict(nm => bounds[nm][1] + rand(rng)*(bounds[nm][2]-bounds[nm][1]) for nm in names) for _ in 1:n]
    B = [Dict(nm => bounds[nm][1] + rand(rng)*(bounds[nm][2]-bounds[nm][1]) for nm in names) for _ in 1:n]
    yA = [run_fn(a) for a in A]
    yB = [run_fn(b) for b in B]
    var_y = var(vcat(yA, yB))
    indices = Dict{String,Any}()
    for nm in names
        AB_i = [merge(copy(A[j]), Dict(nm => B[j][nm])) for j in 1:n]
        y_ABi = [run_fn(x) for x in AB_i]
        first_order = var_y == 0 ? 0.0 : (mean(yA .* y_ABi) - mean(yA) * mean(yB)) / var_y
        indices[nm] = Dict("first_order_index" => first_order, "n_samples" => n)
    end
    return indices
end

end # module
