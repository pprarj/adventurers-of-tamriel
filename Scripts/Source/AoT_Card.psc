Scriptname AoT_Card extends Quest
{Adventurer card: a read-only web panel (one screen) with the player's own guild record.
Opens on a hotkey through the Lodestone WebUI bridge. It never writes to the guild (D-23).
The handshake, the watchdog and the fallback are the same ones Intelligence Matters uses
for its journal panel (IM_SpellResearch, "O APERTO DE MAO" and OnUpdate), copied here.}

; ---------------------------------------------------------------------------
; Contract with the page (card.html). NOTHING VALIDATES THESE NAMES: a typo is
; a call that silently does nothing. They must match window.AoTOnCard,
; window.AoTCardAction and window.AoTCardLog in the page.
; ---------------------------------------------------------------------------

String Property ViewId     = "AdventurersOfTamrielCard" AutoReadOnly
String Property ViewPath   = "AdventurersOfTamriel/card.html" AutoReadOnly
String Property FnCard     = "AoTOnCard" AutoReadOnly
String Property FnAction   = "AoTCardAction" AutoReadOnly
String Property EvtAction  = "AoT_WebUICardAction" AutoReadOnly
String Property FnLog      = "AoTCardLog" AutoReadOnly
String Property EvtLog     = "AoT_WebUICardLog" AutoReadOnly
String Property EvtReady   = "LodestoneWebUIViewReady" AutoReadOnly

; Two floors, one per surface. Never one number for both: the web surface and
; the focus surface entered in different DLL versions.
; 1023000 (1.23.0) is where the Meridian UI level left the mod root (see
; IM_Core.WebUIMinVersion); 1022000 (1.22.0) is where WebUIFocusView exists.
Int Property WebUIMinVersion      = 1023000 AutoReadOnly
Int Property WebUIFocusMinVersion = 1022000 AutoReadOnly

; DirectX scan code of the hotkey: 65 is F7.
Int Property HotkeyCode = 65 AutoReadOnly

; How long to wait for the page to announce itself before giving up on it.
Float Property HelloSeconds    = 6.0 AutoReadOnly
; Period of the focus watchdog.
Float Property WatchdogSeconds = 1.0 AutoReadOnly

; ---------------------------------------------------------------------------
; Session cstate. Every flag here is bounded by the single OnUpdate timer, so a
; save taken in the middle of an opening cannot leave one stuck true.
; ---------------------------------------------------------------------------

Bool _pending       = False
Bool _visible       = False
Bool _wanted        = False
Bool _awaitingHello = False

Event OnInit()
	RegisterForKey(HotkeyCode)
EndEvent

Event OnKeyDown(Int aiKeyCode)
	If aiKeyCode != HotkeyCode
		Return
	EndIf
	; Closing our own panel is never a game action: it comes BEFORE the menu
	; guard, which only gates opening (a focused view may read as menu mode).
	If _visible || _awaitingHello
		ClosePanel("key")
		Return
	EndIf
	If Utility.IsInMenuMode() || UI.IsTextInputEnabled()
		Return
	EndIf
	OpenCard()
EndEvent

; ---------------------------------------------------------------------------
; Opening
; ---------------------------------------------------------------------------

Bool Function CanUsePanel()
	{Both gates: the web surface and the focus surface. The panel is interactive
	only (a card that cannot be closed would be a poster), so no focus, no panel.}
	If Lodestone.GetVersion() < WebUIFocusMinVersion || Lodestone.GetVersion() < WebUIMinVersion
		Return False
	EndIf
	If !Lodestone.WebUIAvailable()
		Return False
	EndIf
	Return Lodestone.WebUIHasCapability("view-focus")
EndFunction

Function OpenCard()
	; An orphan from before a load: the view outlives the load, the flags do not.
	If !_visible && Lodestone.WebUIIsViewReady(ViewId) && Lodestone.WebUIIsViewVisible(ViewId)
		Lodestone.WebUIClearFocus(ViewId)
		Lodestone.WebUIHide(ViewId)
	EndIf

	If !CanUsePanel()
		Debug.Trace("[AoT] Card: panel not available, plain card")
		ShowPlain()
		Return
	EndIf

	_wanted = True
	; Truth is the question, not the saved flag: after a load the view is gone.
	If Lodestone.WebUIIsViewReady(ViewId)
		OpenNow()
		Return
	EndIf
	If _pending
		Return
	EndIf

	; Register BEFORE asking: the view may become ready between two lines, and
	; an event with no receiver is lost forever.
	RegisterForModEvent(EvtReady, "OnCardReady")
	_pending = True
	; The wait for the page is the only timer in this phase.
	RegisterForSingleUpdate(HelloSeconds)
	If !Lodestone.WebUICreateView(ViewId, ViewPath)
		_pending = False
		_wanted = False
		Debug.Trace("[AoT] Card: WebUICreateView refused " + ViewPath)
		ShowPlain()
	EndIf
EndFunction

Event OnCardReady(String asEvent, String asViewId, Float afNum, Form akSender)
	If asViewId != ViewId || !_pending
		Return
	EndIf
	_pending = False
	RegisterForModEvent(EvtAction, "OnCardAction")
	RegisterForModEvent(EvtLog, "OnCardLog")
	Lodestone.WebUIRegisterListener(ViewId, FnAction, EvtAction)
	Lodestone.WebUIRegisterListener(ViewId, FnLog, EvtLog)
	If !_wanted
		Return
	EndIf
	OpenNow()
EndEvent

Function OpenNow()
	{SHOW comes first and FOCUS only after the page said "ready": ready from the
	bridge means SOME page loaded (an error page loads too). Only the page can say
	it is OURS, and it does that by calling AoTCardAction("ready-...").}
	_awaitingHello = True
	RegisterForSingleUpdate(HelloSeconds)
	Lodestone.WebUIShow(ViewId)
	_visible = True
	Push()
EndFunction

Function Push()
	Debug.Trace("[AoT] Card: push rank=" + RankLetter(AoT_Core.GetRank()) + " points=" + AoT_Core.GetPoints())
	Lodestone.WebUICall(ViewId, FnCard, BuildPayload())
EndFunction

Event OnCardAction(String asEvent, String asAction, Float afNum, Form akSender)
	String act = Unwrap(asAction)
	If StringUtil.Find(act, "ready") == 0
		If !_awaitingHello
			Return
		EndIf
		_awaitingHello = False
		Debug.Trace("[AoT] Card: page said " + act)
		Debug.Trace("[AoT] Card: asking focus; menuMode=" + Utility.IsInMenuMode())
		If !Lodestone.WebUIFocusView(ViewId)
			; Refusal is a normal case: one view at a time in the whole load order.
			Debug.Trace("[AoT] Card: WebUIFocusView refused")
			HideQuiet()
			ShowPlain()
			Return
		EndIf
		RegisterForSingleUpdate(WatchdogSeconds)
	ElseIf StringUtil.Find(act, "close") == 0
		ClosePanel("page")
	EndIf
EndEvent

Event OnCardLog(String asEvent, String asText, Float afNum, Form akSender)
	Debug.Trace("[AoT] Card page: " + Unwrap(asText))
EndEvent

; The page's argument may come wrapped in one pair of double quotes.
String Function Unwrap(String asRaw)
	Int n = StringUtil.GetLength(asRaw)
	If n < 2
		Return asRaw
	EndIf
	String quote = StringUtil.AsChar(34)
	If StringUtil.GetNthChar(asRaw, 0) != quote || StringUtil.GetNthChar(asRaw, n - 1) != quote
		Return asRaw
	EndIf
	Return StringUtil.Substring(asRaw, 1, n - 2)
EndFunction

; ---------------------------------------------------------------------------
; Watchdog and closing
; ---------------------------------------------------------------------------

; OnUpdate is per FORM, not per script: this quest carries exactly one script.
; The two timers (hello wait, focus watchdog) are mutually exclusive and share
; the single slot.
Event OnUpdate()
	If _pending
		; The view never became ready: wrong path or a backend that went away.
		_pending = False
		_wanted = False
		Debug.Trace("[AoT] Card: view not ready in time, plain card")
		ShowPlain()
		Return
	EndIf
	If _awaitingHello
		_awaitingHello = False
		_wanted = False
		HideQuiet()
		Debug.Trace("[AoT] Card: page did not answer in " + HelloSeconds + " s; focus NOT taken")
		ShowPlain()
		Return
	EndIf
	If !_visible
		Return
	EndIf
	If Lodestone.WebUIIsViewFocused(ViewId)
		RegisterForSingleUpdate(WatchdogSeconds)
		Return
	EndIf
	; Lost the focus (panic key, load, a pausing menu). Do not ask it back.
	Debug.Trace("[AoT] Card: focus lost, closing the panel")
	ClosePanel("watchdog")
EndEvent

Function HideQuiet()
	Lodestone.WebUIClearFocus(ViewId)
	Lodestone.WebUIHide(ViewId)
	_visible = False
EndFunction

Function ClosePanel(String asVia)
	{asVia says who closed it: "key", "page" or "watchdog". The line is written
	only when there was something to close.}
	Bool hadPanel = _visible || _awaitingHello
	_wanted = False
	_awaitingHello = False
	If !_visible
		If hadPanel
			Debug.Trace("[AoT] Card: closed by " + asVia)
		EndIf
		Return
	EndIf
	HideQuiet()
	Debug.Trace("[AoT] Card: closed by " + asVia)
EndFunction

Int Function BrowserKeyCode(Int aiScanCode)
	{DirectX scan code to the browser keyCode the page sees: F1-F10 (59-68) are
	112-121, F11/F12 (87/88) are 122/123. 0 = unknown, the page then keeps Esc only.}
	If aiScanCode >= 59 && aiScanCode <= 68
		Return aiScanCode + 53
	ElseIf aiScanCode == 87 || aiScanCode == 88
		Return aiScanCode + 35
	EndIf
	Return 0
EndFunction

; ---------------------------------------------------------------------------
; Payload (read-only, rebuilt at every opening) and the plain card
; ---------------------------------------------------------------------------

String Function BuildPayload()
	{One "key|value" line per fact. The page compares keys case-insensitively
	because Papyrus literals come back in the spelling the string pool holds.}
	Int rank = AoT_Core.GetRank()
	Int step = AoT_Core.LadderStep(rank)
	Int done = 0
	Int failed = 0
	Int open = 0
	Int lost = 0
	Int[] doneByBand = new Int[6]
	Int total = AoT_Core.ContractCount()
	Int id = 1
	While id <= total
		Int cstate = AoT_Core.ContractState(id)
		If cstate == 2
			done += 1
			Int band = AoT_Core.ContractBand(id)
			If band >= 0 && band < 6
				doneByBand[band] = doneByBand[band] + 1
			EndIf
		ElseIf cstate == 3 || cstate == 4
			failed += 1
			Int delta = AoT_Core.ContractDelta(id)
			If delta < 0
				lost += -delta
			EndIf
		ElseIf cstate == 1
			open += 1
		EndIf
		id += 1
	EndWhile

	String eol = StringUtil.AsChar(10)
	String text = "c_name|" + Game.GetPlayer().GetDisplayName() + eol
	text += "hotkey|" + BrowserKeyCode(HotkeyCode) + eol
	text += "c_rank|" + rank + eol
	text += "c_maxrank|" + AoT_Core.MaxRank() + eol
	text += "c_points|" + AoT_Core.GetPoints() + eol
	text += "c_step|" + step + eol
	If AoT_Core.IsPromotionEligible()
		text += "c_exam|1" + eol
	Else
		text += "c_exam|0" + eol
	EndIf
	text += "c_done|" + done + eol
	text += "c_failed|" + failed + eol
	text += "c_open|" + open + eol
	text += "c_lost|" + lost + eol
	Int b = 0
	While b < 6
		Int paid = 0
		If AoT_Core.IsBandPaid(b)
			paid = 1
		EndIf
		text += "c_band" + b + "|" + paid + "," + doneByBand[b] + eol
		b += 1
	EndWhile
	Return text
EndFunction

Function ShowPlain()
	{Where the panel is not possible (no backend, old DLL, focus refused, page
	dead): the same facts as a message box, so the key never ends in nothing.}
	String rankLetter = RankLetter(AoT_Core.GetRank())
	String text = "Adventurer card - rank " + rankLetter + ". Points " + AoT_Core.GetPoints()
	Int step = AoT_Core.LadderStep(AoT_Core.GetRank())
	If step >= 0
		text += " / " + step
	EndIf
	If AoT_Core.IsPromotionEligible()
		text += ". Ready for the promotion exam."
	EndIf
	Debug.MessageBox(text)
EndFunction

String Function RankLetter(Int aiRank)
	String letters = "FEDCBAS"
	If aiRank < 0 || aiRank > 6
		Return "?"
	EndIf
	Return StringUtil.GetNthChar(letters, aiRank)
EndFunction
