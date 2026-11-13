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
    AoT_Hall.EnsureFixtures()
    AoT_Exam.Tick()
    _tick += 1
    If _tick >= 7
        _tick = 0
        SyncGlobals()
        AoT_Emergency.Heal()
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
        String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + i, "")
        Int cellId = JsonUtil.IntListGet(path, "aot_hall_" + i, 0)
        Cell c = None
        If plug != ""
            c = Game.GetFormFromFile(cellId, plug) as Cell
        EndIf
        If c && c == here
            hall = c
            spot = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + i, 1), plug) as ObjectReference
            attKey = "aot_att_ref_" + hold
        EndIf
        i += 1
    EndWhile
    If !hall
        Return
    EndIf
    If !Game.IsPluginInstalled("AdventurersOfTamriel.esp")
        Return
    EndIf
    ActorBase base = Game.GetFormFromFile(0x000D99, "AdventurersOfTamriel.esp") as ActorBase
    Actor cur = StorageUtil.GetFormValue(None, attKey, None) as Actor
    If !(cur && !cur.IsDead() && cur.GetParentCell() == hall)
        ; Fase 13 etapa 6: the stored ref can be lost (reload, a second tick); look in the hall itself before placing
        cur = _AdoptOrTrim(hall, base, cur)
    EndIf
    If cur && !cur.IsDead() && cur.GetParentCell() == hall
        StorageUtil.SetFormValue(None, attKey, cur)
        If spot && spot.Is3DLoaded() && cur.GetDistance(spot) > 90.0
            ; the sandbox package let her wander off from behind the counter: bring her back and hold her there
            cur.MoveTo(spot)
            cur.SetAngle(0.0, 0.0, spot.GetAngleZ())
            AoT_Core.Log("[AoT] Attendant: back to the counter " + cur)
        EndIf
        If !cur.IsInDialogueWithPlayer()
            cur.SetDontMove(True)
        EndIf
        Return
    EndIf
    If !spot || !base
        Debug.Trace("[AoT] Attendant: spot or base missing, not placed")
        Return
    EndIf
    If !spot.Is3DLoaded()
        AoT_Core.Log("[AoT] Attendant: spot 3D not loaded yet, retry next tick (" + spot + ")")
        Return
    EndIf
    Actor a = spot.PlaceAtMe(base, 1, True) as Actor
    If a
        a.SetDontMove(True)
        AoT_Core.Log("[AoT] Attendant: spot at " + spot.GetPositionX() + "," + spot.GetPositionY() + "," + spot.GetPositionZ())
        StorageUtil.SetFormValue(None, attKey, a)
        StorageUtil.SetFormValue(None, "aot_att_ref", a)
        AoT_Core.Log("[AoT] Attendant placed " + a + " in the hall")
    EndIf
EndFunction

Actor Function _AdoptOrTrim(Cell akHall, ActorBase akBase, Actor akStored) Global
    {Fase 13 etapa 6: one attendant per hall. Keeps the stored one if it is a live attendant of this hall, else the
    first live attendant found in the cell; every other ref of the base in the cell is disabled and deleted.
    Returns the keeper, or None when the cell has none.}
    If !akHall || !akBase
        Return None
    EndIf
    Actor keep = None
    If akStored && !akStored.IsDead() && akStored.GetParentCell() == akHall
        keep = akStored
    EndIf
    Int n = akHall.GetNumRefs(43)
    Int k = 0
    While k < n
        Actor r = akHall.GetNthRef(k, 43) as Actor
        If r && r.GetBaseObject() == akBase
            If !keep && !r.IsDead()
                keep = r
            ElseIf r != keep
                AoT_Core.Log("[AoT] Attendant: duplicate removed " + r)
                r.Disable()
                r.Delete()
            EndIf
        EndIf
        k += 1
    EndWhile
    Return keep
EndFunction

Function ProbeReport() Global
    {In-game probe (D034): console `cgf "AoT_Attendant.ProbeReport"`. Logs, per fee band, the
    fee, paid, what the topic condition sees; the delivery and open-contract globals; gold.
    Run SyncGlobals first so it reads what the dialogue will read.}
    SyncGlobals()
    Int b = 1
    While b <= AoT_Core.MaxBand()
        GlobalVariable g = None
        If Game.IsPluginInstalled("AdventurersOfTamriel.esp")
            g = Game.GetFormFromFile(_GlobalId("fee" + b), "AdventurersOfTamriel.esp") as GlobalVariable
        EndIf
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
        AoT_Core.Log("[AoT] Attendant PayFee: already paid band=" + aiBand)
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
        AoT_Core.Log("[AoT] Attendant PayFee: band " + aiBand + " is free")
        Return
    EndIf
    Actor player = Game.GetPlayer()
    Int goldBefore = player.GetGoldAmount()
    If goldBefore < cost
        AoT_Core.Log("[AoT] Attendant PayFee: insufficient gold " + goldBefore + " < " + cost)
        Return
    EndIf
    If !AoT_Core.MarkBandPaid(aiBand)
        AoT_Core.Log("[AoT] Attendant PayFee: band " + aiBand + " was claimed by another caller")
        Return
    EndIf
    player.RemoveItem(Game.GetForm(0x0000000F) as MiscObject, cost)
    ; Fase 14 etapa 2 (B2b): the board shows the band on the same day, not on the next
    AoT_Core.InvalidateBoards()
    Int goldAfter = player.GetGoldAmount()
    AoT_Core.Log("[AoT] Attendant PayFee band=" + aiBand + " cost=" + cost + " gold " + goldBefore + " -> " + goldAfter)
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
    ; D077: the settings page scales every fee (0 = no fee at all, a free band is never charged)
    Return AoT_Core.ScaleByOption(JsonUtil.IntListGet(path, "aot_fee_by_band", aiBand), AoT_Core.FeeMultiplier())
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
    ; Fase 9: a generated contract keeps its quest under aot_own_q<id> (AoT_Contract.TryOpen).
    Quest own = StorageUtil.GetFormValue(None, "aot_own_q" + aiId, None) as Quest
    AoT_Contract oc = own as AoT_Contract
    If oc && AoT_Core.FindOpenContract(own) == aiId
        Return oc.TryAbandon()
    EndIf
    Quest q2b = Game.GetFormFromFile(0x000D97, "AdventurersOfTamriel.esp") as Quest
    If q2b && AoT_Core.FindOpenContract(q2b) == aiId
        AoT_Contract_2b contract = q2b as AoT_Contract_2b
        If contract
            Return contract.TryAbandon()
        EndIf
    EndIf
    Bool ok = AoT_Core.AbandonContract(aiId)
    AoT_Core.Log("[AoT] Attendant Abandon id=" + aiId + " ok=" + ok)
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
    ; Any form from that plugin proves it is loaded (0x800 is its own ARMO). The extension has
    ; no form at 0xF0C of its own, so it is not probed.
    Form f = Game.GetFormFromFile(0x00000800, "Headhunter - Bounties Redone.esp")
    Return f != None
EndFunction

Bool Function HasMMH() Global
    Form f = Game.GetFormFromFile(0x06000845, "MissivesMonsterHunt.esp")
    Return f != None
EndFunction

; -- dialogue glue (Part F, D034) --
; The attendant's topics live in AdventurersOfTamriel.esp. Their conditions read
; globals (gold needs a global to compare against); SyncGlobals keeps them true to the
; save. Fragments call RunAction. Every entry is global: a topic fragment has no quest.
Int Function _GlobalId(String asName) Global
    If asName == "fee1"
        Return 0x000D9D
    ElseIf asName == "fee2"
        Return 0x000D9E
    ElseIf asName == "fee3"
        Return 0x000D9F
    ElseIf asName == "fee4"
        Return 0x000DA0
    ElseIf asName == "fee5"
        Return 0x000DA1
    ElseIf asName == "head"
        Return 0x000DA2
    ElseIf asName == "mmh"
        Return 0x000DA3
    ElseIf asName == "exam"
        Return 0x000E2F
    ElseIf asName == "promote"
        Return 0x000E30
    ; Fase 14 etapa 1 (D077): the globals of the conversation tree, all in AdventurersOfTamriel.esp
    ElseIf asName == "ismember"
        Return 0x000F21
    ElseIf asName == "canunlock"
        Return 0x000F22
    ElseIf asName == "hasdone"
        Return 0x000F23
    ElseIf asName == "opencount"
        Return 0x000F24
    ElseIf asName == "exammarked"
        Return 0x000F25
    ElseIf asName == "canexam"
        Return 0x000F26
    ElseIf asName == "canmarkexam"
        Return 0x000F27
    ElseIf asName == "abandonpick"
        Return 0x000F28
    EndIf
    Return 0x000DA4
EndFunction

Function _SetGlobal(String asName, Int aiValue) Global
    ; the exam and promotion globals live in the ExamTalk plugin (D037); the rest in Actors
    String plug = "AdventurersOfTamriel.esp"
    If asName == "exam" || asName == "promote"
        plug = "AdventurersOfTamriel.esp"
    EndIf
    If !Game.IsPluginInstalled(plug)
        Return
    EndIf
    GlobalVariable g = Game.GetFormFromFile(_GlobalId(asName), plug) as GlobalVariable
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
    Int member = 0
    If AoT_Core.IsMember()
        member = 1
    EndIf
    _SetGlobal("ismember", member)
    AoT_Core.SyncD32()
    ; D077: a fee is offered only for a band the current rank can draw (weight above 0), unpaid, with a price
    Int anyFee = 0
    Int rank = AoT_Core.GetRank()
    Int b = 1
    While b <= AoT_Core.MaxBand()
        Int c = FeeForBand(b)
        If c < 0 || AoT_Core.IsBandPaid(b) || AoT_Core.BandWeight(rank, b) <= 0
            c = 0
        EndIf
        If c > 0
            anyFee = 1
        EndIf
        _SetGlobal("fee" + b, c)
        b += 1
    EndWhile
    If member == 0
        anyFee = 0
    EndIf
    _SetGlobal("canunlock", anyFee)
    ; E5: the adapters find the foreign hunt quest at stage 40 and the attendant records it; with the
    ; third-party mod absent both stay None, the two topics stay hidden (D-35, a control).
    StorageUtil.SetFormValue(None, "aot_head_q", AoT_HeadhunterAdapter.FindReadyQuest())
    StorageUtil.SetFormValue(None, "aot_mmh_q", AoT_MMHAdapter.FindReadyQuest())
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
    ; D077: open contracts, at most 4 (the abandon list has four lines), counted from the ledger
    Int oc = 0
    Int ln = AoT_Core.ContractCount()
    Int li = 1
    While li <= ln && oc < 4
        If AoT_Core.ContractState(li) == 1
            oc += 1
        EndIf
        li += 1
    EndWhile
    If member == 0
        oc = 0
    EndIf
    _SetGlobal("opencount", oc)
    ; Fase 14 etapa 2: the report topic shows while a finished contract waits (ours, aot_to_report) or a Missives
    ; quest of the guild waits at its Steward stage (R1)
    Int done = 0
    If member == 1 && ReadyToReport() > 0
        done = 1
    EndIf
    _SetGlobal("hasdone", done)
    _SetGlobal("abandonpick", StorageUtil.GetIntValue(None, "aot_abandon_pick", 0))
    ; the ladder cut (Fase 8): the exam topic shows when the points enable a promotion that asks for the
    ; room exam and none is running; the plain promotion shows when the cut asks for no exam.
    Int exState = AoT_Exam.ExamState()
    Int eligibleExam = 0
    Int ex = 0
    Int pr = 0
    If AoT_Core.IsPromotionEligible() && exState == 0
        Int kind = AoT_Core.ExamKind(AoT_Core.GetRank())
        If kind == 1
            ex = 1
            eligibleExam = 1
        ElseIf kind == 0
            pr = 1
        EndIf
    EndIf
    If member == 0
        ex = 0
        pr = 0
        eligibleExam = 0
    EndIf
    _SetGlobal("exam", ex)
    _SetGlobal("promote", pr)
    ; D077: the exam is marked at the attendant and taken with the examiner. The mark stays while the exam runs,
    ; and is cleared when the exam ended or the points no longer enable it.
    Int marked = StorageUtil.GetIntValue(None, "aot_exam_marked", 0)
    If marked == 1
        If exState != 0
            StorageUtil.SetIntValue(None, "aot_exam_ran", 1)
        ElseIf StorageUtil.GetIntValue(None, "aot_exam_ran", 0) == 1 || eligibleExam == 0
            StorageUtil.SetIntValue(None, "aot_exam_marked", 0)
            StorageUtil.SetIntValue(None, "aot_exam_ran", 0)
            marked = 0
        EndIf
    EndIf
    Int canMark = 0
    If eligibleExam == 1 && marked == 0
        canMark = 1
    EndIf
    Int canExam = 0
    If eligibleExam == 1 && marked == 1
        canExam = 1
    EndIf
    _SetGlobal("exammarked", marked)
    _SetGlobal("canmarkexam", canMark)
    _SetGlobal("canexam", canExam)
EndFunction

String Function ContractName(Int aiId) Global
    {Display name of the contract with this ledger id, for the abandon list: the name of its quest, else "Contract <id>".}
    Quest own = StorageUtil.GetFormValue(None, "aot_own_q" + aiId, None) as Quest
    If !own
        Quest q2b = Game.GetFormFromFile(0x000D97, "AdventurersOfTamriel.esp") as Quest
        If q2b && AoT_Core.FindOpenContract(q2b) == aiId
            own = q2b
        EndIf
    EndIf
    If own
        String nm = own.GetName()
        If nm != ""
            Return nm
        EndIf
    EndIf
    Return "Contract " + aiId
EndFunction

Function FillSlots() Global
    {D077: the abandon list. The up to four oldest open contracts take slots 1 to 4 (ledger id kept in aot_slot_id_K);
    the name of each is put on a marker reference of its own and that reference fills the matching alias of
    AoT_AttendantTalk (AoT_SlotK), whose text the topic prompt shows ("<Alias=AoT_SlotK>"). INFERRED, not
    measured: that a display name on a marker reaches the alias text of a prompt (D077, to be confirmed in game).}
    Quest tq = Game.GetFormFromFile(0x000DA5, "AdventurersOfTamriel.esp") as Quest
    Int n = AoT_Core.ContractCount()
    Int slot = 1
    Int i = 1
    While i <= n && slot <= 4
        If AoT_Core.ContractState(i) == 1
            StorageUtil.SetIntValue(None, "aot_slot_id_" + slot, i)
            If tq
                _PutSlotName(tq, slot, ContractName(i))
            EndIf
            slot += 1
        EndIf
        i += 1
    EndWhile
    While slot <= 4
        StorageUtil.SetIntValue(None, "aot_slot_id_" + slot, 0)
        slot += 1
    EndWhile
EndFunction

Function _PutSlotName(Quest akTalk, Int aiSlot, String asName) Global
    ReferenceAlias al = akTalk.GetAliasById(aiSlot - 1) as ReferenceAlias
    If !al
        AoT_Core.Log("[AoT] Attendant: alias slot " + aiSlot + " missing on the talk quest")
        Return
    EndIf
    String slotKey = "aot_slot_ref_" + aiSlot
    ObjectReference r = StorageUtil.GetFormValue(None, slotKey, None) as ObjectReference
    If !r
        Form marker = Game.GetForm(0x0000003B)
        r = Game.GetPlayer().PlaceAtMe(marker, 1, True)
        If !r
            AoT_Core.Log("[AoT] Attendant: no marker for slot " + aiSlot)
            Return
        EndIf
        StorageUtil.SetFormValue(None, slotKey, r)
    EndIf
    r.SetDisplayName(asName, True)
    al.ForceRefTo(r)
EndFunction

AoT_MissivesAdapter Function MissivesAdapter() Global
    If !Game.IsPluginInstalled("AdventurersOfTamriel_Missives.esp")
        Return None
    EndIf
    Return Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_Missives.esp") as AoT_MissivesAdapter
EndFunction

Int Function ReadyToReport() Global
    {Fase 14 etapa 2: contracts of ours whose work is done (aot_to_report), plus the Missives quests of the guild at
    their Steward stage (R1).}
    Int n = StorageUtil.FormListCount(None, "aot_to_report")
    AoT_MissivesAdapter ma = MissivesAdapter()
    If ma
        n += ma.CountStewardReady()
    EndIf
    Return n
EndFunction

Int Function ReportAll() Global
    {Fase 14 etapa 2 (Reportar, R1): ours are delivered (points and the band's gold); a Missives quest goes to stage 100,
    where Missives pays its own gold, and the ledger closes it with the points.}
    Int n = 0
    Int i = StorageUtil.FormListCount(None, "aot_to_report") - 1
    While i >= 0
        AoT_Contract c = StorageUtil.FormListGet(None, "aot_to_report", i) as AoT_Contract
        If c && c.Deliver()
            n += 1
        ElseIf !c
            StorageUtil.FormListRemoveAt(None, "aot_to_report", i)
        EndIf
        i -= 1
    EndWhile
    AoT_MissivesAdapter ma = MissivesAdapter()
    If ma
        n += ma.DeliverStewardReady()
    EndIf
    Return n
EndFunction

Function RunAction(Int aiAction, Int aiBand) Global
    {1 pay the fee of aiBand, 2 abandon the oldest open contract, 3 deliver the head,
    4 deliver the MMH hunt, 5 start the promotion exam, 6 promote at a step without exam.
    Fase 14 etapa 1 (D077): 7 join the guild, 8 mark the exam, 9 report (Fase 14 etapa 2), 10 and 11 fill the
    abandon list, 12 abandon the picked slot, 13 refuse, 21 to 24 pick slot 1 to 4. 30 is test surface (D083): take a
    note of the hall board to the player, kind in aiBand.
    Re-syncs the globals after.}
    Quest q = Game.GetFormFromFile(0x000DB6, "AdventurersOfTamriel.esp") as Quest
    AoT_Attendant a = q as AoT_Attendant
    If aiAction == 1
        If a && ShouldShowFee(aiBand)
            a.PayFee(aiBand)
        Else
            AoT_Core.Log("[AoT] Attendant RunAction: fee not payable band=" + aiBand)
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
    ElseIf aiAction == 5
        Bool started = AoT_Exam.StartExam()
        AoT_Core.Log("[AoT] Attendant RunAction: exam started=" + started)
    ElseIf aiAction == 6
        Int rb = AoT_Core.GetRank()
        Int pb = AoT_Core.GetPoints()
        Bool pro = AoT_Core.PromoteWithoutExam()
        AoT_Core.Log("[AoT] Attendant promote=" + pro + " rank " + rb + " -> " + AoT_Core.GetRank() + " points " + pb + " -> " + AoT_Core.GetPoints())
    ElseIf aiAction == 7
        ; D077: "I want to join the guild." - member at rank F
        Bool joined = AoT_Core.JoinGuild()
        AoT_Core.Log("[AoT] Attendant: join=" + joined)
    ElseIf aiAction == 8
        ; the examiner is told the exam is marked; only while the points enable it (SyncGlobals clears a stale mark)
        SyncGlobals()
        If Game.GetFormFromFile(0x000F27, "AdventurersOfTamriel.esp") as GlobalVariable
            If (Game.GetFormFromFile(0x000F27, "AdventurersOfTamriel.esp") as GlobalVariable).GetValue() > 0.5
                StorageUtil.SetIntValue(None, "aot_exam_marked", 1)
                StorageUtil.SetIntValue(None, "aot_exam_ran", 0)
            EndIf
        EndIf
    ElseIf aiAction == 9
        ; Fase 14 etapa 2: "I want to report a finished contract." - every finished contract is paid at once
        Int rp = AoT_Core.GetPoints()
        Int rn = ReportAll()
        AoT_Core.Log("[AoT] Attendant: report delivered=" + rn + " points " + rp + " -> " + AoT_Core.GetPoints())
    ElseIf aiAction == 10 || aiAction == 11
        ; open the abandon list / greet: the slot names are filled before the topic menu is built
        StorageUtil.SetIntValue(None, "aot_abandon_pick", 0)
        FillSlots()
    ElseIf aiAction == 12
        ; "Yes, abandon it.": the ledger id kept for the picked slot, abandoned only while still open
        Int pick = StorageUtil.GetIntValue(None, "aot_abandon_pick", 0)
        Int aid = 0
        If pick >= 1 && pick <= 4
            aid = StorageUtil.GetIntValue(None, "aot_slot_id_" + pick, 0)
        EndIf
        If aid > 0 && a && AoT_Core.ContractState(aid) == 1
            Bool gone = a.TryAbandonById(aid)
            AoT_Core.Log("[AoT] Attendant: abandon slot " + pick + " id " + aid + " ok=" + gone)
        Else
            AoT_Core.Log("[AoT] Attendant: abandon pick " + pick + " is not an open contract")
        EndIf
        StorageUtil.SetIntValue(None, "aot_abandon_pick", 0)
    ElseIf aiAction == 13
        StorageUtil.SetIntValue(None, "aot_abandon_pick", 0)
    ElseIf aiAction >= 21 && aiAction <= 24
        ; a line of the abandon list was picked: remember which slot until the player confirms or refuses
        StorageUtil.SetIntValue(None, "aot_abandon_pick", aiAction - 20)
    ElseIf aiAction == 30
        ; test surface (D083): take a note of the hall board to the player, kind in aiBand (0 ours, 1 Missives, 2 Missives with a Steward)
        AoT_GuildBoardAlias ba = AoT_ContractsCtl.Get().GetAlias(0) as AoT_GuildBoardAlias
        If ba
            ba.TestTakeNote(aiBand)
        EndIf
    EndIf
    SyncGlobals()
EndFunction
