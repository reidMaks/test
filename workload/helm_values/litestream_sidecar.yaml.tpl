controllers:
  ${controller_name}:
    containers:
      litestream:
        image:
          repository: litestream/litestream
          tag: latest
        securityContext:
          runAsUser: 0
          runAsGroup: 0
        command:
          - litestream
          - replicate
          - -config
          - /etc/litestream.yml
        ports:
          - name: metrics
            containerPort: 9090
        envFrom:
          - secretRef:
              name: ${secret_name}
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 128Mi
%{ if try(db_path, "") != "" }
    initContainers:
      01-litestream-restore:
        image:
          repository: litestream/litestream
          tag: latest
        securityContext:
          runAsUser: 0
          runAsGroup: 0
        command:
          - litestream
          - restore
          - -config
          - /etc/litestream.yml
          - -if-replica-exists
          - -if-db-not-exists
          - ${db_path}
        envFrom:
          - secretRef:
              name: ${secret_name}
%{ endif }

configMaps:
  litestream-config:
    enabled: true
    data:
      litestream.yml: |
        addr: ":9090"
        dbs:
          - %{ if try(db_dir, "") != "" }dir: ${db_dir}
            pattern: "*.sqlite"
            recursive: true
            watch: true%{ else }path: ${db_path_exact}%{ endif }
            replica:
              url: s3://kms-lab-data/${bucket_path}?endpoint=http://minio.default.svc.cluster.local:9000&region=us-east-1&forcePathStyle=true
              access-key-id: $${MINIO_ACCESS_KEY}
              secret-access-key: $${MINIO_SECRET_KEY}

persistence:
  litestream-config:
    type: configMap
    identifier: litestream-config
    advancedMounts:
      ${controller_name}:
        litestream:
          - path: /etc/litestream.yml
            subPath: litestream.yml
%{ if try(db_path, "") != "" || try(db_dir, "") != "" }
        01-litestream-restore:
          - path: /etc/litestream.yml
            subPath: litestream.yml
%{ endif }
