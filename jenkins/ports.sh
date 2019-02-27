#! /bin/bash

# Prints the ports and databases used by jenkins.

ssh jenkins@themis bash <<EOF
grep -E 'PORT_BASE|POSTGRES_DB_1|POSTGRES_DB_2|BIND_HOST|PORT_COUNT' /var/lib/jenkins/jobs/*/config.xml \
    | cut -c23- \
    | sed 's|/config.xml:\( *<command>\)*export||;s|=| |'
EOF
