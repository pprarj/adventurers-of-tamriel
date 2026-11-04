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
	_Ensure(hall, 2, "aot_board_ref_", "AdventurersOfTamriel_ExamTalk.esp", 0x000806)
	_Ensure(hall, 4, "aot_exm_ref_", "AdventurersOfTamriel_Exam.esp", 0x000803)
EndFunction
