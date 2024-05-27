#!/run/current-system/sw/bin/bash

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
# Step 1: Introduction and prompt for user input
echo "--------------------------------------------------------------------------------"
echo "Your attached storage devices will now be listed."
read -p "Press 'enter' to exit the list. Press enter to continue." NULL

#sudo fdisk -l | less

# -------------------- PART 2 --------------------
# Step 2: Device selection
echo "--------------------------------------------------------------------------------"
echo "Detected the following devices:"
echo

i=0
for device in $(sudo fdisk -l | grep "^Disk /dev" | awk '{print $2}' | sed 's/://'); do
    echo "[$i] $device"
    i=$((i+1))
    DEVICES[$i]=$device
done

echo
read -p "Which device do you wish to install on? " DEVICE

DEV=${DEVICES[$(($DEVICE+1))]}

# Unmount all partitions and deactivate swap
echo "Unmounting all partitions and deactivating swap on ${DEV}..."
for part in $(lsblk -ln -o NAME ${DEV} | grep -v ${DEV}); do
    sudo umount /dev/${part} 2>/dev/null || true
    sudo swapoff /dev/${part} 2>/dev/null || true
done

# -------------------- PART 3 --------------------
# Step 3: Swap space input (Fixed at 4 GiB)
SWAP=4

# -------------------- PART 4 --------------------
# Step 4: Partitioning the selected device

echo "partitioning ${DEV}..."
(
  echo g # new gpt partition table

  echo n # new partition (/EFI System Partition)
  echo 1 # partition 1
  echo   # default start sector
  echo +512M # size is 512M

  echo n # new partition (/swap partition)
  echo 2 # partition 2
  echo   # default start sector
  echo +4G # size is 4G

  echo n # new partition (/root partition for OS)
  echo 3 # partition 3
  echo   # default start sector
  echo +50G # size is 50G

  echo n # new partition (/var partition  for db, var and data)
  echo 4 # partition 4
  echo   # default start sector
  echo +500G # size is 500G

  echo n # new partition (/root partition for apps and Docker containers)
  echo 5 # partition 5
  echo   # default start sector
  echo   # use the remaining space

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

# -------------------- PART 5 --------------------
# Step 5: Partition alignment check
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

# -------------------- PART 6 --------------------
# Step 6: Getting created partition names
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

# -------------------- PART 7 --------------------
# Step 7: Creating filesystems
echo "--------------------------------------------------------------------------------"

echo "making filesystem on ${P1}..."
sudo mkfs.fat -F 32 -n boot ${P1}            # (for UEFI systems only)

echo "enabling swap..."
sudo mkswap -L swap ${P2}
sudo swapon ${P2}

echo "making filesystem on ${P3}..."
sudo mkfs.ext4 -L nixos ${P3}                # (root partition for OS)

echo "making filesystem on ${P4}..."
sudo mkfs.ext4 -L var ${P4}                  # (partition for databases and other variable data)

echo "making filesystem on ${P5}..."
sudo mkfs.ext4 -L apps ${P5}                 # (partition for apps and Docker containers)

# -------------------- PART 8 --------------------
# Step 8: Mounting filesystems
echo "mounting filesystems..."

sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot

sudo mkdir -p /mnt/var
sudo mount /dev/disk/by-label/var /mnt/var

sudo mkdir -p /mnt/apps
sudo mount /dev/disk/by-label/apps /mnt/apps

# Create additional directories for Docker
sudo mkdir -p /mnt/apps/docker

# -------------------- PART 9 --------------------
# Step 9: Generating NixOS configuration
echo "generating NixOS configuration..."

sudo nixos-generate-config --root /mnt

# -------------------- PART 10 --------------------
# Step 10: Editing the configuration
read -p "Press enter and the Nix configuration will be opened in nano." NULL

sudo nano /mnt/etc/nixos/configuration.nix

# -------------------- PART 11 --------------------
# Step 11: Installing NixOS
echo "installing NixOS..."

sudo nixos-install

# -------------------- PART 12 --------------------
# Step 12: Final steps
read -p "Remove installation media and press enter to reboot." NULL

reboot
