Scriptname AoT_HallWalker extends Actor
{Hall adventurer that leaves through the door and comes back (Fase 11 etapa 4, D057; two trips and the door
sound, Fase 14 etapa 3). Attached to the placed actor. When a leave package ends next to the DoorMarker
(inside the hall, beside the door) the actor is disabled, and one game-time update brings him back to the
marker at that trip's return hour. No update loop: a single registration, kept by the save. Both steps are
safe to repeat. LeavePack2, ReturnHour2 and DoorSound are optional: left as None the script behaves as before.}

Package Property LeavePack Auto
{The scheduled package that walks the actor to the door marker.}
ObjectReference Property DoorMarker Auto
{Marker inside the hall, beside the door. Also the place he comes back to.}
Float Property ReturnHour = 22.0 Auto
{Game hour (0-24) at which he comes back from the trip that LeavePack starts.}
Float Property ArriveDist = 300.0 Auto
{Distance to the marker under which the package counts as having arrived.}
Package Property LeavePack2 Auto
{Optional second leave package of the day. None = no second trip.}
Float Property ReturnHour2 = 22.0 Auto
{Game hour (0-24) at which he comes back from the trip that LeavePack2 starts.}
Sound Property DoorSound Auto
{Optional. The door's open sound, played at the marker when he leaves and when he comes back. None = silent.}

Event OnPackageEnd(Package akOldPackage)
	If akOldPackage == LeavePack
		Leave(ReturnHour)
	ElseIf LeavePack2 != None && akOldPackage == LeavePack2
		Leave(ReturnHour2)
	EndIf
EndEvent

Function Leave(Float afReturnHour)
	If DoorMarker == None || IsDisabled() || IsDead()
		Return
	EndIf
	If GetDistance(DoorMarker) > ArriveDist
		Return
	EndIf
	Float t = Utility.GetCurrentGameTime()
	Float hour = (t - Math.Floor(t)) * 24.0
	Float wait = afReturnHour - hour
	If wait < 0.0
		wait += 24.0
	EndIf
	If wait < 0.05
		wait = 0.05
	EndIf
	RegisterForSingleUpdateGameTime(wait)
	If DoorSound != None
		DoorSound.Play(DoorMarker)
	EndIf
	Disable()
EndFunction

Event OnUpdateGameTime()
	ComeBack()
EndEvent

Function ComeBack()
	If DoorMarker == None || !IsDisabled()
		Return
	EndIf
	MoveTo(DoorMarker)
	Enable()
	If DoorSound != None
		DoorSound.Play(DoorMarker)
	EndIf
EndFunction
