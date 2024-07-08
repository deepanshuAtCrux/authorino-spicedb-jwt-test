#!/usr/bin/env sh

set -eux

echo "PODS >>>>>>>>>>>"
kubectl get pods -n docs-api

kubectl get pods -n keycloak

kubectl get pods -n spicedb

echo "SVC >>>>>>>>>>>"

kubectl get svc -n docs-api

kubectl get svc -n keycloak

kubectl get svc -n spicedb