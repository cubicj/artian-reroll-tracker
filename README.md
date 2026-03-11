# Artian Reroll Tracker

[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-Artian%20Reroll%20Tracker-orange)](https://www.nexusmods.com/monsterhunterwilds/mods/3902)

Track your Gogmazios Artian weapon grinding and skill lottery results. Skips all animations and confirmation dialogs so you can reroll as fast as possible.

## Features

- Tracks Gogmazios Artian grinding bonus options and skill lottery results
- Skips grinding, lottery, and gauge animations
- Auto-confirms all dialogs during rerolling
- Auto-detects weapon type and attribute
- Automatically manages sessions per weapon
- Exports all results to JSON

## Requirements

- [REFramework](https://www.nexusmods.com/monsterhunterwilds/mods/39)

## Installation

1. Install REFramework if you haven't already
2. Extract the mod archive into your Monster Hunter Wilds game directory
3. File structure: `<game folder>/reframework/autorun/artian_reroll_tracker.lua`

## Usage

1. Open REFramework menu (default: `Insert` key)
2. Find **Artian Reroll Tracker** → Check **Enable Tracker**
3. Perform grinding or skill lottery as usual
4. Uncheck to stop and save

Data saved to: `reframework/data/reroll_sessions.json`

### Recommended Workflow

1. **Save your game** before starting rerolls
2. Enable Tracker and reroll until materials run out
3. Disable Tracker and check the JSON output
4. If you found a good combination, note the attempt number
5. **Reload your save** and perform exactly that many attempts

<details>
<summary>JSON Output Examples</summary>

#### Grinding Mode

```json
{
  "nickname": "Paralysis Type Sword & Shield",
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

#### Lottery Mode

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

## License

[MIT](LICENSE)

## Author

**JCubic** — [Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/3902)
