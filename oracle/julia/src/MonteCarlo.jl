"""
    MonteCarloEngine

ORACLE's Monte Carlo Engine: runs a model thousands of times over
sampled parameters and reports the full distribution of outcomes, not
just a point estimate. Every sample gets its own reproducible derived
seed (see `Reproducibility.derive_seed`) so a single sample can be
re-run in isolation and reproduce exactly, and the whole run's master
seed is recorded alongside the results.
"""
module MonteCarloEngine

using Random
using ..StatsEngine
using ..Reproducibility

export run_monte_carlo, ParameterDistSpec

"""A sampleable parameter: one of uniform / normal / lognormal /
categorical / constant, matching the distributions the Haskell layer
already validated in the Experiment Definition."""
struct ParameterDistSpec
    name::String
    kind::String   # "uniform" | "normal" | "lognormal" | "categorical" | "constant"
    a::Float64     # low / mean / mu / (unused for categorical)
    b::Float64     # high / std / sigma / (unused for categorical)
    categories::Vector{String}
end

function draw(spec::ParameterDistSpec, rng::AbstractRNG)
    if spec.kind == "uniform"
        return sample_uniform(rng, spec.a, spec.b)
    elseif spec.kind == "normal"
        return sample_normal(rng, spec.a, spec.b)
    elseif spec.kind == "lognormal"
        return sample_lognormal(rng, spec.a, spec.b)
    elseif spec.kind == "constant"
        return spec.a
    else
        error("Categorical sampling returns a string, use draw_categorical instead")
    end
end

"""
    run_monte_carlo(specs, evaluate, n_samples, master_seed; constraint_check=nothing)

`evaluate(params::Dict{String,Float64}) -> Dict{String,Float64}`
computes whatever metrics the experiment cares about for one sampled
parameter set. `constraint_check(params, outputs) -> Bool` (optional)
reports whether a sample satisfies the experiment's declared
constraints, so ORACLE can report the empirical probability of
constraint violation — a first-class Monte Carlo Engine requirement,
not an afterthought.

Returns a Dict with, for every output metric: mean / variance /
percentiles / a 95% confidence interval on the mean, plus the overall
probability of constraint violation and full reproducibility metadata.
"""
function run_monte_carlo(specs::Vector{ParameterDistSpec}, evaluate::Function,
                          n_samples::Int, master_seed::Integer;
                          constraint_check::Union{Nothing,Function}=nothing,
                          config_hash_str::String="")
    n_samples > 0 || error("n_samples must be positive")
    samples_params = Vector{Dict{String,Float64}}(undef, n_samples)
    samples_outputs = Vector{Dict{String,Float64}}(undef, n_samples)
    violations = falses(n_samples)

    for i in 1:n_samples
        seed_i = derive_seed(master_seed, i)
        rng = Xoshiro(seed_i)
        params = Dict{String,Float64}()
        for spec in specs
            params[spec.name] = draw(spec, rng)
        end
        outputs = evaluate(params)
        samples_params[i] = params
        samples_outputs[i] = outputs
        if constraint_check !== nothing
            violations[i] = !constraint_check(params, outputs)
        end
    end

    metric_names = isempty(samples_outputs) ? String[] : collect(keys(samples_outputs[1]))
    metric_summary = Dict{String,Any}()
    for m in metric_names
        vals = [o[m] for o in samples_outputs]
        stats = descriptive_stats(vals)
        ci = confidence_interval_mean(vals)
        stats["confidence_interval_95"] = [ci[1], ci[2]]
        metric_summary[m] = stats
    end

    return Dict{String,Any}(
        "nSamples" => n_samples,
        "masterSeed" => master_seed,
        "metrics" => metric_summary,
        "probabilityOfConstraintViolation" => constraint_check === nothing ? nothing : (count(violations) / n_samples),
        "reproducibility" => run_metadata(master_seed, 0, config_hash_str),
    )
end

end # module
