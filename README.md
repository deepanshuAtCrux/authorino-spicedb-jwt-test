# authorino-spicedb-jwt-test

0) make sure to add these entries to your host file

```
127.0.0.1 docs-api.127.0.0.1.nip.io
127.0.0.1 spicedb.127.0.0.1.nip.io
```

1) To setup the cluster run

```bash
./setup_cluster.sh
./setup_auth.sh
```


2) Run tests

```bash
./test_auth.sh
```

3) For cleanup run

```bash
./cleanup_cluster.sh

```