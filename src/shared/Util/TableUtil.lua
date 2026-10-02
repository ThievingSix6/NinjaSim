local TableUtil = {}

function TableUtil.DeepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t :: any) do
		copy[k] = TableUtil.DeepCopy(v)
	end
	return copy :: any
end

-- Fills in any keys that exist in `template` but are missing from `target`.
-- Used to migrate old save data forward when new fields are added.
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in pairs(template) do
		if target[k] == nil then
			target[k] = TableUtil.DeepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil and #v == 0 then
			-- only recurse into dictionary-style defaults (e.g. Settings, Upgrades)
			TableUtil.Reconcile(target[k], v)
		end
	end
	return target
end

function TableUtil.Count(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function TableUtil.Keys(t: { [any]: any }): { any }
	local out = {}
	for k in pairs(t) do
		table.insert(out, k)
	end
	return out
end

function TableUtil.Find(list: { any }, value: any): number?
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

return TableUtil
