# Pokémon Spawn Dataset Generator

Builds a Gen 1–9 wild-encounter corpus from PokéAPI for G1R Deluxe.

The design separates **source data**, **derived species profiles**, and the
**runtime target-game encounter skeleton**.

## Runtime targets

The eight actual runtime target games are:

```text
Red
Blue
Yellow
FireRed
LeafGreen
Gold
Silver
Crystal
Ruby
Sapphire
Emerald
```

## Install

```bash
python -m pip install requests
```

## Run

```bash
python generate_spawn_data.py
```

Refresh cached PokéAPI responses:

```bash
python generate_spawn_data.py --refresh
```

Quick test:

```bash
python generate_spawn_data.py --max-pokemon 151 --workers 8
```

Build the profile file the Modern Spawns mod loads:

```bash
python generate_spawn_data.py --lua ../data/spawn_profiles.lua
```

JSON output goes to `./pokemon_spawn_data/`, relative to the directory you
run from; change it with `--out`. PokéAPI responses are cached in
`<out>/.cache/`, so a rerun takes seconds and works offline.

## Wild encounters only

The raw corpus keeps every PokéAPI encounter record. Species profiles and the
Lua export are built only from **wild** methods (walk, surf, fishing rods,
cave spots, overworld and so on). Each wild method is mapped to a terrain:
grass, cave, water or fish. `walk` counts as cave when the location is a
cave. Gifts, static encounters, trades, raids, Dynamax Adventures, roamers
and Shadow Pokémon snags are left out, so they don't distort level ranges.
The method-to-terrain map is `WILD_METHOD_TERRAIN` in the script.

## `spawn_profiles.lua` (the `--lua` export)

This file is keyed by national dex number and covers default varieties only:

- `generation[dex]`: the generation the species was introduced in, for all
  1025 species.
- `special[dex]`: `"legendary"` or `"mythical"`.
- `species[dex]`: `{ lo, hi, typ, r, h, t }`:
  - `lo` / `hi`: the usual wild level range, the 25th percentile of minimum
    levels to the 75th percentile of maximum levels, unweighted.
  - `typ`: the median level.
  - `r`: rarity, `c` / `u` / `r` / `v` (common, uncommon, rare, very rare).
  - `h`: habitats found on at least 15% of the species' records.
  - `t`: terrains found on at least 10% of its records; the most common
    terrain is always kept.

PokéAPI has no wild data for Gen 9 (Scarlet/Violet), so those species appear
only in `generation` and `special`. The mod estimates their profiles at
runtime.

## Output

### `pokemon_encounters.json`

Normalized encounter observations containing Pokémon, generation, version,
location area, habitat hints, method, levels, chance, and conditions.

### `pokemon_spawn_profiles.json`

One derived profile per species. Includes:

- generation introduced
- generations observed
- native versions
- encounter methods (wild only)
- terrains (grass / cave / water / fish)
- habitat hints
- first/last/typical wild levels
- progression-band overlap
- rough native rarity
- special-spawn classification

### `progression_pools.json`

Candidates grouped into level bands from 1–5 through 81–100. Each candidate
contains level overlap, rarity, habitat, method, generation, and special-spawn
metadata.

### `target_game_reference.json`

Original encounter skeletons for the eight runtime target games. Use these as
the map/table structure while replacing species dynamically.

### `special_spawns.json`

A compact index of species that need special handling:

- legendary
- mythical
- very rare
- rare

Legendary and mythical species are intended to be protected by default.
Very-rare species can be explicitly enabled as special candidates.

**Important:** this is a species-level classification, not a complete database
of static/story/scripted encounters. If the mod needs exact authored legendary
or event encounters, add a separate `special_encounters.json` and have it
override normal redistribution.

### `dataset_manifest.json`

Dataset version metadata, counts, target versions, level bands, and output
file list.
