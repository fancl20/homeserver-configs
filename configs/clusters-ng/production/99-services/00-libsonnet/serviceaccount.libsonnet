{
  local base = self,

  ServiceAccount():: self {
    'serviceaccount.yaml': {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: {
        name: base.Name,
        namespace: base.Namespace,
      },
    },
  },

  ClusterRole(name=base.Name, rules):: self {
    ['clusterrole_' + name + '.yaml']: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: {
        name: name,
      },
      rules: rules,
    },

    ['clusterrolebinding_' + name + '.yaml']: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        name: name,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: name,
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: base.Name,
        namespace: base.Namespace,
      }],
    },
  },

  Role(name=base.Name, rules):: self {
    ['role_' + name + '.yaml']: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        name: name,
        namespace: base.Namespace,
      },
      rules: rules,
    },

    ['rolebinding_' + name + '.yaml']: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        name: name,
        namespace: base.Namespace,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: name,
        namespace: base.Namespace,
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: base.Name,
        namespace: base.Namespace,
      }],
    },
  },
}
