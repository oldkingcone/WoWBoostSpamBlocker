-- ChatFilter:                    A simple chat filter addon for WoW Classic
-- Filters out unwanted messages from chat channels

local addonName = "ChatFilter"
local filterPatterns = {}
local blockedPlayers = {}  -- Temporary, per-session only
local respondedPlayers = {}  -- Track who we've already responded to (per session)
local notifiedBlocks = {}  -- Track who we've already notified the user about blocking
local playerName = nil  -- Store player name globally

-- Spam classification categories
local SPAM_TYPES = {
    DUNGEON_BOOST = "Dungeon Boost Spam",
    LEVELING_SERVICE = "Leveling Service Spam",
    POWER_LEVELING = "Power Leveling Spam",
    CARRY_SERVICE = "Carry Service Spam",
    GOLD_SELLER = "Gold Seller Spam",
    GENERAL_BOOST = "General Boost Spam",
}

-- Comprehensive dungeon abbreviations and names
local dungeonKeywords = {
    "rfc", "wc", "sfk", "bfd", "gnomer", "gnomeregan", "rfk", "sm", "rfd", 
    "ulda", "uldaman", "zf", "mara", "maraudon", "st", "brd", "lbrs", "ubrs", 
    "strat", "stratholme", "scholo", "scholomance", "dm", "dire maul", 
    "zg", "zul'gurub", "stockade", "stocks", "wailing caverns", 
    "shadowfang", "blackfathom", "razorfen kraul", "scarlet monastery",
    "razorfen downs", "zul farrak", "sunken temple", "blackrock depths",
    "lower blackrock", "upper blackrock", "arm", "cath", "army", "lib", "library", "armory",
    "cathedral",
}

-- Boost spam detection patterns with classifications
local boostSpamPatterns = {
    -- Dungeon boost patterns (short form like "RFC 1 SPOT 15/5")
    {pattern = "%a+.*spot.*%d+/%d+", classification = SPAM_TYPES.DUNGEON_BOOST},
    {pattern = "%a+.*spots.*%d+/%d+", classification = SPAM_TYPES.    DUNGEON_BOOST},
    {pattern = "%a+.*%d+.*spot", classification = SPAM_TYPES.    DUNGEON_BOOST},
    {pattern = "%a+.*%d+.*spots", classification = SPAM_TYPES.  DUNGEON_BOOST},
    {pattern = "spot.*%d+/%d+", classification = SPAM_TYPES.   DUNGEON_BOOST},
    {pattern = "spots.*%d+/%d+", classification = SPAM_TYPES.   DUNGEON_BOOST},
    {pattern = "boost.*%d+/%d+", classification = SPAM_TYPES.    DUNGEON_BOOST},
    {pattern = "leveling.*%d+/%d+", classification = SPAM_TYPES.    LEVELING_SERVICE},
    
    -- Dungeon + boost/leveling/mobs combinations
    {pattern = "boost.*%d+.*mobs", classification = SPAM_TYPES.   DUNGEON_BOOST},
    {pattern = "leveling.*%d+.*mobs", classification = SPAM_TYPES.    LEVELING_SERVICE},
    {pattern = "%d+.*mobs.*boost", classification = SPAM_TYPES.    DUNGEON_BOOST},
    {pattern = "%d+.*mobs.*leveling", classification = SPAM_TYPES.    LEVELING_SERVICE},
    {pattern = "mobs.*boost", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "mobs.*leveling", classification = SPAM_TYPES.  LEVELING_SERVICE},
    
    -- Direct boost/leveling selling
    {pattern = "wts.*boost", classification = SPAM_TYPES.  GENERAL_BOOST},
    {pattern = "wts.*leveling", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "wts.*carry", classification = SPAM_TYPES.  CARRY_SERVICE},
    {pattern = "wts.*power.*level", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "selling.*boost", classification = SPAM_TYPES.  GENERAL_BOOST},
    {pattern = "selling.*leveling", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "selling.*carry", classification = SPAM_TYPES.  CARRY_SERVICE},
    {pattern = "selling.*power.*level", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "sell.*boost", classification = SPAM_TYPES.  GENERAL_BOOST},
    {pattern = "sell.*leveling", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "sell.*carry", classification = SPAM_TYPES. CARRY_SERVICE},
    {pattern = "sell.*power.*level", classification = SPAM_TYPES. POWER_LEVELING},
    
    -- Service keywords combined with boost/leveling
    {pattern = "service.*boost", classification = SPAM_TYPES.  GENERAL_BOOST},
    {pattern = "service.*leveling", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "service.*carry", classification = SPAM_TYPES. CARRY_SERVICE},
    {pattern = "service.*power.*level", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "boosting.*service", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*service", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "carry.*service", classification = SPAM_TYPES. CARRY_SERVICE},
    
    -- Power leveling variations
    {pattern = "power.*leveling", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "powerleveling", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "powerlvling", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "power.*lvling", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "power.*level.*service", classification = SPAM_TYPES. POWER_LEVELING},
    
    -- Boost/leveling with commercial indicators
    {pattern = "boost.*pst", classification = SPAM_TYPES.  GENERAL_BOOST},
    {pattern = "leveling.*pst", classification = SPAM_TYPES.    LEVELING_SERVICE},
    {pattern = "boost.*whisper", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*whisper", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "boost.*pm", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*pm", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "boost.*w me", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*w me", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*cheap", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*cheap", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*price", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*price", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*gold", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*gold", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*%d+g[^a-z]", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*%d+g[^a-z]", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*fast", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*fast", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*quick", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*quick", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*safe", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "leveling.*safe", classification = SPAM_TYPES. LEVELING_SERVICE},
    
    -- Spam opener phrases
    {pattern = "hi sir.*boost", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "hello sir.*boost", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "hey sir.*boost", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "hi sir.*leveling", classification = SPAM_TYPES.    LEVELING_SERVICE},
    {pattern = "hello sir.*leveling", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "sir.*you want.*boost", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "sir.*you want.*leveling", classification = SPAM_TYPES.    LEVELING_SERVICE},
    {pattern = "you want.*boost%?   ", classification = SPAM_TYPES.    GENERAL_BOOST},
    {pattern = "you want.*leveling%?  ", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "you want.*power.*level", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "you need.*boost%?", classification = SPAM_TYPES.    GENERAL_BOOST},
    {pattern = "you need.*leveling%?", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "interested.*boost%?", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "interested.*leveling%?", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "interested.*carry%?", classification = SPAM_TYPES. CARRY_SERVICE},
    {pattern = "interested.*power.*level", classification = SPAM_TYPES. POWER_LEVELING},
    
    -- Multi-word combinations
    {pattern = "leveling.*min.*level", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "leveling.*req.*level", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "leveling.*required.*level", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "leveling.*min.*%d+", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "boost.*min.*level", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "boost.*req.*level", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "boost.*required.*level", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "pack.*mobs.*quick", classification = SPAM_TYPES.   DUNGEON_BOOST},
    {pattern = "pack.*mobs.*fast", classification = SPAM_TYPES.  DUNGEON_BOOST},
    {pattern = "mobs.*quick.*time", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "mobs.*fast.*time", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "pack.*mobs.*leveling", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "pack.*mobs.*boost", classification = SPAM_TYPES. DUNGEON_BOOST},
    
    -- Specific advertising language
    {pattern = "service.*power.*leveling", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "quick.*time.*price.*pst", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "fast.*time.*price.*pst", classification = SPAM_TYPES.    GENERAL_BOOST},
    {pattern = "min.*%d+.*%d+.*level", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "req.*level.*%d+.*%d+", classification = SPAM_TYPES. LEVELING_SERVICE},
    
    -- All caps advertising
    {pattern = "LEVELING.*SERVICE", classification = SPAM_TYPES.    LEVELING_SERVICE},
    {pattern = "POWER.*LEVELING", classification = SPAM_TYPES.   POWER_LEVELING},
    {pattern = "BOOSTING.*SERVICE", classification = SPAM_TYPES. GENERAL_BOOST},
    {pattern = "SERVICE.*POWER.*LEVELING", classification = SPAM_TYPES. POWER_LEVELING},
    {pattern = "BOOST.*SERVICE", classification = SPAM_TYPES.    GENERAL_BOOST},
    {pattern = "CARRY.*SERVICE", classification = SPAM_TYPES.  CARRY_SERVICE},
    
    -- XP/EXP boost related
    {pattern = "boost.*xp.*hour", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "boost.*exp.*hour", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "leveling.*xp.*hour", classification = SPAM_TYPES.    LEVELING_SERVICE},
    {pattern = "leveling.*exp.*hour", classification = SPAM_TYPES.  LEVELING_SERVICE},
    {pattern = "fast.*xp.*boost", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "fast.*exp.*boost", classification = SPAM_TYPES. DUNGEON_BOOST},
    
    -- Server specific
    {pattern = "merica.*boost", classification = SPAM_TYPES. DUNGEON_BOOST},
    {pattern = "merica.*leveling", classification = SPAM_TYPES. LEVELING_SERVICE},
    {pattern = "merica.*%d+.*mobs", classification = SPAM_TYPES. DUNGEON_BOOST},
}

-- Generate dungeon-specific patterns dynamically
local function GenerateDungeonPatterns()
    local patterns = {}
    
    for _, dungeon in ipairs(dungeonKeywords) do
        -- Dungeon + boost
        table.insert(patterns, {pattern = dungeon .. ".*boost", classification = SPAM_TYPES. DUNGEON_BOOST})
        table.insert(patterns, {pattern = dungeon .. ".*leveling", classification = SPAM_TYPES.   LEVELING_SERVICE})
        table.insert(patterns, {pattern = dungeon .. ".*%d+.*mobs", classification = SPAM_TYPES. DUNGEON_BOOST})
        table.insert(patterns, {pattern = dungeon .. ".*spot", classification = SPAM_TYPES. DUNGEON_BOOST})
        table.insert(patterns, {pattern = dungeon .. ".*spots", classification = SPAM_TYPES.DUNGEON_BOOST})
        table.insert(patterns, {pattern = dungeon .. ".*carry", classification = SPAM_TYPES.CARRY_SERVICE})
        table.insert(patterns, {pattern = dungeon .. ".*service", classification = SPAM_TYPES.DUNGEON_BOOST})
        table.insert(patterns, {pattern = dungeon .. ".*xp", classification = SPAM_TYPES.DUNGEON_BOOST})
        table.insert(patterns, {pattern = dungeon .. ".*exp", classification = SPAM_TYPES.DUNGEON_BOOST})
        table.insert(patterns, {pattern = dungeon ..    ".*power", classification = SPAM_TYPES.POWER_LEVELING})
        
        -- Uppercase versions
        local upperDungeon = dungeon: upper()
        table.insert(patterns, {pattern = upperDungeon ..    ".*BOOST", classification = SPAM_TYPES.DUNGEON_BOOST})
        table.insert(patterns, {pattern = upperDungeon ..  ".*LEVELING", classification = SPAM_TYPES.   LEVELING_SERVICE})
        table.insert(patterns, {pattern = upperDungeon .. ".*SPOT", classification = SPAM_TYPES.DUNGEON_BOOST})
        table.insert(patterns, {pattern = upperDungeon ..    ".*SPOTS", classification = SPAM_TYPES.DUNGEON_BOOST})
    end
    
    return patterns
end

-- Gold seller patterns (more specific - only gold + website combinations)
local goldSellerPatterns = {
    {pattern = "buy.*gold.*www", classification = SPAM_TYPES. GOLD_SELLER},
    {pattern = "buy.*gold.*%.    com", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "buy.*gold.*%.   net", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "cheap.*gold.*www", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "cheap.*gold.*%.  com", classification = SPAM_TYPES.  GOLD_SELLER},
    {pattern = "sell.*gold.*www", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "selling.*gold.*www", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "gold.*for.*sale.*www", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "www.*gold.*cheap", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "www.*buy.*gold", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "%.    com.*gold", classification = SPAM_TYPES.GOLD_SELLER},
    {pattern = "gold.*%.   com", classification = SPAM_TYPES.  GOLD_SELLER},
}

-- Auto-response message for boost spam whispers
local AUTO_RESPONSE = "Sorry, this player does not utilize boosting services.    You have been added to a block list and can no longer message this player."

-- Initialize the addon
local function InitializeFilters()
    -- Store player name globally
    playerName = UnitName("player")
    
    -- Add dynamically generated dungeon patterns
    local dungeonPatterns = GenerateDungeonPatterns()
    for _, patternData in ipairs(dungeonPatterns) do
        table.insert(boostSpamPatterns, patternData)
    end
    
    print("|cFF00FF00" .. addonName .. "|r: Chat filter loaded.    Type /chatfilter for commands.")
    print("|cFFFFAA00" .. addonName ..    "|r: Block list is temporary (resets each session).")
    print("|cFF00FF00" .. addonName .. "|r: You (" .. playerName .. ") are protected from being filtered.")
    print("|cFF00FF00" .. addonName .. "|r: Guild, Officer, Party, and Raid chats are not filtered.")
    print("|cFF00FF00" .. addonName .. "|r: Legitimate WTS/WTB messages are allowed.")
    print("|cFF00FF00" .. addonName .. "|r: Loaded " .. #boostSpamPatterns .. " boost spam patterns.")
end

-- Check if message is a legitimate trade message (NOT boost spam)
local function IsLegitimateTradeMessage(message)
    local lowerMessage = message:lower()
    
    -- Keywords that indicate legitimate item/service trading (NOT boost related)
    local legitKeywords = {
        "enchant", "enchanting", "tailoring", "blacksmith", "alchemy",
        "engineering", "leatherworking", "mining", "herbalism", "skinning",
        "flask", "elixir", "potion", "armor", "weapon", "ore", "bar",
        "herb", "leather", "cloth", "runecloth", "recipe", "pattern",
        "schematic", "plan", "epic", "rare", "blue", "purple", "green",
        "boe", "bop", "crusader", "fiery", "lifestealing", "mongoose",
        "spellpower", "healing", "agility", "strength", "stamina",
        "intellect", "spirit", "defense", "resistance", "arcane", "fire",
        "frost", "nature", "shadow", "holy",
    }
    
    -- If the message contains WTS/WTB and legitimate trade keywords, allow it
    if lowerMessage:find("wts") or lowerMessage:find("wtb") or lowerMessage:find("selling") or lowerMessage:find("buying") then
        for _, keyword in ipairs(legitKeywords) do
            if lowerMessage:find(keyword) then
                return true
            end
        end
    end
    
    return false
end

-- Advanced spam detection - returns classification if spam, nil otherwise
local function DetectSpamType(message)
    -- First check if it's a legitimate trade message
    if IsLegitimateTradeMessage(message) then
        return nil
    end
    
    local lowerMessage = message:lower()
    
    -- Check boost spam patterns
    for _, patternData in ipairs(boostSpamPatterns) do
        if lowerMessage:find(patternData.pattern) then
            return patternData.classification
        end
    end
    
    -- Check gold seller patterns
    for _, patternData in ipairs(goldSellerPatterns) do
        if lowerMessage:find(patternData.pattern) then
            return patternData.classification
        end
    end
    
    -- Check for custom added patterns
    for _, pattern in ipairs(filterPatterns) do
        if lowerMessage:find(pattern) then
            return SPAM_TYPES.GENERAL_BOOST  -- Default classification for custom patterns
        end
    end
    
    return nil
end

-- Check if a message should be filtered
local function ShouldFilterMessage(message, sender)
    if not message then return false, nil end
    
    -- CRITICAL: Never filter yourself
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName or sender == UnitName("player") then
        return false, nil
    end
    
    -- Check if player is already blocked
    if blockedPlayers[sender] then
        return true, blockedPlayers[sender]  -- Return stored classification
    end
    
    -- Run spam detection
    local spamType = DetectSpamType(message)
    if spamType then
        return true, spamType
    end
    
    return false, nil
end

-- Get proper channel name from event arguments (renamed to avoid conflict with WoW API)
local function GetEventChannelName(event, ...)
    if event == "CHAT_MSG_WHISPER" then
        return "Whisper"
    elseif event == "CHAT_MSG_SAY" then
        return "Say"
    elseif event == "CHAT_MSG_YELL" then
        return "Yell"
    elseif event == "CHAT_MSG_CHANNEL" then
        -- For channel messages, extract the actual channel name
        -- Arguments:    message, sender, language, channelString, target, flags, unknown, channelNumber, channelName
        local channelName = select(9, ...)
        if channelName and channelName ~= "" then
            return channelName
        end
        
        -- Fallback:    try to get channel info by number using the WoW API
        local channelNumber = select(8, ...)
        if channelNumber and channelNumber > 0 then
            -- Call the WoW API GetChannelName which returns:  id, name, instanceID, isCommunitiesChannel
            local id, name = GetChannelName(channelNumber)
            if name and name ~= "" then
                return name
            end
        end
        
        return "Channel"
    else
        return "Unknown"
    end
end

-- Function to safely block a player (with protection against blocking yourself)
local function SafeBlockPlayer(sender, channelName, spamType, isWhisper)
    -- NEVER block yourself - triple check
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName or sender == UnitName("player") then
        print("|cFFFF0000[ChatFilter]|r ERROR:    Attempted to block yourself!    Protection prevented this.")
        return false
    end
    
    -- Check if already blocked
    if blockedPlayers[sender] then
        return false
    end
    
    -- Safe to block - store the classification
    blockedPlayers[sender] = spamType
    notifiedBlocks[sender] = true
    
    print("|cFFFF6B6B[ChatFilter]|r Blocked |cFFFF0000" .. sender .. "|r")
    print("|cFFFFAA00  Channel:|r " .. channelName)
    print("|cFFFFAA00  Classification:|r " .. spamType)
    if isWhisper then
        print("|cFF00FF00  Auto-response sent.|r")
    end
    
    return true
end

-- The main filter function for whispers (with auto-response)
local function WhisperChatFilter(self, event, message, sender, ...)
    -- CRITICAL: Never filter yourself
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName or sender == UnitName("player") then
        return false
    end
    
    local shouldFilter, spamType = ShouldFilterMessage(message, sender)
    if shouldFilter then
        local channelName = GetEventChannelName(event, ...)
        
        -- Auto-block the player temporarily using safe function
        if not blockedPlayers[sender] then
            SafeBlockPlayer(sender, channelName, spamType, true)
        end
        
        -- Send auto-response (only once per player per session)
        if not respondedPlayers[sender] and sender ~= playerName and sender ~= UnitName("player") then
            SendChatMessage(AUTO_RESPONSE, "WHISPER", nil, sender)
            respondedPlayers[sender] = true
        end
        
        return true
    end
    return false
end

-- The main filter function for public channels only (no auto-response)
local function ChatFilter(self, event, message, sender, ...)
    -- CRITICAL: Never filter yourself
    if not playerName then
        playerName = UnitName("player")
    end
    
    if sender == playerName or sender == UnitName("player") then
        return false
    end
    
    local shouldFilter, spamType = ShouldFilterMessage(message, sender)
    if shouldFilter then
        local channelName = GetEventChannelName(event, ...)
        
        -- Auto-block the player temporarily using safe function
        if not blockedPlayers[sender] then
            SafeBlockPlayer(sender, channelName, spamType, false)
        end
        
        return true
    end
    return false
end

-- Register the filter for various chat types
local function RegisterFilters()
    -- Whisper gets special treatment with auto-response
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", WhisperChatFilter)
    
    -- Public channels where spam is common (no auto-response)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", ChatFilter)
    
    print("|cFF00FF00" .. addonName .. "|r:    Filtering Whispers, General, Trade, LFG, Say, and Yell.")
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
        table.insert(filterPatterns, arg:   lower())
        print("|cFF00FF00" .. addonName .. "|r:  Added filter pattern: " .. arg)
    
    elseif command == "remove" and arg ~= "" then
        for i, pattern in ipairs(filterPatterns) do
            if pattern == arg:   lower() then
                table.remove(filterPatterns, i)
                print("|cFF00FF00" .. addonName .. "|r: Removed filter pattern:    " .. arg)
                return
            end
        end
        print("|cFFFF0000" .. addonName .. "|r: Pattern not found:    " .. arg)
    
    elseif command == "list" then
        print("|cFF00FF00" .. addonName .. "|r: Active patterns:  " .. #boostSpamPatterns .. " boost spam, " .. #goldSellerPatterns .. " gold seller")
        if #filterPatterns > 0 then
            print("|cFF00FF00" .. addonName .. "|r: Custom filter patterns:")
            for i, pattern in ipairs(filterPatterns) do
                print(i .. ".    " .. pattern)
            end
        end
    
    elseif command == "block" and arg ~= "" then
        if not playerName then
            playerName = UnitName("player")
        end
        
        if arg == playerName or arg == UnitName("player") then
            print("|cFFFF0000" .. addonName .. "|r: You cannot block yourself!")
            return
        end
        
        if blockedPlayers[arg] then
            print("|cFFFFAA00" .. addonName .. "|r: Player is already blocked:    " .. arg)
            return
        end
        
        blockedPlayers[arg] = SPAM_TYPES.GENERAL_BOOST
        notifiedBlocks[arg] = true
        print("|cFF00FF00" .. addonName .. "|r: Blocked player (this session): " .. arg)
    
    elseif command == "unblock" and arg ~= "" then
        local playerNumber = tonumber(arg)
        
        if playerNumber then
            local sortedList = GetSortedBlockedPlayers()
            if playerNumber > 0 and playerNumber <= #sortedList then
                local playerToUnblock = sortedList[playerNumber]
                blockedPlayers[playerToUnblock] = nil
                notifiedBlocks[playerToUnblock] = nil
                print("|cFF00FF00" .. addonName .. "|r: Unblocked player:   " .. playerToUnblock)
            else
                print("|cFFFF0000" .. addonName ..    "|r: Invalid number.    Use /cf blocked to see the list.")
            end
        else
            if blockedPlayers[arg] then
                blockedPlayers[arg] = nil
                notifiedBlocks[arg] = nil
                print("|cFF00FF00" .. addonName .. "|r: Unblocked player:  " .. arg)
            else
                print("|cFFFF0000" .. addonName ..  "|r: Player not found in block list:    " .. arg)
            end
        end
    
    elseif command == "blocked" then
        local sortedList = GetSortedBlockedPlayers()
        print("|cFF00FF00" .. addonName .. "|r: Blocked players (this session):")
        for i, player in ipairs(sortedList) do
            local classification = blockedPlayers[player] or "Unknown"
            print(i ..    ". " .. player .. " |cFFFFAA00(" .. classification .. ")|r")
        end
        if #sortedList == 0 then
            print("No players currently blocked.")
        else
            print("|cFFFFAA00Use /cf unblock <number> to unblock a player.|r")
        end
    
    elseif command == "clear" then
        filterPatterns = {}
        print("|cFF00FF00" .. addonName .. "|r: All custom filter patterns cleared.")
    
    elseif command == "clearblocked" then
        blockedPlayers = {}
        notifiedBlocks = {}
        print("|cFF00FF00" .. addonName .. "|r: All blocked players cleared.")
    
    else
        print("|cFF00FF00" .. addonName .. "|r: Available commands:")
        print("/chatfilter add <pattern> - Add a custom filter pattern")
        print("/chatfilter remove <pattern> - Remove a custom filter pattern")
        print("/chatfilter list - List pattern counts and custom patterns")
        print("/chatfilter block <player> - Block a player (this session only)")
        print("/chatfilter unblock <number> - Unblock a player by list number")
        print("/chatfilter blocked - List all blocked players with classifications")
        print("/chatfilter clear - Clear custom filter patterns")
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
