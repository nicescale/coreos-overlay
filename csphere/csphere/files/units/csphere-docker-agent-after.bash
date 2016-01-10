#!/bin/bash
set -ex
. /etc/csphere/inst-opts.env
if [ "${COS_NETMODE}" != "ipvlan" ]; then
  exit 0
fi

if docker network inspect ipvlan >/dev/null 2>&1; then
  exit 0
fi

get_subnet_1st_ip() {
  for i in `seq 1 10`; do
    ipaddr=$(ip a s $COS_INETDEV|awk '/inet /{print $2}'|cut -d / -f 1)
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
  mask=$( ifconfig ${COS_INETDEV} 2>&- |\
    awk '($1=="inet"){print $4;exit}'|cut -d : -f 2 )
  if [ $? -ne 0 ]; then
    echo "WARN: convert mask to cidr error on ${mask}"
  fi
  IFS=. read -r m0 m1 m2 m3 <<< "$mask"
  IFS=. read -r i0 i1 i2 i3 <<< "$ipaddr"
  printf "%d.%d.%d.%d" "$((i0 & m0))" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))"
}

mask_bits=$(ip a s $COS_INETDEV|awk '/inet /{print $2;exit}'|cut -d / -f 2)
subnet=$(get_subnet_1st_ip)/$mask_bits
gateway=$(route -n 2>&- |\
  awk '($1=="0.0.0.0" && $4~/UG/){print $2;exit;}' )

docker network create -d ipvlan --ipam-driver=csphere --subnet=$subnet --gateway=$gateway -o master_interface=$COS_INETDEV ipvlan
