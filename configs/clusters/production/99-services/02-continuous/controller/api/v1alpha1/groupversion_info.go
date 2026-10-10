// Package v1alpha1 contains the ContainerImage API types.
//
// +kubebuilder:object:generate=true
// +groupName=d20.fan
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
	// GroupVersion is the API group/version served by this controller.
	GroupVersion = schema.GroupVersion{Group: "d20.fan", Version: "v1alpha1"}

	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

	AddToScheme = SchemeBuilder.AddToScheme
)

// Regenerate the deepcopy functions and the CRD with:
//
//	go generate ./...
//
// The CRD is emitted next to this controller's manifests (../../../ is
// 02-continuous/) because generate.py wipes per-app directories under
// generated/ and every .yaml under 99-services is applied by Flux.
//
//go:generate go run sigs.k8s.io/controller-tools/cmd/controller-gen@v0.21.0 object paths=../../...
//go:generate go run sigs.k8s.io/controller-tools/cmd/controller-gen@v0.21.0 crd paths=../../... output:crd:artifacts:config=../../../
