#!/bin/sh

if [ "$1" != "VCS_USER" ];
then
  exit 1
fi

exec "/phabricator/bin/ssh-auth" $@
