-- ── mod/theme.lua ─────────────────────────────────────────────────────
-- Subscribes to the theme watchable published by mod.watchers.
-- Currently just logs; future: push theme to sketchybar, etc.

local log = hs.logger.new("theme", "debug")

local cache = {}
local module = {}

module.start = function()
  cache.watcher = hs.watchable.watch("status", "theme", function(_, _, _, old, new)
    log.df("update: %s → %s", tostring(old), tostring(new))
  end)
end

module.stop = function()
  if cache.watcher then
    cache.watcher:release()
  end
  cache = {}
end

return module
