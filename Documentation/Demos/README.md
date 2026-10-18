# MetalSprocketsParticles Demos

Clips of every built-in preset, rendered offscreen with `particles-render --video` (1280×720, re-encoded to
H.264 MP4, 30 fps, seed 0, the preset's camera). Finite effects play until they finish. Regenerate them with
`Scripts/make-demos.sh`.

## Contents

- [Fountain](#fountain)
- [Campfire](#campfire)
- [Fireworks](#fireworks)
- [Sparks](#sparks)
- [Snow](#snow)
- [Rain](#rain)
- [Magic Trail](#magic-trail)
- [Comet](#comet)
- [Galaxy](#galaxy)
- [Waterfall](#waterfall)
- [Confetti](#confetti)
- [Portal](#portal)
- [Hearts](#hearts)
- [Moon Phases](#moon-phases)
- [Color Smoke](#color-smoke)
- [Fog](#fog)
- [Pond](#pond)
- [Ring of Fire](#ring-of-fire)
- [Swarms](#swarms)
- [Geyser](#geyser)
- [Bumper](#bumper)
- [Paddle Wheel](#paddle-wheel)
- [Teapot](#teapot)
- [Flag](#flag)
- [Strange Attractor](#strange-attractor)
- [Pointer Stir](#pointer-stir)
- [Embers to Ash](#embers-to-ash)
- [Awning](#awning)
- [Lantern](#lantern)
- [Dunk](#dunk)
- [Flare](#flare)

## Fountain

A water fountain sprays up and falls back onto the ground and a few colliders that move around. Shows gravity, bouncing, and colliders that push and carry particles as they move.

[![fountain](posters/fountain.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/fountain.mp4)

## Campfire

Flames, rising smoke, and embers over two logs. The flames are additive smoke puffs, the smoke is alpha-blended and sorted back to front, the embers are velocity-stretched sparks, and turbulence makes everything flicker. The logs are rotated capsule colliders.

[![campfire](posters/campfire.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/campfire.mp4)

## Fireworks

Rockets climb from the ground, leave sparkle trails, and burst into shells of stars when they burn out. Shows sub-emitters: a while-alive trail and an on-death burst.

[![fireworks](posters/fireworks.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/fireworks.mp4)

## Sparks

Grinder sparks streak across the floor and bounce off a wall. Shows velocity-aligned stretching, bounce with per-particle variation, and friction.

[![sparks](posters/sparks.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/sparks.mp4)

## Snow

Snowflakes drift down through gentle turbulence and settle on the ground and on a sphere. Shows plane emission over a large area, turbulence, and particles that come to rest on colliders.

[![snow](posters/snow.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/snow.mp4)

## Rain

Rain falls onto the ground and a tilted slab. Each drop dies when it hits and splashes where it lands. Shows velocity stretching, die-on-collision, and an on-collision sub-emitter.

[![rain](posters/rain.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/rain.mp4)

## Magic Trail

A wand of stars traces a figure eight, leaving a continuous trail and drifting dust. Shows a moving emitter, births spread along its path, and inherited velocity.

[![magic-trail](posters/magic-trail.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/magic-trail.mp4)

## Comet

A comet circles overhead with a long glowing tail and a bright core. Shows a fast-moving emitter that still leaves a smooth trail.

[![comet](posters/comet.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/comet.mp4)

## Galaxy

Two spiral arms of stars swirl around a bright core. Shows torus emitters, a vortex force field, and an attractor.

[![galaxy](posters/galaxy.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/galaxy.mp4)

## Waterfall

A sheet of water pours over a ledge, hits rocks, and throws up mist. Shows a box emitter, collisions, and soft sorted mist.

[![waterfall](posters/waterfall.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/waterfall.mp4)

## Confetti

A party popper fires one burst of confetti, which flutters down, settles on the ground, and fades. Shows a one-shot emitter (an emission duration that does not loop), which makes the effect finite: when every piece is gone the HUD says Finished, and Restart in the toolbar plays it again. Also shows textured sprites with random spin, turbulence, and friction.

[![confetti](posters/confetti.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/confetti.mp4)

## Portal

A sorcerer's portal: a spinning ring of fire that throws sparks off its rim like a Catherine wheel. Shows tangential birth direction and a spinning emitter whose births spread along its rotation.

[![portal](posters/portal.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/portal.mp4)

## Hearts

Emoji hearts float up and wobble, with pink sparkles. Shows emoji sprites drawn with Core Text: tint them white so they keep their own colors.

[![hearts](posters/hearts.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/hearts.mp4)

## Moon Phases

Emoji moons orbit slowly, each cycling through the moon phases from its own starting phase. Shows a sprite-sheet flipbook with random start frames.

[![moon-phases](posters/moon-phases.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/moon-phases.mp4)

## Color Smoke

Thick, nearly opaque colored smoke billows up and out. Every puff overlaps others, so drawing back to front matters: set Sort to None to see far puffs paint over near ones.

[![color-smoke](posters/color-smoke.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/color-smoke.mp4)

## Fog

Low fog drifts across the ground and around a box, a ball, and a log. The colliders are drawn as solids, and the fog is soft: each puff fades where it meets a surface instead of cutting a hard line through it. Set Softness to 0 to see the hard edges.

[![fog](posters/fog.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/fog.mp4)

## Pond

Raindrops fall into a pond, and each one spreads a ripple that lies flat on the water. Shows fixed (flat) orientation and emoji droplet sprites.

[![pond](posters/pond.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/pond.mp4)

## Ring of Fire

A ring of emoji flames seen from above. The flames are Y-aligned: they stay upright and turn only around Y, instead of tipping toward the camera like billboards.

[![ring-of-fire](posters/ring-of-fire.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/ring-of-fire.mp4)

## Swarms

Two identical firefly swarms circle side by side. The gold one simulates in local space and travels as a tight cloud; the blue one simulates in world space and leaves a trail.

[![swarms](posters/swarms.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/swarms.mp4)

## Geyser

A geyser erupts for 1.5 seconds every 4: water shoots from a cylinder, rocks tumble out and bounce, and steam rises from a cone. Shows the emit/idle loop, opaque particles, and screen blending.

[![geyser](posters/geyser.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/geyser.mp4)

## Bumper

Balls drop onto a bumper. Each hit bursts sparks, balls that bounce into the goal burst stars, a ring pulses every 2 seconds, and sending the event 'boom' fires confetti. Shows the emission triggers.

[![bumper](posters/bumper.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/bumper.mp4)

## Paddle Wheel

Sand pours onto a spinning paddle wheel, which flings it across the ground. The two blades are box colliders that turn at a steady rate (colliderSpins); their spin throws the sand that hits them, and fast blades do not tunnel through it.

[![paddle-wheel](posters/paddle-wheel.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/paddle-wheel.mp4)

## Teapot

The Utah teapot outlined in glowing particles, slowly dissolving into sand that pours onto the ground. Shows emission from the surface of a mesh.

[![teapot](posters/teapot.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/teapot.mp4)

## Flag

A flag of glowing sparks waves from a pole. The flag is a mesh that the system deforms every frame, and the sparks are born on its moving surface. Shows a deforming mesh emitter (meshDeformation).

[![flag](posters/flag.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/flag.mp4)

## Strange Attractor

Glowing particles trace the Lorenz attractor. A user Metal function (updateFunction) sets each particle's velocity from the Lorenz equations every step; nothing in the built-in settings moves them.

[![strange-attractor](posters/strange-attractor.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/strange-attractor.mp4)

## Pointer Stir

Glowing dust hangs in the air. Move the mouse over the view: a vortex and a ball follow the pointer, stirring the dust and pushing it aside. Shows pointer bindings (pointerBindings); without a mouse, the pointer traces a figure eight (pointerMotion).

[![pointer-stir](posters/pointer-stir.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/pointer-stir.mp4)

## Embers to Ash

Glowing embers rise from a fire, and after 1.4 seconds each one turns into a gray flake of ash that drifts down and settles. Shows a transition: a sub-emitter that replaces its parent (SubEmitter.transition) at an age, keeping its position and velocity, with its own sprite and settings.

[![embers-to-ash](posters/embers-to-ash.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/embers-to-ash.mp4)

## Awning

Rain falls straight through an awning and slants in the wind, while sparks from a grinder land on the awning and slide off. Shows category masks: each emitter chooses which colliders and fields affect it.

[![awning](posters/awning.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/awning.mp4)

## Lantern

Smoke and dust lit by a warm lantern and cool moonlight. Shows particle lighting: point and directional lights over low ambient light.

[![lantern](posters/lantern.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/lantern.mp4)

## Dunk

A ball bounces through a pool, and every time it enters the water a splash bursts up. Shows a tracked object and an object-enters trigger.

[![dunk](posters/dunk.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/dunk.mp4)

## Flare

A road flare that ignites, burns, and dies out: sparks and pink smoke whose emission ramps up over half a second, burns for three, and fades out by five seconds. Shows emission over time and a finite effect: once every particle has died the system reports it is finished (the HUD says Finished; Restart plays it again).

[![flare](posters/flare.jpg)](https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos/flare.mp4)
