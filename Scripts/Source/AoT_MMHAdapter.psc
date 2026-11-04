Scriptname AoT_MMHAdapter extends Quest
{Soft bridge to Monster Hunt Missives (MMH).
Plugin AdventurersOfTamriel_MMH.esp, master MissivesMonsterHunt.esp.
MMH has no rank of its own, only the MMH_HuntsCompleted counter. The guild rank
is the gate (D007): MMH respects the rank or stays out. Delivery calls
MMH_RewardScript.PayAndClose(), the same public function the MMH broker calls.
Presence is probed with Game.GetFormFromFile, so a missing MMH hides the branch
and logs nothing (D007). The file imports the MMH source at compile time so
PayAndClose resolves; at runtime the call is guarded by HasMMH().}

Bool Function HasMMH() Global
    Form f = Game.GetFormFromFile(0x06000845, "MissivesMonsterHunt.esp")
    Return f != None
EndFunction

Bool Function CanTakeMMHBand(Int aiBand)
    {True when the guild rank allows this band (D007). The MMH hunt counter never
    widens the gate: a low-rank player cannot take a High hunt because the
    counter is high.}
    Return AoT_Core.BandWeight(AoT_Core.GetRank(), aiBand) > 0
EndFunction

Quest Function FindReadyQuest() Global
    {E5 (D034 gap 1): scans the hunt quests listed in adapters.json for the one at stage 40, the one
    the attendant takes delivery of. None when the mod is absent or no hunt is ready; no log either
    way, so the soft path costs nothing (D007, D-35).}
    If !Game.IsPluginInstalled("MissivesMonsterHunt.esp")
        Return None
    EndIf
    String path = "../../../Config/AdventurersOfTamriel/adapters"
    Int n = JsonUtil.IntListCount(path, "aot_adapter_mmh")
    Int i = 0
    While i < n
        Quest q = Game.GetFormFromFile(JsonUtil.IntListGet(path, "aot_adapter_mmh", i), "MissivesMonsterHunt.esp") as Quest
        If q && q.GetStage() == 40
            Return q
        EndIf
        i += 1
    EndWhile
    Return None
EndFunction

Function DeliverMMH(Quest akMMHQuest)
    {Pays and closes an MMH hunt. akMMHQuest is the MMH_RewardScript quest at stage 40.}
    If !akMMHQuest
        Debug.Trace("[AoT-MMH] DeliverMMH: no quest")
        Return
    EndIf
    If !HasMMH()
        Debug.Trace("[AoT-MMH] DeliverMMH: MMH not present")
        Return
    EndIf
    If akMMHQuest.GetStage() != 40
        Debug.Trace("[AoT-MMH] DeliverMMH: stage is " + akMMHQuest.GetStage() + " not 40")
        Return
    EndIf
    ; The MMH quest IS an MMH_RewardScript (extends Quest). If the cast fails
    ; (another family), fall back to stage 100.
    MMH_RewardScript m = akMMHQuest as MMH_RewardScript
    If m
        m.PayAndClose()
        Debug.Trace("[AoT-MMH] DeliverMMH -> PayAndClose on " + akMMHQuest)
    Else
        akMMHQuest.SetStage(100)
        Debug.Trace("[AoT-MMH] DeliverMMH -> SetStage 100 fallback on " + akMMHQuest)
    EndIf
EndFunction
