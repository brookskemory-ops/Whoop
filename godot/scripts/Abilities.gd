class_name Abilities
extends RefCounted
## Active abilities, ported from js/abilities.js and since redesigned so each
## class has its OWN exclusive set of mechanics — no ability plays the same
## as another class's (only the base weapon attack is allowed to repeat a
## "shape"). Knight/Archer/Mage have been fully redone with bespoke
## mechanics; Rogue/Cleric/Barbarian still use the older shared mechanics
## (nova/slam/volley/radial/chain/orbit/dash/blink) pending their own pass.

# kind per mechanic: "attack" auto-fires on cooldown, "orbit" is a persistent
# ring synced via sync_orbit(), "movement" fires on the ability button,
# "passive" is applied once per rank via apply_passive() (no cooldown loop).
const KIND := {
	# universal passives (see passives()) and synergy keystones (see keystones())
	"stat": "passive", "keystone": "passive",
	# legacy shared mechanics (rogue/cleric/barbarian, not yet redone)
	"nova": "attack", "slam": "attack", "volley": "attack", "radial": "attack",
	"chain": "attack", "orbit": "orbit", "dash": "movement", "blink": "movement",
	# knight — guardian (control/defense)
	"guard_break": "attack", "seismic_slam": "attack", "lance": "attack", "taunt": "attack",
	"barrier": "attack", "sword_orbit": "orbit", "charge": "movement", "warp_slam": "movement",
	# archer — hunter (precision/traps/patience)
	"arrow_fan": "attack", "snipe": "attack", "trap": "attack", "mark": "attack",
	"bombardment": "attack", "ricochet": "attack", "retreat_shot": "movement", "focus_stacks": "passive",
	# mage — elementalist (area denial/elemental combos)
	"fire_nova": "attack", "meteor_crater": "attack", "cinder_field": "attack", "frost_homing": "attack",
	"chain_lightning": "attack", "arcane_beam": "attack", "arcane_surge": "movement", "mana_shield": "passive",
}

static func _d(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in extra: out[k] = extra[k]
	return out

# Universal in-run passives. Unlike the class abilities above these are shared
# by every class and appear in the level-up roll alongside them, so each choice
# is a decision between deepening one ability and buffing the whole kit. Each
# rank applies ONE `step` (see Player.apply_stat) — effects are incremental, not
# recomputed. `mech` is "stat" so roll()/describe()/apply_pick() can treat them
# uniformly with abilities. `per`/`suffix` drive the level-up card text.
static func passives() -> Array:
	return [
		{"id": "ps_might", "name": "Might", "mech": "stat", "stat": "might", "icon_key": "might", "max_rank": 8, "step": 0.08, "per": 8, "suffix": "% damage", "flavor": "Sharpen every blow", "color": "ff8a5a"},
		{"id": "ps_haste", "name": "Haste", "mech": "stat", "stat": "haste", "icon_key": "haste", "max_rank": 6, "step": 0.06, "per": 6, "suffix": "% faster abilities", "flavor": "Strike more often", "color": "ffe08a"},
		{"id": "ps_reach", "name": "Reach", "mech": "stat", "stat": "reach", "icon_key": "reach", "max_rank": 6, "step": 0.12, "per": 12, "suffix": "% area", "flavor": "Widen every strike", "color": "8ad0ff"},
		{"id": "ps_fortune", "name": "Fortune", "mech": "stat", "stat": "fortune", "icon_key": "fortune", "max_rank": 6, "step": 0.04, "per": 4, "suffix": "% crit chance", "flavor": "Court a luckier edge", "color": "f5e08a"},
		{"id": "ps_precision", "name": "Precision", "mech": "stat", "stat": "precision", "icon_key": "precision", "max_rank": 5, "step": 0.15, "per": 15, "suffix": "% crit damage", "flavor": "Make every crit count", "color": "ffd0a0"},
		{"id": "ps_swift", "name": "Swiftness", "mech": "stat", "stat": "swift", "icon_key": "swift", "max_rank": 5, "step": 0.06, "per": 6, "suffix": "% move speed", "flavor": "Outpace the horde", "color": "a0f0c0"},
		{"id": "ps_vigor", "name": "Vigor", "mech": "stat", "stat": "vigor", "icon_key": "vigor", "max_rank": 6, "step": 20.0, "per": 20, "suffix": " max health", "flavor": "Endure a heavier toll", "color": "ff6a6a"},
		{"id": "ps_growth", "name": "Growth", "mech": "stat", "stat": "growth", "icon_key": "growth", "max_rank": 5, "step": 0.12, "per": 12, "suffix": "% experience", "flavor": "Learn from every kill", "color": "c8a0ff"},
		{"id": "ps_greed", "name": "Greed", "mech": "stat", "stat": "greed", "icon_key": "greed", "max_rank": 5, "step": 0.15, "per": 15, "suffix": "% gold", "flavor": "Pry loose more coin", "color": "f5d24a"},
	]

static func passive_by_id(id: String) -> Dictionary:
	for p in passives():
		if p["id"] == id:
			return p
	return {}

# Weapon evolutions — the survivors-like payoff for committing to a build. Each
# reuses an existing mech with beefed numbers + an extra effect, and is offered
# (once) only when its base ability is maxed AND its paired passive has reached
# `req_rank`. `replaces` names the base ability that is swapped out on pick;
# `max_rank` is 1 so an evolution can't be re-rolled. See roll()/Player.apply_pick.
static func evolutions() -> Array:
	return [
		{"id": "kn_whirl_evo", "name": "Bladestorm", "mech": "sword_orbit", "icon_key": "orbit", "max_rank": 1, "evo": true,
			"replaces": "kn_whirl", "requires": "ps_might", "req_rank": 3,
			"flavor": "A storm of blades encircles you", "count": 6, "count_step": 0, "dmg": 1.1, "dmg_step": 0.0, "dist": 88.0, "speed": 4.2, "size": 20.0, "color": "eaf0ff"},
		{"id": "ar_multi_evo", "name": "Arrow Storm", "mech": "arrow_fan", "icon_key": "volley", "max_rank": 1, "evo": true,
			"replaces": "ar_multi", "requires": "ps_haste", "req_rank": 3,
			"flavor": "Loose an unending storm of arrows", "cd": 0.6, "cd_step": 0.0, "count": 9, "count_step": 0, "dmg": 0.85, "pierce": 3, "size": 6.0, "spread": 1.4, "color": "d6f5d6"},
		{"id": "mg_firenova_evo", "name": "Inferno", "mech": "fire_nova", "icon_key": "nova", "max_rank": 1, "evo": true,
			"replaces": "mg_firenova", "requires": "ps_reach", "req_rank": 3,
			"flavor": "A firestorm engulfs all around you", "cd": 1.6, "cd_step": 0.0, "rad": 150.0, "rad_step": 0.0, "dmg": 1.4, "dmg_step": 0.0, "burn": 6.0, "burn_time": 3.0, "color": "ff5a1a"},
		{"id": "ar_ricochet_evo", "name": "Chain Volley", "mech": "ricochet", "icon_key": "ricochet", "max_rank": 1, "evo": true,
			"replaces": "ar_ricochet", "requires": "ps_fortune", "req_rank": 3,
			"flavor": "A shot that caroms endlessly through the horde", "cd": 1.2, "cd_step": 0.0, "dmg": 1.0, "bounces": 7, "bounce_step": 0, "speed": 440.0, "size": 7.0, "color": "d6f5d6"},
		{"id": "kn_slam_evo", "name": "Tectonic Slam", "mech": "seismic_slam", "icon_key": "slam", "max_rank": 1, "evo": true,
			"replaces": "kn_slam", "requires": "ps_reach", "req_rank": 3,
			"flavor": "The earth splits in a colossal shockwave", "cd": 2.6, "cd_step": 0.0, "rad": 160.0, "rad_step": 0.0, "dmg": 2.6, "dmg_step": 0.0, "knock": 260.0, "color": "d8c49a"},
	]

static func evolution_by_id(id: String) -> Dictionary:
	for e in evolutions():
		if e["id"] == id:
			return e
	return {}

# Ability "tags" the synergy keystones read. Derived from mech (rather than hand-
# tagging every def): "movement" is any movement-kind mech; "fire" is the mage's
# flame mechs (incl. the Inferno evolution, which reuses fire_nova).
const FIRE_MECHS := ["fire_nova", "meteor_crater", "cinder_field"]

static func def_has_tag(def: Dictionary, tag: String) -> bool:
	if def.is_empty():
		return false
	if tag == "movement":
		return KIND.get(def.get("mech", ""), "") == "movement"
	if tag == "fire":
		return def.get("mech", "") in FIRE_MECHS
	return false

static func owns_tag(owned: Dictionary, tag: String) -> bool:
	for id in owned:
		if owned[id] > 0 and def_has_tag(by_id(id), tag):
			return true
	return false

# Synergy keystones — rare, build-defining picks that transform every ability of a
# theme rather than a single one. Offered (once) only when the player owns at least
# one ability with the matching tag. Same option shape as passives; the effect is a
# player flag consumed in activate()/use_movement_ability().
static func keystones() -> Array:
	return [
		{"id": "ks_kindling", "name": "Kindling", "mech": "keystone", "requires_tag": "fire", "max_rank": 1, "icon_key": "nova",
			"flavor": "Your flames cling and spread — every fire ability sets foes ablaze", "color": "ff7a2a", "burn": 5.0, "burn_time": 2.5},
		{"id": "ks_momentum", "name": "Momentum", "mech": "keystone", "requires_tag": "movement", "max_rank": 1, "icon_key": "dash",
			"flavor": "You crash down where you land — movement abilities detonate on arrival", "color": "a0f0c0", "dmg": 1.2, "rad": 70.0},
	]

static func keystone_by_id(id: String) -> Dictionary:
	for k in keystones():
		if k["id"] == id:
			return k
	return {}

# Per-class ability pools. Knight/Archer/Mage: every mechanic below is used
# by exactly one class in the whole roster. Rogue/Cleric/Barbarian keep the
# older shared-mechanic abilities for now (next pass).
static func by_class() -> Dictionary:
	return {
		"knight": [
			{"id": "kn_bash", "name": "Shield Bash", "mech": "guard_break", "icon_key": "nova", "max_rank": 5, "flavor": "Knock foes back around you", "cd": 2.2, "cd_step": 0.15, "rad": 70.0, "rad_step": 12.0, "dmg": 1.2, "dmg_step": 0.4, "knock": 200.0, "color": "dfe7f5"},
			{"id": "kn_slam", "name": "Ground Slam", "mech": "seismic_slam", "icon_key": "slam", "max_rank": 5, "flavor": "Shatter the earth", "cd": 3.0, "cd_step": 0.2, "rad": 80.0, "rad_step": 14.0, "dmg": 1.6, "dmg_step": 0.5, "knock": 140.0, "color": "b9c2d6"},
			{"id": "kn_lance", "name": "Spear Impale", "mech": "lance", "icon_key": "lance", "max_rank": 5, "flavor": "A piercing thrust skewers everything in a line", "cd": 1.8, "cd_step": 0.12, "length": 260.0, "length_step": 20.0, "width": 22.0, "dmg": 1.4, "dmg_step": 0.4, "color": "cdd6e6"},
			{"id": "kn_taunt", "name": "Taunt Roar", "mech": "taunt", "icon_key": "taunt", "max_rank": 5, "flavor": "Roar, pulling foes in and marking them for retribution", "cd": 5.0, "cd_step": 0.3, "rad": 130.0, "rad_step": 15.0, "pull": 220.0, "mult": 1.25, "mult_step": 0.04, "dur": 3.0, "color": "f5e9b0"},
			{"id": "kn_barrier", "name": "Bulwark Stance", "mech": "barrier", "icon_key": "barrier", "max_rank": 5, "flavor": "Raise your shield, absorbing the next blows", "cd": 6.0, "cd_step": 0.4, "shield": 30.0, "shield_step": 8.0, "color": "dfe7f5"},
			{"id": "kn_whirl", "name": "Whirling Blades", "mech": "sword_orbit", "icon_key": "orbit", "max_rank": 5, "flavor": "Swords orbit you", "count": 2, "count_step": 1, "dmg": 0.5, "dmg_step": 0.12, "dist": 70.0, "speed": 3.0, "size": 13.0, "color": "cdd6e6"},
			{"id": "kn_charge", "name": "Valor Charge", "mech": "charge", "icon_key": "dash", "max_rank": 5, "flavor": "Charge, trampling foes", "cd": 4.0, "cd_step": 0.3, "dist": 150.0, "dist_step": 25.0, "dmg": 1.0, "dmg_step": 0.4, "color": "dfe7f5"},
			{"id": "kn_step", "name": "Guardian's Step", "mech": "warp_slam", "icon_key": "blink", "max_rank": 5, "flavor": "Flash aside, slamming down on both ends", "cd": 3.5, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "rad": 55.0, "rad_step": 8.0, "dmg": 0.6, "dmg_step": 0.15, "color": "dfe7f5"},
		],
		"archer": [
			{"id": "ar_multi", "name": "Multishot", "mech": "arrow_fan", "icon_key": "volley", "max_rank": 6, "flavor": "Fan of arrows", "cd": 1.3, "cd_step": 0.08, "count": 3, "count_step": 1, "dmg": 0.7, "pierce": 1, "size": 5.0, "color": "cdeccd"},
			{"id": "ar_snipe", "name": "Called Shot", "mech": "snipe", "icon_key": "snipe", "max_rank": 5, "flavor": "A perfect shot on the farthest foe, guaranteed to crit", "cd": 3.2, "cd_step": 0.2, "dmg": 2.2, "dmg_step": 0.6, "color": "a9e6b4"},
			{"id": "ar_trap", "name": "Explosive Trap", "mech": "trap", "icon_key": "trap", "max_rank": 5, "flavor": "Plant a trap that detonates when a foe nears", "cd": 3.0, "cd_step": 0.2, "dmg": 0.9, "dmg_step": 0.25, "rad": 70.0, "rad_step": 10.0, "trigger": 50.0, "color": "cdeccd"},
			{"id": "ar_mark", "name": "Hunter's Mark", "mech": "mark", "icon_key": "mark", "max_rank": 5, "flavor": "Mark the nearest foe; marked foes take bonus damage from everything", "cd": 4.5, "cd_step": 0.3, "mult": 1.3, "mult_step": 0.05, "dur": 4.0, "color": "a9e6b4"},
			{"id": "ar_bombard", "name": "Bombardment", "mech": "bombardment", "icon_key": "bombardment", "max_rank": 5, "flavor": "Call a telegraphed strike on a foe's position", "cd": 2.6, "cd_step": 0.16, "dmg": 1.3, "dmg_step": 0.4, "rad": 75.0, "rad_step": 12.0, "delay": 0.75, "color": "bfe0bf"},
			{"id": "ar_ricochet", "name": "Ricochet Shot", "mech": "ricochet", "icon_key": "ricochet", "max_rank": 6, "flavor": "A shot that physically bounces between foes", "cd": 1.7, "cd_step": 0.1, "dmg": 0.8, "bounces": 2, "bounce_step": 1, "speed": 380.0, "size": 6.0, "color": "cdeccd"},
			{"id": "ar_retreat", "name": "Disengage", "mech": "retreat_shot", "icon_key": "dash", "max_rank": 5, "flavor": "Leap back, loosing a suppressing volley", "cd": 2.8, "cd_step": 0.25, "dist": 130.0, "dist_step": 18.0, "dmg": 0.5, "color": "cdeccd"},
			{"id": "ar_focus", "name": "Eagle Eye", "mech": "focus_stacks", "icon_key": "focus", "max_rank": 5, "flavor": "Standing still sharpens your aim, stacking bonus crit chance", "stacks": 4, "stacks_step": 1, "step": 0.05, "color": "cdeccd"},
		],
		"mage": [
			{"id": "mg_firenova", "name": "Fire Nova", "mech": "fire_nova", "icon_key": "nova", "max_rank": 6, "flavor": "Erupt in flame, igniting nearby foes", "cd": 2.0, "cd_step": 0.12, "rad": 90.0, "rad_step": 14.0, "dmg": 1.0, "dmg_step": 0.35, "burn": 3.0, "burn_time": 2.0, "color": "ff7a2a"},
			{"id": "mg_meteor", "name": "Meteor", "mech": "meteor_crater", "icon_key": "slam", "max_rank": 5, "flavor": "Call down a meteor that leaves a burning crater", "cd": 3.0, "cd_step": 0.2, "rad": 95.0, "rad_step": 16.0, "dmg": 2.0, "dmg_step": 0.6, "zone_dps": 4.0, "zone_time": 2.5, "color": "ff9a4a"},
			{"id": "mg_cinder", "name": "Cinder Field", "mech": "cinder_field", "icon_key": "zone", "max_rank": 5, "flavor": "Drop a lingering field of fire", "cd": 3.2, "cd_step": 0.2, "dps_mult": 0.35, "dps_step": 0.08, "rad": 70.0, "rad_step": 10.0, "dur": 3.0, "color": "ff9a4a"},
			{"id": "mg_frostbolt", "name": "Frost Bolt", "mech": "frost_homing", "icon_key": "volley", "max_rank": 5, "flavor": "A homing bolt of frost that slows on impact", "cd": 1.6, "cd_step": 0.1, "dmg": 1.1, "dmg_step": 0.3, "speed": 260.0, "size": 7.0, "slow": 1.0, "color": "7fd0ff"},
			{"id": "mg_chain", "name": "Chain Lightning", "mech": "chain_lightning", "icon_key": "chain", "max_rank": 6, "flavor": "Lightning arcs between foes", "cd": 1.8, "cd_step": 0.12, "targets": 3, "target_step": 1, "dmg": 1.1, "color": "bfe6ff"},
			{"id": "mg_beam", "name": "Arcane Beam", "mech": "arcane_beam", "icon_key": "beam", "max_rank": 5, "flavor": "Channel a piercing, chilling beam", "cd": 2.2, "cd_step": 0.15, "length": 220.0, "length_step": 20.0, "width": 24.0, "dmg": 0.7, "dmg_step": 0.2, "slow": 0.6, "color": "6aa9ff"},
			{"id": "mg_surge", "name": "Arcane Surge", "mech": "arcane_surge", "icon_key": "dash", "max_rank": 5, "flavor": "Surge forward, leaving a detonating afterimage", "cd": 3.2, "cd_step": 0.25, "dist": 150.0, "dist_step": 20.0, "rad": 55.0, "rad_step": 8.0, "dmg": 0.6, "dmg_step": 0.2, "color": "6aa9ff"},
			{"id": "mg_shield", "name": "Mana Shield", "mech": "mana_shield", "icon_key": "shield", "max_rank": 5, "flavor": "A regenerating shield absorbs damage before your health", "shield": 24.0, "shield_step": 8.0, "regen": 2.0, "regen_step": 0.5, "color": "6aa9ff"},
		],
		"rogue": [
			{"id": "rg_fan", "name": "Fan of Knives", "mech": "volley", "icon": "knife fan", "max_rank": 6, "flavor": "Spray of knives", "cd": 1.1, "cd_step": 0.07, "count": 3, "count_step": 1, "dmg": 0.6, "size": 5.0, "spread": 0.9, "color": "f4dd8a"},
			{"id": "rg_poison", "name": "Poison Cloud", "mech": "slam", "icon": "poison cloud", "max_rank": 5, "flavor": "Choking venom", "cd": 2.6, "cd_step": 0.18, "rad": 80.0, "rad_step": 14.0, "dmg": 1.0, "dmg_step": 0.35, "slow": 1.0, "color": "9bd34a"},
			{"id": "rg_flurry", "name": "Blade Flurry", "mech": "nova", "icon": "spin slash", "max_rank": 5, "flavor": "Spin, cutting all nearby", "cd": 1.9, "cd_step": 0.13, "rad": 65.0, "rad_step": 10.0, "dmg": 1.1, "dmg_step": 0.35, "color": "f4dd8a"},
			{"id": "rg_burst", "name": "Knife Storm", "mech": "radial", "icon": "knife burst", "max_rank": 5, "flavor": "Knives in all directions", "cd": 2.2, "cd_step": 0.14, "count": 7, "count_step": 2, "dmg": 0.55, "size": 5.0, "color": "f4dd8a"},
			{"id": "rg_backstab", "name": "Backstab Chain", "mech": "chain", "icon": "dagger leap", "max_rank": 5, "flavor": "Dagger leaps foe to foe", "cd": 1.7, "cd_step": 0.11, "targets": 3, "target_step": 1, "dmg": 1.0, "color": "f4dd8a"},
			{"id": "rg_knives", "name": "Whirling Knives", "mech": "orbit", "icon": "orbiting knife", "max_rank": 5, "flavor": "Knives orbit you", "count": 3, "count_step": 1, "dmg": 0.45, "dmg_step": 0.1, "dist": 60.0, "speed": 4.0, "size": 10.0, "color": "f4dd8a"},
			{"id": "rg_shadow", "name": "Shadow Dash", "mech": "dash", "icon": "shadow slash", "max_rank": 6, "flavor": "Slip through foes, cutting them", "cd": 2.0, "cd_step": 0.2, "dist": 150.0, "dist_step": 16.0, "dmg": 1.2, "dmg_step": 0.35, "color": "cdb0ff"},
			{"id": "rg_smoke", "name": "Smoke Step", "mech": "blink", "icon": "smoke puff", "max_rank": 5, "flavor": "Vanish in smoke", "cd": 3.0, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "b0b0c0"},
		],
		"cleric": [
			{"id": "cl_holynova", "name": "Holy Nova", "mech": "nova", "icon": "holy burst", "max_rank": 6, "flavor": "Burst of light, heals you", "cd": 2.2, "cd_step": 0.13, "rad": 90.0, "rad_step": 12.0, "dmg": 1.0, "dmg_step": 0.3, "heal": 10.0, "color": "fff3c4"},
			{"id": "cl_smite", "name": "Smite", "mech": "slam", "icon": "holy pillar", "max_rank": 5, "flavor": "Pillar of holy fire", "cd": 2.6, "cd_step": 0.18, "rad": 80.0, "rad_step": 14.0, "dmg": 1.8, "dmg_step": 0.5, "color": "fff3c4"},
			{"id": "cl_bolts", "name": "Holy Bolts", "mech": "volley", "icon": "light bolt", "max_rank": 5, "flavor": "Bolts of light", "cd": 1.5, "cd_step": 0.1, "count": 2, "count_step": 1, "dmg": 0.9, "pierce": 1, "size": 6.0, "color": "fff3c4"},
			{"id": "cl_radiance", "name": "Radiant Burst", "mech": "radial", "icon": "radiant motes", "max_rank": 5, "flavor": "Holy motes fly outward", "cd": 2.6, "cd_step": 0.16, "count": 6, "count_step": 2, "dmg": 0.6, "size": 6.0, "color": "fff3c4"},
			{"id": "cl_judgment", "name": "Judgment", "mech": "chain", "icon": "light arc", "max_rank": 5, "flavor": "Light leaps between foes", "cd": 2.0, "cd_step": 0.13, "targets": 3, "target_step": 1, "dmg": 1.0, "color": "fff3c4"},
			{"id": "cl_censers", "name": "Censers", "mech": "orbit", "icon": "orbiting censer", "max_rank": 5, "flavor": "Holy flames orbit you", "count": 2, "count_step": 1, "dmg": 0.5, "dmg_step": 0.12, "dist": 74.0, "speed": 2.6, "size": 13.0, "color": "fff3c4"},
			{"id": "cl_sancdash", "name": "Sanctified Dash", "mech": "dash", "icon": "wings of light", "max_rank": 5, "flavor": "Dash on wings of light", "cd": 3.0, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "fff3c4"},
			{"id": "cl_step", "name": "Divine Step", "mech": "blink", "icon": "divine flash", "max_rank": 5, "flavor": "Teleport in a flash of light", "cd": 3.4, "cd_step": 0.3, "dist": 140.0, "dist_step": 18.0, "color": "fff3c4"},
		],
		"barbarian": [
			{"id": "bb_cleave", "name": "Cleave", "mech": "nova", "icon": "sweeping axe", "max_rank": 5, "flavor": "Brutal sweeping cleave", "cd": 1.8, "cd_step": 0.12, "rad": 80.0, "rad_step": 12.0, "dmg": 1.3, "dmg_step": 0.4, "knock": 120.0, "color": "e89a8a"},
			{"id": "bb_quake", "name": "Earthquake", "mech": "slam", "icon": "ground crack", "max_rank": 5, "flavor": "The ground erupts", "cd": 3.0, "cd_step": 0.2, "rad": 100.0, "rad_step": 16.0, "dmg": 1.7, "dmg_step": 0.5, "knock": 160.0, "color": "c08050"},
			{"id": "bb_axes", "name": "Axe Throw", "mech": "volley", "icon": "thrown axe", "max_rank": 5, "flavor": "Hurl heavy axes", "cd": 1.6, "cd_step": 0.1, "count": 1, "count_step": 1, "dmg": 1.6, "pierce": 3, "size": 9.0, "speed": 380.0, "color": "d98c5a"},
			{"id": "bb_storm", "name": "Axe Storm", "mech": "radial", "icon": "axe burst", "max_rank": 5, "flavor": "Axes fly in all directions", "cd": 2.8, "cd_step": 0.18, "count": 7, "count_step": 2, "dmg": 0.6, "pierce": 1, "size": 8.0, "speed": 360.0, "color": "d98c5a"},
			{"id": "bb_frenzy", "name": "Frenzied Swings", "mech": "chain", "icon": "axe frenzy", "max_rank": 5, "flavor": "Axe blows leap foe to foe", "cd": 1.9, "cd_step": 0.12, "targets": 3, "target_step": 1, "dmg": 1.1, "color": "e89a8a"},
			{"id": "bb_whirlwind", "name": "Whirlwind", "mech": "orbit", "icon": "orbiting axe", "max_rank": 6, "flavor": "Axes whirl about you", "count": 2, "count_step": 1, "dmg": 0.55, "dmg_step": 0.12, "dist": 66.0, "speed": 3.4, "size": 16.0, "color": "e2655a"},
			{"id": "bb_rush", "name": "Battle Rush", "mech": "dash", "icon": "charging rush", "max_rank": 6, "flavor": "Charge, smashing through ranks", "cd": 2.5, "cd_step": 0.2, "dist": 160.0, "dist_step": 20.0, "dmg": 1.4, "dmg_step": 0.4, "color": "e2655a"},
			{"id": "bb_leap", "name": "Berserker's Leap", "mech": "blink", "icon": "leaping roar", "max_rank": 5, "flavor": "Leap clear of the fray, roaring", "cd": 3.6, "cd_step": 0.3, "dist": 150.0, "dist_step": 20.0, "color": "e2655a"},
		],
	}

static func by_id(id: String) -> Dictionary:
	for cls in by_class():
		for a in by_class()[cls]:
			if a["id"] == id:
				return a
	# Universal passives and evolutions live in their own pools but share the
	# skills[] array, so lookups (physics loop, owned_ranks) must resolve them too.
	var ps := passive_by_id(id)
	if not ps.is_empty():
		return ps
	var ev := evolution_by_id(id)
	if not ev.is_empty():
		return ev
	return keystone_by_id(id)

static func kind_of(def: Dictionary) -> String:
	return KIND[def["mech"]]

static func cooldown(def: Dictionary, rank: int) -> float:
	var cd_min := 1.0
	match def["mech"]:
		"volley", "arrow_fan": cd_min = 0.6
		"radial", "chain", "chain_lightning", "lance": cd_min = 1.2
		"dash", "charge", "retreat_shot": cd_min = 1.5
		"blink", "warp_slam", "arcane_surge": cd_min = 2.0
	return maxf(cd_min, def["cd"] - def.get("cd_step", 0.0) * (rank - 1))

static func describe(def: Dictionary, rank: int) -> String:
	var f: String = def["flavor"]
	match def["mech"]:
		"stat":
			# Cumulative bonus at this rank (e.g. "+16% damage" at Might rank 2).
			var total: float = def["per"] * rank
			var sign := "-" if def["stat"] == "haste" else "+"
			var num := "%d" % roundi(total)
			return "%s — %s%s%s" % [f, sign, num, def["suffix"]]
		"keystone":
			return f   # keystone flavor already states the whole effect
		"nova", "slam", "guard_break", "seismic_slam", "fire_nova":
			return "%s — %d%% dmg, %d radius" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100), roundi(def["rad"] + def.get("rad_step", 0.0) * (rank - 1))]
		"meteor_crater":
			return "%s — %d%% dmg, %d radius, burning crater" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100), roundi(def["rad"] + def.get("rad_step", 0.0) * (rank - 1))]
		"volley", "arrow_fan":
			return "%s — %d projectiles" % [f, def["count"] + def.get("count_step", 1) * (rank - 1)]
		"radial":
			return "%s — %d bolts outward" % [f, def["count"] + def.get("count_step", 2) * (rank - 1)]
		"chain", "chain_lightning":
			return "%s — leaps to %d foes" % [f, def["targets"] + def.get("target_step", 1) * (rank - 1)]
		"orbit", "sword_orbit":
			return "%s — %d orbiting, %d%% dmg" % [f, def["count"] + def.get("count_step", 1) * (rank - 1), roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100)]
		"dash", "blink", "charge":
			return "%s — %d dist" % [f, roundi(def["dist"] + def.get("dist_step", 0.0) * (rank - 1))]
		"warp_slam":
			return "%s — %d dist, %d%% dmg on both ends" % [f, roundi(def["dist"] + def.get("dist_step", 0.0) * (rank - 1)), roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100)]
		"lance", "arcane_beam":
			return "%s — %d%% dmg, %d range" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100), roundi(def["length"] + def.get("length_step", 0.0) * (rank - 1))]
		"taunt":
			return "%s — +%d%% dmg taken, %d radius" % [f, roundi((def["mult"] + def.get("mult_step", 0.0) * (rank - 1) - 1.0) * 100), roundi(def["rad"] + def.get("rad_step", 0.0) * (rank - 1))]
		"barrier":
			return "%s — %d shield" % [f, roundi(def["shield"] + def.get("shield_step", 0.0) * (rank - 1))]
		"trap":
			return "%s — %d%% dmg, %d radius" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100), roundi(def["rad"] + def.get("rad_step", 0.0) * (rank - 1))]
		"mark":
			return "%s — +%d%% dmg taken for %ds" % [f, roundi((def["mult"] + def.get("mult_step", 0.0) * (rank - 1) - 1.0) * 100), roundi(def["dur"])]
		"bombardment":
			return "%s — %d%% dmg, %d radius" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100), roundi(def["rad"] + def.get("rad_step", 0.0) * (rank - 1))]
		"ricochet":
			return "%s — bounces to %d foes" % [f, def["bounces"] + def.get("bounce_step", 1) * (rank - 1)]
		"snipe":
			return "%s — %d%% dmg, always crits" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100)]
		"retreat_shot":
			return "%s — %d dist" % [f, roundi(def["dist"] + def.get("dist_step", 0.0) * (rank - 1))]
		"focus_stacks":
			var stacks: int = def["stacks"] + def.get("stacks_step", 0) * (rank - 1)
			return "%s — up to +%d%% crit" % [f, roundi(stacks * def["step"] * 100)]
		"cinder_field":
			return "%s — %d%% dps, %d radius" % [f, roundi((def["dps_mult"] + def.get("dps_step", 0.0) * (rank - 1)) * 100), roundi(def["rad"] + def.get("rad_step", 0.0) * (rank - 1))]
		"frost_homing":
			return "%s — %d%% dmg, homing + slows" % [f, roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100)]
		"arcane_surge":
			return "%s — %d dist, %d%% dmg burst" % [f, roundi(def["dist"] + def.get("dist_step", 0.0) * (rank - 1)), roundi((def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * 100)]
		"mana_shield":
			return "%s — %d shield, regen %d/s" % [f, roundi(def["shield"] + def.get("shield_step", 0.0) * (rank - 1)), roundi(def["regen"] + def.get("regen_step", 0.0) * (rank - 1))]
	return f

static func sync_orbit(def: Dictionary, player: Player, rank: int) -> void:
	var count: int = def["count"] + def.get("count_step", 1) * (rank - 1)
	var mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
	player.sync_orbit_group(def["id"], count, mult, def.get("dist", 70.0), def.get("speed", 2.8), def.get("size", 14.0), Color(def["color"]))

## Passive abilities (Archer's Eagle Eye, Mage's Mana Shield) apply their
## effect directly to player stats once per rank instead of running through
## the cooldown loop in activate().
static func apply_passive(def: Dictionary, player: Player, rank: int) -> void:
	match def["mech"]:
		"focus_stacks":
			player.focus_rank = rank
			player.focus_max_stacks = def["stacks"] + def.get("stacks_step", 0) * (rank - 1)
			player.focus_step = def["step"]
		"mana_shield":
			var new_max: float = def["shield"] + def.get("shield_step", 0.0) * (rank - 1)
			var delta: float = new_max - player.shield_max
			player.shield_max = new_max
			player.shield = minf(player.shield_max, player.shield + delta)
			player.shield_regen = def["regen"] + def.get("regen_step", 0.0) * (rank - 1)

static func activate(def: Dictionary, player: Player, main: Node, rank: int) -> void:
	var col := Color(def["color"])
	match def["mech"]:
		"nova", "guard_break", "fire_nova":
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			var mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			var opts := {"color": col}
			if def.has("slow"): opts["slow"] = def["slow"]
			if def.has("knock"): opts["knockback"] = def["knock"]
			if def.has("burn"): opts["burn_dps"] = def["burn"]; opts["burn_time"] = def.get("burn_time", 2.0)
			# Kindling keystone: every fire ability ignites, even those without burn.
			if def["mech"] in FIRE_MECHS and player.fire_burn_bonus > 0.0:
				opts["burn_dps"] = maxf(opts.get("burn_dps", 0.0), player.fire_burn_bonus)
				opts["burn_time"] = maxf(opts.get("burn_time", 0.0), player.fire_burn_time)
			main.area_damage(player.global_position, rad, mult, opts)
			var world := main.get_node("World")
			Vfx.ring(world, player.global_position, col, rad, 0.35)
			Vfx.burst(world, player.global_position, col, 10, 140.0, 0.3, 3.0)
			if def.has("heal"): player.hp = min(player.max_hp, player.hp + def["heal"])
		"slam", "seismic_slam":
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			if t == null: return
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			var mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			var opts := {"color": col}
			if def.has("slow"): opts["slow"] = def["slow"]
			if def.has("knock"): opts["knockback"] = def["knock"]
			main.area_damage(t.global_position, rad, mult, opts)
			var world := main.get_node("World")
			Vfx.ring(world, t.global_position, col, rad, 0.35)
			Vfx.burst(world, t.global_position, col, 12, 160.0, 0.3, 3.0)
		"meteor_crater":
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			if t == null: return
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			var mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			var opts := {"color": col}
			if player.fire_burn_bonus > 0.0:   # Kindling: meteor impact also ignites
				opts["burn_dps"] = player.fire_burn_bonus
				opts["burn_time"] = player.fire_burn_time
			main.area_damage(t.global_position, rad, mult, opts)
			main.spawn_zone(t.global_position, rad * 0.8, def.get("zone_dps", 4.0), def.get("zone_time", 2.5), col)
			var world := main.get_node("World")
			Vfx.ring(world, t.global_position, col, rad, 0.35)
			Vfx.burst(world, t.global_position, col, 12, 160.0, 0.3, 3.0)
		"volley", "arrow_fan":
			var base: float = main.dir_to_nearest(player.global_position)
			var n: int = def["count"] + def.get("count_step", 1) * (rank - 1)
			var spread: float = def.get("spread", 0.6)
			for i in n:
				var a: float = base if n == 1 else base + (i - (n - 1) / 2.0) * (spread / n)
				main.spawn_player_projectile(player.global_position, Vector2(cos(a), sin(a)) * def.get("speed", 460.0), player.damage * def.get("dmg", 0.8), false, def.get("pierce", 0), def.get("size", 6.0), col)
		"radial":
			var n: int = def["count"] + def.get("count_step", 2) * (rank - 1)
			for i in n:
				var a := (float(i) / n) * TAU
				main.spawn_player_projectile(player.global_position, Vector2(cos(a), sin(a)) * def.get("speed", 380.0), player.damage * def.get("dmg", 0.7), false, def.get("pierce", 0), def.get("size", 6.0), col)
		"chain", "chain_lightning":
			var hops: int = def["targets"] + def.get("target_step", 1) * (rank - 1)
			var seen := {}
			var from := player.global_position
			for i in hops:
				var best: Node2D = null
				var bd := INF
				for e in main.get_tree().get_nodes_in_group("enemies"):
					if seen.has(e.get_instance_id()): continue
					var d: float = from.distance_squared_to(e.global_position)
					if d < bd: bd = d; best = e
				if best == null: break
				seen[best.get_instance_id()] = true
				Vfx.chain_link(main.get_node("World"), from, best.global_position, col, 2.5, 0.25)
				best.take_damage(player.damage * def.get("dmg", 1.1), false)
				Vfx.burst(main.get_node("World"), best.global_position, col, 5, 90.0, 0.2, 2.0)
				from = best.global_position
		"lance":
			var length: float = def["length"] + def.get("length_step", 0.0) * (rank - 1)
			var a: float = main.dir_to_nearest(player.global_position)
			var dmg: float = player.damage * (def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1))
			main.line_damage(player.global_position, Vector2(cos(a), sin(a)), length, def.get("width", 20.0), dmg, {"color": col, "vfx_width": 6.0})
		"arcane_beam":
			var length: float = def["length"] + def.get("length_step", 0.0) * (rank - 1)
			var a: float = main.dir_to_nearest(player.global_position)
			var dir := Vector2(cos(a), sin(a))
			var dmg: float = player.damage * (def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1))
			var opts := {"color": col, "vfx_width": 5.0}
			if def.has("slow"): opts["slow"] = def["slow"]
			main.line_damage(player.global_position, dir, length, def.get("width", 20.0), dmg, opts)
			main.get_tree().create_timer(0.15).timeout.connect(func():
				if is_instance_valid(player): main.line_damage(player.global_position, dir, length, def.get("width", 20.0), dmg, opts)
			)
		"taunt":
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			var mult: float = def["mult"] + def.get("mult_step", 0.0) * (rank - 1)
			main.pull_and_mark(player.global_position, rad, def.get("pull", 200.0), mult, def.get("dur", 3.0))
			var world := main.get_node("World")
			Vfx.ring(world, player.global_position, col, rad, 0.35)
		"barrier":
			var amt: float = def["shield"] + def.get("shield_step", 0.0) * (rank - 1)
			player.shield = maxf(player.shield, amt)
			Vfx.ring(main.get_node("World"), player.global_position, col, 44.0, 0.3)
		"trap":
			var dmg: float = player.damage * (def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1))
			var blast: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			main.spawn_trap(player.global_position, def.get("trigger", 50.0), blast, dmg, col)
		"mark":
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			if t == null: return
			var mult: float = def["mult"] + def.get("mult_step", 0.0) * (rank - 1)
			t.marked_until = main.elapsed + def.get("dur", 4.0)
			t.marked_mult = mult
			Vfx.ring(main.get_node("World"), t.global_position, col, t.radius + 8.0, 0.3)
		"bombardment":
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			var pos: Vector2 = t.global_position if t != null else player.global_position
			var dmg: float = player.damage * (def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1))
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			main.spawn_telegraph(pos, rad, dmg, def.get("delay", 0.8), col)
		"ricochet":
			var base: float = main.dir_to_nearest(player.global_position)
			var bounces: int = def["bounces"] + def.get("bounce_step", 1) * (rank - 1)
			var dmg: float = player.damage * def.get("dmg", 0.8)
			main.spawn_bounce(player.global_position, Vector2(cos(base), sin(base)) * def.get("speed", 380.0), dmg, false, bounces, def.get("size", 6.0), col)
		"snipe":
			var farthest: Node2D = null
			var bd := -1.0
			for e in main.get_tree().get_nodes_in_group("enemies"):
				var d: float = player.global_position.distance_squared_to(e.global_position)
				if d > bd: bd = d; farthest = e
			if farthest == null: return
			var dmg: float = player.damage * (def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)) * player.crit_mult
			farthest.take_damage(dmg, true)
			var world := main.get_node("World")
			Vfx.chain_link(world, player.global_position, farthest.global_position, col, 3.0, 0.2)
			Vfx.burst(world, farthest.global_position, col, 14, 160.0, 0.3, 3.0)
		"cinder_field":
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			var pos: Vector2 = t.global_position if t != null else player.global_position
			var dps: float = player.damage * (def["dps_mult"] + def.get("dps_step", 0.0) * (rank - 1))
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			main.spawn_zone(pos, rad, dps, def.get("dur", 3.0), col)
		"frost_homing":
			var dmg: float = player.damage * (def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1))
			var a: float = main.dir_to_nearest(player.global_position)
			main.spawn_homing(player.global_position, Vector2(cos(a), sin(a)), def.get("speed", 260.0), dmg, false, def.get("size", 7.0), col, def.get("slow", 1.0))
		"dash", "charge":
			var dist: float = def["dist"] + def.get("dist_step", 0.0) * (rank - 1)
			var d := player.move_dir
			if d.length() < 0.01:
				var a: float = main.dir_to_nearest(player.global_position)
				d = Vector2(cos(a), sin(a))
			var hit_mult: float = def.get("dmg", 0.0)
			if def.has("dmg"): hit_mult = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			Vfx.burst(main.get_node("World"), player.global_position, col, 8, 60.0, 0.25, 2.5)
			player.start_dash(d.normalized(), dist, hit_mult)
		"retreat_shot":
			var dist: float = def["dist"] + def.get("dist_step", 0.0) * (rank - 1)
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			var away_a: float
			if t != null: away_a = (player.global_position - t.global_position).angle()
			elif player.move_dir.length() > 0.01: away_a = (-player.move_dir).angle()
			else: away_a = randf() * TAU
			player.global_position += Vector2(cos(away_a), sin(away_a)) * dist
			player.invuln = maxf(player.invuln, 0.35)
			var back_a := away_a + PI
			var n := 3
			var dmg: float = player.damage * def.get("dmg", 0.5)
			for i in n:
				var spread_a: float = back_a + (i - (n - 1) / 2.0) * 0.25
				main.spawn_player_projectile(player.global_position, Vector2(cos(spread_a), sin(spread_a)) * 420.0, dmg, false, 1, 6.0, col)
			Vfx.ring(main.get_node("World"), player.global_position, col, 40.0, 0.3)
		"arcane_surge":
			var dist: float = def["dist"] + def.get("dist_step", 0.0) * (rank - 1)
			var d := player.move_dir
			if d.length() < 0.01:
				var a: float = main.dir_to_nearest(player.global_position)
				d = Vector2(cos(a), sin(a))
			var origin := player.global_position
			var dmg_mult: float = def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1)
			var rad: float = def["rad"] + def.get("rad_step", 0.0) * (rank - 1)
			var world := main.get_node("World")
			Vfx.burst(world, origin, col, 8, 60.0, 0.25, 2.5)
			player.start_dash(d.normalized(), dist, 0.0)
			main.get_tree().create_timer(0.15).timeout.connect(func():
				main.area_damage(origin, rad, dmg_mult, {"color": col})
				Vfx.ring(world, origin, col, rad, 0.3)
				Vfx.burst(world, origin, col, 12, 150.0, 0.3, 3.0)
			)
		"blink", "warp_slam":
			var dist: float = def["dist"] + def.get("dist_step", 0.0) * (rank - 1)
			var t: Node2D = main.nearest_enemy_to(player.global_position)
			var a: float
			if t != null: a = (player.global_position - t.global_position).angle()
			elif player.move_dir.length() > 0.01: a = player.move_dir.angle()
			else: a = randf() * TAU
			var world := main.get_node("World")
			var has_impact := def.has("dmg") and def.has("rad")
			var rad: float = def.get("rad", 55.0) + def.get("rad_step", 0.0) * (rank - 1)
			if has_impact:
				main.area_damage(player.global_position, rad, def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1), {"color": col})
			Vfx.ring(world, player.global_position, col, rad if has_impact else 40.0, 0.3)
			player.global_position += Vector2(cos(a), sin(a)) * dist
			if has_impact:
				main.area_damage(player.global_position, rad, def["dmg"] + def.get("dmg_step", 0.0) * (rank - 1), {"color": col})
			Vfx.ring(world, player.global_position, col, rad if has_impact else 40.0, 0.3)
			player.invuln = maxf(player.invuln, 0.4)

# Roll n level-up options: each is NEW (rank 1) or a RANK-UP of an owned
# ability/passive. Abilities and universal passives are drawn from separate
# pools and composed so passives never crowd out ability choices — at most
# `max_passives` of the n cards are passives, the rest abilities (falling back
# to whichever pool still has entries once one is exhausted).
static func roll(class_id: String, owned: Dictionary, n: int, max_passives: int = 2) -> Array:
	var ability_pool := []
	for ab in by_class().get(class_id, []):
		var cur: int = owned.get(ab["id"], 0)
		if cur < ab["max_rank"]:
			ability_pool.append({"ability": ab, "is_new": cur == 0, "next_rank": cur + 1})
	var passive_pool := []
	for ps in passives():
		var cur: int = owned.get(ps["id"], 0)
		if cur < ps["max_rank"]:
			passive_pool.append({"ability": ps, "is_new": cur == 0, "next_rank": cur + 1})
	ability_pool.shuffle()
	passive_pool.shuffle()
	var out := []
	out.append_array(passive_pool.slice(0, max_passives))
	for opt in ability_pool:
		if out.size() >= n: break
		out.append(opt)
	# Backfill from passives if abilities ran dry (e.g. everything maxed).
	for opt in passive_pool.slice(max_passives):
		if out.size() >= n: break
		out.append(opt)
	out.shuffle()
	out = out.slice(0, n)
	# Keystones and evolutions take priority: any eligible-and-unowned one is
	# prepended as a special card, displacing the last rolled option so the count
	# stays at n. (Evolutions pushed last → sit first, ahead of keystones.)
	for ks in eligible_keystones(owned):
		out.push_front(ks)
	for evo in eligible_evolutions(class_id, owned):
		out.push_front(evo)
	return out.slice(0, n)

# Keystone cards whose required tag is owned and which aren't already taken.
static func eligible_keystones(owned: Dictionary) -> Array:
	var out := []
	for ks in keystones():
		if owned.get(ks["id"], 0) > 0:
			continue
		if not owns_tag(owned, ks["requires_tag"]):
			continue
		out.append({"ability": ks, "is_new": true, "next_rank": 1, "is_keystone": true})
	return out

# Evolution cards whose base ability is maxed and paired passive has reached its
# threshold, and which aren't already owned. Marked is_evo for gold card styling.
static func eligible_evolutions(class_id: String, owned: Dictionary) -> Array:
	var out := []
	for evo in evolutions():
		var base := by_class_lookup(class_id, evo["replaces"])
		if base.is_empty():
			continue   # evolution belongs to another class
		if owned.get(evo["id"], 0) > 0:
			continue   # already evolved
		if owned.get(evo["replaces"], 0) < base["max_rank"]:
			continue   # base not maxed
		if owned.get(evo["requires"], 0) < evo["req_rank"]:
			continue   # paired passive not yet high enough
		out.append({"ability": evo, "is_new": true, "next_rank": 1, "is_evo": true})
	return out

static func by_class_lookup(class_id: String, id: String) -> Dictionary:
	for a in by_class().get(class_id, []):
		if a["id"] == id:
			return a
	return {}
