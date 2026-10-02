# NinjaSim

An original Roblox ninja incremental / simulator RPG, written entirely in Luau.

Fight enemies to earn XP and Coins. Level up to unlock ninja ranks from Brown Ninja to Void Ninja, each with its own outfit and katana. Push through 8 areas, beat the bosses, hatch pets, and rebirth for Spirit Shards and permanent upgrades.

## Opening it in Roblox Studio

**Option A: the place file**

1. Open `NinjaSim.rbxl` in Roblox Studio and press **Play**.
2. To make saves persist, publish the place. Then turn on **Game Settings → Security → Enable Studio Access to API Services**. Without that, Studio uses an in-memory save that resets each session, and says so in the Output window.

**Option B: live sync with Rojo** (best for editing code)

1. Install Rojo 7 and its Studio plugin.
2. Run `rojo serve` in this folder.
3. Connect from the plugin in an empty baseplate and press Play.

**Everything is generated when the game runs:** the world (terrain, 8 zones, props, gates, egg stands, boss arenas), characters, katanas, pets and UI. In edit mode you'll only see an empty baseplate, so press Play to see the game.

## Controls

| Action | Keyboard / mouse | Gamepad / touch |
|---|---|---|
| Attack (hold to keep swinging; a press during a swing is queued) | Left click or `F` | R2 / on-screen button |
| Dodge roll (the way you move; standing still hops back) | `Q` or `Left Ctrl` | Circle (PlayStation) / B (Xbox) / Roll button |
| Skills (4 slots) / Skills menu | `1` `2` `3` `4` / `K` | LB, RB, Y, LT / skill bar on the HUD |
| Suit ultimates (unlocked by mastery) | `Z` `X` `C` `V` | D-pad up, right, down, left / ultimate bar on the HUD |
| Shop / Pets / Inventory | `G` / `P` / `I` | HUD buttons |
| Rebirth / Upgrades / Areas / Trophies | `R` / `U` / `M` / `T` | HUD buttons |
| Suits / Trade | `N` / `Y` | HUD buttons |
| Sprint (x1.4 speed) | Hold `Shift` | Click L3 / always on for touch |
| Double jump (with a flip) | `Space` again in the air | Jump again in the air |
| Close menu | `Esc` | B |
| Admin panel (admins only) | `F2` | Admin button (top right) |
| Hatch an egg / unlock a gate / Mutation Machine | Walk up and press the prompt (`E`) | prompt |

## What's in the game

- **Combat:** a four-hit katana combo (horizontal slice left, rising slice right, spin slice right, jumping downward finisher) animated full-body in code, with katana trails, hit stop, a small lunge into each strike and light aim assist. The spin hits all around; the finisher hits harder, launches enemies and slams the ground. It has damage numbers, crits, hit sparks, enemy recoil, knockback, death effects, a combo meter, kill streaks, screen shake and coin fly-ups. Hit detection is server-authoritative (arc + range).
  - **Souls-style pacing** (2026-10-02): swings are slower and heavier (`Combo.Pace`, `Balance.BaseAttackInterval` 0.62 s), each one cuts at most 4 enemies, you walk slowly while a swing plays, and a press during a swing is queued. No weapon reaches further round you than the katana: nunchaku, spear and claw spins lost their extra reach, and only one move per weapon hits all around.
  - **Stamina** (`Balance.Stamina`, `Util/Stamina`): every swing (finishers more) and every dodge spends it; it refills after a short pause. The bar is under your health. The server keeps its own pool and refuses actions it can't cover.
  - **Dodge roll** (`DodgeController`, `CombatService`): Circle / B, `Q` or `Left Ctrl`. Rolls 17 studs the way you move (a backstep standing still), with i-frames that make enemy and boss hits miss ("DODGED!"). You can roll out of a swing's recovery but not its windup.
  - Enemies wind their attacks up for 0.62 s (`Balance.EnemyWindup`) so you can read them and roll through.
- **Skills:** 12 ninja and samurai skills for crowd fights, on 4 hotkey slots with a skill bar (cooldown sweeps) above the XP bar.
  - Shuriken Storm, Whirlwind Slash, Iaido Dash, Wind Step, Smoke Bomb, Kunai Rain, Dragon Flame, Oni Quake, Lightning Blade, Shadow Clone, Bushido Spirit and the Thousand Cuts ultimate: cones, circles, lines, chains, clones, dashes and buffs.
  - Some unlock free by level or ninja tier, the rest are learned with Coins (or Spirit Shards for the ultimate) in the Skills menu (`K`); each levels up to 5.
  - Server authoritative (`SkillService`): ownership, slot, cooldown and targets are checked on the server, and damage uses the player's hit damage, so skills grow with progression. Bosses take skill damage too. Data lives in `Config/Skills.lua`.
- **Elemental tier skills:** every ninja rank also unlocks 2 skills of its colour's element (24 in all), free when you first reach that rank. They stay through rebirths (the unlock reads `BestTier`), and level, equip and cool down like the base skills.

  | Rank | Element | Strong attack | Second skill |
  |---|---|---|---|
  | Brown | Earth | Stone Spikes (line of spikes, knock-up) | Earth Wall (wall that shoves and pins) |
  | Green | Wind | Razor Gale (travelling tornado, 4 hits) | Vine Snare (roots a crowd 3 s) |
  | Blue | Ice | Frost Nova (freezes everything around you) | Blizzard Gust (cone, slows 55%) |
  | Purple | Arcane Lightning | Arcane Storm (8+ bolts on random foes) | Arcane Blink (blink, both ends explode) |
  | Red | Fire | Phoenix Dive (dive and explode, burn) | Ring of Fire (5 s burning ring, slows) |
  | Black | Smoke Storm | Storm Cloud (6 lightning strikes) | Smoke Cyclone (pulls in, launches up) |
  | White | Holy Light | Holy Judgment (pillar of light) | Sanctuary (heals you, sears foes) |
  | Gold | Sun | Solar Flare (huge blinding burst) | Sunbeam (beam, 5 hits) |
  | Crimson | Blood | Crimson Crescent (flying wave, bleed) | Life Drain (tethers that heal you) |
  | Shadow | Darkness | Umbral Grasp (hands grab, then crush) | Eclipse (dome that blinds and slows) |
  | Celestial | Cosmic | Starfall (7+ meteors) | Constellation (star chain that bursts) |
  | Void | Gravity | Black Hole (pulls in, then collapses) | Zero Gravity (enemies float, then slam) |

  - Strong attacks scale from x2.2 (Brown) to x5.5 (Void) of your hit damage per hit. Bosses take the damage but aren't slowed, pulled, launched or floated.
  - The Skills menu has a **Ninja Arts** tab and an **Elements** tab (a block per rank with its two skills; locked ones show the rank and level). A toast and a line in the tier-up cinematic announce new ones.
  - Data: `Config/ElementSkills.lua`; server: `Services/ElementCasts.lua`; looks: `Controllers/ElementEffects.lua`.
  - `SkillService:CastAt(player, skillId, position, level?)` fires any skill at a point with no slot or cooldown (for procs); skills with `PointCast = true` read best that way.
- **Progression:** fast early XP curve (Lv 10 in about 3 minutes). 12 ninja tiers unlock with a cinematic, a new outfit and a matching katana. HP scales with level and tier.
- **8 areas:** Ninja Village, Bamboo Forest, Samurai Village, Demon Valley, Shadow Forest, Volcanic Fortress, Sky Temple and Void Realm.
  - The **Ninja Village** (2026-10-02) is a full-size valley modelled on Kyoto (`ZoneDecor.Village`, `ZoneLayouts.village`): a great vermilion torii over a spawn plaza ringed with cherry trees, Gion street lined with machiya and strings of paper lanterns, a stone-walled canal with weeping cherries and willows, the Ninenzaka lane climbing past a five-storey pagoda to the Kiyomizu stage on its pillars, the golden pavilion over its pond, a tunnel of torii (Fushimi Inari) up to the boss shrine, a dojo and zen garden by the training dummies, cherry blossoms everywhere and forests of cedar, maple and wild cherry on every hill and ridge. Renders: `assets/previews/world/`.
  - Each area has its own terrain, props, lighting, ambient particles, 3 enemy camps, a boss and an egg.
  - Gates unlock by level plus Coins.
- **Enemies:** 24 enemy types across 6 procedural rig archetypes, all with walk, attack, hit and death animation. Stats are derived from level.
- **Bosses:** 8 bosses with health bars, enrage below 35% HP, and summons at 66% and 33%. Their telegraphed attacks are Slam, Shockwave ring, Meteor barrage and Dash. Rewards are shared with everyone who helped, and each boss has a rare katana drop.
- **Rebirth:** resets level, coins and areas for Spirit Shards and a permanent bonus. Unlocks milestones such as the Spirit Egg, auto swing and exclusive cosmetics.
- **Spirit upgrades:** 10 permanent upgrades (XP, Coins, Damage, Speed, Attack Speed, Crit, Luck, Respawn, Double Drop, Shard gain).
- **Shop (not pay-to-win):** everything costs Coins or Shards earned in game.
  - 7 katanas, plus nunchucks, spears and dual claws.
  - Timed boosts that stack to 3 hours.
  - Cosmetics: auras, trails, kill effects and titles.
  - Utility items: sandals, pet slots, storage, triple hatch and auto swing.
- **Pets:** 51 pets across 8 rarities and 9 eggs. Luck-weighted rolls, hatch animation (x1 or x3), equip best, favourites, multi-delete. Pets follow you and are rendered on the client only.
  - Models (2026-10-02): rounded chibi pets built from ellipsoids, with big shiny eyes, blush and a look per species from each pet's `Look` (fox, panda, tanuki, wolf, stag, salamander, maneki-neko, crane, owl, bat, phoenix, serpent and kirin dragons, koi, slimes, oni masks, cloud pup, spirit flames, ninja and samurai minis...). Wings and tails flap about a hinge. Gallery: `assets/previews/pets/gallery.png` (`pet_previews.py ... --gallery`).
  - **Auto-delete:** click a pet in an egg's menu to stop keeping it (up to Epic, so a misclick can't eat a Legendary).
  - **Mutations** (like Grow a Garden): every hatch rolls one, about 1 in 9 overall. A mutation multiplies all of the pet's stats and changes its look everywhere (hatch reveal, cards, detail panel, the follow pet).
    - Big (1 in 15, x1.5, 1.4x size), Golden (1 in 40, x2), Frozen (1 in 90, x2.5), Shocked (1 in 150, x3), Shadow (1 in 300, x4), Rainbow (1 in 500, x5), Giant (1 in 2,000, x8, 2.2x size), Celestial (1 in 25,000, x20).
    - Luck raises every mutation chance by 25% per point of Luck, up to double. Data is in `Config/Mutations.lua`, the looks in `Visuals/MutationLook.lua`.
    - Saved as `Pets[uid].Mutation` (old pets have none). Equip Best and sorting count the multiplier. Mutated pets skip auto-delete, Select All in Multi Delete skips them, and deleting one warns first.
    - Rainbow and rarer are announced to the server; Giant and Celestial get the big banner.
    - Admin panel **Give Pet**: type `golden fox` (or `Rainbow Jade Dragon`) to give that pet, or just `Giant` to make the selected player's next hatch Giant.
    - Previews: `SCENARIO=petshots lune run run.luau` in `tools/playtest`, then `python3 tools/blender/pet_previews.py /tmp/claude-0/petshots/pets.json assets/previews/pets/mutations --ui /tmp/claude-0/petprev/ui`. Pass `UIPREVIEW_ASSETS=/tmp/claude-0/petprev/ui/assets.json` to `tools/uipreview/shoot.mjs` and the UI shots show the rendered pets.
- **Mutation Machine** (`MutationService`, by the village spawn): reroll the mutation of a pet or a hat. A roll costs Coins (more for rarer items), a Lucky Roll 25 Spirit Shards and makes Rainbow, Giant, Celestial and Secret three times as likely. Every roll gives a mutation, sometimes a worse one (rerolling a Rainbow or better asks first). **Secret** (x50 pet stats, a black glitch with shifting neon seams, runes and a galaxy haze) only comes from the machine. Hats take mutations too: x1.1 (Big) up to x3 (Secret) on all their stats, with a name prefix and a recolour.
- **Trading** (`TradeService`, Trade menu, `Y`): invite a player in the server, both put up to 9 pets and hats on the table, both press Ready; any change un-readies both, and after a 3 s countdown the server checks everything again and swaps the items in one step, then saves both players.
- **Suits and mastery** (Blox Fruits style; `Config/Mastery`, `MasteryService`, Suits menu `N`): wear any ninja suit you have reached (it only changes your look). The worn suit gains mastery from kills (bosses give much more) up to 100: +0.5% damage per level, and four ultimates in the suit's element, cast with `Z X C V` from the ultimate bar:
  - Mastery 25, movement: an invulnerable 60 stud rush through everything, bursting at the end.
  - Mastery 50, long range: a 140 stud beam that pierces everything on it five times.
  - Mastery 75, area: three expanding shockwaves up to 46 studs.
  - Mastery 100, awakening: 20 s of x1.75 damage and faster moves and swings; every swing throws a wave and hits heal you.
  - Each suit's four have their own names (Brown's Landslide Rush to Void's Void Emperor) and hit harder on higher suits. Server: `UltimateCasts` via `SkillService:CastUltimate`; looks: `UltimateEffects`. Admin panel: **Set Mastery**.
- **Hat loot (Diablo-style):** every kill has a 1% chance to drop a hat (bosses 25%, training dummies never), only for the players who earned the kill. It lands in a pillar of light coloured by rarity; walk into it (or it flies to you after 6 s) for a toast with its name.
  - 20 base hats (Hachimaki and Straw Kasa in the village up to the Shogun Helm and Void Crown in the Void Realm), each with fixed base stats and the areas it drops in (`Config/Hats.lua`).
  - Rarities: Common (no affixes), Magic (1-2), Rare (3-4), Legendary (4 + an on-hit skill proc), Mythic (5 + a proc, x1.6 rolls). Luck makes better rarities likelier; it never changes the 1% rate.
  - Affixes scale with item level (the enemy's level): damage, crit, max HP, move and attack speed, XP, coins, luck, HP regen, faster regen start, life steal (1 point heals 1% of max HP per kill) and "X% chance on hit to cast <skill>" (2 s cooldown per proc, cast through `SkillService:CastAt`).
  - Hats menu (`H` or the HUD button): rarity grid, a tooltip with base stats, affixes, proc and a green/red comparison with the worn hat, Equip, Lock, Salvage (Coins, plus Shards for Legendary+) and bulk salvage up to Common / Magic / Rare. 60 hats max; a pickup with full storage is salvaged.
  - The hat is worn on the head, fitted over the ninja suit's own head (`Visuals/HatBuilder.lua`). An imported mesh named `Hat_<id>` replaces the part-built hat.
  - Admin panel: **Drop Hat** drops a hat at the selected player; type a rarity in the box (or leave it empty for a normal roll).
- **Inventory:** equip or unequip, compare against what you hold, sort by best, rarity or name, and favourites.
- **Guide:** a glowing trail and marker lead new players to their next goal (training dummies, the first egg, the next gate, the first boss). The Next Goal card opens the menu that finishes the goal. It can be turned off in Settings.
- **Free gifts:** 8 gifts unlock over 45 minutes of play each session (Coins that scale with level, boosts and Shards). The HUD shows a countdown and a badge when one is ready.
- **Daily streak:** a reward every day you join, cycling over 7 days (day 7 gives Spirit Shards). Missing a day resets it.
- **Trophies:** 34 long-term goals (kills, bosses, eggs, coins, level, rank, areas, rebirths, katanas) that pay Spirit Shards, with Claim All.
- **Server events:** every 10 minutes the whole server gets a 3-minute Coin Frenzy, XP Storm or Ninja Rush, with a banner and a HUD countdown (`Config/Events.lua`).
- **Play with friends:** +10% Coins and XP for each friend in the server (up to +30%), shown on the HUD.
- **Shoutouts:** the server announces Legendary+ hatches, rare pet mutations, new high ranks and rebirths to everyone.
- **Top Ninjas board:** a global leaderboard by the village spawn (Rebirths, then Level), stored in an OrderedDataStore. Without DataStore access it ranks the players in the current server.
- **Codes:** `RELEASE`, `NINJA`, `SHURIKEN`, `SPIRIT`, `FOXFRIEND` (see `src/shared/Config/Codes.lua`).
- **Settings:** music and SFX volume, guide trail, damage numbers, screen shake, other players' pets, low graphics, auto swing. There's also a lifetime stats panel.

## Saving

`src/server/Services/DataService.lua` handles saving:

- **Session locking:** `UpdateAsync` with a session lock, so two servers can't overwrite each other.
- **Retries:** failed calls retry with backoff.
- **Autosave:** every 120 s, on leave, and on server shutdown (`BindToClose`).
- **No wipes on failure:** if a load fails, the player is kicked with a friendly message instead of being given a blank save. Unloaded data is never saved.
- **Safe to grow:** new fields in `DataTemplate.lua` are merged into old saves automatically.

## Security

The client only ever asks; the server decides.

- **One validated entry point:** all actions go through one `Request` RemoteFunction. It has a token-bucket rate limit and type checks, and routes each action to a service that re-checks ownership, price, level, distance and cooldown.
- **Combat:** the server checks swing cadence and burst, counts the combo itself (a client can't claim the finisher every swing), and re-does range and arc checks itself. The client never reports damage, XP or currency.
- **Movement:** zone gates are enforced on the server (players are pushed out of locked areas), and large teleports are reverted.

## Project layout

```
default.project.json      Rojo project
src/shared/               ReplicatedStorage.Shared
  Config/                 all game data: Tiers, Katanas, Enemies, Zones, Pets, Mutations, Mastery, Shop, Upgrades, Rebirth, Codes, Gifts, Achievements, Events, Balance, Sounds, Skills
  Visuals/                code-built models: KatanaBuilder, OutfitBuilder, EnemyBuilder, PetBuilder, Particles
  Util/                   Format, TableUtil, Pose, Stamina
  Stats.lua               one function computes every derived stat (used by server and UI)
  DataTemplate.lua        save schema
  Net.lua                 remotes
src/server/               ServerScriptService.Server
  Main.server.lua         boots the world + services
  Services/               Data, Stat, Zone, Character, Progression, Enemy, Boss, Combat, Skill, Mastery, Rebirth, Shop, Pet, Mutation, Trade, Inventory, Event, Gift, Leaderboard, Achievement, Request (+ ElementCasts, UltimateCasts)
  World/                  WorldBuilder, ZoneDecor, Props
src/client/               StarterPlayerScripts.Client
  Main.client.lua         boots the controllers
  Controllers/            Data, UI, Sound, Camera, Notification, Effects, Animation, Combat, Dodge, Skill, Ultimate, Trade, EnemyUI, Boss, Pet, Lighting, World, Guide
  UI/                     Kit (widgets), Theme, HUD, MenuManager, MenuCommon, Overlays, Menus/*
tools/playtest/           headless playtest (see below)
```

## Adding content

Almost everything is data-driven.

- **New katana:** add an entry to `Config/Katanas.lua` with a `Look` table. Set `Source = "Shop"` to sell it, or reference it as a boss `Drop`.
- **New tier:** append to `Config/Tiers.lua` and give it a new katana id.
- **New enemy:** add it to `Config/Enemies.lua`, picking an archetype, colours, hat and weapon. Place it in a zone's `Camps`.
- **New zone:** append to `Config/Zones.lua` with camps, a boss, a theme, lighting and an egg. Add a decor function in `server/World/ZoneDecor.lua` for a unique look.
- **New pet or egg:** add to `Config/Pets.lua`.
- **New shop item, boost, cosmetic or code:** add to `Config/Shop.lua` or `Config/Codes.lua`.
- **New trophy:** append to `Config/Achievements.lua`. Progress is read from the save, so a new stat only needs a reader in `Achievements.Stats`.
- **Gifts and daily rewards:** edit the lists in `Config/Gifts.lua`.
- **Balance:** every formula is in `Config/Balance.lua` (XP curve, enemy HP, rewards, rebirth requirement, shards).
- **Sounds and music:** swap in asset ids in `Config/Sounds.lua`. Music is empty by default; add a sound id per zone.
- **New menu:** create `client/UI/Menus/<Name>.lua` exporting `Build(ctx)`, then add its name to `MENUS` in `MenuManager.lua`.

## 3D models (Blender mesh packs)

Katanas, village props, the player's ninja suit and the enemies also exist as sculpted
Blender meshes. The game uses them when they are imported, and falls back to the
part-built models when they aren't, so it always runs.

- `tools/blender/*.py` build each pack headless with the `bpy` pip package:
  `katanas.py`, `props.py`, `ninja.py` (full-body player suit) and `enemies.py` (with `enemy_body.py`,
  `enemy_gear.py` and `enemy_beasts.py`). `sculpt.py` and `kit.py` hold the sculpting helpers
  (metaballs, skin-modifier limbs, voxel fusing, cloth folds, straps that hug a body).
  Each script writes an FBX, preview renders and a manifest.
- The manifests live in `src/shared/Visuals/Manifests` and hold every mesh's exact size and position.
- `assets/` holds the FBX packs and `assets/previews/` their renders.
  - `NinjaSim_AllAssets.fbx` is every pack merged by `tools/blender/combine.py`: 580 meshes (about 74 MB with the embedded textures) (each under 20k triangles) plus the `UIIconAtlas` plate that carries the UI icons.
  - `combine.py` also checks each mesh against its manifest.
- With the suit imported, the avatar's body parts turn invisible. A sculpted suit is worn over every body part:
  - Hood and mask, gi, obi, sleeves, wraps, gloves and tabi.
  - Per tier: a scarf, samurai armour, a cape, horns and a halo.
  - Pieces scale to the part they dress, so the suit fits R15, R6 and scaled avatars.
- Enemy meshes:
  - Enemy box parts turn invisible under the meshes but still drive animation and hits.
  - `Armor = "Light" | "Full"` and `Menpo = true` in `Config/Enemies.lua` add samurai armour.
- To import:
  1. In Studio, delete any older imported pack first (an old `ReplicatedStorage.NinjaAssets` folder, or an old model in Workspace).
  2. Use Import 3D on `NinjaSim_AllAssets.fbx` with default settings, and leave the model wherever it lands.
  3. Press Play. At startup the server finds the model (in Workspace, ReplicatedStorage or ServerStorage) and moves it into `ReplicatedStorage.NinjaAssets` itself. Output prints "[NinjaSim] Using N imported meshes". A "looks rotated" warning means the import axes were changed.
  - The raw imported model is plain grey. That's expected: the game clones each piece and paints it in code.
  - Moving it into a `NinjaAssets` folder under ReplicatedStorage yourself still works, and keeps the edit-mode view tidy.
- Import 3D turns the packs half a turn about Y, so `Assets.Place` turns every mesh back (fixed 2026-09-30 after faces showed on the back of heads and katanas were held by the blade). If a pack ever arrives already facing the right way, set the attribute `NoImportTurn = true` on `ReplicatedStorage.NinjaAssets`.
- Colours and materials are set in code, so one mesh serves every zone and tier.
- Prop meshes don't collide. Invisible boxes named `Collider` handle collision.
- Headless check of the mesh code paths: `NINJA_MESHES=1 sh tools/playtest/playtest.sh`.

### Combo animations

- The four moves live in `src/shared/Config/Combo.lua`: timings, damage, knockback, arc and one keyframed pose per beat (windup, strike, follow-through). `src/shared/Util/Pose.lua` explains the joint angle signs.
- Joints can be `Motor6D`s or the `AnimationConstraint`s that newer Roblox avatars use (for those the pose goes on `Attachment0`). The first swing prints "[NinjaSim] Combo animates N R15 joints (...)" in Output, or warns with the joints it found when it can't animate.
- `AnimationController` writes the poses through `Motor6D.C0` (blended over the Animator's walk/idle), because in Studio writing `Transform` showed nothing. It plays them on R15 (every joint) and R6 (elbows, wrists and waist folded into the joints R6 has), layered over the default walk and idle.
- To see a change without Studio: `lune run tools/anim/frames.luau /tmp/frames.json 60`, then `python3 tools/blender/anim_preview.py /tmp/frames.json /tmp/anim` renders a key frame sheet per move with the blade tip's path. Add `--gif` (with 30 fps frames) for a GIF of the whole combo, `--stats` to print where the blade points each frame.

### Walking, running and jumping

- R15 characters use Roblox's free Ninja Animation Package for idle, walk, run, jump, fall,
  climb and swim. The ids are in `src/shared/Config/Animations.lua`, and `CharacterService`
  writes them into each character's `Animate` script once its appearance has loaded, so
  they replace the player's own avatar animations. Set `Enabled = false` there to let
  players keep their own. R6 characters keep the default animations.

### Enemy attacks

- Humanoid enemies wind the weapon up high and slash down across the body, timed so
  the blade lands when the server deals the hit. Poses go through `Motor6D.C0`, the
  same way as the player's combo.
- Defeated enemies turn into a local ragdoll (ball-socket joints, knocked away from you)
  that fades out after about 2.5 s. At most 24 lie around at once; the rest topple over.
- Enemy rigs stream in whole (`ModelStreamingMode = Atomic`), and the client retries rigs
  whose parts haven't arrived yet, so they animate in places with StreamingEnabled on.

### Hero models (textured, from the reference sheets)

The Brown, Green and Blue tiers and their katanas (`brown_katana`, `jade_katana`,
`tide_katana`) have hand-matched textured models built from justin's reference sheets.

- `tools/blender/hero_katanas.py` and `tools/blender/hero_ninjas.py` build them;
  `hero.py` (shapes, decal UVs, blade builder, studio render), `patterns.py` (greek keys,
  runes, knots, scrolls, stitches drawn with PIL) and `bake.py` (one shared UV atlas,
  colour x ambient occlusion baked into one PNG) are their helpers.
- Each model ships one baked texture in `assets/textures/` (embedded in the FBX, so Import 3D
  uploads it). Glowing bits (gem eyes, sword gems) are separate `__Glow` meshes the game makes Neon.
- Katanas: one mesh `HeroKatana_<id>`. Its manifest entry also holds `BladeBase`/`BladeTip`
  for the swing trail. `KatanaBuilder` uses it before the kit katana.
- Ninjas: one mesh per body part, `HeroNinja_<tier id>_<Part>` (Head, UpperTorso, LowerTorso and
  the six limb parts per side). Each piece is stretched to the default R15 part size, so
  `OutfitBuilder` welds it exactly like the NSuit pieces, on R15 and R6. The suit brings its
  own yellow face and hands, so the avatar's head is hidden too.
- Since 2026-10-01 all 12 ninja tiers and every katana have hero models in the same style;
  higher-rarity katanas also get stronger trails, sparkles, beams and auras (`KatanaBuilder.rarityEffects`).
- Previews: `assets/previews/hero/`.

### Horde battles and nunchucks

- Every camp spawns `Balance.EnemyDensity` (4x since the 2026-10-02 combat rework, was 10x) as many enemies
  at `HordeHealth` (60%) health, with full XP and 1.5x Coins per kill (`XPMultiplier`, `CoinRewardMultiplier`).
  Zones fill only while someone is in them. At most `MaxAttackers` (3) enemies hit one player at a time;
  the rest circle round. Swings cut up to `MaxTargetsPerSwing` (4) targets.
- Nunchucks are katanas with `Weapon = "Nunchaku"` in `Config/Katanas.lua`, with their own 5-move combo
  (`Combo.Nunchaku`). `NunchakuController` swings the free stick on each client.
- Pets show 1-in-N odds; every egg has a Secret pet (1 in 100K up to 1 in 1B).

### Spears and claws

- Spears are katanas with `Weapon = "Spear"` in `Config/Katanas.lua` (6 in the shop, Uncommon to Divine),
  built from parts in `KatanaBuilder` (shaft, wraps, bands, tassel, ribbons, glowing runes; yari, leaf,
  jumonji, naginata, crescent and celestial heads). Optional imported mesh: `HeroSpear_<id>` (+ `__Glow`).
- `Combo.Spear`: quick jab, double thrust, sweeping spin, rising spin-lift, overhead twirl and a lunging
  piercing finisher. Thrusts reach further (`Reach`) in a narrow lane (`Width`, checked by `CombatService`);
  only the sweeping spin hits all around. The `Grip` pose joint turns the shaft in the hand and `Spin` twirls it
  (`Combo.SpinCFrame`), both applied by `AnimationController` to the grip weld.
- Claws are `Weapon = "Claws"` (6 in the shop, topped by the Divine **Bartuc's Claws**, a katar modelled on
  Diablo II's Bartuc's Cut-Throat). They are dual-wielded: `CharacterService` welds a second model,
  `EquippedOffhand`, to the left hand and removes it on every re-equip. Both claws trail. `Combo.Claws` is
  six fast, light moves alternating hands, ending in a pouncing X-slash. Optional mesh: `HeroClaw_<id>`.
- Previews: `lune run tools/anim/frames.luau /tmp/f.json 60 Spear` then
  `python3 tools/blender/anim_preview.py /tmp/f.json /tmp/out` (spear sheets in `assets/previews/spear/`).

### Hero demons (enemies)

Humanoid and oni enemies wear demon suits built in the same textured style as the brown
ninja: horns, fanged grins, claws, spikes and glowing eyes and scars.

- `tools/blender/hero_demons.py` builds them (it reuses the hero ninja parts):
  `python3 tools/blender/hero_demons.py <out dir> [variant ...]`. Four families
  (hooded ninja demons, demon samurai, oni, imp) make 14 variants, each with its own texture.
- One mesh per R6 part, `HeroDemon_<variant>_<Part>` (Head, Torso, RightArm, LeftArm,
  RightLeg, LeftLeg), made for the enemy rig's part sizes, plus `__Glow` meshes that the game
  lights in the enemy's eye colour (or ember red when its eyes don't glow).
- `Demon = "<variant>"` in `Config/Enemies.lua` picks the suit. When it is imported,
  `EnemyBuilder` hides the rig boxes and drops the hat and armour (a Halo stays). Weapons stay.
- Previews: `assets/previews/demons/`.

## UI look and icons

The UI copies the bright simulator style: candy gradient buttons with diagonal shine
stripes and thick dark outlines, chunky white Fredoka text with a dark stroke, and dark
slate windows with a striped colour header and a big icon breaking out of the corner.

- `src/client/UI/Theme.lua` holds the colours and the paint pairs (`Theme.Paint`), and
  `Kit.lua` holds the building blocks: `Button`, `Window`, `Panel`, `ProgressBar`, `Tabs`, `Icon`, `Badge`, `Rays`.
  `MenuCommon.lua` holds the menu-level pieces: cards, the detail panel, price tags and confirm dialogs.
- Icons are 36 Blender-rendered 3D icons (`tools/blender/icons.py`) packed into one
  1024x1024 atlas, `assets/icons/UIIcons.png`. Their rects are in `src/shared/Visuals/IconAtlas.lua`.
- The atlas rides inside `NinjaSim_AllAssets.fbx` as the texture of a small plate mesh
  called `UIIconAtlas`. Import 3D uploads the texture, and the game reads the mesh's
  TextureID and crops each icon out of it. Output prints "[NinjaSim] UI icons loaded from ...".
- If the icons don't show, upload `assets/icons/UIIcons.png` yourself (Asset Manager > Import),
  then put its `rbxassetid://...` in a String attribute named `IconAtlas` on
  `ReplicatedStorage.NinjaAssets` (or in a StringValue named `IconAtlas` inside it).
- Without the atlas every icon falls back to an emoji, so the UI still works.
- UI previews without Studio: `SCENARIO=uishots NINJA_MESHES=1 lune run run.luau` in
  `tools/playtest` dumps the HUD and every menu to JSON. Then
  `node tools/uipreview/shoot.mjs <dump dir> <out dir>` renders them to PNGs with Playwright's
  Chromium, emulating Roblox's layout rules.

## Admin panel

Press `F2` or the purple Admin button (top right, shown only to admins). Pick a player
on the left, type an amount, message or kick reason in the box, then press a command.

- **Player tab:** give coins or shards (a negative amount takes them away), add levels,
  unlock every area, unlock every skill, heal, god mode, go to, bring, knock out, kick, set the
  worn suit's mastery (type the level).
- **Reset Progress** (for testing): type `RESET` in the box, then press it. It wipes the
  player back to a new save (level, coins, shards, rebirths, items, pets, skills, areas)
  and respawns them. Settings and the daily streak are kept.
- **Server tab:** start any server event, spawn the boss in the selected player's area,
  announce the text in the box to everyone (it goes through Roblox's text filter).
- **Admins tab:** owners appoint or remove admins. Appointed admins are saved in the
  `NinjaSim_Admins` DataStore, so they are admins in every server.

Owners are the game's creator (or rank 255 in the owning group), anyone listed in
`Owners` in `src/shared/Config/Admins.lua`, and everyone while testing in Studio. Put
your user id in `Owners` if the game is published under a different account. The server
checks the rank on every command and prints each one in the server Output.

## UI scale

`UI_SIZE` in `src/client/Controllers/UIController.lua` (0.88) sets how big the HUD and
menus are. The HUD stretches to the real screen edges (inside the device safe area) at
any size.

## Checking the code

- `selene src` runs the linter, with the custom std in `ninjasim_std.yml`.
- `sh tools/playtest/playtest.sh` runs the headless playtest. It needs `rojo` and [Lune](https://github.com/lune-org/lune). It builds the place, runs the real server and client scripts against an emulated engine, and plays a full session:
  - Combat, level-ups and tier unlocks.
  - Shop purchases, eggs (with auto-delete), codes and settings.
  - Free gifts, trophies, server events, the leaderboard, the guide trail and the Next Goal shortcut.
  - Pressing every button in every menu.
  - A rebirth and a boss fight.
  - Death and respawn, then leaving, saving and rejoining (the daily streak must carry over).

  It reports any script error. It can't check rendering or physics, so playtest in Studio for feel.
  - `ONLY=spear,combat sh tools/playtest/playtest.sh` (or `ONLY=... lune run run.luau <place>` in `tools/playtest`) runs just those steps. Every step starts with full stamina.
  - Steps for the 2026-10-02 features: `stamina + dodge`, `suits + mastery`, `mutation machine` and `trading` (with a server-only second player, `E.addServerPlayer`).
  - The `skills` step can stall in the emulator (it did before these changes too); run the others with `ONLY` if it does.
- World previews without Studio: `SCENARIO=worldshots WORLDSHOTS_ZONE=village lune run run.luau <place>` in `tools/playtest`, then `python3 tools/blender/world_preview.py /tmp/claude-0/worldshots/village.json <out dir>` renders an overview and close views of the zone.
