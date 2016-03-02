#!/bin/bash
set -ex

# def
FInstOpts="/etc/csphere/inst-opts.env"
FPublicEnv="/etc/csphere/csphere-public.env"

# func def
mask2cidr() {
    local nbits=0
    IFS=.
    for dec in $1 ; do
        case $dec in
            255) let nbits+=8;;
            254) let nbits+=7;;
            252) let nbits+=6;;
            248) let nbits+=5;;
            240) let nbits+=4;;
            224) let nbits+=3;;
            192) let nbits+=2;;
            128) let nbits+=1;;
            0);;
            *) return 1 ;;
        esac
    done
    echo -e "$nbits"
}

# disable user core
os=$( awk -F= '(/^NAME=/){print $2;exit}' /etc/os-release 2>&-)
if [ "${os}" == "COS" ]; then
	usermod  -L core || true
	systemctl mask system-cloudinit@usr-share-coreos-developer_data.service || true
fi

# load install opts file
. ${FInstOpts}

# compatible with old version
if [ -z "${COS_NETMODE}" ]; then
	COS_NETMODE="bridge"
fi

if [ "${COS_NETMODE}" == "bridge" -a "${COS_ROLE}" == "agent" ]; then
	# sync br0 ether mac firstly, so dhcp work well
	# promisc br0, setup br0 hw ether mac
	ifconfig br0 promisc
	br0inet="$(brctl show br0 2>&- | awk '($1=="br0" && NF==4){print $NF}')"
	br0inetmac="$(ifconfig "${br0inet}" | awk '(/\<ether\>/){print $2}')"
	if [ -n "${br0inetmac}" ]; then
		ifconfig br0 hw ether "${br0inetmac}"
	else
		echo "WARN: br0 hw ether mac Null"
	fi
fi


# write csphere-public.env
ipaddr=
mask1=
mask=
defaultgw=

# get controller ip/mask
if [ "${COS_ROLE}" == "controller" ]; then
	for i in `seq 1 10`
	do
		ipaddr=$( ifconfig br0 2>&- |\
			awk '($1=="inet"){print $2;exit}' )
		if [ -z "${ipaddr}" ]; then
			echo "WARN: no local ipaddr found on br0, waitting for ${i} seconds ..."
			sleep ${i}s
		else
			break
		fi
	done
	# we stop while networking broken
	if [ -z "${ipaddr}" ]; then
		echo "CRIT: no local ipaddr found on ${COS_INETDEV}, abort."
		exit 1
	fi
	mask1=$( ifconfig ${COS_INETDEV} 2>&- |\
		awk '($1=="inet"){print $4;exit}' )
	mask=$( mask2cidr ${mask1} )
	if [ $? -ne 0 ]; then
		echo "WARN: convert mask to cidr error on ${mask1}"
	fi

# get agent ip/mask <bridge/ipvlan>
elif [ "${COS_NETMODE}" == "bridge" ]; then
	for i in `seq 1 10`
	do
		ipaddr=$( ifconfig br0  2>&- |\
			awk '($1=="inet"){print $2;exit}' )
		if [ -z "${ipaddr}" ]; then
			echo "WARN: no local ipaddr found on br0, waitting for ${i} seconds ..."
			sleep ${i}s
		else
			break
		fi
	done
	# we stop while networking broken
	if [ -z "${ipaddr}" ]; then
		echo "CRIT: no local ipaddr found on br0, abort."
		exit 1
	fi
	mask1=$( ifconfig br0  2>&- |\
		awk '($1=="inet"){print $4;exit}' )
	mask=$( mask2cidr ${mask1} )
	if [ $? -ne 0 ]; then
		echo "WARN: convert mask to cidr error on ${mask1}"
	fi

elif [ "${COS_NETMODE}" == "ipvlan" ]; then

	for i in `seq 1 10`
	do
		ipaddr=$( ifconfig ${COS_INETDEV} 2>&- |\
			awk '($1=="inet"){print $2;exit}' )
		if [ -z "${ipaddr}" ]; then
			echo "WARN: no local ipaddr found on ${COS_INETDEV} , waitting for ${i} seconds ..."
			sleep ${i}s
		else
			break
		fi
	done
	# we stop while networking broken
	if [ -z "${ipaddr}" ]; then
		echo "CRIT: no local ipaddr found on ${COS_INETDEV}, abort."
		exit 1
	fi
	mask1=$( ifconfig ${COS_INETDEV} 2>&- |\
		awk '($1=="inet"){print $4;exit}' )
	mask=$( mask2cidr ${mask1} )
	if [ $? -ne 0 ]; then
		echo "WARN: convert mask to cidr error on ${mask1}"
	fi

fi

defaultgw=$(route -n 2>&- |\
	awk '($1=="0.0.0.0" && $4~/UG/){print $2;exit;}' )
if [ -z "${defaultgw}" ]; then
	echo "WARN: no local default gateway route found"
fi

IFS=. read -r m0 m1 m2 m3 <<< "$mask1"
IFS=. read -r i0 i1 i2 i3 <<< "$ipaddr"
network=$( printf "%d.%d.%d.%d" "$((i0 & m0))" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" )

cat <<EOF > ${FPublicEnv}
LOCAL_IP=${ipaddr}
NET_MASK=${mask}
DEFAULT_GW=${defaultgw}
NETWORK=${network}
EOF

# load public env file
# variable needed later: ${LOCAL_IP} ${NET_MASK} {DEFAULT_GW}
. ${FPublicEnv}

# setup related files for csphere service units
if [ "${COS_ROLE}" == "controller" ]; then
	# setup /etc/ntp.conf
	[ -L /etc/ntp.conf ] && rm -f /etc/ntp.conf
	cat << EOF > /etc/ntp.conf
server 0.pool.ntp.org
server 1.pool.ntp.org
server 2.pool.ntp.org
server 3.pool.ntp.org

restrict default nomodify nopeer noquery limited kod
restrict ${NETWORK} mask ${mask1} nomodify notrap
EOF

	# create /etc/csphere/csphere-backup.env
	cat << EOF > /etc/csphere/csphere-backup.env
BACKUP_DIR=${BACKUP_DIR:-/backup}
BACKUP_RESERV_DAY=${BACKUP_RESERV_DAY:-7}
DISK_RESERV_PCT=${DISK_RESERV_PCT:-10}
DISK_RESERV_SIZE=${DISK_RESERV_SIZE:-5120}
EOF

	# compatible with old version
	if ! systemctl is-enabled ntpd >/dev/null 2>&1; then
		systemctl enable ntpd.service
	fi
	if ! systemctl is-enabled csphere-backup.service >/dev/null 2>&1; then
		systemctl enable csphere-backup.service
	fi
	if ! systemctl is-active csphere-backup.timer >/dev/null 2>&1; then
		systemctl start csphere-backup.timer
	fi

	# create /etc/csphere/csphere-etcd2-controller.env
	cat << EOF > /etc/csphere/csphere-etcd2-controller.env
ETCD_DATA_DIR=/var/lib/etcd2
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ETCD_ADVERTISE_CLIENT_URLS=http://${LOCAL_IP}:2379
ETCD_LISTEN_PEER_URLS=http://${LOCAL_IP}:2380
ETCD_DEBUG=true
COS_CLUSTER_SIZE=${COS_CLUSTER_SIZE}
EOF

	# create /etc/csphere/csphere-controller.env
	cat << EOF > /etc/csphere/csphere-controller.env
ROLE=controller
AUTH_KEY=${COS_AUTH_KEY}
DEBUG=true
DB_URL=mongodb://127.0.0.1:27017
DB_NAME=csphere
LISTEN_ADDR=:${COS_CONTROLLER_PORT}
EOF

	# create /etc/csphere/csphere-agent.env
	cat << EOF > /etc/csphere/csphere-agent.env
ROLE=agent
CONTROLLER_ADDR=${LOCAL_IP}:${COS_CONTROLLER_PORT}
AUTH_KEY=${COS_AUTH_KEY}
SVRPOOLID=${COS_SVRPOOL_ID}
EOF

	# create /etc/prometheus.yml
	cat << EOF > /etc/prometheus.yml
global:
  scrape_interval: 30s
  evaluation_interval: 45s
rule_files:
  - "/data/alarm-rules/*.rule"
scrape_configs:
  - job_name: 'csphere-exporter'
    basic_auth:
      username: 'csphere'
      password: '${COS_AUTH_KEY}'
    scrape_interval: 30s
    scrape_timeout: 10s
    metrics_path: '/api/metrics'
    target_groups:
      - targets: ['127.0.0.1:${COS_CONTROLLER_PORT}']
EOF

	# create /etc/mime.types
	if [ ! -e /etc/mime.types ]; then
		ln -sv /usr/lib/csphere/etc/mime.types /etc/mime.types
	fi

elif [ "${COS_ROLE}" == "agent" ]; then
	# setup /etc/systemd/timesyncd.conf
	cat << EOF > /etc/systemd/timesyncd.conf
[Time]
NTP=${COS_CONTROLLER%%:*}
FallbackNTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
EOF

	# create /etc/csphere/csphere-docker-agent.env
	if [ "${COS_NETMODE}" == "bridge" ]; then
	cat << EOF > /etc/csphere/csphere-docker-agent.env
DOCKER_START_OPTS=daemon -b br0 --csphere --iptables=false --ip-forward=false --storage-driver=overlay --default-gateway=${DEFAULT_GW}
DEFAULT_NETWORK=${COS_NETMODE}
EOF
	elif [ "${COS_NETMODE}" == "ipvlan" ]; then
	cat << EOF > /etc/csphere/csphere-docker-agent.env
DOCKER_START_OPTS=daemon --csphere --iptables=false --ip-forward=false --storage-driver=overlay
DEFAULT_NETWORK=${COS_NETMODE}
EOF
	fi

	SKYDNS_IP=$( echo -e "${LOCAL_IP}" | awk 'BEGIN{FS=OFS="."}{$NF=$NF+1; print}' )
	AGENT_DNSIP=${LOCAL_IP}
	if [ "${COS_NETMODE}" == "ipvlan" ]; then
		AGENT_DNSIP=${SKYDNS_IP}
	fi

	# create /etc/csphere/csphere-skydns.env
	if [ "${COS_NETMODE}" == "bridge" ]; then
		:> /etc/csphere/csphere-skydns.env
	elif [ "${COS_NETMODE}" == "ipvlan" ]; then
		cat << EOF > /etc/csphere/csphere-skydns.env
SKYDNS_IP=${SKYDNS_IP}
EOF
	fi

	# create /etc/csphere/csphere-dockeripam.env
	cat << EOF > /etc/csphere/csphere-dockeripam.env
DEBUG=true
EOF

	# create /etc/csphere/csphere-agent.env
	cat << EOF > /etc/csphere/csphere-agent.env
ROLE=agent
CONTROLLER_ADDR=${COS_CONTROLLER}
DNS_ADDR=${AGENT_DNSIP}
AUTH_KEY=${COS_INST_CODE}
SVRPOOLID=${COS_SVRPOOL_ID}
DEFAULT_NETWORK=${COS_NETMODE}
EOF

	# create /etc/csphere/csphere-etcd2-agent.env
	cat << EOF > /etc/csphere/csphere-etcd2-agent.env
ETCD_NAME=${COS_ETCD_NAME}
ETCD_DATA_DIR=/var/lib/etcd2
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://${LOCAL_IP}:2380
ETCD_ADVERTISE_CLIENT_URLS=http://${LOCAL_IP}:2379
ETCD_LISTEN_PEER_URLS=http://${LOCAL_IP}:2380
ETCD_DEBUG=true
EOF

    # load etcd env
    . /etc/csphere/csphere-etcd2-agent.env
	# we setup env ETCD_DISCOVERY only for uninitialized etcd2,
	# so it won't conflict with etcd flag: ETCD_INITIAL_CLUSTER
	if [ ! -d "${ETCD_DATA_DIR}/proxy" ] && [ ! -d "${ETCD_DATA_DIR}/member" ] ; then
		cat << EOF >> /etc/csphere/csphere-etcd2-agent.env
ETCD_DISCOVERY=${COS_DISCOVERY_URL}
EOF
	fi

else
	echo "CRIT: cos role unknown: (${COS_ROLE})"
fi

# create ssl key/cert
fcpem="/data/tls/cert.pem"
fkpem="/data/tls/key.pem"
if [ -s "${fcpem}" -a -s "${fkpem}" ]; then
	:
else 
	mkdir -p /data/tls /root/.csphere
	openssl genrsa -out ${fkpem}
	openssl req -new -key ${fkpem} \
  		-out /data/tls/tmp.csr \
  		-subj /C=CN/ST=BeiJing/L=BeiJing/O=cSphere/CN=localhost 
	openssl x509 -in /data/tls/tmp.csr \
  		-out ${fcpem} \
  		-req -signkey ${fkpem} \
  		-days 3650
	rm -f /data/tls/tmp.csr 
	ln -sv ${fkpem} /root/.csphere/key.pem
	ln -sv ${fcpem} /root/.csphere/cert.pem
	/bin/true
fi

mkdir -p /opt/bin/
ln -sf /usr/lib/csphere/etc/bin/{axel,bc,dig,host,nc,nslookup,strace,telnet}  /opt/bin/

# make sure all of symlink prepared
# as cos update won't create new added symlink
if [ ! -e /etc/mongodb.conf ]; then
	if [ -e /usr/lib/csphere/etc/mongodb.conf ]; then
		ln -sv /usr/lib/csphere/etc/mongodb.conf  /etc/mongodb.conf
	fi
fi
if [ ! -e /etc/csphere/csphere-prepare.bash ]; then
	if [ -e /usr/lib/csphere/etc/bin/csphere-prepare.bash ]; then
		ln -sv /usr/lib/csphere/etc/bin/csphere-prepare.bash /etc/csphere/csphere-prepare.bash
	fi
fi
if [ ! -e /etc/csphere/csphere-backup.bash ]; then
	if [ -e /usr/lib/csphere/etc/bin/csphere-backup.bash ]; then
		ln -sv /usr/lib/csphere/etc/bin/csphere-backup.bash /etc/csphere/csphere-backup.bash
	fi
fi
if [ ! -e /etc/csphere/csphere-agent-after.bash ]; then
	if [ -e /usr/lib/csphere/etc/bin/csphere-agent-after.bash ]; then
		ln -sv /usr/lib/csphere/etc/bin/csphere-agent-after.bash /etc/csphere/csphere-agent-after.bash
	fi
fi
if [ ! -e /etc/csphere/etcd2-proxy2member.bash ]; then
	if [ -e /usr/lib/csphere/etc/bin/etcd2-proxy2member.bash ]; then
		ln -sv /usr/lib/csphere/etc/bin/etcd2-proxy2member.bash /etc/csphere/etcd2-proxy2member.bash
	fi
fi
if [ ! -e /etc/csphere/csphere-docker-agent-after.bash ]; then
	if [ -e /usr/lib/csphere/etc/bin/csphere-docker-agent-after.bash ]; then
		ln -sv /usr/lib/csphere/etc/bin/csphere-docker-agent-after.bash  /etc/csphere/csphere-docker-agent-after.bash
	fi
fi
if [ ! -e /etc/csphere/csphere-skydns-startup.bash ]; then
	if [ -e /usr/lib/csphere/etc/bin/csphere-skydns-startup.bash ]; then
		ln -sv /usr/lib/csphere/etc/bin/csphere-skydns-startup.bash /etc/csphere/csphere-skydns-startup.bash
	fi
fi
