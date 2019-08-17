using Revise
using DocStringExtensions

"""
$(TYPEDSIGNATURES)

Solve a time-varying, finite horizon LQ-game to find closed-loop NASH feedback
strategies for both players.

Assumes that dynamics are given by `xₖ₊₁ = Aₖ*xₖ + ∑ᵢBₖⁱ uₖⁱ`.

# Fields

- `As`: list over time: of state dynamics matrix Aₖ

- `Bs`: list over time, over players: of control input matrix Bₖⁱ

- `Qs`: list over time, over players: of quadratic state cost Qₖⁱ

- `ls`: list over time, over players: of linear state cost lₖⁱ

- `Rs`: list over time, over `player_a` over `player_b`: of quadratic control cos
        (cost that player a sees if player b takes a certain control action)

"""
function solve_lq_game(As::AbstractVector{AbstractMatrix},
                       Bs::AbstractVector{AbstractVector{AbstractMatrix}},
                       Qs::AbstractVector{AbstractVector{AbstractMatrix}},
                       ls::AbstractVector{AbstractVector{AbstractVector}},
                       Rs::AbstractVector{AbstractVector{AbstractVector{AbstractMatrix}}})
    horizon = length(As)
    num_players = length(first(Bs))
    total_xdim = first(size(first(As)))
    total_udim = sum(last(size(Bi)) for Bi in first(Bs))

    # initialize some intermediate representations

    # quadratic cost to go
    Z = last(Qs)
    # linear cost to go
    ζ = last(lis)

    # working backwards in time to solve the dynamic program
    for kk in horizon:-1:1
        # convenience shorthands for the relevant quantities
        A = As[k]; B = Bs[k]; Q = Qs[k]; l = ls[k]; R = Rs[k];

        # Compute Ps given previously computed Zs.
        # Refer to equation 6.17a in Basar and Olsder.
        # This will involve solving a system of matrix linear equations of the
        # form [S1s; S2s; ...] * [P1; P2; ...] = [Y1; Y2; ...].

        # Setup the S and Y matrix of the S * X = Y matrix equation
        S = zeros(0, total_udim)
        Y = zeros(0, total_xdim)

        # TODO maybe optimize this to allow for SMatrix or at least MMatrix.
        # Maybe concatenating is the better thing to do here if things are
        # static?
        for ii in 1:num_players
            BᵢZᵢ = B[ii]' * Z[ii]
            udim_ii = last(size(B[ii]))
            # the current set of rows that we construct for player ii
            S_row = zeros(udim_ii, 0)
            # the term for own own control cost
            for jj in 1:num_players
                # TODO: maybe think about col-major optimization here for
                # caching or windowing to avoid concatenating
                # append the column for the jth player to the current row
                S_row = hcat(S_row, (ii == jj ? R[ii] + BᵢZᵢ * B[jj] : BᵢZᵢ * B[jj]))
            end
            # append the fully constructed row to the full S-Matrix
            S = vcat(S, S_row)
            Y = vcat([(BᵢZᵢ*A) (B[ii]'*ζ(ii))])
        end

        # solve for the gains `P` and feed forward terms `α` simulatiously
        P_and_α = S \ A
        P = P_and_α[:, 1:total_udim]
        α = P_and_α[:, end]

        # compute F and β as intermediate result for estimating the cost to go
        # for the next step backwards in time
        # TODO: the splat operator here might be really slow
        B_row_vec = hcat(Bs...)
        F = A - B_row_vec * P
        β = -B_row_vec * α

        # update Z and ζ (cost to go representation for the next step backwards
        # in time)
        for ii in 1:num_players
            ζ[ii] = F' * (ζ[ii] + Z[ii] * β) + l[ii] + P.... # TODO
            Z[ii] = F' * Z[ii] * F + Q[ii] + # TODO (maybe use smart indexing, offset arrays or subarrays for this)
        end
    end
end