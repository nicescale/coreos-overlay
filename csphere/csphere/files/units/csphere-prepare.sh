#!/bin/bash
set -ex

# def
FInstOpts="/etc/csphere/inst-opts.env"
FPublicEnv="/etc/csphere/csphere-public.env"

# load install opts file
. ${FInstOpts}

if [ "${COS_ROLE}" == "controller" ]; then

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
DEBUG=true
SVRPOOLID=csphere-internal
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
	:
else
	echo "CRIT: cos role unknown: (${COS_ROLE})"
fi

# write csphere-public.env
# br0 IPAddress and Default Route Gateway
ipaddr=$( ifconfig br0  2>&- |\
	awk '($1=="inet"){print $2;exit}' )
if [ -z "${ipaddr}" ]; then
	echo "WARN: no local ipaddr found on br0"
fi
defaultgw=$(route -n 2>&- |\
	awk '($1=="0.0.0.0" && $4~/UG/){print $2;exit;}' )
if [ -z "${defaultgw}" ]; then
	echo "WARN: no local default gateway route found"
fi
cat <<EOF > ${FPublicEnv}
LOCAL_IP=${ipaddr}
DEFAULT_GW=${defaultgw}
EOF


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
