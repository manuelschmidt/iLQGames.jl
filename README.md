# iLQGames.jl

An implementation of the iterative linear-quadratic methods for general-sum
differential games.

For a full description of the algorithm itself and examples of how it can be
applied, please refer to [paper](https://arxiv.org/abs/1909.04694).
A brief introduction to this framework and benchmarks against a [C++
implementation](https://github.com/HJReachability/ilqgames)
can be found in the [workshop paper]().
Finally, [this paper](https://arxiv.org/abs/2002.04354) demonstrates the flexibility and performance of iLQGames.jl
by combining it with a particle-filter scheme to reason about uncertainty in
differential games in real-time.

## Installation

```julia
]add github.com/lassepe/iLQGames.jl

```

## Minimal Example

Here is a minimal example of two players controlling a singe unicycle.
Player-1 controls the steering, Player-2 controls the acceleration.

We define a Unicycle as a subtype of our `ControlSystem` type and implement the
differential equation by overloading `dx` for our type.


```julia
import iLQGames: dx, xyindex
using iLQGames:
    ControlSystem, GeneralGame, iLQSolver, PlayerCost, solve, plot_traj,
    FunctionPlayerCost

using StaticArrays

# parametes: number of states, number of inputs, sampling time, horizon
nx, nu, ΔT, game_horizon = 4, 2, 0.1, 200

# setup the dynamics
struct Unicycle <: ControlSystem{ΔT,nx,nu} end
# the differential equation of a uncycle with state: (px, py, phi, v)
dx(cs::Unicycle, x, u, t) = SVector(x[4]cos(x[3]), x[4]sin(x[3]), u[1], u[2])
dynamics = Unicycle()

```

To setup the costs encoding each players objectives, we can derive a custom subtype
from `PlayerCost`, or, as done here, simply hand the objective as a lambda function
to the `FunctionPlayerCost`.

```julia

# player-1 wants the unicycle to stay close to the origin,
# player-2 wants to keep close to 1 m/s
costs = (FunctionPlayerCost{nx,nu}((g, x, u, t) -> (x[1]^2 + x[2]^2 + u[1]^2)),
         FunctionPlayerCost{nx,nu}((g, x, u, t) -> ((x[4] - 1)^2 + u[2]^2)))
# indices of inputs that each player controls
player_inputs = (SVector(1), SVector(2))
```

With this information we can construct the game...

```julia
g = GeneralGame{player_inputs, game_horizon}(dynamics, costs)
```

...and solve it for some initial conditions `x0`.
Automatic differentiation will save us from having to specify how to compute LQ approximations of the system.

```julia
# get a solver, choose initial conditions and solve (in about 9 ms with automatic
# differentiation)
solver = iLQSolver(g)
x0 = SVector(1, 1, 0, 0.5)
converged, trajectory, strategies = solve(g, solver, x0)
```

Here what the path of the unicycle looks like (x- and y-position):
```julia
# animate the resulting trajectory. Use the `plot_traj` call without @animated to
# get a static plot instead.
@animated(plot_traj(trajectory, g, [:red, :green], player_inputs),
          1:game_horizon, "minimal_example.gif")
```

At the equilibrium solution, Player-2 accelerates to reach the desired speed. Player-1 steers the unicycle in
a figure-8 to stay close to the origin.

![](examples/minimal_example.gif)

