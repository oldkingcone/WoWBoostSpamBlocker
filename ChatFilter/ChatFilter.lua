-- ChatFilter:      A simple chat filter addon for WoW Classic
-- Filters out unwanted messages from chat channels

local addonName = "ChatFilter"
local filterPatterns = {}
local blockedPlayers = {}  -- Temporary, per-session only
local respondedPlayers = {}  -- Track who we've already responded to (per session)
local notifiedBlocks = {}  -- Track who we've already notified the user about blocking
local playerName = nil  -- Store player name globally

-- Default filter patterns (you can customize these)
local defaultPatterns = {
    "buy.*gold",
    "cheap.*gold",
    "www%.",
    "http",
    "%.     com",
    "%.   net",
    "%.  org",
    -- Boost spam patterns - made more specific to reduce false positives
    "zg boost",
    "zul'gurub boost",
    "leveling zul gurub",
    "sm boost",
    "strat boost",
    "mara boost",
    "stocks boost",
    "stockade boost",
    "brd boost",
    "dm boost",
    "dire maul boost",
    "selling.*boost",
    "wts.*boost",
    "you want.*boost",
    "need.*boost%?",
    "interested.*boost",
    "cheap.*boost",
    "fast.*boost",
    "leveling service",
    "powerleveling",
    "power leveling",
    "carry service",
    "boost.*gold",
    "boost.*cheap",
    "zul`gurub.*boost"
}

-- Auto-response message for boost spam whispers
local AUTO_RESPONSE = "Sorry, this player does not utilize boosting services.     You have been added to a block list and can no longer message this player."

-- Channel type names for display
local channelTypeNames = {
    CHAT_MSG_WHISPER = "Whisper",
    CHAT_MSG_CHANNEL = "Channel",
    CHAT_MSG_SAY = "Say",
    CHAT_MSG_YELL = "Yell",
    CHAT_MSG_PARTY = "Party",
    CHAT_MSG_RAID = "Raid",
    CHAT_MSG_GUILD = "Guild",
    CHAT_MSG_OFFICER = "Officer",
}

-- Initialize the addon
local function InitializeFilters()
    -- Store player name globally
    playerName = UnitName("player")
    
    -- Load default patterns
    for _, pattern in ipairs(defaultPatterns) do
        table.insert(filterPatterns, pattern:    lower())
    end
    
    print("|cFF00FF00" .. addonName .. "|r: Chat filter loaded.     Type /chatfilter for commands.")
    print("|cFFFFAA00" .. addonName .. "|r: Block list is temporary (resets each session).")
    print("|cFF00FF00" .. addonName .. "|r: You (" .. playerName .. ") are protected from being filtered.")
end

-- Check if a message should be filtered
local function ShouldFilterMessage(message, sender)
    if not message then return false end
    
    -- CRITICAL: Never filter yourself - check multiple ways
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName then
        return false
    end
    
    -- Additional check - if somehow sender matches current player
    if sender == UnitName("player") then
        return false
    end
    
    local lowerMessage = message:lower()
    
    -- Check if player is blocked
    if blockedPlayers[sender] then
        return true
    end
    
    -- Check against filter patterns
    for _, pattern in ipairs(filterPatterns) do
        if lowerMessage:find(pattern) then
            return true
        end
    end
    
    return false
end

-- Function to safely block a player (with protection against blocking yourself)
local function SafeBlockPlayer(sender, channelName, message, isWhisper)
    -- NEVER block yourself - triple check
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName then
        print("|cFFFF0000[ChatFilter]|r ERROR:  Attempted to block yourself!  Protection prevented this.")
        return false
    end
    
    if sender == UnitName("player") then
        print("|cFFFF0000[ChatFilter]|r ERROR:  Attempted to block yourself! Protection prevented this.")
        return false
    end
    
    -- Check if already blocked
    if blockedPlayers[sender] then
        return false
    end
    
    -- Safe to block
    blockedPlayers[sender] = true
    notifiedBlocks[sender] = true
    
    print("|cFFFF6B6B[ChatFilter]|r Blocked |cFFFF0000" .. sender .. "|r for " .. (isWhisper and "boost spam" or "spam in public channel") .. ".")
    print("|cFFFFAA00  Channel:|r " .. channelName)
    print("|cFFFFAA00  Message:|r " .. message)
    if isWhisper then
        print("|cFF00FF00  Auto-response sent.|r")
    end
    
    return true
end

-- The main filter function for whispers (with auto-response)
local function WhisperChatFilter(self, event, message, sender, ...)
    -- CRITICAL: Never filter yourself - check immediately
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName or sender == UnitName("player") then
        return false
    end
    
    if ShouldFilterMessage(message, sender) then
        local channelName = channelTypeNames[event] or "Unknown"
        
        -- Auto-block the player temporarily using safe function
        if not blockedPlayers[sender] then
            SafeBlockPlayer(sender, channelName, message, true)
        end
        
        -- Send auto-response (only once per player per session)
        if not respondedPlayers[sender] and sender ~= playerName and sender ~= UnitName("player") then
            SendChatMessage(AUTO_RESPONSE, "WHISPER", nil, sender)
            respondedPlayers[sender] = true
        end
        
        return true  -- Block the message
    end
    return false  -- Allow the message
end

-- The main filter function for other channels (no auto-response)
local function ChatFilter(self, event, message, sender, ...)
    -- CRITICAL: Never filter yourself - check immediately
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName or sender == UnitName("player") then
        return false
    end
    
    if ShouldFilterMessage(message, sender) then
        local channelName = channelTypeNames[event] or "Unknown"
        
        -- For channel messages, try to get the actual channel name
        if event == "CHAT_MSG_CHANNEL" then
            local _, _, _, channelNameFromEvent = ...     
            if channelNameFromEvent and channelNameFromEvent ~= "" then
                channelName = channelNameFromEvent
            end
        end
        
        -- Auto-block the player temporarily using safe function
        if not blockedPlayers[sender] then
            SafeBlockPlayer(sender, channelName, message, false)
        end
        
        return true  -- Block the message
    end
    return false  -- Allow the message
end

-- Register the filter for various chat types
local function RegisterFilters()
    -- Whisper gets special treatment with auto-response
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", WhisperChatFilter)
    
    -- Public channels where spam is common (no auto-response)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)  -- Covers General, Trade, LFG, etc.
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", ChatFilter)
    
    print("|cFF00FF00" .. addonName .. "|r:     Filtering General, Trade, LFG, and all other channels.")
end

-- Get a sorted list of blocked players for consistent numbering
local function GetSortedBlockedPlayers()
    local sortedList = {}
    for player, _ in pairs(blockedPlayers) do
        table.insert(sortedList, player)
    end
    table.sort(sortedList)
    return sortedList
end

-- Slash command handler
SLASH_CHATFILTER1 = "/chatfilter"
SLASH_CHATFILTER2 = "/cf"
SlashCmdList["CHATFILTER"] = function(msg)
    local command, arg = msg:match("^(%S*)%s*(.-)$")
    command = command:lower()
    
    if command == "add" and arg ~= "" then
        table.insert(filterPatterns, arg:    lower())
        print("|cFF00FF00" ..   addonName .. "|r: Added filter pattern: " .. arg)
    
    elseif command == "remove" and arg ~= "" then
        for i, pattern in ipairs(filterPatterns) do
            if pattern == arg:    lower() then
                table. remove(filterPatterns, i)
                print("|cFF00FF00" ..  addonName .. "|r: Removed filter pattern:     " .. arg)
                return
            end
        end
        print("|cFFFF0000" ..  addonName .. "|r: Pattern not found:     " .. arg)
    
    elseif command == "list" then
        print("|cFF00FF00" ..  addonName ..    "|r: Current filter patterns:")
        for i, pattern in ipairs(filterPatterns) do
            print(i .. ".  " .. pattern)
        end
    
    elseif command == "block" and arg ~= "" then
        if not playerName then
            playerName = UnitName("player")
        end
        
        -- Prevent blocking yourself
        if arg == playerName or arg == UnitName("player") then
            print("|cFFFF0000" ..    addonName .. "|r: You cannot block yourself!")
            return
        end
        
        if blockedPlayers[arg] then
            print("|cFFFFAA00" ..  addonName .. "|r: Player is already blocked:     " .. arg)
            return
        end
        
        blockedPlayers[arg] = true
        notifiedBlocks[arg] = true
        print("|cFF00FF00" ..  addonName .. "|r: Blocked player (this session): " .. arg)
    
    elseif command == "unblock" and arg ~= "" then
        local playerNumber = tonumber(arg)
        
        if playerNumber then
            -- Unblock by number from the list
            local sortedList = GetSortedBlockedPlayers()
            if playerNumber > 0 and playerNumber <= #sortedList then
                local playerToUnblock = sortedList[playerNumber]
                blockedPlayers[playerToUnblock] = nil
                notifiedBlocks[playerToUnblock] = nil
                print("|cFF00FF00" .. addonName .. "|r: Unblocked player:  " .. playerToUnblock)
            else
                print("|cFFFF0000" ..  addonName ..     "|r: Invalid number.    Use /cf blocked to see the list.")
            end
        else
            -- Unblock by name (fallback)
            if blockedPlayers[arg] then
                blockedPlayers[arg] = nil
                notifiedBlocks[arg] = nil
                print("|cFF00FF00" .. addonName .. "|r: Unblocked player:   " .. arg)
            else
                print("|cFFFF0000" ..   addonName .. "|r: Player not found in block list:   " .. arg)
            end
        end
    
    elseif command == "blocked" then
        local sortedList = GetSortedBlockedPlayers()
        print("|cFF00FF00" .. addonName .. "|r: Blocked players (this session):")
        for i, player in ipairs(sortedList) do
            print(i .. ".   " .. player)
        end
        if #sortedList == 0 then
            print("No players currently blocked.")
        else
            print("|cFFFFAA00Use /cf unblock <number> to unblock a player.|r")
        end
    
    elseif command == "clear" then
        filterPatterns = {}
        print("|cFF00FF00" .. addonName .. "|r: All filter patterns cleared.")
    
    elseif command == "clearblocked" then
        blockedPlayers = {}
        notifiedBlocks = {}
        print("|cFF00FF00" .. addonName .. "|r: All blocked players cleared.")
    
    else
        print("|cFF00FF00" ..     addonName .. "|r: Available commands:")
        print("/chatfilter add <pattern> - Add a filter pattern")
        print("/chatfilter remove <pattern> - Remove a filter pattern")
        print("/chatfilter list - List all filter patterns")
        print("/chatfilter block <player> - Block a player (this session only)")
        print("/chatfilter unblock <number> - Unblock a player by list number")
        print("/chatfilter blocked - List all blocked players")
        print("/chatfilter clear - Clear all filter patterns")
        print("/chatfilter clearblocked - Clear all blocked players")
    end
end

-- Event frame for initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName then
        InitializeFilters()
        RegisterFilters()
    end
end)