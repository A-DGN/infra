#!/run/current-system/sw/bin/bash

# Root access verification
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Requesting root privileges..."
  exec sudo "$0" "$@"
fi

# Function to get the latest stable NixOS minimal version
get_latest_stable_iso_info() {
  local iso_url=$(curl -s https://nixos.org/download.html | grep -Eo 'https://channels.nixos.org/nixos-[0-9]+\.[0-9]+/latest-nixos-minimal-x86_64-linux.iso' | head -n 1)
  local version=$(echo "$iso_url" | grep -Eo 'nixos-[0-9]+\.[0-9]+' | grep -Eo '[0-9]+\.[0-9]+')
  echo "$version $iso_url"
}

# Function to get the current NixOS version
get_current_nixos_version() {
  nixos-version | grep -Eo '^[0-9]+\.[0-9]+'
}

# Defining variables
MOUNT_POINT="/mnt"
NIXOS_ISO_PATH="/tmp/nixos-minimal.iso"
CURRENT_VERSION=$(get_current_nixos_version | tr -d '\n')
CONFIGURATION_NIX_PATH="/tmp/configuration.nix"
latest_iso_info=$(get_latest_stable_iso_info)
LATEST_VERSION=$(echo $latest_iso_info | cut -d ' ' -f 1)
LATEST_ISO_URL=$(echo $latest_iso_info | cut -d ' ' -f 2)

# Display ASCII header
display_header() {
  clear
  cat << "EOF"

   _____                              ____                 __     _____           _       __ 
  / ___/___  ______   _____  _____   / __ \___  ________  / /_   / ___/__________(_)___  / /_
  \__ \/ _ \/ ___/ | / / _ \/ ___/  / /_/ / _ \/ ___/ _ \/ __/   \__ \/ ___/ ___/ / __ \/ __/
 ___/ /  __/ /   | |/ /  __/ /     / _, _/  __(__  )  __/ /_    ___/ / /__/ /  / / /_/ / /_  
/____/\___/_/    |___/\___/_/     /_/ |_|\___/____/\___/\__/   /____/\___/_/  /_/ .___/\__/  
                                                                               /_/ 

EOF
}

display_header
echo "Your current version of NixOS is: $CURRENT_VERSION || The latest version of NixOS is: $LATEST_VERSION"

# -------------------- PART 1 OPERATING SYSTEM --------------------
# Ask if the user wants to update the OS or not
if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    read -p "Keep the current version of NixOS ($CURRENT_VERSION)? Or get the latest stable version ($LATEST_VERSION)? (y/n): " USER_CHOICE
    if [ "$USER_CHOICE" == "y" ]; then
        echo "You have chosen to keep the current version of NixOS ($CURRENT_VERSION)."
    elif [ "$USER_CHOICE" == "n" ]; then
        NIXOS_ISO_URL=$LATEST_ISO_URL
    else
        echo "Invalid choice. Please choose 'y' or 'n'."
        exit 1
    fi
else
    echo "The current version of NixOS ($CURRENT_VERSION) is already the latest stable version."
    USER_CHOICE="y"
fi

# Check if the ISO URL has been determined
if [ "$USER_CHOICE" == "n" ] && [ -z "$NIXOS_ISO_URL" ]; then
    echo "Unable to determine the NixOS ISO URL."
    exit 1
fi

if [ "$USER_CHOICE" == "n" ]; then
    echo "Downloading NixOS ISO from: $NIXOS_ISO_URL"
    curl -L $NIXOS_ISO_URL -o $NIXOS_ISO_PATH || { echo "Failed to download the ISO."; exit 1; }
fi

# -------------------- PART 2 GET THE CURRENT CONFIGURATION FILE --------------------
# Ensure the configuration.nix file exists or prompt the user for the path
if [ ! -f $CONFIGURATION_NIX_PATH ]; then
  echo "The file $CONFIGURATION_NIX_PATH does not exist."
  read -p "Please provide the path to the configuration.nix file: " CONFIG_PATH_INPUT
  if [ -f $CONFIG_PATH_INPUT ]; then
    CONFIGURATION_NIX_PATH=$CONFIG_PATH_INPUT
  else
    echo "The file $CONFIG_PATH_INPUT does not exist. Aborting."
    exit 1
  fi
fi
echo "The NixOS configuration file has been found at $CONFIGURATION_NIX_PATH."

# -------------------- PART 3 DISKS MANAGEMENT --------------------
# List available disks and ask the user to choose one
echo ""
echo " ----------------------------- "
echo ""
echo "List of available disks:"
lsblk -d -n -o NAME,SIZE
echo ""
echo " ----------------------------- "
echo ""
read -p "Please choose the disk to install NixOS on (e.g., sda, nvme0n1): " DISK_CHOICE
DEVICE="/dev/$DISK_CHOICE"

# Get the size of the selected disk in MiB
DISK_SIZE=$(lsblk -b -d -n -o SIZE $DEVICE)
DISK_SIZE_MIB=$((DISK_SIZE / 1024 / 1024))

# Function to convert size to MiB
size_to_mib() {
  local SIZE=$1
  echo "$SIZE" | awk '/G$/{print int($1 * 1024)} /M$/{print int($1)} /K$/{print int($1 / 1024)} /^[0-9]+$/{print int($1 / 1024 / 1024)}'
}

# Default partition sizes
DEFAULT_ROOT_SIZE="50G"
DEFAULT_VAR_SIZE="100G"
DEFAULT_DATA_SIZE="300G"
DEFAULT_SWAP_SIZE="26.9G"

# Ask for partition sizes with defaults
while true; do
  echo ""
  echo "You will now be asked to specify the sizes for each partition."
  read -p "Enter the size for the root partition (default: $DEFAULT_ROOT_SIZE): " ROOT_SIZE
  ROOT_SIZE=${ROOT_SIZE:-$DEFAULT_ROOT_SIZE}
  read -p "Enter the size for the var partition (default: $DEFAULT_VAR_SIZE): " VAR_SIZE
  VAR_SIZE=${VAR_SIZE:-$DEFAULT_VAR_SIZE}
  read -p "Enter the size for the data partition (default: $DEFAULT_DATA_SIZE): " DATA_SIZE
  DATA_SIZE=${DATA_SIZE:-$DEFAULT_DATA_SIZE}
  read -p "Enter the size for the swap partition (default: $DEFAULT_SWAP_SIZE): " SWAP_SIZE
  SWAP_SIZE=${SWAP_SIZE:-$DEFAULT_SWAP_SIZE}

  # Convert partition sizes to MiB
  ROOT_SIZE_MIB=$(size_to_mib $ROOT_SIZE)
  VAR_SIZE_MIB=$(size_to_mib $VAR_SIZE)
  DATA_SIZE_MIB=$(size_to_mib $DATA_SIZE)
  SWAP_SIZE_MIB=$(size_to_mib $SWAP_SIZE)

  # Calculate total requested size in MiB
  TOTAL_REQUESTED_SIZE=$((ROOT_SIZE_MIB + VAR_SIZE_MIB + DATA_SIZE_MIB + SWAP_SIZE_MIB))

  if [ $TOTAL_REQUESTED_SIZE -le $DISK_SIZE_MIB ]; then
    echo ""
    echo "You have specified the following partition sizes:"
    echo "Root: $ROOT_SIZE"
    echo "Var: $VAR_SIZE"
    echo "Data: $DATA_SIZE"
    echo "Swap: $SWAP_SIZE"
    read -p "Are these sizes correct? (y/n): " SIZE_CONFIRM
    if [ "$SIZE_CONFIRM" == "y" ]; then
      break
    fi
  else
    echo "The total size of the partitions exceeds the size of the disk. Please enter the sizes again."
  fi
done

# Proceed with partitioning
echo "Proceeding with disk partitioning..."
parted $DEVICE -- mklabel gpt
parted $DEVICE -- mkpart primary 512MiB $((512 + ROOT_SIZE_MIB))MiB
parted $DEVICE -- mkpart primary $((512 + ROOT_SIZE_MIB))MiB $((512 + ROOT_SIZE_MIB + VAR_SIZE_MIB))MiB
parted $DEVICE -- mkpart primary $((512 + ROOT_SIZE_MIB + VAR_SIZE_MIB))MiB $((512 + ROOT_SIZE_MIB + VAR_SIZE_MIB + DATA_SIZE_MIB))MiB
parted $DEVICE -- mkpart primary $((512 + ROOT_SIZE_MIB + VAR_SIZE_MIB + DATA_SIZE_MIB))MiB $((512 + ROOT_SIZE_MIB + VAR_SIZE_MIB + DATA_SIZE_MIB + SWAP_SIZE_MIB))MiB
parted $DEVICE -- mkpart ESP fat32 1MiB 512MiB
parted $DEVICE -- set 5 boot on

# Format the partitions
mkfs.ext4 ${DEVICE}1
mkfs.ext4 ${DEVICE}2
mkfs.ext4 ${DEVICE}3
mkfs.ext4 ${DEVICE}4
mkswap ${DEVICE}5
mkfs.vfat -F 32 ${DEVICE}6

# Mount the partitions
mount ${DEVICE}1 $MOUNT_POINT
mkdir -p $MOUNT_POINT/boot
mount ${DEVICE}6 $MOUNT_POINT/boot
mkdir -p $MOUNT_POINT/var
mount ${DEVICE}2 $MOUNT_POINT/var
mkdir -p $MOUNT_POINT/data
mount ${DEVICE}3 $MOUNT_POINT/data
swapon ${DEVICE}5

# Copy the configuration file to the new system
mkdir -p $MOUNT_POINT/etc/nixos
cp $CONFIGURATION_NIX_PATH $MOUNT_POINT/etc/nixos/configuration.nix

# Install NixOS with the boot loader installation
nixos-install --root $MOUNT_POINT --no-root-passwd

# Ensure EFI boot loader is correctly installed
bootctl --path=$MOUNT_POINT/boot install

# Inform the user that the installation is complete
echo "NixOS installation is complete. You can reboot into your new system."
