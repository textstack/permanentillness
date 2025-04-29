sql.Query("CREATE TABLE IF NOT EXISTS permanent_illness ( id INTEGER PRIMARY KEY ON CONFLICT REPLACE, map TEXT, x INTEGER, y INTEGER, z INTEGER, size INTEGER, done INTEGER );")

local curMap = sql.SQLStr(game.GetMap())

local function spawnNode(id, x, y, z, sizeInt, done)
	local ent = ents.Create("ill_node")

	ent:SetPos(Vector(x, y, z))
	ent:Spawn()

	if tonumber(done) ~= 0 then
		ent.DONE = true
	end

	ent.ID = id
	PermIll.SetScale(ent, sizeInt / 1000)
end

local function getSaveData(ent)
	local pos = ent:GetPos()

	local data = {
		pos.x,
		pos.y,
		pos.z,
		math.floor(ent:GetNWFloat("permanent_illness", 0.1) * 1000),
		ent.DONE and 1 or 0,
		curMap
	}

	if ent.ID then
		table.insert(data, ent.ID)
	end

	return "( " .. table.concat(data, ", ") .. " )", not ent.ID
end

-- this is bonyoze code i don't want to bother making my own position locator
local surfs = {}
local size, attempts, bounces = 4, 10, 10
local mins = Vector(-size, -size, -size)
local maxs = Vector(size, size, size)
local function randomPos()
	if table.IsEmpty(surfs) then
		for _, v in ipairs(game.GetWorld():GetBrushSurfaces()) do
			if #v:GetVertices() >= 3 then
				surfs[#surfs + 1] = v
			end
		end

		if table.IsEmpty(surfs) then return vector_zero end
	end

	local found = Vector()

	local indexes = {}
	for i = 1, #surfs do
		indexes[i] = i
	end

	-- find a surface to spawn on
	for i = 1, attempts do
		local num = #indexes
		if num == 0 then break end

		local idx = indexes[math.random(num)]
		table.remove(indexes, idx)

		local surf = surfs[idx]
		local verts = surf:GetVertices()

		local dir = (verts[3] - verts[1]):Cross(verts[2] - verts[1])
		local norm = dir / dir:Length()

		local pos = (verts[1] + verts[2] + verts[3]) / 3

		local start = pos + norm * size * 2

		local tr = util.TraceHull({
			start = start,
			endpos = start,
			mins = mins,
			maxs = maxs,
			mask = MASK_SOLID_BRUSHONLY
		})

		found = tr.HitPos

		if not tr.Hit then break end
	end

	local dir = VectorRand():GetNormalized()
	local valid = true

	-- do some bounces
	for i = 1, bounces + 10 do
		if i > bounces and valid then break end

		local tr = util.TraceHull({
			start = found,
			endpos = found + dir * 32768,
			mins = mins,
			maxs = maxs,
			mask = MASK_SOLID_BRUSHONLY
		})

		local norm = tr.HitNormal

		found = tr.HitPos
		dir = dir - norm * (2 * dir:Dot(norm))
		valid = tr.Hit and not tr.HitNoDraw and not tr.HitSky
	end

	return found
end

local function spawnAllNodes()
	local q = sql.Query(string.format("SELECT * FROM permanent_illness WHERE map = %s;", curMap))
	if not q or table.IsEmpty(q) then
		local ent = ents.Create("ill_node")
		ent:SetPos(randomPos())
		ent:Spawn()

		PermIll.SetScale(ent, 0.1)

		return
	end

	for _, v in pairs(q) do
		spawnNode(v.id, v.x, v.y, v.z, v.size, v.done)
	end
end

local function saveAllNodes()
	local saveData = {}
	local newSaveData = {}

	for _, v in ipairs(ents.FindByClass("ill_node")) do
		local data, new = getSaveData(v)
		if not data then continue end

		if new then
			table.insert(newSaveData, data)
		else
			table.insert(saveData, data)
		end
	end

	if not table.IsEmpty(newSaveData) then
		sql.Query(string.format("INSERT OR REPLACE INTO permanent_illness ( x, y, z, size, done, map ) VALUES %s;", table.concat(newSaveData, ", ")))
	end

	if not table.IsEmpty(saveData) then
		sql.Query(string.format("INSERT OR REPLACE INTO permanent_illness ( x, y, z, size, done, map, id ) VALUES %s;", table.concat(saveData, ", ")))
	end
end

timer.Create("permanent_illness_save", 120, 0, saveAllNodes)

hook.Add("InitPostEntity", "permanent_illness_spawn", function()
	timer.Simple(0, spawnAllNodes)
end)