AddCSLuaFile()

ENT.Base = "base_gmodentity"
ENT.AdminOnly = true
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true
ENT.Spawnable = false

if CLIENT then return end

function ENT:Initialize()
	self:SetModel("models/hunter/misc/sphere1x1.mdl")
	self:SetMaterial("models/flesh")
	self:SetSolid(SOLID_VPHYSICS)
	self:PhysicsInit(SOLID_VPHYSICS)

	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then return end

	phys:EnableMotion(false)
end

function ENT:StartTouch(ent)
	if not IsValid(ent) then return end

	if ent:IsPlayer() then
		ent:Kill()
	elseif ent:IsNPC() then
		ent:TakeDamage(ent:Health(), ent, ent)
	else
		return
	end

	ent:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav")

	timer.Simple(0.1, function()
		if not IsValid(self) then return end
		PermIll.AddScale(self, 0.025)
	end)
end

local size, bounces = 4, 10
local mins = Vector(-size, -size, -size)
local maxs = Vector(size, size, size)

local function localRandomPos(ent)
	local found = ent:GetPos()
	local dir = VectorRand():GetNormalized()
	local valid = true

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

function ENT:Think()
	if #ents.FindByClass("ill_node") >= 1000 then
		self.DONE = true
	end

	if self:GetNWFloat("permanent_illness", 0.1) < 1 or self.DONE then
		self:NextThink(CurTime() + 100)
		return true
	end

	self:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav")

	self.DONE = true

	for i = 1, 2 do
		local ent = ents.Create("ill_node")
		ent:SetPos(localRandomPos(self))
		ent:Spawn()

		PermIll.SetScale(ent, 0.1)

		ent:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav")
	end

	self:NextThink(CurTime() + 100)
	return true
end