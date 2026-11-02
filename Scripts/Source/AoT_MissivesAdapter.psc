Scriptname AoT_MissivesAdapter extends Quest
{Missives adapter: polls the offered and the open contracts once per game hour,
and re-applies the D005 via(c) chance globals.
Quest SGE, attached to AdventurersOfTamriel_Missives.esp.
A quest the board started is an OFFER (aot_missives_offer). The contract opens in
the ledger when the player takes the note (the Missives alias script writes stage 20
on pickup), and closes by the stage the quest reaches (D026).}

GlobalVariable Property HighChance Auto
GlobalVariable Property VeryHighChance Auto

Float Property PollHours = 1.0 Auto

Event OnInit()
    ResolveGlobals()
    ApplyViaC()
    RegisterForSingleUpdateGameTime(PollHours)
EndEvent

; OnPlayerLoadGame is declared by Actor and ReferenceAlias, NOT by Quest, so it never
; fires here; the load hook lives in AoT_MissivesAdapter_Player (ReferenceAlias).

Event OnUpdateGameTime()
    RegisterForSingleUpdateGameTime(PollHours)
    ApplyViaC()
    PollOffers()
    PollOpenContracts()
EndEvent

Function ResolveGlobals()
    if HighChance == None
        Form f = Game.GetFormFromFile(0x001D95, "Missives.esp")
        HighChance = f as GlobalVariable
    endif
    if VeryHighChance == None
        Form f2 = Game.GetFormFromFile(0x009450, "Missives.esp")
        VeryHighChance = f2 as GlobalVariable
    endif
EndFunction

Function ApplyViaC()
    ; D005 via(c): zero High/VeryHigh on town boards; re-apply after the settings loader
    if HighChance
        if HighChance.GetValue() != 0.0
            HighChance.SetValue(0.0)
            Debug.Trace("[AoT-Missives] via(c) High -> 0")
        endif
    endif
    if VeryHighChance
        if VeryHighChance.GetValue() != 0.0
            VeryHighChance.SetValue(0.0)
            Debug.Trace("[AoT-Missives] via(c) VeryHigh -> 0")
        endif
    endif
EndFunction

Function PollOffers()
    {An offer becomes a contract when its quest reached stage 20 (the player took the
    note). An offer whose quest stopped or ended before that is dropped: no contract,
    no points. Walks back to front because entries are removed on the way.}
    int count = StorageUtil.FormListCount(None, "aot_missives_offer")
    int i = count - 1
    while i >= 0
        Quest q = StorageUtil.FormListGet(None, "aot_missives_offer", i) as Quest
        if q == None
            StorageUtil.FormListRemoveAt(None, "aot_missives_offer", i)
        elseif q.IsStageDone(20)
            int band = StorageUtil.GetIntValue(q, "aot_offer_band", 0)
            int id = AoT_Core.OpenContract(q, band)
            Debug.Trace("[AoT-Missives] poll Open q=" + q + " band=" + band + " id=" + id)
            if id > 0
                RegisterContractQuest(id, q)
                StorageUtil.FormListRemoveAt(None, "aot_missives_offer", i)
            endif
        elseif q.IsStageDone(105) || q.IsStageDone(110) || !q.IsRunning()
            Debug.Trace("[AoT-Missives] poll Offer dropped q=" + q)
            StorageUtil.FormListRemoveAt(None, "aot_missives_offer", i)
        endif
        i -= 1
    endwhile
EndFunction

Function PollOpenContracts()
    {Completion = stage 100 (all families), expiration = 103 (courier only),
    failure = 105 (counted as an expiration: their delivery was not met), cleanup = 110. A contract whose quest was cleaned up without
    any of the first three never stood: it closes void, with no points (D026).
    Walks back to front because aot_open loses the entry it closes.}
    int count = StorageUtil.IntListCount(None, "aot_open")
    if count == 0
        return
    endif
    float t0 = Utility.GetCurrentRealTime()
    int i = count - 1
    while i >= 0
        int id = StorageUtil.IntListGet(None, "aot_open", i)
        Quest q = StorageUtil.GetFormValue(None, "aot_missives_q" + id, None) as Quest
        if q
            if q.IsStageDone(100)
                bool ok = AoT_Core.CompleteContract(id)
                Debug.Trace("[AoT-Missives] poll Complete id=" + id + " q=" + q + " ok=" + ok)
            elseif q.IsStageDone(103)
                bool ok2 = AoT_Core.ExpireContract(id)
                Debug.Trace("[AoT-Missives] poll Expire id=" + id + " q=" + q + " ok=" + ok2)
            elseif q.IsStageDone(105)
                bool ok3 = AoT_Core.ExpireContract(id)
                Debug.Trace("[AoT-Missives] poll Fail id=" + id + " q=" + q + " ok=" + ok3)
            elseif q.IsStageDone(110)
                bool ok4 = AoT_Core.VoidContract(id)
                Debug.Trace("[AoT-Missives] poll Void id=" + id + " q=" + q + " ok=" + ok4)
            endif
        endif
        i -= 1
    endwhile
    float dt = Utility.GetCurrentRealTime() - t0
    Debug.Trace("[AoT-Missives] poll " + count + " open in " + dt + "s")
EndFunction

Function RegisterOffer(Quest akQuest, int aiBand)
    {Called by the board after a successful Quest.Start(). Offering is not taking.}
    if akQuest
        StorageUtil.SetIntValue(akQuest, "aot_offer_band", aiBand)
        StorageUtil.FormListAdd(None, "aot_missives_offer", akQuest, False)
        Debug.Trace("[AoT-Missives] offer q=" + akQuest + " band=" + aiBand)
    endif
EndFunction

Function RegisterContractQuest(int aiId, Quest akQuest)
    {Remembers which quest a ledger id belongs to, for the polling.}
    if aiId > 0 && akQuest
        StorageUtil.SetFormValue(None, "aot_missives_q" + aiId, akQuest)
        Debug.Trace("[AoT-Missives] register id=" + aiId + " q=" + akQuest)
    endif
EndFunction

Bool Function IsAboveRankNote(int aiBand) Global
    int rank = AoT_Core.GetRank()
    if rank < AoT_Core.MaxRank()
        int w = AoT_Core.BandWeight(rank, aiBand)
        if w == 0
            return true
        endif
    endif
    return false
EndFunction
