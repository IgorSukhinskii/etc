{ ... }:
{
  flake.darwinModules.zen =
    { ... }:
    {
      homebrew.casks = [ "zen" ];
    };

  flake.homeManagerModules.zen =
    {
      isDarwin,
      pkgs,
      lib,
      config,
      ...
    }:
    let
      mkCssVars =
        prefix: p:
        lib.concatStrings (
          lib.mapAttrsToList (name: value: "    --${name}: #${value};\n") (
            lib.filterAttrs (n: _: lib.hasPrefix "base" n) p
          )
        );
    in
    lib.optionalAttrs isDarwin {

      programs.zen-browser = {
        enable = true;
        package = null;

        darwinDefaultsId = lib.mkIf pkgs.stdenv.isDarwin "app.zen-browser.zen";

        policies =
          let
            mkLockedAttrs = builtins.mapAttrs (
              _: value: {
                Value = value;
                Status = "locked";
              }
            );

            mkPluginUrl = id: "https://addons.mozilla.org/firefox/downloads/latest/${id}/latest.xpi";

            mkExtensionEntry =
              {
                id,
                pinned ? false,
                allowInPrivate ? false,
              }:
              let
                base = {
                  install_url = mkPluginUrl id;
                  installation_mode = "force_installed";
                  private_browsing = allowInPrivate; # allow extensions in private windows (policy override)
                };
              in
              if pinned then base // { default_area = "navbar"; } else base;

            mkExtensionSettings = builtins.mapAttrs (
              _: entry: if builtins.isAttrs entry then entry else mkExtensionEntry { id = entry; }
            );
          in
          {
            AutofillAddressEnabled = true;
            AutofillCreditCardEnabled = false;
            DisableAppUpdate = true;
            DisableFeedbackCommands = true;
            DisableFirefoxStudies = true;
            DisablePocket = true; # save webs for later reading
            DisableTelemetry = true;
            DontCheckDefaultBrowser = true;
            OfferToSaveLogins = false;
            EnableTrackingProtection = {
              Value = true;
              Locked = true;
              Cryptomining = true;
              Fingerprinting = true;
            };
            SanitizeOnShutdown = {
              FormData = true;
              Cache = true;
            };
            ExtensionSettings = mkExtensionSettings {
              "uBlock0@raymondhill.net" = mkExtensionEntry {
                id = "ublock-origin";
                pinned = true;
                allowInPrivate = true;
              };
              "tridactyl.vim@cmcaine.co.uk" = mkExtensionEntry {
                id = "tridactyl-vim";
                pinned = true;
                allowInPrivate = true;
              };
            };
            Preferences = mkLockedAttrs {
              "browser.aboutConfig.showWarning" = false;
              "browser.tabs.warnOnClose" = false;
              "media.videocontrols.picture-in-picture.video-toggle.enabled" = true;
              # Disable swipe gestures (Browser:BackOrBackDuplicate, Browser:ForwardOrForwardDuplicate)
              "browser.gesture.swipe.left" = "";
              "browser.gesture.swipe.right" = "";
              "browser.tabs.hoverPreview.enabled" = true;
              "browser.newtabpage.activity-stream.feeds.topsites" = false;
              "browser.topsites.contile.enabled" = false;

              "network.cookie.cookieBehavior" = 5; # Total Cookie Protection (dFPI)
              "dom.battery.enabled" = false; # hide Battery Status API (fingerprinting vector)

              "gfx.webrender.all" = true;
              "network.http.http3.enabled" = true;
              "network.socket.ip_addr_any.disabled" = true; # block WebRTC 0.0.0.0 local IP leak
            };
          };

        profiles.default = {
          path = "default";
          settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          userChrome = ''
            /* Palette variables — light by default, dark under prefers-color-scheme */
            :root {
            ${mkCssVars "light" config.themes.palette.light}}
            @media (prefers-color-scheme: dark) {
              :root {
            ${mkCssVars "dark" config.themes.palette.dark}  }
            }

            /* ── Zen chrome theming ────────────────────────────────────────── */
            :root {
              --zen-colors-primary:               var(--base02) !important;
              --zen-primary-color:                var(--base0D) !important;
              --zen-colors-secondary:             var(--base02) !important;
              --zen-colors-tertiary:              var(--base01) !important;
              --zen-colors-border:                var(--base0D) !important;
              --toolbarbutton-icon-fill:          var(--base0D) !important;
              --lwt-text-color:                   var(--base05) !important;
              --toolbar-field-color:              var(--base05) !important;
              --tab-selected-textcolor:           var(--base05) !important;
              --toolbar-field-focus-color:        var(--base05) !important;
              --toolbar-color:                    var(--base05) !important;
              --newtab-text-primary-color:        var(--base05) !important;
              --arrowpanel-color:                 var(--base05) !important;
              --arrowpanel-background:            var(--base00) !important;
              --sidebar-text-color:               var(--base05) !important;
              --lwt-sidebar-text-color:           var(--base05) !important;
              --lwt-sidebar-background-color:     var(--base00) !important;
              --toolbar-bgcolor:                  var(--base02) !important;
              --newtab-background-color:          var(--base00) !important;
              --zen-themed-toolbar-bg:            var(--base00) !important;
              --zen-main-browser-background:      var(--base00) !important;
              --toolbox-bgcolor-inactive:         var(--base01) !important;
            }

            #permissions-granted-icon { color: var(--base05) !important; }

            .sidebar-placesTree      { background-color: var(--base00) !important; }
            #zen-workspaces-button   { background-color: var(--base00) !important; }
            #TabsToolbar             { background-color: var(--base00) !important; }
            .urlbar-background       { background-color: var(--base02) !important; }
            .urlbarView-url          { color: var(--base0D) !important; }

            .content-shortcuts {
              background-color: var(--base00) !important;
              border-color:     var(--base0D) !important;
            }

            #urlbar-input::selection {
              background-color: var(--base0D) !important;
              color:            var(--base00) !important;
            }

            #zenEditBookmarkPanelFaviconContainer { background: var(--base00) !important; }

            #zen-media-controls-toolbar #zen-media-progress-bar::-moz-range-track {
              background: var(--base02) !important;
            }

            toolbar .toolbarbutton-1:not([disabled]):is([open],[checked])
              > :is(.toolbarbutton-icon, .toolbarbutton-text, .toolbarbutton-badge-stack) {
              fill: var(--base00);
            }

            #navigator-toolbox {
              --zen-main-browser-background-toolbar: var(--base00) !important;
            }

            #zen-appcontent-navbar-container { background-color: var(--base00) !important; }

            menupopup {
              --panel-background: var(--base01) !important;
              --panel-color:      var(--base05) !important;
              background-color:   var(--base01) !important;
              color:              var(--base05) !important;
            }

            .menupopup-arrowscrollbox {
              background-color: var(--base01) !important;
            }

            menuitem, menu {
              color: var(--base05) !important;
            }

            menuitem:hover, menuitem[_moz-menuactive="true"],
            menu:hover,     menu[_moz-menuactive="true"] {
              background-color: var(--base0D) !important;
              color:            var(--base00) !important;
            }

            /* Container identity colors */
            .identity-color-blue      { --identity-tab-color: var(--base0D) !important; --identity-icon-color: var(--base0D) !important; }
            .identity-color-turquoise { --identity-tab-color: var(--base0C) !important; --identity-icon-color: var(--base0C) !important; }
            .identity-color-green     { --identity-tab-color: var(--base0B) !important; --identity-icon-color: var(--base0B) !important; }
            .identity-color-yellow    { --identity-tab-color: var(--base0A) !important; --identity-icon-color: var(--base0A) !important; }
            .identity-color-orange    { --identity-tab-color: var(--base09) !important; --identity-icon-color: var(--base09) !important; }
            .identity-color-red       { --identity-tab-color: var(--base08) !important; --identity-icon-color: var(--base08) !important; }
            .identity-color-pink      { --identity-tab-color: var(--base0E) !important; --identity-icon-color: var(--base0E) !important; }
            .identity-color-purple    { --identity-tab-color: var(--base0F) !important; --identity-icon-color: var(--base0F) !important; }
          '';

          # user.js — applied unconditionally on startup (user-level, not locked)
          settings = {
            # Modern Fingerprinting Protection — does NOT force light mode
            "privacy.fingerprintingProtection" = true;
            # All FPP protections EXCEPT CSS color-scheme spoofing (preserves dark mode)
            "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme";
            # Silently spoof Accept-Language to en-US (language fingerprinting resistance)
            "privacy.spoof_english" = 2;

            # Zen-specific preferences (not policy targets, must be in user.js)
            # Follow macOS system appearance (0=light, 1=dark, -1=system)
            "browser.theme.toolbar-theme" = -1;

            "widget.macos.sidebar-blend-mode.behind-window" = false;

            "zen.workspaces.continue-where-left-off" = true;
            "zen.view.compact.animate-sidebar" = false;
            "zen.view.compact.enable-at-startup" = true;
            "zen.view.compact.show-background-tab-toast" = false;
            "zen.view.compact.show-sidebar-and-toolbar-on-hover" = false;
            "zen.view.compact.toolbar-flash-popup" = false;
            "zen.welcome-screen.seen" = true;
            "zen.urlbar.show-domain-only-in-sidebar" = false;
            "full-screen-api.macos-native-full-screen" = false;
          };

          search = {
            force = true;
            default = "ddg";
            privateDefault = "ddg";
            engines =
              let
                nixSnowflakeIcon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              in
              {
                "Nix Packages" = {
                  urls = [
                    {
                      template = "https://search.nixos.org/packages";
                      params = [
                        {
                          name = "type";
                          value = "packages";
                        }
                        {
                          name = "channel";
                          value = "unstable";
                        }
                        {
                          name = "query";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                  icon = nixSnowflakeIcon;
                  definedAliases = [ "pkgs" ];
                };
                "Nix Options" = {
                  urls = [
                    {
                      template = "https://search.nixos.org/options";
                      params = [
                        {
                          name = "channel";
                          value = "unstable";
                        }
                        {
                          name = "query";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                  icon = nixSnowflakeIcon;
                  definedAliases = [ "nop" ];
                };
                "Home Manager Options" = {
                  urls = [
                    {
                      template = "https://home-manager-options.extranix.com/";
                      params = [
                        {
                          name = "query";
                          value = "{searchTerms}";
                        }
                        {
                          name = "release";
                          value = "master"; # unstable
                        }
                      ];
                    }
                  ];
                  icon = nixSnowflakeIcon;
                  definedAliases = [ "hmop" ];
                };

                "Google Maps" = {
                  urls = [
                    {
                      template = "http://maps.google.com";
                      params = [
                        {
                          name = "hl";
                          value = "en";
                        }
                        {
                          name = "q";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                  definedAliases = [
                    "maps"
                    "gmaps"
                  ];
                };

                bing.metaData.hidden = "true";
              };
          };
        };
      };
    };
}
