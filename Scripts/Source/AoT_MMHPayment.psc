Scriptname AoT_MMHPayment extends AoT_MMHAdapter
{The payout of an MMH hunt. Lives only in the MMH option of the installer (it names MMH_RewardScript, a type of
Monster Hunt Missives); the core reaches it through the parent type AoT_MMHAdapter, so no core script names a
third-party type. Attached to AoT_MMHAdapterQuest in AdventurersOfTamriel_MMH.esp.}

Function DeliverMMH(Quest akMMHQuest)
    {Pays and closes an MMH hunt. akMMHQuest is the MMH_RewardScript quest at stage 40.}
    If !akMMHQuest
        Debug.Trace("[AoT-MMH] DeliverMMH: no quest")
        Return
    EndIf
    If !AoT_MMHAdapter.HasMMH()
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
