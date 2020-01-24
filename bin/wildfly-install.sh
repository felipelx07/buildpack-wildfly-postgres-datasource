#!/bin/bash

set -e

# parse args
BUILD_DIR=$1
CACHE_DIR=$2
ENV_DIR=$3

cd $BUILD_DIR

BP_DIR="/.." # absolute path
BIN_DIR=$BP_DIR/bin

WILDFLY_VERSION="18.0.0.Final"
WILDFLY_SHA1="2d4778b14fda6257458a26943ea82988e3ae6a66"
POSTGRESL_DRIVER_VERSION="42.2.5"
POSTGRES_DRIVER_SHA1="951b7eda125f3137538a94e2cbdcf744088ad4c2"
JBOSS_HOME="/opt/wildfly-${WILDFLY_VERSION}"


printf -- "#######################################################################\n"
printf -- "##              BUILDPACK WILDFLY POSTGRES DATASOURCE                ##\n"
printf -- "#######################################################################\n"

if [ -f "$JBOSS_HOME" ]; then
	rm -rf $JBOSS_HOME
fi

printf -- ".\n"
printf -- "..\n"
printf -- "...\n"
printf -- "------------------------------------------------------------------------------\n"
printf -- "Installing Wildfly ${WILDFLY_VERSION}\n"
printf -- "------------------------------------------------------------------------------\n"
if [ -f "$wildfly-$WILDFLY_VERSION.tar.gz" ]; then
	printf -- "File already downloaded...\n"
else 
    curl -O https://download.jboss.org/wildfly/$WILDFLY_VERSION/wildfly-$WILDFLY_VERSION.tar.gz
	printf -- "----> downloaded\n"
	sha1sum wildfly-$WILDFLY_VERSION.tar.gz | grep $WILDFLY_SHA1 > /dev\null 2>&1
	printf -- "----> verified\n"
fi

printf -- "----> Initializing extract tar wildfly-$WILDFLY_VERSION.tar.gz\n"
tar xf wildfly-$WILDFLY_VERSION.tar.gz
printf -- "----> extracted\n"

printf -- "----> moving wildfly-$WILDFLY_VERSION to $JBOSS_HOME\n"
mv wildfly-$WILDFLY_VERSION $JBOSS_HOME
printf -- "----> moved\n"

printf -- "----> removing wildfly-$WILDFLY_VERSION.tar.gz\n"
rm wildfly-$WILDFLY_VERSION.tar.gz
printf -- "----> done\n"

printf -- "------------------------------------------------------------------------------\n"
printf -- "Installing PostgreSQL Wildfly module\n"
printf -- "------------------------------------------------------------------------------\n"
if [ -f "$postgresql-$POSTGRESL_DRIVER_VERSION.jar" ]; then
	printf -- "----> PostgreSQL Driver already downloaded...\n"
else
	curl -O https://repo1.maven.org/maven2/org/postgresql/postgresql/$POSTGRESL_DRIVER_VERSION/postgresql-$POSTGRESL_DRIVER_VERSION.jar
	printf -- "----> downloaded\n"
	sha1sum postgresql-$POSTGRESL_DRIVER_VERSION.jar | grep $POSTGRES_DRIVER_SHA1 > /dev\null 2>&1
	printf -- "----> verified\n"
fi

printf -- "----> moving postgresql-$POSTGRESL_DRIVER_VERSION.jar to $JBOSS_HOME\n"
mv postgresql-$POSTGRESL_DRIVER_VERSION.jar $JBOSS_HOME
printf -- "----> moved\n"

printf -- "..............................................................................\n"
printf -- " Initializing and waiting for wildfly standalone gets up\n"
printf -- "..............................................................................\n"
nohup $JBOSS_HOME/bin/standalone.sh -b=0.0.0.0 -Djboss.http.port=8080 > /dev\null 2>&1 &
until $(curl --output /dev\null --silent --head --fail http://localhost:8080); do echo '.'; sleep 5; done

cat << EOF > /tmp/wildfly-postgresql-installer
connect
module add --name=org.postgresql --resources=$JBOSS_HOME/postgresql-$POSTGRESL_DRIVER_VERSION.jar --dependencies=javax.api,javax.transaction.api
/subsystem=datasources/jdbc-driver=postgresql:add(driver-name="postgresql",driver-module-name="org.postgresql",driver-class-name=org.postgresql.Driver)
quit
EOF

printf -- "-----> Connecting to jboss-cli to add Postgres driver module...\n"
$JBOSS_HOME/bin/jboss-cli.sh --file=/tmp/wildfly-postgresql-installer
printf -- "-----> PostgreSQL wildfly module installed successfully\n"
$JBOSS_HOME/bin/jboss-cli.sh --connect command=:shutdown
printf -- "-----> Disconnect with jboss-cli...\n"

printf -- "Coping configured standalone.xml to $JBOSS_HOME/standalone/configuration/\n"
cp /opt/buildpack-wildfly-postgres-datasource/standalone/standalone.xml $JBOSS_HOME/standalone/configuration/
printf -- "standalone.xml datasource configured\n"
rm $JBOSS_HOME/postgresql-$POSTGRESL_DRIVER_VERSION.jar
printf -- "-----> done\n"

printf -- "-----> Creating configuration...\n"
if [ -f $BUILD_DIR/Procfile ]; then
  printf -- "        - Using existing process types\n"
else

cat << EOF > $BUILD_DIR/Procfile
web: \$JBOSS_HOME/bin/standalone.sh -b=0.0.0.0 -Djboss.http.port=\$PORT
EOF
fi

printf -- "------------------------------------------------------------------------------\n"
printf -- "Create wildfly service on init.d
printf -- "------------------------------------------------------------------------------\n"
ln -s $JBOSS_HOME /opt/wildfly

groupadd -r wildfly
useradd -r -g wildfly -d /opt/wildfly -s /sbin/nologin wildfly
chown -RH wildfly: /opt/wildfly


 mkdir /etc/wildfly
 cp $JBOSS_HOME/docs/contrib/scripts/systemd/wildfly.conf /etc/wildfly/
 cp $JBOSS_HOME/docs/contrib/scripts/systemd/wildfly.service /etc/systemd/system/
 cp $JBOSS_HOME/docs/contrib/scripts/systemd/launch.sh $JBOSS_HOME/bin/

 systemctl enable wildfly
 systemctl start wildfly


cat << EOF > $BUILD_DIR/etc/default/wildfly.conf
export JBOSS_HOME=${JBOSS_HOME}
EOF

printf -- "----> done!


printf -- "#######################################################################\n"
printf -- "##                    EVERYTHING'S ALLRIGHT NOW!                     ##\n"
printf -- "#######################################################################\n"
