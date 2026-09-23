"""
    JsonMini

A small, dependency-free JSON reader/writer for the Julia Simulation
Engine. ORACLE keeps its numerical core to Julia's standard library
(Random, Statistics, LinearAlgebra, Printf, Dates) plus this ~150-line
module, rather than pulling in JSON.jl, so a fresh Julia install with
zero registered packages can run an experiment end to end.
"""
module JsonMini

export parse_json, to_json, to_json_pretty

# ---------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------

function parse_json(s::AbstractString)
    chars = collect(s)
    pos = Ref(1)
    skip_ws!(chars, pos)
    value = parse_value(chars, pos)
    skip_ws!(chars, pos)
    if pos[] <= length(chars)
        error("Unexpected trailing content at position $(pos[])")
    end
    return value
end

function skip_ws!(chars::Vector{Char}, pos::Ref{Int})
    n = length(chars)
    while pos[] <= n && isspace(chars[pos[]])
        pos[] += 1
    end
end

function parse_value(chars::Vector{Char}, pos::Ref{Int})
    skip_ws!(chars, pos)
    n = length(chars)
    pos[] > n && error("Unexpected end of input")
    c = chars[pos[]]
    if c == '"'
        return parse_string(chars, pos)
    elseif c == '{'
        return parse_object(chars, pos)
    elseif c == '['
        return parse_array(chars, pos)
    elseif c == 't' && matches(chars, pos, "true")
        pos[] += 4; return true
    elseif c == 'f' && matches(chars, pos, "false")
        pos[] += 5; return false
    elseif c == 'n' && matches(chars, pos, "null")
        pos[] += 4; return nothing
    elseif c == '-' || isdigit(c)
        return parse_number(chars, pos)
    else
        error("Unexpected character '$c' at position $(pos[])")
    end
end

function matches(chars::Vector{Char}, pos::Ref{Int}, lit::String)
    lc = collect(lit)
    n = length(lc)
    pos[] + n - 1 <= length(chars) && chars[pos[]:pos[]+n-1] == lc
end

function parse_string(chars::Vector{Char}, pos::Ref{Int})
    pos[] += 1 # opening quote
    buf = IOBuffer()
    n = length(chars)
    while true
        pos[] > n && error("Unterminated string literal")
        c = chars[pos[]]
        if c == '"'
            pos[] += 1
            return String(take!(buf))
        elseif c == '\\'
            pos[] += 1
            pos[] > n && error("Unterminated escape sequence")
            e = chars[pos[]]
            if e == '"'; write(buf, '"')
            elseif e == '\\'; write(buf, '\\')
            elseif e == '/'; write(buf, '/')
            elseif e == 'n'; write(buf, '\n')
            elseif e == 't'; write(buf, '\t')
            elseif e == 'r'; write(buf, '\r')
            elseif e == 'b'; write(buf, '\b')
            elseif e == 'f'; write(buf, '\f')
            elseif e == 'u'
                hex = String(chars[pos[]+1:pos[]+4])
                write(buf, Char(parse(Int, hex, base=16)))
                pos[] += 4
            else
                error("Invalid escape character: \\$e")
            end
            pos[] += 1
        else
            write(buf, c)
            pos[] += 1
        end
    end
end

function parse_number(chars::Vector{Char}, pos::Ref{Int})
    start = pos[]
    n = length(chars)
    if chars[pos[]] == '-'; pos[] += 1; end
    while pos[] <= n && isdigit(chars[pos[]]); pos[] += 1; end
    if pos[] <= n && chars[pos[]] == '.'
        pos[] += 1
        while pos[] <= n && isdigit(chars[pos[]]); pos[] += 1; end
    end
    if pos[] <= n && (chars[pos[]] == 'e' || chars[pos[]] == 'E')
        pos[] += 1
        if pos[] <= n && (chars[pos[]] == '+' || chars[pos[]] == '-'); pos[] += 1; end
        while pos[] <= n && isdigit(chars[pos[]]); pos[] += 1; end
    end
    return parse(Float64, String(chars[start:pos[]-1]))
end

function parse_array(chars::Vector{Char}, pos::Ref{Int})
    pos[] += 1 # '['
    result = Any[]
    skip_ws!(chars, pos)
    if chars[pos[]] == ']'
        pos[] += 1
        return result
    end
    while true
        push!(result, parse_value(chars, pos))
        skip_ws!(chars, pos)
        c = chars[pos[]]
        if c == ','
            pos[] += 1
            skip_ws!(chars, pos)
        elseif c == ']'
            pos[] += 1
            return result
        else
            error("Expected ',' or ']' at position $(pos[])")
        end
    end
end

function parse_object(chars::Vector{Char}, pos::Ref{Int})
    pos[] += 1 # '{'
    result = Dict{String,Any}()
    skip_ws!(chars, pos)
    if chars[pos[]] == '}'
        pos[] += 1
        return result
    end
    while true
        skip_ws!(chars, pos)
        chars[pos[]] == '"' || error("Expected string key at position $(pos[])")
        key = parse_string(chars, pos)
        skip_ws!(chars, pos)
        chars[pos[]] == ':' || error("Expected ':' at position $(pos[])")
        pos[] += 1
        value = parse_value(chars, pos)
        result[key] = value
        skip_ws!(chars, pos)
        c = chars[pos[]]
        if c == ','
            pos[] += 1
        elseif c == '}'
            pos[] += 1
            return result
        else
            error("Expected ',' or '}' at position $(pos[])")
        end
    end
end

# ---------------------------------------------------------------------
# Encoding
# ---------------------------------------------------------------------

to_json(x) = to_json_impl(x, false, 0)
to_json_pretty(x) = to_json_impl(x, true, 0)

function to_json_impl(x::Nothing, ::Bool, ::Int); return "null"; end
function to_json_impl(x::Bool, ::Bool, ::Int); return x ? "true" : "false"; end
function to_json_impl(x::Real, ::Bool, ::Int)
    isinteger(x) && isfinite(x) ? string(Int(round(x))) : string(Float64(x))
end
function to_json_impl(x::AbstractString, ::Bool, ::Int)
    buf = IOBuffer(); write(buf, '"')
    for c in x
        if c == '"'; write(buf, "\\\"")
        elseif c == '\\'; write(buf, "\\\\")
        elseif c == '\n'; write(buf, "\\n")
        elseif c == '\t'; write(buf, "\\t")
        elseif c == '\r'; write(buf, "\\r")
        else; write(buf, c)
        end
    end
    write(buf, '"')
    return String(take!(buf))
end
function to_json_impl(x::AbstractVector, pretty::Bool, indent::Int)
    isempty(x) && return "[]"
    if !pretty
        return "[" * join([to_json_impl(v, pretty, indent) for v in x], ",") * "]"
    end
    pad = "  "^(indent+1)
    inner = join([pad * to_json_impl(v, pretty, indent+1) for v in x], ",\n")
    return "[\n" * inner * "\n" * "  "^indent * "]"
end
function to_json_impl(x::AbstractDict, pretty::Bool, indent::Int)
    isempty(x) && return "{}"
    ks = collect(keys(x))
    if !pretty
        parts = [to_json_impl(string(k), pretty, indent) * ":" * to_json_impl(x[k], pretty, indent) for k in ks]
        return "{" * join(parts, ",") * "}"
    end
    pad = "  "^(indent+1)
    parts = [pad * to_json_impl(string(k), pretty, indent+1) * ": " * to_json_impl(x[k], pretty, indent+1) for k in ks]
    return "{\n" * join(parts, ",\n") * "\n" * "  "^indent * "}"
end

end # module
