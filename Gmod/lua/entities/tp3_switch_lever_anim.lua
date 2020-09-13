AddCSLuaFile()
DEFINE_BASECLASS("tp3_base_prop")
ENT.PrintName = "Trakpak3 Switch Stand (Animated)"
ENT.Author = "Magnum MacKivler"
ENT.Purpose = "Change Switches/Squash Toes"
ENT.Instructions = "Place in Hammer"
ENT.AutomaticFrameAdvance = true

if SERVER then
	ENT.KeyValueMap = {
		model = "string",
		bodygroups = "string",
		skin = "number",
		seq_idle_close = "string",
		seq_idle_open = "string",
		seq_throw_close = "string",
		seq_throw_open = "string",
		behavior = "number",
		autoreset = "boolean",
		
		bodygroups_closed = "string",
		bodygroups_motion = "string",
		bodygroups_open = "string",
		
		OnUse = "output",
		OnThrownMain = "output",
		OnThrownDiverging = "output"
	}
	
	function ENT:Initialize()
		self:ValidateNumerics()
		
		--Model/Physics Init
		self:SetModel(self.model)
		self:PhysicsInitStatic(SOLID_VPHYSICS)
		self:SetSkin(self.skin)
		if self.bodygroups then self:SetBodygroups(self.bodygroups) end
		
		--transform sequences into ID numbers for faster usage
		self.seq_idle_close = self:LookupSequence(self.seq_idle_close)
		self.seq_idle_open = self:LookupSequence(self.seq_idle_open)
		self.seq_throw_open, self.dur_throw_open = self:LookupSequence(self.seq_throw_open)
		self.seq_throw_close, self.dur_throw_close = self:LookupSequence(self.seq_throw_close)
		
		timer.Simple(1,function() self:ResetSequence(self.seq_idle_close) end)
		
		self.animate = self.seq_idle_close and self.seq_idle_open and self.seq_throw_close and self.seq_throw_open
		self.state = false
		self.targetstate = false
		self.animating = false
		
		self:SetUseType(SIMPLE_USE)
		
		--Store old pos and ang
		self.originalpos = self:GetPos()
		self.originalang = self:GetAngles()
		
		--find max frame for animation plot
		if Trakpak3.SwitchStandPlots and Trakpak3.SwitchStandPlots[self.model] then
			self.Plot = Trakpak3.SwitchStandPlots[self.model]
			self.MaxFrame = self.Plot[#self.Plot][1] or 0
		end
		
		--Wire I/O
		if WireLib then
			local names = {"ThrowMain","ThrowDiverging","ThrowToggle","Throw"}
			local types = {"NORMAL","NORMAL","NORMAL","NORMAL"}
			local descs = {}
			WireLib.CreateSpecialInputs(self, names, types, descs)
			
			local names = {"Main","Diverging","Blocked","Broken"}
			local types = {"NORMAL","NORMAL","NORMAL","NORMAL"}
			WireLib.CreateSpecialOutputs(self, names, types, descs)
			
			WireLib.TriggerOutput(self,"Main",1)
			WireLib.TriggerOutput(self,"Diverging",0)
			WireLib.TriggerOutput(self,"Blocked",0)
			WireLib.TriggerOutput(self,"Broken",0)
		end
		
		--Initial Broadcast
		hook.Run("TP3_SwitchUpdate",self:GetName(),false)
	end
	
	--Functions called by the switch
	
	--Initial Handshake to link the entities
	function ENT:StandSetup(ent)
		--print("Stand "..self:GetName().." set up with switch "..ent:EntIndex().." with behavior mode "..self.behavior)
		self.switch = ent
		ent:SwitchSetup(self.behavior or 1)
	end
	
	--Force the switch stand to throw to the specified state (a result of trailing)
	function ENT:StandThrowTo(state)
		self:Actuate(state)
	end
	
	--Break the switch stand temporarily (a result of trailing)
	function ENT:StandBreak(state, vel)
		self.targetstate = state
		self.state = state
		self.broken = true
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetCollisionGroup(COLLISION_GROUP_WORLD)
		
		vel = vel or 0
		
		local p1 = math.random(1,2)
		local s_table = {"physics/metal/metal_box_break1.wav", "physics/metal/metal_box_break2.wav"}
		self:EmitSound(s_table[p1])
		
		p1 = math.random(1,4)
		s_table = {"physics/wood/wood_plank_break1.wav","physics/wood/wood_plank_break2.wav","physics/wood/wood_plank_break3.wav","physics/wood/wood_plank_break4.wav"}
		self:EmitSound(s_table[p1])
		--print("Broken switch at "..vel)
		local po = self:GetPhysicsObject()
		po:ApplyForceCenter(po:GetMass()*(Vector(0,0,1) + VectorRand(-0.5,0.5))*vel*0.5)
		po:ApplyTorqueCenter(po:GetMass()*VectorRand()*math.min(vel,200)*0.0625)
		
		--Broadcast
		hook.Run("TP3_SwitchUpdate",self:GetName(),state,true)
		Trakpak3.Dispatch.SendInfo(self:GetName(),"broken",1)
		
		WireLib.TriggerOutput(self,"Broken",1)
		
		timer.Simple(60,function()
			if self.broken then self:StandFix() end
		end)
	end
	
	function ENT:StandFix()
		self.broken = false
		self:SetCollisionGroup(COLLISION_GROUP_NONE)
		self:PhysicsInitStatic(SOLID_VPHYSICS)
		self:SetPos(self.originalpos)
		self:SetAngles(self.originalang)
		
		local p1 = math.random(1,3)
		local s_table = {"physics/wood/wood_box_impact_hard1.wav","physics/wood/wood_box_impact_hard2.wav","physics/wood/wood_box_impact_hard3.wav"}
		self:EmitSound(s_table[p1])
		
		WireLib.TriggerOutput(self,"Broken",0)
		Trakpak3.Dispatch.SendInfo(self:GetName(),"broken",0)
		
		if self.state then self:CompleteThrowDV() else self:CompleteThrowMN() end
	end
	
	--Receive occupancy status
	function ENT:StandSetOccupied(occ)
		if occ then
			Trakpak3.Dispatch.SendInfo(self:GetName(),"blocked",1)
		else
			Trakpak3.Dispatch.SendInfo(self:GetName(),"blocked",0)
		end
		self.occupied = occ
		local occn = 0
		if occ then occn = 1 end
		WireLib.TriggerOutput(self,"Blocked",occn)
		if self.autoreset and self.targetstate then
			self.targetstate = false
		end
	end
	
	
	--Disable Physgun
	function ENT:PhysgunPickup() return false end
	
	--Do these when the throw is completed
	function ENT:CompleteThrowMN()
		self.state = false
		if self.animate then
			self.animating = false
			self:ResetSequence(self.seq_idle_close)
		end
		if WireLib then
			WireLib.TriggerOutput(self,"Main",1)
			WireLib.TriggerOutput(self,"Diverging",0)
		end
		if self.bodygroups_closed then self:SetBodygroups(self.bodygroups_closed) end
		self:TriggerOutput("OnThrownMain",self)
		if self.switch then self.switch:Switch(false) end
		--Broadcast
		hook.Run("TP3_SwitchUpdate",self:GetName(),false)
		Trakpak3.Dispatch.SendInfo(self:GetName(),"state",0)
	end
	
	function ENT:CompleteThrowDV()
		self.state = true
		if self.animate then
			self.animating = false
			self:ResetSequence(self.seq_idle_open)
		end
		if WireLib then
			WireLib.TriggerOutput(self,"Main",0)
			WireLib.TriggerOutput(self,"Diverging",1)
		end
		if self.bodygroups_open then self:SetBodygroups(self.bodygroups_open) end
		self:TriggerOutput("OnThrownDiverging",self)
		if self.switch then self.switch:Switch(true) end
		--Broadcast
		hook.Run("TP3_SwitchUpdate",self:GetName(),true)
		Trakpak3.Dispatch.SendInfo(self:GetName(),"state",1)
	end
	
	--Animate Yourself - should be called after all other state-dependent logic is done!
	function ENT:Actuate(state)
		self.targetstate = state
		if state then --throw it open
			self.state = true
			if self.animate then
				self.animating = true
				self:ResetSequence(self.seq_throw_open)
				WireLib.TriggerOutput(self,"Main",0)
				WireLib.TriggerOutput(self,"Diverging",0)
				
				Trakpak3.Dispatch.SendInfo(self:GetName(),"state",2)
				
				if self.bodygroups_motion then self:SetBodygroups(self.bodygroups_motion) end
				--When throw animation is done:
				timer.Simple(self:SequenceDuration(self.seq_throw_open), function() self:CompleteThrowDV() end)
			else
				self:CompleteThrowDV()
			end
			
			
		else --throw it closed
			self.state = false
			if self.animate then
				self.animating = true
				self:ResetSequence(self.seq_throw_close)
				WireLib.TriggerOutput(self,"Main",0)
				WireLib.TriggerOutput(self,"Diverging",0)
				
				Trakpak3.Dispatch.SendInfo(self:GetName(),"state",2)
				
				if self.bodygroups_motion then self:SetBodygroups(self.bodygroups_motion) end
				--when throw animation is done:
				timer.Simple(self:SequenceDuration(self.seq_throw_close), function() self:CompleteThrowMN() end)
			else
				self:CompleteThrowMN()
			end
		end
	end
	util.AddNetworkString("tp3_switchblocked_notify")
	--Handle animations and throw functions normally
	function ENT:Use(ply)
		if self.broken then
			self:StandFix()
		elseif not self.animating and self.occupied then
			net.Start("tp3_switchblocked_notify")
			net.Send(ply)
		elseif not self.animating then
			self.targetstate = not self.targetstate
		end
	end
	
	function ENT:Think()
		if not self.animating and not self.occupied and (self.state != self.targetstate) then
			self.switch:SwitchThrow(self.targetstate)
			self:Actuate(self.targetstate)
		end
		self:NextThink(CurTime())
		return true
	end
	
	--Hammer Input Handler
	function ENT:AcceptInput( inputname, activator, caller, data )
		if inputname=="ThrowToggle" then
			self.targetstate = not self.targetstate
		elseif inputname=="ThrowMain" then
			self.targetstate = false
		elseif inputname=="ThrowDiverging" then
			self.targetstate = true
		end
	end
	
	--Wire input handler
	function ENT:TriggerInput(iname, value)
		if iname=="ThrowToggle" and value>0 then
			self.targetstate = not self.state
		elseif iname=="ThrowMain" and value>0 then
			self.targetstate = false
		elseif iname=="ThrowDiverging" and value>0 then
			self.targetstate = true
		elseif iname=="Throw" then
			local new = (value>0)
			self.targetstate = new
		end
	end
	
	--Receive DS commands
	hook.Add("TP3_Dispatch_Command", "Trakpak3_DS_Switches", function(name, cmd, val)
		for _, stand in pairs(ents.FindByClass("tp3_switch_lever_anim")) do --For Each Stand,
			--print(stand:GetName(), cmd, val)
			if (name==stand:GetName()) and (cmd=="throw") then
				if val==1 then
					stand.targetstate = true
				else
					stand.targetstate = false
				end
			end
		end
	end)
	
end

if CLIENT then
	net.Receive("tp3_switchblocked_notify", function()
		chat.AddText("[Trakpak3] The switch you are attempting to throw is blocked.")
	end)
end