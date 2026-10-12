# Changelog

All notable changes to **Challenges** (Project Zomboid Build 42 mod, id `VB_Challenges`).
Newest version first. Each version lists what players will notice, then technical notes
for server owners and modders.

## [Unreleased]

### Added

- **Carving:** whittle items, carve a wooden spear, make bone tools, carve tool handles
  (Carving 1+), carve wooden utensils, *Master Carver* (15 items, Carving 1+) and
  *Batter Up* (carve a baseball bat or short bat, Carving 7+).
- Carving now appears in the "gain levels" skill challenges.
- **Carpentry:** saw logs into planks, board up windows with planks, rustic builds (log
  walls, stick and log fences), furniture (Carpentry 1+), *Handyman* (6 wooden structures,
  Carpentry 1+), a rain collector (Carpentry 3+), 12 wooden walls (Carpentry 2+) and a
  staircase (Carpentry 3+).

## [0.7.0] - 2026-10-11

> **Breaking:** the mod id changed from `challenges` to `VB_Challenges`. Re-enable the mod
> after updating. Challenge progress from older saves does not carry over.

### Added

- **Supply caches:** reaching a location challenge's building hides a bag of supplies
  somewhere inside it. A hot/cold hint on the challenge card helps you find it.
  Contents scale with your level and the challenge difficulty.
- **Animal challenges:** starter ones anyone can do at a farm (visit a farm, pet, feed or
  water animals, collect eggs, catch an animal) and farming ones for players with Animal
  Care 1+ (milking, shearing, butchering, egg deliveries).
- **Skill milestones:** *First Steps* (reach level 1 in a skill you haven't trained) and
  *Master of the Craft* (reach level 10, offered from level 8).
- **Trapping:** set traps, collect catches, catch rabbits, *Master Trapper*.
- **Tracking:** find and inspect animal tracks, including deer tracks.
- **Foraging:** berries and mushrooms, insects, medicinal plants, firewood and stones,
  forest rarities, and a 40-50 find hard challenge.
- **Fishing:** bass, a big fish, three different species, heavy fish, a 15 lb catfish and
  trophy fish (Fishing 8+).
- **Mechanics:** remove a car radio, install a battery, change tires, strip parts, hotwire
  a car (when you're able to), install or remove many parts.
- **Welding:** welding crafts, metal barricades, metal structures from the build menu.
- **Tailoring:** patch holes, reinforce clothing with denim or leather, sew items,
  leatherworking, and *Laundry Day*.
- **Pottery:** gather clay, shape pottery, turn in kiln-fired pieces, fired bricks.
- **Masonry:** stonecutting, cooking pits, brick and stone structures, walls, a mill or quern.
- **Knapping:** gather flint, knap stone tools, stone blades, heavy axe and maul heads.
- **Glassmaking:** gather broken glass, cast a glass panel, fill a crucible, blow glass,
  make a mirror or jar.
- **Electrical:** salvage electronics, improvised lights, connect and start a generator,
  repair a generator, makeshift radios and HAM radios.
- **Cooking:** sandwiches and burgers, pickling, stews and soups with 3+ ingredients,
  doughs and batters, pies and cakes, sushi, preserving jars.
- Many challenges are only offered when you can do them (skill level, known recipe,
  season). Basic ones in each area are open to everyone as a way into something new.
- Tracking, Pottery, Masonry, Knapping and Glassmaking now appear in the
  "gain levels" skill challenges.
- Sandbox options: **Supply caches at locations** and **Animal challenges** (both on by default).

### Changed

- **Level curve:** early levels come faster and late levels no longer explode. Each level
  costs 35 more points than the last up to level 15, then 15 more. Reaching level 10 now
  takes 1,620 points in total (was 2,910) and level 20 takes 6,545 (was 18,335).
- General foraging challenges no longer count junk and trash.
- The Hard "gain 2 levels" challenge is now called *Expert Training* (was *Mastery*).

### Fixed

- Console warnings `Translator.reportMissingArgumentsFromPastAbuse` for texts with a
  percent sign (risk modifier bonus, vehicle condition, bounty contract).
- Cooking challenges could count one meal twice.
- Level-ups owed after changing "Points needed per level" are granted automatically.

### Technical

- Everything internal is prefixed `VB_Challenges` (Lua table, files, UI classes,
  translation keys `UI_VB_Challenges_*` / `Sandbox_VB_Challenges_*`, sandbox options
  `SandboxVars.VB_Challenges.*`, mod data, options id) to avoid clashing with other mods.
  Players still only see "Challenges".
- Sandbox options renamed: `EnableLocationQuests` → `EnableLocationChallenges`, and new
  `EnableLocationCaches`, `EnableAnimalChallenges`.
- Translation files must write a literal percent sign as `%%`.
- Performance: the HUD and window refresh on a timer instead of every 30 frames, rebuild
  at most once per frame, and delivery item counts are cached briefly.
- Delivery challenges can accept a group of items (`itemGroup`).
- Challenge templates support `goalLevel`, `minStartLevel`, `pointsMult`, `months`,
  `canOffer`, `requiresPerk` / `requiresLevel` and `recipeGroup`.
- Known limitation: vehicle part, barricade, patching, washing and generator challenges are
  checked where the game applies the result, so they may not count in multiplayer.

## [0.6.0]

- Baseline before this changelog: Easy / Medium / Hard challenges, risk modifiers,
  location challenges, level-up rewards (items, XP, tokens, traits), HUD tracker.
