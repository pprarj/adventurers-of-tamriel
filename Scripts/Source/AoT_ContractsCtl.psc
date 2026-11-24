Scriptname AoT_ContractsCtl extends Quest
{The board quest of the generated contracts (Fase 9, D038). Alias 0 holds the board of the hall
the player is in; the contract quests point their Board alias at it (external alias) and create
their note inside it. Keeps the forbidden places list whole: the Skyrim.esm places are in the
plugin, the DLC places are added at runtime, so the plugin needs no DLC master (D-35).}

FormList Property Forbidden Auto

String Function ContractsPath() Global
	{JsonUtil path of the runtime data written by the generator.}
	Return "../../../Config/AdventurersOfTamriel/contracts"
EndFunction

String Function PluginName() Global
	Return "AdventurersOfTamriel.esp"
EndFunction

AoT_ContractsCtl Function Get() Global
	Return Game.GetFormFromFile(0x000DB7, PluginName()) as AoT_ContractsCtl
EndFunction

Event OnInit()
	EnsureForbidden()
EndEvent

Function EnsureForbidden()
	If !Forbidden
		Return
	EndIf
	ReleaseIsolation(self)
	String path = ContractsPath()
	Int n = JsonUtil.IntListCount(path, "aot_forbidden_dlc_ids")
	Int i = 0
	While i < n
		String plug = JsonUtil.StringListGet(path, "aot_forbidden_dlc_plugins", i)
		If plug != "" && Game.IsPluginInstalled(plug)
			Form f = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_forbidden_dlc_ids", i), plug)
			If f && !Forbidden.HasForm(f)
				Forbidden.AddForm(f)
				Debug.Trace("[AoT-F9] forbidden += " + f + " (" + plug + ")")
			EndIf
		EndIf
		i += 1
	EndWhile
EndFunction

Bool Function ForbidLocation(Location akLoc, String asWhy) Global
	{Fase 17 etapa 3 (D137): a place whose Boss no mod gives us (disabled by a third-party mod) joins the forbidden list at
	runtime, so the Dungeon alias of no contract picks it again. FormList.AddForm is kept by the save, so this is said once
	per place and per save; no list by mod. True when the place was added now.}
	AoT_ContractsCtl ctl = Get()
	If !ctl || !ctl.Forbidden || !akLoc
		Return False
	EndIf
	If ctl.Forbidden.HasForm(akLoc)
		Return False
	EndIf
	ctl.Forbidden.AddForm(akLoc)
	Debug.Trace("[AoT-F17] forbidden += " + akLoc + " (" + asWhy + ")")
	Return True
EndFunction

; ---------------------------------------------------------------- Boss not filled, start failed (D145)

Int Function LocalId(Form akForm) Global
	{The id of a form inside its own file, as the json tables write it (light plugin: the low 12 bits).}
	Int id = akForm.GetFormID()
	If Math.LogicalAnd(Math.RightShift(id, 24), 0xFF) == 0xFE
		Return Math.LogicalAnd(id, 0xFFF)
	EndIf
	Return Math.LogicalAnd(id, 0xFFFFFF)
EndFunction

Bool Function InForbidden(FormList akList, Location akLoc, Location akHold) Global
	{GetInCurrentLocFormList of the Dungeon alias: the place or one of its parents (below the hold) is in the list.}
	Location l = akLoc
	Int guard = 0
	While l && guard < 8
		If akList.HasForm(l)
			Return True
		EndIf
		If l == akHold
			Return False
		EndIf
		l = PO3_SKSEFunctions.GetParentLocation(l)
		guard += 1
	EndWhile
	Return False
EndFunction

Function ReleaseIsolation(AoT_ContractsCtl akCtl) Global
	{Gives back the places ForbidBossless put in the list only to test one place alone. Also run at each load, so a save
	made in the middle of a test keeps nothing.}
	Int n = StorageUtil.FormListCount(None, "aot_bosscheck_tmp")
	If n == 0 || !akCtl || !akCtl.Forbidden
		Return
	EndIf
	Int i = 0
	While i < n
		Form f = StorageUtil.FormListGet(None, "aot_bosscheck_tmp", i)
		If f
			akCtl.Forbidden.RemoveAddedForm(f)
		EndIf
		i += 1
	EndWhile
	StorageUtil.FormListClear(None, "aot_bosscheck_tmp")
EndFunction

Int Function ForbidBossless(Quest akQuest) Global
	{Fase 17 etapa 3 conserto 2 (D145): the Start() of a contract was refused and the engine already emptied its aliases.
	The places the Dungeon alias could have taken are rebuilt from the same four conditions (contracts.json aot_dun_*: the
	archetype keyword and the hold of the quest, read from the plugin; LocationHasRefType Boss; not in the forbidden list).
	One place: the refused Start() had only it, so its Boss did not fill. Two to 16: each one is tried alone by Start(),
	the others forbidden for the try and given back; a place refused alone has no Boss to fill. If every place is refused
	alone, or the board alias is empty, the cause is not a place and nothing is forbidden. Returns how many places joined
	the list.}
	AoT_ContractsCtl ctl = Get()
	AoT_Contract c = akQuest as AoT_Contract
	If !ctl || !ctl.Forbidden || !c
		Return 0
	EndIf
	ReferenceAlias boardAlias = ctl.GetAlias(0) as ReferenceAlias
	If !boardAlias || !boardAlias.GetReference()
		Debug.Trace("[AoT-F17] boss check " + akQuest + ": the board alias is empty, the refusal is not a place's")
		Return 0
	EndIf
	String path = ContractsPath()
	Int row = JsonUtil.IntListFind(path, "aot_dun_quest", LocalId(akQuest))
	If row < 0
		Debug.Trace("[AoT-F17] boss check " + akQuest + ": no Boss row in contracts.json, nothing forbidden")
		Return 0
	EndIf
	Keyword kw = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_dun_kw", row), "Skyrim.esm") as Keyword
	Location hold = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_dun_hold", row), "Skyrim.esm") as Location
	LocationRefType bossType = Game.GetFormFromFile(0x0130F7, "Skyrim.esm") as LocationRefType
	If !kw || !hold || !bossType
		Debug.Trace("[AoT-F17] boss check " + akQuest + ": bad row " + row + " kw=" + kw + " hold=" + hold)
		Return 0
	EndIf
	Keyword[] kws = new Keyword[1]
	kws[0] = kw
	Form[] all = PO3_SKSEFunctions.GetAllForms(104, kws)
	If !all
		Debug.Trace("[AoT-F17] boss check " + akQuest + ": no place with " + kw + ", nothing forbidden")
		Return 0
	EndIf
	Location[] cand = new Location[16]
	Int n = 0
	Int over = 0
	Int i = 0
	While i < all.Length
		Location l = all[i] as Location
		If l && l.HasKeyword(kw) && l.HasRefType(bossType) && (l == hold || hold.IsChild(l)) && !InForbidden(ctl.Forbidden, l, hold)
			If n < cand.Length
				cand[n] = l
				n += 1
			Else
				over += 1
			EndIf
		EndIf
		i += 1
	EndWhile
	Debug.Trace("[AoT-F17] boss check " + akQuest + " read=" + all.Length + " places=" + n + " over=" + over)
	If n == 0 || over > 0
		Return 0
	EndIf
	Bool[] bad = new Bool[16]
	Int nBad = 0
	If n == 1
		bad[0] = True
		nBad = 1
	Else
		Int k = 0
		While k < n
			Int j = 0
			While j < n
				If j != k
					ctl.Forbidden.AddForm(cand[j])
					StorageUtil.FormListAdd(None, "aot_bosscheck_tmp", cand[j], False)
				EndIf
				j += 1
			EndWhile
			If akQuest.Start()
				Debug.Trace("[AoT-F17] boss check alone " + cand[k] + ": started, dungeon=" + c.DungeonLocation() + " target=" + c.TargetActor())
				c.Retire()
				If !c.WaitStopped()
					ReleaseIsolation(ctl)
					Debug.Trace("[AoT-F17] boss check " + akQuest + ": did not stop after a try, nothing forbidden")
					Return 0
				EndIf
			Else
				Debug.Trace("[AoT-F17] boss check alone " + cand[k] + ": refused")
				bad[k] = True
				nBad += 1
			EndIf
			ReleaseIsolation(ctl)
			k += 1
		EndWhile
		If nBad == n
			Debug.Trace("[AoT-F17] boss check " + akQuest + ": every place refused alone, the cause is not a place; nothing forbidden")
			Return 0
		EndIf
	EndIf
	Int added = 0
	i = 0
	While i < n
		If bad[i] && ForbidLocation(cand[i], "Boss not filled, start failed")
			added += 1
		EndIf
		i += 1
	EndWhile
	Return added
EndFunction

Function SetBoard(ObjectReference akBoard)
	{The hall board the player is near goes into alias 0; activation is blocked so the alias
	script runs the offers before the container opens.}
	ReferenceAlias a = GetAlias(0) as ReferenceAlias
	If !a || !akBoard
		Return
	EndIf
	If a.GetReference() != akBoard
		a.ForceRefTo(akBoard)
		Debug.Trace("[AoT-F9] board alias -> " + akBoard)
	EndIf
	akBoard.BlockActivation(True)
EndFunction

Function SetMissBoard(ObjectReference akBoard)
	{Fase 16 etapa 13 (D123): with Missives installed the hall has two boards; the Missives board the player is near goes
	into alias 1 (MissivesBoard), blocked as alias 0 is, so its offers run before its container opens. None clears it.}
	ReferenceAlias a = GetAlias(1) as ReferenceAlias
	If !a
		Return
	EndIf
	If !akBoard
		If a.GetReference()
			a.Clear()
			Debug.Trace("[AoT-F16] missives board alias cleared")
		EndIf
		Return
	EndIf
	If a.GetReference() != akBoard
		a.ForceRefTo(akBoard)
		Debug.Trace("[AoT-F16] missives board alias -> " + akBoard)
	EndIf
	akBoard.BlockActivation(True)
EndFunction