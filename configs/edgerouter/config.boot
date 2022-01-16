firewall {
    all-ping enable
    broadcast-ping disable
    ipv6-receive-redirects disable
    ipv6-src-route disable
    ip-src-route disable
    log-martians enable
    name WAN_IN {
        default-action drop
        description "WAN to internal"
        rule 10 {
            action accept
            description "Allow established/related"
            state {
                established enable
                related enable
            }
        }
        rule 20 {
            action drop
            description "Drop invalid state"
            state {
                invalid enable
            }
        }
    }
    name WAN_LOCAL {
        default-action drop
        description "WAN to router"
        rule 10 {
            action accept
            description "Allow established/related"
            state {
                established enable
                related enable
            }
        }
        rule 20 {
            action drop
            description "Drop invalid state"
            state {
                invalid enable
            }
        }
    }
    receive-redirects disable
    send-redirects enable
    source-validation disable
    syn-cookies enable
}
interfaces {
    ethernet eth0 {
        address dhcp
        description Internet
        duplex auto
        firewall {
            in {
                name WAN_IN
            }
            local {
                name WAN_LOCAL
            }
        }
        speed auto
    }
    ethernet eth1 {
        address 192.168.1.1/24
        description Local
        duplex auto
        speed auto
    }
    ethernet eth2 {
        duplex auto
        speed auto
    }
    loopback lo {
    }
}
service {
    dhcp-server {
        disabled false
        hostfile-update disable
        shared-network-name LAN1 {
            authoritative enable
            subnet 192.168.1.0/24 {
                /* 192.168.1.1-192.168.1.4     used by router, controller, dns */
                /* 192.168.1.5-192.168.1.37    used by metallb */
                /* 192.168.1.245-192.168.1.250 used by clash and proxied devices */
                default-router 192.168.1.1
                dns-server 192.168.1.1
                lease 86400
                start 192.168.1.38 {
                    stop 192.168.1.243
                }
                static-mapping PlayStation5 {
                    mac-address 00:e4:21:e8:79:0c
                    ip-address 192.168.1.250
                    static-mapping-parameters "option routers 192.168.1.245;"
                    static-mapping-parameters "option domain-name-servers 192.168.1.245;"
                }
            }
        }
        static-arp disable
        use-dnsmasq disable
    }
    dns {
        forwarding {
            cache-size 150
            listen-on eth1
            name-server 1.1.1.1
            name-server 1.0.0.1
            options server=/local.d20.fan/192.168.1.3
        }
    }
    gui {
        http-port 80
        https-port 443
        older-ciphers enable
    }
    nat {
        rule 5010 {
            description "masquerade for WAN"
            outbound-interface eth0
            type masquerade
        }
    }
    ssh {
        port 22
        protocol-version v2
    }
    unms {
    }
}
system {
    analytics-handler {
        send-analytics-report true
    }
    crash-handler {
        send-crash-report true
    }
    host-name ubnt
    login {
        user ubnt {
            authentication {
                encrypted-password $5$e0a1UbX/3smy/MwE$TmornS/dFXgNmFaP/jIG1BTLjbJ2ULiUXmTkwysqdOD
                plaintext-password ""
            }
            full-name ""
            level admin
        }
    }
    ntp {
        server 0.ubnt.pool.ntp.org {
        }
        server 1.ubnt.pool.ntp.org {
        }
        server 2.ubnt.pool.ntp.org {
        }
        server 3.ubnt.pool.ntp.org {
        }
    }
    syslog {
        global {
            facility all {
                level notice
            }
            facility protocols {
                level debug
            }
        }
    }
    time-zone UTC
}


/* Warning: Do not remove the following line. */
/* === vyatta-config-version: "config-management@1:conntrack@1:cron@1:dhcp-relay@1:dhcp-server@4:firewall@5:ipsec@5:nat@3:qos@1:quagga@2:suspend@1:system@5:ubnt-l2tp@1:ubnt-pptp@1:ubnt-udapi-server@1:ubnt-unms@2:ubnt-util@1:vrrp@1:vyatta-netflow@1:webgui@1:webproxy@1:zone-policy@1" === */
/* Release version: v2.0.9-hotfix.2.5402463.210511.1317 */
