"""Day/night calls the encounter data cannot make (generate_spawn_data.py --time-of-day).

Only the games with a clock (Gold/Silver/Crystal, Diamond/Pearl/Platinum,
HeartGold/SoulSilver) record when a species is out, so everything newer is
classified here, by hand, from what its own Pokédex entries say (the
--tod-report lists them as candidates) and how the species is drawn. Our own
review: never copied from another mod's lists.

OVERRIDES: national dex number -> (code, reason). code is
  "N" / "D"  only at night / only by day (STRICT keeps the species to it)
  "n" / "d"  mostly at night / mostly by day (weighted only)
  None       clear a call the encounter data made (an artifact)

EXPECTED: the Gold/Silver/Crystal reference (their ROM tables' night-only and
day-only grass species). Every run reports where the generated data differs,
so a change in PokéAPI or in the rules never goes unnoticed.
"""

OVERRIDES: dict[int, tuple[str | None, str]] = {
    # Pokédex text alone only ever makes a lean ("n"/"d"): STRICT enforces what
    # the games with a clock actually did, never an entry's flavour. A family
    # member without a call of its own follows these (generate_spawn_data.py).
    # Only clear behaviour counts: active / sleeping at night or by day, basking
    # in sunlight. Glowing, crying at the moon or a mood does not.

    # --- Gen 1-4, where the encounter data has no call or the wrong one
    1: ("d", "napping in bright sunlight; the seed grows from the sun's rays"),
    27: ("d", "at night it burrows into the desert sand to sleep"),
    35: ("n", "full-moon nights bring groups of it out to play (HGSS/GSC Mt. Moon at night)"),
    36: ("n", "strolls on lakes on quiet, moonlit nights"),
    41: ("n", "avoids sunlight; sleeps in caves until sundown (caves keep it out all day)"),
    42: ("n", "flies at night in search of prey"),
    50: ("n", "hates sunlight, comes out only after the sun goes down"),
    52: ("n", "nocturnal; sleeps by day and patrols at night"),
    55: ("n", "appears by waterways at dusk (Crystal: only at night in the grass)"),
    70: ("d", "at night it hooks on to a branch and sleeps"),
    86: ("n", "in daytime it is often found asleep on the seabed"),
    87: ("n", "sleeps under the water by day, looks for food at night"),
    103: ("d", "its heads grow from strong sunlight (Crystal's trees: asleep at night)"),
    110: ("n", "at night, when people are asleep, it goes through the trash"),
    127: ("d", "sleeps in its burrow at night"),
    152: ("d", "loves to bask in the sunlight"),
    171: ("n", "its light rises from the depths of the sea at night"),
    182: ("d", "dances in warm sunlight (not its night-time Oddish family's habit)"),
    186: ("n", "appears on the shores at nightfall; choruses on moonlit nights"),
    196: ("d", "builds power bathing in sunshine; not good at battling at night"),
    197: ("n", "its rings glow when darkness falls"),
    202: ("n", "lives in a dark cave and only moves about at night"),
    215: ("n", "Gold/Silver/Crystal: only at night on routes (Ice Path keeps it out all day)"),
    222: ("d", "Gold/Silver/Crystal: hooked by day"),
    226: ("d", "schools leap over the waves on sunny days"),
    254: ("d", "regulates its temperature by basking in sunlight"),
    269: ("n", "a nocturnal Pokemon drawn to streetlights at night"),
    271: ("n", "nocturnal; sleeps by day and becomes active after dusk"),
    301: ("n", "nocturnal; becomes active at dusk"),
    313: ("n", "lights up and signals at night"),
    314: ("n", "nocturnal; becomes active at nightfall"),
    332: ("n", "unmoving by day, active and hunting at night"),
    337: ("n", "active around the full moon; power from moonlight"),
    338: ("d", "absorbs solar energy during the day"),
    340: ("n", "sleeps in the mud by day, feeds through the night"),
    360: ("n", "gathers on moonlit nights to play"),
    387: ("d", "more energetic the more sunlight there is"),
    388: ("d", "leaves the forest in the daytime to sunbathe"),
    414: ("n", "flutters around at night stealing honey"),
    415: ("d", "the colony clusters into a hive to sleep at night"),
    420: ("d", "sunlight colours it"),
    421: ("d", "blooms in strong sunlight, folds back up when it wanes"),
    426: ("n", "drowsy in daytime, flies off in the evening"),
    449: ("d", "active during the day, burrowed in the sand at night"),
    456: ("n", "the patterns on its fins shine at night"),
    457: ("n", "schools near the surface of the sea at night"),
    470: ("d", "sleeps in patches of sunshine, photosynthesising"),
    # --- Gen 5-9: no game records a time of day; their Pokédex entries
    495: ("d", "moves more swiftly the more sunlight it gets"),
    517: ("n", "appears beside people's pillows late at night"),
    547: ("d", "its cotton grows as long as it bathes in sunlight"),
    551: ("d", "burrows into the sand at sunset and sleeps until sunrise"),
    552: ("d", "won't move much at night; the desert gets cold"),
    562: ("n", "wanders through ruins by night"),
    575: ("n", "marks the stars' positions at night"),
    593: ("n", "schools gather near the surface under a full moon"),
    621: ("d", "warms itself by absorbing sunlight; cannot move when cold"),
    672: ("d", "lives on sunshine and water"),
    694: ("d", "basks in the sun for its energy"),
    695: ("d", "basks in the sun with its frill outspread"),
    713: ("d", "moves about during the day, heals overnight"),
    714: ("n", "emerges from its cave after nightfall"),
    722: ("n", "stores up energy by day, active at night"),
    730: ("n", "leads its colony in song on moonlit nights"),
    734: ("d", "searches for food all day, falls asleep at dusk"),
    735: ("d", "diurnal; always snoozing by nightfall"),
    753: ("n", "sleeps in the sunlight by day, moves around at night"),
    755: ("n", "its forests are toured at night for its shining spores"),
    756: ("n", "lures people astray with its lights at night"),
    829: ("d", "anchors itself and basks in the sun to bloom"),
    929: ("d", "basks in the sun until its fruit ripens"),
    951: ("d", "the more sunlight it bathes in, the spicier it gets"),
    # --- family leans that do not fit
    44: ("n", "Gold/Silver/Crystal: only at night in the grass (Bellossom's sun keeps "
              "the family rule from reaching it)"),
    265: (None, "Wurmple splits into a day butterfly and a night moth"),
    266: (None, "Silcoon becomes Beautifly, not the night moth Dustox"),
    267: (None, "Beautifly is a flower butterfly, not the night moth Dustox"),
    864: (None, "Cursola is a ghost, not Corsola's daytime fishing catch"),
}

EXPECTED: dict[int, str] = {
    # night only in Gold/Silver/Crystal
    43: "N", 44: "N",            # Oddish, Gloom
    49: "N",                     # Venomoth
    92: "N", 93: "N",            # Gastly, Haunter
    163: "N", 164: "N",          # Hoothoot, Noctowl
    167: "N", 168: "N",          # Spinarak, Ariados
    198: "N",                    # Murkrow
    200: "N",                    # Misdreavus
    215: "N",                    # Sneasel
    228: "N",                    # Houndour
    # day only in Gold/Silver/Crystal
    10: "D", 11: "D", 12: "D",   # Caterpie, Metapod, Butterfree
    13: "D", 14: "D", 15: "D",   # Weedle, Kakuna, Beedrill
    16: "D", 17: "D",            # Pidgey, Pidgeotto
    22: "D",                     # Fearow
    83: "D",                     # Farfetch'd
    84: "D", 85: "D",            # Doduo, Dodrio
    161: "D", 162: "D",          # Sentret, Furret
    165: "D", 166: "D",          # Ledyba, Ledian
    187: "D", 188: "D",          # Hoppip, Skiploom
    191: "D",                    # Sunkern
}
