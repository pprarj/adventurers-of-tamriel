Scriptname AoT_Hall
{Places the guild board in the hall the player stands in and watches the examiner and the attendant, ACHR of the
hall's plugin since Fase 16 etapa 10 (Fase 8, D035, D037, D117).
Same shape as AoT_Attendant.EnsureAttendant: the hall is found by the table of halls, the spot is a
persistent marker of the cloned hall (BoardSpot index 2, ExaminerSpot index 4 of the hall row), the base
is looked up by form file, the ref is kept under an aot_ StorageUtil refKey per hold. No cell override.}

Function _Ensure(Int aiHall, Int aiSpotIdx, String asKeyBase, String asPlugin, Int aiBaseId) Global
	String path = AoT_Attendant.HallsPath()
	String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + aiHall, "")
	If plug == "" || !Game.IsPluginInstalled(plug) || !Game.IsPluginInstalled(asPlugin)
		Return
	EndIf
	String hold = JsonUtil.StringListGet(path, "aot_hall_holds", aiHall)
	String refKey = asKeyBase + hold
	Cell hall = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 0), plug) as Cell
	ObjectReference cur = StorageUtil.GetFormValue(None, refKey, None) as ObjectReference
	If cur && cur.GetParentCell() == hall
		Actor ca = cur as Actor
		If !ca || !ca.IsDead()
			Return
		EndIf
	EndIf
	ObjectReference spot = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, aiSpotIdx), plug) as ObjectReference
	Form base = Game.GetFormFromFile(aiBaseId, asPlugin)
	If base && hall
		; Fase 13 etapa 6: before placing, adopt a ref of this base already in the hall (one per hall, no duplicate after a reload)
		Int nAll = hall.GetNumRefs(0)
		Int q = 0
		ObjectReference keep = None
		While q < nAll
			ObjectReference rr = hall.GetNthRef(q, 0)
			If rr && rr.GetBaseObject() == base
				Actor ra = rr as Actor
				If !keep && (!ra || !ra.IsDead())
					keep = rr
				ElseIf rr != keep
					rr.Disable()
					rr.Delete()
				EndIf
			EndIf
			q += 1
		EndWhile
		If keep
			StorageUtil.SetFormValue(None, refKey, keep)
			Return
		EndIf
	EndIf
	If !spot || !base
		Debug.Trace("[AoT] Hall: spot or base missing for " + refKey)
		Return
	EndIf
	If !spot.Is3DLoaded()
		Return
	EndIf
	ObjectReference r = spot.PlaceAtMe(base, 1, True, False)
	If r
		StorageUtil.SetFormValue(None, refKey, r)
		Debug.Trace("[AoT] Hall: placed " + refKey + " " + r + " spot=" + spot.GetPositionX() + "," + spot.GetPositionY() + "," + spot.GetPositionZ() + " ref=" + r.GetPositionX() + "," + r.GetPositionY() + "," + r.GetPositionZ() + " cellOk=" + (r.GetParentCell() == hall))
	EndIf
EndFunction

Function ExcludeFromRealNames() Global
	{Fase 16 etapa 12 (D121): Real Names - Extended renames every actor whose base is not Unique, unless the base is in its
	own list RealNamesNonUniqueNoRename (RealNamesChange.ChangeName). The attendant and the examiner lost the Unique flag
	in etapa 10 (nine refs per base), so the two bases are added to that list. No master and no file of the other mod:
	the list is looked up by form file and only when the plugin is installed; the addition stays in the save and is made
	again, if missing, at every load. Without the other mod nothing happens.}
	If !Game.IsPluginInstalled("RealNamesExtended.esp") || !Game.IsPluginInstalled("AdventurersOfTamriel.esp")
		Return
	EndIf
	; Fase 16 etapa 9 (D131): one call at a time. The load event of the MCM and the attendant tick can both arrive here
	; in the same second; both read HasForm = False and both add. AdjustIntValue is a single native call, so only the
	; first caller sees 1. A lock left behind by a save made inside the section (time from another session, or older
	; than 30 s) is taken over.
	Float now = Utility.GetCurrentRealTime()
	If StorageUtil.AdjustIntValue(None, "AoT_RneLock", 1) != 1
		Float t = StorageUtil.GetFloatValue(None, "AoT_RneLockT", 0.0)
		If t <= now && now - t < 30.0
			StorageUtil.AdjustIntValue(None, "AoT_RneLock", -1)
			Return
		EndIf
		StorageUtil.SetIntValue(None, "AoT_RneLock", 1)
	EndIf
	StorageUtil.SetFloatValue(None, "AoT_RneLockT", now)
	_ExcludeFromRealNamesLocked()
	StorageUtil.SetIntValue(None, "AoT_RneLock", 0)
EndFunction

Function _ExcludeFromRealNamesLocked() Global
	{Body of ExcludeFromRealNames, run under its lock.}
	FormList lst = Game.GetFormFromFile(0x000CD7, "RealNamesExtended.esp") as FormList
	If !lst
		Debug.Trace("[AoT] Real Names: list RealNamesNonUniqueNoRename not found")
		Return
	EndIf
	Form att = Game.GetFormFromFile(0x000D99, "AdventurersOfTamriel.esp")
	Form exm = Game.GetFormFromFile(0x000E2E, "AdventurersOfTamriel.esp")
	If att && !lst.HasForm(att)
		lst.AddForm(att)
		Debug.Trace("[AoT] Real Names: attendant base added to RealNamesNonUniqueNoRename")
	EndIf
	If exm && !lst.HasForm(exm)
		lst.AddForm(exm)
		Debug.Trace("[AoT] Real Names: examiner base added to RealNamesNonUniqueNoRename")
	EndIf
EndFunction

Function _RestoreName(Actor akRef) Global
	{Gives back the name Real Names - Extended already picked for the ref (key RNE_Name in StorageUtil, which the other mod
	writes when it names an actor): the key is cleared and the display name set to the base's. Being on the list later does
	not undo a name, so a new game, or the first load with 1.2, can leave one. Without the other mod the key does not exist
	and nothing happens. Mechanism studied in another mod's fix for the same case; code is ours.}
	If !akRef || !StorageUtil.HasStringValue(akRef, "RNE_Name")
		Return
	EndIf
	ActorBase b = akRef.GetActorBase()
	If !b
		Return
	EndIf
	String renamed = StorageUtil.GetStringValue(akRef, "RNE_Name", "")
	StorageUtil.UnsetStringValue(akRef, "RNE_Name")
	akRef.SetDisplayName(b.GetName(), True)
	StorageUtil.SetStringValue(akRef, "AoT_RneNameGivenBack", renamed)
	Debug.Trace("[AoT] Real Names: name '" + renamed + "' given back to '" + b.GetName() + "' on " + akRef)
EndFunction

Function RestoreRealNames(Int aiHall) Global
	{Fase 16 etapa 12 (D121): the attendant (index 5) and the examiner (index 6) of one hall give back a name Real Names
	already picked.}
	String path = AoT_Attendant.HallsPath()
	String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + aiHall, "")
	If plug == "" || !Game.IsPluginInstalled(plug)
		Return
	EndIf
	Int idA = JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 5)
	Int idE = JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 6)
	If idA > 0
		_RestoreName(Game.GetFormFromFile(idA, plug) as Actor)
	EndIf
	If idE > 0
		_RestoreName(Game.GetFormFromFile(idE, plug) as Actor)
	EndIf
EndFunction

Function RestoreAllRealNames() Global
	{The 18 refs (nine halls); called at every load. No-op without Real Names - Extended.}
	If !Game.IsPluginInstalled("RealNamesExtended.esp")
		Return
	EndIf
	Int n = JsonUtil.StringListCount(AoT_Attendant.HallsPath(), "aot_hall_holds")
	Int i = 0
	While i < n
		RestoreRealNames(i)
		i += 1
	EndWhile
EndFunction

Function EnsureFixtures() Global
	{Board and examiner of the hall the player is in; no-op elsewhere. Called from the attendant tick.
	Fase 16 etapa 10 (D117): the examiner is a persistent ACHR of the hall's plugin (index 6 of the hall row), watched.}
	ExcludeFromRealNames()
	Int hall = AoT_Exam.HallIndexOfPlayer()
	If hall < 0
		Return
	EndIf
	RestoreRealNames(hall)
	_EnsureBoard(hall)
	If Game.IsPluginInstalled("AdventurersOfTamriel.esp")
		WatchNpc(hall, 4, 6, Game.GetFormFromFile(0x000E2E, "AdventurersOfTamriel.esp") as ActorBase, "aot_exm_ref_", "Examiner")
	EndIf
EndFunction

Bool Function _Created(ObjectReference akRef) Global
	{True for a ref the game created at runtime (FormID FF000000 to FFFFFFFF); never true for a plugin's ref.}
	Int id = akRef.GetFormID()
	Return id < 0 && id >= -16777216
EndFunction

Actor Function WatchNpc(Int aiHall, Int aiSpotIdx, Int aiRefIdx, ActorBase akBase, String asKeyBase, String asWho) Global
	{Fase 16 etapa 10 (D117): the NPC of a hall is the plugin's persistent ACHR named by index aiRefIdx of the hall row in
	halls.json. Migration of a 1.0/1.1 save: every ref of the base the script created by PlaceAtMe in this hall (FF
	FormID), the one kept under the old StorageUtil key included, is disabled and deleted; the plugin's ref stays.
	The plugin's ref is restored only when disabled, dead or out of the hall, and the reason is logged.
	Returns the plugin's ref, or None when the plugin or the table has none for this hall.}
	String path = AoT_Attendant.HallsPath()
	String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + aiHall, "")
	If plug == "" || !akBase || !Game.IsPluginInstalled(plug)
		Return None
	EndIf
	String hold = JsonUtil.StringListGet(path, "aot_hall_holds", aiHall)
	String refKey = asKeyBase + hold
	Cell hall = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 0), plug) as Cell
	Actor mine = None
	Int refId = JsonUtil.IntListGet(path, "aot_hall_" + aiHall, aiRefIdx)
	If refId > 0
		mine = Game.GetFormFromFile(refId, plug) as Actor
	EndIf
	If !hall || !mine || mine.GetActorBase() != akBase
		AoT_Attendant.Warn("noref" + asWho + hold, "[AoT] " + asWho + ": no ref of the plugin for " + hold + " (halls.json index " + aiRefIdx + " = " + refId + " in " + plug + "), nothing watched")
		Return None
	EndIf
	; migration (D117): the plugin's ref wins over any created one, the stored one included (it was the keeper before)
	ObjectReference stored = StorageUtil.GetFormValue(None, refKey, None) as ObjectReference
	If stored && stored != mine && _Created(stored)
		Debug.Trace("[AoT] " + asWho + ": created ref removed " + stored + " (stored key " + refKey + "), the plugin's is " + mine)
		stored.Disable()
		stored.Delete()
	EndIf
	Int n = hall.GetNumRefs(43)
	Int k = 0
	While k < n
		ObjectReference r = hall.GetNthRef(k, 43)
		If r && r != mine && r != stored && r.GetBaseObject() == akBase && _Created(r)
			Debug.Trace("[AoT] " + asWho + ": created ref removed " + r + " in " + hold + ", the plugin's is " + mine)
			r.Disable()
			r.Delete()
		EndIf
		k += 1
	EndWhile
	String why = ""
	If mine.IsDisabled()
		why += " disabled"
		mine.Enable()
	EndIf
	If mine.IsDead()
		why += " dead"
		mine.Resurrect()
	EndIf
	If mine.GetParentCell() != hall
		why += " out of the hall"
		ObjectReference spot = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, aiSpotIdx), plug) as ObjectReference
		If spot
			mine.MoveTo(spot)
		EndIf
	EndIf
	If why != ""
		Debug.Trace("[AoT] " + asWho + ": plugin ref " + mine + " restored in " + hold + " (" + why + " )")
	EndIf
	; D126: the examiner's base package became stay-at-editor-location; a save that already holds the ref re-evaluates
	; it once, with the 3D loaded, so she walks back to her spot on this load and not at the next package change
	String pkgKey = refKey + "_pkg"
	If StorageUtil.GetIntValue(None, pkgKey, 0) < 1 && mine.Is3DLoaded()
		mine.EvaluatePackage()
		StorageUtil.SetIntValue(None, pkgKey, 1)
		Debug.Trace("[AoT] " + asWho + ": package re-evaluated once for " + mine + " in " + hold)
	EndIf
	If stored != mine
		StorageUtil.SetFormValue(None, refKey, mine)
		Debug.Trace("[AoT] " + asWho + ": watching the plugin ref " + mine + " in " + hold)
	EndIf
	Return mine
EndFunction

Function _EnsureBoard(Int aiHall) Global
	{Fase 9 (D039): the board is a container that holds the contract notes. Without the contracts
	plugin the Fase 8 activator stays. The Fase 8 activator of the hold is removed once.
	Fase 16 etapa 13 (D123): our board (0x000DB8) always stands at the BoardSpot (index 2 of the hall row), key
	aot_cboard_ref_<hold>, alias 0, with our offers. With Missives installed the Missives board (Missives.esp 0x0012CB)
	stands at the second spot (index 7), key aot_mboard_ref_<hold>, alias 1, with the Missives offers: a Missives or
	Monster Hunt quest creates its note in the nearest board of that base (GetIsID), never in ours.
	A save of 1.0 to 1.2 with Missives kept the Missives board under aot_cboard_ref_: that ref is adopted as the Missives
	board (moved to its spot, its notes stay) and our untaken offers on it leave.}
	String plugin = AoT_ContractsCtl.PluginName()
	If !Game.IsPluginInstalled(plugin)
		_Ensure(aiHall, 2, "aot_board_ref_", "AdventurersOfTamriel.esp", 0x000E35)
		Return
	EndIf
	String path = AoT_Attendant.HallsPath()
	String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + aiHall, "")
	If plug == "" || !Game.IsPluginInstalled(plug)
		Return
	EndIf
	String hold = JsonUtil.StringListGet(path, "aot_hall_holds", aiHall)
	ObjectReference old = StorageUtil.GetFormValue(None, "aot_board_ref_" + hold, None) as ObjectReference
	If old
		old.Disable()
		old.Delete()
		StorageUtil.UnsetFormValue(None, "aot_board_ref_" + hold)
		Debug.Trace("[AoT-F9] Hall: Fase 8 board removed " + old)
	EndIf
	Form ours = Game.GetFormFromFile(0x000DB8, plugin)
	Form miss = None
	If Game.IsPluginInstalled("Missives.esp")
		miss = Game.GetFormFromFile(0x0012CB, "Missives.esp")
	EndIf
	Cell hall = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 0), plug) as Cell
	AoT_ContractsCtl ctl = AoT_ContractsCtl.Get()
	AoT_GuildBoardAlias ba = None
	AoT_GuildBoardAlias bm = None
	If ctl
		ba = ctl.GetAlias(0) as AoT_GuildBoardAlias
		bm = ctl.GetAlias(1) as AoT_GuildBoardAlias
	EndIf
	String refKey = "aot_cboard_ref_" + hold
	String missKey = "aot_mboard_ref_" + hold
	ObjectReference cur = StorageUtil.GetFormValue(None, refKey, None) as ObjectReference
	If cur && cur.GetBaseObject() != ours
		If miss && cur.GetBaseObject() == miss && !StorageUtil.GetFormValue(None, missKey, None)
			; D123: the Missives board of a save with one board becomes the Missives board; our offers on it leave
			StorageUtil.SetFormValue(None, missKey, cur)
			If ba
				ba.RetireOwn(cur)
			EndIf
			StorageUtil.SetIntValue(None, "aot_board_epoch", StorageUtil.GetIntValue(None, "aot_board_epoch", 0) + 1)
			Debug.Trace("[AoT-F16] Hall: one-board save, " + cur + " adopted as the Missives board of " + hold)
		Else
			Debug.Trace("[AoT-F9] Hall: board base changed, replacing " + cur)
			cur.Disable()
			cur.Delete()
		EndIf
		StorageUtil.UnsetFormValue(None, refKey)
		cur = None
	EndIf
	cur = _PlaceBoard(aiHall, plug, hall, ours, refKey, 2, cur)
	If ctl && cur
		ctl.SetBoard(cur)
		; Fase 14 etapa 2: fill the board while the player is in the hall, not on activation (R2-6, R2-7)
		If ba
			ba.RequestRefresh()
		EndIf
	EndIf
	ObjectReference mb = StorageUtil.GetFormValue(None, missKey, None) as ObjectReference
	If !miss
		If mb || StorageUtil.GetFormValue(None, missKey, None)
			StorageUtil.UnsetFormValue(None, missKey)
		EndIf
		If ctl
			ctl.SetMissBoard(None)
		EndIf
		Return
	EndIf
	If mb && mb.GetBaseObject() != miss
		mb.Disable()
		mb.Delete()
		StorageUtil.UnsetFormValue(None, missKey)
		mb = None
	EndIf
	mb = _PlaceBoard(aiHall, plug, hall, miss, missKey, 7, mb)
	If ctl && mb
		ctl.SetMissBoard(mb)
		If bm
			bm.RequestRefresh()
		EndIf
	EndIf
EndFunction

ObjectReference Function _PlaceBoard(Int aiHall, String asPlug, Cell akHall, Form akBase, String asKey, Int aiSpotIdx, ObjectReference akCur) Global
	{Fase 16 etapa 13 (D123): the board of base akBase at the spot of index aiSpotIdx of the hall row, kept under asKey.
	A ref of the hall more than 8 u off its spot goes to it (the adopted Missives board, D123). A ref out of the hall
	is replaced by a new one, placed only when the spot's 3D is loaded. Returns the ref, or None.}
	If !akBase || !akHall
		Return None
	EndIf
	ObjectReference spot = None
	Int spotId = JsonUtil.IntListGet(AoT_Attendant.HallsPath(), "aot_hall_" + aiHall, aiSpotIdx)
	If spotId > 0
		spot = Game.GetFormFromFile(spotId, asPlug) as ObjectReference
	EndIf
	If akCur && akCur.GetParentCell() == akHall
		If spot && akCur.GetDistance(spot) > 8.0
			akCur.MoveTo(spot)
			Debug.Trace("[AoT-F16] Hall: " + asKey + " " + akCur + " moved to its spot " + spot)
		EndIf
		Return akCur
	EndIf
	If !spot || !spot.Is3DLoaded()
		Return None
	EndIf
	ObjectReference r = spot.PlaceAtMe(akBase, 1, True, False)
	If r
		StorageUtil.SetFormValue(None, asKey, r)
		Debug.Trace("[AoT-F9] Hall: placed " + asKey + " " + r + " base=" + akBase)
	EndIf
	Return r
EndFunction