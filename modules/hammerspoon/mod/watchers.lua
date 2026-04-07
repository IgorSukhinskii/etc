-- ── mod/watchers.lua ──────────────────────────────────────────────────
-- Owns all notification listeners and publishes changes
-- as hs.watchable values so other modules can subscribe without each
-- setting up their own system-level listener.
--
-- Exposed watchables (path → key → type):
--   "status" → "theme" → "dark" | "light"

local status = hs.watchable.new("status")
local log = hs.logger.new("watchables", "debug")

local cache = { status = status }
local module = { cache = cache }

local function updateTheme()
  local theme = (hs.host.interfaceStyle() or "Light"):lower()
  status.theme = theme
end

module.start = function()
  cache.watchers = {
    -- screen = hs.screen.watcher.new(updateScreen),
    -- sleep = hs.caffeinate.watcher.new(updateSleep),
    -- wifi = hs.wifi.watcher.new(updateWiFi),
    -- battery = hs.battery.watcher.new(updateBattery),
    theme = hs.distributednotifications.new(updateTheme, "AppleInterfaceThemeChangedNotification"),
    -- usb = hs.usb.watcher.new(updateUSB),
  }

  hs.fnutils.each(cache.watchers, function(watcher)
    watcher:start()
  end)

  updateTheme()
end

module.stop = function()
  hs.fnutils.each(cache.watchers, function(watcher)
    watcher:stop()
  end)
end

return module
