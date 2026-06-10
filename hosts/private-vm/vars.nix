{
  # Single source of truth for the user-facing user inside the VM.
  # Bootstrap user is hardcoded "nixos" (generic, hypervisor-only — see
  # bootstrap.nix); this is the user the rebuild creates for actual use.
  # Available everywhere as `inputs.self.privateVm.username`.
  flake.privateVm = {
    username = "igor";
  };
}
