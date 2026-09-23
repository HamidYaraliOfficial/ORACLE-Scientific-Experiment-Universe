"""
    Solvers

ORACLE's Simulation Engine core: real, from-scratch numerical
integrators for the ordinary-differential-equation models produced by
the Model Editor / Formula Engine. Three interchangeable solvers are
provided (`:euler`, `:rk4`, `:rk45`), selected per-experiment exactly
as the Experiment Definition Language's `solver.method` field
specifies. This module also implements the Numerical Stability
Analyzer: every step is checked for divergence, overflow and NaN/Inf,
and a run is flagged rather than silently returning garbage.
"""
module Solvers

export integrate, StepResult, StabilityFlag, STABLE, DIVERGENT, OVERFLOW, NAN_OR_INF, MAX_STEPS_EXCEEDED

@enum StabilityFlag begin
    STABLE
    DIVERGENT
    OVERFLOW
    NAN_OR_INF
    MAX_STEPS_EXCEEDED
end

struct StepResult
    times::Vector{Float64}
    states::Vector{Dict{String,Float64}}
    flag::StabilityFlag
    steps_taken::Int
end

function is_bad(x::Float64)
    return isnan(x) || isinf(x) || abs(x) > 1.0e150
end

"""
    integrate(rhs, y0, t0, t1, params, method, step, tol, max_steps)

`rhs(t, state, params) -> Dict{String,Float64}` returns dState/dt for
every state variable, given the current time, the current state, and
the parameter environment. `y0` is the initial state.
"""
function integrate(rhs::Function, y0::Dict{String,Float64}, t0::Float64, t1::Float64,
                    params::Dict{String,Float64}, method::Symbol, step::Float64,
                    tol::Float64, max_steps::Int)
    if method == :euler
        return integrate_fixed_step(rhs, y0, t0, t1, params, step, max_steps, euler_step)
    elseif method == :rk4
        return integrate_fixed_step(rhs, y0, t0, t1, params, step, max_steps, rk4_step)
    elseif method == :rk45
        return integrate_adaptive_rk45(rhs, y0, t0, t1, params, step, tol, max_steps)
    else
        error("Unknown solver method: $method (expected :euler, :rk4 or :rk45)")
    end
end

function state_add(a::Dict{String,Float64}, b::Dict{String,Float64}, scale::Float64)
    out = Dict{String,Float64}()
    for (k, v) in a
        out[k] = v + scale * get(b, k, 0.0)
    end
    return out
end

function any_bad(state::Dict{String,Float64})
    for v in values(state)
        is_bad(v) && return true
    end
    return false
end

function euler_step(rhs, t, y, h, params)
    dy = rhs(t, y, params)
    return state_add(y, dy, h)
end

function rk4_step(rhs, t, y, h, params)
    k1 = rhs(t, y, params)
    k2 = rhs(t + h/2, state_add(y, k1, h/2), params)
    k3 = rhs(t + h/2, state_add(y, k2, h/2), params)
    k4 = rhs(t + h, state_add(y, k3, h), params)
    out = copy(y)
    for k in keys(y)
        out[k] = y[k] + (h/6.0) * (k1[k] + 2k2[k] + 2k3[k] + k4[k])
    end
    return out
end

function state_norm(y::Dict{String,Float64})
    s = 0.0
    for v in values(y)
        (isnan(v) || isinf(v)) && return Inf
        s += v*v
    end
    return sqrt(s)
end

function integrate_fixed_step(rhs, y0, t0, t1, params, step, max_steps, step_fn)
    times = Float64[t0]
    states = Dict{String,Float64}[copy(y0)]
    t = t0
    y = copy(y0)
    steps = 0
    flag = STABLE
    prev_norm = state_norm(y)
    while t < t1 && steps < max_steps
        h = min(step, t1 - t)
        y_new = step_fn(rhs, t, y, h, params)
        if any_bad(y_new)
            flag = NAN_OR_INF
            break
        end
        new_norm = state_norm(y_new)
        if new_norm > 1.0e12 && new_norm > 1.0e6 * max(prev_norm, 1.0)
            flag = DIVERGENT
            y = y_new; t += h; steps += 1
            push!(times, t); push!(states, copy(y))
            break
        end
        y = y_new
        t += h
        steps += 1
        prev_norm = new_norm
        push!(times, t)
        push!(states, copy(y))
    end
    if steps >= max_steps && flag == STABLE
        flag = MAX_STEPS_EXCEEDED
    end
    return StepResult(times, states, flag, steps)
end

"""Embedded Dormand-Prince RK45 with adaptive step-size control,
targeting local error `tol`. This is the same coefficient tableau used
by classical `ode45`-style integrators, implemented directly (no
external ODE package) so ORACLE's numerical core has zero
dependencies beyond Julia's standard library."""
function integrate_adaptive_rk45(rhs, y0, t0, t1, params, step0, tol, max_steps)
    c = [0.0, 1/5, 3/10, 4/5, 8/9, 1.0, 1.0]
    a = [
        Float64[],
        [1/5],
        [3/40, 9/40],
        [44/45, -56/15, 32/9],
        [19372/6561, -25360/2187, 64448/6561, -212/729],
        [9017/3168, -355/33, 46732/5247, 49/176, -5103/18656],
        [35/384, 0.0, 500/1113, 125/192, -2187/6784, 11/84],
    ]
    b5 = [35/384, 0.0, 500/1113, 125/192, -2187/6784, 11/84, 0.0]
    b4 = [5179/57600, 0.0, 7571/16695, 393/640, -92097/339200, 187/2100, 1/40]

    times = Float64[t0]
    states = Dict{String,Float64}[copy(y0)]
    t = t0
    y = copy(y0)
    h = step0
    steps = 0
    flag = STABLE
    keyorder = collect(keys(y0))

    while t < t1 && steps < max_steps
        h = min(h, t1 - t)
        ks = Vector{Dict{String,Float64}}(undef, 7)
        ks[1] = rhs(t, y, params)
        for i in 2:7
            ystage = copy(y)
            for k in keyorder
                acc = 0.0
                for j in 1:(i-1)
                    acc += a[i][j] * ks[j][k]
                end
                ystage[k] = y[k] + h * acc
            end
            ks[i] = rhs(t + c[i]*h, ystage, params)
        end
        y5 = copy(y); y4 = copy(y)
        for k in keyorder
            s5 = sum(b5[i] * ks[i][k] for i in 1:7)
            s4 = sum(b4[i] * ks[i][k] for i in 1:7)
            y5[k] = y[k] + h * s5
            y4[k] = y[k] + h * s4
        end
        if any_bad(y5)
            flag = NAN_OR_INF
            break
        end
        err = sqrt(sum((y5[k] - y4[k])^2 for k in keyorder) / max(length(keyorder),1))
        if err <= tol || h < 1e-10
            t += h
            y = y5
            steps += 1
            push!(times, t)
            push!(states, copy(y))
            if state_norm(y) > 1.0e12
                flag = DIVERGENT
                break
            end
        end
        scale = err == 0.0 ? 2.0 : 0.9 * (tol / err) ^ 0.2
        h *= clamp(scale, 0.2, 5.0)
    end
    if steps >= max_steps && flag == STABLE
        flag = MAX_STEPS_EXCEEDED
    end
    return StepResult(times, states, flag, steps)
end

end # module
