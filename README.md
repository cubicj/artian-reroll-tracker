# Artian Reroll Tracker

Gogmazios Artian weapon refinement and skill lottery tracker for Monster Hunter Wilds.

## Features

- **Grinding Mode**: Tracks 5 bonus options from weapon grinding
- **Lottery Mode**: Tracks skill lottery results (Series/Group skills)
- Auto-detects weapon type, attribute, and Kageki type
- Animation skip for faster rerolling (~0.5-0.6 seconds per attempt)
- Auto-skip confirmation dialogs
- Auto session management (detects weapon changes mid-session)
- JSON export for data analysis

## Requirements

- REFramework
- Monster Hunter Wilds

## Usage

1. Open REFramework menu (Insert key)
2. Find "Artian Reroll Tracker" section
3. Check "Enable Tracker" to start tracking
4. Perform grinding or skill lottery actions
5. Uncheck to stop and save session

## Auto Detection

The tracker automatically detects:
- Weapon type (Great Sword, Long Sword, etc.)
- Attribute type (Fire, Water, Paralysis, etc.)
- Kageki type (Attack Kageki, Element Kageki, etc.)

If you change weapons mid-session, a new session automatically starts.

## JSON Output

Data is saved to: `reframework/data/reroll_sessions.json`

### Grinding Mode Example
```json
{
  "nickname": "Attack Kageki Type Paralysis Type Sword & Shield",
  "weaponType": 1,
  "weaponTypeName": "Sword & Shield",
  "attribute": "Paralysis Type",
  "kagekiType": "Attack Kageki Type",
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

### Lottery Mode Example
```json
{
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

## Workflow

1. Prepare artian weapon for grinding/lottery
2. Enable Tracker
3. Perform actions until materials run out
4. Disable Tracker (session saves automatically)
5. Analyze JSON file
6. If desired combination found, note the attempt number
7. Reload save and perform that many attempts

## Notes

- Tracker only activates when enabled
- No impact on other mods when disabled
- Multiplayer safe (local data only)

## Version

v3.11.1

## Author

JCubic
