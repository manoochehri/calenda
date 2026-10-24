--!strict
-- Player-facing text. Spanish is the primary language (spec header); keep every visible string here.
local function sectionsGained(n: number): string
	return `+{n} secciones` -- spec s7: the combined-celebration indicator
end

local function nextSectionIn(n: number): string
	return `Próxima sección en {n}`
end

return table.freeze({
	sectionsGained = sectionsGained,
	hint = "Arrastra para moverte", -- spec s9, first seconds of a run
	followers = "Seguidores",
	loose = "Sueltos",
	sections = "Secciones",
	score = "Puntos",
	best = "Mejor",
	completed = "¡Calenda completada!",
	defeated = "¡Uy, la calenda se dispersó!", -- Amendment 1 (the server does not send this outcome until #36)
	ended = "Fin de la calenda", -- any outcome this client does not know yet
	hpIcon = "♥", -- issue #50: the HP bar icon, so the bar reads with the sound off
	musicOn = "♫ Música: Sí",
	musicOff = "♫ Música: No",
	replay = "¡Otra calenda!", -- spec s9
	newBest = "¡Nuevo récord!", -- issue #16: shown beside the best when a completed run beats it
	laugh = "¡Ja ja!", -- issue #16: followers wandering off after a breakup (Amendment 1)
	nextSectionIn = nextSectionIn, -- issue #16: the section meter caption
	-- Issue #16: finale banners by celebration tier (index = tier; tier 0 has none).
	tierBanner = table.freeze({
		"¡Qué fiesta!",
		"¡Calenda para recordar!",
		"¡Calenda legendaria!",
	}),
})
