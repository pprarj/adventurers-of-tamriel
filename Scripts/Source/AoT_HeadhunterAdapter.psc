Scriptname AoT_HeadhunterAdapter extends Quest
{Soft bridge to Headhunter / Bounties Redone.
Plugin AdventurersOfTamriel_Headhunter.esp, master Headhunter - Bounties Redone.esp,
and optionally BountiesRedone_MissivesExtension.esp (the stage-40 INFO lives there; the hunt
quests themselves are Missives.esp records that the extension only overrides).
The attendant's own INFO is conditioned on the foreign quest being at stage 40
(GetStageDone 40, the condition the foreign INFO uses); its fragment calls
DeliverHead. The foreign stage-100 fragment pays the gold (D007).
Presence is probed with Game.GetFormFromFile and hides the branch without
logging an error.}

Bool Function HasHeadhunter() Global
    {Soft presence check without logging.}
    Form f = Game.GetFormFromFile(0x00000800, "Headhunter - Bounties Redone.esp")
    Return f != None
EndFunction

Quest Function FindReadyQuest() Global
    {E5 (D034 gap 1): scans the hunt quests listed in adapters.json for the one at stage 40, the one
    the attendant takes delivery of. None when the mod is absent or no hunt is ready; no log either
    way, so the soft path costs nothing (D007, D-35). The ids are Missives.esp quests: the extension
    overrides them but owns none, so GetFormFromFile against the extension finds nothing.}
    If !Game.IsPluginInstalled("BountiesRedone_MissivesExtension.esp")
        Return None
    EndIf
    String path = "../../../Config/AdventurersOfTamriel/adapters"
    Int n = JsonUtil.IntListCount(path, "aot_adapter_head")
    Int i = 0
    While i < n
        Quest q = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_adapter_head", i), "Missives.esp") as Quest
        If q && q.GetStage() == 40
            Return q
        EndIf
        i += 1
    EndWhile
    Return None
EndFunction

Function DeliverHead(Quest akHeadhunterQuest)
    {Called when the player hands over the head. akHeadhunterQuest is the foreign
    quest at stage 40; it is advanced to 100 and its own fragment pays.}
    If !akHeadhunterQuest
        Debug.Trace("[AoT-Headhunter] DeliverHead: no quest")
        Return
    EndIf
    If akHeadhunterQuest.GetStage() != 40
        Debug.Trace("[AoT-Headhunter] DeliverHead: stage is " + akHeadhunterQuest.GetStage() + " not 40")
        Return
    EndIf
    akHeadhunterQuest.SetStage(100)
    Debug.Trace("[AoT-Headhunter] DeliverHead -> SetStage 100 on " + akHeadhunterQuest)
EndFunction

Bool Function TryRepointToAttendant(Quest akHeadhunterQuest, ObjectReference akAttendantRef)
    {Best effort: if the foreign quest has a ReferenceAlias named Steward, point it
    at the attendant ref so the objective marker leads here. No caller yet.
    Returns true when a repoint was done.}
    If !akHeadhunterQuest || !akAttendantRef
        Return False
    EndIf
    Alias ali = akHeadhunterQuest.GetAliasByName("Steward")
    If !ali
        ; The Steward is alias 3 in the Kill family.
        ali = akHeadhunterQuest.GetNthAlias(3)
        If !ali
            Return False
        EndIf
    EndIf
    ReferenceAlias refAli = ali as ReferenceAlias
    If !refAli
        Return False
    EndIf
    refAli.ForceRefTo(akAttendantRef)
    Debug.Trace("[AoT-Headhunter] ForceRefTo Steward -> attendant on " + akHeadhunterQuest)
    Return True
EndFunction
