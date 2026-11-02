Scriptname AoT_Contract_2b_Alias extends ReferenceAlias
{Alias script for the Target (Boss): completes the contract when the Boss dies.
Attached to alias id 2. Closes by function call (D012), not by SetStage.}

; Unused. Kept only because removing a property from a published script
; upsets saves that already stored it.
Quest Property OwningQuestRef Auto

Event OnDeath(Actor akKiller)
    Quest q = GetOwningQuest()
    If !q
        return
    EndIf
    ; The hunt stage (20) is written by AoT_Contract_2b.TryOpen (D025).
    If q.GetStage() < 20 || q.IsStageDone(100)
        return
    EndIf
    AoT_Contract_2b contract = q as AoT_Contract_2b
    If !contract
        Debug.Trace("[AoT-2b-Alias] Boss died but quest has no AoT_Contract_2b script: " + q)
        return
    EndIf
    Debug.Trace("[AoT-2b-Alias] Boss died, completing contract on " + q)
    contract.TryComplete()
EndEvent
