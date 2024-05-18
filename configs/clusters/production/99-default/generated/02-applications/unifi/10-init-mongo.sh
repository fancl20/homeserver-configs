set -e

mongo <<EOF
use unifi
db.createUser({
  user: 'unifi',
  pwd: '$(cat /vault/secrets/unifi_mongo_pass)',
  roles: [
    { db: 'unifi', role: 'dbOwner' },
    { db: 'unifi_stat', role: 'dbOwner' },
  ]
})
EOF
