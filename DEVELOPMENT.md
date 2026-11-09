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
| `<Monster Hunt Missives>\Source\Scripts` | `MMH_RewardScript`, called by the MMH adapter |
| `<Headhunter - Bounties Redone>\Source\Scripts` | the Headhunter scripts the Headhunter adapter calls |

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

## Public contract for other mods (version 1.0)

This is what a mod that wants to read the guild may rely on. Everything else in this file describes the mod's own
internals and may change between releases.

**Contract version: 1.0.** The version changes only by these rules: a new read function or a new optional key is a
minor step (1.1); a changed meaning, a changed return value, a renamed or removed function, or a changed persisted key
is a major step (2.0) and ships with the old name kept for one major release where that is possible. A mod that calls
only what is listed below keeps working across every 1.x.

**Soft dependency.** Call these scripts only after checking that the mod is installed, so yours still loads without it:

```
if Game.IsPluginInstalled("AdventurersOfTamriel.esp")
    Int rank = AoT_Core.GetRank()
endif
```

All functions are `Global` on the script `AoT_Core`. They never write, never block and never throw; they return the
sentinel written next to them when the guild is absent or the save is empty.

| Function | Returns | If absent / unknown |
|---|---|---|
| `Int GetRank()` | the player's rank, 0 (F) to 6 (S). **0 also means "never joined"**: to tell F from not joined, use the next row with `Game.GetPlayer()` | 0 |
| `Int GetAdventurerRank(Actor a)` | the rank of any actor that belongs to the guild, 0 to 6. For the player: the rank once the player has taken a first contract | **-1** (not a member, the player before the first contract, `None`, or `_Adventurers.esp` not loaded) |
| `Int GetPoints()` | points earned inside the current rank | 0 |
| `Bool IsPromotionEligible()` | the points reached the step of the current rank | False |
| `Int LadderStep(Int rank)` | points needed inside `rank` to become eligible | -1 |
| `Int SchemaVersion()` | version of the persisted format in this save | 0 |

NPC members can also be read with no script at all: `GetFactionRank` on the faction `AoT_GuildFaction`
(`AdventurersOfTamriel.esp`, form `0xE36`) returns the rank, and **-2 for a non-member** (the faction call,
not `GetAdventurerRank`, which maps that case to -1). The player is not in the faction.

**Not part of the contract (internal; may change in any release):** every write function (`OpenContract`,
`CompleteContract`, `AbandonContract`, `ExpireContract`, `VoidContract`, `AdjustPoints`, `MarkBandPaid`, `Promote`,
`SetCardTree`), the contract ledger reads, the card and exam scripts, and the persisted keys. A mod must not write
guild state. If it needs the guild to react to something (for example a contract of its own), ask for a function in
an issue instead of calling a write.

**Promotion event (1.0).** When a promotion happens, `AoT_Core.Promote()` sends the mod event `AoT_Promoted` once, after the rank has risen and the points have restarted. `numArg` is the new rank in the scale of `GetRank()` (0 = F ... 6 = S); `strArg` is empty; the sender is the player. A refused promotion (not eligible, or already S) sends nothing. Register for it the usual way:

```
Event OnInit()
    RegisterForModEvent("AoT_Promoted", "OnAoTPromoted")
EndEvent

Event OnAoTPromoted(String asEventName, String asStr, Float afNewRank, Form akSender)
    Int newRank = afNewRank as Int
    ; react here
EndEvent
```

The registration is per script and does not survive a missing mod, so register again on game load if your script needs it. The name, the arguments and their meaning are frozen for every 1.x.

The sections below document the whole core, for contributors. Only the table above is the contract.

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
| `Int GetAdventurerRank(Actor a)` | guild rank of any actor, 0 (F) to 6 (S); **-1 when the actor has no rank** (not a member, `None`, or the adventurers plugin is not loaded). Never 0 for "no rank": 0 is F. NPC members carry the rank as their rank in the faction `AoT_GuildFaction` (`AdventurersOfTamriel.esp`, form `0xE36`), so a mod can also read it with `GetFactionRank`. The player is not in the faction: for the player it is `GetRank()` once the player has joined, -1 before |
| `Int GetPoints()` | points earned inside the current rank; never below 0 |
| `Bool IsPromotionEligible()` | points reached the ladder step of the current rank. Points only make the player eligible; the exam is what promotes |
| `Int LadderStep(Int rank)` | points needed inside `rank` to become eligible; -1 at S or on a table error |
| `Int PointsForBand(Int band)` | what a completed contract of `band` is worth; -1 on error |
| `Int BandWeight(Int rank, Int band)` | draw weight of `band` for `rank`; -1 on error |
| `Bool IsBandPaid(Int band)` | the fee of `band` was paid |
| `Int ContractCount()` | contracts ever opened; ids run from 1 to this |
| `Int ContractState(Int id)` | 1 to 5, or 0 for an unknown id |
| `Int ContractBand(Int id)` | band, or -1 for an unknown id |
| `Int ContractDelta(Int id)` | points the contract actually applied, after the floor; 0 while open |
| `Int FindOpenContract(Quest q)` | id of the open contract of `q`, or 0 |
| `Int SchemaVersion()` | persisted-format version in this save; 0 if the core never wrote |
| `Int JoinedDay()` | the game day the player joined the guild (the day of the first contract, or of the first read in a save that predates the stamp); kept from then on |
| `Int CardSlots()` | how many perk-tree columns the card shows at most (5) |
| `String GetCardTree(Int slot)` | the skill (engine enum name, e.g. `OneHanded`) chosen for a card column; `""` when empty |
| `Int SkillCount()`, `String SkillEnumName(Int i)`, `Int SkillLevel(String skill)` | the 18 skills by enum name, and the player's level in one |

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
| `Bool SetCardTree(Int slot, String skill)` | chooses the skill of a card column; `""` empties it. Refused (False) for a bad slot, for a skill already in another column, or when the save is newer than this build |

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
| `aot_schema` | Int | global | persisted-format version, 2 (a save at 1 is migrated on its first write; no other key changes) |
| `aot_joined_day` | Int | global | game day the player joined (schema 2) |
| `aot_card_tree_0` to `aot_card_tree_4` | String | global | skill chosen for each card column; absent or empty = none (schema 2) |
| `aot_rank` | Int | global | the rank; its only writer is `Promote()` |
| `aot_points` | Int | global | points inside the current rank |
| `aot_bands_paid` | Int list | global | bands whose fee was paid |
| `aot_contracts` | Int list | global | the contract ledger, one packed entry per contract |
| `aot_open` | Int list | global | ids of the contracts still open |
| `aot_contract_id` | Int | the contract's `Quest` | id of that quest's latest contract |

Ledger entry: `state + 8 * band + 64 * (delta + 1024)`, with `state` 1 to 5 (5 = void: closed with no points),
`band` 0 to 5 and `delta` -1024 to 1023 - every term non-negative, so integer
division decodes it. Zero is never a valid entry, id or state, because
`StorageUtil` stores 0 as an unset key.

Eligibility, career totals and per-state counts are derived from these keys
and are never stored.

## The adventurer card (`AoT_Card`, `Panel/card.html`, `AoT_MCM`)

A one-screen web panel with the player's own record (rank, level, joined date, points toward the next rank, promotion exam ready, contracts completed / in progress / failed, fee status) and the perk trees the player chose. It reads `AoT_Core` at every opening and keeps no guild state of its own, and it has no action on the guild. The one thing it does is spend a perk point: a click on a node asks `Lodestone.TryBuyPerk`, which buys in one atomic step or changes nothing.

- Opens on a hotkey (F7, DirectX scan code 65, `AoT_Card.HotkeyCode`). The same key closes it, and so do Esc and the Close button.
- Goes through the Lodestone `WebUI*` bridge. Version floors, never one number: `WebUIMinVersion` 1023000 for the web surface, `WebUIFocusMinVersion` 1022000 for focus, and `PerkMinVersion` 1037000 for the perk surface; it also asks `WebUIHasCapability("view-focus")`. Without the web floors the key shows the same facts in a message box; without the perk floor the card opens with no trees and says so.
- Handshake: the view is shown first and focus is asked only after the page itself calls `AoTCardAction("ready-...")` (a loaded page is not necessarily our page). No answer in 6 s: hide, no focus, message box. A watchdog polls `WebUIIsViewFocused` every second and closes the panel if the focus is gone.
- Payloads are partial: a header first, then `c_trees|N`, then one payload per column, so the first tree draws while the next ones are still being read. The page asks nothing of the game's rules: the state of every node (0 locked, 1 can buy, 2 owned, 3 partly owned and the next rank can be bought, 4 partly owned) comes from Papyrus, which reads `HasPerk` and `IsPerkEligible` per node. A tree node is the first rank of a perk; later ranks hang on `Perk.GetNextPerk`, and the perk bought next is the one after the highest rank owned.
- A buy is `AoTCardAction("buy|column|node")`. Papyrus re-reads the tree of that column, works out the perk, calls `TryBuyPerk`, logs `[AoT] Card: buy ... points before -> after, owned` and pushes the column again.
- Which trees: the skills chosen in the MCM page (`AoT_MCM`, five menus, each listing the skills whose tree is loaded plus "(none)"; the same skill is refused twice). With every menu on "(none)" the card shows the five skills of highest level. The choice lives in the save, never in a script.
- The page is `Panel/card.html` plus `Panel/fonts/` (Cinzel 500 and 700 as `.woff2`, `OFL.txt` with the license; no request leaves the page). The whole folder is packed for `PrismaUI/views/AdventurersOfTamriel/` (the backend the card is tested on), `Magelight/AdventurersOfTamriel/` and `MeridianUI/AdventurersOfTamriel/` (same page; Meridian UI is discontinued and no longer tested or packaged). ES5 only, so the same file runs on all of them.
- Plugin `AdventurersOfTamriel_Card.esp` carries two Start Game Enabled quests: `AoT_CardQuest` (script `AoT_Card`) and `AoT_MCMQuest` (script `AoT_MCM`, a SkyUI `SKI_ConfigBase`). Not installed means no card and no settings page; the core `.esl` is not touched.

## The Missives adapter (soft dependency, D-35)

Missives, Headhunter and MMH are **soft** (D-35, Rev 24): the core never has a third-party master. Each gains an adapter in its own plugin, with that mod as master. The first adapter is `AdventurersOfTamriel_Missives.esp` (masters `Skyrim.esm, Update.esm, Missives.esp`).

Presence check (runtime, no error when missing):

```
if Game.GetFormFromFile(0x001D95, "Missives.esp") != None
    ; adapter present, board serves both pools
endif
```

Without the adapter the board serves only our own contracts. The board reads the Missives FormLists (`_M_ListQuests*`) **in game** via `Game.GetFormFromFile` so SkyPatcher injections are visible, and tests each entry as `Quest` before use. BadGuys lists are not read: it does not expose `_D_ListQuests*` (D029). A quest the board starts is only an offer (`aot_missives_offer`, band in `aot_offer_band`); the adapter opens the contract when the quest reaches stage 20 and closes it by stage 100, 103, 105 or 110 (D026). See D005/D006 for stage table, D-30 via(c) re-apply and E-12 above-rank note (StoresText on 00F0C6, alias Missive index 6).

## The promotion exam (`AoT_Exam`, `AoT_Hall`)

Promotion stays "points enable, a test promotes" (`IsPromotionEligible`, then `Promote`). Where the ladder asks for a test is data, in `Config/AdventurersOfTamriel/points.json` (indexed by the current rank, F to A): `aot_exam_required` (0 none, 1 exam room, 2 emergency call), `aot_exam_foes` (bandits) and `aot_exam_boss` (bosses).

```
Int  AoT_Core.ExamKind(Int aiRank) Global      ; -1 on a short table
Bool AoT_Core.CanOfferExam() Global            ; eligible and the step asks for the room exam
Bool AoT_Core.PromoteWithoutExam() Global      ; eligible and the step asks for none
Bool AoT_Exam.StartExam() Global               ; spawns the foes at the examiner spot
Function AoT_Exam.Tick() Global                ; win -> Promote; leaving, dying or a lost record -> abort
```

State lives under `aot_exam_state`, `aot_exam_rank`, `aot_exam_hall` and the FormList `aot_exam_foes`. Losing or fleeing touches neither points nor rank. `AoT_Hall.EnsureFixtures` places the guild board (`AdventurersOfTamriel_ExamTalk.esp`) and the examiner (`AdventurersOfTamriel_Exam.esp`) at the markers of the hall the player stands in. `AoT_HeadhunterAdapter.FindReadyQuest` and `AoT_MMHAdapter.FindReadyQuest` scan the quest ids of `adapters.json` for one at stage 40; with the mod absent they return `None`.

## The SKSE plugin

The project has no C++ yet. This section will say how to configure and
build the plugin - toolchain, presets, and where the DLL lands - once it does.

## What the author's own tree does differently, and why you do not need it

The author develops inside a Mod Organizer 2 instance, where this repository
sits inside the mod folder and the compiler writes `.pex` up into it, so the
game loads a build immediately. That arrangement is convenient and entirely
optional: it is one way of pointing `-o=`, and nothing in the source depends
on it.
