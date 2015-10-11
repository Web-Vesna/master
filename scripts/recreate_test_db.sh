#!/bin/bash

echo 'drop database `apek-energo-test`; create database `apek-energo-test`; use `apek-energo-test`; grant all privileges on `apek-energo-test`.* to `apek-energo-test`@localhost; grant all privileges on `apek-energo-test`.* to `apek-energo-user`@`%`;' | mysql
mysql apek-energo-test < /tmp/data.sql
mysql apek-energo-test < db/districts.sql
mysql apek-energo-test  < db/objects.sql
mysql apek-energo-test < db/migrate.sql
perl ./scripts/unificate_tables.pl
perl ./scripts/add_buildings.pl
