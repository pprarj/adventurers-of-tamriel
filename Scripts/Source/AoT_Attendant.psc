Scriptname AoT_Attendant extends Quest

; AoT_Attendant - the guild clerk: fee, abandon, delivery.
; This quest owns the attendant NPC/dialogue (Fase 3, cell of test until Fase 6).
; All logic is Papyrus + AoT_Core; no third-party master on the core.
; The Headhunter and MMH delivery branches are soft: they probe at runtime
; via Game.GetFormFromFile and hide when the soft master is absent, without
; logging an error (same pattern as Fase 2 presence check).

; -- fee (D-20/D-28/D-31) --
; Paying the fee marks the band as paid (AoT_Core.MarkBandPaid).
; Insufficient gold: the dialogue line does not appear (condition on gold).
; Enough gold: remove gold, then mark paid. One band at a time.

; -- abandon (D-16, E2) --
; Lists open contracts (aot_open) and calls AoT_Core.AbandonContract(id).
; Does NOT call Quest.Stop() on foreign quests; after reading the Missives
; family scripts (_M_QuestKillScript, _M_QuestCourierScript etc.) Stop() from
; outside was found unsafe: it can leave the board note in the world or in
; inventory and leaves the quest's alias reservations. Our contracts stay open
; in their own quest until their own script closes them; abandoning here only
; moves the ledger entry (aot_open -> aot_contracts with state 3) and applies
; the abandon delta. The foreign quest, if any, is left for its own timeout
; or for the player to discard the note; abandoning twice is idempotent via
; the aot_open claim (second call returns false, no second delta).

; -- delivery --
; Headhunter (soft, D-5/D-35): our own Topic/INFO conditioned on the Headhunter
;   quest being at stage 40 (GetStageDone 40). Fragment calls SetStage on that
;   quest. Payment follows the Headhunter's own fragment (stage 100 GoldReward).
;   Arrow: try ForceRefTo on existing alias if the record allows; otherwise
;   leave the objective on Steward and note in TESTPLAN (A-6).
; MMH (soft, D-7/D-35): rule maps MMH_HuntsCompleted counter to rank (A-5);
;   attendant calls MMH_RewardScript.PayAndClose() (stage-40 guard inside).
;   Compile against the MMH .psc when the MMH kit is present; at runtime the
;   branch hides when Game.GetFormFromFile("MissivesMonsterHunt.esp") fails.

; No properties need filling: all lookups are by FormFile at runtime.
; The quest is Start Game Enabled, no aliases required (attendant alias if
; needed is wired in the plugin).

Function PayFee(Int aiBand)
    {Called from the fee fragment after the gold check passed.}
    If aiBand < 0 || aiBand > AoT_Core.MaxBand()
        Debug.Trace("[AoT] Attendant PayFee: bad band " + aiBand)
        Return
    EndIf
    Int cost = FeeForBand(aiBand)
    If cost < 0
        Debug.Trace("[AoT] Attendant PayFee: fee missing for band " + aiBand)
        Return
    EndIf
    Actor player = Game.GetPlayer()
    Int goldBefore = player.GetGoldAmount()
    If goldBefore < cost
        Debug.Trace("[AoT] Attendant PayFee: insufficient gold " + goldBefore + " < " + cost)
        Return
    EndIf
    player.RemoveItem(Game.GetForm(0x0000000F) as MiscObject, cost)
    Bool newlyPaid = AoT_Core.MarkBandPaid(aiBand)
    Int goldAfter = player.GetGoldAmount()
    Debug.Trace("[AoT] Attendant PayFee band=" + aiBand + " cost=" + cost + " gold " + goldBefore + " -> " + goldAfter + " newlyPaid=" + newlyPaid)
EndFunction

Int Function FeeForBand(Int aiBand) Global
    {Gold cost of the fee for this band; -1 on missing key or bad band.}
    If aiBand < 0 || aiBand > AoT_Core.MaxBand()
        Return -1
    EndIf
    String path = AoT_Core.TablePath()
    If JsonUtil.IntListCount(path, "aot_fee_by_band") <= aiBand
        Debug.Trace("[AoT] table: aot_fee_by_band missing or short for band " + aiBand)
        Return -1
    EndIf
    Return JsonUtil.IntListGet(path, "aot_fee_by_band", aiBand)
EndFunction

Bool Function ShouldShowFee(Int aiBand) Global
    {True when the fee line should appear: not yet paid and affordable.}
    If AoT_Core.IsBandPaid(aiBand)
        Return False
    EndIf
    Int cost = FeeForBand(aiBand)
    If cost < 0
        Return False
    EndIf
    Return Game.GetPlayer().GetGoldAmount() >= cost
EndFunction

Bool Function TryAbandonByIndex(Int aiIndex)
    {Abandon the open contract at position aiIndex in the aot_open list.
    Returns true when a contract was abandoned.}
    Int count = StorageUtil.IntListCount(None, "aot_open")
    If aiIndex < 0 || aiIndex >= count
        Debug.Trace("[AoT] Attendant TryAbandon: bad index " + aiIndex + "/" + count)
        Return False
    EndIf
    Int id = StorageUtil.IntListGet(None, "aot_open", aiIndex)
    Bool ok = AoT_Core.AbandonContract(id)
    Debug.Trace("[AoT] Attendant Abandon idx=" + aiIndex + " id=" + id + " ok=" + ok)
    Return ok
EndFunction

Bool Function TryAbandonById(Int aiId)
    {Direct abandon by ledger id.}
    Bool ok = AoT_Core.AbandonContract(aiId)
    Debug.Trace("[AoT] Attendant Abandon id=" + aiId + " ok=" + ok)
    Return ok
EndFunction

; -- MMH rank mapping (A-5) --
; MMH has no rank. We map its hunt counter to our rank for the rule
; "MMH respects rank or stays out". This is OUR rule (D-7), not MMH's.
Int Function MMHRank() Global
    {Rank 0..6 derived from MMH_HuntsCompleted; 0 when MMH not present.}
    Form f = Game.GetFormFromFile(0x06000845, "MissivesMonsterHunt.esp")
    GlobalVariable g = f as GlobalVariable
    If !g
        Return 0
    EndIf
    Int hunts = g.GetValue() as Int
    If hunts < 0
        hunts = 0
    EndIf
    ; Thresholds match the ladder shape: 0->F, 3->E, 6->D, 12->C, 20->B, 32->A, 48->S
    ; but using the same ladder data as the core for consistency.
    Int r = 0
    While r < AoT_Core.MaxRank()
        Int step = AoT_Core.LadderStep(r)
        If step < 0
            Return r
        EndIf
        Int cum = 0
        Int k = 0
        While k <= r
            Int s = AoT_Core.LadderStep(k)
            If s < 0
                cum = 9999
                k = r + 1
            Else
                cum += s
            EndIf
            k += 1
        EndWhile
        If hunts < cum
            Return r
        EndIf
        r += 1
    EndWhile
    Return AoT_Core.MaxRank()
EndFunction

; -- soft presence (Fase 2 pattern, E3 gate) --
Bool Function HasHeadhunter() Global
    ; Any form from that plugin proves it is loaded; use GoldReward as probe.
    Form f = Game.GetFormFromFile(0x00000800, "Headhunter - Bounties Redone.esp")
    ; Fallback: extension plugin
    If !f
        f = Game.GetFormFromFile(0x00000F0C, "BountiesRedone_MissivesExtension.esp")
    EndIf
    Return f != None
EndFunction

Bool Function HasMMH() Global
    Form f = Game.GetFormFromFile(0x06000845, "MissivesMonsterHunt.esp")
    Return f != None
EndFunction
