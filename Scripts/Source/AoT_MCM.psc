Scriptname AoT_MCM extends SKI_ConfigBase
{Settings page of Adventurers of Tamriel. One job in this phase: choose which perk
trees the adventurer card shows (D016). Five menus, one per card column; each lists
the skills whose tree is loaded, plus "(none)". With every menu on "(none)" the card
shows the five skills of highest level. The choice lives in the save (aot_card_tree_N,
AoT_Core.SetCardTree), never in this script.}

Int[] _opt
Bool _optReady = False
String[] _list
String[] _enum
Int _listCount = 0

Event OnConfigInit()
	ModName = "Adventurers of Tamriel"
EndEvent

Event OnGameReload()
	{D116: the MCM quest hears every load (SKI_QuestBase). The DLC places the contracts must not use (contracts.json) are
	added to the forbidden list here too, so a pack installed while the game was off is covered at once.}
	parent.OnGameReload()
	; D121: before any hall loads, the attendant and the examiner leave the Real Names - Extended renaming
	AoT_Hall.ExcludeFromRealNames()
	; D121: and a name Real Names already picked for the 18 refs is given back (a new game, or the first load with 1.2)
	AoT_Hall.RestoreAllRealNames()
	; D117: a missing PapyrusUtil or table of halls is said once per load
	AoT_Attendant att = Game.GetFormFromFile(0x000DB6, "AdventurersOfTamriel.esp") as AoT_Attendant
	If att
		att.NewLoad()
	EndIf
	AoT_ContractsCtl ctl = AoT_ContractsCtl.Get()
	If ctl
		ctl.EnsureForbidden()
	EndIf
	; D124: the global of the hall murmur follows the stored switch (a save from before 1.2 has no switch: on)
	AoT_Core.SyncHallSound()
	; D144: the portrait key is registered on a save from before 1.3 too
	AoT_Card card = CardQuest()
	If card
		card.NewLoad()
	EndIf
EndEvent

; D077 (Fase 14 etapa 1): the six options of the guild. Values live in the save (AoT_Core reads them at the moment
; of use, nothing is copied here); defaults: card key F7, fee x1.0, points x1.0, 5 offers, D-32 on, debug log off.
Int _optKey = 0
Int _optFee = 0
Int _optPts = 0
Int _optOffers = 0
Int _optD32 = 0
Int _optDebug = 0
Int _optMod = 0
Int _optSound = 0
; D144: the portrait key (the background page); it takes the card key's modifier.
Int _optPortrait = 0

Event OnPageReset(String asPage)
	SetCursorFillMode(TOP_TO_BOTTOM)
	AddHeaderOption("Guild")
	_optKey = AddKeyMapOption("Card key", AoT_Core.CardKey())
	_optMod = AddMenuOption("Card key modifier", ModMenuText(AoT_Core.CardModifier()))
	_optPortrait = AddKeyMapOption("Portrait key", AoT_Core.PortraitKey())
	_optFee = AddSliderOption("Fee multiplier", AoT_Core.FeeMultiplier(), "x{2}")
	_optPts = AddSliderOption("Points multiplier", AoT_Core.PointsMultiplier(), "x{2}")
	_optOffers = AddSliderOption("Contracts offered by the board", AoT_Core.BoardOffers() as Float, "{0}")
	_optD32 = AddToggleOption("Suppress vanilla inn and steward bounties", AoT_Core.SuppressVanillaBounties())
	; D124: label by translation key, as the modifier values (D106)
	_optSound = AddToggleOption("$AoT_HallSound", AoT_Core.HallSoundOn())
	_optDebug = AddToggleOption("Debug log", AoT_Core.DebugLogOn())
	; D105: the ids SkyUI gave and the value the modifier line shows (R1170 item 1, empty value and menu); debug log only
	AoT_Core.Log("[AoT] MCM: page reset page=" + asPage + " key=" + _optKey + " mod=" + _optMod + " dbg=" + _optDebug + " stored=" + StorageUtil.GetIntValue(None, "aot_opt_card_mod", 0) + " modText=[" + ModMenuText(AoT_Core.CardModifier()) + "]")
	; D189: the perk trees in the right column, from the top of the page (SkyUI: odd positions are the right column)
	SetCursorPosition(1)
	If Lodestone.GetVersion() < 1037000
		AddHeaderOption("Perk trees")
		AddTextOption("Needs Lodestone 1.6.0 or newer", "", OPTION_FLAG_DISABLED)
		Return
	EndIf
	BuildList()
	AddHeaderOption("Perk trees on the adventurer card")
	_opt = new Int[5]
	_optReady = True
	Int slot = 0
	While slot < AoT_Core.CardSlots()
		_opt[slot] = AddMenuOption("Column " + (slot + 1), Shown(AoT_Core.GetCardTree(slot)))
		slot += 1
	EndWhile
EndEvent

Function BuildList()
	{The skills that have a loaded perk tree. Index 0 is "(none)".}
	_list = new String[19]
	_enum = new String[19]
	_list[0] = "(none)"
	_enum[0] = ""
	_listCount = 1
	Int i = 0
	While i < AoT_Core.SkillCount()
		String nm = AoT_Core.SkillEnumName(i)
		If Lodestone.GetPerkTreePerks(nm).Length > 0
			_list[_listCount] = nm
			_enum[_listCount] = nm
			_listCount += 1
		EndIf
		i += 1
	EndWhile
EndFunction

String Function Shown(String asSkill)
	If asSkill == ""
		Return "(none)"
	EndIf
	Return asSkill
EndFunction

String Function ModMenuText(Int aiMod)
	{D106: the modifier line and its menu show translation keys (Interface/Translations/AdventurersOfTamriel_*.txt), as
	other SkyUI menus do; the plain strings left the line and the menu empty (R1170 item 1, twice).}
	If aiMod == 1
		Return "$AoT_ModShift"
	ElseIf aiMod == 2
		Return "$AoT_ModCtrl"
	ElseIf aiMod == 3
		Return "$AoT_ModAlt"
	EndIf
	Return "$AoT_ModOff"
EndFunction

Int Function SlotOf(Int aiOption)
	If !_optReady
		Return -1
	EndIf
	Int slot = 0
	While slot < AoT_Core.CardSlots()
		If _opt[slot] == aiOption
			Return slot
		EndIf
		slot += 1
	EndWhile
	Return -1
EndFunction

AoT_Card Function CardQuest()
	{The card's quest. D093: it lives in the main plugin (AoT_CardQuest 0xF59) since the card plugin joined it (D080);
	the old lookup in AdventurersOfTamriel_Card.esp found nothing, so a new key was never registered.}
	Return Game.GetFormFromFile(0x000F59, "AdventurersOfTamriel.esp") as AoT_Card
EndFunction

Event OnOptionKeyMapChange(Int aiOption, Int aiKeyCode, String asConflictControl, String asConflictName)
	If aiOption != _optKey && aiOption != _optPortrait
		Return
	EndIf
	If aiKeyCode < 1 || aiKeyCode > 255
		Return
	EndIf
	; D144: the card key and the portrait key are never the same key
	If aiOption == _optKey && aiKeyCode == AoT_Core.PortraitKey()
		ShowMessage("That key takes the portrait. Choose another one.", False)
		Return
	ElseIf aiOption == _optPortrait && aiKeyCode == AoT_Core.CardKey()
		ShowMessage("That key opens the adventurer card. Choose another one.", False)
		Return
	EndIf
	If asConflictControl != ""
		If !ShowMessage("That key is already used by " + asConflictControl + ". Use it anyway?", True)
			Return
		EndIf
	EndIf
	If aiOption == _optPortrait
		StorageUtil.SetIntValue(None, "aot_opt_portrait_key", aiKeyCode)
	Else
		StorageUtil.SetIntValue(None, "aot_opt_card_key", aiKeyCode)
	EndIf
	SetKeyMapOptionValue(aiOption, aiKeyCode)
	AoT_Card card = CardQuest()
	If card
		card.ApplyKey()
	EndIf
EndEvent

Event OnOptionSliderOpen(Int aiOption)
	If aiOption == _optFee
		SetSliderDialogStartValue(AoT_Core.FeeMultiplier())
		SetSliderDialogDefaultValue(1.0)
		SetSliderDialogRange(0.0, 3.0)
		SetSliderDialogInterval(0.25)
	ElseIf aiOption == _optPts
		SetSliderDialogStartValue(AoT_Core.PointsMultiplier())
		SetSliderDialogDefaultValue(1.0)
		SetSliderDialogRange(0.25, 3.0)
		SetSliderDialogInterval(0.25)
	ElseIf aiOption == _optOffers
		SetSliderDialogStartValue(AoT_Core.BoardOffers() as Float)
		SetSliderDialogDefaultValue(5.0)
		SetSliderDialogRange(3.0, 15.0)
		SetSliderDialogInterval(1.0)
	EndIf
EndEvent

Event OnOptionSliderAccept(Int aiOption, Float afValue)
	If aiOption == _optFee
		StorageUtil.SetFloatValue(None, "aot_opt_fee_mult", afValue)
		SetSliderOptionValue(aiOption, afValue, "x{2}")
		AoT_Attendant.SyncGlobals()
	ElseIf aiOption == _optPts
		StorageUtil.SetFloatValue(None, "aot_opt_points_mult", afValue)
		SetSliderOptionValue(aiOption, afValue, "x{2}")
	ElseIf aiOption == _optOffers
		StorageUtil.SetIntValue(None, "aot_board_offers", afValue as Int)
		SetSliderOptionValue(aiOption, afValue, "{0}")
	EndIf
EndEvent

Event OnOptionSelect(Int aiOption)
	If aiOption == _optD32
		Bool on = !AoT_Core.SuppressVanillaBounties()
		If on
			StorageUtil.SetIntValue(None, "aot_opt_d32", 1)
		Else
			StorageUtil.SetIntValue(None, "aot_opt_d32", 0)
		EndIf
		AoT_Core.SyncD32()
		SetToggleOptionValue(aiOption, on)
	ElseIf aiOption == _optSound
		Bool snd = !AoT_Core.HallSoundOn()
		If snd
			StorageUtil.SetIntValue(None, "aot_opt_hall_sound", 1)
		Else
			StorageUtil.SetIntValue(None, "aot_opt_hall_sound", 0)
		EndIf
		SetToggleOptionValue(aiOption, snd)
		AoT_Core.SyncHallSound(True)
	ElseIf aiOption == _optDebug
		Bool dbg = !AoT_Core.DebugLogOn()
		If dbg
			StorageUtil.SetIntValue(None, "aot_opt_debug", 1)
		Else
			StorageUtil.SetIntValue(None, "aot_opt_debug", 0)
		EndIf
		SetToggleOptionValue(aiOption, dbg)
	EndIf
EndEvent

Event OnOptionMenuOpen(Int aiOption)
	AoT_Core.Log("[AoT] MCM: menu open option=" + aiOption + " mod=" + _optMod + " slot=" + SlotOf(aiOption))
	If aiOption == _optMod
		String[] mods = new String[4]
		Int m = 0
		While m < 4
			mods[m] = ModMenuText(m)
			m += 1
		EndWhile
		AoT_Core.Log("[AoT] MCM: modifier options=[" + mods[0] + "|" + mods[1] + "|" + mods[2] + "|" + mods[3] + "] len=" + mods.Length + " start=" + AoT_Core.CardModifier())
		SetMenuDialogOptions(mods)
		SetMenuDialogStartIndex(AoT_Core.CardModifier())
		SetMenuDialogDefaultIndex(0)
		Return
	EndIf
	Int slot = SlotOf(aiOption)
	If slot < 0
		Return
	EndIf
	String current = AoT_Core.GetCardTree(slot)
	Int start = 0
	Int i = 0
	While i < _listCount
		If _enum[i] == current
			start = i
		EndIf
		i += 1
	EndWhile
	String[] shown = Utility.CreateStringArray(_listCount)
	i = 0
	While i < _listCount
		shown[i] = _list[i]
		i += 1
	EndWhile
	SetMenuDialogOptions(shown)
	SetMenuDialogStartIndex(start)
	SetMenuDialogDefaultIndex(0)
EndEvent

Event OnOptionMenuAccept(Int aiOption, Int aiIndex)
	AoT_Core.Log("[AoT] MCM: menu accept option=" + aiOption + " index=" + aiIndex + " mod=" + _optMod)
	If aiOption == _optMod
		If aiIndex >= 0 && aiIndex <= 3
			StorageUtil.SetIntValue(None, "aot_opt_card_mod", aiIndex)
			SetMenuOptionValue(aiOption, ModMenuText(aiIndex))
			AoT_Core.Log("[AoT] MCM: modifier stored=" + StorageUtil.GetIntValue(None, "aot_opt_card_mod", 0) + " text=[" + ModMenuText(aiIndex) + "]")
		EndIf
		Return
	EndIf
	Int slot = SlotOf(aiOption)
	If slot < 0 || aiIndex < 0 || aiIndex >= _listCount
		Return
	EndIf
	If !AoT_Core.SetCardTree(slot, _enum[aiIndex])
		ShowMessage("That tree is already shown in another column.", False)
		Return
	EndIf
	SetMenuOptionValue(aiOption, Shown(_enum[aiIndex]))
EndEvent

Event OnOptionDefault(Int aiOption)
	If aiOption == _optKey
		StorageUtil.SetIntValue(None, "aot_opt_card_key", 65)
		SetKeyMapOptionValue(aiOption, 65)
		AoT_Card card = CardQuest()
		If card
			card.ApplyKey()
		EndIf
		Return
	ElseIf aiOption == _optPortrait
		; D144: the default F8 only when the card key is not on it
		If AoT_Core.CardKey() == 66
			Return
		EndIf
		StorageUtil.SetIntValue(None, "aot_opt_portrait_key", 66)
		SetKeyMapOptionValue(aiOption, 66)
		AoT_Card pcard = CardQuest()
		If pcard
			pcard.ApplyKey()
		EndIf
		Return
	ElseIf aiOption == _optMod
		StorageUtil.SetIntValue(None, "aot_opt_card_mod", 0)
		SetMenuOptionValue(aiOption, ModMenuText(0))
		Return
	ElseIf aiOption == _optD32
		StorageUtil.SetIntValue(None, "aot_opt_d32", 1)
		AoT_Core.SyncD32()
		SetToggleOptionValue(aiOption, True)
		Return
	ElseIf aiOption == _optSound
		StorageUtil.SetIntValue(None, "aot_opt_hall_sound", 1)
		SetToggleOptionValue(aiOption, True)
		AoT_Core.SyncHallSound(True)
		Return
	ElseIf aiOption == _optDebug
		StorageUtil.SetIntValue(None, "aot_opt_debug", 0)
		SetToggleOptionValue(aiOption, False)
		Return
	EndIf
	Int slot = SlotOf(aiOption)
	If slot < 0
		Return
	EndIf
	AoT_Core.SetCardTree(slot, "")
	SetMenuOptionValue(aiOption, Shown(""))
EndEvent

Event OnOptionHighlight(Int aiOption)
	If aiOption == _optKey
		SetInfoText("The key that opens the adventurer card. Default F7. The card opens only for guild members.")
	ElseIf aiOption == _optMod
		SetInfoText("A key to hold with the card key to open the card: Shift, Ctrl or Alt (left or right), or no modifier. With one chosen, the card key alone does not open it. The portrait key takes the same modifier. Default: no modifier.")
	ElseIf aiOption == _optPortrait
		SetInfoText("Takes your portrait for the adventurer card and opens the page where you pick its background. With a portrait already taken, it opens the page, which can take another. Default F8. Needs Lodestone 1.53.0 or newer.")
	ElseIf aiOption == _optFee
		SetInfoText("Multiplies the fee paid at the attendant to unlock a band of contracts. 0 means no fee at all. Default 1.0.")
	ElseIf aiOption == _optPts
		SetInfoText("Multiplies the points a finished contract gives. Default 1.0.")
	ElseIf aiOption == _optOffers
		SetInfoText("How many contracts the board offers at each refresh, 3 to 15. Default 5.")
	ElseIf aiOption == _optD32
		SetInfoText("Hides the vanilla bounty and steward quests the guild replaces. Default on. With it on, stewards and innkeepers do not offer them.")
	ElseIf aiOption == _optSound
		SetInfoText("The murmur of people talking in the guild halls. Default on. The tavern music of the halls is the game's own and follows the game's music volume.")
	ElseIf aiOption == _optDebug
		SetInfoText("Writes the guild's informational lines to the Papyrus log. Errors are always written. Default off.")
	EndIf
	If SlotOf(aiOption) >= 0
		SetInfoText("The skill whose perk tree this column of the card shows. With every column on (none), the card shows the five skills of highest level.")
	EndIf
EndEvent
