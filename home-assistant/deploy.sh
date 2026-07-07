#!/bin/sh
# Deploy custom Lovelace cards to the HAOS NUC (Terminal & SSH add-on, host "hass").
# After deploying, bump the ?v= query on the /local/mealie-cards.js Lovelace
# resource (or hard-refresh clients) so browsers pick up the new file.
set -eu
cd "$(dirname "$0")"
ssh hass 'mkdir -p /config/www'
scp www/mealie-cards.js hass:/config/www/mealie-cards.js
echo "Deployed www/mealie-cards.js -> hass:/config/www/mealie-cards.js"
