#!/bin/bash
GLOBAL_PATH=$(pwd)
TESTNET_DIR=$(cat testnet.name);

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    local a=$(echo "$ip" | cut -f1 -d".");
    local b=$(echo "$ip" | cut -f2 -d".");
    local c=$(echo "$ip" | cut -f3 -d".");
    local d=$(echo "$ip" | cut -f4 -d".");
    if [[ $ip == "0.0.0.0" ]]; then
    	stat=0
    fi
    if [[ $a != "192" ]] || [[ $b != "168" ]]; then
    	stat=0
    fi
    if [ "$c" -gt "103" ] || [ "$c" -lt "100" ]; then
    	stat=0
    fi
    return $stat
}


## Check KBFS mount point
echo
echo "--------------- VERIFYING KEYBASE FILE SYSTEM ---------------";
echo

KBFS_MOUNT=$(keybase status | grep mount | cut -f 2 -d: | sed -e 's/^\s*//' -e '/^$/d');

## Restart Keybase if needed

if [ ! -d "$KBFS_MOUNT" ]; then
	echo "KBFS is not running!";
	run_keybase
	sleep 3
else
	echo "KBFS mount point: $KBFS_MOUNT";
fi

myKeybaseUser=$(keybase status | grep Username: | cut -f2- -d: | sed -e 's/^\s*//' -e '/^$/d');

echo "Keybase user = $myKeybaseUser";
echo "# --- --- ---" > config.ini.temp;

wgPeerCount=0;
eosPeerCount=0;

if [[ $1 == "lxd" ]]; then
	echo -e "\n ### ----- LXD MODE ----- ###\n";
	LXD_MODE=true;
	WG_DATA=$(lxc exec eos-node -- cat /etc/wireguard/ghostbusters.conf)
	PVT_KEY=$(echo "$WG_DATA" | grep "PrivateKey" | cut -f2 -d"=" | sed -e 's/^\s*//' -e '/^$/d')"=";
	WG_PUB_KEY=$(echo "$PVT_KEY" | wg pubkey);
else
	LXD_MODE=false;
	WG_DATA=$(sudo cat /etc/wireguard/ghostbusters.conf)
	WG_ADDR=$(echo "$WG_DATA" | grep "Address" | cut -f2 -d"=" | sed -e 's/^\s*//' -e '/^$/d' | cut -f1 -d'/')
	echo "Wireguard: $WG_ADDR";
	PVT_KEY=$(echo "$WG_DATA" | grep "PrivateKey" | cut -f2 -d"=" | sed -e 's/^\s*//' -e '/^$/d')"=";
	WG_PUB_KEY=$(echo "$PVT_KEY" | wg pubkey);
fi

if [[ ! -f base_config.ini ]]; then
	echo "base_config.ini not found!";
	exit 1
else
	EOS_PUB_KEY=$(cat base_config.ini | grep "peer-private-key" | cut -f3 -d' ' | sed 's/\[//' | cut -f1 -d',');
	echo -e "\nCurrent Public Key: $EOS_PUB_KEY\n";
fi

add_section() {

	if [[ "$WG_PUB_KEY" != "$publickey=" ]]; then
		if [[ $section == "wg" ]] && [[ $publickey != "" ]] && [[ $endpoint != "" ]] && [[ $allowedips != "" ]]; then
			peerIP=$(echo "$allowedips" | cut -f1 -d"/");
			if valid_ip $peerIP; then
				echo -e "\n Injecting wg peer with:\n >> PublicKey: $publickey\n >> Endpoint: $endpoint\n >> AllowedIPs: $allowedips\n >> PKA: $persistentkeepalive\n";
				if [[ $LXD_MODE == true ]]; then
					lxc exec eos-node -- sudo wg set ghostbusters peer "$publickey=" endpoint "$endpoint" allowed-ips "$allowedips" persistent-keepalive "$persistentkeepalive"
				else
					sudo wg set ghostbusters peer "$publickey=" endpoint "$endpoint" allowed-ips "$allowedips" persistent-keepalive "$persistentkeepalive";
				fi
			else
				echo " >> INVALID IP: $allowedips";
				echo
			fi
			publickey=""
			endpoint=""
			allowedips=""
		fi
		section=""
	fi
}

add_eos_line() {

	if [[ $line == "peer-key"* ]]; then
		NEW_PUB_KEY=$(echo "$line" | cut -f3 -d" ");
		if [[ "$NEW_PUB_KEY" != "$EOS_PUB_KEY" ]]; then
			if [[ ${#NEW_PUB_KEY} == 55 ]]; then
				echo " >> $line";
				echo "$line" >> config.ini.temp;
			fi
		fi
	fi

	if [[ $line == "p2p-peer-address"* ]]; then
		EOS_ADDR=$(echo "$line" | cut -f3 -d " " | cut -f1 -d":");
		if [[ "$WG_ADDR" != "$EOS_ADDR" ]]; then
			echo " >> $line";
			echo "$line" >> config.ini.temp;
		fi
	fi
}

if [[ ! -f /etc/wireguard/ghostbusters.conf ]]; then
	echo "Configuration file not found! Please add your interface info to /etc/wireguard/ghostbusters.conf";
	exit 1;
else
	if [[ $LXD_MODE == true ]]; then
		lxc exec eos-node -- wg-quick up ghostbusters;
	else
		sudo wg-quick up ghostbusters;
	fi
fi

for file in $KBFS_MOUNT/team/eos_ghostbusters/mesh/*.trusted_peers.enc.signed; do

	[ -e "$file" ] || continue;

	kbuser=$(echo "$file" | sed -e 's/.*mesh\/\(.*\).trusted_peers.enc.signed*/\1/');

	echo

	echo " --- Verifying signature from $kbuser ---";

	cat "$file" | keybase verify -S "$kbuser" | keybase decrypt &>output;

	out=$(<output);

	err=$(echo "$out" | grep "ERR");

	if [[ "$err" == "" ]]; then

		section="";

		while read line; do
			if [[ $line != "" ]] && [[ $line != \#* ]]; then
				if [[ $line == "["* ]]; then
					add_section;
				fi
				if [[ "${line,,}" == "[peer]" ]]; then
					((wgPeerCount++))
					section="wg";
					continue;
				fi
				if [[ "${line,,}" == "[eos]" ]]; then
					((eosPeerCount++))
					section="eos";
					continue;
				fi
				if [[ $section == "wg" ]]; then
					shopt -s extglob
					prop=$(echo "$line" | cut -f1 -d"=" | sed -e 's/^\s*//' -e '/^$/d');
					prop="${prop,,}";
					prop="${prop%%*( )}";
					value=$(echo "$line" | cut -f2 -d"=" | sed -e 's/^\s*//' -e '/^$/d');
					declare "$prop=$value";
					shopt -u extglob
				fi
				if [[ $section == "eos" ]]; then
					add_eos_line;
				fi
			fi
		done <output
	else
		echo -e "Unable to verify! Skipping...";
	fi
done

# Save wg config
if [[ $LXD_MODE == true ]]; then
	lxc exec eos-node -- wg-quick save ghostbusters;
else
	sudo wg-quick save ghostbusters;
fi

# Display wg
echo -e "\n-------- WIREGUARD INTERFACE ---------";
if [[ $LXD_MODE == true ]]; then
	lxc exec eos-node -- wg show ghostbusters;
else
	sudo wg show ghostbusters;
fi

echo -e "\n-------- EOS CONFIG DATA ---------";

sort config.ini.temp | uniq > autoPeers;
cat autoPeers;
cat base_config.ini > config.ini
echo -e "\n\n### ----- AUTO GENERATED PEER INFO ----- ###\n" >> config.ini;
cat autoPeers >> config.ini
rm autoPeers config.ini.temp;

if [[ $LXD_MODE == true ]]; then
	lxc file push config.ini eos-node/home/eos/gb/config.ini;
	rm config.ini
else
	if [[ -f ./$TESTNET_DIR/config.ini ]]; then
		rm ./$TESTNET_DIR/config.ini;
	fi
	mv config.ini ./$TESTNET_DIR/config.ini;
fi

echo -e "\n >> Update finished!\n >> WG Peers: $wgPeerCount \n >> EOS Peers: $eosPeerCount \n ------ END ------ \n";

if [[ $2 == "restart" ]]; then
	if [[ $LXD_MODE == true ]]; then
		echo -e "\nRestarting nodeos on lxd... \n";
	else
		echo -e "\nRestarting nodeos... \n";
		./$TESTNET_DIR/start.sh
		tail -f ./$TESTNET_DIR/stderr.txt
	fi
fi
