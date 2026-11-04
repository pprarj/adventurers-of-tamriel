Scriptname AoT_Exam
{The promotion exam in the exam room of the hall (Fase 8, D-13, D-18, D-21).
All entries are global; the state lives in StorageUtil under aot_ keys, so a reload in the
middle neither promotes nor traps the player: the tick that runs from the attendant quest
either finishes the exam (every foe dead, player alive and still in the hall) or aborts it
(player left the hall, a foe vanished). Aborting touches neither rank nor points (D-21).
Where the cut falls lives in points.json (AoT_Core.ExamKind); the foes by rank too.
Only AoT_Core.Promote writes the rank, and only when eligible.}

; aot_exam_state: 0 none, 1 in progress. aot_exam_rank: rank the exam started at.
; aot_exam_hall: index of the hall in halls.json. aot_exam_foes: FormList of the spawned actors.

Int Function ExamState() Global
	Return StorageUtil.GetIntValue(None, "aot_exam_state", 0)
EndFunction

Cell Function _HallCell(Int aiHall) Global
	String path = AoT_Attendant.HallsPath()
	String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + aiHall, "")
	If plug == "" || !Game.IsPluginInstalled(plug)
		Return None
	EndIf
	Return Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 0), plug) as Cell
EndFunction

ObjectReference Function _ExaminerSpot(Int aiHall) Global
	String path = AoT_Attendant.HallsPath()
	String plug = JsonUtil.GetStringValue(path, "aot_hall_plugin_" + aiHall, "")
	If plug == "" || !Game.IsPluginInstalled(plug)
		Return None
	EndIf
	Return Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_hall_" + aiHall, 4), plug) as ObjectReference
EndFunction

Int Function HallIndexOfPlayer() Global
	{Index of the hall the player stands in, -1 when none.}
	Cell here = Game.GetPlayer().GetParentCell()
	If !here || !here.IsInterior()
		Return -1
	EndIf
	String path = AoT_Attendant.HallsPath()
	Int n = JsonUtil.StringListCount(path, "aot_hall_holds")
	Int i = 0
	While i < n
		If _HallCell(i) == here
			Return i
		EndIf
		i += 1
	EndWhile
	Return -1
EndFunction

Function _Clear() Global
	{Removes the foes still standing and resets the state. Never touches rank or points.}
	Int n = StorageUtil.FormListCount(None, "aot_exam_foes")
	Int i = 0
	While i < n
		ObjectReference r = StorageUtil.FormListGet(None, "aot_exam_foes", i) as ObjectReference
		If r
			r.Disable()
			r.Delete()
		EndIf
		i += 1
	EndWhile
	StorageUtil.FormListClear(None, "aot_exam_foes")
	StorageUtil.SetIntValue(None, "aot_exam_state", 0)
EndFunction

Bool Function StartExam() Global
	{Called by the attendant ("I want the exam", action 5). Needs eligibility, a cut that asks for the
	exam, no exam running, and the player inside a hall that has an examiner spot with 3D loaded.}
	If ExamState() != 0
		Debug.Trace("[AoT] Exam start refused: already running")
		Return False
	EndIf
	If !AoT_Core.CanOfferExam()
		Debug.Trace("[AoT] Exam start refused: not eligible or no exam at rank " + AoT_Core.GetRank())
		Return False
	EndIf
	Int hall = HallIndexOfPlayer()
	If hall < 0
		Return False
	EndIf
	ObjectReference spot = _ExaminerSpot(hall)
	If !spot || !spot.Is3DLoaded()
		Debug.Trace("[AoT] Exam start refused: examiner spot missing or not loaded")
		Return False
	EndIf
	Int rank = AoT_Core.GetRank()
	String tbl = AoT_Core.TablePath()
	Int foes = JsonUtil.IntListGet(tbl, "aot_exam_foes", rank)
	Int boss = JsonUtil.IntListGet(tbl, "aot_exam_boss", rank)
	Form foeBase = Game.GetForm(0x0003DECD)
	Form bossBase = Game.GetForm(0x0003DF16)
	If foes + boss < 1 || !foeBase || !bossBase
		Debug.Trace("[AoT] Exam start refused: no foes in the table for rank " + rank)
		Return False
	EndIf
	StorageUtil.FormListClear(None, "aot_exam_foes")
	StorageUtil.SetIntValue(None, "aot_exam_state", 1)
	StorageUtil.SetIntValue(None, "aot_exam_rank", rank)
	StorageUtil.SetIntValue(None, "aot_exam_hall", hall)
	Actor pl = Game.GetPlayer()
	Int k = 0
	Int total = foes + boss
	While k < total
		Form b = foeBase
		If k >= foes
			b = bossBase
		EndIf
		ObjectReference r = spot.PlaceAtMe(b, 1, False, False)
		If r
			r.MoveTo(spot, 0.0, (k as Float - (total as Float - 1.0) / 2.0) * 110.0, 0.0)
			StorageUtil.FormListAdd(None, "aot_exam_foes", r, True)
			(r as Actor).StartCombat(pl)
		EndIf
		k += 1
	EndWhile
	Debug.Trace("[AoT] Exam started: rank=" + rank + " hall=" + hall + " foes=" + StorageUtil.FormListCount(None, "aot_exam_foes") + " points=" + AoT_Core.GetPoints())
	Return True
EndFunction

Function Tick() Global
	{Every attendant tick: finishes or aborts the exam in progress. Cheap when none is running.}
	If ExamState() != 1
		Return
	EndIf
	Actor pl = Game.GetPlayer()
	Int hall = StorageUtil.GetIntValue(None, "aot_exam_hall", -1)
	Cell hc = _HallCell(hall)
	If !hc || pl.GetParentCell() != hc
		Debug.Trace("[AoT] Exam aborted: player left the hall; rank=" + AoT_Core.GetRank() + " points=" + AoT_Core.GetPoints())
		_Clear()
		Return
	EndIf
	If pl.IsDead()
		_Clear()
		Return
	EndIf
	Int n = StorageUtil.FormListCount(None, "aot_exam_foes")
	If n < 1
		Debug.Trace("[AoT] Exam aborted: no foes recorded")
		_Clear()
		Return
	EndIf
	Int i = 0
	Int alive = 0
	While i < n
		Actor a = StorageUtil.FormListGet(None, "aot_exam_foes", i) as Actor
		If a && !a.IsDead()
			alive += 1
		EndIf
		i += 1
	EndWhile
	If alive > 0
		Return
	EndIf
	Int started = StorageUtil.GetIntValue(None, "aot_exam_rank", -1)
	Int before = AoT_Core.GetRank()
	Int ptsBefore = AoT_Core.GetPoints()
	Bool won = False
	If started == before
		won = AoT_Core.Promote()
	EndIf
	Debug.Trace("[AoT] Exam won=" + won + " rank " + before + " -> " + AoT_Core.GetRank() + " points " + ptsBefore + " -> " + AoT_Core.GetPoints())
	_Clear()
EndFunction
