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

# load install opts file
. ${FInstOpts}

# write csphere-public.env
# br0 IPAddress, br0 Netmask, Default Route Gateway
ipaddr=$( ifconfig br0  2>&- |\
	awk '($1=="inet"){print $2;exit}' )
if [ -z "${ipaddr}" ]; then
	echo "WARN: no local ipaddr found on br0"
fi
mask1=$( ifconfig br0  2>&- |\
	awk '($1=="inet"){print $4;exit}' )
mask=$( mask2cidr ${mask1} )
if [ $? -ne 0 ]; then
	echo "WARN: convert mask to cidr error on ${mask1}"
fi
defaultgw=$(route -n 2>&- |\
	awk '($1=="0.0.0.0" && $4~/UG/){print $2;exit;}' )
if [ -z "${defaultgw}" ]; then
	echo "WARN: no local default gateway route found"
fi
cat <<EOF > ${FPublicEnv}
LOCAL_IP=${ipaddr}
NET_MASK=${mask}
DEFAULT_GW=${defaultgw}
EOF

# load public env file
# variable needed later: ${LOCAL_IP} ${NET_MASK}
. ${FPublicEnv}

# setup related files for csphere service units
if [ "${COS_ROLE}" == "controller" ]; then
	#
cat << EOF > /etc/csphere/csphere-etcd2-controller.env
ETCD_DATA_DIR=/var/lib/etcd2
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ETCD_ADVERTISE_CLIENT_URLS=http://${LOCAL_IP}:2379
ETCD_LISTEN_PEER_URLS=http://${LOCAL_IP}:2380
ETCD_DEBUG=true
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
CONTROLLER_ADDR=127.0.0.1:${COS_CONTROLLER_PORT}
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
	# create /etc/csphere/csphere-dockeripam.env
	cat << EOF > /etc/csphere/csphere-dockeripam.env
START=${COS_CONTROLLER%%:*}/${NET_MASK}
END=${COS_CONTROLLER%%:*}/${NET_MASK}
DEBUG=true
EOF

	# create /etc/csphere/csphere-agent.env
	cat << EOF > /etc/csphere/csphere-agent.env
ROLE=agent
CONTROLLER_ADDR=${COS_CONTROLLER}
DNS_ADDR=${LOCAL_IP}
AUTH_KEY=${COS_INST_CODE}
SVRPOOLID=${COS_SVRPOOL_ID}
EOF

	# create /etc/csphere/csphere-etcd2-agent.env
	cat << EOF > /etc/csphere/csphere-etcd2-agent.env
ETCD_DATA_DIR=/var/lib/etcd2
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://${LOCAL_IP}:2380
ETCD_ADVERTISE_CLIENT_URLS=http://${LOCAL_IP}:2379
ETCD_LISTEN_PEER_URLS=http://${LOCAL_IP}:2380
ETCD_DISCOVERY=${COS_DISCOVERY_URL}
ETCD_DEBUG=true
EOF
else
	echo "CRIT: cos role unknown: (${COS_ROLE})"
fi


# promisc br0
# setup br0 hw ether mac
ifconfig br0 promisc
br0inet="$(brctl show br0 2>&- | awk '($1=="br0" && NF==4){print $NF}')"
br0inetmac="$(ifconfig "${br0inet}" | awk '(/\<ether\>/){print $2}')"
if [ -n "${br0inetmac}" ]; then
	ifconfig br0 hw ether "${br0inetmac}"
else
	echo "WARN: br0 hw ether mac Null"
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
