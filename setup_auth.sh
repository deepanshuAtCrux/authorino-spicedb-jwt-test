#!/usr/bin/env sh

set -eux



kubectl -n docs-api apply -f -<<EOF
apiVersion: authorino.kuadrant.io/v1beta2
kind: AuthConfig
metadata:
  name: docs-api-protection
spec:
  hosts:
    - docs-api.127.0.0.1.nip.io
  authentication:
    "keycloak-kuadrant-realm":
      jwt:
        issuerUrl: http://keycloak.keycloak.svc.cluster.local:8080/realms/kuadrant
  metadata:
    "resource-data":
      uma:
        endpoint: http://keycloak.keycloak.svc.cluster.local:8080/realms/kuadrant
        credentialsRef:
          name: talker-api-uma-credentials

  authorization:
    "authzed-spicedb":
      spicedb:
        endpoint: spicedb.spicedb.svc.cluster.local:50051
        insecure: true
        sharedSecretRef:
          name: spicedb
          key: token
        subject:
          kind:
            value: user
          name:
            selector: auth.identity.preferred_username
        resource:
          kind:
            value: doc
          name:
            selector: context.request.http.path.@extract:{"sep":"/","pos":2}
        permission:
          selector: context.request.http.method.@replace:{"old":"GET","new":"read"}.@replace:{"old":"POST","new":"write"}
EOF

