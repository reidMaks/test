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
          - -exec
          - ""
          - ${db_path}
          - ${s3_path}?endpoint=${oci_s3_endpoint}&region=eu-zurich-1&forcePathStyle=true
        envFrom:
          - secretRef:
              name: ${secret_name}
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 128Mi
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
          - -if-replica-exists
          - -if-db-not-exists
          - -o
          - ${db_path}
          - ${s3_path}?endpoint=${oci_s3_endpoint}&region=eu-zurich-1&forcePathStyle=true
        envFrom:
          - secretRef:
              name: ${secret_name}
