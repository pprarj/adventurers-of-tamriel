Scriptname AoT_Contract_2b_Alias extends ReferenceAlias
{Alias script for Target (Boss) - completes quest when Boss dies.
Attached to alias id 2.}

Quest Property OwningQuestRef Auto

Event OnDeath(Actor akKiller)
    Quest q = GetOwningQuest()
    If !q
        return
    EndIf
    If q.GetStage() < 20 || q.IsStageDone(100)
        return
    EndIf
    Debug.Trace("[AoT-2b-Alias] Boss died, setting stage 100 on " + q)
    q.SetStage(100)
EndEvent
