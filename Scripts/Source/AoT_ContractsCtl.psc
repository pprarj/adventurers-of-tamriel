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