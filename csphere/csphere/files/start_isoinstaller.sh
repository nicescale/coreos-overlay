read -r CMDLINE </proc/cmdline;
for i in $CMDLINE; do
    case "$i" in
         coreos.isoinstall*) 
		clear
		sudo /bin/bash /usr/share/oem/iso_install.sh
		;;
    esac
done
