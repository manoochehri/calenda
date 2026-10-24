# Stutter check in Roblox Studio

The Lune interpolation tests model server State delivery; they do not measure Roblox render or
physics cost. Use the [Roblox MicroProfiler walkthrough](https://create.roblox.com/docs/performance-optimization/microprofiler/use-microprofiler)
to find whether stutter comes from client script work or outside the labeled render path.

1. Open an empty Studio place and sync this branch with Rojo as described in `.trazo/project/RUNBOOK.md`.
2. Use the same device and graphics settings for the current `main` build and this branch. Record the
   device/model and graphics level.
3. Start Play Solo, press **Jugar**, and run through the opening, a busy mid-street section, and the
   finale. Watch the lead, camera, followers, spectators, and sections for visible stops or jumps.
4. Show the Performance Summary (Ctrl+Shift+F5; on macOS, ⌘+Shift+F5). Record the observed FPS
   during each segment. The project target is sustained 30 FPS on a named lower-end mobile device;
   agent-side simulations do not establish that target.
5. Open the MicroProfiler (Ctrl+Alt+F6; on macOS, ⌘+Option+F6).
   Inspect `Calenda/ClockAndInput`, `Calenda/CrowdAndSections`, `Calenda/AudioAndEffects`, and
   `Calenda/CameraAndHud`. Note which label is longest and whether it spikes on the same frames as
   the visible stutter. If the labels stay short while frame time spikes, the cause is outside these
   script sections (for example rendering or another engine task).
6. Record the device/model, graphics level, FPS observed in each segment, the label or engine task
   that coincides with the stutter, and whether the symptom is present on `main` and this branch.

Do not mark movement smooth or the performance target met until this Studio check has been run.
