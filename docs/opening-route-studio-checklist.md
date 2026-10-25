# Opening count-in and route Studio checklist

Engine presentation is UNVERIFIED until this checklist is run in Roblox Studio.

1. Open an empty place and start a local play session.
2. Wait for `Jugar`, then press it once. Confirm the selected music starts while the server run is still ready, the clock remains at zero, and the lead, parade, gates, attacks, and other gameplay events stay still.
3. Confirm the on-screen cues read `¡Tres!`, `¡Dos!`, `¡Uno!`, `¡Vamos!` in that order. The play button must not start a second countdown while one is running.
4. At `¡Vamos!`, confirm the run starts once. The lead and parade walk out of the broad starting plaza, continue down the street without a teleport or camera cut, and arrive in the separate finale plaza at the existing route timing.
5. Confirm the completed run celebrates in the finale plaza for 8–10 seconds; defeat still ends without that finale.
6. Toggle music off with the in-game music control and confirm later music updates do not unmute it; the count-in remains understandable without audio.

Automated checks cover the cue order, the delayed start gate, and the authored plaza boundaries. They do not prove Roblox rendering, audio playback, or physical movement.
