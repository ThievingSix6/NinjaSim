--[[
	CharmEffects: the looks of charm spells (Config/Charms), client side only.
	SkillEffects requires this and calls Register(E, tools).

	  Hexfire  (the Hexfire Torch) a rolling tendril of flame: a burning head snakes
	           forward along the ground a segment at a time (in step with the server's
	           hits), leaving licks of fire and violet hex sparks that die down behind it.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Charms = require(Shared.Config.Charms)

local CharmEffects = {}

local T -- SkillEffects.Tools
local HEX = Color3.fromRGB(170, 60, 255)
local CORE = Color3.fromRGB(255, 230, 140)

local looks = {}

looks.Hexfire = {
	Start = function() end,
	Result = function(ctx, info)
		local d = Charms.Hexfire
		local length = info.Length or d.Length
		local dir = ctx.Dir
		local side = dir:Cross(Vector3.yAxis)
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
		local ground = ctx.Origin - Vector3.new(0, 2.6, 0)
		local phase = ((info.Seed or 0) % 628) / 100
		local duration = d.Step * d.Segments
		local function at(k: number): Vector3
			-- a snaking line: sideways sway that grows a little as it travels
			return ground + dir * length * k + side * math.sin(phase + k * 9) * (1.2 + 1.6 * k)
		end
		local head = T.part(Vector3.new(2.6, 2.6, 2.6), CFrame.new(at(0)), d.Color, Enum.Material.Neon, Enum.PartType.Ball)
		local core = T.part(Vector3.new(1.4, 1.4, 1.4), CFrame.new(at(0)), CORE, Enum.Material.Neon, Enum.PartType.Ball)
		head.Transparency = 0.1
		local fire = Instance.new("Fire")
		fire.Color = d.Color
		fire.SecondaryColor = HEX
		fire.Size = 6
		fire.Heat = 9
		fire.Parent = head
		local light = Instance.new("PointLight")
		light.Color = d.Color
		light.Range = 16
		light.Brightness = 3
		light.Parent = head
		local low = T.lowGraphics()
		local lastLick = 0
		T.sound("Finisher", 0.8, 0.7)
		T.animate(duration, function(k)
			local p = at(k) + Vector3.new(0, 1 + math.abs(math.sin(k * 18)) * 0.8, 0)
			local roll = CFrame.Angles(k * 30, 0, 0)
			head.CFrame = CFrame.lookAt(p, p + dir) * roll
			core.CFrame = head.CFrame
			-- licks of flame left behind
			if k - lastLick >= (if low then 0.2 else 0.08) then
				lastLick = k
				local spot = at(k)
				local lick = T.part(Vector3.new(1.4, 3.2, 1.4), CFrame.new(spot + Vector3.new(0, 1.4, 0)), d.Color, Enum.Material.Neon, Enum.PartType.Ball)
				lick.Transparency = 0.25
				T.tween(lick, { Size = Vector3.new(0.4, 5.5, 0.4), Transparency = 1, CFrame = lick.CFrame + Vector3.new(0, 2.5, 0) }, 0.6)
				Debris:AddItem(lick, 0.65)
				local scorch = T.part(Vector3.new(0.1, 3, 3), CFrame.new(spot + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), HEX, Enum.Material.Neon, Enum.PartType.Cylinder)
				scorch.Transparency = 0.35
				T.tween(scorch, { Transparency = 1, Size = Vector3.new(0.1, 4.5, 4.5) }, 1.1)
				Debris:AddItem(scorch, 1.15)
			end
		end, function()
			local finish = at(1)
			T.ring(finish, d.Color, 7, 0.4, 2)
			T.fx():Sphere(finish + Vector3.new(0, 1.5, 0), CORE, 2, 9, 0.35)
			head:Destroy()
			core:Destroy()
		end)
		Debris:AddItem(head, duration + 1)
		Debris:AddItem(core, duration + 1)
		T.shake(ctx, 0.12)
	end,
}

function CharmEffects.Register(E, tools)
	T = tools
	E[Charms.Hexfire.Id] = looks.Hexfire
end

return CharmEffects
