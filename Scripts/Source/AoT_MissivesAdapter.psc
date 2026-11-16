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
    ApplyTownRule()
    RegisterForSingleUpdateGameTime(PollHours)
EndEvent

; OnPlayerLoadGame is declared by Actor and ReferenceAlias, NOT by Quest, so it never
; fires here; the load hook lives in AoT_MissivesAdapter_Player (ReferenceAlias).

Event OnUpdateGameTime()
    RegisterForSingleUpdateGameTime(PollHours)
    ApplyViaC()
    ApplyTownRule()
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

; -- Fase 14 etapa 2 (R1, caminho 1): a Missives quest turned in to the Steward or the Jarl (an alias named "Steward",
; stage 40 = come back for the reward) is also turned in at the attendant, by the report topic. Our line only sets
; stage 100, the same as their own turn-in line; Missives pays at 100. No record of theirs is edited.

Bool Function IsStewardReady(Quest akQuest)
    if akQuest == None || !akQuest.IsRunning() || akQuest.GetAliasByName("Steward") == None
        return false
    endif
    return akQuest.IsStageDone(40) && !akQuest.IsStageDone(100) && !akQuest.IsStageDone(105) && !akQuest.IsStageDone(110)
EndFunction

Int Function CountStewardReady()
    {Open contracts of ours whose Missives quest waits at the Steward stage.}
    int n = 0
    int count = StorageUtil.IntListCount(None, "aot_open")
    int i = 0
    while i < count
        Quest q = StorageUtil.GetFormValue(None, "aot_missives_q" + StorageUtil.IntListGet(None, "aot_open", i), None) as Quest
        if IsStewardReady(q)
            n += 1
        endif
        i += 1
    endwhile
    return n
EndFunction

Int Function DeliverStewardReady()
    {Sets stage 100 on each of them (Missives pays the gold), then closes the ledger entries at once (points).}
    int n = 0
    int i = StorageUtil.IntListCount(None, "aot_open") - 1
    while i >= 0
        Quest q = StorageUtil.GetFormValue(None, "aot_missives_q" + StorageUtil.IntListGet(None, "aot_open", i), None) as Quest
        if IsStewardReady(q)
            bool ok = q.SetStage(100)
            Debug.Trace("[AoT-F14] report at the attendant q=" + q + " formid=" + q.GetFormID() + " stage100=" + ok)
            n += 1
        endif
        i -= 1
    endwhile
    if n > 0
        PollOpenContracts()
    endif
    return n
EndFunction

; -- Fase 14 etapa 2 (C3a): the town boards of Missives leave the world while this adapter runs. Their 14 refs (all
; persistent, read from Missives.esp: one per walled city in its own world and its twin in Tamriel, one per town) are
; disabled at runtime, and the Low and Med quest chances of the town triggers go to 0 as High and VeryHigh already do
; (D005 via(c)), so a trigger neither starts a quest nor cleans up (stage 110) an offer of the guild board. No record
; of theirs is edited.

Int[] Function TownBoardIds() Global
    Int[] ids = new Int[14]
    ids[0] = 0x0012CC
    ids[1] = 0x021846
    ids[2] = 0x009477
    ids[3] = 0x02183A
    ids[4] = 0x009491
    ids[5] = 0x021844
    ids[6] = 0x00948F
    ids[7] = 0x021838
    ids[8] = 0x0094A2
    ids[9] = 0x021840
    ids[10] = 0x0094AE
    ids[11] = 0x0094A6
    ids[12] = 0x0094AA
    ids[13] = 0x0094B2
    return ids
EndFunction

Function ApplyTownRule()
    Int[] ids = TownBoardIds()
    int hid = 0
    int i = 0
    while i < ids.Length
        ObjectReference r = Game.GetFormFromFile(ids[i], "Missives.esp") as ObjectReference
        if r && !r.IsDisabled()
            r.Disable()
            hid += 1
        endif
        i += 1
    endwhile
    int zeroed = 0
    GlobalVariable low = Game.GetFormFromFile(0x001D93, "Missives.esp") as GlobalVariable
    if low && low.GetValue() != 0.0
        low.SetValue(0.0)
        zeroed += 1
    endif
    GlobalVariable med = Game.GetFormFromFile(0x001D94, "Missives.esp") as GlobalVariable
    if med && med.GetValue() != 0.0
        med.SetValue(0.0)
        zeroed += 1
    endif
    if hid > 0 || zeroed > 0
        Debug.Trace("[AoT-F14] town boards: " + hid + " of " + ids.Length + " disabled now, Low/Med chances set to 0: " + zeroed)
    endif
EndFunction

Function RegisterOffer(Quest akQuest, int aiBand)
    {Called by the board after a successful Quest.Start(). Offering is not taking.}
    if akQuest
        StorageUtil.SetIntValue(akQuest, "aot_offer_band", aiBand)
        StorageUtil.FormListAdd(None, "aot_missives_offer", akQuest, False)
        Debug.Trace("[AoT-Missives] offer q=" + akQuest + " band=" + aiBand)
    endif
EndFunction

; -- Fase 15 etapa 1 (D089, R4-3): a contract abandoned at the attendant leaves the journal. The ledger entry is already
; closed (state 3, out of aot_open, so the polling no longer sees it); the quest goes to its own cleanup stage 110, the
; one Missives sets when a note expires unread. Their record is not edited; only a running quest that reached none of
; 100, 105 or 110 is touched.

Bool Function CleanUpAbandoned(int aiId)
    Quest q = StorageUtil.GetFormValue(None, "aot_missives_q" + aiId, None) as Quest
    if q == None
        return false
    endif
    if !q.IsRunning() || q.IsStageDone(100) || q.IsStageDone(105) || q.IsStageDone(110)
        Debug.Trace("[AoT-F15] abandon missives q=" + q + " id=" + aiId + " left as is (running=" + q.IsRunning() + ")")
        return false
    endif
    bool ok = q.SetStage(110)
    Debug.Trace("[AoT-F15] abandon missives q=" + q + " id=" + aiId + " stage110=" + ok + " running=" + q.IsRunning())
    return ok
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
