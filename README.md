# Adventurers of Tamriel

An adventurers' guild for Skyrim: a branch of the guild in every hold, a board of ranked contracts from F to S, and
promotion earned through points and proof.

**Status: released.** Version 1.0.0 is on Nexus Mods:
https://www.nexusmods.com/skyrimspecialedition/mods/194936

## What the mod does

- A guild hall in each of the nine holds, with an attendant and a board of contracts.
- Seven ranks, F to S. Points make you eligible; a test (an exam room, or an emergency call) promotes you.
- A fee per band of contracts, paid to the attendant.
- Contracts of its own for the dungeons of the world, and, if you have them, contracts of Missives, Headhunter and
  Monster Hunt Missives served on the same board.
- An adventurer card (a one-screen panel) with your record and the perk trees you chose, where you can spend perk points.
- NPC adventurers who belong to the guild and keep a rank of their own.

## Requirements

What the base mod needs, from the scripts it contains:

- SKSE
- PapyrusUtil SE (the saved state and the tables)
- powerofthree's Papyrus Extender (the contracts that ask you to clear a place)
- Lodestone 1.6.0 or newer (the adventurer card and the perk purchase go through it)
- Prisma UI (the card's panel; Magelight UI is the secondary backend)
- SkyUI (the settings page)

The adventurer card and its settings page are part of the base mod, not an option: the main plugin carries the two quests
that start them, so a game without Lodestone, a panel framework and SkyUI loses the card and the settings page.

The Missives, Headhunter and Monster Hunt Missives adapters are optional, one each, and each needs its own mod.

## For other mods

A small read-only interface (your rank, any guild member's rank, the points) is documented and versioned in
[DEVELOPMENT.md](DEVELOPMENT.md#public-contract-for-other-mods-version-10).

## License

No license has been chosen yet. One will be added before the first outside contribution is accepted.

## What is in this repository, and what is not

```
Scripts/Source/     Papyrus source (.psc)
Panel/              the web page of the adventurer card
plugin-skse/        SKSE plugin source (C++), when the project has one
```

**This repository holds the source of what players receive.** The development records - design notes, phase logs,
decision history - and the development tools live in a separate private repository, on purpose.

## Building

See [DEVELOPMENT.md](DEVELOPMENT.md).

## Contributing

Issues and patches are welcome. Because the development history lives elsewhere, a pull request is judged on the code
alone - explain the why in the description rather than assuming shared context.
