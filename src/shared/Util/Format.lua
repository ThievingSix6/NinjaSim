-- Number / time formatting helpers shared by server and client.
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

-- 1234 -> "1.23K", 5600000 -> "5.6M"
function Format.Abbrev(n: number?): string
	local v = tonumber(n) or 0
	local neg = v < 0
	v = math.abs(v)
	local out
	if v < 1000 then
		if v % 1 == 0 then
			out = tostring(math.floor(v))
		else
			out = trimZeros(string.format("%.1f", v))
		end
	else
		local i = math.floor(math.log10(v) / 3)
		i = math.min(i, #SUFFIXES - 1)
		local scaled = v / (10 ^ (i * 3))
		local decimals = if scaled < 10 then 2 elseif scaled < 100 then 1 else 0
		out = trimZeros(string.format("%." .. decimals .. "f", scaled)) .. SUFFIXES[i + 1]
	end
	return (if neg then "-" else "") .. out
end

-- 1234567 -> "1,234,567"
function Format.Commas(n: number?): string
	local s = tostring(math.floor(tonumber(n) or 0))
	local neg = string.sub(s, 1, 1) == "-"
	if neg then
		s = string.sub(s, 2)
	end
	local formatted = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return (if neg then "-" else "") .. formatted
end

-- 65 -> "1:05", 3700 -> "1h 1m"
function Format.Time(seconds: number?): string
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	if s >= 3600 then
		return string.format("%dh %dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

function Format.Percent(mult: number, decimals: number?): string
	local pct = (mult - 1) * 100
	local d = decimals or (if math.abs(pct) < 10 then 1 else 0)
	return (if pct >= 0 then "+" else "") .. trimZeros(string.format("%." .. d .. "f", pct)) .. "%"
end

function Format.Mult(mult: number): string
	if mult >= 1000 then
		return "x" .. Format.Abbrev(mult)
	end
	return "x" .. trimZeros(string.format("%.2f", mult))
end

return Format
