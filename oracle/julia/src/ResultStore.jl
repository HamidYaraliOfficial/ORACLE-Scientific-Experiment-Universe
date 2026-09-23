"""
    ResultStore

ORACLE's Result Store (Julia side): writes every run's result as a
self-describing JSON artifact, tagged with the provenance metadata the
Data Provenance Engine requires — which experiment, which
configuration hash, which solver, which seed produced it — so that any
result file found later on disk can be traced back to exactly how it
was generated without consulting anything else.
"""
module ResultStore

using Dates
using ..JsonMini

export write_result, write_quality_flagged

"""Write a result dict to `<output_dir>/<run_id>.json`, merging in a
standard provenance envelope. Returns the path written."""
function write_result(output_dir::AbstractString, run_id::AbstractString,
                       experiment_name::AbstractString, result::Dict{String,Any};
                       config_hash::AbstractString="", solver_method::AbstractString="",
                       status::AbstractString="valid")
    mkpath(output_dir)
    envelope = Dict{String,Any}(
        "runId" => run_id,
        "experimentName" => experiment_name,
        "status" => status, # "valid" | "warning" | "incomplete" | "numerically_unstable" | "constraint_violated" | "failed"
        "configurationHash" => config_hash,
        "solverMethod" => solver_method,
        "writtenAt" => string(now()),
        "result" => result,
    )
    path = joinpath(output_dir, run_id * ".json")
    open(path, "w") do io
        write(io, JsonMini.to_json_pretty(envelope))
    end
    return path
end

"""Convenience wrapper for the Result Quality Engine's rule: a result
must never be written as silently "valid" if the solver reported an
instability. Call this instead of `write_result` whenever a
`Solvers.StabilityFlag` other than `STABLE` was observed."""
function write_quality_flagged(output_dir::AbstractString, run_id::AbstractString,
                                experiment_name::AbstractString, result::Dict{String,Any},
                                stability_flag::AbstractString; kwargs...)
    status = stability_flag == "STABLE" ? "valid" : "numerically_unstable"
    result["stabilityFlag"] = stability_flag
    return write_result(output_dir, run_id, experiment_name, result; status=status, kwargs...)
end

end # module
