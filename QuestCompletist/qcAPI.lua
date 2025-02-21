-- API compatibility layer
local function GetQuestLogIndexByID(questID)
    if not questID then return nil end
    
    -- For classic WoW
    if GetNumQuestLogEntries then
        local numEntries = GetNumQuestLogEntries()
        for i=1, numEntries do
            local _, _, _, _, _, _, _, questId = GetQuestLogTitle(i)
            if questId and questId == questID then
                return i
            end
        end
        return nil
    end
    
    -- For retail WoW
    if C_QuestLog then
        -- Try direct method first
        if C_QuestLog.GetLogIndexForQuestID then
            return C_QuestLog.GetLogIndexForQuestID(questID)
        end
        -- Fallback to info method
        if C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(questID)
            return info and info.questLogIndex
        end
    end
    
    return nil
end

-- Create global API object
qcAPI = {
    GetLogIndexForQuestID = GetQuestLogIndexByID,
}

-- Make available through C_QuestLog for compatibility
if not C_QuestLog then
    C_QuestLog = {}
end
C_QuestLog.GetLogIndexForQuestID = GetQuestLogIndexByID 