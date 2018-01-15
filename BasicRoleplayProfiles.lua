--[[
	Notes:
		BeginGroupElection
			- message payload can be up to 100 bytes (some characters like extended ascii take up 2 bytes, but string.len works correctly on them)
			- cooldown between messages is 10 seconds
			- only one group election can be active at any time (so veto system messages ASAP!)
			
]]--

local ADDON_NAME = "BasicRoleplayProfiles"

local MESSAGE_API = LibStub("LibGroupMessage")

SLASH_COMMANDS["/tt"] = function() 
	MESSAGE_API:SendMessage("RP", "This is the first message")
	MESSAGE_API:SendMessage("RP", "This is the second message")
	MESSAGE_API:SendMessage("RP", "This is the third message")
	MESSAGE_API:SendMessage("SPECIAL", "This is the last message")
end

local function OnAddonLoaded()
	MESSAGE_API:RegisterMessageCallback("RP", function(senderUnitTag, data) d("CALLBACK=" .. data) end)
	EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)