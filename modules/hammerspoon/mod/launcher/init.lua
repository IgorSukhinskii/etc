local log = hs.logger.new("launcher", "debug")

local cache = {}
local module = {}

-- ── config (set these before calling start()) ─────────────────────────
module.config = {
  width  = 640, -- panel visual width  (px)
  height = 420, -- panel visual height (px)
  shadow = 24,  -- transparent margin on each side for drop-shadow bleed
}

local palette = dofile(hs.configdir .. "/palette.lua")

-- ── app scanner ───────────────────────────────────────────────────────
local appDirs = {
  "/Applications",
  "/System/Applications",
  "/System/Applications/Utilities",
  os.getenv("HOME") .. "/Applications",
  os.getenv("HOME") .. "/Applications/Home Manager Apps",
}

local function findApps()
  local seen, items = {}, {}
  for _, dir in ipairs(appDirs) do
    local iter, dirObj = hs.fs.dir(dir)
    if iter then
      for file in iter, dirObj do
        if file:match("%.app$") and not seen[file] then
          seen[file] = true
          local appPath = dir .. "/" .. file
          table.insert(items, { name = file:gsub("%.app$", ""), path = appPath })
        end
      end
    end
  end
  table.sort(items, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return items
end

-- ── webview geometry ──────────────────────────────────────────────────
local function launcherRect()
  local cfg = module.config
  local W = cfg.width  + 2 * cfg.shadow
  local H = cfg.height + 2 * cfg.shadow
  local screen = hs.screen.mainScreen():frame()
  return hs.geometry.rect((screen.w - W) / 2, screen.h / 4, W, H)
end

-- ── Lua -> JS helpers ─────────────────────────────────────────────────
local function pushTheme(wv)
  local style = (hs.host.interfaceStyle() or "Light"):lower()
  local colors = palette[style]
  local parts = {}
  for k, v in pairs(colors) do
    table.insert(parts, string.format("'%s':'%s'", k, v))
  end
  table.insert(parts, string.format("'shadow-space':'%dpx'", module.config.shadow))
  log.df("pushing theme: %s", style)
  wv:evaluateJavaScript(string.format("window.setTheme({%s})", table.concat(parts, ",")))
end

local function pushApps(wv)
  local apps = findApps()
  wv:evaluateJavaScript(string.format("window.loadApps(%s)", hs.json.encode(apps)))
  -- deferred to next runloop iteration to avoid blocking the show
  hs.timer.doAfter(0, function()
    local icons = {}
    for _, app in ipairs(apps) do
      local img = hs.image.iconForFile(app.path)
      if img then
        icons[app.path] = img:setSize({ w = 32, h = 32 }):encodeAsURLString()
      end
    end
    wv:evaluateJavaScript(string.format("window.loadIcons(%s)", hs.json.encode(icons)))
  end)
end

-- ── focus / hide helpers ──────────────────────────────────────────────
local function hideLauncher()
  cache.wv:hide()
  if cache.prevApp then
    cache.prevApp:activate()
    cache.prevApp = nil
  end
end

-- ── module lifecycle ──────────────────────────────────────────────────
module.start = function()
  -- webview
  cache.uc = hs.webview.usercontent.new("launcher")
  cache.wv = hs.webview.new(launcherRect(), { developerExtrasEnabled = false }, cache.uc)
  cache.wv:windowStyle({ "borderless", "nonactivating" })
  cache.wv:transparent(true)
  cache.wv:allowTextEntry(true)
  cache.wv:level(hs.canvas.windowLevels.floating)
  cache.wv:url("file://" .. hs.configdir .. "/mod/launcher/launcher.html")

  -- JS -> Lua handler
  cache.uc:setCallback(function(msg)
    local body = hs.json.decode(msg.body)
    if body.action == "ready" then
      pushTheme(cache.wv)
      pushApps(cache.wv)
    elseif body.action == "launch" then
      cache.wv:hide()
      cache.prevApp = nil
      hs.application.open(body.path)
    elseif body.action == "hide" then
      hideLauncher()
    end
  end)

  -- hide on focus loss — permanently subscribed with isVisible() guard
  -- (subscribe/unsubscribe on show/hide causes ~2s latency due to window list rebuild)
  cache.wf = hs.window.filter.new(false):setDefaultFilter({})
  cache.wf:subscribe(hs.window.filter.windowFocused, function(win)
    if not cache.wv:isVisible() then
      return
    end
    local wvWin = cache.wv:hswindow()
    if wvWin and win:id() == wvWin:id() then
      return
    end
    hideLauncher()
  end)

  -- theme watcher — subscribes to watchable published by mod.watchers
  cache.themeWatcher = hs.watchable.watch("status", "theme", function()
    pushTheme(cache.wv)
  end)

  -- hotkey: alt+space toggles the launcher
  cache.hotkey = hs.hotkey.bind({ "alt" }, "space", function()
    if cache.wv:isVisible() then
      hideLauncher()
    else
      cache.prevApp = hs.application.frontmostApplication()
      cache.wv:frame(launcherRect())
      cache.wv:evaluateJavaScript("window.activate()")
      cache.wv:show()
      local win = cache.wv:hswindow()
      if win then
        win:focus()
      end
    end
  end)
end

module.stop = function()
  if cache.hotkey then
    cache.hotkey:delete()
  end
  if cache.wf then
    cache.wf:unsubscribeAll()
  end
  if cache.themeWatcher then
    cache.themeWatcher:release()
  end
  if cache.wv then
    cache.wv:hide()
    cache.wv:delete()
  end
  cache = {}
end

return module
