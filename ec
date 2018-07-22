#!/bin/bash
panel="cynix3"

for ip in $(wget http://$panel.ethosdistro.com/?ips=yes -q -O -)
do
	echo "$* sent to $ip" 
	ssh ethos@${ip} "$*" &
done
echo "Command send waiting for reply"
sleep 3
