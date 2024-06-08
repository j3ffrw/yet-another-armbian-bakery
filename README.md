# yet-another-armbian-bakery

Bake Your Perfect (almost) Armbian Image.

I already use this method inspired on this script [here](https://github.com/kenfallon/fix-ssh-on-pi/blob/master/fix-ssh-on-pi.bash) for a raspberry-pi board it works without any issues, I've customized the script to my own needs. 

The main goal is:
- WIFI up at the first boot by disabling the NetworkManager
  and enabling systemd-networkd and wpa_supplicant.
- Make some small adjustments on SSH configuration.
- Change root password.
- Add a pi user.
- Add a public key so I can connect orange pi through and manage it through ansible (important topic).

The script it's pretty simple, you have to change the properties file accordling to your needs.

# How to execute?

```bash
git clone https://github.com/thiagosanches/yet-another-armbian-bakery.git
cd yet-another-armbian-bakery
cp properties.armbian.template properties.armbian
sudo bake-armbian.sh 
# or provide your own properties stored somewhere else.
sudo bake-armbian.sh $HOME/my-properties.armbian
```

Right after it finishes, you can write the `.img` to your SD card.

```bash
dd bs=4M status=progress if=NEW_IMAGE.IMG of=/dev/xyz
```
