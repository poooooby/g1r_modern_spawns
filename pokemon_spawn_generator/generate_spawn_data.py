#!/usr/bin/env python3
"""
Pokemon Spawn Dataset Generator
===============================

Builds a normalized Gen 1-9 wild-encounter corpus from PokéAPI and produces:
  1. pokemon_encounters.json
     Complete normalized encounter records.
  2. pokemon_spawn_profiles.json
     Compact per-species profiles intended for Claude/Lua.
  3. progression_pools.json
     Level-band candidate pools with diversity metadata.
  4. dataset_manifest.json
     Dataset metadata and generation statistics.

The generator deliberately separates:
  - SOURCE DATA: what Pokémon actually do in the original games.
  - DESIGN DATA: derived profiles used to generate new spawn tables.

Target games are separately marked so Claude can use the actual
FireRed/LeafGreen/Gold/Silver/Crystal/Ruby/Sapphire/Emerald tables
as map skeletons while using Gen 1-9 encounters as the candidate corpus.

Requirements:
    Python 3.10+
    pip install requests

Usage:
    python generate_spawn_data.py

Optional:
    python generate_spawn_data.py --refresh
    python generate_spawn_data.py --workers 12
    python generate_spawn_data.py --max-pokemon 151
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import re
import sys
import threading
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

import requests


BASE_URL = "https://pokeapi.co/api/v2"
DEFAULT_OUT = Path("pokemon_spawn_data")
CACHE_DIR = DEFAULT_OUT / ".cache"

# These are PokeAPI version names, not version groups.
# Versions included in the historical Gen 1-9 source corpus.
CORPUS_VERSIONS = {
    "red", "blue", "yellow",
    "gold", "silver", "crystal",
    "ruby", "sapphire", "emerald",
    "firered", "leafgreen",
    "diamond", "pearl", "platinum", "heartgold", "soulsilver",
    "black", "white", "black-2", "white-2",
    "x", "y", "omega-ruby", "alpha-sapphire",
    "sun", "moon", "ultra-sun", "ultra-moon",
    "lets-go-pikachu", "lets-go-eevee",
    "sword", "shield", "brilliant-diamond", "shining-pearl", "legends-arceus",
    "the-isle-of-armor-sword", "the-isle-of-armor-shield",
    "the-crown-tundra-sword", "the-crown-tundra-shield",
    "red-japan", "green-japan", "blue-japan", "colosseum", "xd",
    "scarlet", "violet",
}

# Actual ROM/mod targets for runtime table replacement.
TARGET_GAMES = {
    "firered", "leafgreen",
    "gold", "silver", "crystal",
    "ruby", "sapphire", "emerald",
}


GENERATION_BY_VERSION = {
    # Gen 1
    "red": 1, "blue": 1, "yellow": 1,
    "red-japan": 1, "green-japan": 1, "blue-japan": 1,
    # Gen 2
    "gold": 2, "silver": 2, "crystal": 2,
    # Gen 3
    "ruby": 3, "sapphire": 3, "emerald": 3,
    "firered": 3, "leafgreen": 3, "colosseum": 3, "xd": 3,
    # Gen 4
    "diamond": 4, "pearl": 4, "platinum": 4,
    "heartgold": 4, "soulsilver": 4,
    # Gen 5
    "black": 5, "white": 5, "black-2": 5, "white-2": 5,
    # Gen 6
    "x": 6, "y": 6, "omega-ruby": 6, "alpha-sapphire": 6,
    # Gen 7
    "sun": 7, "moon": 7, "ultra-sun": 7, "ultra-moon": 7,
    "lets-go-pikachu": 7, "lets-go-eevee": 7,
    # Gen 8
    "sword": 8, "shield": 8,
    "the-isle-of-armor-sword": 8, "the-isle-of-armor-shield": 8,
    "the-crown-tundra-sword": 8, "the-crown-tundra-shield": 8,
    "brilliant-diamond": 8, "shining-pearl": 8, "legends-arceus": 8,
    # Gen 9
    "scarlet": 9, "violet": 9,
}

# Encounter methods that describe a genuine WILD encounter, mapped to the
# runtime terrain they correspond to in a Gen 1-style encounter table. Any
# method not listed here (gift, static, npc-trade, snag, max-raid,
# dynamax-adventure, roaming-*, ...) is a one-off or scripted encounter: it
# stays in the raw corpus but never feeds a species' wild profile.
# "walk" resolves to "cave" instead of "grass" when the location is a cave.
WILD_METHOD_TERRAIN = {
    "walk": "grass", "overworld": "grass", "wanderer": "grass",
    "grass-spots": "grass", "dark-grass": "grass", "rough-terrain": "grass",
    "yellow-flowers": "grass", "red-flowers": "grass", "purple-flowers": "grass",
    "overworld-flying": "grass", "overworld-flying-special": "grass",
    "overworld-dirt": "grass", "overworld-special": "grass",
    "honey-tree": "grass", "berry-trees": "grass", "headbutt": "grass",
    "headbutt-high": "grass", "headbutt-low": "grass", "headbutt-normal": "grass",
    "sos": "grass", "horde": "grass", "hidden-grotto": "grass",
    "rustling-bush-ambush": "grass", "ground-ambush": "grass",
    "sky-ambush": "grass", "bridge-spots": "grass",
    "cave-spots": "cave", "rock-smash": "cave", "ceiling-ambush": "cave",
    "surf": "water", "surf-spots": "water", "overworld-water": "water",
    "overworld-water-special": "water", "wanderer-water": "water",
    "bubbling-spots": "water", "sos-from-bubbling-spot": "water",
    "chase-water": "water", "seaweed": "water",
    "old-rod": "fish", "good-rod": "fish", "super-rod": "fish",
    "super-rod-spots": "fish", "feebas-tile-fishing": "fish",
}


def wild_terrain(method: str, habitats: list[str]) -> str | None:
    terrain = WILD_METHOD_TERRAIN.get(method)
    if terrain == "grass" and method == "walk" and "cave" in habitats:
        return "cave"
    return terrain

# Useful for keeping the output stable and understandable.
LEVEL_BANDS = [
    ("1-5", 1, 5),
    ("6-9", 6, 9),
    ("10-14", 10, 14),
    ("15-19", 15, 19),
    ("20-24", 20, 24),
    ("25-29", 25, 29),
    ("30-34", 30, 34),
    ("35-39", 35, 39),
    ("40-44", 40, 44),
    ("45-49", 45, 49),
    ("50-54", 50, 54),
    ("55-60", 55, 60),
    ("61-70", 61, 70),
    ("71-80", 71, 80),
    ("81-100", 81, 100),
]

# Broad habitat labels inferred from location names. These are intentionally
# conservative. Claude/Lua should treat them as hints, not hard constraints.
HABITAT_RULES = [
    ("cave", ["cave", "tunnel", "mount", "rock", "mine", "meteor-falls", "victory-road"]),
    ("water", ["sea", "lake", "river", "pond", "marsh", "swamp", "wetland", "island"]),
    ("forest", ["forest", "woods", "wood", "grove", "jungle"]),
    ("mountain", ["mount", "mountain", "cliff", "peak", "volcano", "crater"]),
    ("coast", ["coast", "shore", "beach", "sea", "island"]),
    ("urban", ["city", "town", "town-square", "building", "department-store", "mart"]),
    ("route", ["route"]),
    ("grassland", ["meadow", "field", "plain", "savanna", "prairie"]),
    ("desert", ["desert", "sand"]),
    ("snow", ["snow", "ice", "frost", "glacier", "mountain"]),
    ("ruins", ["ruin", "temple", "tower", "cave-of-origin", "ancient"]),
]


def slug(value: str) -> str:
    value = value.lower().strip()
    value = value.replace("’", "'")
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def habitat_tags(location_name: str) -> list[str]:
    s = location_name.lower()
    tags = []
    for tag, needles in HABITAT_RULES:
        if any(n in s for n in needles):
            tags.append(tag)
    if not tags:
        tags.append("general")
    return sorted(set(tags))


def rarity_from_rate(rate: float | None) -> str:
    if rate is None:
        return "unknown"
    if rate >= 25:
        return "common"
    if rate >= 10:
        return "uncommon"
    if rate >= 3:
        return "rare"
    return "very_rare"


def weighted_mean(items: list[tuple[float, float]]) -> float | None:
    if not items:
        return None
    denom = sum(w for _, w in items)
    if denom <= 0:
        return sum(v for v, _ in items) / len(items)
    return sum(v * w for v, w in items) / denom


class API:
    def __init__(self, cache_dir: Path, refresh: bool = False, timeout: int = 30):
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.refresh = refresh
        self.timeout = timeout
        self._locks: dict[str, threading.Lock] = {}
        self._locks_guard = threading.Lock()
        # URLs already refreshed this run, so --refresh fetches each only once.
        self._fetched: set[str] = set()
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "PokemonSpawnDatasetGenerator/1.0"
        })

    def _cache_path(self, url: str) -> Path:
        import hashlib
        key = hashlib.sha256(url.encode()).hexdigest()
        return self.cache_dir / f"{key}.json"

    def get(self, path_or_url: str) -> dict[str, Any]:
        url = path_or_url if path_or_url.startswith("http") else BASE_URL + path_or_url
        # Serialize per URL: several forms share one species, and worker
        # threads must not read a cache file while another is writing it.
        with self._locks_guard:
            lock = self._locks.setdefault(url, threading.Lock())
        with lock:
            return self._get_locked(url)

    def _get_locked(self, url: str) -> dict[str, Any]:
        cp = self._cache_path(url)

        if cp.exists() and (not self.refresh or url in self._fetched):
            return json.loads(cp.read_text(encoding="utf-8"))

        last_error = None
        for attempt in range(5):
            try:
                r = self.session.get(url, timeout=self.timeout)
            except requests.RequestException as exc:
                last_error = exc
                time.sleep(1.5 * (attempt + 1))
                continue

            # Rate limits and server errors are transient; other client
            # errors (e.g. 404) will not succeed on retry.
            if r.status_code == 429 or r.status_code >= 500:
                last_error = f"HTTP {r.status_code}"
                time.sleep(1.5 * (attempt + 1))
                continue
            if r.status_code >= 400:
                raise RuntimeError(f"Failed to GET {url}: HTTP {r.status_code}")

            data = r.json()
            # Write via a temp file so an interrupted run never leaves a
            # truncated cache entry behind.
            tmp = cp.with_suffix(".tmp")
            tmp.write_text(json.dumps(data), encoding="utf-8")
            os.replace(tmp, cp)
            self._fetched.add(url)
            return data
        raise RuntimeError(f"Failed to GET {url}: {last_error}")

    def get_all(self, endpoint: str, limit: int = 1000) -> list[dict[str, Any]]:
        data = self.get(f"{endpoint}?limit={limit}&offset=0")
        results = list(data["results"])
        count = data["count"]

        offset = len(results)
        while offset < count:
            page = self.get(f"{endpoint}?limit={limit}&offset={offset}")
            results.extend(page["results"])
            offset += len(page["results"])
            if not page["results"]:
                break
        return results


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--workers", type=int, default=8)
    p.add_argument("--refresh", action="store_true")
    p.add_argument("--max-pokemon", type=int, default=None,
                   help="Debug option; limit species count.")
    p.add_argument("--lua", type=Path, default=None,
                   help="Also write the compact dex-keyed Lua profiles the "
                        "modern_spawns mod loads (e.g. ../data/spawn_profiles.lua).")
    return p.parse_args()


def fetch_pokemon_data(api: API, pokemon_ref: dict[str, Any]) -> dict[str, Any]:
    name = pokemon_ref["name"]
    # Resolve the species through the pokemon resource: alternate forms such
    # as "deoxys-normal" have no /pokemon-species/{name} entry of their own.
    pokemon = api.get(f"/pokemon/{name}")
    encounters = api.get(f"/pokemon/{name}/encounters")
    species = api.get(pokemon["species"]["url"])
    return {
        "name": name,
        "id": pokemon["id"],
        "is_default": bool(pokemon.get("is_default", False)),
        "data": encounters,
        "species": species,
    }


def build_raw_encounters(api: API, pokemon_refs: list[dict[str, Any]], workers: int) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], dict[int, str]]:
    """Returns (records, species_metadata by pokemon name, default pokemon
    name by national dex number)."""
    records: list[dict[str, Any]] = []
    species_metadata: dict[str, dict[str, Any]] = {}
    default_by_dex: dict[int, str] = {}

    # Concurrent requests dramatically reduce runtime on a cached/local run,
    # while the API class still caches every response.
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        futures = [ex.submit(fetch_pokemon_data, api, ref) for ref in pokemon_refs]
        for idx, future in enumerate(concurrent.futures.as_completed(futures), 1):
            result = future.result()
            pokemon_name = result["name"]
            species_metadata[pokemon_name] = result["species"]
            if result["is_default"] and result["species"].get("id"):
                default_by_dex[int(result["species"]["id"])] = pokemon_name

            for area in result["data"]:
                location_area = area["location_area"]["name"]
                habitats = habitat_tags(location_area)

                for version_detail in area.get("version_details", []):
                    version = version_detail["version"]["name"]
                    generation = GENERATION_BY_VERSION.get(version)
                    if generation is None:
                        # Unknown/current future version: retain it but mark gen unknown.
                        generation = None

                    for detail in version_detail.get("encounter_details", []):
                        method = detail["method"]["name"]
                        conditions = sorted(
                            c["name"] for c in detail.get("condition_values", [])
                        )

                        records.append({
                            "pokemon": pokemon_name,
                            "generation": generation,
                            "version": version,
                            "is_target_game": version in TARGET_GAMES,
                            "location_area": location_area,
                            "habitats": habitats,
                            "method": method,
                            # None for non-wild (gift/static/trade/raid...).
                            "terrain": wild_terrain(method, habitats),
                            "min_level": detail["min_level"],
                            "max_level": detail["max_level"],
                            "chance": detail.get("chance"),
                            "conditions": conditions,
                        })

            if idx % 100 == 0 or idx == len(pokemon_refs):
                print(f"  processed {idx}/{len(pokemon_refs)} Pokémon")

    # Stable deterministic order.
    records.sort(key=lambda x: (
        x["generation"] if x["generation"] is not None else 99,
        x["version"],
        x["location_area"],
        x["method"],
        x["pokemon"],
        x["min_level"],
        x["max_level"],
        x["chance"] if x["chance"] is not None else -1,
    ))
    return records, species_metadata, default_by_dex


def interval_distance(a_min: float, a_max: float, b_min: float, b_max: float) -> float:
    if a_max < b_min:
        return b_min - a_max
    if b_max < a_min:
        return a_min - b_max
    return 0.0


def build_species_profiles(raw: list[dict[str, Any]], species_metadata: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
    # Only genuine wild encounters describe where and at what level a species
    # is found; gifts, statics, trades and raids would skew both.
    by_species: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in raw:
        if r["terrain"] is not None:
            by_species[r["pokemon"]].append(r)

    profiles: dict[str, dict[str, Any]] = {}

    for pokemon, rows in sorted(by_species.items()):
        all_levels = []
        weighted_levels = []
        generations = set()
        versions = set()
        methods = set()
        habitats = Counter()
        native_rates = []
        encounter_count_by_gen = Counter()
        target_game_encounters = 0
        total_encounters = len(rows)
        locations = set()

        for r in rows:
            all_levels.extend([r["min_level"], r["max_level"]])
            midpoint = (r["min_level"] + r["max_level"]) / 2
            weight = max(float(r["chance"] or 1), 1.0)
            weighted_levels.append((midpoint, weight))
            if r["generation"] is not None:
                generations.add(r["generation"])
                encounter_count_by_gen[r["generation"]] += 1
            versions.add(r["version"])
            methods.add(r["method"])
            habitats.update(r["habitats"])
            locations.add(r["location_area"])
            if r["chance"] is not None:
                native_rates.append(float(r["chance"]))
            if r["is_target_game"]:
                target_game_encounters += 1

        first_level = min(all_levels)
        last_level = max(all_levels)
        typical_level = weighted_mean(weighted_levels)

        # Frequency is based on encounter-slot chance when available. This is
        # a rough cross-game design signal, not a literal global probability.
        mean_rate = sum(native_rates) / len(native_rates) if native_rates else None

        # Build a normalized 0..1 progression curve from the observed level
        # distribution. This is deliberately soft: Lua should score candidates,
        # not treat these as hard eligibility gates.
        progression = {}
        for band_name, lo, hi in LEVEL_BANDS:
            overlap_weight = 0.0
            samples = 0
            for r in rows:
                overlap = max(0, min(hi, r["max_level"]) - max(lo, r["min_level"]) + 1)
                span = max(1, r["max_level"] - r["min_level"] + 1)
                if overlap:
                    samples += 1
                    overlap_weight += overlap / span
            progression[band_name] = round(min(1.0, overlap_weight / max(1, len(rows))), 4)

        # A species with many high-level-only encounters should not be treated
        # as an early-game candidate merely because it has one low-level anomaly.
        rarity = rarity_from_rate(mean_rate)
        species_data = species_metadata.get(pokemon, {})
        introduced = species_generation(species_data)

        is_legendary = bool(species_data.get("is_legendary", False))
        is_mythical = bool(species_data.get("is_mythical", False))
        if is_legendary:
            special_category = "legendary"
        elif is_mythical:
            special_category = "mythical"
        elif rarity == "very_rare":
            special_category = "very_rare"
        elif rarity == "rare":
            special_category = "rare"
        else:
            special_category = "normal"

        is_special = is_legendary or is_mythical or rarity == "very_rare"

        profiles[pokemon] = {
            "species": pokemon,
            "generation_introduced": introduced if introduced is not None else (min(generations) if generations else None),
            "special_spawn": {
                "is_special": is_special,
                "category": special_category,
                "is_legendary": is_legendary,
                "is_mythical": is_mythical,
                "requires_special_handling": is_legendary or is_mythical or rarity == "very_rare",
            },
            "generations_seen": sorted(generations),
            "native_versions": sorted(versions),
            "target_game_encounter_count": target_game_encounters,
            "native_encounter_count": total_encounters,
            "location_count": len(locations),
            "methods": sorted(methods),
            "terrains": sorted({r["terrain"] for r in rows}),
            "habitats": sorted(habitats),
            "progression": {
                "first_wild_level": first_level,
                "last_wild_level": last_level,
                "typical_wild_level": round(typical_level, 2) if typical_level is not None else None,
                "level_bands": progression,
            },
            "rarity": {
                "classification": rarity,
                "mean_slot_chance": round(mean_rate, 3) if mean_rate is not None else None,
            },
            "encounters_by_generation": {
                str(k): v for k, v in sorted(encounter_count_by_gen.items())
            },
        }

    return profiles


def build_progression_pools(profiles: dict[str, dict[str, Any]]) -> dict[str, Any]:
    pools = {}

    for band_name, lo, hi in LEVEL_BANDS:
        candidates = []

        for species, p in profiles.items():
            score = p["progression"]["level_bands"].get(band_name, 0.0)
            if score <= 0:
                continue

            # Keep this score explainable. It is NOT a recommendation.
            # It is simply a ranking signal for the generator.
            generation_count = len(p["generations_seen"])
            diversity_bonus = min(generation_count, 3) * 0.05

            candidates.append({
                "pokemon": species,
                "eligibility_score": round(min(1.0, score + diversity_bonus), 4),
                "level_overlap": score,
                "rarity": p["rarity"]["classification"],
                "habitats": p["habitats"],
                "methods": p["methods"],
                "generation_introduced": p["generation_introduced"],
                "generations_seen": p["generations_seen"],
                "special_spawn": p["special_spawn"],
                "native_versions": p["native_versions"],
            })

        candidates.sort(
            key=lambda x: (-x["eligibility_score"], x["pokemon"])
        )

        pools[band_name] = {
            "min_level": lo,
            "max_level": hi,
            "candidate_count": len(candidates),
            "candidates": candidates,
        }

    return {
        "bands": pools,
        "selection_note": (
            "eligibility_score is a design signal derived from observed "
            "wild-level overlap and generation diversity. It is not an "
            "official Pokémon probability or recommendation."
        ),
    }


def build_special_spawns(profiles: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Return species that need special handling by the runtime generator.

    This is a derived species-level classification, not a complete database of
    scripted/static/event encounters. Those should be represented separately
    when exact story encounters matter.
    """
    special = {}
    for species, profile in profiles.items():
        if profile["special_spawn"]["is_special"]:
            special[species] = profile["special_spawn"]

    counts = Counter(v["category"] for v in special.values())
    return {
        "species": special,
        "counts": dict(sorted(counts.items())),
        "selection_policy": {
            "legendary": "protected_by_default",
            "mythical": "protected_by_default",
            "very_rare": "allowed_only_when_explicitly_enabled",
            "rare": "normal_rarity_handling",
        },
        "warning": (
            "PokéAPI location-area encounters do not guarantee complete coverage "
            "of scripted/static/story/event encounters. Use a separate "
            "special_encounters.json for exact authored encounters when needed."
        ),
    }


def build_target_game_reference(raw: list[dict[str, Any]]) -> dict[str, Any]:
    """
    Produces compact target-game encounter skeletons. These are especially
    useful to Claude: the Lua system can preserve the map's original slot
    count/method/level envelope while replacing species.
    """
    games: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "generation": None,
        "locations": {}
    })

    # De-duplicate identical species/method/level/condition records.
    grouped: dict[tuple, set[str]] = defaultdict(set)

    for r in raw:
        if not r["is_target_game"]:
            continue

        key = (
            r["version"], r["location_area"], r["method"],
            r["min_level"], r["max_level"], tuple(r["conditions"])
        )
        grouped[key].add(r["pokemon"])

    for key, species in grouped.items():
        version, location, method, min_level, max_level, conditions = key
        g = GENERATION_BY_VERSION.get(version)

        loc = games[version]
        loc["generation"] = g
        loc["locations"].setdefault(location, [])
        loc["locations"][location].append({
            "method": method,
            "min_level": min_level,
            "max_level": max_level,
            "conditions": list(conditions),
            "original_species": sorted(species),
        })

    for game in games.values():
        for location, rows in game["locations"].items():
            rows.sort(key=lambda x: (
                x["method"], x["min_level"], x["max_level"],
                x["conditions"], x["original_species"]
            ))

    return dict(sorted(games.items()))


LUA_PROFILE_VERSION = 1
RARITY_CODE = {"common": "c", "uncommon": "u", "rare": "r", "very_rare": "v"}
# A habitat must appear on at least this share of a species' wild records to
# be exported, so one odd location does not make a Pidgey a cave dweller.
HABITAT_MIN_SHARE = 0.15
# Same idea for terrains: a handful of Isle of Armor "walk" rows at sea must
# not turn Tentacool into a grass species. The most common terrain is always
# kept.
TERRAIN_MIN_SHARE = 0.10


def weighted_percentile(items: list[tuple[float, float]], pct: float) -> float:
    ordered = sorted(items)
    total = sum(w for _, w in ordered)
    if total <= 0:
        return ordered[len(ordered) // 2][0]
    target = total * pct
    running = 0.0
    for value, weight in ordered:
        running += weight
        if running >= target:
            return value
    return ordered[-1][0]


def species_generation(species: dict[str, Any]) -> int | None:
    m = re.search(r"generation-(\w+)", (species.get("generation") or {}).get("name", ""))
    if not m:
        return None
    roman = {"i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5, "vi": 6, "vii": 7,
             "viii": 8, "ix": 9}
    token = m.group(1)
    return int(token) if token.isdigit() else roman.get(token)


def build_lua_profiles(raw: list[dict[str, Any]],
                       species_metadata: dict[str, dict[str, Any]],
                       default_by_dex: dict[int, str]) -> dict[str, Any]:
    """Compact, dex-keyed profiles for the Lua mod.

    Only what the game's runtime cannot answer itself: observed wild level
    window, habitats, terrains, rarity, and legendary/mythical status. Keyed
    by national dex number (default variety only) so the mod never has to map
    PokéAPI names onto engine species ids.
    """
    wild_by_pokemon: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in raw:
        if r["terrain"] is not None:
            wild_by_pokemon[r["pokemon"]].append(r)

    species_out: dict[int, dict[str, Any]] = {}
    special_out: dict[int, str] = {}
    generation_out: dict[int, int] = {}

    for dex in sorted(default_by_dex):
        name = default_by_dex[dex]
        meta = species_metadata.get(name, {})
        gen = species_generation(meta)
        if gen is not None:
            generation_out[dex] = gen
        if meta.get("is_legendary"):
            special_out[dex] = "legendary"
        elif meta.get("is_mythical"):
            special_out[dex] = "mythical"

        rows = wild_by_pokemon.get(name)
        if not rows:
            continue
        # Unweighted quartiles: slot chance is not comparable across games,
        # and a p10/p90 window let late-game DLC wanderers stretch Pidgey to
        # 3-56. The interquartile window reads as "where it usually lives".
        mins = [(float(r["min_level"]), 1.0) for r in rows]
        maxs = [(float(r["max_level"]), 1.0) for r in rows]
        mids = [((r["min_level"] + r["max_level"]) / 2, 1.0) for r in rows]
        rates = [float(r["chance"]) for r in rows if r["chance"] is not None]
        mean_rate = sum(rates) / len(rates) if rates else None

        habitat_counts = Counter(h for r in rows for h in r["habitats"])
        habitats = sorted(h for h, n in habitat_counts.items()
                          if h != "general" and n / len(rows) >= HABITAT_MIN_SHARE)
        lo = int(weighted_percentile(mins, 0.25))
        hi = int(weighted_percentile(maxs, 0.75))
        terrain_counts = Counter(r["terrain"] for r in rows)
        main_terrain = terrain_counts.most_common(1)[0][0]
        terrains = sorted(t for t, n in terrain_counts.items()
                          if t == main_terrain or n / len(rows) >= TERRAIN_MIN_SHARE)
        species_out[dex] = {
            "lo": min(lo, hi),
            "hi": max(lo, hi),
            "typ": int(round(weighted_percentile(mids, 0.5))),
            "r": RARITY_CODE.get(rarity_from_rate(mean_rate), "u"),
            "h": habitats,
            "t": terrains,
        }

    return {
        "version": LUA_PROFILE_VERSION,
        "generation": generation_out,
        "special": special_out,
        "species": species_out,
    }


def lua_string_list(values: list[str]) -> str:
    return "{ " + ", ".join(f'"{v}"' for v in values) + " }" if values else "{}"


def write_lua_profiles(path: Path, data: dict[str, Any]):
    lines = [
        "-- Generated by pokemon_spawn_generator/generate_spawn_data.py --lua.",
        "-- PokéAPI-derived wild-encounter profiles, keyed by national dex number.",
        "-- Do not edit by hand; regenerate instead.",
        "return {",
        f"  version = {data['version']},",
        "  generation = {",
    ]
    for dex, gen in sorted(data["generation"].items()):
        lines.append(f"    [{dex}] = {gen},")
    lines.append("  },")
    lines.append("  special = {")
    for dex, cat in sorted(data["special"].items()):
        lines.append(f'    [{dex}] = "{cat}",')
    lines.append("  },")
    lines.append("  species = {")
    for dex, p in sorted(data["species"].items()):
        lines.append(
            f"    [{dex}] = {{ lo = {p['lo']}, hi = {p['hi']}, typ = {p['typ']}, "
            f"r = \"{p['r']}\", h = {lua_string_list(p['h'])}, t = {lua_string_list(p['t'])} }},"
        )
    lines.append("  },")
    lines.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_json(path: Path, obj: Any):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=False),
        encoding="utf-8"
    )


def main():
    args = parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    api = API(CACHE_DIR if args.out == DEFAULT_OUT else args.out / ".cache",
              refresh=args.refresh)

    print("Fetching Pokémon index...")
    pokemon_refs = api.get_all("/pokemon", limit=1000)
    pokemon_refs.sort(key=lambda x: x["name"])

    if args.max_pokemon:
        pokemon_refs = pokemon_refs[:args.max_pokemon]

    print(f"Building encounter corpus for {len(pokemon_refs)} Pokémon...")
    raw, species_metadata, default_by_dex = build_raw_encounters(
        api, pokemon_refs, args.workers)

    print("Building species profiles...")
    profiles = build_species_profiles(raw, species_metadata)

    print("Building special-spawn index...")
    special_spawns = build_special_spawns(profiles)

    print("Building progression pools...")
    pools = build_progression_pools(profiles)

    print("Building target-game reference tables...")
    targets = build_target_game_reference(raw)

    manifest = {
        "schema_version": "1.0.0",
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": "PokéAPI",
        "source_url": BASE_URL,
        "pokemon_count_requested": len(pokemon_refs),
        "pokemon_count_with_encounters": len(profiles),
        "raw_encounter_record_count": len(raw),
        "target_games": sorted(TARGET_GAMES),
        "candidate_generations": list(range(1, 10)),
        "level_bands": [
            {"id": name, "min_level": lo, "max_level": hi}
            for name, lo, hi in LEVEL_BANDS
        ],
        "files": {
            "pokemon_encounters": "pokemon_encounters.json",
            "pokemon_spawn_profiles": "pokemon_spawn_profiles.json",
            "progression_pools": "progression_pools.json",
            "target_game_reference": "target_game_reference.json",
            "special_spawns": "special_spawns.json",
        },
        "notes": [
            "Raw encounter data preserves version, location, method, levels, chance, and conditions.",
            "Spawn profiles are derived design metadata; they are not official game data.",
            "Eligibility scores are generator signals, not encounter probabilities.",
            "Habitat tags are conservative labels inferred from location names.",
            "Target-game reference data is the original encounter skeleton used by the Lua generator.",
            "Legendary/mythical/very-rare status is a derived species-level classification; it is not a complete static/event encounter database.",
            "Red/Blue/Yellow remain in the historical corpus but are not runtime target games.",
        ],
    }

    write_json(args.out / "pokemon_encounters.json", raw)
    write_json(args.out / "pokemon_spawn_profiles.json", profiles)
    write_json(args.out / "progression_pools.json", pools)
    write_json(args.out / "target_game_reference.json", targets)
    write_json(args.out / "special_spawns.json", special_spawns)
    write_json(args.out / "dataset_manifest.json", manifest)

    if args.lua:
        lua = build_lua_profiles(raw, species_metadata, default_by_dex)
        write_lua_profiles(args.lua, lua)
        print(f"Lua profiles: {args.lua.resolve()} "
              f"({len(lua['species'])} with wild data, "
              f"{len(lua['generation'])} species, {len(lua['special'])} special)")

    print()
    print("Done.")
    print(f"Output: {args.out.resolve()}")
    print(f"Raw records: {len(raw):,}")
    print(f"Species with encounters: {len(profiles):,}")
    print("Files:")
    for f in manifest["files"].values():
        print(f"  - {f}")


if __name__ == "__main__":
    main()
