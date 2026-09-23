"""
    FormulaEval

Evaluates the same formula-AST JSON produced by Haskell's
`Oracle.Formula.exprToJson` (and consumed by the Web UI's JS
evaluator), so all three layers agree on exactly one expression
semantics. This is the hot-path evaluator: it is called once per
timestep per replication per Monte-Carlo sample, so it is written to
avoid unnecessary allocation.
"""
module FormulaEval

export eval_ast, ast_dependencies

# An AST node is a Dict{String,Any} as produced by JsonMini.parse_json,
# e.g. Dict("type"=>"binop","op"=>"+","left"=>...,"right"=>...)

function eval_ast(node, env::Dict{String,Float64})::Float64
    t = node["type"]
    if t == "num"
        return Float64(node["value"])
    elseif t == "var"
        name = node["name"]
        haskey(env, name) || error("Undefined variable during evaluation: $name")
        return env[name]
    elseif t == "unop"
        op = node["op"]
        v = eval_ast(node["expr"], env)
        return op == "-" ? -v : (v == 0.0 ? 1.0 : 0.0)
    elseif t == "binop"
        op = node["op"]
        l = eval_ast(node["left"], env)
        r = eval_ast(node["right"], env)
        return apply_binop(op, l, r)
    elseif t == "call"
        name = node["name"]
        args = [eval_ast(a, env) for a in node["args"]]
        return apply_call(name, args)
    elseif t == "if"
        c = eval_ast(node["cond"], env)
        return c != 0.0 ? eval_ast(node["then"], env) : eval_ast(node["else"], env)
    else
        error("Unknown AST node type: $t")
    end
end

@inline function apply_binop(op::AbstractString, l::Float64, r::Float64)::Float64
    if op == "+"; return l + r
    elseif op == "-"; return l - r
    elseif op == "*"; return l * r
    elseif op == "/"; r == 0.0 && error("Division by zero"); return l / r
    elseif op == "^"; return l ^ r
    elseif op == "<"; return l < r ? 1.0 : 0.0
    elseif op == "<="; return l <= r ? 1.0 : 0.0
    elseif op == ">"; return l > r ? 1.0 : 0.0
    elseif op == ">="; return l >= r ? 1.0 : 0.0
    elseif op == "=="; return l == r ? 1.0 : 0.0
    elseif op == "!="; return l != r ? 1.0 : 0.0
    elseif op == "&&"; return (l != 0.0 && r != 0.0) ? 1.0 : 0.0
    elseif op == "||"; return (l != 0.0 || r != 0.0) ? 1.0 : 0.0
    else; error("Unknown binary operator: $op")
    end
end

function apply_call(name::AbstractString, args::Vector{Float64})::Float64
    if name == "sin"; return sin(args[1])
    elseif name == "cos"; return cos(args[1])
    elseif name == "tan"; return tan(args[1])
    elseif name == "exp"; return exp(args[1])
    elseif name == "log"; return log(args[1])
    elseif name == "sqrt"; return sqrt(args[1])
    elseif name == "abs"; return abs(args[1])
    elseif name == "min"; return min(args[1], args[2])
    elseif name == "max"; return max(args[1], args[2])
    elseif name == "floor"; return floor(args[1])
    elseif name == "ceil"; return ceil(args[1])
    else; error("Unknown function or wrong arity: $name/$(length(args))")
    end
end

"""Collect every variable name an AST node references (used for
dependency-ordering coupled ODE right-hand sides before integration)."""
function ast_dependencies(node, acc::Set{String}=Set{String}())
    t = node["type"]
    if t == "num"
        # nothing
    elseif t == "var"
        push!(acc, node["name"])
    elseif t == "unop"
        ast_dependencies(node["expr"], acc)
    elseif t == "binop"
        ast_dependencies(node["left"], acc); ast_dependencies(node["right"], acc)
    elseif t == "call"
        for a in node["args"]; ast_dependencies(a, acc); end
    elseif t == "if"
        ast_dependencies(node["cond"], acc); ast_dependencies(node["then"], acc); ast_dependencies(node["else"], acc)
    end
    return acc
end

end # module
