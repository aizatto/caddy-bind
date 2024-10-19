# caddy-bind

The goal of this repository is to demonstrate how to get caddy working with bind9 over dynamic updates (RFC 2136).

I open sourced this because I don't see any tests online.

Why I did this:

1. I didn't see many tests of getting xcaddy working
    1. I wanted the build to support multi platform builds
1. I wanted to simplify my DNS management
    1. As I already specify the domains in my Caddyfile, I wondered if caddy could update my DNS
1. I run this in on own internal network
1. I found very little easy to understand information on RFC 2136

I am by no means a caddy, bind9, RFC 2136, or a dns expert.

## Getting started

Run

```sh
docker compose up
```

Bind expects the zone files to belong to the `bind` user in the container, else the `nsupdate` won't work. This only needs to be done once. If you create new zone files, make sure to run this again.

```sh
docker exec -it bind chown -R bind:bind /etc/bind/zones/
```

You can check permissions to see if it worked.

```sh
docker exec -it bind ls -l /etc/bind/zones
```

Query the dns to see if it works.

```sh
dig @localhost bind.test.com
```

## Notes

These are things I encountered, gotchas, learned along the way, design decisions, and configuration choices.

See my list of [References](README.references.md)

### Caddy

1. Acme is disabled to simplify the example.

#### Use static ip

As the intention is to use this in an internal network, I didn't want dynamic dns to use the public ip.

I configured the Caddyfile to use a `static_ip`.

An alternative solution would be:
1. Get the Docker container to use the [host network](https://docs.docker.com/reference/compose-file/services/#network_mode)
2. Specify in the Caddyfile to use host network interface

test:

In `docker-compose.yaml`:
```yaml
services:
  caddy:
    network: host
```

In `Caddyfile`, in the `dynamic_dns` block, assuming your interface is `eth0`:
```
  dynamic_dns {
   ip_source interface eth0
  }
```

#### Cross compile / Multi-platform builds

The `Dockerfile` supports cross compilation / [multi-platform builds](https://docs.docker.com/build/building/multi-platform/).

To cross compile run:

```sh
docker build \
  --platform linux/amd64,linux/arm64 \
  .
```

#### Debugging

Grep `docker logs` for `dynamic_dns`

```sh
docker logs -f caddy  2>&1 | grep dynamic_dns
```

### Bind

Gotchas:

1. Out of the box, when running the docker container, there is no logging.
    1. I enabled logging
1. Configuration files terminate each line with a semi colon.
1. Bind will exit if there are problems with the configuration files

#### zone file syntax is sensitive

Ensure there is a new line at the end of the file.

#### Check zone file for errors

The simplest way I found to verify the zone file is to grep the docker logs.

```sh
docker logs -f bind 2>&1 | grep test
```

test errors you will see:

```sh
general: warning: /etc/bind/zones/test.com.zone:47: file does not end with newline
zoneload: error: zone test.com/IN: loading from master file /etc/bind/zones/test.com.zone failed: unknown class/type
```

#### Sync zones

After an update the `test.com.zone` file may not be immediately updated because of how [journal files](https://bind9.readthedocs.io/en/v9.18.14/chapter6.html#the-journal-file) work.

You can see if a `test.com.zone.jnl` file is created after running caddy

```sh
docker exec -it bind ls -l /etc/bind/zones
```

To force a sync of the journal file you can run:

```sh
docker exec -it bind rndc sync test.com
```

#### Generate a new TSIG key

```sh
KEY_NAME="new-key"
docker exec -it bind tsig-keygen $KEY_NAME > bind/tsig/$KEY_NAME.key
```

### dig

`dig` is used to query dns information

```sh
dig @localhost test.com
```

Example response for `example.com`:

```sh
; <<>> DiG 9.18.28-1~deb12u2-Debian <<>> example.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 53553
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; QUESTION SECTION:
;example.com.			IN	A

;; ANSWER SECTION:
example.com.		2645	IN	A	93.184.215.14

;; Query time: 16 msec
;; SERVER: 192.168.13.5#53(192.168.13.5) (UDP)
;; WHEN: Sat Oct 19 08:55:19 +08 2024
;; MSG SIZE  rcvd: 56
```

### nsupdate

`nsupdate` is used to update bind.

When searching online, there is a lot inconsistent information on `nsupdate` online. I suggest sticking to the [Administrator Reference Manual](https://bind9.readthedocs.io/en/v9.18.14/manpages.html#nsupdate-dynamic-dns-update-utility).

You can send commands via a file or standard input.

Via `file`:

```sh
nsupdate nsupdate-examples/add.txt
```

Piping via `stdin`:

```sh
cat <<EOF | nsupdate
server 127.0.0.1 53
zone test.com.
key hmac-sha256:nsupdate sHJp801e5gFuu//pHHYQdPMwdyxBQPYtStPkxBWLsjo=
update add nsupdate.test.com. 60 A 192.168.1.1
show
send
EOF
```

Or just use `nsupdate` and enter the commands.

### Docker Stats

```sh
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

```sh
NAME      CPU %     MEM USAGE / LIMIT
caddy     0.00%     10.88MiB / 1GiB
bind      0.00%     11.27MiB / 1GiB
```
