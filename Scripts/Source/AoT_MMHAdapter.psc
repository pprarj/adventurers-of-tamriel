Scriptname AoT_MMHAdapter extends Quest

; AoT_MMHAdapter - soft bridge to Monster Hunt Missives (MMH).
; Plugin: AdventurersOfTamriel_MMH.esp, master: MissivesMonsterHunt.esp
; Our rule (D-7/A-5): MMH respects rank or stays out. MMH itself has no rank,
; only MMH_HuntsCompleted counter and MMH_DifficultyTier. We map the counter to
; a rank (AoT_Attendant.MMHRank) and gate the delivery/boarding on it.
; Delivery calls MMH_RewardScript.PayAndClose() - same public function the MMH
; broker calls. Presence: Game.GetFormFromFile; when MMH is absent the branch
; is hidden and nothing logs an error (Fase 2 pattern).

; Compile dependency: this file imports the MMH source at compile time
; (-i includes the MMH Source/Scripts folder) so PayAndClose resolves.
; At runtime the call is guarded by HasMMH() so a missing MMH never faults.

Bool Function HasMMH() Global
    Form f = Game.GetFormFromFile(0x06000845, "MissivesMonsterHunt.esp")
    Return f != None
EndFunction

; Our counter->rank (A-5) is in AoT_Attendant.MMHRank(); this file mirrors the
; check so the dialogue condition can call this quest without cross-script CTDA
; tricks. Returns true when the player's MMH-derived rank covers aiBand's
; minimum rank for that band (or when aiBand is already within current rank).
Bool Function CanTakeMMHBand(Int aiBand)
    Int mmhRank = AoT_Attendant.MMHRank()
    Int curRank = AoT_Core.GetRank()
    ; Effective rank for access is the higher of the two? No: D-7 says MMH
    ; respects rank - a low-rank player cannot take a High hunt even if the
    ; hunt counter is low; use the real rank as gate, and mmhRank only for
    ; future-rank display if we ever show it.
    Int gateRank = curRank
    If mmhRank > gateRank
        gateRank = mmhRank
    EndIf
    Int w = AoT_Core.BandWeight(gateRank, aiBand)
    Return w > 0
EndFunction

; Delivery: pay and close the MMH hunt. aiQuest is the MMH_RewardScript quest
; at stage 40 (resolved from the alias or from the form file).
Function DeliverMMH(Quest akMMHQuest)
    If !akMMHQuest
        Debug.Trace("[AoT-MMH] DeliverMMH: no quest")
        Return
    EndIf
    If !HasMMH()
        Debug.Trace("[AoT-MMH] DeliverMMH: MMH not present")
        Return
    EndIf
    If akMMHQuest.GetStage() != 40
        Debug.Trace("[AoT-MMH] DeliverMMH: stage is " + akMMHQuest.GetStage() + " not 40")
        Return
    EndIf
    ; The MMH quest IS an MMH_RewardScript (extends Quest). Cast and call
    ; PayAndClose(); if the cast fails (wrong family), fall back to stage 100.
    MMH_RewardScript m = akMMHQuest as MMH_RewardScript
    If m
        m.PayAndClose()
        Debug.Trace("[AoT-MMH] DeliverMMH -> PayAndClose on " + akMMHQuest)
    Else
        akMMHQuest.SetStage(100)
        Debug.Trace("[AoT-MMH] DeliverMMH -> SetStage 100 fallback on " + akMMHQuest)
    EndIf
EndFunction
