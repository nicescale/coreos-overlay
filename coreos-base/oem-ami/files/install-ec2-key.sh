#!/bin/bash

USER_DIR="/home/core/user"

if [ ! -d ${USER_DIR}/.ssh ] ; then
	mkdir -p ${USER_DIR}/.ssh
	chmod 700 ${USER_DIR}/.ssh
fi
# Fetch public key using HTTP
curl -s http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key > /tmp/my-key
if [ $? -eq 0 ] ; then
	cat /tmp/my-key >> ${USER_DIR}/.ssh/authorized_keys
	chmod 700 ${USER_DIR}/.ssh/authorized_keys
	rm /tmp/my-key
fi
chown -R core: $USER_DIR/.ssh