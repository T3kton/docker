#!/bin/sh

/etc/init.d/postgresql start

/etc/init.d/mongodb start

apachectl -D FOREGROUND
