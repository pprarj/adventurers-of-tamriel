Scriptname AoT_Crystals Hidden
{Fase 17 etapa 6 (D143): creature crystals. Global functions only, no state of its own: the table is
Config/AdventurersOfTamriel/crystals.json, the count per contract lives in StorageUtil on the contract quest.
- The Boss of an open contract always drops one large crystal of the level of the contract's band (GiveLarge,
  from the Target alias and, in the two-phase contracts, from the Risen alias).
- The other kills: while one of our contracts is open, its note alias (4) is registered for the PO3 kill
  event (Arm, from TryOpen; Disarm, from Finish). A kill counts when the victim is in the contract's Dungeon,
  the killer is the player or a follower (or a summon of either), and, with aot_crystal_creature_only, the
  victim is not ActorTypeNPC. With the band's chance it gets 1 to 3 small crystals, never past the band's cap
  per contract. A dragon gets one large instead (aot_crystal_large_on_dragon).
- The attendant takes every crystal the player carries and pays the table's value (TradeIn, action 16).
The crystal goes to the corpse (AddItem on the victim): the player loots it.}

String Function TablePath() Global
	{JsonUtil path of the crystal table, relative to Data/SKSE/Plugins/StorageUtilData.}
	Return "../../../Config/AdventurersOfTamriel/crystals"
EndFunction

Int Function _BandInt(String asKey, Int aiBand, Int aiMissing) Global
	String path = TablePath()
	If aiBand < 0 || JsonUtil.IntListCount(path, asKey) <= aiBand
		Return aiMissing
	EndIf
	Return JsonUtil.IntListGet(path, asKey, aiBand)
EndFunction

Int Function Level(Int aiBand) Global
	{1 to 4, from aot_crystal_level_by_band; 0 when the table has no level for the band.}
	Int lvl = _BandInt("aot_crystal_level_by_band", aiBand, 0)
	If lvl < 1 || lvl > 4
		Return 0
	EndIf
	Return lvl
EndFunction

MiscObject Function Crystal(Int aiLevel, Bool abLarge) Global
	{The crystal of a level (1 to 4), by the object id the table keeps; None when the table or the plugin lacks it.}
	String path = TablePath()
	String listKey = "aot_crystal_small_id"
	If abLarge
		listKey = "aot_crystal_large_id"
	EndIf
	String plug = JsonUtil.GetStringValue(path, "aot_crystal_plugin", "")
	If aiLevel < 1 || plug == "" || JsonUtil.IntListCount(path, listKey) < aiLevel
		Return None
	EndIf
	Return Game.GetFormFromFile(JsonUtil.IntListGet(path, listKey, aiLevel - 1), plug) as MiscObject
EndFunction

Int Function Value(Int aiLevel, Bool abLarge) Global
	{Gold the attendant pays for one crystal; 0 when the table has no value (the crystal is then kept).}
	String path = TablePath()
	String listKey = "aot_crystal_small_value"
	If abLarge
		listKey = "aot_crystal_large_value"
	EndIf
	If aiLevel < 1 || JsonUtil.IntListCount(path, listKey) < aiLevel
		Return 0
	EndIf
	Return JsonUtil.IntListGet(path, listKey, aiLevel - 1)
EndFunction

Bool Function GiveLarge(AoT_Contract akContract, Actor akVictim, String asWhy) Global
	{One large crystal of the contract's level into the corpse.}
	If !akContract || !akVictim
		Return False
	EndIf
	Int lvl = Level(akContract.Band)
	MiscObject cr = Crystal(lvl, True)
	If !cr
		Debug.Trace("[AoT-F17e6] no large crystal for band " + akContract.Band + " level " + lvl + " on " + akContract)
		Return False
	EndIf
	akVictim.AddItem(cr, 1, True)
	AoT_Core.Log("[AoT-F17e6] large " + asWhy + " lvl=" + lvl + " band=" + akContract.Band + " victim=" + akVictim + " q=" + akContract)
	Return True
EndFunction

Function Arm(AoT_Contract akContract) Global
	{The contract opened: its note alias listens to every kill until Disarm. The count starts at 0.}
	Alias a = akContract.GetAlias(4)
	If !a
		Debug.Trace("[AoT-F17e6] Arm: no note alias on " + akContract)
		Return
	EndIf
	StorageUtil.SetIntValue(akContract, "aot_crystal_small_count", 0)
	PO3_Events_Alias.RegisterForActorKilled(a)
	AoT_Core.Log("[AoT-F17e6] armed " + akContract + " band=" + akContract.Band + " dungeon=" + akContract.DungeonLocation())
EndFunction

Function Disarm(AoT_Contract akContract) Global
	{The contract ended (delivered, abandoned, failed): no more kills are heard and the count is cleared.}
	Alias a = akContract.GetAlias(4)
	If a
		PO3_Events_Alias.UnregisterForActorKilled(a)
	EndIf
	Int n = StorageUtil.GetIntValue(akContract, "aot_crystal_small_count", 0)
	StorageUtil.UnsetIntValue(akContract, "aot_crystal_small_count")
	AoT_Core.Log("[AoT-F17e6] disarmed " + akContract + " small=" + n)
EndFunction

Bool Function IsOurs(Actor akKiller, Actor akPlayer) Global
	{The player, a follower, or a summon of either.}
	If !akKiller
		Return False
	EndIf
	If akKiller == akPlayer || akKiller.IsPlayerTeammate()
		Return True
	EndIf
	If akKiller.IsCommandedActor()
		Actor boss = PO3_SKSEFunctions.GetCommandingActor(akKiller)
		Return boss && (boss == akPlayer || boss.IsPlayerTeammate())
	EndIf
	Return False
EndFunction

Function OnKill(AoT_Contract akContract, Actor akVictim, Actor akKiller) Global
	{The PO3 kill event of an armed contract (AoT_ContractNoteAlias).}
	If !akContract.IsRunning() || akContract.GetStage() < 20 || akContract.IsStageDone(100) || akContract.IsStageDone(105)
		Disarm(akContract)
		Return
	EndIf
	If !akVictim || akVictim == akContract.TargetActor()
		Return
	EndIf
	ReferenceAlias risen = akContract.GetAlias(5) as ReferenceAlias
	If risen && risen.GetActorReference() == akVictim
		Return
	EndIf
	Location dun = akContract.DungeonLocation()
	If !dun || !akVictim.IsInLocation(dun)
		Return
	EndIf
	Actor pl = Game.GetPlayer()
	If !IsOurs(akKiller, pl)
		AoT_Core.Log("[AoT-F17e6] kill not ours victim=" + akVictim + " killer=" + akKiller + " q=" + akContract)
		Return
	EndIf
	String path = TablePath()
	If akVictim.HasKeyword(Game.GetForm(0x00035D59) as Keyword) && JsonUtil.GetIntValue(path, "aot_crystal_large_on_dragon", 0) == 1
		GiveLarge(akContract, akVictim, "dragon")
		Return
	EndIf
	If JsonUtil.GetIntValue(path, "aot_crystal_creature_only", 1) == 1 && akVictim.HasKeyword(Game.GetForm(0x00013794) as Keyword)
		AoT_Core.Log("[AoT-F17e6] kill skipped (ActorTypeNPC) victim=" + akVictim + " q=" + akContract)
		Return
	EndIf
	Int band = akContract.Band
	Int cap = _BandInt("aot_crystal_cap_by_band", band, 0)
	Int had = StorageUtil.GetIntValue(akContract, "aot_crystal_small_count", 0)
	If had >= cap
		AoT_Core.Log("[AoT-F17e6] cap reached " + had + "/" + cap + " victim=" + akVictim + " q=" + akContract)
		Return
	EndIf
	Int chance = _BandInt("aot_crystal_chance_by_band", band, 0)
	Int roll = Utility.RandomInt(1, 100)
	If roll > chance
		AoT_Core.Log("[AoT-F17e6] no drop roll=" + roll + " chance=" + chance + " victim=" + akVictim + " q=" + akContract)
		Return
	EndIf
	Int lo = _BandInt("aot_crystal_min_by_band", band, 1)
	Int hi = _BandInt("aot_crystal_max_by_band", band, 3)
	If lo < 1
		lo = 1
	EndIf
	If hi < lo
		hi = lo
	EndIf
	Int n = Utility.RandomInt(lo, hi)
	If had + n > cap
		n = cap - had
	EndIf
	MiscObject cr = Crystal(Level(band), False)
	If !cr || n <= 0
		Debug.Trace("[AoT-F17e6] no small crystal for band " + band + " on " + akContract)
		Return
	EndIf
	akVictim.AddItem(cr, n, True)
	StorageUtil.SetIntValue(akContract, "aot_crystal_small_count", had + n)
	AoT_Core.Log("[AoT-F17e6] small n=" + n + " total=" + (had + n) + "/" + cap + " roll=" + roll + " chance=" + chance + " lvl=" + Level(band) + " victim=" + akVictim + " q=" + akContract)
EndFunction

Int Function TradeIn() Global
	{Action 16: the attendant takes every crystal the player carries and pays the table. Returns the gold paid. A
	crystal whose value the table lacks is kept.}
	Actor pl = Game.GetPlayer()
	Int gold = 0
	Int count = 0
	Int lvl = 1
	While lvl <= 4
		Int k = 0
		While k < 2
			Bool large = k == 1
			MiscObject cr = Crystal(lvl, large)
			Int v = Value(lvl, large)
			If cr && v > 0
				Int n = pl.GetItemCount(cr)
				If n > 0
					pl.RemoveItem(cr, n, True)
					gold += n * v
					count += n
				EndIf
			EndIf
			k += 1
		EndWhile
		lvl += 1
	EndWhile
	If gold > 0
		pl.AddItem(Game.GetForm(0x0000000F), gold)
	EndIf
	AoT_Core.Log("[AoT-F17e6] trade crystals=" + count + " gold=" + gold)
	Return gold
EndFunction
