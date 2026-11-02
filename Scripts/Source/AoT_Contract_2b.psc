Scriptname AoT_Contract_2b extends Quest
{Whiterun bandit camp contract, the first contract archetype.
Silent, no fragments. The contract opens, closes, is abandoned and expires by a
CALL to a function of this script (TryOpen, TryComplete, TryAbandon, TryExpire);
the quest stage is only the journal mirror, written AFTER the ledger moved (D012).
Quest.psc declares no OnStageSet: an event with that name compiles and never runs.
Nothing opens the contract by itself: whoever offers it (the board, the attendant)
calls TryOpen, and the hunt stage is written by TryOpen (D025).
The Boss alias (id 2) is a Boss ref type (LocTypeRefType 0x130F7) inside a Dungeon.
The band is Low (0). See D005.}

Int Property Band = 0 AutoReadOnly Hidden

; Quest stages mirror the Missives kill family:
; 0 start, 20 hunt, 30 awarded, 100 complete, 103 expire, 105 fail, 110 cleanup.
; Objective 20 -> alias 2 (Target), objective 30 -> alias 3 (Steward).

Function TryOpen()
    {Opens the contract and starts the hunt (stage 20). One-shot: a contract that
    already ended in this save is not offered again.}
    If IsStageDone(100) || IsStageDone(103) || IsStageDone(105)
        Debug.Trace("[AoT-2b] TryOpen refused: this contract already ended")
        Return
    EndIf
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id > 0
        Debug.Trace("[AoT-2b] TryOpen already open id=" + id)
        Return
    EndIf
    If !IsRunning()
        Start()
    EndIf
    id = AoT_Core.OpenContract(self as Quest, Band)
    Debug.Trace("[AoT-2b] OpenContract band=" + Band + " -> id=" + id)
    If id > 0
        MirrorStage(20)
    EndIf
EndFunction

Bool Function TryComplete()
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id == 0
        Debug.Trace("[AoT-2b] TryComplete no open contract")
        Return False
    EndIf
    Bool ok = AoT_Core.CompleteContract(id)
    Debug.Trace("[AoT-2b] CompleteContract id=" + id + " -> " + ok + " points=" + AoT_Core.GetPoints())
    If ok
        MirrorStage(100)
    EndIf
    Return ok
EndFunction

Bool Function TryAbandon()
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id == 0
        Debug.Trace("[AoT-2b] TryAbandon no open contract")
        Return False
    EndIf
    Bool ok = AoT_Core.AbandonContract(id)
    Debug.Trace("[AoT-2b] AbandonContract id=" + id + " -> " + ok)
    If ok
        MirrorStage(105)
    EndIf
    Return ok
EndFunction

Bool Function TryExpire()
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id == 0
        Debug.Trace("[AoT-2b] TryExpire no open contract")
        Return False
    EndIf
    Bool ok = AoT_Core.ExpireContract(id)
    Debug.Trace("[AoT-2b] ExpireContract id=" + id + " -> " + ok)
    If ok
        MirrorStage(103)
    EndIf
    Return ok
EndFunction

Function MirrorStage(Int aiStage)
    {Journal mirror only. Nothing listens to the stage, so this cannot re-enter.}
    If !IsStageDone(aiStage)
        SetStage(aiStage)
    EndIf
EndFunction
