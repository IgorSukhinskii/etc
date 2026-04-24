{ ... }:
{
  flake.homeManagerModules.tridactyl =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      # Prefix both palettes to avoid collision: dark_base00, light_base00, etc.
      darkVars = lib.mapAttrs' (n: v: lib.nameValuePair "dark_${n}" v) config.themes.palette.dark;
      lightVars = lib.mapAttrs' (n: v: lib.nameValuePair "light_${n}" v) config.themes.palette.light;
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [ pkgs.tridactyl-native ];

      # Native messaging manifest — standard Firefox path (Zen Browser uses the same)
      home.file."Library/Application Support/Mozilla/NativeMessagingHosts/tridactyl.json".source =
        "${pkgs.tridactyl-native}/lib/mozilla/native-messaging-hosts/tridactyl.json";

      home.file.".config/tridactyl/tridactylrc".source = pkgs.replaceVars ./tridactylrc {
        homeDirectory = config.home.homeDirectory;
      };

      home.file.".config/tridactyl/themes/theme.css".source = pkgs.replaceVars ./theme.css (
        darkVars // lightVars
      );
    };
}
