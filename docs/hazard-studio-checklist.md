# Hazard response: Roblox Studio checklist (issue #96)

Status: UNVERIFIED in Studio. The server logic is tested headless (tests/issue96_hazards.test.luau); presentation and phone performance are not.

Run one Studio session on the debug level and check:

1. Tomato warning: a warning cue appears about 2.5 s before each tomato lands, and it shows the building side and the lane.
2. Gift blocking: firing gift shots while a warning is active blocks the tomato. Note shots do not. Record which shots blocked.
3. Tomato hit: an unblocked tomato in your lane costs 5 HP once, and the HP bar drops once.
4. Dodge: steering out of the lane before impact avoids the tomato.
5. Cart warning: a cart cue appears about 2 s before the cart reaches you, and it shows the clear gap.
6. Cart clearance: steering into the gap passes the cart. Outside the gap costs the −10 crowd loss once.
7. Nothing fires before the run starts (countdown and Start).
8. Replay repeats the same hazard times and positions.
9. Phone performance at the lowest quality setting: no frame-time drop caused by the cues.

Known gap: the server emits hazard_warning, hazard_blocked, hazard_dodged and hazard_hit events. Client rendering of these cues is not in this change.
