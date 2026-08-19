{ ... }:
{
  # Single shared skill tree for every agent harness. Sources live in
  # `configs/agents/skills/<name>/SKILL.md`; each skill directory is symlinked
  # into the skills dir of whichever harnesses are enabled, so one file is
  # visible to claude-code, codex and opencode alike.
  flake.homeManagerModules.agentSkills =
    {
      lib,
      config,
      ...
    }:
    let
      # Skill *names* are enumerated from the store copy of the tree (pure eval
      # can't read the working copy), but each link *target* is the working copy
      # via mkOutOfStoreSymlink — same trade-off as the claude settings file:
      # editing a skill needs no rebuild, adding or removing one does.
      skillsSrc = ../../configs/agents/skills;
      liveSkillsDir = "${config.local.flakeDir}/configs/agents/skills";

      skillNames = lib.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsSrc)
      );

      # home.file keys are home-relative; harness skill dirs are absolute.
      relToHome = lib.removePrefix "${config.home.homeDirectory}/";

      # One entry per skill rather than one for the whole directory: harnesses
      # keep their own state there (codex ships builtins in `skills/.system`),
      # so the skills dir itself must stay a real, writable directory.
      linksInto =
        dir:
        lib.listToAttrs (
          map (
            name:
            lib.nameValuePair "${relToHome dir}/${name}" {
              source = config.lib.file.mkOutOfStoreSymlink "${liveSkillsDir}/${name}";
            }
          ) skillNames
        );

      codexConfigDir =
        if config.home.preferXdgDirectories then
          "${config.xdg.configHome}/codex"
        else
          "${config.home.homeDirectory}/.codex";
    in
    {
      home.file = lib.mkMerge [
        (lib.optionalAttrs config.programs.claude-code.enable (
          linksInto "${config.programs.claude-code.configDir}/skills"
        ))
        (lib.optionalAttrs config.programs.codex.enable (linksInto "${codexConfigDir}/skills"))
        (lib.optionalAttrs config.programs.opencode.enable (
          linksInto "${config.xdg.configHome}/opencode/skills"
        ))
      ];
    };
}
