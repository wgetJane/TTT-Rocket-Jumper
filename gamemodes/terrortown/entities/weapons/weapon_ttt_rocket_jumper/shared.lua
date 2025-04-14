---- Rocket Jumper SWEP

--- Credits:
-- BeeJay28 (Rocket-Jump connoisseur, Main Developer)
-- James (Good friend, helped me test a lot, knows his "source" stuff better than me)
-- EntranceJew (Nice guy, contributed quality of life changes, bugfix, reload-mechanic and some Gmod education to yours truly)

-- First some standard GMod stuff
if SERVER then
	AddCSLuaFile()

	resource.AddFile("materials/vgui/ttt/rocketjumper_icon.vmt")
	resource.AddFile("sound/Critical_Hit.mp3")
end

-- Equipment menu information is only needed on the client
if CLIENT then

	-- Text shown in the equip menu
	SWEP.EquipMenuData = {
		type = "item_weapon",
		name = "Rocket Jumper",
		desc = "LMB: Launch into the air\nCrowbar another player while midair to CRIT",
	}

	-- Path to the icon material
	SWEP.Icon = "vgui/ttt/rocketjumper_icon.vtf"

	SWEP.PrintName = "Rocket Jumper"
	SWEP.Instructions = "Switch to crowbar and melee another player while midair to CRIT"

	SWEP.ViewModelFOV  = 65
	SWEP.ViewModelFlip = false

	SWEP.DrawAmmo = false
	SWEP.DrawCrosshair = false
end

-- Always derive from weapon_tttbase.
SWEP.Base				 = "weapon_tttbase"

--- Standard GMod values

SWEP.HoldType			 = "rpg"
SWEP.HoldType1			 = "melee"

SWEP.Primary.Delay       = 0.5
SWEP.Primary.Automatic   = true
SWEP.Primary.Ammo        = "none"
SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1

SWEP.Primary.Sound = Sound("Weapon_Crossbow.Single")

SWEP.DeploySpeed = 12

SWEP.ViewModel  = "models/weapons/v_rpg.mdl"
SWEP.WorldModel = "models/weapons/w_rocket_launcher.mdl"

local ttt_rocket_jumper_crouched_mult = CreateConVar(
	"ttt_rocket_jumper_crouched_mult", "1.5", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED,
	"set to 1.0 if you want knockback while crouched to be the same"
)

local ttt_rocket_jumper_bhop_window = CreateConVar(
	"ttt_rocket_jumper_bhop_window", "0.1", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED
)

local ttt_rocket_jumper_knockback_force = CreateConVar(
	"ttt_rocket_jumper_knockback_force", "1000", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED
)

local ttt_rocket_jumper_trace_distance = CreateConVar(
	"ttt_rocket_jumper_trace_distance", "200", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED
)

local ttt_rocket_jumper_melee_range = CreateConVar(
	"ttt_rocket_jumper_melee_range", "120", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED
)

local ttt_rocket_jumper_melee_damage = CreateConVar(
	"ttt_rocket_jumper_melee_damage", "1000", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED
)


-- Make sure this is equal to their lua-filenames
local jumperWeaponString = "weapon_ttt_rocket_jumper"
local meleeWeaponString = "weapon_zm_improvised"


--- TTT config values

-- Kind specifies the category this weapon is in. Players can only carry one of
-- each. Can be: WEAPON_... MELEE, PISTOL, HEAVY, NADE, CARRY, EQUIP1, EQUIP2 or ROLE.
-- Matching SWEP.Slot values: 0      1       2     3      4      6       7        8
SWEP.Kind = WEAPON_EQUIP1
SWEP.Slot = 6

-- If AutoSpawnable is true and SWEP.Kind is not WEAPON_EQUIP1/2, then this gun can
-- be spawned as a random weapon.
SWEP.AutoSpawnable = false

-- CanBuy is a table of ROLE_* entries like ROLE_TRAITOR and ROLE_DETECTIVE. If
-- a role is in this table, those players can buy this.
SWEP.CanBuy = { ROLE_TRAITOR }

-- InLoadoutFor is a table of ROLE_* entries that specifies which roles should
-- receive this weapon as soon as the round starts. In this case, none.
SWEP.InLoadoutFor = nil

-- If LimitedStock is true, you can only buy one per round.
SWEP.LimitedStock = true

-- If AllowDrop is false, players can't manually drop the gun with Q
SWEP.AllowDrop = true

-- If IsSilent is true, victims will not scream upon death.
SWEP.IsSilent = false

-- If NoSights is true, the weapon won't have ironsights
SWEP.NoSights = true

-- other SWEPs
SWEP.UseHands = true
SWEP.Weight = 5
SWEP.AutoSwitchTo = true
SWEP.AutoSwitchFrom = false
SWEP.Spawnable = false
SWEP.AdminSpawnable = true
SWEP.ShouldDropOnDie = true

local function GetAimedAtVector(ply)
	local worldShootPos = ply:GetShootPos()
	local viewTargetPos = ply:GetAimVector() * ttt_rocket_jumper_trace_distance:GetFloat()
	local tr = util.TraceLine({
		start = worldShootPos,
		endpos = worldShootPos + viewTargetPos,
		filter = ply,
		mask = MASK_NPCSOLID_BRUSHONLY
	})
	local worldTargetPos = worldShootPos + tr.Fraction * viewTargetPos
	return worldTargetPos, tr.Fraction < 1
end

local function spawnExplosion(explosionLocation)
	local exp = ents.Create( "env_explosion" )
	exp:SetPos( explosionLocation )
	exp:Spawn()
	exp:SetKeyValue( "iMagnitude", "0" )
	exp:Fire( "Explode", 0, 0 )
end

function SWEP:Initialize()
	if CLIENT then
		if self.AddHUDHelpLine then
			self.HUDHelp = {
				bindingLines = {},
				maxLength = 0
			}
			self:AddHUDHelpLine(self.Instructions, Key("+reload", "undefined_key"))
		else
			self:AddHUDHelp(self.Instructions, nil, false)
		end
	end

	return self.BaseClass.Initialize(self)
end

function SWEP:PrimaryAttack()
	local ply = self:GetOwner()

	if not (IsValid(ply) and ply:IsPlayer()) then
		return
	end

	ply:LagCompensation(true)
	local worldTargetPos, isInRange = GetAimedAtVector(ply)
	ply:LagCompensation(false)

	if not isInRange then
		return
	end

	local addvel = ply:GetAimVector()

	addvel:Mul(-ttt_rocket_jumper_knockback_force:GetFloat())

	-- +50% self-knockback while crouched like in tf2
	if not ply:IsFlagSet(FL_DUCKING	+ FL_ANIMDUCKING) then
		addvel:Div(ttt_rocket_jumper_crouched_mult:GetFloat())
	end

	ply:SetLocalVelocity(ply:GetVelocity() + addvel)

	ply:SetAnimation(PLAYER_ATTACK1)

	ply:SetNW2Float("ttt_rocket_jumper_groundedtime", 0)
	ply:SetNW2Bool("ttt_rocket_jumper_isblastjumping", true)

	if SERVER then
		spawnExplosion(worldTargetPos)
	end

	self:EmitSound(self.Primary.Sound)

	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
end

function SWEP:SecondaryAttack()
end

function SWEP:Reload()
end

function SWEP:Deploy()
	local ply = self:GetOwner()

	if IsValid(ply) then
		local vm = ply:GetViewModel()

		if IsValid(vm) then
			vm:SetPlaybackRate(2)
		end
	end

	return true
end

function SWEP:Holster()
	return true
end

if CLIENT then
	hook.Add("CreateMove", "ttt_rocket_jumper_ReloadQuickSwitch", function(cmd)
		local ply = LocalPlayer()

		if not (IsValid(ply) and ply:KeyPressed(IN_RELOAD)) then
			return
		end

		local oldwep = ply:GetActiveWeapon()

		if not IsValid(oldwep) then
			return
		end

		local oldclass = oldwep:GetClass()

		local newclass = (
			oldclass == jumperWeaponString and meleeWeaponString
			or oldclass == meleeWeaponString and jumperWeaponString
			or nil
		)

		if not newclass then
			return
		end

		local newwep = ply:GetWeapon(newclass)

		if not IsValid(newwep) then
			return
		end

		cmd:SelectWeapon(newwep)
	end)
end

local function blastjumpproxy(self, name, old, new)
	return self:OnRocketJumperBlastJumpingUpdated(new)
end

if CLIENT then
	hook.Add("InitPostEntity", "ttt_rocket_jumper_InitPostEntity", function()
		LocalPlayer():SetNW2VarProxy("ttt_rocket_jumper_isblastjumping", blastjumpproxy)
	end)
else
	hook.Add("PlayerInitialSpawn", "ttt_rocket_jumper_PlayerInitialSpawn", function(ply)
		ply:SetNW2VarProxy("ttt_rocket_jumper_isblastjumping", blastjumpproxy)
	end)
end

local Player = FindMetaTable("Player")

local MarketGardenerNewPrimaryAttack

function Player:OnRocketJumperBlastJumpingUpdated(isjumping)
	local melee = self:GetWeapon(meleeWeaponString)

	if not IsValid(melee) then
		return
	end

	if isjumping then
		melee:SetDeploySpeed(12)

		if SERVER then
			melee.MarketGardenerOldPrimaryAttack = melee.MarketGardenerOldPrimaryAttack or melee.PrimaryAttack
			melee.PrimaryAttack = MarketGardenerNewPrimaryAttack
		end
	else
		melee:SetDeploySpeed(melee.DeploySpeed or 1.5)

		if SERVER and melee.MarketGardenerOldPrimaryAttack then
			melee.PrimaryAttack = melee.MarketGardenerOldPrimaryAttack
			melee.MarketGardenerOldPrimaryAttack = nil
		end
	end
end

hook.Add("PlayerPostThink", "ttt_rocket_jumper_PlayerPostThink", function(ply)
	-- this lets people bhop to retain the market gardener crit like in tf2

	if not ply:GetNW2Bool("ttt_rocket_jumper_isblastjumping", false) then
		return
	end

	local groundedtime = ply:GetNW2Float("ttt_rocket_jumper_groundedtime", 0)

	if not (ply:OnGround() or ply:WaterLevel() ~= 0) then
		if groundedtime ~= 0 then
			ply:SetNW2Float("ttt_rocket_jumper_groundedtime", 0)
		end

		return
	end

	groundedtime = groundedtime + FrameTime()

	if groundedtime > ttt_rocket_jumper_bhop_window:GetFloat() then
		ply:SetNW2Float("ttt_rocket_jumper_groundedtime", 0)
		ply:SetNW2Bool("ttt_rocket_jumper_isblastjumping", false)
	else
		ply:SetNW2Float("ttt_rocket_jumper_groundedtime", groundedtime)
	end
end)

if CLIENT then
	return
end

local function GardenerSwing(self)
	local ply = self:GetOwner()

	if not IsValid(ply) then
		return
	end

	if not ply:GetNW2Bool("ttt_rocket_jumper_isblastjumping", false) then
		return
	end

	ply:LagCompensation(true)

	local shootPos = ply:GetShootPos()
	local endShootPos = (ply:GetAimVector() * ttt_rocket_jumper_melee_range:GetFloat()) + shootPos

	local tr = util.TraceLine({
		start = shootPos,
		endpos = endShootPos,
		mask = MASK_SHOT_HULL,
		filter = ply
	})

	if not IsValid(tr.Entity) then
		tr = util.TraceHull({
			start = shootPos,
			endpos = endShootPos,
			filter = ply,
			mask = MASK_SHOT_HULL,
			mins = Vector(-12, -12, -12),
			maxs = Vector(12, 12, 12)
		})
	end

	ply:LagCompensation(false)

	local hitEnt = tr.Entity

	if not (IsValid(hitEnt) and (hitEnt:IsPlayer() or hitEnt:IsNPC())) then
		return
	end

	self:SendWeaponAnim(ACT_VM_HITCENTER)
	ply:SetAnimation(PLAYER_ATTACK1)

	timer.Simple(0.05, function()
		if not (IsValid(self) and IsValid(ply) and IsValid(hitEnt)) then
			return
		end

		local wep = ply:GetWeapon("weapon_ttt_rocket_jumper")

		if not IsValid(wep) then
			wep = self
		end

		wep:EmitSound(Sound("Critical_Hit.mp3"))

		if not (IsValid(ply) and IsValid(hitEnt)) then
			return
		end

		local dmg = DamageInfo()
		dmg:SetDamage(ttt_rocket_jumper_melee_damage:GetFloat())
		dmg:SetAttacker(ply)
		dmg:SetInflictor(wep)
		dmg:SetDamageForce(ply:GetAimVector() * 5)
		dmg:SetDamagePosition(ply:GetPos())
		dmg:SetDamageType(DMG_CLUB)

		hitEnt:TakeDamageInfo(dmg)
	end)

	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	return true
end

function MarketGardenerNewPrimaryAttack(self)
	if GardenerSwing(self) then
		return
	end

	return self:MarketGardenerOldPrimaryAttack()
end

hook.Add("EntityTakeDamage", "ttt_rocket_jumper_NoFallDamage", function(victim, dmginfo)
	if victim:IsPlayer() and dmginfo:IsFallDamage() and victim:GetNW2Bool("ttt_rocket_jumper_isblastjumping", false) then
		dmginfo:SetDamage(0)
	end
end)
