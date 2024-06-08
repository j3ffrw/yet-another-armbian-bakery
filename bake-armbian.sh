#!/bin/bash

set -eo pipefail

# Bake the Armbian image with some customization.
# Totally based on https://github.com/kenfallon/fix-ssh-on-pi/blob/master/fix-ssh-on-pi.bash
# However, I wanted to remove some stuff and make script smaller for Armbian.

# shellcheck source=./properties
#
properties_file=${1:-'./properties.armbian'}
source "${properties_file}"

if [[ downloaded_image == "" ]]; then
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
else
    extracted_image_path=$(basename "${downloaded_image}" | sed 's/.xz//g')
fi


## Extract the image.
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
echo loop_base: "$loop_base"
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
}" > ${partition1}/etc/wpa_supplicant/wpa_supplicant-wlan0.conf

echo "[Match]
Name=wl*

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=20" > ${partition1}/etc/systemd/network/wireless.network

################################################################################
# IMPORTANT
################################################################################
# NetworkManager ALWAYS conflicts with something (wpa_supplicant).
# Note: Tested and worked at the first boot and reboots!
echo  Disable NetworkManager
rm -f ${partition1}/etc/systemd/system/multi-user.target.wants/NetworkManager.service
rm -f ${partition1}/etc/systemd/dbus-org.freedesktop.nm-dispatcher.service
echo  Remove systemd-networkd mask
rm -f ${partition1}/etc/systemd/system/systemd-networkd.service
echo Enable systemd-networkd
ln -s /lib/systemd/system/systemd-networkd.service ${partition1}/etc/systemd/system/dbus-org.freedesktop.network1.service
ln -s /lib/systemd/system/systemd-networkd.service ${partition1}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -s /lib/systemd/system/systemd-networkd.socket ${partition1}/etc/systemd/system/sockets.target.wants/systemd-networkd.socket
ln -s /lib/systemd/system/systemd-network-generator.service ${partition1}/etc/systemd/system/sysinit.target.wants/systemd-network-generator.service
mkdir ${partition1}/etc/systemd/system/network-online.target.wants
ln -s /lib/systemd/system/systemd-networkd-wait-online.service ${partition1}/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
echo Enable wpa_supplicant@wlan0
ln -s /lib/systemd/system/wpa_supplicant@.service ${partition1}/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service
ls -l ${partition1}/etc/systemd/system/multi-user.target.wants/
ls -l ${partition1}/etc/systemd/system/

echo "\nIP: \4{wlan0}" >> ${partition1}/etc/issue
################################################################################

# Add extra user
echo "${extra_user_name}:x:9000:9000:${extra_user_name}:/home/${extra_user_name}:/bin/bash" | tee -a ${partition1}/etc/passwd
echo "${extra_user_name}:x:9000:" | tee -a ${partition1}/etc/group
echo "${extra_user_name}:${extra_user_password_hash}:19086:0:99999:7:::" | tee -a ${partition1}/etc/shadow
#
## Add extra user to sudo group and sudoers.
echo "sudo:x:27:${extra_user_name}" | tee -a ${partition1}/etc/group
echo "${extra_user_name} ALL=(ALL) NOPASSWD: ALL" | tee -a ${partition1}/etc/sudoers

# Provision the extra user's home folder.
cp --recursive "${partition1}/etc/skel" "${partition1}/home/${extra_user_name}"
chown --recursive 9000:9000 "${partition1}/home/${extra_user_name}"
chmod --recursive 0755 "${partition1}/home/${extra_user_name}"
#
## Add Ansible Key to extra user.
mkdir -p "${partition1}/home/${extra_user_name}/.ssh"
chmod 0700 "${partition1}/home/${extra_user_name}/.ssh"
chown 9000:9000 "${partition1}/home/${extra_user_name}/.ssh"
cat "${public_key_file}" >> "${partition1}/home/${extra_user_name}/.ssh/authorized_keys"
chown 9000:9000 "${partition1}/home/${extra_user_name}/.ssh/authorized_keys"
chmod 0600 "${partition1}/home/${extra_user_name}/.ssh/authorized_keys"
#
## Remove this file so we don't trigger the wizard.
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
