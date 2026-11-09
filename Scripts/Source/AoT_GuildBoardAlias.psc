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
Bool[] _missDry
Bool[] _bandDry
Quest[] _missSkip
Int _nMissSkip = 0
Quest[] _retired
Int _nRetired = 0
Bool _steal = False

Event OnActivate(ObjectReference akActionRef)
	Actor pl = Game.GetPlayer()
	If akActionRef != pl
		Return
	EndIf
	ObjectReference board = GetReference()
	If !board
		Return
	EndIf
	If !_busy
		_busy = True
		Refresh(board)
		_busy = False
	EndIf
	board.Activate(pl, True)
EndEvent

Function Refresh(ObjectReference akBoard)
	AoT_Emergency.Heal()
	AoT_ContractsCtl ctl = GetOwningQuest() as AoT_ContractsCtl
	If ctl
		ctl.EnsureForbidden()
	EndIf
	Float now = Utility.GetCurrentGameTime()
	If StorageUtil.GetIntValue(None, "aot_board_nogate", 0) != 1
		If now < StorageUtil.GetFloatValue(akBoard, "aot_board_day", -100.0) + 1.0
			Return
		EndIf
	EndIf
	StorageUtil.SetFloatValue(akBoard, "aot_board_day", now)
	Int hall = AoT_Exam.HallIndexOfPlayer()
	Debug.Trace("[AoT-F9] board refresh " + akBoard + " hall=" + hall + " rank=" + AoT_Core.GetRank() + " missives=" + ResolveMissives(hall))
	_offered = new Quest[64]
	_nOffered = 0
	_failed = new Quest[64]
	_nFailed = 0
	_missDry = new Bool[6]
	_bandDry = new Bool[6]
	_retired = new Quest[64]
	_nRetired = 0
	LoadMissSkip()
	RetireOwn(akBoard)
	RetireMissives(akBoard)
	OfferSituation(akBoard, hall)
	OfferContracts(akBoard, hall)
	OfferEmergency(akBoard, hall)
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

Bool Function StartOwn(Quest akQuest, ObjectReference akBoard, String asWhy)
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
	Debug.Trace("[AoT-F9] offer " + akQuest + " " + asWhy + " band=" + c.Band + " hold=" + c.HoldIndex + " dungeon=" + c.DungeonLocation() + " target=" + c.TargetActor())
	Return True
EndFunction

; ---------------------------------------------------------------- normal offers

Function OfferContracts(ObjectReference akBoard, Int aiHall)
	Int rank = AoT_Core.GetRank()
	Int offers = JsonUtil.GetIntValue(AoT_ContractsCtl.ContractsPath(), "aot_board_offers", 5)
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
		Quest q = PickFromBand(band, akBoard, aiHall)
		If q
			If aboveKind > 0
				SetAboveRankNote(q, " [Above Rank]")
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

Quest Function PickFromBand(Int aiBand, ObjectReference akBoard, Int aiHall)
	{One item, one chance: our candidates of the hold (Collect tiers) and the Missives list of the
	band. A quest that fails to start leaves the refresh and the draw goes again (D042); None only
	when no candidate is left.}
	Quest[] cand = new Quest[64]
	FormList miss = MissList(aiBand)
	Int guard = 0
	While guard < 64
		guard += 1
		Int nOurs = Collect(OurList(aiBand), aiHall, cand, True, akBoard)
		Bool steal = _steal
		Int nMiss = 0
		If miss && !_missDry[aiBand]
			nMiss = miss.GetSize()
		EndIf
		If nOurs + nMiss == 0
			Return None
		EndIf
		Int roll = Utility.RandomInt(0, nOurs + nMiss - 1)
		If roll < nOurs
			AoT_Contract c = cand[roll] as AoT_Contract
			Bool ready = True
			If steal
				Debug.Trace("[AoT-F9] moving offer " + c + " from " + StorageUtil.GetFormValue(c as Quest, "aot_offer_board", None) + " to " + akBoard)
				c.Retire()
				ready = c.WaitStopped()
			EndIf
			If ready && StartOwn(cand[roll], akBoard, "pool=ours")
				Return cand[roll]
			EndIf
			MarkFailed(cand[roll])
		Else
			Quest qm = PickStartableFromFLST(miss, akBoard)
			If qm
				AoT_MissivesAdapter adapter = Game.GetFormFromFile(0x000800, "AdventurersOfTamriel_Missives.esp") as AoT_MissivesAdapter
				If adapter
					adapter.RegisterOffer(qm, aiBand)
				EndIf
				Debug.Trace("[AoT-F9] offer " + qm + " pool=missives band=" + aiBand)
				Return qm
			EndIf
			_missDry[aiBand] = True
		EndIf
	EndWhile
	Return None
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

Quest Function PickStartableFromFLST(FormList akFLST, ObjectReference akBoard)
	{Missives side, as in the Fase 8 board: a running quest still at stage 0 from an earlier refresh
	is cleaned up (110). D042: a quest offered or failed in this refresh is skipped, never cleaned
	up, and the offer counts only with the quest running and its note in the board.}
	Int n = akFLST.GetSize()
	If n == 0
		Return None
	EndIf
	Int tries = 8
	While tries > 0
		tries -= 1
		Quest q = akFLST.GetAt(Utility.RandomInt(0, n - 1)) as Quest
		If q && !SkipThisRefresh(q) && !InList(_missSkip, _nMissSkip, q)
			If q.IsRunning()
				ObjectReference owner = MissOfferBoard(q)
				If q.GetStage() == 0 && (!owner || owner == akBoard)
					RetireMissive(q, akBoard)
				EndIf
			ElseIf q.Start()
				ObjectReference note = MissiveNote(q)
				If q.IsRunning() && note && akBoard.GetItemCount(note.GetBaseObject()) >= 1
					StorageUtil.SetFormValue(q, "aot_offer_board", akBoard)
					MarkOffered(q)
					Return q
				EndIf
				Debug.Trace("[AoT-F9] missives not offerable " + q + " running=" + q.IsRunning() + " note=" + note)
				If q.IsRunning()
					q.SetStage(110)
				EndIf
				MarkFailed(q)
			Else
				MarkFailed(q)
			EndIf
		EndIf
	EndWhile
	Return None
EndFunction

ObjectReference Function MissiveNote(Quest akQuest)
	ReferenceAlias ali = akQuest.GetAliasByName("Missive") as ReferenceAlias
	If ali
		Return ali.GetReference()
	EndIf
	Return None
EndFunction

Function SetAboveRankNote(Quest akQuest, String asNote)
	ReferenceAlias ali = akQuest.GetAliasByName("Missive") as ReferenceAlias
	If !ali
		ali = akQuest.GetNthAlias(6) as ReferenceAlias
	EndIf
	If ali && ali.GetReference()
		ObjectReference note = ali.GetReference()
		String newName = note.GetDisplayName() + asNote
		Bool ok = note.SetDisplayName(newName, True)
		Debug.Trace("[AoT-F9] note " + akQuest + " -> " + newName + " ok=" + ok)
	EndIf
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