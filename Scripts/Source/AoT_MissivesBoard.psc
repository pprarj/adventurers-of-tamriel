Scriptname AoT_MissivesBoard extends ObjectReference
{Guild board trigger. Draws a band by BandWeight(rank, band) among the paid bands
and offers up to 5 quests: 2 from a band that exists at rank+1 and not at rank,
1 from a band that exists at rank+2 and not at rank+1, flagged "[Above Rank]" (D005).
Reads the FormLists at runtime so SkyPatcher injections are visible. Pattern after
the Missives activator script: proximity trigger, GameDaysPassed gate, BlockActivation,
weighted draw and Quest.Start(); no text copied.
Offering is not taking: the quest is only REGISTERED as an offer here, and the
contract opens in the ledger when the player accepts it (D026).}

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
    if GameDaysPassed == None
        ; Skyrim.esm GameDaysPassed: without it the one-day gate would never apply.
        GameDaysPassed = Game.GetForm(0x00000039) as GlobalVariable
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
    AoT_MissivesAdapter adapter = AdapterQuest as AoT_MissivesAdapter
    if adapter == None
        ; A quest started without the adapter could never be tracked.
        Debug.Trace("[AoT-MissivesBoard] AdapterQuest not set: nothing offered")
        return
    endif
    int rank = AoT_Core.GetRank()
    int started = 0
    int attempts = 0
    int aboveOne = 0
    int aboveTwo = 0
    while started < 5 && attempts < 30
        attempts += 1
        int band = -1
        int aboveKind = 0
        if aboveOne < 2 && rank < AoT_Core.MaxRank()
            band = DrawBandAbove(rank, 1)
            if band >= 0
                aboveKind = 1
            endif
        endif
        if band < 0 && aboveTwo < 1 && rank + 1 < AoT_Core.MaxRank()
            band = DrawBandAbove(rank, 2)
            if band >= 0
                aboveKind = 2
            endif
        endif
        if band < 0
            band = DrawBand(rank)
        endif
        if band < 0
            return
        endif
        FormList src = BandToFLST(band)
        if src != None && src.GetSize() > 0
            Quest q = PickStartableFromFLST(src)
            if q != None
                string note = ""
                if aboveKind > 0
                    note = " [Above Rank]"
                    SetAboveRankNote(q, note)
                    if aboveKind == 1
                        aboveOne += 1
                    else
                        aboveTwo += 1
                    endif
                endif
                adapter.RegisterOffer(q, band)
                Debug.Trace("[AoT-MissivesBoard] offering " + q + " band=" + band + note)
                started += 1
            endif
        endif
    endwhile
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
    {A band that exists at rank + aiOffset and NOT at the rank right below it
    (rank + aiOffset - 1), weighted by its weight at rank + aiOffset (D005).}
    int targetRank = aiRank + aiOffset
    if targetRank > AoT_Core.MaxRank()
        return -1
    endif
    int baseRank = targetRank - 1
    int total = 0
    int b = 0
    while b <= 3
        if AoT_Core.IsBandPaid(b) || b == 0
            int wBase = AoT_Core.BandWeight(baseRank, b)
            int wTgt = AoT_Core.BandWeight(targetRank, b)
            if wBase == 0 && wTgt > 0
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
            int wBase2 = AoT_Core.BandWeight(baseRank, b)
            int wTgt2 = AoT_Core.BandWeight(targetRank, b)
            if wBase2 == 0 && wTgt2 > 0
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
        Debug.Trace("[AoT-MissivesBoard] note " + akQuest + " -> " + newName + " ok=" + ok)
    endif
EndFunction
