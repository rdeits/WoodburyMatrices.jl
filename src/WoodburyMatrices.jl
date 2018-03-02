isdefined(Base, :__precompile__) && __precompile__()

module WoodburyMatrices

using Compat
using Compat.LinearAlgebra
import Compat.LinearAlgebra: det, A_ldiv_B!
import Base: *, \, convert, copy, show, similar, size

# TOOD: remove these definitions once Compat.jl catches up
@static if VERSION <= v"0.7.0-DEV.3185"
    const ldiv! = A_ldiv_B!
    const mul! = A_mul_B!
end

export Woodbury, SymWoodbury, liftFactor

#### Woodbury matrices ####
"""
`W = Woodbury(A, U, C, V)` creates a matrix `W` identical to `A + U*C*V` whose inverse will be calculated using
the Woodbury matrix identity.
"""
mutable struct Woodbury{T,AType,UType,VType,CType,CpType} <: AbstractMatrix{T}
    A::AType
    U::UType
    C::CType
    Cp::CpType
    V::VType
    tmpN1::Vector{T}
    tmpN2::Vector{T}
    tmpk1::Vector{T}
    tmpk2::Vector{T}
end

function Woodbury(A, U::AbstractMatrix{T}, C, V::AbstractMatrix{T}) where {T}
    N = size(A, 1)
    k = size(U, 2)
    if size(A, 2) != N || size(U, 1) != N || size(V, 1) != k || size(V, 2) != N
        throw(DimensionMismatch("Sizes of U ($(size(U))) and/or V ($(size(V))) are inconsistent with A ($(size(A)))"))
    end
    if k > 1
        if size(C, 1) != k || size(C, 2) != k
            throw(DimensionMismatch("C should be $(k)x$(k)"))
        end
    end
    Cp = inv(convert(Matrix, inv(C) .+ V*(A\U)))
    # temporary space for allocation-free solver
    tmpN1 = Array{T,1}(uninitialized, N)
    tmpN2 = Array{T,1}(uninitialized, N)
    tmpk1 = Array{T,1}(uninitialized, k)
    tmpk2 = Array{T,1}(uninitialized, k)

    # Construct the struct based on the types of the copies,
    # not the originals. See: https://github.com/JuliaLang/julia/issues/26294
    # don't copy A, it could be huge.
    Woodbury(A, copy(U), copy(C), Cp, copy(V), tmpN1, tmpN2, tmpk1, tmpk2)
end

Woodbury(A, U::Vector{T}, C, V::Matrix{T}) where {T} = Woodbury(A, reshape(U, length(U), 1), C, V)
@static if VERSION <= v"0.7.0-DEV.3040"
    Woodbury(A, U::AbstractVector, C, V::RowVector) = Woodbury(A, U, C, Matrix(V))
else
    Woodbury(A, U::AbstractVector, C, V::Adjoint) = Woodbury(A, U, C, Matrix(V))
end

size(W::Woodbury) = size(W.A)

function show(io::IO, W::Woodbury)
    println(io, summary(W), ":")
    print(io, "A:\n", W.A)
    print(io, "\nU:\n")
    Base.print_matrix(io, W.U)
    if isa(W.C, Matrix)
        print(io, "\nC:\n")
        Base.print_matrix(io, W.C)
    else
        print(io, "\nC: ", W.C)
    end
    print(io, "\nV:\n")
    Base.print_matrix(io, W.V)
end

Base.Matrix(W::Woodbury{T}) where {T} = convert(Matrix{T}, W)
convert(::Type{Matrix{T}}, W::Woodbury{T}) where {T} = Matrix(W.A) + W.U*W.C*W.V

copy(W::Woodbury) = Woodbury(W.A, W.U, W.C, W.V)

## Woodbury matrix routines ##

*(W::Woodbury, B::StridedVecOrMat)=W.A*B + W.U*(W.C*(W.V*B))

function \(W::Woodbury, R::StridedVecOrMat)
    AinvR = W.A\R
    AinvR - W.A\(W.U*(W.Cp*(W.V*AinvR)))
end

det(W::Woodbury)=det(W.A)*det(W.C)/det(W.Cp)

function A_ldiv_B!(W::Woodbury, B::AbstractVector)
    length(B) == size(W, 1) || throw(DimensionMismatch("Vector length $(length(B)) must match matrix size $(size(W,1))"))
    copyto!(W.tmpN1, B)
    Alu = lufact(W.A) # Note. This makes an allocation (unless A::LU). Alternative is to destroy W.A.
    ldiv!(Alu, W.tmpN1)
    mul!(W.tmpk1, W.V, W.tmpN1)
    mul!(W.tmpk2, W.Cp, W.tmpk1)
    mul!(W.tmpN2, W.U, W.tmpk2)
    ldiv!(Alu, W.tmpN2)
    for i = 1:length(W.tmpN2)
        @inbounds B[i] = W.tmpN1[i] - W.tmpN2[i]
    end
    B
end

"""
Given a type `T`, an integer `n` and `m` tuples of the form (i, j, v), build
sparse matrices `rows`, `vals`, `cols` such that the product
`out = rows * vals * cols` is equivalent to:

```julia
out = zeros(T, n, n)

for (i, j, v) in args
    out[i, j] = v
end
```

The first two components (`i` and `j`) of each tuple should be integers
whereas the third component should be of type `T`

Example:


```
julia> r, v, c = WoodburyMatrices.sparse_factors(Float64, 3,
                                                 (1, 1, 2.0),
                                                 (2, 2, 3.0),
                                                 (3, 3, 4.0));

julia> r*c*v - Diagonal([2.0, 3.0, 4.0])
3x3 sparse matrix with 0 Float64 entries:
```

"""
function sparse_factors(::Type{T}, n::Int, args::@compat(Tuple{Int, Int, Any})...) where {T}
    m = length(args)
    rows = spzeros(T, n, m)
    cols = spzeros(T, m, n)
    vals = zeros(T, m, m)

    ix = 1
    for (i, (row, col, val)) in enumerate(args)
        rows[row, ix] = 1
        cols[ix, col] = 1
        vals[ix, ix] = val
        ix += 1
    end

    rows, vals, cols
end

include("SymWoodburyMatrices.jl")

end
