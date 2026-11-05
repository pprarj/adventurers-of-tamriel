Scriptname AoT_ContractRisen extends AoT_Contract
{Fase 10 (D047), S2: the boss of two phases. The death of the Boss (alias 2) gives no point: a
vanilla leveled actor (RisenBase) is placed at the body and forced into alias 5, Risen. Its death
closes the contract.
Stages: 0 offered, 20 phase 1 (the Boss), 30 phase 2 (the Risen), 100 complete, 105 failed or
abandoned, 110 retired offer.}

Form Property RisenBase Auto
{The leveled actor of the second phase (generator data, f9-arquetipos.json, field risen).}

Actor Function RisenActor()
	ReferenceAlias a = GetAlias(5) as ReferenceAlias
	If a
		Return a.GetActorReference()
	EndIf
	Return None
EndFunction

Bool Function TryComplete()
	{Called by the Target alias on the death of the Boss. Phase 1 ends here; the point waits for
	the Risen (RisenDied).}
	If IsStageDone(30)
		Return False
	EndIf
	Actor boss = TargetActor()
	ReferenceAlias ra = GetAlias(5) as ReferenceAlias
	ObjectReference r = None
	If boss && ra && RisenBase
		r = boss.PlaceAtMe(RisenBase)
	EndIf
	If !r
		; nothing to fight in phase 2: the contract closes on the first death, and the log says so
		Debug.Trace("[AoT-F10] risen not placed on " + self + " base=" + RisenBase + " boss=" + boss)
		Return Parent.TryComplete()
	EndIf
	ra.ForceRefTo(r)
	Debug.Trace("[AoT-F10] Boss dead, risen " + r + " placed on " + self)
	SetObjectiveCompleted(20)
	MirrorStage(30)
	SetObjectiveDisplayed(30)
	Return False
EndFunction

Function RisenDied()
	{Stage 30 only: called by the Risen alias on its death.}
	If !IsRunning() || !IsStageDone(30) || IsStageDone(100) || IsStageDone(105)
		Return
	EndIf
	Debug.Trace("[AoT-F10] risen died on " + self)
	SetObjectiveCompleted(30)
	Parent.TryComplete()
EndFunction

Bool Function TryAbandon()
	{Abandoned in phase 2: the Risen still standing leaves with the contract (the alias empties on
	Stop, so it is read before).}
	Actor r = RisenActor()
	Bool ok = Parent.TryAbandon()
	If ok && r && !r.IsDead()
		r.Disable()
		r.Delete()
	EndIf
	Return ok
EndFunction
