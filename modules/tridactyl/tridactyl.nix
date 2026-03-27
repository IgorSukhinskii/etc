{ ... }:
{
  flake.homeManagerModules.tridactyl =
    { pkgs, config, ... }:
    let
      colors = config.lib.stylix.colors;
    in
    {
      home.packages = [ pkgs.tridactyl-native ];

      # Native messaging manifest — standard Firefox path (Zen Browser uses the same)
      home.file."Library/Application Support/Mozilla/NativeMessagingHosts/tridactyl.json".source =
        "${pkgs.tridactyl-native}/lib/mozilla/native-messaging-hosts/tridactyl.json";

      home.file.".config/tridactyl/tridactylrc".source = pkgs.replaceVars ./tridactylrc {
        homeDirectory = config.home.homeDirectory;
      };

      home.file.".config/tridactyl/themes/stylix.css".source = pkgs.replaceVars ./stylix.css {
        inherit (colors)
          base00
          base01
          base02
          base03
          base04
          base05
          base06
          base07
          base08
          base09
          base0A
          base0B
          base0C
          base0D
          base0E
          base0F
          ;
      };
    };
}
