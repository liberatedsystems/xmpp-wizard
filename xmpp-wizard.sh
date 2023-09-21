#!/bin/sh
sqldb="ejabberd"
sqlusername="ejabberd"
ejabberdtlsdir="/var/lib/ejabberd"

pacman -S --noconfirm ejabberd

read -p "Enter your domain: " domain

domains=("conference.$domain" "proxy.$domain" "pubsub.$domain" "upload.$domain")
certdirs=("/etc/letsencrypt/live/$domain" "/etc/letsencrypt/live/${domains[0]}" "/etc/letsencrypt/live/${domains[1]}" "/etc/letsencrypt/live/${domains[2]}" "/etc/letsencrypt/live/${domains[3]}")
ejabberdcertdirs=("${ejabberdtlsdir}/${domain}.pem" "${ejabberdtlsdir}/${domains[0]}.pem" "${ejabberdtlsdir}/${domains[1]}.pem" "${ejabberdtlsdir}/${domains[2]}.pem" "${ejabberdtlsdir}/${domains[3]}.pem")

index=0

# try to find any existing certificates for the various vhosts required by
# ejabberd, otherwise retrieve them via certbot
for vhost in ${domains[@]}; do # for each vhost
    [ ! -d "${certdirs[$index]}" ] && # if default cert dir for the vhost doesn't exist
        certdirs[$index]=$(certbot certificates 2>/dev/null | grep "Domains:.* \(\*\.$domain\|$vhost\)\(\s\|$\)" -A 2 | awk '/Certificate Path/ {print $3}' | head -n1) # set cert dir for certificate
        ((index++))

        [ ! -d "${certdirs[$index]}" ] && # if there is no certificate for the domain 
            if systemctl is-active --quiet nginx
            then
                pacman -S --noconfirm certbot-nginx
                certbot -d "$vhost" certonly --nginx --register-unsafely-without-email --agree-tos &&
                    certdirs[$index]="/etc/letsencrypt/live/$vhost" # request cert with nginx
            else
                pacman -S --noconfirm certbot
                certbot -d "$vhost" certonly --standalone --register-unsafely-without-email --agree-tos &&
                    certdirs[$index]="/etc/letsencrypt/live/$vhost" # request cert with certbot
            fi
    [ ! -d "${certdirs[$index]}" ] && echo "Error locating or installing SSL certificate." && exit 1
done

read -p "Enter the username for the admin user: " adminusername
while read -p "$adminusername@$domain is this correct? (y/n): " confirm; do
    if [ "$confirm" == "y" ]; then
        break
    else
        read -p "Enter the username for the admin user: " adminusername
        continue
    fi
done

read -p "Enter the password for the ejabberd SQL user: " sqlpassword
while read -p "$sqlpassword is this correct? (y/n): " confirm; do
    if [ "$confirm" == "y" ]; then
        break
    else
        read -p "Enter the password for the ejabberd SQL user: " sqlpassword
        continue
    fi
done

index=0

echo "Creating ejabberd TLS cert files..." # we have to create special TLS
                                           # certs just for ejabberd because 
                                           # it's a special snowflake who 
                                           # reads the guardian
for vhost in ${certdirs[@]}; do # for each vhost
    # concatenate the private key and fullchain into one file
    cat ${certdirs[$index]}/privkey.pem ${certdirs[$index]}/fullchain.pem > ${ejabberdtlsdir}/${vhost}.pem 
    # update file perms
    chown jabber:jabber ${ejabberdtlsdir}/${vhost}.pem
    chmod 700 ${ejabberdtlsdir}/${vhost}.pem
done

echo "Setting up ejabberd SQL database..."

mariadb -e "CREATE DATABASE $sqldb; CREATE USER $sqlusername@localhost IDENTIFIED BY '$sqlpassword'; GRANT ALL ON ejabberd.* TO $sqlusername@localhost"

echo """
--
-- ejabberd, Copyright (C) 2002-2023   ProcessOne
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation; either version 2 of the
-- License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along
-- with this program; if not, write to the Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
--

CREATE TABLE users (
    username varchar(191) PRIMARY KEY,
    password text NOT NULL,
    serverkey varchar(128) NOT NULL DEFAULT '',
    salt varchar(128) NOT NULL DEFAULT '',
    iterationcount integer NOT NULL DEFAULT 0,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Add support for SCRAM auth to a database created before ejabberd 16.03:
-- ALTER TABLE users ADD COLUMN serverkey varchar(64) NOT NULL DEFAULT '';
-- ALTER TABLE users ADD COLUMN salt varchar(64) NOT NULL DEFAULT '';
-- ALTER TABLE users ADD COLUMN iterationcount integer NOT NULL DEFAULT 0;

CREATE TABLE last (
    username varchar(191) PRIMARY KEY,
    seconds text NOT NULL,
    state text NOT NULl
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;


CREATE TABLE rosterusers (
    username varchar(191) NOT NULL,
    jid varchar(191) NOT NULL,
    nick text NOT NULL,
    subscription character(1) NOT NULL,
    ask character(1) NOT NULL,
    askmessage text NOT NULL,
    server character(1) NOT NULL,
    subscribe text NOT NULL,
    type text,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_rosteru_user_jid ON rosterusers(username(75), jid(75));
CREATE INDEX i_rosteru_jid ON rosterusers(jid);

CREATE TABLE rostergroups (
    username varchar(191) NOT NULL,
    jid varchar(191) NOT NULL,
    grp text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX pk_rosterg_user_jid ON rostergroups(username(75), jid(75));

CREATE TABLE sr_group (
    name varchar(191) NOT NULL,
    opts text NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_sr_group_name ON sr_group(name);

CREATE TABLE sr_user (
    jid varchar(191) NOT NULL,
    grp varchar(191) NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_sr_user_jid_group ON sr_user(jid(75), grp(75));
CREATE INDEX i_sr_user_grp ON sr_user(grp);

CREATE TABLE spool (
    username varchar(191) NOT NULL,
    xml mediumtext NOT NULL,
    seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX i_despool USING BTREE ON spool(username);
CREATE INDEX i_spool_created_at USING BTREE ON spool(created_at);

CREATE TABLE archive (
    username varchar(191) NOT NULL,
    timestamp BIGINT UNSIGNED NOT NULL,
    peer varchar(191) NOT NULL,
    bare_peer varchar(191) NOT NULL,
    xml mediumtext NOT NULL,
    txt mediumtext,
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
    kind varchar(10),
    nick varchar(191),
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE FULLTEXT INDEX i_text ON archive(txt);
CREATE INDEX i_username_timestamp USING BTREE ON archive(username(191), timestamp);
CREATE INDEX i_username_peer USING BTREE ON archive(username(191), peer(191));
CREATE INDEX i_username_bare_peer USING BTREE ON archive(username(191), bare_peer(191));
CREATE INDEX i_timestamp USING BTREE ON archive(timestamp);

CREATE TABLE archive_prefs (
    username varchar(191) NOT NULL PRIMARY KEY,
    def text NOT NULL,
    always text NOT NULL,
    never text NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE vcard (
    username varchar(191) PRIMARY KEY,
    vcard mediumtext NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE vcard_search (
    username varchar(191) NOT NULL,
    lusername varchar(191) PRIMARY KEY,
    fn text NOT NULL,
    lfn varchar(191) NOT NULL,
    family text NOT NULL,
    lfamily varchar(191) NOT NULL,
    given text NOT NULL,
    lgiven varchar(191) NOT NULL,
    middle text NOT NULL,
    lmiddle varchar(191) NOT NULL,
    nickname text NOT NULL,
    lnickname varchar(191) NOT NULL,
    bday text NOT NULL,
    lbday varchar(191) NOT NULL,
    ctry text NOT NULL,
    lctry varchar(191) NOT NULL,
    locality text NOT NULL,
    llocality varchar(191) NOT NULL,
    email text NOT NULL,
    lemail varchar(191) NOT NULL,
    orgname text NOT NULL,
    lorgname varchar(191) NOT NULL,
    orgunit text NOT NULL,
    lorgunit varchar(191) NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX i_vcard_search_lfn       ON vcard_search(lfn);
CREATE INDEX i_vcard_search_lfamily   ON vcard_search(lfamily);
CREATE INDEX i_vcard_search_lgiven    ON vcard_search(lgiven);
CREATE INDEX i_vcard_search_lmiddle   ON vcard_search(lmiddle);
CREATE INDEX i_vcard_search_lnickname ON vcard_search(lnickname);
CREATE INDEX i_vcard_search_lbday     ON vcard_search(lbday);
CREATE INDEX i_vcard_search_lctry     ON vcard_search(lctry);
CREATE INDEX i_vcard_search_llocality ON vcard_search(llocality);
CREATE INDEX i_vcard_search_lemail    ON vcard_search(lemail);
CREATE INDEX i_vcard_search_lorgname  ON vcard_search(lorgname);
CREATE INDEX i_vcard_search_lorgunit  ON vcard_search(lorgunit);

CREATE TABLE privacy_default_list (
    username varchar(191) PRIMARY KEY,
    name varchar(191) NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE privacy_list (
    username varchar(191) NOT NULL,
    name varchar(191) NOT NULL,
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_privacy_list_username_name USING BTREE ON privacy_list (username(75), name(75));

CREATE TABLE privacy_list_data (
    id bigint,
    t character(1) NOT NULL,
    value text NOT NULL,
    action character(1) NOT NULL,
    ord NUMERIC NOT NULL,
    match_all boolean NOT NULL,
    match_iq boolean NOT NULL,
    match_message boolean NOT NULL,
    match_presence_in boolean NOT NULL,
    match_presence_out boolean NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX i_privacy_list_data_id ON privacy_list_data(id);

CREATE TABLE private_storage (
    username varchar(191) NOT NULL,
    namespace varchar(191) NOT NULL,
    data text NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_private_storage_username_namespace USING BTREE ON private_storage(username(75), namespace(75));

-- Not tested in mysql
CREATE TABLE roster_version (
    username varchar(191) PRIMARY KEY,
    version text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- To update from 1.x:
-- ALTER TABLE rosterusers ADD COLUMN askmessage text AFTER ask;
-- UPDATE rosterusers SET askmessage = '';
-- ALTER TABLE rosterusers ALTER COLUMN askmessage SET NOT NULL;

CREATE TABLE pubsub_node (
  host text NOT NULL,
  node text NOT NULL,
  parent VARCHAR(191) NOT NULL DEFAULT '',
  plugin text NOT NULL,
  nodeid bigint auto_increment primary key
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE INDEX i_pubsub_node_parent ON pubsub_node(parent(120));
CREATE UNIQUE INDEX i_pubsub_node_tuple ON pubsub_node(host(71), node(120));

CREATE TABLE pubsub_node_option (
  nodeid bigint,
  name text NOT NULL,
  val text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE INDEX i_pubsub_node_option_nodeid ON pubsub_node_option(nodeid);
ALTER TABLE \`pubsub_node_option\` ADD FOREIGN KEY (\`nodeid\`) REFERENCES \`pubsub_node\` (\`nodeid\`) ON DELETE CASCADE;

CREATE TABLE pubsub_node_owner (
  nodeid bigint,
  owner text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE INDEX i_pubsub_node_owner_nodeid ON pubsub_node_owner(nodeid);
ALTER TABLE \`pubsub_node_owner\` ADD FOREIGN KEY (\`nodeid\`) REFERENCES \`pubsub_node\` (\`nodeid\`) ON DELETE CASCADE;

CREATE TABLE pubsub_state (
  nodeid bigint,
  jid text NOT NULL,
  affiliation character(1),
  subscriptions VARCHAR(191) NOT NULL DEFAULT '',
  stateid bigint auto_increment primary key
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE INDEX i_pubsub_state_jid ON pubsub_state(jid(60));
CREATE UNIQUE INDEX i_pubsub_state_tuple ON pubsub_state(nodeid, jid(60));
ALTER TABLE \`pubsub_state\` ADD FOREIGN KEY (\`nodeid\`) REFERENCES \`pubsub_node\` (\`nodeid\`) ON DELETE CASCADE;

CREATE TABLE pubsub_item (
  nodeid bigint,
  itemid text NOT NULL,
  publisher text NOT NULL,
  creation varchar(32) NOT NULL,
  modification varchar(32) NOT NULL,
  payload mediumtext NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE INDEX i_pubsub_item_itemid ON pubsub_item(itemid(36));
CREATE UNIQUE INDEX i_pubsub_item_tuple ON pubsub_item(nodeid, itemid(36));
ALTER TABLE \`pubsub_item\` ADD FOREIGN KEY (\`nodeid\`) REFERENCES \`pubsub_node\` (\`nodeid\`) ON DELETE CASCADE;

CREATE TABLE pubsub_subscription_opt (
  subid text NOT NULL,
  opt_name varchar(32),
  opt_value text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE UNIQUE INDEX i_pubsub_subscription_opt ON pubsub_subscription_opt(subid(32), opt_name(32));

CREATE TABLE muc_room (
    name text NOT NULL,
    host text NOT NULL,
    opts mediumtext NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_muc_room_name_host USING BTREE ON muc_room(name(75), host(75));
CREATE INDEX i_muc_room_host_created_at ON muc_room(host(75), created_at);

CREATE TABLE muc_registered (
    jid text NOT NULL,
    host text NOT NULL,
    nick text NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX i_muc_registered_nick USING BTREE ON muc_registered(nick(75));
CREATE UNIQUE INDEX i_muc_registered_jid_host USING BTREE ON muc_registered(jid(75), host(75));

CREATE TABLE muc_online_room (
    name text NOT NULL,
    host text NOT NULL,
    node text NOT NULL,
    pid text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_muc_online_room_name_host USING BTREE ON muc_online_room(name(75), host(75));

CREATE TABLE muc_online_users (
    username text NOT NULL,
    server text NOT NULL,
    resource text NOT NULL,
    name text NOT NULL,
    host text NOT NULL,
    node text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_muc_online_users USING BTREE ON muc_online_users(username(75), server(75), resource(75), name(75), host(75));

CREATE TABLE muc_room_subscribers (
   room varchar(191) NOT NULL,
   host varchar(191) NOT NULL,
   jid varchar(191) NOT NULL,
   nick text NOT NULL,
   nodes text NOT NULL,
   created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY i_muc_room_subscribers_host_room_jid (host, room, jid)
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX i_muc_room_subscribers_host_jid USING BTREE ON muc_room_subscribers(host, jid);
CREATE INDEX i_muc_room_subscribers_jid USING BTREE ON muc_room_subscribers(jid);

CREATE TABLE motd (
    username varchar(191) PRIMARY KEY,
    xml text,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE caps_features (
    node varchar(191) NOT NULL,
    subnode varchar(191) NOT NULL,
    feature text,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX i_caps_features_node_subnode ON caps_features(node(75), subnode(75));

CREATE TABLE sm (
    usec bigint NOT NULL,
    pid text NOT NULL,
    node text NOT NULL,
    username varchar(191) NOT NULL,
    resource varchar(191) NOT NULL,
    priority text NOT NULL,
    info text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_sid ON sm(usec, pid(75));
CREATE INDEX i_node ON sm(node(75));
CREATE INDEX i_username ON sm(username);

CREATE TABLE oauth_token (
    token varchar(191) NOT NULL PRIMARY KEY,
    jid text NOT NULL,
    scope text NOT NULL,
    expire bigint NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE oauth_client (
    client_id varchar(191) NOT NULL PRIMARY KEY,
    client_name text NOT NULL,
    grant_type text NOT NULL,
    options text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE route (
    domain text NOT NULL,
    server_host text NOT NULL,
    node text NOT NULL,
    pid text NOT NULL,
    local_hint text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_route ON route(domain(75), server_host(75), node(75), pid(75));

CREATE TABLE bosh (
    sid text NOT NULL,
    node text NOT NULL,
    pid text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_bosh_sid ON bosh(sid(75));

CREATE TABLE proxy65 (
    sid text NOT NULL,
    pid_t text NOT NULL,
    pid_i text NOT NULL,
    node_t text NOT NULL,
    node_i text NOT NULL,
    jid_i text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_proxy65_sid ON proxy65 (sid(191));
CREATE INDEX i_proxy65_jid ON proxy65 (jid_i(191));

CREATE TABLE push_session (
    username text NOT NULL,
    timestamp bigint NOT NULL,
    service text NOT NULL,
    node text NOT NULL,
    xml text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_push_usn ON push_session (username(191), service(191), node(191));
CREATE UNIQUE INDEX i_push_ut ON push_session (username(191), timestamp);

CREATE TABLE mix_channel (
    channel text NOT NULL,
    service text NOT NULL,
    username text NOT NULL,
    domain text NOT NULL,
    jid text NOT NULL,
    hidden boolean NOT NULL,
    hmac_key text NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_mix_channel ON mix_channel (channel(191), service(191));
CREATE INDEX i_mix_channel_serv ON mix_channel (service(191));

CREATE TABLE mix_participant (
    channel text NOT NULL,
    service text NOT NULL,
    username text NOT NULL,
    domain text NOT NULL,
    jid text NOT NULL,
    id text NOT NULL,
    nick text NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_mix_participant ON mix_participant (channel(191), service(191), username(191), domain(191));

CREATE TABLE mix_subscription (
    channel text NOT NULL,
    service text NOT NULL,
    username text NOT NULL,
    domain text NOT NULL,
    node text NOT NULL,
    jid text NOT NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_mix_subscription ON mix_subscription (channel(153), service(153), username(153), domain(153), node(153));
CREATE INDEX i_mix_subscription_chan_serv_node ON mix_subscription (channel(191), service(191), node(191));

CREATE TABLE mix_pam (
    username text NOT NULL,
    channel text NOT NULL,
    service text NOT NULL,
    id text NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX i_mix_pam ON mix_pam (username(191), channel(191), service(191));

CREATE TABLE mqtt_pub (
    username varchar(191) NOT NULL,
    resource varchar(191) NOT NULL,
    topic text NOT NULL,
    qos tinyint NOT NULL,
    payload blob NOT NULL,
    payload_format tinyint NOT NULL,
    content_type text NOT NULL,
    response_topic text NOT NULL,
    correlation_data blob NOT NULL,
    user_properties blob NOT NULL,
    expiry int unsigned NOT NULL,
    UNIQUE KEY i_mqtt_topic (topic(191))
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;""" | mariadb -D $sqldb

if [ ! -f /etc/ssl/dh2048.pem ]
then
    echo "Generating dhfile..."
    openssl dhparam -out /etc/ssl/dh2048.pem 2048
fi

echo "HTTP uploads in XMPP are stored on the server itself. There are many
different parameters you can configure with respect to HTTP uploads. A soft
quota can be set per user, along with a hard quota. After the hard quota is
exceeded, files are deleted from the oldest until the total size of files the
user has on the server is less than the soft quota."

read -p "What soft quota would you like to set per user? (MB): " softquota
while read -p "$softquota MB is this correct? (y/n): " confirm; do
    if [ "$confirm" == "y" ]; then
        break
    else
        read -p "What soft quota would you like to set per user? (MB): " softquota
        continue
    fi
done

read -p "What hard quota would you like to set per user? (MB): " hardquota
while read -p "$hardquota MB is this correct? (y/n): " confirm; do
    if [ "$confirm" == "y" ]; then
        break
    else
        read -p "What hard quota would you like to set per user? (MB): " hardquota
        continue
    fi
done

echo "Installing ejabberd config file..."

echo """
###
###              ejabberd configuration file
###
### The parameters used in this configuration file are explained at
###
###       https://docs.ejabberd.im/admin/configuration
###
### The configuration file is written in YAML.
### *******************************************************
### *******           !!! WARNING !!!               *******
### *******     YAML IS INDENTATION SENSITIVE       *******
### ******* MAKE SURE YOU INDENT SECTIONS CORRECTLY *******
### *******************************************************
### Refer to http://en.wikipedia.org/wiki/YAML for the brief description.
###

# strict TLS configuration to disable insecure ciphers and TLS versions
define_macro:
  BACKLOG: 50
  DH_FILE: /etc/ssl/dh2048.pem
  CIPHERS: \"ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256\"
  TLS_OPTIONS:
    - \"no_sslv2\"
    - \"no_sslv3\"
    - \"no_tlsv1\"
    - \"no_tlsv1_1\"
    - \"cipher_server_preference\"
    - \"no_compression\"

hosts:
  - $domain

loglevel: info

acme:
  auto: false

certfiles:
  - ${ejabberdtlsdirs[0]}
  - ${ejabberdtlsdirs[1]}
  - ${ejabberdtlsdirs[2]}
  - ${ejabberdtlsdirs[3]}
  - ${ejabberdtlsdirs[4]}

c2s_ciphers: TLS_CIPHERS
c2s_protocol_options: TLS_OPTIONS
c2s_dhfile: DH_FILE
s2s_ciphers: TLS_CIPHERS
s2s_protocol_options: TLS_OPTIONS
s2s_dhfile: DH_FILE
s2s_use_starttls: required

listen:
  -
    port: 5222
    ip: \"::\"
    module: ejabberd_c2s
    max_stanza_size: 262144    
    starttls: true
    starttls_required: false
    tls_compression: false
    shaper: c2s_shaper
    access: c2s
    backlog: BACKLOG
  -
    port: 5223
    ip: \"::\"
    tls: true
    backlog: BACKLOG
    module: ejabberd_c2s
    max_stanza_size: 262144
    shaper: c2s_shaper
    access: c2s
    tls_compression: false
  -
    port: 5269
    ip: \"::\"
    module: ejabberd_s2s_in
    max_stanza_size: 524288
    tls_compression: false
  -
    port: 5270
    ip: \"::\"
    backlog: BACKLOG
    module: ejabberd_s2s_in
    max_stanza_size: 524288
    tls_compression: false
  -
    port: 5280
    ip: \"::\"
    module: ejabberd_http
    request_handlers:
      /admin: ejabberd_web_admin
      /.well-known/acme-challenge: ejabberd_acme
      /upload: mod_http_upload
  -
    port: 3478
    ip: \"::\"
    transport: udp
    module: ejabberd_stun
    use_turn: true
  -
    port: 1883
    ip: \"::\"
    module: mod_mqtt
    backlog: 1000

auth_method: sql
default_db: sql

sql_type: mysql
sql_server: \"localhost\"
sql_database: \"$sqldb\"
sql_username: \"$sqlusername\"
sql_password: \"$sqlpassword\"

acl:
  admin:
    user: $adminusername@$domain
  local:
    user_regexp: \"\"
  loopback:
    ip:
      - 127.0.0.0/8
      - ::1/128

access_rules:
  configure:
    allow: admin # only allow an admin to configure the server
  local:
    allow: local
  c2s:
    allow: all
    deny: blocked
  announce:
    allow: admin # only allow an admin to send announcements
  muc_create:
    allow: admin # only allow an admin to create MUCs
  pubsub_createnode:
    allow: local
  trusted_network:
    allow: loopback

api_permissions:
  \"console commands\":
    from:
      - ejabberd_ctl
    who: all
    what: \"*\"
  \"admin access\":
    who:
      access:
        allow:
          - acl: loopback
          - acl: admin
      oauth:
        scope: \"ejabberd:admin\"
        access:
          allow:
            - acl: loopback
            - acl: admin
    what:
      - \"*\"
      - \"!stop\"
      - \"!start\"
  \"public commands\":
    who:
      ip: 127.0.0.1/8
    what:
      - status
      - connected_users_number

shaper:
  normal:
    rate: 1000000 # monal (iOS XMPP client) only has 30 seconds to load messages (of which there could be many) from a push notification, hence the high rate
    burst_size: 5000000 # see above
  fast: 50000000

shaper_rules:
  max_user_sessions: 10
  max_user_offline_messages:
    5000: admin
    1000: all
  c2s_shaper:
    none: admin
    normal: all
  s2s_shaper: fast
  soft_upload_quota:
    $softquota: all # MB
  hard_upload_quota:
    $hardquota: all # MB

modules:
  mod_adhoc: {}
  mod_admin_extra: {}
  mod_announce:
    access: announce
  mod_avatar: {}
  mod_blocking: {}
  mod_bosh: {}
  mod_caps: {}
  mod_carboncopy: {}
  mod_client_state: {}
  mod_configure: {}
  mod_disco: {}
  mod_fail2ban: {}
  mod_http_api: {}
  mod_http_upload:
    put_url: \"https://${domains[3]}/upload/@HOST@\"
    hosts:
      - ${domains[3]}
    custom_headers:
      \"Access-Control-Allow-Origin\": \"*\"
      \"Access-Control-Allow-Methods\": \"GET,HEAD,PUT,OPTIONS\"
      \"Access-Control-Allow-Headers\": \"Content-Type\"
  #mod_http_upload_quota:
    #max_days: 100 # 100 days until content is deleted
  mod_last: {}
  mod_mam:
    ## Mnesia is limited to 2GB, better to use an SQL backend
    ## For small servers SQLite is a good fit and is very easy
    ## to configure. Uncomment this when you have SQL configured:
    db_type: sql
    assume_mam_usage: true
    default: always
  mod_mqtt: {}
  mod_muc:
    access:
      - allow
    access_admin:
      - allow: admin
    access_create: muc_create
    access_persistent: muc_create
    access_mam:
      - allow
    default_room_options:
      mam: true
  mod_muc_admin: {}
  mod_offline:
    access_max_user_messages: max_user_offline_messages
  mod_ping: {}
  mod_privacy: {}
  mod_private: {}
  mod_proxy65:
    access: local
    max_connections: 5
  mod_pubsub:
    access_createnode: pubsub_createnode
    plugins:
      - flat
      - pep
    force_node_config:
      ## Avoid buggy clients to make their bookmarks public
      \"eu.siacs.conversations.axolotl.*\":
        access_model: open
      storage:bookmarks:
        access_model: whitelist
  mod_push: {}
  mod_push_keepalive: {}
  mod_register:
    ## Only accept registration requests from the \"trusted\"
    ## network (see access_rules section above).
    ## Think twice before enabling registration from any
    ## address. See the Jabber SPAM Manifesto for details:
    ## https://github.com/ge0rg/jabber-spam-fighting-manifesto
    ip_access: trusted_network
  mod_roster:
    versioning: true
  mod_s2s_dialback: {}
  mod_shared_roster: {}
  mod_stream_mgmt:
    resend_on_timeout: if_offline
  mod_stun_disco: {}
  mod_vcard: {}
  mod_vcard_xupdate: {}
  mod_version:
    show_os: false

### Local Variables:
### mode: yaml
### End:
### vim: set filetype=yaml tabstop=8""" > /etc/ejabberd/ejabberd.yml

chmod 700 /etc/ejabberd/ejabberd.yml

echo "Installing nginx upload vhost file..."

echo "
server {
    server_name ${domains[3]};
   
    listen 443 ssl; 
    ssl_certificate ${certdirs[4]}/fullchain.pem;
    ssl_certificate_key ${certdirs[4]}/privkey.pem; 
    include /etc/letsencrypt/options-ssl-nginx.conf; 
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; 

    location /upload {
	   proxy_pass http://localhost:5280/upload;
	   proxy_set_header Host \$host;
	   proxy_set_header X-Real-IP \$remote_addr;
	   proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	   proxy_set_header X-Forwarded-Proto \$scheme;
    }

}
server {
    if (\$host = ${domains[3]}) {
        return 301 https://\$host\$request_uri;
    }


    server_name ${domains[3]};

    listen 80;
    return 404;


}" > /etc/nginx/sites-available/${domains[3]} # direct uploads to ejabberd

ln -s /etc/nginx/sites-available/${domains[3]} /etc/nginx/sites-enabled/${domains[3]}

systemctl restart nginx
