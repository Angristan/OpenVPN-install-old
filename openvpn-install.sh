#!/bin/bash
#Définition des variables de coloration
ROUGE="\\033[1;31m"
VERT="\\033[1;32m"
JAUNE="\\033[1;33m"
BLEU="\\033[1;34m"

echo -e "${BLEU}""###########################################################################"
echo -e "$BLEU""#                                                                         #"
echo -e "$BLEU""#  ""$JAUNE""Ce script bash installe un serveur OpenVPN sur Debian 8 uniquement""$BLEU""     #"
echo -e "$BLEU""# ""$JAUNE""Le serveur utilisera le protocole TCP sur le port 443                  ""$BLEU"" #"
echo -e "$BLEU""#                                                                         #"
echo -e "$BLEU""###########################################################################"

if [ "$UID" -ne "0" ] #On vérifie les droits
then
   echo -e "$ROUGE""Veuillez exécuter ce script en tant que root."
   exit
elif [[ ! -e /dev/net/tun ]] #On vérifie que le module TUN est activé
then
	echo -e "$ROUGE""TUN/TAP n'est pas activé."
  exit
else
  PS3='Entrez votre choix: '
  options=("Installer le serveur OpenVPN" "Créer un utilisateur" "Désinstaller OpenVPN" "Quiter")
  select opt in "${options[@]}"
  do
    case $opt in #1er CHOIX
      "Installer le serveur OpenVPN")
        read -p 'Port à utiliser pour le VPN : ' PORT
        echo -e "$VERT""###########################"
        echo -e "$VERT""# Installation de OpenVPN #"
        echo -e "$VERT""###########################"
        apt-get -y install openvpn easy-rsa zip dnsutils
        IP=`dig +short myip.opendns.com @resolver1.opendns.com` #On récupère l'IP publique
        echo -e "$VERT""##################################"
        echo -e "$VERT""# Création des clés/certificatst #"
        echo -e "$VERT""##################################"
        cd /etc/openvpn/
        mkdir easy-rsa
        cp -R /usr/share/easy-rsa/* easy-rsa/
        cd /etc/openvpn/easy-rsa/
        source vars
        ./clean-all
        ./build-dh
        ./pkitool --initca
        ./pkitool --server server
        openvpn --genkey --secret keys/the.key
        cd /etc/openvpn/easy-rsa/keys
        cp ca.crt dh2048.pem server.crt server.key the.key ../../
        echo -e "$VERT""########################################"
        echo -e "$VERT""# Création de la configuration serveur #"
        echo -e "$VERT""########################################"
        mkdir /etc/openvpn/jail
        mkdir /etc/openvpn/jail//tmp
        mkdir /etc/openvpn/confuser
        cd /etc/openvpn
        #On écrit la configuration du serveur
echo "#Serveur
mode server
proto tcp
port $PORT
dev tun

#Clés et certificats
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
tls-auth the.key 0
cipher AES-256-CBC

#Réseau
server 10.10.10.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 80.67.169.12" #On utilise les DNS de la FDN
push "dhcp-option DNS 80.67.169.40"
keepalive 10 120

#Sécurité
user nobody
group nogroup
chroot /etc/openvpn/jail
persist-key
persist-tun
comp-lzo #Compression

#Log
verb 3 #Niveau de log
mute 20
status openvpn-status.log
log-append /var/log/openvpn/openvpn.log #Fchier log" > server.conf
#Fin de la conf
        mkdir /var/log/openvpn/ #On crée le dossier et fichier de log
        touch /var/log/openvpn/openvpn.log
        echo -e "$VERT""########################"
        echo -e "$VERT""# Configuration réseau #"
        echo -e "$VERT""########################"
        systemctl enable openvpn #Activation d'OpenVPn au boot
        service openvpn start #Démarrage du daemon OpenVPN
        sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf
        sysctl -p
        #On active la passerelle vers Internet
        iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE
        iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o venet0 -j MASQUERADE
        sh -c "iptables-save > /etc/iptables.rules" #On sauve les règles iptables en cas de reboot
        echo "pre-up iptables-restore < /etc/iptables.rules" >> /etc/network/interfaces
      break
      ;;
      "Créer un utilisateur") #2ème CHOIX
      	if [ -e /etc/openvpn/server.conf ]
      		then
		        echo -e "$BLEU""Un utiisateur ne peut effectuer qu'une connexion à la fois."
		        echo -e "$BLEU""Mais vous pouvez créer autant d'utilisateurs que vous voulez,"
		        echo -e "$BLEU""et donc avoir autant de connexions simultanées que vous voulez ! :)"
		        echo -e "$ROUGE""L'IP ET LE PORT DOIVENT ÊTRE LES MÊMES QUE DANS LA CONFIGURATION DU SERVEUR"
		        read -p 'Port à utiliser pour le VPN : ' PORT
		        read -p "Nom de l'utilisateur (pas de caractères scpéciaux) : " CLIENT
		        IP=`dig +short myip.opendns.com @resolver1.opendns.com` #On récupère l'IP publique
		        echo -e "$VERT""####################################"
		        echo -e "$VERT""# Création des clés et certificats #"
		        echo -e "$VERT""####################################"
		        cd /etc/openvpn/easy-rsa
		        source vars
		        ./build-key-pass $CLIENT
		        mkdir /etc/openvpn/confuser/$CLIENT
		        cp keys/$CLIENT*.* keys/the.key keys/ca.crt /etc/openvpn/confuser/$CLIENT/
		        echo -e "$VERT""##########################################"
		        echo -e "$VERT""# Création de la configuration du client #"
		        echo -e "$VERT""##########################################"
		        cd /etc/openvpn/confuser/$CLIENT/
echo "#Client
client
dev tun
proto tcp-client
remote $IP $PORT
resolv-retry infinite
cipher AES-256-CBC

#Clés et certificats
ca ca.crt
cert $CLIENT.crt
key $CLIENT.key
tls-auth the.key 1

#Sécurité
nobind
persist-key
persist-tun
comp-lzo #Compression
verb 3 #Niveau de log" > client.conf
		        cp client.conf client.ovpn
		        chmod +r * #On rend les clé lisibles
		        zip $CLIENT-vpn.zip * #On zip le tout pour faciliter la récupération de la conf
		        chmod +r $CLIENT-vpn.zip
		        echo -e "$VERT""La configuration client se trouve dans $PWD/$CLIENT-vpn.zip"
		        echo -e "$VERT"'Pour récuprer le fichier de configuration, vous pouvez utiliser cette commande sur votre PC (GNU/Linux/OSX): '
		        echo -e "$JAUNE"'scp' "utilisateurSSH@$IP:/etc/openvpn/confuser/$CLIENT/$CLIENT-vpn.zip $CLIENT-vpn.zip"
		        break
		    else
		    	echo -e "$ROUGE""Vous devez installez le serveur avant de créer des utilisateurs."
		    	break
		    fi
      ;;
      "Désinstaller OpenVPN")
        systemctl stop openvpn
        systemctl disable openvpn
        rm -rf /etc/openvpn
        rm ~/*-vpn.zip
        rm -rf /var/log/openvpn/
        sed -i 's|net.ipv4.ip_forward=1|#net.ipv4.ip_forward=1|' /etc/sysctl.conf
        sysctl -p
        sed -i 's|pre-up iptables-restore < /etc/iptables.rules||' /etc/network/interfaces
        iptables -F
        apt-get autoremove --purge openvpn easy-rsa
        echo -e "$VERT""######################################################"
        echo -e "$VERT""# Le serveur OpenVPN a été complètement désinstallé. #"
        echo -e "$VERT""######################################################"
        break
      ;;
      "Quiter")
        break
      ;;
      *)
        echo invalid option;;
    esac
  done
fi
