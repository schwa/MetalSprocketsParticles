# How MetalSprocketsParticles Was Built

MetalSprocketsParticles is a GPU particle system for Swift and Metal, built on MetalSprockets. Every line of code, every
test, every preset, and every issue description was written by an AI coding agent (Claude, running in the pi coding
harness). The human role was direction: prompts, decisions, priorities, and review. This document reconstructs the
process from the pi session logs.

## The starting prompt

The first session began on 17 October 2026 with:

> make a new project - MetalSprocketsParticles
>
> swift package. import MetalSprockets.
>
> potentially use the point cloud rendering from MetalSprocketsAddOns (your choice)
>
> the goal - start simple.
>
> the final goal - a better particle system than the one in realitykit and scenekit
>
> stretch goal - particles that interact with geometry

The work took a few days, with breaks.

## The loop: issues first, then work

Almost all work went through an issue tracker (the `issues` CLI, which stores issues in `ISSUES.md` in the repo).

1. **Ask for features as issues.** Early prompts were things like "lets file issues for all the top level things we
   want to do", "have we reviewed SceneKit and RealityKit particle systems to see what features we need?" (which led to
   a documentation review and a batch of feature issues), and short asks such as "new issue: show wireframes for force
   fields etc".
2. **Triage.** The `issues-triage` skill assigned kind, priority, and effort; the human adjusted ("15 should be high.
   it's going to impact testing", "bump priority up: 25, 32, 54", "defer 74").
3. **Work the backlog autonomously.** The `auto-issue-fixer` skill did most of the work. Each run asked a few scope
   questions (how many issues, include low priority or untriaged), set a jj bookmark, printed the plan, and loaded one
   task per issue into pi's task queue. Each task: load the issue, write a failing test first for bugs, fix, build and
   test, then commit with the issue closed in the same commit. Hard or ambiguous issues were punted with a comment
   explaining what was tried and what decision was needed.
4. **Summarize.** Each run ended with fixed, punted, failed, and skipped lists, plus caveats and anything the human
   should look at.
5. **Review and redirect.** The human read the summaries and asked follow-ups ("ok so #28 - what happened"), made the
   decisions punts asked for ("24: functions. 32: C. 2: yeah let's skip"), and pushed back when a punt looked too
   cautious ("coliders and force fields have positions and other attributes a mask doesn't seem too difficult?").

Small requests skipped the tracker: "add a particle count hud", "lets add video export", "commit".

## The issue tracker

The tracker is the `issues` CLI. It keeps every issue in one Markdown file, `ISSUES.md`, in the repository, so issues
are versioned with the code and each change to them is a commit. An issue has a title, a description, a kind (bug,
feature, enhancement, task, or documentation), a priority, labels, a status, and comments.

**Filing.** Most issues started as one line from the human, such as "new issue: the coins keep rotating when they hit
the floor". The agent wrote the full description: what happens, what should happen, a likely place in the code, and
related issues. It read the code first, so the description named real files and settings. When it was guessing, the
description said so. When a guess turned out wrong, the agent added a comment with the correction instead of
rewriting history.

**Triage.** New issues get a kind, a priority, an effort label (`effort:xs` to `effort:xl`), and an area label (such as
`area:rendering` or `area:demo`), and then move from New to Open. Triage also looks for duplicates and adds "related"
comments between issues that touch the same code. Labels also say when an issue must wait: `deferred`, `needs-design`,
`needs-decision`, or `needs-info`.

**Decisions.** When an issue needed a choice, the agent asked one short question with its recommendation, and wrote
the answer on the issue as a comment. The decision then traveled with the issue, so the run that fixed it could follow
it without asking again.

**Working.** Autonomous runs skip any issue whose labels say to wait, and sort the rest: priority first, then bugs
before enhancements before features, then small before large. Each fix is one commit that also closes the issue, so the
history shows the change and the closed issue together. The closing comment says what was done, and also what was
left out and why.

**Follow-ups.** Parts left out of a fix did not stay hidden in comments. At the end of a run the human asked which of
them were worth doing, and they became new issues with links back to the issue they came from.

## Rendering from the command line

Early on, the human asked the agent to stop launching the demo app to check its work. The agent used a command-line
renderer, `particles-render`, instead. It loads a sample preset or a saved effect file, runs the simulation offscreen
with the preset's camera and a fixed seed, and writes a PNG of the last frame or a movie. Options set the size, the
number of frames, the camera, wireframes, and debug views such as false colors by age or speed.

The agent then looked at the PNG itself. Most visual problems were found this way: smoke too gray, letters smeared by
turbulence, ribbons that zigzagged, coins half buried in the floor. Each fix was checked by rendering again.

The same renderer made the rest of the visual tooling possible:

- **Golden images.** Tests render every sample preset and compare the result with a stored image. A changed image
  fails the test and writes the new image to a temporary file. The agent looked at each changed image before it
  replaced the stored one.
- **Demo previews.** A script renders a short movie of each preset, turns it into an animated image that plays on
  GitHub, and rewrites the demo index from the preset files.
- **Showreels.** On request, the agent cut clips of presets into one titled movie for sharing, compressed for social
  media.
- **Measurement.** A second tool, `particles-bench`, times frames for large particle counts and for every sample
  preset against a frame budget. It found that one slow demo spent its time on the CPU, rebuilding collider meshes
  every frame, and not on the GPU as first guessed.

Video export once hung with no output. The agent could not make it happen again on demand, so it added a watchdog to
the renderer: if no frame finishes for a while, the renderer saves a sample of the stuck process and exits with an
error. The cause was later fixed in MetalSprockets.

## Gap reviews

After each burst of features the human asked, in effect, "is it all shown and sound?":

- "do we have cool demos for everything we added" led to demo-gap issues, then new presets (Teapot, Bumper, Pond,
  Swarms, Geyser, Awning, Lantern, Dunk, and others).
- `improve-codebase-architecture` produced four refactor issues (one emitter description type, a pure CPU frame
  planner, named Swift/Metal struct fields in the MetalSprockets header style, library-owned enum kinds). An
  auto-issue-fixer run then did all four, with golden images proving output was unchanged.
- `swiftui-house-rules` (a SwiftUI review) found two crash risks and several style issues; they were filed and fixed.
  One finding was that a house rule itself had caused a crash, which was reported back to the human.
- `swift-concurrency-pro` (a concurrency review) found no real problems and said so, rather than inventing some.
- "in the real world - i expect things to move a lot and even meshes to morph" led to issues and fixes for spinning
  emitters, collider spin and tunneling, and emitters driven by deformed (morphing or skinned) mesh buffers, aimed at
  replacing the particle system in MetalSprocketsSceneGraph.

## The second day

The first day built the engine. The second day was mostly about finish, reach, and extension points:

- **Cleanup.** A SwiftLint setup (generated, then curated by hand), a simple README with a feature list written for
  library users, an MIT license, and this document.
- **Upstream fixes.** Two gaps in MetalSprockets (no access to the frame's depth, and a confusing `enabled:` label)
  were filed upstream from here. The human fixed them in MetalSprockets, and this project then moved to its `main`
  branch.
- **Demo audit.** The human asked "do we have good demos for everything?" The agent compared features with presets,
  filed the gaps, then removed presets that only repeated others. The gaps became presets: Fog (soft particles against
  solid colliders), Flag (a deforming mesh), Paddle Wheel (spinning colliders), Strange Attractor (a user Metal
  function), Pointer Stir (mouse control), and Embers to Ash (chained transitions).
- **Extension points.** A spike tested user-supplied Metal functions through a visible function table, compiled at
  runtime against a small public struct. It measured no cost at one million particles, and then became update, spawn,
  collision, and death hooks.
- **Transitions.** The human asked for particles that turn into another kind on an event. The agent noticed that
  sub-emitters already did most of this, and added only the missing parts: the parent dies, an age event, a sprite
  per sub-emitter, keeping the parent's life, entering a volume, and nesting.
- **Packaging.** A standalone `ParticleView` in its own UI library, built on MetalSprockets' `RenderView`. The sample
  presets moved out of the core library into their own optional library, on the human's direction.
- **Demo previews.** A script renders an animated preview of every preset that plays inline on GitHub, and rewrites
  the demo index. A test fails if any preset is missing one.

## Tools

- **pi** (the harness): file read, edit, write, shell, a JavaScript "codemode" for batching tool calls, a task queue
  that drove the autonomous runs, and structured questions for scope decisions.
- **A build wrapper** around `xcodebuild` and SwiftPM for every build, test, and run, so the agent always got the same
  compact error and test summaries.
- **jj** (Jujutsu) for version control: one commit per issue, bookmarks marking each autonomous run, splits and squashes
  where needed. Nothing was pushed.
- **issues** CLI for the tracker, including dependencies and labels such as `deferred`, `needs-decision`, and
  `needs-info` that autonomous runs respect.
- **GoldenImage** (a MetalSprockets package) for image regression tests, and **particles-render**, a CLI built early
  in the project, to look at results without launching the app. The human asked for this explicitly ("stop running
  the app... use golden image testing").
- MetalSprockets ecosystem packages: MetalCompilerPlugin (precompiled shaders), Interaction3D (camera), SwiftMesh
  (meshes, the Utah teapot), MetalSprocketsUI (RenderView, frame timing HUD, offscreen video renderer).

## Skills

pi skills are instruction files the agent loads when a task matches. Used directly in this project:

- `auto-issue-fixer`, `issues`, `issues-triage`, `writing-issues`: the tracker workflow.
- `improve-codebase-architecture`, `swiftui-house-rules`, `swift-concurrency-pro`: reviews.
- `swiftlint`: the lint setup. `simple-english`: the README and this document.
- Build, `jujutsu`, `metalsprockets`, `swift-no-shadow-types`, `writing-comments`: house rules for builds, version
  control, the MetalSprockets API, Codable design, and comment style.

Global instructions (`AGENTS.md`) set the working style: concise answers, no commits without permission (the
auto-issue-fixer runs had it), and ask before skipping planned work.

## What kept the AI honest

- **Tests before claims.** Bugs got a failing test first, and the commit message said what failed before the fix.
  Where a red test was impossible (SwiftUI crashes kill the test process), the exemption was recorded in the issue and
  the commit.
- **Golden images.** Reference images made refactors provably behavior-neutral and made visual changes deliberate:
  each changed golden was reviewed before acceptance.
- **Determinism.** One of the first fixes made the simulation repeatable from a seed, which made golden images
  possible.
- **Measured performance.** A benchmark CLI tracked simulate and render times. When numbers looked worse, the agent
  reran them back to back against the previous commit before concluding anything; several apparent regressions were
  load from other processes.
- **Corrections in the open.** Mistakes were stated in summaries, not hidden: wrong test expectations, a reversed
  sign in swept collision, a wrong claim about a MetalSprockets API, and a feature audit that missed a setting.
- **Evidence before explanations.** When test runs hung, the agent sampled the stuck process before guessing, said
  plainly when it did not know the root cause, and filed what it found.
- **Automatic fixes checked.** Lint autofix broke the build in several ways; each was caught by building and testing.

## What the human contributed

Direction and taste, not code: the goal, the order of work, design decisions at forks, priorities, "show me" requests
(screenshots, demos, videos), and pushback. Everything else, from shader code to issue text to this document, was
generated.
