# Artian Reroll Tracker

[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-Artian%20Reroll%20Tracker-orange)](https://www.nexusmods.com/monsterhunterwilds/mods/3902)

Gogmazios Artian weapon refinement and skill lottery tracker for **Monster Hunter Wilds**.

Track every reroll attempt, skip animations for faster grinding, and export results to JSON for analysis.

## Features

- **Grinding Mode** — Tracks all 5 bonus options from Gog Restoration Enhancement
- **Lottery Mode** — Tracks Skill Reassignment results (Series / Group skills)
- **Animation Skip** — Skips reroll animations for faster iteration (~0.5s per attempt)
- **Auto-skip Dialogs** — Automatically confirms reroll dialogs
- **Auto Detection** — Detects weapon type, attribute, and Kageki type automatically
- **Session Management** — Auto-switches sessions when you change weapons mid-reroll
- **JSON Export** — All data saved to JSON for external analysis

## Requirements

- [REFramework](https://www.nexusmods.com/monsterhunterwilds/mods/39)
- Monster Hunter Wilds

## Installation

1. Install REFramework if you haven't already
2. Extract the mod archive into your Monster Hunter Wilds game directory
3. The file structure should be: `<game folder>/reframework/autorun/artian_reroll_tracker.lua`

## Usage

1. Open REFramework menu (`Insert` key)
2. Find **Artian Reroll Tracker** section
3. Check **Enable Tracker** to start
4. Perform Gog Restoration Enhancement or Skill Reassignment
5. Uncheck to stop — session saves automatically

### Recommended Workflow

1. **Save your game** before starting rerolls
2. Enable Tracker
3. Reroll until materials run out
4. Disable Tracker and check the JSON output
5. If you found a good combination, note the attempt number
6. **Reload your save** and perform exactly that many attempts

## Auto Detection

The tracker automatically detects and groups sessions by:

| Field | Example |
|-------|---------|
| Weapon Type | Great Sword, Long Sword, Sword & Shield, etc. |
| Attribute | Fire, Water, Paralysis, etc. |

If you switch to a different weapon mid-session, a new session starts automatically. Switching back restores the previous session.

## JSON Output

Data is saved to `reframework/data/reroll_sessions.json`.

<details>
<summary>Grinding Mode Example</summary>

```json
{
  "nickname": "Paralysis Type Sword & Shield",
  "weaponType": 1,
  "weaponTypeName": "Sword & Shield",
  "attribute": "Paralysis Type",
  "mode": "grinding",
  "attempts": [
    {
      "attemptNum": 1,
      "timestamp": "2026-02-05 12:00:00",
      "bonuses": ["Crit Rate II", "Attack EX", "Sharpness I", "Attack II", "Crit Rate I"]
    }
  ]
}
```

</details>

<details>
<summary>Lottery Mode Example</summary>

```json
{
  "nickname": "Paralysis Type Sword & Shield",
  "mode": "lottery",
  "attempts": [
    {
      "attemptNum": 1,
      "timestamp": "2026-02-05 12:00:00",
      "skills": {
        "series": "Insect Awakening",
        "group": "Gogmazios Apocalypse"
      }
    }
  ]
}
```

</details>

## Notes

- No performance impact when disabled
- Multiplayer safe (local tracking only)
- Does not modify any game data — only reads and records results

## License

[MIT](LICENSE)

## Author

**JCubic** — [Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/3902)
