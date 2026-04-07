hs.autoLaunch(true)
hs.automaticallyCheckForUpdates(false)
hs.menuIcon(false)
hs.consoleOnTop(false)

local launcher = require("mod.launcher")
launcher.config.shadow = 48
launcher.config.width = 640
local modules = {
  launcher,
  require("mod.watchers"),
  require("mod.theme"),
}

hs.fnutils.each(modules, function(m) m.start() end)

hs.shutdownCallback = function()
  hs.fnutils.each(modules, function(m) m.stop() end)
end

-- reload: URL handler (triggered by nix-rebuild) + hotkey
hs.urlevent.bind("reload", function() hs.reload() end)
hs.hotkey.bind({ "ctrl", "alt", "cmd", "shift" }, "r", hs.reload)
