#!/bin/bash

GREEN="\e[0;92m"
RED="\e[0;91m"
BLUE="\e[0;34m"
PURPLE="\e[0;35m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
RESET="\e[0m"

part_mode=

# Never run pacman -Sy on your system!
# Install dialog
pacman -Sy dialog --noconfirm

### Set the console keyboard layout ###
# Available layouts can be listed with: ls /usr/share/kbd/keymaps/**/*.map.gz
# if zsh (z-shell) is in use
ls -R /usr/share/kbd/keymaps/ | grep map.gz | rev | cut -d'.' -f 3- | rev > keymap.list  # lista todos arquivos map.gz e retira o final map.gz
while true ; do
	KEYB=$(dialog --no-cancel --stdout --title "Set the console keyboard layout" \
		--menu	"The default console keymap is US" \
		0 0 0	\
		1 "Set br-abnt2 BR" \
		2 "Maintain default US" \
		3 "Other layouts")
	if [ "$KEYB" = "1" ]; then
		clear ; KEYB="br-abnt2" ; loadkeys $KEYB
		break 
	elif [ "$KEYB" = "3" ]; then
		KEYB=$(dialog --stdout --title "Set the console keyboard layout" \
		--menu "Choose your layout" \
		0 0 0 \
		$(cat -n keymap.list))
		if [[ $? == 0 ]]; then
			KEYB=$(sed -n ${KEYB}p keymap.list)
			clear
			loadkeys $KEYB
			break
		fi	
	else
		break
	fi
done
rm keymap.list

### Verify boot (UEFI or BIOS) ###
UEFI=0
ls /sys/firmware/efi/efivars 2> /dev/null && UEFI=1

### Connect to the internet ###
clear
echo -e "\n         ${PURPLE}Connect to the internet${RESET}"
echo -e "\n     Ensure your network interface is listed and enabled"
echo
ip link
sleep 3
echo
echo -e "  \n ${CYAN}The connection may be verified with ping${RESET}\n"
ping -c 3 archlinux.org
if [ "$?" = "0" ]; then
	echo
	echo -e "    ${GREEN}Connected${RESET}"
	sleep 1
else
	echo
  	echo -e "    ${RED}Not connected${RESET}"
	sleep 2
	exit
fi
read -rp "Press Enter to continue  "

### Update the system clock ###
clear
echo -e "\n\n   Updating the system clock ..."
timedatectl set-ntp true
sleep 1
echo
echo
timedatectl status
echo
read -rp "   Press Enter to continue  "

# Welcome message of type yesno - see 'man dialog'
dialog --defaultno --title "Are you sure?" --yesno \
    "This is the partition session. \n\n\
    It will DESTROY EVERYTHING on one of your device. \n\n\
    Don't say YES if you are not sure what you're doing! \n\n\
    Do you want to continue?" 15 60 || exit

#dialog --no-cancel --inputbox "Enter a name for your computer." \
#    10 60 2> comp

#comp=$(cat comp) && rm comp

# Choosing the hard drive
DEVICES_LIST=($(lsblk -d | awk '{print "/dev/" $1 " " $4 " on"}' \
    | grep -E 'sd|hd|vd|nvme|mmcblk'))

dialog --title "Choose your device" --no-cancel --radiolist \
    "Where do you want to install your new system? \n\n\
    Select with SPACE, valid with ENTER. \n\n\
    WARNING: Everything will be DESTROYED on the device!" \
    15 60 4 "${DEVICES_LIST[@]}" 2> hd

DEVICE=$(cat hd) && rm hd

prepare_partition() {
	mountpoint -q /mnt/boot
    	if [ $? == 0 ]; then
        	umount /mnt/boot
    	fi
    	mountpoint -q /mnt
    	if [ $? == 0 ]; then
        	umount /mnt
    	fi
}

auto_partition() {
	prepare_partition
	SWAP_TYPE=$(dialog --title "Swap type" \
		--no-cancel --stdout --menu	"Would you like \
		a swap partition, a file swap or no swap?" \
		0 0 0 1 "Swap partition" \
			  2 "File swap" \
			  3 "No swap")
	if [ "$SWAP_TYPE" = "1" ]; then
		# Ask for the size of the swap partition
		DEFAULT_SIZE=4
		dialog --no-cancel --inputbox \
			"You need three partitions: Boot, Root and Swap \n\
			The boot partition will be 512M \n\
			The root partition will be the remaining of the device \n\n\
			Enter below the partition size (in GB) for the swap. \n\n\
			If you don't enter anything, it will default to ${DEFAULT_SIZE}G. \n" \
			20 60 2> swap_size

		SWAP_SIZE=$(cat swap_size) && rm swap_size

		[[ $SWAP_SIZE =~ ^[0-9]+$ ]] || SWAP_SIZE=$DEFAULT_SIZE
	fi	

	dialog --no-cancel \
		--title "!!! DELETE EVERYTHING !!!" \
		--menu "Choose the way you'll wipe your device ($DEVICE)" \
		15 60 5 \
		1 "Use sgdisk (faster)" \
		2 "Use dd (wipe all disk)" \
		3 "Use schred (slow & secure)" \
		4 "No need - my device is empty" 2> eraser

	DEVICE_ERASER=$(cat eraser); rm eraser

	#This function can wipe out a hard disk.
	#DO NOT RUN THIS FUNCTION ON YOUR ACTUAL SYSTEM!
	#If you did it, DO NOT CALL IT!!
	# If you did it, I'm sorry.
	function eraseDisk() {
		case $1 in
		    1) 	sgdisk --zap-all $DEVICE
        		sgdisk -o $DEVICE
        		wipefs -a -f $DEVICE
        		partprobe -s $DEVICE
		    2) dd if=/dev/zero of="$DEVICE" status=progress 2>&1 \
		        | dialog \
		        --title "Formatting $DEVICE ..." \
		        --progressbox --stdout 20 60;;
		    3) shred -v "$DEVICE" \
		        | dialog \
		        --title "Formatting $DEVICE ..." \
		        --progressbox --stdout 20 60;;
		    *) ;;
		esac
	}

	eraseDisk "$DEVICE_ERASER"

	BOOT_PARTITION_TYPE=1
	[[ "$UEFI" == 0 ]] && BOOT_PARTITION_TYPE=4
	
	PARTITION_PARTED_UEFI="mklabel gpt mkpart ESP fat32 1MiB 512MiB mkpart root ext4 512MiB 100% set 1 esp on"
	PARTITION_PARTED_UEFI_SWAP="mklabel gpt mkpart ESP fat32 1MiB 512MiB mkpart swap linux-swap 512MiB ${SWAP_SIZE}.5GiB mkpart root ext4 $SWAP_SIZE}.5GiB 100% set 1 esp on"
    PARTITION_PARTED_BIOS="mklabel msdos mkpart primary ext4 4MiB 512MiB mkpart primary ext4 512MiB 100% set 1 boot on"
    PARTITION_PARTED_BIOS_SWAP="mklabel msdos mkpart primary ext4 4MiB 512MiB mkpart primary linux-swap 512MiB ${SWAP_SIZE}.5GiB mkpart primary ext4 $SWAP_SIZE}.5GiB 100% set 1 boot on"

	# Create the partitions

	#g - create non empty GPT partition table
	#n - create new partition
	#p - primary partition
	#e - extended partition
	#w - write the table to disk and exit

	partprobe "$DEVICE"
	
	if [ "$SWAP_TYPE" = "1" ]; then
		if [ "UEFI" = "1" ]; then
			parted -s $DEVICE $PARTITION_PARTED_UEFI_SWAP
		else
			parted -s $DEVICE $PARTITION_PARTED_BIOS_SWAP
		fi
	else
		if [ "UEFI" = "1" ]; then
			parted -s $DEVICE $PARTITION_PARTED_UEFI
		else
			parted -s $DEVICE $PARTITION_PARTED_BIOS
		fi	
	fi
	partprobe "$DEVICE"
}

manual_partition() {
	fdisk "$DEVICE"
	clear
	echo -e "Let's format the partitions: "
	fdisk -l
	while true ; do
		read -p "1)Swap Partition 2)Swap File or 3)No swap (1,2 or 3):" swap
		SWAP_TYPE=$swap
		if [ "$swap" -lt "1" ] || [ "$swap" -gt "3" ]; then
			echo "Wrong number"
		elif [ "$swap" = "1" ]; then
			read -p "Swap partition number ${DEVICE}? :" swap_number
			mkswap "${DEVICE}${swap_number}"
        		swapon "${DEVICE}${swap_number}"
			break
		fi
	done
	while true ; do
		read -p "Root partition number ${DEVICE}? :" root_number
		echo "${DEVICE}${root_number} - Is that correct? yn" 
		read answer
		if [ "$answer" = "y" ]; then
	 		mkfs.ext4 "${DEVICE}${root_number}"
			mount "${DEVICE}${root_number}" /mnt
			break
		fi
	done
}

while true ; do
	part_mode=$(dialog --stdout --title "Partition mode" \
		--no-cancel --menu "\nWould you like to partition manually \
		or automatically?" \
		0 0 0 1 "Manual" \
			  2 "Auto" \
			  3 "Abort installation")
	if [ "$part_mode" = "1" ]; then
		manual_partition
		if [ "$?" = "0" ]; then
			break
		fi
	elif [ "$part_mode" = "2" ]; then
		auto_partition
		break
	else
		exit	
	fi
done

### Format the partitions and mount the file systems ###

if [ "$part_mode" = "2" ]; then
	if [ "$SWAP_TYPE" = "1" ]; then
		mkswap "${DEVICE}2"
		swapon "${DEVICE}2"
		mkfs.ext4 "${DEVICE}3"
		mount "${DEVICE}3" /mnt
	else
		mkfs.ext4 "${DEVICE}2"
		mount "${DEVICE}2" /mnt
	fi
fi

if [ "$uefi" = "1" ]; then
    mkfs.fat -F32 "${DEVICE}1"
    mkdir -p /mnt/boot/efi
    mount "${DEVICE}1" /mnt/boot/efi
fi


clear
echo " script interrupted for testing"
read -rp "   Press Enter to continue  "
exit

# Install Arch Linux! Glory and fortune!
pacstrap /mnt base base-devel linux linux-firmware
genfstab -U /mnt >> /mnt/etc/fstab

# Persist important values for the next script
echo "$uefi" > /mnt/var_uefi
echo "$DEVICE" > /mnt/var_hd
echo "$comp" > /mnt/comp

# Don't forget to replace "Phantas0s" by the username of your Github account
curl https://raw.githubusercontent.com/scorpium\
/arch_installer/main/install_chroot.sh > /mnt/install_chroot.sh

arch-chroot /mnt bash install_chroot.sh

rm /mnt/var_uefi
rm /mnt/var_hd
rm /mnt/install_chroot.sh
rm /mnt/comp

dialog --title "To reboot or not to reboot?" --yesno \
/"Congrats! The install is done! \n\n\
Do you want to reboot your computer?" 20 60

response=$?

case $response in
    0) reboot;;
    1) clear;;
esac
