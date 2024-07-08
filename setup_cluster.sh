#!/usr/bin/env sh

set -eux

kind delete cluster --name authorino-demo

# create cluster
kind create cluster --name authorino-demo --config -<<EOF
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    listenAddress: "0.0.0.0"
  - containerPort: 443
    hostPort: 443
    listenAddress: "0.0.0.0"
EOF

# Install contour
kubectl apply -f https://raw.githubusercontent.com/guicassolato/authorino-spicedb/main/contour.yaml

# Install authorino
curl -sL https://raw.githubusercontent.com/Kuadrant/authorino-operator/main/utils/install.sh | bash -s

# install keycloak
kubectl create namespace keycloak
kubectl -n keycloak apply -f https://raw.githubusercontent.com/kuadrant/authorino-examples/main/keycloak/keycloak-deploy.yaml

# Install spicedb
kubectl create namespace spicedb
kubectl -n spicedb apply -f -<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spicedb
  labels:
    app: spicedb
spec:
  selector:
    matchLabels:
      app: spicedb
  template:
    metadata:
      labels:
        app: spicedb
    spec:
      containers:
        - name: spicedb
          image: authzed/spicedb
          args:
            - serve
            - "--grpc-preshared-key"
            - secret
            - "--http-enabled"
          ports:
            - containerPort: 50051
            - containerPort: 8443
  replicas: 1
---
apiVersion: v1
kind: Service
metadata:
  name: spicedb
spec:
  selector:
    app: spicedb
  ports:
    - name: grpc
      port: 50051
      protocol: TCP
    - name: http
      port: 8443
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spicedb
  labels:
    app: spicedb
spec:
  rules:
    - host: spicedb.127.0.0.1.nip.io
      http:
        paths:
          - backend:
              service:
                name: spicedb
                port:
                  number: 8443
            path: /
            pathType: Prefix
EOF

kubectl apply -f -<<EOF
apiVersion: v1
kind: Secret
metadata:
  name: spicedb
  labels:
    app: spicedb
stringData:
  grpc-preshared-key: secret
EOF

# Setup api
kubectl create namespace docs-api
kubectl -n docs-api apply -f -<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  selector:
    matchLabels:
      app: docs-api
  template:
    metadata:
      labels:
        app: docs-api
    spec:
      containers:
        - name: docs-api
          image: quay.io/kuadrant/authorino-examples:docs-api
          imagePullPolicy: IfNotPresent
          env:
            - name: PORT
              value: "3000"
          tty: true
          ports:
            - containerPort: 3000
  replicas: 1
---
apiVersion: v1
kind: Service
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  selector:
    app: docs-api
  ports:
    - name: http
      port: 3000
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  rules:
    - host: docs-api.127.0.0.1.nip.io
      http:
        paths:
          - backend:
              service:
                name: docs-api
                port:
                  number: 3000
            path: /docs
            pathType: Prefix
EOF
# wait for cluster to get spin up
sleep 60
curl http://docs-api.127.0.0.1.nip.io/docs -i

curl -X POST http://spicedb.127.0.0.1.nip.io/v1/schema/write \
     -H 'Authorization: Bearer secret' \
     -H 'Content-Type: application/json' \
     -d @- <<EOF
{
  "schema": "definition user {}\ndefinition doc {\n\trelation reader: user\n\trelation writer: user\n\n\tpermission read = reader + writer\n\tpermission write = writer\n}"
}
EOF

#Request an instance of Authorino
kubectl -n docs-api apply -f -<<EOF
apiVersion: operator.authorino.kuadrant.io/v1beta1
kind: Authorino
metadata:
  name: authorino
spec:
  logLevel: debug
  logMode: production
  listener:
    tls:
      enabled: false
  oidcServer:
    tls:
      enabled: false
EOF

# REDEPLOY DOCS API WITH SIDECAR Proxy
kubectl -n docs-api apply -f -<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  selector:
    matchLabels:
      app: docs-api
  template:
    metadata:
      labels:
        app: docs-api
    spec:
      containers:
        - name: docs-api
          image: quay.io/kuadrant/authorino-examples:docs-api
          imagePullPolicy: IfNotPresent
          env:
            - name: PORT
              value: "3000"
          tty: true
          ports:
            - containerPort: 3000
        - name: envoy
          image: envoyproxy/envoy:v1.19-latest
          imagePullPolicy: IfNotPresent
          command:
            - /usr/local/bin/envoy
          args:
            - --config-path /usr/local/etc/envoy/envoy.yaml
            - --service-cluster front-proxy
            - --log-level info
            - --component-log-level filter:trace,http:debug,router:debug
          ports:
            - containerPort: 8000
          volumeMounts:
            - mountPath: /usr/local/etc/envoy
              name: config
              readOnly: true
      volumes:
        - name: config
          configMap:
            items:
              - key: envoy.yaml
                path: envoy.yaml
            name: envoy
  replicas: 1
---
apiVersion: v1
kind: Service
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  selector:
    app: docs-api
  ports:
    - name: envoy
      port: 8000
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  rules:
    - host: docs-api.127.0.0.1.nip.io
      http:
        paths:
          - backend:
              service:
                name: docs-api
                port:
                  number: 8000
            path: /docs
            pathType: Prefix
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy
  labels:
    app: envoy
data:
  envoy.yaml: |
    static_resources:
      clusters:
        - name: docs-api
          connect_timeout: 0.25s
          type: strict_dns
          lb_policy: round_robin
          load_assignment:
            cluster_name: docs-api
            endpoints:
              - lb_endpoints:
                  - endpoint:
                      address:
                        socket_address:
                          address: 127.0.0.1
                          port_value: 3000
        - name: authorino
          connect_timeout: 0.25s
          type: strict_dns
          lb_policy: round_robin
          http2_protocol_options: {}
          load_assignment:
            cluster_name: authorino
            endpoints:
              - lb_endpoints:
                  - endpoint:
                      address:
                        socket_address:
                          address: authorino-authorino-authorization
                          port_value: 50051
      listeners:
        - address:
            socket_address:
              address: 0.0.0.0
              port_value: 8000
          filter_chains:
            - filters:
                - name: envoy.http_connection_manager
                  typed_config:
                    "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                    stat_prefix: local
                    route_config:
                      name: docs-api
                      virtual_hosts:
                        - name: docs-api
                          domains: ['*']
                          routes:
                            - match:
                                prefix: /
                              route:
                                cluster: docs-api
                    http_filters:
                      - name: envoy.filters.http.ext_authz
                        typed_config:
                          "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
                          transport_api_version: V3
                          failure_mode_allow: false
                          include_peer_certificate: true
                          grpc_service:
                            envoy_grpc:
                              cluster_name: authorino
                            timeout: 1s
                      - name: envoy.filters.http.lua
                        typed_config:
                          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                          inline_code: |
                            function envoy_on_request(request_handle)
                              if string.match(request_handle:headers():get(":path"), '^/docs/[^/]+/allow/.+') then
                                request_handle:respond({[":status"] = "200"}, "")
                              end
                            end
                      - name: envoy.filters.http.router
                        typed_config: {}
                    use_remote_address: true
    admin:
      access_log_path: "/tmp/admin_access.log"
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 8001
EOF

# Deploy the docs-api Deployment
kubectl -n docs-api apply -f -<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  selector:
    matchLabels:
      app: docs-api
  template:
    metadata:
      labels:
        app: docs-api
    spec:
      containers:
        - name: docs-api
          image: quay.io/kuadrant/authorino-examples:docs-api
          imagePullPolicy: IfNotPresent
          env:
            - name: PORT
              value: "3000"
          tty: true
          ports:
            - containerPort: 3000
        - name: envoy
          image: envoyproxy/envoy:v1.19-latest
          imagePullPolicy: IfNotPresent
          command:
            - /usr/local/bin/envoy
          args:
            - --config-path /usr/local/etc/envoy/envoy.yaml
            - --service-cluster front-proxy
            - --log-level debug
            - --component-log-level filter:trace,http:debug,router:debug
          ports:
            - containerPort: 8000
          volumeMounts:
            - mountPath: /usr/local/etc/envoy
              name: config
              readOnly: true
      volumes:
        - name: config
          configMap:
            items:
              - key: envoy.yaml
                path: envoy.yaml
            name: envoy
  replicas: 1
---
apiVersion: v1
kind: Service
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  selector:
    app: docs-api
  ports:
    - name: envoy
      port: 8000
      protocol: TCP
EOF

# deploy service
kubectl -n docs-api apply -f -<<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docs-api
  labels:
    app: docs-api
spec:
  rules:
    - host: docs-api.127.0.0.1.nip.io
      http:
        paths:
          - backend:
              service:
                name: docs-api
                port:
                  number: 8000
            path: /docs
            pathType: Prefix
EOF

# configure envoy
kubectl -n docs-api apply -f -<<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy
  labels:
    app: envoy
data:
  envoy.yaml: |
    static_resources:
      clusters:
        - name: docs-api
          connect_timeout: 0.25s
          type: strict_dns
          lb_policy: round_robin
          load_assignment:
            cluster_name: docs-api
            endpoints:
              - lb_endpoints:
                  - endpoint:
                      address:
                        socket_address:
                          address: 127.0.0.1
                          port_value: 3000
        - name: keycloak
          connect_timeout: 0.25s
          type: logical_dns
          lb_policy: round_robin
          load_assignment:
            cluster_name: keycloak
            endpoints:
            - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: keycloak.keycloak.svc.cluster.local
                      port_value: 8080
        - name: authorino
          connect_timeout: 0.25s
          type: strict_dns
          lb_policy: round_robin
          http2_protocol_options: {}
          load_assignment:
            cluster_name: authorino
            endpoints:
              - lb_endpoints:
                  - endpoint:
                      address:
                        socket_address:
                          address: authorino-authorino-authorization
                          port_value: 50051
      listeners:
        - address:
            socket_address:
              address: 0.0.0.0
              port_value: 8000
          filter_chains:
            - filters:
                - name: envoy.http_connection_manager
                  typed_config:
                    "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                    stat_prefix: local
                    route_config:
                      name: docs-api
                      virtual_hosts:
                        - name: docs-api
                          domains: ['*']
                          routes:
                            - match:
                                prefix: /
                              route:
                                cluster: docs-api
                    http_filters:
                      - name: envoy.filters.http.jwt_authn
                        typed_config:
                          "@type": type.googleapis.com/envoy.extensions.filters.http.jwt_authn.v3.JwtAuthentication
                          providers:
                            keycloak:
                              issuer: http://keycloak.keycloak.svc.cluster.local:8080/realms/kuadrant
                              remote_jwks:
                                http_uri:
                                  uri: http://keycloak.keycloak.svc.cluster.local:8080/realms/kuadrant/protocol/openid-connect/certs
                                  cluster: keycloak
                                  timeout: 5s
                                cache_duration:
                                  seconds: 300
                              payload_in_metadata: verified_jwt
                          rules:
                            - match: { prefix: / }
                              requires: { provider_name: keycloak }
                      - name: envoy.filters.http.ext_authz
                        typed_config:
                          "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
                          transport_api_version: V3
                          failure_mode_allow: false
                          include_peer_certificate: true
                          metadata_context_namespaces:
                            - envoy.filters.http.jwt_authn
                          grpc_service:
                            envoy_grpc:
                              cluster_name: authorino
                            timeout: 1s
                      - name: envoy.filters.http.lua
                        typed_config:
                          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                          inline_code: |
                            function envoy_on_request(request_handle)
                              if string.match(request_handle:headers():get(":path"), '^/docs/[^/]+/allow/.+') then
                                request_handle:respond({[":status"] = "200"}, "")
                              end
                            end
                      - name: envoy.filters.http.router
                        typed_config: {}
                    use_remote_address: true
    admin:
      access_log_path: "/tmp/admin_access.log"
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 8001
EOF

# wait for cluster to get spin up
sleep 20

kubectl -n docs-api apply -f -<<EOF
apiVersion: v1
kind: Secret
metadata:
  name: talker-api-uma-credentials
stringData:
  clientID: talker-api
  clientSecret: 523b92b6-625d-4e1e-a313-77e7a8ae4e88
type: Opaque
---
apiVersion: v1
kind: Secret
metadata:
  name: spicedb
  labels:
    app: spicedb
stringData:
  grpc-preshared-key: secret
  token: secret
EOF

# we should not be able to access the docs api
curl http://docs-api.127.0.0.1.nip.io/docs -i

# HTTP/1.1 404 Not Found
# x-ext-auth-reason: Service not found
# server: envoy
# ...


