Scriptname AoT_MissivesAdapter_Player extends ReferenceAlias
{Player alias for AoT Missives adapter - reapplies via(c) on load.
Quest SGE AoT_MissivesAdapterQuest does NOT receive OnPlayerLoadGame
(evidencia f2 e4b3: only PlayerAlias of other mods fired). This alias does.}

GlobalVariable Property HighChance Auto
GlobalVariable Property VeryHighChance Auto

Event OnPlayerLoadGame()
    ResolveGlobals()
    ApplyViaC()
EndEvent

Function ResolveGlobals()
    if HighChance == None
        Form f = Game.GetFormFromFile(0x001D95, "Missives.esp")
        HighChance = f as GlobalVariable
    endif
    if VeryHighChance == None
        Form f2 = Game.GetFormFromFile(0x009450, "Missives.esp")
        VeryHighChance = f2 as GlobalVariable
    endif
EndFunction

Function ApplyViaC()
    if HighChance
        if HighChance.GetValue() != 0.0
            HighChance.SetValue(0.0)
            Debug.Trace("[AoT-Missives] via(c) High -> 0")
        endif
    endif
    if VeryHighChance
        if VeryHighChance.GetValue() != 0.0
            VeryHighChance.SetValue(0.0)
            Debug.Trace("[AoT-Missives] via(c) VeryHigh -> 0")
        endif
    endif
EndFunction
