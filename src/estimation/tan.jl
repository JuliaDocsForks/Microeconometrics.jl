#==========================================================================================#

# TYPE

mutable struct Tan <: TwoStageModel

    first_stage::Micromodel
    second_stage::IV
    pscore::Vector{Float64}
    eweights::PWeights

    Tan() = new()
end

#==========================================================================================#

# FIRST STAGE

function first_stage(::Type{Tan}, MM::Type{<:Micromodel}, MD::Microdata; kwargs...)

    FSM                = Dict(:treatment => "", :instrument => "")
    FSD                = Microdata(MD, FSM)
    FSD.map[:response] = MD.map[:instrument]

    return fit(MM, FSD; kwargs...)
end

#==========================================================================================#

# ESTIMATION

function fit(
        ::Type{Tan}, MM::Type{<:Micromodel}, MD::Microdata; novar::Bool = false, kwargs...
    )

    m = first_stage(Tan, MM, MD; novar = novar)
    return fit(Tan, m, MD; novar = novar, kwargs...)
end

function fit(
        ::Type{Tan},
        MM::Micromodel,
        MD::Microdata;
        novar::Bool = false,
        trim::AbstractFloat = 0.0,
    )

    w = getweights(MD)
    z = getvector(MD, :instrument)
    p = mean(z, getweights(MD))
    π = fitted(MM)
    v = [(1.0 - zi) * (1.0 - p) / (1.0 - πi) + zi * p / πi for (zi, πi) in zip(z, π)]

    v[((trim .> π) .| (1.0 - trim .< π))] .= 0.0

    SSD              = Microdata(MD, Dict(:control => "1"))
    obj              = Tan()
    obj.first_stage  = MM
    obj.second_stage = IV(SSD)
    obj.pscore       = π
    obj.eweights      = pweights(v)

    _fit!(second_stage(obj), reweight(w, obj.eweights))
    novar || _vcov!(obj, getcorr(obj), w)

    return obj
end

#==========================================================================================#

# SCORE (MOMENT CONDITIONS)

score(obj::Tan) = lmul!(Diagonal(obj.eweights), score(second_stage(obj)))

# EXPECTED JACOBIAN OF SCORE × NUMBER OF OBSERVATIONS

jacobian(obj::Tan, w::UnitWeights) = jacobian(second_stage(obj), obj.eweights)

function jacobian(obj::Tan, w::AbstractWeights)
    return jacobian(second_stage(obj), reweight(w, obj.eweights))
end

# EXPECTED JACOBIAN OF SCORE W.R.T. FIRST-STAGE PARAMETERS × NUMBER OF OBSERVATIONS

function crossjacobian(obj::Tan, w::UnitWeights)

    z = getvector(obj, :instrument)
    p = mean(z)
    π = obj.pscore
    D = [(1.0 - zi) * (1.0 - p) / abs2(1.0 - πi) - zi * p / abs2(πi)
         for (zi, πi) in zip(z, π)]

    D[iszero.(obj.eweights)] .= 0.0

    g₁ = jacobexp(obj.first_stage)
    g₂ = score(obj.second_stage)

    return g₂' * lmul!(Diagonal(D), g₁)
end

function crossjacobian(obj::Tan, w::AbstractWeights)

    z = getvector(obj, :instrument)
    p = mean(z, w)
    π = obj.pscore
    D = [wi * ((1.0 - zi) * (1.0 - p) / abs2(1.0 - πi) - zi * p / abs2(πi))
         for (zi, πi, wi) in zip(z, π, w)]

    D[iszero.(obj.eweights)] .= 0.0

    g₁ = jacobexp(obj.first_stage)
    g₂ = score(obj.second_stage)

    return g₂' * lmul!(Diagonal(D), g₁)
end

#==========================================================================================#

# LINEAR PREDICTOR

predict(obj::Tan) = predict(second_stage(obj))

# FITTED VALUES

fitted(obj::Tan) = fitted(second_stage(obj))

# DERIVATIVE OF FITTED VALUES

jacobexp(obj::Tan) = jacobexp(second_stage(obj))

#==========================================================================================#

# UTILITIES

coefnames(obj::Tan) = coefnames(second_stage(obj))
