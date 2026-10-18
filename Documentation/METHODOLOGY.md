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

About 26 hours of wall-clock time later (with breaks), the project had:

- 118 commits and 76 filed issues, 68 of them closed.
- About 11,100 lines of Swift and 1,450 lines of Metal and shared C headers.
- 206 library tests and 36 demo tests, including 44 golden images.
- 26 presets, a macOS editor app, a render/video CLI, a benchmark CLI, and video export.

## The loop: issues first, then work

Almost all work went through an issue tracker (the `issues` CLI, which stores issues in `ISSUES.md` in the repo).

1. **Ask for features as issues.** Early prompts were things like "lets file issues for all the top level things we
   want to do", "have we reviewed SceneKit and RealityKit particle systems to see what features we need?" (which led to
   a documentation review and a batch of feature issues), and short asks such as "new issue: show wireframes for force
   fields etc".
2. **Triage.** The `issues-triage` skill assigned kind, priority, and effort; the human adjusted ("15 should be high.
   it's going to impact testing", "bump priority up: 25, 32, 54", "defer 74").
3. **Work the backlog autonomously.** The `auto-issue-fixer` skill ran seven times. Each run asked a few scope
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

## Tools

- **pi** (the harness): file read, edit, write, shell, a JavaScript "codemode" for batching tool calls, a task queue
  that drove the autonomous runs, and structured questions for scope decisions.
- **xcb** for every build, test, and run (about 85 builds, 129 test runs). Raw `swift`/`xcodebuild` were not used.
- **jj** (Jujutsu) for version control: one commit per issue, bookmarks marking each autonomous run, splits and squashes
  where needed. Nothing was pushed.
- **issues** CLI for the tracker, including dependencies and labels such as `deferred`, `needs-decision`, and
  `needs-info` that autonomous runs respect.
- **GoldenImage** (a MetalSprockets package) for image regression tests, and **particles-render**, a CLI built early
  in the project, to look at results without launching the app. The human asked for this explicitly ("stop running
  the app... use golden image testing").
- **magick** (ImageMagick) for side-by-side comparisons of renders and goldens, and **ffprobe/ffmpeg** to check video
  exports.
- MetalSprockets ecosystem packages: MetalCompilerPlugin (precompiled shaders), Interaction3D (camera), SwiftMesh
  (meshes, the Utah teapot), MetalSprocketsUI (RenderView, frame timing HUD, offscreen video renderer).

## Skills

pi skills are instruction files the agent loads when a task matches. Used directly in this project:

- `auto-issue-fixer` (seven runs), `issues`, `issues-triage`, `writing-issues`: the tracker workflow.
- `improve-codebase-architecture`, `swiftui-house-rules`, `swift-concurrency-pro`: reviews.
- `xcb`, `jujutsu`, `metalsprockets`, `swift-no-shadow-types`, `writing-comments`: house rules for builds, version
  control, the MetalSprockets API, Codable design, and comment style.

Global instructions (`AGENTS.md`) set the working style: concise answers, no commits without permission (the
auto-issue-fixer runs had it), ask before skipping planned work, use `rg`/`fd`, edit files only with the edit tool.

## What kept the AI honest

- **Tests before claims.** Bugs got a failing test first, and the commit message said what failed before the fix.
  Where a red test was impossible (SwiftUI crashes kill the test process), the exemption was recorded in the issue and
  the commit.
- **Golden images.** 44 reference images made refactors provably behavior-neutral and made visual changes deliberate:
  each changed golden was reviewed before acceptance.
- **Determinism.** One of the first fixes made the simulation repeatable from a seed, which made golden images
  possible.
- **Measured performance.** A benchmark CLI tracked simulate and render times. When numbers looked worse, the agent
  reran them back to back against the previous commit before concluding anything; several apparent regressions were
  load from other processes.
- **Corrections in the open.** Mistakes were stated in summaries: wrong test expectations, a reversed sign in swept
  collision, a wrong claim about a MetalSprockets API, a miscounted preset total, and a spike closed on our side's
  measurements only.

## What the human contributed

Direction and taste, not code: the goal, the order of work, design decisions at forks, priorities, "show me" requests
(screenshots, demos, videos), and pushback. Everything else, from shader code to issue text to this document, was
generated.
