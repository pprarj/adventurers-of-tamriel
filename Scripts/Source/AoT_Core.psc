Scriptname AoT_Core Hidden
{Adventurers of Tamriel core: rank, points and the single global wallet.
Global functions only. State lives in the PapyrusUtil co-save (StorageUtil);
the scoring table lives in Data/Config/AdventurersOfTamriel/points.json (JsonUtil).
The persisted format is irreversible: see DEVELOPMENT.md, "Persisted state".}

; ---------------------------------------------------------------------------
; Identifiers
; ---------------------------------------------------------------------------
; Ranks: 0 F, 1 E, 2 D, 3 C, 4 B, 5 A, 6 S.
; Bands: 0 Low, 1 Med, 2 High, 3 VeryHigh, 4 own rank-A contract, 5 own rank-S contract.
; Contract states: 1 open, 2 completed, 3 abandoned, 4 expired, 5 void (never stood, no points; D025).

Int Function SchemaCode() Global
	{Persisted-format version this build writes.}
	Return 2
EndFunction

String Function TablePath() Global
	{JsonUtil path of the scoring table, relative to Data/SKSE/Plugins/StorageUtilData.}
	Return "../../../Config/AdventurersOfTamriel/points"
EndFunction

Int Function MaxRank() Global
	Return 6
EndFunction

Int Function MaxBand() Global
	Return 5
EndFunction

; ---------------------------------------------------------------------------
; Reads
; ---------------------------------------------------------------------------

Int Function SchemaVersion() Global
	{Schema stored in this save; 0 when the core never wrote anything.}
	Return StorageUtil.GetIntValue(None, "aot_schema", 0)
EndFunction

Int Function GetRank() Global
	{Current rank, 0 (F) to 6 (S). Global: one wallet for every branch.}
	Return StorageUtil.GetIntValue(None, "aot_rank", 0)
EndFunction

Int Function GetAdventurerRank(Actor akActor) Global
	{Guild rank of any actor, 0 (F) to 6 (S), or -1 when the actor has no rank (not a member, None, or the
	adventurers plugin is not loaded). -1 is never F: F is 0. An NPC carries its rank as its rank in the
	guild faction (AoT_GuildFaction), so a mod without this script can read it with GetFactionRank. The player
	is not in that faction (D-14: one wallet); for the player this returns GetRank() once the player has
	joined (the first contract stamps the join day), and -1 before that.}
	If akActor == None
		Return -1
	EndIf
	If akActor == Game.GetPlayer()
		; D077: the player is a member once the attendant has enrolled them (or an older save already used the guild)
		If IsMember()
			Return GetRank()
		EndIf
		Return -1
	EndIf
	Faction f = Game.GetFormFromFile(0x000E36, "AdventurersOfTamriel.esp") as Faction
	If f == None
		Return -1
	EndIf
	Int r = akActor.GetFactionRank(f)
	If r < 0 || r > 6
		Return -1
	EndIf
	Return r
EndFunction

Bool Function IsMember() Global
	{D077: true when the player is a guild member. A new character becomes one at the attendant ("aot_member" = 1,
	JoinGuild). A save made before that topic existed counts as a member when it already used the guild: any
	points, any rank above F, or any contract ever opened. The join day alone does not count: reading the card
	stamps it (JoinedDay), so it proves nothing about joining.}
	If StorageUtil.GetIntValue(None, "aot_member", 0) == 1
		Return True
	EndIf
	If StorageUtil.GetIntValue(None, "aot_points", 0) > 0 || StorageUtil.GetIntValue(None, "aot_rank", 0) > 0
		Return True
	EndIf
	Return ContractCount() > 0
EndFunction

Bool Function JoinGuild() Global
	{D077: enrols the player at rank F. True when this call enrolled them; false when they already were a member
	or the save cannot be written. Stamps the join day; points and rank stay as they are (0 and F for a new character).}
	If IsMember()
		Return False
	EndIf
	If !_CanWrite()
		Return False
	EndIf
	StorageUtil.SetIntValue(None, "aot_member", 1)
	JoinedDay()
	InvalidateBoards()
	Return True
EndFunction

Int Function GetPoints() Global
	{Points earned inside the current rank. Never below 0.}
	Return StorageUtil.GetIntValue(None, "aot_points", 0)
EndFunction

Int Function JoinedDay() Global
	{Game day the player joined the guild (D015). A save that never stamped it gets
	today's day on this first read, and keeps it from then on.}
	If StorageUtil.HasIntValue(None, "aot_joined_day")
		Return StorageUtil.GetIntValue(None, "aot_joined_day", 0)
	EndIf
	Int today = Utility.GetCurrentGameTime() as Int
	If _CanWrite()
		StorageUtil.SetIntValue(None, "aot_joined_day", today)
	EndIf
	Return today
EndFunction

Int Function CardSlots() Global
	{How many perk trees the card shows at most.}
	Return 5
EndFunction

Int Function SkillCount() Global
	{The 18 skills, by the engine's enum names (the form Lodestone's perk-tree
	functions take).}
	Return 18
EndFunction

String Function SkillEnumName(Int aiIndex) Global
	{Engine enum name of skill aiIndex (0 to 17); "" for a bad index.}
	If aiIndex == 0
		Return "OneHanded"
	ElseIf aiIndex == 1
		Return "TwoHanded"
	ElseIf aiIndex == 2
		Return "Marksman"
	ElseIf aiIndex == 3
		Return "Block"
	ElseIf aiIndex == 4
		Return "Smithing"
	ElseIf aiIndex == 5
		Return "HeavyArmor"
	ElseIf aiIndex == 6
		Return "LightArmor"
	ElseIf aiIndex == 7
		Return "Pickpocket"
	ElseIf aiIndex == 8
		Return "Lockpicking"
	ElseIf aiIndex == 9
		Return "Sneak"
	ElseIf aiIndex == 10
		Return "Alchemy"
	ElseIf aiIndex == 11
		Return "Speechcraft"
	ElseIf aiIndex == 12
		Return "Alteration"
	ElseIf aiIndex == 13
		Return "Conjuration"
	ElseIf aiIndex == 14
		Return "Destruction"
	ElseIf aiIndex == 15
		Return "Illusion"
	ElseIf aiIndex == 16
		Return "Restoration"
	ElseIf aiIndex == 17
		Return "Enchanting"
	EndIf
	Return ""
EndFunction

Int Function SkillLevel(String asSkill) Global
	{The player's current level in a skill, by enum name.}
	Return Game.GetPlayer().GetActorValue(asSkill) as Int
EndFunction

String Function GetCardTree(Int aiSlot) Global
	{The skill (engine enum name, e.g. "OneHanded") the player put in slot aiSlot of the
	card; "" when the slot is empty (the card then fills it, D016).}
	If aiSlot < 0 || aiSlot >= CardSlots()
		Return ""
	EndIf
	Return StorageUtil.GetStringValue(None, "aot_card_tree_" + aiSlot, "")
EndFunction

Bool Function SetCardTree(Int aiSlot, String asSkill) Global
	{Puts a skill in a slot; "" empties it. False when the slot is bad, the same skill
	already sits in another slot, or the save is newer than this build.}
	If aiSlot < 0 || aiSlot >= CardSlots()
		Return False
	EndIf
	If !_CanWrite()
		Return False
	EndIf
	If asSkill != ""
		Int i = 0
		While i < CardSlots()
			If i != aiSlot && GetCardTree(i) == asSkill
				Return False
			EndIf
			i += 1
		EndWhile
	EndIf
	StorageUtil.SetStringValue(None, "aot_card_tree_" + aiSlot, asSkill)
	Return True
EndFunction

Int Function LadderStep(Int aiRank) Global
	{Points needed inside aiRank to become eligible for the next rank; -1 at S or on a table error.}
	If aiRank < 0 || aiRank >= MaxRank()
		Return -1
	EndIf
	If JsonUtil.IntListCount(TablePath(), "aot_ladder") <= aiRank
		Debug.Trace("[AoT] table: aot_ladder missing or short")
		Return -1
	EndIf
	Return JsonUtil.IntListGet(TablePath(), "aot_ladder", aiRank)
EndFunction

Bool Function IsPromotionEligible() Global
	{Points enable, the exam promotes: true when the points reached the ladder step of the current rank.}
	Int stepNeeded = LadderStep(GetRank())
	Return stepNeeded >= 0 && GetPoints() >= stepNeeded
EndFunction

Int Function ExamKind(Int aiRank) Global
	{How the promotion out of aiRank is decided (the ladder cut, Fase 8, D-18): 0 no exam, 1 exam in the
	exam room, 2 the emergency call (A to S, Fase 9). -1 on a table error. Data, not code: points.json.}
	If aiRank < 0 || aiRank >= MaxRank()
		Return -1
	EndIf
	If JsonUtil.IntListCount(TablePath(), "aot_exam_required") <= aiRank
		Debug.Trace("[AoT] table: aot_exam_required missing or short")
		Return -1
	EndIf
	Return JsonUtil.IntListGet(TablePath(), "aot_exam_required", aiRank)
EndFunction

Bool Function CanOfferExam() Global
	{True when the attendant may offer the room exam: points enable it and the cut asks for one.}
	Return IsPromotionEligible() && ExamKind(GetRank()) == 1
EndFunction

Bool Function PromoteWithoutExam() Global
	{The ladder steps below the cut: the attendant promotes straight away. Same guard as the exam.}
	If !IsPromotionEligible() || ExamKind(GetRank()) != 0
		Return False
	EndIf
	Return Promote()
EndFunction

Int Function PointsForBand(Int aiBand) Global
	{Points a completed contract of this band is worth; -1 on a bad band or a table error.}
	If aiBand < 0 || aiBand > MaxBand()
		Return -1
	EndIf
	If JsonUtil.IntListCount(TablePath(), "aot_points_by_band") <= aiBand
		Debug.Trace("[AoT] table: aot_points_by_band missing or short")
		Return -1
	EndIf
	Int base = JsonUtil.IntListGet(TablePath(), "aot_points_by_band", aiBand)
	Return ScaleByOption(base, PointsMultiplier())
EndFunction

Int Function GoldForBand(Int aiBand) Global
	{Fase 14 etapa 2: gold the attendant pays when a contract of this band is reported (aot_gold_by_band of the table);
	0 on a bad band or a missing entry.}
	If aiBand < 0 || aiBand > MaxBand()
		Return 0
	EndIf
	If JsonUtil.IntListCount(TablePath(), "aot_gold_by_band") <= aiBand
		Debug.Trace("[AoT] table: aot_gold_by_band missing or short")
		Return 0
	EndIf
	Return JsonUtil.IntListGet(TablePath(), "aot_gold_by_band", aiBand)
EndFunction

; ---------------------------------------------------------------------------
; Options (D077): the six values of the settings page. They live in the save (StorageUtil, no key
; object), are read at the moment of use and never copied into a property. Missing key = the default.
; ---------------------------------------------------------------------------

Int Function CardKey() Global
	{DirectInput scancode of the card key; 65 (F7) by default.}
	Int k = StorageUtil.GetIntValue(None, "aot_opt_card_key", 65)
	If k < 1 || k > 255
		Return 65
	EndIf
	Return k
EndFunction

Int Function CardModifier() Global
	{D093: the modifier the card key needs to OPEN the card: 0 none (default), 1 Shift, 2 Ctrl, 3 Alt.}
	Int m = StorageUtil.GetIntValue(None, "aot_opt_card_mod", 0)
	If m < 0 || m > 3
		Return 0
	EndIf
	Return m
EndFunction

Bool Function CardModifierHeld() Global
	{D093: True when the modifier of CardModifier() is held, left or right; always True with none.}
	Int m = CardModifier()
	If m == 1
		Return Input.IsKeyPressed(42) || Input.IsKeyPressed(54)
	ElseIf m == 2
		Return Input.IsKeyPressed(29) || Input.IsKeyPressed(157)
	ElseIf m == 3
		Return Input.IsKeyPressed(56) || Input.IsKeyPressed(184)
	EndIf
	Return True
EndFunction

String Function CardModifierName(Int aiMod) Global
	If aiMod == 1
		Return "Shift"
	ElseIf aiMod == 2
		Return "Ctrl"
	ElseIf aiMod == 3
		Return "Alt"
	EndIf
	Return "no modifier"
EndFunction

Float Function FeeMultiplier() Global
	{Multiplier on the fee of every band, 0 to 3; 1.0 by default. 0 = no fee at all.}
	Float m = StorageUtil.GetFloatValue(None, "aot_opt_fee_mult", 1.0)
	If m < 0.0
		Return 0.0
	ElseIf m > 3.0
		Return 3.0
	EndIf
	Return m
EndFunction

Float Function PointsMultiplier() Global
	{Multiplier on the points of a completed contract, 0.25 to 3; 1.0 by default.}
	Float m = StorageUtil.GetFloatValue(None, "aot_opt_points_mult", 1.0)
	If m < 0.25
		Return 0.25
	ElseIf m > 3.0
		Return 3.0
	EndIf
	Return m
EndFunction

Int Function BoardOffers() Global
	{Contracts the board offers per refresh, 3 to 15; 5 by default. The key aot_board_offers of the save wins over
	the one of contracts.json (D077: the settings page writes it).}
	Int n = StorageUtil.GetIntValue(None, "aot_board_offers", 0)
	If n <= 0
		n = JsonUtil.GetIntValue("../../../Config/AdventurersOfTamriel/contracts", "aot_board_offers", 5)
	EndIf
	If n < 3
		Return 3
	ElseIf n > 15
		Return 15
	EndIf
	Return n
EndFunction

Function InvalidateBoards() Global
	{Fase 14 etapa 2 (B2b): what the boards may offer changed (a fee paid, the join, a promotion). Every board refreshes
	at its next check, on the same game day.}
	StorageUtil.AdjustIntValue(None, "aot_board_epoch", 1)
EndFunction

Bool Function SuppressVanillaBounties() Global
	{D-32 switch, on by default. Stored by the settings page; SyncD32 copies it to AoT_D32Suppress.}
	Return StorageUtil.GetIntValue(None, "aot_opt_d32", 1) != 0
EndFunction

Function SyncD32() Global
	{Fase 14 etapa 2 (D082): the eight vanilla lines that hand out BQ01-04 (steward and innkeeper) show only while the
	global AoT_D32Suppress (main plugin 0xF5E, 1 by default) is 0. It follows the switch.}
	GlobalVariable g = Game.GetFormFromFile(0x000F5E, "AdventurersOfTamriel.esp") as GlobalVariable
	If !g
		Return
	EndIf
	Float v = 0.0
	If SuppressVanillaBounties()
		v = 1.0
	EndIf
	If g.GetValue() != v
		g.SetValue(v)
		Log("[AoT] D-32: AoT_D32Suppress -> " + v)
	EndIf
EndFunction

Bool Function HallSoundOn() Global
	{D124: the murmur of people talking in the halls, on by default. Stored by the settings page; SyncHallSound copies
	it to AoT_HallSoundOn.}
	Return StorageUtil.GetIntValue(None, "aot_opt_hall_sound", 1) != 0
EndFunction

Function SyncHallSound(Bool abRestart = False) Global
	{D124: the murmur's sound descriptor (AoT_HallCrowdLPSD, main plugin 0xF69) plays only while the global
	AoT_HallSoundOn (0xF68, 1 by default) is 1, the condition of the descriptor. The engine reads that condition when the
	marker starts, so with abRestart the marker of the hall the player stands in (a ref of AoT_HallCrowdLP 0xF6A, the
	closest within 4096 units; every hall has one) is disabled and enabled again once the menu is closed.}
	GlobalVariable g = Game.GetFormFromFile(0x000F68, "AdventurersOfTamriel.esp") as GlobalVariable
	If !g
		Return
	EndIf
	Float v = 0.0
	If HallSoundOn()
		v = 1.0
	EndIf
	If g.GetValue() != v
		g.SetValue(v)
		Log("[AoT] hall sound: AoT_HallSoundOn -> " + v)
	EndIf
	If !abRestart
		Return
	EndIf
	Form base = Game.GetFormFromFile(0x000F6A, "AdventurersOfTamriel.esp")
	ObjectReference m = None
	If base
		m = Game.FindClosestReferenceOfTypeFromRef(base, Game.GetPlayer(), 4096.0)
	EndIf
	If !m
		Log("[AoT] hall sound: no marker near the player, AoT_HallSoundOn=" + v)
		Return
	EndIf
	m.DisableNoWait()
	Utility.Wait(0.5)
	m.EnableNoWait()
	Log("[AoT] hall sound: marker " + m + " restarted, AoT_HallSoundOn=" + g.GetValue())
EndFunction

Bool Function DebugLogOn() Global
	{Off by default: the guild's informational lines go to the Papyrus log only when this is on.}
	Return StorageUtil.GetIntValue(None, "aot_opt_debug", 0) != 0
EndFunction

Function Log(String asText) Global
	{Informational line of the guild: written only when the debug option is on. Errors keep Debug.Trace.}
	If DebugLogOn()
		Debug.Trace(asText)
	EndIf
EndFunction

Int Function ScaleByOption(Int aiValue, Float afMult) Global
	{aiValue * afMult rounded to the nearest whole; a positive value never rounds down to 0 unless the multiplier is 0.}
	If aiValue <= 0 || afMult <= 0.0
		Return 0
	EndIf
	Int r = Math.Floor(aiValue * afMult + 0.5) as Int
	If r < 1
		r = 1
	EndIf
	Return r
EndFunction

Int Function BandWeight(Int aiRank, Int aiBand) Global
	{Draw weight of a band for a rank, from the table; -1 on bad arguments or a table error.}
	If aiRank < 0 || aiRank > MaxRank() || aiBand < 0 || aiBand > MaxBand()
		Return -1
	EndIf
	String listKey = "aot_band_weight_rank" + aiRank
	If JsonUtil.IntListCount(TablePath(), listKey) <= aiBand
		Debug.Trace("[AoT] table: " + listKey + " missing or short")
		Return -1
	EndIf
	Return JsonUtil.IntListGet(TablePath(), listKey, aiBand)
EndFunction

Bool Function IsBandPaid(Int aiBand) Global
	{True when the fee of this band was paid.}
	Return StorageUtil.IntListHas(None, "aot_bands_paid", aiBand)
EndFunction

Int Function ContractCount() Global
	{Contracts ever opened. Ids run from 1 to this number.}
	Return StorageUtil.IntListCount(None, "aot_contracts")
EndFunction

Int Function ContractState(Int aiId) Global
	{1 open, 2 completed, 3 abandoned, 4 expired, 5 void; 0 for an unknown id.}
	Int entry = _Entry(aiId)
	If entry <= 0
		Return 0
	EndIf
	Return entry % 8
EndFunction

Int Function ContractBand(Int aiId) Global
	{Band of the contract; -1 for an unknown id.}
	Int entry = _Entry(aiId)
	If entry <= 0
		Return -1
	EndIf
	Return (entry / 8) % 8
EndFunction

Int Function ContractDelta(Int aiId) Global
	{Points the contract actually applied, after the floor; 0 while open or for an unknown id.}
	Int entry = _Entry(aiId)
	If entry <= 0
		Return 0
	EndIf
	Return (entry / 64) - 1024
EndFunction

Int Function FindOpenContract(Quest akQuest) Global
	{Id of the open contract of this quest; 0 when it has none.}
	If !akQuest
		Return 0
	EndIf
	Int id = StorageUtil.GetIntValue(akQuest, "aot_contract_id", 0)
	If id > 0 && ContractState(id) == 1
		Return id
	EndIf
	Return 0
EndFunction

; ---------------------------------------------------------------------------
; Writes
; ---------------------------------------------------------------------------

Int Function OpenContract(Quest akQuest, Int aiBand) Global
	{Registers a contract the player took. Returns its id (1 or more), or 0 on error.
	akQuest may be None for a contract without a quest. Opening a quest whose contract is
	still open returns that same id.}
	If aiBand < 0 || aiBand > MaxBand()
		Debug.Trace("[AoT] OpenContract: bad band " + aiBand)
		Return 0
	EndIf
	If !_CanWrite()
		Return 0
	EndIf
	Int openId = FindOpenContract(akQuest)
	If openId > 0
		Return openId
	EndIf
	JoinedDay()
	Int idx = StorageUtil.IntListAdd(None, "aot_contracts", _Pack(1, aiBand, 0), True)
	If idx < 0
		Debug.Trace("[AoT] OpenContract: ledger append failed")
		Return 0
	EndIf
	Int id = idx + 1
	StorageUtil.IntListAdd(None, "aot_open", id, False)
	If akQuest
		StorageUtil.SetIntValue(akQuest, "aot_contract_id", id)
	EndIf
	; Fase 15 etapa 12 (D107): the abandon list's quest restarts with the new contract
	AoT_Attendant.MarkListDirty("open id=" + id)
	Return id
EndFunction

Bool Function CompleteContract(Int aiId) Global
	{Completed: adds the band's points. Acts once per contract, and only while it is open.}
	Return _Close(aiId, 2)
EndFunction

Bool Function AbandonContract(Int aiId) Global
	{Explicit abandon at the attendant: applies the table's abandon delta, floored. Once per contract.}
	Return _Close(aiId, 3)
EndFunction

Bool Function ExpireContract(Int aiId) Global
	{The other mod's deadline passed: applies the table's expired delta, floored. Once per contract.}
	Return _Close(aiId, 4)
EndFunction

Bool Function VoidContract(Int aiId) Global
	{The contract never stood (its quest was cleaned up before anything happened): closes it
	with no points and no loss. Once per contract.}
	Return _Close(aiId, 5)
EndFunction

Int Function AdjustPoints(Int aiDelta) Global
	{Low-level: adds aiDelta to the points, floored. NOT idempotent - contract events
	go through the contract functions. Returns the delta actually applied.}
	If !_CanWrite()
		Return 0
	EndIf
	Return _Apply(aiDelta)
EndFunction

Bool Function MarkBandPaid(Int aiBand) Global
	{Records the fee of a band as paid. True when it was not paid before.}
	If aiBand < 0 || aiBand > MaxBand()
		Debug.Trace("[AoT] MarkBandPaid: bad band " + aiBand)
		Return False
	EndIf
	If !_CanWrite()
		Return False
	EndIf
	If StorageUtil.IntListHas(None, "aot_bands_paid", aiBand)
		Return False
	EndIf
	Return StorageUtil.IntListAdd(None, "aot_bands_paid", aiBand, False) >= 0
EndFunction

Bool Function Promote() Global
	{The exam's outcome: rank + 1 and the points restart inside the new rank.
	Only when eligible. This is the only writer of the rank, and it never lowers it.}
	If !_CanWrite()
		Return False
	EndIf
	Int current = GetRank()
	If current >= MaxRank() || !IsPromotionEligible()
		Return False
	EndIf
	StorageUtil.SetIntValue(None, "aot_rank", current + 1)
	StorageUtil.SetIntValue(None, "aot_points", 0)
	InvalidateBoards()
	; Public contract 1.0: tell other mods. numArg = the new rank (0 = F ... 6 = S), strArg empty.
	Game.GetPlayer().SendModEvent("AoT_Promoted", "", (current + 1) as Float)
	Return True
EndFunction

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

Function _MigrateBootContract() Global
	{D025: up to the build that opened it on every boot, the first contract (the Whiterun
	bandit camp) opened by itself, with no offer. Such a contract is still open with its
	quest short of the hunt stage (20); it is closed void, once, at the first write.
	The flag is set first: _Close writes, and a write comes back through here.}
	If StorageUtil.HasIntValue(None, "aot_boot_contract_checked")
		Return
	EndIf
	StorageUtil.SetIntValue(None, "aot_boot_contract_checked", 1)
	Quest q = Game.GetFormFromFile(0x000D97, "AdventurersOfTamriel.esp") as Quest
	If !q
		Return
	EndIf
	Int id = FindOpenContract(q)
	If id > 0 && !q.IsStageDone(20)
		Bool ok = _Close(id, 5)
		Debug.Trace("[AoT] boot-opened contract id=" + id + " closed void: " + ok)
	EndIf
EndFunction

Bool Function _CanWrite() Global
	{Stamps the schema on the first write; refuses to write over a newer format.}
	Int stored = StorageUtil.GetIntValue(None, "aot_schema", 0)
	If stored == 0
		StorageUtil.SetIntValue(None, "aot_schema", SchemaCode())
		_MigrateBootContract()
		Return True
	EndIf
	If stored > SchemaCode()
		Debug.Trace("[AoT] save schema " + stored + " is newer than this build (" + SchemaCode() + "): not writing")
		Return False
	EndIf
	If stored < SchemaCode()
		; Migration 1 -> 2 (D015): only added keys (aot_joined_day, aot_card_tree_N); nothing
		; that version 1 wrote changes meaning, so the migration is the stamp itself.
		StorageUtil.SetIntValue(None, "aot_schema", SchemaCode())
		Debug.Trace("[AoT] save schema " + stored + " migrated to " + SchemaCode())
	EndIf
	_MigrateBootContract()
	Return True
EndFunction

Int Function _Floor() Global
	Int floorValue = JsonUtil.GetIntValue(TablePath(), "aot_floor", 0)
	If floorValue < 0
		Return 0
	EndIf
	Return floorValue
EndFunction

Int Function _Apply(Int aiDelta) Global
	{Adds aiDelta and cuts at the floor. Returns the delta actually applied.}
	Int floorValue = _Floor()
	Int after = StorageUtil.AdjustIntValue(None, "aot_points", aiDelta)
	If after < floorValue
		StorageUtil.SetIntValue(None, "aot_points", floorValue)
		Return aiDelta + (floorValue - after)
	EndIf
	Return aiDelta
EndFunction

Int Function _Pack(Int aiState, Int aiBand, Int aiDelta) Global
	{One ledger entry: state + 8 * band + 64 * (delta + 1024).}
	Int clamped = aiDelta
	If clamped < -1024
		clamped = -1024
	ElseIf clamped > 1023
		clamped = 1023
	EndIf
	Return aiState + 8 * aiBand + 64 * (clamped + 1024)
EndFunction

Int Function _Entry(Int aiId) Global
	If aiId < 1 || aiId > ContractCount()
		Return 0
	EndIf
	Return StorageUtil.IntListGet(None, "aot_contracts", aiId - 1)
EndFunction

Bool Function _Close(Int aiId, Int aiNewState) Global
	{Moves an open contract to a final state and applies its delta, once.}
	Int entry = _Entry(aiId)
	If entry <= 0 || entry % 8 != 1
		Return False
	EndIf
	If !_CanWrite()
		Return False
	EndIf
	Int band = (entry / 8) % 8
	Int delta = 0
	If aiNewState == 2
		delta = PointsForBand(band)
		If delta < 0
			Return False
		EndIf
	ElseIf aiNewState == 3
		delta = JsonUtil.GetIntValue(TablePath(), "aot_delta_abandon", 9999)
	ElseIf aiNewState == 5
		delta = 0
	Else
		delta = JsonUtil.GetIntValue(TablePath(), "aot_delta_expired", 9999)
	EndIf
	If delta == 9999
		Debug.Trace("[AoT] table: loss delta missing")
		Return False
	EndIf
	; Claim the contract: IntListRemove is one native call that returns how many instances it
	; removed, so of two callers racing on the same id only one sees 1. IntListSet cannot do
	; this: it returns the value just written, not the previous one.
	If StorageUtil.IntListRemove(None, "aot_open", aiId, True) < 1
		Return False
	EndIf
	Int applied = _Apply(delta)
	StorageUtil.IntListSet(None, "aot_contracts", aiId - 1, _Pack(aiNewState, band, applied))
	; Fase 15 etapa 12 (D107): completed, abandoned, expired or void, the contract leaves the abandon list
	AoT_Attendant.MarkListDirty("close id=" + aiId + " state=" + aiNewState)
	Return True
EndFunction
