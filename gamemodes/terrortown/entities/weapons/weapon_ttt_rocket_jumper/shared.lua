---- Rocket Jumper SWEP

--- Credits:
-- BeeJay28 (Rocket-Jump connoisseur, Main Developer)
-- James (Good friend, helped me test a lot, knows his "source" stuff better than me)
-- EntranceJew (Nice guy, contributed quality of life changes, bugfix, reload-mechanic and some Gmod education to yours truly)

-- First some standard GMod stuff
if SERVER then
	AddCSLuaFile()

	resource.AddFile("materials/vgui/ttt/rocketjumper_icon.vmt")
end

-- Equipment menu information is only needed on the client
if CLIENT then

	-- Text shown in the equip menu
	SWEP.EquipMenuData = {
		type = "item_weapon",
		name = "Rocket Jumper",
		desc = "LMB: Launch into the air\nLMB again: Melee another player while midair to CRIT",
	}

	-- Path to the icon material
	SWEP.Icon = "vgui/ttt/rocketjumper_icon.vtf"

	SWEP.PrintName = "Rocket Jumper"
	SWEP.Instructions = "LMB off the ground, melee another player while midair to CRIT"

	SWEP.ViewModelFOV  = 65
	SWEP.ViewModelFlip = false

	SWEP.DrawAmmo = false
	SWEP.DrawCrosshair = false
end


local VM_JUMPER = 0
local VM_GARDEN = 1

-- Always derive from weapon_tttbase.
SWEP.Base				 = "weapon_tttbase"

--- Standard GMod values

SWEP.HoldType			 = "rpg"
SWEP.HoldType1			 = "melee"

SWEP.Primary.Delay       = 0.08
SWEP.Primary.Automatic   = true
SWEP.Primary.Ammo        = "none"
SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1

SWEP.Primary.HitSound = Sound("Critical_Hit.mp3")
SWEP.Primary.MissSound = Sound("Weapon_Crowbar.Single")

SWEP.Secondary.Automatic = true

SWEP.DeploySpeed = 12

SWEP.ViewModel  = "models/weapons/v_rpg.mdl"
SWEP.ViewModel0  = "models/weapons/v_rpg.mdl"
SWEP.ViewModel1  = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_rocket_launcher.mdl"
SWEP.WorldModel0 = "models/weapons/w_rocket_launcher.mdl"
SWEP.WorldModel1 = "models/weapons/w_crowbar.mdl"

local shootSound = Sound( "Weapon_Crossbow.Single" )

--- Parameters
local thrustSpeed = 1000
local traceRange = 200
-- gardener:
local hitboxRange = 120
local damageValue = 1000
local dropCheckInterval = 0.1
local meleeSwingDelay = 0.05
local swapSpeed = 4
local deployUrgency = 100
local gardenerExtents = 10
local meleeForce = 5
local deployLag = 3

-- Make sure this is equal to their lua-filenames
local jumperWeaponString = "weapon_ttt_rocket_jumper"


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

local ttt_rocket_jumper_muh_skill_ceiling = CreateConVar(
	"ttt_rocket_jumper_muh_skill_ceiling", "0", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED,
	"allow players to spam shots by rapidly clicking their mouse, what an epic display of video game skill"
)

local function GetAimedAtVector(ply)
	local worldShootPos = ply:GetShootPos()
	local viewTargetPos = ply:GetAimVector() * traceRange
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

local function IsJumping(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:HasWeapon(jumperWeaponString)
end

function SWEP:SetupDataTables()
	self:NetworkVar( "Bool", "IsJumper" )
	self:NetworkVar( "Bool", "FireKeyReleased" )
	self:NetworkVar( "Float", "GroundedTime" )
end

function SWEP:Initialize()
	self:SetIsJumper(true)
	if CLIENT then
		self:RefreshTTT2HUDHelp()
	end
end

function SWEP:GetActiveViewModelIndex()
	return not self:GetIsJumper() and VM_GARDEN or VM_JUMPER
end

function SWEP:Equip(ply)
	ply:SelectWeapon(self:GetClass())
end

-- jumper attack
function SWEP:PrimaryAttack()
	if ttt_rocket_jumper_muh_skill_ceiling:GetBool() and not self:GetFireKeyReleased() then
		return
	end

	if self:GetIsJumper() then
		self:JumperFire()
	else
		self:GardenerSwing()
	end
end

-- M2 is equivalent to R+M1 but doesn't pull the melee out
function SWEP:SecondaryAttack()
	if ttt_rocket_jumper_muh_skill_ceiling:GetBool() and not self:GetFireKeyReleased() then
		return
	end

	if CurTime() < self:GetNextPrimaryFire() then
		return
	end

	if not self:GetIsJumper() then
		self:BecomeJumper()
	end

	self:JumperFire(true)
end

function SWEP:Reload()
	if not self:GetIsJumper() then
		self:BecomeJumper()
	end
end

function SWEP:JumperFire(secondary)
	local ply = self:GetOwner()

	if not (IsValid(ply) and ply:IsPlayer()) then
		return
	end

	ply:LagCompensation(true)
	local worldTargetPos, isInRange = GetAimedAtVector(ply)
	ply:LagCompensation(false)

	if isInRange then
		local addvel = ply:GetAimVector()

		addvel:Mul(-thrustSpeed)

		-- +50% self-knockback while crouched like in tf2
		if not ply:IsFlagSet(FL_DUCKING	+ FL_ANIMDUCKING) then
			addvel:Div(1.5)
		end

		ply:SetLocalVelocity(ply:GetVelocity() + addvel)

		ply:RemoveFlags( FL_ONGROUND )

		if SERVER then
			spawnExplosion(worldTargetPos)
		end

		self:EmitSound(shootSound)

		if secondary then
			self:SendViewModelAnim(ACT_VM_PRIMARYATTACK, VM_JUMPER )
		else
			self:SendViewModelAnim(ACT_RANGE_ATTACK_RPG, VM_JUMPER )
			self:BecomeGardener()
		end

		ply:SetAnimation(PLAYER_ATTACK1)

		if ttt_rocket_jumper_muh_skill_ceiling:GetBool() then
			self:SetNextPrimaryFire( CurTime() )
		else
			self:SetNextPrimaryFire( CurTime() + 0.5 )
		end

		self:SetFireKeyReleased(false)
	end
end

function SWEP:GardenerSwing()
	local ply = self:GetOwner()

	ply:LagCompensation(true)

	local shootPos = ply:GetShootPos()
	local endShootPos = (ply:GetAimVector() * hitboxRange) + shootPos
	local tMin = Vector(1, 1, 1) * -gardenerExtents
	local tMax = Vector(1, 1, 1) * gardenerExtents

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
			mins = tMin,
			maxs = tMax
		})
	end

	ply:LagCompensation(false)

	local hitEnt = tr.Entity

	if (IsValid(hitEnt) and (hitEnt:IsPlayer() or hitEnt:IsNPC())) then
		self:SendViewModelAnim(ACT_VM_HITCENTER, VM_GARDEN)
		ply:SetAnimation(PLAYER_ATTACK1)

		if SERVER then
			timer.Simple(meleeSwingDelay, function ()
				local dmg = DamageInfo()
				dmg:SetDamage(damageValue)
				dmg:SetAttacker(ply)
				if IsValid(self) then dmg:SetInflictor(self) end
				dmg:SetDamageForce(ply:GetAimVector() * meleeForce)
				dmg:SetDamagePosition(ply:GetPos())
				dmg:SetDamageType(DMG_CLUB)

				hitEnt:TakeDamageInfo(dmg)
			end)
		end
		self:EmitSound(self.Primary.HitSound)

	else
		self:SendViewModelAnim(ACT_VM_MISSCENTER, VM_GARDEN)
		ply:SetAnimation(PLAYER_ATTACK1)

		self:EmitSound(self.Primary.MissSound)
	end

	if ttt_rocket_jumper_muh_skill_ceiling:GetBool() then
		self:SetNextPrimaryFire( CurTime() )
	else
		self:SetNextPrimaryFire( CurTime() + 0.5 )
	end

	self:SetFireKeyReleased(false)
end

function SWEP:BecomeGardener()
	self:SetIsJumper(false)

	self.WorldModel = self.WorldModel1
	self:SetModel( self.WorldModel )
	-- lil hack to simulate jumper holster anim
	self:SendViewModelAnim( ACT_VM_DRAW, VM_JUMPER, -swapSpeed)
	self:SendViewModelAnim( ACT_VM_DRAW , VM_GARDEN)
	self:SetHoldType("melee")
	if CLIENT then
		self:RefreshTTT2HUDHelp()
	end
end

function SWEP:BecomeJumper()
	self:SetIsJumper(true)

	self.WorldModel = self.WorldModel0
	self:SetModel( self.WorldModel )
	self:SendViewModelAnim( ACT_VM_HOLSTER, VM_GARDEN, swapSpeed)
	self:SendViewModelAnim( ACT_VM_DRAW, VM_JUMPER, swapSpeed)
	self:SetHoldType("rpg")
	if CLIENT then
		self:RefreshTTT2HUDHelp()
	end
end

function SWEP:Deploy()
	self:SetFireKeyReleased(true)

	if not self:GetIsJumper() then
		self:SetNextPrimaryFire(CurTime() + dropCheckInterval * deployLag)
	end

	local ply = self:GetOwner()
	if not IsValid(ply) then return end
	local vm1 = ply:GetViewModel( VM_GARDEN )
	if ( IsValid( vm1 ) ) then
		--associate its weapon to us
		vm1:SetWeaponModel( self.ViewModel1, self )
	end

	if self:GetIsJumper() then
		self:SendViewModelAnim( ACT_VM_HOLSTER, VM_GARDEN, swapSpeed * deployUrgency )
	else
		self:SendViewModelAnim( ACT_VM_DRAW, VM_JUMPER, -swapSpeed * deployUrgency )
	end

	return true
end

function SWEP:Holster()
	local ply = self:GetOwner()
	if not IsValid(ply) then return end
	local vm1 = ply:GetViewModel( VM_GARDEN )
	if ( IsValid( vm1 ) ) then
		--set its weapon to nil, this way the viewmodel won't show up again
		vm1:SetWeaponModel( self.ViewModel1 , nil )
	end

	return true
end

function SWEP:SendViewModelAnim( act , index , rate )
	local vm = self:GetOwner():GetViewModel( index )

	if ( not IsValid( vm ) ) then
		return
	end

	local seq = vm:SelectWeightedSequence( act )

	if ( seq == -1 ) then
		return
	end

	vm:SendViewModelMatchingSequence( seq )
	vm:SetPlaybackRate( rate or 1 )
end

function SWEP:Think()
	local ply = self:GetOwner()

	if IsValid(ply) and ply:IsPlayer() and (ply:KeyReleased(IN_ATTACK) or ply:KeyReleased(IN_ATTACK2)) then
		self:SetFireKeyReleased(true)
	end

	-- this lets people bhop to retain the market gardener crit like in tf2

	if not IsValid(ply) or self:GetIsJumper() or not (ply:OnGround() or ply:WaterLevel() ~= 0) then
		if self:GetGroundedTime() ~= 0 then
			self:SetGroundedTime(0)
		end

		return
	end

	self:SetGroundedTime(self:GetGroundedTime() + FrameTime())

	if self:GetGroundedTime() > 0.05 then
		self:SetGroundedTime(0)
		self:BecomeJumper()
	end
end

function SWEP:RefreshTTT2HUDHelp()
	if not self.AddHUDHelpLine then
		-- base ttt doesnt have this function
		return
	end

	self.HUDHelp = {
		bindingLines = {},
		maxLength = 0
	}

	if not self:GetIsJumper() then
		self:AddHUDHelpLine("rocket_jumper_primary", Key("+attack", "MOUSE1"))
	else
		self:AddHUDHelpLine("market_gardener_primary", Key("+attack", "MOUSE1"))
		self:AddHUDHelpLine("market_gardener_cancel", Key("+reload", "R"))
	end
end

if SERVER then
	-- rocket jumper logic
	hook.Add("EntityTakeDamage", "rocket_jumper__NoFallDamage", function (target, dmgInfo)
		local inflictor = dmgInfo:GetInflictor()

		if (IsJumping(target) and dmgInfo:IsFallDamage())
		or (IsJumping(inflictor) and dmgInfo:IsDamageType(DMG_CRUSH)) then
			dmgInfo:SetDamage(0)
		end
	end)
end