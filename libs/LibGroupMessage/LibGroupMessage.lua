local libLoaded
local LIB_NAME, VERSION = "LibGroupMessage", 1
local GroupMessageLib, oldminor = LibStub:NewLibrary(LIB_NAME, VERSION)
if not GroupMessageLib then return end

-------------------
--[[ Constants ]]--
-------------------

local MESSAGE_SEND_INTERVAL = 10125
local MESSAGE_SEND_INTERVAL_DIVISION = 5

-- Use characters we know are not likely to be part of a group ready check.
local GROUP_INDEX_ENCODE_CHARSET = {
	[1]='!',[2]='"',[3]='$',[4]='%',[5]='(',[6]=')',
	[7]='^',[8]='&',[9]='*',[10]='-',[11]='_',[12]='=',
	[13]='+',[14]=':',[15]=';',[16]='{',[17]='}',[18]='|',
	[19]='.',[20]='/',[21]='?',[22]='>',[23]='<',[24]=','
}

local GROUP_INDEX_DECODE_CHARSET = {
	["!"]=1,["\""]=2,["$"]=3,["%"]=4,["("]=5,[")"]=6,
	["^"]=7,["&"]=8,["*"]=9,["-"]=10,["_"]=11,["="]=12,
	["+"]=13,[":"]=14,[";"]=15,["{"]=16,["}"]=17,["|"]=18,
	["."]=19,["/"]=20,["?"]=21,[">"]=22,["<"]=23,[","]=24
}

---------------------------
--[[ Utility functions ]]--
---------------------------

local function GetPlayerGroupIndex()
	if GetGroupSize() > 0 then
		for i = 1, GetGroupSize(), 1 do
			local unit = 'group' .. i
			if (GetUnitName(unit) == GetUnitName('player')) then
				return i
			end
		end
	end
	return nil
end

local function GetUnitTagFromGroupIndex(groupIndex)
	return 'group' .. groupIndex
end

local function EncodeGroupIndex(groupIndex)
	return GROUP_INDEX_ENCODE_CHARSET[groupIndex]
end

local function DecodeGroupIndex(encodedGroupIndex)
	return GROUP_INDEX_DECODE_CHARSET[encodedGroupIndex] or nil
end

-- Copied from: https://stackoverflow.com/questions/19262761/lua-need-to-split-at-comma
local function strsplit(inputstr, sep)
	local outResults = {}
	local theStart = 1
	local theSplitStart, theSplitEnd = string.find( inputstr, sep, theStart )
	while theSplitStart do
		table.insert( outResults, string.sub( inputstr, theStart, theSplitStart-1 ) )
		theStart = theSplitEnd + 1
		theSplitStart, theSplitEnd = string.find( inputstr, sep, theStart )
	end
	table.insert( outResults, string.sub( inputstr, theStart ) )
	return outResults
end

-- Copied from: https://stackoverflow.com/questions/2705793/how-to-get-number-of-entries-in-a-lua-table
-- Lua is a shit language FYI
local function tablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

--------------------------------
--[[ Outgoing Message class ]]--
--------------------------------

local OutgoingMessage = ZO_Object:Subclass()

function OutgoingMessage:New(channel, data)
	local object = ZO_Object.New(self)
	object.channel = channel
	object.data = data
	return object
end

function OutgoingMessage:ComputeMessageText()
	local groupIndex = GetPlayerGroupIndex()
	if (groupIndex == nil) then return "" end

	local messageText = EncodeGroupIndex(groupIndex) .. self.channel .. "#" .. self.data
	return messageText
end

local MessageCallback = ZO_Object:Subclass()

function MessageCallback:New(channel, callback)
	local object = ZO_Object.New(self)
	object.channel = channel
	object.callback = callback
	return object
end

----------------------
--[[ Main library ]]--
----------------------

function GroupMessageLib:SendMessage(channel, data)
	-- TODO validate channel
	-- channel can't be too long, cannot include delimiter symbol
	-- TODO validate data
	-- data length limit

	GroupMessageLib.outgoingMessageQueue[#GroupMessageLib.outgoingMessageQueue + 1] = OutgoingMessage:New(channel, data)
end

function GroupMessageLib:RegisterMessageCallback(channel, callback)
	GroupMessageLib.messageCallbacks[#GroupMessageLib.messageCallbacks + 1] = MessageCallback:New(channel, callback)
end

local function IsGroupMessageLibDescriptor(descriptor)
	local groupIndex = DecodeGroupIndex(string.sub(descriptor, 1, 1))
	local splitString = strsplit(descriptor, "#")
	if (tablelength(splitString) < 2) then 
		-- Not a LibGroupMessage message, we expect at least 2 tokens
		return false
	end
	return (groupIndex ~= nil)
end

local function OnMessageReceived(message)
	local splitString = strsplit(message, "#")
	if (tablelength(splitString) < 2) then 
		-- Not a LibGroupMessage message, we expect at least 2 tokens
		return 
	end
	local firstToken = splitString[1]
	local encodedGroupIndex = string.sub(message, 1, 1)
	
	-- If we cannot decode the first symbol of the message as a LibGroupMessage group index, then it's not a LibGroupMessage message.
	local groupIndex = DecodeGroupIndex(encodedGroupIndex)
	if (groupIndex == nil) then return end
	
	local senderUnitTag = GetUnitTagFromGroupIndex(groupIndex)
	local channel = string.sub(firstToken, 2, string.len(firstToken))
	local data = string.sub(message, string.len(firstToken) + 2, string.len(message))
	
	d("GROUPINDEX=" .. groupIndex .. ", SENDER=" .. GetUnitName(senderUnitTag) .. ", CHANNEL='" .. channel .. "', DATA='" .. data .. "'")
	
	for k, messageCallback in pairs(GroupMessageLib.messageCallbacks) do
		if (messageCallback.channel == channel) then
			messageCallback.callback(senderUnitTag, data)
		end
	end
end

local function OnUpdateInterval()
	if GetGroupSize() <= 0 then
		GroupMessageLib.outgoingMessageQueue = {}
		return
	end

	if (GroupMessageLib.messageSendIntervalCount == 0) then
		if (#GroupMessageLib.outgoingMessageQueue > 0) then
			local messageToSend = GroupMessageLib.outgoingMessageQueue[1]
			if (not messageToSend) then return end
			
			local sendSuccess = BeginGroupElection(GROUP_ELECTION_TYPE_GENERIC_UNANIMOUS, messageToSend:ComputeMessageText())
			
			if (sendSuccess) then
				GroupMessageLib.messageSendIntervalCount = MESSAGE_SEND_INTERVAL_DIVISION - 1
				table.remove(GroupMessageLib.outgoingMessageQueue, 1)
			end
		end
	else
		GroupMessageLib.messageSendIntervalCount = GroupMessageLib.messageSendIntervalCount - 1
	end
end

function GroupMessageLib:Initialize()
	GroupMessageLib.outgoingMessageQueue = {}
	GroupMessageLib.messageCallbacks = {}
	GroupMessageLib.messageSendIntervalCount = 0

	-- Begin hijacking ZOS notifications for group elections
	local function OnGroupElectionNotificationAdded()
        local electionType, timeRemainingSeconds, descriptor, targetUnitTag = GetGroupElectionInfo()
        local function AcceptCallback()
            CastGroupVote(GROUP_VOTE_CHOICE_FOR)
        end
        local function DeclineCallback()
            CastGroupVote(GROUP_VOTE_CHOICE_AGAINST)
        end
        local function DeferDecisionCallback()
            PLAYER_TO_PLAYER:RemoveFromIncomingQueue(INTERACT_TYPE_GROUP_ELECTION)
        end
        local messageFormat, messageParams
        if ZO_IsGroupElectionTypeCustom(electionType) then
            if descriptor == ZO_GROUP_ELECTION_DESCRIPTORS.READY_CHECK then
                messageFormat = GetString(SI_GROUP_ELECTION_READY_CHECK_MESSAGE)
            else
                messageFormat = descriptor
            end
            messageParams = {}
        else
            if electionType == GROUP_ELECTION_TYPE_KICK_MEMBER then
                messageFormat = SI_GROUP_ELECTION_KICK_MESSAGE
            elseif electionType == GROUP_ELECTION_TYPE_NEW_LEADER then
                messageFormat = SI_GROUP_ELECTION_PROMOTE_MESSAGE
            end
            local primaryName = ZO_GetPrimaryPlayerNameFromUnitTag(targetUnitTag)
            local secondaryName = ZO_GetSecondaryPlayerNameFromUnitTag(targetUnitTag)
            messageParams = { primaryName, secondaryName }
        end
		
		if (IsGroupMessageLibDescriptor(descriptor)) then
			d("Hit our group election added hook!")
			d("payload=\"" .. descriptor .. "\"")
			CastGroupVote(GROUP_VOTE_CHOICE_AGAINST)
			OnMessageReceived(descriptor)
			return
		end
        
        PlaySound(SOUNDS.NEW_TIMED_NOTIFICATION)
        PLAYER_TO_PLAYER:RemoveFromIncomingQueue(INTERACT_TYPE_GROUP_ELECTION)
        
        local promptData = PLAYER_TO_PLAYER:AddPromptToIncomingQueue(INTERACT_TYPE_GROUP_ELECTION, nil, nil, nil, AcceptCallback, DeclineCallback, DeferDecisionCallback)
        promptData.acceptText = GetString(SI_YES)
        promptData.declineText = GetString(SI_NO)
        promptData.expiresAtS = GetFrameTimeSeconds() + timeRemainingSeconds
        promptData.messageFormat = messageFormat
        promptData.messageParams = messageParams
        promptData.expirationCallback = DeferDecisionCallback
        promptData.dialogTitle = GetString("SI_NOTIFICATIONTYPE", NOTIFICATION_TYPE_GROUP_ELECTION)
        promptData.uniqueSounds = {
            accept = SOUNDS.GROUP_ELECTION_VOTE_SUBMITTED,
            decline = SOUNDS.GROUP_ELECTION_VOTE_SUBMITTED,
        }
    end
	PLAYER_TO_PLAYER.control:UnregisterForEvent(EVENT_GROUP_ELECTION_NOTIFICATION_ADDED)
	PLAYER_TO_PLAYER.control:RegisterForEvent(EVENT_GROUP_ELECTION_NOTIFICATION_ADDED, function(event, ...) OnGroupElectionNotificationAdded(...) end)
	
	local handlers = ZO_AlertText_GetHandlers()
	local function EventHookGroupElectionResult()
		-- Modify these 3 hooks to suppress only our special message
		d("hit EventHookGroupElectionResult")
		return true
	end
	ZO_PreHook(handlers, EVENT_GROUP_ELECTION_RESULT, EventHookGroupElectionResult)
	
	local function EventHookGroupElectionRequested()
		d("hit EventHookGroupElectionRequested")
		return true
	end
	ZO_PreHook(handlers, EVENT_GROUP_ELECTION_REQUESTED, EventHookGroupElectionRequested)
	
	local function EventHookGroupElectionFailed()
		d("hit EventHookGroupElectionFailed")
		return true
	end
	ZO_PreHook(handlers, EVENT_GROUP_ELECTION_FAILED, EventHookGroupElectionFailed)
	
	
	local function hookGroupElectionBuildNotificationList(self)
		local electionType, timeRemainingSeconds, descriptor, targetUnitTag = GetGroupElectionInfo()
		if (IsGroupMessageLibDescriptor(descriptor)) then
			return true
		end
	end
	ZO_PreHook(ZO_GroupElectionProvider, "BuildNotificationList", hookGroupElectionBuildNotificationList)
	-- End hijacking ZOS notifications for group elections

	EVENT_MANAGER:RegisterForUpdate(LIB_NAME, (MESSAGE_SEND_INTERVAL / MESSAGE_SEND_INTERVAL_DIVISION), OnUpdateInterval)
end

local function OnAddonLoaded()
	if not libLoaded then
		libLoaded = true
		local LIB = LibStub(LIB_NAME)
		LIB:Initialize()
		EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_ADD_ON_LOADED)
	end
end

EVENT_MANAGER:RegisterForEvent(LIB_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)