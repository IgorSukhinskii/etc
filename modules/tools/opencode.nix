{ ... }:
{
  flake.homeManagerModules.opencode =
    { ... }:
    {
      programs.opencode = {
        enable = true;
        enableMcpIntegration = true;
      };
    };
}
