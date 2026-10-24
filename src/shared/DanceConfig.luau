--!strict
-- Dance-only tuning defaults. Angles are radians; times are in beats/seconds.
return table.freeze({
	cycleBeats = 16, -- four bars at the configured four beats per bar
	chorusStartsAtBar = 3,
	maxJointRadians = 1.25,
	maxAmplitude = 1.5,
	doubleTempoAt = 0.72,
	maxHopStuds = 0.65,
	maxSwayRadians = 0.45,
	maxArmRadians = 1.25,
	maxSpinRadians = 0.9,
	puppetBowRadians = 0.28,
	globoSpinBeats = 16, -- one turn across the full four-bar choreography
	farDistance = 18, -- studs: beyond this, retain silhouette motion at reduced amplitude
	farAmplitude = 0.45,
	leadBobStuds = 0.25,
	leadBobRadiansPerSecond = 9,
	followerBounceMin = 0.5,
	followerBounceMax = 0.95,
	followerTempoMin = 8,
	followerTempoMax = 13,
	puppetHeadBobStuds = 0.6,
	puppetArmRadians = 1.25,
	puppetSwayRadians = 0.12,
	dancerHopStuds = 0.35,
	dancerFootLiftStuds = 0.7,
	dancerMaxSwirlRadians = 1.6,
	dancerSwayRadians = 0.08,
	dancerArmRadians = 0.5,
	globoTiltRadians = 0.28,
	globoLiftStuds = 0.5,
	moves = table.freeze({ "bounceSway", "sideStep", "spinTwirl", "armsUp", "clap", "march" }),
})
