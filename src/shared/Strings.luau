--!strict
-- Player-facing text. Spanish is the primary language (spec header); keep every visible string here.
return table.freeze({
	hint = "Arrastra para moverte", -- spec s9, first seconds of a run
	followers = "Seguidores",
	loose = "Sueltos",
	sections = "Secciones",
	score = "Puntos",
	best = "Mejor",
	completed = "¡Calenda completada!",
	defeated = "¡Se acabó la fiesta!", -- Amendment 1 (the server does not send this outcome until #36)
	ended = "Fin de la calenda", -- any outcome this client does not know yet
	replay = "¡Otra calenda!", -- spec s9
})
