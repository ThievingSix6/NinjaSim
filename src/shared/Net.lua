--[[
	Remote registry. The server creates every remote on start; clients wait for them.

	Security model: the client only ever *asks*. Every Request is validated on the
	server (ownership, prices, cooldowns, requirements). The client never reports
	damage, currency, XP or rewards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- server -> client
	"DataSync", -- full profile snapshot
	"DataChanged", -- { key = value } batched changes
	"CombatResult", -- attacker-only hit results (damage numbers, crits)
	"Swing", -- another player swung (for their animation)
	"EnemyHit", -- enemy took damage (flash / recoil for nearby clients)
	"EnemyDied", -- enemy defeated (death effect + rewards popup)
	"Notify", -- toast text
	"LevelUp",
	"TierUnlocked",
	"Rebirthed",
	"BossEvent", -- spawn / defeat announcements
	"BossTelegraph", -- warning shapes for boss attacks
	"EggHatched",
	"ZoneChanged",
	"PlayerHurt",
	"Reward", -- generic reward popup (codes, boss loot)
	"SkillCast", -- another player cast a skill (their effects)
	"SkillHits", -- skill damage results (caster: numbers; others: flinches)
	"HatLoot", -- hat loot: drops, pickups, procs, life steal heals (LootService)
	"Dodged", -- another player dodged (their roll pose)
	"Evaded", -- an enemy or boss hit missed you during a dodge's i-frames
	"Trade", -- trade invites and the shared trade window's state (TradeService)
	-- client -> server
	"Attack",
	"Dodge", -- the local player rolled (CombatService opens the i-frames)
	"CancelAttack", -- the local player jumped out of a swing's wind-up (CombatService cancels it)
	"Duel", -- duel invites, start, hits and results (DuelService)
	"Temple", -- Cursed Temple gate, floors, clears and run end (TempleService)
}

Net.Functions = {
	"Request", -- generic validated action: Request:InvokeServer(action, ...)
}

local folder: Folder

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing then
			folder = existing :: Folder
		else
			local f = Instance.new("Folder")
			f.Name = "Remotes"
			for _, name in ipairs(Net.Events) do
				local re = Instance.new("RemoteEvent")
				re.Name = name
				re.Parent = f
			end
			for _, name in ipairs(Net.Functions) do
				local rf = Instance.new("RemoteFunction")
				rf.Name = name
				rf.Parent = f
			end
			f.Parent = ReplicatedStorage
			folder = f
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder
end

function Net.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

-- Fire to every player within `radius` of `position`.
function Net.FireNear(event: RemoteEvent, position: Vector3, radius: number, ...)
	local Players = game:GetService("Players")
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude <= radius then
			event:FireClient(player, ...)
		end
	end
end

return Net
