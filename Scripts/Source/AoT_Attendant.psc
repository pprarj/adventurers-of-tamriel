Scriptname AoT_Attendant extends Quest
{The guild clerk: fee, abandon and delivery.
Logic is Papyrus plus AoT_Core; the core has no third-party master. The Headhunter
and MMH branches are soft: they probe at runtime with Game.GetFormFromFile and hide
when the soft master is absent, without logging an error (D007).
No properties need filling: every lookup is by form file at runtime.}

; -- keeps the dialogue true (D034): a 3 second tick places the attendant when the player is in
; the guild hall, and every 7th tick re-syncs the dialogue globals. Single updates are re-armed
; in OnUpdate and persist across saves. Cheap: a cell compare per tick, a few reads per sync.
Int _tick = 0

Event OnInit()
    RegisterForSingleUpdate(3.0)
EndEvent

Event OnUpdate()
    EnsureAttendant()
    _tick += 1
    If _tick >= 7
        _tick = 0
        SyncGlobals()
    EndIf
    RegisterForSingleUpdate(3.0)
EndEvent

String Function HallsPath() Global
    {JsonUtil path of the table of halls written by the hall cloner (one row per hold).}
    Return "../../../Config/AdventurersOfTamriel/halls"
EndFunction

Function EnsureAttendant() Global
    {The base NPC is placed at the hall's AoT_GuildHallAttendantSpot the first time the player is
    inside, and again if it died or vanished. The hall is found by the table of halls (cloned,
    one per hold; the plugin, the cell and the marker are looked up by form file, so no plugin needs
    a new master); the single Fase 6 hall is the fallback. No cell override, so the Actors plugin
    keeps its clean header.}
    Actor pl = Game.GetPlayer()
    Cell here = pl.GetParentCell()
    If !here || !here.IsInterior()
        Return
    EndIf
    Cell hall = None
    ObjectReference spot = None
    String attKey = "aot_att_ref"
    String path = HallsPath()
    Int n = JsonUtil.StringListCount(path, "aot_hall_holds")
    Int i = 0
    While i < n && !hall
        String hold = JsonUtil.StringListGet(path, "aot_hall_holds", i)
        String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + hold, "")
        Int cellId = JsonUtil.IntListGet(path, "aot_hall_" + hold, 0)
        Cell c = Game.GetFormFromFile(cellId, plug) as Cell
        If c && c == here
            hall = c
            spot = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + hold, 1), plug) as ObjectReference
            attKey = "aot_att_ref_" + hold
        EndIf
        i += 1
    EndWhile
    If !hall
        hall = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_GuildHall.esp") as Cell
        If !hall || here != hall
            Return
        EndIf
        spot = Game.GetFormFromFile(0x00097A, "AdventurersOfTamriel_GuildHall.esp") as ObjectReference
    EndIf
    Actor cur = StorageUtil.GetFormValue(None, attKey, None) as Actor
    If cur && !cur.IsDead() && cur.GetParentCell() == hall
        Return
    EndIf
    ActorBase base = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_Actors.esp") as ActorBase
    If !spot || !base
        Debug.Trace("[AoT] Attendant: spot or base missing, not placed")
        Return
    EndIf
    Actor a = spot.PlaceAtMe(base, 1, True) as Actor
    If a
        StorageUtil.SetFormValue(None, attKey, a)
        StorageUtil.SetFormValue(None, "aot_att_ref", a)
        Debug.Trace("[AoT] Attendant placed " + a + " in the hall")
    EndIf
EndFunction

Function ProbeReport() Global
    {In-game probe (D034): console `cgf "AoT_Attendant.ProbeReport"`. Logs, per fee band, the
    fee, paid, what the topic condition sees; the delivery and open-contract globals; gold.
    Run SyncGlobals first so it reads what the dialogue will read.}
    SyncGlobals()
    Int b = 1
    While b <= AoT_Core.MaxBand()
        GlobalVariable g = Game.GetFormFromFile(_GlobalId("fee" + b), "AdventurersOfTamriel_Actors.esp") as GlobalVariable
        Float gv = -1.0
        If g
            gv = g.GetValue()
        EndIf
        Debug.Trace("[AoT-PROBE] band " + b + " fee=" + FeeForBand(b) + " paid=" + AoT_Core.IsBandPaid(b) + " global=" + gv + " show=" + ShouldShowFee(b))
        b += 1
    EndWhile
    Debug.Trace("[AoT-PROBE] open=" + FirstOpenContractId() + " gold=" + Game.GetPlayer().GetGoldAmount() + " head=" + HasHeadhunter() + " mmh=" + HasMMH() + " ref=" + (StorageUtil.GetFormValue(None, "aot_att_ref", None)))
EndFunction

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

; -- dialogue glue (Part F, D034) --
; The attendant's topics live in AdventurersOfTamriel_Actors.esp. Their conditions read
; globals (gold needs a global to compare against); SyncGlobals keeps them true to the
; save. Fragments call RunAction. Every entry is global: a topic fragment has no quest.
Int Function _GlobalId(String asName) Global
    If asName == "fee1"
        Return 0x000804
    ElseIf asName == "fee2"
        Return 0x000805
    ElseIf asName == "fee3"
        Return 0x000806
    ElseIf asName == "fee4"
        Return 0x000807
    ElseIf asName == "fee5"
        Return 0x000808
    ElseIf asName == "head"
        Return 0x000809
    ElseIf asName == "mmh"
        Return 0x00080A
    EndIf
    Return 0x00080B
EndFunction

Function _SetGlobal(String asName, Int aiValue) Global
    GlobalVariable g = Game.GetFormFromFile(_GlobalId(asName), "AdventurersOfTamriel_Actors.esp") as GlobalVariable
    If g
        g.SetValue(aiValue as Float)
    Else
        Debug.Trace("[AoT] Attendant: global " + asName + " not found")
    EndIf
EndFunction

Int Function FirstOpenContractId() Global
    {Ledger id of the oldest open contract; 0 when none (state 1 = open).}
    Int n = AoT_Core.ContractCount()
    Int i = 1
    While i <= n
        If AoT_Core.ContractState(i) == 1
            Return i
        EndIf
        i += 1
    EndWhile
    Return 0
EndFunction

Function SyncGlobals() Global
    {Fee global = the fee when the band is payable and unpaid, else 0 (the topic is
    hidden by "fee > 0 and gold >= fee"). Delivery globals read the quests the board
    recorded under aot_head_q / aot_mmh_q, at stage 40.}
    Int b = 1
    While b <= AoT_Core.MaxBand()
        Int c = FeeForBand(b)
        If c < 0 || AoT_Core.IsBandPaid(b)
            c = 0
        EndIf
        _SetGlobal("fee" + b, c)
        b += 1
    EndWhile
    Quest hq = StorageUtil.GetFormValue(None, "aot_head_q", None) as Quest
    Quest mq = StorageUtil.GetFormValue(None, "aot_mmh_q", None) as Quest
    Int h = 0
    If hq && HasHeadhunter() && hq.GetStage() == 40
        h = 1
    EndIf
    Int m = 0
    If mq && HasMMH() && mq.GetStage() == 40
        m = 1
    EndIf
    _SetGlobal("head", h)
    _SetGlobal("mmh", m)
    Int o = 0
    If FirstOpenContractId() > 0
        o = 1
    EndIf
    _SetGlobal("open", o)
EndFunction

Function RunAction(Int aiAction, Int aiBand) Global
    {1 pay the fee of aiBand, 2 abandon the oldest open contract, 3 deliver the head,
    4 deliver the MMH hunt. Re-syncs the globals after.}
    Quest q = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_Attendant.esp") as Quest
    AoT_Attendant a = q as AoT_Attendant
    If aiAction == 1
        If a && ShouldShowFee(aiBand)
            a.PayFee(aiBand)
        Else
            Debug.Trace("[AoT] Attendant RunAction: fee not payable band=" + aiBand)
        EndIf
    ElseIf aiAction == 2
        Int id = FirstOpenContractId()
        If id > 0 && a
            a.TryAbandonById(id)
        EndIf
    ElseIf aiAction == 3
        Quest hq = StorageUtil.GetFormValue(None, "aot_head_q", None) as Quest
        If hq
            Quest hqa = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_Headhunter.esp") as Quest
            AoT_HeadhunterAdapter ad = hqa as AoT_HeadhunterAdapter
            If ad
                ad.DeliverHead(hq)
            EndIf
        EndIf
    ElseIf aiAction == 4
        Quest mq = StorageUtil.GetFormValue(None, "aot_mmh_q", None) as Quest
        If mq
            Quest mqa = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_MMH.esp") as Quest
            AoT_MMHAdapter am = mqa as AoT_MMHAdapter
            If am
                am.DeliverMMH(mq)
            EndIf
        EndIf
    EndIf
    SyncGlobals()
EndFunction
