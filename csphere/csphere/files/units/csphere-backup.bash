#!/bin/bash
set -ex

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin

#
# ENV:
# BACKUP_DIR:        backup save path
# BACKUP_RESERV_DAY: backup reserved day
# DISK_RESERV_PCT:   reserved disk percent
# DISK_RESERV_SIZE:  reserved disk space (by MB)

BACKUP_DIR=${BACKUP_DIR:-/backup}
if [ ! -d "${BACKUP_DIR}" ]; then
	mkdir -pv "${BACKUP_DIR}"
fi

BACKUP_RESERV_DAY=${BACKUP_RESERV_DAY:-7}
DISK_RESERV_PCT=${DISK_RESERV_PCT:-10}
DISK_RESERV_SIZE=${DISK_RESERV_SIZE:-5120}

# pre check
avail_pct=$(df --output=pcent ${BACKUP_DIR}|tail -n1|tr -d '%')
avail_pct=$((100-${avail_pct}))
avail_size=$(df --output=avail -m ${BACKUP_DIR}|tail -n1)
if [ $avail_pct -le ${DISK_RESERV_PCT} ]; then
	echo "disk avaliable percent ${avail_pct} <= ${DISK_RESERV_PCT}, abort."
	exit 1
fi
if [ $avail_size -le ${DISK_RESERV_SIZE} ]; then
	echo "disk avaliable space ${avail_size} <= ${DISK_RESERV_SIZE}, abort."
	exit 1
fi

# backup
prefix="csphere-mongo-dump"     # search by, prevent from misdelete
suffix=$(date +%Y-%m-%d_%H-%M-%S)
name="${BACKUP_DIR}/${prefix}-${suffix}.tgz"

cd $BACKUP_DIR
mongodump -v --db csphere --excludeCollection=containers --excludeCollection=images
tar -c --remove-files -zf $name dump

# longterm reserve
md=$(date +%d)
if [ "${md}" == "01" ] || [ "${md}" == "15" ]; then
	dh=$(date +%H)
	if [ "${dh}" == "01" ] || [ "${dh}" == "23" ];  then
		mkdir -pv "${BACKUP_DIR}"/reserve
		cp -avf ${name} "${BACKUP_DIR}"/reserve
	fi
fi

# cleanup overdue
find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 \
	-mtime +${BACKUP_RESERV_DAY} -regextype posix-extended -regex \
	"${BACKUP_DIR}/${prefix}.*\.tgz" -exec rm -fv {} \;
