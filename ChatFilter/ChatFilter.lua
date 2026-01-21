-- ChatFilter: A simple chat filter addon for WoW Classic
-- Filters out unwanted messages from chat channels

local addonName = "ChatFilter"
local filterPatterns = {}
local blockedPlayers = {}
local respondedPlayers = {}
local notifiedBlocks = {}
local spammerMessages = {}
local addonUsers = {}
local playerName = nil
local ADDON_PREFIX = "ChatFilter"
local MSG_PING = "PING"
local MSG_PONG = "PONG"
local DISCOVERY_INTERVAL = 300
local dungeonPatternsCache = nil
local legitKeywordsLookup = {}
local messageLowerCache = {}
local MAX_MESSAGE_CACHE = 100
local patternHits = {}
local patternCheckCount = 0
local PATTERN_REORDER_THRESHOLD = 500

local blockStats = {
    totalBlocks = 0,
    totalMessagesScanned = 0,
    totalSpamFiltered = 0,
    categoryCounts = {},
    playerSpamCounts = {},
    blocksSinceLastReport = 0,
    REPORT_INTERVAL = 30  
}

local function NormalizePlayerName(name)
    if not name or name == "" then
        return ""
    end
    
    if name:find("-") then
        return name
    end
    
    local realm = GetRealmName()
    if realm and realm ~= "" then
        realm = realm:gsub("%s+", "")
        return name .. "-" .. realm
    end
    
    return name
end

local SPAM_TYPES = {
    DUNGEON_BOOST = "Dungeon Boost Spam",
    LEVELING_SERVICE = "Leveling Service Spam",
    POWER_LEVELING = "Power Leveling Spam",
    CARRY_SERVICE = "Carry Service Spam",
    QUEST_SERVICE = "Quest Service Spam",
    GOLD_SELLER = "Gold Seller Spam",
    GENERAL_BOOST = "General Boost Spam",
}

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

local boostSpamPatterns = {
    {pattern = "%a+.*spot.*%d+/%d+", classification = SPAM_TYPES.DUNGEON_BOOST},
    {pattern = "%a+.*spots.*%d+/%d+", classification = SPAM_TYPES.            DUNGEON_BOOST},
    {pattern = "%a+.*%d+.*spot", classification = SPAM_TYPES.            DUNGEON_BOOST},
    {pattern = "%a+.*%d+.*spots", classification = SPAM_TYPES.       DUNGEON_BOOST},
    {pattern = "spot.*%d+/%d+", classification = SPAM_TYPES.          DUNGEON_BOOST},
    {pattern = "spots.*%d+/%d+", classification = SPAM_TYPES.        DUNGEON_BOOST},
    {pattern = "boost.*%d+/%d+", classification = SPAM_TYPES.            DUNGEON_BOOST},
    {pattern = "leveling.*%d+/%d+", classification = SPAM_TYPES.          LEVELING_SERVICE},
    
    {pattern = "boost.*%d+.*mobs", classification = SPAM_TYPES.        DUNGEON_BOOST},
    {pattern = "leveling.*%d+.*mobs", classification = SPAM_TYPES.          LEVELING_SERVICE},
    {pattern = "%d+.*mobs.*boost", classification = SPAM_TYPES.          DUNGEON_BOOST},
    {pattern = "%d+.*mobs.*leveling", classification = SPAM_TYPES.           LEVELING_SERVICE},
    {pattern = "mobs.*boost", classification = SPAM_TYPES.              DUNGEON_BOOST},
    {pattern = "mobs.*leveling", classification = SPAM_TYPES.       LEVELING_SERVICE},
    
    {pattern = "wts.*boost", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "wts.*carry", classification = SPAM_TYPES.       CARRY_SERVICE},
    {pattern = "wts.*power.*level", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "selling.*boost", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "selling.*carry", classification = SPAM_TYPES.         CARRY_SERVICE},
    {pattern = "selling.*power.*level", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "sell.*boost", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "sell.*carry", classification = SPAM_TYPES.        CARRY_SERVICE},
    {pattern = "sell.*power.*level", classification = SPAM_TYPES.      POWER_LEVELING},
    
    {pattern = "service.*boost", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "service.*leveling", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "service.*carry", classification = SPAM_TYPES.        CARRY_SERVICE},
    {pattern = "service.*power.*level", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "boosting.*service", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "leveling.*service", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "carry.*service", classification = SPAM_TYPES.      CARRY_SERVICE},
    
    {pattern = "power.*leveling", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "powerleveling", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "powerlvling", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "power.*lvling", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "power.*level.*service", classification = SPAM_TYPES.      POWER_LEVELING},
    
    {pattern = "boost.*pst", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "boost.*whisper", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*pm", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*w me", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*cheap", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*price", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*gold", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*%d+g[^a-z]", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*fast", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*quick", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "boost.*safe", classification = SPAM_TYPES.      GENERAL_BOOST},
    
    {pattern = "leveling.*service", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "service.*leveling", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "power.*level.*service", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "service.*power.*level", classification = SPAM_TYPES.      POWER_LEVELING},
    
    {pattern = "hi sir.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "hello sir.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "hey sir.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "sir.*you want.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "you want.*boost%?", classification = SPAM_TYPES.          GENERAL_BOOST},
    {pattern = "you want.*power.*level", classification = SPAM_TYPES.       POWER_LEVELING},
    {pattern = "you need.*boost%?", classification = SPAM_TYPES.            GENERAL_BOOST},
    {pattern = "interested.*boost%?", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "interested.*carry%?", classification = SPAM_TYPES.      CARRY_SERVICE},
    {pattern = "interested.*power.*level", classification = SPAM_TYPES.      POWER_LEVELING},
    
    {pattern = "boost.*min.*level", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "boost.*req.*level", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "boost.*required.*level", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "pack.*mobs.*quick", classification = SPAM_TYPES.        DUNGEON_BOOST},
    {pattern = "pack.*mobs.*fast", classification = SPAM_TYPES.       DUNGEON_BOOST},
    {pattern = "mobs.*quick.*time", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "mobs.*fast.*time", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "pack.*mobs.*leveling", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "pack.*mobs.*boost", classification = SPAM_TYPES.      DUNGEON_BOOST},
    
    {pattern = "quick.*time.*price.*pst", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "fast.*time.*price.*pst", classification = SPAM_TYPES.            GENERAL_BOOST},
    
    {pattern = "LEVELING.*SERVICE", classification = SPAM_TYPES.          LEVELING_SERVICE},
    {pattern = "POWER.*LEVELING", classification = SPAM_TYPES.        POWER_LEVELING},
    {pattern = "BOOSTING.*SERVICE", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "SERVICE.*POWER.*LEVELING", classification = SPAM_TYPES.      POWER_LEVELING},
    {pattern = "BOOST.*SERVICE", classification = SPAM_TYPES.            GENERAL_BOOST},
    {pattern = "CARRY.*SERVICE", classification = SPAM_TYPES.       CARRY_SERVICE},
    
    {pattern = "boost.*xp.*hour", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "boost.*exp.*hour", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "fast.*xp.*boost", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "fast.*exp.*boost", classification = SPAM_TYPES.      DUNGEON_BOOST},
    
    {pattern = "merica.*boost", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "merica.*leveling", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "merica.*%d+.*mobs", classification = SPAM_TYPES.      DUNGEON_BOOST},
    
    {pattern = "vendo.*boost", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "vendo.*subida", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "vendo.*carry", classification = SPAM_TYPES.       CARRY_SERVICE},
    {pattern = "vendo.*nivel", classification = SPAM_TYPES.       LEVELING_SERVICE},
    {pattern = "vendiendo.*boost", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "vendiendo.*subida", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "vendiendo.*carry", classification = SPAM_TYPES.       CARRY_SERVICE},
    {pattern = "servicio.*boost", classification = SPAM_TYPES.       GENERAL_BOOST},
    {pattern = "servicio.*subida", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "servicio.*nivel", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "boost.*barato", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "subida.*barato", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "boost.*rapido", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "subida.*rapido", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "subida.*de.*nivel", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "subir.*nivel", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "subir.*de.*nivel", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "mazmorras.*boost", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "mazmorra.*boost", classification = SPAM_TYPES.      DUNGEON_BOOST},
    {pattern = "boost.*oro", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "subida.*oro", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "necesitas.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "necesitas.*subida", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "quieres.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "quieres.*subida", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "interesado.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "interesado.*subida", classification = SPAM_TYPES.      LEVELING_SERVICE},
    {pattern = "hola.*boost", classification = SPAM_TYPES.      GENERAL_BOOST},
    {pattern = "hola.*subida", classification = SPAM_TYPES.      LEVELING_SERVICE},
    
    {pattern = "wts.*quest", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "selling.*quest", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "sell.*quest", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*service", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*help.*gold", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*help.*%d+g", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*completion", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*carry", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*run.*gold", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*run.*%d+g", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "help.*quest.*gold", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "help.*quest.*%d+g", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "help.*with.*quest.*fee", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "quest.*assistance.*gold", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "complete.*quest.*gold", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "complete.*quest.*%d+g", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "doing.*quests.*gold", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "do.*your.*quest", classification = SPAM_TYPES.      QUEST_SERVICE},
    
    {pattern = "vendo.*mision", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "vendo.*quest", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "vendiendo.*mision", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "servicio.*mision", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "ayuda.*mision.*oro", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "completar.*mision.*oro", classification = SPAM_TYPES.      QUEST_SERVICE},
    {pattern = "mision.*servicio", classification = SPAM_TYPES.      QUEST_SERVICE},
}

local function GenerateDungeonPatterns()
    if dungeonPatternsCache then
        return dungeonPatternsCache
    end
    
    local patterns = {}
    local patternCount = 0
    
    local estimatedSize = #dungeonKeywords * 10
    
    for i = 1, #dungeonKeywords do
        local dungeon = dungeonKeywords[i]
        local dungeonLower = dungeon:lower()
        
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*boost", classification = SPAM_TYPES.DUNGEON_BOOST}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*leveling", classification = SPAM_TYPES.LEVELING_SERVICE}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*%d+.*mobs", classification = SPAM_TYPES.DUNGEON_BOOST}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*spot", classification = SPAM_TYPES.DUNGEON_BOOST}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*spots", classification = SPAM_TYPES.DUNGEON_BOOST}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*carry", classification = SPAM_TYPES.CARRY_SERVICE}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*service", classification = SPAM_TYPES.DUNGEON_BOOST}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*xp", classification = SPAM_TYPES.DUNGEON_BOOST}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*exp", classification = SPAM_TYPES.DUNGEON_BOOST}
        patternCount = patternCount + 1
        patterns[patternCount] = {pattern = dungeonLower .. ".*power", classification = SPAM_TYPES.POWER_LEVELING}
    end
    
    dungeonPatternsCache = patterns
    return patterns
end

local goldSellerPatterns = {
    {pattern = "buy.*gold.*www", classification = SPAM_TYPES.      GOLD_SELLER},
    {pattern = "buy.*gold.*%.           com", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "buy.*gold.*%.          net", classification = SPAM_TYPES.      GOLD_SELLER},
    {pattern = "cheap.*gold.*www", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "cheap.*gold.*%.       com", classification = SPAM_TYPES.       GOLD_SELLER},
    {pattern = "sell.*gold.*www", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "selling.*gold.*www", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "gold.*for.*sale.*www", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "www.*gold.*cheap", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "www.*buy.*gold", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "%.           com.*gold", classification = SPAM_TYPES.     GOLD_SELLER},
    {pattern = "gold.*%.          com", classification = SPAM_TYPES.       GOLD_SELLER},
}

local AUTO_RESPONSE = "Sorry, this player does not utilize boosting services. You have been added to a block list and can no longer message this player."

local function InitializeStats()
    for _, spamType in pairs(SPAM_TYPES) do
        blockStats.categoryCounts[spamType] = 0
    end
end

local function InitializeLegitKeywords()
    legitKeywordsLookup = {
        enchant = true, enchanting = true, tailoring = true, blacksmith = true, alchemy = true,
        engineering = true, leatherworking = true, mining = true, herbalism = true, skinning = true,
        flask = true, elixir = true, potion = true, armor = true, weapon = true, ore = true, bar = true,
        herb = true, leather = true, cloth = true, runecloth = true, recipe = true, pattern = true,
        schematic = true, plan = true, epic = true, rare = true, blue = true, purple = true, green = true,
        boe = true, bop = true, crusader = true, fiery = true, lifestealing = true, mongoose = true,
        spellpower = true, healing = true, agility = true, strength = true, stamina = true,
        intellect = true, spirit = true, ["defense"] = true, resistance = true, arcane = true, fire = true,
        frost = true, nature = true, shadow = true, holy = true,
        
        enchanter = true, enchants = true, tailor = true, alchemist = true, engineer = true,
        blacksmithing = true, leatherworker = true, tips = true, lfw = true, lfwork = true,
        
        encantamiento = true, encantar = true, sastreria = true, herreria = true,
        alquimia = true, ingenieria = true, peleteria = true,
        mineria = true, herboristeria = true, desuello = true,
        frasco = true, elixir = true, pocion = true, armadura = true, arma = true,
        mena = true, mineral = true, barra = true, hierba = true, cuero = true, tela = true,
        receta = true, patron = true, esquema = true, plano = true,
        epico = true, raro = true, azul = true, morado = true, verde = true,
    }
end

local function ReorderPatternsByFrequency()
    for i = 1, #boostSpamPatterns do
        local pattern = boostSpamPatterns[i].pattern
        if not patternHits[pattern] then
            patternHits[pattern] = 0
        end
    end
    
    table.sort(boostSpamPatterns, function(a, b)
        local hitsA = patternHits[a.pattern] or 0
        local hitsB = patternHits[b.pattern] or 0
        return hitsA > hitsB
    end)
    
    patternCheckCount = 0
end

local function UpdateBlockStats(spamType)
    blockStats.totalBlocks = blockStats.totalBlocks + 1
    blockStats.blocksSinceLastReport = blockStats.blocksSinceLastReport + 1
    
    if blockStats.categoryCounts[spamType] then
        blockStats.categoryCounts[spamType] = blockStats.categoryCounts[spamType] + 1
    else
        blockStats.categoryCounts[spamType] = 1
    end
    
    if blockStats.blocksSinceLastReport >= blockStats.REPORT_INTERVAL then
        ShowBlockStats()
        blockStats.blocksSinceLastReport = 0
    end
end

function ShowBlockStats()
    print("|cFFFF6B6B============ ChatFilter Statistics =============|r")
    print("|cFF00FF00Total Messages Scanned:|r " .. blockStats.totalMessagesScanned)
    print("|cFF00FF00Total Spam Filtered:|r " .. blockStats.totalSpamFiltered)
    print("|cFF00FF00Unique Spammers Blocked:|r " .. blockStats.totalBlocks)
    
    if blockStats.totalMessagesScanned > 0 then
        local spamRate = (blockStats.totalSpamFiltered / blockStats.totalMessagesScanned) * 100
        print("|cFFFFAA00Spam Detection Rate:|r " .. string.format("%.2f%%", spamRate))
    end
    
    print("|cFFFFAA00Top 3 Spam Offenders:|r")
    local offenders = {}
    for player, count in pairs(blockStats.playerSpamCounts) do
        offenders[#offenders + 1] = {player = player, count = count}
    end
    
    table.sort(offenders, function(a, b) return a.count > b.count end)
    
    local topCount = math.min(3, #offenders)
    if topCount > 0 then
        for i = 1, topCount do
            local classification = blockedPlayers[offenders[i].player] or "Unknown"
            print("  " .. i .. ". |cFFFF6B6B" .. offenders[i].player .. "|r - " .. offenders[i].count .. " spam messages |cFFAA7744(" .. classification .. ")|r")
        end
    else
        print("  No spam detected yet.")
    end
    
    print("|cFFFFAA00Breakdown by Category:|r")
    
    local sortedCategories = {}
    for category, count in pairs(blockStats.categoryCounts) do
        if count > 0 then
            table.insert(sortedCategories, {category = category, count = count})
        end
    end
    
    table.sort(sortedCategories, function(a, b) return a.count > b.count end)
    
    for _, data in ipairs(sortedCategories) do
        print("  |cFF91BE0F" .. data.category .. ":|r " .. data.count)
    end
    print("|cFFFF6B6B Made by oldkingcone. Visit |r|cFF00FFFFhttps://github.com/oldkingcone|r|cFFFF6B6B for more addons or my other fun projects!|r")
    
    print("|cFFFF6B6B==========================================|r")
end

local function InitializeFilters()
    playerName = NormalizePlayerName(UnitName("player"))
    
    InitializeStats()
    InitializeLegitKeywords()
    
    local dungeonPatterns = GenerateDungeonPatterns()
    local currentSize = #boostSpamPatterns
    for i = 1, #dungeonPatterns do
        currentSize = currentSize + 1
        boostSpamPatterns[currentSize] = dungeonPatterns[i]
    end
    
    print("|cFF00FF00" .. addonName .. "|r: Chat filter loaded. Type /chatfilter for commands.")
    print("|cFFFFAA00" .. addonName .. "|r: Block list is temporary (resets each session).")
    print("|cFF00FF00" .. addonName .. "|r: You (" .. playerName .. ") are protected from being filtered.")
    print("|cFF00FF00" .. addonName .. "|r: Guild, Officer, Party, and Raid chats are not filtered.")
    print("|cFF00FF00" .. addonName .. "|r: Legitimate WTS/WTB messages are allowed.")
    print("|cFF00FF00" .. addonName .. "|r: Loaded " .. #boostSpamPatterns .. " boost spam patterns.")
    print("|cFFFFAA00" .. addonName .. "|r: Statistics shown every " .. blockStats.REPORT_INTERVAL .. " blocks.")
end

local function IsGuildRecruitment(lowerMessage)
    local guildPatterns = {
        "guild.*recruit", "recruit.*guild", "recruiting.*for.*guild",
        "guild.*looking.*for", "lfm.*guild", "guild.*lfm",
        "join.*our.*guild", "our.*guild.*is", "guild.*is.*recruiting",
        "new.*guild", "casual.*guild", "raiding.*guild", "pvp.*guild",
        "guild.*needs", "looking.*for.*members", "guild.*members",
        "<.*>.*recruit", "<.*>.*looking", "<.*>.*lfm",
        "recruiting.*members", "recruiting.*raiders", "recruiting.*pvpers",
        "recruiting.*all.*classes", "recruiting.*all.*levels",
        "social.*guild", "leveling.*guild", "friendly.*guild",
        
        "hermandad.*recluta", "recluta.*hermandad", "reclutando.*para.*hermandad",
        "hermandad.*busca", "buscamos.*hermandad", "hermandad.*necesita",
        "unete.*hermandad", "nueva.*hermandad",
        "hermandad.*casual", "hermandad.*raiding", "hermandad.*pvp",
        "hermandad.*social", "hermandad.*amistosa", "hermandad.*reclutando",
        "nuestra.*hermandad", "buscamos.*miembros", "buscamos.*jugadores",
        "reclutando.*miembros", "reclutando.*jugadores", "reclutando.*todas.*clases",
        "<.*>.*recluta", "<.*>.*busca", "<.*>.*necesita",
        "guild.*espanol", "hermandad.*espanol", "guild.*hispana",
        "hermandad.*hispana", "guild.*latina", "hermandad.*latina",
    }
    
    for i = 1, #guildPatterns do
        if lowerMessage:find(guildPatterns[i]) then
            return true
        end
    end
    
    return false
end

local function HasItemLinks(message)
    if message:find("|Hitem:") or message:find("|h%[.-%]|h") then
        return true
    end
    
    if message:find("%[.-%]") then
        return true
    end
    
    return false
end

local function IsProfessionService(lowerMessage)
    local professionPatterns = {
        "enchanter.*lfw", "lfw.*enchanter", "lfw.*enchant",
        "enchants.*available", "enchanting.*service", "enchanter.*here",
        "tailor.*lfw", "lfw.*tailor", "tailoring.*service",
        "blacksmith.*lfw", "lfw.*blacksmith", "bs.*lfw",
        "alchemist.*lfw", "lfw.*alchemist", "alchemy.*service",
        "engineer.*lfw", "lfw.*engineer", "engineering.*service",
        "leatherworker.*lfw", "lfw.*leatherwork", "lw.*lfw",
        "enchanter.*pst", "tips.*enchant", "free.*enchant",
        "enchants.*tips", "offering.*enchant",
    }
    
    for i = 1, #professionPatterns do
        if lowerMessage:find(professionPatterns[i]) then
            return true
        end
    end
    
    return false
end

local function IsLegitimateTradeMessage(lowerMessage)
    if not (lowerMessage:find("wts", 1, true) or lowerMessage:find("wtb", 1, true) or 
            lowerMessage:find("selling", 1, true) or lowerMessage:find("buying", 1, true) or
            lowerMessage:find("lfw", 1, true) or lowerMessage:find("lfwork", 1, true) or
            lowerMessage:find("vendo", 1, true) or lowerMessage:find("compro", 1, true) or
            lowerMessage:find("vendiendo", 1, true) or lowerMessage:find("comprando", 1, true)) then
        return false
    end
    
    for keyword, _ in pairs(legitKeywordsLookup) do
        if lowerMessage:find(keyword, 1, true) then
            return true
        end
    end
    
    return false
end

local function DetectSpamType(message)
    blockStats.totalMessagesScanned = blockStats.totalMessagesScanned + 1
    
    local lowerMessage = messageLowerCache[message]
    if not lowerMessage then
        lowerMessage = message:lower()
        if next(messageLowerCache) and #messageLowerCache >= MAX_MESSAGE_CACHE then
            messageLowerCache = {}
        end
        messageLowerCache[message] = lowerMessage
    end
    
    if HasItemLinks(message) then
        if IsLegitimateTradeMessage(lowerMessage) or IsProfessionService(lowerMessage) then
            return nil
        end
    end
    
    if IsGuildRecruitment(lowerMessage) then
        return nil
    end
    
    if IsProfessionService(lowerMessage) then
        return nil
    end
    
    if IsLegitimateTradeMessage(lowerMessage) then
        return nil
    end
    
    patternCheckCount = patternCheckCount + 1
    
    if patternCheckCount >= PATTERN_REORDER_THRESHOLD then
        ReorderPatternsByFrequency()
    end
    
    for i = 1, #boostSpamPatterns do
        if lowerMessage:find(boostSpamPatterns[i].pattern) then
            local pattern = boostSpamPatterns[i].pattern
            patternHits[pattern] = (patternHits[pattern] or 0) + 1
            return boostSpamPatterns[i].classification
        end
    end
    
    for i = 1, #goldSellerPatterns do
        if lowerMessage:find(goldSellerPatterns[i].pattern) then
            return goldSellerPatterns[i].classification
        end
    end
    
    for i = 1, #filterPatterns do
        if lowerMessage:find(filterPatterns[i]) then
            return SPAM_TYPES.GENERAL_BOOST
        end
    end
    
    return nil
end

local function StoreSpammerMessage(normalizedSender, message)
    local messages = spammerMessages[normalizedSender]
    if not messages then
        messages = {}
        spammerMessages[normalizedSender] = messages
    end
    
    local count = #messages
    if count >= 3 then
        messages[1] = messages[2]
        messages[2] = messages[3]
        messages[3] = message
    else
        messages[count + 1] = message
    end
end

local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX then
        return
    end
    
    local normalizedSender = NormalizePlayerName(sender)
    
    if normalizedSender == playerName then
        return
    end
    
    if message == MSG_PING then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, MSG_PONG, channel)
        addonUsers[normalizedSender] = time()
    elseif message == MSG_PONG then
        addonUsers[normalizedSender] = time()
    end
end

local function SendDiscoveryPing()
    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, MSG_PING, "GUILD")
    end
    
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, MSG_PING, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, MSG_PING, "PARTY")
    end
end

local function CleanupAddonUsers()
    local currentTime = time()
    local cutoff = currentTime - 1800
    
    for user, lastSeen in pairs(addonUsers) do
        if lastSeen < cutoff then
            addonUsers[user] = nil
        end
    end
end

local function GetSortedAddonUsers()
    local sortedList = {}
    local count = 0
    
    for user, _ in pairs(addonUsers) do
        count = count + 1
        sortedList[count] = user
    end
    
    table.sort(sortedList)
    return sortedList, count
end

local function GetEventChannelName(event, ...)
    if event == "CHAT_MSG_WHISPER" then
        return "Whisper"
    elseif event == "CHAT_MSG_SAY" then
        return "Say"
    elseif event == "CHAT_MSG_YELL" then
        return "Yell"
    elseif event == "CHAT_MSG_CHANNEL" then
        local channelName = select(9, ...)
        if channelName and channelName ~= "" then
            return channelName
        end
        
        local channelNumber = select(8, ...)
        if channelNumber and channelNumber > 0 then
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

local function SafeBlockPlayer(normalizedSender, spamType)
    if normalizedSender == playerName then
        print("|cFFFF0000[ChatFilter]|r ERROR: Attempted to block yourself! Protection prevented this.")
        return false
    end
    
    if blockedPlayers[normalizedSender] then
        return false
    end
    
    blockedPlayers[normalizedSender] = spamType
    notifiedBlocks[normalizedSender] = true
    
    UpdateBlockStats(spamType)
    
    return true
end

local function WhisperChatFilter(self, event, message, sender, ...)
    local normalizedSender = NormalizePlayerName(sender)
    
    if normalizedSender == playerName then
        return false
    end
    
    if blockedPlayers[normalizedSender] then
        blockStats.totalSpamFiltered = blockStats.totalSpamFiltered + 1
        
        blockStats.playerSpamCounts[normalizedSender] = (blockStats.playerSpamCounts[normalizedSender] or 0) + 1
        
        return true
    end
    
    local spamType = DetectSpamType(message)
    if spamType then
        blockStats.totalSpamFiltered = blockStats.totalSpamFiltered + 1
        
        blockStats.playerSpamCounts[normalizedSender] = (blockStats.playerSpamCounts[normalizedSender] or 0) + 1
        
        StoreSpammerMessage(normalizedSender, message)
        
        SafeBlockPlayer(normalizedSender, spamType)
        
        if not respondedPlayers[normalizedSender] then
            SendChatMessage(AUTO_RESPONSE, "WHISPER", nil, sender)
            respondedPlayers[normalizedSender] = true
        end
        
        return true
    end
    
    return false
end

local function ChatFilter(self, event, message, sender, ...)
    local normalizedSender = NormalizePlayerName(sender)
    
    if normalizedSender == playerName then
        return false
    end
    
    if blockedPlayers[normalizedSender] then
        blockStats.totalSpamFiltered = blockStats.totalSpamFiltered + 1
        blockStats.playerSpamCounts[normalizedSender] = (blockStats.playerSpamCounts[normalizedSender] or 0) + 1
        
        return true
    end
    
    local spamType = DetectSpamType(message)
    if spamType then
        blockStats.totalSpamFiltered = blockStats.totalSpamFiltered + 1
        
        blockStats.playerSpamCounts[normalizedSender] = (blockStats.playerSpamCounts[normalizedSender] or 0) + 1
        
        StoreSpammerMessage(normalizedSender, message)
        
        SafeBlockPlayer(normalizedSender, spamType)
        return true
    end
    
    return false
end

local function RegisterFilters()
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", WhisperChatFilter)
    
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChatFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", ChatFilter)
    
    print("|cFF00FF00" .. addonName .. "|r:            Filtering Whispers, General, Trade, LFG, Say, and Yell.")
end

local function GetSortedBlockedPlayers()
    local sortedList = {}
    local count = 0
    
    for player, _ in pairs(blockedPlayers) do
        count = count + 1
        sortedList[count] = player
    end
    
    table.sort(sortedList)
    return sortedList
end

SLASH_CHATFILTER1 = "/chatfilter"
SLASH_CHATFILTER2 = "/cf"
SlashCmdList["CHATFILTER"] = function(msg)
    msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
    
    local command, arg = msg:match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()
    arg = arg or ""
    
    if command == "add" and arg ~= "" then
        local lowerArg = arg:lower()
        filterPatterns[#filterPatterns + 1] = lowerArg
        print("|cFF00FF00" .. addonName .. "|r: Added filter pattern: " .. arg)
    
    elseif command == "remove" and arg ~= "" then
        local lowerArg = arg:lower()
        for i = 1, #filterPatterns do
            if filterPatterns[i] == lowerArg then
                table.remove(filterPatterns, i)
                print("|cFF00FF00" .. addonName .. "|r: Removed filter pattern: " .. arg)
                return
            end
        end
        print("|cFFFF0000" .. addonName .. "|r: Pattern not found: " .. arg)
    
    elseif command == "list" then
        print("|cFF00FF00" .. addonName .. "|r: Active patterns: " .. #boostSpamPatterns .. " boost spam, " .. #goldSellerPatterns .. " gold seller")
        if #filterPatterns > 0 then
            print("|cFF00FF00" .. addonName .. "|r: Custom filter patterns:")
            for i = 1, #filterPatterns do
                print(i .. ". " .. filterPatterns[i])
            end
        end
    
    elseif command == "stats" then
        ShowBlockStats()
    
    elseif command == "block" and arg ~= "" then
        if not playerName then
            playerName = NormalizePlayerName(UnitName("player"))
        end
        
        local normalizedArg = NormalizePlayerName(arg)
        
        if normalizedArg == playerName then
            print("|cFFFF0000" .. addonName .. "|r:  You cannot block yourself!")
            return
        end
        
        if blockedPlayers[normalizedArg] then
            print("|cFFFFAA00" .. addonName .. "|r: Player is already blocked:            " .. normalizedArg)
            return
        end
        
        blockedPlayers[normalizedArg] = SPAM_TYPES.GENERAL_BOOST
        notifiedBlocks[normalizedArg] = true
        UpdateBlockStats(SPAM_TYPES.GENERAL_BOOST)
        print("|cFF00FF00" .. addonName .. "|r: Blocked player (this session): " .. normalizedArg)
    
    elseif command == "unblock" and arg ~= "" then
        local playerNumber = tonumber(arg)
        
        if playerNumber then
            local sortedList = GetSortedBlockedPlayers()
            if playerNumber > 0 and playerNumber <= #sortedList then
                local playerToUnblock = sortedList[playerNumber]
                blockedPlayers[playerToUnblock] = nil
                notifiedBlocks[playerToUnblock] = nil
                print("|cFF00FF00" .. addonName ..  "|r: Unblocked player:          " .. playerToUnblock)
            else
                print("|cFFFF0000" .. addonName ..            "|r: Invalid number.            Use /cf blocked to see the list.")
            end
        else
            local normalizedArg = NormalizePlayerName(arg)
            if blockedPlayers[normalizedArg] then
                blockedPlayers[normalizedArg] = nil
                notifiedBlocks[normalizedArg] = nil
                print("|cFF00FF00" .. addonName .. "|r: Unblocked player:         " .. normalizedArg)
            else
                print("|cFFFF0000" .. addonName ..       "|r: Player not found in block list:            " .. normalizedArg)
            end
        end
    
    elseif command == "blocked" then
        local sortedList = GetSortedBlockedPlayers()
        local count = #sortedList
        print("|cFF00FF00" .. addonName .. "|r: Blocked players (this session):")
        for i = 1, count do
            local player = sortedList[i]
            local classification = blockedPlayers[player] or "Unknown"
            print(i .. ". " .. player .. " |cFFFFAA00(" .. classification .. ")|r")
        end
        if count == 0 then
            print("No players currently blocked.")
        else
            print("|cFFFFAA00Use /cf unblock <number> to unblock a player.|r")
        end
    
    elseif command == "clear" then
        filterPatterns = {}
        print("|cFF00FF00" .. addonName .. "|r:  All custom filter patterns cleared.")
    
    elseif command == "clearblocked" then
        blockedPlayers = {}
        notifiedBlocks = {}
        print("|cFF00FF00" .. addonName .. "|r: All blocked players cleared.")
    
    elseif command == "messages" and arg ~= "" then
        local playerNumber = tonumber(arg)
        local targetPlayer = nil
        
        if playerNumber then
            local sortedList = GetSortedBlockedPlayers()
            if playerNumber > 0 and playerNumber <= #sortedList then
                targetPlayer = sortedList[playerNumber]
            else
                print("|cFFFF0000" .. addonName .. "|r: Invalid number. Use /cf blocked to see the list.")
                return
            end
        else
            targetPlayer = NormalizePlayerName(arg)
        end
        
        if targetPlayer and spammerMessages[targetPlayer] then
            local messages = spammerMessages[targetPlayer]
            local classification = blockedPlayers[targetPlayer] or "Unknown"
            print("|cFF00FF00" .. addonName .. "|r: Last " .. #messages .. " message(s) from |cFFFF6B6B" .. targetPlayer .. "|r |cFFAA7744(" .. classification .. ")|r:")
            for i = 1, #messages do
                print("  " .. i .. ". |cFFFFFFFF" .. messages[i] .. "|r")
            end
        elseif targetPlayer then
            print("|cFFFF0000" .. addonName .. "|r: No messages stored for " .. targetPlayer)
        end
    
    elseif command == "discover" then
        CleanupAddonUsers()
        SendDiscoveryPing()
        print("|cFF00FF00" .. addonName .. "|r: Sending discovery ping to guild/party/raid...")
        print("|cFFFFAA00" .. addonName .. "|r: Use /cf users after a few seconds to see results.")
    
    elseif command == "users" then
        CleanupAddonUsers()
        local sortedList, count = GetSortedAddonUsers()
        
        if count > 0 then
            print("|cFF00FF00" .. addonName .. "|r: Detected " .. count .. " other user(s) of this addon:")
            for i = 1, count do
                local lastSeen = addonUsers[sortedList[i]]
                local timeDiff = time() - lastSeen
                local timeStr
                if timeDiff < 60 then
                    timeStr = "just now"
                elseif timeDiff < 3600 then
                    timeStr = math.floor(timeDiff / 60) .. "m ago"
                else
                    timeStr = math.floor(timeDiff / 3600) .. "h ago"
                end
                print("  " .. i .. ". |cFF00FF00" .. sortedList[i] .. "|r (" .. timeStr .. ")")
            end
        else
            print("|cFFFFAA00" .. addonName .. "|r: No other addon users detected.")
            print("|cFFFFAA00" .. addonName .. "|r: Use /cf discover to search for users in your guild/party/raid.")
        end
    
    else
        print("|cFF00FF00" .. addonName .. "|r: Available commands:")
        print("/chatfilter add <pattern> - Add a custom filter pattern")
        print("/chatfilter remove <pattern> - Remove a custom filter pattern")
        print("/chatfilter list - List pattern counts and custom patterns")
        print("/chatfilter stats - Show current blocking statistics")
        print("/chatfilter block <player> - Block a player (this session only)")
        print("/chatfilter unblock <number> - Unblock a player by list number")
        print("/chatfilter blocked - List all blocked players with classifications")
        print("/chatfilter messages <player|number> - Show last 3 messages from a spammer")
        print("/chatfilter discover - Find other users of this addon in guild/party/raid")
        print("/chatfilter users - List detected addon users")
        print("/chatfilter clear - Clear custom filter patterns")
        print("/chatfilter clearblocked - Clear all blocked players")
    end
end

local eventFrame = CreateFrame("Frame")
local lastDiscoveryTime = 0
local timeSinceLastUpdate = 0

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            InitializeFilters()
            RegisterFilters()
            
            C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
            
            lastDiscoveryTime = time()
        end
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(5, SendDiscoveryPing)
    end
end)

local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    
    if timeSinceLastUpdate >= 1 then
        timeSinceLastUpdate = 0
        local currentTime = time()
        
        if currentTime - lastDiscoveryTime >= DISCOVERY_INTERVAL then
            SendDiscoveryPing()
            CleanupAddonUsers()
            lastDiscoveryTime = currentTime
        end
    end
end)
