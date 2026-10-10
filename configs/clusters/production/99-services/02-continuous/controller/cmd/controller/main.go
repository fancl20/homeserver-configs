// Command controller runs the image-controller.
package main

import (
	"flag"
	"os"
	"time"

	_ "time/tzdata" // schedules and dates work regardless of the base image

	imagev1 "github.com/fluxcd/image-reflector-controller/api/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	controllerpkg "sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	logz "sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	"image-controller/api/v1alpha1"
	"image-controller/internal/config"
	"image-controller/internal/controller"
)

func main() {
	setupLog := ctrl.Log.WithName("setup")

	fs := flag.NewFlagSet("image-controller", flag.ContinueOnError)
	logOpts := logz.Options{Development: false}
	logOpts.BindFlags(fs)
	metricsAddr := fs.String("metrics-bind-address", "0", "metrics bind address, 0 to disable")
	probeAddr := fs.String("health-probe-bind-address", ":8081", "health probe bind address")
	leaderElect := fs.Bool("leader-elect", false, "leader election (single replica, off)")

	cfg, err := config.FromFlags(fs, os.Args[1:])
	if err != nil {
		setupLog.Error(err, "invalid flags")
		os.Exit(1)
	}
	ctrl.SetLogger(logz.New(logz.UseFlagOptions(&logOpts)))

	scheme := clientgoscheme.Scheme
	for _, add := range []func(*runtime.Scheme) error{
		v1alpha1.AddToScheme,
		sourcev1.AddToScheme,
		imagev1.AddToScheme,
	} {
		if err := add(scheme); err != nil {
			setupLog.Error(err, "cannot register scheme")
			os.Exit(1)
		}
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		LeaderElection:         *leaderElect,
		Metrics:                metricsserver.Options{BindAddress: *metricsAddr},
		HealthProbeBindAddress: *probeAddr,
		Cache: cache.Options{
			// The CRD and its RBAC are cluster-scoped: ContainerImages are
			// cached wherever they are created. Only Jobs and Pods — where
			// the Role RBAC is limited to the build namespace anyway — are
			// pruned to it.
			ByObject: map[client.Object]cache.ByObject{
				&batchv1.Job{}: {Namespaces: map[string]cache.Config{cfg.BuildNamespace: {}}},
				&corev1.Pod{}:  {Namespaces: map[string]cache.Config{cfg.BuildNamespace: {}}},
			},
		},
	})
	if err != nil {
		setupLog.Error(err, "cannot start manager")
		os.Exit(1)
	}

	if err := controller.RegisterIndexes(mgr); err != nil {
		setupLog.Error(err, "cannot register field indexes")
		os.Exit(1)
	}

	reconciler := &controller.ContainerImageReconciler{
		Client:   mgr.GetClient(),
		Scheme:   mgr.GetScheme(),
		Recorder: mgr.GetEventRecorder("image-controller"),
		Config:   cfg,
		Clock:    time.Now,
	}

	// Predicates are scoped per watch. WithEventFilter ANDs its predicates
	// into every watch, which silently disabled the cross-object watches:
	// artifact revisions, selected tags, and Job completion are status-only
	// updates that neither bump metadata.generation nor touch requestedAt.
	// On the primary watch, annotation writes do not bump generation either,
	// so the requestedAt predicate must be OR-ed in or manual triggers never
	// fire.
	if err := ctrl.NewControllerManagedBy(mgr).
		For(&v1alpha1.ContainerImage{},
			builder.WithPredicates(predicate.Or(
				predicate.GenerationChangedPredicate{},
				controller.RequestedAtPredicate{},
			))).
		Owns(&batchv1.Job{},
			builder.WithPredicates(controller.JobStatusChangedPredicate{})).
		Watches(&sourcev1.GitRepository{}, handler.EnqueueRequestsFromMapFunc(reconciler.MapSource),
			builder.WithPredicates(controller.SourceArtifactPredicate{})).
		Watches(&imagev1.ImagePolicy{}, handler.EnqueueRequestsFromMapFunc(reconciler.MapBasePolicy),
			builder.WithPredicates(controller.BasePolicyPredicate{})).
		WithOptions(controllerpkg.Options{MaxConcurrentReconciles: cfg.ConcurrentBuilds}).
		Named("containerimage").
		Complete(reconciler); err != nil {
		setupLog.Error(err, "cannot create controller")
		os.Exit(1)
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "cannot add healthz check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "cannot add readyz check")
		os.Exit(1)
	}

	setupLog.Info("starting image-controller",
		"registry", cfg.RegistryHost,
		"buildNamespace", cfg.BuildNamespace,
		"timeZone", cfg.Location.String())

	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "controller stopped")
		os.Exit(1)
	}
}
