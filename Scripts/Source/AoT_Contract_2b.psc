Scriptname AoT_Contract_2b extends Quest
{Whiterun bandit camp contract (Fase 2b, arquetipo inaugural).
Mudo, sem fragment. Usa OnStageSet para abrir/fechar o contrato no nucleo.
O Boss alias (id 2) e Boss REFT (LocTypeRefType 0x130F7 dentro de Dungeon).
A faixa e Low (0). Ver D005.}

Int Property Band = 0 AutoReadOnly Hidden

; Quest stages mirror Missives _M_QuestWhiterunKillGiant:
; 0 StartUp, 20 hunt, 30 awarded, 100 complete, 103 expire, 105 fail, 110 cleanup.
; Objective 20 -> alias 2 (Target), objective 30 -> alias 3 (Steward) - minimal.

Event OnInit()
    ; Quest is Start Game Enabled. Open once here as well as on stage 0 fallback.
    TryOpen()
EndEvent

Event OnStageSet(Int aiStageID, Int aiItemID)
    If aiStageID == 0
        TryOpen()
    ElseIf aiStageID == 20
        ; accepted/hunt - already opened.
    ElseIf aiStageID == 100
        TryComplete()
    ElseIf aiStageID == 105
        TryAbandon()
    ElseIf aiStageID == 103
        TryExpire()
    EndIf
EndEvent

Function TryOpen()
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id > 0
        Debug.Trace("[AoT-2b] TryOpen already open id=" + id)
        return
    EndIf
    id = AoT_Core.OpenContract(self as Quest, Band)
    Debug.Trace("[AoT-2b] OpenContract band=" + Band + " -> id=" + id)
EndFunction

Function TryComplete()
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id == 0
        Debug.Trace("[AoT-2b] TryComplete no open contract")
        return
    EndIf
    Bool ok = AoT_Core.CompleteContract(id)
    Debug.Trace("[AoT-2b] CompleteContract id=" + id + " -> " + ok + " points=" + AoT_Core.GetPoints())
EndFunction

Function TryAbandon()
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id == 0
        return
    EndIf
    Bool ok = AoT_Core.AbandonContract(id)
    Debug.Trace("[AoT-2b] AbandonContract id=" + id + " -> " + ok)
EndFunction

Function TryExpire()
    Int id = AoT_Core.FindOpenContract(self as Quest)
    If id == 0
        return
    EndIf
    Bool ok = AoT_Core.ExpireContract(id)
    Debug.Trace("[AoT-2b] ExpireContract id=" + id + " -> " + ok)
EndFunction
