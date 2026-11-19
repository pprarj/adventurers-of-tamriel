Scriptname AoT_Attendant extends Quest
{The guild clerk: fee, abandon and delivery.
Logic is Papyrus plus AoT_Core; the core has no third-party master. The Headhunter
and MMH branches are soft: they probe at runtime with Game.GetFormFromFile and hide
when the soft master is absent, without logging an error (D007).
No properties need filling: every lookup is by form file at runtime.}

; -- keeps the dialogue true (D034): a 3 second tick watches the attendant (D117) when the player is in
; the guild hall, and every 7th tick re-syncs the dialogue globals. Single updates are re-armed
; in OnUpdate and persist across saves. Cheap: a cell compare per tick, a few reads per sync.
Int _tick = 0

Event OnInit()
    RegisterForSingleUpdate(3.0)
EndEvent

Event OnUpdate()
    ; Fase 15 etapa 12 (D107): a change of the abandon list refreshes its quest here, on this script's own thread
    ; (MarkListDirty brings this update forward to now)
    If StorageUtil.GetIntValue(None, "aot_list_dirty", 0) == 1
        RefreshList()
    EndIf
    ; D117: without PapyrusUtil or the table of halls one line per load says so; nothing of the halls is watched
    If CheckDeps()
        EnsureAttendant()
        AoT_Hall.EnsureFixtures()
    EndIf
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

String Function HallHoldHere() Global
    {Fase 16 etapa 5 (D113): the hold of the hall the player stands in, read from the table of halls ("" outside a hall).}
    Cell here = Game.GetPlayer().GetParentCell()
    If !here || !here.IsInterior()
        Return ""
    EndIf
    String path = HallsPath()
    Int n = JsonUtil.StringListCount(path, "aot_hall_holds")
    Int i = 0
    While i < n
        String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + i, "")
        If plug != ""
            Cell c = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + i, 0), plug) as Cell
            If c && c == here
                Return JsonUtil.StringListGet(path, "aot_hall_holds", i)
            EndIf
        EndIf
        i += 1
    EndWhile
    Return ""
EndFunction

Function StampJoinHold() Global
    {Fase 16 etapa 5 (D113): the hold of the member's first hall is kept once ("aot_join_hold"), read by the card's crest.
    Called at the join and at every greeting, so a save that joined before it existed gets its hold at the next talk.}
    If StorageUtil.GetStringValue(None, "aot_join_hold", "") != "" || !AoT_Core.IsMember()
        Return
    EndIf
    String hold = HallHoldHere()
    If hold != "" && AoT_Core._CanWrite()
        StorageUtil.SetStringValue(None, "aot_join_hold", hold)
        AoT_Core.Log("[AoT] Attendant: join hold " + hold)
    EndIf
EndFunction

Function EnsureAttendant() Global
    {Fase 16 etapa 10 (D117): the attendant of each hall is a persistent ACHR of the hall's _Interiors plugin, at the
    AoT_GuildHallAttendantSpot marker, held there by DefaultStayAtEditorLocation. This only watches her: the plugin's
    ref (index 5 of the hall row in halls.json) is adopted, restored when dead, disabled or out of the hall, and a ref
    of the base the script created in a 1.0/1.1 save is removed (AoT_Hall.WatchNpc). Nothing is placed, moved back
    to the counter or held with SetDontMove any more.}
    Int i = AoT_Exam.HallIndexOfPlayer()
    If i < 0 || !Game.IsPluginInstalled("AdventurersOfTamriel.esp")
        Return
    EndIf
    ActorBase base = Game.GetFormFromFile(0x000D99, "AdventurersOfTamriel.esp") as ActorBase
    Actor a = AoT_Hall.WatchNpc(i, 1, 5, base, "aot_att_ref_", "Attendant")
    If a && StorageUtil.GetFormValue(None, "aot_att_ref", None) != a
        StorageUtil.SetFormValue(None, "aot_att_ref", a)
    EndIf
EndFunction

; -- once per load (D117): a missing dependency is said in the log once, not every tick --
String _warned = ""

Function NewLoad()
    {Called by AoT_MCM.OnGameReload: the warnings may be said again after this load.}
    _warned = ""
EndFunction

Function _WarnOnce(String asKey, String asLine)
    If StringUtil.Find(_warned, "|" + asKey + "|") < 0
        _warned += "|" + asKey + "|"
        Debug.Trace(asLine)
    EndIf
EndFunction

Function Warn(String asKey, String asLine) Global
    {One [AoT] line per load for the key (without SkyUI, whose quest gives the load event, once per session).}
    AoT_Attendant a = Game.GetFormFromFile(0x000DB6, "AdventurersOfTamriel.esp") as AoT_Attendant
    If a
        a._WarnOnce(asKey, asLine)
    Else
        Debug.Trace(asLine)
    EndIf
EndFunction

Bool Function CheckDeps() Global
    {D117: the halls are found through PapyrusUtil and Config/AdventurersOfTamriel/halls.json. Without either, nothing
    of the guild appears in the halls; that was silent and is now one log line per load. False when one is missing.}
    If PapyrusUtil.GetVersion() <= 0
        Warn("papyrusutil", "[AoT] PapyrusUtil not loaded: the guild halls are not watched (no attendant, examiner or board check)")
        Return False
    EndIf
    If !JsonUtil.JsonExists(HallsPath()) || JsonUtil.StringListCount(HallsPath(), "aot_hall_holds") <= 0
        Warn("halls", "[AoT] Config/AdventurersOfTamriel/halls.json missing or empty: the guild halls are not watched")
        Return False
    EndIf
    Return True
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
    ; Fase 15 etapa 1 (D089, R4-3): a Missives contract leaves the journal through the quest's own cleanup stage
    If ok
        AoT_MissivesAdapter ma = MissivesAdapter()
        If ma
            ma.CleanUpAbandoned(aiId)
        EndIf
    EndIf
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
    ElseIf asName == "hassteward"
        ; Fase 14 etapa 4 (D085): a Missives quest of the guild waits at its Steward stage (the R1 topic)
        Return 0x000F5F
    ElseIf asName == "listready"
        ; Fase 15 etapa 12 (D107): 1 once the abandon list's quest holds the current list (D108: its location aliases)
        Return 0x000F62
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
    ; D077: open contracts, at most 4 (the abandon list has four lines), counted from the ledger.
    ; Fase 15 etapa 1 (D089, R4-3): the count and the four slots come from the same pass (FillSlots), on every sync.
    ; Fase 15 etapa 13 (D108): the destinations reach the list quest's location aliases (RefreshList); its topic waits.
    Int oc = 0
    If member == 1
        oc = FillSlots(False)
    EndIf
    If oc > 4
        oc = 4
    EndIf
    _SetGlobal("opencount", oc)
    ; Fase 14 etapa 4 (D085): the report topic shows while a finished contract of ours waits (aot_to_report); the R1
    ; topic while a Missives quest of the guild waits at its Steward stage. Two numbers, two topics.
    Int done = 0
    If member == 1 && ReadyToReport() > 0
        done = 1
    EndIf
    _SetGlobal("hasdone", done)
    Int steward = 0
    If member == 1 && ReadyAtSteward() > 0
        steward = 1
    EndIf
    _SetGlobal("hassteward", steward)
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

Quest Function ContractQuest(Int aiId) Global
    {The quest of the contract with this ledger id: ours (aot_own_q), a Missives quest of the guild (aot_missives_q,
    Fase 15 etapa 1, D089), or the 2b quest; None for a contract without a quest.}
    Quest q = StorageUtil.GetFormValue(None, "aot_own_q" + aiId, None) as Quest
    If !q
        q = StorageUtil.GetFormValue(None, "aot_missives_q" + aiId, None) as Quest
    EndIf
    If !q
        Quest q2b = Game.GetFormFromFile(0x000D97, "AdventurersOfTamriel.esp") as Quest
        If q2b && AoT_Core.FindOpenContract(q2b) == aiId
            q = q2b
        EndIf
    EndIf
    Return q
EndFunction

String Function ContractName(Int aiId) Global
    {Display name of the contract with this ledger id, for the abandon list: the name of its quest, else "Contract <id>".
    Fase 15 etapa 1 (D089): a Missives contract is named by its own quest too (it fell back to "Contract <id>").}
    Quest q = ContractQuest(aiId)
    If q
        String nm = q.GetName()
        If nm != ""
            Return nm
        EndIf
    EndIf
    Return "Contract " + aiId
EndFunction

Location Function ContractLocation(Int aiId) Global
    {Fase 15 etapa 13 (D108): the destination of the contract with this ledger id, the name its line in the abandon list
    shows. Ours: the contract's dungeon (alias 1 of AoT_Contract, the <Alias=Dungeon> of the note's name). Another
    quest (Missives, the legacy 2b): its first location alias that holds a location other than a hold, else its first
    that holds one. None when the quest has no location.}
    Quest q = ContractQuest(aiId)
    If !q
        Return None
    EndIf
    AoT_Contract c = q as AoT_Contract
    If c
        Return c.DungeonLocation()
    EndIf
    Keyword hold = Game.GetForm(0x00016771) as Keyword
    Location first = None
    Int n = q.GetNumAliases()
    Int i = 0
    While i < n
        LocationAlias la = q.GetNthAlias(i) as LocationAlias
        If la && la.GetLocation()
            If !hold || !la.GetLocation().HasKeyword(hold)
                Return la.GetLocation()
            EndIf
            If !first
                first = la.GetLocation()
            EndIf
        EndIf
        i += 1
    EndWhile
    Return first
EndFunction

String Function ContractPlace(Int aiId) Global
    {Fase 15 etapa 13 (D108): the name of the contract's destination, "<no location>" without one (log and signature).}
    Location loc = ContractLocation(aiId)
    If loc
        Return loc.GetName()
    EndIf
    Return "<no location>"
EndFunction

Int Function FillSlots(Bool abLog = False) Global
    {D077: the abandon list. The up to four oldest open contracts take slots 1 to 4 (ledger id kept in aot_slot_id_K).
    Fase 15 etapa 12 (D107): this pass writes no alias; it marks the list for RefreshList when the four ids or
    destinations changed, or when the list quest runs without an open contract or is stopped with one. Returns every
    open contract (a fifth and later wait for a free line).}
    String sig = _ComputeSlots()
    Int open = StorageUtil.GetIntValue(None, "aot_list_open", 0)
    Quest lq = ListQuest()
    Bool running = lq && lq.IsRunning()
    Float busyAt = StorageUtil.GetFloatValue(None, "aot_list_busy_at", 0.0)
    Bool busy = busyAt > 0.0 && Utility.GetCurrentGameTime() - busyAt < 0.005
    If !busy && (sig != StorageUtil.GetStringValue(None, "aot_list_sig", "") || (open > 0) != running)
        MarkListDirty("fill")
    EndIf
    If abLog
        AoT_Core.Log("[AoT-F15] abandon list n=" + open + " " + sig)
    EndIf
    ; D105: what the topic list can show, every line, the empty ones too (R4-3 "Empty"); debug log only
    If AoT_Core.DebugLogOn()
        AoT_Core.Log("[AoT] Attendant: list shown n=" + open + " listRunning=" + running + " busy=" + busy + _ShownSlots(lq))
    EndIf
    Return open
EndFunction

String Function _ComputeSlots() Global
    {Fase 15 etapa 12 (D107): writes aot_slot_id_1..4 (0 for an empty slot) and aot_list_open (every open contract);
    returns the list's signature, "id:destination|" per filled slot (Fase 15 etapa 13, D108: the destination).}
    Int n = AoT_Core.ContractCount()
    Int open = 0
    Int slot = 1
    String sig = ""
    Int i = 1
    While i <= n
        If AoT_Core.ContractState(i) == 1
            open += 1
            If slot <= 4
                StorageUtil.SetIntValue(None, "aot_slot_id_" + slot, i)
                sig += i + ":" + ContractPlace(i) + "|"
                slot += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    While slot <= 4
        StorageUtil.SetIntValue(None, "aot_slot_id_" + slot, 0)
        slot += 1
    EndWhile
    StorageUtil.SetIntValue(None, "aot_list_open", open)
    Return sig
EndFunction

Quest Function ListQuest() Global
    {Fase 15 etapa 12 (D107): AoT_AttendantList, the quest of the abandon list's topics (AoT_AttDrop*).}
    Return Game.GetFormFromFile(0x000F67, "AdventurersOfTamriel.esp") as Quest
EndFunction

LocationAlias Function _SlotAlias(Quest akList, Int aiSlot) Global
    {Fase 15 etapa 13 (D108): slot K of the list is the location alias AoT_LocK, alias id 4 + K.}
    If !akList
        Return None
    EndIf
    Return akList.GetAliasById(4 + aiSlot) as LocationAlias
EndFunction

Function MarkListDirty(String asWhy) Global
    {Fase 15 etapa 12 (D107): the abandon list changed (a contract opened or closed in the ledger, or FillSlots saw
    other ids or destinations). The attendant quest refreshes the list quest on its next update, brought forward to now.}
    StorageUtil.SetIntValue(None, "aot_list_dirty", 1)
    StorageUtil.SetStringValue(None, "aot_list_why", asWhy)
    AoT_Attendant a = Game.GetFormFromFile(0x000DB6, "AdventurersOfTamriel.esp") as AoT_Attendant
    If a
        a.RegisterForSingleUpdate(0.2)
    EndIf
    AoT_Core.Log("[AoT-F15e12] list marked why=" + asWhy)
EndFunction

Function RefreshList() Global
    {Fase 15 etapa 13 (D108): puts the current list in AoT_AttendantList. The quest runs while a contract is open; slot
    K is its location alias AoT_LocK, forced to the contract's destination with ForceLocationTo while the quest runs,
    and the prompt <Alias=AoT_LocK> shows that location's name. Same order as Skyrim.esm: MQ302 runs, its stage 40
    starts MQ302FillAliases, which forces MQ302's location aliases (Optional, Allow Reuse, Stores Text, Allow Reserved),
    and MQ302's prompts read them ("How about <Alias=SonsMajorHoldCapital>?"). An empty slot is cleared; with no
    contract the quest stops. A quest still running with the etapa 12 aliases is restarted once, and the etapa 11/12
    slot markers are deleted. Runs on the attendant quest's update; a change during the refresh runs it again (three
    passes at most).}
    Quest lq = ListQuest()
    If !lq
        Debug.Trace("[AoT] Attendant: list quest not found")
        Return
    EndIf
    Int pass = 0
    While pass < 3 && (pass == 0 || StorageUtil.GetIntValue(None, "aot_list_dirty", 0) == 1)
        pass += 1
        StorageUtil.SetIntValue(None, "aot_list_dirty", 0)
        StorageUtil.SetFloatValue(None, "aot_list_busy_at", Utility.GetCurrentGameTime())
        _SetGlobal("listready", 0)
        String sig = _ComputeSlots()
        Int open = StorageUtil.GetIntValue(None, "aot_list_open", 0)
        Bool was = lq.IsRunning()
        Bool oldLayout = StorageUtil.GetIntValue(None, "aot_list_layout", 0) != 13
        If oldLayout
            _DropOldMarkers()
        EndIf
        If was && (open == 0 || oldLayout)
            lq.Stop()
            Int w = 0
            While lq.IsRunning() && w < 50
                Utility.Wait(0.1)
                w += 1
            EndWhile
        EndIf
        StorageUtil.SetIntValue(None, "aot_list_layout", 13)
        Bool started = False
        If open > 0 && !lq.IsRunning()
            started = lq.Start()
            Int s = 0
            While !lq.IsRunning() && s < 50
                Utility.Wait(0.1)
                s += 1
            EndWhile
        EndIf
        String line = ""
        Int k = 1
        While k <= 4
            LocationAlias la = _SlotAlias(lq, k)
            Int id = StorageUtil.GetIntValue(None, "aot_slot_id_" + k, 0)
            Location loc = None
            If id > 0
                loc = ContractLocation(id)
            EndIf
            If !la
                line += " slot" + k + "=" + id + ":<no alias>"
            ElseIf loc && lq.IsRunning()
                la.ForceLocationTo(loc)
                line += " slot" + k + "=" + id + ":" + loc.GetName()
            Else
                la.Clear()
                If id > 0
                    line += " slot" + k + "=" + id + ":<no location>"
                Else
                    line += " slot" + k + "=0:<empty>"
                EndIf
            EndIf
            k += 1
        EndWhile
        StorageUtil.SetStringValue(None, "aot_list_sig", sig)
        If open > 0 && lq.IsRunning()
            _SetGlobal("listready", 1)
        EndIf
        AoT_Core.Log("[AoT-F15e13] list refresh pass=" + pass + " why=" + StorageUtil.GetStringValue(None, "aot_list_why", "") + " wasRunning=" + was + " oldLayout=" + oldLayout + " started=" + started + " running=" + lq.IsRunning() + " n=" + open + " forced:" + line)
        AoT_Core.Log("[AoT-F15e13] list refresh pass=" + pass + " read back:" + _ShownSlots(lq))
    EndWhile
    StorageUtil.SetFloatValue(None, "aot_list_busy_at", 0.0)
EndFunction

Function _DropOldMarkers() Global
    {Fase 15 etapa 13 (D108): the etapa 11/12 slot markers (persistent XMarkers kept under aot_slot_ref_K) are no
    longer used; each is deleted once and its key unset.}
    Int k = 1
    While k <= 4
        ObjectReference r = StorageUtil.GetFormValue(None, "aot_slot_ref_" + k, None) as ObjectReference
        If r
            r.Disable()
            r.Delete()
        EndIf
        StorageUtil.UnsetFormValue(None, "aot_slot_ref_" + k)
        k += 1
    EndWhile
EndFunction

String Function _ShownSlots(Quest akList) Global
    {D105: per slot, the ledger id kept and what the slot's alias holds ("<empty>" with nothing).
    Fase 15 etapa 13 (D108): the slots are the location aliases AoT_Loc1..4 (alias ids 5 to 8); read back by
    GetLocation and the location's name.}
    String line = ""
    Int k = 1
    While k <= 4
        String shown = "<no list quest>"
        If akList
            shown = "<empty>"
            LocationAlias la = _SlotAlias(akList, k)
            If !la
                shown = "<no alias>"
            ElseIf la.GetLocation()
                shown = la.GetLocation().GetName()
            EndIf
        EndIf
        line += " slot" + k + "=" + StorageUtil.GetIntValue(None, "aot_slot_id_" + k, 0) + ":" + shown
        k += 1
    EndWhile
    Return line
EndFunction

Function _LogAtSpeech(String asWhat) Global
    {Fase 15 etapa 12 (D107): at a line of the abandon list, whether the list quest runs and what its aliases hold.}
    Quest lq = ListQuest()
    Int ready = -1
    GlobalVariable g = Game.GetFormFromFile(0x000F62, "AdventurersOfTamriel.esp") as GlobalVariable
    If g
        ready = g.GetValueInt()
    EndIf
    AoT_Core.Log("[AoT-F15e13] at speech " + asWhat + " listRunning=" + (lq && lq.IsRunning()) + " ready=" + ready + _ShownSlots(lq))
EndFunction

AoT_MissivesAdapter Function MissivesAdapter() Global
    If !Game.IsPluginInstalled("AdventurersOfTamriel_Missives.esp")
        Return None
    EndIf
    Return Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_Missives.esp") as AoT_MissivesAdapter
EndFunction

Int Function ReadyToReport() Global
    {Fase 14 etapa 4 (D085): contracts of ours whose work is done (aot_to_report). The Missives quests at their Steward
    stage have their own topic now (ReadyAtSteward).}
    Return StorageUtil.FormListCount(None, "aot_to_report")
EndFunction

Int Function ReadyAtSteward() Global
    {Fase 14 etapa 4 (D085, R1): the Missives quests of the guild (aot_open) waiting at their Steward stage.}
    AoT_MissivesAdapter ma = MissivesAdapter()
    If ma
        Return ma.CountStewardReady()
    EndIf
    Return 0
EndFunction

Int Function DeliverAtSteward() Global
    {Fase 14 etapa 4 (D085, R1): each Missives quest at its Steward stage goes to stage 100, where Missives pays its own
    gold, and the ledger closes it with the points.}
    AoT_MissivesAdapter ma = MissivesAdapter()
    If ma
        Return ma.DeliverStewardReady()
    EndIf
    Return 0
EndFunction

Int Function ReportAll() Global
    {Fase 14 etapa 2 (Reportar): ours are delivered (points and the band's gold). Fase 14 etapa 4 (D085): the Missives
    quests at their Steward stage left this path for DeliverAtSteward (action 14).}
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
    Return n
EndFunction

Function RunAction(Int aiAction, Int aiBand) Global
    {1 pay the fee of aiBand, 2 abandon the oldest open contract, 3 deliver the head,
    4 deliver the MMH hunt, 5 start the promotion exam, 6 promote at a step without exam.
    Fase 14 etapa 1 (D077): 7 join the guild, 8 mark the exam, 9 report (Fase 14 etapa 2; ours only since etapa 4),
    10 and 11 fill the abandon list, 12 abandon the picked slot, 13 refuse, 14 turn in the Missives quests at their
    Steward stage (R1, Fase 14 etapa 4, D085), 21 to 24 pick slot 1 to 4. 30 is test surface (D083): take a note of
    the hall board to the player, kind in aiBand.
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
        StampJoinHold()
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
    ElseIf aiAction == 14
        ; Fase 14 etapa 4 (D085): "I finished a job the steward posted." - every Missives quest at its Steward stage
        Int sp = AoT_Core.GetPoints()
        Int sn = DeliverAtSteward()
        AoT_Core.Log("[AoT] Attendant: steward delivered=" + sn + " points " + sp + " -> " + AoT_Core.GetPoints())
    ElseIf aiAction == 10 || aiAction == 11
        ; open the abandon list / greet (Fase 15 etapa 1, D089: SyncGlobals fills the slots too; action 10 writes the
        ; list to the log). Fase 15 etapa 12 (D107): a change found here refreshes the list quest (FillSlots, RefreshList)
        StorageUtil.SetIntValue(None, "aot_abandon_pick", 0)
        StampJoinHold()
        If aiAction == 10
            _LogAtSpeech("open")
        EndIf
        FillSlots(aiAction == 10)
    ElseIf aiAction == 12
        ; "Yes, abandon it.": the ledger id kept for the picked slot, abandoned only while still open
        Int pick = StorageUtil.GetIntValue(None, "aot_abandon_pick", 0)
        Int aid = 0
        If pick >= 1 && pick <= 4
            aid = StorageUtil.GetIntValue(None, "aot_slot_id_" + pick, 0)
        EndIf
        If aid > 0 && a && AoT_Core.ContractState(aid) == 1
            Quest cq = ContractQuest(aid)
            String cn = ContractName(aid)
            Bool gone = a.TryAbandonById(aid)
            AoT_Core.Log("[AoT] Attendant: abandon slot " + pick + " id " + aid + " ok=" + gone)
            AoT_Core.Log("[AoT-F15] abandon done q=" + cq + " id=" + aid + " name=" + cn + " ok=" + gone + " state=" + AoT_Core.ContractState(aid) + " points=" + AoT_Core.GetPoints())
        Else
            AoT_Core.Log("[AoT] Attendant: abandon pick " + pick + " is not an open contract")
            AoT_Core.Log("[AoT-F15] abandon refused pick=" + pick + " id=" + aid)
        EndIf
        StorageUtil.SetIntValue(None, "aot_abandon_pick", 0)
    ElseIf aiAction == 13
        AoT_Core.Log("[AoT-F15] abandon kept pick=" + StorageUtil.GetIntValue(None, "aot_abandon_pick", 0))
        StorageUtil.SetIntValue(None, "aot_abandon_pick", 0)
    ElseIf aiAction >= 21 && aiAction <= 24
        ; a line of the abandon list was picked: remember which slot until the player confirms or refuses
        StorageUtil.SetIntValue(None, "aot_abandon_pick", aiAction - 20)
        AoT_Core.Log("[AoT-F15] abandon pick slot=" + (aiAction - 20) + " id=" + StorageUtil.GetIntValue(None, "aot_slot_id_" + (aiAction - 20), 0))
        _LogAtSpeech("pick " + (aiAction - 20))
    ElseIf aiAction == 30
        ; test surface (D083): take a note of the hall board to the player, kind in aiBand (0 ours, 1 Missives, 2 Missives with a Steward)
        ; Fase 16 etapa 13 (D123): a Missives note sits on the Missives board, alias 1, when it is filled
        AoT_GuildBoardAlias ba = AoT_ContractsCtl.Get().GetAlias(0) as AoT_GuildBoardAlias
        If aiBand != 0
            AoT_GuildBoardAlias bm = AoT_ContractsCtl.Get().GetAlias(1) as AoT_GuildBoardAlias
            If bm && bm.GetReference()
                ba = bm
            EndIf
        EndIf
        If ba
            ba.TestTakeNote(aiBand)
        EndIf
    EndIf
    SyncGlobals()
EndFunction
