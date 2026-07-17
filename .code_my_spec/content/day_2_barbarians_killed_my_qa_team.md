# Day 2 building Broken Oaths: combat, barbarians, and the wilderness that killed my QA team

Recap: Broken Oaths is a massively multiplayer 4X where losing doesn't end your game. Your conqueror vassalizes you instead: tribute, forced wars, and coordinated rebellions with your fellow vassals. Civ-style hexes on a real globe, EU-style always-running time. Day 0 was a world builder, day 1 was cities and living turns. Day 2 the world learned to fight back.

## What shipped

Combat. Civ-style damage curve: 30 base damage at equal strength, scaled exponentially by the strength difference, with a ±25% roll. Wounded units fight at reduced effective strength, sliding linearly from 100% at full health to 50% near death, and every piece of combat math consumes that. Attacker and defender strike simultaneously from pre-combat state, so a killing blow still eats the counter. Right-click an adjacent enemy to attack; a battle report ("dealt 26 · took 33") flashes over the board.

Barbarians. Founding your first city spawns 5 to 8 camps, 8 to 15 hexes out, and the wilderness warns you it has noticed. Each camp breeds a warrior every 3 turns, capped at 2 alive per camp. Barbarian warriors run 15/15/120 against your warrior's 10/10/100: you lose a fair fight, by design. They hunt anything within 5 hexes, roam near their camps otherwise, never attack each other, and pillage improvements they walk over (a worker repairs the damage in 1 turn). Kills pay a 10-gold bounty in either direction of the moral spectrum.

Camp assault. Camps never counter-attack, but grinding 100 HP at flat effective strength takes real commitment, and the guards respawn while you dig. Destroy one and you get 30 gold, spawning stops, and the tile opens for founding.

City defense. Cities have 100 HP and defensive strength of 20 plus 5 per population plus the garrison's defense, all visible in the panel. Up to 3 military units stack on the city tile (the game's only stacking exception); the keep turns a fourth away; civilians shelter freely without counting. Garrisons fight from the walls at +50% defense, quiet cities regenerate, and barbarians pillage a fallen city rather than capture it: it stays yours, smaller and briefly idle.

The lord's lineage. Your lord grants +2 strength to adjacent friendlies, attacking and defending. And lords stopped being mortal in the permanent sense: when yours falls, his heir arrives at your capital ten turns later. My QA sessions watched four separate successions fire in the wild before I ever tested the feature deliberately.

Configurable turn speed. Worlds now carry their own turn length. Production keeps its 60-second heartbeat while QA runs 10-second worlds, so a full settle-grow-produce-fight cycle compresses from an hour into minutes. This one feature made everything below possible in a single day.

Plus: warrior, worker, barbarian, camp, farm, and mine pixel sprites; camps and improvements rendering on the globe; a tile info panel on click; dig progress on the worker panel; and a real landing page so visitors stop meeting the Phoenix default.

## The wilderness ate the test plan

Here's my favorite part. The QA phase runs AI agents that play the game in a real browser with real clicks, checking every acceptance criterion against ground truth in the database. Day 2's QA turned into a war documentary.

The first agent found camps spawning directly adjacent to a fresh city, a genuine placement bug that turned the early game into a kill zone. It lost three lords proving it. We fixed the placement band and purged the offending camps.

The next agent tried to stage a controlled A/B combat comparison and could not keep test subjects alive long enough to run it. Every warrior that marched anywhere alone got hunted down and killed en route. That is the design working: the story literally says players lose 1v1 against barbarians.

Then camp assault QA hit a wall that turned out to be the best bug of the batch: the respawn counter kept climbing while a camp sat at its 2-warrior cap, so the instant you killed a guard, a replacement spawned on the next tick. Camps were unclearable by accident. The agent lost 25 warriors and 3 lords documenting it. The fix makes each kill buy a genuine 3-turn grace, which is what the rule said all along.

By the end, seven staging parties had died to the feature under test, the heir mechanic had quietly replaced four fallen lords, and every death produced either a bug fix or evidence that the balance works as designed. I cannot think of a better argument for testing a game by playing it.

## The score

Seven stories went from example mapping (me answering PM questions from my phone) through browser-driven BDD specs to implementation to QA in one continuous run: 542 unit tests, 118 end-to-end spec files, all green, every story with a passing QA record, every bug found along the way fixed and verified.

Stack: Elixir + Phoenix + LiveView, PostgreSQL, canvas 2D. Build tools: Claude Code + CodeMySpec.

Next up: the tech tree, player discovery and chat, and then the vassalization mechanics that are the whole point.

Demo: https://broken-oaths.com. Free to play. The barbarians are real now; bring a friend.
