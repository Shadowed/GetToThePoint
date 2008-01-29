local GTTP = {}
local origClicks = {}
local questList = {}

local CT_SUPPORT = true
local CT_COLOR = {r = 1.0, g = 0.47, b = 0.039}

local L = {
	["No longer auto turning in \"%s\"."] = "No longer auto turning in \"%s\".",
	["No longer auto skipping \"%s\"."] = "No longer auto skipping \"%s\".",
	["No longer auto accepting \"%s\"."] = "No longer auto accepting \"%s\".",
	
	["Now auto accepting \"%s\". Hold CTRL and click the option again to stop auto accepting."] = "Now auto accepting \"%s\". Hold CTRL and click the option again to stop auto accepting.",
	["Now auto skipping \"%s\". Hold ALT and click the option again to remove it."] = "Now auto skipping \"%s\". Hold ALT and click the option again to remove it.",
	["Now auto turning in \"%s\". Hold ALT and click the option again to remove it."] = "Now auto turning in \"%s\". Hold ALT and click the option again to remove it.",
}

-- Tries to deal with incompatabilities that other mods cause
local function stripStupid(text)
	-- Strip [<level crap>] <quest title>
	text = string.gsub(text, "%[(.+)%]", "")
	-- Strip color codes
	text = string.gsub(text, "|c[a-zA-Z0-9][a-zA-Z0-9][a-zA-Z0-9][a-zA-Z0-9][a-zA-Z0-9][a-zA-Z0-9][a-zA-Z0-9][a-zA-Z0-9](.+)|r", "%1")
	-- Strip (low level) at the end of a quest
	text = string.gsub(text, "(.+) %((.+)%)", "%1")
	
	return string.trim(text)
end

function GTTP:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99GTTP|r: " .. msg)
end

function GTTP:Initialize()
	if( not GTTP_List ) then
		GTTP_List = {}
	end
	
	if( not GTTP_Accept ) then
		GTTP_Accept = {}
	end
	
	-- Upgrade
	if( type(GTTP_List.manual) == "table" ) then
		local newList = {}
		for _, quests in pairs(GTTP_List) do
			for name, data in pairs(quests) do
				newList[name] = data
			end
		end
		
		GTTP_List = newList
	end
	
	-- Hook for auto turnin
	local orig_QuestAccept = QuestFrameAcceptButton:GetScript("OnClick")
	QuestFrameAcceptButton:SetScript("OnClick", function(self, ...)
		if( IsControlKeyDown() and GetTitleText() ) then
			local text = stripStupid(GetTitleText())
			local questName = string.lower(text)

			if( GTTP_Accept[questName] ) then
				GTTP:Print(string.format(L["No longer auto accepting \"%s\"."], text))
				GTTP_Accept[questName] = nil
			else
				GTTP:Print(string.format(L["Now auto accepting \"%s\". Hold CTRL and click the option again to stop auto accepting."], text))
				GTTP_Accept[questName] = true		
			end
			return
		end
	

		if( orig_QuestAccept ) then
			orig_QuestAccept(self, ...)
		end
	end)
end

-- Auto skip gossip
local function gossipOnClick(self, ...)
	-- Adding a new skip
	if( IsAltKeyDown() and self:GetText() ) then
		-- If it already exists, remove it
		local text = stripStupid(self:GetText())
		local questName = string.lower(text)
		
		DevTools_Dump(self:GetText())
		DevTools_Dump(text)
		
		if( GTTP_List[questName] ) then
			if( self.type ~= "Gossip" ) then
				GTTP:Print(string.format(L["No longer auto turning in \"%s\"."], text))
			else
				GTTP:Print(string.format(L["No longer auto skipping \"%s\"."], text))
			end
			
			GTTP_List[questName] = nil
		
		-- Gossip doesn't have item requirements
		elseif( self.type == "Gossip" ) then
			GTTP:Print(string.format(L["Now auto skipping \"%s\". Hold ALT and click the option again to remove it."], text))
			GTTP_List[questName] = true

		-- It's not gossip, so it could possibly have item requirements
		else
			GTTP:Print(string.format(L["Now auto turning in \"%s\". Hold ALT and click the option again to remove it."], text))
			GTTP_List[questName] = {checkItems = true}
		end
		
		return
	
	-- Adding new auto acception
	elseif( IsControlKeyDown() and self:GetText() and self.type ~= "Gossip" ) then
		local text = stripStupid(self:GetText())
		local questName = string.lower(text)
		
		if( GTTP_Accept[questName] ) then
			GTTP:Print(string.format(L["No longer auto accepting \"%s\"."], text))
			GTTP_Accept[questName] = nil
		else
			GTTP:Print(string.format(L["Now auto accepting \"%s\". Hold CTRL and click the option again to stop auto accepting."], text))
			GTTP_Accept[questName] = true		
		end
		
		return
	end
	
	origClicks[self:GetName()](self, ...)
end

-- Check if we need to auto skip
function GTTP:GOSSIP_SHOW()
	if( not GossipFrame.buttonIndex or IsShiftKeyDown() ) then
		return
	end
	
	-- Recycle
	for k in pairs(questList) do
		questList[k] = nil
	end
	
	-- List all available quests
	for i=1, GossipFrame.buttonIndex do
		local button = getglobal("GossipTitleButton" .. i)		
		if( not origClicks["GossipTitleButton" .. i] ) then
			origClicks["GossipTitleButton" .. i] = button:GetScript("OnClick")
			button:SetScript("OnClick", gossipOnClick)
		end

		if( button:IsVisible() and button:GetText() ) then
			questList[string.lower(stripStupid(button:GetText()))] = button
		end
	end
	
	-- Now see what to auto skip
	for name, button in pairs(questList) do
		if( self:IsAutoQuest(name, questList) or (button.type == "Available" and GTTP_Accept[name]) ) then
			if( button.type == "Available" ) then
				SelectGossipAvailableQuest(button:GetID())
			elseif( button.type == "Active" ) then
				SelectGossipActiveQuest(button:GetID())
			else
				SelectGossipOption(button:GetID())
			end
			
			return
		end
	end
end

-- Figure out if we need to auto skip this too!
function GTTP:QUEST_PROGRESS()
	if( IsShiftKeyDown() ) then
		return
	end
	
	-- Check if we need to find items
	local questName = string.lower(GetTitleText())

	-- It's got items, do we need to scan them?
	if( GetNumQuestItems() > 0 ) then
		local data = GTTP_List[questName]
		if( type(data) == "table" and data.checkItems ) then
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
				GTTP_List[questName] = items
			end
		end
		
	-- No items required
	elseif( GTTP_List[questName] ) then
		GTTP_List[questName] = true
	end
	
	-- Alright! Complete
	if( not IsShiftKeyDown() and IsQuestCompletable() and self:IsAutoQuest(GetTitleText(), questList) ) then
		CompleteQuest()
	end
end

function GTTP:QUEST_COMPLETE()
	-- Unflag the quest as an item check so it can be auto completed
	local questName = string.lower(GetTitleText())
	local data = GTTP_List[questName]
	if( type(data) == "table" and data.checkItems ) then
		data = true
	end
	
	if( not IsShiftKeyDown() and IsQuestCompletable() and GetNumQuestChoices() == 0 and self:IsAutoQuest(GetTitleText(), questList) ) then
		if( QuestFrameRewardPanel.itemChoice == 0 and GetNumQuestChoices() > 0 ) then
			QuestChooseRewardError()
		else
			PlaySound("igQuestListComplete")
			GetQuestReward(QuestFrameRewardPanel.itemChoice)
		end
	end
end

function GTTP:QUEST_DETAIL()
	if( not IsShiftKeyDown() and GTTP_Accept[string.lower(GetTitleText())] ) then
		AcceptQuest()
	end
end

-- Figure out if it's an auto turn in quest
-- and if we can actually complete it
function GTTP:IsAutoQuest(name, questList)
	if( not name ) then
		return nil
	end
	
	name = string.lower(name)
	
	local data = GTTP_List[name]
	if( not data ) then
		return nil
	end
	
	-- No item requirements, so can exit quickly
	if( type(data) ~= "table" ) then
		return true
	
	-- Need to check items still so don't auto complete
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
	local questName = name
	local highestItems = data
		
	-- I'm fairly sure theres a better way to do this, need to improve it later
	for name, data in pairs(GTTP_List) do
		-- Make sure we aren't checking our own quest, that we have actual items
		-- and that we either don't have a filter, or the quest is in the filter list
		if( name ~= questName and type(data) == "table" and not data.checkItems and ( not questList or ( questList and questList[name] ) ) ) then
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
	
	return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
	if( event == "ADDON_LOADED" and addon == "GetToThePoint" ) then
		GTTP.Initialize(GTTP)
	elseif( event ~= "ADDON_LOADED" ) then
		GTTP[event](GTTP)
	end
end)