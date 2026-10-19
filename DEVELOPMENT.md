# Building Adventurers of Tamriel

This repository holds source only. Building it produces the files a release
archive carries; it does not produce an installed mod on its own.

## Papyrus

`Scripts/Source/*.psc` compiles with the Papyrus compiler that ships with the
Creation Kit. Besides this repository's source folder, the compiler needs the
script sources of everything these scripts extend or call, and none of them are
redistributable here:

| Import | Why |
|---|---|
| `<this repo>\Scripts\Source` | this project's scripts |
| `<Skyrim>\Data\Scripts\Source` or `<Skyrim>\Data\Source\Scripts` | vanilla and SKSE script sources |
| `<PapyrusUtil SE>\Scripts\Source` | `StorageUtil` and `JsonUtil`, used by the core |

```
PapyrusCompiler.exe <script or folder> ^
  -f="TESV_Papyrus_Flags.flg" ^
  -i="<import 1>;<import 2>;..." ^
  -o="<where you want the .pex>"
```

**The game paths differ between installs**, which is why they are written as
placeholders rather than committed as a script. The Creation Kit puts the
vanilla sources in one of the two game folders above depending on how it was
installed - check which one exists. The list is order-independent and the
separator is `;`.

If the mod depends on another framework's scripts, that framework's
`Scripts\Source` joins the `-i=` list, and a row joins the table above.

## The core API (`AoT_Core`)

`Scripts/Source/AoT_Core.psc` is the surface every other part of the mod
calls: the contract board, the attendant, the adventurer card, the promotion
exam. It is a script of global functions only - call it as
`AoT_Core.GetRank()`, with no form and no property to fill. It needs
PapyrusUtil SE at runtime.

### Identifiers

| Rank | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| letter | F | E | D | C | B | A | S |

| Band | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| meaning | Low | Med | High | VeryHigh | own rank-A contract | own rank-S contract |

The rank is not the band: there are more ranks than bands, and which bands a
rank draws from is data (the weights below), not code.

Contract states: 1 open, 2 completed, 3 abandoned, 4 expired.

### Reads

| Function | Returns |
|---|---|
| `Int GetRank()` | current rank, 0 to 6. One rank for the whole guild, every branch |
| `Int GetPoints()` | points earned inside the current rank; never below 0 |
| `Bool IsPromotionEligible()` | points reached the ladder step of the current rank. Points only make the player eligible; the exam is what promotes |
| `Int LadderStep(Int rank)` | points needed inside `rank` to become eligible; -1 at S or on a table error |
| `Int PointsForBand(Int band)` | what a completed contract of `band` is worth; -1 on error |
| `Int BandWeight(Int rank, Int band)` | draw weight of `band` for `rank`; -1 on error |
| `Bool IsBandPaid(Int band)` | the fee of `band` was paid |
| `Int ContractCount()` | contracts ever opened; ids run from 1 to this |
| `Int ContractState(Int id)` | 1 to 4, or 0 for an unknown id |
| `Int ContractBand(Int id)` | band, or -1 for an unknown id |
| `Int ContractDelta(Int id)` | points the contract actually applied, after the floor; 0 while open |
| `Int FindOpenContract(Quest q)` | id of the open contract of `q`, or 0 |
| `Int SchemaVersion()` | persisted-format version in this save; 0 if the core never wrote |

### Writes

| Function | Does |
|---|---|
| `Int OpenContract(Quest q, Int band)` | registers a contract the player took; returns its id, or 0 on error. `q` may be `None` (a contract with no quest). Opening a quest whose contract is still open returns the same id; opening it again after that contract ended returns a new one |
| `Bool CompleteContract(Int id)` | adds the band's points |
| `Bool AbandonContract(Int id)` | explicit abandon at the attendant: applies the table's abandon delta |
| `Bool ExpireContract(Int id)` | the quest's own deadline passed: applies the table's expired delta. The core keeps no timer; the deadline belongs to the quest that owns it, and the caller reports it |
| `Bool MarkBandPaid(Int band)` | records the fee of `band`; true only the first time |
| `Bool Promote()` | the exam's outcome: rank + 1, points restart at 0. Refused unless eligible |
| `Int AdjustPoints(Int delta)` | low level, floored, **not** idempotent; returns the delta applied |

**Every contract event acts once.** An event changes only an open contract,
and the event claims the contract by removing its id from `aot_open` with
one native call (`StorageUtil.IntListRemove`), which returns how many copies
it removed. Of two callers racing on the same id only one sees `1`, so a
second call for the same contract - or a complete after an abandon - returns
`False` and changes nothing. (`IntListSet` cannot serve as the claim: it
returns the value just written, not the previous one.)

**Points never go below the floor, and the floor never goes below 0.** The
delta stored for the contract is the one actually applied.

**Losing points never lowers the rank.** `Promote()` is the only function that
writes the rank, and it only adds.

### The scoring table

`Data/Config/AdventurersOfTamriel/points.json`, read with `JsonUtil` and never
written. There is no scoring number in the scripts: a missing key makes the
event refuse and log, instead of falling back to a built-in value.

| Key | Type | Meaning |
|---|---|---|
| `aot_table_version` | int | format of this file |
| `aot_points_by_band` | int list, 6 | points per completed contract, by band |
| `aot_ladder` | int list, 6 | points to become eligible from rank F, E, D, C, B, A |
| `aot_delta_abandon` | int | delta of an abandon |
| `aot_delta_expired` | int | delta of an expired deadline |
| `aot_floor` | int | floor of the points; a negative value is read as 0 |
| `aot_band_weight_rank0` to `aot_band_weight_rank6` | int list, 6 | draw weight of each band for that rank |

`JsonUtil` caches the file for the session; a change on disk is seen after
the next save load, or after `JsonUtil.Unload` on the path
`../../../Config/AdventurersOfTamriel/points`.

### Persisted state

Everything lives in the PapyrusUtil co-save (`StorageUtil`), next to the game
save. **This format does not change in place**: a save written by one version
must load in every later one. A new key may be added without a schema change;
a change in the meaning or layout of an existing key bumps `aot_schema`, takes
a new key name, and ships with a migration. A build that finds a schema newer
than its own refuses to write.

| Key | Type | Holder | Content |
|---|---|---|---|
| `aot_schema` | Int | global | persisted-format version, 1 |
| `aot_rank` | Int | global | the rank; its only writer is `Promote()` |
| `aot_points` | Int | global | points inside the current rank |
| `aot_bands_paid` | Int list | global | bands whose fee was paid |
| `aot_contracts` | Int list | global | the contract ledger, one packed entry per contract |
| `aot_open` | Int list | global | ids of the contracts still open |
| `aot_contract_id` | Int | the contract's `Quest` | id of that quest's latest contract |

Ledger entry: `state + 8 * band + 64 * (delta + 1024)`, with `state` 1 to 4,
`band` 0 to 5 and `delta` -1024 to 1023 - every term non-negative, so integer
division decodes it. Zero is never a valid entry, id or state, because
`StorageUtil` stores 0 as an unset key.

Eligibility, career totals and per-state counts are derived from these keys
and are never stored.

## The SKSE plugin

The project has no C++ yet. This section will say how to configure and
build the plugin - toolchain, presets, and where the DLL lands - once it does.

## What the author's own tree does differently, and why you do not need it

The author develops inside a Mod Organizer 2 instance, where this repository
sits inside the mod folder and the compiler writes `.pex` up into it, so the
game loads a build immediately. That arrangement is convenient and entirely
optional: it is one way of pointing `-o=`, and nothing in the source depends
on it.
