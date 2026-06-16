{ lib, ... }:
{
  flake.homeManagerModules.starship =
    { ... }:
    let
      # builtins.fromJSON decodes \uXXXX at eval time, keeping source ASCII-safe.
      promptRight = builtins.fromJSON ''"\u276F"''; # U+276F right-pointing angle (prompt caret)
      promptLeft = builtins.fromJSON ''"\u276E"''; # U+276E left-pointing angle (vi normal mode)
      nfGitBranch = builtins.fromJSON ''"\uE0A0"''; # nf-pl-branch
      nfLinux = builtins.fromJSON ''"\uF17C"''; # nf-fa-linux / Tux (marks private-vm)
    in
    {
      programs.starship = {
        enable = true;
        settings = {
          add_newline = false;
          format = lib.concatStrings [
            "$env_var"
            "$username"
            "$hostname"
            "$directory"
            "$git_branch"
            "$git_status"
            "$git_state"
            "$cmd_duration"
            "$line_break"
            "$character"
          ];
          right_format = "$time";

          character = {
            success_symbol = "[${promptRight}](green)";
            error_symbol = "[${promptRight}](red)";
            vimcmd_symbol = "[${promptLeft}](yellow)";
          };

          time = {
            disabled = false;
            format = "[$time]($style)";
            time_format = "%H:%M:%S";
            style = "bright-black";
          };

          directory = {
            style = "blue";
            truncation_length = 4;
            truncate_to_repo = false;
          };

          git_branch = {
            symbol = "${nfGitBranch} ";
            style = "purple";
          };
          git_status.style = "yellow";

          # Suppress username/hostname inside the private VM -- the env_var
          # glyph below is the (subtler) indicator. Still shown for regular
          # SSH to other hosts.
          username = {
            format = "[$user]($style)@";
            style_user = "purple";
            style_root = "red";
            detect_env_vars = [ "!IN_PRIVATE_VM" ];
          };
          hostname = {
            ssh_only = true;
            format = "[$hostname]($style) in ";
            style = "purple";
            detect_env_vars = [ "!IN_PRIVATE_VM" ];
          };

          env_var.IN_PRIVATE_VM = {
            variable = "IN_PRIVATE_VM";
            symbol = "${nfLinux} ";
            style = "blue";
            format = "[$symbol]($style)";
          };

          # Language detectors disabled -- not useful in this workflow.
          nodejs.disabled = true;
          rust.disabled = true;
          python.disabled = true;
          golang.disabled = true;
          java.disabled = true;
          ruby.disabled = true;
          php.disabled = true;
          package.disabled = true;
        };
      };
    };
}
