--[[
	HealthService: gradual health regen out of combat (justin, 2026-10-01).

	No regen while fighting: after RegenDelay seconds without taking damage the
	player heals HealthRegen x MaxHealth per second (both from Stats.Compute, so
	items can improve them). Level-ups no longer heal. Roblox's default "Health"
	script (1%/s, even mid-fight) is removed from every character.
]]

local Players = game:GetService("Players")

local HealthService = {}

local TICK = 0.25

local services
local lastHurt: { [Player]: number } = {}

function HealthService:Init(registry)
	services = registry
end

-- Restarts the out-of-combat timer (call when something hurts a player outside the Humanoid).
function HealthService:MarkHurt(player: Player)
	lastHurt[player] = os.clock()
end

function HealthService:IsRegenerating(player: Player): boolean
	local stats = services.StatService:Get(player)
	local delay = if stats and stats.RegenDelay then stats.RegenDelay else 5
	return os.clock() - (lastHurt[player] or 0) >= delay
end

local function watchCharacter(player: Player, character: Model)
	task.spawn(function()
		local script = character:WaitForChild("Health", 5)
		if script and script:IsA("Script") then
			script:Destroy()
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.01 then
			lastHurt[player] = os.clock()
		end
		last = health
	end)
end

function HealthService:Start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastHurt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and self:IsRegenerating(player) then
					local stats = services.StatService:Get(player)
					local rate = if stats and stats.HealthRegen then stats.HealthRegen else 0.03
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * rate * TICK)
				end
			end
		end
	end)
end

return HealthService
