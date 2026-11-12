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
; 1023000 (1.23.0) is where the Meridian UI level left the mod root (see
; IM_Core.WebUIMinVersion); 1022000 (1.22.0) is where WebUIFocusView exists.
Int Property WebUIMinVersion      = 1023000 AutoReadOnly
Int Property WebUIFocusMinVersion = 1022000 AutoReadOnly
; 1037000 (Nexus 1.6.0) is the perk module (GetPerkPoints, TryBuyPerk, GetPerkTree*).
; Below it the card opens without trees and says why.
Int Property PerkMinVersion       = 1037000 AutoReadOnly

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

; The skills drawn right now, one per column, filled at every opening. A buy
; click names a column and a node index; the index is only meaningful against
; the tree of THAT skill, read again at click time (same order every call).
String[] _skills
Int _skillCount = 0
; Set by NextToBuy: the position in the rank chain of the highest owned rank.
Int _lastHighest = -1

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
	_regKey = want
	RegisterForKey(want)
EndFunction

Event OnKeyDown(Int aiKeyCode)
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
	If Utility.IsInMenuMode() || UI.IsTextInputEnabled()
		Return
	EndIf
	; D077: the card belongs to the guild's members; the attendant enrols a new character
	If !AoT_Core.IsMember()
		Debug.Notification("You are not a member of the Adventurers Guild.")
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
	RegisterForKey(EscCode)
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
		UnregisterForKey(EscCode)
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
	AoT_Core.Log("[AoT] Card: push rank=" + RankLetter(AoT_Core.GetRank()) + " points=" + AoT_Core.GetPoints())
	Lodestone.WebUICall(ViewId, FnCard, BuildPayload())
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
	text += "c_joined|" + AoT_Core.JoinedDay() + eol
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
	Perk target = akHead
	Perk cur = akHead
	Int pos = 0
	While cur != None && pos < 16
		If Lodestone.HasPerk(cur)
			_lastHighest = pos
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

	String xs = ""
	String ys = ""
	String ss = ""
	String nm = ""
	Int i = 0
	While i < n
		If i > 0
			xs += ","
			ys += ","
			ss += ","
			nm += "^"
		EndIf
		xs += gx[i]
		ys += gy[i]
		ss += NodeState(perks[i], pp)
		nm += pn[i]
		i += 1
	EndWhile
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
	text += k + "s|" + ss + eol
	text += k + "names|" + nm + eol
	text += k + "e|" + es + eol
	AoT_Core.Log("[AoT] Card: tree " + skill + " nodes=" + n + " edges=" + (edges.Length / 2) + " points=" + pp + " read in " + (Utility.GetCurrentRealTime() - t0) + " s")
	Return text
EndFunction

Function BuyPerk(Int aiSlot, Int aiIndex)
	{A click on a node the page drew as buyable. The page decides nothing: the state
	is read again here, and TryBuyPerk re-checks everything. The trace line carries
	the points before and after the buy, and whether the perk is owned.}
	If !_visible || !PerkOk() || _skills == None
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
