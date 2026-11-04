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
offered at most once per refresh and the stale cleanup never stops one offered in this refresh.}

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
Bool _busy = False

; per refresh (D042): what was offered and what failed to start, our side and Missives side
Quest[] _offered
Int _nOffered = 0
Quest[] _failed
Int _nFailed = 0
Bool[] _missDry
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
	Debug.Trace("[AoT-F9] board refresh " + akBoard + " hall=" + hall + " rank=" + AoT_Core.GetRank() + " missives=" + ResolveMissives())
	_offered = new Quest[64]
	_nOffered = 0
	_failed = new Quest[64]
	_nFailed = 0
	_missDry = new Bool[4]
	RetireOwn(akBoard)
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
	Return InList(_offered, _nOffered, akQuest) || InList(_failed, _nFailed, akQuest)
EndFunction

; ---------------------------------------------------------------- pools

Bool Function ResolveMissives()
	{True when the Missives lists and the Fase 7 adapter are there; Missives quests are tracked
	by that adapter, so without it they are not offered.}
	If !Game.IsPluginInstalled("Missives.esp") || !Game.IsPluginInstalled("AdventurersOfTamriel_Missives.esp")
		Return False
	EndIf
	If !MissLow
		MissLow = Game.GetFormFromFile(0x001D8F, "Missives.esp") as FormList
		MissMed = Game.GetFormFromFile(0x001D90, "Missives.esp") as FormList
		MissHigh = Game.GetFormFromFile(0x001D92, "Missives.esp") as FormList
		MissVeryHigh = Game.GetFormFromFile(0x009451, "Missives.esp") as FormList
	EndIf
	Return MissLow != None
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
	EndIf
	Return None
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
	While k < 6
		FormList L = None
		If k < 4
			L = OurList(k)
		ElseIf k == 4
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

Bool Function StartOwn(Quest akQuest, ObjectReference akBoard, String asWhy)
	AoT_Contract c = akQuest as AoT_Contract
	If !c
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
		ElseIf aboveKind == 1
			aboveOne += 1
		ElseIf aboveKind == 2
			aboveTwo += 1
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
	While b <= 3
		If AoT_Core.IsBandPaid(b) || b == 0
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
	While b <= 3
		If AoT_Core.IsBandPaid(b) || b == 0
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
	While b <= 3
		If AoT_Core.IsBandPaid(b) || b == 0
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
	While b <= 3
		If AoT_Core.IsBandPaid(b) || b == 0
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
		If q && !SkipThisRefresh(q)
			If q.IsRunning()
				If q.GetStage() == 0
					q.SetStage(110)
				EndIf
			ElseIf q.Start()
				ObjectReference note = MissiveNote(q)
				If q.IsRunning() && note && akBoard.GetItemCount(note.GetBaseObject()) >= 1
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
			If !(AoT_Core.IsBandPaid(c.Band) || c.Band == 0) || AoT_Core.BandWeight(rank, c.Band) <= 0
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