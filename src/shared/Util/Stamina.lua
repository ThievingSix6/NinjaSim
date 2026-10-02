--[[
	Stamina: one pool per player that attacks and dodges spend (Balance.Stamina). The
	server keeps the real pool in CombatService and the client keeps its own copy for
	the HUD bar and to hold back actions it can't afford; both run this same math.

	An action is allowed while the pool is above 0 (Souls rule: the last swing of a
	bar may overdraw it, down to 0). Spending pauses regen for RegenDelay seconds.
]]

local Balance = require(script.Parent.Parent.Config.Balance)

local Stamina = {}

export type Pool = { Value: number, At: number, RegenFrom: number }

function Stamina.new(now: number): Pool
	return { Value = Balance.Stamina.Max, At = now, RegenFrom = now }
end

-- The pool's value at `now` (regen applied).
function Stamina.Get(pool: Pool, now: number): number
	local regenStart = math.max(pool.At, pool.RegenFrom)
	local regen = math.max(0, now - regenStart) * Balance.Stamina.Regen
	return math.min(Balance.Stamina.Max, pool.Value + regen)
end

-- Can an action start at `now`? `slack` (seconds of extra regen) lets the server
-- forgive network jitter between two actions the client sent in time.
function Stamina.CanAct(pool: Pool, now: number, slack: number?): boolean
	return Stamina.Get(pool, now + (slack or 0)) > 0.5
end

function Stamina.Spend(pool: Pool, now: number, cost: number)
	pool.Value = math.max(0, Stamina.Get(pool, now) - cost)
	pool.At = now
	pool.RegenFrom = now + Balance.Stamina.RegenDelay
end

function Stamina.Refill(pool: Pool, now: number)
	pool.Value = Balance.Stamina.Max
	pool.At = now
	pool.RegenFrom = now
end

-- What a combo move costs.
function Stamina.MoveCost(move): number
	return if move and move.Finisher then Balance.Stamina.Finisher else Balance.Stamina.Attack
end

return Stamina
