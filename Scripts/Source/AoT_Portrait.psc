Scriptname AoT_Portrait Hidden
{The player's portrait for the adventurer card (D144): taken on a key of its own, shown on a page of its own (the
background page, portrait.html), and read by the card. Global functions only; the key, the page and its timers live
in AoT_Card, which owns the card quest.

THE FILES. Lodestone writes a cut-out PNG (alpha where the depth is not the player) next to the pages, under a key per
character, and a capture deletes only the earlier files of its OWN key. So the portrait uses two keys per character,
<name>_a and <name>_b: the confirmed one is in the save (aot_portrait_slot), and a new capture always goes to the other
one. Cancelling leaves the confirmed file untouched; confirming makes the other key the confirmed one. Two characters
with the same name share the files (the key is the name).

THE BACKGROUND. 0 the card's own yellow, 1 Nordic ruins, 2 Soul Cairn, 3 Word Wall (aot_portrait_bg, in the save, read
by the card at every opening). The pages draw it under the cut-out; nothing of it goes into the PNG.}

; 1053000 (1.53.0) adds CapturePlayerPortraitCutout and GetPlayerPortrait. Below it there is no portrait at all.
Int Function MinVersion() Global
	Return 1053000
EndFunction

; The folder of the pages under Data\PrismaUI\views\ and Data\Magelight\ (the view path without the file).
String Function Folder() Global
	Return "AdventurersOfTamriel"
EndFunction

; Side of the PNG. The card draws it at 200 page units and the page at 360, both scaled up to 1.5 with the screen.
Int Function Size() Global
	Return 512
EndFunction

Int Function BackgroundCount() Global
	Return 4
EndFunction

; D161: how long a capture from the first person waits for the third-person view, and then for its zoom out (real
; time, seconds).
Float Function CameraSeconds() Global
	Return 2.0
EndFunction

Float Function SettleSeconds() Global
	Return 0.5
EndFunction

Bool Function Available() Global
	Return Lodestone.GetVersion() >= MinVersion()
EndFunction

String Function BaseKey() Global
	{The player's name as the key. Lodestone cleans it (letters, digits, '_' and '-', lower case, at most 32); it is cut
	to 30 here so the slot suffix always fits. No name reads as "player", never "" (the key-less names are the ones the
	older capture deletes).}
	String nm = Game.GetPlayer().GetDisplayName()
	If nm == ""
		nm = "player"
	EndIf
	If StringUtil.GetLength(nm) > 30
		nm = StringUtil.Substring(nm, 0, 30)
	EndIf
	Return nm
EndFunction

Int Function ConfirmedSlot() Global
	{0 no portrait confirmed (a new character, or a save from before 1.3), 1 the key _a, 2 the key _b.}
	Int s = StorageUtil.GetIntValue(None, "aot_portrait_slot", 0)
	If s < 0 || s > 2
		Return 0
	EndIf
	Return s
EndFunction

Int Function PendingSlot() Global
	{Where the next capture goes: never the confirmed one.}
	If ConfirmedSlot() == 1
		Return 2
	EndIf
	Return 1
EndFunction

String Function SlotKey(Int aiSlot) Global
	If aiSlot == 2
		Return BaseKey() + "_b"
	EndIf
	Return BaseKey() + "_a"
EndFunction

String Function ConfirmedFile() Global
	{The confirmed portrait's file name, "" when there is none (no slot, an old DLL, or the file is gone).}
	Int s = ConfirmedSlot()
	If s == 0 || !Available()
		Return ""
	EndIf
	Return Lodestone.GetPlayerPortrait(Folder(), SlotKey(s))
EndFunction

Int Function Background() Global
	Int b = StorageUtil.GetIntValue(None, "aot_portrait_bg", 0)
	If b < 0 || b >= BackgroundCount()
		Return 0
	EndIf
	Return b
EndFunction

String Function Take() Global
	{One capture to the pending key, never repeated (a refusal is said on the page). Latent: a few frames, and up to
	CameraSeconds() + SettleSeconds() more from the first person. Returns the file name, "" when refused.
	D161: the native takes the picture only in the plain third-person view. From the first person (camera state 0) the
	capture switches to the third person, waits for it, takes the picture and goes back to the first person, so the
	player takes as many as they want without changing the view by hand. Any other state is left as it is.}
	If !Available()
		Return ""
	EndIf
	Int cam = Game.GetCameraState()
	Bool back = cam == 0
	If back
		Game.ForceThirdPerson()
		Float t0 = Utility.GetCurrentRealTime()
		Int now = Game.GetCameraState()
		While now != 8 && now != 9 && Utility.GetCurrentRealTime() - t0 < CameraSeconds()
			Utility.WaitMenuMode(0.05)
			now = Game.GetCameraState()
		EndWhile
		; the state changes before the camera has zoomed out of the head
		Utility.WaitMenuMode(SettleSeconds())
	EndIf
	Int at = Game.GetCameraState()
	StorageUtil.SetIntValue(None, "aot_portrait_take_cam", at)
	String got = Lodestone.CapturePlayerPortraitCutout(Folder(), Size(), SlotKey(PendingSlot()), True)
	If back
		Game.ForceFirstPerson()
	EndIf
	; Always on: the camera the capture started from, the one it ran in, and whether it went back
	Debug.Trace("[AoT] Portrait: camera from=" + cam + " capture=" + at + " back=" + back + " now=" + Game.GetCameraState())
	Return got
EndFunction

; 1054000 (1.54.0) adds GetPlayerPortraitFailure, the reason of a refused capture. Below it the reason is read from the
; camera state, as before.
Int Function ReasonMinVersion() Global
	Return 1054000
EndFunction

String Function RefusalText(Int aiCameraState) Global
	{The reason the page shows for a refused capture (D169). With Lodestone 1.54.0 or newer the text follows the code the
	native gives for the capture that just failed; below it, or with no code, the camera state tells the two cases the
	player can fix. D161: the state the last Take() captured in wins over the one the caller read before it (Take()
	leaves the first person by itself).}
	If Lodestone.GetVersion() >= ReasonMinVersion()
		String code = Lodestone.GetPlayerPortraitFailure()
		Debug.Trace("[AoT] Portrait: refusal code=" + code)
		If code == "busy"
			Return "A portrait was still being taken. Wait a moment and take it again."
		ElseIf code == "menu"
			Return "A menu was open. Close it and take the portrait again."
		ElseIf code == "firstperson"
			Return "The portrait needs the plain third-person view: not on a mount, at furniture or in the free camera."
		ElseIf code == "camera"
			Return "The camera did not stay where the portrait needs it. Take it again; if it repeats, the camera of another mod is moving it."
		ElseIf code == "face"
			Return "Your character is turned away from the camera. Face the camera and take it again."
		ElseIf code == "faded"
			Return "The camera is too close to a wall behind you. Step away from the wall and take it again."
		ElseIf code == "load"
			Return "A game was loading. Take the portrait again."
		ElseIf code == "other"
			Return "The portrait could not be taken. Take it again."
		EndIf
	EndIf
	aiCameraState = StorageUtil.GetIntValue(None, "aot_portrait_take_cam", aiCameraState)
	If aiCameraState == 0
		Return "Switch to the third-person view and take it again."
	ElseIf aiCameraState != 8 && aiCameraState != 9
		Return "The portrait needs the plain third-person view."
	EndIf
	Return "The portrait was not taken. Face the camera and take it again."
EndFunction

Function Confirm(String asNewFile, Int aiBackground) Global
	{The page's confirm: a new file makes its key the confirmed one; the background is kept either way.}
	Int bg = aiBackground
	If bg < 0 || bg >= BackgroundCount()
		bg = 0
	EndIf
	If asNewFile != ""
		StorageUtil.SetIntValue(None, "aot_portrait_slot", PendingSlot())
	EndIf
	StorageUtil.SetIntValue(None, "aot_portrait_bg", bg)
EndFunction
