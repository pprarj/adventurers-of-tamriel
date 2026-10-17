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

## The SKSE plugin

The project has no C++ yet. This section will say how to configure and
build the plugin - toolchain, presets, and where the DLL lands - once it does.

## What the author's own tree does differently, and why you do not need it

The author develops inside a Mod Organizer 2 instance, where this repository
sits inside the mod folder and the compiler writes `.pex` up into it, so the
game loads a build immediately. That arrangement is convenient and entirely
optional: it is one way of pointing `-o=`, and nothing in the source depends
on it.
