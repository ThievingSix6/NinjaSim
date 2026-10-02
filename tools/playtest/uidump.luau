--!nocheck
-- Dumps the player's ScreenGuis (visible parts only) to JSON for tools/uipreview.
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local GUI_PROPS = { "Size", "Position", "AnchorPoint", "Rotation", "ZIndex", "LayoutOrder", "BackgroundColor3", "BackgroundTransparency",
	"BorderSizePixel", "BorderColor3", "ClipsDescendants", "AutomaticSize" }
local CLASS_PROPS = {
	TextLabel = { "Text", "TextColor3", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment", "TextYAlignment", "Font", "RichText",
		"TextTransparency", "TextStrokeTransparency", "TextStrokeColor3", "LineHeight" },
	ImageLabel = { "Image", "ImageColor3", "ImageTransparency", "ImageRectOffset", "ImageRectSize", "ScaleType", "SliceCenter" },
	ScrollingFrame = { "CanvasSize", "ScrollBarThickness", "ScrollBarImageColor3", "AutomaticCanvasSize", "CanvasPosition" },
	ViewportFrame = { "ImageTransparency", "ImageColor3" },
	CanvasGroup = { "GroupTransparency", "GroupColor3" },
	UICorner = { "CornerRadius" },
	UIStroke = { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "Enabled" },
	UIGradient = { "Color", "Transparency", "Rotation", "Offset", "Enabled" },
	UIPadding = { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" },
	UIListLayout = { "FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder" },
	UIGridLayout = { "CellSize", "CellPadding", "FillDirection", "FillDirectionMaxCells", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "StartCorner" },
	UIScale = { "Scale" },
	UITextSizeConstraint = { "MaxTextSize", "MinTextSize" },
	UIAspectRatioConstraint = { "AspectRatio", "AspectType", "DominantAxis" },
	UISizeConstraint = { "MinSize", "MaxSize" },
	ScreenGui = { "DisplayOrder", "Enabled", "IgnoreGuiInset" },
}
CLASS_PROPS.TextButton = CLASS_PROPS.TextLabel
CLASS_PROPS.TextBox = table.clone(CLASS_PROPS.TextLabel)
table.insert(CLASS_PROPS.TextBox, "PlaceholderText")
table.insert(CLASS_PROPS.TextBox, "PlaceholderColor3")
CLASS_PROPS.ImageButton = CLASS_PROPS.ImageLabel
local GUI_CLASSES = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true,
	ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true }

local function enc(v)
	local t = typeof(v)
	if t == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "UDim" then
		return { v.Scale, v.Offset }
	elseif t == "Vector2" then
		return { v.X, v.Y }
	elseif t == "Color3" then
		return { v.R, v.G, v.B }
	elseif t == "ColorSequence" then
		local out = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(out, { k.Time, k.Value.R, k.Value.G, k.Value.B })
		end
		return out
	elseif t == "NumberSequence" then
		local out = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(out, { k.Time, k.Value })
		end
		return out
	elseif t == "EnumItem" then
		return v.Name
	elseif t == "Rect" then
		return { v.Min.X, v.Min.Y, v.Max.X, v.Max.Y }
	elseif t == "number" or t == "string" or t == "boolean" then
		return v
	end
	return tostring(v)
end

return function(E, rootProxy)
	local function read(p, prop)
		local ok, v = pcall(function()
			return p[prop]
		end)
		if ok and v ~= nil then
			return enc(v)
		end
		return nil
	end
	local function node(inst)
		local p = E.wrap(inst)
		local class = inst.ClassName
		local isGui = GUI_CLASSES[class]
		if isGui and read(p, "Visible") == false then
			return nil
		end
		if class == "ScreenGui" and read(p, "Enabled") == false then
			return nil
		end
		local n = { c = class, n = inst.Name, p = {} }
		if isGui then
			for _, prop in ipairs(GUI_PROPS) do
				n.p[prop] = read(p, prop)
			end
		end
		for _, prop in ipairs(CLASS_PROPS[class] or {}) do
			n.p[prop] = read(p, prop)
		end
		if class == "ViewportFrame" then
			-- summarise the model for the preview (it can't render 3D)
			local names = {}
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("Model") and #names < 3 then
					table.insert(names, d.Name)
				end
			end
			n.model = table.concat(names, "/")
			return n
		end
		local kids = {}
		for _, child in ipairs(inst:GetChildren()) do
			local k = node(child)
			if k then
				table.insert(kids, k)
			end
		end
		if #kids > 0 then
			n.k = kids
		end
		return n
	end
	local root = E.unwrap(rootProxy)
	local guis = {}
	for _, child in ipairs(root:GetChildren()) do
		if child.ClassName == "ScreenGui" then
			local n = node(child)
			if n then
				table.insert(guis, n)
			end
		end
	end
	table.sort(guis, function(a, b)
		return (a.p.DisplayOrder or 0) < (b.p.DisplayOrder or 0)
	end)
	return guis
end
