#!/usr/bin/env sh

set -eux


# test without auth
#curl -X GET \
#   -H 'Content-Type: application/json' \
#   http://docs-api.127.0.0.1.nip.io/docs -i

JOHNS_DOC_ID=$(shuf -i 1-100000 -n 1)
JANES_DOC_ID=$(shuf -i 1-100000 -n 1)

ACCESS_TOKEN_JOHN=$(kubectl run token --attach --rm --restart=Never -q --image=curlimages/curl -- http://keycloak.keycloak.svc.cluster.local:8080/realms/kuadrant/protocol/openid-connect/token -s -d 'grant_type=password' -d 'client_id=demo' -d 'username=john' -d 'password=p' -d 'scope=openid' | jq -r .access_token)

ACCESS_TOKEN_JANE=$(kubectl run token --attach --rm --restart=Never -q --image=curlimages/curl -- http://keycloak.keycloak.svc.cluster.local:8080/realms/kuadrant/protocol/openid-connect/token -s -d 'grant_type=password' -d 'client_id=demo' -d 'username=jane' -d 'password=p' -d 'scope=openid' | jq -r .access_token)

curl -X POST http://spicedb.127.0.0.1.nip.io/v1/relationships/write \
  -H 'Authorization: Bearer secret' \
  -H 'Content-Type: application/json' \
  -d @- << EOF
{
  "updates": [
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {
          "objectType": "doc",
          "objectId": "${JOHNS_DOC_ID}"
        },
        "relation": "writer",
        "subject": {
          "object": {
            "objectType": "user",
            "objectId": "john"
          }
        }
      }
    },
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {
          "objectType": "doc",
          "objectId": "${JANES_DOC_ID}"
        },
        "relation": "writer",
        "subject": {
          "object": {
            "objectType": "user",
            "objectId": "jane"
          }
        }
      }
    }
  ]
}
EOF

echo "John creating  his own doc>>>>>"
curl -H "Authorization: Bearer $ACCESS_TOKEN_JOHN" \
   -X POST \
   -H 'Content-Type: application/json' \
   -d '{"title":"johns´s doc","body":"This is john´s doc."}' \
   "http://docs-api.127.0.0.1.nip.io/docs/$JOHNS_DOC_ID" -i

echo "Jane creating her doc>>>>>"
curl -H "Authorization: Bearer $ACCESS_TOKEN_JANE" \
   -X POST \
   -H 'Content-Type: application/json' \
   -d '{"title":"jane´s doc","body":"This is jane´s doc."}' \
   "http://docs-api.127.0.0.1.nip.io/docs/$JANES_DOC_ID" -i


echo "John asking for his own doc>>>>>"
curl -H "Authorization: Bearer $ACCESS_TOKEN_JOHN" \
   -X GET \
   -H 'Content-Type: application/json' \
   "http://docs-api.127.0.0.1.nip.io/docs/$JOHNS_DOC_ID" -i

 # ACCESS GRANTED
echo "John asking for someone's else doc>>>>>"
curl -H "Authorization: Bearer $ACCESS_TOKEN_JOHN" \
   -X GET \
   -H 'Content-Type: application/json' \
   "http://docs-api.127.0.0.1.nip.io/docs/$JANES_DOC_ID" -i

 # ACCESS REFUSED
echo "Jane asking for her own doc>>>>>"
curl -H "Authorization: Bearer $ACCESS_TOKEN_JANE" \
   -X GET \
   -H 'Content-Type: application/json' \
   "http://docs-api.127.0.0.1.nip.io/docs/$JANES_DOC_ID" -i

 # ACCESS GRANTED
echo "Jane asking for someone's else doc>>>>>"
curl -H "Authorization: Bearer $ACCESS_TOKEN_JANE" \
   -X GET \
   -H 'Content-Type: application/json' \
   "http://docs-api.127.0.0.1.nip.io/docs/$JOHNS_DOC_ID" -i

 # ACCESS GRANTED


#curl -H "Authorization: Bearer $ACCESS_TOKEN_JANE" \
#     -X GET \
#     -H 'Content-Type: application/json' \
#     http://docs-api.127.0.0.1.nip.io/docs -i