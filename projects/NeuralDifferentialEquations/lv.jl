
import Pkg
Pkg.activate("projects/NeuralDifferentialEquations") # change this to "." if your working directy is already projects/NeuralDifferentialEquations

using Flux, DifferentialEquations, Plots, DiffEqSensitivity
using ChaoticNDETools, NODEData

begin 
    function lotka_volterra(x,p,t)
        α, β, γ, δ = p 
        [α*x[1] - β*x[1]*x[2], -γ*x[2] + δ*x[1]*x[2]]
    end
    
    α = 1.3
    β = 0.9
    γ = 0.8
    δ = 1.8
    p = [α, β, γ, δ] 
    tspan = (0.,50.)
    dt = 0.1 

    x0 = [0.44249296, 4.6280594] 
    
    prob = ODEProblem(lotka_volterra, x0, tspan, p) 
    sol = solve(prob, Tsit5(), saveat=dt)
end 

train, valid = NODEDataloader(sol, 10; dt=dt, valid_set=0.8)

N_WEIGHTS = 10
nn = Chain(Dense(2, N_WEIGHTS, swish), Dense(N_WEIGHTS, N_WEIGHTS, swish), Dense(N_WEIGHTS, N_WEIGHTS, swish), Dense(N_WEIGHTS, 2)) |> gpu
p, re_nn = Flux.destructure(nn)

neural_ode(u, p, t) = re_nn(p)(u)
basic_tgrad(u,p,t) = zero(u)
nnf = ODEFunction{false}(neural_ode,tgrad=basic_tgrad)
node_prob = ODEProblem(nnf, x0, (Float32(0.),Float32(dt)), p)

model = ChaoticNDE(node_prob)
model(train[1])

loss(x, y) = sum(abs2, x - y)
loss(model(train[1]), train[1][2]) 

function plot_node()
    plt = plot(sol.t, Array(model((sol.t,train[1][2])))', label="Neural ODE")
    plot!(plt, sol.t, Array(sol)', label="Training Data")
    plot!(plt, [train[1][1][1],train[end][1][end]],zeros(2),label="Length of Training Set", linewidth=5, ylims=[0,5])
    display(plt)
end
plot_node()

η = 1f-3
opt = Flux.AdamW(η)
opt_state = Flux.setup(opt, model)

# pre-compile adjoint code 
g = gradient(model) do m
    result = m(train[1])
    loss(result, train[1][2])
end

TRAIN = true
if TRAIN 
    println("starting training...")

    for i_e = 1:400

        Flux.train!(model, train, opt_state) do m, t, x
            result = m((t,x))
            loss(result, x)
        end 

        plot_node()

        if (i_e % 30) == 0  # reduce the learning rate every 30 epochs
            η /= 2
            Flux.adjust!(opt_state, η)
        end
    end
end
