--!strict
-- Player-facing text. Spanish is the primary language (spec header); keep every visible string here.
return table.freeze({
	completed = "¡Listo!", -- issue #112: one short results headline
	defeated = "¡Uy, la calenda se dispersó!", -- Amendment 1 (the server does not send this outcome until #36)
	ended = "Fin de la calenda", -- any outcome this client does not know yet
	replay = "¡Otra calenda!", -- spec s9
	newBest = "¡Récord!", -- issue #112: short cue when a completed run sets a new best
	laugh = "¡Ja ja!", -- issue #16: followers wandering off after a breakup (Amendment 1)
	-- Issue #16: finale banners by celebration tier (index = tier; tier 0 has none).
	tierBanner = table.freeze({
		"¡Qué fiesta!",
		"¡Calenda para recordar!",
		"¡Calenda legendaria!",
	}),
})
