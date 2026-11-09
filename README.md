# PlayLimiter

A World of Warcraft addon (built for WoW Classic / Anniversary, interface `16001`) that limits my playtime like a normal person.

You set how much you can play per day on weekdays and weekends. When the time runs out, a full-screen overlay blocks the game until you solve a run of annoying puzzles to earn a bit more time, or you give up and log out.

![Settings panel](screenshots/Wow_YcK1yNNHIV.png)

## Features

- **Separate weekday and weekend daily limits.** Monday to Friday and Saturday/Sunday each get their own daily allowance. Set either to `0` for no limit.
- **Resets at midnight.** Play time is tracked per calendar day. Logging out and back in on the same day picks up where you left off. If you are still playing when the date changes, your time resets right away.
- **On-screen countdown timer.** Shows how much time is left today. It turns orange at 5 minutes and red at 1 minute. Shift+drag to move it.
- **Warnings** at 10, 5 and 1 minute remaining, with a chat message, an on-screen alert and a raid-warning sound.
- **Puzzle challenge when time is up.** Solve several puzzles in a row (3 by default) to earn extra minutes (15 by default). A wrong answer resets your streak to zero.
- **Combat-safe.** If the limit is reached mid-fight, the challenge waits until combat ends.
- **"Never mind, log out" button** on the challenge screen if you would rather just stop. It uses a secure `/logout` macro button, so the game does not block it.

## Puzzles

Each challenge picks puzzles at random, never the same kind twice in a row.

| Puzzle | What you do |
| --- | --- |
| Mental arithmetic | Solve one quick sum with friendly numbers, like `5 x 6`, `40 + 25` or `50 - 45`. No calculator. |
| Vanishing code | Memorize a 4-digit code that disappears after 4 seconds, then type it in. |
| Pattern repeat | Watch four coloured squares flash in sequence, then repeat it. The pattern starts at 4 and gets one longer for each puzzle already solved in your streak. |
| Wordle | Guess a 5-letter WoW word (e.g. `GNOME`, `DRAKE`, `TOTEM`) with unlimited guesses. Green = right spot, yellow = wrong spot, grey = not in the word. |
| Runaway button | Click a button 7 times while it keeps jumping around the panel. |

### Screenshots

**Mental arithmetic**

![Math puzzle](screenshots/Wow_k2CnqZu2pL.png)

**Vanishing code**

![Memory code puzzle](screenshots/Wow_NRiMNBdPBc.png)

**Pattern repeat**

![Pattern repeat puzzle](screenshots/Wow_0k14eVAj2L.png)

**Wordle**

![Wordle puzzle](screenshots/Wow_1M1XAmBCBI.png)

**Runaway button**

![Runaway button puzzle](screenshots/Wow_RR31GItz0p.png)

## Installation

1. Download or clone this repository.
2. Copy the inner `PlayLimiter` folder (the one containing `PlayLimiter.toc` and `PlayLimiter.lua`) into your WoW AddOns directory, for example:
   ```
   World of Warcraft\_anniversary_\Interface\AddOns\PlayLimiter
   ```
3. Restart the game or type `/reload`, and make sure **Play Limiter** is enabled in the AddOns list on the character select screen.

## Usage

Open the settings with `/pl` or `/playlimit`, or go to **Game Menu > Options > AddOns > Play Limiter**.

| Setting | Default | Description |
| --- | --- | --- |
| Weekday daily limit | 120 min | Monday to Friday. `0` = no limit. |
| Weekend daily limit | 240 min | Saturday and Sunday. `0` = no limit. |
| Puzzles required per challenge | 3 | Puzzles in a row needed to earn more time. Minimum 1. |
| Minutes earned per challenge | 15 | Extra play time granted when you pass. Minimum 1. |
| Show on-screen timer | On | Toggle the countdown display. |

Click **Save** to apply changes immediately. Click **Test the puzzles** to try a challenge without earning any time.

The settings panel also shows whether today counts as a weekday or weekend, how long you have played today, and how much time remains.

## How time is tracked

- Time only counts while you are logged in, and it pauses while a challenge is on screen.
- Passing a challenge sets your remaining time to exactly the bonus amount, so going over the limit is not rewarded.
- Settings and today's progress are saved per account in the `PlayLimiterDB` saved variable.

## License

See [LICENSE](LICENSE).
