#!/run/current-system/sw/bin/bash

# root verification (if not root the script ask the root's password)
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root. Demande de privilèges root..."
  exec sudo "$0" "$@"
fi

# fonction to get the nixos's latest stable iso
get_latest_stable_iso_url() {
  curl -s https://nixos.org/download.html | grep -Eo 'https://channels.nixos.org/nixos-[0-9]+\.[0-9]+/latest-nixos-minimal-x86_64-linux.iso' | head -n 1
}

# fonction to get the current nixos's iso version
get_current_nixos_version() {
  nixos-version | grep -Eo '^[0-9]+\.[0-9]+'
}

# defining variables
MOUNT_POINT="/mnt"
NIXOS_ISO_PATH="/tmp/nixos-minimal.iso"
CURRENT_VERSION=$(get_current_nixos_version | tr -d '\n') # current nixos version
CONFIGURATION_NIX_PATH="/tmp/configuration.nix"

# Clear the terminal screen
clear

# Function to display ASCII header
display_header() {
  cat << "EOF"


   _____                              ____                 __     _____           _       __ 
  / ___/___  ______   _____  _____   / __ \___  ________  / /_   / ___/__________(_)___  / /_
  \__ \/ _ \/ ___/ | / / _ \/ ___/  / /_/ / _ \/ ___/ _ \/ __/   \__ \/ ___/ ___/ / __ \/ __/
 ___/ /  __/ /   | |/ /  __/ /     / _, _/  __(__  )  __/ /_    ___/ / /__/ /  / / /_/ / /_  
/____/\___/_/    |___/\___/_/     /_/ |_|\___/____/\___/\__/   /____/\___/_/  /_/ .___/\__/  
                                                                               /_/               


EOF
}

# Display the ASCII header
display_header

echo "Your current NixOS's version : $CURRENT_VERSION"

# Demander à l'utilisateur quelle version utiliser
read -p "Do we keep NixOS current version ($CURRENT_VERSION) ? Or get the last stable version ? (y/n) : " USER_CHOICE

if [ "$USER_CHOICE" == "n" ]; then
  NIXOS_ISO_URL="https://channels.nixos.org/nixos-$CURRENT_VERSION/latest-nixos-minimal-x86_64-linux.iso"
elif [ "$USER_CHOICE" == "y" ]; then
  NIXOS_ISO_URL=$(get_latest_stable_iso_url)
else
  echo "Choix invalide. Veuillez choisir 'y' ou 'n'."
  exit 1
fi

if [ -z "$NIXOS_ISO_URL" ]; then
  echo "Impossible de déterminer l'URL de l'ISO de NixOS."
  exit 1
fi

echo "Téléchargement de l'ISO de NixOS depuis: $NIXOS_ISO_URL"

# Copier le fichier configuration.nix existant
if [ -f /etc/nixos/configuration.nix ]; then
  cp /etc/nixos/configuration.nix $CONFIGURATION_NIX_PATH
else
  echo "Le fichier /etc/nixos/configuration.nix n'existe pas. Abandon."
  exit 1
fi

# Télécharger l'ISO de NixOS
curl -L $NIXOS_ISO_URL -o $NIXOS_ISO_PATH

# Lister les disques disponibles et demander à l'utilisateur de choisir
echo "Liste des disques disponibles :"
lsblk -d -n -o NAME,SIZE
echo "Veuillez choisir le disque où installer NixOS (par exemple, sda, nvme0n1) :"
read -p "Disque : " DISK_CHOICE
DEVICE="/dev/$DISK_CHOICE"

# Fonction pour extraire les partitions et les systèmes de fichiers du fichier configuration.nix
extract_partitions() {
  sed -n '/fileSystems = {/,/};/p' /etc/nixos/configuration.nix > /tmp/filesystems.nix
  sed -i '1d;$d' /tmp/filesystems.nix  # Supprimer les lignes de début et de fin

  PARTITIONS=()
  while IFS= read -r line; do
    if [[ $line == *"/dev/"* ]]; then
      PARTITION=$(echo $line | grep -Eo '/dev/[a-zA-Z0-9]+')
      FS_TYPE=$(echo $line | grep -Eo 'type = "[a-z0-9]+"' | cut -d'"' -f2)
      PARTITIONS+=("$PARTITION:$FS_TYPE")
    fi
  done < /tmp/filesystems.nix
}

# Extraire les partitions et les systèmes de fichiers
extract_partitions

# Créer les partitions (simplifié pour l'exemple)
parted $DEVICE -- mklabel gpt
for PARTITION in "${PARTITIONS[@]}"; do
  PART=${PARTITION%%:*}
  FS_TYPE=${PARTITION##*:}
  SIZE="512MiB"  # Placeholder size, should be adjusted based on actual configuration
  if [ "$FS_TYPE" == "fat32" ]; then
    parted $DEVICE -- mkpart primary fat32 0% $SIZE
    mkfs.fat -F 32 $PART
  elif [ "$FS_TYPE" == "swap" ]; then
    parted $DEVICE -- mkpart primary linux-swap 0% $SIZE
    mkswap $PART
  else
    parted $DEVICE -- mkpart primary $FS_TYPE 0% $SIZE
    mkfs.$FS_TYPE $PART
  fi
done

# Monter les partitions
mount ${PARTITIONS[0]%%:*} $MOUNT_POINT
mkdir -p $MOUNT_POINT/boot
mount ${PARTITIONS[1]%%:*} $MOUNT_POINT/boot

# Activer le swap
swapon ${PARTITIONS[2]%%:*}

# Installation de NixOS
nixos-generate-config --root $MOUNT_POINT
cp $CONFIGURATION_NIX_PATH $MOUNT_POINT/etc/nixos/

nixos-install --root $MOUNT_POINT

# Redémarrer le système
reboot