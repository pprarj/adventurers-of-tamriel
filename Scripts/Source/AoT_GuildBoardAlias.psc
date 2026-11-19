Scriptname AoT_GuildBoardAlias extends ReferenceAlias
{The guild board of the hall (Fase 9, D038, D039). Activating it refreshes the offers once per
game day and per board, then opens the container. The pool of a band is our generated contracts
of this hold (any hold when this one has none) plus, with Missives installed, the Missives list of
the same band, one item one chance. The band draw, the [Above Rank] quota (2 from rank+1, 1 from
rank+2) and the paid gate are the ones of the Fase 8 board (D005). One situation contract when its
world event is on, and the emergency call when the cut asks for it. Offering is not taking (D026).
Conserto fase 9 (D042): a quest whose Start() fails leaves this refresh and the board tries the
next one; when the free quests run out, an untaken offer sitting on another board moves here; the
situation goes first and retires the untaken offer of its common counterpart; a Missives quest is
offered at most once per refresh and the stale cleanup never stops one offered in this refresh.
Conserto fase 9b (D043): the Missives quest this board offered and nobody took leaves at the next
refresh, as ours do; the stale cleanup leaves alone a Missives offer of another board.
Fase 10 (D047): the draw runs over every band up to AoT_Core.MaxBand(). Bands 4 (our A) and 5
(our S) are our lists only, read by the id in contracts.json (aot_band_flst). A band is open when
it is Low, paid, or free in the table (fee <= 0); a band whose pick came back empty leaves the
draw of this refresh, so an empty band no longer eats the offers of the others.}

FormList Property OurLow Auto
FormList Property OurMed Auto
FormList Property OurHigh Auto
FormList Property OurVeryHigh Auto
FormList Property OurSituation Auto
FormList Property OurEmergency Auto
Container Property BoardBase Auto
; Fase 16 etapa 13 (D123): alias 1 (MissivesSide) is the Missives board of the hall and offers only the Missives lists;
; alias 0 is our board and offers only ours (situation, contracts, emergency)
Bool Property MissivesSide = False Auto

FormList MissLow
FormList MissMed
FormList MissHigh
FormList MissVeryHigh
FormList _ourA
FormList _ourS
Bool _busy = False

; per refresh (D042): what was offered and what failed to start, our side and Missives side
Quest[] _offered
Int _nOffered = 0
Quest[] _failed
Int _nFailed = 0
Bool[] _bandDry
Quest[] _missSkip
Int _nMissSkip = 0
Quest[] _retired
Int _nRetired = 0
Bool _steal = False

; Fase 14 etapa 2: the board is filled while the player is in the hall (RequestRefresh, from the hall tick), so it
; is full before anyone activates it, and the container opens once, after any refresh in flight.
Bool _openWhenDone = False

Event OnActivate(ObjectReference akActionRef)
	If akActionRef != Game.GetPlayer()
		Return
	EndIf
	_openWhenDone = True
	TryRefresh(True)
EndEvent

Event OnItemAdded(Form akBaseItem, Int aiItemCount, ObjectReference akItemReference, ObjectReference akSourceContainer)
	{Conserto 1 da etapa 2 (D083): another mod may post a note on the nearest Missives board, which is this one (Monster
	Hunt Missives keeps its hunts posted there every 15 s). A non member sees it leave at once, not at the next tick.}
	If !AoT_Core.IsMember()
		RequestRefresh()
	EndIf
EndEvent

Function RequestRefresh()
	{Fase 14 etapa 2: asked by the hall tick; runs on this alias' own thread so the tick does not wait.}
	RegisterForSingleUpdate(0.1)
EndFunction

Event OnUpdate()
	TryRefresh(False)
EndEvent

Function TryRefresh(Bool abActivation)
	{Fase 14 etapa 2: one refresh at a time. A non member sees an empty board; a member gets the offers of the day,
	again when a fee, the join or a promotion changed what the board may offer (aot_board_epoch). The player who
	activated the board while a refresh was running gets the container once, at its end.}
	ObjectReference board = GetReference()
	If !board || _busy
		Return
	EndIf
	_busy = True
	If !AoT_Core.IsMember()
		If StorageUtil.GetIntValue(board, "aot_board_empty", 0) == 0
			ClearBoard(board)
			StorageUtil.SetIntValue(board, "aot_board_empty", 1)
		ElseIf board.GetNumItems() > 0
			HoldForeign(board)
		EndIf
	Else
		ReleaseHeld(board)
		If IsDue(board, abActivation)
			Refresh(board)
			StorageUtil.SetIntValue(board, "aot_board_empty", 0)
		EndIf
	EndIf
	_busy = False
	If _openWhenDone
		_openWhenDone = False
		board.Activate(Game.GetPlayer(), True)
	EndIf
EndFunction

Bool Function IsDue(ObjectReference akBoard, Bool abActivation)
	{Once per game day and per board; at once when aot_board_epoch moved since this board's last refresh. The test
	switch aot_board_nogate = 1 refreshes at every activation, never from the tick.}
	If abActivation && StorageUtil.GetIntValue(None, "aot_board_nogate", 0) == 1
		Return True
	EndIf
	If StorageUtil.GetIntValue(akBoard, "aot_board_epoch", -1) != StorageUtil.GetIntValue(None, "aot_board_epoch", 0)
		Return True
	EndIf
	Return Utility.GetCurrentGameTime() >= StorageUtil.GetFloatValue(akBoard, "aot_board_day", -100.0) + 1.0
EndFunction

Function ClearBoard(ObjectReference akBoard)
	{Fase 14 etapa 2: no offer for a non member. The untaken offers of this board leave, and the next refresh is due
	as soon as the player joins.}
	_offered = new Quest[64]
	_nOffered = 0
	_failed = new Quest[64]
	_nFailed = 0
	_retired = new Quest[64]
	_nRetired = 0
	RetireOwn(akBoard)
	RetireMissives(akBoard)
	StorageUtil.UnsetFloatValue(akBoard, "aot_board_day")
	Debug.Trace("[AoT-F9] board cleared " + akBoard + ": not a member, items=" + akBoard.GetNumItems())
	If akBoard.GetNumItems() > 0
		HoldForeign(akBoard)
	EndIf
EndFunction

ObjectReference Function HolderOf(ObjectReference akBoard)
	{Conserto 1 da etapa 2 (D083): a disabled container of our board base, placed once at the board, that keeps what
	other mods posted here while the player is not a member. Its base is not the Missives one, so no alias of theirs
	ever picks it.}
	ObjectReference holder = StorageUtil.GetFormValue(akBoard, "aot_board_hold", None) as ObjectReference
	If holder
		Return holder
	EndIf
	Form base = Game.GetFormFromFile(0x000DB8, AoT_ContractsCtl.PluginName())
	If !base
		Return None
	EndIf
	holder = akBoard.PlaceAtMe(base, 1, True, True)
	If holder
		StorageUtil.SetFormValue(akBoard, "aot_board_hold", holder)
		Debug.Trace("[AoT-F14] board holder " + holder + " placed for " + akBoard)
	EndIf
	Return holder
EndFunction

Function HoldForeign(ObjectReference akBoard)
	{Conserto 1 da etapa 2 (D083): a non member sees no note at all. What is left after our cleanup is not ours (a note
	of another mod's quest, which still runs): it waits in the holder, quest items too, and comes back at the join.}
	ObjectReference holder = HolderOf(akBoard)
	If !holder
		Debug.Trace("[AoT-F14] board " + akBoard + ": no holder, items=" + akBoard.GetNumItems())
		Return
	EndIf
	Int n = akBoard.GetNumItems()
	akBoard.RemoveAllItems(holder, True, True)
	Debug.Trace("[AoT-F14] board held " + n + " foreign items of " + akBoard + " in " + holder + ", left=" + akBoard.GetNumItems())
EndFunction

Function ReleaseHeld(ObjectReference akBoard)
	{Conserto 1 da etapa 2 (D083): the member gets back what other mods posted here before the join.}
	ObjectReference holder = StorageUtil.GetFormValue(akBoard, "aot_board_hold", None) as ObjectReference
	If !holder || holder.GetNumItems() <= 0
		Return
	EndIf
	Int n = holder.GetNumItems()
	holder.RemoveAllItems(akBoard, True, True)
	Debug.Trace("[AoT-F14] board released " + n + " held items to " + akBoard + ", items=" + akBoard.GetNumItems())
EndFunction

Function Refresh(ObjectReference akBoard)
	AoT_Emergency.Heal()
	AoT_ContractsCtl ctl = GetOwningQuest() as AoT_ContractsCtl
	If ctl
		ctl.EnsureForbidden()
	EndIf
	StorageUtil.SetFloatValue(akBoard, "aot_board_day", Utility.GetCurrentGameTime())
	StorageUtil.SetIntValue(akBoard, "aot_board_epoch", StorageUtil.GetIntValue(None, "aot_board_epoch", 0))
	Int hall = AoT_Exam.HallIndexOfPlayer()
	Debug.Trace("[AoT-F9] board refresh " + akBoard + " hall=" + hall + " rank=" + AoT_Core.GetRank() + " missives=" + ResolveMissives(hall) + " side=" + MissivesSide)
	_offered = new Quest[64]
	_nOffered = 0
	_failed = new Quest[64]
	_nFailed = 0
	_bandDry = new Bool[6]
	_retired = new Quest[64]
	_nRetired = 0
	LoadMissSkip()
	If MissivesSide
		; Fase 16 etapa 13 (D123): the Missives board shows the Missives lists of its hold (D048), nothing of ours
		OfferMissives(akBoard, hall)
		; conserto 1 da etapa 2 (D083): an untaken Missives offer still shown stays (OfferMissives keeps it); only the rest leaves
		RetireMissives(akBoard)
	Else
		RetireOwn(akBoard)
		OfferSituation(akBoard, hall)
		OfferContracts(akBoard, hall)
		OfferEmergency(akBoard, hall)
	EndIf
	Debug.Trace("[AoT-F9] board done " + akBoard + " offered=" + _nOffered + " failed=" + _nFailed + " items=" + akBoard.GetNumItems())
EndFunction

Bool Function InList(Quest[] akList, Int aiCount, Quest akQuest)
	Int i = 0
	While i < aiCount
		If akList[i] == akQuest
			Return True
		EndIf
		i += 1
	EndWhile
	Return False
EndFunction

Function MarkOffered(Quest akQuest)
	If _nOffered < _offered.Length && !InList(_offered, _nOffered, akQuest)
		_offered[_nOffered] = akQuest
		_nOffered += 1
	EndIf
EndFunction

Function MarkFailed(Quest akQuest)
	If _nFailed < _failed.Length && !InList(_failed, _nFailed, akQuest)
		_failed[_nFailed] = akQuest
		_nFailed += 1
	EndIf
EndFunction

Bool Function SkipThisRefresh(Quest akQuest)
	Return InList(_offered, _nOffered, akQuest) || InList(_failed, _nFailed, akQuest) || InList(_retired, _nRetired, akQuest)
EndFunction

; ---------------------------------------------------------------- pools

Bool Function ResolveMissives(Int aiHall = -1)
	{True when the Missives lists and the Fase 7 adapter are there; Missives quests are tracked
	by that adapter, so without it they are not offered. Fase 10 Emenda 3 (D048): with a hall
	index (each refresh), the four lists of the hold of that hall are loaded from contracts.json
	(aot_miss_flst: four ids of Missives.esp per hall, Low to VeryHigh; a hold without the list of
	a band has the Whiterun one in the data). Without a hall, the lists already loaded stay, or
	the default ones (aot_miss_flst_default) when none is.}
	If !Game.IsPluginInstalled("Missives.esp") || !Game.IsPluginInstalled("AdventurersOfTamriel_Missives.esp")
		Return False
	EndIf
	If aiHall < 0 && MissLow
		Return True
	EndIf
	String path = AoT_ContractsCtl.ContractsPath()
	String listKey = "aot_miss_flst"
	Int base = aiHall * 4
	If aiHall < 0 || JsonUtil.IntListCount(path, listKey) < base + 4
		listKey = "aot_miss_flst_default"
		base = 0
	EndIf
	If JsonUtil.IntListCount(path, listKey) < base + 4
		Debug.Trace("[AoT-F10] no Missives lists in " + path + " (" + listKey + ")")
		MissLow = None
		MissMed = None
		MissHigh = None
		MissVeryHigh = None
		Return False
	EndIf
	MissLow = Game.GetFormFromFile(JsonUtil.IntListGet(path, listKey, base), "Missives.esp") as FormList
	MissMed = Game.GetFormFromFile(JsonUtil.IntListGet(path, listKey, base + 1), "Missives.esp") as FormList
	MissHigh = Game.GetFormFromFile(JsonUtil.IntListGet(path, listKey, base + 2), "Missives.esp") as FormList
	MissVeryHigh = Game.GetFormFromFile(JsonUtil.IntListGet(path, listKey, base + 3), "Missives.esp") as FormList
	Debug.Trace("[AoT-F10] missives lists hall=" + aiHall + " " + listKey + " " + MissLow + " " + MissMed + " " + MissHigh + " " + MissVeryHigh)
	Return MissLow != None
EndFunction

Function LoadMissSkip()
	{D-27 on the board (D047): the Missives quests listed in contracts.json (aot_miss_skip_ids of
	aot_miss_skip_plugin, the GatherOre of the VeryHigh lists) are never drawn. No record of theirs
	is edited; a quest already offered before this list leaves by the normal cleanup.}
	_missSkip = new Quest[16]
	_nMissSkip = 0
	String path = AoT_ContractsCtl.ContractsPath()
	String plug = JsonUtil.GetStringValue(path, "aot_miss_skip_plugin", "")
	If plug == "" || !Game.IsPluginInstalled(plug)
		Return
	EndIf
	Int n = JsonUtil.IntListCount(path, "aot_miss_skip_ids")
	Int i = 0
	While i < n && _nMissSkip < _missSkip.Length
		Quest q = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_miss_skip_ids", i), plug) as Quest
		If q
			_missSkip[_nMissSkip] = q
			_nMissSkip += 1
		EndIf
		i += 1
	EndWhile
EndFunction

FormList Function OurList(Int aiBand)
	If aiBand == 0
		Return OurLow
	ElseIf aiBand == 1
		Return OurMed
	ElseIf aiBand == 2
		Return OurHigh
	ElseIf aiBand == 3
		Return OurVeryHigh
	ElseIf aiBand == 4 || aiBand == 5
		If !_ourA
			String path = AoT_ContractsCtl.ContractsPath()
			If JsonUtil.IntListCount(path, "aot_band_flst") > 5
				_ourA = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_band_flst", 4), "AdventurersOfTamriel.esp") as FormList
				_ourS = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_band_flst", 5), "AdventurersOfTamriel.esp") as FormList
			EndIf
		EndIf
		If aiBand == 4
			Return _ourA
		EndIf
		Return _ourS
	EndIf
	Return None
EndFunction

Bool Function BandFree(Int aiBand)
	{D047: no fee in the table (fee <= 0) opens the band without a payment (A and S today). A
	missing fee entry is a table error and keeps the band closed.}
	If aiBand <= 0
		Return True
	EndIf
	If JsonUtil.IntListCount(AoT_Core.TablePath(), "aot_fee_by_band") <= aiBand
		Return False
	EndIf
	Return AoT_Attendant.FeeForBand(aiBand) <= 0
EndFunction

Bool Function BandOpen(Int aiBand)
	{The paid gate of the draw: Low, paid, or free in the table; never a band that came back empty
	in this refresh.}
	If _bandDry[aiBand]
		Return False
	EndIf
	Return aiBand == 0 || AoT_Core.IsBandPaid(aiBand) || BandFree(aiBand)
EndFunction

FormList Function MissList(Int aiBand)
	If !ResolveMissives()
		Return None
	EndIf
	If aiBand == 0
		Return MissLow
	ElseIf aiBand == 1
		Return MissMed
	ElseIf aiBand == 2
		Return MissHigh
	ElseIf aiBand == 3
		Return MissVeryHigh
	EndIf
	Return None
EndFunction

Int Function Collect(FormList akList, Int aiHall, Quest[] akOut, Bool abAnyHoldFallback, ObjectReference akBoard = None)
	{Fills akOut with the first tier that has candidates, skipping what failed or was offered in
	this refresh (D042): 1 the free quests of this hall; with abAnyHoldFallback, 2 the untaken
	offers of this hall sitting on another board (akBoard given), 3 the free quests of every hall,
	4 the untaken offers of every hall on another board. _steal tells a tier 2 or 4 answer.}
	_steal = False
	Int n = 0
	If !akList
		Return 0
	EndIf
	Int size = akList.GetSize()
	Int tier = 1
	While tier <= 4 && n == 0
		Bool moving = tier == 2 || tier == 4
		If (tier == 1 || abAnyHoldFallback) && (!moving || akBoard)
			Int i = 0
			While i < size && n < akOut.Length
				AoT_Contract c = akList.GetAt(i) as AoT_Contract
				If c && (tier >= 3 || c.HoldIndex == aiHall) && !SkipThisRefresh(c as Quest)
					If moving
						If IsUntakenElsewhere(c, akBoard)
							akOut[n] = c as Quest
							n += 1
						EndIf
					ElseIf !c.IsRunning()
						akOut[n] = c as Quest
						n += 1
					EndIf
				EndIf
				i += 1
			EndWhile
			If n > 0 && moving
				_steal = True
			EndIf
		EndIf
		tier += 1
	EndWhile
	Return n
EndFunction

Bool Function IsUntakenElsewhere(AoT_Contract akC, ObjectReference akBoard)
	{An offer nobody took that sits on another board.}
	If !akC.IsRunning() || akC.GetStage() >= 20
		Return False
	EndIf
	ObjectReference other = StorageUtil.GetFormValue(akC as Quest, "aot_offer_board", None) as ObjectReference
	Return other && other != akBoard
EndFunction

Function RetireOwn(ObjectReference akBoard)
	{Yesterday's offers on this board that nobody took leave it.}
	Int k = 0
	While k < 8
		FormList L = None
		If k < 6
			L = OurList(k)
		ElseIf k == 6
			L = OurSituation
		Else
			L = OurEmergency
		EndIf
		If L
			Int size = L.GetSize()
			Int i = 0
			While i < size
				AoT_Contract c = L.GetAt(i) as AoT_Contract
				If c && c.IsRunning() && c.GetStage() < 20 && StorageUtil.GetFormValue(c as Quest, "aot_offer_board", None) == akBoard
					c.Retire()
				EndIf
				i += 1
			EndWhile
		EndIf
		k += 1
	EndWhile
EndFunction

ObjectReference Function MissOfferBoard(Quest akQuest)
	{The board of an open Missives offer (still in aot_missives_offer), None otherwise. The adapter
	drops the entry when the note is taken or the quest ends, so a stale board never answers.}
	If StorageUtil.FormListFind(None, "aot_missives_offer", akQuest) < 0
		Return None
	EndIf
	Return StorageUtil.GetFormValue(akQuest, "aot_offer_board", None) as ObjectReference
EndFunction

Function RetireMissive(Quest akQuest, ObjectReference akBoard)
	{Same cleanup as the Missives board: stage 110 removes the note and stops the quest. The quest
	leaves the offer list and is not offered again in this refresh.}
	akQuest.SetStage(110)
	StorageUtil.FormListRemove(None, "aot_missives_offer", akQuest, True)
	StorageUtil.UnsetFormValue(akQuest, "aot_offer_board")
	If _nRetired < _retired.Length && !InList(_retired, _nRetired, akQuest)
		_retired[_nRetired] = akQuest
		_nRetired += 1
	EndIf
	Debug.Trace("[AoT-F9] retired missive " + akQuest + " from " + akBoard)
EndFunction

Function RetireMissives(ObjectReference akBoard)
	{Conserto fase 9b (D043): the Missives quests this board offered that nobody took (running,
	stage 0, a note of theirs still in this board) leave it. A taken quest (stage 20), an offer of
	another board and an offer of this refresh are not touched. Back to front: entries leave.}
	Int i = StorageUtil.FormListCount(None, "aot_missives_offer") - 1
	While i >= 0
		Quest q = StorageUtil.FormListGet(None, "aot_missives_offer", i) as Quest
		If q && !SkipThisRefresh(q) && StorageUtil.GetFormValue(q, "aot_offer_board", None) == akBoard
			If q.IsRunning() && q.GetStage() == 0 && !q.IsStageDone(20)
				ObjectReference note = MissiveNote(q)
				If note && akBoard.GetItemCount(note.GetBaseObject()) >= 1
					RetireMissive(q, akBoard)
				EndIf
			EndIf
		EndIf
		i -= 1
	EndWhile
EndFunction

Bool Function TwinBusy(AoT_Contract akC)
	{Fase 10 (D047): two of our quests that fill the same places (an A or S contract and its
	Counterpart: the emergency call, or the common contract) are never offered together. Forward by
	the Counterpart property; backward by a scan of the A and S lists, because a quest of an older
	plugin keeps the property values of the save.}
	AoT_Contract twin = akC.Counterpart as AoT_Contract
	If twin && twin.IsRunning()
		Return True
	EndIf
	twin = akC.Counterpart2 as AoT_Contract
	If twin && twin.IsRunning()
		Return True
	EndIf
	twin = akC.Counterpart3 as AoT_Contract
	If twin && twin.IsRunning()
		Return True
	EndIf
	Quest self_q = akC as Quest
	Int b = 4
	While b <= 5
		FormList L = OurList(b)
		If L
			Int n = L.GetSize()
			Int i = 0
			While i < n
				AoT_Contract x = L.GetAt(i) as AoT_Contract
				If x && (x.Counterpart == self_q || x.Counterpart2 == self_q || x.Counterpart3 == self_q) && x.IsRunning()
					Return True
				EndIf
				i += 1
			EndWhile
		EndIf
		b += 1
	EndWhile
	Return False
EndFunction

Bool Function StartOwn(Quest akQuest, ObjectReference akBoard, String asWhy, Bool abAbove = False)
	{Fase 14 etapa 4 (D085): the one path of our offers (common, situation, emergency) also writes the band label on the
	note; abAbove adds the [Above Rank] mark after it.}
	AoT_Contract c = akQuest as AoT_Contract
	If !c
		Return False
	EndIf
	If TwinBusy(c)
		Debug.Trace("[AoT-F10] not offered " + akQuest + ": its counterpart runs")
		MarkFailed(akQuest)
		Return False
	EndIf
	StorageUtil.SetFormValue(akQuest, "aot_offer_board", akBoard)
	If !akQuest.Start()
		Debug.Trace("[AoT-F9] start failed " + akQuest + " (" + asWhy + ")")
		MarkFailed(akQuest)
		Return False
	EndIf
	ObjectReference note = c.NoteRef()
	If !c.IsOfferable() || akBoard.GetItemCount(note.GetBaseObject()) < 1
		Debug.Trace("[AoT-F9] not offerable " + akQuest + " dungeon=" + c.DungeonLocation() + " target=" + c.TargetActor() + " note=" + note)
		c.Retire()
		MarkFailed(akQuest)
		Return False
	EndIf
	MarkOffered(akQuest)
	LabelNote(akQuest, note, c.Band, abAbove)
	Debug.Trace("[AoT-F9] offer " + akQuest + " " + asWhy + " band=" + c.Band + " hold=" + c.HoldIndex + " dungeon=" + c.DungeonLocation() + " target=" + c.TargetActor())
	Return True
EndFunction

; ---------------------------------------------------------------- normal offers

Function OfferContracts(ObjectReference akBoard, Int aiHall)
	Int rank = AoT_Core.GetRank()
	Int offers = AoT_Core.BoardOffers()
	Int started = 0
	Int attempts = 0
	Int aboveOne = 0
	Int aboveTwo = 0
	While started < offers && attempts < 30
		attempts += 1
		Int band = -1
		Int aboveKind = 0
		If aboveOne < 2 && rank < AoT_Core.MaxRank()
			band = DrawBandAbove(rank, 1)
			If band >= 0
				aboveKind = 1
			EndIf
		EndIf
		If band < 0 && aboveTwo < 1 && rank + 1 < AoT_Core.MaxRank()
			band = DrawBandAbove(rank, 2)
			If band >= 0
				aboveKind = 2
			EndIf
		EndIf
		If band < 0
			band = DrawBand(rank)
		EndIf
		If band < 0
			Return
		EndIf
		Quest q = PickFromBand(band, akBoard, aiHall, aboveKind > 0)
		If q
			If aboveKind > 0
				If aboveKind == 1
					aboveOne += 1
				Else
					aboveTwo += 1
				EndIf
			EndIf
			started += 1
		Else
			Debug.Trace("[AoT-F10] band " + band + " empty in this refresh, out of the draw")
			_bandDry[band] = True
			If aboveKind == 1
				aboveOne += 1
			ElseIf aboveKind == 2
				aboveTwo += 1
			EndIf
		EndIf
	EndWhile
EndFunction

Quest Function PickFromBand(Int aiBand, ObjectReference akBoard, Int aiHall, Bool abAbove = False)
	{One of our candidates of the hold (Collect tiers). A quest that fails to start leaves the refresh
	and the draw goes again (D042); None only when no candidate is left. Fase 14 etapa 2: the Missives
	quests are no longer drawn here; OfferMissives puts them all on the board.}
	Quest[] cand = new Quest[64]
	Int guard = 0
	While guard < 64
		guard += 1
		Int nOurs = Collect(OurList(aiBand), aiHall, cand, True, akBoard)
		Bool steal = _steal
		If nOurs == 0
			Return None
		EndIf
		Int roll = Utility.RandomInt(0, nOurs - 1)
		AoT_Contract c = cand[roll] as AoT_Contract
		Bool ready = True
		If steal
			Debug.Trace("[AoT-F9] moving offer " + c + " from " + StorageUtil.GetFormValue(c as Quest, "aot_offer_board", None) + " to " + akBoard)
			c.Retire()
			ready = c.WaitStopped()
		EndIf
		If ready && StartOwn(cand[roll], akBoard, "pool=ours", abAbove)
			Return cand[roll]
		EndIf
		MarkFailed(cand[roll])
	EndWhile
	Return None
EndFunction

; ---------------------------------------------------------------- Missives offers

Function OfferMissives(ObjectReference akBoard, Int aiHall)
	{Fase 14 etapa 2 (R2-9, C3b): with the town board gone, the hall board shows every quest of the Missives lists of
	its hold, in every band the rank draws (weight above 0) and that is open (Low, paid or free), outside the
	aot_board_offers count of our contracts. A band of the next rank, open but not drawn at this rank, gives at most
	two quests marked [Above Rank], and one of two ranks up gives one (D005). MISS_CAP bounds one refresh, logged.}
	Int MISS_CAP = 40
	If !ResolveMissives()
		Return
	EndIf
	Int rank = AoT_Core.GetRank()
	Int total = 0
	Int b = 0
	While b <= 3
		If BandOpen(b)
			Int quota = -1
			String note = ""
			If AoT_Core.BandWeight(rank, b) <= 0
				quota = 0
				If rank < AoT_Core.MaxRank() && AoT_Core.BandWeight(rank + 1, b) > 0
					quota = 2
				ElseIf rank + 1 < AoT_Core.MaxRank() && AoT_Core.BandWeight(rank + 2, b) > 0
					quota = 1
				EndIf
				note = " [Above Rank]"
			EndIf
			If quota != 0
				Int got = OfferMissivesBand(b, akBoard, quota, note, MISS_CAP - total)
				total += got
				Debug.Trace("[AoT-F14] missives band " + b + " hall=" + aiHall + " offered=" + got + " quota=" + quota)
			EndIf
		EndIf
		b += 1
	EndWhile
	If total >= MISS_CAP
		Debug.Trace("[AoT-F14] missives cap " + MISS_CAP + " reached on " + akBoard + ": the rest of the lists waits for the next refresh")
	EndIf
EndFunction

Int Function OfferMissivesBand(Int aiBand, ObjectReference akBoard, Int aiQuota, String asNote, Int aiRoom)
	{Every startable quest of the band's list, in list order, up to aiQuota (-1 = all) and aiRoom. A quest offered or
	failed in this refresh, or in the skip list, is passed over; a running stage 0 offer of this board or of no board
	is cleaned up (as the Fase 8 board did) and waits for the next refresh.}
	FormList L = MissList(aiBand)
	If !L
		Return 0
	EndIf
	AoT_MissivesAdapter adapter = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_Missives.esp") as AoT_MissivesAdapter
	Int n = L.GetSize()
	Int got = 0
	Int i = 0
	While i < n && got < aiRoom && (aiQuota < 0 || got < aiQuota)
		Quest q = L.GetAt(i) as Quest
		Int how = 0
		If q
			how = TryStartMissive(q, akBoard)
		EndIf
		If how > 0
			String kept = ""
			If how == 2
				kept = " kept"
			EndIf
			; D085: new or kept, the note is labelled again (the label is rebuilt from the plain name, so a kept note
			; loses an [Above Rank] mark its band no longer earns, as FixAboveRankNote did, D083)
			LabelNote(q, MissiveNote(q), aiBand, asNote != "")
			If adapter
				adapter.RegisterOffer(q, aiBand)
			EndIf
			Debug.Trace("[AoT-F9] offer " + q + " pool=missives band=" + aiBand + asNote + kept)
			got += 1
		EndIf
		i += 1
	EndWhile
	Return got
EndFunction

Int Function TryStartMissive(Quest akQuest, ObjectReference akBoard)
	{One Missives quest: 1 when it starts with its note in this board, 2 when it already ran as an untaken offer with its
	note in this board and stays (conserto 1 da etapa 2, D083: the board shows every quest of its bands, so a refresh
	in the same day no longer takes them away), 0 otherwise.}
	If SkipThisRefresh(akQuest) || InList(_missSkip, _nMissSkip, akQuest)
		Return 0
	EndIf
	If akQuest.IsRunning()
		ObjectReference owner = MissOfferBoard(akQuest)
		If akQuest.GetStage() != 0 || (owner && owner != akBoard)
			Return 0
		EndIf
		ObjectReference held = MissiveNote(akQuest)
		If held && akBoard.GetItemCount(held.GetBaseObject()) >= 1
			StorageUtil.SetFormValue(akQuest, "aot_offer_board", akBoard)
			MarkOffered(akQuest)
			Return 2
		EndIf
		RetireMissive(akQuest, akBoard)
		Return 0
	EndIf
	If !akQuest.Start()
		Debug.Trace("[AoT-F14] missives start failed " + akQuest + " formid=" + akQuest.GetFormID())
		MarkFailed(akQuest)
		Return 0
	EndIf
	ObjectReference note = MissiveNote(akQuest)
	If akQuest.IsRunning() && note && akBoard.GetItemCount(note.GetBaseObject()) >= 1
		StorageUtil.SetFormValue(akQuest, "aot_offer_board", akBoard)
		MarkOffered(akQuest)
		Return 1
	EndIf
	Debug.Trace("[AoT-F9] missives not offerable " + akQuest + " formid=" + akQuest.GetFormID() + " running=" + akQuest.IsRunning() + " note=" + note)
	If akQuest.IsRunning()
		akQuest.SetStage(110)
	EndIf
	MarkFailed(akQuest)
	Return 0
EndFunction

Function LabelNote(Quest akQuest, ObjectReference akNote, Int aiBand, Bool abAbove)
	{Fase 14 etapa 4 (D085, D084): every board note, ours and of Missives, carries its band, " [Band F]" to " [Band A]"
	(band 0 to 5), and " [Above Rank]" after it when the band is above the rank (D005). The name is first cut back to its
	plain part, so a note labelled before (a kept Missives offer, D083) ends with one label, and loses an [Above Rank]
	mark its band no longer earns. One log line per labelled note, for the test to read the name without the menu.}
	If !akNote || aiBand < 0 || aiBand > AoT_Core.MaxBand()
		Debug.Trace("[AoT-F14] note label skipped q=" + akQuest + " band=" + aiBand + " note=" + akNote)
		Return
	EndIf
	String nm = akNote.GetDisplayName()
	Int cut = StringUtil.Find(nm, " [Band ")
	Int at = StringUtil.Find(nm, " [Above Rank]")
	If at >= 0 && (cut < 0 || at < cut)
		cut = at
	EndIf
	If cut > 0
		nm = StringUtil.Substring(nm, 0, cut)
	EndIf
	String newName = nm + " [Band " + StringUtil.Substring("FEDCBA", aiBand, 1) + "]"
	If abAbove
		newName += " [Above Rank]"
	EndIf
	If !akNote.SetDisplayName(newName, True)
		Debug.Trace("[AoT-F14] note label SetDisplayName failed q=" + akQuest + " note=" + akNote)
	EndIf
	Debug.Trace("[AoT-F14] note label q=" + akQuest + " band=" + aiBand + " name=" + akNote.GetDisplayName())
EndFunction

Int Function DrawBand(Int aiRank)
	Int total = 0
	Int b = 0
	While b <= AoT_Core.MaxBand()
		If BandOpen(b)
			Int w = AoT_Core.BandWeight(aiRank, b)
			If w > 0
				total += w
			EndIf
		EndIf
		b += 1
	EndWhile
	If total <= 0
		Return -1
	EndIf
	Int roll = Utility.RandomInt(1, total)
	Int acc = 0
	b = 0
	While b <= AoT_Core.MaxBand()
		If BandOpen(b)
			Int w2 = AoT_Core.BandWeight(aiRank, b)
			If w2 > 0
				acc += w2
				If roll <= acc
					Return b
				EndIf
			EndIf
		EndIf
		b += 1
	EndWhile
	Return -1
EndFunction

Int Function DrawBandAbove(Int aiRank, Int aiOffset)
	{A band that exists at rank + aiOffset and NOT at the rank right below it, weighted by its
	weight at rank + aiOffset (D005).}
	Int targetRank = aiRank + aiOffset
	If targetRank > AoT_Core.MaxRank()
		Return -1
	EndIf
	Int baseRank = targetRank - 1
	Int total = 0
	Int b = 0
	While b <= AoT_Core.MaxBand()
		If BandOpen(b)
			If AoT_Core.BandWeight(baseRank, b) == 0 && AoT_Core.BandWeight(targetRank, b) > 0
				total += AoT_Core.BandWeight(targetRank, b)
			EndIf
		EndIf
		b += 1
	EndWhile
	If total <= 0
		Return -1
	EndIf
	Int roll = Utility.RandomInt(1, total)
	Int acc = 0
	b = 0
	While b <= AoT_Core.MaxBand()
		If BandOpen(b)
			If AoT_Core.BandWeight(baseRank, b) == 0 && AoT_Core.BandWeight(targetRank, b) > 0
				acc += AoT_Core.BandWeight(targetRank, b)
				If roll <= acc
					Return b
				EndIf
			EndIf
		EndIf
		b += 1
	EndWhile
	Return -1
EndFunction

; ---------------------------------------------------------------- test surface (D083)

Quest Function TestTakeNote(Int aiKind)
	{Test surface, conserto 1 da etapa 2 (D083), reached by AoT_Attendant.RunAction(30, kind): takes the note of the first
	untaken offer on this board to the player, by the alias ref itself (the same move as taking it from the container,
	so the note alias gets OnContainerChanged). Kind 0: an offer of ours; 1: a Missives offer; 2: a Missives offer whose
	quest has a "Steward" alias (the report path). Logs whether the engine calls the held ref deleted.}
	ObjectReference board = GetReference()
	Actor player = Game.GetPlayer()
	Quest q = None
	ObjectReference note = None
	If board && aiKind == 0
		Int k = 0
		While k < 8 && !q
			FormList L = None
			If k < 6
				L = OurList(k)
			ElseIf k == 6
				L = OurSituation
			Else
				L = OurEmergency
			EndIf
			If L
				Int i = 0
				While i < L.GetSize() && !q
					AoT_Contract c = L.GetAt(i) as AoT_Contract
					If c && c.IsRunning() && c.GetStage() < 20 && StorageUtil.GetFormValue(c as Quest, "aot_offer_board", None) == board
						q = c as Quest
						note = c.NoteRef()
					EndIf
					i += 1
				EndWhile
			EndIf
			k += 1
		EndWhile
	ElseIf board && (aiKind == 1 || aiKind == 2)
		Int j = 0
		Int n = StorageUtil.FormListCount(None, "aot_missives_offer")
		While j < n && !q
			Quest m = StorageUtil.FormListGet(None, "aot_missives_offer", j) as Quest
			If m && m.IsRunning() && m.GetStage() == 0 && StorageUtil.GetFormValue(m, "aot_offer_board", None) == board
				If aiKind == 1 || m.GetAliasByName("Steward")
					q = m
					note = MissiveNote(m)
				EndIf
			EndIf
			j += 1
		EndWhile
	EndIf
	If !q || !note
		Debug.Trace("[AoT-F14] test take note kind=" + aiKind + " board=" + board + ": no offer (q=" + q + " note=" + note + ")")
		Return None
	EndIf
	Form nb = note.GetBaseObject()
	Int before = player.GetItemCount(nb)
	Bool del = note.IsDeleted()
	Int onBoard = board.GetItemCount(nb)
	board.RemoveItem(note, 1, True, player)
	Utility.Wait(0.5)
	Debug.Trace("[AoT-F14] test take note kind=" + aiKind + " q=" + q + " formid=" + q.GetFormID() + " note=" + note + " deleted=" + del + " on_board=" + onBoard + " player " + before + " -> " + player.GetItemCount(nb) + " stage=" + q.GetStage())
	Return q
EndFunction

ObjectReference Function MissiveNote(Quest akQuest)
	ReferenceAlias ali = akQuest.GetAliasByName("Missive") as ReferenceAlias
	If ali
		Return ali.GetReference()
	EndIf
	Return None
EndFunction

; ---------------------------------------------------------------- situation and emergency

Bool Function EventIsOn(Int aiEvent)
	{The world event of a situation contract (contracts.json aot_sit_*); aot_sit_force = 1 turns
	every event on, for the test.}
	If StorageUtil.GetIntValue(None, "aot_sit_force", 0) == 1
		Return True
	EndIf
	String path = AoT_ContractsCtl.ContractsPath()
	If aiEvent < 0 || aiEvent >= JsonUtil.IntListCount(path, "aot_sit_quest")
		Return False
	EndIf
	String plug = JsonUtil.StringListGet(path, "aot_sit_plugin", aiEvent)
	If !Game.IsPluginInstalled(plug)
		Return False
	EndIf
	Quest q = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_sit_quest", aiEvent), plug) as Quest
	Return q && q.IsCompleted()
EndFunction

Function OfferSituation(ObjectReference akBoard, Int aiHall)
	{One situation contract of this hold when its event is on and its band is open to the rank.
	It runs before the common offers, and the untaken offer of its common counterpart (same places,
	any board) leaves first (D042); a counterpart already taken keeps the place.}
	If !OurSituation
		Return
	EndIf
	Int rank = AoT_Core.GetRank()
	Int size = OurSituation.GetSize()
	Int i = 0
	While i < size
		AoT_Contract c = OurSituation.GetAt(i) as AoT_Contract
		If c && c.HoldIndex == aiHall
			If c.IsRunning()
				Return
			EndIf
			If !EventIsOn(c.EventIndex)
				Return
			EndIf
			If !(c.Band == 0 || AoT_Core.IsBandPaid(c.Band) || BandFree(c.Band)) || AoT_Core.BandWeight(rank, c.Band) <= 0
				Debug.Trace("[AoT-F9] situation " + c + " skipped: band " + c.Band + " closed at rank " + rank)
				Return
			EndIf
			AoT_Contract twin = c.Counterpart as AoT_Contract
			If twin && twin.IsRunning()
				If twin.GetStage() >= 20
					Debug.Trace("[AoT-F9] situation " + c + " skipped: counterpart " + twin + " taken")
					Return
				EndIf
				Debug.Trace("[AoT-F9] situation " + c + " retires counterpart " + twin)
				twin.Retire()
				twin.WaitStopped()
			EndIf
			StartOwn(c as Quest, akBoard, "situation event=" + c.EventIndex)
			Return
		EndIf
		i += 1
	EndWhile
EndFunction

Function OfferEmergency(ObjectReference akBoard, Int aiHall)
	{The A to S call: only when the points enable the promotion and the cut asks for the call.}
	Int rank = AoT_Core.GetRank()
	If !AoT_Core.IsPromotionEligible() || AoT_Core.ExamKind(rank) != 2
		Return
	EndIf
	If StorageUtil.GetIntValue(None, "aot_emg_state", 0) == 1
		Return
	EndIf
	Quest[] cand = new Quest[64]
	Int n = Collect(OurEmergency, aiHall, cand, True)
	Int tries = 4
	While n > 0 && tries > 0
		tries -= 1
		Int idx = Utility.RandomInt(0, n - 1)
		If StartOwn(cand[idx], akBoard, "emergency")
			Return
		EndIf
		n -= 1
		cand[idx] = cand[n]
	EndWhile
EndFunction