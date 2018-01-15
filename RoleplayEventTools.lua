local ADDON_NAME = "RoleplayEventTools"
local ADDON_VERSION = 1

local DEBUG_MODE = false
local function TactiDebug(...) if (DEBUG_MODE) then d(...) end end

local MESSAGE_API = LibStub("LibGroupMessage")
local WINDOW_MANAGER = GetWindowManager()

local MESSAGE_CHANNEL = "RE"



local function SendDiceRoll(diceNotation, result, comment)
	local encodedMessage = diceNotation .. "#" .. result .. "#" .. comment
	-- TODO: truncate excessive comments
	MESSAGE_API:SendMessage(MESSAGE_CHANNEL, encodedMessage)
end

local function OnDiceRollReceived(senderUnitTag, data)
	local diceNotation, result, comment = string.match(data, "(.*)#(.*)#(.*)")
	if (diceNotation == nil or result == nil or comment == nil) then return end

	local unitName = GetUnitName(senderUnitTag)
	StartChatInput("[" .. unitName .. " (" .. comment .. ") : " .. diceNotation .. " = " .. result .. " : success] ")
end

local function OnRollCommand(params)
	-- Format: /roll (diceNotation) # (comment)
	local diceNotation, comment = string.match(params, "(.*)#[ ]*(.*)")
	if (diceNotation == nil) then
		diceNotation = params
		comment = ""
	end
	
	-- Clean up dice notation; strip out whitespace.
	diceNotation = string.gsub(diceNotation, "%s+", "")
	
	d("rolling " .. diceNotation .. ", comment=" .. comment)
	
	local dice = nil
	local status, err = pcall(function () dice = RL_DICE:new(diceNotation) end)
	if (status == false) then
		d("\"" .. diceNotation .. "\" is invalid dice notation. Type /rollhelp for details.")
		return
	end
	
	local result = dice:roll()
	d(diceNotation .. " = " .. result)
	
	SendDiceRoll(diceNotation, result, comment)
	
	EventToolsDMPanelWindow:SetHidden(false)
end

local function OnAddonLoaded()
	SLASH_COMMANDS["/roll"] = OnRollCommand
	
	MESSAGE_API:RegisterMessageCallback(MESSAGE_CHANNEL, OnDiceRollReceived)
	
	EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)