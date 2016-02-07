#!/bin/bash

home=$1
name=$2
prj=$3

mkdir -p /var/log/$name
chmod 755 $home/$prj/script/$prj
mkdir -p $home/$prj/log
touch $home/$prj/log/development.log
ln -sf $home/$prj/log/development.log /var/log/$name/$prj.log
chown -R $name:$name $home/$prj/log
