Scriptname AoT_TIF_Attendant extends TopicInfo
{Topic fragment of the guild attendant: dispatches to AoT_Attendant.RunAction.
ActionId: 1 pay fee, 2 abandon, 3 deliver head, 4 deliver MMH hunt. BandId: fee band.}

Int Property ActionId Auto
Int Property BandId Auto

Function Fragment_0(ObjectReference akSpeakerRef)
    AoT_Attendant.RunAction(ActionId, BandId)
EndFunction
