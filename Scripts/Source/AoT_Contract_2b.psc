Scriptname AoT_Contract_2b extends Quest
{Whiterun bandit camp contract (Fase 2b, arquetipo inaugural).
Mudo, sem fragment. O contrato abre, fecha, abandona e expira por CHAMADA de
funcao deste script (TryOpen/TryComplete/TryAbandon/TryExpire); o stage da quest
e so o espelho para o diario, gravado DEPOIS do fechamento no nucleo (D012).
Quest.psc nao declara OnStageSet: um evento com esse nome compila e nunca roda.
O Boss alias (id 2) e Boss REFT (LocTypeRefType 0x130F7 dentro de Dungeon).
A faixa e Low (0). Ver D005.}

Int Property Band = 0 AutoReadOnly Hidden

; Quest stages mirror Missives _M_QuestWhiterunKillGiant:
; 0 StartUp, 20 hunt, 30 awarded, 100 complete, 103 expire, 105 fail, 110 cleanup.
; Objective 20 -> alias 2 (Target), objective 30 -> alias 3 (Steward) - minimal.

Event OnInit()
    ; Quest is Start Game Enabled: open once here.
    TryOpen()
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
