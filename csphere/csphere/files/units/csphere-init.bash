#!/bin/bash

# def
AgentComps=(
	csphere-prepare.service
	csphere-etcd2-agent.service
	csphere-skydns.service
	csphere-dockeripam.service
	csphere-docker-agent.service
	csphere-agent.service
)

ControllerComps=(
	csphere-prepare.service
	csphere-mongodb.service
	csphere-prometheus.service
	csphere-etcd2-controller.service
	csphere-docker-controller.service
	csphere-controller.service
	csphere-agent.service
)

Role=
ControllerAddr=
ControllerHost=
ControllerPort=
InstCode=
SvrPoolID=
ClusterSize=
AuthKey=
DisvUrl=

function show_usage() {
cat << HELP
Options:
	-h|--help         show help stuff what you are reading
	-r|--role         setup role you want to initlized, allow: agent / controller
	-c|--controller   setup controller address, only for agent, format: ip:port
	-i|--instcode     setup install code, only for agent
	-s|--clustersize  setup initial cluster size, only for controller
	-p|--svrport      setup controller http service port, only for controller

Example:
	initialized as controller:
	${BASH_SOURCE[0]} --role controller --svrport 80 --clustersize 1

	initialized as agent:
	${BASH_SOURCE[0]} --role agent --controller 10.3.1.2:80 --instcode 7823

HELP
	exit 0
}

# parse flags
while :; do
	case $1 in
		-h|h|--help|help|-\?)
			show_usage
			;;
		-r|--role)
			if [ -n $2 ]; then
				Role=$2
				shift 2
				continue
			else
				echo 'Error: --role require a non-empty option argument.' >&2
				exit 1
			fi
			;;
		--role=?*)
			Role=${1#*=}
			;;
		-c|--controller)
			if [ -n $2 ]; then
				ControllerAddr=$2
				shift 2
				continue
			else
				echo 'Error: --controller require a non-empty option argument.' >&2
				exit 1
			fi
			;;
		--controller=?*)
			ControllerAddr=${1#*=}
			;;
		-i|--instcode)
			if [ -n $2 ]; then
				InstCode=$2
				shift 2
				continue
			else
				echo 'Error: --instcode require a non-empty option argument.' >&2
				exit 1
			fi
			;;
		--instcode=*?)
			InstCode=${1#*=}
			;;
		-s|--clustersize)
			if [ -n $2 ]; then
				ClusterSize=$2
				shift 2
				continue
			else
				echo 'Error: --clustersize require a non-empty option argument.' >&2
				exit 1
			fi
			;;
		--clustersize=?*)
			ClusterSize=${1#*=}
			;;
		-p|--svrport)
			if [ -n $2 ]; then
				ControllerPort=$2
				shift 2
				continue
			else
				echo 'Error: --svrport require a non-empty option arguments.' >&2
				exit 1
			fi
			;;
		--svrport=?*)
			ControllerPort=${1#*=}
			;;
		--)
			shift
			break
			;;
		*)
			break
			;;
	esac
done

# validate flags
if [ "${Role}" != "agent" -a "${Role}" != "controller" ]; then
	echo "--role ${Role} invalid, must be agent or controller"
	exit 1
fi
if [ "${Role}" == "agent" ]; then
	ControllerAddr=$( echo -e "${ControllerAddr}" | sed -e 's#^[ \t]*https*://##g' )
	if ! ( echo -e "${ControllerAddr}" | grep -E -q "^.+:[1-9]+[0-9]*$" ); then
		echo "--controller ${ControllerAddr} should be like: ip:port"
		exit 1
	fi
	if ! ( echo -e "${InstCode}" | grep -E -q "^[0-9]{4,4}$" ); then   
		echo "--instcode ${InstCode} should be four numbers"
		exit 1
	fi
	ControllerHost=${ControllerAddr%%:*}
	ControllerPort=${ControllerAddr##*:}
	SvrPoolID=
	AuthKey=
	DisvUrl="http://${ControllerHost}:2379/v2/keys/discovery/hellocsphere"

elif [ "${Role}" == "controller" ]; then
	ClusterSize="${ClusterSize//[ \t]}"
	if [ -n "${ClusterSize//[0-9]}" ]; then
		echo "--clustersize ${ClusterSize} must be odd number"
		exit 1
	fi
	if (( ${ClusterSize} % 2 != 1 )); then
		echo "--clustersize ${ClusterSize} must be odd number"
		exit 1
	fi
	if [ -n "${ControllerPort//[0-9]}" ]; then
		echo "--svrport ${ControllerPort} must be number"
		exit 1
	fi

	ControllerHost="127.0.0.1"
	ControllerAddr="127.0.0.1:${ControllerPort}"
	SvrPoolID="csphere-internal"
	AuthKey=$(head -n 100 /dev/urandom|tr -dc 'a-zA-Z0-9'|head -c 32)
	DisvUrl=
fi


#
# main begin
#

# network bridge configs
cat > /etc/systemd/network/br0-static.network << EOF
[Match]
Name=br0

[Network]
DHCP=yes
EOF

cat > /etc/systemd/network/br0-slave-eth0.network << EOF
[Match]
Name=eth0

[Network]
Bridge=br0
EOF

# sync macaddr from eth0 to br0
br0inetmac="$(ifconfig eth0 | awk '(/\<ether\>/){print $2}')"
if [ -z "${br0inetmac}" ]; then
	echo "mac address not found on eth0"
	exit 1
fi
ifconfig br0 hw ether ${br0inetmac}
systemctl restart systemd-networkd

# make sure ip configs all right
...

# emulate cos install options
cat > /etc/csphere/inst-opts.env << EOF
COS_ROLE=${Role}
COS_CONTROLLER=${ControllerAddr}
COS_CONTROLLER_PORT=${ControllerPort}
COS_AUTH_KEY=${AuthKey}
COS_INST_CODE=${InstCode}
COS_DISCOVERY_URL=${DisvUrl}
COS_SVRPOOL_ID=${SvrPoolID}
COS_CLUSTER_SIZE=${ClusterSize}
EOF

# startup components 
if [ "${Role}" == "agent" ]; then
	systemctl enable ${AgentComps[*]}
	systemctl start ${AgentComps[*]}
elif [ "${Role}" == "controller" ]; then
	systemctl enable ${ControllerComps[*]}
	systemctl start ${ControllerComps[*]}
fi
