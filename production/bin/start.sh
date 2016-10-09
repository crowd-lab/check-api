#!/bin/bash

# start.sh
# the Dockerfile CMD

UPLOADS=${DEPLOYDIR}/shared/files/uploads

# should only run this on ${PRIMARY} nodes, perhaps in an out-of-band process during major multi-node deployments
echo "running migrations"
su ${DEPLOYUSER} -c "bundle exec rake db:migrate"

echo "setting permissions for ${UPLOADS}"
chown -R ${DEPLOYUSER}:www-data ${UPLOADS}
find ${UPLOADS} -type d -exec chmod 2777 {} \; # set the sticky bit on directories to preserve permissions
find ${UPLOADS} -type f -exec chmod 0664 {} \; # files are 664

echo "starting redis"
redis-server &

echo "starting sidekiq"
bundle exec sidekiq -L log/sidekiq.log -d

echo "starting nginx"

nginx
