Scriptname AoT_HallWalker extends Actor
{Hall adventurer that leaves through the door and comes back (Fase 11 etapa 4, D057). Attached to the
placed actor. When the leave package ends next to the DoorMarker (inside the hall, beside the door) the
actor is disabled, and one game-time update brings him back to the marker at ReturnHour. No update loop:
a single registration, kept by the save. Both steps are safe to repeat.}

Package Property LeavePack Auto
{The scheduled package that walks the actor to the door marker.}
ObjectReference Property DoorMarker Auto
{Marker inside the hall, beside the door. Also the place he comes back to.}
Float Property ReturnHour = 22.0 Auto
{Game hour (0-24) at which he comes back.}
Float Property ArriveDist = 300.0 Auto
{Distance to the marker under which the package counts as having arrived.}

Event OnPackageEnd(Package akOldPackage)
	If akOldPackage == LeavePack
		Leave()
	EndIf
EndEvent

Function Leave()
	If DoorMarker == None || IsDisabled() || IsDead()
		Return
	EndIf
	If GetDistance(DoorMarker) > ArriveDist
		Return
	EndIf
	Float t = Utility.GetCurrentGameTime()
	Float hour = (t - Math.Floor(t)) * 24.0
	Float wait = ReturnHour - hour
	If wait < 0.0
		wait += 24.0
	EndIf
	If wait < 0.05
		wait = 0.05
	EndIf
	RegisterForSingleUpdateGameTime(wait)
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
EndFunction
