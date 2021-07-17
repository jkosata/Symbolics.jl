@metatheory_init ()

TermInterface.isterm(t::Type{<:Sym}) = false
TermInterface.isterm(t::Type{<:Symbolic}) = true

TermInterface.gethead(t::Symbolic) = :call 
TermInterface.gethead(t::Sym) = t
TermInterface.getargs(t::Symbolic) = [operation(t), arguments(t)...]
TermInterface.arity(t::Symbolic) = length(arguments(t))


function TermInterface.similarterm(x::Type{<:Symbolic{T}}, head, args; metadata=nothing) where T
    @assert head == :call
    Term{T}(args[1], args[2:end])
end

function EGraphs.preprocess(t::Symbolic)
    # TODO change to isterm after PR
    if SymbolicUtils.istree(t)
        f = operation(t)
        if f == (+) || f == (*) || f == (-) # check out for other binary ops TODO
            a = arguments(t)
            if length(a) > 2
                return unflatten_args(f, a, 2)
            end
        end
    end
    return t
end

function EGraphs.preprocess(t::Mul{T}) where T
    args = []
    push!(args, t.coeff)
    for (k,v) in t.dict
        for i in 1:v 
            push!(args, k)
        end
    end
    EGraphs.preprocess(Term{T}(*, args))
end

function EGraphs.preprocess(t::Add{T}) where T
    args = []
    for (k,v) in t.dict
        push!(args, v*k)
    end
    EGraphs.preprocess(Term{T}(+, args))
end

"""
Equational rewrite rules for optimizing expressions
"""
opt_theory = @methodtheory begin
    a * x == x * a
    a * x + a * y == a*(x+y)
    -1 * a == -a
    # fraction rules 
    # (a/b) + (c/b) => (a+c)*(1/b)
end

"""
Approximation of costs of operators in number 
of CPU cycles required for the numerical computation

See 
 * https://latkin.org/blog/2014/11/09/a-simple-benchmark-of-various-math-operations/
 * https://streamhpc.com/blog/2012-07-16/how-expensive-is-an-operation-on-a-cpu/
 * https://github.com/triscale-innov/GFlops.jl
"""
const op_costs = Dict(
    (+)     => 1,
    (-)     => 1,
    abs     => 2,
    (*)     => 3,
    exp     => 18,
    (/)     => 24,
    log1p   => 24,
    deg2rad => 25,
    rad2deg => 25,
    acos    => 27,
    asind   => 28,
    acsch   => 33,
    sin     => 34,
    cos     => 34,
    atan    => 35,
    tan     => 56,
)
# TODO some operator costs are in FLOP and not in cycles!!

function costfun(n::ENode, g::EGraph, an)
    arity(n) == 0 && return get(op_costs, n.head, 1)

    if !(n.head == :call)
        return 1000000000
    end
    cost = 0

    for id ∈ n.args
        eclass = geteclass(g, id)
        !hasdata(eclass, an) && (cost += Inf; break)
        cost += last(getdata(eclass, an))
    end
    cost
end

function optimize(ex; params=SaturationParams())
    # ex = SymbolicUtils.Code.toexpr(ex)
    g = EGraph()

    
    settermtype!(g, Term{symtype(ex), Any})
    
    ec, _ = addexpr!(g, ex)
    g.root = ec.id
    display(g.classes); println()
    saturate!(g, opt_theory, params)

    extract!(g, costfun) # --> "term" head args
end