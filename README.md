# Input Binder

Categories for the Godot Input Map. Input Binder adds a tab beside the built-in Input Map
in Project Settings where actions are grouped, dragged, filtered and edited instead of
scrolled through as one long list. It highlights conflicting bindings, generates a
constants class so action names stop being typo-prone strings, scans your scripts for
actions you forgot to define — or defined and never used — and exports your action set as
a preset the next project can import.

## Features

- Named categories over your input actions. Drag actions between categories, drag
  categories to reorder them, double-click to rename, collapse what you're not working
  on. Everything is undoable with Ctrl+Z inside the tab.
- The categories are sidecar metadata. Your actions stay ordinary `input/*` project
  settings — the built-in Input Map tab, `Input`, and exported games see exactly what
  they always did.
- A press-to-bind dialog for keys, mouse and gamepad: press the input and it's captured,
  with a physical/label toggle for keys and a device selector. Gamepad buttons and axes
  can also be picked from menus, so you can author controller bindings without a
  controller plugged in.
- Conflicts are highlighted where they live: an input bound to two actions tints both
  event rows and the tooltip names the other actions. Binding Space to `jump` and
  `ui_accept` is normal, so built-in overlap is deliberately not flagged.
- The filter matches bindings as well as names — type `space` and every action bound to
  Space appears.
- Auto-categorize by prefix (Tools menu): `player_jump`, `player_dash` → a Player
  category, always behind a preview that shows exactly what will move before you apply.
  Your naming convention does the organizing.
- An opt-in constants file, regenerated automatically on every change:

  ```gdscript
  if Input.is_action_just_pressed(InputBinder.JUMP):    # autocompleted, typo-proof
      velocity.y = JUMP_VELOCITY
  for action in InputBinder.ALL: ...
  ```

- Scan Action Usage (Tools menu) reads your scripts and reports the two mistakes the
  editor can't catch: strings passed to `is_action_pressed` and friends that match no
  defined action, and actions no script ever references. Double-click a result to open
  the script at that line.
- Find Uses on any action (right-click) lists every quoted reference to it across
  scripts, scenes and resources.
- Presets: export your actions and categories to an `.inputpreset` file and import them
  into the next project — with a preview that marks each incoming action as new, kept or
  overwritten before anything happens.
- A small runtime API for building settings menus from your categories:

  ```gdscript
  for category in InputBinderLayout.categories():
      add_section(category)
      for action in InputBinderLayout.actions_in(category):
          add_rebind_row(InputBinderLayout.display_name(action), action)
  ```

  It reads project settings directly, so it works in exported games and in `@tool`
  scripts, with the plugin enabled or not.
- Godot's built-in `ui_*` actions are hidden by default (one toggle shows them), kept
  safe from rename and delete, and still editable when you mean to override one — with
  right-click → Revert to Default when you're done experimenting.

## Install

1. Copy `addons/input_binder/` into your project, or install it from the Asset Store.
2. Enable Input Binder in Project Settings > Plugins.

The tab appears in Project Settings, to the right of the built-in tabs. Needs Godot 4.7
or newer.

## Quick start

1. Open Project Settings and switch to the Input Binder tab.
2. Click Add Category and drag actions into it — or run Tools > Auto-Categorize by
   Prefix and let your action names do it.
3. Select an action, click its + button, and press the key, mouse or gamepad input you
   want bound.
4. Optionally turn on Tools > Auto-generate Constants File and write `InputBinder.JUMP`
   in scripts instead of `"jump"`.

## What it writes

- Actions remain plain `input/*` entries in project.godot, exactly as the built-in
  editor writes them.
- The category layout is one extra setting, `addons/input_binder/layout`. Remove every
  category and the setting removes itself.
- With constants generation on, the class is written to
  `res://input_binder/input_actions.gd` and kept current; the file stays put (and
  useful) if you later disable the plugin.
- Removing the addon costs nothing: your actions are untouched, and the layout line in
  project.godot sits inert until you delete it or reinstall.

## Notes and limitations

- The built-in Input Map tab doesn't refresh while both tabs are open in the same
  dialog; it re-reads when the dialog reopens. Input Binder's own tab refreshes itself
  either way.
- The usage scan reads saved text files and only trusts quoted strings. Calls through
  the generated constants can't be typos, so they're not reported; "unused" is
  conservative — any quoted occurrence of the name, anywhere, counts as a use.
- Renaming an action does not rewrite your scripts. Run Tools > Scan Action Usage
  afterwards and the stale strings surface as undefined references.
- Categories are editor organization; they change nothing about how input behaves at
  runtime unless you read them through `InputBinderLayout`.
- The global names `InputBinderLayout` and — only while constants generation is on —
  `InputBinder` need to stay free in your project. Generation checks first and warns
  instead of overwriting someone else's class.

## License

MIT, see [LICENSE](LICENSE). Copyright Thiago Rocha.
