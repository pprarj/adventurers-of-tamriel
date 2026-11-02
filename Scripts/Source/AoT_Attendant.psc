Scriptname AoT_Attendant extends Quest
{The guild clerk: fee, abandon and delivery.
Logic is Papyrus plus AoT_Core; the core has no third-party master. The Headhunter
and MMH branches are soft: they probe at runtime with Game.GetFormFromFile and hide
when the soft master is absent, without logging an error (D007).
No properties need filling: every lookup is by form file at runtime.}

; -- fee (D007, D008) --
; Paying the fee marks the band as paid (AoT_Core.MarkBandPaid) and takes the gold.
; Insufficient gold: the dialogue line does not appear (condition on gold).

; -- abandon (D007) --
; Calls AoT_Core.AbandonContract(id) by ledger id. It does NOT call Quest.Stop() on a
; foreign quest: after reading the Missives family scripts, Stop() from outside can
; leave the board note in the world or in the inventory, and leaves the alias
; reservations. The ledger entry moves (aot_open -> aot_contracts, state 3) and the
; abandon delta applies; the foreign quest is left for its own timeout or for the
; player to discard the note. Abandoning twice is idempotent through the aot_open claim.
; The contract of AoT_Contract_2b is abandoned through that script, so its journal
; stage follows (D025).

; -- delivery (D007) --
; Headhunter (soft, D007): the attendant's INFO is conditioned on the Headhunter
;   quest being at stage 40 (GetStageDone 40); the fragment calls
;   AoT_HeadhunterAdapter.DeliverHead.
; MMH (soft, D007): the attendant calls MMH_RewardScript.PayAndClose() through
;   AoT_MMHAdapter.DeliverMMH (its own stage-40 guard inside).

Function PayFee(Int aiBand)
    {Called from the fee fragment. Claims the band first (MarkBandPaid is the claim),
    and only then takes the gold, so a second caller cannot pay the same band twice.}
    If AoT_Core.IsBandPaid(aiBand)
        Debug.Trace("[AoT] Attendant PayFee: already paid band=" + aiBand)
        Return
    EndIf
    If aiBand < 0 || aiBand > AoT_Core.MaxBand()
        Debug.Trace("[AoT] Attendant PayFee: bad band " + aiBand)
        Return
    EndIf
    Int cost = FeeForBand(aiBand)
    If cost < 0
        Debug.Trace("[AoT] Attendant PayFee: fee missing for band " + aiBand)
        Return
    EndIf
    If cost == 0
        ; A free band (Low, D028) is never charged and never recorded as paid.
        Debug.Trace("[AoT] Attendant PayFee: band " + aiBand + " is free")
        Return
    EndIf
    Actor player = Game.GetPlayer()
    Int goldBefore = player.GetGoldAmount()
    If goldBefore < cost
        Debug.Trace("[AoT] Attendant PayFee: insufficient gold " + goldBefore + " < " + cost)
        Return
    EndIf
    If !AoT_Core.MarkBandPaid(aiBand)
        Debug.Trace("[AoT] Attendant PayFee: band " + aiBand + " was claimed by another caller")
        Return
    EndIf
    player.RemoveItem(Game.GetForm(0x0000000F) as MiscObject, cost)
    Int goldAfter = player.GetGoldAmount()
    Debug.Trace("[AoT] Attendant PayFee band=" + aiBand + " cost=" + cost + " gold " + goldBefore + " -> " + goldAfter)
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
    {True when the fee line should appear: a fee above zero, not yet paid, affordable.
    A free band (Low, D028) never shows one.}
    If AoT_Core.IsBandPaid(aiBand)
        Return False
    EndIf
    Int cost = FeeForBand(aiBand)
    If cost <= 0
        Return False
    EndIf
    Return Game.GetPlayer().GetGoldAmount() >= cost
EndFunction

Bool Function TryAbandonById(Int aiId)
    {Abandons the open contract with this ledger id. The id, never a list position:
    the polling can close a contract between the listing and the choice.
    Returns true when a contract was abandoned.}
    Quest q2b = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel.esl") as Quest
    If q2b && AoT_Core.FindOpenContract(q2b) == aiId
        AoT_Contract_2b contract = q2b as AoT_Contract_2b
        If contract
            Return contract.TryAbandon()
        EndIf
    EndIf
    Bool ok = AoT_Core.AbandonContract(aiId)
    Debug.Trace("[AoT] Attendant Abandon id=" + aiId + " ok=" + ok)
    Return ok
EndFunction

; -- MMH rank mapping --
; MMH has no rank. Its hunt counter maps to a guild rank, for display only: the
; gate for MMH hunts is the real guild rank (D007, AoT_MMHAdapter.CanTakeMMHBand).
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
    ; Rank r holds while hunts < the sum of the ladder steps up to r (3, 9, 21, 41,
    ; 73, 121 with the shipped table), read from the same ladder data as the core.
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

; -- soft presence --
Bool Function HasHeadhunter() Global
    ; Any form from that plugin proves it is loaded.
    Form f = Game.GetFormFromFile(0x00000800, "Headhunter - Bounties Redone.esp")
    ; Fallback: the extension plugin.
    If !f
        f = Game.GetFormFromFile(0x00000F0C, "BountiesRedone_MissivesExtension.esp")
    EndIf
    Return f != None
EndFunction

Bool Function HasMMH() Global
    Form f = Game.GetFormFromFile(0x06000845, "MissivesMonsterHunt.esp")
    Return f != None
EndFunction
