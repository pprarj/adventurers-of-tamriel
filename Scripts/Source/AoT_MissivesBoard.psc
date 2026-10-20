Scriptname AoT_MissivesBoard extends ObjectReference
{Guild board trigger - draws band by BandWeight(rank,band) among paid bands,
picks up to 5 slots: 2 rank+1 and 1 rank+2 (E-12, flagged Above Rank).
Reads FLSTs at runtime so SkyPatcher injections are visible. Pattern after
_M_ActivatorScript: proximity trigger, GameDaysPassed gate, BlockActivation,
weighted draw and Quest.Start() - text not copied.}

FormList Property QuestsLow Auto
FormList Property QuestsMed Auto
FormList Property QuestsHigh Auto
FormList Property QuestsVeryHigh Auto

GlobalVariable Property GameDaysPassed Auto
Float Property RefreshGameDays = 1.0 Auto
Float LastUpdate = -100.0

Quest Property AdapterQuest Auto
String Property MissivesPlugin = "Missives.esp" Auto

Event OnTriggerEnter(ObjectReference akActionRef)
    if akActionRef != Game.GetPlayer()
        return
    endif
    if GameDaysPassed != None
        if GameDaysPassed.GetValue() <= LastUpdate + RefreshGameDays
            return
        endif
        LastUpdate = GameDaysPassed.GetValue()
    endif
    ResolveLists()
    BlockActivation(true)
    OfferContracts()
    BlockActivation(false)
EndEvent

Function ResolveLists()
    if QuestsLow == None
        Form fLow = Game.GetFormFromFile(0x001D8F, MissivesPlugin)
        QuestsLow = fLow as FormList
    endif
    if QuestsMed == None
        Form fMed = Game.GetFormFromFile(0x001D90, MissivesPlugin)
        QuestsMed = fMed as FormList
    endif
    if QuestsHigh == None
        Form fHigh = Game.GetFormFromFile(0x001D92, MissivesPlugin)
        QuestsHigh = fHigh as FormList
    endif
    if QuestsVeryHigh == None
        Form fVery = Game.GetFormFromFile(0x009451, MissivesPlugin)
        QuestsVeryHigh = fVery as FormList
    endif
EndFunction

Function OfferContracts()
    int rank = AoT_Core.GetRank()
    int started = 0
    int attempts = 0
    int aboveOne = 0
    int aboveTwo = 0
    while started < 5 && attempts < 30
        attempts += 1
        int band = -1
        bool isAbove = false
        if aboveOne < 2 && rank < AoT_Core.MaxRank()
            band = DrawBandAbove(rank, 1)
            if band >= 0
                isAbove = true
            endif
        endif
        if band < 0 && aboveTwo < 1 && rank + 1 < AoT_Core.MaxRank()
            band = DrawBandAbove(rank, 2)
            if band >= 0
                isAbove = true
            endif
        endif
        if band < 0
            band = DrawBand(rank)
            isAbove = AoT_MissivesAdapter.IsAboveRankNote(band)
        endif
        if band < 0
            return
        endif
        FormList src = BandToFLST(band)
        if src != None && src.GetSize() > 0
            Quest q = PickStartableFromFLST(src)
            if q != None
                string note = ""
                if isAbove
                    note = " [Above Rank]"
                endif
                int id = AoT_Core.OpenContract(q, band)
                if id > 0
                    (AdapterQuest as AoT_MissivesAdapter).RegisterContractQuest(id, q)
                    if isAbove
                        SetAboveRankNote(q, note)
                        if aboveOne < 2 && IsBandFromRank(band, rank + 1)
                            aboveOne += 1
                        elseif aboveTwo < 1 && IsBandFromRank(band, rank + 2)
                            aboveTwo += 1
                        endif
                    endif
                    Debug.Trace("[AoT-MissivesBoard] offering " + q + " band=" + band + note)
                    started += 1
                endif
            endif
        endif
    endwhile
EndFunction

Bool Function IsBandFromRank(int aiBand, int aiRank) Global
    if aiRank < 0 || aiRank > AoT_Core.MaxRank()
        return false
    endif
    int w = AoT_Core.BandWeight(aiRank, aiBand)
    return w > 0
EndFunction

Int Function DrawBand(int aiRank)
    int total = 0
    int b = 0
    while b <= 3
        if AoT_Core.IsBandPaid(b) || b == 0
            int w = AoT_Core.BandWeight(aiRank, b)
            if w > 0
                total += w
            endif
        endif
        b += 1
    endwhile
    if total <= 0
        return -1
    endif
    int roll = Utility.RandomInt(1, total)
    int acc = 0
    b = 0
    while b <= 3
        if AoT_Core.IsBandPaid(b) || b == 0
            int w2 = AoT_Core.BandWeight(aiRank, b)
            if w2 > 0
                acc += w2
                if roll <= acc
                    return b
                endif
            endif
        endif
        b += 1
    endwhile
    return -1
EndFunction

Int Function DrawBandAbove(int aiRank, int aiOffset)
    int targetRank = aiRank + aiOffset
    if targetRank > AoT_Core.MaxRank()
        return -1
    endif
    int total = 0
    int b = 0
    while b <= 3
        if AoT_Core.IsBandPaid(b) || b == 0
            int wCur = AoT_Core.BandWeight(aiRank, b)
            int wTgt = AoT_Core.BandWeight(targetRank, b)
            if wCur == 0 && wTgt > 0
                total += wTgt
            endif
        endif
        b += 1
    endwhile
    if total <= 0
        return -1
    endif
    int roll = Utility.RandomInt(1, total)
    int acc = 0
    b = 0
    while b <= 3
        if AoT_Core.IsBandPaid(b) || b == 0
            int wCur2 = AoT_Core.BandWeight(aiRank, b)
            int wTgt2 = AoT_Core.BandWeight(targetRank, b)
            if wCur2 == 0 && wTgt2 > 0
                acc += wTgt2
                if roll <= acc
                    return b
                endif
            endif
        endif
        b += 1
    endwhile
    return -1
EndFunction

FormList Function BandToFLST(int aiBand)
    if aiBand == 0
        return QuestsLow
    elseif aiBand == 1
        return QuestsMed
    elseif aiBand == 2
        return QuestsHigh
    elseif aiBand == 3
        return QuestsVeryHigh
    endif
    return None
EndFunction

Quest Function PickStartableFromFLST(FormList akFLST)
    int n = akFLST.GetSize()
    if n == 0
        return None
    endif
    int tries = 8
    while tries > 0
        tries -= 1
        int idx = Utility.RandomInt(0, n - 1)
        Form f = akFLST.GetAt(idx)
        Quest q = f as Quest
        if q != None
            if q.IsRunning()
                if q.GetStage() == 0
                    q.SetStage(110)
                endif
            else
                bool ok = q.Start()
                if ok
                    return q
                endif
            endif
        endif
    endwhile
    return None
EndFunction

Function SetAboveRankNote(Quest akQuest, string aNote)
    if akQuest == None || aNote == ""
        return
    endif
    Alias ali = akQuest.GetAliasByName("Missive")
    ObjectReference missiveRef = None
    if ali
        missiveRef = (ali as ReferenceAlias).GetReference()
    else
        Alias ali2 = akQuest.GetNthAlias(6)
        if ali2
            missiveRef = (ali2 as ReferenceAlias).GetReference()
        endif
    endif
    if missiveRef
        string cur = missiveRef.GetDisplayName()
        string newName = cur + aNote
        bool ok = missiveRef.SetDisplayName(newName, true)
        Debug.Trace("[AoT-MissivesBoard] StoresText " + akQuest + " -> " + newName + " ok=" + ok)
    endif
EndFunction
