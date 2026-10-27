Scriptname AoT_Contract_2b_Alias extends ReferenceAlias
{Alias script for Target (Boss) - completes the contract when Boss dies.
Attached to alias id 2. Closes by function call (D012), not by SetStage.}

Quest Property OwningQuestRef Auto

Event OnDeath(Actor akKiller)
    Quest q = GetOwningQuest()
    If !q
        return
    EndIf
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
