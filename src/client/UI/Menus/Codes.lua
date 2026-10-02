--[[
	Codes: type a code, redeem it. The server validates and fires a Reward popup.
]]

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme = ctx.Kit, ctx.Theme
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Codes", Title = "Codes", Icon = "Codes", Accent = "Pink", Size = UDim2.fromOffset(540, 330), Parent = ctx.Parent,
	})
	Kit.Label({ Text = "Enter a code for free rewards!", TextSize = 22, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), StrokeThickness = 2.5, Parent = content })
	local boxFrame = Kit.Panel({ Size = UDim2.new(1, -40, 0, 60), Position = UDim2.fromOffset(20, 42), Paint = { Color3.fromRGB(250, 250, 255), Color3.fromRGB(214, 220, 232) }, Stripes = false, StrokeThickness = 3.5, Radius = 12, Parent = content })
	local box = Kit.New("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), ZIndex = 2,
		Font = Theme.FontTitle, TextSize = 28, TextColor3 = Theme.Ink, PlaceholderText = "ENTER CODE", PlaceholderColor3 = Color3.fromRGB(150, 158, 178),
		Text = "", ClearTextOnFocus = false, Parent = boxFrame,
	})
	local status = Kit.Label({ Text = "", TextSize = 18, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 110), StrokeThickness = 2, Parent = content })

	local function redeem()
		local code = box.Text
		if #code == 0 then
			return
		end
		local ok, message = DataController:Request("RedeemCode", code)
		status.Text = if ok then tostring(message or "Redeemed!") else tostring(message or "Invalid code")
		status.TextColor3 = if ok then Theme.Green else Theme.Red
		if ok then
			box.Text = ""
			ctx.Controllers.SoundController:Play("Purchase")
		end
	end
	Kit.Button({ Text = "Redeem", Icon = "Check", Color = "Green", TextSize = 28, IconSize = 38, Size = UDim2.new(1, -40, 0, 62), Position = UDim2.fromOffset(20, 146), Radius = 12, StrokeThickness = 3.5, Parent = content, OnClick = redeem })
	box.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)

	return {
		Window = window,
		Close = close,
		OnOpen = function()
			status.Text = ""
		end,
	}
end

return Menu
