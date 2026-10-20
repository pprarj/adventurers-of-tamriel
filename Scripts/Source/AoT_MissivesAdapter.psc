Scriptname AoT_MissivesAdapter extends Quest
{AoT Missives adapter - polling over aot_open, E-12 and via(c).
Quest SGE, attached to AdventurersOfTamriel_Missives.esp.
Polls once per game hour; re-applies via(c) after load.}

GlobalVariable Property HighChance Auto
GlobalVariable Property VeryHighChance Auto

Float Property PollHours = 1.0 Auto

Event OnInit()
    ResolveGlobals()
    ApplyViaC()
    RegisterForSingleUpdateGameTime(PollHours)
EndEvent

Event OnPlayerLoadGame()
    ResolveGlobals()
    ApplyViaC()
    RegisterForSingleUpdateGameTime(PollHours)
EndEvent

Event OnUpdateGameTime()
    RegisterForSingleUpdateGameTime(PollHours)
    ApplyViaC()
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
    ; D-30 via(c): zero High/VeryHigh on town boards; re-apply after SettingsLoader
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

Function PollOpenContracts()
    int count = StorageUtil.IntListCount(None, "aot_open")
    if count == 0
        return
    endif
    float t0 = Utility.GetCurrentRealTime()
    int i = 0
    while i < count
        int id = StorageUtil.IntListGet(None, "aot_open", i)
        Form f = StorageUtil.GetFormValue(None, "aot_missives_q" + id, None)
        Quest q = f as Quest
        if q
            ; completion = stage 100 (all families), expiration = 103 (courier only)
            if q.IsStageDone(100)
                bool ok = AoT_Core.CompleteContract(id)
                Debug.Trace("[AoT-Missives] poll Complete id=" + id + " q=" + q + " ok=" + ok)
            elseif q.IsStageDone(103)
                bool ok2 = AoT_Core.ExpireContract(id)
                Debug.Trace("[AoT-Missives] poll Expire id=" + id + " q=" + q + " ok=" + ok2)
            endif
        endif
        i += 1
    endwhile
    float dt = Utility.GetCurrentRealTime() - t0
    Debug.Trace("[AoT-Missives] poll " + count + " open in " + dt + "s")
EndFunction

; Called by the board trigger after a successful Start()
Function RegisterContractQuest(int aiId, Quest akQuest)
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
