local IllNodes = {}

local sizeLimit = 4
local class = "ill_node"

local function getSizeData(ent)
	if IllNodes[ent:EntIndex()] and IllNodes[ent:EntIndex()].size then
		return IllNodes[ent:EntIndex()].size
	end

	local sizedata = {}

	sizedata[1] = 1

	if SERVER then
		sizedata[2], sizedata[3] = ent:GetCollisionBounds()
	else
		sizedata[2], sizedata[3] = ent:GetRenderBounds()
	end

	IllNodes[ent:EntIndex()] = IllNodes[ent:EntIndex()] or { ent = ent }
	IllNodes[ent:EntIndex()].size = sizedata

	return sizedata
end

local function resizePhysics(ent, scale)
	ent:PhysicsInit(SOLID_VPHYSICS)

	local phys = ent:GetPhysicsObject()
	if not IsValid(phys) then return false end

	local physmesh = phys:GetMeshConvexes()
	if not istable(physmesh) or #physmesh < 1 then return false end

	for convexkey, convex in pairs(physmesh) do
		for poskey, postab in pairs(convex) do
			convex[poskey] = postab.pos * scale
		end
	end

	ent:PhysicsInitMultiConvex(physmesh)
	ent:EnableCustomCollisions(true)

	return IsValid(ent:GetPhysicsObject())
end

if SERVER then
	PermIll = PermIll or {}

	util.AddNetworkString("permanent_illness")

	local physData = {}

	local function storePhysicsData(phys)
		physData[1] = phys:IsGravityEnabled()
		physData[2] = phys:GetMaterial()
		physData[3] = phys:IsCollisionEnabled()
		physData[4] = phys:IsDragEnabled()
		physData[5] = phys:GetVelocity()
		physData[6] = phys:GetAngleVelocity()
		physData[7] = phys:IsMotionEnabled()
	end

	local function applyPhysicsData(phys)
		phys:EnableGravity(physData[1])
		phys:SetMaterial(physData[2])
		phys:EnableCollisions(physData[3])
		phys:EnableDrag(physData[4])
		phys:SetVelocity(physData[5])
		phys:AddAngleVelocity(physData[6] - phys:GetAngleVelocity())
		phys:EnableMotion(physData[7])
	end

	local meta = FindMetaTable( "Entity" )

	local oldStartMotionController = meta.StartMotionController
	meta.StartMotionController = function(ent)
		oldStartMotionController(ent)
		ent.IsMotionControlled = true
	end

	local oldStopMotionController = meta.StopMotionController
	meta.StopMotionController = function(ent)
		oldStopMotionController(ent)
		ent.IsMotionControlled = nil
	end

	local function setScale(ent, scale)
		scale = math.Clamp(scale, 1, sizeLimit)

		local phys = ent:GetPhysicsObject()
		if not IsValid(phys) then return end

		local sizedata = getSizeData(ent)
		local sizediff = scale / sizedata[1]
		sizedata[1] = scale

		if sizediff == 1 then return end

		storePhysicsData(phys)
		local mass = phys:GetMass()

		local success = resizePhysics(ent, scale)
		if not success then return end

		phys = ent:GetPhysicsObject()

		ent:SetCollisionBounds(sizedata[2] * scale, sizedata[3] * scale)

		phys:SetMass(math.Clamp(mass * sizediff^2, 0.1, 50000))
		phys:SetDamping(0, 0)

		applyPhysicsData(phys)

		phys:Wake()

		if ent.IsMotionControlled then
			oldStartMotionController(ent)
		end

		ent:SetNWFloat("permanent_illness", scale)

		net.Start("permanent_illness")
		net.WriteEntity(ent)
		net.WriteFloat(scale)
		net.Broadcast()

		duplicator.StoreEntityModifier(ent, "permanent_illness", { scale })
	end
	PermIll.SetScale = setScale

	local function addScale(ent, add)
		local sizedata = getSizeData(ent)
		setScale(ent, sizedata[1] * (1 + add))
	end
	PermIll.AddScale = addScale

	timer.Create("permanent_illness", 30, 0, function()
		for k, v in pairs(IllNodes) do
			if not IsValid(v.ent) then
				IllNodes[k] = nil
				continue
			end

			if v.ent:IsPlayerHolding() then continue end
			if constraint.HasConstraints(v.ent) then continue end

			local phys = v.ent:GetPhysicsObject()
			if not IsValid(phys) or not phys:IsMotionEnabled() then continue end

			local isVisible
			for _, ply in player.Iterator() do
				if v.ent:TestPVS(ply) then
					isVisible = true
					break
				end
			end
			if isVisible then continue end

			addScale(v.ent, 0.025)
		end
	end)

	duplicator.RegisterEntityModifier("permanent_illness", function(_, ent, data)
		if ent:GetClass() ~= class then return end
		setScale(ent, data[1])
	end)
else
	local function setScale(ent, scale)
		scale = math.Clamp(scale, 1, sizeLimit)

		local sizedata = getSizeData(ent)
		local sizediff = scale / sizedata[1]
		sizedata[1] = scale

		if sizediff == 1 then return end

		local m = Matrix()
		m:Scale(Vector(scale, scale, scale))
		ent:EnableMatrix("RenderMultiply", m)

		ent:SetRenderBounds(sizedata[2] * scale, sizedata[3] * scale)
		ent:DestroyShadow()

		local success = resizePhysics(ent, scale)
		if not success then return end

		local phys = ent:GetPhysicsObject()

		phys:SetPos(ent:GetPos())
		phys:SetAngles(ent:GetAngles())
		phys:EnableMotion(false)
		phys:Sleep()
	end

	net.Receive("permanent_illness", function()
		local ent = net.ReadEntity()
		local scale = net.ReadFloat()
		if IsValid(ent) then
			ent:SetNWFloat("permanent_illness", scale)
			setScale(ent, scale)
		end
	end)

	timer.Create("permanent_illness", 10, 0, function()
		for k, v in pairs(IllNodes) do
			if not IsValid(v.ent) then
				IllNodes[k] = nil
				continue
			end

			local scale = v.ent:GetNWFloat("permanent_illness", -1)
			if scale == -1 then continue end

			setScale(v.ent, scale)
		end
	end)

	hook.Add("Think", "permanent_illness", function()
		for k, v in pairs(IllNodes) do
			if not IsValid(v.ent) then
				IllNodes[k] = nil
				continue
			end

			if v.ent:IsDormant() then continue end

			local phys = v.ent:GetPhysicsObject()
			if not IsValid(phys) then continue end

			phys:SetPos(v.ent:GetPos())
			phys:SetAngles(v.ent:GetAngles())
			phys:EnableMotion(false)
			phys:Sleep()
		end
	end)
end

hook.Add("OnEntityCreated", "permanent_illness", function(ent)
	if ent:GetClass() ~= class then return end

	local id = ent:EntIndex()

	IllNodes[id] = IllNodes[id] or { ent = ent }
	ent:CallOnRemove("permanent_illness", function()
		IllNodes[id] = nil
	end)
end)