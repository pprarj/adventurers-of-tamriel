Scriptname AoT_MMHAdapter extends Quest
{Soft bridge to Monster Hunt Missives (MMH).
Plugin AdventurersOfTamriel_MMH.esp, master MissivesMonsterHunt.esp.
MMH has no rank of its own, only the MMH_HuntsCompleted counter. The guild rank
is the gate (D007): MMH respects the rank or stays out. Delivery calls
MMH_RewardScript.PayAndClose(), the same public function the MMH broker calls - but that call lives in the
child script AoT_MMHPayment, which ships only with the MMH option of the installer (the core never names a
third-party type).
Presence is probed with Game.GetFormFromFile, so a missing MMH hides the branch
and logs nothing (D007). THIS script names no MMH type: the base DeliverMMH below pays
nothing and the child overrides it (the child imports the MMH source at compile time).}

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
    {Base version: pays nothing. The MMH option attaches AoT_MMHPayment (extends this script), which overrides
    this function with the real payout. Reached only if the quest carries the base script by mistake.}
    Debug.Trace("[AoT-MMH] DeliverMMH: no payer attached (AoT_MMHPayment missing), nothing paid")
EndFunction
