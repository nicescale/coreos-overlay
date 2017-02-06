#!/bin/bash
set -x

# load inst-opts.env
. /etc/csphere/inst-opts.env

# load csphere-public.env
. /etc/csphere/csphere-public.env

if [ "${COS_NETMODE}"  == "bridge" ]; then
	exec /bin/skydns -verbose -addr=0.0.0.0:53 -domain="csphere.local." -machines=http://127.0.0.1:2379
	exit
fi

if [ "${COS_NETMODE}" == "qingcloud" ]; then
	exec /bin/skydns -verbose -addr=${LOCAL_IP}:53 -domain="csphere.local." -machines=http://127.0.0.1:2379
	exit
fi

if [ "${COS_NETMODE}" != "ipvlan" ]; then
	echo "env COS_NETMODE must be ipvlan or bridge or qingcloud"
	exit 1
fi

# The IPV4 address of the gateway.
GATEWAY=${DEFAULT_GW}

# The first IPV4 address of the subnet.
NETWORK=${NETWORK}

# Numerical net mask
NET_MASK=${NET_MASK}

# The IPV4 address we want to assign to skydns service.
SKYDNS_IP=${SKYDNS_IP}

# Register the IP address to etcd to avoid new containers get the address.
container_id=skydns-$SKYDNS_IP
key=/csphere/network/$NETWORK/ips/$SKYDNS_IP
etcd_record='{"ContainerID":"'$container_id'","IP":"'$SKYDNS_IP'"}'
reserved_ip=$(etcdctl get $key)
if [ $? -eq 0 ]; then
  if ! echo $reserved_ip|grep -q "$container_id"; then
    echo "$SKYDNS_IP is not available"
    exit 1
  fi
else
  etcdctl set $key "$etcd_record"
fi


NS="skydns"
IPVLSLAVE="ipvlskydns"

# create a new net namespace skydns
ip netns del ${NS} || true
ip netns add ${NS}

# create veth pair and assign fixed ip 192.168.199.1/2
ip link delete veth1 || true
ip link add veth0 type veth peer name veth1
ip link set veth0 netns ${NS}
ip addr add 192.168.199.1/24 dev veth1 
ip link set veth1 up
ip netns exec ${NS} ip addr add 192.168.199.2/24 dev veth0   
ip netns exec ${NS} ip link set veth0 up
ip netns exec ${NS} curl http://192.168.199.1:2379

# create ipvlan slaves ipvlskydns on master device 
ip link add link ${COS_INETDEV} ${IPVLSLAVE} type ipvlan mode l2

# assign slaves to the network namespaces
ip link set ${IPVLSLAVE} netns ${NS}

# Now switch to the namespace (skydns) to configure the slave devices
ip netns exec ${NS} ip link set ${IPVLSLAVE} up promisc on
ip netns exec ${NS} ip addr add ${SKYDNS_IP}/${NET_MASK} dev ${IPVLSLAVE}
ip netns exec ${NS} ip r add default via ${GATEWAY} dev ${IPVLSLAVE}
ip netns exec ${NS} ping -c 3 ${GATEWAY}
ip netns exec ${NS} /bin/skydns -verbose -addr=0.0.0.0:53 -domain="csphere.local." -machines=http://192.168.199.1:2379
