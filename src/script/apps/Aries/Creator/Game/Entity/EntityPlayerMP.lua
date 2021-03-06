--[[
Title: entity player multiplayer
Author(s): LiXizhi
Date: 2014/6/29
Desc: a player entity on the server side. it will send update to clients. 
on the server, each client player and the main player on the server is from this class.
In case of the main player on server, self.playerNetServerHandler is nil.
use the lib:
------------------------------------------------------------
NPL.load("(gl)script/apps/Aries/Creator/Game/Entity/EntityPlayerMP.lua");
local EntityPlayerMP = commonlib.gettable("MyCompany.Aries.Game.EntityManager.EntityPlayerMP")
-------------------------------------------------------
]]
NPL.load("(gl)script/apps/Aries/Creator/Game/Entity/EntityPlayer.lua");
local Packets = commonlib.gettable("MyCompany.Aries.Game.Network.Packets");
local TableCodec = commonlib.gettable("commonlib.TableCodec");
local BlockEngine = commonlib.gettable("MyCompany.Aries.Game.BlockEngine")
local block_types = commonlib.gettable("MyCompany.Aries.Game.block_types")
local GameLogic = commonlib.gettable("MyCompany.Aries.Game.GameLogic")
local EntityManager = commonlib.gettable("MyCompany.Aries.Game.EntityManager");
local PlayerSkins = commonlib.gettable("MyCompany.Aries.Game.EntityManager.PlayerSkins")
local ChunkLocation = commonlib.gettable("MyCompany.Aries.Game.Common.ChunkLocation");
local Desktop = commonlib.gettable("MyCompany.Aries.Creator.Game.Desktop");

local Entity = commonlib.inherit(commonlib.gettable("MyCompany.Aries.Game.EntityManager.EntityPlayer"), commonlib.gettable("MyCompany.Aries.Game.EntityManager.EntityPlayerMP"));
-- class name
Entity.class_name = "PlayerMP";
EntityManager.RegisterEntityClass(Entity.class_name, Entity);

-- player is always framemoved as fast as possible
Entity.framemove_interval = 0.03;

function Entity:ctor()
	self.sleepTimer = 0;
	self.rotationPitch = 0;
	-- array of entityId which are untracked since last tick, we will need to inform the client to remove it. 
	self.destroyedItemsNetCache = commonlib.UnorderedArraySet:new();
	-- for newly loaded chunks, we will need to send full map chunk data in that chunk to the player. 
	self.loadedChunks = commonlib.vector:new();
	self.motionX = 0;
	self.motionY = 0;
	self.motionZ = 0;
	self.managedPosBX = 0;
	self.managedPosBZ = 0;
end

function Entity:init(username, world)
	self.username = username or "";
	self.name = "__MP__"..self.username;
	self.worldObj = world; -- Entity._super.init(self, world);
	local x, y, z = world:GetSpawnPoint();
	self:SetLocationAndAngles(x, y, z, 0, 0);
	self:SetDisplayName(self.username);
	-- self.skin = EntityManager.PlayerSkins:GetSkinByID(2);
	self:CreateInnerObject();
	self:RefreshClientModel();
	return self;
end

function Entity:IsShowHeadOnDisplay()
	return true;
end

-- this is message from administrator:
-- @param chatmsg: ChatMessage or string. 
function Entity:SendChatMsg(chatmsg, chatdata)
	local packet_Chat = Packets.PacketChat:new():Init(chatmsg, chatdata)
	packet_Chat.text = self:GetUserName()..": "..packet_Chat.text;
	chat_msg = packet_Chat:ToChatMessage();
	Desktop.GetChatGUI():PrintChatMessage(chat_msg);
	self.worldObj:GetServerManager():SendChatMsg(chat_msg);
	return true;
end

function Entity:KickPlayerFromServer(reason)
	if(self.playerNetServerHandler) then
		self.playerNetServerHandler:KickPlayerFromServer("You logged in from another location");
	end
end

function Entity:CreateInnerObject(...)
	local obj = Entity._super.CreateInnerObject(self, self:GetMainAssetPath(), true, 0, 1);

	if(self:IsShowHeadOnDisplay()) then
		System.ShowHeadOnDisplay(true, obj, self:GetDisplayName(), GameLogic.options.NPCHeadOnTextColor);	
	end
	return obj;
end

function Entity:MountEntity(targetEntity)
	Entity._super.MountEntity(self, targetEntity);
	if(self.playerNetServerHandler) then
		self.playerNetServerHandler:SendPacketToPlayer(Packets.PacketAttachEntity:new():Init(0, self, self.ridingEntity));
		self.playerNetServerHandler:SetPlayerLocation(self.x, self.y, self.z, self.facing, self.rotationPitch);
	end
end

-- make player always sentient
function Entity:IsAlwaysSentient()
	return true;
end

function Entity:MountEntityAndWakeUp()
    if (self.riddenByEntity) then
        self.riddenByEntity:MountEntity(self);
    end
    if (self.sleeping) then
        self:WakeUpPlayer(true, false, false);
    end
end

function Entity:GetWorldServer()
    return self.worldObj;
end

function Entity:SetServerHandler(serverHandler)
	self.playerNetServerHandler = serverHandler;
end

function Entity:GetServerHandler()
	return self.playerNetServerHandler;
end

-- Wake up the player if they're sleeping.
function Entity:WakeUpPlayer(bResetSleepTime, bUpdateSleepFlag, bSpawnInChunk)
    if (self:IsPlayerSleeping()) then
        self:GetWorldServer():GetEntityTracker():SendPacketToAllAssociatedPlayers(self, Packets.PacketAnimation:new():Init(self, 3));
    end

    Entity._super.WakeUpPlayer(self, bResetSleepTime, bUpdateSleepFlag, bSpawnInChunk);

    if (self.playerNetServerHandler) then
		self.playerNetServerHandler:SetPlayerLocation(self.x, self.y, self.z, self.facing, self.rotationPitch);
    end
end

-- on recieving this message the client (if permission is given) will download the requested textures
function Entity:RequestTexturePackLoad(texture_pack)
	self:SendPacketToPlayer(Packets.PacketCustomPayload:new():Init("PC|TexturePack", texture_pack));
end

-- called when server received the move packet from client
function Entity:OnUpdateEntity()
	Entity._super.OnUpdate(self);
	-- TODO: send addtional info to clients
end

-- @param animId: 4 for sneaking, 5 is running. 0 is standing, etc. 
function Entity:SetEntityAction(animId)
	if(animId) then
		self:SetAnimId(animId);
		self:SetSneaking(animId == 4 or animId == 66);
	end
end

function Entity:GetEntityAction(animId)
	return self:GetAnimId();
end

-- attach to entity manager
function Entity:Attach()
	Entity._super.Attach(self);
	self:GetWorldServer():AddPlayerEntity(self);
end

function Entity:Detach()
	Entity._super.Detach(self);
	self:GetWorldServer():RemovePlayerEntity(self);
end

-- only called when this is the admin(pure server side) player, such as a player controlled admin entity. 
function Entity:OnUpdateServerPlayer()
	
end


-- update the entity's position and logic per tick.
-- the actually framemove is in NetServerHandler:handleMove, so here we just send cached changes to client. 
function Entity:OnUpdate()
	if(not self.playerNetServerHandler) then
		self:OnUpdateServerPlayer();
	end

    if (#(self.destroyedItemsNetCache) >0) then
        local entity_ids = {};
        for i=1, #(self.destroyedItemsNetCache) do
            entity_ids[#entity_ids+1] = self.destroyedItemsNetCache[i];
        end
		self:SendPacketToPlayer(Packets.PacketDestroyEntity:new():Init(entity_ids));
		
		self.destroyedItemsNetCache:clear();
    end

    if (not self.loadedChunks:empty()) then
        local chunkList = commonlib.vector:new();
        local tileEntities = commonlib.vector:new();

		local index = 1;
		local chunkIndex = self.loadedChunks:first();
        while ( chunkIndex and #chunkList<5) do
			self.loadedChunks:removeByValue(chunkIndex);
			local chunkPos = ChunkLocation:FromPackedChunkPos(chunkIndex);
			local chunk = self:GetWorldServer():GetChunkFromChunkCoords(chunkPos.chunkX, chunkPos.chunkZ);
			if(chunk) then
				chunkList:add(chunk);
				tileEntities:AddAll(self:GetWorldServer():GetBlockEntityList(chunkPos.chunkX * 16, 0, chunkPos.chunkZ * 16, chunkPos.chunkX * 16 + 16, 256, chunkPos.chunkZ * 16 + 16));
			end
            chunkIndex = self.loadedChunks:first();
        end

        if (not chunkList:empty()) then
            self:SendPacketToPlayer(Packets.PacketMapChunks:new():Init(chunkList));
            
			for i, entity in ipairs(tileEntities) do
				self:SendBlockEntityToPlayer(entity);
			end

            for i, chunk in ipairs(chunkList) do
                self:GetWorldServer():GetEntityTracker():TrySendEventInChunkToPlayer(self, chunk);
            end
        end
    end
end

function Entity:UpdateEntityActionState()
	local curAnimId = self:GetAnimId();
	if(self.lastAnimId ~= curAnimId and curAnimId) then
		self.lastAnimId = curAnimId;
		local obj = self:GetInnerObject();
		if(obj) then
			obj:SetField("AnimID", curAnimId);
		end
	end
	local curSkinId = self:GetSkinId();
	if(self.lastSkinId ~= curSkinId and curSkinId) then
		self.lastSkinId = curSkinId;
		local skin = PlayerSkins:GetSkinByID(curSkinId);
		if(skin) then
			self:SetSkin(skin, true);
		end
	end
end

-- Called in OnUpdate() of Framemove() to frequently update entity state every tick as required. 
function Entity:OnLivingUpdate()
	self:UpdateEntityActionState();
end

function Entity:SendPacketToPlayer(packet)
	if (self.playerNetServerHandler) then
		self.playerNetServerHandler:SendPacketToPlayer(packet);
	end
end

-- called from onUpdate for all tileEntity in specific chunks
function Entity:SendBlockEntityToPlayer(tileEntity)
    if (tileEntity) then
        local packet = tileEntity:GetDescriptionPacket();
        if (packet) then
			self:SendPacketToPlayer(packet);
        end
    end
end


-- Takes in the distance the entity has fallen this tick and whether its on the ground to update the fall distance
-- and deal fall damage if landing on the ground.  
function Entity:UpdateFallState(distanceFallenThisTick, bOnGround)
end

function Entity:UpdateFallStateMP(distanceFallenThisTick, bOnGround)
	return Entity._super.UpdateFallState(self, distanceFallenThisTick, bOnGround);
end