-- Registry of the scripted archetypes (§15, plus `rush`/`recon`, Session 019). Each is a `{ name, decide }`
-- strategy: `decide(config, view)` returns this round's command batch, reading
-- only the View the harness hands it (see view.luau).

return {
	{ name = "highground", decide = require("./archetypes/highground").decide },
	{ name = "defilade", decide = require("./archetypes/defilade").decide },
	{ name = "boomer", decide = require("./archetypes/boomer").decide },
	{ name = "mortarline", decide = require("./archetypes/mortarline").decide },
	{ name = "sprawl", decide = require("./archetypes/sprawl").decide },
	{ name = "rush", decide = require("./archetypes/rush").decide },
	{ name = "recon", decide = require("./archetypes/recon").decide },
}
