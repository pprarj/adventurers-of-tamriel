Scriptname AoT_MCM extends SKI_ConfigBase
{Settings page of Adventurers of Tamriel. One job in this phase: choose which perk
trees the adventurer card shows (D016). Five menus, one per card column; each lists
the skills whose tree is loaded, plus "(none)". With every menu on "(none)" the card
shows the five skills of highest level. The choice lives in the save (aot_card_tree_N,
AoT_Core.SetCardTree), never in this script.}

Int[] _opt
String[] _list
String[] _enum
Int _listCount = 0

Event OnConfigInit()
	ModName = "Adventurers of Tamriel"
EndEvent

Event OnPageReset(String asPage)
	SetCursorFillMode(TOP_TO_BOTTOM)
	If Lodestone.GetVersion() < 1037000
		AddHeaderOption("Perk trees")
		AddTextOption("Needs Lodestone 1.37.0 or newer", "", OPTION_FLAG_DISABLED)
		Return
	EndIf
	BuildList()
	AddHeaderOption("Perk trees on the adventurer card")
	_opt = new Int[5]
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

Int Function SlotOf(Int aiOption)
	If _opt == None
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

Event OnOptionMenuOpen(Int aiOption)
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
	Int slot = SlotOf(aiOption)
	If slot < 0
		Return
	EndIf
	AoT_Core.SetCardTree(slot, "")
	SetMenuOptionValue(aiOption, Shown(""))
EndEvent

Event OnOptionHighlight(Int aiOption)
	If SlotOf(aiOption) >= 0
		SetInfoText("The skill whose perk tree this column of the card shows. With every column on (none), the card shows the five skills of highest level.")
	EndIf
EndEvent
