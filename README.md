# XMPP server setup script
An XMPP server is hecking hard to configure!! But not any more.

You too, can be an XMPP server operator, through the use of this simple script!
No scouring over documentation for hours or headache required ;)

However, celibacy is required, since this script is written for use on **Arch
Linux* only**.

## Prerequisites
Make sure you have the following packages installed:
```
Nginx
Mariadb
```

## Running
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
