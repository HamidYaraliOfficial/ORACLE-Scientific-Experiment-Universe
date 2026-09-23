"""
    Sweep

ORACLE's Parameter Sweep Engine: turns a set of parameter ranges into
a list of concrete configurations, each of which becomes one
independent Experiment Run. Three sampling strategies are implemented
for real: full-factorial grid search, uniform random search, and
Latin Hypercube Sampling (LHS), which stratifies each dimension so
that samples spread evenly across the whole space rather than
clumping, as plain random search tends to do.
"""
module Sweep

using Random

export grid_search, random_search, latin_hypercube

"""
    grid_search(ranges) -> Vector{Dict{String,Float64}}

`ranges` maps a parameter name to `(lo, hi, n)`: sample `n` evenly
spaced points (inclusive) between `lo` and `hi`. Returns the full
Cartesian product as a vector of parameter dictionaries — this is a
genuine combinatorial expansion, so callers should be mindful of the
`n1 * n2 * ... * nk` size before requesting an enormous grid.
"""
function grid_search(ranges::Dict{String,Tuple{Float64,Float64,Int}})
    names = collect(keys(ranges))
    axes = [range(ranges[nm][1], ranges[nm][2], length=ranges[nm][3]) for nm in names]
    combos = Dict{String,Float64}[]
    _grid_recurse!(combos, names, axes, Dict{String,Float64}(), 1)
    return combos
end

function _grid_recurse!(out, names, axes, current, idx)
    if idx > length(names)
        push!(out, copy(current))
        return
    end
    for v in axes[idx]
        current[names[idx]] = v
        _grid_recurse!(out, names, axes, current, idx + 1)
    end
end

"""Uniform random search: `n_samples` independent draws, one per
parameter, uniformly within its declared `(lo, hi)` bounds."""
function random_search(bounds::Dict{String,Tuple{Float64,Float64}}, n_samples::Int, rng::AbstractRNG)
    names = collect(keys(bounds))
    return [Dict(nm => bounds[nm][1] + rand(rng) * (bounds[nm][2] - bounds[nm][1]) for nm in names)
            for _ in 1:n_samples]
end

"""
    latin_hypercube(bounds, n_samples, rng)

Classic Latin Hypercube Sampling: each parameter's range is divided
into `n_samples` equal-probability strata; one sample is drawn from
each stratum, and the per-parameter stratum orderings are
independently shuffled so the resulting design is space-filling
without the combinatorial blow-up of a full grid.
"""
function latin_hypercube(bounds::Dict{String,Tuple{Float64,Float64}}, n_samples::Int, rng::AbstractRNG)
    names = collect(keys(bounds))
    k = length(names)
    result = [Dict{String,Float64}() for _ in 1:n_samples]
    for nm in names
        lo, hi = bounds[nm]
        perm = randperm(rng, n_samples)
        for i in 1:n_samples
            stratum = perm[i]
            u = rand(rng)
            val = lo + (hi - lo) * ((stratum - 1 + u) / n_samples)
            result[i][nm] = val
        end
    end
    return result
end

end # module
