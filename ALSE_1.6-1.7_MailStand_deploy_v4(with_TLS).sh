#!/usr/bin/env bash

MAIL_DOMAIN='astra.local'
MAIL_SERVER_FQDN='mail.astra.local'
PKGS='exim4-daemon-heavy dovecot-imapd bsd-mailx dnsutils net-tools telnet'

BLUE_COLOR='\033[94m'
GREEN_COLOR='\033[92m'
RED_COLOR='\033[91m'
DEFAULT_COLOR='\033[39m'
SEPARATOR='******************************'

function print_blue {

	echo -e "$BLUE_COLOR$SEPARATOR\n$1\n$SEPARATOR\n$DEFAULT_COLOR"

}

function print_green {

	echo -e "$GREEN_COLOR$SEPARATOR\n$1\n$SEPARATOR\n$DEFAULT_COLOR"

}


function print_red {

	echo -e "$RED_COLOR$SEPARATOR\n$1\nExiting...\n$SEPARATOR\n$DEFAULT_COLOR"

}

function set_hostname {

	print_blue '1/5 Configuring hostname...' &&\

    cat <<-EOF | sudo tee /etc/hosts > /dev/null 2>&1
	127.0.0.1       localhost
	127.0.1.1       $MAIL_SERVER_FQDN

	# The following lines are desirable for IPv6 capable hosts
	::1     localhost ip6-localhost ip6-loopback
	ff02::1 ip6-allnodes
	ff02::2 ip6-allrouters
	EOF

	sudo hostnamectl set-hostname $MAIL_SERVER_FQDN &&\
	print_green ':) Hostname configured without errors.'

}

function install_pkgs {

	print_blue '2/5 Installing packages...' &&\
	### Check GUI
	if dpkg-query -W fly-dm 2>/dev/null; then
		sudo apt-get install -y $PKGS thunderbird
	else
		sudo apt-get install -y $PKGS
	fi &&\
	print_green ':) Packages installed without errors.'

}

function backup_configs {

	print_blue '3/5 Creating configs backup...' &&\
	sudo tar -C /etc/ -czf /etc/dovecot_$(date +"%Y-%m-%d")_BAK.tar.gz dovecot/ &&\
	sudo tar -C /etc/ -czf /etc/exim4_$(date +"%Y-%m-%d")_BAK.tar.gz exim4/ &&\
	print_green ':) Configs backup created without errors.'

}

function edit_configs {

	print_blue '4/5 Editing configs...' &&\
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
	print_green ':) Configs edited without errors.'

}

function tls_config {

	sudo usermod -a -G ssl-cert Debian-exim  &&\
	sudo sed -i 's/MAIN_TLS_CERTIFICATE = CONFDIR\/exim.crt/###MAIN_TLS_CERTIFICATE = CONFDIR\/exim.crt/g' /etc/exim4/conf.d/main/03_exim4-config_tlsoptions &&\
	sudo sed -i 's/MAIN_TLS_PRIVATEKEY = CONFDIR\/exim.key/###MAIN_TLS_PRIVATEKEY = CONFDIR\/exim.key/g' /etc/exim4/conf.d/main/03_exim4-config_tlsoptions &&\
	sudo sed -i '1s/^/tls_on_connect_ports = 465\ndaemon_smtp_ports = 25 : 465\nMAIN_TLS_ENABLE = true\nMAIN_TLS_CERTIFICATE = \/etc\/ssl\/certs\/ssl-cert-snakeoil.pem\nMAIN_TLS_PRIVATEKEY = \/etc\/ssl\/private\/ssl-cert-snakeoil.key\n/' /etc/exim4/conf.d/main/03_exim4-config_tlsoptions &&\
	print_green ':) TLS configured without errors.'

}

function start_services {

	print_blue '5/5 Starting services...'  &&\
	### Fix permissions
	sudo chown -R Debian-exim:Debian-exim /var/spool/exim4/ &&\
	sudo update-exim4.conf &&\
	sudo systemctl restart dovecot exim4 &&\
	sudo systemctl enable exim4 &&\
	print_green ':) Services started without errors.'

}


if ! set_hostname && print_red ':( Errors occurred while configuring hostname!'; then exit
elif ! install_pkgs && print_red ':( Errors occurred while installing packages!'; then exit
elif ! backup_configs && print_red ':( Errors occurred while creating backup configs!'; then exit
elif ! edit_configs && print_red ':( Errors occurred while editing configs!'; then exit
elif ! tls_config && print_red ':( Errors occurred while configuring TLS!'; then exit
elif ! start_services && print_red ':( Errors occurred while starting services!'; then exit
else
	print_green ':) All jobs competed!'
fi
