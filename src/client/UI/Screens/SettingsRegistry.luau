-- Ordered registry of settings entries, each shaped
-- { id, label, kind, default, apply }. Settings.luau renders whatever this
-- contains and nothing else -- adding a setting later means appending one
-- entry here, never touching the panel itself. Empty for now (§6.2): there are
-- no settings yet, so this renders an empty panel.

return {}
