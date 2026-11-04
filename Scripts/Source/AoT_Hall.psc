Scriptname AoT_Hall
{Places the guild board and the examiner in the hall the player stands in (Fase 8, D035, D037).
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

Function EnsureFixtures() Global
	{Board and examiner of the hall the player is in; no-op elsewhere. Called from the attendant tick.}
	Int hall = AoT_Exam.HallIndexOfPlayer()
	If hall < 0
		Return
	EndIf
	_EnsureBoard(hall)
	_Ensure(hall, 4, "aot_exm_ref_", "AdventurersOfTamriel_Exam.esp", 0x000803)
EndFunction

Function _EnsureBoard(Int aiHall) Global
	{Fase 9 (D039): the board is a container that holds the contract notes. Without the contracts
	plugin the Fase 8 activator stays. With Missives installed the board is the Missives board base
	(a Missives quest creates its note in the nearest one of them, GetIsID), else ours. The Fase 8
	activator of the hold is removed once. The board goes into the board quest alias.}
	String plugin = AoT_ContractsCtl.PluginName()
	If !Game.IsPluginInstalled(plugin)
		_Ensure(aiHall, 2, "aot_board_ref_", "AdventurersOfTamriel_ExamTalk.esp", 0x000806)
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
	Form base = None
	If Game.IsPluginInstalled("Missives.esp")
		base = Game.GetFormFromFile(0x0012CB, "Missives.esp")
	EndIf
	If !base
		base = Game.GetFormFromFile(0x000801, plugin)
	EndIf
	Cell hall = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 0), plug) as Cell
	String refKey = "aot_cboard_ref_" + hold
	ObjectReference cur = StorageUtil.GetFormValue(None, refKey, None) as ObjectReference
	If cur && cur.GetBaseObject() != base
		Debug.Trace("[AoT-F9] Hall: board base changed, replacing " + cur)
		cur.Disable()
		cur.Delete()
		cur = None
	EndIf
	If !cur || cur.GetParentCell() != hall
		ObjectReference spot = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 2), plug) as ObjectReference
		If !spot || !base || !spot.Is3DLoaded()
			Return
		EndIf
		cur = spot.PlaceAtMe(base, 1, True, False)
		If !cur
			Return
		EndIf
		StorageUtil.SetFormValue(None, refKey, cur)
		Debug.Trace("[AoT-F9] Hall: placed " + refKey + " " + cur + " base=" + base)
	EndIf
	AoT_ContractsCtl ctl = AoT_ContractsCtl.Get()
	If ctl
		ctl.SetBoard(cur)
	EndIf
EndFunction