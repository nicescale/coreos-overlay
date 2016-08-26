#!/bin/bash
set -e

# Import variable: CONTROLLER_FLOAT_IP
. /etc/csphere/inst-opts.env

host="127.0.0.1"

### Def

isRepl() {
	local output
	output=$( mongo --eval "tojson(rs.status())" $host 2>&1 ) 
	if [ $? -ne 0 ]; then
		echo "exec rs.status() failed: ${output}"
		return 2  # mongo error
	fi
	if echo -e "${output}" | grep -E -q "errmsg.+not running with --replSet"; then
		return 1  # not replset
	fi
	return 0	  # is replset
}

isMaster() {
	local output
	output=$( mongo --eval "tojson(db.isMaster())" $host 2>&1 ) # default 5s timeout
	if [ $? -ne 0 ]; then
		echo "exec db.isMaster() failed: ${output}"
		return 2  # mongo error
	fi
	if echo -e "${output}" | grep -E -q "\"ismaster\" : true"; then
		return 0  # is master
	fi
	return 1 	  # not master
}

online_iface_list() {
	ip link show |grep 'state UP'|awk -F : '{split($2, a, "@"); sub(/^[ \t\r\n]+/, "", a[1]); print a[1]}'
}

iface_addr_list() {
	ip addr show $1|grep -w inet|awk '{split($2, a, "/"); print a[1]}'
}

cidr_mask_bits() {
	ip addr show $1|grep -w $2|awk '{split($2, a, "/"); print a[2]}'
}

in_cidr?() {
	awk -v addr=$1 -v cidr=$2 '
	function ip2long(ip) {
		split(ip, a, ".")
		return lshift(a[1], 24) + lshift(a[2], 16) + lshift(a[3], 8) + a[4]
	}

	BEGIN{
		split(cidr, parts, "/")
		long_ip = ip2long(addr)
		long_range = ip2long(parts[1])
		mask = compl(lshift(1, 32-parts[2]) - 1)
		if (and(long_ip, mask) == and(long_range, mask)) {
			print "yes"
		}
	}'
}

del_ip() {
	if [ -z "$CONTROLLER_FLOAT_IP" ]; then
		return
	fi

	for iface in $(online_iface_list); do
		for addr in $(iface_addr_list $iface); do
			if [ "$addr" = "$CONTROLLER_FLOAT_IP" ]; then
				addr=$addr/$(cidr_mask_bits $iface $CONTROLLER_FLOAT_IP)
				ip addr del $addr dev $iface
				echo "Deleted floating IP $CONTROLLER_FLOAT_IP from $iface"
				return
			fi
		done
	done
}

add_ip() {
	if [ -z "$CONTROLLER_FLOAT_IP" ]; then
		return
	fi
 
	# Already holding the IP
	if ip addr|grep -w inet|grep -q -w $CONTROLLER_FLOAT_IP; then
		return
	fi

	for iface in $(online_iface_list); do
		for cidr in $(ip addr show $iface|grep -w inet|awk '{print $2}'); do
			if [ "yes" = "$(in_cidr? $CONTROLLER_FLOAT_IP $cidr)" ]; then
				echo "Adding IP $CONTROLLER_FLOAT_IP to $iface"
				bits=$(echo $cidr|cut -d / -f 2)
				ip addr add $CONTROLLER_FLOAT_IP/$bits dev $iface
				arping -A -I $iface -c 5 -w 1 $CONTROLLER_FLOAT_IP
				return
			fi
		done
	done
}

### Main Begin

if ! isRepl; then
	echo "$host not in mongo replset mode"
	exit 0
fi

echo "$host is in mongo replset mode"
while :; do
	sleep 1
	if ! isMaster; then
		if cspherectl status controller >/dev/null 2>&1; then
			echo "trying to stop controller ..."
			cspherectl stop controller
		fi
		if cspherectl status prometheus >/dev/null 2>&1; then
			echo "trying to stop prometheus ..."
			cspherectl stop prometheus
		fi
		del_ip
		continue
	fi

	if ! cspherectl status prometheus >/dev/null 2>&1; then
		echo "trying to start prometheus ..."
		cspherectl start prometheus
	fi
	if ! cspherectl status controller >/dev/null 2>&1; then
		echo "trying to start controller ..."
		cspherectl start controller
	fi
	add_ip
done
