using Test
using StaticArrays
using LinearAlgebra

using iLQGames:
    LinearSystem,
    AffineStrategy,
    QuadraticPlayerCost,
    FiniteHorizonLQGame,
    solve_lq_game,
    n_states,
    n_controls,
    n_players,
    u_idx_ranges,
    horizon

using Profile
using ProfileView
using BenchmarkTools

using Plots
gr()

function generate_1D_pointmass_game()
    # Testing the solver at a simple example: A two-player point mass 1D system.
    # The state composes of position and oritation. Therefore, the system dynamics
    # are a pure integrator.
    ΔT = 0.1
    H = 10.0
    N_STEPS = Int(H / ΔT)

    # dynamical system
    A = SMatrix{2, 2}([1. ΔT; 0. 1.])
    B = SMatrix{2, 2}([0.5*ΔT^2 ΔT; 0.32*ΔT^2 0.11*ΔT]')
    dyn = LinearSystem(A, B)
    # costs for each player
    c1 = QuadraticPlayerCost((@SMatrix [1. 0.; 0. 1.]), # Q
                             (@SVector [0., 0.]),       # l
                             (@SMatrix [1. 0.; 0. 0.])) # R
    c2 = QuadraticPlayerCost(-c1.Q,                     # Q
                             -c1.l,                     # l
                             (@SMatrix [0. 0.; 0. 1.])) # R

    costs = @SVector [c1, c2]
    # the lq game (player one has control input 1 and 2; player 2 has control input 3
    ltv_dyn = Size(N_STEPS)(repeat([dyn], N_STEPS))
    qtv_costs = Size(N_STEPS)(repeat([costs], N_STEPS))
    lqGame = FiniteHorizonLQGame{((@SVector [1]), (@SVector [2]))}(ltv_dyn, qtv_costs)

    # test all the function calls:
    @test n_states(lqGame) == size(A)[1]
    @test n_controls(lqGame) == size(B)[2]
    @test n_players(lqGame) == length(costs)
    @test horizon(lqGame) == N_STEPS
    u_idx_ranges(lqGame)

    return lqGame
end

function generate_2D_pointmass_game()
    ΔT = 0.1
    HORIZON = 10.0
    N_STEPS = Int(HORIZON / ΔT)

    # dynamical system
    # state layout: x = (x, y, vx, vy)
    A = I + ΔT * @SMatrix [0. 0. 1. 0.;
                           0. 0. 0. 1.;
                           0. 0. 0. 0.;
                           0. 0. 0. 0.]
    B = ΔT * @SMatrix [0. 0. 1. 0.
                       0. 0. 0. 1.
                       1. 0. 0. 0.
                       0. 1. 0. 0.]
    dyn = LinearSystem(A, B)

    # cost
    # player 1 want's the position to be zero
    c1 = QuadraticPlayerCost((@SMatrix [1. 0. 0. 0.;
                                        0. 2. 0. 0.;
                                        0. 0. 0. 0.;
                                        0. 0. 0. 0.]), # Q
                             (@SVector zeros(4)),      # l
                             (@SMatrix [1. 0. 0. 0.;
                                        0. 1. 0. 0.;
                                        0. 0. 0. 0.;
                                        0. 0. 0. 0.]))# R)
    # cost
    # player 2 is adversarial
    c2 = QuadraticPlayerCost(-c1.Q,                   # Q
                             -c1.l ,                  # l
                             (@SMatrix [0. 0. 0. 0.;
                                        0. 0. 0. 0.;
                                        0. 0. 1. 0.;
                                        0. 0. 0. 1.]))# R)
    costs = @SVector [c1, c2]

    ltv_dyn = Size(N_STEPS)(repeat([dyn], N_STEPS))
    qtv_costs = Size(N_STEPS)(repeat([costs], N_STEPS))
    lqGame = FiniteHorizonLQGame{((@SVector [1, 2]), (@SVector [3, 4]))}(ltv_dyn, qtv_costs)

    return lqGame
end


# solve two-player inifinite horizion (time-invariant) LQ game by Lyapunov
# iterations
# TODO this could also use the struct version
function solve_lyapunov_iterations(dyn::LinearSystem, c1::QuadraticPlayerCost, c2::QuadraticPlayerCost, ud1, ud2, n_iter=100)
    A = dyn.A
    B1 = dyn.B[:, ud1]
    B2 = dyn.B[:, ud2]
    Q1 = c1.Q
    Q2 = c2.Q
    R11 = c1.R[ud1, ud1]
    R12 = c1.R[ud2, ud2]
    R21 = c2.R[ud1, ud1]
    R22 = c2.R[ud2, ud2]

    # Initialize cost-to-go with terminal state cost
    Z1 = Q1
    Z2 = Q2

    # Initialize controls
    P1 = (R11 + B1' * Z1 * B1) \ (B1' * Z1 * A)
    P2 = (R22 + B2' * Z2 * B2) \ (B2' * Z2 * A)

    for ii in 1:n_iter
        P1_old = P1
        P2_old = P2

        P1 = (R11 + B1' * Z1 * B1) \ (B1' * Z1 * (A - B2 * P2_old))
        P2 = (R22 + B2' * Z2 * B2) \ (B2' * Z2 * (A - B1 * P1_old))

        Z1 = (A - B1 * P1 - B2 * P2)' * Z1 * (A - B1 * P1 - B2 * P2) + P1' * R11 * P1 + P2' * R12 * P2 + Q1
        Z2 = (A - B1 * P1 - B2 * P2)' * Z2 * (A - B1 * P1 - B2 * P2) + P1' * R21 * P1 + P2' * R22 * P2 + Q2
    end

    return (P1, P2)
end

function benchmark_solve_lq_game(g::FiniteHorizonLQGame)
    b = @benchmark solve_lq_game($g::FiniteHorizonLQGame)
    show(stdout, "text/plain", b)
    println()
end

function profile_solve_lq_game(g::FiniteHorizonLQGame)
    Profile.clear()
    @profile begin for i in 1:1000
            solve_lq_game(g)
    end end
    ProfileView.view()
end


function test_lyapunov(g::FiniteHorizonLQGame)

    # 1. Lyapunov solution for the inifnite horizion problem
    P1_lyap, P2_lyap = solve_lyapunov_iterations(g.dyn[1],
                                                 g.player_costs[1][1],
                                                 g.player_costs[1][2],
                                                 u_idx_ranges(g)[1],
                                                 u_idx_ranges(g)[2])
    P_lyap = [P1_lyap; P2_lyap]

    # 2. LQ game solution
    strategies = solve_lq_game(g)
    γ0 = first(strategies)
    P_lqg = γ0.P

    print("""
          P_lyap: $(round.(P_lyap; digits=2))
          P_lqg:  $(round.(P_lqg; digits=2))
          """)

    @testset "lyapunov" begin
        @test isapprox(P_lyap, P_lqg; norm=v->norm(v, Inf), atol=1e-4)
    end;

    return P_lyap, P_lqg
end

@testset "solve_lq_game" begin
    g_1D = generate_1D_pointmass_game()
    test_lyapunov(g_1D)
    benchmark_solve_lq_game(g_1D)

    g_2D = generate_2D_pointmass_game()
    test_lyapunov(g_2D)
    benchmark_solve_lq_game(g_2D)
end;

function benchmark_solve_lq_game(g::FiniteHorizonLQGame)
    b = @benchmark solve_lq_game($g::FiniteHorizonLQGame)
    show(stdout, "text/plain", b)
    println()
end

function profile_solve_lq_game(g::FiniteHorizonLQGame)
    Profile.clear()
    @profile begin for i in 1:1000
            solve_lq_game(g)
    end end
    ProfileView.view()
end

function gen_fake_data()
    # fake data:
    nx = 5;
    nu = 2;
    N_STEPS = 100;

    A = rand(nx, nx)
    B = rand(nx, nu)

    P = rand(nu, nx)
    α = zeros(nu)
    x0 = rand(nx)

    while any(abs(e) >=1 for e in first(eigen(A+B*P)))
        P = -rand(nu, nx)
        println(maximum(abs.(first(eigen(A+B*P)))))
    end

    xs = [x0]
    us = []
    resize!(xs, N_STEPS)
    resize!(us, N_STEPS-1)
    for k in 1:(N_STEPS-1)
        us[k] = P*xs[k] + α
        xs[k+1] = A*xs[k] + B*us[k]
    end

    return xs, us
end


function plot_systraj(xs, us)
    nx = length(first(xs))
    nu = length(first(us))

    # states
    px = plot(hcat(xs...)'; layout=(nx, 1))

    # inputs
    pu = plot(hcat(us...)'; layout=(nu, 1))

    plot(px, pu, layout=2)
end
