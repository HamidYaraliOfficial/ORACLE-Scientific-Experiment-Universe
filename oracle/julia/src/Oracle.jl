"""
    Oracle

Top-level module for ORACLE's Julia Numerical Computing & Simulation
core. `using Oracle` brings every engine into scope:

  * `JsonMini`          – dependency-free JSON I/O
  * `FormulaEval`        – shared formula-AST evaluator
  * `Reproducibility`    – seed derivation & config hashing
  * `StatsEngine`        – sampling distributions & statistical tests
  * `Solvers`            – ODE integrators (Euler / RK4 / adaptive RK45)
  * `Sweep`              – grid / random / Latin-hypercube sampling
  * `Sensitivity`        – OAT and Sobol sensitivity analysis
  * `MonteCarloEngine`   – Monte Carlo simulation orchestration
  * `ResultStore`        – versioned, provenance-tagged result artifacts

See `run_experiment.jl` for the command-line entry point that wires
these together against a Haskell-validated experiment JSON file.
"""
module Oracle

include("JsonMini.jl")
include("FormulaEval.jl")
include("Reproducibility.jl")
include("StatsEngine.jl")
include("Solvers.jl")
include("Sweep.jl")
include("Sensitivity.jl")
include("MonteCarlo.jl")
include("ResultStore.jl")

using .JsonMini
using .FormulaEval
using .Reproducibility
using .StatsEngine
using .Solvers
using .Sweep
using .Sensitivity
using .MonteCarloEngine
using .ResultStore

export JsonMini, FormulaEval, Reproducibility, StatsEngine, Solvers, Sweep,
       Sensitivity, MonteCarloEngine, ResultStore

end # module
