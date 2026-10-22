Scriptname AoT_HeadhunterAdapter extends Quest

; AoT_HeadhunterAdapter - soft bridge to Headhunter / Bounties Redone.
; Plugin: AdventurersOfTamriel_Headhunter.esp, master: Headhunter - Bounties Redone.esp
; and optionally BountiesRedone_MissivesExtension.esp (the 144 INFO live there).
; Our dialogue Topic/INFO is conditioned on the foreign quest being at stage 40
; (same condition the foreign INFO uses: GetStageDone 40). Fragment does SetStage
; on that quest; payment follows the foreign fragment (stage 100 -> GoldReward).
; Arrow (A-6): try ForceRefTo on an existing alias if the record leaves room;
; otherwise the objective stays on Steward and we note it in TESTPLAN.
; Presence: hide the branch when Game.GetFormFromFile fails; no error log.

; Soft presence check without logging.
Bool Function HasHeadhunter() Global
    Form f = Game.GetFormFromFile(0x00000800, "Headhunter - Bounties Redone.esp")
    If f
        Return True
    EndIf
    f = Game.GetFormFromFile(0x00000F0C, "BountiesRedone_MissivesExtension.esp")
    Return f != None
EndFunction

; Called from the attendant dialogue fragment when the player delivers the head.
; akHeadhunterQuest is the foreign quest at stage 40 (resolved via GetOwningQuest
; or via alias lookup). We advance it; its own stage-100 fragment pays.
Function DeliverHead(Quest akHeadhunterQuest)
    If !akHeadhunterQuest
        Debug.Trace("[AoT-Headhunter] DeliverHead: no quest")
        Return
    EndIf
    ; Only deliver when the foreign contract is in the collect stage.
    If akHeadhunterQuest.GetStage() != 40
        Debug.Trace("[AoT-Headhunter] DeliverHead: stage is " + akHeadhunterQuest.GetStage() + " not 40")
        Return
    EndIf
    ; The foreign script pays on stage 100; we drive it there.
    akHeadhunterQuest.SetStage(100)
    Debug.Trace("[AoT-Headhunter] DeliverHead -> SetStage 100 on " + akHeadhunterQuest)
EndFunction

; Try to point the objective at the attendant instead of Steward.
; Best effort: if the foreign quest exposes a ReferenceAlias that currently
; points at the Steward, repoint it to the attendant ref we pass.
; Returns true when a repoint was done.
Bool Function TryRepointToAttendant(Quest akHeadhunterQuest, ObjectReference akAttendantRef)
    If !akHeadhunterQuest || !akAttendantRef
        Return False
    EndIf
    ; Look for alias named Steward (index varies per quest family but name is stable).
    Alias ali = akHeadhunterQuest.GetAliasByName("Steward")
    If !ali
        ; Fallback by index: Steward is alias 3 in the Kill family.
        ali = akHeadhunterQuest.GetNthAlias(3)
        If !ali
            Return False
        EndIf
    EndIf
    ReferenceAlias refAli = ali as ReferenceAlias
    If !refAli
        Return False
    EndIf
    refAli.ForceRefTo(akAttendantRef)
    Debug.Trace("[AoT-Headhunter] ForceRefTo Steward -> attendant on " + akHeadhunterQuest)
    Return True
EndFunction
