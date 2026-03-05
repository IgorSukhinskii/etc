{ pkgs, ... }:
{
  programs.zen-browser = {
    enable = true;

    darwinDefaultsId = "app.zen-browser.zen";

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
          }:
          let
            base = {
              install_url = mkPluginUrl id;
              installation_mode = "force_installed";
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
          };
          "tridactyl.vim@cmcaine.co.uk" = mkExtensionEntry {
            id = "tridactyl-vim";
            pinned = true;
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

          # Turn OFF classic RFP (the one that forces light mode)
          "privacy.resistFingerprinting" = false;
          # Turn ON modern Fingerprinting Protection
          "privacy.fingerprintingProtection" = true;
          # Keep all FPP protections but DON'T tamper with CSS color-scheme
          # (Zen/Firefox recent builds honor this override)
          "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme";
          "privacy.spoof_english" = 1;
          "privacy.firstparty.isolate" = true;

          "network.cookie.cookieBehavior" = 5;
          "dom.battery.enabled" = false;

          "gfx.webrender.all" = true;
          "network.http.http3.enabled" = true;
          "network.socket.ip_addr_any.disabled" = true; # disallow bind to 0.0.0.0
        };
      };

    profiles.default = {
      path = "nk615yc5.Default (release)";
      settings = {
        "zen.workspaces.continue-where-left-off" = true;
        "zen.view.compact.animate-sidebar" = false;
        "zen.view.compact.enable-at-startup" = true;
        "zen.view.compact.show-background-tab-toast" = false;
        "zen.view.compact.show-sidebar-and-toolbar-on-hover" = false;
        "zen.view.compact.toolbar-flash-popup" = false;
        "zen.welcome-screen.seen" = true;
        "full-screen-api.macos-native-full-screen" = false;
        "zen.urlbar.show-domain-only-in-sidebar" = false;
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
  stylix.targets.zen-browser.profileNames = [ "default" ];
}
