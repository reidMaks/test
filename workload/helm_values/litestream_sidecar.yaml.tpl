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
