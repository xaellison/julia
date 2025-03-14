# This file is a part of Julia. License is MIT: https://julialang.org/license

## array.jl: Dense arrays

"""
    DimensionMismatch([msg])

The objects called do not have matching dimensionality. Optional argument `msg` is a
descriptive error string.
"""
struct DimensionMismatch <: Exception
    msg::String
end
DimensionMismatch() = DimensionMismatch("")

## Type aliases for convenience ##
"""
    AbstractVector{T}

Supertype for one-dimensional arrays (or array-like types) with
elements of type `T`. Alias for [`AbstractArray{T,1}`](@ref).
"""
const AbstractVector{T} = AbstractArray{T,1}

"""
    AbstractMatrix{T}

Supertype for two-dimensional arrays (or array-like types) with
elements of type `T`. Alias for [`AbstractArray{T,2}`](@ref).
"""
const AbstractMatrix{T} = AbstractArray{T,2}

"""
    AbstractVecOrMat{T}

Union type of [`AbstractVector{T}`](@ref) and [`AbstractMatrix{T}`](@ref).
"""
const AbstractVecOrMat{T} = Union{AbstractVector{T}, AbstractMatrix{T}}
const RangeIndex = Union{Int, AbstractRange{Int}, AbstractUnitRange{Int}}
const DimOrInd = Union{Integer, AbstractUnitRange}
const IntOrInd = Union{Int, AbstractUnitRange}
const DimsOrInds{N} = NTuple{N,DimOrInd}
const NeedsShaping = Union{Tuple{Integer,Vararg{Integer}}, Tuple{OneTo,Vararg{OneTo}}}

"""
    Array{T,N} <: AbstractArray{T,N}

`N`-dimensional dense array with elements of type `T`.
"""
Array

"""
    Vector{T} <: AbstractVector{T}

One-dimensional dense array with elements of type `T`, often used to represent
a mathematical vector. Alias for [`Array{T,1}`](@ref).

See also [`empty`](@ref), [`similar`](@ref) and [`zero`](@ref) for creating vectors.
"""
const Vector{T} = Array{T,1}

"""
    Matrix{T} <: AbstractMatrix{T}

Two-dimensional dense array with elements of type `T`, often used to represent
a mathematical matrix. Alias for [`Array{T,2}`](@ref).

See also [`fill`](@ref), [`zeros`](@ref), [`undef`](@ref) and [`similar`](@ref)
for creating matrices.
"""
const Matrix{T} = Array{T,2}

"""
    VecOrMat{T}

Union type of [`Vector{T}`](@ref) and [`Matrix{T}`](@ref) which allows functions to accept either a Matrix or a Vector.

# Examples
```jldoctest
julia> Vector{Float64} <: VecOrMat{Float64}
true

julia> Matrix{Float64} <: VecOrMat{Float64}
true

julia> Array{Float64, 3} <: VecOrMat{Float64}
false
```
"""
const VecOrMat{T} = Union{Vector{T}, Matrix{T}}

"""
    DenseArray{T, N} <: AbstractArray{T,N}

`N`-dimensional dense array with elements of type `T`.
The elements of a dense array are stored contiguously in memory.
"""
DenseArray

"""
    DenseVector{T}

One-dimensional [`DenseArray`](@ref) with elements of type `T`. Alias for `DenseArray{T,1}`.
"""
const DenseVector{T} = DenseArray{T,1}

"""
    DenseMatrix{T}

Two-dimensional [`DenseArray`](@ref) with elements of type `T`. Alias for `DenseArray{T,2}`.
"""
const DenseMatrix{T} = DenseArray{T,2}

"""
    DenseVecOrMat{T}

Union type of [`DenseVector{T}`](@ref) and [`DenseMatrix{T}`](@ref).
"""
const DenseVecOrMat{T} = Union{DenseVector{T}, DenseMatrix{T}}

## Basic functions ##

import Core: arraysize, arrayset, arrayref, const_arrayref

vect() = Vector{Any}()
vect(X::T...) where {T} = T[ X[i] for i = 1:length(X) ]

"""
    vect(X...)

Create a [`Vector`](@ref) with element type computed from the `promote_typeof` of the argument,
containing the argument list.

# Examples
```jldoctest
julia> a = Base.vect(UInt8(1), 2.5, 1//2)
3-element Vector{Float64}:
 1.0
 2.5
 0.5
```
"""
function vect(X...)
    T = promote_typeof(X...)
    #T[ X[i] for i=1:length(X) ]
    # TODO: this is currently much faster. should figure out why. not clear.
    return copyto!(Vector{T}(undef, length(X)), X)
end

size(a::Array, d::Integer) = arraysize(a, convert(Int, d))
size(a::Vector) = (arraysize(a,1),)
size(a::Matrix) = (arraysize(a,1), arraysize(a,2))
size(a::Array{<:Any,N}) where {N} = (@inline; ntuple(M -> size(a, M), Val(N))::Dims)

asize_from(a::Array, n) = n > ndims(a) ? () : (arraysize(a,n), asize_from(a, n+1)...)

allocatedinline(T::Type) = (@_pure_meta; ccall(:jl_stored_inline, Cint, (Any,), T) != Cint(0))

"""
    Base.isbitsunion(::Type{T})

Return whether a type is an "is-bits" Union type, meaning each type included in a Union is [`isbitstype`](@ref).

# Examples
```jldoctest
julia> Base.isbitsunion(Union{Float64, UInt8})
true

julia> Base.isbitsunion(Union{Float64, String})
false
```
"""
isbitsunion(u::Union) = allocatedinline(u)
isbitsunion(x) = false

function _unsetindex!(A::Array{T}, i::Int) where {T}
    @inline
    @boundscheck checkbounds(A, i)
    t = @_gc_preserve_begin A
    p = Ptr{Ptr{Cvoid}}(pointer(A, i))
    if !allocatedinline(T)
        unsafe_store!(p, C_NULL)
    elseif T isa DataType
        if !datatype_pointerfree(T)
            for j = 1:(Core.sizeof(T) ÷ Core.sizeof(Ptr{Cvoid}))
                unsafe_store!(p, C_NULL, j)
            end
        end
    end
    @_gc_preserve_end t
    return A
end


"""
    Base.bitsunionsize(U::Union) -> Int

For a `Union` of [`isbitstype`](@ref) types, return the size of the largest type; assumes `Base.isbitsunion(U) == true`.

# Examples
```jldoctest
julia> Base.bitsunionsize(Union{Float64, UInt8})
8

julia> Base.bitsunionsize(Union{Float64, UInt8, Int128})
16
```
"""
function bitsunionsize(u::Union)
    isinline, sz, _ = uniontype_layout(u)
    @assert isinline
    return sz
end

length(a::Array) = arraylen(a)
elsize(@nospecialize _::Type{A}) where {T,A<:Array{T}} = aligned_sizeof(T)
sizeof(a::Array) = Core.sizeof(a)

function isassigned(a::Array, i::Int...)
    @inline
    ii = (_sub2ind(size(a), i...) % UInt) - 1
    @boundscheck ii < length(a) % UInt || return false
    ccall(:jl_array_isassigned, Cint, (Any, UInt), a, ii) == 1
end

## copy ##

"""
    unsafe_copyto!(dest::Ptr{T}, src::Ptr{T}, N)

Copy `N` elements from a source pointer to a destination, with no checking. The size of an
element is determined by the type of the pointers.

The `unsafe` prefix on this function indicates that no validation is performed on the
pointers `dest` and `src` to ensure that they are valid. Incorrect usage may corrupt or
segfault your program, in the same manner as C.
"""
function unsafe_copyto!(dest::Ptr{T}, src::Ptr{T}, n) where T
    # Do not use this to copy data between pointer arrays.
    # It can't be made safe no matter how carefully you checked.
    ccall(:memmove, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
          dest, src, n * aligned_sizeof(T))
    return dest
end


function _unsafe_copyto!(dest, doffs, src, soffs, n)
    destp = pointer(dest, doffs)
    srcp = pointer(src, soffs)
    @inbounds if destp < srcp || destp > srcp + n
        for i = 1:n
            if isassigned(src, soffs + i - 1)
                dest[doffs + i - 1] = src[soffs + i - 1]
            else
                _unsetindex!(dest, doffs + i - 1)
            end
        end
    else
        for i = n:-1:1
            if isassigned(src, soffs + i - 1)
                dest[doffs + i - 1] = src[soffs + i - 1]
            else
                _unsetindex!(dest, doffs + i - 1)
            end
        end
    end
    return dest
end

"""
    unsafe_copyto!(dest::Array, do, src::Array, so, N)

Copy `N` elements from a source array to a destination, starting at offset `so` in the
source and `do` in the destination (1-indexed).

The `unsafe` prefix on this function indicates that no validation is performed to ensure
that N is inbounds on either array. Incorrect usage may corrupt or segfault your program, in
the same manner as C.
"""
function unsafe_copyto!(dest::Array{T}, doffs, src::Array{T}, soffs, n) where T
    t1 = @_gc_preserve_begin dest
    t2 = @_gc_preserve_begin src
    destp = pointer(dest, doffs)
    srcp = pointer(src, soffs)
    if !allocatedinline(T)
        ccall(:jl_array_ptr_copy, Cvoid, (Any, Ptr{Cvoid}, Any, Ptr{Cvoid}, Int),
              dest, destp, src, srcp, n)
    elseif isbitstype(T)
        ccall(:memmove, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
              destp, srcp, n * aligned_sizeof(T))
    elseif isbitsunion(T)
        ccall(:memmove, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
              destp, srcp, n * aligned_sizeof(T))
        # copy selector bytes
        ccall(:memmove, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
              ccall(:jl_array_typetagdata, Ptr{UInt8}, (Any,), dest) + doffs - 1,
              ccall(:jl_array_typetagdata, Ptr{UInt8}, (Any,), src) + soffs - 1,
              n)
    else
        _unsafe_copyto!(dest, doffs, src, soffs, n)
    end
    @_gc_preserve_end t2
    @_gc_preserve_end t1
    return dest
end

unsafe_copyto!(dest::Array, doffs, src::Array, soffs, n) =
    _unsafe_copyto!(dest, doffs, src, soffs, n)

"""
    copyto!(dest, do, src, so, N)

Copy `N` elements from collection `src` starting at offset `so`, to array `dest` starting at
offset `do`. Return `dest`.
"""
function copyto!(dest::Array, doffs::Integer, src::Array, soffs::Integer, n::Integer)
    return _copyto_impl!(dest, doffs, src, soffs, n)
end

# this is only needed to avoid possible ambiguities with methods added in some packages
function copyto!(dest::Array{T}, doffs::Integer, src::Array{T}, soffs::Integer, n::Integer) where T
    return _copyto_impl!(dest, doffs, src, soffs, n)
end

function _copyto_impl!(dest::Array, doffs::Integer, src::Array, soffs::Integer, n::Integer)
    n == 0 && return dest
    n > 0 || _throw_argerror()
    if soffs < 1 || doffs < 1 || soffs+n-1 > length(src) || doffs+n-1 > length(dest)
        throw(BoundsError())
    end
    unsafe_copyto!(dest, doffs, src, soffs, n)
    return dest
end

# Outlining this because otherwise a catastrophic inference slowdown
# occurs, see discussion in #27874.
# It is also mitigated by using a constant string.
function _throw_argerror()
    @noinline
    throw(ArgumentError("Number of elements to copy must be nonnegative."))
end

copyto!(dest::Array, src::Array) = copyto!(dest, 1, src, 1, length(src))

# also to avoid ambiguities in packages
copyto!(dest::Array{T}, src::Array{T}) where {T} = copyto!(dest, 1, src, 1, length(src))

# N.B: The generic definition in multidimensional.jl covers, this, this is just here
# for bootstrapping purposes.
function fill!(dest::Array{T}, x) where T
    xT = convert(T, x)
    for i in eachindex(dest)
        @inbounds dest[i] = xT
    end
    return dest
end

"""
    copy(x)

Create a shallow copy of `x`: the outer structure is copied, but not all internal values.
For example, copying an array produces a new array with identically-same elements as the
original.

See also [`copy!`](@ref Base.copy!), [`copyto!`](@ref).
"""
copy

copy(a::T) where {T<:Array} = ccall(:jl_array_copy, Ref{T}, (Any,), a)

## Constructors ##

similar(a::Array{T,1}) where {T}                    = Vector{T}(undef, size(a,1))
similar(a::Array{T,2}) where {T}                    = Matrix{T}(undef, size(a,1), size(a,2))
similar(a::Array{T,1}, S::Type) where {T}           = Vector{S}(undef, size(a,1))
similar(a::Array{T,2}, S::Type) where {T}           = Matrix{S}(undef, size(a,1), size(a,2))
similar(a::Array{T}, m::Int) where {T}              = Vector{T}(undef, m)
similar(a::Array, T::Type, dims::Dims{N}) where {N} = Array{T,N}(undef, dims)
similar(a::Array{T}, dims::Dims{N}) where {T,N}     = Array{T,N}(undef, dims)

# T[x...] constructs Array{T,1}
"""
    getindex(type[, elements...])

Construct a 1-d array of the specified type. This is usually called with the syntax
`Type[]`. Element values can be specified using `Type[a,b,c,...]`.

# Examples
```jldoctest
julia> Int8[1, 2, 3]
3-element Vector{Int8}:
 1
 2
 3

julia> getindex(Int8, 1, 2, 3)
3-element Vector{Int8}:
 1
 2
 3
```
"""
function getindex(::Type{T}, vals...) where T
    a = Vector{T}(undef, length(vals))
    if vals isa NTuple
        @inbounds for i in 1:length(vals)
            a[i] = vals[i]
        end
    else
        # use afoldl to avoid type instability inside loop
        afoldl(1, vals...) do i, v
            @inbounds a[i] = v
            return i + 1
        end
    end
    return a
end

function getindex(::Type{Any}, @nospecialize vals...)
    a = Vector{Any}(undef, length(vals))
    @inbounds for i = 1:length(vals)
        a[i] = vals[i]
    end
    return a
end
getindex(::Type{Any}) = Vector{Any}()

function fill!(a::Union{Array{UInt8}, Array{Int8}}, x::Integer)
    ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), a, convert(eltype(a), x), length(a))
    return a
end

to_dim(d::Integer) = d
to_dim(d::OneTo) = last(d)

"""
    fill(value, dims::Tuple)
    fill(value, dims...)

Create an array of size `dims` with every location set to `value`.

For example, `fill(1.0, (5,5))` returns a 5×5 array of floats,
with `1.0` in every location of the array.

The dimension lengths `dims` may be specified as either a tuple or a sequence of arguments.
An `N`-length tuple or `N` arguments following the `value` specify an `N`-dimensional
array. Thus, a common idiom for creating a zero-dimensional array with its only location
set to `x` is `fill(x)`.

Every location of the returned array is set to (and is thus [`===`](@ref) to)
the `value` that was passed; this means that if the `value` is itself modified,
all elements of the `fill`ed array will reflect that modification because they're
_still_ that very `value`. This is of no concern with `fill(1.0, (5,5))` as the
`value` `1.0` is immutable and cannot itself be modified, but can be unexpected
with mutable values like — most commonly — arrays.  For example, `fill([], 3)`
places _the very same_ empty array in all three locations of the returned vector:

```jldoctest
julia> v = fill([], 3)
3-element Vector{Vector{Any}}:
 []
 []
 []

julia> v[1] === v[2] === v[3]
true

julia> value = v[1]
Any[]

julia> push!(value, 867_5309)
1-element Vector{Any}:
 8675309

julia> v
3-element Vector{Vector{Any}}:
 [8675309]
 [8675309]
 [8675309]
```

To create an array of many independent inner arrays, use a [comprehension](@ref man-comprehensions) instead.
This creates a new and distinct array on each iteration of the loop:

```jldoctest
julia> v2 = [[] for _ in 1:3]
3-element Vector{Vector{Any}}:
 []
 []
 []

julia> v2[1] === v2[2] === v2[3]
false

julia> push!(v2[1], 8675309)
1-element Vector{Any}:
 8675309

julia> v2
3-element Vector{Vector{Any}}:
 [8675309]
 []
 []
```

See also: [`fill!`](@ref), [`zeros`](@ref), [`ones`](@ref), [`similar`](@ref).

# Examples
```jldoctest
julia> fill(1.0, (2,3))
2×3 Matrix{Float64}:
 1.0  1.0  1.0
 1.0  1.0  1.0

julia> fill(42)
0-dimensional Array{Int64, 0}:
42

julia> A = fill(zeros(2), 2) # sets both elements to the same [0.0, 0.0] vector
2-element Vector{Vector{Float64}}:
 [0.0, 0.0]
 [0.0, 0.0]

julia> A[1][1] = 42; # modifies the filled value to be [42.0, 0.0]

julia> A # both A[1] and A[2] are the very same vector
2-element Vector{Vector{Float64}}:
 [42.0, 0.0]
 [42.0, 0.0]
```
"""
function fill end

fill(v, dims::DimOrInd...) = fill(v, dims)
fill(v, dims::NTuple{N, Union{Integer, OneTo}}) where {N} = fill(v, map(to_dim, dims))
fill(v, dims::NTuple{N, Integer}) where {N} = (a=Array{typeof(v),N}(undef, dims); fill!(a, v); a)
fill(v, dims::Tuple{}) = (a=Array{typeof(v),0}(undef, dims); fill!(a, v); a)

"""
    zeros([T=Float64,] dims::Tuple)
    zeros([T=Float64,] dims...)

Create an `Array`, with element type `T`, of all zeros with size specified by `dims`.
See also [`fill`](@ref), [`ones`](@ref), [`zero`](@ref).

# Examples
```jldoctest
julia> zeros(1)
1-element Vector{Float64}:
 0.0

julia> zeros(Int8, 2, 3)
2×3 Matrix{Int8}:
 0  0  0
 0  0  0
```
"""
function zeros end

"""
    ones([T=Float64,] dims::Tuple)
    ones([T=Float64,] dims...)

Create an `Array`, with element type `T`, of all ones with size specified by `dims`.
See also [`fill`](@ref), [`zeros`](@ref).

# Examples
```jldoctest
julia> ones(1,2)
1×2 Matrix{Float64}:
 1.0  1.0

julia> ones(ComplexF64, 2, 3)
2×3 Matrix{ComplexF64}:
 1.0+0.0im  1.0+0.0im  1.0+0.0im
 1.0+0.0im  1.0+0.0im  1.0+0.0im
```
"""
function ones end

for (fname, felt) in ((:zeros, :zero), (:ones, :one))
    @eval begin
        $fname(dims::DimOrInd...) = $fname(dims)
        $fname(::Type{T}, dims::DimOrInd...) where {T} = $fname(T, dims)
        $fname(dims::Tuple{Vararg{DimOrInd}}) = $fname(Float64, dims)
        $fname(::Type{T}, dims::NTuple{N, Union{Integer, OneTo}}) where {T,N} = $fname(T, map(to_dim, dims))
        function $fname(::Type{T}, dims::NTuple{N, Integer}) where {T,N}
            a = Array{T,N}(undef, dims)
            fill!(a, $felt(T))
            return a
        end
        function $fname(::Type{T}, dims::Tuple{}) where {T}
            a = Array{T}(undef)
            fill!(a, $felt(T))
            return a
        end
    end
end

function _one(unit::T, x::AbstractMatrix) where T
    require_one_based_indexing(x)
    m,n = size(x)
    m==n || throw(DimensionMismatch("multiplicative identity defined only for square matrices"))
    # Matrix{T}(I, m, m)
    I = zeros(T, m, m)
    for i in 1:m
        I[i,i] = unit
    end
    I
end

one(x::AbstractMatrix{T}) where {T} = _one(one(T), x)
oneunit(x::AbstractMatrix{T}) where {T} = _one(oneunit(T), x)

## Conversions ##

convert(::Type{T}, a::AbstractArray) where {T<:Array} = a isa T ? a : T(a)
convert(::Type{Union{}}, a::AbstractArray) = throw(MethodError(convert, (Union{}, a)))

promote_rule(a::Type{Array{T,n}}, b::Type{Array{S,n}}) where {T,n,S} = el_same(promote_type(T,S), a, b)

## Constructors ##

if nameof(@__MODULE__) === :Base  # avoid method overwrite
# constructors should make copies
Array{T,N}(x::AbstractArray{S,N})         where {T,N,S} = copyto_axcheck!(Array{T,N}(undef, size(x)), x)
AbstractArray{T,N}(A::AbstractArray{S,N}) where {T,N,S} = copyto_axcheck!(similar(A,T), A)
end

## copying iterators to containers

"""
    collect(element_type, collection)

Return an `Array` with the given element type of all items in a collection or iterable.
The result has the same shape and number of dimensions as `collection`.

# Examples
```jldoctest
julia> collect(Float64, 1:2:5)
3-element Vector{Float64}:
 1.0
 3.0
 5.0
```
"""
collect(::Type{T}, itr) where {T} = _collect(T, itr, IteratorSize(itr))

_collect(::Type{T}, itr, isz::Union{HasLength,HasShape}) where {T} =
    copyto!(_array_for(T, isz, _similar_shape(itr, isz)), itr)
function _collect(::Type{T}, itr, isz::SizeUnknown) where T
    a = Vector{T}()
    for x in itr
        push!(a, x)
    end
    return a
end

# make a collection similar to `c` and appropriate for collecting `itr`
_similar_for(c, ::Type{T}, itr, isz, shp) where {T} = similar(c, T)

_similar_shape(itr, ::SizeUnknown) = nothing
_similar_shape(itr, ::HasLength) = length(itr)::Integer
_similar_shape(itr, ::HasShape) = axes(itr)

_similar_for(c::AbstractArray, ::Type{T}, itr, ::SizeUnknown, ::Nothing) where {T} =
    similar(c, T, 0)
_similar_for(c::AbstractArray, ::Type{T}, itr, ::HasLength, len::Integer) where {T} =
    similar(c, T, len)
_similar_for(c::AbstractArray, ::Type{T}, itr, ::HasShape, axs) where {T} =
    similar(c, T, axs)

# make a collection appropriate for collecting `itr::Generator`
_array_for(::Type{T}, ::SizeUnknown, ::Nothing) where {T} = Vector{T}(undef, 0)
_array_for(::Type{T}, ::HasLength, len::Integer) where {T} = Vector{T}(undef, Int(len))
_array_for(::Type{T}, ::HasShape{N}, axs) where {T,N} = similar(Array{T,N}, axs)

# used by syntax lowering for simple typed comprehensions
_array_for(::Type{T}, itr, isz) where {T} = _array_for(T, isz, _similar_shape(itr, isz))


"""
    collect(collection)

Return an `Array` of all items in a collection or iterator. For dictionaries, returns
`Pair{KeyType, ValType}`. If the argument is array-like or is an iterator with the
[`HasShape`](@ref IteratorSize) trait, the result will have the same shape
and number of dimensions as the argument.

Used by comprehensions to turn a generator into an `Array`.

# Examples
```jldoctest
julia> collect(1:2:13)
7-element Vector{Int64}:
  1
  3
  5
  7
  9
 11
 13

julia> [x^2 for x in 1:8 if isodd(x)]
4-element Vector{Int64}:
  1
  9
 25
 49
```
"""
collect(itr) = _collect(1:1 #= Array =#, itr, IteratorEltype(itr), IteratorSize(itr))

collect(A::AbstractArray) = _collect_indices(axes(A), A)

collect_similar(cont, itr) = _collect(cont, itr, IteratorEltype(itr), IteratorSize(itr))

_collect(cont, itr, ::HasEltype, isz::Union{HasLength,HasShape}) =
    copyto!(_similar_for(cont, eltype(itr), itr, isz, _similar_shape(itr, isz)), itr)

function _collect(cont, itr, ::HasEltype, isz::SizeUnknown)
    a = _similar_for(cont, eltype(itr), itr, isz, nothing)
    for x in itr
        push!(a,x)
    end
    return a
end

_collect_indices(::Tuple{}, A) = copyto!(Array{eltype(A),0}(undef), A)
_collect_indices(indsA::Tuple{Vararg{OneTo}}, A) =
    copyto!(Array{eltype(A)}(undef, length.(indsA)), A)
function _collect_indices(indsA, A)
    B = Array{eltype(A)}(undef, length.(indsA))
    copyto!(B, CartesianIndices(axes(B)), A, CartesianIndices(indsA))
end

# NOTE: this function is not meant to be called, only inferred, for the
# purpose of bounding the types of values generated by an iterator.
function _iterator_upper_bound(itr)
    x = iterate(itr)
    while x !== nothing
        val = getfield(x, 1)
        if inferencebarrier(nothing)
            return val
        end
        x = iterate(itr, getfield(x, 2))
    end
    throw(nothing)
end

# define this as a macro so that the call to Core.Compiler
# gets inlined into the caller before recursion detection
# gets a chance to see it, so that recursive calls to the caller
# don't trigger the inference limiter
if isdefined(Core, :Compiler)
    macro default_eltype(itr)
        I = esc(itr)
        return quote
            if $I isa Generator && ($I).f isa Type
                T = ($I).f
            else
                T = Core.Compiler.return_type(_iterator_upper_bound, Tuple{typeof($I)})
            end
            promote_typejoin_union(T)
        end
    end
else
    macro default_eltype(itr)
        I = esc(itr)
        return quote
            if $I isa Generator && ($I).f isa Type
                promote_typejoin_union($I.f)
            else
                Any
            end
        end
    end
end

function collect(itr::Generator)
    isz = IteratorSize(itr.iter)
    et = @default_eltype(itr)
    if isa(isz, SizeUnknown)
        return grow_to!(Vector{et}(), itr)
    else
        shp = _similar_shape(itr, isz)
        y = iterate(itr)
        if y === nothing
            return _array_for(et, isz, shp)
        end
        v1, st = y
        dest = _array_for(typeof(v1), isz, shp)
        # The typeassert gives inference a helping hand on the element type and dimensionality
        # (work-around for #28382)
        et′ = et <: Type ? Type : et
        RT = dest isa AbstractArray ? AbstractArray{<:et′, ndims(dest)} : Any
        collect_to_with_first!(dest, v1, itr, st)::RT
    end
end

_collect(c, itr, ::EltypeUnknown, isz::SizeUnknown) =
    grow_to!(_similar_for(c, @default_eltype(itr), itr, isz, nothing), itr)

function _collect(c, itr, ::EltypeUnknown, isz::Union{HasLength,HasShape})
    et = @default_eltype(itr)
    shp = _similar_shape(itr, isz)
    y = iterate(itr)
    if y === nothing
        return _similar_for(c, et, itr, isz, shp)
    end
    v1, st = y
    dest = _similar_for(c, typeof(v1), itr, isz, shp)
    # The typeassert gives inference a helping hand on the element type and dimensionality
    # (work-around for #28382)
    et′ = et <: Type ? Type : et
    RT = dest isa AbstractArray ? AbstractArray{<:et′, ndims(dest)} : Any
    collect_to_with_first!(dest, v1, itr, st)::RT
end

function collect_to_with_first!(dest::AbstractArray, v1, itr, st)
    i1 = first(LinearIndices(dest))
    dest[i1] = v1
    return collect_to!(dest, itr, i1+1, st)
end

function collect_to_with_first!(dest, v1, itr, st)
    push!(dest, v1)
    return grow_to!(dest, itr, st)
end

function setindex_widen_up_to(dest::AbstractArray{T}, el, i) where T
    @inline
    new = similar(dest, promote_typejoin(T, typeof(el)))
    f = first(LinearIndices(dest))
    copyto!(new, first(LinearIndices(new)), dest, f, i-f)
    @inbounds new[i] = el
    return new
end

function collect_to!(dest::AbstractArray{T}, itr, offs, st) where T
    # collect to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    i = offs
    while true
        y = iterate(itr, st)
        y === nothing && break
        el, st = y
        if el isa T || typeof(el) === T
            @inbounds dest[i] = el::T
            i += 1
        else
            new = setindex_widen_up_to(dest, el, i)
            return collect_to!(new, itr, i+1, st)
        end
    end
    return dest
end

function grow_to!(dest, itr)
    y = iterate(itr)
    y === nothing && return dest
    dest2 = empty(dest, typeof(y[1]))
    push!(dest2, y[1])
    grow_to!(dest2, itr, y[2])
end

function push_widen(dest, el)
    @inline
    new = sizehint!(empty(dest, promote_typejoin(eltype(dest), typeof(el))), length(dest))
    if new isa AbstractSet
        # TODO: merge back these two branches when copy! is re-enabled for sets/vectors
        union!(new, dest)
    else
        append!(new, dest)
    end
    push!(new, el)
    return new
end

function grow_to!(dest, itr, st)
    T = eltype(dest)
    y = iterate(itr, st)
    while y !== nothing
        el, st = y
        if el isa T || typeof(el) === T
            push!(dest, el::T)
        else
            new = push_widen(dest, el)
            return grow_to!(new, itr, st)
        end
        y = iterate(itr, st)
    end
    return dest
end

## Iteration ##

iterate(A::Array, i=1) = (@inline; (i % UInt) - 1 < length(A) ? (@inbounds A[i], i + 1) : nothing)

## Indexing: getindex ##

"""
    getindex(collection, key...)

Retrieve the value(s) stored at the given key or index within a collection. The syntax
`a[i,j,...]` is converted by the compiler to `getindex(a, i, j, ...)`.

See also [`get`](@ref), [`keys`](@ref), [`eachindex`](@ref).

# Examples
```jldoctest
julia> A = Dict("a" => 1, "b" => 2)
Dict{String, Int64} with 2 entries:
  "b" => 2
  "a" => 1

julia> getindex(A, "a")
1
```
"""
function getindex end

# This is more complicated than it needs to be in order to get Win64 through bootstrap
@eval getindex(A::Array, i1::Int) = arrayref($(Expr(:boundscheck)), A, i1)
@eval getindex(A::Array, i1::Int, i2::Int, I::Int...) = (@inline; arrayref($(Expr(:boundscheck)), A, i1, i2, I...))

# Faster contiguous indexing using copyto! for AbstractUnitRange and Colon
function getindex(A::Array, I::AbstractUnitRange{<:Integer})
    @inline
    @boundscheck checkbounds(A, I)
    lI = length(I)
    X = similar(A, axes(I))
    if lI > 0
        copyto!(X, firstindex(X), A, first(I), lI)
    end
    return X
end

# getindex for carrying out logical indexing for AbstractUnitRange{Bool} as Bool <: Integer
getindex(a::Array, r::AbstractUnitRange{Bool}) = getindex(a, to_index(r))

function getindex(A::Array, c::Colon)
    lI = length(A)
    X = similar(A, lI)
    if lI > 0
        unsafe_copyto!(X, 1, A, 1, lI)
    end
    return X
end

# This is redundant with the abstract fallbacks, but needed for bootstrap
function getindex(A::Array{S}, I::AbstractRange{Int}) where S
    return S[ A[i] for i in I ]
end

## Indexing: setindex! ##

"""
    setindex!(collection, value, key...)

Store the given value at the given key or index within a collection. The syntax `a[i,j,...] =
x` is converted by the compiler to `(setindex!(a, x, i, j, ...); x)`.
"""
function setindex! end

@eval setindex!(A::Array{T}, x, i1::Int) where {T} = arrayset($(Expr(:boundscheck)), A, convert(T,x)::T, i1)
@eval setindex!(A::Array{T}, x, i1::Int, i2::Int, I::Int...) where {T} =
    (@inline; arrayset($(Expr(:boundscheck)), A, convert(T,x)::T, i1, i2, I...))

# This is redundant with the abstract fallbacks but needed and helpful for bootstrap
function setindex!(A::Array, X::AbstractArray, I::AbstractVector{Int})
    @_propagate_inbounds_meta
    @boundscheck setindex_shape_check(X, length(I))
    require_one_based_indexing(X)
    X′ = unalias(A, X)
    I′ = unalias(A, I)
    count = 1
    for i in I′
        @inbounds x = X′[count]
        A[i] = x
        count += 1
    end
    return A
end

# Faster contiguous setindex! with copyto!
function setindex!(A::Array{T}, X::Array{T}, I::AbstractUnitRange{Int}) where T
    @inline
    @boundscheck checkbounds(A, I)
    lI = length(I)
    @boundscheck setindex_shape_check(X, lI)
    if lI > 0
        unsafe_copyto!(A, first(I), X, 1, lI)
    end
    return A
end
function setindex!(A::Array{T}, X::Array{T}, c::Colon) where T
    @inline
    lI = length(A)
    @boundscheck setindex_shape_check(X, lI)
    if lI > 0
        unsafe_copyto!(A, 1, X, 1, lI)
    end
    return A
end

# efficiently grow an array

_growbeg!(a::Vector, delta::Integer) =
    ccall(:jl_array_grow_beg, Cvoid, (Any, UInt), a, delta)
_growend!(a::Vector, delta::Integer) =
    ccall(:jl_array_grow_end, Cvoid, (Any, UInt), a, delta)
_growat!(a::Vector, i::Integer, delta::Integer) =
    ccall(:jl_array_grow_at, Cvoid, (Any, Int, UInt), a, i - 1, delta)

# efficiently delete part of an array

_deletebeg!(a::Vector, delta::Integer) =
    ccall(:jl_array_del_beg, Cvoid, (Any, UInt), a, delta)
_deleteend!(a::Vector, delta::Integer) =
    ccall(:jl_array_del_end, Cvoid, (Any, UInt), a, delta)
_deleteat!(a::Vector, i::Integer, delta::Integer) =
    ccall(:jl_array_del_at, Cvoid, (Any, Int, UInt), a, i - 1, delta)

## Dequeue functionality ##

"""
    push!(collection, items...) -> collection

Insert one or more `items` in `collection`. If `collection` is an ordered container,
the items are inserted at the end (in the given order).

# Examples
```jldoctest
julia> push!([1, 2, 3], 4, 5, 6)
6-element Vector{Int64}:
 1
 2
 3
 4
 5
 6
```

If `collection` is ordered, use [`append!`](@ref) to add all the elements of another
collection to it. The result of the preceding example is equivalent to `append!([1, 2, 3], [4,
5, 6])`. For `AbstractSet` objects, [`union!`](@ref) can be used instead.

See [`sizehint!`](@ref) for notes about the performance model.

See also [`pushfirst!`](@ref).
"""
function push! end

function push!(a::Array{T,1}, item) where T
    # convert first so we don't grow the array if the assignment won't work
    itemT = convert(T, item)
    _growend!(a, 1)
    @inbounds a[end] = itemT
    return a
end

function push!(a::Array{Any,1}, @nospecialize item)
    _growend!(a, 1)
    arrayset(true, a, item, length(a))
    return a
end

"""
    append!(collection, collections...) -> collection.

For an ordered container `collection`, add the elements of each `collections`
to the end of it.

!!! compat "Julia 1.6"
    Specifying multiple collections to be appended requires at least Julia 1.6.

# Examples
```jldoctest
julia> append!([1], [2, 3])
3-element Vector{Int64}:
 1
 2
 3

julia> append!([1, 2, 3], [4, 5], [6])
6-element Vector{Int64}:
 1
 2
 3
 4
 5
 6
```

Use [`push!`](@ref) to add individual items to `collection` which are not already
themselves in another collection. The result of the preceding example is equivalent to
`push!([1, 2, 3], 4, 5, 6)`.

See [`sizehint!`](@ref) for notes about the performance model.

See also [`vcat`](@ref) for vectors, [`union!`](@ref) for sets,
and [`prepend!`](@ref) and [`pushfirst!`](@ref) for the opposite order.
"""
function append!(a::Vector, items::AbstractVector)
    itemindices = eachindex(items)
    n = length(itemindices)
    _growend!(a, n)
    copyto!(a, length(a)-n+1, items, first(itemindices), n)
    return a
end

append!(a::AbstractVector, iter) = _append!(a, IteratorSize(iter), iter)
push!(a::AbstractVector, iter...) = append!(a, iter)

append!(a::AbstractVector, iter...) = foldl(append!, iter, init=a)

function _append!(a, ::Union{HasLength,HasShape}, iter)
    n = length(a)
    i = lastindex(a)
    resize!(a, n+Int(length(iter))::Int)
    @inbounds for (i, item) in zip(i+1:lastindex(a), iter)
        a[i] = item
    end
    a
end

function _append!(a, ::IteratorSize, iter)
    for item in iter
        push!(a, item)
    end
    a
end

"""
    prepend!(a::Vector, collections...) -> collection

Insert the elements of each `collections` to the beginning of `a`.

When `collections` specifies multiple collections, order is maintained:
elements of `collections[1]` will appear leftmost in `a`, and so on.

!!! compat "Julia 1.6"
    Specifying multiple collections to be prepended requires at least Julia 1.6.

# Examples
```jldoctest
julia> prepend!([3], [1, 2])
3-element Vector{Int64}:
 1
 2
 3

julia> prepend!([6], [1, 2], [3, 4, 5])
6-element Vector{Int64}:
 1
 2
 3
 4
 5
 6
```
"""
function prepend! end

function prepend!(a::Vector, items::AbstractVector)
    itemindices = eachindex(items)
    n = length(itemindices)
    _growbeg!(a, n)
    if a === items
        copyto!(a, 1, items, n+1, n)
    else
        copyto!(a, 1, items, first(itemindices), n)
    end
    return a
end

prepend!(a::Vector, iter) = _prepend!(a, IteratorSize(iter), iter)
pushfirst!(a::Vector, iter...) = prepend!(a, iter)

prepend!(a::AbstractVector, iter...) = foldr((v, a) -> prepend!(a, v), iter, init=a)

function _prepend!(a, ::Union{HasLength,HasShape}, iter)
    require_one_based_indexing(a)
    n = length(iter)
    _growbeg!(a, n)
    i = 0
    for item in iter
        @inbounds a[i += 1] = item
    end
    a
end
function _prepend!(a, ::IteratorSize, iter)
    n = 0
    for item in iter
        n += 1
        pushfirst!(a, item)
    end
    reverse!(a, 1, n)
    a
end

"""
    resize!(a::Vector, n::Integer) -> Vector

Resize `a` to contain `n` elements. If `n` is smaller than the current collection
length, the first `n` elements will be retained. If `n` is larger, the new elements are not
guaranteed to be initialized.

# Examples
```jldoctest
julia> resize!([6, 5, 4, 3, 2, 1], 3)
3-element Vector{Int64}:
 6
 5
 4

julia> a = resize!([6, 5, 4, 3, 2, 1], 8);

julia> length(a)
8

julia> a[1:6]
6-element Vector{Int64}:
 6
 5
 4
 3
 2
 1
```
"""
function resize!(a::Vector, nl::Integer)
    l = length(a)
    if nl > l
        _growend!(a, nl-l)
    elseif nl != l
        if nl < 0
            throw(ArgumentError("new length must be ≥ 0"))
        end
        _deleteend!(a, l-nl)
    end
    return a
end

"""
    sizehint!(s, n)

Suggest that collection `s` reserve capacity for at least `n` elements. This can improve performance.

# Notes on the performance model

For types that support `sizehint!`,

1. `push!` and `append!` methods generally may (but are not required to) preallocate extra
   storage. For types implemented in `Base`, they typically do, using a heuristic optimized for
   a general use case.

2. `sizehint!` may control this preallocation. Again, it typically does this for types in
   `Base`.

3. `empty!` is nearly costless (and O(1)) for types that support this kind of preallocation.
"""
function sizehint! end

function sizehint!(a::Vector, sz::Integer)
    ccall(:jl_array_sizehint, Cvoid, (Any, UInt), a, sz)
    a
end

"""
    pop!(collection) -> item

Remove an item in `collection` and return it. If `collection` is an
ordered container, the last item is returned; for unordered containers,
an arbitrary element is returned.

See also: [`popfirst!`](@ref), [`popat!`](@ref), [`delete!`](@ref), [`deleteat!`](@ref), [`splice!`](@ref), and [`push!`](@ref).

# Examples
```jldoctest
julia> A=[1, 2, 3]
3-element Vector{Int64}:
 1
 2
 3

julia> pop!(A)
3

julia> A
2-element Vector{Int64}:
 1
 2

julia> S = Set([1, 2])
Set{Int64} with 2 elements:
  2
  1

julia> pop!(S)
2

julia> S
Set{Int64} with 1 element:
  1

julia> pop!(Dict(1=>2))
1 => 2
```
"""
function pop!(a::Vector)
    if isempty(a)
        throw(ArgumentError("array must be non-empty"))
    end
    item = a[end]
    _deleteend!(a, 1)
    return item
end

"""
    popat!(a::Vector, i::Integer, [default])

Remove the item at the given `i` and return it. Subsequent items
are shifted to fill the resulting gap.
When `i` is not a valid index for `a`, return `default`, or throw an error if
`default` is not specified.

See also: [`pop!`](@ref), [`popfirst!`](@ref), [`deleteat!`](@ref), [`splice!`](@ref).

!!! compat "Julia 1.5"
    This function is available as of Julia 1.5.

# Examples
```jldoctest
julia> a = [4, 3, 2, 1]; popat!(a, 2)
3

julia> a
3-element Vector{Int64}:
 4
 2
 1

julia> popat!(a, 4, missing)
missing

julia> popat!(a, 4)
ERROR: BoundsError: attempt to access 3-element Vector{Int64} at index [4]
[...]
```
"""
function popat!(a::Vector, i::Integer)
    x = a[i]
    _deleteat!(a, i, 1)
    x
end

function popat!(a::Vector, i::Integer, default)
    if 1 <= i <= length(a)
        x = @inbounds a[i]
        _deleteat!(a, i, 1)
        x
    else
        default
    end
end

"""
    pushfirst!(collection, items...) -> collection

Insert one or more `items` at the beginning of `collection`.

This function is called `unshift` in many other programming languages.

# Examples
```jldoctest
julia> pushfirst!([1, 2, 3, 4], 5, 6)
6-element Vector{Int64}:
 5
 6
 1
 2
 3
 4
```
"""
function pushfirst!(a::Array{T,1}, item) where T
    item = convert(T, item)
    _growbeg!(a, 1)
    a[1] = item
    return a
end

"""
    popfirst!(collection) -> item

Remove the first `item` from `collection`.

This function is called `shift` in many other programming languages.

See also: [`pop!`](@ref), [`popat!`](@ref), [`delete!`](@ref).

# Examples
```jldoctest
julia> A = [1, 2, 3, 4, 5, 6]
6-element Vector{Int64}:
 1
 2
 3
 4
 5
 6

julia> popfirst!(A)
1

julia> A
5-element Vector{Int64}:
 2
 3
 4
 5
 6
```
"""
function popfirst!(a::Vector)
    if isempty(a)
        throw(ArgumentError("array must be non-empty"))
    end
    item = a[1]
    _deletebeg!(a, 1)
    return item
end

"""
    insert!(a::Vector, index::Integer, item)

Insert an `item` into `a` at the given `index`. `index` is the index of `item` in
the resulting `a`.

See also: [`push!`](@ref), [`replace`](@ref), [`popat!`](@ref), [`splice!`](@ref).

# Examples
```jldoctest
julia> insert!(Any[1:6;], 3, "here")
7-element Vector{Any}:
 1
 2
  "here"
 3
 4
 5
 6
```
"""
function insert!(a::Array{T,1}, i::Integer, item) where T
    # Throw convert error before changing the shape of the array
    _item = convert(T, item)
    _growat!(a, i, 1)
    # _growat! already did bound check
    @inbounds a[i] = _item
    return a
end

"""
    deleteat!(a::Vector, i::Integer)

Remove the item at the given `i` and return the modified `a`. Subsequent items
are shifted to fill the resulting gap.

See also: [`delete!`](@ref), [`popat!`](@ref), [`splice!`](@ref).

# Examples
```jldoctest
julia> deleteat!([6, 5, 4, 3, 2, 1], 2)
5-element Vector{Int64}:
 6
 4
 3
 2
 1
```
"""
function deleteat!(a::Vector, i::Integer)
    i isa Bool && depwarn("passing Bool as an index is deprecated", :deleteat!)
    _deleteat!(a, i, 1)
    return a
end

function deleteat!(a::Vector, r::AbstractUnitRange{<:Integer})
    if eltype(r) === Bool
        return invoke(deleteat!, Tuple{Vector, AbstractVector{Bool}}, a, r)
    else
        n = length(a)
        f = first(r)
        f isa Bool && depwarn("passing Bool as an index is deprecated", :deleteat!)
        isempty(r) || _deleteat!(a, f, length(r))
        return a
    end
end

"""
    deleteat!(a::Vector, inds)

Remove the items at the indices given by `inds`, and return the modified `a`.
Subsequent items are shifted to fill the resulting gap.

`inds` can be either an iterator or a collection of sorted and unique integer indices,
or a boolean vector of the same length as `a` with `true` indicating entries to delete.

# Examples
```jldoctest
julia> deleteat!([6, 5, 4, 3, 2, 1], 1:2:5)
3-element Vector{Int64}:
 5
 3
 1

julia> deleteat!([6, 5, 4, 3, 2, 1], [true, false, true, false, true, false])
3-element Vector{Int64}:
 5
 3
 1

julia> deleteat!([6, 5, 4, 3, 2, 1], (2, 2))
ERROR: ArgumentError: indices must be unique and sorted
Stacktrace:
[...]
```
"""
deleteat!(a::Vector, inds) = _deleteat!(a, inds)
deleteat!(a::Vector, inds::AbstractVector) = _deleteat!(a, to_indices(a, (inds,))[1])

struct Nowhere; end
push!(::Nowhere, _) = nothing
_growend!(::Nowhere, _) = nothing

@inline function _push_deleted!(dltd, a::Vector, ind)
    if @inbounds isassigned(a, ind)
        push!(dltd, @inbounds a[ind])
    else
        _growend!(dltd, 1)
    end
end

@inline function _copy_item!(a::Vector, p, q)
    if @inbounds isassigned(a, q)
        @inbounds a[p] = a[q]
    else
        _unsetindex!(a, p)
    end
end

function _deleteat!(a::Vector, inds, dltd=Nowhere())
    n = length(a)
    y = iterate(inds)
    y === nothing && return a
    (p, s) = y
    checkbounds(a, p)
    _push_deleted!(dltd, a, p)
    q = p+1
    while true
        y = iterate(inds, s)
        y === nothing && break
        (i,s) = y
        if !(q <= i <= n)
            if i < q
                throw(ArgumentError("indices must be unique and sorted"))
            else
                throw(BoundsError())
            end
        end
        while q < i
            _copy_item!(a, p, q)
            p += 1; q += 1
        end
        _push_deleted!(dltd, a, i)
        q = i+1
    end
    while q <= n
        _copy_item!(a, p, q)
        p += 1; q += 1
    end
    _deleteend!(a, n-p+1)
    return a
end

# Simpler and more efficient version for logical indexing
function deleteat!(a::Vector, inds::AbstractVector{Bool})
    n = length(a)
    length(inds) == n || throw(BoundsError(a, inds))
    p = 1
    for (q, i) in enumerate(inds)
        _copy_item!(a, p, q)
        p += !i
    end
    _deleteend!(a, n-p+1)
    return a
end

const _default_splice = []

"""
    splice!(a::Vector, index::Integer, [replacement]) -> item

Remove the item at the given index, and return the removed item.
Subsequent items are shifted left to fill the resulting gap.
If specified, replacement values from an ordered
collection will be spliced in place of the removed item.

See also: [`replace`](@ref), [`delete!`](@ref), [`deleteat!`](@ref), [`pop!`](@ref), [`popat!`](@ref).

# Examples
```jldoctest
julia> A = [6, 5, 4, 3, 2, 1]; splice!(A, 5)
2

julia> A
5-element Vector{Int64}:
 6
 5
 4
 3
 1

julia> splice!(A, 5, -1)
1

julia> A
5-element Vector{Int64}:
  6
  5
  4
  3
 -1

julia> splice!(A, 1, [-1, -2, -3])
6

julia> A
7-element Vector{Int64}:
 -1
 -2
 -3
  5
  4
  3
 -1
```

To insert `replacement` before an index `n` without removing any items, use
`splice!(collection, n:n-1, replacement)`.
"""
function splice!(a::Vector, i::Integer, ins=_default_splice)
    v = a[i]
    m = length(ins)
    if m == 0
        _deleteat!(a, i, 1)
    elseif m == 1
        a[i] = ins[1]
    else
        _growat!(a, i, m-1)
        k = 1
        for x in ins
            a[i+k-1] = x
            k += 1
        end
    end
    return v
end

"""
    splice!(a::Vector, indices, [replacement]) -> items

Remove items at specified indices, and return a collection containing
the removed items.
Subsequent items are shifted left to fill the resulting gaps.
If specified, replacement values from an ordered collection will be spliced in
place of the removed items; in this case, `indices` must be a `AbstractUnitRange`.

To insert `replacement` before an index `n` without removing any items, use
`splice!(collection, n:n-1, replacement)`.

!!! compat "Julia 1.5"
    Prior to Julia 1.5, `indices` must always be a `UnitRange`.

!!! compat "Julia 1.8"
    Prior to Julia 1.8, `indices` must be a `UnitRange` if splicing in replacement values.

# Examples
```jldoctest
julia> A = [-1, -2, -3, 5, 4, 3, -1]; splice!(A, 4:3, 2)
Int64[]

julia> A
8-element Vector{Int64}:
 -1
 -2
 -3
  2
  5
  4
  3
 -1
```
"""
function splice!(a::Vector, r::AbstractUnitRange{<:Integer}, ins=_default_splice)
    v = a[r]
    m = length(ins)
    if m == 0
        deleteat!(a, r)
        return v
    end

    n = length(a)
    f = first(r)
    l = last(r)
    d = length(r)

    if m < d
        delta = d - m
        _deleteat!(a, (f - 1 < n - l) ? f : (l - delta + 1), delta)
    elseif m > d
        _growat!(a, (f - 1 < n - l) ? f : (l + 1), m - d)
    end

    k = 1
    for x in ins
        a[f+k-1] = x
        k += 1
    end
    return v
end

splice!(a::Vector, inds) = (dltds = eltype(a)[]; _deleteat!(a, inds, dltds); dltds)

function empty!(a::Vector)
    _deleteend!(a, length(a))
    return a
end

_memcmp(a, b, len) = ccall(:memcmp, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t), a, b, len % Csize_t) % Int

# use memcmp for cmp on byte arrays
function cmp(a::Array{UInt8,1}, b::Array{UInt8,1})
    c = _memcmp(a, b, min(length(a),length(b)))
    return c < 0 ? -1 : c > 0 ? +1 : cmp(length(a),length(b))
end

const BitIntegerArray{N} = Union{map(T->Array{T,N}, BitInteger_types)...} where N
# use memcmp for == on bit integer types
==(a::Arr, b::Arr) where {Arr <: BitIntegerArray} =
    size(a) == size(b) && 0 == _memcmp(a, b, sizeof(eltype(Arr)) * length(a))

# this is ~20% faster than the generic implementation above for very small arrays
function ==(a::Arr, b::Arr) where Arr <: BitIntegerArray{1}
    len = length(a)
    len == length(b) && 0 == _memcmp(a, b, sizeof(eltype(Arr)) * len)
end

"""
    reverse(v [, start=1 [, stop=length(v) ]] )

Return a copy of `v` reversed from start to stop.  See also [`Iterators.reverse`](@ref)
for reverse-order iteration without making a copy, and in-place [`reverse!`](@ref).

# Examples
```jldoctest
julia> A = Vector(1:5)
5-element Vector{Int64}:
 1
 2
 3
 4
 5

julia> reverse(A)
5-element Vector{Int64}:
 5
 4
 3
 2
 1

julia> reverse(A, 1, 4)
5-element Vector{Int64}:
 4
 3
 2
 1
 5

julia> reverse(A, 3, 5)
5-element Vector{Int64}:
 1
 2
 5
 4
 3
```
"""
function reverse(A::AbstractVector, start::Integer, stop::Integer=lastindex(A))
    s, n = Int(start), Int(stop)
    B = similar(A)
    for i = firstindex(A):s-1
        B[i] = A[i]
    end
    for i = s:n
        B[i] = A[n+s-i]
    end
    for i = n+1:lastindex(A)
        B[i] = A[i]
    end
    return B
end

# 1d special cases of reverse(A; dims) and reverse!(A; dims):
for (f,_f) in ((:reverse,:_reverse), (:reverse!,:_reverse!))
    @eval begin
        $f(A::AbstractVector; dims=:) = $_f(A, dims)
        $_f(A::AbstractVector, ::Colon) = $f(A, firstindex(A), lastindex(A))
        $_f(A::AbstractVector, dim::Tuple{Integer}) = $_f(A, first(dim))
        function $_f(A::AbstractVector, dim::Integer)
            dim == 1 || throw(ArgumentError("invalid dimension $dim ≠ 1"))
            return $_f(A, :)
        end
    end
end

function reverseind(a::AbstractVector, i::Integer)
    li = LinearIndices(a)
    first(li) + last(li) - i
end

"""
    reverse!(v [, start=1 [, stop=length(v) ]]) -> v

In-place version of [`reverse`](@ref).

# Examples
```jldoctest
julia> A = Vector(1:5)
5-element Vector{Int64}:
 1
 2
 3
 4
 5

julia> reverse!(A);

julia> A
5-element Vector{Int64}:
 5
 4
 3
 2
 1
```
"""
function reverse!(v::AbstractVector, start::Integer, stop::Integer=lastindex(v))
    s, n = Int(start), Int(stop)
    liv = LinearIndices(v)
    if n <= s  # empty case; ok
    elseif !(first(liv) ≤ s ≤ last(liv))
        throw(BoundsError(v, s))
    elseif !(first(liv) ≤ n ≤ last(liv))
        throw(BoundsError(v, n))
    end
    r = n
    @inbounds for i in s:div(s+n-1, 2)
        v[i], v[r] = v[r], v[i]
        r -= 1
    end
    return v
end

# concatenations of homogeneous combinations of vectors, horizontal and vertical

vcat() = Vector{Any}()
hcat() = Vector{Any}()

function hcat(V::Vector{T}...) where T
    height = length(V[1])
    for j = 2:length(V)
        if length(V[j]) != height
            throw(DimensionMismatch("vectors must have same lengths"))
        end
    end
    return [ V[j][i]::T for i=1:length(V[1]), j=1:length(V) ]
end

function vcat(arrays::Vector{T}...) where T
    n = 0
    for a in arrays
        n += length(a)
    end
    arr = Vector{T}(undef, n)
    nd = 1
    for a in arrays
        na = length(a)
        @assert nd + na <= 1 + length(arr) # Concurrent modification of arrays?
        unsafe_copyto!(arr, nd, a, 1, na)
        nd += na
    end
    return arr
end

_cat(n::Integer, x::Integer...) = reshape([x...], (ntuple(Returns(1), n-1)..., length(x)))

## find ##

"""
    findnext(A, i)

Find the next index after or including `i` of a `true` element of `A`,
or `nothing` if not found.

Indices are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

# Examples
```jldoctest
julia> A = [false, false, true, false]
4-element Vector{Bool}:
 0
 0
 1
 0

julia> findnext(A, 1)
3

julia> findnext(A, 4) # returns nothing, but not printed in the REPL

julia> A = [false false; true false]
2×2 Matrix{Bool}:
 0  0
 1  0

julia> findnext(A, CartesianIndex(1, 1))
CartesianIndex(2, 1)
```
"""
findnext(A, start) = findnext(identity, A, start)

"""
    findfirst(A)

Return the index or key of the first `true` value in `A`.
Return `nothing` if no such value is found.
To search for other kinds of values, pass a predicate as the first argument.

Indices or keys are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

See also: [`findall`](@ref), [`findnext`](@ref), [`findlast`](@ref), [`searchsortedfirst`](@ref).

# Examples
```jldoctest
julia> A = [false, false, true, false]
4-element Vector{Bool}:
 0
 0
 1
 0

julia> findfirst(A)
3

julia> findfirst(falses(3)) # returns nothing, but not printed in the REPL

julia> A = [false false; true false]
2×2 Matrix{Bool}:
 0  0
 1  0

julia> findfirst(A)
CartesianIndex(2, 1)
```
"""
findfirst(A) = findfirst(identity, A)

# Needed for bootstrap, and allows defining only an optimized findnext method
findfirst(A::AbstractArray) = findnext(A, first(keys(A)))

"""
    findnext(predicate::Function, A, i)

Find the next index after or including `i` of an element of `A`
for which `predicate` returns `true`, or `nothing` if not found.

Indices are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

# Examples
```jldoctest
julia> A = [1, 4, 2, 2];

julia> findnext(isodd, A, 1)
1

julia> findnext(isodd, A, 2) # returns nothing, but not printed in the REPL

julia> A = [1 4; 2 2];

julia> findnext(isodd, A, CartesianIndex(1, 1))
CartesianIndex(1, 1)
```
"""
function findnext(testf::Function, A, start)
    i = oftype(first(keys(A)), start)
    l = last(keys(A))
    i > l && return nothing
    while true
        testf(A[i]) && return i
        i == l && break
        # nextind(A, l) can throw/overflow
        i = nextind(A, i)
    end
    return nothing
end

"""
    findfirst(predicate::Function, A)

Return the index or key of the first element of `A` for which `predicate` returns `true`.
Return `nothing` if there is no such element.

Indices or keys are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

# Examples
```jldoctest
julia> A = [1, 4, 2, 2]
4-element Vector{Int64}:
 1
 4
 2
 2

julia> findfirst(iseven, A)
2

julia> findfirst(x -> x>10, A) # returns nothing, but not printed in the REPL

julia> findfirst(isequal(4), A)
2

julia> A = [1 4; 2 2]
2×2 Matrix{Int64}:
 1  4
 2  2

julia> findfirst(iseven, A)
CartesianIndex(2, 1)
```
"""
function findfirst(testf::Function, A)
    for (i, a) in pairs(A)
        testf(a) && return i
    end
    return nothing
end

# Needed for bootstrap, and allows defining only an optimized findnext method
findfirst(testf::Function, A::Union{AbstractArray, AbstractString}) =
    findnext(testf, A, first(keys(A)))

findfirst(p::Union{Fix2{typeof(isequal),Int},Fix2{typeof(==),Int}}, r::OneTo{Int}) =
    1 <= p.x <= r.stop ? p.x : nothing

findfirst(p::Union{Fix2{typeof(isequal),T},Fix2{typeof(==),T}}, r::AbstractUnitRange) where {T<:Integer} =
    first(r) <= p.x <= last(r) ? firstindex(r) + Int(p.x - first(r)) : nothing

function findfirst(p::Union{Fix2{typeof(isequal),T},Fix2{typeof(==),T}}, r::StepRange{T,S}) where {T,S}
    isempty(r) && return nothing
    minimum(r) <= p.x <= maximum(r) || return nothing
    d = convert(S, p.x - first(r))
    iszero(d % step(r)) || return nothing
    return d ÷ step(r) + 1
end

"""
    findprev(A, i)

Find the previous index before or including `i` of a `true` element of `A`,
or `nothing` if not found.

Indices are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

See also: [`findnext`](@ref), [`findfirst`](@ref), [`findall`](@ref).

# Examples
```jldoctest
julia> A = [false, false, true, true]
4-element Vector{Bool}:
 0
 0
 1
 1

julia> findprev(A, 3)
3

julia> findprev(A, 1) # returns nothing, but not printed in the REPL

julia> A = [false false; true true]
2×2 Matrix{Bool}:
 0  0
 1  1

julia> findprev(A, CartesianIndex(2, 1))
CartesianIndex(2, 1)
```
"""
findprev(A, start) = findprev(identity, A, start)

"""
    findlast(A)

Return the index or key of the last `true` value in `A`.
Return `nothing` if there is no `true` value in `A`.

Indices or keys are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

See also: [`findfirst`](@ref), [`findprev`](@ref), [`findall`](@ref).

# Examples
```jldoctest
julia> A = [true, false, true, false]
4-element Vector{Bool}:
 1
 0
 1
 0

julia> findlast(A)
3

julia> A = falses(2,2);

julia> findlast(A) # returns nothing, but not printed in the REPL

julia> A = [true false; true false]
2×2 Matrix{Bool}:
 1  0
 1  0

julia> findlast(A)
CartesianIndex(2, 1)
```
"""
findlast(A) = findlast(identity, A)

# Needed for bootstrap, and allows defining only an optimized findprev method
findlast(A::AbstractArray) = findprev(A, last(keys(A)))

"""
    findprev(predicate::Function, A, i)

Find the previous index before or including `i` of an element of `A`
for which `predicate` returns `true`, or `nothing` if not found.

Indices are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

# Examples
```jldoctest
julia> A = [4, 6, 1, 2]
4-element Vector{Int64}:
 4
 6
 1
 2

julia> findprev(isodd, A, 1) # returns nothing, but not printed in the REPL

julia> findprev(isodd, A, 3)
3

julia> A = [4 6; 1 2]
2×2 Matrix{Int64}:
 4  6
 1  2

julia> findprev(isodd, A, CartesianIndex(1, 2))
CartesianIndex(2, 1)
```
"""
function findprev(testf::Function, A, start)
    f = first(keys(A))
    i = oftype(f, start)
    i < f && return nothing
    while true
        testf(A[i]) && return i
        i == f && break
        # prevind(A, f) can throw/underflow
        i = prevind(A, i)
    end
    return nothing
end

"""
    findlast(predicate::Function, A)

Return the index or key of the last element of `A` for which `predicate` returns `true`.
Return `nothing` if there is no such element.

Indices or keys are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

# Examples
```jldoctest
julia> A = [1, 2, 3, 4]
4-element Vector{Int64}:
 1
 2
 3
 4

julia> findlast(isodd, A)
3

julia> findlast(x -> x > 5, A) # returns nothing, but not printed in the REPL

julia> A = [1 2; 3 4]
2×2 Matrix{Int64}:
 1  2
 3  4

julia> findlast(isodd, A)
CartesianIndex(2, 1)
```
"""
function findlast(testf::Function, A)
    for (i, a) in Iterators.reverse(pairs(A))
        testf(a) && return i
    end
    return nothing
end

# Needed for bootstrap, and allows defining only an optimized findprev method
findlast(testf::Function, A::Union{AbstractArray, AbstractString}) =
    findprev(testf, A, last(keys(A)))

"""
    findall(f::Function, A)

Return a vector `I` of the indices or keys of `A` where `f(A[I])` returns `true`.
If there are no such elements of `A`, return an empty array.

Indices or keys are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

# Examples
```jldoctest
julia> x = [1, 3, 4]
3-element Vector{Int64}:
 1
 3
 4

julia> findall(isodd, x)
2-element Vector{Int64}:
 1
 2

julia> A = [1 2 0; 3 4 0]
2×3 Matrix{Int64}:
 1  2  0
 3  4  0
julia> findall(isodd, A)
2-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(2, 1)

julia> findall(!iszero, A)
4-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(2, 1)
 CartesianIndex(1, 2)
 CartesianIndex(2, 2)

julia> d = Dict(:A => 10, :B => -1, :C => 0)
Dict{Symbol, Int64} with 3 entries:
  :A => 10
  :B => -1
  :C => 0

julia> findall(x -> x >= 0, d)
2-element Vector{Symbol}:
 :A
 :C

```
"""
findall(testf::Function, A) = collect(first(p) for p in pairs(A) if testf(last(p)))

# Broadcasting is much faster for small testf, and computing
# integer indices from logical index using findall has a negligible cost
findall(testf::Function, A::AbstractArray) = findall(testf.(A))

"""
    findall(A)

Return a vector `I` of the `true` indices or keys of `A`.
If there are no such elements of `A`, return an empty array.
To search for other kinds of values, pass a predicate as the first argument.

Indices or keys are of the same type as those returned by [`keys(A)`](@ref)
and [`pairs(A)`](@ref).

See also: [`findfirst`](@ref), [`searchsorted`](@ref).

# Examples
```jldoctest
julia> A = [true, false, false, true]
4-element Vector{Bool}:
 1
 0
 0
 1

julia> findall(A)
2-element Vector{Int64}:
 1
 4

julia> A = [true false; false true]
2×2 Matrix{Bool}:
 1  0
 0  1

julia> findall(A)
2-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(2, 2)

julia> findall(falses(3))
Int64[]
```
"""
function findall(A)
    collect(first(p) for p in pairs(A) if last(p))
end

# Allocating result upfront is faster (possible only when collection can be iterated twice)
function findall(A::AbstractArray{Bool})
    n = count(A)
    I = Vector{eltype(keys(A))}(undef, n)
    cnt = 1
    for (i,a) in pairs(A)
        if a
            I[cnt] = i
            cnt += 1
        end
    end
    I
end

findall(x::Bool) = x ? [1] : Vector{Int}()
findall(testf::Function, x::Number) = testf(x) ? [1] : Vector{Int}()
findall(p::Fix2{typeof(in)}, x::Number) = x in p.x ? [1] : Vector{Int}()

# similar to Matlab's ismember
"""
    indexin(a, b)

Return an array containing the first index in `b` for
each value in `a` that is a member of `b`. The output
array contains `nothing` wherever `a` is not a member of `b`.

See also: [`sortperm`](@ref), [`findfirst`](@ref).

# Examples
```jldoctest
julia> a = ['a', 'b', 'c', 'b', 'd', 'a'];

julia> b = ['a', 'b', 'c'];

julia> indexin(a, b)
6-element Vector{Union{Nothing, Int64}}:
 1
 2
 3
 2
  nothing
 1

julia> indexin(b, a)
3-element Vector{Union{Nothing, Int64}}:
 1
 2
 3
```
"""
function indexin(a, b::AbstractArray)
    inds = keys(b)
    bdict = Dict{eltype(b),eltype(inds)}()
    for (val, ind) in zip(b, inds)
        get!(bdict, val, ind)
    end
    return Union{eltype(inds), Nothing}[
        get(bdict, i, nothing) for i in a
    ]
end

function _findin(a::Union{AbstractArray, Tuple}, b)
    ind  = Vector{eltype(keys(a))}()
    bset = Set(b)
    @inbounds for (i,ai) in pairs(a)
        ai in bset && push!(ind, i)
    end
    ind
end

# If two collections are already sorted, _findin can be computed with
# a single traversal of the two collections. This is much faster than
# using a hash table (although it has the same complexity).
function _sortedfindin(v::Union{AbstractArray, Tuple}, w)
    viter, witer = keys(v), eachindex(w)
    out  = eltype(viter)[]
    vy, wy = iterate(viter), iterate(witer)
    if vy === nothing || wy === nothing
        return out
    end
    viteri, i = vy
    witerj, j = wy
    @inbounds begin
        vi, wj = v[viteri], w[witerj]
        while true
            if isless(vi, wj)
                vy = iterate(viter, i)
                if vy === nothing
                    break
                end
                viteri, i = vy
                vi        = v[viteri]
            elseif isless(wj, vi)
                wy = iterate(witer, j)
                if wy === nothing
                    break
                end
                witerj, j = wy
                wj        = w[witerj]
            else
                push!(out, viteri)
                vy = iterate(viter, i)
                if vy === nothing
                    break
                end
                # We only increment the v iterator because v can have
                # repeated matches to a single value in w
                viteri, i = vy
                vi        = v[viteri]
            end
        end
    end
    return out
end

function findall(pred::Fix2{typeof(in),<:Union{Array{<:Real},Real}}, x::Array{<:Real})
    if issorted(x, Sort.Forward) && issorted(pred.x, Sort.Forward)
        return _sortedfindin(x, pred.x)
    else
        return _findin(x, pred.x)
    end
end
# issorted fails for some element types so the method above has to be restricted
# to element with isless/< defined.
findall(pred::Fix2{typeof(in)}, x::AbstractArray) = _findin(x, pred.x)
findall(pred::Fix2{typeof(in)}, x::Tuple) = _findin(x, pred.x)

# Copying subregions
function indcopy(sz::Dims, I::Vector)
    n = length(I)
    s = sz[n]
    for i = n+1:length(sz)
        s *= sz[i]
    end
    dst = eltype(I)[_findin(I[i], i < n ? (1:sz[i]) : (1:s)) for i = 1:n]
    src = eltype(I)[I[i][_findin(I[i], i < n ? (1:sz[i]) : (1:s))] for i = 1:n]
    dst, src
end

function indcopy(sz::Dims, I::Tuple{Vararg{RangeIndex}})
    n = length(I)
    s = sz[n]
    for i = n+1:length(sz)
        s *= sz[i]
    end
    dst::typeof(I) = ntuple(i-> _findin(I[i], i < n ? (1:sz[i]) : (1:s)), n)::typeof(I)
    src::typeof(I) = ntuple(i-> I[i][_findin(I[i], i < n ? (1:sz[i]) : (1:s))], n)::typeof(I)
    dst, src
end

## Filter ##

"""
    filter(f, a)

Return a copy of collection `a`, removing elements for which `f` is `false`.
The function `f` is passed one argument.

!!! compat "Julia 1.4"
    Support for `a` as a tuple requires at least Julia 1.4.

See also: [`filter!`](@ref), [`Iterators.filter`](@ref).

# Examples
```jldoctest
julia> a = 1:10
1:10

julia> filter(isodd, a)
5-element Vector{Int64}:
 1
 3
 5
 7
 9
```
"""
function filter(f, a::Array{T, N}) where {T, N}
    j = 1
    b = Vector{T}(undef, length(a))
    for ai in a
        @inbounds b[j] = ai
        j = ifelse(f(ai), j+1, j)
    end
    resize!(b, j-1)
    sizehint!(b, length(b))
    b
end

function filter(f, a::AbstractArray)
    (IndexStyle(a) != IndexLinear()) && return a[map(f, a)::AbstractArray{Bool}]

    j = 1
    idxs = Vector{Int}(undef, length(a))
    for idx in eachindex(a)
        @inbounds idxs[j] = idx
        ai = @inbounds a[idx]
        j = ifelse(f(ai), j+1, j)
    end
    resize!(idxs, j-1)
    res = a[idxs]
    empty!(idxs)
    sizehint!(idxs, 0)
    return res
end

"""
    filter!(f, a)

Update collection `a`, removing elements for which `f` is `false`.
The function `f` is passed one argument.

# Examples
```jldoctest
julia> filter!(isodd, Vector(1:10))
5-element Vector{Int64}:
 1
 3
 5
 7
 9
```
"""
function filter!(f, a::AbstractVector)
    j = firstindex(a)
    for ai in a
        @inbounds a[j] = ai
        j = ifelse(f(ai), nextind(a, j), j)
    end
    j > lastindex(a) && return a
    if a isa Vector
        resize!(a, j-1)
        sizehint!(a, j-1)
    else
        deleteat!(a, j:lastindex(a))
    end
    return a
end

"""
    keepat!(a::Vector, inds)
    keepat!(a::BitVector, inds)

Remove the items at all the indices which are not given by `inds`,
and return the modified `a`.
Items which are kept are shifted to fill the resulting gaps.

`inds` must be an iterator of sorted and unique integer indices.
See also [`deleteat!`](@ref).

!!! compat "Julia 1.7"
    This function is available as of Julia 1.7.

# Examples
```jldoctest
julia> keepat!([6, 5, 4, 3, 2, 1], 1:2:5)
3-element Vector{Int64}:
 6
 4
 2
```
"""
keepat!(a::Vector, inds) = _keepat!(a, inds)

"""
    keepat!(a::Vector, m::AbstractVector{Bool})
    keepat!(a::BitVector, m::AbstractVector{Bool})

The in-place version of logical indexing `a = a[m]`. That is, `keepat!(a, m)` on
vectors of equal length `a` and `m` will remove all elements from `a` for which
`m` at the corresponding index is `false`.

# Examples
```jldoctest
julia> a = [:a, :b, :c];

julia> keepat!(a, [true, false, true])
2-element Vector{Symbol}:
 :a
 :c

julia> a
2-element Vector{Symbol}:
 :a
 :c
```
"""
keepat!(a::Vector, m::AbstractVector{Bool}) = _keepat!(a, m)

# set-like operators for vectors
# These are moderately efficient, preserve order, and remove dupes.

_unique_filter!(pred, update!, state) = function (x)
    if pred(x, state)
        update!(state, x)
        true
    else
        false
    end
end

_grow_filter!(seen) = _unique_filter!(∉, push!, seen)
_shrink_filter!(keep) = _unique_filter!(∈, pop!, keep)

function _grow!(pred!, v::AbstractVector, itrs)
    filter!(pred!, v) # uniquify v
    for itr in itrs
        mapfilter(pred!, push!, itr, v)
    end
    return v
end

union!(v::AbstractVector{T}, itrs...) where {T} =
    _grow!(_grow_filter!(sizehint!(Set{T}(), length(v))), v, itrs)

symdiff!(v::AbstractVector{T}, itrs...) where {T} =
    _grow!(_shrink_filter!(symdiff!(Set{T}(), v, itrs...)), v, itrs)

function _shrink!(shrinker!, v::AbstractVector, itrs)
    seen = Set{eltype(v)}()
    filter!(_grow_filter!(seen), v)
    shrinker!(seen, itrs...)
    filter!(in(seen), v)
end

intersect!(v::AbstractVector, itrs...) = _shrink!(intersect!, v, itrs)
setdiff!(  v::AbstractVector, itrs...) = _shrink!(setdiff!, v, itrs)

vectorfilter(T::Type, f, v) = T[x for x in v if f(x)]

function _shrink(shrinker!, itr, itrs)
    T = promote_eltype(itr, itrs...)
    keep = shrinker!(Set{T}(itr), itrs...)
    vectorfilter(T, _shrink_filter!(keep), itr)
end

intersect(itr, itrs...) = _shrink(intersect!, itr, itrs)
setdiff(  itr, itrs...) = _shrink(setdiff!, itr, itrs)

function intersect(v::AbstractVector, r::AbstractRange)
    T = promote_eltype(v, r)
    common = Iterators.filter(in(r), v)
    seen = Set{T}(common)
    return vectorfilter(T, _shrink_filter!(seen), common)
end
intersect(r::AbstractRange, v::AbstractVector) = intersect(v, r)
