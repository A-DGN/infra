{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # SSH configuration
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh.settings.PermitRootLogin = "yes";

  # Docker configuration
  virtualisation.docker.enable = true;
  virtualisation.docker.extraOptions = "--data-root /apps/docker"; # Définir l'emplacement des données Docker
  system.activationScripts.dockerSetup = ''
    mkdir -p /apps/docker
    chown root:root /apps/docker
    mkdir -p /var/docker-volumes
    chown root:root /var/docker-volumes
  '';

  system.stateVersion = "23.11";
}
