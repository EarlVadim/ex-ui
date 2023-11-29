#!/bin/bash
##############  INSTALL X_PRO  ####################

[[ $EUID -ne 0 ]] && echo "Run as root!" && exit 1
if [[ -f /etc/redhat-release ]]; then Pak="yum"
elif grep -Eqi "debian" /etc/issue; then Pak="apt"
elif grep -Eqi "ubuntu" /etc/issue; then Pak="apt"
elif grep -Eqi "centos|red hat|redhat" /etc/issue; then Pak="yum"
elif grep -Eqi "debian|raspbian" /proc/version; then Pak="apt"
elif grep -Eqi "ubuntu" /proc/version; then Pak="apt"
elif grep -Eqi "centos|red hat|redhat" /proc/version; then Pak="yum"
fi
################################Msg#################################
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Blue="\033[36m"
Font="\033[0m"
OK="${Green}[OK]${Font}"
ERROR="${Red}[ERROR]${Font}"
function msg_inf() {  echo -e "${Blue} $1 ${Font}"; }
function msg_ok() { echo -e "${OK} ${Blue} $1 ${Font}"; }
function msg_err() { echo -e "${ERROR} ${Yellow} $1 ${Font}"; }
echo
echo " ####### ##     ##         ##     ## ####  ";
echo " ##       ##   ##          ##     ##  ##   ";
echo " ##        ## ##           ##     ##  ##   ";
echo " #######    ###    ####### ##     ##  ##   ";
echo " ##        ## ##           ##     ##  ##   ";
echo " ##       ##   ##          ##     ##  ##   ";
echo " ####### ##     ##          #######  ####  ";
echo
#####################Random String and Port ####################################
RNDSTR=$(tr -dc A-Za-z0-9 </dev/urandom | head -c "$(shuf -i 6-12 -n 1)")
while true; do 
    PORT=$(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 ))
    status="$(nc -z 127.0.0.1 $PORT < /dev/null &>/dev/null; echo $?)"
    if [ "${status}" != "0" ]; then
        break
    fi
done
################################Get arguments########################
XUIDB="/etc/x-ui/x-ui.db"
domain=""
UNINSTALL="x"
INSTALL="n"
UPGRADE="n"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -install) INSTALL="yes"; shift 2;;
	-upgrade) UPGRADE="yes"; INSTALL="yes"; shift 2;;
    -subdomain) domain="$2"; shift 2;;
    -uninstall) UNINSTALL="$2"; shift 2;;
    *) shift 1;;
  esac
done
##############################Uninstall##############################
UNINSTALL_XUI(){
	printf 'y\n' | x-ui uninstall
	rm -rf "/etc/x-ui/" "/usr/local/x-ui/" "/usr/bin/x-ui/"
	$Pak -y remove nginx nginx-common nginx-core nginx-full python3-certbot-nginx haproxy
	$Pak -y purge nginx nginx-common nginx-core nginx-full python3-certbot-nginx haproxy
	$Pak -y autoremove
	$Pak -y autoclean
	rm -rf "/var/www/html/" "/etc/nginx/" "/usr/share/nginx/" 
}
if [[ ${UNINSTALL} == *"y"* ]]; then
	UNINSTALL_XUI	
	clear && msg_ok "Completely Uninstalled!" && exit 1
fi
##############################Domain Validations######################
while true; do
	domain=$(echo "$domain" 2>&1 | tr -d '[:space:]' )
	SubDomain=$(echo "$domain" 2>&1 | sed 's/^[^ ]* \|\..*//g')
	MainDomain=$(echo "$domain" 2>&1 | sed 's/.*\.\([^.]*\..*\)$/\1/')
	if [[ -n "$domain" ]] &&  [[ "${SubDomain}.${MainDomain}" == "${domain}" ]] ; then
		if [[ -n $(host "$domain" 2>/dev/null | grep -v NXDOMAIN) ]]; then
			break
		fi
	fi
	echo -en "${Blue}Enter available subdomain${Font} (${Yellow}sub.domain.tld${Font}): " && read domain 
done
###############################Install Packages#############################
if [[ ${INSTALL} == *"y"* ]]; then
	$Pak -y update
	$Pak -y install nginx-full certbot python3-certbot-nginx sqlite3 dnsutils haproxy
	
	systemctl enable --now haproxy
	systemctl enable --now nginx
fi
#########################Install nginx Config###############################
systemctl stop nginx 
systemctl stop haproxy
fuser -k 80/tcp 80/udp 443/tcp 443/udp 2>/dev/null
if [[ ! -f "/etc/letsencrypt/live/${SubDomain}.${MainDomain}/privkey.pem" ]]; then
	certbot certonly --standalone --non-interactive --force-renewal --agree-tos --register-unsafely-without-email --cert-name "$SubDomain.$MainDomain" -d "$domain"
else
	msg_ok "$SubDomain.$MainDomain SSL Certificate is exist!"
fi
sleep 3
if [[ ! -f "/etc/letsencrypt/live/${SubDomain}.${MainDomain}/privkey.pem" ]]; then
	msg_err "$SubDomai}.$MainDomain SSL certificate could not be generated, Maybe the domain or IP domain is invalid!" && exit 1
fi

cat > "/etc/nginx/sites-available/$MainDomain" << EOF
server {
	server_name ~^((?<subdomain>.*)\.)?(?<domain>[^.]+)\.(?<tld>[^.]+)\$;
	listen 11443 ssl http2;
	listen [::]:11443 ssl http2 ipv6only=on;
	http2_push_preload on;
	index index.html index.htm index.php index.nginx-debian.html;
	root /var/www/html/;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_certificate /etc/letsencrypt/live/$SubDomain.$MainDomain/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/$SubDomain.$MainDomain/privkey.pem;
	if (\$host !~* ^(.+\.)?$MainDomain\$ ) { return 444; }
	if (\$request_method !~ ^(GET|HEAD|POST|PUT|DELETE)\$ ) { return 444; }
	add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
	location ~* (?:\.(?:db|json|pub|pem|config|conf|inf|ini|inc|bak|sql|log|py|sh|passwd|pwd|cgi|lua)|~)\$ { deny all; }
	location ~* (\`|"|'|0x00|%0A|%0D|%27|%22|%3C|%3E|%00|%60|%24&x|%0|%A|%B|%C|%D|%E|%F|127\.0) { deny all; }
	location ~* "(&pws=0|_vti_|\(null\)|\{\$itemURL\}|echo(.*)kae|etc/passwd|eval\(|self/environ)" { deny all; }
	location ~ "(\\|\.\.\.|\.\./|~|\`|<|>|\|)" { deny all; }
	location ~* [a-zA-Z0-9_]=(\.\.//?)+ { deny all; }
	location ~* [a-zA-Z0-9_]=/([a-z0-9_.]//?)+ { deny all; }
	location /$RNDSTR/ {
		proxy_redirect off;
		proxy_set_header Host \$host;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_pass http://127.0.0.1:$PORT;
   }
	location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)\$ {
		client_max_body_size 0;
		client_body_timeout 1d;
		grpc_read_timeout 1d;
		grpc_socket_keepalive on;
		proxy_read_timeout 1d;
		proxy_http_version 1.1;
		proxy_buffering off;
		proxy_request_buffering off;
		proxy_socket_keepalive on;
		proxy_set_header Upgrade \$http_upgrade;
		proxy_set_header Connection "upgrade";
		proxy_set_header Host \$host;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		if (\$content_type = "application/grpc") {
			grpc_pass grpc://127.0.0.1:\$fwdport;
			break;
		}
		if (\$http_upgrade = "websocket") {
			proxy_pass http://127.0.0.1:\$fwdport/\$fwdport/\$fwdpath;
			break;
		}	
	}
	location / { try_files \$uri \$uri/ =404; }
}
EOF

cat > "/etc/haproxy/haproxy.cfg" << EOF
global
	log /dev/log	local0
	log /dev/log	local1 notice
	chroot /var/lib/haproxy
	stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
	stats timeout 30s
	user haproxy
	group haproxy
	daemon
	ca-base /etc/ssl/certs
	crt-base /etc/ssl/private
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
	log	global
	mode	http
	option	httplog
	option	dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
	errorfile 400 /etc/haproxy/errors/400.http
	errorfile 403 /etc/haproxy/errors/403.http
	errorfile 408 /etc/haproxy/errors/408.http
	errorfile 500 /etc/haproxy/errors/500.http
	errorfile 502 /etc/haproxy/errors/502.http
	errorfile 503 /etc/haproxy/errors/503.http
	errorfile 504 /etc/haproxy/errors/504.http

listen front
 mode tcp
 bind ipv4@*:443

 tcp-request inspect-delay 5s
 tcp-request content accept if { req.ssl_hello_type 1 }

 use_backend CDN if { req.ssl_sni -m end $SubDomain.$MainDomain }
 use_backend REALITY_TROJAN if { req.ssl_sni -m end trojan.$MainDomain }
 use_backend REALITY_VLESS if { req.ssl_sni -m end vless.$MainDomain }


backend CDN
 mode tcp
 server srv1 127.0.0.1:11443
 
backend REALITY_VLESS
 mode tcp
 server srv1 127.0.0.1:22443 
 
backend REALITY_TROJAN
 mode tcp
 server srv1 127.0.0.1:23443
EOF
###################################Enable Site###############################
if [[ -f "/etc/nginx/sites-available/$MainDomain" ]]; then
	unlink /etc/nginx/sites-enabled/default 2>/dev/null
	ln -s "/etc/nginx/sites-available/$MainDomain" /etc/nginx/sites-enabled/
	systemctl start nginx 
else
	msg_err "$MainDomain nginx config not exist!" && exit 1
fi
systemctl start haproxy
###################################Update Db##################################
UPDATE_XUIDB(){
if [[ -f $XUIDB ]]; then
	sqlite3 $XUIDB <<EOF
	DELETE FROM "settings" WHERE "key"="webPort";
	DELETE FROM "settings" WHERE "key"="webCertFile";
	DELETE FROM "settings" WHERE "key"="webKeyFile";
	DELETE FROM "settings" WHERE "key"="webBasePath";
	INSERT INTO "settings" ("key", "value") VALUES ("webPort",  "${PORT}");
	INSERT INTO "settings" ("key", "value") VALUES ("webCertFile",  "");
	INSERT INTO "settings" ("key", "value") VALUES ("webKeyFile", "");
	INSERT INTO "settings" ("key", "value") VALUES ("webBasePath", "/${RNDSTR}/");
EOF
else
	msg_err "x-ui.db file not exist! Maybe x-ui isn't installed." && exit 1;
fi
}
###################################Install Panel#########################

INSTALL_NEW_PANEL(){
    printf 'n\n' | bash <(wget -qO- https://raw.githubusercontent.com/EarlVadim/ex-ui/main/add-x-ui.sh)
	UPDATE_XUIDB
	if ! systemctl is-enabled --quiet x-ui; then
		systemctl daemon-reload
		systemctl enable x-ui.service
	fi
	x-ui restart
}

if systemctl is-active --quiet x-ui; then
    if [[ ${UPGRADE} == *"y"* ]]; then
	   x-ui stop
	   INSTALL_NEW_PANEL
	else
	   UPDATE_XUIDB
	   x-ui restart
	fi
else
    INSTALL_NEW_PANEL
	
fi
######################cronjob for ssl and reload service##################
crontab -l | grep -v "certbot\|x-ui" | crontab -
(crontab -l 2>/dev/null; echo '0 1 * * * x-ui restart && nginx -s reload') | crontab -
(crontab -l 2>/dev/null; echo '0 0 1 * * certbot renew --nginx --force-renewal --non-interactive --post-hook "nginx -s reload"') | crontab -
##################################Show Details############################
XUIPORT=$(sqlite3 -list $XUIDB 'SELECT "value" FROM settings WHERE "key"="webPort" LIMIT 1;' 2>&1)
if systemctl is-active --quiet x-ui && [[ $XUIPORT -eq $PORT ]]; then clear
	msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
	printf '0\n' | x-ui | grep --color=never -i ':'
	msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
	nginx -T | grep -i 'ssl_certificate\|ssl_certificate_key'
	msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
	certbot certificates | grep -i 'Path:\|Domains:\|Expiry Date:'
	msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
	msg_inf "\nTo use the VLESS+reality, create the vless.${MainDomain} in DNS-only mode        "
	msg_inf "To use the TROJAN+reality, create the trojan.${MainDomain} in DNS-only mode        "
	msg_inf "\nX-UI Admin Panel: https://${domain}/${RNDSTR}/\n"
	msg_inf "  Login  | Password"
	sqlite3 -batch $XUIDB 'SELECT "username","password" FROM users;'
	msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
else
	nginx -t && printf '0\n' | x-ui | grep --color=never -i ':'
	msg_err "sqlite and x-ui to be checked, try on a new clean linux! "
fi
#####N-joy##### 
