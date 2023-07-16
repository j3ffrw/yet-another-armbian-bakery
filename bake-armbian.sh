#!/bin/bash

set -eo pipefail

# Bake the Armbian image with some customization.
# Totally based on https://github.com/kenfallon/fix-ssh-on-pi/blob/master/fix-ssh-on-pi.bash
# However, I wanted to remove some stuff and make script smaller for Armbian.

# shellcheck source=./properties
source "./properties.armbian"

shortcut_url="${download_site}/orangepi4/${os_version}"
shortcut_url_response=$(curl --silent "${shortcut_url}" --head)
download_url=$(echo "${shortcut_url_response}" | grep location | sed -e 's/^.*https:/https:/g' -e 's/xz.*$/xz/g')
downloaded_image=$(basename "${download_url}")

echo "Download URL: $download_url"
echo "Download Image: $downloaded_image"
 
[[ ! -f "${downloaded_image}" ]] && curl -O "${download_url}" 
current_sha256=$(sha256sum "${downloaded_image}")
image_sha256=$(curl "${download_url}.sha" | sed -r 's/(.*)(\*.*)(Armbian.*)/\1 \3/g')
extracted_image_path=$(echo "${downloaded_image}" | sed 's/.xz//g')

echo "Downloaded image sha256..: $current_sha256"
echo "Expected image sha256....: $image_sha256"

if [[ "$current_sha256" != "$image_sha256" ]]
then
    echo -e "\e[31mERROR: Invalid Checksum!\e[0m"
    exit 1
fi

# Extract the image.
7z x -y "${downloaded_image}"
partition1=$(echo "${extracted_image_path}" | sed 's#.img#/p1#g')

echo "Creating partitions:"
echo "$partition1"

# Create the mount points.
mkdir -p "${partition1}"

################################################################################
# BEGIN CUSTOMIZATION / (PARTITION 1)
# Everything you need to customize goes between the MOUNT (line 52) and UMOUNT (line 109) commands.
################################################################################

# Mount the / partition
loop_base=$(losetup --partscan --find --show "${extracted_image_path}")
echo "$loop_base"
mount "${loop_base}p1" "${partition1}"

# Hardening a little bit the SSH.
sed -e "s#^root:[^:]\+:#root:${root_password_hash}:#" "${partition1}/etc/shadow" 
sed -e 's;^#PasswordAuthentication.*$;PasswordAuthentication no;g' -e 's;^PermitRootLogin .*$;PermitRootLogin no;g' -i "${partition1}/etc/ssh/sshd_config"
sed 's/#Port 22/Port 2222/g' -i "${partition1}/etc/ssh/sshd_config"

# Configure WIFI - Attempt 2 via /etc/wpa_supplicant.conf
echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=${wifi_country}

network={
	ssid=\"${wifi_name}\"
	psk=\"${wifi_password}\"
}" > ${partition1}/etc/wpa_supplicant/wpa_supplicant.conf

echo "auto wlan0
iface wlan0 inet dhcp
wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf" | tee -a ${partition1}/etc/network/interfaces

################################################################################
# IMPORTANT
################################################################################
# NetworkManager ALWAYS conflicts with something (wpa_supplicant).
# It's not a elegant solution, but since we cannot disable it during the baking time using systemd or something similar,
# I'm doing the bruteforce here, maybe we'll face another collateral effects, but let's see.
# Note: Tested and worked at the first boot and reboots!
mv ${partition1}/etc/NetworkManager ${partition1}/etc/NetworkManager.old
################################################################################

# Add pi user.
echo "pi:x:9000:9000:pi:/home/pi:/bin/bash" | tee -a ${partition1}/etc/passwd
echo "pi:x:9000:" | tee -a ${partition1}/etc/group
echo "pi:${pi_password_hash}:19086:0:99999:7:::" | tee -a ${partition1}/etc/shadow

# Add pi to sudo group and sudoers.
echo "sudo:x:27:pi" | tee -a ${partition1}/etc/group
echo "pi ALL=(ALL) NOPASSWD: ALL" | tee -a ${partition1}/etc/sudoers

# Provision the pi's home folder.
cp --recursive "${partition1}/etc/skel" "${partition1}/home/pi"
chown --recursive 9000:9000 "${partition1}/home/pi"
chmod --recursive 0755 "${partition1}/home/pi"

# Add Ansible Key to pi user.
mkdir -p "${partition1}/home/pi/.ssh"
chmod 0700 "${partition1}/home/pi/.ssh"
chown 9000:9000 "${partition1}/home/pi/.ssh"
cat "${public_key_file}" >> "${partition1}/home/pi/.ssh/authorized_keys"
chown 9000:9000 "${partition1}/home/pi/.ssh/authorized_keys"
chmod 0600 "${partition1}/home/pi/.ssh/authorized_keys"

# Remove this file so we don't trigger the wizard.
rm -rf "${partition1}/root/.not_logged_in_yet"

# Umount the / partition.
sync; umount --verbose "${partition1}"; sync
losetup --verbose --detach "${loop_base}"; rmdir -v "${partition1}"
################################################################################
# END CUSTOMIZATION / (PARTITION 1)
################################################################################

new_name="${extracted_image_path%.*}-baked-by-thiago.img"
mv -v "${extracted_image_path}" "${new_name}"
 
rm -rf "${extracted_image_path}"
rm -rf "${downloaded_image}.sha256"
rm -rf "${partition1}"
rm -rf "$(dirname "${partition1}")"

echo -e "\e[32m#####################################################################\e[0m"
echo -e "\e[32mSUCCESS\e[0m"
echo "You can execute: dd bs=4M status=progress if=${new_name} of=/dev/xyz"
echo -e "\e[32m#####################################################################\e[0m"
