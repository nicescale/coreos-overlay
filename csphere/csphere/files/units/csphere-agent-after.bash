#!/bin/bash
set -ex

# def
FInstOpts="/etc/csphere/inst-opts.env"
FAgentUuid="/etc/.csphere-uuid"
FEtcd2AgentEnv="/etc/csphere/csphere-etcd2-agent.env"

# load install opts file
. ${FInstOpts}

Uuid=
if [ -f "${FAgentUuid}" -a -s "${FAgentUuid}" ]; then
	Uuid=$(cat "${FAgentUuid}" 2>&-)
	if [ -z "${Uuid}" ]; then
		echo "csphere agent uuid empty, abort."
		exit 1
	fi
else
	echo "${FAgentUuid} missing, agent not started yet? abort."
	exit 1
fi

EtcdCliUrls=
if [ -f "${FEtcd2AgentEnv}" -a -s "${FEtcd2AgentEnv}" ]; then
	EtcdCliUrls=$(awk -F= '/ETCD_ADVERTISE_CLIENT_URLS/{print $2;exit}' ${FEtcd2AgentEnv} 2>&-)
	if [ -z "${EtcdCliUrls}" ]; then
		echo "ETCD_ADVERTISE_CLIENT_URLS empty, abort."
		exit 1
	fi
else
	echo "${FEtcd2AgentEnv} missing, abort."
	exit 1
fi

EtcdDiscUrl="${COS_DISCOVERY_URL%%/v2/keys*}"
EtcdDiscUrl="${EtcdDiscUrl}/v2/keys/csphere/agents/${Uuid}"
echo -e "set EtcdDiscUrl=${EtcdDiscUrl}"

/usr/bin/curl -v -XPUT ${EtcdDiscUrl} -d value="${EtcdCliUrls}"
