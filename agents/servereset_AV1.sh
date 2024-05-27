#!/run/current-system/sw/bin/bash

# Root access verification
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Requesting root privileges..."
  exec sudo "$0" "$@"
fi

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

# -------------------- PART 1 --------------------
# Step 1: List attached storage devices and select the first one
echo "--------------------------------------------------------------------------------"
echo "Your attached storage devices will now be listed."

# List devices and select the first one
i=0
for device in $(sudo fdisk -l | grep "^Disk /dev" | awk '{print $2}' | sed 's/://'); do
    echo "[$i] $device"
    i=$((i+1))
    DEVICES[$i]=$device
done

DEVICE=0
DEV=${DEVICES[$(($DEVICE+1))]}

# Unmount all partitions and deactivate swap
echo "Unmounting all partitions and deactivating swap on ${DEV}..."
for part in $(lsblk -ln -o NAME ${DEV} | grep -v ${DEV}); do
    sudo umount /dev/${part} 2>/dev/null || true
    sudo swapoff /dev/${part} 2>/dev/null || true
done

# -------------------- PART 2 --------------------
# Step 2: Partitioning the selected device
SWAP=4

echo "partitioning ${DEV}..."
(
  echo g # new gpt partition table

  echo n # new partition
  echo 1 # partition 1
  echo   # default start sector
  echo +512M # size is 512M (EFI System Partition)

  echo n # new partition
  echo 2 # partition 2
  echo   # default start sector
  echo +4G # size is 4G (swap partition)

  echo n # new partition
  echo 3 # partition 3
  echo   # default start sector
  echo +20G # size is 20G (root partition for OS)

  echo n # new partition
  echo 4 # partition 4
  echo   # default start sector
  echo +50G # size is 50G (partition for databases and other variable data)

  echo n # new partition
  echo 5 # partition 5
  echo   # default start sector
  echo   # use the remaining space (partition for apps and Docker containers)

  echo t # set type
  echo 1 # select partition 1
  echo 1 # EFI System

  echo t # set type
  echo 2 # select partition 2
  echo 19 # Linux swap

  echo t # set type
  echo 3 # select partition 3
  echo 20 # Linux Filesystem

  echo t # set type
  echo 4 # select partition 4
  echo 20 # Linux Filesystem

  echo t # set type
  echo 5 # select partition 5
  echo 20 # Linux Filesystem

  echo p # print the partition table

  echo w # write the partition table
) | sudo fdisk ${DEV}

# -------------------- PART 3 --------------------
# Step 3: Partition alignment check
echo "--------------------------------------------------------------------------------"
echo "checking partition alignment..."

function align_check() {
    (
      echo
      echo $1
    ) | sudo parted $DEV align-check opt $1 | grep aligned | sed "s/^/partition /"
}

align_check 1
align_check 2
align_check 3
align_check 4
align_check 5

# -------------------- PART 4 --------------------
# Step 4: Getting created partition names
echo "--------------------------------------------------------------------------------"
echo "getting created partition names..."

i=1
for part in $(sudo fdisk -l | grep $DEV | grep -v "," | awk '{print $1}'); do
    echo "[$i] $part"
    i=$((i+1))
    PARTITIONS[$i]=$part
done

P1=${PARTITIONS[2]}
P2=${PARTITIONS[3]}
P3=${PARTITIONS[4]}
P4=${PARTITIONS[5]}
P5=${PARTITIONS[6]}

# -------------------- PART 5 --------------------
# Step 5: Creating filesystems
echo "--------------------------------------------------------------------------------"

echo "making filesystem on ${P1}..."
sudo umount ${P1} 2>/dev/null || true
sudo mkfs.fat -F 32 -n boot ${P1}            # (for UEFI systems only)

echo "enabling swap..."
sudo mkswap -L swap ${P2}
sudo swapon ${P2}

echo "making filesystem on ${P3}..."
sudo umount ${P3} 2>/dev/null || true
sudo mkfs.ext4 -L nixos ${P3}                # (root partition for OS)

echo "making filesystem on ${P4}..."
sudo umount ${P4} 2>/dev/null || true
sudo mkfs.ext4 -L var ${P4}                  # (partition for databases and other variable data)

echo "making filesystem on ${P5}..."
sudo umount ${P5} 2>/dev/null || true
sudo mkfs.ext4 -L apps ${P5}                 # (partition for apps and Docker containers)

# -------------------- PART 6 --------------------
# Step 6: Mounting filesystems
echo "mounting filesystems..."

sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot

sudo mkdir -p /mnt/var
sudo mount /dev/disk/by-label/var /mnt/var

sudo mkdir -p /mnt/apps
sudo mount /dev/disk/by-label/apps /mnt/apps

# Create additional directories for Docker volumes
sudo mkdir -p /mnt/var/docker-volumes
sudo mkdir -p /mnt/apps/docker

# -------------------- PART 7 --------------------
# Step 7: Generating NixOS configuration
echo "generating NixOS configuration..."

sudo nixos-generate-config --root /mnt

# -------------------- PART 8 --------------------
# Step 8: Installing NixOS
echo "installing NixOS..."

sudo nixos-install --no-root-passwd

# -------------------- PART 9 --------------------
# Step 9: Final steps
echo "Remove installation media and the system will reboot in 10 seconds."
sleep 10

reboot
