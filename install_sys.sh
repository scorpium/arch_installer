#!/bin/bash

green="\e[0;92m"
red="\e[0;91m"
blue="\e[0;34m"
purple="\e[0;35m"
yellow="\e[0;33m"
cyan="\e[0;36m"
reset="\e[0m"

# Never run pacman -Sy on your system!
# Install dialog
pacman -Sy dialog --noconfirm

### Set the console keyboard layout ###
# Available layouts can be listed with: ls /usr/share/kbd/keymaps/**/*.map.gz
# if zsh (z-shell) is in use
ls -R /usr/share/kbd/keymaps/ | grep map.gz | rev | cut -d'.' -f 3- | rev > keymap.list  # lista todos arquivos map.gz e retira o final map.gz
while true ; do
	keyb=$(dialog --no-cancel --stdout --title "Set the console keyboard layout" \
		--menu	"The default console keymap is US" \
		0 0 0	\
		1 "Set br-abnt2 BR" \
		2 "Maintain default US" \
		3 "Other layouts")
	if [ "$keyb" = "1" ]; then
		clear ; keyb="br-abnt2"  #loadkeys $keyb
		break 
	elif [ "$keyb" = "3" ]; then
		keyb=$(dialog --stdout --title "Set the console keyboard layout" \
		--menu "Choose your layout" \
		0 0 0 \
		$(cat -n keymap.list))
		if [[ $? == 0 ]]; then
			keyb=$(sed -n ${keyb}p keymap.list)
			clear
			echo $keyb # loadkeys $keyb
			sleep 2
			break
		fi	
	else
		echo "US"
		break
	fi
done
rm keymap.list
echo $keyb

### Verify boot (UEFI or BIOS) ###
uefi=0
ls /sys/firmware/efi/efivars 2> /dev/null && uefi=1

### Connect to the internet ###
clear
echo -e "\n         ${purple}Connect to the internet${reset}"
echo -e "\n     Ensure your network interface is listed and enabled"
echo
ip link
sleep 5
echo
echo -e "  \n ${cyan}The connection may be verified with ping${reset}\n"
ping -c 4 archlinux.org
if [ "$?" = "0" ]; then
	echo
	echo -e "    ${green}Connected${reset}"
	sleep 2
else
	echo
  	echo -e "    ${red}Not connected${reset}"
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
    It will DESTROY EVERYTHING on one of your hard disk. \n\n\
    Don't say YES if you are not sure what you're doing! \n\n\
    Do you want to continue?" 15 60 || exit

#dialog --no-cancel --inputbox "Enter a name for your computer." \
#    10 60 2> comp

#comp=$(cat comp) && rm comp

# Choosing the hard drive
devices_list=($(lsblk -d | awk '{print "/dev/" $1 " " $4 " on"}' \
    | grep -E 'sd|hd|vd|nvme|mmcblk'))

dialog --title "Choose your hard drive" --no-cancel --radiolist \
    "Where do you want to install your new system? \n\n\
    Select with SPACE, valid with ENTER. \n\n\
    WARNING: Everything will be DESTROYED on the hard disk!" \
    15 60 4 "${devices_list[@]}" 2> hd

hd=$(cat hd) && rm hd

auto_partition() {
	swap_type=$(dialog --title "Swap type" \
		--menu --no-cancel --stdout\
		"Would you like a swap partition, a file \
		swap or no swap?" \
		0 0 0 1 "Swap partition" \n
			  2 "File swap" \n
			  3 "No swap")
	if [ "$swap_type" = "1" ]; then
		# Ask for the size of the swap partition
		default_size=4
		dialog --no-cancel --inputbox \
			"You need three partitions: Boot, Root and Swap \n\
			The boot partition will be 512M \n\
			The root partition will be the remaining of the hard disk \n\n\
			Enter below the partition size (in GB) for the swap. \n\n\
			If you don't enter anything, it will default to ${default_size}G. \n" \
			20 60 2> swap_size

		size=$(cat swap_size) && rm swap_size

		[[ $size =~ ^[0-9]+$ ]] || size=$default_size
	fi	

	dialog --no-cancel \
		--title "!!! DELETE EVERYTHING !!!" \
		--menu "Choose the way you'll wipe your hard didk ($hd)" \
		15 60 4 \
		1 "Use dd (wipe all disk)" \
		2 "Use schred (slow & secure)" \
		3 "No need - my hard disk is empty" 2> eraser

	hderaser=$(cat eraser); rm eraser

	# This function can wipe out a hard disk.
	# DO NOT RUN THIS FUNCTION ON YOUR ACTUAL SYSTEM!
	# If you did it, DO NOT CALL IT!!
	# If you did it, I'm sorry.
	function eraseDisk() {
		case $1 in
		    1) dd if=/dev/zero of="$hd" status=progress 2>&1 \
		        | dialog \
		        --title "Formatting $hd..." \
		        --progressbox --stdout 20 60;;
		    2) shred -v "$hd" \
		        | dialog \
		        --title "Formatting $hd..." \
		        --progressbox --stdout 20 60;;
		    3) ;;
		esac
	}

	eraseDisk "$hderaser"

	boot_partition_type=1
	[[ "$uefi" == 0 ]] && boot_partition_type=4

	# Create the partitions

	#g - create non empty GPT partition table
	#n - create new partition
	#p - primary partition
	#e - extended partition
	#w - write the table to disk and exit

	partprobe "$hd"
	
	if [ "$swap_type" = 1 ]; then
		fdisk "$hd" << EOF
		g
		n


		+300M
		t
		$boot_partition_type
		n


		+${size}G
		n



		w
		EOF
	else
		fdisk "$hd" << EOF
		g
		n


		+300M
		t
		$boot_partition_type
		n



		w
		EOF
	fi
	partprobe "$hd"
}

manual_partition() {
	fdisk "$hd"
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
	elif [ "$part_mode" = "2" ]; then
		auto_partition
		break
	else
		exit	
	fi
done

### Format the partitions and mount the file systems ###

if [ "$swap_type" = "1" ]; then
	mkswap "${hd}2"
	swapon "${hd}2"
	mkfs.ext4 "${hd}3"
	mount "${hd}3" /mnt
else
	mkfs.ext4 "${hd}2"
	mount "${hd}2" /mnt
fi

if [ "$uefi" = 1 ]; then
    mkfs.fat -F32 "${hd}1"
    mkdir -p /mnt/boot/efi
    mount "${hd}1" /mnt/boot/efi
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
echo "$hd" > /mnt/var_hd
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
"Congrats! The install is done! \n\n\
Do you want to reboot your computer?" 20 60

response=$?

case $response in
    0) reboot;;
    1) clear;;
esac
