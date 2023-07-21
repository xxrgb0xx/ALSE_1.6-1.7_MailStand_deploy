#!/usr/bin/env bash

### Скрипт поднимает стенд Exim+Dovecot на Astra Linux SE 1.6 / 1.7 (PAM-аутентификация + TLS с самозаверенным сертификатом).
### См. Руководство администратора, глава "15. ЗАЩИЩЕННЫЙ КОМПЛЕКС ПРОГРАММ ЭЛЕКТРОННОЙ ПОЧТЫ".

MAIL_DOMAIN='astra.local'
MAIL_SERVER_FQDN='mail.astra.local'
PKGS='exim4-daemon-heavy dovecot-imapd bsd-mailx dnsutils net-tools telnet'

function set_hostname {

	echo -e '\033[94m\n******************************\n1/6 Configuring hostname...\n******************************\n\033[39m' &&\

    cat <<-EOF | sudo tee /etc/hosts > /dev/null 2>&1
	127.0.0.1       localhost
	127.0.1.1       $MAIL_SERVER_FQDN

	# The following lines are desirable for IPv6 capable hosts
	::1     localhost ip6-localhost ip6-loopback
	ff02::1 ip6-allnodes
	ff02::2 ip6-allrouters
	EOF

	sudo hostnamectl set-hostname $MAIL_SERVER_FQDN &&\
	echo -e '\033[92m\n******************************\n:) Hostname configured without errors.\n******************************\n\033[39m'

}

function install_pkgs {

	echo -e '\033[94m\n******************************\n2/6 Installing packages...\n******************************\n\033[39m' &&\
	### Check GUI
	if dpkg-query -W fly-dm 2>/dev/null; then
		sudo apt-get install -y $PKGS thunderbird
	else
		sudo apt-get install -y $PKGS
	fi &&\
	echo -e '\033[92m\n******************************\n:) Packages installed without errors.\n******************************\n\033[39m'

}

function backup_configs {

	echo -e '\033[94m******************************\n3/6 Creating configs backup...\n******************************\n\033[39m' &&\
	sudo tar -C /etc/ -czf /etc/dovecot_$(date +"%Y-%m-%d")_BAK.tar.gz dovecot/ &&\
	sudo tar -C /etc/ -czf /etc/exim4_$(date +"%Y-%m-%d")_BAK.tar.gz exim4/ &&\
	echo -e '\033[92m******************************\n:) Configs backup created without errors.\n******************************\n\033[39m'

}

function edit_configs {

	echo -e '\033[94m******************************\n4/6 Editing configs...\n******************************\n\033[39m' &&\
	sudo sed -i 's/auth_mechanisms = plain/auth_mechanisms = plain\ndisable_plaintext_auth = no/g' /etc/dovecot/conf.d/10-auth.conf &&\
	sudo sed -i 's/service auth {/service auth {\n  unix_listener auth-client {\n    mode = 0600\n    user = Debian-exim\n  }/g' /etc/dovecot/conf.d/10-master.conf &&\

	cat <<-EOF | sudo tee /etc/exim4/update-exim4.conf.conf > /dev/null
	dc_eximconfig_configtype='internet'
	dc_other_hostnames='$MAIL_DOMAIN'
	dc_local_interfaces='0.0.0.0'
	dc_readhost=''
	dc_relay_domains=''
	dc_minimaldns='false'
	dc_relay_nets=''
	dc_smarthost=''
	CFILEMODE='644'
	dc_use_split_config='true'
	dc_hide_mailname=''
	dc_mailname_in_oh='true'
	dc_localdelivery='maildir_home'
	EOF

	sudo touch /etc/exim4/conf.d/auth/05_dovecot_login &&\

	cat <<-'EOF' | sudo tee /etc/exim4/conf.d/auth/05_dovecot_login > /dev/null
	dovecot_plain:
	    driver = dovecot
	    public_name = plain
	    server_socket = /var/run/dovecot/auth-client
	    server_set_id = \$auth1
	EOF

	sudo sed -i 's/acl_check_rcpt:/acl_check_rcpt:\n  deny\n    message = "Auth required"\n    hosts = *:+relay_from_hosts\n    !authenticated = *\n/g' /etc/exim4/conf.d/acl/30_exim4-config_check_rcpt &&\
	echo -e '\033[92m\n******************************\n:) Configs edited without errors.\n******************************\n\033[39m'

}

function tls_config {

	sudo usermod -a -G ssl-cert Debian-exim  &&\
	sudo sed -i 's/MAIN_TLS_CERTIFICATE = CONFDIR\/exim.crt/###MAIN_TLS_CERTIFICATE = CONFDIR\/exim.crt/g' /etc/exim4/conf.d/main/03_exim4-config_tlsoptions &&\
	sudo sed -i 's/MAIN_TLS_PRIVATEKEY = CONFDIR\/exim.key/###MAIN_TLS_PRIVATEKEY = CONFDIR\/exim.key/g' /etc/exim4/conf.d/main/03_exim4-config_tlsoptions &&\
	sudo sed -i '1s/^/tls_on_connect_ports = 465\ndaemon_smtp_ports = 25 : 465\nMAIN_TLS_ENABLE = true\nMAIN_TLS_CERTIFICATE = \/etc\/ssl\/certs\/ssl-cert-snakeoil.pem\nMAIN_TLS_PRIVATEKEY = \/etc\/ssl\/private\/ssl-cert-snakeoil.key\n/' /etc/exim4/conf.d/main/03_exim4-config_tlsoptions &&\
	echo -e '\033[92m\n******************************\n:) TLS configured without errors.\n******************************\n\033[39m'

}

function start_services {

	echo -e '\033[94m******************************\n5/6 Starting services...\n******************************\n\033[39m'  &&\
	### Fix permissions
	sudo chown -R Debian-exim:Debian-exim /var/spool/exim4/ &&\
	sudo update-exim4.conf &&\
	sudo systemctl restart dovecot exim4 &&\
	sudo systemctl enable exim4 &&\
	echo -e '\033[92m\n******************************\n6/6 :) Services started without errors.\n******************************\n\033[39m'

}


if ! set_hostname && echo -e '\033[91m\n******************************\n:( Errors occurred while configuring hostname!\nExiting...\n******************************\n\033[39m'; then exit
elif ! install_pkgs && echo -e '\033[91m\n******************************\n:( Errors occurred while installing packages!\nExiting...\n******************************\n\033[39m'; then exit
elif ! backup_configs && echo -e '\033[91m\n******************************\n:( Errors occurred while creating backup configs!\nExiting...\n******************************\n\033[39m'; then exit
elif ! edit_configs && echo -e '\033[91m\n******************************\n:( Errors occurred while editing configs!\nExiting...\n******************************\n\033[39m'; then exit
elif ! tls_config && echo -e '\033[91m\n******************************\n:( Errors occurred while configuring TLS!\nExiting...\n******************************\n\033[39m'; then exit
elif ! start_services && echo -e '\033[91m\n******************************\n:( Errors occurred while starting services!\nExiting...\n******************************\n\033[39m'; then exit
else
echo -e '\033[92m******************************\n:) All jobs competed!\n******************************\n\033[39m'
fi
