#!/bin/bash
set -e

# def
FInstEnv="/etc/csphere/inst-opts.env"
FEtcd2AgentEnv="/etc/csphere/csphere-etcd2-agent.env"

# root required
if [ "$(id -u)" != "0" ]; then
	echo "root privilege required."
	exit 1
fi

# load inst env
. ${FInstEnv}
if [ "${COS_ROLE}" != "agent" ]; then
	echo "this script only runs under cos role agent, abort."
	exit 1
fi

# confirm local etcd is a proxy
. ${FEtcd2AgentEnv}
if [ -d "${ETCD_DATA_DIR}/member" ]; then
	echo "local etcd2 have been initilized as cluster member already, skip."
	exit 1
elif [ -d "${ETCD_DATA_DIR}/proxy" ]; then
	:
else
	echo "local etcd2 not initilized before? abort"
	exit 1
fi

# confirm etcd cluster is healthy
if ! systemctl is-active csphere-etcd2-agent >/dev/null 2>&1; then
	echo "local etcd service not active, abort."
	exit 1
fi
if ! etcdctl cluster-health >/dev/null 2>&1; then
	echo "etcd cluster is not healthy now. abort."
	exit 1
fi
if ! etcdctl ls / >/dev/null 2>&1; then
	echo "local etcd is not working well. abort."
	exit 1
fi

# turn etcd proxy as etcd member
memName=$(hostname -s)
output=$( etcdctl member add ${memName} ${ETCD_INITIAL_ADVERTISE_PEER_URLS} 2>&1 )
if [ $? -ne 0 ]; then
	echo -e "add etcd member error:\n${output}"
	exit 1
fi

cfg=$(echo -e "${output}" | \
		awk '(/^ETCD_INITIAL_CLUSTER=/){gsub("ETCD_INITIAL_CLUSTER=","",$0);print;exit}')
if [ -z "${cfg}" ]; then
	echo -e "not found ETCD_INITIAL_CLUSTER settings, failed."
	exit 1
fi

cat >> ${FEtcd2AgentEnv} <<EOF
ETCD_NAME=${memName}
ETCD_INITIAL_CLUSTER=${cfg}
ETCD_INITIAL_CLUSTER_STATE="existing"
EOF

sed -i '/ETCD_DISCOVERY/d' /etc/csphere/csphere-etcd2-agent.env
systemctl  stop csphere-etcd2-agent
rm -rf /var/lib/etcd2/proxy
systemctl  start csphere-etcd2-agent

# TODO
# check nower etcd cluster size
