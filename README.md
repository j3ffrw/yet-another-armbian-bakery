# yet-another-armbian-bakery

Bake Your Perfect (almost) Armbian Image.

I already use this method inspired on this script [here](https://github.com/kenfallon/fix-ssh-on-pi/blob/master/fix-ssh-on-pi.bash) for a raspberry-pi board it works without any issues, I've customized the script to my own needs. 

However, recenytly I got an orange-pi 4 board, which suits better with a Armbian distro. I decided to use the same technique, but I was facing an issue with `NetworkManager` that conflicts with `wpa_supplicant`, I've tried any approaches and the last option was to **rename** the folder of the NetworkManager, and that worked! No more conflitcts and I was able to get the wifi connected on the FIRST boot, right after writing to the SD card! 

**I understand that it may not be the most elegant solution, but due to the limitations of removing it via systemd during the baking process, I resorted to trying this alternative approach.**

The main goal is:
- Configure the WIFI.
- Make some small adjustments on SSH configuration.
- Change root password.
- Add a pi user.
- Add a public key so I can connect orange pi through and manage it through ansible (important topic).

The script it's pretty simple, you have to change the properties file accordling to your needs.

# How to execute?

```bash
git clone https://github.com/thiagosanches/yet-another-armbian-bakery.git
cd yet-another-armbian-bakery
sudo bake-armbian.sh
```

Right after it finishes, you can write the `.img` to your SD card.

```bash
dd bs=4M status=progress if=NEW_IMAGE.IMG of=/dev/xyz
```
