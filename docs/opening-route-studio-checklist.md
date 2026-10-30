# Opening camera move and route Studio checklist

Engine presentation is UNVERIFIED until this checklist is run in Roblox Studio.

1. Open an empty place and start a local play session.
2. Wait for `Jugar`, then press it once. Confirm the selected music starts while the server run is still ready, the clock remains at zero, and the lead, parade, gates, attacks, and other gameplay events stay still.
3. Confirm the camera opens on a close view of the player's avatar face and pans and zooms out to the normal game view over about 3.2 s (issue #177). There is no Spanish count-in and no on-screen countdown cues. If the avatar is not yet in the world when Play is pressed, the camera holds the close view and the move begins as soon as the avatar appears, or after about 1.5 s without it; confirm the camera never dollies out over empty road. Confirm the avatar face height looks right (the 4.9-stud estimate is UNVERIFIED).
4. Confirm the run starts once, after the camera move settles. The lead and parade walk out of the broad starting plaza, continue down the street without a teleport or camera cut, and arrive in the separate finale plaza at the existing route timing.
5. Confirm the completed run celebrates in the finale plaza for 8–10 seconds; defeat still ends without that finale.
6. Toggle music off with the in-game music control and confirm later music updates do not unmute it. The opening move is understandable without audio.

Automated checks cover the opening camera move, the delayed start gate (including the missing-avatar wait), and the authored plaza boundaries. They do not prove Roblox rendering, audio playback, or physical movement.
