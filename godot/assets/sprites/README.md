# Sprite assets

Drop character/enemy PNGs here (transparent background, ideally a 3/4 or side view
facing **right** — the game flips them to face left and adds an idle bob).

To activate a sprite, add its filename to `manifest.json`. Recognized keys (filename
without `.png`):

- Players: knight, archer, mage, rogue, cleric, barbarian
- Enemies: skeleton, goblin, ogre, shooter, exploder, splitter, charger
- Bosses: miniboss (the Champion), finalboss (the Warden)

Any key not present here falls back to the built-in hand-pixeled sprite.
