# AGENTS.md

## Project

The Shaft is a Godot 4.7 narrative elevator-operator demo.

The player is not a hero exploring the building. The player is an arbitration elevator operator working from inside an elevator control cabin.

The game is about route judgment, system records, camera evidence, passenger testimony, delayed doors, and logs. The player does not control the whole building. The player temporarily changes how a route is interpreted.

## Repository Root

The repository root is the folder that contains:

- `project.godot`
- `AGENTS.md`
- `assets/`
- `data/`
- `docs/`
- `scenes/`
- `scripts/`

Do not work inside nested duplicate folders such as:

- `the_shaft/the_shaft/`

Do not create a second Godot project inside the repository.

Do not move `project.godot` unless explicitly requested.

## Godot Version Rules

- This project uses Godot 4.7.
- Use Godot 4.7-compatible GDScript.
- Do not use Godot 3.x APIs.
- Do not assume older Godot 4.x behavior if Godot 4.7 has a clearer pattern.
- Prefer simple, readable GDScript over clever engine-specific tricks.
- Scenes, scripts, and resources must open in Godot 4.7 without conversion warnings.
- Keep the project friendly to beginner Godot developers.

## Demo Goal

Build a 10–15 minute vertical slice that proves the core loop:

1. A dispatch appears.
2. A passenger enters the elevator.
3. The player reads system records.
4. The player checks camera evidence.
5. The player asks or observes.
6. The player chooses a route reason.
7. The elevator arrives.
8. The player writes a log.
9. The world gives indirect feedback later.

The first demo should prove the feel of the game, not the full scale of the world.

## Current Demo Scope

The first playable demo should focus on:

- One elevator operation cabin.
- A small number of passenger cases.
- Basic dispatch flow.
- Basic route choice.
- Basic log choice.
- Placeholder or simple camera evidence.
- Placeholder art where necessary.
- Minimal but readable UI.
- Clear development structure.

Do not implement large systems before the core loop works.

Avoid adding:

- Free-roaming building exploration.
- Large map systems.
- Full 3D character controllers.
- Complex inventory systems.
- Large branching quest frameworks.
- Full save/load systems.
- Procedural generation.
- Complete relationship systems.
- Full audio middleware.
- Unrequested plugins.

## Core Design Rules

- Do not turn the game into a free-roaming building exploration game.
- Do not make the building a simple evil villain.
- System suggestions can be reasonable.
- Disobedience is not always correct.
- Stability should sometimes protect people.
- Deviation should sometimes hurt people.
- The player changes how a route is interpreted, not just which floor to visit.
- Small actions should feel meaningful: delaying the door, checking a record, switching a camera, asking one more question, writing a log.
- The player should feel like a worker inside the running system, not an outside rebel.
- Every important action should create responsibility, not simple heroism.
- The game should avoid obvious “system bad, rebellion good” moral structure.

## Technical Rules

- Use Godot 4.7.
- Use GDScript unless explicitly told otherwise.
- Keep scenes small and composable.
- Prefer data-driven passenger cases.
- Do not hardcode passenger case text inside UI scripts.
- Do not add large third-party dependencies.
- Do not rename existing public APIs unless all references are updated.
- Do not create unnecessary global singletons.
- Do not reformat the whole project.
- Do not modify unrelated files.
- Make the smallest useful change for the current issue.
- Prefer clear names over short names.
- Prefer explicit state flow over hidden magic.
- Keep scripts readable for beginner Godot developers.

## Version Control Rules

- Do not commit changes unless explicitly asked.
- Do not push changes unless explicitly asked.
- Do not modify `.gitignore`, `.gitattributes`, or repository settings unless the current issue asks for it.
- Do not add generated cache folders to version control.
- Do not add `.godot/` to version control.
- Do not add exported builds to version control.
- Do not add temporary files, logs, or editor backups.
- Keep each change scoped to the current GitHub issue.
- After changing files, summarize exactly which files were changed and how to test them.

## VS Code / Codex Workflow Rules

- Codex will usually be used inside VS Code.
- Treat the repository root as the folder containing `project.godot`.
- Read this file before starting work.
- Work only on the current GitHub issue.
- Do not implement extra systems.
- Do not redesign the whole project.
- Do not modify unrelated files.
- Do not reformat the whole project.
- Do not commit or push.
- After coding, summarize:
  - Files changed.
  - What was implemented.
  - How to test it in Godot 4.7.
  - Any known limitations.

## Folder Structure Rules

Use this general structure:

- `assets/art/` for sprites, textures, UI art, and visual assets.
- `assets/audio/` for music, ambience, and sound effects.
- `data/passengers/` for passenger case data.
- `data/routes/` for route data.
- `docs/` for design notes and implementation notes.
- `scenes/main/` for main entry scenes.
- `scenes/elevator/` for elevator cabin and elevator-related scenes.
- `scenes/passenger/` for passenger scenes.
- `scenes/ui/` for UI panels.
- `scripts/core/` for shared utilities and core definitions.
- `scripts/flow/` for demo flow and state management.
- `scripts/passenger/` for passenger data and behavior.
- `scripts/route/` for route options and route logic.
- `scripts/ui/` for UI scripts.
- `scripts/camera/` for camera switching and camera effects.

Do not create new top-level folders unless the current issue requires it.

## Scene Rules

- Main entry scenes should live in `scenes/main/`.
- UI panels should live in `scenes/ui/`.
- Keep scene responsibility narrow.
- Do not put all gameplay logic into one large scene script.
- Do not hardcode passenger content directly in scene nodes when it can be data-driven.
- Prefer connecting UI to flow managers through clear signals or explicit method calls.
- Avoid hidden dependencies between unrelated scenes.
- Keep node names clear and stable.

## GDScript Style Rules

- Use clear class and variable names.
- Use typed variables where it improves readability.
- Avoid clever one-liners.
- Avoid deeply nested logic.
- Use comments for intent, not for obvious syntax.
- Keep functions short when possible.
- Prefer simple state machines for demo flow.
- Print useful debug information for early prototype tasks.
- Do not introduce complex architecture before the demo needs it.

## Data-Driven Passenger Rules

Passenger cases should eventually be represented as data, not hardcoded into UI scripts.

A passenger case may include:

- `case_id`
- `display_name`
- `route_grade`
- `system_request`
- `passenger_request`
- `record_lines`
- `camera_clues`
- `route_options`
- `log_options`
- `consequences`

Early prototypes may use simple placeholder data, but keep the structure easy to replace with real resources later.

## Route Design Rules

The route system is not a large transport simulation.

The player should not manually plan every elevator path.

The player chooses how the building should understand this movement.

Route options may include:

- Standard delivery.
- Delayed delivery.
- Care route.
- Maintenance detour.
- Transfer wait.
- Return route.
- Non-registered stop.
- Manual override.
- Report anomaly.

The key question is not only “where does the passenger go,” but “what does the system record this movement as?”

## UI Rules

The operator console should feel like a work interface, not a fantasy menu.

Important UI modules may include:

- Dispatch panel.
- Passenger record panel.
- Camera panel.
- Route option panel.
- Door control panel.
- Communication panel.
- Log panel.
- Stability or system status panel.

Early UI can be simple and ugly, but it must be readable and testable.

Do not spend time on final visual polish before the core loop works.

## Camera Rules

The camera system is central to the game.

Cameras should provide evidence, not just decoration.

Possible camera views:

- Front camera.
- Side camera.
- Floor camera.
- Cargo camera.
- Door camera.
- Top-corner camera.

Different cameras should reveal different information:

- Face, posture, clothes, badge, speech state.
- Hands, hidden objects, side posture.
- Shoes, footprints, liquid, shadows.
- Bags, carts, forbidden objects, supplies.
- Doorway slice, corridor state, waiting figures.

For early implementation, text placeholders are acceptable.

Later camera visuals may use:

- Low frame rate.
- Scanlines.
- Timestamp.
- Delay.
- Noise.
- Compression artifacts.
- Distortion.
- Identification boxes.

The player should feel they are seeing compressed system images, not complete people.

## Art Direction Rules

- Use low-cost paper-person / billboard-style passengers.
- Do not replace the style with full 3D characters unless explicitly requested.
- Ordinary passengers can be simple.
- Key passengers can have more directions and special poses.
- Passenger clarity is more important than animation smoothness.
- Cameras must provide different evidence, not just different views.
- Monitoring visuals can hide low-cost art through style, but must also express the world.
- The player sees people through the building’s recording system, not through direct human contact.

## Narrative Rules

- Passenger cases should be about people being partially misread by a process.
- Avoid writing passengers as abstract victims.
- Avoid making every deviation heroic.
- Avoid making every standard route cruel.
- The building uses ordinary management language:
  - suggestion
  - route
  - risk
  - maintenance
  - permission
  - standard process
  - non-essential access
  - stability
  - record
  - dispatch
- Dialogue should be restrained and practical.
- Characters should not directly explain the whole theme.
- Passengers should sound like people trying to get somewhere, not like symbols explaining the setting.
- The player should often face incomplete information.
- A good passenger case should make the player ask: “Is the process enough to describe this person?”

## Building Portrayal Rules

The building is not a simple villain.

The building should not say “obey me.”

The building should not act like an angry dictator.

The building should feel like:

- infrastructure
- logistics
- housing
- maintenance
- transport
- risk control
- permission
- records
- workflow
- stability management

The building can be cold, reasonable, useful, protective, harmful, blind, and incomplete at the same time.

Its horror comes from ordinary process language producing unbearable results.

## Choice Design Rules

Good choices should not have obvious moral answers.

Stability must sometimes be genuinely useful.

Deviation must sometimes have genuine cost.

The player should not learn a simple rule like:

- “Always obey the system.”
- “Always disobey the system.”
- “Always trust the passenger.”
- “Always trust the record.”

Each case should depend on specific evidence, specific people, and specific consequences.

## Log System Rules

The log is not just a score screen.

The log decides how the system remembers the event.

Possible log actions:

- Record as standard delivery.
- Record passenger self-report.
- Mark minor anomaly.
- Report route conflict.
- Hide non-critical deviation.
- Record delay.
- Leave no additional note.

Logs should feel like responsibility.

Avoid turning logs into simple good/bad scoring.

## Door Control Rules

Door actions should feel meaningful.

Important door actions may include:

- Open door.
- Close door.
- Delay closing.
- Reopen.
- Refuse entry.
- Hold at destination.
- Allow short outside action.
- Lock down.

Delaying the door is one of the most important actions in the project.

It can mean: “I am willing to wait a few more seconds for this person.”

## Audio Direction Rules

The game’s music and sound should support atmosphere, not overwhelm the player.

Preferred sound direction:

- Ambient guitar.
- Post-rock.
- Noise environment.
- Low mechanical hum.
- Elevator motor.
- Relay clicks.
- Soft UI beeps.
- Distant broadcasts.
- Room tone.
- Short guitar phrases for private moments.

Avoid:

- Overly heroic music.
- Overly emotional melodrama.
- Cyberpunk nightclub beats.
- Generic horror stingers everywhere.
- Constant loud music.

## Issue Implementation Rules

When implementing a GitHub issue:

1. Read this file.
2. Read the current issue.
3. Follow the acceptance criteria.
4. Make the smallest useful change.
5. Do not implement future systems unless requested.
6. Do not redesign existing systems unless requested.
7. Do not modify unrelated files.
8. Do not commit or push.
9. Summarize changed files.
10. Explain how to test in Godot 4.7.

## Testing Rules

For every code change, explain how to test it.

A good test explanation should include:

- Which scene to open.
- Which button to press, if any.
- What should appear in the Output panel.
- What should be visible on screen.
- What should not happen.

For early prototype tasks, simple Output panel prints are acceptable.

Do not claim a task is finished if the project cannot open in Godot 4.7.

## Current First Milestone

The first milestone is to create a basic runnable skeleton.

Minimum target:

- `scenes/main/Main.tscn`
- `scripts/flow/demo_flow_manager.gd`
- A simple demo state machine.
- The project opens in Godot 4.7.
- Running the main scene prints the current state.
- State advancement can be tested.

Do not build UI, passengers, camera rendering, or save/load before the current issue asks for them.

## First Demo State Suggestions

The basic demo flow may use these states:

- `BOOT`
- `WAITING_FOR_DISPATCH`
- `PASSENGER_BOARDING`
- `ROUTE_SELECTION`
- `ARRIVAL`
- `LOGGING`
- `CASE_COMPLETE`

Keep the first state machine simple.

## Final Reminder

The Shaft is not about escaping the building.

It is about why the building is difficult to refuse.

The player is not outside the system.

The player is one of the people making the system feel normal.

Every implementation decision should protect this core.