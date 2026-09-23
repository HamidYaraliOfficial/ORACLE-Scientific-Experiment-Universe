"""
    StatsEngine

ORACLE's Statistical Analysis Engine and the sampling primitives used
by the Monte Carlo Engine and Parameter Sweep Engine. Built entirely
on Julia's `Random`, `Statistics` and `LinearAlgebra` standard
libraries — no Distributions.jl / HypothesisTests.jl dependency — so
every probability distribution and every statistical test below is a
direct, from-first-principles numerical implementation.
"""
module StatsEngine

using Random, Statistics, LinearAlgebra

export sample_uniform, sample_normal, sample_lognormal, sample_categorical,
       descriptive_stats, pearson_correlation, covariance_matrix,
       linear_regression, confidence_interval_mean, one_sample_t_test,
       two_sample_t_test, bootstrap_ci, percentile, student_t_cdf

# ------------------------------------------------------------------
# Sampling (Random Variable generation for Monte Carlo / Sweep)
# ------------------------------------------------------------------

sample_uniform(rng::AbstractRNG, lo::Real, hi::Real) = lo + (hi - lo) * rand(rng)

"""Standard Box-Muller transform for N(mean, std)."""
function sample_normal(rng::AbstractRNG, mean::Real, std::Real)
    u1 = max(rand(rng), 1e-12)
    u2 = rand(rng)
    z0 = sqrt(-2.0 * log(u1)) * cos(2π * u2)
    return mean + std * z0
end

sample_lognormal(rng::AbstractRNG, mu::Real, sigma::Real) = exp(sample_normal(rng, mu, sigma))

function sample_categorical(rng::AbstractRNG, values::Vector{String}, weights::Union{Nothing,Vector{Float64}}=nothing)
    n = length(values)
    w = weights === nothing ? fill(1.0/n, n) : weights ./ sum(weights)
    u = rand(rng)
    cum = 0.0
    for i in 1:n
        cum += w[i]
        u <= cum && return values[i]
    end
    return values[end]
end

# ------------------------------------------------------------------
# Descriptive statistics
# ------------------------------------------------------------------

function percentile(xs::AbstractVector{<:Real}, p::Real)
    n = length(xs)
    n == 0 && error("percentile of empty sample")
    s = sort(xs)
    if n == 1; return Float64(s[1]); end
    rank = (p / 100.0) * (n - 1) + 1
    lo = floor(Int, rank); hi = ceil(Int, rank)
    lo = clamp(lo, 1, n); hi = clamp(hi, 1, n)
    frac = rank - lo
    return Float64(s[lo]) + frac * Float64(s[hi] - s[lo])
end

function descriptive_stats(xs::AbstractVector{<:Real})
    n = length(xs)
    n == 0 && error("descriptive_stats of empty sample")
    m = mean(xs)
    v = n > 1 ? var(xs) : 0.0
    return Dict{String,Any}(
        "n" => n, "mean" => m, "variance" => v, "std" => sqrt(v),
        "min" => minimum(xs), "max" => maximum(xs), "median" => percentile(xs, 50),
        "p05" => percentile(xs, 5), "p25" => percentile(xs, 25),
        "p75" => percentile(xs, 75), "p95" => percentile(xs, 95),
        "skewness" => n > 2 ? skewness(xs, m, sqrt(v)) : 0.0,
    )
end

function skewness(xs::AbstractVector{<:Real}, m::Real, s::Real)
    n = length(xs)
    s == 0 && return 0.0
    return (sum(((x - m)/s)^3 for x in xs) / n)
end

pearson_correlation(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}) = cor(x, y)

function covariance_matrix(data::Matrix{Float64})
    return Statistics.cov(data)
end

"""Ordinary least squares via the normal equations, i.e. a real
implementation of ORACLE's regression capability without an external
GLM package. Returns coefficients (including intercept), R^2 and
residual standard error."""
function linear_regression(X::Matrix{Float64}, y::Vector{Float64})
    n, k = size(X)
    Xd = hcat(ones(n), X) # design matrix with intercept
    beta = (Xd' * Xd) \ (Xd' * y)
    yhat = Xd * beta
    resid = y .- yhat
    ss_res = sum(resid .^ 2)
    ss_tot = sum((y .- mean(y)) .^ 2)
    r2 = ss_tot == 0 ? 1.0 : 1.0 - ss_res / ss_tot
    dof = max(n - k - 1, 1)
    se = sqrt(ss_res / dof)
    return Dict{String,Any}("coefficients" => beta, "r_squared" => r2, "residual_std_error" => se, "dof" => dof)
end

# ------------------------------------------------------------------
# Confidence intervals & hypothesis testing
# ------------------------------------------------------------------

"""Regularized incomplete beta function via a continued-fraction
expansion (Numerical Recipes formulation). Needed to compute exact
Student-t p-values without an external special-functions package."""
function betacf(a::Float64, b::Float64, x::Float64; maxit::Int=200, eps::Float64=3e-12)
    qab = a + b; qap = a + 1.0; qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    abs(d) < 1e-30 && (d = 1e-30)
    d = 1.0 / d
    h = d
    for m in 1:maxit
        m2 = 2m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d; abs(d) < 1e-30 && (d = 1e-30)
        c = 1.0 + aa / c; abs(c) < 1e-30 && (c = 1e-30)
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d; abs(d) < 1e-30 && (d = 1e-30)
        c = 1.0 + aa / c; abs(c) < 1e-30 && (c = 1e-30)
        d = 1.0 / d
        del = d * c
        h *= del
        abs(del - 1.0) < eps && break
    end
    return h
end

function incomplete_beta(a::Float64, b::Float64, x::Float64)
    (x <= 0.0) && return 0.0
    (x >= 1.0) && return 1.0
    lbeta = lgamma_(a + b) - lgamma_(a) - lgamma_(b)
    front = exp(lbeta + a * log(x) + b * log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0)
        return front * betacf(a, b, x) / a
    else
        return 1.0 - front * betacf(b, a, 1.0 - x) / b
    end
end

# Lanczos approximation for ln(Gamma(x)), x > 0.
function lgamma_(x::Float64)
    g = 7.0
    c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028,
         771.32342877765313, -176.61502916214059, 12.507343278686905,
         -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
    x < 0.5 && return log(pi / sin(pi * x)) - lgamma_(1.0 - x)
    x -= 1.0
    a = c[1]
    t = x + g + 0.5
    for i in 2:9
        a += c[i] / (x + i - 1)
    end
    return 0.5 * log(2π) + (x + 0.5) * log(t) - t + log(a)
end

"""Two-sided p-value for Student's t distribution with `dof` degrees
of freedom, evaluated at statistic `t`, via the incomplete beta
function relation P(|T|>|t|) = I_{dof/(dof+t^2)}(dof/2, 1/2)."""
function student_t_cdf(t::Float64, dof::Float64)
    x = dof / (dof + t^2)
    p_one_tail = 0.5 * incomplete_beta(dof/2, 0.5, x)
    return t > 0 ? 1.0 - p_one_tail : p_one_tail
end

function two_sided_p_value(t::Float64, dof::Float64)
    x = dof / (dof + t^2)
    return incomplete_beta(dof/2, 0.5, x)
end

"""Confidence interval for a sample mean using the t-distribution
critical value approximated via bisection against `student_t_cdf`."""
function t_critical(dof::Float64, alpha::Float64)
    lo, hi = 0.0, 100.0
    target = 1 - alpha/2
    for _ in 1:100
        mid = (lo + hi) / 2
        cdf = 1.0 - two_sided_p_value(mid, dof) # two-sided p at t=mid corresponds to P(|T|>mid)
        if cdf < target
            lo = mid
        else
            hi = mid
        end
    end
    return (lo + hi) / 2
end

function confidence_interval_mean(xs::AbstractVector{<:Real}, confidence::Real=0.95)
    n = length(xs)
    m = mean(xs)
    s = n > 1 ? std(xs) : 0.0
    dof = max(n - 1, 1)
    tcrit = t_critical(Float64(dof), 1 - confidence)
    margin = tcrit * s / sqrt(n)
    return (m - margin, m + margin)
end

"""One-sample t-test against a hypothesized mean mu0."""
function one_sample_t_test(xs::AbstractVector{<:Real}, mu0::Real)
    n = length(xs)
    m = mean(xs); s = std(xs); dof = n - 1
    se = s / sqrt(n)
    t = (m - mu0) / se
    p = two_sided_p_value(t, Float64(dof))
    d = (m - mu0) / s # Cohen's d effect size
    return Dict{String,Any}("statistic" => t, "dof" => dof, "p_value" => p,
                             "mean" => m, "effect_size_cohens_d" => d)
end

"""Welch's two-sample t-test (does not assume equal variances)."""
function two_sample_t_test(xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real})
    nx, ny = length(xs), length(ys)
    mx, my = mean(xs), mean(ys)
    vx, vy = var(xs), var(ys)
    se = sqrt(vx/nx + vy/ny)
    t = (mx - my) / se
    dof = (vx/nx + vy/ny)^2 / ((vx/nx)^2/(nx-1) + (vy/ny)^2/(ny-1))
    p = two_sided_p_value(t, dof)
    pooled_sd = sqrt(((nx-1)*vx + (ny-1)*vy) / (nx+ny-2))
    d = (mx - my) / pooled_sd
    return Dict{String,Any}("statistic" => t, "dof" => dof, "p_value" => p,
                             "mean_diff" => mx - my, "effect_size_cohens_d" => d)
end

"""Non-parametric bootstrap confidence interval for an arbitrary
statistic function, used by the Uncertainty Quantification Engine when
a distributional assumption is not warranted."""
function bootstrap_ci(xs::AbstractVector{<:Real}, statfn::Function, rng::AbstractRNG;
                       n_boot::Int=2000, confidence::Real=0.95)
    n = length(xs)
    boots = Vector{Float64}(undef, n_boot)
    for i in 1:n_boot
        sampled = [xs[rand(rng, 1:n)] for _ in 1:n]
        boots[i] = statfn(sampled)
    end
    lo_p = (1 - confidence) / 2 * 100
    hi_p = (1 - (1 - confidence) / 2) * 100
    return (percentile(boots, lo_p), percentile(boots, hi_p))
end

end # module
