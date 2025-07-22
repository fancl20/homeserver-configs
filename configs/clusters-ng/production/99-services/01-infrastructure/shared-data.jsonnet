local app = import '../app.libsonnet';

{
  'pvc.yaml': {
    apiVersion: "v1",
    kind: "PersistentVolumeClaim",
    metadata: {
      name: app.Volumes.shared_data.persistentVolumeClaim.claimName,
      namespace: "default"
   },
   spec: {
      accessModes: [ "ReadWriteMany" ],
      resources: {
         "requests": { "storage": "4Ti" }
      },
      volumeMode: "Filesystem",
   }
  }
}

