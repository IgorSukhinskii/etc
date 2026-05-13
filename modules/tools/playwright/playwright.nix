{ ... }:
{
  flake.homeManagerModules.playwright =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      profileDir = "${config.xdg.dataHome}/playwright-mcp/profile";
      stateFile = "${config.xdg.dataHome}/playwright-mcp/storage-state.json";
      outputDir = "${config.xdg.cacheHome}/playwright-mcp/output";

      playwrightOpenScript = pkgs.writeText "playwright-open.js" (builtins.readFile ./playwright-open.js);

      playwrightOpen = pkgs.writeShellScriptBin "playwright-open" ''
        set -euo pipefail
        if [ $# -eq 0 ]; then
          echo "Usage: playwright-open <url>" >&2
          echo "" >&2
          echo "Opens the URL in the persistent Chromium profile used by playwright-mcp." >&2
          echo "Log in once here; cookies persist for the agent across launches." >&2
          exit 1
        fi
        mkdir -p "${profileDir}" "$(dirname "${stateFile}")"
        export NODE_PATH="${pkgs.playwright-test}/lib/node_modules"
        export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
        export PLAYWRIGHT_PROFILE_DIR="${profileDir}"
        export PLAYWRIGHT_STATE_FILE="${stateFile}"
        exec ${pkgs.nodejs}/bin/node ${playwrightOpenScript} "$@"
      '';

      mcpWrapper = pkgs.writeShellScript "mcp-server-playwright-wrapped" ''
        STATE="${stateFile}"
        if [ ! -f "$STATE" ]; then
          mkdir -p "$(dirname "$STATE")"
          echo '{"cookies":[],"origins":[]}' > "$STATE"
        fi
        mkdir -p "${outputDir}"
        exec ${pkgs.playwright-mcp}/bin/mcp-server-playwright \
          --headless \
          --isolated \
          --storage-state "$STATE" \
          --output-dir "${outputDir}" \
          "$@"
      '';
    in
    {
      home.packages = [ playwrightOpen ];

      programs.mcp.enable = true;
      programs.mcp.servers.playwright = {
        command = "${mcpWrapper}";
      };

      programs.opencode = lib.mkIf config.programs.opencode.enable {
        settings.agent = {
          build.permission."playwright_*" = "deny";
          browser = {
            description = "Browser automation via Playwright. Loads pages, reads accessibility trees, clicks/types/navigates, extracts content, returns structured findings. Delegate for any task that requires a real browser: UI validation, scraping, multi-step web flows, content extraction.";
            mode = "subagent";
            permission = {
              "playwright_*" = "allow";
              bash = "allow";
              read = "allow";
              edit = "deny";
              write = "deny";
            };
            steps = 50;
            prompt = builtins.readFile ./BROWSER-AGENT.md;
          };
        };
      };
    };
}
