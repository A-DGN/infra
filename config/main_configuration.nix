{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh.settings.PermitRootLogin = "yes";

  system.stateVersion = "23.11";
}
