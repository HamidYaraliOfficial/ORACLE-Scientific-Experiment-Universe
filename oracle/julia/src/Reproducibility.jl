"""
    Reproducibility

ORACLE's Reproducibility Engine (Julia side). Every run gets a master
seed, and every sub-unit of work (a Monte Carlo sample, a sweep
combination, a replication) gets a *derived* seed computed
deterministically from the master seed and its index, so that:

  * two runs with the same master seed and the same experiment
    configuration always produce bit-identical results, and
  * an individual sample/replication can be re-run in isolation and
    still reproduce exactly.

Config hashing uses a small dependency-free FNV-1a implementation
(rather than pulling in the SHA package) so the whole Julia engine
stays zero-dependency, matching the design of the Haskell and Scala
layers.
"""
module Reproducibility

export derive_seed, fnv1a_hash, config_hash, run_metadata

const FNV_OFFSET_BASIS = 0xcbf29ce484222325
const FNV_PRIME        = 0x100000001b3

"""64-bit FNV-1a hash of a string. Deterministic across platforms and
Julia versions since it only uses byte-level unsigned arithmetic."""
function fnv1a_hash(s::AbstractString)::UInt64
    h = FNV_OFFSET_BASIS
    for b in codeunits(s)
        h = xor(h, UInt64(b))
        h = h * FNV_PRIME
    end
    return h
end

"""Deterministic hash of an experiment configuration (its canonical
JSON string), used for the Scientific Cache Layer: if the config hash,
dataset hash and solver version are unchanged, a prior result can be
reused instead of recomputed."""
config_hash(canonical_json::AbstractString)::String = string(fnv1a_hash(canonical_json), base=16)

"""Derive a reproducible per-unit seed from a master seed and an index
(sample number, replication number, sweep-combination index, ...).
Uses a simple, well-mixed combination (splitmix-style) rather than
naive addition, so nearby indices do not produce correlated seeds."""
function derive_seed(master_seed::Integer, index::Integer)::UInt64
    z = (UInt64(master_seed) + UInt64(index) * 0x9E3779B97F4A7C15) & typemax(UInt64)
    z = xor(z, z >> 30) * 0xBF58476D1CE4E5B9
    z = xor(z, z >> 27) * 0x94D049BB133111EB
    z = xor(z, z >> 31)
    return z
end

"""Bundle the metadata ORACLE's Reproducibility Engine promises to
record for every run: the master seed, the derived seed actually used,
the generator identity, and the configuration hash. This dict is
merged into every result JSON that `ResultStore.write_result` writes."""
function run_metadata(master_seed::Integer, unit_index::Integer, cfg_hash::AbstractString)
    return Dict{String,Any}(
        "masterSeed"        => master_seed,
        "derivedSeed"       => string(derive_seed(master_seed, unit_index)),
        "generator"         => "Xoshiro256** (Julia stdlib Random, seeded via ORACLE splitmix derivation)",
        "juliaVersion"      => string(VERSION),
        "configurationHash" => cfg_hash,
        "generatedAt"       => string(Base.Libc.strftime("%Y-%m-%dT%H:%M:%SZ", time())),
    )
end

end # module
