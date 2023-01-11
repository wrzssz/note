#!/bin/bash
# install v2ray on centos9
set -e
port=37788
uuid=`cat /proc/sys/kernel/random/uuid`

# download v2ray
tf=`mktemp`; td=`mktemp -d`
curl -sqRLS -H 'Cache-Control: no-cache' --retry 5 --retry-delay 10 --retry-max-time 60 -o $tf 'https://github.com/v2fly/v2ray-core/releases/download/v5.1.0/v2ray-linux-64.zip'
unzip $tf -d $td

# install program file
install -d /usr/local/share/v2ray /usr/local/etc/v2ray
install -m 755 $td/v2ray /usr/local/bin/v2ray
install -m 644 $td/geoip.dat /usr/local/share/v2ray/geoip.dat
install -m 644 $td/geosite.dat /usr/local/share/v2ray/geosite.dat
echo '{
"inbounds": [{
    "port": '$port',
    "protocol": "vmess",
    "settings": {
    "clients": [
        {
            "id": "'$uuid'"
        }
    ]
    }
}],
"outbounds": [{
    "protocol": "freedom",
    "settings": {}
}]
}' > /usr/local/etc/v2ray/config.json

# install log file
install -dm 700 -o nobody -g nobody /var/log/v2ray/
install -m 600 -o nobody -g nobody /dev/null /var/log/v2ray/access.log
install -m 600 -o nobody -g nobody /dev/null /var/log/v2ray/error.log

# install systemd file
install -d /etc/systemd/system/v2ray.service.d /etc/systemd/system/v2ray@.service.d
install -m 644 $td/systemd/system/v2ray.service /etc/systemd/system/v2ray.service
install -m 644 $td/systemd/system/v2ray@.service /etc/systemd/system/v2ray@.service
echo '[Service]
ExecStart=
ExecStart=/usr/local/bin/v2ray run -config /usr/local/etc/v2ray/config.json' > /etc/systemd/system/v2ray.service.d/10-donot_touch_single_conf.conf
cp -f /etc/systemd/system/v2ray.service.d/10-donot_touch_single_conf.conf /etc/systemd/system/v2ray@.service.d/10-donot_touch_single_conf.conf
rm -f /etc/systemd/system/v2ray.service.d/10-donot_touch_multi_conf.conf /etc/systemd/system/v2ray@.service.d/10-donot_touch_multi_conf.conf

# clean
rm -rf $tf $td
systemctl daemon-reload
systemctl enable v2ray --now

echo 'port: '$port
echo 'uuid: '$uuid
echo 'ip: '`curl -sS http://ip.bmh.im/`