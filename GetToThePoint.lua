local GTTP = {}
local L = GTTPLocals

local origClicks = {}
local buttonIndex = 1

-- Basically this makes sure we can go off the original text
-- so other mods don't affect it
local function setButtonText(...)
	for i=1, select("#", ...), 2 do
		getglobal("GossipTitleButton" .. buttonIndex).originalText = select(i, ...)
		buttonIndex = buttonIndex + 1
	end
end

function GTTP:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99GTTP|r: " .. msg)
end

function GTTP:Initialize()
	if( not GTTP_List ) then
		GTTP_List = { ["manual"] = {} }
	end

	if( not GTTPDB ) then
		GTTPDB = { enabled = true }
	end

	hooksecurefunc("GossipFrameAvailableQuestsUpdate", setButtonText)
	hooksecurefunc("GossipFrameActiveQuestsUpdate", setButtonText)
	hooksecurefunc("GossipFrameOptionsUpdate", setButtonText)
	hooksecurefunc("GossipFrameUpdate", function()
		buttonIndex = 1
	end)
	
	-- Merge all the default quest things in
	for type, quests in pairs(GTTPQuests) do
		if( not GTTP_List[type] ) then
			GTTP_List[type] = {}
		end

		-- Check if any new quests need to be added into the list
		for name, data in pairs(quests) do
			name = string.lower(name)
			if( GTTP_List[type][name] == nil ) then
				GTTP_List[type][name] = data
			end
		end
	end
end

-- Auto skip gossip
local function gossipOnClick(self, ...)
	-- Adding a new skip
	if( IsAltKeyDown() ) then
		-- If it already exists, remove it
		local questName = string.lower(self.originalText)
		for type, quests in pairs(GTTP_List) do
			if( not GTTPDB[type] and quests[questName] ) then
				if( self.type ~= "Gossip" ) then
					GTTP:Print(string.format(L["No longer auto turning in %s."], self.originalText))
				else
					GTTP:Print(string.format(L["No longer auto skipping %s."], self.originalText))
				end
				
				-- Manual can be removed fine, others won't since we want them disabled but not re-enabled
				-- on next log in from a merge
				if( type == "manual" ) then
					quests[questName] = nil
				else
					quests[questName] = false
				end
			end
		end
		
		if( self.type ~= "Gossip" ) then
			GTTP:Print(string.format(L["Now auto turning in %s. Hold ALT and click the option again to remove it."], self.originalText))
			GTTP_List["manual"][questName] = {checkItems = true}
		else
			GTTP:Print(string.format(L["Now auto skipping %s. Hold ALT and click the option again to remove it."], self.originalText))
			GTTP_List["manual"][questName] = true
		end
		return
	end
	
	origClicks[self:GetName()](self, ...)
end

-- Check if we need to auto skip
function GTTP:GOSSIP_SHOW()
	if( not GTTPDB.enabled or not GossipFrame.buttonIndex or IsShiftKeyDown() ) then
		return
	end
	
	for i=1, GossipFrame.buttonIndex do
		local button = getglobal("GossipTitleButton" .. i)
		
		if( not origClicks["GossipTitleButton" .. i] ) then
			origClicks["GossipTitleButton" .. i] = button:GetScript("OnClick")
			button:SetScript("OnClick", gossipOnClick)
		end

		-- Make sure it's a quest we want to skip, and that it's the highest one
		-- So for things like Alterac Valley crystal turn ins
		-- will choose the one with 5 crystals not 1 if need be
		if( button.originalText and self:IsAutoQuest(button.originalText) ) then
			if( button.type == "Available" ) then
				SelectGossipAvailableQuest(i)
			elseif( button.type == "Active" ) then
				SelectGossipActiveQuest(i)
			else
				SelectGossipOption(i)
			end
		end
	end
end

-- Figure out if we need to auto skip this too!
function GTTP:QUEST_PROGRESS()
	if( not GTTPDB.enabled or IsShiftKeyDown() ) then
		return
	end
	
	-- It's got items, do we need to scan them?
	if( GetNumQuestItems() > 0 ) then
		local data, questType
		local questName = string.lower(GetTitleText())
		
		for catType, quests in pairs(GTTP_List) do
			if( quests[questName] ) then
				questType = catType
				break
			end
		end
		
		if( questType ) then
			local items
			
			-- Store how many we need, and the itemid for next time
			-- technically, due to this way you have to complete the quest
			-- yourself the first time, but thats better then storing quest info
			-- for every quest in-game
			for i=1, GetNumQuestItems() do
				local itemLink = GetQuestItemLink("required", i)

				if( itemLink ) then
					local itemid = string.match(itemLink, "|c.+|Hitem:([0-9]+):(.+)|h%[(.+)%]|h|r")
					
					itemid = tonumber(itemid)
					
					if( itemid ) then
						if( not items ) then
							items = {}
						end

						items[itemid] = select(3, GetQuestItemInfo("required", i))
					end
				end
			end
			
			-- If we found no items...and it has items, something bad happened
			if( items ) then
				GTTP_List[questType][questName] = items
			end
		end
	end
	
	-- Alright! Complete
	if( IsQuestCompletable() and self:IsAutoQuest(GetTitleText()) ) then
		QuestFrameCompleteButton:Click()
	end
end

function GTTP:QUEST_COMPLETE()
	if( GTTPDB.enabled and IsQuestCompletable() and self:IsAutoQuest(GetTitleText()) ) then
		QuestFrameCompleteQuestButton:Click()
	end
end

-- Figure out if it's an auto turn in quest
-- and if we can actually complete it
function GTTP:IsAutoQuest(name)
	if( not name ) then
		return nil
	end
	
	name = string.lower(name)

	local questName
	local highestItems
	
	for catType, quests in pairs(GTTP_List) do
		if( not GTTPDB[catType] and quests[name] ) then
			local data = quests[name]
			
			-- No item requirements, so can exit quickly
			if( type(data) ~= "table" ) then
				return true
			elseif( data.checkItems ) then
				return nil
			end
			
			-- Make sure we have the items required for this quest
			for itemid, quantity in pairs(data) do
				if( GetItemCount(itemid) < quantity ) then
					return nil
				end
			end
			
			-- Alright, make sure we have enough items
			questName = name
			highestItems = data
			break
		end
	end
	
	-- Cannot find any quest, or it's disabled
	if( not questName ) then
		return nil
	end
	
	-- I'm fairly sure theres a better way to do this, need to improve it later
	for catType, quests in pairs(GTTP_List) do
		if( not GTTPDB[catType] ) then
			for name, data in pairs(quests) do
				if( name ~= questName and type(data) == "table" and not data.checkItems ) then
					local required = 0
					local found = 0
					
					-- Check it against our saved quests
					for itemid, quantity in pairs(data) do
						required = required + 1

						if( highestItems[itemid] and quantity >= highestItems[itemid] and GetItemCount(itemid) >= quantity ) then
							found = found + 1
						end
					end
										
					-- This quest is higher then ours, so don't auto accept
					if( found >= required ) then
						return nil
					end
				end
			end
		end
	end

	return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
	if( event == "ADDON_LOADED" and addon == "GetToThePoint" ) then
		GTTP.Initialize(GTTP)
	elseif( event ~= "ADDON_LOADED" ) then
		GTTP[event](GTTP)
	end
end)