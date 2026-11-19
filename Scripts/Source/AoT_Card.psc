Scriptname AoT_Card extends Quest
{Adventurer card: a web panel (one screen) with the player's own guild record and the
perk trees the player chose (D016). It never writes to the guild; the one thing
it does is spend a perk point on a click, through Lodestone.TryBuyPerk.
Opens on a hotkey through the Lodestone WebUI bridge.
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
; 1023000 (1.23.0) is where the web UI level left the mod root (see
; IM_Core.WebUIMinVersion); 1022000 (1.22.0) is where WebUIFocusView exists.
Int Property WebUIMinVersion      = 1023000 AutoReadOnly
Int Property WebUIFocusMinVersion = 1022000 AutoReadOnly
; 1037000 (Nexus 1.6.0) is the perk module (GetPerkPoints, TryBuyPerk, GetPerkTree*).
; Below it the card opens without trees and says why.
Int Property PerkMinVersion       = 1037000 AutoReadOnly
; 1044000 (1.44.0) adds GetPerkTreeOffsetX / GetPerkTreeOffsetY (the node's fine position, HNAM / VNAM). Below it the
; card draws on the integer grid alone (D094).
Int Property OffsetMinVersion     = 1044000 AutoReadOnly
; 1049000 (1.49.0) adds CapturePlayerPortrait (D116). Below it the portrait stays the silhouette, with no message.
Int Property PortraitMinVersion   = 1049000 AutoReadOnly
; The folder of the page under Data\PrismaUI\views\ and Data\Magelight\ (the view path without the file), and the
; side of the PNG. The native returns the file name; the page loads it relative to itself.
String Property PortraitFolder    = "AdventurersOfTamriel" AutoReadOnly
Int Property PortraitSize         = 256 AutoReadOnly
; D134: the native refuses a capture whose head is turned from the camera (about 0.6 s for one refusal). A refused
; capture is asked again at most PortraitRetries more times, only while the card is still opening, and only when the
; next try, as long as the last one, ends within PortraitBudget seconds of the key press: the card shows in 2 s.
Int Property PortraitRetries      = 2 AutoReadOnly
Float Property PortraitBudget     = 1.9 AutoReadOnly

; DirectX scan code of the hotkey: the settings page writes it (D077), AoT_Core.CardKey() reads it at the
; moment of use; 65 (F7) is the default. _regKey is the key registered now, 0 in a save made before the option.
Int _regKey = 0
; DirectX scan code of Esc. Registered ONLY while the card is open or opening (D021):
; with the card closed Esc belongs to the game and this mod does not listen.
Int Property EscCode = 1 AutoReadOnly

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
; D103: True once the payload of this opening left. A "ready" before it is the page's own hello at load, which can
; overtake the payload while BuildPayload runs; trees pushed then were wiped by the payload that came after them.
Bool _payloadSent   = False
; D116: the file name the native returned for THIS opening; sent in the payload, then cleared (never kept in the save).
String _portrait = ""
; D134: the last file a capture of this card wrote, and the real time of that capture. The native deletes a file only
; at the NEXT good capture to the folder, so a refused one can send this one instead. A save keeps both; a stamp later
; than the clock is another boot, where the native may have swept the file or reused the name, and it is not sent.
String _lastPortrait = ""
Float _lastPortraitAt = 0.0
; D134: real time of the card key press that is opening the card; the retry budget counts from it. 0.0 = no key.
Float _keyAt = 0.0

; The skills drawn right now, one per column, filled at every opening. A buy
; click names a column and a node index; the index is only meaningful against
; the tree of THAT skill, read again at click time (same order every call).
String[] _skills
Int _skillCount = 0
; Set by NextToBuy: the position in the rank chain of the highest owned rank, and that rank (None when none owned).
Int _lastHighest = -1
Perk _lastOwned = None
; Set by NodeState: the rank the player would take next (None when the chain is complete).
Perk _lastTarget = None

; D093: the last perks taken ("Skill:Perk^...", newest first, at most RecentMax) and, per skill, how many ranks of
; each node the player had at the last read of that tree. Both live in the save (StorageUtil on None).
String Property RecentKey  = "aot_card_recent" AutoReadOnly
String Property OwnedKey   = "aot_card_own_" AutoReadOnly
Int Property RecentMax     = 4 AutoReadOnly

Event OnInit()
	ApplyKey()
EndEvent

Function ApplyKey()
	{Registers the card key of the settings page; drops the previous registration when it changed. A save made
	before the option has _regKey = 0 and a registration of 65: that one is dropped too.}
	Int want = AoT_Core.CardKey()
	If _regKey == 0
		If want != 65
			UnregisterForKey(65)
		EndIf
	ElseIf _regKey != want
		UnregisterForKey(_regKey)
	EndIf
	Int before = _regKey
	_regKey = want
	RegisterForKey(want)
	; Always on (not behind AoT_Core.Log): once per boot and per key change, and it tells a run whether this
	; script is alive at all - a missing quest leaves no other trace.
	Debug.Trace("[AoT] Card: ApplyKey registered=" + want + " previous=" + before)
EndFunction

Event OnKeyDown(Int aiKeyCode)
	Float keyAt = Utility.GetCurrentRealTime()
	; Always on: only the card key and Esc are registered, so this fires on those presses only.
	Debug.Trace("[AoT] Card: OnKeyDown code=" + aiKeyCode + " cardKey=" + AoT_Core.CardKey() + " visible=" + _visible + " member=" + AoT_Core.IsMember())
	If aiKeyCode == EscCode
		If _visible || _awaitingHello
			ClosePanel("esc")
		Else
			; A registration left over from a save taken with the card open.
			UnregisterForKey(EscCode)
		EndIf
		Return
	EndIf
	If aiKeyCode != AoT_Core.CardKey()
		Return
	EndIf
	; Closing our own panel is never a game action: it comes BEFORE the menu
	; guard, which only gates opening (a focused view may read as menu mode).
	If _visible || _awaitingHello
		ClosePanel("key")
		Return
	EndIf
	; Always on: a silent Return here would leave a card that never opens with no trace at all.
	Bool inMenu = Utility.IsInMenuMode()
	Bool inText = UI.IsTextInputEnabled()
	If inMenu || inText
		Debug.Trace("[AoT] Card: OnKeyDown ignored, menuMode=" + inMenu + " textInput=" + inText)
		Return
	EndIf
	; D093: with a modifier chosen on the settings page, the key alone does not open (closing above never needs it)
	If !AoT_Core.CardModifierHeld()
		Debug.Trace("[AoT] Card: OnKeyDown ignored, modifier " + AoT_Core.CardModifierName(AoT_Core.CardModifier()) + " not held")
		Return
	EndIf
	; D077: the card belongs to the guild's members; the attendant enrols a new character
	If !AoT_Core.IsMember()
		Debug.Notification("You are not a member of the Adventurers Guild.")
		Return
	EndIf
	_keyAt = keyAt
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
	Debug.Trace("[AoT] Card: OpenCard pending=" + _pending + " ready=" + Lodestone.WebUIIsViewReady(ViewId))
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
	RegisterForKey(EscCode)
	; Truth is the question, not the saved flag: after a load the view is gone.
	If Lodestone.WebUIIsViewReady(ViewId)
		OpenNow()
		Return
	EndIf
	If _pending
		Debug.Trace("[AoT] Card: OpenCard ignored, an opening is already pending")
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
		UnregisterForKey(EscCode)
		Debug.Trace("[AoT] Card: WebUICreateView refused " + ViewPath)
		ShowPlain()
		Return
	EndIf
	Debug.Trace("[AoT] Card: WebUICreateView accepted " + ViewPath)
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
	_payloadSent = False
	RegisterForSingleUpdate(HelloSeconds)
	; D116: the capture comes BEFORE the show and the focus: the native refuses a pausing menu, and a focused view may
	; read as one. It is latent (a few frames), so the card may be closed (Esc) while it runs.
	CapturePortrait()
	If !_awaitingHello
		_portrait = ""
		Return
	EndIf
	Lodestone.WebUIShow(ViewId)
	_visible = True
	Push()
EndFunction

Function CapturePortrait()
	{Asks the native for a front portrait of the player. "" (first person, a menu, one already in flight, an old DLL)
	is asked again within the budget (D134); still "", the last good file of this boot goes instead, and without one
	the payload carries an empty c_portrait and the page draws the silhouette. No message to the player.}
	_portrait = ""
	Float t0 = Utility.GetCurrentRealTime()
	; The budget counts from the key press; an opening with no fresh key press (a direct OpenCard) counts from here.
	Float start = _keyAt
	_keyAt = 0.0
	If start <= 0.0 || start > t0 || t0 - start > HelloSeconds
		start = t0
	EndIf
	Int attempts = 0
	Bool closed = False
	If Lodestone.GetVersion() >= PortraitMinVersion
		Bool again = True
		While again
			Float a0 = Utility.GetCurrentRealTime()
			_portrait = Lodestone.CapturePlayerPortrait(PortraitFolder, PortraitSize)
			attempts += 1
			Float now = Utility.GetCurrentRealTime()
			again = False
			If _portrait == ""
				If !_awaitingHello
					closed = True
				ElseIf attempts <= PortraitRetries && (now - start) + (now - a0) <= PortraitBudget
					again = True
				EndIf
			EndIf
		EndWhile
	EndIf
	String shown
	If _portrait != ""
		shown = _portrait
		_lastPortrait = _portrait
		_lastPortraitAt = Utility.GetCurrentRealTime()
	ElseIf _lastPortrait != "" && _lastPortraitAt <= t0
		_portrait = _lastPortrait
		shown = "previous " + _lastPortrait
	Else
		shown = "refused"
	EndIf
	If closed
		shown += " closed"
	EndIf
	; Always on, like the key lines: it is the line the bench reads. One per opening.
	Debug.Trace("[AoT] Card: portrait " + shown + " attempts=" + attempts + " in " + (Utility.GetCurrentRealTime() - t0) + " s since key " + (Utility.GetCurrentRealTime() - start) + " s")
EndFunction

Function PollMissives()
	{D116: the open Missives contracts are read now, not at the next hourly poll, so a delivery just done does not show as
	in progress. Soft: without the Missives plugin there is no adapter and nothing changes.}
	AoT_MissivesAdapter ma = AoT_Attendant.MissivesAdapter()
	If ma
		ma.PollOpenContracts()
	EndIf
EndFunction

Function Push()
	PollMissives()
	AoT_Core.Log("[AoT] Card: push rank=" + RankLetter(AoT_Core.GetRank()) + " points=" + AoT_Core.GetPoints())
	String payload = BuildPayload()
	_portrait = ""
	Lodestone.WebUICall(ViewId, FnCard, payload)
	_payloadSent = True
EndFunction

Function PushTrees()
	{One call per column, so the card draws as each tree is read: reading the states
	costs native calls and the player should see the first column early. Stops when
	the panel closes in the middle.}
	If !PerkOk()
		Return
	EndIf
	_skillCount = ResolveTrees()
	; The page lays out its columns from this count before any tree arrives.
	Lodestone.WebUICall(ViewId, FnCard, "c_trees|" + _skillCount)
	Int slot = 0
	While slot < _skillCount && _visible
		Lodestone.WebUICall(ViewId, FnCard, BuildTree(slot))
		slot += 1
	EndWhile
EndFunction

Event OnCardAction(String asEvent, String asAction, Float afNum, Form akSender)
	String act = Unwrap(asAction)
	If StringUtil.Find(act, "ready") == 0
		If !_awaitingHello
			Return
		EndIf
		; D103: the page answers every payload with "ready", so the one that counts comes after ours
		If !_payloadSent
			AoT_Core.Log("[AoT] Card: early " + act + " ignored, payload not sent yet")
			Return
		EndIf
		_awaitingHello = False
		AoT_Core.Log("[AoT] Card: page said " + act)
		AoT_Core.Log("[AoT] Card: asking focus; menuMode=" + Utility.IsInMenuMode())
		If !Lodestone.WebUIFocusView(ViewId)
			; Refusal is a normal case: one view at a time in the whole load order.
			Debug.Trace("[AoT] Card: WebUIFocusView refused")
			HideQuiet()
			ShowPlain()
			Return
		EndIf
		RegisterForSingleUpdate(WatchdogSeconds)
		PushTrees()
	ElseIf StringUtil.Find(act, "close") == 0
		ClosePanel("page")
	ElseIf StringUtil.Find(act, "buy|") == 0
		String[] parts = PapyrusUtil.StringSplit(act, "|")
		If parts.Length == 3
			BuyPerk(parts[1] as Int, parts[2] as Int)
		EndIf
	EndIf
EndEvent

Event OnCardLog(String asEvent, String asText, Float afNum, Form akSender)
	AoT_Core.Log("[AoT] Card page: " + Unwrap(asText))
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
		UnregisterForKey(EscCode)
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
	AoT_Core.Log("[AoT] Card: focus lost, closing the panel")
	ClosePanel("watchdog")
EndEvent

Function HideQuiet()
	Lodestone.WebUIClearFocus(ViewId)
	Lodestone.WebUIHide(ViewId)
	_visible = False
	UnregisterForKey(EscCode)
EndFunction

Function ClosePanel(String asVia)
	{asVia says who closed it: "key", "esc", "page" or "watchdog". The line is written
	only when there was something to close.}
	Bool hadPanel = _visible || _awaitingHello
	_wanted = False
	_awaitingHello = False
	UnregisterForKey(EscCode)
	If !_visible
		If hadPanel
			AoT_Core.Log("[AoT] Card: closed by " + asVia)
		EndIf
		Return
	EndIf
	HideQuiet()
	AoT_Core.Log("[AoT] Card: closed by " + asVia)
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
	text += "hotkey|" + BrowserKeyCode(AoT_Core.CardKey()) + eol
	text += "c_level|" + Game.GetPlayer().GetLevel() + eol
	; D116: always sent, empty when there is no picture: the page goes back to the silhouette
	text += "c_portrait|" + _portrait + eol
	text += "c_joined|" + AoT_Core.JoinedDay() + eol
	; Fase 16 etapa 5 (D113): the hold of the first hall; absent until a talk with an attendant has stamped it
	String joinHold = StorageUtil.GetStringValue(None, "aot_join_hold", "")
	If joinHold != ""
		text += "c_hold|" + joinHold + eol
	EndIf
	If PerkOk()
		text += "c_perkok|1" + eol
		text += "c_pp|" + PerkPoints() + eol
	Else
		text += "c_perkok|0" + eol
	EndIf
	text += "c_rank|" + rank + eol
	text += "c_maxrank|" + AoT_Core.MaxRank() + eol
	String mat = JsonUtil.StringListGet(AoT_Core.TablePath(), "aot_rank_material", rank)
	; Always sent, empty when the table has no entry: the page keeps the keys of the last payload.
	text += "c_mat|" + mat + eol
	text += "c_ficha|" + RankFichas(rank) + eol
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
	; D093: the last perks taken as the save holds them now; each tree read below may add to it
	text += "c_recent|" + StorageUtil.GetStringValue(None, RecentKey, "") + eol
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

String Function RankFichas(Int aiRank)
	{What the rank already unlocks, for the card: "band:points,..." for every band whose draw weight is above zero at this rank. Both numbers come from points.json at open time.}
	String out = ""
	Int b = 0
	While b <= AoT_Core.MaxBand()
		If AoT_Core.BandWeight(aiRank, b) > 0
			If out != ""
				out += ","
			EndIf
			out += b + ":" + AoT_Core.PointsForBand(b)
		EndIf
		b += 1
	EndWhile
	Return out
EndFunction

; ---------------------------------------------------------------------------
; Perk trees. Every read here is a Lodestone native: one call returns a
; whole tree, but HasPerk / IsPerkEligible are one call per perk, so the states
; are timed and traced, and a tree is pushed as soon as it is read.
; ---------------------------------------------------------------------------

Bool Function PerkOk()
	Return Lodestone.GetVersion() >= PerkMinVersion
EndFunction

Int Function PerkPoints()
	{The engine's unspent points; -1 (player not available) reads as 0.}
	Int pp = Lodestone.GetPerkPoints()
	If pp < 0
		Return 0
	EndIf
	Return pp
EndFunction

Int Function ResolveTrees()
	{Fills _skills with the skills to draw and returns how many. The chosen skills
	(MCM, D016) whose tree is loaded; with none, the five of highest level.}
	_skills = new String[5]
	Int n = 0
	Int slot = 0
	While slot < AoT_Core.CardSlots()
		String chosen = AoT_Core.GetCardTree(slot)
		If chosen != ""
			If Lodestone.GetPerkTreePerks(chosen).Length > 0
				_skills[n] = chosen
				n += 1
			EndIf
		EndIf
		slot += 1
	EndWhile
	If n > 0
		Return n
	EndIf

	String[] names = new String[18]
	Int[] levels = new Int[18]
	Int found = 0
	Int i = 0
	While i < AoT_Core.SkillCount()
		String nm = AoT_Core.SkillEnumName(i)
		If Lodestone.GetPerkTreePerks(nm).Length > 0
			names[found] = nm
			levels[found] = AoT_Core.SkillLevel(nm)
			found += 1
		EndIf
		i += 1
	EndWhile
	While n < 5 && n < found
		Int best = -1
		Int j = 0
		While j < found
			If names[j] != ""
				If best < 0
					best = j
				ElseIf levels[j] > levels[best]
					best = j
				EndIf
			EndIf
			j += 1
		EndWhile
		_skills[n] = names[best]
		names[best] = ""
		n += 1
	EndWhile
	Return n
EndFunction

Perk Function NextToBuy(Perk akHead)
	{A tree node is the first rank of a perk; later ranks hang on GetNextPerk. The
	perk to buy next is the one after the highest rank owned, the head when none is
	owned, None when the chain is complete. Sets _lastHighest (-1 when none owned).}
	_lastHighest = -1
	_lastOwned = None
	Perk target = akHead
	Perk cur = akHead
	Int pos = 0
	While cur != None && pos < 16
		If Lodestone.HasPerk(cur)
			_lastHighest = pos
			_lastOwned = cur
			target = cur.GetNextPerk()
		EndIf
		cur = cur.GetNextPerk()
		pos += 1
	EndWhile
	Return target
EndFunction

Int Function NodeState(Perk akHead, Int aiPoints)
	{0 locked, 1 can buy, 2 owned (chain complete), 3 partly owned and the next rank
	can be bought, 4 partly owned and it cannot.}
	Perk target = NextToBuy(akHead)
	_lastTarget = target
	Int highest = _lastHighest
	If target == None
		Return 2
	EndIf
	Bool canBuy = False
	If aiPoints > 0
		canBuy = Lodestone.IsPerkEligible(target)
	EndIf
	If highest >= 0
		If canBuy
			Return 3
		EndIf
		Return 4
	EndIf
	If canBuy
		Return 1
	EndIf
	Return 0
EndFunction

String Function BuildTree(Int aiSlot)
	{One column: skill, level, and per-node parallel lists. Names are joined by "^",
	numbers by ",". The index of a node is its position in GetPerkTreePerks.}
	String skill = _skills[aiSlot]
	Float t0 = Utility.GetCurrentRealTime()
	Perk[] perks = Lodestone.GetPerkTreePerks(skill)
	Int[] gx = Lodestone.GetPerkTreeGridX(skill)
	Int[] gy = Lodestone.GetPerkTreeGridY(skill)
	String[] pn = Lodestone.GetPerkTreeNames(skill)
	Int[] edges = Lodestone.GetPerkTreeEdges(skill)
	Int pp = PerkPoints()
	Int n = perks.Length

	; D094: the fine position of each node (HNAM / VNAM), same order as the grid. Older Lodestone, or a list that does
	; not match the tree: no offset keys are sent and the card draws on the grid alone.
	; (an array is never assigned, compared or passed as None in Papyrus: a Bool says whether the lists are usable)
	Bool hasOffset = False
	Float[] hx
	Float[] vy
	If Lodestone.GetVersion() >= OffsetMinVersion
		hx = Lodestone.GetPerkTreeOffsetX(skill)
		vy = Lodestone.GetPerkTreeOffsetY(skill)
		hasOffset = hx.Length == n && vy.Length == n
	Else
		AoT_Core.Log("[AoT] Card: Lodestone below 1.44.0, no perk offsets (grid only)")
	EndIf

	; D093: what the save saw at the last read of this tree, to find the ranks taken since (in or out of the card)
	; (first read of this skill, or a tree whose node count changed: only the picture is written, no entry)
	String seen = StorageUtil.GetStringValue(None, OwnedKey + skill, "")
	String[] before = PapyrusUtil.StringSplit(seen, ",")
	Bool compare = seen != "" && before.Length == n && n > 0
	String xs = ""
	String ys = ""
	String hs = ""
	String vs = ""
	String ss = ""
	String nm = ""
	String ds = ""
	String own = ""
	Int i = 0
	While i < n
		If i > 0
			xs += ","
			ys += ","
			hs += ","
			vs += ","
			ss += ","
			nm += "^"
			ds += "^"
			own += ","
		EndIf
		xs += gx[i]
		ys += gy[i]
		If hasOffset
			hs += hx[i]
			vs += vy[i]
		EndIf
		ss += NodeState(perks[i], pp)
		nm += pn[i]
		; the rank the player would take now; with the chain complete, the last one taken
		Perk shown = _lastTarget
		If shown == None
			shown = _lastOwned
		EndIf
		If shown == None
			shown = perks[i]
		EndIf
		ds += OneLine(PO3_SKSEFunctions.GetDescription(shown))
		Int ranks = _lastHighest + 1
		own += ranks
		If compare
			If ranks > (before[i] as Int)
				AddRecent(skill, pn[i], ranks)
			EndIf
		EndIf
		i += 1
	EndWhile
	StorageUtil.SetStringValue(None, OwnedKey + skill, own)
	String es = ""
	i = 0
	While i < edges.Length
		If i > 0
			es += ","
		EndIf
		es += edges[i]
		i += 1
	EndWhile

	String eol = StringUtil.AsChar(10)
	String k = "t" + aiSlot + "_"
	String text = "c_pp|" + pp + eol
	text += k + "skill|" + skill + eol
	text += k + "lvl|" + AoT_Core.SkillLevel(skill) + eol
	text += k + "n|" + n + eol
	text += k + "x|" + xs + eol
	text += k + "y|" + ys + eol
	If hasOffset
		text += k + "hx|" + hs + eol
		text += k + "vy|" + vs + eol
	EndIf
	text += k + "s|" + ss + eol
	text += k + "names|" + nm + eol
	text += k + "e|" + es + eol
	text += k + "desc|" + ds + eol
	text += "c_recent|" + StorageUtil.GetStringValue(None, RecentKey, "") + eol
	AoT_Core.Log("[AoT] Card: tree " + skill + " nodes=" + n + " edges=" + (edges.Length / 2) + " points=" + pp + " owned=" + own + " read in " + (Utility.GetCurrentRealTime() - t0) + " s")
	If AoT_Core.DebugLogOn()
		; D093: the whole payload on one line, so a bench can replay what the game really sent
		Debug.Trace("[AoT] Card: payload " + PapyrusUtil.StringJoin(PapyrusUtil.StringSplit(text, eol), " ~ "))
	EndIf
	Return text
EndFunction

String Function OneLine(String asText)
	{The payload is one "key|value" line per fact and "^" joins the nodes: a line break or a "^" in a perk's text
	becomes a space.}
	String out = asText
	String[] bad = new String[3]
	bad[0] = StringUtil.AsChar(10)
	bad[1] = StringUtil.AsChar(13)
	bad[2] = "^"
	Int j = 0
	While j < 3
		If StringUtil.Find(out, bad[j]) >= 0
			out = PapyrusUtil.StringJoin(PapyrusUtil.StringSplit(out, bad[j]), " ")
		EndIf
		j += 1
	EndWhile
	Return out
EndFunction

String Function RankSuffix(Int aiRanks)
	{"" for the first rank; " II" to " X" after it, the number past ten.}
	If aiRanks < 2
		Return ""
	EndIf
	String[] roman = new String[11]
	roman[2] = " II"
	roman[3] = " III"
	roman[4] = " IV"
	roman[5] = " V"
	roman[6] = " VI"
	roman[7] = " VII"
	roman[8] = " VIII"
	roman[9] = " IX"
	roman[10] = " X"
	If aiRanks <= 10
		Return roman[aiRanks]
	EndIf
	Return " " + aiRanks
EndFunction

Function AddRecent(String asSkill, String asPerk, Int aiRanks)
	{D093: puts "Skill:Perk" in front of the last perks taken and keeps at most RecentMax.}
	String entry = asSkill + ":" + OneLine(asPerk) + RankSuffix(aiRanks)
	String old = StorageUtil.GetStringValue(None, RecentKey, "")
	String joined = entry
	If old != ""
		joined = entry + "^" + old
	EndIf
	String[] parts = PapyrusUtil.StringSplit(joined, "^")
	String out = ""
	Int j = 0
	While j < parts.Length && j < RecentMax
		If j > 0
			out += "^"
		EndIf
		out += parts[j]
		j += 1
	EndWhile
	StorageUtil.SetStringValue(None, RecentKey, out)
	AoT_Core.Log("[AoT] Card: recent + " + entry)
EndFunction

Function BuyPerk(Int aiSlot, Int aiIndex)
	{A click on a node the page drew as buyable. The page decides nothing: the state
	is read again here, and TryBuyPerk re-checks everything. The trace line carries
	the points before and after the buy, and whether the perk is owned.}
	If !_visible || !PerkOk()
		Return
	EndIf
	If aiSlot < 0 || aiSlot >= _skillCount
		Debug.Trace("[AoT] Card: buy refused, bad column " + aiSlot)
		Return
	EndIf
	String skill = _skills[aiSlot]
	Perk[] perks = Lodestone.GetPerkTreePerks(skill)
	If aiIndex < 0 || aiIndex >= perks.Length
		Debug.Trace("[AoT] Card: buy refused, bad node " + aiIndex + " in " + skill)
		Return
	EndIf
	Perk target = NextToBuy(perks[aiIndex])
	Int before = PerkPoints()
	Bool bought = False
	If target != None
		bought = Lodestone.TryBuyPerk(target)
	EndIf
	Int after = PerkPoints()
	Bool owned = False
	If target != None
		owned = Lodestone.HasPerk(target)
	EndIf
	AoT_Core.Log("[AoT] Card: buy skill=" + skill + " node=" + aiIndex + " perk=" + target + " bought=" + bought + " points " + before + " -> " + after + " owned=" + owned)
	If _visible
		Lodestone.WebUICall(ViewId, FnCard, BuildTree(aiSlot))
	EndIf
EndFunction

Function ShowPlain()
	{Where the panel is not possible (no backend, old DLL, focus refused, page
	dead): the same facts as a message box, so the key never ends in nothing.}
	String rankLetter = RankLetter(AoT_Core.GetRank())
	String text = "Adventurer card - rank " + rankLetter + ", level " + Game.GetPlayer().GetLevel() + ". Points " + AoT_Core.GetPoints()
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
