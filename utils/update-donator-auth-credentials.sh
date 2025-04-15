#!/usr/bin/env bash

#!/usr/bin/env bash

# Define the scope and secrets
echo -n "Enter your Client Secret: "
read -s CLIENT_SECRET

echo

echo -n "Enter your refresh token: "
read -s REFRESH_TOKEN

echo

./update-secret-template.sh "ldtteam" "donator-auth" "donator-auth-ldtteam-authentication-server" "Patreon.ApiClientSecret" "$CLIENT_SECRET"
./update-secret-template.sh "ldtteam" "donator-auth" "donator-auth-ldtteam-authentication-server" "Patreon.InitializingRefreshToken" "$REFRESH_TOKEN"