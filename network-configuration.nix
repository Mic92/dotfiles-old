{ config, lib, pkgs, ...}:
with lib;

let
  internetSharing = {
    enable = false;
    hotspot = false;
  };
  network = (import ./network.nix);
in {
  services = {
    #ferm = {
    #  enable = true;
    #  config = builtins.readFile "/etc/nixos/ferm.conf";
    #};
    dnscrypt-proxy = {
      enable = true;
      localAddress = "127.1.0.1";
      resolverName = "cs-de";
    };
    dnsmasq = {
      enable = true;
      extraConfig = ''
        #server=74.82.42.42
        #server=2001:470:20::2
        server=127.1.0.1
        server=/dn42/172.23.75.6

        no-resolv
        cache-size=1000
        min-cache-ttl=3600
        bind-dynamic
        all-servers

        dnssec
        trust-anchor=.,19036,8,2,49AAC11D7B6F6446702E54A1607371607A1A41855200FD2CE1CDDE32F24E8FB5

        address=/blog/127.0.0.1
        address=/blog/::1
        server=/higgsboson.tk/173.245.59.126
        rebind-domain-ok=/onion/
        server=/.onion/127.0.0.1#9053
        port=53
        #log-queries
        # dhcp
        # HOTSPOT
        interface=enp0s25
        dhcp-option=enp0s25,1,255.255.255.0  # subnet
        dhcp-option=enp0s25,3,192.168.43.254 # router
        dhcp-option=enp0s25,6,192.168.43.254 # dns
        dhcp-range=enp0s25,192.168.43.0,192.168.43.253,12h
        ${if internetSharing.hotspot then
        ''
          interface=wlp3s0
          dhcp-option=wlp3s0,1,255.255.255.0  # subnet
          dhcp-option=wlp3s0,3,192.168.44.254 # router
          dhcp-option=wlp3s0,6,192.168.44.254 # dns
          dhcp-range=wlp3s0,192.168.44.0,192.168.44.253,12h
        '' else if internetSharing.enable then ''
          interface=enp0s25
          dhcp-option=enp0s25,1,255.255.255.0  # subnet
          dhcp-option=enp0s25,3,192.168.43.254 # router
          dhcp-option=enp0s25,6,192.168.43.254 # dns
          dhcp-range=enp0s25,192.168.43.0,192.168.43.253,12h
        '' else ""}
      '';
    };
    resolved = {
      enable = false;
      dnssec = "false";
    };
    hostapd = {
      enable = internetSharing.hotspot;
      ssid = "cipherpunk";
      wpaPassphrase = "cipherpunk";
      interface = "wlp3s0";
    };
  };

  networking = {
    defaultMailServer = {
      directDelivery = true;
      hostName = "mail.thalheim.io:587";
      root = "joerg@thalheim.io";
      authUser = "joerg@higgsboson.tk";
      authPassFile = "/etc/nixos/secrets/smtp-authpass";
      domain = "thalheim.io";
      useSTARTTLS = true;
    };
    
    firewall.enable = false;
    nftables = {
      enable = true;
      ruleset = ''
        # Check out https://wiki.nftables.org/ for better documentation.
        # Table for both IPv4 and IPv6.
        table inet filter {
          # Block all incomming connections traffic except SSH and "ping".
          chain input {
            type filter hook input priority 0;
        
            ## accept any localhost traffic
            #iifname lo accept
        
            ## accept traffic originated from us
            #ct state {established, related} accept
       
            ## ICMP
            ## routers may also want: mld-listener-query, nd-router-solicit
            #ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
            #ip protocol icmp icmp type { destination-unreachable, router-advertisement, time-exceeded, parameter-problem } accept

            ## allow "ping"
            #ip6 nexthdr icmp icmpv6 type echo-request accept
            #ip protocol icmp icmp type echo-request accept

            ## accept SSH connections (required for a server)
            #tcp dport 22 accept
        
            ## count and drop any other traffic
            #counter drop
          }
        
          # Allow all outgoing connections.
          chain output {
            type filter hook output priority 0;
            accept
          }
        
          chain forward {
            type filter hook forward priority 0;
            accept
          }
        }
      '';
    };
    nameservers = [ "127.0.0.1" ];
    hostId = "8425e349";
    hostName = "turingmachine";
    wireless.enable = !internetSharing.hotspot;
    extraHosts = ''
      #141.76.50.75 sharelatex.local
    '';
    dhcpcd.enable = false;
  };

  systemd.network.enable = true;
  systemd.services.systemd-networkd.serviceConfig.ExecStart = [
    ""
    "${pkgs.networkd}/bin/systemd-networkd"
  ];
  systemd.network.netdevs = let
    wgTemplate = lport: name: endpoint: key: {
      netdevConfig = { Name = "wg-${name}"; Kind = "wireguard"; };
      extraConfig = ''
       [Wireguard]
       PrivateKey = ${lib.readFile ./secrets/wireguard-key}
       ListenPort = ${toString lport}

       [WireguardPeer]
       AllowedIPs = 0.0.0.0/0
       AllowedIPs = ::/0
       Endpoint = ${endpoint}
       PublicKey = ${key}
      '';
    };
  in {
    wg-eve = wgTemplate 42421 "eve" "ipv4.dn42.higgsboson.tk:42422" "fxiGmHUK1aMa07cejTP3SHxYivIj3aXZwdvzTEXmYHM=";
    wg-eve6 = wgTemplate 42422 "eve6" "ipv6.dn42.higgsboson.tk:42422" "fxiGmHUK1aMa07cejTP3SHxYivIj3aXZwdvzTEXmYHM=";
    wg-rauter = wgTemplate 42423 "rauter" "ipv4.rauter.thalheim.io:42422" "l6LjG1WuLNkEwd2047mw2GpgPUppM1VwP/LWMaOqJ0E=";
    wg-matchbox = wgTemplate 42424 "matchbox" "ipv4.matchbox.thalheim.io:42432" "6ExGu7MjeHoPbWj8/F3YNcdMHa7e3fXFFPkswAXv4T4=";

    dummy0.netdevConfig = { Name = "dummy0"; Kind = "dummy"; };
    #physical = {
    #  netdevConfig = { 
    #    Name = "physical";
    #    Kind = "vrf";
    #  };
    #  extraConfig = ''
    #    TableId=42
    #  '';
    #};
  };
  systemd.network.networks = {
    ethernet.extraConfig = ''
      [Match]
      Name = enp0s25

      [Network]
      DHCP=both
      LLMNR=true
      IPv4LL=true
      ${optionalString internetSharing.enable ''
        IPForward=yes
        Address=192.168.43.254/24
      ''}
      LLDP=true
      IPv6AcceptRA=true
      #VRF=physical

      [DHCP]
      UseHostname=false
      UseDNS=false
      RouteMetric=512
    '';
    wlan.extraConfig = ''
      [Match]
      Name=wlp3s0

      [Network]
      DHCP=both
      LLMNR=true
      IPv4LL=true
      ${optionalString internetSharing.enable ''
        IPForward=yes
        Address=192.168.44.254/24
      ''}
      IPForward=yes
      LLDP=true
      IPv6AcceptRA=true
      #VRF=physical

      [DHCP]
      UseHostname=false
      UseDNS=false
      RouteMetric=1024
    '';
    dummy.extraConfig = ''
      [Match]
      Name=dummy0

      [Network]
      Address=${network.ip4_prefix}/32
      Address=${network.ula_prefix}::1/64

      [Address]
      Address=${network.ip6_prefix}::1/120
      PreferredLifetime=0
    '';
    wg-eve.extraConfig = ''
      [Match]
      Name=wg-eve

      [Network]
      DNS=172.23.75.6
      Domains=~dn42
      DNSSEC=allow-downgrade
      BindCarrier=enp0s20u*,wlp3s0,enp0s25
      Address=fe80::${network.router_id}/64

      [Address]
      Address=169.254.1.${network.router_id}/16
      PreferredLifetime=0
      Scope=link

      [Route]
      Destination=2000::/3
      Source=2a03:4000:13:31e:200::/120
      Gateway=fe80::1
      Metric=512
    '';
    wireguard.extraConfig = ''
      [Match]
      Name=wg-*

      [Network]
      BindCarrier=enp0s20u*,wlp3s0,enp0s25
      Address=fe80::${network.router_id}/64

      [Address]
      Address=169.254.1.${network.router_id}/16
      PreferredLifetime=0
      Scope=link
    '';
    tethering.extraConfig = ''
      [Match]
      Name=enp0s20u*

      [Network]
      DHCP=both
      LLMNR=true
      IPv4LL=false
      IPForward=yes
      LLDP=true
      Address=192.168.42.254/24

      [DHCP]
      UseHostname=false
      UseDNS=false
      RouteMetric=2048
    '';
    bluetooth.extraConfig = ''
      [Match]
      Name=bnep0

      [Network]
      DHCP=both
      LLMNR=true
      IPv4LL=true
      IPForward=yes
      LLDP=true
      Address=192.168.42.254/24

      [DHCP]
      UseHostname=false
      UseDNS=false
      RouteMetric=2048
    '';
  };
}
