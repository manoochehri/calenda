# 0003: The player's own Roblox avatar is the lead musician

**Date:** 2026-10-24  **Status:** accepted

## Context
Issues #8 and #13 set `Players.CharacterAutoLoads = false` and drew a primitive block as a placeholder lead. The owner decided on 2026-10-24: "Roblox should always have its avatar."

## Decision
The lead musician is the player's own Roblox character, driven by the client as a pure visual (issue #55); the server's authority and the fixed lead hitbox are unchanged. This supersedes the placeholder-lead choice of #8 and #13.

**Rule:** None

## Alternatives considered
- Keep the primitive placeholder lead: contradicts the owner decision.

## Consequences
The client owns a character it must keep anchored, non-colliding and in step with State; the block remains only as a fallback when no character loads. Revisit if avatar readability at camera distance hurts steering (issue #54).
