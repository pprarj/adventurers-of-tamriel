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
; Contract states: 1 open, 2 completed, 3 abandoned, 4 expired.

Int Function SchemaCode() Global
	{Persisted-format version this build writes.}
	Return 1
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

Int Function GetPoints() Global
	{Points earned inside the current rank. Never below 0.}
	Return StorageUtil.GetIntValue(None, "aot_points", 0)
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

Int Function PointsForBand(Int aiBand) Global
	{Points a completed contract of this band is worth; -1 on a bad band or a table error.}
	If aiBand < 0 || aiBand > MaxBand()
		Return -1
	EndIf
	If JsonUtil.IntListCount(TablePath(), "aot_points_by_band") <= aiBand
		Debug.Trace("[AoT] table: aot_points_by_band missing or short")
		Return -1
	EndIf
	Return JsonUtil.IntListGet(TablePath(), "aot_points_by_band", aiBand)
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
	{1 open, 2 completed, 3 abandoned, 4 expired; 0 for an unknown id.}
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
	Return True
EndFunction

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

Bool Function _CanWrite() Global
	{Stamps the schema on the first write; refuses to write over a newer format.}
	Int stored = StorageUtil.GetIntValue(None, "aot_schema", 0)
	If stored == 0
		StorageUtil.SetIntValue(None, "aot_schema", SchemaCode())
		Return True
	EndIf
	If stored > SchemaCode()
		Debug.Trace("[AoT] save schema " + stored + " is newer than this build (" + SchemaCode() + "): not writing")
		Return False
	EndIf
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
	Return True
EndFunction
