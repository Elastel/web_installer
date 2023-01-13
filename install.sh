#!/bin/bash

model=$(cat /etc/fw_model)
bit=$(getconf LONG_BIT)

if [ ! -n "$model" ]; then
        model="EG500"
fi

echo model:$model

echo -e "\r\nInstalling Dependency Packages..."
sudo apt-get update
sudo apt-get install git dhcpcd5 lighttpd hostapd dnsmasq iptables-persistent vnstat qrencode php7.4-cgi libmosquitto-dev libsqlite3-dev libcurl4-openssl-dev libjson-c-dev ifmetric wireless-tools bridge-utils

echo -e "\r\nCheck packages..."
arr=(git dhcpcd5 lighttpd hostapd dnsmasq iptables-persistent vnstat qrencode php7.4-cgi libmosquitto-dev libsqlite3-dev libcurl4-openssl-dev ifmetric wireless-tools bridge-utils)
count=0

for i in ${arr[@]}; do
	dpkg -s "$i" &> /dev/null

	if [ $? -eq 0 ]; then
		echo "$i is installed!"
	else
		echo "$i is NOT installed!"
		((count++))
    fi
done

if [[ $count > 0 ]]; then
	echo -e "\r\n\e[31mWarnnning:\e[0mInstallation of the dependency package fails. Check the network or manually install the uninstalled software package."
	exit 0
fi

if [ ! -f "/usr/local/sbin/WebTunnelAgent" ]; then
    curl https://raw.githubusercontent.com/my-devices/agent-installer/master/install.sh | bash
fi

echo -e "Enabled web server..."
sudo lighttpd-enable-mod fastcgi-php
sudo service lighttpd force-reload
sudo systemctl restart lighttpd.service

echo -e "Create web APP..."
sudo rm -rf /var/www/html
sudo git clone -b EG-develop https://github.com/Elastel/webgui /var/www/html

htmlPath="/var/www/html"
if [ ! -d "$htmlPath" ]; then
	echo -e "\r\n\e[31mWarnnning:\e[0mThe Web app fails to be downloaded. Check the network or run install.sh again."
	exit 0
fi

sleep 1

cd /var/www/html
sudo cp config/50-raspap-router.conf /etc/lighttpd/conf-available/
sudo ln -s /etc/lighttpd/conf-available/50-raspap-router.conf /etc/lighttpd/conf-enabled/50-raspap-router.conf
sudo systemctl restart lighttpd.service
sudo cp config/090_raspap /etc/sudoers.d/090_raspap

sleep 1

sudo mkdir /etc/raspap/
sudo mkdir /etc/raspap/backups
sudo mkdir /etc/raspap/networking
sudo mkdir /etc/raspap/hostapd
sudo mkdir /etc/raspap/lighttpd
sudo mkdir /etc/config
sudo cp raspap.php /etc/raspap
sudo chown -R www-data:www-data /var/www/html
sudo chown -R www-data:www-data /etc/raspap

sleep 1

sudo cp installers/*log.sh /etc/raspap/hostapd
sudo cp installers/service*.sh /etc/raspap/hostapd
sudo chown -c root:www-data /etc/raspap/hostapd/*.sh
sudo chmod 750 /etc/raspap/hostapd/*.sh
sudo cp installers/configport.sh /etc/raspap/lighttpd
sudo chown -c root:www-data /etc/raspap/lighttpd/*.sh
sudo cp installers/raspapd.service /lib/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable raspapd.service

sleep 1

sudo cp /etc/default/hostapd ~/default_hostapd.old
sudo cp /etc/hostapd/hostapd.conf ~/hostapd.conf.old
sudo cp config/hostapd.conf /etc/hostapd/hostapd.conf
sudo cp config/090_raspap.conf /etc/dnsmasq.d/090_raspap.conf
sudo cp config/090_br0.conf /etc/dnsmasq.d/090_br0.conf
sudo cp config/dhcpcd.conf /etc/dhcpcd.conf
sudo cp config/config.php /var/www/html/includes/
sudo cp config/defaults.json /etc/raspap/networking/
sudo cp -r Elastel/$model/etc/* /etc/
sleep 1
sub_mac=$(ifconfig br0 | grep ether | awk '{print $2}' | cut -f 5-6 -d ":" | tr -d ":")
ssid="$model"_"$sub_mac"
sed -i "s/ssid.*/ssid=$ssid/" /etc/hostapd/hostapd.conf
sleep 1
sudo rm /etc/rc5.d/S01init-wifi
sudo rm /etc/rc5.d/S10failover
sudo rm /etc/rc5.d/S10lte
sudo rm /etc/rc5.d/S10dct
sudo rm /etc/rc5.d/S10daemon
sudo rm /etc/rc5.d/S10ddns
sudo rm /etc/rc5.d/S10macchina
sleep 1
sudo ln -s /etc/init.d/init-wifi /etc/rc5.d/S01init-wifi
sudo ln -s /etc/init.d/failover /etc/rc5.d/S10failover
sudo ln -s /etc/init.d/lte /etc/rc5.d/S10lte
sudo ln -s /etc/init.d/dct /etc/rc5.d/S10dct
sudo ln -s /etc/init.d/daemon /etc/rc5.d/S10daemon
sudo ln -s /etc/init.d/ddns /etc/rc5.d/S10ddns
sudo ln -s /etc/init.d/macchina /etc/rc5.d/S10macchina
sleep 1
sudo /etc/init.d/dct stop
sudo /etc/init.d/failover stop
sudo /etc/init.d/lte stop
sudo /etc/init.d/ddns stop

sleep 2
sudo cp -r Elastel/$model/usr/* /usr/
sleep 2
sudo systemctl stop systemd-networkd
sudo systemctl disable systemd-networkd
sudo cp config/raspap-bridge-br0.netdev /etc/systemd/network/raspap-bridge-br0.netdev
sudo cp config/raspap-br0-member-eth1.network /etc/systemd/network/raspap-br0-member-eth1.network

sleep 1

sudo sed -i -E 's/^session\.cookie_httponly\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/session.cookie_httponly = 1/' 	/etc/php/7.4/cgi/php.ini
sudo sed -i -E 's/^;?opcache\.enable\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/opcache.enable = 1/' 	/etc/php/7.4/cgi/php.ini
sudo phpenmod opcache

sleep 1

echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/90_raspap.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/90_raspap.conf
sudo /etc/init.d/procps restart
sudo iptables -t nat -A POSTROUTING -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.50.0/24 ! -d 192.168.50.0/24 -j MASQUERADE
sudo iptables-save | sudo tee /etc/iptables/rules.v4

sleep 1

if [ $model = "EG410" ]; then
	if [ -e /dev/ttyACM0 ]; then
		sudo cp Elastel/$model/usr/sbin/dctd-new /usr/sbin/dctd
	fi

fi

sudo kill -9 $(pgrep daemond) && sudo cp Elastel/$model/sbin/* /sbin/

echo -e "Complete to install, it will reboot system."

sudo systemctl unmask hostapd.service
sudo systemctl enable hostapd.service
sudo systemctl reboot
