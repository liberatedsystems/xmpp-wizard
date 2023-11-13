# XMPP server setup script
<div styling="text-align: center">
    <img src="images/thumbnail.png" alt="A priest aiming a gun at the Discord logo" width="500"/>
</div>

An XMPP server is hecking hard to configure!! But not any more.

You too, can be an XMPP server operator, through the use of this simple script!
No scouring over documentation for hours or headache required ;)

However, celibacy is required, since this script is written for use on __Arch
Linux* only__.

## Features
* Modern TLS configuration by default
* Uses MariaDB as the SQL database
* Adds an admin account

## Modules configured
* HTTP uploads (XEP-0363)
* HTTP upload quotas (by total size)
* STUN/TURN server

## Installation
### Prerequisites
Make sure you have the following packages installed:
```
Nginx
MariaDB
```

### Installs
This script installs the following packages:
* ejabberd - XMPP server
* certbot - managing certificates


### Running
The script should be run as root.

```doas/sudo bash xmpp-wizard.sh```

## To do
### mod_http_upload_quota
Allow for toggling of this module and configuring of max_days in script

## Disclaimers
Much of the inspiration for this project, along with some of the logic
(particularly the certificate detection) was taken from Luke Smith's
[emailwiz](https://github.com/LukeSmithxyz/emailwiz) script.

## Notes
*fedora and cringe atheistic world view not included
