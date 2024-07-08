#!/usr/bin/env sh

set -eux
echo "ENVOY LOGS >>>>>>>>>"
kubectl logs -n docs-api -l app=docs-api -c envoy
echo "DOCS API LOGS >>>>>>>>>"
kubectl logs -n docs-api -l app=docs-api -c docs-api
echo "SPICEDB LOGS >>>>>>>>>"
kubectl logs -n spicedb -l app=spicedb
echo "KEYCLOAK LOGS >>>>>>>>>"
kubectl logs -n keycloak -l app=keycloak
echo "AUTHORINO LOGS >>>>>>>>>"
kubectl logs -l authorino-resource=authorino -n docs-api

